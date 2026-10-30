from datetime import date, datetime
import uuid
from typing import Any, Optional
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
    is_damaged: bool = False
    is_dispatched_damaged: bool = False
    flag_reason: Optional[str] = None


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
    is_damaged: bool = False
    is_dispatched_damaged: bool = False
    flag_reason: Optional[str] = None


class SerialListResponse(BaseModel):
    total: int
    items: list[SerialListItem]


class BulkSerialCheckRequest(BaseModel):
    serials: list[str] = Field(default_factory=list, description="List of serial numbers to verify against the database")
    serial_numbers: Optional[list[str]] = None


class ExistingSerialInfo(BaseModel):
    serial_number: str
    product_id: uuid.UUID
    product_name: str
    brand: str
    model: str
    status: str
    status_label: str
    unit_type: Optional[str] = None
    exists: bool = True


class BulkSerialCheckResponse(BaseModel):
    existing: dict[str, ExistingSerialInfo] = {}
    existing_count: int = 0
    new_count: int = 0
    results: list[ExistingSerialInfo] = []


class ExcelSerialImportItem(BaseModel):
    serial_number: str
    product_id: Optional[uuid.UUID] = None
    model_name: Optional[str] = None
    unit_type: Optional[str] = None
    row_index: Optional[int] = None


class ExcelSerialImportRequest(BaseModel):
    items: list[ExcelSerialImportItem] = Field(..., min_length=1)
    default_product_id: Optional[uuid.UUID] = None
    batch_reference: Optional[str] = None
    inward_reference: Optional[str] = None
    remarks: Optional[str] = None
    skip_existing: bool = True


class ExcelSerialImportResponse(BaseModel):
    total_submitted: int = 0
    total_processed: int = 0
    imported_count: int = 0
    skipped_existing_count: int = 0
    skipped_invalid_count: int = 0
    skipped_serials: list[Any] = []
    imported_serials: list[str] = []
    products_updated: list[dict[str, Any]] = []
    inward_batch_ids: list[str] = []
    message: str = "Serials imported successfully."


class ExcelSerialPreviewResponse(BaseModel):
    filename: str
    sheet_names: list[str] = []
    selected_sheet: str
    columns: list[str] = []
    suggested_serial_column: Optional[str] = None
    suggested_model_column: Optional[str] = None
    suggested_brand_column: Optional[str] = None
    suggested_unit_type_column: Optional[str] = None
    total_rows: int
    sample_rows: list[dict[str, str]] = []