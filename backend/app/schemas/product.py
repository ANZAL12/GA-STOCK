from datetime import datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field, computed_field


class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    sku: Optional[str] = Field(None, max_length=100)
    category_id: uuid.UUID
    brand: str = Field(..., min_length=1, max_length=100)
    model: str = Field(..., min_length=1, max_length=255)
    size_capacity: Optional[str] = Field(None, max_length=100)
    unit: str = Field("piece", max_length=50)
    serial_number_required: bool = True
    description: Optional[str] = None
    opening_stock_qty: int = Field(0, ge=0)


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    sku: Optional[str] = Field(None, max_length=100)
    category_id: Optional[uuid.UUID] = None
    brand: Optional[str] = Field(None, min_length=1, max_length=100)
    model: Optional[str] = Field(None, min_length=1, max_length=255)
    size_capacity: Optional[str] = None
    unit: Optional[str] = Field(None, max_length=50)
    serial_number_required: Optional[bool] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None
    # opening_stock_qty can only be adjusted if has_had_inward is False
    opening_stock_qty: Optional[int] = Field(None, ge=0)


class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    sku: Optional[str] = None
    category_id: uuid.UUID
    category_name: Optional[str] = None
    brand: str
    model: str
    size_capacity: Optional[str] = None
    unit: str
    serial_number_required: bool
    description: Optional[str] = None
    opening_stock_qty: int
    current_stock_qty: int
    has_had_inward: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime

    @computed_field
    def out_of_stock_reminder(self) -> bool:
        """
        True only when tracked count is 0 AND the product has had
        at least one inward since go-live.
        """
        return self.current_stock_qty == 0 and self.has_had_inward

    @computed_field
    def stock_status_label(self) -> str:
        if self.current_stock_qty == 0 and self.has_had_inward:
            return "No tracked stock left"
        if self.current_stock_qty == 0 and not self.has_had_inward:
            return "0 units (untracked)"
        return f"{self.current_stock_qty} in stock"