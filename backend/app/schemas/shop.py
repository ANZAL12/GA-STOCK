from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class ShopCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    city: Optional[str] = Field(None, max_length=100)
    phone: Optional[str] = Field(None, max_length=30)


class ShopUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    city: Optional[str] = Field(None, max_length=100)
    phone: Optional[str] = Field(None, max_length=30)
    is_active: Optional[bool] = None


class ShopResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    city: Optional[str] = None
    phone: Optional[str] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime
    total_dispatched_count: int = 0


class ShopExcelColumnsResponse(BaseModel):
    filename: str
    columns: list[str]
    suggested_column: Optional[str] = None
    sample_preview: list[str] = []


class ShopExcelImportResponse(BaseModel):
    column_used: str
    total_rows_scanned: int
    unique_shops_found: int
    newly_created_count: int
    already_existing_count: int
    new_shops: list[str] = []
    existing_shops: list[str] = []


class ShopDispatchedSerial(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    serial_text: str
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    transaction_date: date
    delivery_reference: Optional[str] = None
    is_matched: bool
    is_flagged_for_review: bool
    status_label: str  # "Matched" or "Recorded only" or "Flagged"