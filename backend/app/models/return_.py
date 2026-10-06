import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, Enum, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin
from app.models.enums import InspectionResult


class Return(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    A returned serial number.

    Two cases:
      A) The original dispatch was matched (serial was tracked):
         serial_number_id is known immediately from the outward_line.

      B) The original dispatch was unmatched (old pre-go-live stock):
         At return time the service creates a NEW serial_numbers record for
         this serial, sets serial_number_id to it, and retroactively updates
         the outward_line.serial_number_id to link them.
         From this point on the serial is fully tracked.

    outward_line_id links back to the original dispatch (nullable — staff may
    not always be able to identify the exact dispatch record).

    Return history entry shows: "Dispatched (recorded only) → Returned → Inspected".
    """
    __tablename__ = "returns"

    serial_text:       Mapped[str]                    = mapped_column(String(100), nullable=False, index=True)
    serial_number_id:  Mapped[Optional[uuid.UUID]]    = mapped_column(
        UUID(as_uuid=True), ForeignKey("serial_numbers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    outward_line_id:   Mapped[Optional[uuid.UUID]]    = mapped_column(
        UUID(as_uuid=True), ForeignKey("outward_lines.id", ondelete="SET NULL"), nullable=True
    )
    shop_id:           Mapped[uuid.UUID]              = mapped_column(
        UUID(as_uuid=True), ForeignKey("shops.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    product_id:        Mapped[uuid.UUID]              = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    return_date:       Mapped[date]                   = mapped_column(Date, nullable=False, index=True)
    reason:            Mapped[str]                    = mapped_column(Text, nullable=False)
    condition:         Mapped[Optional[str]]          = mapped_column(String(100), nullable=True)
    received_by_user_id: Mapped[uuid.UUID]            = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True
    )

    # Inspection (filled in after physical check — may be done by admin later)
    inspection_result: Mapped[Optional[InspectionResult]] = mapped_column(
        Enum(InspectionResult, name="inspection_result", native_enum=True), nullable=True
    )
    inspected_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    inspected_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    remarks: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    def __repr__(self) -> str:
        return f"<Return {self.serial_text!r} shop={self.shop_id}>"
