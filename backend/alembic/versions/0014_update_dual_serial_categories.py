"""Update dual serial flag on AC, General, and Formenty categories

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-26 14:10:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0014'
down_revision: Union[str, None] = '0013'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    # 1. Ensure any formenty category without AC is strictly single serial (e.g. LED FORMENTY)
    conn.execute(sa.text("""
        UPDATE categories
        SET has_dual_serial = FALSE
        WHERE (
            LOWER(name) LIKE '%formenty%'
            OR LOWER(name) LIKE '%forementy%'
            OR LOWER(name) LIKE '%fmty%'
        )
        AND NOT (
            LOWER(name) LIKE 'ac%'
            OR LOWER(name) LIKE '%ac'
            OR LOWER(name) LIKE '% ac %'
        );
    """))

    # 2. Mark dual series categories (General, AC, AC Formenty / Forementy AC, Air Conditioners)
    conn.execute(sa.text("""
        UPDATE categories
        SET has_dual_serial = TRUE
        WHERE (
            LOWER(name) = 'general'
            OR LOWER(name) LIKE '%general%'
            OR LOWER(name) LIKE 'ac%formenty%'
            OR LOWER(name) LIKE '%formenty%ac'
            OR LOWER(name) LIKE 'ac%forementy%'
            OR LOWER(name) LIKE '%forementy%ac'
            OR LOWER(name) LIKE 'ac%fmty%'
            OR LOWER(name) LIKE '%fmty%ac'
            OR LOWER(name) = 'ac'
            OR LOWER(name) LIKE 'ac %'
            OR LOWER(name) LIKE 'ac-%'
            OR LOWER(name) LIKE 'ac(%'
            OR LOWER(name) LIKE '% ac'
            OR LOWER(name) LIKE '%-ac'
            OR LOWER(name) LIKE '%air condition%'
            OR LOWER(name) LIKE '%split%'
            OR LOWER(name) LIKE '%cassette%'
        )
        AND LOWER(name) NOT LIKE '%stand%'
        AND LOWER(name) NOT LIKE '%stabilizer%'
        AND LOWER(name) NOT LIKE '%bracket%'
        AND LOWER(name) NOT LIKE '%pipe%'
        AND LOWER(name) NOT LIKE '%remote%'
        AND LOWER(name) NOT LIKE '%trolley%'
        AND LOWER(name) NOT LIKE '%cover%'
        AND LOWER(name) NOT LIKE '%blender%'
        AND LOWER(name) NOT LIKE '%led%'
        AND LOWER(name) NOT LIKE '%tv%';
    """))


def downgrade() -> None:
    pass
