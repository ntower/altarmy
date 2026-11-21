"""Fold Forever houses named by region and ruleset ("US PvE") into their fixed realm's ("Americas Normal")

Scans from the addon on Forever 1.60.1 name "<region> <ruleset>"; uploaded before the site read that name as
a fixed realm (`versions.REGION_RULESET`), they made a house of their own, so the Trends page listed both
"US PvE Horde" and "Americas Normal Horde". Every Forever house whose realm `GameVersion.realm_name` now
reads as another realm moves its scans (snapshots, with their observations and bodies) to that realm's
house of the same faction (or, with none, is renamed to it), and its per-house rows (current prices, daily
and hourly figures, feed state) go: the fixed realm's house keeps its own, and the merge rebuilds the daily
figures from the moved observations. Selections naming the old realm name the fixed one. Data only, and
safe for the previous release.

Revision ID: 0035
Revises: 0034
Create Date: 2026-11-21 13:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from altarmy_site import versions

revision: str = "0035"
down_revision: str | None = "0034"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Every table naming an auction house but price_snapshots, price_current first (it names snapshots)
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


def upgrade() -> None:
    conn = op.get_bind()
    forever = versions.get("forever")
    rows = conn.execute(
        sa.text("SELECT id, realm, faction FROM auction_houses WHERE game_version = 'forever' ORDER BY id")
    ).all()
    houses = {(realm, faction): house for house, realm, faction in rows}
    for house, realm, faction in rows:
        name = forever.realm_name(realm)
        if name == realm:
            continue
        target = houses.get((name, faction))
        if target is None:
            conn.execute(
                sa.text("UPDATE auction_houses SET realm = :n WHERE id = :h"), {"n": name, "h": house}
            )
            houses[(name, faction)] = house
            continue
        for table in HOUSE_TABLES:
            conn.execute(sa.text(f"DELETE FROM {table} WHERE auction_house_id = :h"), {"h": house})
        conn.execute(
            sa.text("UPDATE price_snapshots SET auction_house_id = :t WHERE auction_house_id = :h"),
            {"t": target, "h": house},
        )
        conn.execute(sa.text("DELETE FROM auction_houses WHERE id = :h"), {"h": house})
        conn.execute(
            sa.text("UPDATE auction_houses SET price_version = price_version + 1 WHERE id = :t"),
            {"t": target},
        )
    selected: list[str] = list(
        conn.execute(
            sa.text(
                "SELECT DISTINCT selected_realm FROM user_settings "
                "WHERE game_version = 'forever' AND selected_realm IS NOT NULL"
            )
        ).scalars()
    )
    for realm in selected:
        name = forever.realm_name(realm)
        if name != realm:
            conn.execute(
                sa.text(
                    "UPDATE user_settings SET selected_realm = :n "
                    "WHERE game_version = 'forever' AND selected_realm = :r"
                ),
                {"n": name, "r": realm},
            )


def downgrade() -> None:
    # The houses folded together stay together (their scans can no longer be told apart)
    pass
