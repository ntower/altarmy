"""character_items, characters.bags_at/bank_at and kept_items: what each character holds in their bags and
bank, when those were scanned, and the items the user keeps (What I hold)

Additive: tables and nullable columns the previous release's instances never read; holdings arrive with
the next upload of the addon's file.

Revision ID: 0029
Revises: 0028
Create Date: 2026-10-16 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0029"
down_revision: str | None = "0028"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("characters", sa.Column("bags_at", sa.BigInteger(), nullable=True))
    op.add_column("characters", sa.Column("bank_at", sa.BigInteger(), nullable=True))
    op.create_table(
        "character_items",
        sa.Column("character_id", sa.Integer(), nullable=False),
        sa.Column("item_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("place", sa.String(length=8), nullable=False),
        sa.Column("bound", sa.Boolean(), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["character_id"],
            ["characters.id"],
            name=op.f("fk_character_items_character_id_characters"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("character_id", "item_id", "place", "bound", name=op.f("pk_character_items")),
    )
    op.create_table(
        "kept_items",
        sa.Column("user_uid", sa.String(length=128), nullable=False),
        sa.Column("game_version", sa.String(length=16), nullable=False),
        sa.Column("item_id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["game_version"], ["game_versions.id"], name=op.f("fk_kept_items_game_version_game_versions")
        ),
        sa.ForeignKeyConstraint(
            ["user_uid"], ["users.uid"], name=op.f("fk_kept_items_user_uid_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("user_uid", "game_version", "item_id", name=op.f("pk_kept_items")),
    )


def downgrade() -> None:
    op.drop_table("kept_items")
    op.drop_table("character_items")
    op.execute("ALTER TABLE characters DROP COLUMN bank_at")
    op.execute("ALTER TABLE characters DROP COLUMN bags_at")
