from typing import Optional

from sqlalchemy import Boolean, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin


class Category(Base, PrimaryKeyMixin, TimestampMixin):
    __tablename__ = "categories"
    __table_args__ = (
        Index("ix_categories_name", "name", unique=True),
    )

    name:               Mapped[str]           = mapped_column(String(100), nullable=False)
    has_dual_serial:    Mapped[bool]          = mapped_column(Boolean, nullable=False, default=False)
    is_active:          Mapped[bool]          = mapped_column(Boolean, nullable=False, default=True)
    tally_guid:         Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
    tally_parent_group: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    source:             Mapped[str]           = mapped_column(String(50), nullable=False, default="TALLY")

    def __repr__(self) -> str:
        return f"<Category {self.name!r}>"
