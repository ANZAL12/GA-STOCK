from datetime import date, datetime, timezone
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.database import get_db
from app.models.category import Category
from app.models.device import Device
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.reports import (
    NeedsAttentionPills,
    OverviewSummaryResponse,
    StockByModelItem,
    TodayTimelineItem,
)
from app.services.exporter import export_to_csv, export_to_excel, export_to_pdf

router = APIRouter(prefix="/reports", tags=["reports"])


def create_export_response(
    export_format: str,
    title: str,
    subtitle: str,
    headers: list[str],
    rows: list[list],
    filename_base: str,
) -> Response:
    if export_format == "csv":
        data = export_to_csv(headers, rows)
        return Response(
            content=data,
            media_type="text/csv",
            headers={"Content-Disposition": f"attachment; filename={filename_base}.csv"},
        )
    elif export_format == "xlsx":
        data = export_to_excel(title, headers, rows)
        return Response(
            content=data,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename={filename_base}.xlsx"},
        )
    elif export_format == "pdf":
        data = export_to_pdf(title, subtitle, headers, rows)
        return Response(
            content=data,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename_base}.pdf"},
        )
    else:
        raise HTTPException(status_code=400, detail="Invalid export format. Must be 'csv', 'xlsx', or 'pdf'.")


@router.get("/overview", response_model=OverviewSummaryResponse)
async def get_overview(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OverviewSummaryResponse:
    """
    Top metrics for web dashboard:
    - Large headline: items currently on shelves + total received since go-live
    - Today pills: In today, Out today, Recorded only today
    - Bottom 'Needs attention' pills
    """
    today = date.today()

    # 1. Total available tracked on shelves
    res_avail = await db.execute(
        select(func.count(SerialNumber.id)).where(SerialNumber.status == SerialStatus.available)
    )
    tracked_on_shelves = res_avail.scalar() or 0

    # 2. Total received since go-live
    res_rec = await db.execute(select(func.count(SerialNumber.id)))
    received_since_golive = res_rec.scalar() or 0

    # 3. Inward today
    res_in_today = await db.execute(
        select(func.coalesce(func.sum(InwardBatch.quantity), 0)).where(InwardBatch.transaction_date == today)
    )
    inward_today = res_in_today.scalar() or 0

    # 4. Outward today (total)
    res_out_today = await db.execute(
        select(func.coalesce(func.sum(OutwardBatch.quantity), 0)).where(OutwardBatch.transaction_date == today)
    )
    outward_today = res_out_today.scalar() or 0

    # 5. Recorded only today (unmatched old stock today)
    res_unm_today = await db.execute(
        select(func.coalesce(func.sum(OutwardBatch.unmatched_count), 0)).where(OutwardBatch.transaction_date == today)
    )
    recorded_only_today = res_unm_today.scalar() or 0

    # 6. Needs attention items
    # Out of stock models (where current_stock_qty == 0 AND has_had_inward == True)
    res_oos = await db.execute(
        select(func.count(Product.id)).where(
            Product.current_stock_qty == 0,
            Product.has_had_inward == True,
            Product.is_active == True,
        )
    )
    oos_count = res_oos.scalar() or 0

    # Flagged outward reviews
    res_flagged = await db.execute(
        select(func.count(OutwardLine.id)).where(OutwardLine.is_flagged_for_review == True)
    )
    flagged_count = res_flagged.scalar() or 0

    # Damaged units
    res_damaged = await db.execute(
        select(func.count(SerialNumber.id)).where(SerialNumber.status == SerialStatus.damaged)
    )
    damaged_count = res_damaged.scalar() or 0

    # Under repair units
    res_repair = await db.execute(
        select(func.count(SerialNumber.id)).where(SerialNumber.status == SerialStatus.under_repair)
    )
    repair_count = res_repair.scalar() or 0

    # Pending devices awaiting admin approval
    res_dev = await db.execute(select(func.count(Device.id)).where(Device.is_active == False))
    pending_devices = res_dev.scalar() or 0

    all_clear = (oos_count == 0 and flagged_count == 0 and damaged_count == 0 and repair_count == 0 and pending_devices == 0)

    pills = NeedsAttentionPills(
        out_of_stock_models=oos_count,
        flagged_outward_reviews=flagged_count,
        damaged_units=damaged_count,
        under_repair_units=repair_count,
        pending_devices=pending_devices,
        all_clear=all_clear,
    )

    return OverviewSummaryResponse(
        tracked_items_on_shelves=tracked_on_shelves,
        received_since_golive=received_since_golive,
        inward_today=inward_today,
        outward_today=outward_today,
        recorded_only_today=recorded_only_today,
        needs_attention=pills,
    )


@router.get("/stock-by-model")
async def get_stock_by_model(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category_id: Optional[uuid.UUID] = Query(None, description="Filter by category"),
    export: Optional[str] = Query(None, pattern="^(csv|xlsx|pdf)$"),
):
    """
    Main area Left column: "Stock by model" overview.
    Shows available (green), dispatched (amber), damaged (red), total received,
    and unmatched outward dispatches per product.
    Supports export via ?export=csv|xlsx|pdf.
    """
    # Subqueries for serial counts per product
    sn_counts = (
        select(
            SerialNumber.product_id,
            func.count(SerialNumber.id).label("total_received"),
            func.count(case((SerialNumber.status == SerialStatus.available, 1))).label("available_count"),
            func.count(case((SerialNumber.status == SerialStatus.dispatched, 1))).label("dispatched_count"),
            func.count(case((SerialNumber.status == SerialStatus.damaged, 1))).label("damaged_count"),
        )
        .group_by(SerialNumber.product_id)
        .subquery()
    )

    # Subquery for unmatched outward dispatches per product
    unmatched_counts = (
        select(
            OutwardLine.product_id,
            func.count(OutwardLine.id).label("unmatched_count"),
        )
        .where(OutwardLine.is_matched == False)
        .group_by(OutwardLine.product_id)
        .subquery()
    )

    query = (
        select(
            Product,
            Category.name.label("category_name"),
            func.coalesce(sn_counts.c.available_count, 0).label("available_count"),
            func.coalesce(sn_counts.c.dispatched_count, 0).label("dispatched_count"),
            func.coalesce(sn_counts.c.damaged_count, 0).label("damaged_count"),
            func.coalesce(sn_counts.c.total_received, 0).label("total_received"),
            func.coalesce(unmatched_counts.c.unmatched_count, 0).label("unmatched_dispatched_count"),
        )
        .join(Category, Product.category_id == Category.id)
        .outerjoin(sn_counts, Product.id == sn_counts.c.product_id)
        .outerjoin(unmatched_counts, Product.id == unmatched_counts.c.product_id)
        .where(Product.is_active == True)
        .order_by(Product.name.asc())
    )

    if category_id:
        query = query.where(Product.category_id == category_id)

    result = await db.execute(query)
    rows = result.all()

    items = []
    export_rows = []
    for p, cat_name, avail, disp, dam, tot_rec, unm_cnt in rows:
        oos_rem = (p.current_stock_qty == 0 and p.has_had_inward)
        label = "No tracked stock left" if oos_rem else None

        items.append(
            StockByModelItem(
                product_id=p.id,
                name=p.name,
                brand=p.brand,
                model=p.model,
                category_name=cat_name,
                sku=p.sku,
                available_count=avail,
                dispatched_count=disp,
                damaged_count=dam,
                total_received=tot_rec,
                unmatched_dispatched_count=unm_cnt,
                current_stock_qty=p.current_stock_qty,
                out_of_stock_reminder=oos_rem,
                reminder_label=label,
            )
        )

        if export:
            export_rows.append(
                [
                    p.name,
                    cat_name,
                    p.brand,
                    p.model,
                    p.current_stock_qty,
                    avail,
                    disp,
                    dam,
                    tot_rec,
                    unm_cnt,
                    label or "In stock",
                ]
            )

    if export:
        headers = [
            "Product Name", "Category", "Brand", "Model", "Stock Qty",
            "Available", "Dispatched", "Damaged", "Total Inward",
            "Unmatched Outward", "Status",
        ]
        return create_export_response(
            export,
            "Stock by Model Report",
            "Global Agencies Godown Management",
            headers,
            export_rows,
            f"stock_by_model_{date.today()}",
        )

    return items


@router.get("/today-timeline", response_model=list[TodayTimelineItem])
async def get_today_timeline(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(50, ge=1, le=100),
) -> list[TodayTimelineItem]:
    """
    Main area Right column: "Today" vertical movements timeline.
    Shows dispatches with shop names, inward scans, and returns.
    """
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    query = (
        select(
            SerialHistory,
            Shop.name.label("shop_name"),
            User.full_name.label("user_name"),
            Product.name.label("product_name"),
        )
        .outerjoin(Shop, SerialHistory.shop_id == Shop.id)
        .join(User, SerialHistory.user_id == User.id)
        .outerjoin(SerialNumber, SerialHistory.serial_number_id == SerialNumber.id)
        .outerjoin(Product, SerialNumber.product_id == Product.id)
        .where(SerialHistory.created_at >= today_start)
        .order_by(SerialHistory.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(query)
    rows = result.all()

    items = []
    for h, s_name, u_name, p_name in rows:
        p_display = p_name or "Appliance"
        dot = "indigo"
        desc = ""

        if h.action == HistoryAction.inward_recorded:
            dot = "green"
            desc = f"{h.serial_text} ({p_display}) scanned in"
        elif h.action in (HistoryAction.dispatched_matched, HistoryAction.dispatched_unmatched, HistoryAction.dispatched_flagged):
            dot = "amber"
            dest = f" to {s_name}" if s_name else ""
            tag = " [unmatched]" if h.action == HistoryAction.dispatched_unmatched else ""
            desc = f"{h.serial_text} out{dest}{tag}"
        elif h.action == HistoryAction.returned:
            dot = "indigo"
            src = f" from {s_name}" if s_name else ""
            desc = f"{h.serial_text} returned{src}"
        elif h.action == HistoryAction.inspected:
            dot = "green" if h.to_status == SerialStatus.available else "red"
            desc = f"{h.serial_text} inspected ({h.to_status.value if h.to_status else ''})"
        else:
            dot = "red"
            desc = f"{h.serial_text} marked {h.to_status.value if h.to_status else ''}"

        items.append(
            TodayTimelineItem(
                id=h.id,
                timestamp=h.created_at,
                action=h.action.value,
                serial_number=h.serial_text,
                product_name=p_display,
                shop_name=s_name,
                user_name=u_name,
                dot_color=dot,
                description=desc,
            )
        )
    return items


@router.get("/stock-out")
async def get_stock_out_report(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    shop_id: Optional[uuid.UUID] = Query(None, description="Filter by shop"),
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    date_from: Optional[date] = Query(None, description="Filter from date"),
    date_to: Optional[date] = Query(None, description="Filter to date"),
    is_matched: Optional[bool] = Query(None, description="Filter matched vs recorded only"),
    export: Optional[str] = Query(None, pattern="^(csv|xlsx|pdf)$"),
):
    """
    Stock out report: shows every outward line with 'Matched' vs 'Recorded only' column.
    Filterable by shop, product, and date.
    """
    query = (
        select(
            OutwardLine,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            OutwardBatch.delivery_reference,
            User.full_name.label("dispatcher_name"),
        )
        .join(Product, OutwardLine.product_id == Product.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(User, OutwardBatch.dispatched_by_user_id == User.id)
        .order_by(OutwardLine.transaction_date.desc(), OutwardLine.created_at.desc())
    )

    if shop_id:
        query = query.where(OutwardLine.shop_id == shop_id)
    if product_id:
        query = query.where(OutwardLine.product_id == product_id)
    if date_from:
        query = query.where(OutwardLine.transaction_date >= date_from)
    if date_to:
        query = query.where(OutwardLine.transaction_date <= date_to)
    if is_matched is not None:
        query = query.where(OutwardLine.is_matched == is_matched)

    result = await db.execute(query)
    rows = result.all()

    items = []
    export_rows = []
    for l, p_name, p_brand, p_model, s_name, s_city, del_ref, u_name in rows:
        label = "Flagged" if l.is_flagged_for_review else ("Matched" if l.is_matched else "Recorded only")
        entry = {
            "id": l.id,
            "transaction_date": l.transaction_date,
            "serial_number": l.serial_text,
            "product_name": p_name,
            "brand": p_brand,
            "model": p_model,
            "shop_name": s_name,
            "shop_city": s_city,
            "delivery_reference": del_ref,
            "is_matched": l.is_matched,
            "status_label": label,
            "dispatcher_name": u_name,
        }
        items.append(entry)

        if export:
            export_rows.append(
                [
                    str(l.transaction_date),
                    l.serial_text,
                    p_name,
                    f"{s_name} ({s_city})",
                    del_ref or "-",
                    label,
                    u_name,
                ]
            )

    if export:
        headers = ["Date", "Serial Number", "Product Model", "Destination Shop", "Delivery Ref", "Match Status", "Dispatched By"]
        return create_export_response(
            export,
            "Stock Out Dispatch Report",
            f"Filter: {len(items)} records",
            headers,
            export_rows,
            f"stock_out_{date.today()}",
        )

    return items


@router.get("/unmatched-outward")
async def get_unmatched_outward_report(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    shop_id: Optional[uuid.UUID] = Query(None, description="Filter by shop"),
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    date_from: Optional[date] = Query(None, description="Filter from date"),
    date_to: Optional[date] = Query(None, description="Filter to date"),
    export: Optional[str] = Query(None, pattern="^(csv|xlsx|pdf)$"),
):
    """
    Dedicated "Unmatched Outward" report:
    Lists every serial dispatched without an inward record (pre-go-live stock).
    Filterable by shop, model, and date.
    """
    return await get_stock_out_report(
        current_user=current_user,
        db=db,
        shop_id=shop_id,
        product_id=product_id,
        date_from=date_from,
        date_to=date_to,
        is_matched=False,
        export=export,
    )


@router.get("/damaged")
async def get_damaged_report(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    product_id: Optional[uuid.UUID] = Query(None, description="Filter by product"),
    export: Optional[str] = Query(None, pattern="^(csv|xlsx|pdf)$"),
):
    """
    Damaged and Under-Repair stock report.
    """
    query = (
        select(
            SerialNumber,
            Product.name.label("product_name"),
            Product.brand.label("product_brand"),
            Product.model.label("product_model"),
            Shop.name.label("shop_name"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
        .where(SerialNumber.status.in_([SerialStatus.damaged, SerialStatus.under_repair]))
        .order_by(SerialNumber.updated_at.desc())
    )

    if product_id:
        query = query.where(SerialNumber.product_id == product_id)

    result = await db.execute(query)
    rows = result.all()

    items = []
    export_rows = []
    for sn, p_name, p_brand, p_model, s_name in rows:
        entry = {
            "id": sn.id,
            "serial_number": sn.serial_number,
            "product_name": p_name,
            "brand": p_brand,
            "model": p_model,
            "status": sn.status.value,
            "last_shop_name": s_name,
            "updated_at": sn.updated_at,
        }
        items.append(entry)

        if export:
            export_rows.append(
                [
                    sn.serial_number,
                    p_name,
                    p_brand,
                    p_model,
                    sn.status.value.replace("_", " ").title(),
                    s_name or "Godown",
                    str(sn.updated_at.date() if sn.updated_at else "-"),
                ]
            )

    if export:
        headers = ["Serial Number", "Product", "Brand", "Model", "Condition", "Location/Shop", "Date Marked"]
        return create_export_response(
            export,
            "Damaged & Under Repair Report",
            f"Attention list: {len(items)} items",
            headers,
            export_rows,
            f"damaged_stock_{date.today()}",
        )

    return items