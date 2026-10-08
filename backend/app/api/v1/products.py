from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

import json
from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.category import Category
from app.models.enums import SerialStatus
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.user import User
from app.schemas.product import ProductCreate, ProductResponse, ProductUpdate, ProductSerialItem

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=list[ProductResponse])
async def list_products(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: Optional[str] = Query(None, description="Search query across name, brand, model, SKU"),
    category_id: Optional[uuid.UUID] = Query(None, description="Filter by category"),
    is_active: Optional[bool] = Query(True, description="Filter by active status"),
) -> list[ProductResponse]:
    """
    Search and list products with real-time stock counts.
    Accessible by both admin and staff.
    """
    query = (
        select(
            Product,
            Category.name.label("category_name"),
            Category.has_dual_serial.label("has_dual_serial"),
        )
        .join(Category, Product.category_id == Category.id)
        .order_by(Product.name.asc())
    )

    if is_active is not None:
        query = query.where(Product.is_active == is_active)

    if category_id:
        query = query.where(Product.category_id == category_id)

    if q and q.strip():
        search_term = f"%{q.strip().lower()}%"
        query = query.where(
            or_(
                func.lower(Product.name).like(search_term),
                func.lower(Product.brand).like(search_term),
                func.lower(Product.model).like(search_term),
                func.lower(Product.sku).like(search_term),
            )
        )

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for prod, cat_name, has_dual in rows:
        resp = ProductResponse.model_validate(prod)
        resp.category_name = cat_name
        resp.has_dual_serial = has_dual
        responses.append(resp)

    return responses


@router.get("/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ProductResponse:
    """
    Get a single product by ID.
    """
    query = (
        select(
            Product,
            Category.name.label("category_name"),
            Category.has_dual_serial.label("has_dual_serial"),
        )
        .join(Category, Product.category_id == Category.id)
        .where(Product.id == product_id)
    )
    result = await db.execute(query)
    row = result.first()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

    prod, cat_name, has_dual = row
    resp = ProductResponse.model_validate(prod)
    resp.category_name = cat_name
    resp.has_dual_serial = has_dual
    return resp


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
async def create_product(
    req: ProductCreate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ProductResponse:
    """
    Admin only: add a new product model.
    Initial current_stock_qty starts equal to opening_stock_qty.
    """
    # Verify category exists
    cat_res = await db.execute(select(Category).where(Category.id == req.category_id))
    cat = cat_res.scalar_one_or_none()
    if not cat:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Selected category does not exist")

    # Verify SKU uniqueness if provided
    clean_sku = req.sku.strip() if req.sku else None
    if clean_sku:
        existing_sku = await db.execute(select(Product).where(Product.sku == clean_sku))
        if existing_sku.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"SKU '{clean_sku}' is already in use")

    opening_qty = max(0, req.opening_stock_qty)

    product = Product(
        name=req.name.strip(),
        sku=clean_sku,
        category_id=req.category_id,
        brand=req.brand.strip(),
        model=req.model.strip(),
        size_capacity=req.size_capacity.strip() if req.size_capacity else None,
        unit=req.unit.strip() if req.unit else "piece",
        serial_number_required=req.serial_number_required,
        description=req.description.strip() if req.description else None,
        opening_stock_qty=opening_qty,
        current_stock_qty=opening_qty,
        has_had_inward=False,
        is_active=True,
    )
    db.add(product)
    await db.flush()

    audit = AuditLog(
        user_id=admin.id,
        action="PRODUCT_CREATED",
        entity_type="product",
        entity_id=str(product.id),
        details={
            "name": product.name,
            "brand": product.brand,
            "model": product.model,
            "opening_stock_qty": product.opening_stock_qty,
        },
    )
    db.add(audit)

    await db.commit()
    await db.refresh(product)

    resp = ProductResponse.model_validate(product)
    resp.category_name = cat.name
    resp.has_dual_serial = cat.has_dual_serial

    await ws_manager.broadcast("product_created", json.loads(resp.model_dump_json()))
    return resp


@router.put("/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: uuid.UUID,
    req: ProductUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ProductResponse:
    """
    Admin only: edit product details.
    """
    result = await db.execute(select(Product).where(Product.id == product_id))
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

    if req.category_id is not None:
        cat_res = await db.execute(select(Category).where(Category.id == req.category_id))
        cat = cat_res.scalar_one_or_none()
        if not cat:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Selected category does not exist")
        product.category_id = req.category_id

    if req.sku is not None:
        clean_sku = req.sku.strip() if req.sku else None
        if clean_sku:
            existing_sku = await db.execute(
                select(Product).where(Product.sku == clean_sku, Product.id != product_id)
            )
            if existing_sku.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"SKU '{clean_sku}' is already in use")
        product.sku = clean_sku

    if req.name is not None:
        product.name = req.name.strip()
    if req.brand is not None:
        product.brand = req.brand.strip()
    if req.model is not None:
        product.model = req.model.strip()
    if req.size_capacity is not None:
        product.size_capacity = req.size_capacity.strip() if req.size_capacity else None
    if req.unit is not None:
        product.unit = req.unit.strip()
    if req.serial_number_required is not None:
        product.serial_number_required = req.serial_number_required
    if req.description is not None:
        product.description = req.description.strip() if req.description else None
    if req.is_active is not None:
        product.is_active = req.is_active

    # Opening stock adjustment: permitted by admin even after inward transactions have started
    if req.opening_stock_qty is not None and req.opening_stock_qty != product.opening_stock_qty:
        # Adjust current_stock_qty by the difference
        diff = req.opening_stock_qty - product.opening_stock_qty
        new_current = product.current_stock_qty + diff
        if new_current < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"New opening stock of {req.opening_stock_qty} would cause negative current stock ({new_current}).",
            )
        old_opening = product.opening_stock_qty
        old_current = product.current_stock_qty
        product.opening_stock_qty = req.opening_stock_qty
        product.current_stock_qty = new_current

        audit_stock = AuditLog(
            user_id=admin.id,
            action="PRODUCT_OPENING_STOCK_EDITED",
            entity_type="product",
            entity_id=str(product.id),
            details={
                "name": product.name,
                "old_opening_stock": old_opening,
                "new_opening_stock": req.opening_stock_qty,
                "old_current_stock": old_current,
                "new_current_stock": new_current,
                "diff": diff,
                "has_had_inward": product.has_had_inward,
            },
        )
        db.add(audit_stock)

    audit = AuditLog(
        user_id=admin.id,
        action="PRODUCT_UPDATED",
        entity_type="product",
        entity_id=str(product.id),
        details={"name": product.name, "is_active": product.is_active},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(product)

    # Fetch category
    cat_res = await db.execute(select(Category).where(Category.id == product.category_id))
    cat = cat_res.scalar_one_or_none()

    resp = ProductResponse.model_validate(product)
    resp.category_name = cat.name if cat else None
    resp.has_dual_serial = cat.has_dual_serial if cat else False

    await ws_manager.broadcast("product_updated", json.loads(resp.model_dump_json()))
    return resp


@router.delete("/{product_id}", response_model=ProductResponse)
async def deactivate_product(
    product_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ProductResponse:
    """
    Admin only: deactivate product.
    Products are NEVER hard-deleted to preserve transaction history and serial audit integrity.
    """
    result = await db.execute(select(Product).where(Product.id == product_id))
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

    product.is_active = False

    audit = AuditLog(
        user_id=admin.id,
        action="PRODUCT_DEACTIVATED",
        entity_type="product",
        entity_id=str(product.id),
        details={"name": product.name},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(product)

    cat_res = await db.execute(select(Category.name).where(Category.id == product.category_id))
    cat_name = cat_res.scalar_one_or_none()

    resp = ProductResponse.model_validate(product)
    resp.category_name = cat_name

    await ws_manager.broadcast("product_deleted", {"id": str(product_id)})
    return resp


@router.get("/{product_id}/serials", response_model=list[ProductSerialItem])
async def list_product_serials(
    product_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[ProductSerialItem]:
    """
    Get all scanned serial numbers for a specific product.
    Includes both in-stock available serials and dispatched serials with full details.
    """
    prod_res = await db.execute(select(Product).where(Product.id == product_id))
    product = prod_res.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    # 1. Outward subquery per serial
    outward_subq = (
        select(
            OutwardLine.serial_number_id,
            OutwardLine.transaction_date.label("outward_date"),
            OutwardBatch.delivery_reference.label("outward_ref"),
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .distinct(OutwardLine.serial_number_id)
        .order_by(OutwardLine.serial_number_id, OutwardLine.created_at.desc())
        .subquery()
    )

    # 2. Tracked serials
    query = (
        select(
            SerialNumber.id,
            SerialNumber.serial_number,
            SerialNumber.status,
            SerialNumber.unit_type,
            SerialNumber.created_at,
            InwardBatch.transaction_date.label("inward_date"),
            InwardBatch.invoice_reference.label("inward_ref"),
            InwardBatch.inward_type.label("inward_type"),
            outward_subq.c.shop_name,
            outward_subq.c.shop_city,
            outward_subq.c.outward_date,
            outward_subq.c.outward_ref,
        )
        .outerjoin(InwardLine, InwardLine.serial_number_id == SerialNumber.id)
        .outerjoin(InwardBatch, InwardLine.batch_id == InwardBatch.id)
        .outerjoin(outward_subq, outward_subq.c.serial_number_id == SerialNumber.id)
        .where(SerialNumber.product_id == product_id)
        .order_by(SerialNumber.created_at.desc())
    )
    rows = (await db.execute(query)).all()

    items: list[ProductSerialItem] = []
    seen_ids = set()

    for r in rows:
        if r.id in seen_ids:
            continue
        seen_ids.add(r.id)

        status_label = {
            SerialStatus.available: "Available",
            SerialStatus.dispatched: "Dispatched",
            SerialStatus.damaged: "Damaged",
            SerialStatus.lost: "Lost",
            SerialStatus.under_repair: "Under Repair",
            SerialStatus.returned: "Returned",
        }.get(r.status, r.status.value.capitalize())

        items.append(
            ProductSerialItem(
                id=str(r.id),
                serial_number=r.serial_number,
                status=r.status.value,
                status_label=status_label,
                unit_type=r.unit_type,
                inward_date=r.inward_date,
                inward_ref=r.inward_ref,
                inward_type=r.inward_type,
                shop_name=r.shop_name,
                shop_city=r.shop_city,
                outward_date=r.outward_date,
                delivery_ref=r.outward_ref,
                scanned_at=r.created_at,
                is_tracked=True,
            )
        )

    # 3. Unmatched outward lines for this product (recorded only)
    unmatched_query = (
        select(
            OutwardLine.id,
            OutwardLine.serial_text,
            OutwardLine.unit_type,
            OutwardLine.transaction_date,
            OutwardLine.created_at,
            OutwardBatch.delivery_reference,
            Shop.name.label("shop_name"),
            Shop.city.label("shop_city"),
        )
        .join(OutwardBatch, OutwardLine.batch_id == OutwardBatch.id)
        .join(Shop, OutwardLine.shop_id == Shop.id)
        .where(
            OutwardLine.product_id == product_id,
            OutwardLine.serial_number_id == None,
        )
        .order_by(OutwardLine.created_at.desc())
    )
    unmatched_rows = (await db.execute(unmatched_query)).all()

    for u in unmatched_rows:
        items.append(
            ProductSerialItem(
                id=f"outward_{u.id}",
                serial_number=u.serial_text,
                status="dispatched",
                status_label="Recorded only",
                unit_type=u.unit_type,
                inward_date=None,
                inward_ref=None,
                inward_type=None,
                shop_name=u.shop_name,
                shop_city=u.shop_city,
                outward_date=u.transaction_date,
                delivery_ref=u.delivery_reference,
                scanned_at=u.created_at,
                is_tracked=False,
            )
        )

    return items