"""Allow negative current_stock_qty on products

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-07 13:45:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0002'
down_revision: Union[str, None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('ck_products_stock_non_negative', 'products', type_='check')


def downgrade() -> None:
    op.create_check_constraint('ck_products_stock_non_negative', 'products', 'current_stock_qty >= 0')
