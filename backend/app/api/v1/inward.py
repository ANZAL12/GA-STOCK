from datetime import date
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_device_optional, get_current_user
from app.database import get_db
from app.models.audit import AuditLog
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
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
) -> InwardValidateSerialResponse:
    """
    Real-time check for barcode scanner on mobile:
    Verifies if a serial number already exists anywhere in the system.
    If it exists, returns the model it is registered under so the mobile app
    can immediately display a clear error row to the staff.
    """
    clean_serial = req.serial_number.strip()
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

    if row:
        sn, prod_name, prod_model = row
        model_display = f"{prod_name} ({prod_model})"
        return InwardValidateSerialResponse(
            serial_number=clean_serial,
            is_valid=False,
            already_exists=True,
            registered_model_name=model_display,
            registered_model_id=sn.product_id,
            message=f"Serial '{clean_serial}' is already registered under {model_display}.",
        )

    return InwardValidateSerialResponse(
        serial_number=clean_serial,
        is_valid=True,
        already_exists=False,
        message="Serial is available for inward.",
    )


@router.post("/batches", response_model=InwardBatchResponse, status_code=status.HTTP_201_CREATED)
async def create_inward_batch(
    req: InwardBatchCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> InwardBatchResponse:
    """
    Record an inward stock batch inside a single atomic transaction.
    - Validates no duplicate serials in the batch
    - Validates no serial already exists in the system (tells which model it belongs to)
    - Creates serial number records with status Available
    - Increments product current_stock_qty and flips has_had_inward=True
    - Writes serial history entries (action='inward_recorded')
    - Writes audit log
    """
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

    # 5. Check if ANY scanned serial already exists anywhere in the database
    existing_res = await db.execute(
        select(SerialNumber, Product.name.label("product_name"), Product.model.label("product_model"))
        .join(Product, SerialNumber.product_id == Product.id)
        .where(SerialNumber.serial_number.in_(raw_serials))
    )
    existing_rows = existing_res.all()
    if existing_rows:
        first_clash = existing_rows[0]
        clash_sn, clash_pname, clash_pmodel = first_clash
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Cannot submit inward: Serial '{clash_sn.serial_number}' is already "
                f"registered under '{clash_pname} ({clash_pmodel})'."
            ),
        )

    # 6. Create InwardBatch
    batch = InwardBatch(
        product_id=product.id,
        invoice_reference=req.invoice_reference.strip() if req.invoice_reference else None,
        transaction_date=req.transaction_date,
        received_by_user_id=current_user.id,
        device_id=device_id,
        quantity=len(raw_serials),
        remarks=req.remarks.strip() if req.remarks else None,
    )
    db.add(batch)
    await db.flush()

    # 7. Create SerialNumber, InwardLine, and SerialHistory for each serial
    created_serials: list[str] = []
    for sn_text in raw_serials:
        sn_record = SerialNumber(
            serial_number=sn_text,
            product_id=product.id,
            status=SerialStatus.available,
            last_shop_id=None,
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
            action=HistoryAction.inward_recorded,
            from_status=None,
            to_status=SerialStatus.available,
            inward_batch_id=batch.id,
            user_id=current_user.id,
            device_id=device_id,
            remarks=req.remarks,
        )
        db.add(history)
        created_serials.append(sn_text)

    # 8. Update product running stock & flip has_had_inward
    product.current_stock_qty += len(raw_serials)
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
            "quantity": len(raw_serials),
            "invoice_reference": batch.invoice_reference,
            "serials_sample": raw_serials[:5],
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(batch)

    return InwardBatchResponse(
        id=batch.id,
        product_id=product.id,
        product_name=product.name,
        brand=product.brand,
        model=product.model,
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