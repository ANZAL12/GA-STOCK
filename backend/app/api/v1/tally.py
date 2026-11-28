"""
Tally Integration API Endpoints
--------------------------------
CRITICAL ARCHITECTURAL INVARIANT: TALLY IS STRICTLY READ-ONLY.
Under NO circumstances does any endpoint here write, alter, create, or import
records into Tally Prime. All communications are strictly Export / Read-Only.
"""
import time
import uuid
import json
from datetime import date, datetime
from typing import Annotated, Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import delete, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.outward import OutwardBatch
from app.models.shop import Shop
from app.models.product import Product
from app.models.category import Category
from app.models.tally import (
    TallyConfig,
    TallySalesVoucher,
    TallySyncHistory,
    TallyVoucherItem,
)
from app.models.user import User
from app.schemas.product import ProductResponse
from app.schemas.tally import (
    TallyAgentPushRequest,
    TallyAgentPushResponse,
    TallyAssignBrandRequest,
    TallyCompanyResponse,
    TallyConfigResponse,
    TallyConnectRequest,
    TallyConnectResponse,
    TallySalesVoucherDetailResponse,
    TallySalesVoucherResponse,
    TallyStatusResponse,
    TallySyncHistoryItemResponse,
    TallySyncRequest,
    TallySyncResponse,
    TallySyncStatusResponse,
    TallyToggleReadingRequest,
    TallyVoucherItemResponse,
)
from app.services.tally_service import (
    TallyBackgroundWorker,
    TallyHttpClient,
    TallySyncService,
    TallyXmlBuilder,
    TallyXmlParser,
)

router = APIRouter(prefix="/tally", tags=["tally"])

# In-memory status cache to ensure < 100ms response time
_last_status_cache: Optional[Dict[str, Any]] = None
_last_status_time: float = 0.0


# ---------------------------------------------------------------------------
# 1. Connection Status & Configuration
# ---------------------------------------------------------------------------

@router.get("/status", response_model=TallyStatusResponse)
async def get_tally_status(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    force_probe: bool = Query(False, description="Bypass cache and force immediate probe"),
) -> TallyStatusResponse:
    """Check Tally connection status and sync state with ultra-fast caching (< 50ms)."""
    global _last_status_cache, _last_status_time
    now = time.time()
    is_force = force_probe is True or str(force_probe).lower() in ("true", "1")
    if not is_force and _last_status_cache is not None and (now - _last_status_time) < 20.0:
        return TallyStatusResponse(**_last_status_cache)

    cfg = await TallySyncService.get_or_create_config(db)

    # Ultra-fast probe across configured Tally endpoints with 0.6s socket timeout
    endpoints = TallySyncService.get_configured_endpoints(cfg)
    probes = await TallyHttpClient.probe_endpoints(endpoints, timeout=0.6)
    reachable = [p for p in probes if p[3]]

    is_connected = len(reachable) > 0

    company_names: List[str] = []
    for _, _, _, _, _, ep_companies in reachable:
        for c in ep_companies:
            cname = (c.get("name") or "").strip()
            if cname and cname != "0" and not cname.isdigit() and cname not in company_names:
                company_names.append(cname)

    active_host = reachable[0][0] if reachable else cfg.host
    active_port = reachable[0][1] if reachable else cfg.port
    active_url = reachable[0][2] if reachable else cfg.tally_url

    # Auto-reconcile vouchers dispatched via OutwardBatch (limit to 50 recent to keep fast)
    reconcile_res = await db.execute(
        select(TallySalesVoucher).where(
            TallySalesVoucher.is_processed == False,
            func.trim(func.lower(TallySalesVoucher.voucher_number)).in_(
                select(func.trim(func.lower(OutwardBatch.bill_number))).where(
                    OutwardBatch.bill_number.is_not(None),
                    OutwardBatch.is_cancelled == False,
                ).order_by(desc(OutwardBatch.created_at)).limit(100)
            ),
        ).limit(50)
    )
    unreconciled = reconcile_res.scalars().all()
    if unreconciled:
        for uv in unreconciled:
            uv.is_processed = True
            uv.processed_at = uv.processed_at or datetime.now()
            if not uv.notes:
                uv.notes = f"Dispatched via GA STOCK Outward (Bill: {uv.voucher_number})"
        await db.commit()

    # Voucher statistics
    total_res = await db.execute(select(func.count(TallySalesVoucher.id)))
    total_count = total_res.scalar() or 0

    pending_res = await db.execute(
        select(func.count(TallySalesVoucher.id)).where(
            TallySalesVoucher.is_processed == False,
            TallySalesVoucher.is_cancelled == False,
        )
    )
    pending_count = pending_res.scalar() or 0

    worker = TallyBackgroundWorker.get_instance()
    tally_settings = TallySyncService.get_tally_settings()

    tally_1_connected = False
    tally_2_connected = False
    tally_1_name = "Tally Instance 1"
    tally_2_name = "Tally Instance 2"

    if len(probes) >= 2:
        p0 = probes[0]
        tally_1_connected = bool(p0[3])
        p0_comps = [c.get("name") for c in p0[5] if c.get("name")]
        tally_1_name = p0_comps[0] if p0_comps else f"{p0[0]}:{p0[1]}"

        # Instance 2 checks second probe and any subsequent reachable probe
        p1 = probes[1]
        tally_2_connected = any(p[3] for p in probes[1:])
        p1_comps = [c.get("name") for p in probes[1:] if p[3] for c in p[5] if c.get("name")]
        tally_2_name = p1_comps[0] if p1_comps else f"{p1[0]}:{p1[1]}"
    elif len(probes) == 1:
        p0 = probes[0]
        tally_1_connected = bool(p0[3])
        p0_comps = [c.get("name") for c in p0[5] if c.get("name")]
        tally_1_name = p0_comps[0] if p0_comps else f"{p0[0]}:{p0[1]}"
        if len(p0_comps) > 1:
            tally_2_connected = bool(p0[3])
            tally_2_name = p0_comps[1]
        else:
            tally_2_connected = False
            tally_2_name = "Not Configured"
    else:
        tally_1_name = cfg.company_name or "Tally Prime"
        tally_2_name = "Not Configured"

    status_data = {
        "is_connected": is_connected,
        "host": active_host,
        "port": active_port,
        "tally_url": active_url,
        "active_company": cfg.company_name,
        "is_enabled": cfg.is_enabled,
        "auto_sync": tally_settings.get("auto_sync", True) and cfg.auto_sync and cfg.is_enabled,
        "sync_interval_minutes": tally_settings.get("sync_interval_minutes") or cfg.sync_interval_minutes or 60,
        "last_sync_at": cfg.last_sync_at,
        "last_sync_status": cfg.last_sync_status,
        "last_sync_message": cfg.last_sync_message,
        "last_alter_id": cfg.last_alter_id,
        "available_companies": company_names,
        "total_vouchers": total_count,
        "pending_vouchers": pending_count,
        "is_syncing": worker.is_syncing,
        "agent_configured": bool(cfg.agent_token),
        "enable_tally_1": tally_settings.get("enable_tally_1", True),
        "enable_tally_2": tally_settings.get("enable_tally_2", True),
        "tally_1_name": tally_1_name,
        "tally_2_name": tally_2_name,
        "tally_1_connected": tally_1_connected,
        "tally_2_connected": tally_2_connected,
    }
    _last_status_cache = status_data
    _last_status_time = now

    return TallyStatusResponse(**status_data)


@router.post("/toggle-reading", response_model=TallyStatusResponse)
async def toggle_tally_reading(
    req: TallyToggleReadingRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TallyStatusResponse:
    """
    Admin only: Toggle Tally background reading / auto-sync or selectively turn off Tally 1 / Tally 2 reading.
    """
    cfg = await TallySyncService.get_or_create_config(db)
    updates = {}
    if req.auto_sync is not None:
        updates["auto_sync"] = req.auto_sync
        cfg.auto_sync = req.auto_sync
        cfg.is_enabled = req.auto_sync
        await db.commit()
    if req.enable_tally_1 is not None:
        updates["enable_tally_1"] = req.enable_tally_1
    if req.enable_tally_2 is not None:
        updates["enable_tally_2"] = req.enable_tally_2
    if req.sync_interval_minutes is not None:
        updates["sync_interval_minutes"] = max(1, req.sync_interval_minutes)
        cfg.sync_interval_minutes = max(1, req.sync_interval_minutes)
        await db.commit()

    if updates:
        TallySyncService.save_tally_settings(updates)
        await ws_manager.broadcast("tally_settings_updated", updates)

    return await get_tally_status(admin, db, force_probe=True)


@router.post("/connect", response_model=TallyConnectResponse)
async def connect_tally(
    req: TallyConnectRequest,
    current_user: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TallyConnectResponse:
    """Configure and test Tally connection."""
    cfg = await TallySyncService.get_or_create_config(db)

    host = req.host or cfg.host
    port = req.port or cfg.port
    tally_url = req.tally_url if req.tally_url is not None else cfg.tally_url
    company = req.company_name if req.company_name is not None else cfg.company_name

    # Test connectivity with the new parameters
    is_connected, test_msg, companies = await TallyHttpClient.test_connection(
        host, port, tally_url, timeout=4.0
    )

    company_names = [c["name"] for c in companies]

    # If active company not set and exactly one open company found, select it
    if not company and len(company_names) == 1:
        company = company_names[0]

    # Persist config
    cfg.host = host
    cfg.port = port
    cfg.tally_url = tally_url
    cfg.company_name = company
    if req.is_enabled is not None:
        cfg.is_enabled = req.is_enabled
    if req.auto_sync is not None:
        cfg.auto_sync = req.auto_sync
    if req.sync_interval_minutes is not None:
        cfg.sync_interval_minutes = req.sync_interval_minutes

    await db.commit()
    await db.refresh(cfg)

    status_str = "CONNECTED" if is_connected else "OFFLINE"
    return TallyConnectResponse(
        status=status_str,
        message=test_msg,
        is_connected=is_connected,
        active_company=cfg.company_name,
        available_companies=company_names,
        config=TallyConfigResponse.model_validate(cfg),
    )


@router.get("/companies", response_model=List[TallyCompanyResponse])
async def list_companies(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> List[TallyCompanyResponse]:
    """Fetch available companies currently open across configured TallyPrime hosts."""
    cfg = await TallySyncService.get_or_create_config(db)
    endpoints = TallySyncService.get_configured_endpoints(cfg)
    probes = await TallyHttpClient.probe_endpoints(endpoints, timeout=5.0)
    reachable = [p for p in probes if p[3]]
    if not reachable:
        tried = ", ".join(TallyHttpClient.get_url(h, p, u) for h, p, u in endpoints)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Cannot reach Tally at {tried}. Please ensure TallyPrime is running with HTTP port enabled.",
        )

    merged_companies: List[Dict[str, Any]] = []
    seen_names: set[str] = set()
    for _, _, _, _, _, ep_companies in reachable:
        for c in ep_companies:
            cname = (c.get("name") or "").strip()
            if cname and cname not in seen_names:
                seen_names.add(cname)
                merged_companies.append(c)

    return [
        TallyCompanyResponse(
            name=c["name"],
            starting_from=c.get("starting_from"),
            ending_at=c.get("ending_at"),
            is_active=(c["name"] == cfg.company_name),
        )
        for c in merged_companies
    ]


# ---------------------------------------------------------------------------
# 2. Sales Vouchers Management
# ---------------------------------------------------------------------------

@router.get("/sales-vouchers", response_model=List[TallySalesVoucherResponse])
async def list_sales_vouchers(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: Optional[str] = Query(None, description="Search by invoice number or party name"),
    from_date: Optional[date] = Query(None, description="Filter vouchers from date"),
    to_date: Optional[date] = Query(None, description="Filter vouchers to date"),
    is_processed: Optional[bool] = Query(None, description="Filter by GA STOCK processed state"),
    is_cancelled: Optional[bool] = Query(None, description="Filter by cancellation state"),
    include_mock: bool = Query(False, description="Include mock / test vouchers"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> List[TallySalesVoucherResponse]:
    """
    List imported Tally sales vouchers.
    STRICTLY NO FINANCIAL DATA RETURNED.
    """
    query = select(TallySalesVoucher).options(selectinload(TallySalesVoucher.items))

    if not include_mock:
        query = query.where(
            ~TallySalesVoucher.guid.ilike("tally-guid-%"),
            ~TallySalesVoucher.guid.ilike("agent-push-%"),
            ~TallySalesVoucher.guid.ilike("live-test-%"),
            ~TallySalesVoucher.guid.ilike("mock-%"),
            TallySalesVoucher.party_name != "Unknown Party",
            ~TallySalesVoucher.voucher_number.ilike("INV/%/045%"),
            ~TallySalesVoucher.voucher_number.ilike("INV/AGENT/%"),
        )

    if q and q.strip():
        term = f"%{q.strip()}%"
        query = query.where(
            or_(
                TallySalesVoucher.voucher_number.ilike(term),
                TallySalesVoucher.party_name.ilike(term),
                TallySalesVoucher.party_ledger_name.ilike(term),
                TallySalesVoucher.buyer_name.ilike(term),
                TallySalesVoucher.vehicle_number.ilike(term),
            )
        )

    if from_date and isinstance(from_date, date):
        query = query.where(
            or_(
                TallySalesVoucher.voucher_date >= from_date,
                func.date(TallySalesVoucher.created_at) >= from_date,
            )
        )
    if to_date and isinstance(to_date, date):
        query = query.where(
            or_(
                TallySalesVoucher.voucher_date <= to_date,
                func.date(TallySalesVoucher.created_at) <= to_date,
            )
        )
    if is_processed is not None:
        query = query.where(TallySalesVoucher.is_processed == is_processed)
    if is_cancelled is not None:
        query = query.where(TallySalesVoucher.is_cancelled == is_cancelled)
    else:
        # Never return cancelled or deleted vouchers by default
        query = query.where(
            TallySalesVoucher.is_cancelled == False,
            TallySalesVoucher.is_deleted == False,
        )

    query = query.order_by(
        desc(TallySalesVoucher.voucher_date),
        desc(TallySalesVoucher.created_at),
    ).offset(offset).limit(limit)

    res = await db.execute(query)
    vouchers = res.scalars().all()

    # Fast targeted reconciliation only for retrieved vouchers
    unproc_vch_numbers = [
        v.voucher_number.strip().lower()
        for v in vouchers
        if not v.is_processed and v.voucher_number and v.voucher_number != "VCH-UNNUMBERED"
    ]
    if unproc_vch_numbers:
        ob_res = await db.execute(
            select(func.lower(OutwardBatch.bill_number)).where(
                OutwardBatch.bill_number.is_not(None),
                OutwardBatch.is_cancelled == False,
                func.lower(OutwardBatch.bill_number).in_(unproc_vch_numbers),
            )
        )
        matched_bills = {b for (b,) in ob_res.all() if b}
        if matched_bills:
            changed = False
            for v in vouchers:
                if (
                    not v.is_processed
                    and v.voucher_number
                    and v.voucher_number.strip().lower() in matched_bills
                ):
                    v.is_processed = True
                    v.processed_at = v.processed_at or datetime.now()
                    if not v.notes:
                        v.notes = f"Dispatched via GA STOCK Outward (Bill: {v.voucher_number})"
                    changed = True
            if changed:
                await db.commit()

    # Pre-lookup shops ONLY for party names present in the retrieved vouchers
    party_names = {v.party_name.strip().lower() for v in vouchers if v.party_name}
    shop_lookup = {}
    if party_names:
        shops_res = await db.execute(
            select(Shop).where(Shop.is_active == True, func.lower(Shop.name).in_(party_names))
        )
        shop_lookup = {s.name.strip().lower(): s.id for s in shops_res.scalars().all()}

    # Pre-lookup ONLY the specific products and categories used in these vouchers
    all_pids = {itm.product_id for v in vouchers for itm in v.items if itm.product_id}
    prod_by_id = {}
    cat_by_id = {}
    if all_pids:
        prods_res = await db.execute(select(Product).where(Product.id.in_(all_pids)))
        prods_list = prods_res.scalars().all()
        prod_by_id = {p.id: p for p in prods_list}
        all_cids = {p.category_id for p in prods_list if p.category_id}
        if all_cids:
            cats_res = await db.execute(select(Category).where(Category.id.in_(all_cids)))
            cat_by_id = {c.id: c for c in cats_res.scalars().all()}

    output: List[TallySalesVoucherResponse] = []
    for v in vouchers:
        item_count = len(v.items)
        total_qty = sum([itm.quantity for itm in v.items])
        godowns = sorted(list({itm.godown_name for itm in v.items if itm.godown_name}))
        matched_shop_id = shop_lookup.get(v.party_name.strip().lower())

        items_list: List[TallyVoucherItemResponse] = []
        has_dual = False
        for itm in v.items:
            p_obj = prod_by_id.get(itm.product_id) if itm.product_id else None
            p_cat = cat_by_id.get(p_obj.category_id) if (p_obj and p_obj.category_id) else None
            cat_name = p_cat.name if p_cat else ""
            item_is_dual = TallySyncService.is_dual_serial_model(itm.item_name, cat_name)
            if not item_is_dual and p_cat and (p_cat.has_dual_serial or TallySyncService.is_dual_serial_category(p_cat.name)):
                name_u = itm.item_name.upper()
                accessories = (
                    "STAND", "TROLLEY", "PIPE", "TUBE", "BLENDER", "CUTTER", "GEAR", "JAR",
                    "STABILIZER", "REMOTE", "BRACKET", "DRAIN", "COVER", "ACCESSORY", "COPPER TUBE",
                    "TV", "LED", "COOLER", "CHILLER", "FREEZER", "REFRIGERATOR", "REF ", "REF/", "FRIDGE",
                    "WASHING", "WM ", "W/M", "FAN", "GEYSER", "HEATER", "DISPENSER", "PURIFIER", "MICROWAVE", "OVEN"
                )
                if not any(acc in name_u for acc in accessories) and TallySyncService.is_dual_serial_category(p_cat.name):
                    item_is_dual = True
            if item_is_dual:
                has_dual = True

            items_list.append(
                TallyVoucherItemResponse(
                    id=itm.id,
                    voucher_id=itm.voucher_id,
                    item_name=itm.item_name,
                    item_code=itm.item_code,
                    quantity=itm.quantity,
                    uom=itm.uom,
                    raw_qty_text=itm.raw_qty_text,
                    godown_name=itm.godown_name,
                    batch_name=itm.batch_name,
                    batch_details=itm.batch_details,
                    product_id=itm.product_id or (p_obj.id if p_obj else None),
                    matched_product_name=p_obj.name if p_obj else None,
                    matched_product_model=p_obj.model if p_obj else None,
                    matched_product_brand=p_obj.brand if p_obj else None,
                    has_dual_serial=item_is_dual,
                    is_new_model=(p_obj is None),
                    created_at=itm.created_at,
                )
            )

        output.append(
            TallySalesVoucherResponse(
                id=v.id,
                guid=v.guid,
                alter_id=v.alter_id,
                master_id=v.master_id,
                voucher_number=v.voucher_number,
                voucher_date=v.voucher_date,
                voucher_type=v.voucher_type,
                party_name=v.party_name,
                party_ledger_name=v.party_ledger_name,
                buyer_name=v.buyer_name,
                shop_id=matched_shop_id,
                address=v.address,
                state_name=v.state_name,
                company_name=v.company_name,
                vehicle_number=v.vehicle_number,
                transporter_name=v.transporter_name,
                delivery_note=v.delivery_note,
                destination=v.destination,
                is_cancelled=v.is_cancelled,
                is_deleted=v.is_deleted,
                is_processed=v.is_processed,
                processed_at=v.processed_at,
                item_count=item_count,
                total_quantity=total_qty,
                has_dual_serial_items=has_dual,
                godowns=godowns,
                items=items_list,
                created_at=v.created_at,
                updated_at=v.updated_at,
            )
        )
    return output


@router.get("/sales-vouchers/{voucher_id}", response_model=TallySalesVoucherDetailResponse)
async def get_sales_voucher_detail(
    voucher_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TallySalesVoucherDetailResponse:
    """Fetch single Tally sales voucher with all its inventory items."""
    res = await db.execute(
        select(TallySalesVoucher)
        .options(selectinload(TallySalesVoucher.items))
        .where(TallySalesVoucher.id == voucher_id)
    )
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Tally sales voucher not found.")

    # 1. Match or auto-create Shop for party
    s_res = await db.execute(select(Shop).where(func.lower(Shop.name) == func.lower(v.party_name.strip())))
    shop = s_res.scalar_one_or_none()
    if not shop:
        city_val = v.state_name
        if not city_val and v.address:
            city_val = v.address.split(",")[0][:90].strip()
        shop = Shop(
            name=v.party_name.strip(),
            city=city_val or "Local",
            address=v.address,
            state=v.state_name,
            source="TALLY",
            is_active=True,
        )
        db.add(shop)
        await db.flush()

    # 2. Look up all products and categories for matching and dual series identification
    prod_res = await db.execute(select(Product).where(Product.is_active == True))
    all_prods = list(prod_res.scalars().all())
    prod_by_id = {p.id: p for p in all_prods}
    prod_by_name = {p.name.strip().lower(): p for p in all_prods}
    prod_by_model = {p.model.strip().lower(): p for p in all_prods}

    cats_res = await db.execute(select(Category))
    cat_by_id = {c.id: c for c in cats_res.scalars().all()}

    item_count = len(v.items)
    total_qty = sum([itm.quantity for itm in v.items])
    godowns = sorted(list({itm.godown_name for itm in v.items if itm.godown_name}))

    items_res: List[TallyVoucherItemResponse] = []
    needs_commit = False
    for itm in v.items:
        p_obj = prod_by_id.get(itm.product_id) if itm.product_id else None
        if not p_obj:
            itm_name_clean = itm.item_name.strip().lower()
            itm_code_clean = (itm.item_code or "").strip().lower()
            p_obj = prod_by_name.get(itm_name_clean) or prod_by_model.get(itm_name_clean) or (prod_by_model.get(itm_code_clean) if itm_code_clean else None)
            if not p_obj:
                for p in all_prods:
                    if len(p.model.strip()) >= 4 and p.model.strip().lower() in itm_name_clean:
                        p_obj = p
                        break
        existed_in_db = (p_obj is not None)
        if not p_obj:
            is_dual = TallySyncService.is_dual_serial_model(itm.item_name)
            # Pick best category: if dual, select an active dual category; if non-dual, select an active non-dual category
            target_cat = None
            if is_dual:
                for c in cat_by_id.values():
                    if c.is_active and (c.has_dual_serial or TallySyncService.is_dual_serial_category(c.name)):
                        target_cat = c
                        break
            else:
                for c in cat_by_id.values():
                    if c.is_active and not c.has_dual_serial and not TallySyncService.is_dual_serial_category(c.name):
                        target_cat = c
                        break
            if not target_cat:
                target_cat = Category(
                    name="General" if is_dual else "General Appliances",
                    has_dual_serial=is_dual,
                    is_active=True,
                    source="TALLY",
                )
                db.add(target_cat)
                await db.flush()
                cat_by_id[target_cat.id] = target_cat

            first_word = itm.item_name.split()[0]
            brand_guess = first_word if len(first_word) <= 20 else "Tally"
            p_obj = Product(
                name=itm.item_name.strip(),
                brand=brand_guess,
                model=itm.item_code or itm.item_name.strip(),
                category_id=target_cat.id,
                unit=itm.uom or "NOS",
                serial_number_required=True,
                is_active=True,
                source="TALLY",
            )
            db.add(p_obj)
            await db.flush()
            all_prods.append(p_obj)
            prod_by_id[p_obj.id] = p_obj

            itm.product_id = p_obj.id
            needs_commit = True

        p_cat = cat_by_id.get(p_obj.category_id) if (p_obj and p_obj.category_id) else None
        cat_name = p_cat.name if p_cat else ""
        is_item_dual = TallySyncService.is_dual_serial_model(itm.item_name, cat_name)
        if not is_item_dual and p_cat and (p_cat.has_dual_serial or TallySyncService.is_dual_serial_category(p_cat.name)):
            name_u = itm.item_name.upper()
            accessories = (
                "STAND", "TROLLEY", "PIPE", "TUBE", "BLENDER", "CUTTER", "GEAR", "JAR",
                "STABILIZER", "REMOTE", "BRACKET", "DRAIN", "COVER", "ACCESSORY", "COPPER TUBE",
                "TV", "LED", "COOLER", "CHILLER", "FREEZER", "REFRIGERATOR", "REF ", "REF/", "FRIDGE",
                "WASHING", "WM ", "W/M", "FAN", "GEYSER", "HEATER", "DISPENSER", "PURIFIER", "MICROWAVE", "OVEN"
            )
            if not any(acc in name_u for acc in accessories) and TallySyncService.is_dual_serial_category(p_cat.name):
                is_item_dual = True

        p_brand = (p_obj.brand or "").strip().upper() if p_obj else ""
        recognized_brands = {"GENERAL", "HAIER", "FORMENTY", "CARRIER", "ROCKWELL", "MIDEA"}
        is_known_brand = p_brand in recognized_brands
        is_new_model = not existed_in_db

        items_res.append(
            TallyVoucherItemResponse(
                id=itm.id,
                voucher_id=itm.voucher_id,
                item_name=itm.item_name,
                item_code=itm.item_code,
                product_id=p_obj.id if p_obj else itm.product_id,
                quantity=itm.quantity,
                uom=itm.uom,
                raw_qty_text=itm.raw_qty_text,
                godown_name=itm.godown_name,
                batch_name=itm.batch_name,
                batch_details=itm.batch_details,
                matched_product_name=p_obj.name if p_obj else None,
                matched_product_model=p_obj.model if p_obj else None,
                matched_product_brand=p_obj.brand if (p_obj and is_known_brand) else None,
                is_new_model=is_new_model,
                has_dual_serial=is_item_dual,
                created_at=itm.created_at,
            )
        )

    if needs_commit:
        await db.commit()

    has_any_dual = any(i.has_dual_serial for i in items_res)

    return TallySalesVoucherDetailResponse(
        id=v.id,
        guid=v.guid,
        alter_id=v.alter_id,
        master_id=v.master_id,
        voucher_number=v.voucher_number,
        voucher_date=v.voucher_date,
        voucher_type=v.voucher_type,
        party_name=v.party_name,
        party_ledger_name=v.party_ledger_name,
        buyer_name=v.buyer_name,
        shop_id=shop.id if shop else None,
        address=v.address,
        state_name=v.state_name,
        company_name=v.company_name,
        vehicle_number=v.vehicle_number,
        transporter_name=v.transporter_name,
        delivery_note=v.delivery_note,
        destination=v.destination,
        is_cancelled=v.is_cancelled,
        is_deleted=v.is_deleted,
        is_processed=v.is_processed,
        processed_at=v.processed_at,
        item_count=item_count,
        total_quantity=total_qty,
        has_dual_serial_items=has_any_dual,
        godowns=godowns,
        notes=v.notes,
        raw_metadata=v.raw_metadata,
        items=items_res,
        created_at=v.created_at,
        updated_at=v.updated_at,
    )


RECOGNIZED_BRANDS = ["GENERAL", "HAIER", "FORMENTY", "CARRIER", "ROCKWELL", "MIDEA"]


@router.post("/assign-brand", response_model=ProductResponse)
async def assign_tally_brand(
    req: TallyAssignBrandRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ProductResponse:
    """
    Staff / Admin: assign a recognized brand (GENERAL, HAIER, FORMENTY, CARRIER, ROCKWELL, MIDEA)
    to a product or voucher item.
    Persists brand and category linkage in GA STOCK database.
    """
    norm_brand = req.brand.strip().upper()
    if norm_brand not in RECOGNIZED_BRANDS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid brand '{req.brand}'. Must be one of: {', '.join(RECOGNIZED_BRANDS)}",
        )

    product: Optional[Product] = None
    if req.product_id:
        p_res = await db.execute(select(Product).where(Product.id == req.product_id))
        product = p_res.scalar_one_or_none()

    voucher_item: Optional[TallyVoucherItem] = None
    if req.voucher_item_id:
        vi_res = await db.execute(select(TallyVoucherItem).where(TallyVoucherItem.id == req.voucher_item_id))
        voucher_item = vi_res.scalar_one_or_none()
        if voucher_item and not product and voucher_item.product_id:
            p_res = await db.execute(select(Product).where(Product.id == voucher_item.product_id))
            product = p_res.scalar_one_or_none()

    item_name_str = (
        req.item_name
        or (voucher_item.item_name if voucher_item else None)
        or (product.name if product else "")
    ).strip()

    if not product and item_name_str:
        p_res = await db.execute(
            select(Product).where(
                or_(
                    func.lower(Product.name) == item_name_str.lower(),
                    func.lower(Product.model) == item_name_str.lower(),
                )
            )
        )
        product = p_res.scalars().first()

    all_cats_res = await db.execute(select(Category).where(Category.is_active == True))
    all_cats = all_cats_res.scalars().all()

    target_cat: Optional[Category] = None
    if req.category_id:
        target_cat = next((c for c in all_cats if c.id == req.category_id), None)

    desired_dual = req.has_dual_serial

    if not target_cat:
        if desired_dual is not None:
            matching_cats = [c for c in all_cats if c.has_dual_serial == desired_dual]
        else:
            matching_cats = all_cats

        if norm_brand == "GENERAL":
            target_cat = next(
                (c for c in matching_cats if "general" in c.name.lower()),
                None,
            )
        elif norm_brand == "CARRIER":
            target_cat = next((c for c in matching_cats if "carrier" in c.name.lower()), None)
            if not target_cat and desired_dual is True:
                target_cat = next((c for c in matching_cats if c.name.strip().upper() == "AC"), None)
        elif norm_brand == "HAIER":
            target_cat = next((c for c in matching_cats if "haier" in c.name.lower()), None)
            if not target_cat and desired_dual is True:
                target_cat = next((c for c in matching_cats if c.name.strip().upper() == "AC"), None)
        elif norm_brand == "MIDEA":
            target_cat = next((c for c in matching_cats if "midea" in c.name.lower()), None)
            if not target_cat and desired_dual is True:
                target_cat = next((c for c in matching_cats if c.name.strip().upper() == "AC"), None)
        elif norm_brand == "ROCKWELL":
            target_cat = next(
                (c for c in matching_cats if "rockwell" in c.name.lower()),
                next((c for c in matching_cats if "celfrost" in c.name.lower()), None),
            )
        elif norm_brand == "FORMENTY":
            if desired_dual is True:
                target_cat = next((c for c in matching_cats if "ac" in c.name.lower() and "formenty" in c.name.lower()), None)
            elif desired_dual is False:
                target_cat = next((c for c in matching_cats if "led" in c.name.lower() and "formenty" in c.name.lower()), None)
            if not target_cat:
                target_cat = next((c for c in matching_cats if "formenty" in c.name.lower()), None)

    if not target_cat:
        is_dual = desired_dual if desired_dual is not None else (norm_brand in ("GENERAL", "CARRIER", "HAIER", "MIDEA"))
        cat_suffix = "AC" if is_dual else "Appliances"
        cat_title = f"{norm_brand.title()} {cat_suffix}" if norm_brand != "GENERAL" else ("General" if is_dual else "General Appliances")
        target_cat = Category(
            name=cat_title,
            has_dual_serial=is_dual,
            is_active=True,
            source="SYSTEM",
        )
        db.add(target_cat)
        await db.flush()

    if not product:
        product = Product(
            name=item_name_str,
            brand=norm_brand,
            model=voucher_item.item_code or item_name_str if voucher_item else item_name_str,
            category_id=target_cat.id,
            unit=voucher_item.uom if (voucher_item and voucher_item.uom) else "NOS",
            serial_number_required=True,
            is_active=True,
            source="TALLY",
        )
        db.add(product)
        await db.flush()
    else:
        product.brand = norm_brand
        product.category_id = target_cat.id

    if voucher_item and voucher_item.product_id != product.id:
        voucher_item.product_id = product.id

    if product.model:
        matching_prods_res = await db.execute(
            select(Product).where(
                Product.id != product.id,
                func.lower(Product.model) == product.model.strip().lower(),
            )
        )
        for other_p in matching_prods_res.scalars().all():
            other_p.brand = norm_brand
            other_p.category_id = target_cat.id

    await db.commit()
    await db.refresh(product)

    resp = ProductResponse.model_validate(product)
    resp.category_name = target_cat.name
    resp.has_dual_serial = target_cat.has_dual_serial

    await ws_manager.broadcast("product_updated", json.loads(resp.model_dump_json()))
    return resp


@router.post("/sales-vouchers/{voucher_id}/mark-processed")
async def mark_voucher_processed(
    voucher_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    processed: bool = Query(True, description="True to mark processed, False to unmark"),
    notes: Optional[str] = Query(None, description="Optional dispatch remarks"),
) -> dict:
    """Mark a Tally voucher as processed in GA STOCK."""
    res = await db.execute(
        select(TallySalesVoucher).where(TallySalesVoucher.id == voucher_id)
    )
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Tally sales voucher not found.")

    v.is_processed = processed
    v.processed_at = datetime.now() if processed else None
    v.processed_by_id = current_user.id if processed else None
    if notes is not None:
        v.notes = notes

    await db.commit()
    try:
        await ws_manager.broadcast("tally_bill_processed", {
            "id": str(v.id),
            "voucher_number": v.voucher_number,
            "is_processed": v.is_processed,
        })
    except Exception:
        pass

    return {
        "status": "success",
        "voucher_id": str(v.id),
        "is_processed": v.is_processed,
        "processed_at": v.processed_at.isoformat() if v.processed_at else None,
    }


@router.delete("/sales-vouchers/{voucher_id}")
async def delete_sales_voucher(
    voucher_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Delete a sales voucher from GA STOCK (Admin or Staff). Note: strictly does not delete from Tally."""
    res = await db.execute(select(TallySalesVoucher).where(TallySalesVoucher.id == voucher_id))
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Tally sales voucher not found.")

    v_num = v.voucher_number
    v_id = str(v.id)

    # Flag as deleted so background Tally sync never resurrects it
    v.is_deleted = True
    v.is_cancelled = True
    await db.execute(delete(TallyVoucherItem).where(TallyVoucherItem.voucher_id == v.id))
    await db.commit()

    # Real-time WebSocket broadcast to remove it from mobile and web screens instantly
    await ws_manager.broadcast("tally_bill_cancelled", {
        "id": v_id,
        "voucher_number": v_num,
        "bill_number": v_num,
    })

    return {"status": "success", "message": f"Voucher {v_num} deleted successfully."}


@router.post("/sales-vouchers/clean-mock")
@router.delete("/sales-vouchers/clean-mock")
async def delete_mock_sales_vouchers(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Remove all mock / test bills from Tally sales vouchers."""
    res = await db.execute(
        select(TallySalesVoucher).where(
            or_(
                TallySalesVoucher.guid.ilike("tally-guid-%"),
                TallySalesVoucher.guid.ilike("agent-push-%"),
                TallySalesVoucher.guid.ilike("live-test-%"),
                TallySalesVoucher.guid.ilike("mock-%"),
                TallySalesVoucher.party_name == "Unknown Party",
                TallySalesVoucher.voucher_number.ilike("INV/%/045%"),
                TallySalesVoucher.voucher_number.ilike("INV/AGENT/%"),
            )
        )
    )
    vouchers = res.scalars().all()
    count = len(vouchers)
    if vouchers:
        v_ids = [v.id for v in vouchers]
        await db.execute(delete(TallyVoucherItem).where(TallyVoucherItem.voucher_id.in_(v_ids)))
        await db.execute(delete(TallySalesVoucher).where(TallySalesVoucher.id.in_(v_ids)))
        await db.commit()

    return {"status": "success", "deleted_count": count, "message": f"Removed {count} mock vouchers."}


# ---------------------------------------------------------------------------
# 3. Synchronization Triggers & Status
# ---------------------------------------------------------------------------

@router.post("/sync", response_model=TallySyncResponse)
@router.get("/sync", response_model=TallySyncResponse)
async def trigger_sync(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: Optional[date] = Query(None, description="Start date for sync"),
    to_date: Optional[date] = Query(None, description="End date for sync"),
    company_name: Optional[str] = Query(None, description="Override company name"),
    force_full: bool = Query(False, description="Ignore AlterID and re-fetch date range"),
) -> TallySyncResponse:
    """Trigger synchronization between Tally and GA STOCK."""
    worker = TallyBackgroundWorker.get_instance()
    t0 = time.time()

    try:
        history = await worker.run_manual_sync(
            from_date=from_date,
            to_date=to_date,
            company_name=company_name,
            force_full=force_full,
        )
        duration = round(time.time() - t0, 2)
        global _last_status_time
        _last_status_time = 0.0

        if history.status == "SUCCESS":
            msg = (
                f"Sync completed successfully. {history.vouchers_fetched} vouchers fetched "
                f"({history.vouchers_created} new, {history.vouchers_updated} updated, {history.vouchers_cancelled} cancelled)."
            )
        else:
            msg = f"Sync failed: {history.error_message or 'Unknown error'}"

        return TallySyncResponse(
            status=history.status,
            message=msg,
            vouchers_fetched=history.vouchers_fetched,
            vouchers_created=history.vouchers_created,
            vouchers_updated=history.vouchers_updated,
            vouchers_cancelled=history.vouchers_cancelled,
            duration_seconds=duration,
            history_id=history.id,
        )
    except RuntimeError as re_err:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(re_err),
        )
    except Exception as ex:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Tally synchronization error: {str(ex)}",
        )


@router.post("/sync-masters")
@router.get("/sync-masters")
async def trigger_masters_sync(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    company_name: Optional[str] = Query(None, description="Override company name"),
) -> dict:
    """Manually pull stock groups (categories), stock items (products), shops (ledgers) & stock qty from Tally."""
    worker = TallyBackgroundWorker.get_instance()
    try:
        res = await worker.run_manual_masters_sync(company_name=company_name)
        shops_total = res.get("shops_created", 0) + res.get("shops_updated", 0)
        cats_total = res.get("categories_created", 0) + res.get("categories_updated", 0)
        prods_total = res.get("products_created", 0) + res.get("products_updated", 0)
        try:
            await ws_manager.broadcast("stock_updated", {"bulk": True})
            await ws_manager.broadcast("category_updated", {"bulk": True})
            await ws_manager.broadcast("shop_updated", {"bulk": True})
        except Exception:
            pass
        return {
            "status": "SUCCESS",
            "message": f"Pulled {cats_total} categories, {prods_total} items, {shops_total} shops, and updated stock qty for {res.get('tally_stock_synced', 0)} items from Tally.",
            "details": res,
        }
    except RuntimeError as re_err:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(re_err),
        )
    except Exception as ex:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Tally masters sync error: {str(ex)}",
        )


@router.get("/sync-status", response_model=TallySyncStatusResponse)
async def get_sync_status(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TallySyncStatusResponse:
    """Returns the last synchronization status and recent run history."""
    cfg = await TallySyncService.get_or_create_config(db)
    worker = TallyBackgroundWorker.get_instance()

    hist_res = await db.execute(
        select(TallySyncHistory)
        .order_by(desc(TallySyncHistory.started_at))
        .limit(10)
    )
    history_items = hist_res.scalars().all()

    return TallySyncStatusResponse(
        last_sync_at=cfg.last_sync_at,
        last_sync_status=cfg.last_sync_status,
        last_sync_message=cfg.last_sync_message,
        is_syncing=worker.is_syncing,
        recent_history=[
            TallySyncHistoryItemResponse.model_validate(h) for h in history_items
        ],
    )


# ---------------------------------------------------------------------------
# 4. Office PC Local Agent Push (for Firewalled / NAT Networks)
# ---------------------------------------------------------------------------

@router.post("/agent/push", response_model=TallyAgentPushResponse)
async def agent_push_vouchers(
    payload: TallyAgentPushRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    x_tally_agent_token: Annotated[Optional[str], Header(alias="X-Tally-Agent-Token")] = None,
) -> TallyAgentPushResponse:
    """
    Secure endpoint for the local connector agent running on the office PC.
    Validates token, processes non-financial vouchers, and records sync history.
    """
    if not x_tally_agent_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing X-Tally-Agent-Token header.",
        )

    cfg = await TallySyncService.get_or_create_config(db)
    if not cfg.agent_token or cfg.agent_token != x_tally_agent_token:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid Tally agent authentication token.",
        )

    t0 = datetime.now()
    created, updated, cancelled = await TallySyncService.process_vouchers(
        db, payload.vouchers, company_name=payload.company_name or cfg.company_name
    )

    # Record sync history from local agent
    history = TallySyncHistory(
        sync_source="LOCAL_AGENT",
        company_name=payload.company_name or cfg.company_name,
        status="SUCCESS",
        started_at=t0,
        completed_at=datetime.now(),
        vouchers_fetched=len(payload.vouchers),
        vouchers_created=created,
        vouchers_updated=updated,
        vouchers_cancelled=cancelled,
    )
    db.add(history)

    cfg.last_sync_at = datetime.now()
    cfg.last_sync_status = "SUCCESS"
    cfg.last_sync_message = f"Agent pushed {len(payload.vouchers)} vouchers ({created} new, {updated} updated)."

    await db.commit()

    return TallyAgentPushResponse(
        status="SUCCESS",
        received_count=len(payload.vouchers),
        created_count=created,
        updated_count=updated,
        cancelled_count=cancelled,
    )

