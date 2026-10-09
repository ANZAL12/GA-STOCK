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
    InwardMultiBatchCreate,
    InwardMultiBatchResponse,
    InwardProductBatchItem,
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

    target_product_id = req.product_id or product_id

    # Check database for existing serial
    query = (
        select(
            SerialNumber,
            Product.name.label("product_name"),
            Product.model.label("product_model"),
            Product.brand.label("product_brand"),
            Category.has_dual_serial.label("has_dual_serial"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .join(Category, Product.category_id == Category.id)
        .where(SerialNumber.serial_number == clean_serial)
    )
    result = await db.execute(query)
    row = result.first()

    # Also check if previously recorded in OutwardLine
    out_res = await db.execute(
        select(
            OutwardLine,
            Shop.name.label("shop_name"),
            Product.name.label("product_name"),
            Product.model.label("product_model"),
            Product.brand.label("product_brand"),
            Category.has_dual_serial.label("has_dual_serial"),
        )
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .outerjoin(Product, OutwardLine.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .where(OutwardLine.serial_text == clean_serial)
    )
    out_row = out_res.first()

    if inward_type == "return":
        # Case 2: Returned product
        if row:
            sn, prod_name, prod_model, prod_brand, has_dual = row
            model_display = f"{prod_brand} {prod_name} ({prod_model})"
            if target_product_id and sn.product_id != target_product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
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
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
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
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' was previously not marked as dispatched (currently {st_label}). Confirm to process as return anyway?",
                )
        elif out_row:
            out_line, shop_name, prod_name, prod_model, prod_brand, has_dual = out_row
            model_display = f"{prod_brand} {prod_name} ({prod_model})" if prod_name else "Unknown"
            if target_product_id and out_line.product_id != target_product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=out_line.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=out_line.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' belongs to {model_display}, not the selected model.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=True,
                requires_confirmation=False,
                warning_not_dispatched=False,
                registered_model_name=model_display,
                registered_model_id=out_line.product_id,
                brand=prod_brand,
                model=prod_model,
                unit_type=out_line.unit_type,
                has_dual_serial=has_dual,
                message=f"Returned unit (previously dispatched to {shop_name}). Will restore to Available stock.",
            )
        else:
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=False,
                requires_confirmation=False,
                warning_not_dispatched=True,
                registered_model_name=None,
                registered_model_id=None,
                message=f"Serial '{clean_serial}' has no previous dispatch record in the system.",
            )

    elif inward_type == "damaged":
        # Case 3: Damaged product
        if row:
            sn, prod_name, prod_model, prod_brand, has_dual = row
            model_display = f"{prod_brand} {prod_name} ({prod_model})"
            if target_product_id and sn.product_id != target_product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' belongs to {model_display}, not the selected model.",
                )
            if sn.status == SerialStatus.damaged:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' is already registered as Damaged.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=sn.product_id,
                brand=prod_brand,
                model=prod_model,
                unit_type=sn.unit_type,
                has_dual_serial=has_dual,
                message=f"Unit will be inwarded as Damaged (does not increase saleable stock).",
            )
        elif out_row:
            out_line, shop_name, prod_name, prod_model, prod_brand, has_dual = out_row
            model_display = f"{prod_brand} {prod_name} ({prod_model})" if prod_name else "Unknown"
            if target_product_id and out_line.product_id != target_product_id:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=out_line.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=out_line.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' belongs to {model_display}, not the selected model.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=out_line.product_id,
                brand=prod_brand,
                model=prod_model,
                unit_type=out_line.unit_type,
                has_dual_serial=has_dual,
                message=f"Previously dispatched unit (shop {shop_name}) will be inwarded as Damaged.",
            )
        else:
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=True,
                already_exists=False,
                registered_model_name=None,
                registered_model_id=None,
                message="New unit will be recorded as Damaged (does not increase saleable stock).",
            )

    else:
        # Case 1: Standard Stock In (Direct from Company)
        if row:
            sn, prod_name, prod_model, prod_brand, has_dual = row
            model_display = f"{prod_brand} {prod_name} ({prod_model})"
            if sn.status == SerialStatus.dispatched:
                return InwardValidateSerialResponse(
                    serial_number=clean_serial,
                    is_valid=False,
                    already_exists=True,
                    registered_model_name=model_display,
                    registered_model_id=sn.product_id,
                    brand=prod_brand,
                    model=prod_model,
                    unit_type=sn.unit_type,
                    has_dual_serial=has_dual,
                    message=f"Serial '{clean_serial}' was previously dispatched. If receiving back, select 'Returned Product' mode.",
                )
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=False,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=sn.product_id,
                brand=prod_brand,
                model=prod_model,
                unit_type=sn.unit_type,
                has_dual_serial=has_dual,
                message=f"Serial '{clean_serial}' is already registered under {model_display}.",
            )

        if out_row:
            out_line, shop_name, prod_name, prod_model, prod_brand, has_dual = out_row
            model_display = f"{prod_brand} {prod_name} ({prod_model})" if prod_name else "Unknown"
            return InwardValidateSerialResponse(
                serial_number=clean_serial,
                is_valid=False,
                already_exists=True,
                registered_model_name=model_display,
                registered_model_id=out_line.product_id,
                brand=prod_brand,
                model=prod_model,
                unit_type=out_line.unit_type,
                has_dual_serial=has_dual,
                message=f"Serial '{clean_serial}' was previously dispatched to shop '{shop_name}'. If receiving back, select 'Returned Product' mode.",
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
    req = InwardValidateSerialRequest(serial_number=serial_number, inward_type=inward_type, product_id=product_id)
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

    # 0. Idempotency check: if client_request_id was already committed, return existing batch
    if req.client_request_id:
        existing_log_res = await db.execute(
            select(AuditLog)
            .where(AuditLog.action.in_(["INWARD_SUBMITTED", "INWARD_MULTI_BATCH"]))
            .order_by(AuditLog.created_at.desc())
            .limit(100)
        )
        for log in existing_log_res.scalars().all():
            if log.details and log.details.get("client_request_id") == req.client_request_id:
                batch_id_str = log.details.get("batch_id") or (log.details.get("batch_ids") and log.details["batch_ids"][0])
                if batch_id_str:
                    b_uuid = uuid.UUID(batch_id_str)
                    existing_b = await db.execute(
                        select(
                            InwardBatch,
                            Product.name.label("product_name"),
                            Product.brand.label("product_brand"),
                            Product.model.label("product_model"),
                            User.full_name.label("receiver_name"),
                        )
                        .join(Product, InwardBatch.product_id == Product.id)
                        .join(User, InwardBatch.received_by_user_id == User.id)
                        .where(InwardBatch.id == b_uuid)
                    )
                    cached_b = existing_b.first()
                    if cached_b:
                        b_obj, p_name, p_brand, p_model, u_name = cached_b
                        cached_lines = await db.execute(
                            select(SerialNumber.serial_number)
                            .join(InwardLine, InwardLine.serial_number_id == SerialNumber.id)
                            .where(InwardLine.batch_id == b_obj.id)
                        )
                        sn_list = [row[0] for row in cached_lines.all()]
                        return InwardBatchResponse(
                            id=b_obj.id,
                            product_id=b_obj.product_id,
                            product_name=p_name,
                            brand=p_brand,
                            model=p_model,
                            inward_type=b_obj.inward_type,
                            invoice_reference=b_obj.invoice_reference,
                            transaction_date=b_obj.transaction_date,
                            quantity=b_obj.quantity,
                            received_by_user_id=b_obj.received_by_user_id,
                            received_by_name=u_name,
                            device_id=b_obj.device_id,
                            remarks=b_obj.remarks,
                            created_at=b_obj.created_at,
                            serials=sn_list,
                        )

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
            "batch_id": str(batch.id),
            "client_request_id": req.client_request_id,
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


@router.post("/multi-batch", response_model=InwardMultiBatchResponse, status_code=status.HTTP_201_CREATED)
async def create_inward_multi_batch(
    req: InwardMultiBatchCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> InwardMultiBatchResponse:
    """
    Record inward stock across multiple products inside a SINGLE atomic transaction.
    - All models and serials are verified and recorded together.
    - If any validation fails or network disconnects mid-flight, nothing is committed.
    - Supports idempotency via client_request_id so retrying after network errors returns the saved result.
    """
    # 0. Idempotency check: if client_request_id was already committed, return existing batches
    if req.client_request_id:
        existing_log_res = await db.execute(
            select(AuditLog)
            .where(AuditLog.action == "INWARD_MULTI_BATCH")
            .order_by(AuditLog.created_at.desc())
            .limit(100)
        )
        for log in existing_log_res.scalars().all():
            if log.details and log.details.get("client_request_id") == req.client_request_id:
                batch_id_strs = log.details.get("batch_ids", [])
                if batch_id_strs:
                    b_uuids = [uuid.UUID(bid) for bid in batch_id_strs]
                    rows_res = await db.execute(
                        select(
                            InwardBatch,
                            Product.name.label("product_name"),
                            Product.brand.label("product_brand"),
                            Product.model.label("product_model"),
                            User.full_name.label("receiver_name"),
                        )
                        .join(Product, InwardBatch.product_id == Product.id)
                        .join(User, InwardBatch.received_by_user_id == User.id)
                        .where(InwardBatch.id.in_(b_uuids))
                        .order_by(InwardBatch.created_at.asc())
                    )
                    cached_rows = rows_res.all()
                    cached_batch_ids = [b.id for b, _, _, _, _ in cached_rows]
                    cached_lines_res = await db.execute(
                        select(InwardLine.batch_id, SerialNumber.serial_number)
                        .join(SerialNumber, InwardLine.serial_number_id == SerialNumber.id)
                        .where(InwardLine.batch_id.in_(cached_batch_ids))
                    )
                    serials_by_batch: dict[uuid.UUID, list[str]] = {}
                    for b_id, s_text in cached_lines_res.all():
                        serials_by_batch.setdefault(b_id, []).append(s_text)

                    cached_responses = []
                    tot_units = 0
                    for b, p_name, p_brand, p_model, u_name in cached_rows:
                        tot_units += b.quantity
                        cached_responses.append(
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
                                serials=serials_by_batch.get(b.id, []),
                            )
                        )
                    return InwardMultiBatchResponse(
                        batches=cached_responses,
                        total_units=tot_units,
                        invoice_reference=req.invoice_reference,
                    )

    # 1. Validate items
    if not req.items:
        raise HTTPException(status_code=400, detail="At least one product item is required.")

    # 2. Check device
    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    device_id = device.id if device else None

    # 3. Gather and validate all serial numbers across items
    global_seen_serials: set[str] = set()
    cleaned_items_per_product: list[tuple[uuid.UUID, str, list[str], dict[str, str]]] = []

    for item in req.items:
        inward_tp = (item.inward_type or "stock_in").lower()
        if inward_tp not in ("stock_in", "return", "damaged"):
            inward_tp = "stock_in"

        unit_map = item.unit_types or {}
        batch_serials: list[str] = []
        for s in item.serials:
            s_clean = s.strip()
            if not s_clean:
                continue
            if s_clean in global_seen_serials:
                raise HTTPException(
                    status_code=400,
                    detail=f"Duplicate serial number in this batch: '{s_clean}'. Each serial must be unique.",
                )
            global_seen_serials.add(s_clean)
            batch_serials.append(s_clean)

        if not batch_serials:
            raise HTTPException(
                status_code=400,
                detail=f"No valid serial numbers provided for model with ID {item.product_id}.",
            )
        cleaned_items_per_product.append((item.product_id, inward_tp, batch_serials, unit_map))

    if not global_seen_serials:
        raise HTTPException(status_code=400, detail="No valid serial numbers provided in batch.")

    # 4. Lock and query all Products
    product_ids = list({pid for pid, _, _, _ in cleaned_items_per_product})
    prod_res = await db.execute(
        select(Product).where(Product.id.in_(product_ids)).with_for_update()
    )
    products_map = {p.id: p for p in prod_res.scalars().all()}
    for pid in product_ids:
        if pid not in products_map:
            raise HTTPException(status_code=404, detail=f"Product with ID {pid} not found.")
        if not products_map[pid].is_active:
            raise HTTPException(status_code=400, detail=f"Product '{products_map[pid].name}' is deactivated.")

    # 5. Fetch categories for dual-serial check
    cat_ids = list({p.category_id for p in products_map.values() if p.category_id})
    cat_res = await db.execute(select(Category).where(Category.id.in_(cat_ids)))
    categories_map = {c.id: c for c in cat_res.scalars().all()}

    # 5b. Dual-serial validation
    for pid, _, batch_serials, unit_map in cleaned_items_per_product:
        prod = products_map[pid]
        cat = categories_map.get(prod.category_id)
        if cat and cat.has_dual_serial:
            in_cnt = sum(1 for s in batch_serials if unit_map.get(s) == "indoor")
            out_cnt = sum(1 for s in batch_serials if unit_map.get(s) == "outdoor")
            if in_cnt != out_cnt:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"Indoor and Outdoor unit counts must match for dual-serial model '{prod.name}'. "
                        f"Scanned: {in_cnt} Indoor unit(s), {out_cnt} Outdoor unit(s)."
                    ),
                )

    # 6. Fetch all existing serial records
    existing_res = await db.execute(
        select(SerialNumber, Product.name.label("product_name"), Product.model.label("product_model"))
        .join(Product, SerialNumber.product_id == Product.id)
        .where(SerialNumber.serial_number.in_(list(global_seen_serials)))
    )
    existing_rows = {row[0].serial_number: row for row in existing_res.all()}

    # Check OutwardLine for previous dispatches
    existing_outward_res = await db.execute(
        select(OutwardLine.serial_text, Shop.name.label("shop_name"))
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(OutwardLine.serial_text.in_(list(global_seen_serials)))
    )
    already_disp_lines = {row[0]: row[1] for row in existing_outward_res.all()}

    # 7. Type-specific validation for all items
    for pid, inward_tp, batch_serials, _ in cleaned_items_per_product:
        product = products_map[pid]
        if inward_tp == "stock_in":
            for s in batch_serials:
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
        elif inward_tp == "return":
            for s in batch_serials:
                if s in existing_rows:
                    sn, pname, pmodel = existing_rows[s]
                    if sn.product_id != product.id:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Cannot return serial '{s}' under this model: it belongs to '{pname} ({pmodel})'.",
                        )
        elif inward_tp == "damaged":
            for s in batch_serials:
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

    # 8. Create batches and lines atomically
    created_batches: list[InwardBatch] = []
    created_batch_responses: list[InwardBatchResponse] = []
    total_units_inwarded = 0

    for pid, inward_tp, batch_serials, unit_map in cleaned_items_per_product:
        product = products_map[pid]
        cat = categories_map.get(product.category_id)

        batch = InwardBatch(
            product_id=product.id,
            inward_type=inward_tp,
            invoice_reference=req.invoice_reference.strip() if req.invoice_reference else None,
            transaction_date=req.transaction_date,
            received_by_user_id=current_user.id,
            device_id=device_id,
            quantity=len(batch_serials),
            remarks=req.remarks.strip() if req.remarks else None,
        )
        db.add(batch)
        await db.flush()
        created_batches.append(batch)

        created_serials: list[str] = []
        for sn_text in batch_serials:
            u_type = unit_map.get(sn_text)
            target_status = SerialStatus.damaged if inward_tp == "damaged" else SerialStatus.available
            hist_action = (
                HistoryAction.status_changed if inward_tp == "damaged"
                else HistoryAction.returned if inward_tp == "return"
                else HistoryAction.inward_recorded
            )

            if sn_text in existing_rows:
                sn_record, _, _ = existing_rows[sn_text]
                from_st = sn_record.status
                sn_record.status = target_status
                if inward_tp == "return":
                    sn_record.last_shop_id = None
                if u_type:
                    sn_record.unit_type = u_type
            else:
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
                remarks=f"Inward [{inward_tp}]: {req.remarks or ''}".strip(),
            )
            db.add(history)
            created_serials.append(sn_text)

        inward_units_count = (len(batch_serials) // 2) if (cat and cat.has_dual_serial) else len(batch_serials)
        if inward_tp in ("stock_in", "return"):
            product.current_stock_qty += inward_units_count

        product.has_had_inward = True
        total_units_inwarded += len(batch_serials)

        created_batch_responses.append(
            InwardBatchResponse(
                id=batch.id,
                product_id=product.id,
                product_name=product.name,
                brand=product.brand,
                model=product.model,
                inward_type=inward_tp,
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
        )

    # 9. Audit Log for multi-batch
    batch_ids_str = [str(b.id) for b in created_batches]
    audit = AuditLog(
        user_id=current_user.id,
        device_id=device_id,
        action="INWARD_MULTI_BATCH",
        entity_type="inward_batch",
        entity_id=batch_ids_str[0] if batch_ids_str else None,
        details={
            "client_request_id": req.client_request_id,
            "batch_ids": batch_ids_str,
            "total_units": total_units_inwarded,
            "total_batches": len(created_batches),
            "invoice_reference": req.invoice_reference,
        },
    )
    db.add(audit)

    # 10. Single atomic commit
    await db.commit()

    # 11. Broadcast WebSockets
    for pid in product_ids:
        p = products_map[pid]
        await ws_manager.broadcast("stock_updated", {
            "type": "inward",
            "product_id": str(p.id),
            "current_stock_qty": p.current_stock_qty,
            "invoice_reference": req.invoice_reference,
        })

    return InwardMultiBatchResponse(
        batches=created_batch_responses,
        total_units=total_units_inwarded,
        invoice_reference=req.invoice_reference,
    )


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