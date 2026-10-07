from datetime import datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class CategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    has_dual_serial: bool = False


class CategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    has_dual_serial: Optional[bool] = None
    is_active: Optional[bool] = None


class CategoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    has_dual_serial: bool = False
    is_active: bool
    created_at: datetime
    product_count: int = 0