import base64
from datetime import date, datetime, timezone
from typing import Annotated, Any, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.database import get_db
from app.models.category import Category
from app.models.enums import HistoryAction, SerialStatus
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.services.exporter import export_bill_to_pdf, export_inward_register_to_pdf, export_to_pdf
from app.services.print_service import PrintService

router = APIRouter(prefix="/print", tags=["print"])


class PrintBillRequest(BaseModel):
    bill_number: str = Field(..., description="Bill Number or delivery reference to print")
    printer_name: Optional[str] = Field(None, description="Office PC printer name. If null, default is used.")
    dry_run: bool = Field(False, description="If true, verifies PDF rendering and printer DC without spooling paper.")


class PrintReportRequest(BaseModel):
    report_type: str = Field(
        ...,
        description="One of: 'today_inward_serials', 'stock_by_model', 'stock_out', 'unmatched_outward', 'damaged', 'today_summary'",
    )
    printer_name: Optional[str] = Field(None, description="Office PC printer name. If null, default is used.")
    category_id: Optional[uuid.UUID] = None
    shop_id: Optional[uuid.UUID] = None
    product_id: Optional[uuid.UUID] = None
    date_from: Optional[date] = None
    date_to: Optional[date] = None
    inward_type: Optional[str] = None
    is_matched: Optional[bool] = None
    dry_run: bool = Field(False, description="If true, verifies PDF rendering and printer DC without spooling paper.")


class PrintRawPdfRequest(BaseModel):
    pdf_base64: str = Field(..., description="Base64 encoded PDF binary data")
    printer_name: Optional[str] = Field(None, description="Target printer name")
    job_name: Optional[str] = Field("Office Print Job", description="Name for the print spooler")
    dry_run: bool = Field(False, description="If true, verifies PDF rendering and printer DC without spooling paper.")


class PrintTestRequest(BaseModel):
    printer_name: Optional[str] = None
    dry_run: bool = Field(False, description="If true, verifies PDF rendering and printer DC without spooling paper.")


@router.get("/printers")
async def get_office_printers(
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    List all printers connected and installed on the Office PC.
    Shows the default printer and connection status for Tailscale clients.
    """
    printers = PrintService.get_printers()
    default_printer = PrintService.get_default_printer_name()
    return {
        "printers": printers,
        "default_printer": default_printer,
        "server_time": datetime.now().isoformat(),
        "tailscale_ready": True,
    }


@router.post("/godown-report")
async def print_godown_report(
    payload: PrintReportRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    Generate Godown Report and immediately print it to the office PC printer over Tailscale.
    """
    rtype = payload.report_type.lower().strip()
    report_title = "Godown Stock Report"
    subtitle = f"Global Agencies Godown Management  •  Printed by {current_user.full_name}"
    headers: list[str] = []
    rows: list[list[Any]] = []
    pdf_bytes: Optional[bytes] = None
    records_count: int = 0

    # 0. TODAY INWARD SERIAL REGISTER (GROUPED BY MODEL)
    if rtype in ("today_inward_serials", "today_inward_by_model", "inward_serials"):
        today = date.today()
        target_date_from = payload.date_from or today
        target_date_to = payload.date_to or today

        if target_date_from == target_date_to:
            date_label = target_date_from.strftime("%d %b %Y").upper()
            report_title = f"INWARD SERIAL REGISTER - {date_label}"
        else:
            d_from_str = target_date_from.strftime("%d %b %Y").upper()
            d_to_str = target_date_to.strftime("%d %b %Y").upper()
            report_title = f"INWARD SERIAL REGISTER - {d_from_str} TO {d_to_str}"

        query = (
            select(
                InwardBatch,
                InwardLine,
                SerialNumber,
                Product,
                Category.name.label("category_name"),
                User.full_name.label("receiver_name"),
            )
            .join(InwardLine, InwardBatch.id == InwardLine.batch_id)
            .join(SerialNumber, InwardLine.serial_number_id == SerialNumber.id)
            .join(Product, InwardBatch.product_id == Product.id)
            .join(Category, Product.category_id == Category.id)
            .join(User, InwardBatch.received_by_user_id == User.id)
            .where(
                or_(
                    InwardBatch.transaction_date.between(target_date_from, target_date_to),
                    func.date(InwardBatch.created_at).between(target_date_from, target_date_to),
                )
            )
            .order_by(
                Product.brand.asc(),
                Product.model.asc(),
                InwardBatch.created_at.asc(),
                SerialNumber.serial_number.asc(),
            )
        )

        if payload.product_id:
            query = query.where(InwardBatch.product_id == payload.product_id)
        if payload.category_id:
            query = query.where(Product.category_id == payload.category_id)
        if getattr(payload, "inward_type", None):
            query = query.where(InwardBatch.inward_type == payload.inward_type)

        result = await db.execute(query)
        db_rows = result.all()

        groups_map: dict[uuid.UUID, dict[str, Any]] = {}
        stock_in_cnt = 0
        returns_cnt = 0
        damaged_cnt = 0

        for b, line, sn, prod, cat_name, u_name in db_rows:
            if prod.id not in groups_map:
                groups_map[prod.id] = {
                    "product_id": prod.id,
                    "brand": prod.brand or "Unknown",
                    "model": prod.model or prod.name,
                    "product_name": prod.name,
                    "category": cat_name,
                    "serials": [],
                }

            inw_type = b.inward_type or "stock_in"
            if inw_type == "return":
                returns_cnt += 1
                inw_label = "Return"
            elif inw_type == "damaged":
                damaged_cnt += 1
                inw_label = "Damaged"
            else:
                stock_in_cnt += 1
                inw_label = "Stock In"

            time_str = b.created_at.strftime("%I:%M %p") if b.created_at else "-"

            groups_map[prod.id]["serials"].append({
                "serial_number": sn.serial_number,
                "unit_type": sn.unit_type or "-",
                "inward_type": inw_label,
                "reference": b.invoice_reference or "-",
                "time": time_str,
                "received_by": u_name,
            })

        model_groups = list(groups_map.values())
        total_serials = len(db_rows)
        records_count = total_serials

        totals = {
            "total_models": len(model_groups),
            "total_serials": total_serials,
            "stock_in": stock_in_cnt,
            "returns": returns_cnt,
            "damaged": damaged_cnt,
        }

        filter_desc = "All Models"
        if payload.product_id and model_groups:
            first_grp = model_groups[0]
            filter_desc = f"{first_grp['brand']} {first_grp['model']}"
        elif payload.product_id:
            p_res = await db.execute(select(Product).where(Product.id == payload.product_id))
            p_obj = p_res.scalar_one_or_none()
            if p_obj:
                filter_desc = f"{p_obj.brand} {p_obj.model}"

        pdf_bytes = export_inward_register_to_pdf(
            title=report_title,
            subtitle=subtitle,
            filter_desc=filter_desc,
            model_groups=model_groups,
            totals=totals,
        )

    # 1. STOCK BY MODEL
    elif rtype == "stock_by_model":
        report_title = "Godown Stock by Model Report"
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

        if payload.category_id:
            query = query.where(Product.category_id == payload.category_id)

        result = await db.execute(query)
        db_rows = result.all()

        headers = [
            "Product Name", "Category", "Brand", "Model", "Stock Qty",
            "Available", "Dispatched", "Damaged", "Total Inward",
            "Unmatched Outward", "Status",
        ]
        for p, cat_name, avail, disp, dam, tot_rec, unm_cnt in db_rows:
            label = "Out of Stock" if p.current_stock_qty <= 0 else "In Stock"
            rows.append([
                p.name, cat_name, p.brand, p.model, max(0, p.current_stock_qty),
                avail, disp, dam, tot_rec, unm_cnt, label
            ])

    # 2. STOCK OUT DISPATCHES
    elif rtype in ("stock_out", "unmatched_outward"):
        is_unmatched_only = (rtype == "unmatched_outward") or (payload.is_matched is False)
        report_title = "Unmatched Outward Dispatches" if is_unmatched_only else "Stock Out Dispatch Report"

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

        if payload.shop_id:
            query = query.where(OutwardLine.shop_id == payload.shop_id)
        if payload.product_id:
            query = query.where(OutwardLine.product_id == payload.product_id)
        if payload.date_from:
            query = query.where(OutwardLine.transaction_date >= payload.date_from)
        if payload.date_to:
            query = query.where(OutwardLine.transaction_date <= payload.date_to)
        if is_unmatched_only:
            query = query.where(OutwardLine.is_matched == False)
        elif payload.is_matched is not None:
            query = query.where(OutwardLine.is_matched == payload.is_matched)

        result = await db.execute(query)
        db_rows = result.all()

        headers = ["Date", "Serial Number", "Product Model", "Destination Shop", "Delivery Ref", "Status", "Dispatcher"]
        for l, p_name, p_brand, p_model, s_name, s_city, del_ref, u_name in db_rows:
            label = "Flagged" if l.is_flagged_for_review else ("Matched" if l.is_matched else "Recorded only")
            s_text = f"{l.serial_text} ({l.unit_type.capitalize()})" if l.unit_type else l.serial_text
            rows.append([
                str(l.transaction_date), s_text, p_name, f"{s_name} ({s_city})", del_ref or "-", label, u_name
            ])

    # 3. DAMAGED & UNDER REPAIR
    elif rtype == "damaged":
        report_title = "Damaged & Under Repair Stock Report"
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
        if payload.product_id:
            query = query.where(SerialNumber.product_id == payload.product_id)

        result = await db.execute(query)
        db_rows = result.all()

        headers = ["Serial Number", "Product", "Brand", "Model", "Condition", "Location/Shop", "Date Marked"]
        for sn, p_name, p_brand, p_model, s_name in db_rows:
            sn_text = f"{sn.serial_number} ({sn.unit_type.capitalize()})" if sn.unit_type else sn.serial_number
            rows.append([
                sn_text, p_name, p_brand, p_model, sn.status.value.replace("_", " ").title(),
                s_name or "Godown", str(sn.updated_at.date() if sn.updated_at else "-")
            ])

    # 4. TODAY'S GODOWN SUMMARY
    elif rtype == "today_summary":
        report_title = "Today's Godown Operations Summary"
        today = date.today()
        # Inward batches today
        res_in = await db.execute(
            select(InwardBatch, Product.name.label("p_name"), User.full_name.label("u_name"))
            .join(Product, InwardBatch.product_id == Product.id)
            .join(User, InwardBatch.received_by_user_id == User.id)
            .where(InwardBatch.transaction_date == today)
        )
        # Outward batches today
        res_out = await db.execute(
            select(OutwardBatch, Shop.name.label("s_name"), User.full_name.label("u_name"))
            .join(Shop, OutwardBatch.shop_id == Shop.id)
            .join(User, OutwardBatch.dispatched_by_user_id == User.id)
            .where(OutwardBatch.transaction_date == today)
        )

        headers = ["Type", "Reference", "Item / Destination", "Quantity", "User / Time"]
        for b, p_name, u_name in res_in.all():
            t_in = b.created_at.strftime("%I:%M %p") if b.created_at else "-"
            ref = b.invoice_reference or f"Inward #{str(b.id)[:8]}"
            rows.append(["INWARD", ref, p_name, str(b.quantity), f"{u_name} ({t_in})"])
        for b, s_name, u_name in res_out.all():
            t_out = b.created_at.strftime("%I:%M %p") if b.created_at else "-"
            ref = b.bill_number or f"Dispatch #{str(b.id)[:8]}"
            rows.append(["DISPATCH", ref, s_name, str(b.quantity), f"{u_name} ({t_out})"])
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported report_type '{payload.report_type}'. Choose today_inward_serials, stock_by_model, stock_out, unmatched_outward, damaged, or today_summary."
        )

    # Generate PDF bytes if not already generated
    if pdf_bytes is None:
        if not rows:
            rows.append(["No records found matching criteria", "-", "-", "-", "-", "-", "-"])
        pdf_bytes = export_to_pdf(report_title, subtitle, headers, rows)
        records_count = len(rows)

    # Dispatch to office PC printer
    job_name = report_title if "INWARD SERIAL REGISTER" in report_title else f"{report_title} - {date.today()}"
    try:
        print_res = await PrintService.print_pdf(
            pdf_bytes=pdf_bytes,
            printer_name=payload.printer_name,
            job_name=job_name,
            dry_run=payload.dry_run,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Print error on Office PC: {str(e)}")

    return {
        "success": True,
        "message": f"Successfully sent '{report_title}' ({records_count} records) to '{print_res['printer']}' on Office PC.",
        "printer": print_res["printer"],
        "pages": print_res.get("pages", 1),
        "job_name": job_name,
        "records_count": records_count,
    }


@router.post("/raw-pdf")
async def print_raw_pdf(
    payload: PrintRawPdfRequest,
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Print any raw base64-encoded PDF (e.g. customer bill or custom report) to the office PC printer.
    """
    try:
        pdf_bytes = base64.b64decode(payload.pdf_base64)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid base64 payload: {e}")

    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="Empty PDF content provided.")

    try:
        print_res = await PrintService.print_pdf(
            pdf_bytes=pdf_bytes,
            printer_name=payload.printer_name,
            job_name=payload.job_name or "Mobile Tailscale Print Job",
            dry_run=payload.dry_run,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Print error on Office PC: {str(e)}")

    return {
        "success": True,
        "message": f"Successfully printed document to '{print_res['printer']}' on Office PC.",
        "printer": print_res["printer"],
        "pages": print_res.get("pages", 1),
    }


@router.post("/test")
async def print_test_slip(
    payload: PrintTestRequest,
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Print a test slip on the Office PC to verify Tailscale connectivity and printer readiness.
    """
    now_str = datetime.now().strftime("%d-%b-%Y %I:%M:%S %p")
    target_printer = payload.printer_name or PrintService.get_default_printer_name() or "Default Printer"
    headers = ["Parameter", "Office PC Print Server Status"]
    rows = [
        ["Connection Mode", "Tailscale Mesh VPN"],
        ["Client User", current_user.full_name],
        ["Target Printer", target_printer],
        ["Host System", "Windows (Office Primary Terminal)"],
        ["Timestamp", now_str],
        ["Status", "OK - Ready to Spool Godown Reports & Bills"],
    ]
    pdf_bytes = export_to_pdf(
        "Tailscale Print Server Test",
        "Global Agencies Godown Management System",
        headers,
        rows,
    )

    try:
        print_res = await PrintService.print_pdf(
            pdf_bytes=pdf_bytes,
            printer_name=payload.printer_name,
            job_name="Print Server Test Slip",
            dry_run=payload.dry_run,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Test print error: {str(e)}")

    return {
        "success": True,
        "message": f"Test slip sent to '{print_res['printer']}' on Office PC.",
        "printer": print_res["printer"],
        "timestamp": now_str,
    }


@router.post("/bill")
async def print_bill(
    payload: PrintBillRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    Print an outward bill / delivery challan directly to the Office PC printer.
    """
    from app.api.v1.outward import get_outward_bill_detail
    clean_b_num = payload.bill_number.strip()
    bill_detail = await get_outward_bill_detail(
        bill_number=clean_b_num,
        current_user=current_user,
        db=db,
    )

    # Render professional Delivery Challan PDF bytes
    bill_dict = bill_detail.model_dump()
    pdf_bytes = export_bill_to_pdf(bill_dict)

    job_name = f"Delivery Challan - {clean_b_num}"
    try:
        print_res = await PrintService.print_pdf(
            pdf_bytes=pdf_bytes,
            printer_name=payload.printer_name,
            job_name=job_name,
            dry_run=payload.dry_run,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Print error on Office PC: {str(e)}")

    return {
        "success": True,
        "message": f"Successfully sent Challan '{clean_b_num}' ({bill_detail.total_units} units) to '{print_res['printer']}' on Office PC.",
        "printer": print_res["printer"],
        "pages": print_res.get("pages", 1),
        "bill_number": clean_b_num,
        "total_units": bill_detail.total_units,
    }
