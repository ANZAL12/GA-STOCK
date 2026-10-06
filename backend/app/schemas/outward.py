from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class OutwardCheckSerialRequest(BaseModel):
    product_id: uuid.UUID
    shop_id: uuid.UUID
    serial_number: str = Field(..., min_length=1, max_length=100)


class OutwardCheckSerialResponse(BaseModel):
    serial_number: str
    case: int  # 1: Matched, 2: Unmatched (old stock), 3: Status conflict, 4: Model mismatch
    badge: str  # "matched" (green), "unmatched" (grey), "warning" (amber)
    badge_label: str  # "Matched", "Not in system, will be recorded", "Status Warning", "Model Warning"
    message: str
    requires_confirmation: bool
    warning_duplicate_dispatch: bool = False
    registered_model_name: Optional[str] = None
    current_status: Optional[str] = None
    last_dispatched_date: Optional[date] = None
    last_dispatched_shop_name: Optional[str] = None


class OutwardCheckRefRequest(BaseModel):
    shop_id: uuid.UUID
    delivery_reference: str
    transaction_date: date = Field(default_factory=date.today)


class OutwardCheckRefResponse(BaseModel):
    has_warning: bool
    message: Optional[str] = None


class OutwardSerialInput(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)
    confirmed_warning: bool = False  # Set to True by staff if confirming case 3 or 4


class OutwardBatchCreate(BaseModel):
    product_id: uuid.UUID
    shop_id: uuid.UUID
    delivery_reference: Optional[str] = Field(None, max_length=100)
    transaction_date: date = Field(default_factory=date.today)
    serials: list[OutwardSerialInput] = Field(..., min_length=1, description="List of scanned serials with confirmation flags")
    remarks: Optional[str] = None


class OutwardLineResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    serial_text: str
    serial_number_id: Optional[uuid.UUID] = None
    is_matched: bool
    is_flagged_for_review: bool
    flag_reason: Optional[str] = None
    status_label: str  # "Matched" | "Recorded only" | "Flagged"


class OutwardBatchResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: str
    delivery_reference: Optional[str] = None
    transaction_date: date
    quantity: int
    matched_count: int
    unmatched_count: int
    flagged_count: int
    dispatched_by_user_id: uuid.UUID
    dispatched_by_name: str
    device_id: Optional[uuid.UUID] = None
    remarks: Optional[str] = None
    created_at: datetime
    lines: list[OutwardLineResponse] = []