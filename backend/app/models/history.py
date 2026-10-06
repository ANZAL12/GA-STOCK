import uuid
from typing import Optional

from sqlalchemy import Boolean, Enum, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin
from app.models.enums import HistoryAction, SerialStatus


class SerialHistory(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    Immutable audit trail for every event affecting a serial number.

    Written for:
      - Tracked serials (serial_number_id SET) for all actions.
      - Unmatched outward dispatches (serial_number_id NULL) — the row
        records the dispatch with serial_text only. If the serial is later
        returned and becomes tracked, serial_number_id is back-filled.

    Every history row stores:
      - serial_text  : always, so history is searchable by raw text.
      - from_status / to_status : before and after the status change.
      - shop_id      : set for dispatches and returns.
      - is_matched   : set for dispatch actions (True = matched, False = unmatched/flagged).
      - Contextual FK to the batch or return that caused this event.
      - user_id + device_id : who did it and from where.
    """
    __tablename__ = "serial_history"

    serial_number_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("serial_numbers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    serial_text: Mapped[str] = mapped_column(String(100), nullable=False, index=True)

    action: Mapped[HistoryAction] = mapped_column(
        Enum(HistoryAction, name="history_action", native_enum=True),
        nullable=False,
        index=True,
    )
    # reuse the already-created serial_status type; create_type=False prevents a duplicate CREATE TYPE
    from_status: Mapped[Optional[SerialStatus]] = mapped_column(
        Enum(SerialStatus, name="serial_status", native_enum=True, create_type=False), nullable=True
    )
    to_status: Mapped[Optional[SerialStatus]] = mapped_column(
        Enum(SerialStatus, name="serial_status", native_enum=True, create_type=False), nullable=True
    )

    shop_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shops.id", ondelete="SET NULL"), nullable=True
    )
    inward_batch_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("inward_batches.id", ondelete="SET NULL"), nullable=True
    )
    outward_batch_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("outward_batches.id", ondelete="SET NULL"), nullable=True
    )
    return_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("returns.id", ondelete="SET NULL"), nullable=True
    )

    # True = matched dispatch, False = unmatched or flagged; NULL for non-dispatch events
    is_matched: Mapped[Optional[bool]] = mapped_column(Boolean, nullable=True)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True
    )
    remarks: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    def __repr__(self) -> str:
        return f"<SerialHistory {self.serial_text!r} action={self.action}>"
