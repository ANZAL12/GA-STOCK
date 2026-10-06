from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class InwardValidateSerialRequest(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)


class InwardValidateSerialResponse(BaseModel):
    serial_number: str
    is_valid: bool
    already_exists: bool
    registered_model_name: Optional[str] = None
    registered_model_id: Optional[uuid.UUID] = None
    message: Optional[str] = None


class InwardBatchCreate(BaseModel):
    product_id: uuid.UUID
    transaction_date: date = Field(default_factory=date.today)
    invoice_reference: Optional[str] = Field(None, max_length=100)
    serials: list[str] = Field(..., min_length=1, description="List of scanned serial numbers")
    remarks: Optional[str] = None


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
    invoice_reference: Optional[str] = None
    transaction_date: date
    quantity: int
    received_by_user_id: uuid.UUID
    received_by_name: str
    device_id: Optional[uuid.UUID] = None
    remarks: Optional[str] = None
    created_at: datetime
    serials: list[str] = []