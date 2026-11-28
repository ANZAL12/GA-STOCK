"""Add tally fields to products and categories

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-06 15:45:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0010'
down_revision: Union[str, None] = '0009'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Categories
    op.add_column('categories', sa.Column('tally_guid', sa.String(100), nullable=True))
    op.add_column('categories', sa.Column('tally_parent_group', sa.String(100), nullable=True))
    op.add_column('categories', sa.Column('source', sa.String(50), nullable=False, server_default='TALLY'))
    op.create_index('ix_categories_tally_guid', 'categories', ['tally_guid'], unique=False)

    # Products
    op.add_column('products', sa.Column('tally_guid', sa.String(100), nullable=True))
    op.add_column('products', sa.Column('tally_part_number', sa.String(100), nullable=True))
    op.add_column('products', sa.Column('source', sa.String(50), nullable=False, server_default='TALLY'))
    op.create_index('ix_products_tally_guid', 'products', ['tally_guid'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_products_tally_guid', table_name='products')
    op.drop_column('products', 'source')
    op.drop_column('products', 'tally_part_number')
    op.drop_column('products', 'tally_guid')

    op.drop_index('ix_categories_tally_guid', table_name='categories')
    op.drop_column('categories', 'source')
    op.drop_column('categories', 'tally_parent_group')
    op.drop_column('categories', 'tally_guid')

