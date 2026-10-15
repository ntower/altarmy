"""copy_counts: how many times a recipe's steps were copied at an auction house, per hour (never by whom),
which Craft and sell shares its posts among

Additive: a table the previous release's instances never read.

Revision ID: 0030
Revises: 0029
Create Date: 2026-10-16 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0030"
down_revision: str | None = "0029"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "copy_counts",
        sa.Column("auction_house_id", sa.Integer(), nullable=False),
        sa.Column("recipe_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("hour", sa.DateTime(timezone=True), nullable=False),
        sa.Column("copies", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["auction_house_id"],
            ["auction_houses.id"],
            name=op.f("fk_copy_counts_auction_house_id_auction_houses"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("auction_house_id", "recipe_id", "hour", name=op.f("pk_copy_counts")),
    )


def downgrade() -> None:
    op.drop_table("copy_counts")
