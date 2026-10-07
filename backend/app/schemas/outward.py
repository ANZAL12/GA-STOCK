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
    case: int  # 0: Blocked (Already Dispatched), 1: Matched, 2: Unmatched (old stock), 3: Status conflict, 4: Model mismatch
    case_name: str = "matched"  # "blocked", "matched", "unmatched", "status_warning", "model_mismatch"
    badge: str  # "blocked", "matched", "unmatched", "warning"
    badge_label: str  # "Already Dispatched", "Matched", "Not in system, will be recorded", "Status Warning", "Model Warning"
    message: str
    requires_confirmation: bool = False
    warning_duplicate_dispatch: bool = False
    is_dispatched: bool = False
    can_dispatch: bool = True
    is_blocked: bool = False
    is_matched: bool = False
    registered_model_name: Optional[str] = None
    registered_product_id: Optional[uuid.UUID] = None
    current_status: Optional[str] = None
    unit_type: Optional[str] = None
    last_dispatched_date: Optional[date] = None
    last_dispatched_shop_name: Optional[str] = None


class OutwardCheckRefRequest(BaseModel):
    shop_id: uuid.UUID
    delivery_reference: str
    transaction_date: date = Field(default_factory=date.today)


class OutwardCheckRefResponse(BaseModel):
    has_warning: bool
    message: Optional[str] = None


from typing import Any, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class OutwardSerialInput(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)
    confirmed_warning: bool = False  # Set to True by staff if confirming case 3 or 4
    unit_type: Optional[str] = None  # "indoor" or "outdoor" for dual-serial models


class OutwardBatchCreate(BaseModel):
    product_id: uuid.UUID
    shop_id: uuid.UUID
    bill_number: Optional[str] = Field(None, max_length=100)
    delivery_reference: Optional[str] = Field(None, max_length=100)
    transaction_date: date = Field(default_factory=date.today)
    serials: list[OutwardSerialInput] = Field(default_factory=list, description="List of scanned serials with confirmation flags")
    unit_types: Optional[dict[str, str]] = Field(default=None, description="Optional mapping of serial to unit_type")
    remarks: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def handle_serial_aliases(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if "serials" not in data or not data["serials"]:
                raw_list = data.get("serial_numbers") or []
                converted = []
                for item in raw_list:
                    if isinstance(item, str):
                        converted.append({"serial_number": item, "confirmed_warning": True})
                    elif isinstance(item, dict):
                        converted.append(item)
                data["serials"] = converted
        return data


class OutwardLineResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    serial_text: str
    serial_number_id: Optional[uuid.UUID] = None
    is_matched: bool
    is_flagged_for_review: bool
    flag_reason: Optional[str] = None
    unit_type: Optional[str] = None
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
    bill_number: Optional[str] = None
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


class BillBatchSummary(BaseModel):
    batch_id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    quantity: int
    matched_count: int
    unmatched_count: int
    flagged_count: int
    lines: list[OutwardLineResponse] = []


class BillDetailResponse(BaseModel):
    bill_number: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: str
    transaction_date: date
    created_at: datetime
    dispatched_by_name: str
    delivery_reference: Optional[str] = None
    remarks: Optional[str] = None
    total_units: int
    total_batches: int
    batches: list[BillBatchSummary] = []


class BillListItem(BaseModel):
    bill_number: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: str
    transaction_date: date
    created_at: datetime
    dispatched_by_name: str
    delivery_reference: Optional[str] = None
    remarks: Optional[str] = None
    total_units: int
    total_batches: int
    models_summary: list[str] = []