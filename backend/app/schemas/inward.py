from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class InwardValidateSerialRequest(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)
    inward_type: Optional[str] = Field(default="stock_in", description="'stock_in', 'return', or 'damaged'")


class InwardValidateSerialResponse(BaseModel):
    serial_number: str
    is_valid: bool
    already_exists: bool
    requires_confirmation: bool = False
    warning_not_dispatched: bool = False
    registered_model_name: Optional[str] = None
    registered_model_id: Optional[uuid.UUID] = None
    message: Optional[str] = None


from typing import Any, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class InwardBatchCreate(BaseModel):
    product_id: uuid.UUID
    inward_type: str = Field(default="stock_in", description="'stock_in', 'return', or 'damaged'")
    transaction_date: date = Field(default_factory=date.today)
    invoice_reference: Optional[str] = Field(None, max_length=100)
    serials: list[str] = Field(default_factory=list, description="List of scanned serial numbers")
    unit_types: Optional[dict[str, str]] = Field(default=None, description="Optional mapping of serial to unit_type (indoor/outdoor)")
    remarks: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def handle_serial_aliases(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if "serials" not in data or not data["serials"]:
                if "serial_numbers" in data:
                    data["serials"] = data["serial_numbers"]
        return data


class InwardLineResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    serial_number_id: uuid.UUID
    serial_number: str


class InwardBatchResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    inward_type: str = "stock_in"
    invoice_reference: Optional[str] = None
    transaction_date: date
    quantity: int
    received_by_user_id: uuid.UUID
    received_by_name: str
    device_id: Optional[uuid.UUID] = None
    remarks: Optional[str] = None
    created_at: datetime
    serials: list[str] = []