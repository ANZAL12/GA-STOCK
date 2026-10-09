from datetime import date
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_device_optional, get_current_user
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.enums import HistoryAction, SerialStatus
from app.models.category import Category
from app.models.history import SerialHistory
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.outward import (
    BillBatchSummary,
    BillDetailResponse,
    BillListItem,
    OutwardBatchCreate,
    OutwardBatchResponse,
    OutwardCheckRefRequest,
    OutwardCheckRefResponse,
    OutwardCheckSerialRequest,
    OutwardCheckSerialResponse,
    OutwardLineResponse,
    OutwardMultiBatchCreate,
    OutwardMultiBatchResponse,
    OutwardProductBatchItem,
)

router = APIRouter(prefix="/outward", tags=["outward"])


@router.post("/check-serial", response_model=OutwardCheckSerialResponse)
async def check_serial(
    req: OutwardCheckSerialRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OutwardCheckSerialResponse:
    """
    Real-time check for mobile scanning:
    Evaluates a scanned serial under the four cases defined in spec §5.
    Returns case number, badge color, and confirmation requirement.
    """
    clean_serial = req.serial_number.strip()
    if not clean_serial:
        raise HTTPException(status_code=400, detail="Serial number cannot be blank.")

    # 1. Query serial_numbers
    query = (
        select(
            SerialNumber,
            Product.name.label("product_name"),
            Product.model.label("product_model"),
            Shop.name.label("last_shop_name"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .where(SerialNumber.serial_number == clean_serial)
    )
    result = await db.execute(query)
    row = result.first()

    # 2. Query previous outward dispatch lines (any batch, any shop)
    prev_disp_res = await db.execute(
        select(OutwardLine, Shop.name.label("shop_name"))
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(OutwardLine.serial_text == clean_serial)
        .order_by(OutwardLine.transaction_date.desc())
    )
    prev_disp = prev_disp_res.first()

    sn = None
    is_already_dispatched = False
    disp_shop_name = None
    disp_date = None
    registered_model_display = None

    if row:
        sn, prod_name, prod_model, last_shop_name = row
        registered_model_display = f"{prod_name} ({prod_model})"
        # If the serial exists in our tracked inventory:
        # Check if its CURRENT status is 'dispatched'.
        # If it was returned via Inward Return, its status is now 'available', so it is in stock and free to dispatch!
        if sn.status == SerialStatus.dispatched:
            is_already_dispatched = True
            disp_shop_name = last_shop_name
            if prev_disp:
                disp_line, s_name = prev_disp
                disp_shop_name = s_name or disp_shop_name
                disp_date = disp_line.transaction_date
    elif prev_disp:
        # Untracked pre-go-live serial (never recorded in serial_numbers):
        # Was previously dispatched and never returned through Inward Return
        is_already_dispatched = True
        disp_line, s_name = prev_disp
        disp_shop_name = s_name
        disp_date = disp_line.transaction_date

    # --- STRICT RULE: ONCE DISPATCHED, NEVER SCANNED OR DISPATCHED AGAIN ---
    if is_already_dispatched:
        shop_info = f" to shop '{disp_shop_name}'" if disp_shop_name else ""
        date_info = f" on {disp_date}" if disp_date else ""
        disp_unit_type = sn.unit_type if sn else (prev_disp[0].unit_type if prev_disp else None)
        return OutwardCheckSerialResponse(
            serial_number=clean_serial,
            case=0,
            case_name="blocked",
            badge="blocked",
            badge_label="Already Dispatched",
            message=f"Serial '{clean_serial}' has ALREADY been dispatched{shop_info}{date_info}. It cannot be scanned or dispatched again.",
            requires_confirmation=False,
            warning_duplicate_dispatch=True,
            is_dispatched=True,
            can_dispatch=False,
            is_blocked=True,
            is_matched=row is not None,
            registered_model_name=registered_model_display,
            current_status="dispatched",
            unit_type=disp_unit_type,
            last_dispatched_date=disp_date,
            last_dispatched_shop_name=disp_shop_name,
        )

    # Case 2: Not in system at all (old pre-go-live stock, not yet dispatched)
    if not row:
        return OutwardCheckSerialResponse(
            serial_number=clean_serial,
            case=2,
            case_name="unmatched",
            badge="unmatched",
            badge_label="Not in system, will be recorded",
            message="Not in system (pre-go-live stock). Will be recorded without error.",
            requires_confirmation=False,
            warning_duplicate_dispatch=False,
            is_dispatched=False,
            can_dispatch=True,
            is_blocked=False,
            is_matched=False,
        )

    sn, prod_name, prod_model, last_shop_name = row
    registered_model_display = f"{prod_name} ({prod_model})"

    # Case 4: Known, not dispatched, but belongs to a different model than the one selected
    if sn.product_id != req.product_id:
        return OutwardCheckSerialResponse(
            serial_number=clean_serial,
            case=4,
            case_name="model_mismatch",
            badge="warning",
            badge_label="Model Warning",
            message=(
                f"Serial is registered under '{registered_model_display}', not the selected model. "
                "Confirm to dispatch anyway (will be flagged for admin review)."
            ),
            requires_confirmation=True,
            warning_duplicate_dispatch=False,
            is_dispatched=False,
            can_dispatch=True,
            is_blocked=False,
            is_matched=False,
            registered_model_name=registered_model_display,
            registered_product_id=sn.product_id,
            current_status=sn.status.value,
            unit_type=sn.unit_type,
        )

    # Case 3: Known, same model, not dispatched, but status is NOT Available
    if sn.status != SerialStatus.available:
        return OutwardCheckSerialResponse(
            serial_number=clean_serial,
            case=3,
            case_name="status_warning",
            badge="warning",
            badge_label="Status Warning",
            message=(
                f"Serial is currently in status '{sn.status.value}'. "
                "Confirm to dispatch anyway (will be flagged for admin review)."
            ),
            requires_confirmation=True,
            warning_duplicate_dispatch=False,
            is_dispatched=False,
            can_dispatch=True,
            is_blocked=False,
            is_matched=True,
            registered_model_name=registered_model_display,
            registered_product_id=sn.product_id,
            current_status=sn.status.value,
            unit_type=sn.unit_type,
            last_dispatched_shop_name=last_shop_name,
        )

    # Case 1: Known, Available, same model -> MATCHED!
    return OutwardCheckSerialResponse(
        serial_number=clean_serial,
        case=1,
        case_name="matched",
        badge="matched",
        badge_label="Matched",
        message="Available and matched to selected model.",
        requires_confirmation=False,
        warning_duplicate_dispatch=False,
        is_dispatched=False,
        can_dispatch=True,
        is_blocked=False,
        is_matched=True,
        registered_model_name=registered_model_display,
        registered_product_id=sn.product_id,
        current_status="available",
        unit_type=sn.unit_type,
    )


@router.post("/check-reference", response_model=OutwardCheckRefResponse)
async def check_reference(
    req: OutwardCheckRefRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OutwardCheckRefResponse:
    """
    Soft warning: Checks if the same delivery reference has already been used
    for the same shop on the same day.
    """
    clean_ref = req.delivery_reference.strip()
    if not clean_ref:
        return OutwardCheckRefResponse(has_warning=False)

    existing = await db.execute(
        select(OutwardBatch).where(
            OutwardBatch.shop_id == req.shop_id,
            OutwardBatch.transaction_date == req.transaction_date,
            func.lower(OutwardBatch.delivery_reference) == clean_ref.lower(),
        )
    )
    if existing.first():
        return OutwardCheckRefResponse(
            has_warning=True,
            message=(
                f"Notice: Delivery reference '{clean_ref}' was already used for "
                f"this shop on {req.transaction_date}. You may still proceed if intentional."
            ),
        )

    return OutwardCheckRefResponse(has_warning=False)


@router.get("/check-serial", response_model=OutwardCheckSerialResponse)
async def check_serial_get(
    product_id: uuid.UUID,
    serial_number: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    shop_id: Optional[uuid.UUID] = None,
) -> OutwardCheckSerialResponse:
    dummy_shop_id = shop_id or uuid.uuid4()
    req = OutwardCheckSerialRequest(product_id=product_id, shop_id=dummy_shop_id, serial_number=serial_number)
    return await check_serial(req=req, current_user=current_user, db=db)


@router.get("/check-reference", response_model=OutwardCheckRefResponse)
async def check_reference_get(
    shop_id: uuid.UUID,
    reference: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OutwardCheckRefResponse:
    req = OutwardCheckRefRequest(shop_id=shop_id, delivery_reference=reference)
    return await check_reference(req=req, current_user=current_user, db=db)


@router.post("/batch", response_model=OutwardBatchResponse, status_code=status.HTTP_201_CREATED)
@router.post("/batches", response_model=OutwardBatchResponse, status_code=status.HTTP_201_CREATED)
async def create_outward_batch(
    req: OutwardBatchCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> OutwardBatchResponse:
    """
    Record an outward dispatch batch inside a single atomic transaction.
    - Shop is mandatory.
    - Evaluates all 4 serial cases.
    - Rejects duplicate serials within the batch.
    - Rejects unconfirmed warning serials (cases 3 & 4 require confirmed_warning=True).
    - Decrements stock count atomically (floored at 0).
    - Writes OutwardBatch, OutwardLines, SerialHistory, and AuditLog.
    """
    # 1. Validate serials
    if not req.serials:
        raise HTTPException(status_code=400, detail="At least one serial number is required.")

    seen_serials = set()
    unit_map = req.unit_types or {}
    cleaned_items: list[tuple[str, bool, Optional[str]]] = []
    for item in req.serials:
        s_clean = item.serial_number.strip()
        if not s_clean:
            continue
        if s_clean in seen_serials:
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate serial number in this batch: '{s_clean}'. Each serial must be unique.",
            )
        seen_serials.add(s_clean)
        u_type = item.unit_type or unit_map.get(s_clean)
        cleaned_items.append((s_clean, item.confirmed_warning, u_type))

    if not cleaned_items:
        raise HTTPException(status_code=400, detail="No valid serial numbers provided.")

    # 2. Check device if header present
    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    device_id = device.id if device else None

    # 3. Check Shop exists and is active
    shop_res = await db.execute(select(Shop).where(Shop.id == req.shop_id))
    shop = shop_res.scalar_one_or_none()
    if not shop:
        raise HTTPException(status_code=404, detail="Selected shop not found.")
    if not shop.is_active:
        raise HTTPException(status_code=400, detail="Selected shop is deactivated.")

    # 4. Lock Product row
    prod_res = await db.execute(
        select(Product).where(Product.id == req.product_id).with_for_update()
    )
    product = prod_res.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Selected product not found.")
    if not product.is_active:
        raise HTTPException(status_code=400, detail="Selected product is deactivated.")

    # 5. Lock and query all matching SerialNumber rows
    serial_texts = [s for s, _, _ in cleaned_items]
    sn_query = (
        select(SerialNumber)
        .where(SerialNumber.serial_number.in_(serial_texts))
        .with_for_update()
    )
    sn_res = await db.execute(sn_query)
    sn_map: dict[str, SerialNumber] = {sn.serial_number: sn for sn in sn_res.scalars().all()}

    # 5b. If category has dual serials, ensure equal numbers of indoor and outdoor units
    cat_res = await db.execute(select(Category).where(Category.id == product.category_id))
    cat = cat_res.scalar_one_or_none()
    if cat and cat.has_dual_serial:
        def get_item_unit_type(s_text: str, u_type: Optional[str]) -> Optional[str]:
            if u_type:
                return u_type
            if req.unit_types and s_text in req.unit_types:
                return req.unit_types[s_text]
            if s_text in sn_map and sn_map[s_text].unit_type:
                return sn_map[s_text].unit_type
            return None

        indoor_count = sum(1 for s_text, _, u_type in cleaned_items if get_item_unit_type(s_text, u_type) == "indoor")
        outdoor_count = sum(1 for s_text, _, u_type in cleaned_items if get_item_unit_type(s_text, u_type) == "outdoor")
        if indoor_count != outdoor_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Indoor and Outdoor unit counts must match for dual-serial model '{product.name}'. "
                    f"Scanned: {indoor_count} Indoor unit(s), {outdoor_count} Outdoor unit(s). "
                    "Equal numbers of indoor and outdoor units are required to dispatch."
                ),
            )

    # 6. STRICT BLOCK: Check if any serial is currently dispatched
    for s_text, _, _ in cleaned_items:
        if s_text in sn_map and sn_map[s_text].status == SerialStatus.dispatched:
            raise HTTPException(
                status_code=400,
                detail=f"Serial '{s_text}' is currently marked as Dispatched. It cannot be dispatched again until returned.",
            )

    # For untracked serials (not in serial_numbers), check if previously dispatched and never returned
    untracked_serials = [s for s, _, _ in cleaned_items if s not in sn_map]
    if untracked_serials:
        existing_outward_res = await db.execute(
            select(OutwardLine.serial_text, Shop.name.label("shop_name"))
            .join(Shop, OutwardLine.shop_id == Shop.id)
            .where(OutwardLine.serial_text.in_(untracked_serials))
        )
        already_disp_lines = existing_outward_res.all()
        if already_disp_lines:
            first_bad = already_disp_lines[0]
            raise HTTPException(
                status_code=400,
                detail=f"Serial '{first_bad.serial_text}' was already dispatched (to shop '{first_bad.shop_name}') and cannot be dispatched again under any circumstances.",
            )

    # 7. Pre-validate: ensure any case 3 or case 4 serial has confirmation
    for s_text, is_confirmed, _ in cleaned_items:
        if s_text in sn_map:
            sn = sn_map[s_text]
            if sn.product_id != product.id:
                if not is_confirmed:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Serial '{s_text}' is registered under a different model. "
                            "Staff confirmation is required to dispatch."
                        ),
                    )
            elif sn.status != SerialStatus.available:
                if not is_confirmed:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Serial '{s_text}' is currently in status '{sn.status.value}'. "
                            "Staff confirmation is required to dispatch."
                        ),
                    )

    # 7. Create OutwardBatch
    batch = OutwardBatch(
        product_id=product.id,
        shop_id=shop.id,
        bill_number=req.bill_number.strip() if req.bill_number else None,
        delivery_reference=req.delivery_reference.strip() if req.delivery_reference else None,
        transaction_date=req.transaction_date,
        dispatched_by_user_id=current_user.id,
        device_id=device_id,
        quantity=len(cleaned_items),
        matched_count=0,
        unmatched_count=0,
        flagged_count=0,
        remarks=req.remarks.strip() if req.remarks else None,
    )
    db.add(batch)
    await db.flush()

    line_responses: list[OutwardLineResponse] = []
    matched_cnt = 0
    unmatched_cnt = 0
    flagged_cnt = 0

    # 8. Process each serial
    for s_text, is_confirmed, u_type in cleaned_items:
        if s_text not in sn_map:
            # Case 2: Unmatched (old stock pre-go-live) -> NOT AN ERROR
            unmatched_cnt += 1
            line = OutwardLine(
                batch_id=batch.id,
                serial_text=s_text,
                serial_number_id=None,
                product_id=product.id,
                shop_id=shop.id,
                transaction_date=req.transaction_date,
                is_matched=False,
                is_flagged_for_review=False,
                flag_reason="Not matched to an inward record (pre-go-live stock)",
                unit_type=u_type,
            )
            db.add(line)
            await db.flush()

            history = SerialHistory(
                serial_number_id=None,
                serial_text=s_text,
                action=HistoryAction.dispatched_unmatched,
                from_status=None,
                to_status=SerialStatus.dispatched,
                shop_id=shop.id,
                outward_batch_id=batch.id,
                is_matched=False,
                user_id=current_user.id,
                device_id=device_id,
                remarks=f"Dispatched (recorded only){f' [{u_type.capitalize()}]' if u_type else ''}",
            )
            db.add(history)

            line_responses.append(
                OutwardLineResponse(
                    id=line.id,
                    serial_text=s_text,
                    serial_number_id=None,
                    is_matched=False,
                    is_flagged_for_review=False,
                    flag_reason=line.flag_reason,
                    unit_type=u_type,
                    status_label="Recorded only",
                )
            )

        else:
            sn = sn_map[s_text]
            old_status = sn.status

            if sn.product_id != product.id:
                # Case 4: Wrong model (flagged)
                flagged_cnt += 1
                sn.status = SerialStatus.dispatched
                sn.last_shop_id = shop.id

                line = OutwardLine(
                    batch_id=batch.id,
                    serial_text=s_text,
                    serial_number_id=sn.id,
                    product_id=product.id,
                    shop_id=shop.id,
                    transaction_date=req.transaction_date,
                    is_matched=False,
                    is_flagged_for_review=True,
                    flag_reason=f"Registered under model ID {sn.product_id}",
                    unit_type=u_type or sn.unit_type,
                )
                db.add(line)
                await db.flush()

                history = SerialHistory(
                    serial_number_id=sn.id,
                    serial_text=s_text,
                    action=HistoryAction.dispatched_flagged,
                    from_status=old_status,
                    to_status=SerialStatus.dispatched,
                    shop_id=shop.id,
                    outward_batch_id=batch.id,
                    is_matched=False,
                    user_id=current_user.id,
                    device_id=device_id,
                    remarks="Dispatched with model mismatch warning (flagged for review)",
                )
                db.add(history)

                line_responses.append(
                    OutwardLineResponse(
                        id=line.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        is_matched=False,
                        is_flagged_for_review=True,
                        flag_reason=line.flag_reason,
                        unit_type=line.unit_type,
                        status_label="Flagged",
                    )
                )

            elif sn.status != SerialStatus.available:
                # Case 3: Wrong status (flagged)
                flagged_cnt += 1
                sn.status = SerialStatus.dispatched
                sn.last_shop_id = shop.id

                line = OutwardLine(
                    batch_id=batch.id,
                    serial_text=s_text,
                    serial_number_id=sn.id,
                    product_id=product.id,
                    shop_id=shop.id,
                    transaction_date=req.transaction_date,
                    is_matched=False,
                    is_flagged_for_review=True,
                    flag_reason=f"Previous status was '{old_status.value}'",
                    unit_type=u_type or sn.unit_type,
                )
                db.add(line)
                await db.flush()

                history = SerialHistory(
                    serial_number_id=sn.id,
                    serial_text=s_text,
                    action=HistoryAction.dispatched_flagged,
                    from_status=old_status,
                    to_status=SerialStatus.dispatched,
                    shop_id=shop.id,
                    outward_batch_id=batch.id,
                    is_matched=False,
                    user_id=current_user.id,
                    device_id=device_id,
                    remarks=f"Dispatched with status conflict ('{old_status.value}')",
                )
                db.add(history)

                line_responses.append(
                    OutwardLineResponse(
                        id=line.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        is_matched=False,
                        is_flagged_for_review=True,
                        flag_reason=line.flag_reason,
                        unit_type=line.unit_type,
                        status_label="Flagged",
                    )
                )

            else:
                # Case 1: Matched!
                matched_cnt += 1
                sn.status = SerialStatus.dispatched
                sn.last_shop_id = shop.id

                line = OutwardLine(
                    batch_id=batch.id,
                    serial_text=s_text,
                    serial_number_id=sn.id,
                    product_id=product.id,
                    shop_id=shop.id,
                    transaction_date=req.transaction_date,
                    is_matched=True,
                    is_flagged_for_review=False,
                    flag_reason=None,
                    unit_type=u_type or sn.unit_type,
                )
                db.add(line)
                await db.flush()

                history = SerialHistory(
                    serial_number_id=sn.id,
                    serial_text=s_text,
                    action=HistoryAction.dispatched_matched,
                    from_status=SerialStatus.available,
                    to_status=SerialStatus.dispatched,
                    shop_id=shop.id,
                    outward_batch_id=batch.id,
                    is_matched=True,
                    user_id=current_user.id,
                    device_id=device_id,
                    remarks=None,
                )
                db.add(history)

                line_responses.append(
                    OutwardLineResponse(
                        id=line.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        is_matched=True,
                        is_flagged_for_review=False,
                        flag_reason=None,
                        unit_type=line.unit_type,
                        status_label="Matched",
                    )
                )

    # 9. Update batch counts
    batch.matched_count = matched_cnt
    batch.unmatched_count = unmatched_cnt
    batch.flagged_count = flagged_cnt

    # 10. Update product stock (allow negative numbers if outward exceeds stock)
    outward_units_count = (len(cleaned_items) // 2) if (cat and cat.has_dual_serial) else len(cleaned_items)
    product.current_stock_qty = product.current_stock_qty - outward_units_count

    # 11. Audit Log
    audit = AuditLog(
        user_id=current_user.id,
        device_id=device_id,
        action="OUTWARD_SUBMITTED",
        entity_type="outward_batch",
        entity_id=str(batch.id),
        details={
            "product_id": str(product.id),
            "shop_id": str(shop.id),
            "shop_name": shop.name,
            "quantity": len(cleaned_items),
            "matched_count": matched_cnt,
            "unmatched_count": unmatched_cnt,
            "flagged_count": flagged_cnt,
            "delivery_reference": batch.delivery_reference,
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(batch)

    resp = OutwardBatchResponse(
        id=batch.id,
        product_id=product.id,
        product_name=product.name,
        brand=product.brand,
        model=product.model,
        shop_id=shop.id,
        shop_name=shop.name,
        shop_city=shop.city,
        bill_number=batch.bill_number,
        delivery_reference=batch.delivery_reference,
        transaction_date=batch.transaction_date,
        quantity=batch.quantity,
        matched_count=batch.matched_count,
        unmatched_count=batch.unmatched_count,
        flagged_count=batch.flagged_count,
        dispatched_by_user_id=current_user.id,
        dispatched_by_name=current_user.full_name,
        device_id=device_id,
        remarks=batch.remarks,
        created_at=batch.created_at,
        lines=line_responses,
    )

    await ws_manager.broadcast("stock_updated", {
        "type": "outward",
        "product_id": str(product.id),
        "current_stock_qty": product.current_stock_qty,
        "quantity": len(cleaned_items),
        "delivery_reference": batch.delivery_reference,
    })

    return resp


@router.post("/multi-batch", response_model=OutwardMultiBatchResponse, status_code=status.HTTP_201_CREATED)
async def create_outward_multi_batch(
    req: OutwardMultiBatchCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
) -> OutwardMultiBatchResponse:
    """
    Record an outward dispatch batch across multiple models inside a SINGLE atomic transaction.
    - All models and serials are verified and dispatched together.
    - If any validation fails or network disconnects mid-flight, nothing is committed.
    - Supports idempotency via client_request_id so retrying after a network failure returns the existing result without "already dispatched" error.
    """
    # 0. Idempotency check: if client_request_id was already successfully committed, return it
    if req.client_request_id:
        existing_log_res = await db.execute(
            select(AuditLog)
            .where(AuditLog.action == "OUTWARD_MULTI_BATCH")
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
                            OutwardBatch,
                            Product.name.label("product_name"),
                            Product.brand.label("product_brand"),
                            Product.model.label("product_model"),
                            Shop.name.label("shop_name"),
                            Shop.city.label("shop_city"),
                            User.full_name.label("dispatcher_name"),
                        )
                        .join(Product, OutwardBatch.product_id == Product.id)
                        .join(Shop, OutwardBatch.shop_id == Shop.id)
                        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
                        .where(OutwardBatch.id.in_(b_uuids))
                        .order_by(OutwardBatch.created_at.asc())
                    )
                    cached_rows = rows_res.all()
                    cached_batch_ids = [b.id for b, _, _, _, _, _, _ in cached_rows]
                    cached_lines_res = await db.execute(
                        select(OutwardLine)
                        .where(OutwardLine.batch_id.in_(cached_batch_ids))
                        .order_by(OutwardLine.created_at.asc())
                    )
                    cached_lines = cached_lines_res.scalars().all()
                    lines_by_batch: dict[uuid.UUID, list[OutwardLineResponse]] = {}
                    for cl in cached_lines:
                        lbl = "Flagged" if cl.is_flagged_for_review else ("Matched" if cl.is_matched else "Recorded only")
                        lines_by_batch.setdefault(cl.batch_id, []).append(
                            OutwardLineResponse(
                                id=cl.id,
                                serial_text=cl.serial_text,
                                serial_number_id=cl.serial_number_id,
                                is_matched=cl.is_matched,
                                is_flagged_for_review=cl.is_flagged_for_review,
                                flag_reason=cl.flag_reason,
                                unit_type=cl.unit_type,
                                status_label=lbl,
                            )
                        )

                    cached_batch_responses = []
                    tot_u = 0
                    tot_m = 0
                    tot_unm = 0
                    tot_flg = 0
                    for b, p_name, p_brand, p_model, s_name, s_city, u_name in cached_rows:
                        tot_u += b.quantity
                        tot_m += b.matched_count
                        tot_unm += b.unmatched_count
                        tot_flg += b.flagged_count
                        cached_batch_responses.append(
                            OutwardBatchResponse(
                                id=b.id,
                                product_id=b.product_id,
                                product_name=p_name,
                                brand=p_brand,
                                model=p_model,
                                shop_id=b.shop_id,
                                shop_name=s_name,
                                shop_city=s_city,
                                bill_number=b.bill_number,
                                delivery_reference=b.delivery_reference,
                                transaction_date=b.transaction_date,
                                quantity=b.quantity,
                                matched_count=b.matched_count,
                                unmatched_count=b.unmatched_count,
                                flagged_count=b.flagged_count,
                                dispatched_by_user_id=b.dispatched_by_user_id,
                                dispatched_by_name=u_name,
                                device_id=b.device_id,
                                remarks=b.remarks,
                                created_at=b.created_at,
                                lines=lines_by_batch.get(b.id, []),
                            )
                        )
                    return OutwardMultiBatchResponse(
                        batches=cached_batch_responses,
                        total_units=tot_u,
                        total_matched=tot_m,
                        total_unmatched=tot_unm,
                        total_flagged=tot_flg,
                        bill_number=req.bill_number,
                        delivery_reference=req.delivery_reference,
                    )

    # 1. Validate items
    if not req.items:
        raise HTTPException(status_code=400, detail="At least one product batch item is required.")

    # 2. Check device if header present
    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    device_id = device.id if device else None

    # 3. Check Shop exists and is active
    shop_res = await db.execute(select(Shop).where(Shop.id == req.shop_id))
    shop = shop_res.scalar_one_or_none()
    if not shop:
        raise HTTPException(status_code=404, detail="Selected shop not found.")
    if not shop.is_active:
        raise HTTPException(status_code=400, detail="Selected shop is deactivated.")

    # 4. Check all serial numbers across all items for duplicates within the dispatch
    global_seen_serials: set[str] = set()
    cleaned_items_per_batch: list[tuple[uuid.UUID, list[tuple[str, bool, Optional[str]]]]] = []

    for item in req.items:
        unit_map = item.unit_types or {}
        batch_cleaned: list[tuple[str, bool, Optional[str]]] = []
        for s in item.serials:
            s_clean = s.serial_number.strip()
            if not s_clean:
                continue
            if s_clean in global_seen_serials:
                raise HTTPException(
                    status_code=400,
                    detail=f"Duplicate serial number in this dispatch: '{s_clean}'. Each serial must be unique across the entire dispatch.",
                )
            global_seen_serials.add(s_clean)
            u_type = s.unit_type or unit_map.get(s_clean)
            batch_cleaned.append((s_clean, s.confirmed_warning, u_type))

        if not batch_cleaned:
            raise HTTPException(
                status_code=400,
                detail=f"No valid serial numbers provided for model with ID {item.product_id}.",
            )
        cleaned_items_per_batch.append((item.product_id, batch_cleaned))

    if not global_seen_serials:
        raise HTTPException(status_code=400, detail="No valid serial numbers provided in dispatch.")

    # 5. Lock and query all Products
    product_ids = list({pid for pid, _ in cleaned_items_per_batch})
    prod_res = await db.execute(
        select(Product).where(Product.id.in_(product_ids)).with_for_update()
    )
    products_map = {p.id: p for p in prod_res.scalars().all()}
    for pid in product_ids:
        if pid not in products_map:
            raise HTTPException(status_code=404, detail=f"Product with ID {pid} not found.")
        if not products_map[pid].is_active:
            raise HTTPException(status_code=400, detail=f"Product '{products_map[pid].name}' is deactivated.")

    # 6. Fetch categories for dual-serial check
    cat_ids = list({p.category_id for p in products_map.values() if p.category_id})
    cat_res = await db.execute(select(Category).where(Category.id.in_(cat_ids)))
    categories_map = {c.id: c for c in cat_res.scalars().all()}

    # 7. Lock and query all matching SerialNumber rows
    sn_query = (
        select(SerialNumber)
        .where(SerialNumber.serial_number.in_(list(global_seen_serials)))
        .with_for_update()
    )
    sn_res = await db.execute(sn_query)
    sn_map: dict[str, SerialNumber] = {sn.serial_number: sn for sn in sn_res.scalars().all()}

    # 8. Dual serial validation
    for pid, batch_cleaned in cleaned_items_per_batch:
        prod = products_map[pid]
        cat = categories_map.get(prod.category_id)
        if cat and cat.has_dual_serial:
            def _get_u_type(s_txt: str, u_tp: Optional[str]) -> Optional[str]:
                if u_tp:
                    return u_tp
                if s_txt in sn_map and sn_map[s_txt].unit_type:
                    return sn_map[s_txt].unit_type
                return None

            in_cnt = sum(1 for s_txt, _, u_tp in batch_cleaned if _get_u_type(s_txt, u_tp) == "indoor")
            out_cnt = sum(1 for s_txt, _, u_tp in batch_cleaned if _get_u_type(s_txt, u_tp) == "outdoor")
            if in_cnt != out_cnt:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"Indoor and Outdoor unit counts must match for dual-serial model '{prod.name}'. "
                        f"Scanned: {in_cnt} Indoor unit(s), {out_cnt} Outdoor unit(s)."
                    ),
                )

    # 9. STRICT BLOCK: Check if any serial is already marked as Dispatched
    for s_clean in global_seen_serials:
        if s_clean in sn_map and sn_map[s_clean].status == SerialStatus.dispatched:
            raise HTTPException(
                status_code=400,
                detail=f"Serial '{s_clean}' is currently marked as Dispatched. It cannot be dispatched again until returned.",
            )

    # For untracked serials, check if previously dispatched
    untracked_serials = [s for s in global_seen_serials if s not in sn_map]
    if untracked_serials:
        existing_outward_res = await db.execute(
            select(OutwardLine.serial_text, Shop.name.label("shop_name"))
            .join(Shop, OutwardLine.shop_id == Shop.id)
            .where(OutwardLine.serial_text.in_(untracked_serials))
        )
        already_disp_lines = existing_outward_res.all()
        if already_disp_lines:
            first_bad = already_disp_lines[0]
            raise HTTPException(
                status_code=400,
                detail=f"Serial '{first_bad.serial_text}' was already dispatched (to shop '{first_bad.shop_name}') and cannot be dispatched again under any circumstances.",
            )

    # 10. Check confirmation for warning cases (3 & 4)
    for pid, batch_cleaned in cleaned_items_per_batch:
        prod = products_map[pid]
        for s_clean, is_confirmed, _ in batch_cleaned:
            if s_clean in sn_map:
                sn = sn_map[s_clean]
                if sn.product_id != prod.id:
                    if not is_confirmed:
                        raise HTTPException(
                            status_code=400,
                            detail=(
                                f"Serial '{s_clean}' is registered under a different model. "
                                "Staff confirmation is required to dispatch."
                            ),
                        )
                elif sn.status != SerialStatus.available:
                    if not is_confirmed:
                        raise HTTPException(
                            status_code=400,
                            detail=(
                                f"Serial '{s_clean}' is currently in status '{sn.status.value}'. "
                                "Staff confirmation is required to dispatch."
                            ),
                        )

    # 11. Process and record all batches in this single atomic transaction
    created_batches: list[OutwardBatch] = []
    created_batch_responses: list[OutwardBatchResponse] = []
    total_units_dispatched = 0
    total_matched_all = 0
    total_unmatched_all = 0
    total_flagged_all = 0

    for pid, batch_cleaned in cleaned_items_per_batch:
        product = products_map[pid]
        cat = categories_map.get(product.category_id)

        batch = OutwardBatch(
            product_id=product.id,
            shop_id=shop.id,
            bill_number=req.bill_number.strip() if req.bill_number else None,
            delivery_reference=req.delivery_reference.strip() if req.delivery_reference else None,
            transaction_date=req.transaction_date,
            dispatched_by_user_id=current_user.id,
            device_id=device_id,
            quantity=len(batch_cleaned),
            matched_count=0,
            unmatched_count=0,
            flagged_count=0,
            remarks=req.remarks.strip() if req.remarks else None,
        )
        db.add(batch)
        await db.flush()
        created_batches.append(batch)

        line_responses: list[OutwardLineResponse] = []
        matched_cnt = 0
        unmatched_cnt = 0
        flagged_cnt = 0

        for s_text, is_confirmed, u_type in batch_cleaned:
            if s_text not in sn_map:
                # Case 2: Unmatched
                unmatched_cnt += 1
                line = OutwardLine(
                    batch_id=batch.id,
                    serial_text=s_text,
                    serial_number_id=None,
                    product_id=product.id,
                    shop_id=shop.id,
                    transaction_date=req.transaction_date,
                    is_matched=False,
                    is_flagged_for_review=False,
                    flag_reason="Not matched to an inward record (pre-go-live stock)",
                    unit_type=u_type,
                )
                db.add(line)
                await db.flush()

                history = SerialHistory(
                    serial_number_id=None,
                    serial_text=s_text,
                    action=HistoryAction.dispatched_unmatched,
                    from_status=None,
                    to_status=SerialStatus.dispatched,
                    shop_id=shop.id,
                    outward_batch_id=batch.id,
                    is_matched=False,
                    user_id=current_user.id,
                    device_id=device_id,
                    remarks=f"Dispatched (recorded only){f' [{u_type.capitalize()}]' if u_type else ''}",
                )
                db.add(history)

                line_responses.append(
                    OutwardLineResponse(
                        id=line.id,
                        serial_text=s_text,
                        serial_number_id=None,
                        is_matched=False,
                        is_flagged_for_review=False,
                        flag_reason=line.flag_reason,
                        unit_type=u_type,
                        status_label="Recorded only",
                    )
                )
            else:
                sn = sn_map[s_text]
                old_status = sn.status

                if sn.product_id != product.id:
                    # Case 4: Wrong model
                    flagged_cnt += 1
                    sn.status = SerialStatus.dispatched
                    sn.last_shop_id = shop.id

                    line = OutwardLine(
                        batch_id=batch.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        product_id=product.id,
                        shop_id=shop.id,
                        transaction_date=req.transaction_date,
                        is_matched=False,
                        is_flagged_for_review=True,
                        flag_reason=f"Registered under model ID {sn.product_id}",
                        unit_type=u_type or sn.unit_type,
                    )
                    db.add(line)
                    await db.flush()

                    history = SerialHistory(
                        serial_number_id=sn.id,
                        serial_text=s_text,
                        action=HistoryAction.dispatched_flagged,
                        from_status=old_status,
                        to_status=SerialStatus.dispatched,
                        shop_id=shop.id,
                        outward_batch_id=batch.id,
                        is_matched=False,
                        user_id=current_user.id,
                        device_id=device_id,
                        remarks="Dispatched with model mismatch warning (flagged for review)",
                    )
                    db.add(history)

                    line_responses.append(
                        OutwardLineResponse(
                            id=line.id,
                            serial_text=s_text,
                            serial_number_id=sn.id,
                            is_matched=False,
                            is_flagged_for_review=True,
                            flag_reason=line.flag_reason,
                            unit_type=line.unit_type,
                            status_label="Flagged",
                        )
                    )
                elif sn.status != SerialStatus.available:
                    # Case 3: Wrong status
                    flagged_cnt += 1
                    sn.status = SerialStatus.dispatched
                    sn.last_shop_id = shop.id

                    line = OutwardLine(
                        batch_id=batch.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        product_id=product.id,
                        shop_id=shop.id,
                        transaction_date=req.transaction_date,
                        is_matched=False,
                        is_flagged_for_review=True,
                        flag_reason=f"Previous status was '{old_status.value}'",
                        unit_type=u_type or sn.unit_type,
                    )
                    db.add(line)
                    await db.flush()

                    history = SerialHistory(
                        serial_number_id=sn.id,
                        serial_text=s_text,
                        action=HistoryAction.dispatched_flagged,
                        from_status=old_status,
                        to_status=SerialStatus.dispatched,
                        shop_id=shop.id,
                        outward_batch_id=batch.id,
                        is_matched=False,
                        user_id=current_user.id,
                        device_id=device_id,
                        remarks=f"Dispatched with status conflict ('{old_status.value}')",
                    )
                    db.add(history)

                    line_responses.append(
                        OutwardLineResponse(
                            id=line.id,
                            serial_text=s_text,
                            serial_number_id=sn.id,
                            is_matched=False,
                            is_flagged_for_review=True,
                            flag_reason=line.flag_reason,
                            unit_type=line.unit_type,
                            status_label="Flagged",
                        )
                    )
                else:
                    # Case 1: Matched
                    matched_cnt += 1
                    sn.status = SerialStatus.dispatched
                    sn.last_shop_id = shop.id

                    line = OutwardLine(
                        batch_id=batch.id,
                        serial_text=s_text,
                        serial_number_id=sn.id,
                        product_id=product.id,
                        shop_id=shop.id,
                        transaction_date=req.transaction_date,
                        is_matched=True,
                        is_flagged_for_review=False,
                        flag_reason=None,
                        unit_type=u_type or sn.unit_type,
                    )
                    db.add(line)
                    await db.flush()

                    history = SerialHistory(
                        serial_number_id=sn.id,
                        serial_text=s_text,
                        action=HistoryAction.dispatched_matched,
                        from_status=SerialStatus.available,
                        to_status=SerialStatus.dispatched,
                        shop_id=shop.id,
                        outward_batch_id=batch.id,
                        is_matched=True,
                        user_id=current_user.id,
                        device_id=device_id,
                        remarks=None,
                    )
                    db.add(history)

                    line_responses.append(
                        OutwardLineResponse(
                            id=line.id,
                            serial_text=s_text,
                            serial_number_id=sn.id,
                            is_matched=True,
                            is_flagged_for_review=False,
                            flag_reason=None,
                            unit_type=line.unit_type,
                            status_label="Matched",
                        )
                    )

        batch.matched_count = matched_cnt
        batch.unmatched_count = unmatched_cnt
        batch.flagged_count = flagged_cnt

        outward_units_count = (len(batch_cleaned) // 2) if (cat and cat.has_dual_serial) else len(batch_cleaned)
        product.current_stock_qty = product.current_stock_qty - outward_units_count

        total_units_dispatched += len(batch_cleaned)
        total_matched_all += matched_cnt
        total_unmatched_all += unmatched_cnt
        total_flagged_all += flagged_cnt

        created_batch_responses.append(
            OutwardBatchResponse(
                id=batch.id,
                product_id=product.id,
                product_name=product.name,
                brand=product.brand,
                model=product.model,
                shop_id=shop.id,
                shop_name=shop.name,
                shop_city=shop.city,
                bill_number=batch.bill_number,
                delivery_reference=batch.delivery_reference,
                transaction_date=batch.transaction_date,
                quantity=batch.quantity,
                matched_count=batch.matched_count,
                unmatched_count=batch.unmatched_count,
                flagged_count=batch.flagged_count,
                dispatched_by_user_id=current_user.id,
                dispatched_by_name=current_user.full_name,
                device_id=device_id,
                remarks=batch.remarks,
                created_at=batch.created_at,
                lines=line_responses,
            )
        )

    # 12. Create Audit Log for entire multi-batch
    batch_ids_str = [str(b.id) for b in created_batches]
    audit = AuditLog(
        user_id=current_user.id,
        device_id=device_id,
        action="OUTWARD_MULTI_BATCH",
        entity_type="outward_batch",
        entity_id=batch_ids_str[0] if batch_ids_str else None,
        details={
            "client_request_id": req.client_request_id,
            "batch_ids": batch_ids_str,
            "shop_id": str(shop.id),
            "shop_name": shop.name,
            "total_units": total_units_dispatched,
            "total_batches": len(created_batches),
            "delivery_reference": req.delivery_reference,
            "bill_number": req.bill_number,
        },
    )
    db.add(audit)

    # 13. Single Atomic Commit
    await db.commit()

    # 14. Broadcast WebSockets
    for pid in product_ids:
        p = products_map[pid]
        await ws_manager.broadcast("stock_updated", {
            "type": "outward",
            "product_id": str(p.id),
            "current_stock_qty": p.current_stock_qty,
            "delivery_reference": req.delivery_reference,
        })

    return OutwardMultiBatchResponse(
        batches=created_batch_responses,
        total_units=total_units_dispatched,
        total_matched=total_matched_all,
        total_unmatched=total_unmatched_all,
        total_flagged=total_flagged_all,
        bill_number=req.bill_number,
        delivery_reference=req.delivery_reference,
    )


@router.get("/batches", response_model=list[OutwardBatchResponse])
async def list_outward_batches(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    shop_id: Optional[uuid.UUID] = Query(None, description="Filter by shop"),
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    bill_number: Optional[str] = Query(None, description="Filter by bill number"),
    date_from: Optional[date] = Query(None, description="Filter from date"),
    date_to: Optional[date] = Query(None, description="Filter to date"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[OutwardBatchResponse]:
    """
    List outward batches with product, shop, and dispatcher details.
    """
    query = (
        select(
            OutwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            User.full_name.label("dispatcher_name"),
        )
        .join(Product, OutwardBatch.product_id == Product.id)
        .join(Shop, OutwardBatch.shop_id == Shop.id)
        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
        .order_by(OutwardBatch.transaction_date.desc(), OutwardBatch.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    if shop_id:
        query = query.where(OutwardBatch.shop_id == shop_id)
    if product_id:
        query = query.where(OutwardBatch.product_id == product_id)
    if bill_number:
        query = query.where(OutwardBatch.bill_number.ilike(f"%{bill_number.strip()}%"))
    if date_from:
        query = query.where(OutwardBatch.transaction_date >= date_from)
    if date_to:
        query = query.where(OutwardBatch.transaction_date <= date_to)

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for b, p_name, p_brand, p_model, s_name, s_city, u_name in rows:
        responses.append(
            OutwardBatchResponse(
                id=b.id,
                product_id=b.product_id,
                product_name=p_name,
                brand=p_brand,
                model=p_model,
                shop_id=b.shop_id,
                shop_name=s_name,
                shop_city=s_city,
                bill_number=b.bill_number,
                delivery_reference=b.delivery_reference,
                transaction_date=b.transaction_date,
                quantity=b.quantity,
                matched_count=b.matched_count,
                unmatched_count=b.unmatched_count,
                flagged_count=b.flagged_count,
                dispatched_by_user_id=b.dispatched_by_user_id,
                dispatched_by_name=u_name,
                device_id=b.device_id,
                remarks=b.remarks,
                created_at=b.created_at,
                lines=[],
            )
        )
    return responses


@router.get("/batches/{batch_id}", response_model=OutwardBatchResponse)
async def get_outward_batch(
    batch_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OutwardBatchResponse:
    """
    Get a single outward batch with its full list of scanned lines.
    """
    query = (
        select(
            OutwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            User.full_name.label("dispatcher_name"),
        )
        .join(Product, OutwardBatch.product_id == Product.id)
        .join(Shop, OutwardBatch.shop_id == Shop.id)
        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
        .where(OutwardBatch.id == batch_id)
    )
    result = await db.execute(query)
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Outward batch not found.")

    b, p_name, p_brand, p_model, s_name, s_city, u_name = row

    # Fetch lines
    lines_res = await db.execute(
        select(OutwardLine)
        .where(OutwardLine.batch_id == batch_id)
        .order_by(OutwardLine.created_at.asc())
    )
    lines_db = lines_res.scalars().all()

    line_items = []
    for l in lines_db:
        label = "Flagged" if l.is_flagged_for_review else ("Matched" if l.is_matched else "Recorded only")
        line_items.append(
            OutwardLineResponse(
                id=l.id,
                serial_text=l.serial_text,
                serial_number_id=l.serial_number_id,
                is_matched=l.is_matched,
                is_flagged_for_review=l.is_flagged_for_review,
                flag_reason=l.flag_reason,
                unit_type=l.unit_type,
                status_label=label,
            )
        )

    return OutwardBatchResponse(
        id=b.id,
        product_id=b.product_id,
        product_name=p_name,
        brand=p_brand,
        model=p_model,
        shop_id=b.shop_id,
        shop_name=s_name,
        shop_city=s_city,
        bill_number=b.bill_number,
        delivery_reference=b.delivery_reference,
        transaction_date=b.transaction_date,
        quantity=b.quantity,
        matched_count=b.matched_count,
        unmatched_count=b.unmatched_count,
        flagged_count=b.flagged_count,
        dispatched_by_user_id=b.dispatched_by_user_id,
        dispatched_by_name=u_name,
        device_id=b.device_id,
        remarks=b.remarks,
        created_at=b.created_at,
        lines=line_items,
    )


@router.get("/bills", response_model=list[BillListItem])
async def list_outward_bills(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    search: Optional[str] = Query(None, description="Search by bill number or shop name"),
    shop_id: Optional[uuid.UUID] = Query(None, description="Filter by shop"),
    date_from: Optional[date] = Query(None, description="Filter from date"),
    date_to: Optional[date] = Query(None, description="Filter to date"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[BillListItem]:
    """
    List outward dispatches aggregated by Bill Number.
    Allows viewing all models/batches dispatched together under one invoice or bill.
    """
    query = (
        select(
            OutwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            User.full_name.label("dispatcher_name"),
        )
        .join(Product, OutwardBatch.product_id == Product.id)
        .join(Shop, OutwardBatch.shop_id == Shop.id)
        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
        .order_by(OutwardBatch.transaction_date.desc(), OutwardBatch.created_at.desc())
    )

    if search:
        s = f"%{search.strip()}%"
        query = query.where(
            (OutwardBatch.bill_number.ilike(s))
            | (Shop.name.ilike(s))
            | (Shop.city.ilike(s))
            | (OutwardBatch.delivery_reference.ilike(s))
        )
    if shop_id:
        query = query.where(OutwardBatch.shop_id == shop_id)
    if date_from:
        query = query.where(OutwardBatch.transaction_date >= date_from)
    if date_to:
        query = query.where(OutwardBatch.transaction_date <= date_to)

    result = await db.execute(query)
    rows = result.all()

    # Group batches by bill_number (or by batch id if bill_number is missing)
    bills_map: dict[str, dict] = {}
    for b, p_name, p_brand, p_model, s_name, s_city, u_name in rows:
        b_key = (b.bill_number.strip() if b.bill_number else f"NO-BILL-{str(b.id)[:8]}").upper()
        if b_key not in bills_map:
            bills_map[b_key] = {
                "bill_number": b.bill_number or f"REF-{b.delivery_reference or str(b.id)[:8]}",
                "shop_id": b.shop_id,
                "shop_name": s_name,
                "shop_city": s_city,
                "transaction_date": b.transaction_date,
                "created_at": b.created_at,
                "dispatched_by_name": u_name,
                "delivery_reference": b.delivery_reference,
                "remarks": b.remarks,
                "total_units": 0,
                "total_batches": 0,
                "models_summary": [],
            }
        item = bills_map[b_key]
        item["total_units"] += b.quantity
        item["total_batches"] += 1
        summary_str = f"{p_brand} {p_model} ({b.quantity}u)"
        if summary_str not in item["models_summary"]:
            item["models_summary"].append(summary_str)

    bill_list = [BillListItem(**data) for data in bills_map.values()]
    return bill_list[offset : offset + limit]


@router.get("/bills/{bill_number}", response_model=BillDetailResponse)
async def get_outward_bill_detail(
    bill_number: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BillDetailResponse:
    """
    Get all batches and scanned serial lines associated with a specific Bill Number.
    """
    clean_b_num = bill_number.strip()
    query = (
        select(
            OutwardBatch,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            User.full_name.label("dispatcher_name"),
        )
        .join(Product, OutwardBatch.product_id == Product.id)
        .join(Shop, OutwardBatch.shop_id == Shop.id)
        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
        .where(
            (func.lower(OutwardBatch.bill_number) == clean_b_num.lower())
            | (func.lower(OutwardBatch.delivery_reference) == clean_b_num.lower())
        )
        .order_by(OutwardBatch.created_at.asc())
    )
    result = await db.execute(query)
    rows = result.all()
    if not rows:
        raise HTTPException(status_code=404, detail=f"Bill '{bill_number}' not found.")

    first_b, _, _, _, s_name, s_city, u_name = rows[0]

    batch_ids = [b.id for b, _, _, _, _, _, _ in rows]
    lines_res = await db.execute(
        select(OutwardLine)
        .where(OutwardLine.batch_id.in_(batch_ids))
        .order_by(OutwardLine.created_at.asc())
    )
    all_lines = lines_res.scalars().all()
    lines_by_batch: dict[uuid.UUID, list[OutwardLineResponse]] = {}
    for l in all_lines:
        lbl = "Flagged" if l.is_flagged_for_review else ("Matched" if l.is_matched else "Recorded only")
        lines_by_batch.setdefault(l.batch_id, []).append(
            OutwardLineResponse(
                id=l.id,
                serial_text=l.serial_text,
                serial_number_id=l.serial_number_id,
                is_matched=l.is_matched,
                is_flagged_for_review=l.is_flagged_for_review,
                flag_reason=l.flag_reason,
                unit_type=l.unit_type,
                status_label=lbl,
            )
        )

    batch_summaries: list[BillBatchSummary] = []
    total_units = 0
    for b, p_name, p_brand, p_model, _, _, _ in rows:
        total_units += b.quantity
        batch_summaries.append(
            BillBatchSummary(
                batch_id=b.id,
                product_id=b.product_id,
                product_name=p_name,
                brand=p_brand,
                model=p_model,
                quantity=b.quantity,
                matched_count=b.matched_count,
                unmatched_count=b.unmatched_count,
                flagged_count=b.flagged_count,
                lines=lines_by_batch.get(b.id, []),
            )
        )

    return BillDetailResponse(
        bill_number=first_b.bill_number or clean_b_num,
        shop_id=first_b.shop_id,
        shop_name=s_name,
        shop_city=s_city,
        transaction_date=first_b.transaction_date,
        created_at=first_b.created_at,
        dispatched_by_name=u_name,
        delivery_reference=first_b.delivery_reference,
        remarks=first_b.remarks,
        total_units=total_units,
        total_batches=len(rows),
        batches=batch_summaries,
    )