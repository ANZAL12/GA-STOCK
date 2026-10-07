from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin


class Category(Base, PrimaryKeyMixin, TimestampMixin):
    __tablename__ = "categories"

    name:            Mapped[str]  = mapped_column(String(100), unique=True, nullable=False)
    has_dual_serial: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_active:       Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    def __repr__(self) -> str:
        return f"<Category {self.name!r}>"
