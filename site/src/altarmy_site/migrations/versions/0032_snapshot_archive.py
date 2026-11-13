"""The long-term archive: snapshot_bodies (each snapshot's full scan, kept until archived),
archive_progress (the days the archive holds, which prune may drop), and indexes that keep the everyday
queries off old rows (price_snapshots by house and status; price_daily and price_sales_daily by house and
day)

Additive: new tables and indexes the previous release's instances never read; the single-column
price_snapshots index the composite ones replace goes too, which only changes query plans.

Revision ID: 0032
Revises: 0031
Create Date: 2026-11-12 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0032"
down_revision: str | None = "0031"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "snapshot_bodies",
        sa.Column("snapshot_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("format", sa.String(length=16), nullable=False),
        sa.Column("body", sa.LargeBinary(), nullable=False),
        sa.CheckConstraint("format IN ('book', 'auctions')", name=op.f("ck_snapshot_bodies_format")),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["price_snapshots.id"],
            name=op.f("fk_snapshot_bodies_snapshot_id_price_snapshots"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", name=op.f("pk_snapshot_bodies")),
    )
    op.create_table(
        "archive_progress",
        sa.Column("name", sa.String(length=32), nullable=False),
        sa.Column("through", sa.Date(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("name", name=op.f("pk_archive_progress")),
    )
    op.create_index(
        op.f("ix_price_snapshots_auction_house_id_status_id"),
        "price_snapshots",
        ["auction_house_id", "status", "id"],
    )
    op.create_index(
        op.f("ix_price_snapshots_auction_house_id_status_scanned_at"),
        "price_snapshots",
        ["auction_house_id", "status", "scanned_at"],
    )
    op.drop_index("ix_price_snapshots_auction_house_id", table_name="price_snapshots")
    op.create_index(op.f("ix_price_daily_auction_house_id_day"), "price_daily", ["auction_house_id", "day"])
    op.create_index(
        op.f("ix_price_sales_daily_auction_house_id_day"), "price_sales_daily", ["auction_house_id", "day"]
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_price_sales_daily_auction_house_id_day"), table_name="price_sales_daily")
    op.drop_index(op.f("ix_price_daily_auction_house_id_day"), table_name="price_daily")
    op.create_index("ix_price_snapshots_auction_house_id", "price_snapshots", ["auction_house_id"])
    op.drop_index(op.f("ix_price_snapshots_auction_house_id_status_scanned_at"), table_name="price_snapshots")
    op.drop_index(op.f("ix_price_snapshots_auction_house_id_status_id"), table_name="price_snapshots")
    op.drop_table("archive_progress")
    op.drop_table("snapshot_bodies")
