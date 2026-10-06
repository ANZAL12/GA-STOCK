from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.database import get_db
from app.models.audit import AuditLog
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.outward import OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.serial_status import (
    SerialDetailResponse,
    SerialHistoryItem,
    SerialStatusChangeRequest,
)

router = APIRouter(prefix="/serials", tags=["serials"])


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
            Shop.id.label("shop_id"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .where(func.lower(SerialNumber.serial_number) == clean_serial.lower())
    )
    result = await db.execute(query)
    row = result.first()

    history_items: list[SerialHistoryItem] = []

    if row:
        sn, p_id, p_name, p_brand, p_model, s_id, s_name, s_city = row

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
            Shop.id.label("shop_id"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(Product, OutwardLine.product_id == Product.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(func.lower(OutwardLine.serial_text) == clean_serial.lower())
    )
    unm_res = await db.execute(unm_query)
    unm_row = unm_res.first()

    if unm_row:
        line, p_id, p_name, p_brand, p_model, s_id, s_name, s_city = unm_row

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