"""Delete the WoW: Forever beta's realms: their auction houses with every price, and the characters on them

The beta's realms ("Classic Beta PvE", "Classic Beta PvP 2") are whatever Forever realm names `beta` (as
`versions.BETA_REALM` reads them; uploads leave them out from now on). Selections on one are forgotten, so the
user's biggest group is selected. Data only, and safe for the previous release: it just sees fewer rows.

Revision ID: 0034
Revises: 0033
Create Date: 2026-11-21 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0034"
down_revision: str | None = "0033"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

BETA = "game_version = 'forever' AND lower(realm) LIKE '%beta%'"
HOUSES = f"SELECT id FROM auction_houses WHERE {BETA}"
SNAPSHOTS = f"SELECT id FROM price_snapshots WHERE auction_house_id IN ({HOUSES})"
CHARACTERS = f"SELECT id FROM characters WHERE {BETA}"
# Every table naming an auction house, price_current first (it names snapshots without a cascade)
HOUSE_TABLES = (
    "price_current",
    "copy_counts",
    "realm_aliases",
    "feed_tables",
    "price_daily",
    "price_hourly",
    "auction_state",
    "auction_ends_daily",
    "price_sales_daily",
)
CHARACTER_TABLES = (
    "character_professions",
    "character_recipes",
    "character_talents",
    "character_reputations",
    "character_items",
)


def upgrade() -> None:
    # Deleted explicitly rather than by the cascades, which SQLite honours only with its foreign_keys pragma
    for table in HOUSE_TABLES:
        op.execute(f"DELETE FROM {table} WHERE auction_house_id IN ({HOUSES})")
    op.execute(f"DELETE FROM price_observations WHERE snapshot_id IN ({SNAPSHOTS})")
    op.execute(f"DELETE FROM snapshot_bodies WHERE snapshot_id IN ({SNAPSHOTS})")
    op.execute(f"DELETE FROM price_snapshots WHERE auction_house_id IN ({HOUSES})")
    op.execute(f"DELETE FROM auction_houses WHERE {BETA}")
    for table in CHARACTER_TABLES:
        op.execute(f"DELETE FROM {table} WHERE character_id IN ({CHARACTERS})")
    op.execute(f"DELETE FROM characters WHERE {BETA}")
    op.execute(
        "UPDATE user_settings SET selected_realm = NULL, selected_faction = NULL "
        "WHERE game_version = 'forever' AND lower(selected_realm) LIKE '%beta%'"
    )


def downgrade() -> None:
    # The deleted characters and prices are gone for good (the price archive keeps the scans)
    pass
