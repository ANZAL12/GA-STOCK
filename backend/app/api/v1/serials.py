from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.database import get_db
from app.models.audit import AuditLog
from app.models.category import Category
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.serial_status import (
    SerialDetailResponse,
    SerialHistoryItem,
    SerialListItem,
    SerialListResponse,
    SerialStatusChangeRequest,
)

router = APIRouter(prefix="/serials", tags=["serials"])


@router.get("", response_model=SerialListResponse)
async def list_serials(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: Optional[str] = Query(None, description="Search query across serial, model, brand, category, shop, ref"),
    flow: Optional[str] = Query("all", description="Filter: all | inward | outward | damaged"),
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0),
) -> SerialListResponse:
    """
    List all serial numbers across inward and outward dispatches.
    Displays model, brand, serial number, category, timestamp, date, shop (for outward), and references.
    """
    # 1. Latest outward dispatch subquery per serial
    outward_subq = (
        select(
            OutwardLine.serial_number_id,
            OutwardLine.transaction_date.label("outward_date"),
            OutwardBatch.delivery_reference.label("outward_ref"),
            OutwardLine.created_at.label("outward_created_at"),
            Shop.name.label("outward_shop_name"),
            Shop.city.label("outward_shop_city"),
        )
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .distinct(OutwardLine.serial_number_id)
        .order_by(OutwardLine.serial_number_id, OutwardLine.created_at.desc())
        .subquery()
    )

    # 2. Tracked serial numbers query
    tracked_query = (
        select(
            SerialNumber.id.label("sn_id"),
            SerialNumber.serial_number.label("sn_text"),
            SerialNumber.status.label("sn_status"),
            SerialNumber.created_at.label("sn_created_at"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            InwardBatch.transaction_date.label("inward_date"),
            InwardBatch.invoice_reference.label("inward_ref"),
            outward_subq.c.outward_date,
            outward_subq.c.outward_ref,
            outward_subq.c.outward_created_at,
            outward_subq.c.outward_shop_name,
            outward_subq.c.outward_shop_city,
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .outerjoin(InwardLine, InwardLine.serial_number_id == SerialNumber.id)
        .outerjoin(InwardBatch, InwardLine.batch_id == InwardBatch.id)
        .outerjoin(outward_subq, outward_subq.c.serial_number_id == SerialNumber.id)
        .order_by(SerialNumber.created_at.desc())
    )
    tracked_rows = (await db.execute(tracked_query)).all()

    items: list[SerialListItem] = []
    seen_serials = set()

    for r in tracked_rows:
        seen_serials.add(r.sn_text.lower())
        is_dispatched = (r.sn_status == SerialStatus.dispatched)
        flow_type = "outward" if is_dispatched else "inward"

        if is_dispatched:
            s_label = "Dispatched"
            t_date = r.outward_date or (r.sn_created_at.date() if r.sn_created_at else None)
            ts = r.outward_created_at or r.sn_created_at
            ref = r.outward_ref
            s_name = r.outward_shop_name or r.shop_name
            s_city = r.outward_shop_city or r.shop_city
        else:
            s_label = r.sn_status.value.replace("_", " ").title()
            t_date = r.inward_date or (r.sn_created_at.date() if r.sn_created_at else None)
            ts = r.sn_created_at
            ref = r.inward_ref
            s_name = r.shop_name if r.sn_status != SerialStatus.available else None
            s_city = r.shop_city if r.sn_status != SerialStatus.available else None

        items.append(
            SerialListItem(
                serial_number=r.sn_text,
                serial_number_id=r.sn_id,
                brand=r.prod_brand,
                model=r.prod_model,
                product_name=r.prod_name,
                category_name=r.cat_name,
                status=r.sn_status.value,
                status_label=s_label,
                flow_type=flow_type,
                transaction_date=t_date,
                created_at=ts,
                shop_name=s_name,
                shop_city=s_city,
                reference=ref,
                is_matched=True,
            )
        )

    # 3. Unmatched outward lines (pre-go-live dispatches not in serial_numbers)
    unm_query = (
        select(
            OutwardLine.serial_text.label("serial_text"),
            OutwardLine.created_at.label("created_at"),
            OutwardLine.transaction_date.label("outward_date"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            OutwardBatch.delivery_reference.label("outward_ref"),
        )
        .join(Product, OutwardLine.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .where(OutwardLine.serial_number_id.is_(None))
        .order_by(OutwardLine.created_at.desc())
    )
    unm_rows = (await db.execute(unm_query)).all()

    for r in unm_rows:
        if r.serial_text.lower() in seen_serials:
            continue
        items.append(
            SerialListItem(
                serial_number=r.serial_text,
                serial_number_id=None,
                brand=r.prod_brand,
                model=r.prod_model,
                product_name=r.prod_name,
                category_name=r.cat_name,
                status="dispatched",
                status_label="Recorded only",
                flow_type="outward",
                transaction_date=r.outward_date,
                created_at=r.created_at,
                shop_name=r.shop_name,
                shop_city=r.shop_city,
                reference=r.outward_ref,
                is_matched=False,
            )
        )

    # 4. Filter by flow type
    if flow == "inward":
        items = [i for i in items if i.flow_type == "inward"]
    elif flow == "outward":
        items = [i for i in items if i.flow_type == "outward"]
    elif flow == "damaged":
        items = [i for i in items if i.status in ("damaged", "under_repair", "lost")]

    # 5. Search query filtering
    if q and q.strip():
        term = q.strip().lower()
        items = [
            i
            for i in items
            if term in i.serial_number.lower()
            or term in i.model.lower()
            or term in i.brand.lower()
            or (i.category_name and term in i.category_name.lower())
            or term in i.product_name.lower()
            or (i.shop_name and term in i.shop_name.lower())
            or (i.shop_city and term in i.shop_city.lower())
            or (i.reference and term in i.reference.lower())
        ]

    # Sort newest first
    items.sort(key=lambda x: x.created_at, reverse=True)
    total_count = len(items)
    sliced = items[offset : offset + limit]

    return SerialListResponse(total=total_count, items=sliced)


@router.get("/lookup", response_model=SerialDetailResponse)
async def lookup_serial(
    serial_number: Annotated[str, Query(min_length=1)],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SerialDetailResponse:
    """
    Universal serial search for the dashboard and staff lookup:
    Searches both tracked and unmatched records. Returns the current status,
    model, destination shop, and complete vertical chronological history.
    """
    clean_serial = serial_number.strip()

    # 1. Search tracked serial_numbers
    query = (
        select(
            SerialNumber,
            Product.id.label("prod_id"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.id.label("shop_id"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .where(func.lower(SerialNumber.serial_number) == clean_serial.lower())
    )
    result = await db.execute(query)
    row = result.first()

    history_items: list[SerialHistoryItem] = []

    if row:
        sn, p_id, p_name, p_brand, p_model, cat_name, s_id, s_name, s_city = row

        # Fetch full history
        hist_query = (
            select(
                SerialHistory,
                Shop.name.label("shop_name"),
                Shop.city.label("shop_city"),
                User.full_name.label("user_name"),
            )
            .outerjoin(Shop, SerialHistory.shop_id == Shop.id)
            .join(User, SerialHistory.user_id == User.id)
            .where(
                or_(
                    SerialHistory.serial_number_id == sn.id,
                    func.lower(SerialHistory.serial_text) == clean_serial.lower(),
                )
            )
            .order_by(SerialHistory.created_at.desc())
        )
        hist_res = await db.execute(hist_query)
        for h, shop_n, shop_c, u_name in hist_res.all():
            history_items.append(
                SerialHistoryItem(
                    id=h.id,
                    created_at=h.created_at,
                    action=h.action,
                    from_status=h.from_status,
                    to_status=h.to_status,
                    shop_id=h.shop_id,
                    shop_name=shop_n,
                    shop_city=shop_c,
                    is_matched=h.is_matched,
                    user_name=u_name,
                    remarks=h.remarks,
                )
            )

        status_label = sn.status.value.replace("_", " ").title()

        return SerialDetailResponse(
            serial_number=sn.serial_number,
            serial_number_id=sn.id,
            is_tracked=True,
            status=sn.status.value,
            product_id=p_id,
            product_name=p_name,
            brand=p_brand,
            model=p_model,
            category_name=cat_name,
            last_shop_id=s_id,
            last_shop_name=s_name,
            last_shop_city=s_city,
            status_label=status_label,
            history=history_items,
        )

    # 2. If not tracked, check if dispatched as unmatched old stock
    unm_query = (
        select(
            OutwardLine,
            Product.id.label("prod_id"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.id.label("shop_id"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(Product, OutwardLine.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(func.lower(OutwardLine.serial_text) == clean_serial.lower())
    )
    unm_res = await db.execute(unm_query)
    unm_row = unm_res.first()

    if unm_row:
        line, p_id, p_name, p_brand, p_model, cat_name, s_id, s_name, s_city = unm_row

        hist_query = (
            select(
                SerialHistory,
                Shop.name.label("shop_name"),
                Shop.city.label("shop_city"),
                User.full_name.label("user_name"),
            )
            .outerjoin(Shop, SerialHistory.shop_id == Shop.id)
            .join(User, SerialHistory.user_id == User.id)
            .where(func.lower(SerialHistory.serial_text) == clean_serial.lower())
            .order_by(SerialHistory.created_at.desc())
        )
        hist_res = await db.execute(hist_query)
        for h, shop_n, shop_c, u_name in hist_res.all():
            history_items.append(
                SerialHistoryItem(
                    id=h.id,
                    created_at=h.created_at,
                    action=h.action,
                    from_status=h.from_status,
                    to_status=h.to_status,
                    shop_id=h.shop_id,
                    shop_name=shop_n,
                    shop_city=shop_c,
                    is_matched=h.is_matched,
                    user_name=u_name,
                    remarks=h.remarks,
                )
            )

        return SerialDetailResponse(
            serial_number=line.serial_text,
            serial_number_id=None,
            is_tracked=False,
            status="dispatched",
            product_id=p_id,
            product_name=p_name,
            brand=p_brand,
            model=p_model,
            category_name=cat_name,
            last_shop_id=s_id,
            last_shop_name=s_name,
            last_shop_city=s_city,
            status_label="Recorded only",
            history=history_items,
        )

    raise HTTPException(status_code=404, detail=f"Serial number '{clean_serial}' not found in system.")


@router.patch("/{serial_id}/status", response_model=SerialDetailResponse)
async def update_serial_status(
    serial_id: uuid.UUID,
    req: SerialStatusChangeRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SerialDetailResponse:
    """
    Change status of a tracked serial (e.g. mark as Damaged, Lost, Under Repair, or restore to Available).
    Adjusts product current_stock_qty atomically when moving to/from Available.
    """
    sn_res = await db.execute(
        select(SerialNumber).where(SerialNumber.id == serial_id).with_for_update()
    )
    sn = sn_res.scalar_one_or_none()
    if not sn:
        raise HTTPException(status_code=404, detail="Serial number not found.")

    old_status = sn.status
    if old_status == req.new_status:
        raise HTTPException(status_code=400, detail=f"Serial is already in status '{req.new_status.value}'.")

    # Update status
    sn.status = req.new_status

    # Stock adjustment
    prod_res = await db.execute(
        select(Product).where(Product.id == sn.product_id).with_for_update()
    )
    product = prod_res.scalar_one()

    if old_status == SerialStatus.available and req.new_status != SerialStatus.available:
        # Stock leaves available pool
        product.current_stock_qty = max(0, product.current_stock_qty - 1)
    elif old_status != SerialStatus.available and req.new_status == SerialStatus.available:
        # Stock returns to available pool
        product.current_stock_qty += 1

    # Record SerialHistory
    history = SerialHistory(
        serial_number_id=sn.id,
        serial_text=sn.serial_number,
        action=HistoryAction.status_changed,
        from_status=old_status,
        to_status=req.new_status,
        shop_id=sn.last_shop_id,
        user_id=current_user.id,
        remarks=f"Status changed to {req.new_status.value}. Reason: {req.reason}. {req.remarks or ''}".strip(),
    )
    db.add(history)

    # Audit Log
    audit = AuditLog(
        user_id=current_user.id,
        action="SERIAL_STATUS_CHANGED",
        entity_type="serial_number",
        entity_id=str(sn.id),
        details={
            "serial": sn.serial_number,
            "old_status": old_status.value,
            "new_status": req.new_status.value,
            "reason": req.reason,
        },
    )
    db.add(audit)

    await db.commit()

    # Re-fetch for response
    return await lookup_serial(serial_number=sn.serial_number, current_user=current_user, db=db)