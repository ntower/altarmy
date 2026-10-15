"""price_current: the time-weighted market price, time to sell, sell-through, sales per stack size, the
auctions that ended lately and the gate they open

Additive: every column reads NULL until scans and the merge fill it.

Revision ID: 0027
Revises: 0026
Create Date: 2026-10-15 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op

revision: str = "0027"
down_revision: str | None = "0026"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

COLUMNS: tuple[tuple[str, sa.types.TypeEngine[Any]], ...] = (
    ("ewma_24h", sa.BigInteger()),
    ("ewma_72h", sa.BigInteger()),
    ("ewma_at", sa.DateTime(timezone=True)),
    ("ttl_hours", sa.Float()),
    ("sell_through", sa.Float()),
    ("stacks", sa.Text()),
    ("resolved_2d", sa.Integer()),
    ("resolved_days", sa.Integer()),
    ("gate", sa.String(8)),
)


def upgrade() -> None:
    # Plain ADD COLUMNs, also on SQLite: no table rebuild (see 0007).
    for name, kind in COLUMNS:
        op.add_column("price_current", sa.Column(name, kind, nullable=True))


def downgrade() -> None:
    for name, _ in reversed(COLUMNS):
        op.execute(f"ALTER TABLE price_current DROP COLUMN {name}")
