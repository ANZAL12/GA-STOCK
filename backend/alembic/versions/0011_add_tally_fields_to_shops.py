"""Add tally fields to shops

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-06 16:15:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0011'
down_revision: Union[str, None] = '0010'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('shops', sa.Column('gstin', sa.String(50), nullable=True))
    op.add_column('shops', sa.Column('address', sa.String(500), nullable=True))
    op.add_column('shops', sa.Column('state', sa.String(100), nullable=True))
    op.add_column('shops', sa.Column('pincode', sa.String(20), nullable=True))
    op.add_column('shops', sa.Column('contact_person', sa.String(100), nullable=True))
    op.add_column('shops', sa.Column('email', sa.String(100), nullable=True))
    op.add_column('shops', sa.Column('tally_guid', sa.String(100), nullable=True))
    op.add_column('shops', sa.Column('source', sa.String(50), nullable=False, server_default='TALLY'))
    op.create_index('ix_shops_tally_guid', 'shops', ['tally_guid'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_shops_tally_guid', table_name='shops')
    op.drop_column('shops', 'source')
    op.drop_column('shops', 'tally_guid')
    op.drop_column('shops', 'email')
    op.drop_column('shops', 'contact_person')
    op.drop_column('shops', 'pincode')
    op.drop_column('shops', 'state')
    op.drop_column('shops', 'address')
    op.drop_column('shops', 'gstin')

