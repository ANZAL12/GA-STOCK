"""Add performance indexes for large-scale serial and timeline queries

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-01 12:35:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0006'
down_revision: Union[str, None] = '0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Indexes on serial_numbers for chronological ordering and status filtering
    op.create_index(
        'ix_serial_numbers_created_at',
        'serial_numbers',
        [sa.text('created_at DESC')],
    )
    op.create_index(
        'ix_serial_numbers_status_created_at',
        'serial_numbers',
        ['status', sa.text('created_at DESC')],
    )

    # 2. Indexes on outward_lines and inward_lines for chronological queries
    op.create_index(
        'ix_outward_lines_created_at',
        'outward_lines',
        [sa.text('created_at DESC')],
    )
    op.create_index(
        'ix_inward_lines_created_at',
        'inward_lines',
        [sa.text('created_at DESC')],
    )

    # 3. Composite index on serial_history for fast serial history lookups
    op.create_index(
        'ix_serial_history_snid_action',
        'serial_history',
        ['serial_number_id', 'action'],
    )


def downgrade() -> None:
    op.drop_index('ix_serial_history_snid_action', table_name='serial_history')
    op.drop_index('ix_inward_lines_created_at', table_name='inward_lines')
    op.drop_index('ix_outward_lines_created_at', table_name='outward_lines')
    op.drop_index('ix_serial_numbers_status_created_at', table_name='serial_numbers')
    op.drop_index('ix_serial_numbers_created_at', table_name='serial_numbers')
