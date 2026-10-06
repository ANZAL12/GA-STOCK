from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

import json
from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.return_ import Return
from app.models.shop import Shop
from app.models.user import User
from app.schemas.shop import ShopCreate, ShopDispatchedSerial, ShopResponse, ShopUpdate

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
    clean_city = req.city.strip()
    clean_phone = req.phone.strip() if req.phone else None

    # Check for duplicate shop name in the same city
    existing = await db.execute(
        select(Shop).where(
            func.lower(Shop.name) == clean_name.lower(),
            func.lower(Shop.city) == clean_city.lower(),
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Shop '{clean_name}' in '{clean_city}' already exists",
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