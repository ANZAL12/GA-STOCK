"""Add cancellation columns to outward_batches and outward_lines

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-02 13:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = '0007'
down_revision: Union[str, None] = '0006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. OutwardBatch cancellation columns
    op.add_column(
        'outward_batches',
        sa.Column('is_cancelled', sa.Boolean(), nullable=False, server_default=sa.text('false'))
    )
    op.add_column(
        'outward_batches',
        sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        'outward_batches',
        sa.Column('cancelled_by_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    )
    op.add_column(
        'outward_batches',
        sa.Column('cancel_reason', sa.Text(), nullable=True)
    )
    op.create_index(
        'ix_outward_batches_is_cancelled',
        'outward_batches',
        ['is_cancelled'],
        unique=False
    )

    # 2. OutwardLine cancellation column
    op.add_column(
        'outward_lines',
        sa.Column('is_cancelled', sa.Boolean(), nullable=False, server_default=sa.text('false'))
    )
    op.create_index(
        'ix_outward_lines_is_cancelled',
        'outward_lines',
        ['is_cancelled'],
        unique=False
    )


def downgrade() -> None:
    op.drop_index('ix_outward_lines_is_cancelled', table_name='outward_lines')
    op.drop_column('outward_lines', 'is_cancelled')

    op.drop_index('ix_outward_batches_is_cancelled', table_name='outward_batches')
    op.drop_column('outward_batches', 'cancel_reason')
    op.drop_column('outward_batches', 'cancelled_by_user_id')
    op.drop_column('outward_batches', 'cancelled_at')
    op.drop_column('outward_batches', 'is_cancelled')
