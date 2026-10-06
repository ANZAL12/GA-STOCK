import uuid
from datetime import date
from typing import Optional

from sqlalchemy import Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin


class InwardBatch(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    One inward submission. Staff selects a model, scans N serials, fills in
    the review form, then taps Submit once. All serials are saved in a single
    DB transaction: all succeed or all roll back.

    One batch = one model. Mixed-model inward is two separate batches.
    """
    __tablename__ = "inward_batches"

    product_id:          Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    invoice_reference:   Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    transaction_date:    Mapped[date]          = mapped_column(Date, nullable=False, index=True)
    received_by_user_id: Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True
    )
    quantity: Mapped[int]           = mapped_column(Integer, nullable=False)
    remarks:  Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    def __repr__(self) -> str:
        return f"<InwardBatch product={self.product_id} qty={self.quantity}>"


class InwardLine(Base, PrimaryKeyMixin, CreatedAtMixin):
    """One serial within an inward batch."""
    __tablename__ = "inward_lines"
    __table_args__ = (
        # Belt-and-suspenders: same serial cannot appear twice in one batch.
        UniqueConstraint("batch_id", "serial_number_id", name="uq_inward_lines_batch_serial"),
    )

    batch_id:         Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("inward_batches.id", ondelete="CASCADE"), nullable=False, index=True
    )
    serial_number_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("serial_numbers.id", ondelete="RESTRICT"), nullable=False, index=True
    )
