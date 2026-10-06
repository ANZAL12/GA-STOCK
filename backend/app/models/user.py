from sqlalchemy import Boolean, Enum, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin
from app.models.enums import UserRole


class User(Base, PrimaryKeyMixin, TimestampMixin):
    __tablename__ = "users"

    username:      Mapped[str]      = mapped_column(String(100), unique=True, nullable=False, index=True)
    full_name:     Mapped[str]      = mapped_column(String(255), nullable=False)
    password_hash: Mapped[str]      = mapped_column(String(255), nullable=False)
    role:          Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role", native_enum=True),
        nullable=False,
        default=UserRole.staff,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    def __repr__(self) -> str:
        return f"<User {self.username!r} role={self.role}>"
