"""Add vehicle and transport fields to tally vouchers

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-05 16:45:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0009'
down_revision: Union[str, None] = '0008'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('tally_sales_vouchers', sa.Column('vehicle_number', sa.String(100), nullable=True))
    op.add_column('tally_sales_vouchers', sa.Column('transporter_name', sa.String(255), nullable=True))
    op.add_column('tally_sales_vouchers', sa.Column('delivery_note', sa.String(100), nullable=True))
    op.add_column('tally_sales_vouchers', sa.Column('destination', sa.String(255), nullable=True))
    op.create_index('ix_tally_sales_vouchers_vehicle_number', 'tally_sales_vouchers', ['vehicle_number'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_tally_sales_vouchers_vehicle_number', table_name='tally_sales_vouchers')
    op.drop_column('tally_sales_vouchers', 'destination')
    op.drop_column('tally_sales_vouchers', 'delivery_note')
    op.drop_column('tally_sales_vouchers', 'transporter_name')
    op.drop_column('tally_sales_vouchers', 'vehicle_number')

