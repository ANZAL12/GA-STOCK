from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import HistoryAction, SerialStatus


class SerialStatusChangeRequest(BaseModel):
    new_status: SerialStatus
    reason: str = Field(..., min_length=1, description="Reason for status change")
    remarks: Optional[str] = None


class SerialHistoryItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
    action: HistoryAction
    from_status: Optional[SerialStatus] = None
    to_status: Optional[SerialStatus] = None
    shop_id: Optional[uuid.UUID] = None
    shop_name: Optional[str] = None
    shop_city: Optional[str] = None
    is_matched: Optional[bool] = None
    user_name: str
    remarks: Optional[str] = None


class SerialDetailResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    serial_number: str
    serial_number_id: Optional[uuid.UUID] = None
    is_tracked: bool
    status: Optional[str] = None
    product_id: Optional[uuid.UUID] = None
    product_name: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    category_name: Optional[str] = None
    unit_type: Optional[str] = None
    last_shop_id: Optional[uuid.UUID] = None
    last_shop_name: Optional[str] = None
    last_shop_city: Optional[str] = None
    status_label: str  # "Available" | "Dispatched" | "Damaged" | "Recorded only" | etc.
    history: list[SerialHistoryItem] = []


class SerialListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    serial_number: str
    serial_number_id: Optional[uuid.UUID] = None
    brand: str
    model: str
    product_name: str
    category_name: Optional[str] = None
    status: str
    status_label: str
    flow_type: str  # "inward" (or "in_stock") vs "outward" (dispatched)
    transaction_date: Optional[date] = None
    created_at: datetime
    shop_name: Optional[str] = None
    shop_city: Optional[str] = None
    reference: Optional[str] = None
    bill_number: Optional[str] = None
    delivery_reference: Optional[str] = None
    is_matched: bool = True
    unit_type: Optional[str] = None


class SerialListResponse(BaseModel):
    total: int
    items: list[SerialListItem]