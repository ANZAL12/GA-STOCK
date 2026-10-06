from datetime import datetime
import uuid
from typing import Any, Optional
from pydantic import BaseModel, ConfigDict


class AuditLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
    user_id: Optional[uuid.UUID] = None
    user_name: Optional[str] = None
    device_id: Optional[uuid.UUID] = None
    device_label: Optional[str] = None
    action: str
    entity_type: str
    entity_id: Optional[str] = None
    details: Optional[dict[str, Any]] = None
    ip_address: Optional[str] = None