import uuid
from datetime import date, datetime
from typing import List, Optional

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CreatedAtMixin, PrimaryKeyMixin, TimestampMixin


class TallyConfig(Base, PrimaryKeyMixin, TimestampMixin):
    """
    Tally connection configuration and sync state.
    Single-row configuration table (id is fixed or managed).
    """
    __tablename__ = "tally_configs"

    host: Mapped[str] = mapped_column(String(255), default="localhost", nullable=False)
    port: Mapped[int] = mapped_column(Integer, default=9000, nullable=False)
    tally_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)  # Optional explicit full URL
    company_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    auto_sync: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    sync_interval_minutes: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    last_sync_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    last_sync_status: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)  # SUCCESS, FAILED, IN_PROGRESS
    last_sync_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    last_alter_id: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    agent_token: Mapped[Optional[str]] = mapped_column(String(100), unique=True, nullable=True)


class TallySalesVoucher(Base, PrimaryKeyMixin, TimestampMixin):
    """
    Sales voucher imported from TallyPrime.
    STRICTLY NO FINANCIAL DATA: only invoice metadata, party info, and inventory lines.
    """
    __tablename__ = "tally_sales_vouchers"

    guid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    alter_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, index=True)
    master_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    voucher_number: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    voucher_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    voucher_type: Mapped[str] = mapped_column(String(100), default="Sales", nullable=False, index=True)
    party_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    party_ledger_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    buyer_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    address: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    state_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    company_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)

    # Dispatch / Transport Details
    vehicle_number: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
    transporter_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    delivery_note: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    destination: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    is_cancelled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)

    # GA STOCK tracking
    is_processed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    processed_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    raw_metadata: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)

    # Relationship to items
    items: Mapped[List["TallyVoucherItem"]] = relationship(
        "TallyVoucherItem",
        back_populates="voucher",
        cascade="all, delete-orphan",
        order_by="TallyVoucherItem.created_at",
        lazy="selectin",
    )


class TallyVoucherItem(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    Inventory item inside a Tally Sales Voucher.
    STRICTLY NO FINANCIAL DATA: only item name, quantity, unit, godown, batch.
    """
    __tablename__ = "tally_voucher_items"

    voucher_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tally_sales_vouchers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    item_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    item_code: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
    product_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("products.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    quantity: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    uom: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    raw_qty_text: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    godown_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    batch_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    batch_details: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)

    voucher: Mapped["TallySalesVoucher"] = relationship("TallySalesVoucher", back_populates="items")


class TallySyncHistory(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    Audit record of each synchronization run between Tally and GA STOCK.
    """
    __tablename__ = "tally_sync_histories"

    sync_source: Mapped[str] = mapped_column(String(50), default="DIRECT_HTTP", nullable=False, index=True)
    company_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(50), default="IN_PROGRESS", nullable=False, index=True)  # SUCCESS, FAILED, IN_PROGRESS
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    vouchers_fetched: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    vouchers_created: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    vouchers_updated: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    vouchers_cancelled: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    from_date: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    to_date: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    last_alter_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    details: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)

