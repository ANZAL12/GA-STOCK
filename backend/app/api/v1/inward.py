from datetime import date
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_device_optional, get_current_user
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.enums import HistoryAction, SerialStatus
from app.models.category import Category
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.inward import (
    InwardBatchCreate,
    InwardBatchResponse,
    InwardValidateSerialRequest,
    InwardValidateSerialResponse,
)

router = APIRouter(prefix="/inward", tags=["inward"])


@router.post("/validate-serial", response_model=InwardValidateSerialResponse)
async def validate_serial(
    req: InwardValidateSerialRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    product_id: Optional[uuid.UUID] = None,
) -> InwardValidateSerialResponse:
    """
    Real-time check for barcode scanner on mobile:
    Verifies if a serial number is valid for the chosen inward type:
    - stock_in: New direct from company (must not exist)
    - return: Returned product (can be previously dispatched, restores to available)
    - damaged: Damaged product (marked as damaged, does not increase saleable stock)
    """
    clean_serial = req.serial_number.strip()
    inward_type = (req.inward_type or "stock_in").lower()

    if not clean_serial:
        return InwardValidateSerialResponse(
            serial_number="",
            is_valid=False,
            already_exists=False,
            message="Serial number cannot be blank.",
        )

    # Check database for existing serial
    query = (
        select(SerialNumber, Product.name.label("product_name"), Product.model.label("product_model"))
        .join(Product, SerialNumber.product_id == Product.id)
        .where(SerialNumber.serial_number == clean_serial)
    )
    result = await db.execute(query)
    row = result.first()

    # Also check if previously recorded in OutwardLine
    out_res = await db.execute(
        select(OutwardLine, Shop.name.label("shop_name"))
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(OutwardLine.serial_text == clean_serial)
    )
    out_row = out_res.first()

    if inward_type == "return":
        # Case 2: Returned product
        if row:
            sn, prod_name, prod_model = row
            model_display = f"{prod_name} ({prod_model})"
            if product_id and sn.product_id != product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Serial '{clean_serial}' belongs to {model_display}, not the selected model.",
                )
            if sn.status == SerialStatus.dispatched:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=True,
                    already_exists=True,
                    requires_confirmation=False,
                    warning_not_dispatched=False,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Returned unit verified ({model_display}). Will restore to Available stock.",
                )
            else:
                # Tracked in system, but previously not in dispatched status (e.g. 'available' or 'damaged')
                st_label = "Available in godown stock" if sn.status == SerialStatus.available else sn.status.value
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=True,
                    already_exists=True,
                    requires_confirmation=True,
                    warning_not_dispatched=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Serial '{clean_serial}' was previously not marked as dispatched (currently {st_label}). Confirm to process as return anyway?",
                )
        elif out_row:
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=True,
                requires_confirmation=False,
                warning_not_dispatched=False,
                message=f"Returned unit (previously dispatched to {out_row[1]}). Will restore to Available stock.",
            )
        else:
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=False,
                requires_confirmation=True,
                warning_not_dispatched=True,
                message=f"Serial '{clean_serial}' has no previous dispatch record in the system. Confirm to accept as return anyway?",
            )

    elif inward_type == "damaged":
        # Case 3: Damaged product
        if row:
            sn, prod_name, prod_model = row
            model_display = f"{prod_name} ({prod_model})"
            if product_id and sn.product_id != product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Serial '{clean_serial}' belongs to {model_display}, not the selected model.",
                )
            if sn.status == SerialStatus.damaged:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Serial '{clean_serial}' is already registered as Damaged.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=sn.product_id,
                message=f"Unit will be inwarded as Damaged (does not increase saleable stock).",
            )
        return InwardValidateSerialResponse(
            serial_number=clean_serial,
            is_valid=True,
            already_exists=False,
            message="New unit will be recorded as Damaged (does not increase saleable stock).",
        )

    else:
        # Case 1: Standard Stock In (Direct from Company)
        if row:
            sn, prod_name, prod_model = row
            model_display = f"{prod_name} ({prod_model})"
            if sn.status == SerialStatus.dispatched:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    message=f"Serial '{clean_serial}' was previously dispatched. If receiving back, select 'Returned Product' mode.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=False,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=sn.product_id,
                message=f"Serial '{clean_serial}' is already registered under {model_display}.",
            )

        if out_row:
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=False,
                already_exists=True,
                message=f"Serial '{clean_serial}' was previously dispatched to shop '{out_row[1]}'. If receiving back, select 'Returned Product' mode.",
            )

        return InwardValidateSerialResponse(
            serial_number=clean_serial,
            is_valid=True,
            already_exists=False,
            message="Serial is available for company stock in.",
        )


@router.get("/validate-serial", response_model=InwardValidateSerialResponse)
async def validate_serial_get(
    serial_number: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    product_id: Optional[uuid.UUID] = None,
    inward_type: Optional[str] = "stock_in",
) -> InwardValidateSerialResponse:
    req = InwardValidateSerialRequest(serial_number=serial_number, inward_type=inward_type)
    return await validate_serial(req=req, current_user=current_user, db=db, product_id=product_id)


@router.post("/batch", response_model=InwardBatchResponse, status_code=status.HTTP_201_CREATED)
@router.post("/batches", response_model=InwardBatchResponse, status_code=status.HTTP_201_CREATED)
async def create_inward_batch(
    req: InwardBatchCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> InwardBatchResponse:
    """
    Record an inward stock batch inside a single atomic transaction.
    Record an inward stock batch inside a single atomic transaction.
    Supports three inward types:
    1) 'stock_in': Direct from company (new serials, +stock, status: Available)
    2) 'return': Returned product (frees previously dispatched serials, +stock, status: Available)
    3) 'damaged': Damaged product (status: Damaged, stock unaffected)
    """
    inward_type = (req.inward_type or "stock_in").lower()
    if inward_type not in ("stock_in", "return", "damaged"):
        inward_type = "stock_in"

    # 1. Clean serial numbers
    raw_serials = [s.strip() for s in req.serials if s.strip()]
    if not raw_serials:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one serial number is required.",
        )

    # 2. Check for duplicate serials within the batch itself
    seen = set()
    for s in raw_serials:
        if s in seen:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Duplicate serial number in this batch: '{s}'. Each serial must be unique.",
            )
        seen.add(s)

    # 3. Check device if header is present
    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    device_id = device.id if device else None

    # 4. Lock product row for atomic stock update
    prod_res = await db.execute(
        select(Product).where(Product.id == req.product_id).with_for_update()
    )
    product = prod_res.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found.")
    if not product.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Product is deactivated.")

    # 4b. If category has dual serials, ensure equal numbers of indoor and outdoor units
    cat_res = await db.execute(select(Category).where(Category.id == product.category_id))
    cat = cat_res.scalar_one_or_none()
    if cat and cat.has_dual_serial:
        indoor_count = sum(1 for s in raw_serials if (req.unit_types or {}).get(s) == "indoor")
        outdoor_count = sum(1 for s in raw_serials if (req.unit_types or {}).get(s) == "outdoor")
        if indoor_count != outdoor_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Indoor and Outdoor unit counts must match for dual-serial model '{product.name}'. "
                    f"Scanned: {indoor_count} Indoor unit(s), {outdoor_count} Outdoor unit(s). "
                    "Equal numbers of indoor and outdoor units are required to store."
                ),
            )

    # 5. Fetch existing serial records
    existing_res = await db.execute(
        select(SerialNumber, Product.name.label("product_name"), Product.model.label("product_model"))
        .join(Product, SerialNumber.product_id == Product.id)
        .where(SerialNumber.serial_number.in_(raw_serials))
    )
    existing_rows = {row[0].serial_number: row for row in existing_res.all()}

    # Check OutwardLine for previous dispatches
    existing_outward_res = await db.execute(
        select(OutwardLine.serial_text, Shop.name.label("shop_name"))
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(OutwardLine.serial_text.in_(raw_serials))
    )
    already_disp_lines = {row[0]: row[1] for row in existing_outward_res.all()}

    # Type-specific validation:
    if inward_type == "stock_in":
        # Cannot already exist or have been dispatched
        for s in raw_serials:
            if s in existing_rows:
                sn, pname, pmodel = existing_rows[s]
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Serial '{s}' is already registered under '{pname} ({pmodel})'. For returns, select 'Returned Product'.",
                )
            if s in already_disp_lines:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Serial '{s}' was previously dispatched to '{already_disp_lines[s]}'. For returns, select 'Returned Product'.",
                )

    elif inward_type == "return":
        # Can be previously dispatched or untracked. Must NOT belong to a different model if already in SerialNumber.
        for s in raw_serials:
            if s in existing_rows:
                sn, pname, pmodel = existing_rows[s]
                if sn.product_id != product.id:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Cannot return serial '{s}' under this model: it belongs to '{pname} ({pmodel})'.",
                    )

    elif inward_type == "damaged":
        # Cannot belong to a different model if already in SerialNumber
        for s in raw_serials:
            if s in existing_rows:
                sn, pname, pmodel = existing_rows[s]
                if sn.product_id != product.id:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Cannot record damaged serial '{s}' under this model: it belongs to '{pname} ({pmodel})'.",
                    )
                if sn.status == SerialStatus.damaged:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Serial '{s}' is already registered as Damaged.",
                    )

    # 6. Create InwardBatch
    batch = InwardBatch(
        product_id=product.id,
        inward_type=inward_type,
        invoice_reference=req.invoice_reference.strip() if req.invoice_reference else None,
        transaction_date=req.transaction_date,
        received_by_user_id=current_user.id,
        device_id=device_id,
        quantity=len(raw_serials),
        remarks=req.remarks.strip() if req.remarks else None,
    )
    db.add(batch)
    await db.flush()

    # 7. Create/Update SerialNumber, InwardLine, and SerialHistory
    created_serials: list[str] = []
    for sn_text in raw_serials:
        u_type = None
        if req.unit_types and sn_text in req.unit_types:
            u_type = req.unit_types[sn_text]

        target_status = SerialStatus.damaged if inward_type == "damaged" else SerialStatus.available
        hist_action = (
            HistoryAction.status_changed if inward_type == "damaged"
            else HistoryAction.returned if inward_type == "return"
            else HistoryAction.inward_recorded
        )

        if sn_text in existing_rows:
            # Update existing serial record
            sn_record, _, _ = existing_rows[sn_text]
            from_st = sn_record.status
            sn_record.status = target_status
            if inward_type == "return":
                sn_record.last_shop_id = None
            if u_type:
                sn_record.unit_type = u_type
        else:
            # Create new serial record
            from_st = None
            sn_record = SerialNumber(
                serial_number=sn_text,
                product_id=product.id,
                status=target_status,
                last_shop_id=None,
                unit_type=u_type,
            )
            db.add(sn_record)
            await db.flush()

        line = InwardLine(
            batch_id=batch.id,
            serial_number_id=sn_record.id,
        )
        db.add(line)

        history = SerialHistory(
            serial_number_id=sn_record.id,
            serial_text=sn_text,
            action=hist_action,
            from_status=from_st,
            to_status=target_status,
            inward_batch_id=batch.id,
            user_id=current_user.id,
            device_id=device_id,
            remarks=f"Inward [{inward_type}]: {req.remarks or ''}".strip(),
        )
        db.add(history)
        created_serials.append(sn_text)

    # 8. Update product running stock
    inward_units_count = (len(raw_serials) // 2) if (cat and cat.has_dual_serial) else len(raw_serials)
    if inward_type in ("stock_in", "return"):
        # Stock-in and returns restore available stock
        product.current_stock_qty += inward_units_count
    elif inward_type == "damaged":
        # Damaged products do NOT add to saleable stock
        pass

    product.has_had_inward = True

    # 9. Audit log
    audit = AuditLog(
        user_id=current_user.id,
        device_id=device_id,
        action="INWARD_SUBMITTED",
        entity_type="inward_batch",
        entity_id=str(batch.id),
        details={
            "product_id": str(product.id),
            "product_name": product.name,
            "inward_type": inward_type,
            "quantity": len(raw_serials),
            "invoice_reference": batch.invoice_reference,
            "serials_sample": raw_serials[:5],
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(batch)

    resp = InwardBatchResponse(
        id=batch.id,
        product_id=product.id,
        product_name=product.name,
        brand=product.brand,
        model=product.model,
        inward_type=inward_type,
        invoice_reference=batch.invoice_reference,
        transaction_date=batch.transaction_date,
        quantity=batch.quantity,
        received_by_user_id=current_user.id,
        received_by_name=current_user.full_name,
        device_id=device_id,
        remarks=batch.remarks,
        created_at=batch.created_at,
        serials=created_serials,
    )

    await ws_manager.broadcast("stock_updated", {
        "type": "inward",
        "inward_type": inward_type,
        "product_id": str(product.id),
        "current_stock_qty": product.current_stock_qty,
        "quantity": len(raw_serials),
        "invoice_reference": batch.invoice_reference,
    })

    return resp


@router.get("/batches", response_model=list[InwardBatchResponse])
async def list_inward_batches(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    date_from: Optional[date] = Query(None, description="Filter from transaction date"),
    date_to: Optional[date] = Query(None, description="Filter to transaction date"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[InwardBatchResponse]:
    """
    List inward batches with product and receiver details.
    """
    query = (
        select(
            InwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            User.full_name.label("receiver_name"),
        )
        .join(Product, InwardBatch.product_id == Product.id)
        .join(User, InwardBatch.received_by_user_id == User.id)
        .order_by(InwardBatch.transaction_date.desc(), InwardBatch.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    if product_id:
        query = query.where(InwardBatch.product_id == product_id)
    if date_from:
        query = query.where(InwardBatch.transaction_date >= date_from)
    if date_to:
        query = query.where(InwardBatch.transaction_date <= date_to)

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for b, p_name, p_brand, p_model, u_name in rows:
        responses.append(
            InwardBatchResponse(
                id=b.id,
                product_id=b.product_id,
                product_name=p_name,
                brand=p_brand,
                model=p_model,
                inward_type=b.inward_type,
                invoice_reference=b.invoice_reference,
                transaction_date=b.transaction_date,
                quantity=b.quantity,
                received_by_user_id=b.received_by_user_id,
                received_by_name=u_name,
                device_id=b.device_id,
                remarks=b.remarks,
                created_at=b.created_at,
                serials=[],
            )
        )
    return responses


@router.get("/batches/{batch_id}", response_model=InwardBatchResponse)
async def get_inward_batch(
    batch_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> InwardBatchResponse:
    """
    Get a single inward batch with the full list of serial numbers included in it.
    """
    query = (
        select(
            InwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            User.full_name.label("receiver_name"),
        )
        .join(Product, InwardBatch.product_id == Product.id)
        .join(User, InwardBatch.received_by_user_id == User.id)
        .where(InwardBatch.id == batch_id)
    )
    result = await db.execute(query)
    row = result.first()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Inward batch not found.")

    b, p_name, p_brand, p_model, u_name = row

    # Fetch serials
    serials_res = await db.execute(
        select(SerialNumber.serial_number)
        .join(InwardLine, SerialNumber.id == InwardLine.serial_number_id)
        .where(InwardLine.batch_id == batch_id)
        .order_by(SerialNumber.serial_number.asc())
    )
    serials_list = [r[0] for r in serials_res.all()]

    return InwardBatchResponse(
        id=b.id,
        product_id=b.product_id,
        product_name=p_name,
        brand=p_brand,
        model=p_model,
        inward_type=b.inward_type,
        invoice_reference=b.invoice_reference,
        transaction_date=b.transaction_date,
        quantity=b.quantity,
        received_by_user_id=b.received_by_user_id,
        received_by_name=u_name,
        device_id=b.device_id,
        remarks=b.remarks,
        created_at=b.created_at,
        serials=serials_list,
    )