import time
import uuid
from datetime import date, datetime
from typing import Annotated, Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user, require_admin
from app.database import get_db
from app.models.tally import (
    TallyConfig,
    TallySalesVoucher,
    TallySyncHistory,
    TallyVoucherItem,
)
from app.models.user import User
from app.schemas.tally import (
    TallyAgentPushRequest,
    TallyAgentPushResponse,
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


# ---------------------------------------------------------------------------
# 1. Connection Status & Configuration
# ---------------------------------------------------------------------------

@router.get("/status", response_model=TallyStatusResponse)
async def get_tally_status(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TallyStatusResponse:
    """Check Tally connection status and sync state."""
    cfg = await TallySyncService.get_or_create_config(db)

    # Fast probe to see if Tally is currently reachable
    is_connected, msg, companies = await TallyHttpClient.test_connection(
        cfg.host, cfg.port, cfg.tally_url, timeout=2.5
    )

    company_names = [c["name"] for c in companies]

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

    return TallyStatusResponse(
        is_connected=is_connected,
        host=cfg.host,
        port=cfg.port,
        tally_url=cfg.tally_url,
        active_company=cfg.company_name,
        is_enabled=cfg.is_enabled,
        auto_sync=cfg.auto_sync,
        sync_interval_minutes=cfg.sync_interval_minutes,
        last_sync_at=cfg.last_sync_at,
        last_sync_status=cfg.last_sync_status,
        last_sync_message=cfg.last_sync_message,
        last_alter_id=cfg.last_alter_id,
        available_companies=company_names,
        total_vouchers=total_count,
        pending_vouchers=pending_count,
        is_syncing=worker.is_syncing,
        agent_configured=bool(cfg.agent_token),
    )


@router.post("/connect", response_model=TallyConnectResponse)
async def connect_tally(
    req: TallyConnectRequest,
    current_user: Annotated[User, Depends(get_current_user)],
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
    """Fetch available companies currently open in TallyPrime."""
    cfg = await TallySyncService.get_or_create_config(db)
    is_connected, _, companies = await TallyHttpClient.test_connection(
        cfg.host, cfg.port, cfg.tally_url, timeout=5.0
    )
    if not is_connected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Cannot reach Tally at {cfg.host}:{cfg.port}. Please ensure TallyPrime is running with port {cfg.port} enabled.",
        )

    return [
        TallyCompanyResponse(
            name=c["name"],
            starting_from=c.get("starting_from"),
            ending_at=c.get("ending_at"),
            is_active=(c["name"] == cfg.company_name),
        )
        for c in companies
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
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> List[TallySalesVoucherResponse]:
    """
    List imported Tally sales vouchers.
    STRICTLY NO FINANCIAL DATA RETURNED.
    """
    query = select(TallySalesVoucher).options(selectinload(TallySalesVoucher.items))

    if q and q.strip():
        term = f"%{q.strip()}%"
        query = query.where(
            or_(
                TallySalesVoucher.voucher_number.ilike(term),
                TallySalesVoucher.party_name.ilike(term),
                TallySalesVoucher.party_ledger_name.ilike(term),
                TallySalesVoucher.buyer_name.ilike(term),
            )
        )

    if from_date:
        query = query.where(TallySalesVoucher.voucher_date >= from_date)
    if to_date:
        query = query.where(TallySalesVoucher.voucher_date <= to_date)
    if is_processed is not None:
        query = query.where(TallySalesVoucher.is_processed == is_processed)
    if is_cancelled is not None:
        query = query.where(TallySalesVoucher.is_cancelled == is_cancelled)

    query = query.order_by(
        desc(TallySalesVoucher.voucher_date),
        desc(TallySalesVoucher.created_at),
    ).offset(offset).limit(limit)

    res = await db.execute(query)
    vouchers = res.scalars().all()

    output: List[TallySalesVoucherResponse] = []
    for v in vouchers:
        item_count = len(v.items)
        total_qty = sum([itm.quantity for itm in v.items])
        godowns = sorted(list({itm.godown_name for itm in v.items if itm.godown_name}))

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
                address=v.address,
                state_name=v.state_name,
                company_name=v.company_name,
                is_cancelled=v.is_cancelled,
                is_deleted=v.is_deleted,
                is_processed=v.is_processed,
                processed_at=v.processed_at,
                item_count=item_count,
                total_quantity=total_qty,
                godowns=godowns,
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

    item_count = len(v.items)
    total_qty = sum([itm.quantity for itm in v.items])
    godowns = sorted(list({itm.godown_name for itm in v.items if itm.godown_name}))

    items_res: List[TallyVoucherItemResponse] = []
    for itm in v.items:
        items_res.append(
            TallyVoucherItemResponse(
                id=itm.id,
                voucher_id=itm.voucher_id,
                item_name=itm.item_name,
                item_code=itm.item_code,
                product_id=itm.product_id,
                quantity=itm.quantity,
                uom=itm.uom,
                raw_qty_text=itm.raw_qty_text,
                godown_name=itm.godown_name,
                batch_name=itm.batch_name,
                batch_details=itm.batch_details,
                created_at=itm.created_at,
            )
        )

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
        address=v.address,
        state_name=v.state_name,
        company_name=v.company_name,
        is_cancelled=v.is_cancelled,
        is_deleted=v.is_deleted,
        is_processed=v.is_processed,
        processed_at=v.processed_at,
        item_count=item_count,
        total_quantity=total_qty,
        godowns=godowns,
        notes=v.notes,
        raw_metadata=v.raw_metadata,
        items=items_res,
        created_at=v.created_at,
        updated_at=v.updated_at,
    )


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
    return {
        "status": "success",
        "voucher_id": str(v.id),
        "is_processed": v.is_processed,
        "processed_at": v.processed_at.isoformat() if v.processed_at else None,
    }


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

