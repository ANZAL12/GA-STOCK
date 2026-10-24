from datetime import datetime, timezone
from typing import Annotated, Any, Dict, List
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.database import get_db
from app.models.category import Category
from app.models.enums import SerialStatus
from app.models.outward import OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User

router = APIRouter(prefix="/sync", tags=["sync"])


@router.get("/snapshot")
async def get_offline_snapshot(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Dict[str, Any]:
    """
    Returns complete local snapshot for 100% offline-first operation on Android scanners:
    - Products catalog
    - Shops directory
    - Full serials & inventory state mapping (available, damaged, dispatched, dual-serial unit types)
    """
    # 1. Active Products
    prod_query = (
        select(
            Product,
            Category.name.label("category_name"),
            Category.has_dual_serial.label("has_dual_serial"),
        )
        .outerjoin(Category, Product.category_id == Category.id)
        .where(Product.is_active == True)
        .order_by(Product.brand, Product.model)
    )
    prod_rows = (await db.execute(prod_query)).all()
    products_list = [
        {
            "id": str(p.id),
            "name": p.name,
            "sku": p.sku,
            "brand": p.brand,
            "model": p.model,
            "size_capacity": p.size_capacity,
            "unit": p.unit,
            "serial_number_required": p.serial_number_required,
            "current_stock_qty": p.current_stock_qty,
            "out_of_stock_reminder": p.current_stock_qty <= 0 and p.has_had_inward,
            "category_id": str(p.category_id) if p.category_id else "",
            "category_name": cat_name,
            "has_dual_serial": bool(has_dual),
            "is_active": p.is_active,
        }
        for p, cat_name, has_dual in prod_rows
    ]

    # 2. Active Shops
    shop_res = await db.execute(
        select(Shop).where(Shop.is_active == True).order_by(Shop.name)
    )
    shops_list = [
        {
            "id": str(s.id),
            "name": s.name,
            "city": s.city,
            "phone": s.phone,
            "is_active": s.is_active,
        }
        for s in shop_res.scalars().all()
    ]

    # 3. Tracked inventory serial numbers
    sn_query = (
        select(
            SerialNumber.serial_number,
            SerialNumber.product_id,
            SerialNumber.status,
            SerialNumber.unit_type,
            Product.model.label("model_name"),
            Product.brand.label("brand_name"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(Product, SerialNumber.product_id == Product.id)
        .outerjoin(Shop, SerialNumber.last_shop_id == Shop.id)
    )
    sn_rows = (await db.execute(sn_query)).all()

    serials_map: Dict[str, Dict[str, Any]] = {}
    for sn_text, prod_id, sn_status, unit_type, p_model, p_brand, s_name, s_city in sn_rows:
        clean_sn = sn_text.strip().upper()
        status_val = sn_status.value if hasattr(sn_status, "value") else str(sn_status)
        serials_map[clean_sn] = {
            "p": str(prod_id),
            "m": f"{p_brand} {p_model}".strip(),
            "st": status_val,
            "u": unit_type,
            "d": status_val == "dispatched",
            "dmg": status_val == "damaged",
            "sn": s_name,
            "sc": s_city,
        }

    # 4. Previously dispatched outward lines (ensures old pre-go-live dispatched serials are blocked offline too)
    outward_disp_res = await db.execute(
        select(
            OutwardLine.serial_text,
            OutwardLine.product_id,
            OutwardLine.unit_type,
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
            Product.model.label("product_model"),
            Product.brand.label("product_brand"),
        )
        .outerjoin(Shop, OutwardLine.shop_id == Shop.id)
        .outerjoin(Product, OutwardLine.product_id == Product.id)
        .distinct()
    )
    for disp_text, disp_prod_id, disp_unit_type, disp_s_name, disp_s_city, disp_p_model, disp_p_brand in outward_disp_res.all():
        clean_disp = disp_text.strip().upper()
        disp_model_name = f"{disp_p_brand or ''} {disp_p_model or ''}".strip() or "Previously Dispatched"
        if clean_disp not in serials_map:
            serials_map[clean_disp] = {
                "p": str(disp_prod_id) if disp_prod_id else None,
                "m": disp_model_name,
                "st": "dispatched",
                "u": disp_unit_type,
                "d": True,
                "dmg": False,
                "sn": disp_s_name,
                "sc": disp_s_city,
            }
        else:
            # If line is recorded dispatched in outward lines, ensure dispatched flag is true
            if serials_map[clean_disp]["st"] == "dispatched":
                serials_map[clean_disp]["d"] = True
                if not serials_map[clean_disp].get("sn") and disp_s_name:
                    serials_map[clean_disp]["sn"] = disp_s_name
                    serials_map[clean_disp]["sc"] = disp_s_city

    return {
        "server_time": datetime.now(timezone.utc).isoformat(),
        "products": products_list,
        "shops": shops_list,
        "serials": serials_map,
        "total_serials_cached": len(serials_map),
    }
