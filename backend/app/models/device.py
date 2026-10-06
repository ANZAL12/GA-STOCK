import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, CreatedAtMixin


class Device(Base, PrimaryKeyMixin, CreatedAtMixin):
    """
    A registered mobile phone. The phone sends its hardware device_uid on
    every request; the backend rejects requests from unapproved devices even
    with a valid JWT. Admin approves devices from the web dashboard.
    """
    __tablename__ = "devices"

    # The phone's OS-level unique identifier (e.g. Android ID)
    device_uid: Mapped[str]           = mapped_column(String(255), unique=True, nullable=False, index=True)
    label:      Mapped[Optional[str]] = mapped_column(String(255), nullable=True)   # Friendly name set by admin

    approved_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    # Starts False (pending). Admin flips to True to allow access.
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    def __repr__(self) -> str:
        return f"<Device {self.device_uid!r} active={self.is_active}>"
