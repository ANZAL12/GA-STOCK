from typing import Annotated, Optional
import uuid
import csv
import io
import json
import openpyxl

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.return_ import Return
from app.models.shop import Shop
from app.models.user import User
from app.schemas.shop import (
    ShopCreate,
    ShopDispatchedSerial,
    ShopExcelColumnsResponse,
    ShopExcelImportResponse,
    ShopResponse,
    ShopUpdate,
)

router = APIRouter(prefix="/shops", tags=["shops"])


@router.get("", response_model=list[ShopResponse])
async def list_shops(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: Optional[str] = Query(None, description="Search query by shop name or city"),
    active_only: bool = Query(True, description="Filter only active shops"),
) -> list[ShopResponse]:
    """
    Search and list shops. Accessible by both admin and staff.
    Includes count of total items dispatched to each shop.
    """
    # Subquery for total items dispatched per shop
    dispatch_count_subq = (
        select(OutwardLine.shop_id, func.count(OutwardLine.id).label("dispatch_count"))
        .group_by(OutwardLine.shop_id)
        .subquery()
    )

    query = (
        select(Shop, func.coalesce(dispatch_count_subq.c.dispatch_count, 0).label("total_dispatched_count"))
        .outerjoin(dispatch_count_subq, Shop.id == dispatch_count_subq.c.shop_id)
        .order_by(Shop.name.asc())
    )

    if active_only:
        query = query.where(Shop.is_active == True)

    if q and q.strip():
        search_term = f"%{q.strip().lower()}%"
        query = query.where(
            or_(
                func.lower(Shop.name).like(search_term),
                func.lower(Shop.city).like(search_term),
            )
        )

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for shop_obj, disp_count in rows:
        resp = ShopResponse.model_validate(shop_obj)
        resp.total_dispatched_count = disp_count
        responses.append(resp)

    return responses


@router.get("/{shop_id}", response_model=ShopResponse)
async def get_shop(
    shop_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ShopResponse:
    """
    Get a single shop's details by ID.
    """
    count_res = await db.execute(
        select(func.count(OutwardLine.id)).where(OutwardLine.shop_id == shop_id)
    )
    total_count = count_res.scalar() or 0

    result = await db.execute(select(Shop).where(Shop.id == shop_id))
    shop_obj = result.scalar_one_or_none()
    if not shop_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = total_count
    return resp


@router.get("/{shop_id}/dispatched-serials", response_model=list[ShopDispatchedSerial])
async def list_shop_dispatched_serials(
    shop_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[ShopDispatchedSerial]:
    """
    List every serial number dispatched to this shop.
    Returns serial, model info, date, delivery ref, and Matched / Recorded only / Flagged tag.
    """
    # Verify shop exists
    shop_res = await db.execute(select(Shop).where(Shop.id == shop_id))
    if not shop_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    query = (
        select(
            OutwardLine.serial_text,
            OutwardLine.product_id,
            Product.name.label("product_name"),
            Product.brand,
            Product.model,
            OutwardLine.transaction_date,
            OutwardBatch.delivery_reference,
            OutwardLine.is_matched,
            OutwardLine.is_flagged_for_review,
        )
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(Product, OutwardLine.product_id == Product.id)
        .where(OutwardLine.shop_id == shop_id)
        .order_by(OutwardLine.transaction_date.desc(), OutwardLine.created_at.desc())
    )

    result = await db.execute(query)
    rows = result.all()

    items = []
    for r in rows:
        if r.is_flagged_for_review:
            label = "Flagged"
        elif r.is_matched:
            label = "Matched"
        else:
            label = "Recorded only"

        items.append(
            ShopDispatchedSerial(
                serial_text=r.serial_text,
                product_id=r.product_id,
                product_name=r.product_name,
                brand=r.brand,
                model=r.model,
                transaction_date=r.transaction_date,
                delivery_reference=r.delivery_reference,
                is_matched=r.is_matched,
                is_flagged_for_review=r.is_flagged_for_review,
                status_label=label,
            )
        )
    return items


@router.post("", response_model=ShopResponse, status_code=status.HTTP_201_CREATED)
async def create_shop(
    req: ShopCreate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ShopResponse:
    """
    Admin only: add a new shop.
    """
    clean_name = req.name.strip()
    clean_city = req.city.strip() if req.city else ""
    clean_phone = req.phone.strip() if req.phone else None

    # Check for duplicate shop name
    existing = await db.execute(
        select(Shop).where(
            func.lower(Shop.name) == clean_name.lower(),
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Shop '{clean_name}' already exists",
        )

    shop_obj = Shop(
        name=clean_name,
        city=clean_city,
        phone=clean_phone,
        is_active=True,
    )
    db.add(shop_obj)
    await db.flush()

    audit = AuditLog(
        user_id=admin.id,
        action="SHOP_CREATED",
        entity_type="shop",
        entity_id=str(shop_obj.id),
        details={"name": shop_obj.name, "city": shop_obj.city, "phone": shop_obj.phone},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(shop_obj)

    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = 0
    await ws_manager.broadcast("shop_created", json.loads(resp.model_dump_json()))
    return resp


@router.put("/{shop_id}", response_model=ShopResponse)
async def update_shop(
    shop_id: uuid.UUID,
    req: ShopUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ShopResponse:
    """
    Admin only: edit shop details including active status.
    """
    result = await db.execute(select(Shop).where(Shop.id == shop_id))
    shop_obj = result.scalar_one_or_none()
    if not shop_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    if req.name is not None:
        shop_obj.name = req.name.strip()
    if req.city is not None:
        shop_obj.city = req.city.strip()
    if req.phone is not None:
        shop_obj.phone = req.phone.strip() if req.phone else None
    if req.is_active is not None:
        shop_obj.is_active = req.is_active

    audit = AuditLog(
        user_id=admin.id,
        action="SHOP_UPDATED",
        entity_type="shop",
        entity_id=str(shop_obj.id),
        details={"name": shop_obj.name, "city": shop_obj.city, "is_active": shop_obj.is_active},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(shop_obj)

    count_res = await db.execute(
        select(func.count(OutwardLine.id)).where(OutwardLine.shop_id == shop_id)
    )
    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = count_res.scalar() or 0
    await ws_manager.broadcast("shop_updated", json.loads(resp.model_dump_json()))
    return resp


@router.patch("/{shop_id}/toggle-active", response_model=ShopResponse)
async def toggle_shop_active(
    shop_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ShopResponse:
    """
    Admin only: toggle shop active/deactivated status.
    """
    result = await db.execute(select(Shop).where(Shop.id == shop_id))
    shop_obj = result.scalar_one_or_none()
    if not shop_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    shop_obj.is_active = not shop_obj.is_active

    audit = AuditLog(
        user_id=admin.id,
        action="SHOP_STATUS_TOGGLED",
        entity_type="shop",
        entity_id=str(shop_obj.id),
        details={"name": shop_obj.name, "is_active": shop_obj.is_active},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(shop_obj)

    count_res = await db.execute(
        select(func.count(OutwardLine.id)).where(OutwardLine.shop_id == shop_id)
    )
    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = count_res.scalar() or 0
    await ws_manager.broadcast("shop_updated", json.loads(resp.model_dump_json()))
    return resp


@router.delete("/{shop_id}", response_model=ShopResponse)
async def delete_shop(
    shop_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    permanent: bool = Query(False, description="Permanently delete from database if no dispatch records exist"),
) -> ShopResponse:
    """
    Admin only: delete or deactivate shop.
    If permanent=True and the shop has 0 outward dispatches or returns, completely deletes it.
    If the shop has dispatch history, soft-deactivates it to protect historical records.
    """
    result = await db.execute(select(Shop).where(Shop.id == shop_id))
    shop_obj = result.scalar_one_or_none()
    if not shop_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shop not found")

    count_res = await db.execute(
        select(func.count(OutwardLine.id)).where(OutwardLine.shop_id == shop_id)
    )
    disp_count = count_res.scalar() or 0

    return_res = await db.execute(
        select(func.count(Return.id)).where(Return.shop_id == shop_id)
    )
    return_count = return_res.scalar() or 0

    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = disp_count

    if permanent:
        if disp_count > 0 or return_count > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot permanently delete '{shop_obj.name}': It has {disp_count} dispatch(es) and {return_count} return(s). Deactivate it instead to preserve transaction records.",
            )

        await db.delete(shop_obj)
        audit = AuditLog(
            user_id=admin.id,
            action="SHOP_PERMANENTLY_DELETED",
            entity_type="shop",
            entity_id=str(shop_id),
            details={"name": shop_obj.name, "city": shop_obj.city},
        )
        db.add(audit)
        await db.commit()
        await ws_manager.broadcast("shop_deleted", {"id": str(shop_id)})
        return resp

    # Soft deactivation
    shop_obj.is_active = False

    audit = AuditLog(
        user_id=admin.id,
        action="SHOP_DEACTIVATED",
        entity_type="shop",
        entity_id=str(shop_obj.id),
        details={"name": shop_obj.name},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(shop_obj)

    resp = ShopResponse.model_validate(shop_obj)
    resp.total_dispatched_count = disp_count
    await ws_manager.broadcast("shop_updated", json.loads(resp.model_dump_json()))
    return resp


@router.delete("/cleanup/unused-deactivated", response_model=dict)
async def cleanup_unused_deactivated_shops(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """
    Admin only: Bulk delete all deactivated shops that have 0 dispatches and 0 returns.
    Cleans up test or dummy shops in one click.
    """
    # Subquery for shops with outward dispatches
    disp_subq = select(OutwardLine.shop_id).distinct()
    return_subq = select(Return.shop_id).distinct()

    query = select(Shop).where(
        Shop.is_active == False,
        ~Shop.id.in_(disp_subq),
        ~Shop.id.in_(return_subq),
    )
    result = await db.execute(query)
    unused_shops = result.scalars().all()

    deleted_count = len(unused_shops)
    for s in unused_shops:
        await db.delete(s)

    if deleted_count > 0:
        audit = AuditLog(
            user_id=admin.id,
            action="BULK_UNUSED_SHOPS_CLEANED",
            entity_type="shop",
            entity_id="bulk",
            details={"deleted_count": deleted_count},
        )
        db.add(audit)
        await db.commit()
        await ws_manager.broadcast("shop_deleted", {"bulk": True})

    return {"message": f"Successfully deleted {deleted_count} unused deactivated shop(s)", "deleted_count": deleted_count}


# ─── EXCEL & CSV SHOP PARSER HELPERS ──────────────────────────────────────────

COMMON_SHOP_KEYWORDS = [
    "shop", "party", "customer", "dealer", "consignee", "buyer",
    "client", "destination", "name", "retailer", "store", "account",
]


def _read_file_rows(file_bytes: bytes, filename: str) -> list[list[str]]:
    rows: list[list[str]] = []
    fname = filename.lower()
    if fname.endswith(".csv"):
        try:
            text = file_bytes.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = file_bytes.decode("latin-1")
        reader = csv.reader(io.StringIO(text))
        for r in reader:
            rows.append([str(c).strip() if c is not None else "" for c in r])
    else:
        wb = openpyxl.load_workbook(io.BytesIO(file_bytes), data_only=True, read_only=True)
        ws = wb.active
        if ws is None:
            raise HTTPException(status_code=400, detail="Excel file does not contain an active worksheet.")
        for r in ws.iter_rows(values_only=True):
            rows.append([str(c).strip() if c is not None else "" for c in r])
    return rows


def _find_header_and_columns(rows: list[list[str]]) -> tuple[int, list[str], Optional[str]]:
    best_row_idx = 0
    best_cols: list[str] = []
    # Scan first 20 rows to find header row with highest number of non-empty cells
    for r_idx in range(min(20, len(rows))):
        row = rows[r_idx]
        non_empty = [c for c in row if c]
        if len(non_empty) > len(best_cols):
            best_cols = non_empty
            best_row_idx = r_idx

    seen = set()
    cleaned_cols = []
    for c in rows[best_row_idx] if best_row_idx < len(rows) else []:
        if c and c.lower() not in seen:
            seen.add(c.lower())
            cleaned_cols.append(c)

    suggested = None
    for kw in COMMON_SHOP_KEYWORDS:
        for c in cleaned_cols:
            if kw in c.lower():
                suggested = c
                break
        if suggested:
            break

    return best_row_idx, cleaned_cols, suggested


def _extract_shops_from_column(
    rows: list[list[str]], header_row_idx: int, target_col: str
) -> tuple[list[str], int]:
    if header_row_idx >= len(rows):
        return [], 0

    header_row = rows[header_row_idx]
    target_idx = None
    target_clean = target_col.strip().lower()

    # Exact match first
    for idx, c in enumerate(header_row):
        if c.strip().lower() == target_clean:
            target_idx = idx
            break

    # Substring match fallback
    if target_idx is None:
        for idx, c in enumerate(header_row):
            if target_clean in c.strip().lower():
                target_idx = idx
                break

    if target_idx is None:
        raise HTTPException(
            status_code=400,
            detail=f"Column '{target_col}' was not found in the uploaded file.",
        )

    ignore_set = {
        "total", "grand total", "sub total", "subtotal", "none",
        "nan", "null", "sum", "average", "count",
    }
    seen_shops = set()
    unique_shops = []
    scanned_rows = 0

    for r_idx in range(header_row_idx + 1, len(rows)):
        row = rows[r_idx]
        if target_idx < len(row):
            scanned_rows += 1
            val = row[target_idx].strip()
            if not val:
                continue
            val_lower = val.lower()
            if val_lower in ignore_set or val_lower.startswith("total"):
                continue
            if val_lower not in seen_shops:
                seen_shops.add(val_lower)
                unique_shops.append(val)

    return unique_shops, scanned_rows


@router.post("/import-excel/preview", response_model=ShopExcelColumnsResponse)
async def preview_excel_columns(
    admin: Annotated[User, Depends(require_admin)],
    file: UploadFile = File(...),
) -> ShopExcelColumnsResponse:
    """
    Admin only: Upload an Excel or CSV file to inspect available columns and preview shop names.
    """
    filename = file.filename or "uploaded.xlsx"
    ext = filename.lower().split(".")[-1]
    if ext not in ["xlsx", "xlsm", "xltx", "xltm", "csv"]:
        raise HTTPException(
            status_code=400,
            detail="Unsupported file format. Please upload an Excel (.xlsx, .xlsm) or .csv file.",
        )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="The uploaded file is empty.")

    try:
        rows = _read_file_rows(content, filename)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read file: {str(e)}")

    if not rows:
        raise HTTPException(status_code=400, detail="No rows found in uploaded file.")

    header_idx, columns, suggested = _find_header_and_columns(rows)
    if not columns:
        raise HTTPException(status_code=400, detail="Could not detect column headers in the file.")

    sample_preview = []
    preview_col = suggested or columns[0]
    try:
        sample_shops, _ = _extract_shops_from_column(rows, header_idx, preview_col)
        sample_preview = sample_shops[:6]
    except Exception:
        pass

    return ShopExcelColumnsResponse(
        filename=filename,
        columns=columns,
        suggested_column=suggested,
        sample_preview=sample_preview,
    )


@router.post("/import-excel", response_model=ShopExcelImportResponse)
async def import_shops_from_excel(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    file: UploadFile = File(...),
    column_name: str = Form(..., description="The exact column header containing shop/party names"),
) -> ShopExcelImportResponse:
    """
    Admin only: Parse unique shops under the specified column from Excel/CSV and add them to the database.
    """
    filename = file.filename or "uploaded.xlsx"
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    rows = _read_file_rows(content, filename)
    header_idx, columns, _ = _find_header_and_columns(rows)
    unique_shops, scanned_count = _extract_shops_from_column(rows, header_idx, column_name)

    if not unique_shops:
        raise HTTPException(
            status_code=400,
            detail=f"No shop names found under column '{column_name}'.",
        )

    # Fetch existing shops to avoid duplicates
    existing_res = await db.execute(select(Shop.name))
    existing_set = {s.lower() for s in existing_res.scalars().all()}

    newly_created: list[str] = []
    already_existing: list[str] = []

    for shop_name in unique_shops:
        if shop_name.lower() in existing_set:
            already_existing.append(shop_name)
        else:
            new_shop = Shop(
                name=shop_name,
                city=None,
                phone=None,
                is_active=True,
            )
            db.add(new_shop)
            existing_set.add(shop_name.lower())
            newly_created.append(shop_name)

    if newly_created:
        audit = AuditLog(
            user_id=admin.id,
            action="EXCEL_SHOPS_IMPORTED",
            entity_type="shop",
            entity_id="bulk",
            details={
                "column_used": column_name,
                "created_count": len(newly_created),
                "created_shops": newly_created[:50],
            },
        )
        db.add(audit)
        await db.commit()
        await ws_manager.broadcast("shop_created", {"bulk": True, "count": len(newly_created)})

    return ShopExcelImportResponse(
        column_used=column_name,
        total_rows_scanned=scanned_count,
        unique_shops_found=len(unique_shops),
        newly_created_count=len(newly_created),
        already_existing_count=len(already_existing),
        new_shops=newly_created,
        existing_shops=already_existing,
    )