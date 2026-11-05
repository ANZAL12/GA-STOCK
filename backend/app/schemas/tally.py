import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field


class TallyConfigBase(BaseModel):
    host: str = Field(default="localhost", min_length=1, max_length=255)
    port: int = Field(default=9000, ge=1, le=65535)
    tally_url: Optional[str] = Field(None, max_length=500)
    company_name: Optional[str] = Field(None, max_length=255)
    is_enabled: bool = True
    auto_sync: bool = True
    sync_interval_minutes: int = Field(default=1, ge=1, le=1440)


class TallyConfigResponse(TallyConfigBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    last_sync_at: Optional[datetime] = None
    last_sync_status: Optional[str] = None
    last_sync_message: Optional[str] = None
    last_alter_id: int = 0
    agent_token: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class TallyConnectRequest(BaseModel):
    host: Optional[str] = "localhost"
    port: Optional[int] = 9000
    tally_url: Optional[str] = None
    company_name: Optional[str] = None
    is_enabled: Optional[bool] = True
    auto_sync: Optional[bool] = True
    sync_interval_minutes: Optional[int] = 1


class TallyConnectResponse(BaseModel):
    status: str
    message: str
    is_connected: bool
    active_company: Optional[str] = None
    available_companies: List[str] = []
    config: Optional[TallyConfigResponse] = None


class TallyCompanyResponse(BaseModel):
    name: str
    starting_from: Optional[str] = None
    ending_at: Optional[str] = None
    is_active: bool = False


class TallyStatusResponse(BaseModel):
    is_connected: bool
    host: str
    port: int
    tally_url: Optional[str] = None
    active_company: Optional[str] = None
    is_enabled: bool
    auto_sync: bool
    sync_interval_minutes: int
    last_sync_at: Optional[datetime] = None
    last_sync_status: Optional[str] = None
    last_sync_message: Optional[str] = None
    last_alter_id: int = 0
    available_companies: List[str] = []
    total_vouchers: int = 0
    pending_vouchers: int = 0
    is_syncing: bool = False
    agent_configured: bool = False


class TallyVoucherItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    voucher_id: uuid.UUID
    item_name: str
    item_code: Optional[str] = None
    product_id: Optional[uuid.UUID] = None
    quantity: float
    uom: Optional[str] = None
    raw_qty_text: Optional[str] = None
    godown_name: Optional[str] = None
    batch_name: Optional[str] = None
    batch_details: Optional[Dict[str, Any]] = None
    matched_product_name: Optional[str] = None
    matched_product_model: Optional[str] = None
    created_at: datetime


class TallySalesVoucherResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    guid: str
    alter_id: Optional[int] = None
    master_id: Optional[int] = None
    voucher_number: str
    voucher_date: date
    voucher_type: str = "Sales"
    party_name: str
    party_ledger_name: Optional[str] = None
    buyer_name: Optional[str] = None
    address: Optional[str] = None
    state_name: Optional[str] = None
    company_name: Optional[str] = None
    is_cancelled: bool = False
    is_deleted: bool = False
    is_processed: bool = False
    processed_at: Optional[datetime] = None
    item_count: int = 0
    total_quantity: float = 0.0
    godowns: List[str] = []
    created_at: datetime
    updated_at: datetime


class TallySalesVoucherDetailResponse(TallySalesVoucherResponse):
    items: List[TallyVoucherItemResponse] = []
    notes: Optional[str] = None
    raw_metadata: Optional[Dict[str, Any]] = None


class TallySyncRequest(BaseModel):
    from_date: Optional[str] = None  # YYYY-MM-DD or YYYYMMDD
    to_date: Optional[str] = None    # YYYY-MM-DD or YYYYMMDD
    company_name: Optional[str] = None
    force_full: bool = False


class TallySyncResponse(BaseModel):
    status: str  # SUCCESS, FAILED
    message: str
    vouchers_fetched: int = 0
    vouchers_created: int = 0
    vouchers_updated: int = 0
    vouchers_cancelled: int = 0
    duration_seconds: float = 0.0
    history_id: Optional[uuid.UUID] = None


class TallySyncHistoryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sync_source: str
    company_name: Optional[str] = None
    status: str
    started_at: datetime
    completed_at: Optional[datetime] = None
    vouchers_fetched: int = 0
    vouchers_created: int = 0
    vouchers_updated: int = 0
    vouchers_cancelled: int = 0
    error_message: Optional[str] = None


class TallySyncStatusResponse(BaseModel):
    last_sync_at: Optional[datetime] = None
    last_sync_status: Optional[str] = None
    last_sync_message: Optional[str] = None
    is_syncing: bool = False
    recent_history: List[TallySyncHistoryItemResponse] = []


class TallyAgentPushRequest(BaseModel):
    company_name: Optional[str] = None
    vouchers: List[Dict[str, Any]]


class TallyAgentPushResponse(BaseModel):
    status: str
    received_count: int
    created_count: int
    updated_count: int
    cancelled_count: int

