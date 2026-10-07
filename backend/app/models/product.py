import uuid
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, PrimaryKeyMixin, TimestampMixin


class Product(Base, PrimaryKeyMixin, TimestampMixin):
    """
    A product model — e.g. "Samsung 43 inch LED TV".

    Stock counting rules:
      opening_stock_qty  Admin sets this once at product creation.
                         Represents pre-go-live units in the godown (no serials).
      current_stock_qty  Running total. Starts == opening_stock_qty.
                         +1 per inward serial scanned.
                         -1 per outward serial (matched OR unmatched), floored at 0.
      has_had_inward     Flipped to True on the first inward scan ever.

    Out-of-stock reminder logic (applied in the API layer):
      Show "No tracked stock left" when current_stock_qty == 0 AND has_had_inward == True.
      Never show the reminder for products that have never had an inward scan
      (they may still have untracked opening stock).
    """
    __tablename__ = "products"

    name:                   Mapped[str]           = mapped_column(String(255), nullable=False)
    sku:                    Mapped[Optional[str]]  = mapped_column(String(100), unique=True, nullable=True)
    category_id:            Mapped[uuid.UUID]      = mapped_column(
        UUID(as_uuid=True), ForeignKey("categories.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    brand:                  Mapped[str]            = mapped_column(String(100), nullable=False)
    model:                  Mapped[str]            = mapped_column(String(255), nullable=False)
    # "43 inch" / "260 L" / "7 kg" / "1.5 Ton"
    size_capacity:          Mapped[Optional[str]]  = mapped_column(String(100), nullable=True)
    unit:                   Mapped[str]            = mapped_column(String(50),  nullable=False, default="piece")
    serial_number_required: Mapped[bool]           = mapped_column(Boolean, nullable=False, default=True)
    description:            Mapped[Optional[str]]  = mapped_column(Text, nullable=True)

    # Stock counts — maintained atomically in service-layer transactions
    opening_stock_qty: Mapped[int]  = mapped_column(Integer, nullable=False, default=0)
    current_stock_qty: Mapped[int]  = mapped_column(Integer, nullable=False, default=0)
    has_had_inward:    Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    def __repr__(self) -> str:
        return f"<Product {self.name!r}>"
