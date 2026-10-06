from datetime import datetime, timezone
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_device_optional, get_current_user
from app.database import get_db
from app.models.audit import AuditLog
from app.models.enums import HistoryAction, InspectionResult, SerialStatus
from app.models.history import SerialHistory
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.return_ import Return
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.return_ import (
    ReturnCreateRequest,
    ReturnInspectRequest,
    ReturnLookupSerialResponse,
    ReturnResponse,
)

router = APIRouter(prefix="/returns", tags=["returns"])


@router.get("/lookup-serial", response_model=ReturnLookupSerialResponse)
async def lookup_serial_for_return(
    serial_number: Annotated[str, Query(min_length=1)],
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ReturnLookupSerialResponse:
    """
    Scans a serial to look up its dispatch details for return:
    - If tracked: gets registered product, last shop, and dispatch date.
    - If unmatched old stock: looks up the outward dispatch line to find where it was sent.
    """
    clean_serial = serial_number.strip()

    # 1. Check serial_numbers table (tracked serials)
    sn_query = (
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
        .where(SerialNumber.serial_number == clean_serial)
    )
    sn_res = await db.execute(sn_query)
    sn_row = sn_res.first()

    if sn_row:
        sn, p_id, p_name, p_brand, p_model, s_id, s_name, s_city = sn_row

        # Find most recent outward dispatch
        out_query = (
            select(OutwardLine.id, OutwardLine.transaction_date, OutwardBatch.delivery_reference)
            .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
            .where(OutwardLine.serial_number_id == sn.id)
            .order_by(OutwardLine.transaction_date.desc(), OutwardLine.created_at.desc())
        )
        out_res = await db.execute(out_query)
        out_row = out_res.first()

        return ReturnLookupSerialResponse(
            serial_number=clean_serial,
            found=True,
            was_matched=True,
            product_id=p_id,
            product_name=p_name,
            brand=p_brand,
            model=p_model,
            shop_id=s_id,
            shop_name=s_name,
            shop_city=s_city,
            outward_line_id=out_row[0] if out_row else None,
            current_status=sn.status.value,
            dispatch_date=out_row[1] if out_row else None,
            delivery_reference=out_row[2] if out_row else None,
        )

    # 2. Check outward_lines (unmatched old stock dispatches)
    unmatched_query = (
        select(
            OutwardLine.id,
            OutwardLine.product_id,
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Shop.id.label("shop_id"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            OutwardLine.transaction_date,
            OutwardBatch.delivery_reference,
        )
        .join(Product, OutwardLine.product_id == Product.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .where(OutwardLine.serial_text == clean_serial)
        .order_by(OutwardLine.transaction_date.desc(), OutwardLine.created_at.desc())
    )
    unmatched_res = await db.execute(unmatched_query)
    unmatched_row = unmatched_res.first()

    if unmatched_row:
        (
            line_id, p_id, p_name, p_brand, p_model,
            s_id, s_name, s_city, trans_date, del_ref
        ) = unmatched_row

        return ReturnLookupSerialResponse(
            serial_number=clean_serial,
            found=True,
            was_matched=False,
            product_id=p_id,
            product_name=p_name,
            brand=p_brand,
            model=p_model,
            shop_id=s_id,
            shop_name=s_name,
            shop_city=s_city,
            outward_line_id=line_id,
            current_status="dispatched",
            dispatch_date=trans_date,
            delivery_reference=del_ref,
        )

    # 3. Not found anywhere
    return ReturnLookupSerialResponse(
        serial_number=clean_serial,
        found=False,
        was_matched=False,
    )


@router.post("", response_model=ReturnResponse, status_code=status.HTTP_201_CREATED)
async def record_return(
    req: ReturnCreateRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> ReturnResponse:
    """
    Record return of an appliance from a shop.
    - If serial was tracked: updates status to Returned.
    - If serial was unmatched (pre-go-live): creates a new SerialNumber record,
      making the serial tracked from that moment on!
    - Links to outward line and destination shop.
    - Writes immutable SerialHistory and AuditLog.
    """
    clean_serial = req.serial_number.strip()
    if not clean_serial:
        raise HTTPException(status_code=400, detail="Serial number is required.")

    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    device_id = device.id if device else None

    # Verify Shop
    shop_res = await db.execute(select(Shop).where(Shop.id == req.shop_id))
    shop = shop_res.scalar_one_or_none()
    if not shop:
        raise HTTPException(status_code=404, detail="Shop not found.")

    # Verify Product
    prod_res = await db.execute(select(Product).where(Product.id == req.product_id))
    product = prod_res.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found.")

    # Check if serial exists in serial_numbers
    sn_res = await db.execute(
        select(SerialNumber).where(SerialNumber.serial_number == clean_serial).with_for_update()
    )
    sn = sn_res.scalar_one_or_none()

    old_status = None
    if sn:
        old_status = sn.status
        sn.status = SerialStatus.returned
        sn.last_shop_id = shop.id
        sn_id = sn.id
    else:
        # Pre-go-live unmatched serial returned: create a new tracked SerialNumber record!
        sn = SerialNumber(
            serial_number=clean_serial,
            product_id=product.id,
            status=SerialStatus.returned,
            last_shop_id=shop.id,
        )
        db.add(sn)
        await db.flush()
        sn_id = sn.id

        # If there is an outward line with this serial, link it
        if req.outward_line_id:
            out_res = await db.execute(select(OutwardLine).where(OutwardLine.id == req.outward_line_id))
            out_line = out_res.scalar_one_or_none()
            if out_line and not out_line.serial_number_id:
                out_line.serial_number_id = sn.id

    # Create Return record
    return_record = Return(
        serial_text=clean_serial,
        serial_number_id=sn_id,
        outward_line_id=req.outward_line_id,
        shop_id=shop.id,
        product_id=product.id,
        return_date=req.return_date,
        reason=req.reason.strip(),
        condition=req.condition.strip() if req.condition else None,
        received_by_user_id=current_user.id,
        device_id=device_id,
        remarks=req.remarks.strip() if req.remarks else None,
    )
    db.add(return_record)
    await db.flush()

    # Create SerialHistory
    history = SerialHistory(
        serial_number_id=sn_id,
        serial_text=clean_serial,
        action=HistoryAction.returned,
        from_status=old_status,
        to_status=SerialStatus.returned,
        shop_id=shop.id,
        return_id=return_record.id,
        user_id=current_user.id,
        device_id=device_id,
        remarks=f"Returned from {shop.name}. Reason: {req.reason}",
    )
    db.add(history)

    # Audit Log
    audit = AuditLog(
        user_id=current_user.id,
        device_id=device_id,
        action="RETURN_RECORDED",
        entity_type="return",
        entity_id=str(return_record.id),
        details={
            "serial": clean_serial,
            "product_id": str(product.id),
            "shop_id": str(shop.id),
            "shop_name": shop.name,
            "reason": req.reason,
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(return_record)

    return ReturnResponse(
        id=return_record.id,
        serial_text=return_record.serial_text,
        serial_number_id=return_record.serial_number_id,
        outward_line_id=return_record.outward_line_id,
        shop_id=shop.id,
        shop_name=shop.name,
        shop_city=shop.city,
        product_id=product.id,
        product_name=product.name,
        brand=product.brand,
        model=product.model,
        return_date=return_record.return_date,
        reason=return_record.reason,
        condition=return_record.condition,
        inspection_result=return_record.inspection_result,
        inspected_at=return_record.inspected_at,
        inspected_by_name=None,
        received_by_name=current_user.full_name,
        remarks=return_record.remarks,
        created_at=return_record.created_at,
    )


@router.post("/{return_id}/inspect", response_model=ReturnResponse)
async def inspect_return(
    return_id: uuid.UUID,
    req: ReturnInspectRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ReturnResponse:
    """
    Inspect a returned unit:
    - If Available: updates serial status to Available, adds +1 back to product current_stock_qty.
    - If Damaged: updates serial status to Damaged.
    """
    ret_res = await db.execute(
        select(Return, Shop, Product)
        .join(Shop, Return.shop_id == Shop.id)
        .join(Product, Return.product_id == Product.id)
        .where(Return.id == return_id)
    )
    row = ret_res.first()
    if not row:
        raise HTTPException(status_code=404, detail="Return record not found.")

    ret_record, shop, product = row

    if ret_record.inspection_result is not None:
        raise HTTPException(status_code=400, detail="This return has already been inspected.")

    # Update Return record
    ret_record.inspection_result = req.inspection_result
    ret_record.inspected_at = datetime.now(timezone.utc)
    ret_record.inspected_by_user_id = current_user.id
    if req.remarks:
        ret_record.remarks = f"{ret_record.remarks or ''}\nInspection: {req.remarks.strip()}".strip()

    # Update Serial status
    if ret_record.serial_number_id:
        sn_res = await db.execute(
            select(SerialNumber).where(SerialNumber.id == ret_record.serial_number_id).with_for_update()
        )
        sn = sn_res.scalar_one_or_none()
        if sn:
            new_status = SerialStatus.available if req.inspection_result == InspectionResult.available else SerialStatus.damaged
            sn.status = new_status

            # If returning to stock, lock and increment product stock
            if req.inspection_result == InspectionResult.available:
                prod_lock = await db.execute(
                    select(Product).where(Product.id == product.id).with_for_update()
                )
                prod_to_update = prod_lock.scalar_one()
                prod_to_update.current_stock_qty += 1

            # SerialHistory
            history = SerialHistory(
                serial_number_id=sn.id,
                serial_text=sn.serial_number,
                action=HistoryAction.inspected,
                from_status=SerialStatus.returned,
                to_status=new_status,
                shop_id=shop.id,
                return_id=ret_record.id,
                user_id=current_user.id,
                remarks=f"Inspection result: {req.inspection_result.value}. {req.remarks or ''}".strip(),
            )
            db.add(history)

    # Audit Log
    audit = AuditLog(
        user_id=current_user.id,
        action="RETURN_INSPECTED",
        entity_type="return",
        entity_id=str(ret_record.id),
        details={
            "serial": ret_record.serial_text,
            "inspection_result": req.inspection_result.value,
            "remarks": req.remarks,
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(ret_record)

    return ReturnResponse(
        id=ret_record.id,
        serial_text=ret_record.serial_text,
        serial_number_id=ret_record.serial_number_id,
        outward_line_id=ret_record.outward_line_id,
        shop_id=shop.id,
        shop_name=shop.name,
        shop_city=shop.city,
        product_id=product.id,
        product_name=product.name,
        brand=product.brand,
        model=product.model,
        return_date=ret_record.return_date,
        reason=ret_record.reason,
        condition=ret_record.condition,
        inspection_result=ret_record.inspection_result,
        inspected_at=ret_record.inspected_at,
        inspected_by_name=current_user.full_name,
        received_by_name="System",
        remarks=ret_record.remarks,
        created_at=ret_record.created_at,
    )


@router.get("", response_model=list[ReturnResponse])
async def list_returns(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    shop_id: Optional[uuid.UUID] = Query(None, description="Filter by shop"),
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    inspection_pending: Optional[bool] = Query(None, description="Filter pending inspection"),
) -> list[ReturnResponse]:
    """
    List return records.
    """
    query = (
        select(
            Return,
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            User.full_name.label("receiver_name"),
        )
        .join(Shop, Return.shop_id == Shop.id)
        .join(Product, Return.product_id == Product.id)
        .join(User, Return.received_by_user_id == User.id)
        .order_by(Return.return_date.desc(), Return.created_at.desc())
    )

    if shop_id:
        query = query.where(Return.shop_id == shop_id)
    if product_id:
        query = query.where(Return.product_id == product_id)
    if inspection_pending is True:
        query = query.where(Return.inspection_result == None)
    elif inspection_pending is False:
        query = query.where(Return.inspection_result != None)

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for ret, s_name, s_city, p_name, p_brand, p_model, u_name in rows:
        responses.append(
            ReturnResponse(
                id=ret.id,
                serial_text=ret.serial_text,
                serial_number_id=ret.serial_number_id,
                outward_line_id=ret.outward_line_id,
                shop_id=ret.shop_id,
                shop_name=s_name,
                shop_city=s_city,
                product_id=ret.product_id,
                product_name=p_name,
                brand=p_brand,
                model=p_model,
                return_date=ret.return_date,
                reason=ret.reason,
                condition=ret.condition,
                inspection_result=ret.inspection_result,
                inspected_at=ret.inspected_at,
                inspected_by_name=None,
                received_by_name=u_name,
                remarks=ret.remarks,
                created_at=ret.created_at,
            )
        )
    return responses