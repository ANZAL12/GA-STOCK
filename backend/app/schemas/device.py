from datetime import datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict


class DeviceRegisterRequest(BaseModel):
    device_uid: str
    label: Optional[str] = None


class DeviceApproveRequest(BaseModel):
    label: Optional[str] = None


class DeviceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    device_uid: str
    label: Optional[str] = None
    approved_by_id: Optional[uuid.UUID] = None
    approved_at: Optional[datetime] = None
    is_active: bool
    created_at: datetime