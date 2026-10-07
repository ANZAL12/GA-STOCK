"""Add inward_type column to inward_batches

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-07 14:10:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0003'
down_revision: Union[str, None] = '0002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'inward_batches',
        sa.Column('inward_type', sa.String(length=50), nullable=False, server_default='stock_in')
    )


def downgrade() -> None:
    op.drop_column('inward_batches', 'inward_type')
