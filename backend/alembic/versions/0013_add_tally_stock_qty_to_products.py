"""Add tally_stock_qty to products

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-07 20:45:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0013'
down_revision: Union[str, None] = '0012'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('products', sa.Column('tally_stock_qty', sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column('products', 'tally_stock_qty')

