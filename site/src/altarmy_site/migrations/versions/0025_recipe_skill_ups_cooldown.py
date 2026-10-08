"""recipes.num_skill_ups and recipes.cooldown_ms: which recipes give skill points, and their cooldowns

Additive: every recipe reads a point a craft and no cooldown until the next game data update.

Revision ID: 0025
Revises: 0024
Create Date: 2026-10-08 10:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0025"
down_revision: str | None = "0024"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    op.add_column("recipes", sa.Column("num_skill_ups", sa.Integer(), server_default="1", nullable=False))
    op.add_column("recipes", sa.Column("cooldown_ms", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    op.execute("ALTER TABLE recipes DROP COLUMN cooldown_ms")
    op.execute("ALTER TABLE recipes DROP COLUMN num_skill_ups")
