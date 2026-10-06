from datetime import datetime, timezone
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_admin
from app.database import get_db
from app.models.audit import AuditLog
from app.models.device import Device
from app.models.user import User
from app.schemas.device import DeviceApproveRequest, DeviceRegisterRequest, DeviceResponse

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", response_model=DeviceResponse)
async def register_device(
    req: DeviceRegisterRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> DeviceResponse:
    """
    Mobile phones call this once to register their hardware device_uid.
    If new, created with is_active=False (pending admin approval).
    If already exists, returns current record and active status.
    """
    clean_uid = req.device_uid.strip()
    if not clean_uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="device_uid cannot be empty",
        )

    result = await db.execute(select(Device).where(Device.device_uid == clean_uid))
    device = result.scalar_one_or_none()

    if device:
        # Update label if provided and currently empty
        if req.label and not device.label:
            device.label = req.label.strip()
            await db.commit()
            await db.refresh(device)
        return DeviceResponse.model_validate(device)

    new_device = Device(
        device_uid=clean_uid,
        label=req.label.strip() if req.label else None,
        is_active=False,
    )
    db.add(new_device)
    await db.commit()
    await db.refresh(new_device)
    return DeviceResponse.model_validate(new_device)


@router.get("", response_model=list[DeviceResponse])
async def list_devices(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status_filter: Optional[str] = Query(None, alias="status", pattern="^(all|pending|approved)$"),
) -> list[DeviceResponse]:
    """
    Admin only: list all mobile devices and their approval status.
    """
    query = select(Device).order_by(Device.created_at.desc())
    if status_filter == "pending":
        query = query.where(Device.is_active == False)
    elif status_filter == "approved":
        query = query.where(Device.is_active == True)

    result = await db.execute(query)
    devices = result.scalars().all()
    return [DeviceResponse.model_validate(d) for d in devices]


@router.patch("/{device_id}/approve", response_model=DeviceResponse)
async def approve_device(
    device_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    req: Optional[DeviceApproveRequest] = None,
) -> DeviceResponse:
    """
    Admin only: approve a pending device so it can access the godown API.
    """
    result = await db.execute(select(Device).where(Device.id == device_id))
    device = result.scalar_one_or_none()

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )

    device.is_active = True
    device.approved_by_id = admin.id
    device.approved_at = datetime.now(timezone.utc)
    if req and req.label:
        device.label = req.label.strip()

    audit = AuditLog(
        user_id=admin.id,
        action="DEVICE_APPROVED",
        entity_type="device",
        entity_id=str(device.id),
        details={"device_uid": device.device_uid, "label": device.label},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(device)
    return DeviceResponse.model_validate(device)


@router.patch("/{device_id}/deactivate", response_model=DeviceResponse)
async def deactivate_device(
    device_id: uuid.UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> DeviceResponse:
    """
    Admin only: deactivate an approved device immediately revoking its access.
    """
    result = await db.execute(select(Device).where(Device.id == device_id))
    device = result.scalar_one_or_none()

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )

    device.is_active = False

    audit = AuditLog(
        user_id=admin.id,
        action="DEVICE_DEACTIVATED",
        entity_type="device",
        entity_id=str(device.id),
        details={"device_uid": device.device_uid, "label": device.label},
    )
    db.add(audit)

    await db.commit()
    await db.refresh(device)
    return DeviceResponse.model_validate(device)