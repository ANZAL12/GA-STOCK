"""Enforce non-negative current_stock_qty on products

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-26 17:50:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0005'
down_revision: Union[str, None] = '0004'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Clean any existing negative stock
    op.execute("UPDATE products SET current_stock_qty = 0 WHERE current_stock_qty < 0")
    # 2. Re-create non-negative check constraint
    op.create_check_constraint('ck_products_stock_non_negative', 'products', 'current_stock_qty >= 0')


def downgrade() -> None:
    op.drop_constraint('ck_products_stock_non_negative', 'products', type_='check')
