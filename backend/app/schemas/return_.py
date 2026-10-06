from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import InspectionResult, SerialStatus


class ReturnLookupSerialResponse(BaseModel):
    serial_number: str
    found: bool
    was_matched: bool = False
    product_id: Optional[uuid.UUID] = None
    product_name: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    shop_id: Optional[uuid.UUID] = None
    shop_name: Optional[str] = None
    shop_city: Optional[str] = None
    outward_line_id: Optional[uuid.UUID] = None
    current_status: Optional[str] = None
    dispatch_date: Optional[date] = None
    delivery_reference: Optional[str] = None


class ReturnCreateRequest(BaseModel):
    serial_number: str = Field(..., min_length=1, max_length=100)
    product_id: uuid.UUID
    shop_id: uuid.UUID
    outward_line_id: Optional[uuid.UUID] = None
    return_date: date = Field(default_factory=date.today)
    reason: str = Field(..., min_length=1, description="Reason for return")
    condition: Optional[str] = Field(None, max_length=100, description="Physical condition of unit")
    remarks: Optional[str] = None


class ReturnInspectRequest(BaseModel):
    inspection_result: InspectionResult  # available | damaged
    remarks: Optional[str] = None


class ReturnResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    serial_text: str
    serial_number_id: Optional[uuid.UUID] = None
    outward_line_id: Optional[uuid.UUID] = None
    shop_id: uuid.UUID
    shop_name: str
    shop_city: str
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    return_date: date
    reason: str
    condition: Optional[str] = None
    inspection_result: Optional[InspectionResult] = None
    inspected_at: Optional[datetime] = None
    inspected_by_name: Optional[str] = None
    received_by_name: str
    remarks: Optional[str] = None
    created_at: datetime