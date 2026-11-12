from typing import Optional

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin


class Shop(Base, PrimaryKeyMixin, TimestampMixin):
    """
    Dispatch destination managed by admin.
    Shops with any dispatch history are never hard-deleted — only deactivated.
    """
    __tablename__ = "shops"

    name:           Mapped[str]           = mapped_column(String(255), nullable=False)
    city:           Mapped[Optional[str]] = mapped_column(String(100), nullable=True, default=None)
    phone:          Mapped[Optional[str]] = mapped_column(String(50),  nullable=True, default=None)
    gstin:          Mapped[Optional[str]] = mapped_column(String(50),  nullable=True, default=None)
    address:        Mapped[Optional[str]] = mapped_column(String(500), nullable=True, default=None)
    state:          Mapped[Optional[str]] = mapped_column(String(100), nullable=True, default=None)
    pincode:        Mapped[Optional[str]] = mapped_column(String(20),  nullable=True, default=None)
    contact_person: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, default=None)
    email:          Mapped[Optional[str]] = mapped_column(String(100), nullable=True, default=None)
    tally_guid:     Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True, default=None)
    source:         Mapped[str]           = mapped_column(String(50),  nullable=False, default="TALLY")
    is_active:      Mapped[bool]          = mapped_column(Boolean,     nullable=False, default=True)

    def __repr__(self) -> str:
        return f"<Shop {self.name!r} city={self.city!r}>"
