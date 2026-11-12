from datetime import date, datetime
import uuid
from typing import Any, Dict, List, Optional, Union
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


def _safe_uuid(v: Any) -> Optional[uuid.UUID]:
    if not v:
        return None
    if isinstance(v, uuid.UUID):
        return v
    try:
        return uuid.UUID(str(v).strip())
    except Exception:
        return None


class OutwardCheckSerialRequest(BaseModel):
    product_id: Optional[Union[uuid.UUID, str]] = None
    shop_id: Optional[Union[uuid.UUID, str]] = None
    serial_number: str = Field(..., min_length=1, max_length=100)

    @field_validator("product_id", mode="before")
    @classmethod
    def validate_product_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

    @field_validator("shop_id", mode="before")
    @classmethod
    def validate_shop_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)


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
    is_damaged: bool = False
    registered_model_name: Optional[str] = None
    registered_product_id: Optional[uuid.UUID] = None
    current_status: Optional[str] = None
    unit_type: Optional[str] = None
    last_dispatched_date: Optional[date] = None
    last_dispatched_shop_name: Optional[str] = None


class OutwardCheckRefRequest(BaseModel):
    shop_id: Optional[Union[uuid.UUID, str]] = None
    delivery_reference: str
    transaction_date: date = Field(default_factory=date.today)

    @field_validator("shop_id", mode="before")
    @classmethod
    def validate_shop_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)


class OutwardCheckRefResponse(BaseModel):
    has_warning: bool
    message: Optional[str] = None


class OutwardSerialInput(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)
    confirmed_warning: bool = False  # Set to True by staff if confirming case 3 or 4
    unit_type: Optional[str] = None  # "indoor" or "outdoor" for dual-serial models


class OutwardBatchCreate(BaseModel):
    product_id: Optional[Union[uuid.UUID, str]] = None
    shop_id: Optional[Union[uuid.UUID, str]] = None
    bill_number: Optional[str] = Field(None, max_length=100)
    delivery_reference: Optional[str] = Field(None, max_length=100)
    transaction_date: date = Field(default_factory=date.today)
    serials: list[OutwardSerialInput] = Field(default_factory=list, description="List of scanned serials with confirmation flags")
    unit_types: Optional[dict[str, str]] = Field(default=None, description="Optional mapping of serial to unit_type")
    remarks: Optional[str] = None
    tally_voucher_id: Optional[Union[uuid.UUID, str]] = None

    @field_validator("product_id", mode="before")
    @classmethod
    def validate_product_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

    @field_validator("shop_id", mode="before")
    @classmethod
    def validate_shop_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

    @field_validator("tally_voucher_id", mode="before")
    @classmethod
    def validate_tally_voucher_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

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


class OutwardProductBatchItem(BaseModel):
    product_id: Optional[Union[uuid.UUID, str]] = None
    product_name: Optional[str] = None
    product_model: Optional[str] = None
    product_brand: Optional[str] = None
    serials: list[OutwardSerialInput] = Field(default_factory=list, description="List of scanned serials with confirmation flags")
    unit_types: Optional[dict[str, str]] = Field(default=None, description="Optional mapping of serial to unit_type")

    @field_validator("product_id", mode="before")
    @classmethod
    def validate_product_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

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


class OutwardMultiBatchCreate(BaseModel):
    shop_id: Optional[Union[uuid.UUID, str]] = None
    shop_name: Optional[str] = None
    bill_number: Optional[str] = Field(None, max_length=100)
    delivery_reference: Optional[str] = Field(None, max_length=100)
    transaction_date: date = Field(default_factory=date.today)
    remarks: Optional[str] = None
    items: list[OutwardProductBatchItem] = Field(..., min_length=1)
    client_request_id: Optional[str] = Field(None, max_length=100)
    tally_voucher_id: Optional[Union[uuid.UUID, str]] = None

    @field_validator("shop_id", mode="before")
    @classmethod
    def validate_shop_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)

    @field_validator("tally_voucher_id", mode="before")
    @classmethod
    def validate_tally_voucher_id(cls, v: Any) -> Optional[uuid.UUID]:
        return _safe_uuid(v)


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
    is_cancelled: bool = False


class OutwardBatchResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: Optional[str] = None
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
    is_cancelled: bool = False
    cancelled_at: Optional[datetime] = None
    cancel_reason: Optional[str] = None
    created_at: datetime
    lines: list[OutwardLineResponse] = []


class OutwardMultiBatchResponse(BaseModel):
    batches: list[OutwardBatchResponse] = []
    total_units: int
    total_matched: int
    total_unmatched: int
    total_flagged: int
    bill_number: Optional[str] = None
    delivery_reference: Optional[str] = None


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
    is_cancelled: bool = False
    lines: list[OutwardLineResponse] = []


class BillDetailResponse(BaseModel):
    bill_number: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: Optional[str] = None
    shop_gstin: Optional[str] = None
    shop_address: Optional[str] = None
    shop_state: Optional[str] = None
    shop_pincode: Optional[str] = None
    shop_phone: Optional[str] = None
    shop_contact_person: Optional[str] = None
    vehicle_number: Optional[str] = None
    transporter_name: Optional[str] = None
    delivery_note: Optional[str] = None
    destination: Optional[str] = None
    transaction_date: date
    created_at: datetime
    dispatched_by_name: str
    delivery_reference: Optional[str] = None
    remarks: Optional[str] = None
    total_units: int
    total_batches: int
    is_cancelled: bool = False
    cancelled_at: Optional[datetime] = None
    cancelled_by_name: Optional[str] = None
    cancel_reason: Optional[str] = None
    batches: list[BillBatchSummary] = []


class BillListItem(BaseModel):
    bill_number: str
    shop_id: uuid.UUID
    shop_name: str
    shop_city: Optional[str] = None
    shop_gstin: Optional[str] = None
    shop_address: Optional[str] = None
    shop_state: Optional[str] = None
    shop_phone: Optional[str] = None
    vehicle_number: Optional[str] = None
    transporter_name: Optional[str] = None
    delivery_note: Optional[str] = None
    destination: Optional[str] = None
    transaction_date: date
    created_at: datetime
    dispatched_by_name: str
    delivery_reference: Optional[str] = None
    remarks: Optional[str] = None
    total_units: int
    total_batches: int
    is_cancelled: bool = False
    cancelled_at: Optional[datetime] = None
    cancelled_by_name: Optional[str] = None
    cancel_reason: Optional[str] = None
    models_summary: list[str] = []


class CancelBillRequest(BaseModel):
    reason: Optional[str] = None


class CancelBillResponse(BaseModel):
    success: bool = True
    bill_number: str
    message: str
    cancelled_at: datetime
    cancelled_by_name: str
    returned_serials_count: int
    ignored_serials_count: int
    returned_serials: list[str] = []
    ignored_serials: list[str] = []
    restored_models: list[dict] = []


class UpdateOutwardLineRequest(BaseModel):
    new_serial_number: str = Field(..., min_length=1, max_length=100, description="New serial number text")


class UpdateOutwardLineResponse(BaseModel):
    success: bool = True
    message: str
    line: OutwardLineResponse
    batch_id: uuid.UUID
    matched_count: int
    unmatched_count: int
    flagged_count: int
    product_id: uuid.UUID
    current_stock_qty: int


class DeleteOutwardLineResponse(BaseModel):
    success: bool = True
    message: str
    deleted_serial: str
    was_matched: bool
    action_taken: str  # "returned_to_inward_stock" or "discarded_with_history"
    batch_id: uuid.UUID
    batch_remaining_quantity: int
    product_id: uuid.UUID
    current_stock_qty: int