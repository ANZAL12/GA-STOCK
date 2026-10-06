import uuid
from typing import Annotated, Optional

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_token
from app.database import get_db
from app.models.device import Device
from app.models.enums import UserRole
from app.models.user import User

security_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    auth: Annotated[Optional[HTTPAuthorizationCredentials], Depends(security_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not auth or not auth.credentials:
        raise credentials_exception

    try:
        payload = decode_token(auth.credentials)
        if payload.get("type") != "access":
            raise credentials_exception
        user_id_str: str = payload.get("sub")
        if not user_id_str:
            raise credentials_exception
        user_id = uuid.UUID(user_id_str)
    except (JWTError, ValueError):
        raise credentials_exception

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if user is None:
        raise credentials_exception
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Inactive user account",
        )
    return user


async def require_admin(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    if current_user.role != UserRole.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    return current_user


async def get_current_device_optional(
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
    db: Annotated[AsyncSession, Depends(get_db)] = None,
) -> Optional[Device]:
    """
    If X-Device-Id header is provided, verifies that the device is registered
    and approved (is_active == True).
    If header is not present (e.g. web desktop browser), returns None.
    """
    if not x_device_id:
        return None

    clean_uid = x_device_id.strip()
    result = await db.execute(select(Device).where(Device.device_uid == clean_uid))
    device = result.scalar_one_or_none()

    if not device:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Device '{clean_uid}' is not registered. Please register the device first.",
        )
    if not device.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Device is awaiting administrator approval.",
        )
    return device


async def require_approved_device(
    x_device_id: Annotated[Optional[str], Header(alias="X-Device-Id")] = None,
    db: Annotated[AsyncSession, Depends(get_db)] = None,
) -> Device:
    """
    Strict requirement for mobile operations (like stock in / stock out scans).
    Requires X-Device-Id header to be present and active.
    """
    if not x_device_id or not x_device_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Device-Id header is required for mobile operations.",
        )
    device = await get_current_device_optional(x_device_id=x_device_id, db=db)
    return device