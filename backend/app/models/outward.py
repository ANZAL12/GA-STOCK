import uuid
from datetime import date
from typing import Optional

from sqlalchemy import Boolean, Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin


class OutwardBatch(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    One outward submission. Staff selects shop + model, scans N serials,
    fills in the review form, then taps Submit once.

    One batch = one shop + one model. The batch stores aggregate counts
    (matched / unmatched / flagged) so the review screen can show them
    without scanning every line.
    """
    __tablename__ = "outward_batches"

    product_id:             Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    shop_id:                Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("shops.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    delivery_reference:     Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    transaction_date:       Mapped[date]          = mapped_column(Date, nullable=False, index=True)
    dispatched_by_user_id:  Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True
    )
    quantity:       Mapped[int] = mapped_column(Integer, nullable=False)
    matched_count:  Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    unmatched_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    flagged_count:  Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    remarks: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    def __repr__(self) -> str:
        return f"<OutwardBatch shop={self.shop_id} qty={self.quantity}>"


class OutwardLine(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    One serial line within an outward batch.

    The four cases from spec §5:
      Case 1 — Matched:
          serial_number_id SET, is_matched=True,  is_flagged=False
          The tracked serial is marked Dispatched; stock count -1.
      Case 2 — Unmatched (old stock, not in system):
          serial_number_id NULL, is_matched=False, is_flagged=False
          Recorded only; stock count -1 (floored at 0); NOT an error.
      Case 3 — Known but not Available (wrong status):
          serial_number_id SET, is_matched=False, is_flagged=True
          Staff confirmed; flagged for admin review; stock count -1.
      Case 4 — Known but wrong model:
          serial_number_id SET, is_matched=False, is_flagged=True
          Staff confirmed; flagged for admin review; stock count -1.

    serial_text is always stored (the raw scanned value) so unmatched and
    flagged records are fully searchable without joining serial_numbers.

    shop_id and transaction_date are denormalised from the parent batch for
    efficient querying (shop dispatch list, unmatched outward report).
    """
    __tablename__ = "outward_lines"
    __table_args__ = (
        # Prevents the same serial being scanned twice in one batch at the DB level.
        UniqueConstraint("batch_id", "serial_text", name="uq_outward_lines_batch_serial"),
    )

    batch_id:     Mapped[uuid.UUID]           = mapped_column(
        UUID(as_uuid=True), ForeignKey("outward_batches.id", ondelete="CASCADE"), nullable=False, index=True
    )
    serial_text:  Mapped[str]                 = mapped_column(String(100), nullable=False, index=True)
    serial_number_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("serial_numbers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Model selected at scan time — may differ from serial's registered model if flagged.
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    # Denormalised from OutwardBatch
    shop_id:          Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shops.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    transaction_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)

    is_matched:           Mapped[bool]          = mapped_column(Boolean, nullable=False, default=False, index=True)
    is_flagged_for_review: Mapped[bool]         = mapped_column(Boolean, nullable=False, default=False, index=True)
    flag_reason:          Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    unit_type:            Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    def __repr__(self) -> str:
        return f"<OutwardLine {self.serial_text!r} matched={self.is_matched}>"
