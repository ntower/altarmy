"""Vendor prices that look wrong, for the Admin page: a to-do list of prices to check in game.

Every vendor exit on the site rests on DB2's SellPrice (`items.sell_price`) or a hand-written override
(`ingest.vendor_overrides`). Three signs say one may be wrong:

- listings under what a vendor pays that stay listed scan after scan (`LISTED_UNDER_AGE`): anyone could buy
  them and vendor them at a profit, so on a live realm they don't sit for long unless the price is wrong;
- vendor prices the newest build moved (`vendor_price_history`): until checked, either build may be right;
- the overrides themselves, to see what is overridden.

Nothing here changes a price: a suspect closes through a row in `data/<version>/vendor_overrides.csv`.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import Connection, select

from . import book, schema

LISTED_UNDER_AGE = 2  # scans or snapshots a cheapest level under the vendor price must have survived


@dataclass(frozen=True)
class ListedUnder:
    item_id: int
    name: str
    vendor: int  # what a vendor pays
    cheapest: int  # the cheapest such listing, on any house
    units: int  # units listed under the vendor price, on every house
    houses: int  # houses listing it under the vendor price


@dataclass(frozen=True)
class Moved:
    item_id: int
    name: str
    build: str  # the newest build loaded
    before: int  # what a vendor paid in the build before
    after: int


@dataclass(frozen=True)
class Overridden:
    item_id: int
    name: str
    vendor: int


@dataclass(frozen=True)
class Suspects:
    listed_under: list[ListedUnder]
    moved: list[Moved]
    overridden: list[Overridden]


def vendor_suspects(conn: Connection, game_version: str) -> Suspects:
    """The version's vendor price suspects (see the module docstring), the likeliest first."""
    return Suspects(
        _listed_under(conn, game_version), _moved(conn, game_version), _overridden(conn, game_version)
    )


def _listed_under(conn: Connection, game_version: str) -> list[ListedUnder]:
    pc, ah, items = schema.price_current, schema.auction_houses, schema.items
    rows = conn.execute(
        select(pc.c.item_id, pc.c.ladder, items.c.name, items.c.sell_price)
        .join(ah, ah.c.id == pc.c.auction_house_id)
        .join(items, (items.c.game_version == ah.c.game_version) & (items.c.id == pc.c.item_id))
        .where(
            ah.c.game_version == game_version,
            pc.c.listed.is_(True),
            pc.c.ladder != "",
            items.c.sell_price > pc.c.price,
        )
    )
    found: dict[int, list[tuple[int, int]]] = defaultdict(list)  # item: (cheapest, units) per house
    names: dict[int, tuple[str, int]] = {}
    for r in rows:
        under = [lv for lv in book.decode(r.ladder) if lv.price < r.sell_price and not lv.tail]
        if not under or under[0].age < LISTED_UNDER_AGE:
            continue
        found[r.item_id].append((under[0].price, sum(lv.quantity for lv in under)))
        names[r.item_id] = (r.name, r.sell_price)
    out = [
        ListedUnder(
            item_id,
            names[item_id][0],
            names[item_id][1],
            min(c for c, _ in houses),
            sum(u for _, u in houses),
            len(houses),
        )
        for item_id, houses in found.items()
    ]
    return sorted(out, key=lambda s: (-s.houses, s.cheapest / s.vendor, s.item_id))


def _moved(conn: Connection, game_version: str) -> list[Moved]:
    h, items = schema.vendor_price_history, schema.items
    newest = conn.execute(
        select(h.c.build).where(h.c.game_version == game_version).order_by(h.c.loaded_at.desc()).limit(1)
    ).scalar_one_or_none()
    if newest is None:
        return []
    out = []
    for r in conn.execute(
        select(h.c.item_id, h.c.sell_price, items.c.name)
        .join(items, (items.c.game_version == h.c.game_version) & (items.c.id == h.c.item_id))
        .where(h.c.game_version == game_version, h.c.build == newest)
        .order_by(h.c.item_id)
    ):
        before = conn.execute(
            select(h.c.sell_price)
            .where(h.c.game_version == game_version, h.c.item_id == r.item_id, h.c.build != newest)
            .order_by(h.c.loaded_at.desc())
            .limit(1)
        ).scalar_one_or_none()
        if before is not None and before != r.sell_price:
            out.append(Moved(r.item_id, r.name, newest, before, r.sell_price))
    return out


def _overridden(conn: Connection, game_version: str) -> list[Overridden]:
    items = schema.items
    return [
        Overridden(r.id, r.name, r.sell_price)
        for r in conn.execute(
            select(items.c.id, items.c.name, items.c.sell_price)
            .where(items.c.game_version == game_version, items.c.sell_price_overridden.is_(True))
            .order_by(items.c.id)
        )
    ]
