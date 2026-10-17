"""characters.source: the WoW account a character was uploaded from (the addon's `accountId`), so each
account's upload replaces only its own characters

Additive: a nullable column the previous release's instances never read (their wholesale replace still
works on it); characters saved before it read None and are taken over by the next upload.

Revision ID: 0031
Revises: 0030
Create Date: 2026-10-17 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0031"
down_revision: str | None = "0030"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, also on SQLite: no table rebuild (see 0007).
    op.add_column("characters", sa.Column("source", sa.String(length=64), nullable=True))


def downgrade() -> None:
    op.execute("ALTER TABLE characters DROP COLUMN source")
