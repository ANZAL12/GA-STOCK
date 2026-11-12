"""Align categories between Tally 1 and Tally 2 safely

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-07 20:30:00
"""
from typing import Sequence, Union
import uuid

from alembic import op
import sqlalchemy as sa


revision: str = '0012'
down_revision: Union[str, None] = '0011'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Remove manually created junk categories that have 0 products
    conn.execute(sa.text("""
        DELETE FROM categories 
        WHERE LOWER(name) = 'jyfjkyfkhg' 
          AND id NOT IN (SELECT DISTINCT category_id FROM products WHERE category_id IS NOT NULL)
    """))

    # 2. Revert Tally 2 guid from Tally 1 'AC'
    conn.execute(sa.text("""
        UPDATE categories 
        SET tally_guid = NULL 
        WHERE name = 'AC' AND tally_guid = '949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d4'
    """))

    # 3. Revert Tally 2 guid from Tally 1 'General'
    conn.execute(sa.text("""
        UPDATE categories 
        SET tally_guid = NULL 
        WHERE name = 'General' AND tally_guid = '949b6368-1ccd-4ac3-9553-d3d99e54a311-000000b8'
    """))

    # 4. Rename empty typo duplicate 'REFRIGERATOR' -> 'REFRIGERATOR (Tally 2)' if 0 products
    conn.execute(sa.text("""
        UPDATE categories 
        SET name = 'REFRIGERATOR (Tally 2)' 
        WHERE name = 'REFRIGERATOR' 
          AND id NOT IN (SELECT DISTINCT category_id FROM products WHERE category_id IS NOT NULL)
    """))

    # 5. Insert Tally 2 colliding categories if not already present
    t2_categories = [
        ("AC (Tally 2)", "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d4", None, True),
        ("General (Tally 2)", "949b6368-1ccd-4ac3-9553-d3d99e54a311-000000b8", None, False),
        ("REFRIGERATOR (Tally 2)", "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d7", None, False),
    ]

    for cat_name, guid, parent, dual in t2_categories:
        existing = conn.execute(sa.text(
            "SELECT id FROM categories WHERE name = :name OR tally_guid = :guid"
        ), {"name": cat_name, "guid": guid}).fetchone()

        if not existing:
            new_id = str(uuid.uuid4())
            conn.execute(sa.text("""
                INSERT INTO categories (id, name, has_dual_serial, is_active, tally_guid, tally_parent_group, source, created_at, updated_at)
                VALUES (:id, :name, :dual, true, :guid, :parent, 'TALLY', NOW(), NOW())
            """), {
                "id": new_id,
                "name": cat_name,
                "dual": dual,
                "guid": guid,
                "parent": parent,
            })
        else:
            conn.execute(sa.text("""
                UPDATE categories 
                SET name = :name, tally_guid = :guid, tally_parent_group = :parent, has_dual_serial = :dual, source = 'TALLY', updated_at = NOW()
                WHERE id = :id
            """), {
                "id": existing[0],
                "name": cat_name,
                "guid": guid,
                "parent": parent,
                "dual": dual,
            })


def downgrade() -> None:
    pass

