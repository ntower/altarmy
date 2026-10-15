"""The hourly auction snapshot feed: price_hourly, auction_state, auction_ends_daily, the auction counts in
price_sales_daily, price_daily's open and close, and price_snapshots.build

Additive: the new tables start empty and the new columns read NULL or 0 until snapshots are recorded.

Revision ID: 0026
Revises: 0025
Create Date: 2026-10-15 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0026"
down_revision: str | None = "0025"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SALES_COUNTS = ("auctions_sold", "bid_sold", "expired", "posted", "relisted", "ambiguous")


def _house() -> sa.Column[int]:
    return sa.Column(
        "auction_house_id",
        sa.Integer(),
        sa.ForeignKey("auction_houses.id", ondelete="CASCADE"),
        nullable=False,
    )


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("price_snapshots", sa.Column("build", sa.String(32), nullable=True))
    op.add_column("price_daily", sa.Column("open", sa.BigInteger(), nullable=True))
    op.add_column("price_daily", sa.Column("close", sa.BigInteger(), nullable=True))
    for name in SALES_COUNTS:
        op.add_column("price_sales_daily", sa.Column(name, sa.Integer(), server_default="0", nullable=False))
    op.create_table(
        "price_hourly",
        _house(),
        sa.Column("item_id", sa.Integer(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("hours", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("auction_house_id", "item_id", "day"),
    )
    op.create_table(
        "auction_state",
        sa.Column(
            "auction_house_id",
            sa.Integer(),
            sa.ForeignKey("auction_houses.id", ondelete="CASCADE"),
            primary_key=True,
            autoincrement=False,
        ),
        sa.Column("snapshot_id", sa.Integer(), nullable=True),
        sa.Column("t", sa.DateTime(timezone=True), nullable=False),
        sa.Column("auctions", sa.Integer(), nullable=False),
        sa.Column("body", sa.LargeBinary(), nullable=False),
    )
    op.create_table(
        "auction_ends_daily",
        _house(),
        sa.Column("item_id", sa.Integer(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("stack", sa.Integer(), nullable=False),
        sa.Column("age_h", sa.Integer(), nullable=False),
        sa.Column("outcome", sa.String(16), nullable=False),
        sa.Column("auctions", sa.Integer(), nullable=False),
        sa.Column("units", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("auction_house_id", "item_id", "day", "stack", "age_h", "outcome"),
    )


def downgrade() -> None:
    op.drop_table("auction_ends_daily")
    op.drop_table("auction_state")
    op.drop_table("price_hourly")
    for name in reversed(SALES_COUNTS):
        op.execute(f"ALTER TABLE price_sales_daily DROP COLUMN {name}")
    op.execute("ALTER TABLE price_daily DROP COLUMN close")
    op.execute("ALTER TABLE price_daily DROP COLUMN open")
    op.execute("ALTER TABLE price_snapshots DROP COLUMN build")
