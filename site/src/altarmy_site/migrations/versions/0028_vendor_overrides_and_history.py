"""items.sell_price_overridden and vendor_price_history: hand-written vendor price overrides, and what
vendors paid in each build loaded

Additive: no item is overridden and the history is empty until the next game data load.

Revision ID: 0028
Revises: 0027
Create Date: 2026-10-15 16:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0028"
down_revision: str | None = "0027"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, also on SQLite: no table rebuild (see 0007).
    op.add_column(
        "items",
        sa.Column("sell_price_overridden", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.create_table(
        "vendor_price_history",
        sa.Column("game_version", sa.String(16), sa.ForeignKey("game_versions.id"), primary_key=True),
        sa.Column("item_id", sa.Integer(), primary_key=True, autoincrement=False),
        sa.Column("build", sa.String(32), primary_key=True),
        sa.Column("loaded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sell_price", sa.Integer(), nullable=False),
        sa.Column("buy_price", sa.Integer(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("vendor_price_history")
    op.execute("ALTER TABLE items DROP COLUMN sell_price_overridden")
