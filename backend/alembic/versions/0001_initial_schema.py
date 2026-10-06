"""Initial schema — all tables, enums, constraints, indexes.

Revision ID: 0001
Revises:
Create Date: 2026-10-05
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------ #
    # 1. PostgreSQL native ENUM types                                     #
    #    Defined once here; referenced with create_type=False below.     #
    # ------------------------------------------------------------------ #
    op.execute("CREATE TYPE user_role AS ENUM ('admin', 'staff')")
    op.execute(
        "CREATE TYPE serial_status AS ENUM "
        "('available', 'dispatched', 'damaged', 'lost', 'under_repair', 'returned')"
    )
    op.execute(
        "CREATE TYPE history_action AS ENUM "
        "('inward_recorded', 'dispatched_matched', 'dispatched_unmatched', "
        "'dispatched_flagged', 'returned', 'status_changed', 'inspected')"
    )
    op.execute("CREATE TYPE inspection_result AS ENUM ('available', 'damaged')")

    # ------------------------------------------------------------------ #
    # 2. users                                                            #
    # ------------------------------------------------------------------ #
    op.create_table(
        "users",
        sa.Column("id",            postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("username",      sa.String(100),  nullable=False),
        sa.Column("full_name",     sa.String(255),  nullable=False),
        sa.Column("password_hash", sa.String(255),  nullable=False),
        sa.Column("role", sa.Enum("admin", "staff", name="user_role", create_type=False), nullable=False),
        sa.Column("is_active",  sa.Boolean(),             nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_users_username", "users", ["username"], unique=True)

    # ------------------------------------------------------------------ #
    # 3. devices                                                          #
    # ------------------------------------------------------------------ #
    op.create_table(
        "devices",
        sa.Column("id",         postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("device_uid", sa.String(255), nullable=False),
        sa.Column("label",      sa.String(255), nullable=True),
        sa.Column(
            "approved_by_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active",   sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at",  sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_devices_device_uid", "devices", ["device_uid"], unique=True)

    # ------------------------------------------------------------------ #
    # 4. categories                                                       #
    # ------------------------------------------------------------------ #
    op.create_table(
        "categories",
        sa.Column("id",         postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name",       sa.String(100), nullable=False),
        sa.Column("is_active",  sa.Boolean(),   nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_categories_name", "categories", ["name"], unique=True)

    # ------------------------------------------------------------------ #
    # 5. shops                                                            #
    # ------------------------------------------------------------------ #
    op.create_table(
        "shops",
        sa.Column("id",         postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name",       sa.String(255), nullable=False),
        sa.Column("city",       sa.String(100), nullable=False),
        sa.Column("phone",      sa.String(30),  nullable=True),
        sa.Column("is_active",  sa.Boolean(),   nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ------------------------------------------------------------------ #
    # 6. products                                                         #
    # ------------------------------------------------------------------ #
    op.create_table(
        "products",
        sa.Column("id",    postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name",  sa.String(255), nullable=False),
        sa.Column("sku",   sa.String(100), nullable=True),
        sa.Column(
            "category_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("categories.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("brand",                  sa.String(100), nullable=False),
        sa.Column("model",                  sa.String(255), nullable=False),
        sa.Column("size_capacity",          sa.String(100), nullable=True),
        sa.Column("unit",                   sa.String(50),  nullable=False, server_default="piece"),
        sa.Column("serial_number_required", sa.Boolean(),   nullable=False, server_default=sa.true()),
        sa.Column("description",            sa.Text(),      nullable=True),
        sa.Column("opening_stock_qty",  sa.Integer(), nullable=False, server_default="0"),
        sa.Column("current_stock_qty",  sa.Integer(), nullable=False, server_default="0"),
        sa.Column("has_had_inward",     sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_active",          sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("current_stock_qty >= 0", name="ck_products_stock_non_negative"),
    )
    op.create_index("ix_products_sku",         "products", ["sku"],         unique=True)
    op.create_index("ix_products_category_id", "products", ["category_id"])

    # ------------------------------------------------------------------ #
    # 7. serial_numbers                                                   #
    # ------------------------------------------------------------------ #
    op.create_table(
        "serial_numbers",
        sa.Column("id",            postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("serial_number", sa.String(100), nullable=False),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.Enum(
                "available", "dispatched", "damaged", "lost", "under_repair", "returned",
                name="serial_status", create_type=False,
            ),
            nullable=False,
            server_default="available",
        ),
        sa.Column(
            "last_shop_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("shops.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_serial_numbers_serial_number", "serial_numbers", ["serial_number"], unique=True)
    op.create_index("ix_serial_numbers_product_id",    "serial_numbers", ["product_id"])
    op.create_index("ix_serial_numbers_status",        "serial_numbers", ["status"])
    op.create_index("ix_serial_numbers_last_shop_id",  "serial_numbers", ["last_shop_id"])

    # ------------------------------------------------------------------ #
    # 8. inward_batches                                                   #
    # ------------------------------------------------------------------ #
    op.create_table(
        "inward_batches",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("invoice_reference",   sa.String(100), nullable=True),
        sa.Column("transaction_date",    sa.Date(),      nullable=False),
        sa.Column(
            "received_by_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("quantity",   sa.Integer(), nullable=False),
        sa.Column("remarks",    sa.Text(),    nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_inward_batches_product_id",       "inward_batches", ["product_id"])
    op.create_index("ix_inward_batches_transaction_date", "inward_batches", ["transaction_date"])

    # ------------------------------------------------------------------ #
    # 9. inward_lines                                                     #
    # ------------------------------------------------------------------ #
    op.create_table(
        "inward_lines",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "batch_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("inward_batches.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "serial_number_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("serial_numbers.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("batch_id", "serial_number_id", name="uq_inward_lines_batch_serial"),
    )
    op.create_index("ix_inward_lines_batch_id",         "inward_lines", ["batch_id"])
    op.create_index("ix_inward_lines_serial_number_id", "inward_lines", ["serial_number_id"])

    # ------------------------------------------------------------------ #
    # 10. outward_batches                                                 #
    # ------------------------------------------------------------------ #
    op.create_table(
        "outward_batches",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "shop_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("shops.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("delivery_reference",    sa.String(100), nullable=True),
        sa.Column("transaction_date",      sa.Date(),      nullable=False),
        sa.Column(
            "dispatched_by_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("quantity",        sa.Integer(), nullable=False),
        sa.Column("matched_count",   sa.Integer(), nullable=False, server_default="0"),
        sa.Column("unmatched_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("flagged_count",   sa.Integer(), nullable=False, server_default="0"),
        sa.Column("remarks",    sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_outward_batches_product_id",       "outward_batches", ["product_id"])
    op.create_index("ix_outward_batches_shop_id",          "outward_batches", ["shop_id"])
    op.create_index("ix_outward_batches_transaction_date", "outward_batches", ["transaction_date"])

    # ------------------------------------------------------------------ #
    # 11. outward_lines                                                   #
    # ------------------------------------------------------------------ #
    op.create_table(
        "outward_lines",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "batch_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("outward_batches.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("serial_text", sa.String(100), nullable=False),
        sa.Column(
            "serial_number_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("serial_numbers.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "shop_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("shops.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("transaction_date",      sa.Date(),    nullable=False),
        sa.Column("is_matched",            sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_flagged_for_review", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("flag_reason", sa.Text(), nullable=True),
        sa.Column("created_at",  sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("batch_id", "serial_text", name="uq_outward_lines_batch_serial"),
    )
    op.create_index("ix_outward_lines_batch_id",           "outward_lines", ["batch_id"])
    op.create_index("ix_outward_lines_serial_text",        "outward_lines", ["serial_text"])
    op.create_index("ix_outward_lines_serial_number_id",   "outward_lines", ["serial_number_id"])
    op.create_index("ix_outward_lines_shop_id",            "outward_lines", ["shop_id"])
    op.create_index("ix_outward_lines_is_matched",         "outward_lines", ["is_matched"])
    op.create_index("ix_outward_lines_is_flagged",         "outward_lines", ["is_flagged_for_review"])
    op.create_index("ix_outward_lines_transaction_date",   "outward_lines", ["transaction_date"])

    # ------------------------------------------------------------------ #
    # 12. returns                                                         #
    # ------------------------------------------------------------------ #
    op.create_table(
        "returns",
        sa.Column("id",          postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("serial_text", sa.String(100), nullable=False),
        sa.Column(
            "serial_number_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("serial_numbers.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "outward_line_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("outward_lines.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "shop_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("shops.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "product_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("return_date", sa.Date(), nullable=False),
        sa.Column("reason",      sa.Text(), nullable=False),
        sa.Column("condition",   sa.String(100), nullable=True),
        sa.Column(
            "received_by_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "inspection_result",
            sa.Enum("available", "damaged", name="inspection_result", create_type=False),
            nullable=True,
        ),
        sa.Column("inspected_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "inspected_by_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("remarks",    sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_returns_serial_text",      "returns", ["serial_text"])
    op.create_index("ix_returns_serial_number_id", "returns", ["serial_number_id"])
    op.create_index("ix_returns_shop_id",          "returns", ["shop_id"])
    op.create_index("ix_returns_return_date",      "returns", ["return_date"])

    # ------------------------------------------------------------------ #
    # 13. serial_history                                                  #
    # ------------------------------------------------------------------ #
    op.create_table(
        "serial_history",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "serial_number_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("serial_numbers.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("serial_text", sa.String(100), nullable=False),
        sa.Column(
            "action",
            sa.Enum(
                "inward_recorded", "dispatched_matched", "dispatched_unmatched",
                "dispatched_flagged", "returned", "status_changed", "inspected",
                name="history_action", create_type=False,
            ),
            nullable=False,
        ),
        sa.Column(
            "from_status",
            sa.Enum(
                "available", "dispatched", "damaged", "lost", "under_repair", "returned",
                name="serial_status", create_type=False,
            ),
            nullable=True,
        ),
        sa.Column(
            "to_status",
            sa.Enum(
                "available", "dispatched", "damaged", "lost", "under_repair", "returned",
                name="serial_status", create_type=False,
            ),
            nullable=True,
        ),
        sa.Column(
            "shop_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("shops.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "inward_batch_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("inward_batches.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "outward_batch_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("outward_batches.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "return_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("returns.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("is_matched", sa.Boolean(), nullable=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("remarks",    sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_serial_history_serial_number_id", "serial_history", ["serial_number_id"])
    op.create_index("ix_serial_history_serial_text",      "serial_history", ["serial_text"])
    op.create_index("ix_serial_history_action",           "serial_history", ["action"])
    op.create_index("ix_serial_history_user_id",          "serial_history", ["user_id"])
    op.create_index("ix_serial_history_created_at",       "serial_history", ["created_at"])

    # ------------------------------------------------------------------ #
    # 14. audit_log                                                       #
    # ------------------------------------------------------------------ #
    op.create_table(
        "audit_log",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("action",      sa.String(100), nullable=False),
        sa.Column("entity_type", sa.String(50),  nullable=False),
        sa.Column("entity_id",   sa.String(100), nullable=True),
        sa.Column("details",     postgresql.JSONB(), nullable=True),
        sa.Column("ip_address",  sa.String(45),  nullable=True),
        sa.Column("created_at",  sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_audit_log_user_id",     "audit_log", ["user_id"])
    op.create_index("ix_audit_log_action",      "audit_log", ["action"])
    op.create_index("ix_audit_log_entity_type", "audit_log", ["entity_type"])
    op.create_index("ix_audit_log_entity_id",   "audit_log", ["entity_id"])
    op.create_index("ix_audit_log_created_at",  "audit_log", ["created_at"])


def downgrade() -> None:
    # Drop in reverse FK order
    op.drop_table("audit_log")
    op.drop_table("serial_history")
    op.drop_table("returns")
    op.drop_table("outward_lines")
    op.drop_table("outward_batches")
    op.drop_table("inward_lines")
    op.drop_table("inward_batches")
    op.drop_table("serial_numbers")
    op.drop_table("products")
    op.drop_table("shops")
    op.drop_table("categories")
    op.drop_table("devices")
    op.drop_table("users")

    # Drop enum types
    op.execute("DROP TYPE inspection_result")
    op.execute("DROP TYPE history_action")
    op.execute("DROP TYPE serial_status")
    op.execute("DROP TYPE user_role")
