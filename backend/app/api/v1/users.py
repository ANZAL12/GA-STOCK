from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin
from app.core.security import get_password_hash
from app.database import get_db
from app.models.audit import AuditLog
from app.models.user import User
from app.schemas.user import UserCreate, UserListItem, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserListItem])
async def list_users(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    active_only: bool = Query(False, description="Filter only active accounts"),
) -> list[UserListItem]:
    """
    Admin only: list all system user accounts (admin and warehouse staff).
    """
    query = select(User).order_by(User.full_name.asc())
    if active_only:
        query = query.where(User.is_active == True)

    result = await db.execute(query)
    users = result.scalars().all()
    return [UserListItem.model_validate(u) for u in users]


@router.post("", response_model=UserListItem, status_code=status.HTTP_201_CREATED)
async def create_user(
    req: UserCreate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserListItem:
    """
    Admin only: create a new user account (e.g. warehouse staff).
    """
    clean_username = req.username.strip().lower()
    existing = await db.execute(select(User).where(func.lower(User.username) == clean_username))
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Username '{clean_username}' is already taken.",
        )

    new_user = User(
        username=clean_username,
        full_name=req.full_name.strip(),
        password_hash=get_password_hash(req.password),
        role=req.role,
        is_active=True,
    )
    db.add(new_user)
    await db.flush()

    audit = AuditLog(
        user_id=admin.id,
        action="USER_CREATED",
        entity_type="user",
        entity_id=str(new_user.id),
        details={"username": new_user.username, "full_name": new_user.full_name, "role": new_user.role.value},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(new_user)
    return UserListItem.model_validate(new_user)


@router.put("/{user_id}", response_model=UserListItem)
async def update_user(
    user_id: uuid.UUID,
    req: UserUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserListItem:
    """
    Admin only: update user account details, change role, or reset password.
    """
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    if req.full_name is not None:
        user.full_name = req.full_name.strip()
    if req.role is not None:
        user.role = req.role
    if req.is_active is not None:
        if user_id == admin.id and not req.is_active:
            raise HTTPException(status_code=400, detail="You cannot deactivate your own current administrator account.")
        user.is_active = req.is_active
    if req.password is not None and req.password.strip():
        user.password_hash = get_password_hash(req.password.strip())

    audit = AuditLog(
        user_id=admin.id,
        action="USER_UPDATED",
        entity_type="user",
        entity_id=str(user.id),
        details={"username": user.username, "role": user.role.value, "is_active": user.is_active},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(user)
    return UserListItem.model_validate(user)


@router.delete("/{user_id}", response_model=UserListItem)
async def deactivate_user(
    user_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserListItem:
    """
    Admin only: deactivate user account (staff accounts are never deleted to preserve audit logs).
    """
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="You cannot deactivate your own current administrator account.")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    user.is_active = False

    audit = AuditLog(
        user_id=admin.id,
        action="USER_DEACTIVATED",
        entity_type="user",
        entity_id=str(user.id),
        details={"username": user.username},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(user)
    return UserListItem.model_validate(user)