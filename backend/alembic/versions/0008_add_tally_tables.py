"""Add tally integration tables

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-05 14:50:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = '0008'
down_revision: Union[str, None] = '0007'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. tally_configs table
    op.create_table(
        'tally_configs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('host', sa.String(255), nullable=False, server_default='localhost'),
        sa.Column('port', sa.Integer(), nullable=False, server_default='9000'),
        sa.Column('tally_url', sa.String(500), nullable=True),
        sa.Column('company_name', sa.String(255), nullable=True),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('auto_sync', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('sync_interval_minutes', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('last_sync_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_sync_status', sa.String(50), nullable=True),
        sa.Column('last_sync_message', sa.Text(), nullable=True),
        sa.Column('last_alter_id', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('agent_token', sa.String(100), nullable=True, unique=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 2. tally_sales_vouchers table
    op.create_table(
        'tally_sales_vouchers',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('guid', sa.String(255), nullable=False),
        sa.Column('alter_id', sa.Integer(), nullable=True),
        sa.Column('master_id', sa.Integer(), nullable=True),
        sa.Column('voucher_number', sa.String(100), nullable=False),
        sa.Column('voucher_date', sa.Date(), nullable=False),
        sa.Column('voucher_type', sa.String(100), nullable=False, server_default='Sales'),
        sa.Column('party_name', sa.String(255), nullable=False),
        sa.Column('party_ledger_name', sa.String(255), nullable=True),
        sa.Column('buyer_name', sa.String(255), nullable=True),
        sa.Column('address', sa.Text(), nullable=True),
        sa.Column('state_name', sa.String(100), nullable=True),
        sa.Column('company_name', sa.String(255), nullable=True),
        sa.Column('is_cancelled', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('is_deleted', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('is_processed', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('processed_by_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('raw_metadata', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_tally_sales_vouchers_guid', 'tally_sales_vouchers', ['guid'], unique=True)
    op.create_index('ix_tally_sales_vouchers_alter_id', 'tally_sales_vouchers', ['alter_id'], unique=False)
    op.create_index('ix_tally_sales_vouchers_voucher_number', 'tally_sales_vouchers', ['voucher_number'], unique=False)
    op.create_index('ix_tally_sales_vouchers_voucher_date', 'tally_sales_vouchers', ['voucher_date'], unique=False)
    op.create_index('ix_tally_sales_vouchers_party_name', 'tally_sales_vouchers', ['party_name'], unique=False)
    op.create_index('ix_tally_sales_vouchers_party_ledger_name', 'tally_sales_vouchers', ['party_ledger_name'], unique=False)
    op.create_index('ix_tally_sales_vouchers_company_name', 'tally_sales_vouchers', ['company_name'], unique=False)
    op.create_index('ix_tally_sales_vouchers_is_cancelled', 'tally_sales_vouchers', ['is_cancelled'], unique=False)
    op.create_index('ix_tally_sales_vouchers_is_processed', 'tally_sales_vouchers', ['is_processed'], unique=False)

    # 3. tally_voucher_items table
    op.create_table(
        'tally_voucher_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('voucher_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('tally_sales_vouchers.id', ondelete='CASCADE'), nullable=False),
        sa.Column('item_name', sa.String(255), nullable=False),
        sa.Column('item_code', sa.String(100), nullable=True),
        sa.Column('product_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('products.id', ondelete='SET NULL'), nullable=True),
        sa.Column('quantity', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('uom', sa.String(50), nullable=True),
        sa.Column('raw_qty_text', sa.String(100), nullable=True),
        sa.Column('godown_name', sa.String(255), nullable=True),
        sa.Column('batch_name', sa.String(100), nullable=True),
        sa.Column('batch_details', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_tally_voucher_items_voucher_id', 'tally_voucher_items', ['voucher_id'], unique=False)
    op.create_index('ix_tally_voucher_items_item_name', 'tally_voucher_items', ['item_name'], unique=False)
    op.create_index('ix_tally_voucher_items_item_code', 'tally_voucher_items', ['item_code'], unique=False)
    op.create_index('ix_tally_voucher_items_product_id', 'tally_voucher_items', ['product_id'], unique=False)
    op.create_index('ix_tally_voucher_items_godown_name', 'tally_voucher_items', ['godown_name'], unique=False)

    # 4. tally_sync_histories table
    op.create_table(
        'tally_sync_histories',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('sync_source', sa.String(50), nullable=False, server_default='DIRECT_HTTP'),
        sa.Column('company_name', sa.String(255), nullable=True),
        sa.Column('status', sa.String(50), nullable=False, server_default='IN_PROGRESS'),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('vouchers_fetched', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('vouchers_created', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('vouchers_updated', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('vouchers_cancelled', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('from_date', sa.String(50), nullable=True),
        sa.Column('to_date', sa.String(50), nullable=True),
        sa.Column('last_alter_id', sa.Integer(), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('details', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_tally_sync_histories_sync_source', 'tally_sync_histories', ['sync_source'], unique=False)
    op.create_index('ix_tally_sync_histories_status', 'tally_sync_histories', ['status'], unique=False)


def downgrade() -> None:
    op.drop_table('tally_sync_histories')
    op.drop_table('tally_voucher_items')
    op.drop_table('tally_sales_vouchers')
    op.drop_table('tally_configs')

