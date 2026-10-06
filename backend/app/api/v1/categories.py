from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

import json
from app.api.deps import get_current_user, require_admin
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.category import Category
from app.models.product import Product
from app.models.user import User
from app.schemas.category import CategoryCreate, CategoryResponse, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("", response_model=list[CategoryResponse])
async def list_categories(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    active_only: bool = Query(True, description="Filter only active categories"),
) -> list[CategoryResponse]:
    """
    List categories. Accessible by both admin and staff.
    Includes count of products associated with each category.
    """
    # Subquery for active product count only (exclude deactivated/deleted products)
    count_subq = (
        select(Product.category_id, func.count(Product.id).label("prod_count"))
        .where(Product.is_active == True)
        .group_by(Product.category_id)
        .subquery()
    )

    query = (
        select(Category, func.coalesce(count_subq.c.prod_count, 0).label("product_count"))
        .outerjoin(count_subq, Category.id == count_subq.c.category_id)
        .order_by(Category.name.asc())
    )

    if active_only:
        query = query.where(Category.is_active == True)

    result = await db.execute(query)
    rows = result.all()

    responses = []
    for cat, p_count in rows:
        resp = CategoryResponse.model_validate(cat)
        resp.product_count = p_count
        responses.append(resp)

    return responses


@router.post("", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_category(
    req: CategoryCreate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CategoryResponse:
    """
    Admin only: add a new product category.
    """
    clean_name = req.name.strip()
    existing = await db.execute(select(Category).where(func.lower(Category.name) == clean_name.lower()))
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Category '{clean_name}' already exists",
        )

    category = Category(name=clean_name, is_active=True)
    db.add(category)
    await db.flush()

    audit = AuditLog(
        user_id=admin.id,
        action="CATEGORY_CREATED",
        entity_type="category",
        entity_id=str(category.id),
        details={"name": category.name},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(category)
    resp = CategoryResponse.model_validate(category)
    resp.product_count = 0
    await ws_manager.broadcast("category_created", json.loads(resp.model_dump_json()))
    return resp


@router.put("/{category_id}", response_model=CategoryResponse)
async def update_category(
    category_id: uuid.UUID,
    req: CategoryUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CategoryResponse:
    """
    Admin only: edit category name or active status.
    """
    result = await db.execute(select(Category).where(Category.id == category_id))
    category = result.scalar_one_or_none()
    if not category:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    if req.name is not None:
        clean_name = req.name.strip()
        existing = await db.execute(
            select(Category).where(
                func.lower(Category.name) == clean_name.lower(),
                Category.id != category_id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Another category with name '{clean_name}' already exists",
            )
        category.name = clean_name

    if req.is_active is not None:
        category.is_active = req.is_active

    audit = AuditLog(
        user_id=admin.id,
        action="CATEGORY_UPDATED",
        entity_type="category",
        entity_id=str(category.id),
        details={"name": category.name, "is_active": category.is_active},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(category)
    resp = CategoryResponse.model_validate(category)
    await ws_manager.broadcast("category_updated", json.loads(resp.model_dump_json()))
    return resp


@router.delete("/{category_id}", response_model=CategoryResponse)
async def deactivate_category(
    category_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CategoryResponse:
    """
    Admin only: deactivate category (categories with products are soft-deactivated).
    """
    result = await db.execute(select(Category).where(Category.id == category_id))
    category = result.scalar_one_or_none()
    if not category:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    category.is_active = False

    audit = AuditLog(
        user_id=admin.id,
        action="CATEGORY_DEACTIVATED",
        entity_type="category",
        entity_id=str(category.id),
        details={"name": category.name},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(category)
    resp = CategoryResponse.model_validate(category)
    await ws_manager.broadcast("category_deleted", {"id": str(category_id)})
    return resp