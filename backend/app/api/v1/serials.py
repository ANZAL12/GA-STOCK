import csv
from datetime import date
import io
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
import openpyxl
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.category import Category
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.return_ import Return
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.serial_status import (
    BulkSerialCheckRequest,
    BulkSerialCheckResponse,
    ExcelSerialImportItem,
    ExcelSerialImportRequest,
    ExcelSerialImportResponse,
    ExcelSerialPreviewResponse,
    ExistingSerialInfo,
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
            OutwardBatch.bill_number.label("outward_bill_no"),
            OutwardBatch.delivery_reference.label("outward_ref"),
            OutwardLine.created_at.label("outward_created_at"),
            OutwardLine.unit_type.label("outward_unit_type"),
            OutwardLine.is_flagged_for_review.label("outward_is_flagged"),
            OutwardLine.flag_reason.label("outward_flag_reason"),
            Shop.name.label("outward_shop_name"),
            Shop.city.label("outward_shop_city"),
        )
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .distinct(OutwardLine.serial_number_id)
        .order_by(OutwardLine.serial_number_id, OutwardLine.created_at.desc())
        .subquery()
    )

    # 1b. Latest inward batch subquery per serial (prevents Cartesian product when inwarded/returned multiple times)
    inward_subq = (
        select(
            InwardLine.serial_number_id,
            InwardBatch.transaction_date.label("inward_date"),
            InwardBatch.invoice_reference.label("inward_ref"),
            InwardBatch.inward_type.label("inward_type"),
            InwardLine.created_at.label("inward_created_at"),
        )
        .join(InwardBatch, InwardLine.batch_id == InwardBatch.id)
        .distinct(InwardLine.serial_number_id)
        .order_by(InwardLine.serial_number_id, InwardLine.created_at.desc())
        .subquery()
    )

    # 1c. Damaged history lookup (serials with damaged history/remarks)
    damaged_hist_query = (
        select(SerialHistory.serial_number_id, func.lower(SerialHistory.serial_text))
        .where(
            or_(
                SerialHistory.from_status == SerialStatus.damaged,
                SerialHistory.to_status == SerialStatus.damaged,
                func.lower(SerialHistory.remarks).contains("damage"),
            )
        )
        .distinct()
    )
    damaged_hist_rows = (await db.execute(damaged_hist_query)).all()
    damaged_sn_ids = {row[0] for row in damaged_hist_rows if row[0] is not None}
    damaged_sn_texts = {row[1] for row in damaged_hist_rows if row[1]}

    # 2. Tracked serial numbers query
    tracked_query = (
        select(
            SerialNumber.id.label("sn_id"),
            SerialNumber.serial_number.label("sn_text"),
            SerialNumber.status.label("sn_status"),
            SerialNumber.unit_type.label("sn_unit_type"),
            SerialNumber.created_at.label("sn_created_at"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            inward_subq.c.inward_date,
            inward_subq.c.inward_ref,
            inward_subq.c.inward_type,
            outward_subq.c.outward_date,
            outward_subq.c.outward_bill_no,
            outward_subq.c.outward_ref,
            outward_subq.c.outward_created_at,
            outward_subq.c.outward_unit_type,
            outward_subq.c.outward_is_flagged,
            outward_subq.c.outward_flag_reason,
            outward_subq.c.outward_shop_name,
            outward_subq.c.outward_shop_city,
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Category, Product.category_id == Category.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .outerjoin(inward_subq, inward_subq.c.serial_number_id == SerialNumber.id)
        .outerjoin(outward_subq, outward_subq.c.serial_number_id == SerialNumber.id)
        .order_by(SerialNumber.created_at.desc())
    )
    tracked_rows = (await db.execute(tracked_query)).all()

    items: list[SerialListItem] = []
    seen_serials = set()

    for r in tracked_rows:
        if r.sn_text.lower() in seen_serials:
            continue
        seen_serials.add(r.sn_text.lower())
        is_dispatched = (r.sn_status == SerialStatus.dispatched)
        flow_type = "outward" if is_dispatched else "inward"

        has_dmg_hist = (r.sn_id in damaged_sn_ids) or (r.sn_text.lower() in damaged_sn_texts)
        is_inward_dmg = (r.inward_type == "damaged")
        is_currently_dmg = (r.sn_status == SerialStatus.damaged)
        outward_flag_r = r.outward_flag_reason or ""
        outward_had_dmg = ("damage" in outward_flag_r.lower()) or (is_dispatched and (has_dmg_hist or is_inward_dmg))

        is_damaged = is_currently_dmg or is_inward_dmg or outward_had_dmg or has_dmg_hist
        is_dispatched_damaged = is_dispatched and is_damaged
        flag_r = r.outward_flag_reason if is_dispatched else None
        if not flag_r and is_dispatched_damaged:
            flag_r = "Product was damaged prior to or during dispatch"

        if is_dispatched:
            s_label = "Dispatched"
            t_date = r.outward_date or (r.sn_created_at.date() if r.sn_created_at else None)
            ts = r.outward_created_at or r.sn_created_at
            bill_no = (r.outward_bill_no or "").strip() or None
            deliv_ref = (r.outward_ref or "").strip() or None
            # Prioritize bill number as the reference for dispatched, otherwise delivery/vehicle ref
            ref = bill_no if bill_no else deliv_ref
            s_name = r.outward_shop_name or r.shop_name
            s_city = r.outward_shop_city or r.shop_city
        else:
            s_label = r.sn_status.value.replace("_", " ").title()
            t_date = r.inward_date or (r.sn_created_at.date() if r.sn_created_at else None)
            ts = r.sn_created_at
            bill_no = None
            deliv_ref = None
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
                bill_number=bill_no,
                delivery_reference=deliv_ref,
                is_matched=True,
                unit_type=r.sn_unit_type or r.outward_unit_type,
                is_damaged=is_damaged,
                is_dispatched_damaged=is_dispatched_damaged,
                flag_reason=flag_r,
            )
        )

    # 3. Unmatched outward lines (pre-go-live dispatches not in serial_numbers)
    unm_query = (
        select(
            OutwardLine.serial_text.label("serial_text"),
            OutwardLine.created_at.label("created_at"),
            OutwardLine.transaction_date.label("outward_date"),
            OutwardLine.unit_type.label("unit_type"),
            OutwardLine.is_flagged_for_review.label("outward_is_flagged"),
            OutwardLine.flag_reason.label("outward_flag_reason"),
            Product.name.label("prod_name"),
            Product.brand.label("prod_brand"),
            Product.model.label("prod_model"),
            Category.name.label("cat_name"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            OutwardBatch.bill_number.label("outward_bill_no"),
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
        bill_no = (r.outward_bill_no or "").strip() or None
        deliv_ref = (r.outward_ref or "").strip() or None
        ref = bill_no if bill_no else deliv_ref
        flag_r = r.outward_flag_reason or ""
        has_dmg_hist = r.serial_text.lower() in damaged_sn_texts
        unm_damaged = ("damage" in flag_r.lower()) or has_dmg_hist

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
                reference=ref,
                bill_number=bill_no,
                delivery_reference=deliv_ref,
                is_matched=False,
                unit_type=r.unit_type,
                is_damaged=unm_damaged,
                is_dispatched_damaged=unm_damaged,
                flag_reason=flag_r if unm_damaged else None,
            )
        )

    # 4. Filter by flow type
    if flow == "inward":
        items = [i for i in items if i.flow_type == "inward"]
    elif flow == "outward":
        items = [i for i in items if i.flow_type == "outward"]
    elif flow == "damaged":
        items = [i for i in items if i.is_damaged or i.status in ("damaged", "under_repair", "lost")]

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
            or (i.bill_number and term in i.bill_number.lower())
            or (i.delivery_reference and term in i.delivery_reference.lower())
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

        disp_unit_type = sn.unit_type
        if not disp_unit_type:
            ol_res = await db.execute(
                select(OutwardLine.unit_type)
                .where(OutwardLine.serial_number_id == sn.id, OutwardLine.unit_type.isnot(None))
                .order_by(OutwardLine.created_at.desc())
            )
            disp_unit_type = ol_res.scalars().first()

        is_currently_dmg = (sn.status == SerialStatus.damaged)
        has_dmg_hist = any(
            h.from_status == SerialStatus.damaged
            or h.to_status == SerialStatus.damaged
            or (h.remarks and "damage" in h.remarks.lower())
            for h in history_items
        )
        is_dispatched = (sn.status == SerialStatus.dispatched)
        is_damaged = is_currently_dmg or has_dmg_hist
        is_dispatched_damaged = is_dispatched and is_damaged

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
            unit_type=disp_unit_type,
            last_shop_id=s_id,
            last_shop_name=s_name,
            last_shop_city=s_city,
            status_label=status_label,
            history=history_items,
            is_damaged=is_damaged,
            is_dispatched_damaged=is_dispatched_damaged,
            flag_reason="Product marked as damaged" if is_damaged else None,
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

        unm_has_dmg = any(
            h.from_status == SerialStatus.damaged
            or h.to_status == SerialStatus.damaged
            or (h.remarks and "damage" in h.remarks.lower())
            for h in history_items
        ) or (line.flag_reason and "damage" in line.flag_reason.lower())

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
            unit_type=line.unit_type,
            last_shop_id=s_id,
            last_shop_name=s_name,
            last_shop_city=s_city,
            status_label="Recorded only",
            history=history_items,
            is_damaged=unm_has_dmg,
            is_dispatched_damaged=unm_has_dmg,
            flag_reason=line.flag_reason if unm_has_dmg else None,
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

    # Real-time WebSocket broadcast so connected tablets/clients update immediately
    await ws_manager.broadcast("serial_updated", {
        "serial": sn.serial_number,
        "product_id": str(sn.product_id),
        "status": req.new_status.value,
        "is_damaged": (req.new_status == SerialStatus.damaged),
        "is_dispatched": (req.new_status == SerialStatus.dispatched),
    })
    await ws_manager.broadcast("stock_updated", {"product_id": str(sn.product_id)})

    # Re-fetch for response
    return await lookup_serial(serial_number=sn.serial_number, current_user=current_user, db=db)


# ─── EXCEL & CSV SERIAL PARSER HELPERS ──────────────────────────────────────

COMMON_SERIAL_KEYWORDS = [
    "serial", "sr", "sn", "s/n", "barcode", "imei", "chassis", "serial_no",
    "serial_number", "serialno", "serialnumber", "tag", "qr", "uid",
]
COMMON_MODEL_KEYWORDS = [
    "model", "model_no", "model_number", "modelno", "modelnumber", "item", "product", "sku", "appliance", "item_name", "product_name",
]
COMMON_BRAND_KEYWORDS = [
    "brand", "make", "mfg", "manufacturer", "company",
]
COMMON_UNIT_TYPE_KEYWORDS = [
    "unit", "unit_type", "type", "indoor", "outdoor", "idu", "odu",
]


def _read_excel_sheets_and_rows(file_bytes: bytes, filename: str, target_sheet: Optional[str] = None):
    fname = filename.lower()
    sheet_names: list[str] = []
    selected_sheet = "Sheet1"
    rows: list[list[str]] = []

    if fname.endswith(".csv"):
        sheet_names = ["CSV"]
        selected_sheet = "CSV"
        try:
            text = file_bytes.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = file_bytes.decode("latin-1")
        reader = csv.reader(io.StringIO(text))
        for r in reader:
            rows.append([str(c).strip() if c is not None else "" for c in r])
    else:
        wb = openpyxl.load_workbook(io.BytesIO(file_bytes), data_only=True, read_only=True)
        sheet_names = wb.sheetnames
        if not sheet_names:
            raise HTTPException(status_code=400, detail="Excel file does not contain any sheets.")
        selected_sheet = target_sheet if (target_sheet and target_sheet in sheet_names) else sheet_names[0]
        ws = wb[selected_sheet]
        for r in ws.iter_rows(values_only=True):
            rows.append([str(c).strip() if c is not None else "" for c in r])
        wb.close()

    return sheet_names, selected_sheet, rows


def _find_sheet_header_and_columns(rows: list[list[str]]) -> tuple[int, list[str]]:
    best_row_idx = 0
    best_cols: list[str] = []
    for r_idx in range(min(25, len(rows))):
        row = rows[r_idx]
        non_empty = [c for c in row if c]
        if len(non_empty) > len(best_cols):
            best_cols = non_empty
            best_row_idx = r_idx

    seen = set()
    cleaned_cols = []
    header_row = rows[best_row_idx] if best_row_idx < len(rows) else []
    for idx, c in enumerate(header_row):
        col_name = c.strip() if c else f"Column {idx + 1}"
        if col_name.lower() not in seen:
            seen.add(col_name.lower())
            cleaned_cols.append(col_name)
        else:
            cleaned_cols.append(f"{col_name} ({idx + 1})")

    return best_row_idx, cleaned_cols


def _suggest_column(columns: list[str], keywords: list[str]) -> Optional[str]:
    for kw in keywords:
        for c in columns:
            if kw == c.lower() or kw in c.lower():
                return c
    return None


@router.post("/check-bulk", response_model=BulkSerialCheckResponse)
async def check_bulk_serials(
    req: BulkSerialCheckRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BulkSerialCheckResponse:
    """
    Check a list of serial numbers against the database in a single query.
    Returns existing serial details (model, brand, status) and count of new vs existing serials.
    Checks globally across the database irrespective of which product/model is selected.
    """
    input_serials = req.serials or req.serial_numbers or []
    raw_serials = [s.strip().upper() for s in input_serials if s and s.strip()]
    if not raw_serials:
        return BulkSerialCheckResponse(existing={}, existing_count=0, new_count=0, results=[])

    # 1. Check SerialNumber table (irrespective of product/model)
    sn_query = (
        select(SerialNumber, Product.name, Product.brand, Product.model)
        .join(Product, SerialNumber.product_id == Product.id)
        .where(SerialNumber.serial_number.in_(raw_serials))
    )
    sn_rows = (await db.execute(sn_query)).all()
    existing_map: dict[str, ExistingSerialInfo] = {}

    for sn, p_name, p_brand, p_model in sn_rows:
        existing_map[sn.serial_number] = ExistingSerialInfo(
            serial_number=sn.serial_number,
            product_id=sn.product_id,
            product_name=p_name,
            brand=p_brand,
            model=p_model,
            status=sn.status.value,
            status_label="Available in Godown" if sn.status == SerialStatus.available else sn.status.value.capitalize(),
            unit_type=sn.unit_type,
            exists=True,
        )

    # 2. Check OutwardLine for unmatched outwards (irrespective of product/model)
    unmatched_query = (
        select(OutwardLine.serial_text, OutwardLine.product_id, Product.name, Product.brand, Product.model, OutwardLine.unit_type)
        .join(Product, OutwardLine.product_id == Product.id)
        .where(OutwardLine.serial_text.in_(raw_serials))
    )
    out_rows = (await db.execute(unmatched_query)).all()
    for s_text, p_id, p_name, p_brand, p_model, u_type in out_rows:
        if s_text not in existing_map:
            existing_map[s_text] = ExistingSerialInfo(
                serial_number=s_text,
                product_id=p_id,
                product_name=p_name,
                brand=p_brand,
                model=p_model,
                status="dispatched",
                status_label="Previously Dispatched",
                unit_type=u_type,
                exists=True,
            )

    unique_input_count = len(set(raw_serials))
    results_list = list(existing_map.values())
    return BulkSerialCheckResponse(
        existing=existing_map,
        existing_count=len(existing_map),
        new_count=max(0, unique_input_count - len(existing_map)),
        results=results_list,
    )


@router.post("/import-bulk", response_model=ExcelSerialImportResponse, status_code=status.HTTP_201_CREATED)
async def import_bulk_serials(
    req: ExcelSerialImportRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ExcelSerialImportResponse:
    """
    Admin only: Import serial numbers into inventory under their specified products.
    Creates SerialNumber records, InwardBatch, InwardLines, updates running product stock,
    and logs audit entries. All serials are converted to UPPERCASE.
    """
    if not req.items:
        raise HTTPException(status_code=400, detail="No serial items provided for import.")

    # 1. Clean, uppercase, and deduplicate within payload
    seen_in_payload: set[str] = set()
    cleaned_items: list[ExcelSerialImportItem] = []
    skipped_invalid: list[dict[str, Any]] = []

    # Cache model name to product_id if needed
    model_name_map: dict[str, uuid.UUID] = {}
    if any(it.model_name and not it.product_id for it in req.items):
        all_prods_res = await db.execute(select(Product.id, Product.model, Product.name))
        for p_id, p_model, p_name in all_prods_res.all():
            model_name_map[p_model.strip().upper()] = p_id
            model_name_map[p_name.strip().upper()] = p_id

    for it in req.items:
        sn_clean = it.serial_number.strip().upper()
        if not sn_clean:
            continue

        prod_id = it.product_id or req.default_product_id
        if not prod_id and it.model_name:
            prod_id = model_name_map.get(it.model_name.strip().upper())

        if not prod_id:
            skipped_invalid.append({
                "serial_number": sn_clean,
                "reason": "No product model specified or matched",
            })
            continue

        if sn_clean not in seen_in_payload:
            seen_in_payload.add(sn_clean)
            cleaned_items.append(ExcelSerialImportItem(
                serial_number=sn_clean,
                product_id=prod_id,
                unit_type=it.unit_type.strip().lower() if it.unit_type else None,
            ))

    if not cleaned_items and not skipped_invalid:
        raise HTTPException(status_code=400, detail="All provided serial numbers were blank.")

    all_serials = [it.serial_number for it in cleaned_items]

    # 2. Check existing serials in DB (globally, irrespective of model)
    existing_sn_res = await db.execute(
        select(SerialNumber.serial_number).where(SerialNumber.serial_number.in_(all_serials))
    )
    existing_sn_set = {s.upper() for s in existing_sn_res.scalars().all()}

    existing_out_res = await db.execute(
        select(OutwardLine.serial_text).where(OutwardLine.serial_text.in_(all_serials))
    )
    existing_out_set = {s.upper() for s in existing_out_res.scalars().all()}

    all_existing = existing_sn_set | existing_out_set

    if not req.skip_existing and all_existing:
        sample_conflicts = list(all_existing)[:5]
        raise HTTPException(
            status_code=400,
            detail=f"{len(all_existing)} serial(s) already exist in database (e.g. {', '.join(sample_conflicts)}). Enable 'Skip existing' to bypass them.",
        )

    to_import = [it for it in cleaned_items if it.serial_number not in all_existing]
    skipped_existing = [it.serial_number for it in cleaned_items if it.serial_number in all_existing]

    if not to_import:
        return ExcelSerialImportResponse(
            total_submitted=len(req.items),
            total_processed=len(req.items),
            imported_count=0,
            skipped_existing_count=len(skipped_existing),
            skipped_invalid_count=len(skipped_invalid),
            skipped_serials=skipped_existing + [s["serial_number"] for s in skipped_invalid],
            imported_serials=[],
            products_updated=[],
            inward_batch_ids=[],
            message="No new serials to import; all submitted serials already exist in the database or had unassigned models.",
        )

    # 3. Group by product_id
    items_by_product: dict[uuid.UUID, list[ExcelSerialImportItem]] = {}
    for it in to_import:
        if it.product_id:
            items_by_product.setdefault(it.product_id, []).append(it)

    products_updated = []
    imported_all: list[str] = []
    created_batch_ids: list[str] = []
    batch_ref = (req.batch_reference or req.inward_reference or "EXCEL_IMPORT").strip().upper()
    remarks_text = req.remarks or f"Excel import: {len(to_import)} serials"

    for prod_id, p_items in items_by_product.items():
        prod_res = await db.execute(
            select(Product).where(Product.id == prod_id).with_for_update()
        )
        product = prod_res.scalar_one_or_none()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {prod_id} not found.")

        # Check category for dual serial
        cat_res = await db.execute(select(Category).where(Category.id == product.category_id))
        cat = cat_res.scalar_one_or_none()
        has_dual = cat.has_dual_serial if cat else False

        units_count = (len(p_items) // 2) if has_dual else len(p_items)
        if units_count == 0 and has_dual:
            units_count = len(p_items)  # fallback if odd/single unit uploaded for dual model

        # Create InwardBatch for audit and godown records
        batch = InwardBatch(
            product_id=product.id,
            inward_type="stock_in",
            transaction_date=date.today(),
            invoice_reference=batch_ref,
            quantity=units_count,
            received_by_user_id=admin.id,
            remarks=remarks_text,
        )
        db.add(batch)
        await db.flush()
        created_batch_ids.append(str(batch.id))

        for it in p_items:
            sn_obj = SerialNumber(
                serial_number=it.serial_number,
                product_id=product.id,
                status=SerialStatus.available,
                last_shop_id=None,
                unit_type=it.unit_type,
            )
            db.add(sn_obj)
            await db.flush()

            line = InwardLine(
                batch_id=batch.id,
                serial_number_id=sn_obj.id,
            )
            db.add(line)

            history = SerialHistory(
                serial_number_id=sn_obj.id,
                serial_text=it.serial_number,
                action=HistoryAction.inward_recorded,
                from_status=None,
                to_status=SerialStatus.available,
                inward_batch_id=batch.id,
                user_id=admin.id,
                remarks=f"Excel Import [{batch_ref}]: Added to godown stock",
            )
            db.add(history)
            imported_all.append(it.serial_number)

        # Update product current stock count
        product.current_stock_qty += units_count
        product.has_had_inward = True

        products_updated.append({
            "product_id": str(product.id),
            "product_name": product.name,
            "brand": product.brand,
            "model": product.model,
            "new_stock_qty": product.current_stock_qty,
            "new_stock": product.current_stock_qty,
            "added_count": units_count,
            "units_added": units_count,
        })

    # 4. Audit Log
    audit = AuditLog(
        user_id=admin.id,
        action="SERIALS_EXCEL_IMPORTED",
        entity_type="inward_batch",
        entity_id=str(products_updated[0]["product_id"]) if products_updated else "bulk",
        details={
            "batch_reference": batch_ref,
            "imported_count": len(imported_all),
            "skipped_count": len(skipped_existing),
            "products_count": len(products_updated),
            "sample_serials": imported_all[:10],
        },
    )
    db.add(audit)
    await db.commit()

    # 5. Real-time WebSocket Broadcasts
    for pu in products_updated:
        await ws_manager.broadcast("stock_updated", {"product_id": pu["product_id"]})
    await ws_manager.broadcast("serial_created", {"count": len(imported_all), "bulk": True})

    msg = f"Successfully imported {len(imported_all)} serial number(s) across {len(products_updated)} product model(s)."
    if skipped_existing:
        msg += f" Skipped {len(skipped_existing)} duplicate(s) already in database."

    return ExcelSerialImportResponse(
        total_submitted=len(req.items),
        total_processed=len(req.items),
        imported_count=len(imported_all),
        skipped_existing_count=len(skipped_existing),
        skipped_invalid_count=len(skipped_invalid),
        skipped_serials=skipped_existing + [s["serial_number"] for s in skipped_invalid],
        imported_serials=imported_all,
        products_updated=products_updated,
        inward_batch_ids=created_batch_ids,
        message=msg,
    )


@router.post("/import-excel/preview", response_model=ExcelSerialPreviewResponse)
async def preview_excel_file(
    admin: Annotated[User, Depends(require_admin)],
    file: UploadFile = File(...),
    sheet_name: Optional[str] = Form(None),
) -> ExcelSerialPreviewResponse:
    """
    Admin only: Upload an Excel (.xlsx, .xlsm) or CSV file to inspect sheet tabs,
    column headers, suggested column mapping, and preview the first 10 rows.
    """
    filename = file.filename or "uploaded.xlsx"
    ext = filename.lower().split(".")[-1]
    if ext not in ["xlsx", "xlsm", "xltx", "xltm", "csv"]:
        raise HTTPException(
            status_code=400,
            detail="Unsupported format. Please upload an Excel (.xlsx, .xlsm) or .csv file.",
        )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    try:
        sheet_names, selected_sheet, rows = _read_excel_sheets_and_rows(content, filename, sheet_name)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse file: {str(e)}")

    if not rows:
        raise HTTPException(status_code=400, detail="No rows found in uploaded sheet.")

    header_idx, columns = _find_sheet_header_and_columns(rows)
    if not columns:
        raise HTTPException(status_code=400, detail="Could not detect column headers in the file.")

    suggested_serial = _suggest_column(columns, COMMON_SERIAL_KEYWORDS)
    suggested_model = _suggest_column(columns, COMMON_MODEL_KEYWORDS)
    suggested_brand = _suggest_column(columns, COMMON_BRAND_KEYWORDS)
    suggested_unit = _suggest_column(columns, COMMON_UNIT_TYPE_KEYWORDS)

    sample_rows = []
    for r_idx in range(header_idx + 1, min(header_idx + 11, len(rows))):
        row = rows[r_idx]
        row_dict = {}
        for c_idx, col_name in enumerate(columns):
            row_dict[col_name] = row[c_idx] if c_idx < len(row) else ""
        if any(row_dict.values()):
            sample_rows.append(row_dict)

    data_rows_count = max(0, len(rows) - header_idx - 1)

    return ExcelSerialPreviewResponse(
        filename=filename,
        sheet_names=sheet_names,
        selected_sheet=selected_sheet,
        columns=columns,
        suggested_serial_column=suggested_serial,
        suggested_model_column=suggested_model,
        suggested_brand_column=suggested_brand,
        suggested_unit_type_column=suggested_unit,
        total_rows=data_rows_count,
        sample_rows=sample_rows,
    )


@router.delete("/{serial_id}")
async def delete_serial(
    serial_id: str,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Admin only: permanently delete a scanned serial number.
    Reconciles product stock count, removes inward references, and audits the deletion.
    """
    if serial_id.startswith("outward_"):
        outward_uuid = uuid.UUID(serial_id.replace("outward_", ""))
        line_res = await db.execute(
            select(OutwardLine).where(OutwardLine.id == outward_uuid).with_for_update()
        )
        outward_line = line_res.scalar_one_or_none()
        if not outward_line:
            raise HTTPException(status_code=404, detail="Outward serial record not found.")

        prod_res = await db.execute(
            select(Product).where(Product.id == outward_line.product_id).with_for_update()
        )
        product = prod_res.scalar_one_or_none()

        deleted_text = outward_line.serial_text
        product_id_str = str(outward_line.product_id)

        # Restore stock if this outward was deducted
        if product:
            product.current_stock_qty += 1

        await db.delete(outward_line)

        audit = AuditLog(
            user_id=admin.id,
            action="SERIAL_DELETED",
            entity_type="outward_line",
            entity_id=str(outward_uuid),
            details={"serial": deleted_text, "product_id": product_id_str},
        )
        db.add(audit)
        await db.commit()

        await ws_manager.broadcast("stock_updated", {"product_id": product_id_str})
        await ws_manager.broadcast("serial_deleted", {"serial_id": serial_id, "serial": deleted_text})

        return {
            "success": True,
            "message": f"Serial '{deleted_text}' deleted successfully.",
            "product_id": product_id_str,
            "current_stock_qty": product.current_stock_qty if product else 0,
        }

    # Standard tracked serial number
    try:
        sn_uuid = uuid.UUID(serial_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid serial ID format.")

    sn_res = await db.execute(
        select(SerialNumber).where(SerialNumber.id == sn_uuid).with_for_update()
    )
    sn = sn_res.scalar_one_or_none()
    if not sn:
        raise HTTPException(status_code=404, detail="Serial number not found.")

    prod_res = await db.execute(
        select(Product).where(Product.id == sn.product_id).with_for_update()
    )
    product = prod_res.scalar_one_or_none()

    deleted_text = sn.serial_number
    product_id_str = str(sn.product_id)
    was_available = (sn.status == SerialStatus.available)

    # 1. Delete inward lines referencing this serial
    inward_lines_res = await db.execute(
        select(InwardLine).where(InwardLine.serial_number_id == sn.id)
    )
    for inl in inward_lines_res.scalars().all():
        batch_res = await db.execute(select(InwardBatch).where(InwardBatch.id == inl.batch_id))
        batch = batch_res.scalar_one_or_none()
        if batch:
            batch.quantity = max(0, batch.quantity - 1)
        await db.delete(inl)

    # 2. Nullify outward lines referencing this serial
    outward_lines_res = await db.execute(
        select(OutwardLine).where(OutwardLine.serial_number_id == sn.id)
    )
    for outl in outward_lines_res.scalars().all():
        outl.serial_number_id = None
        outl.is_matched = False

    # 3. Delete serial history entries
    history_res = await db.execute(
        select(SerialHistory).where(SerialHistory.serial_number_id == sn.id)
    )
    for h in history_res.scalars().all():
        await db.delete(h)

    # 4. Nullify returns referencing this serial
    returns_res = await db.execute(
        select(Return).where(Return.serial_number_id == sn.id)
    )
    for ret in returns_res.scalars().all():
        ret.serial_number_id = None

    # 5. Decrement current stock if this serial was available
    if product and was_available:
        product.current_stock_qty = max(0, product.current_stock_qty - 1)

    # 6. Delete the serial number record
    await db.delete(sn)

    # 7. Audit log
    audit = AuditLog(
        user_id=admin.id,
        action="SERIAL_DELETED",
        entity_type="serial_number",
        entity_id=str(sn_uuid),
        details={
            "serial": deleted_text,
            "product_id": product_id_str,
            "product_name": product.name if product else None,
            "was_status": sn.status.value,
        },
    )
    db.add(audit)
    await db.commit()

    await ws_manager.broadcast("stock_updated", {"product_id": product_id_str})
    await ws_manager.broadcast("serial_deleted", {"serial_id": str(sn_uuid), "serial": deleted_text})

    return {
        "success": True,
        "message": f"Serial number '{deleted_text}' deleted successfully.",
        "product_id": product_id_str,
        "current_stock_qty": product.current_stock_qty if product else 0,
    }