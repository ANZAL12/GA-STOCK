"""Add bill_number column to outward_batches

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-07 15:55:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0004'
down_revision: Union[str, None] = '0003'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'outward_batches',
        sa.Column('bill_number', sa.String(length=100), nullable=True)
    )
    op.create_index(
        'ix_outward_batches_bill_number',
        'outward_batches',
        ['bill_number'],
        unique=False
    )


def downgrade() -> None:
    op.drop_index('ix_outward_batches_bill_number', table_name='outward_batches')
    op.drop_column('outward_batches', 'bill_number')
