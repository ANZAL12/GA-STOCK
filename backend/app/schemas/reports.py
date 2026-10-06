from datetime import date, datetime
import uuid
from typing import Optional
from pydantic import BaseModel, ConfigDict


class NeedsAttentionPills(BaseModel):
    out_of_stock_models: int = 0
    flagged_outward_reviews: int = 0
    damaged_units: int = 0
    under_repair_units: int = 0
    pending_devices: int = 0
    all_clear: bool = True


class OverviewSummaryResponse(BaseModel):
    tracked_items_on_shelves: int
    received_since_golive: int
    inward_today: int
    outward_today: int
    recorded_only_today: int
    needs_attention: NeedsAttentionPills


class StockByModelItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_id: uuid.UUID
    name: str
    brand: str
    model: str
    category_name: str
    sku: Optional[str] = None
    available_count: int
    dispatched_count: int
    damaged_count: int
    total_received: int
    unmatched_dispatched_count: int
    current_stock_qty: int
    out_of_stock_reminder: bool
    reminder_label: Optional[str] = None


class TodayTimelineItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    timestamp: datetime
    action: str
    serial_number: str
    product_name: str
    shop_name: Optional[str] = None
    user_name: str
    dot_color: str  # "green" | "amber" | "red" | "indigo"
    description: str