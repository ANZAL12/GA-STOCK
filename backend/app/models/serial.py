import uuid
from typing import Optional

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin
from app.models.enums import SerialStatus


class SerialNumber(Base, PrimaryKeyMixin, TimestampMixin):
    """
    A tracked serial number. Created when a serial is scanned at inward.
    Can also be created retroactively when an unmatched-outward serial is returned
    (the return service creates the record and links it back to the outward line).

    serial_number is globally unique — no two products can share a serial.
    The DB enforces this with a unique index.
    """
    __tablename__ = "serial_numbers"

    serial_number: Mapped[str]           = mapped_column(String(100), unique=True, nullable=False, index=True)
    product_id:    Mapped[uuid.UUID]     = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    status: Mapped[SerialStatus] = mapped_column(
        Enum(SerialStatus, name="serial_status", native_enum=True),
        nullable=False,
        default=SerialStatus.available,
        index=True,
    )
    # Denormalised: the last shop this serial was dispatched to (or returned from).
    # Kept in sync by the service layer so the serial card renders without extra joins.
    last_shop_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shops.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Unit type for dual-serial models (e.g. "indoor" or "outdoor")
    unit_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    def __repr__(self) -> str:
        return f"<SerialNumber {self.serial_number!r} status={self.status}>"
