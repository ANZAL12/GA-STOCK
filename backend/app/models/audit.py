import uuid
from typing import Optional

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin


class AuditLog(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    High-level audit trail for admin actions: product creation/edit,
    shop changes, user management, device approval, stock adjustments, etc.

    Separate from serial_history which covers per-serial events.
    details (JSONB) stores a before/after snapshot or the relevant payload.

    Examples of action strings:
      PRODUCT_CREATED, PRODUCT_DEACTIVATED
      SHOP_CREATED, SHOP_EDITED, SHOP_DEACTIVATED
      USER_CREATED, USER_DEACTIVATED
      DEVICE_APPROVED, DEVICE_DEACTIVATED
      INWARD_SUBMITTED, OUTWARD_SUBMITTED
      RETURN_RECORDED, SERIAL_STATUS_CHANGED
    """
    __tablename__ = "audit_log"

    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True
    )
    action:      Mapped[str]           = mapped_column(String(100), nullable=False, index=True)
    entity_type: Mapped[str]           = mapped_column(String(50),  nullable=False, index=True)
    entity_id:   Mapped[Optional[str]] = mapped_column(String(100), nullable=True,  index=True)
    details:     Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    ip_address:  Mapped[Optional[str]] = mapped_column(String(45),  nullable=True)

    def __repr__(self) -> str:
        return f"<AuditLog {self.action!r} {self.entity_type}:{self.entity_id}>"
