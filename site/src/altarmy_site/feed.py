"""Recording the hourly auction snapshots (`snapshots.py`) into the price store.

Each snapshot of a house is told apart against the auctions live after the one before
(`auction_state`, one row per house), so what ended in between comes from the feed's own sequence and
never from the addon's scans. Prices mix with those scans in `price_current` as every source does: the
newest per item wins. A snapshot that looks cut short is held back as a quarantined row and the state
stays put, so the next good one is told apart against the last good one.

What a snapshot writes: `price_current` (ladders pooled as the addon pools them, an item no longer listed
unlisted), `price_hourly` (the hour's slot), `price_daily` (low, high, available), `price_sales_daily`
(units bought and what they went for, units pulled, and the auction counts), `auction_ends_daily` (how
the auctions ended by hours up, for time to sell) and the house's state. No `price_observations`:
`price_hourly` is the feed's history.

`poll` is the hourly job (`altarmy-site feed`): every open fixed realm's mapped houses
(`RealmSpec.blizzard_houses`) fetched with `blizzard.Client` and recorded, each in a transaction of its own,
so one house that fails leaves the others recorded.
"""

from __future__ import annotations

import gzip
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, date, datetime

from sqlalchemy import Connection, select

from . import archive, blizzard, book, db, prices, schema, snapshots
from .versions import GameVersion

CLOSE = 1.25  # `match`: an item's cheapest prices within this factor of each other agree
FEED_ALERT = "feed-house-failed"  # the `Run.warn` tag of a house the hourly feed could not record


@dataclass(frozen=True)
class FeedRecorded:
    items: int  # items with a buyout in the snapshot
    moved: int  # of them (and of those it no longer lists), items whose price or listing changed
    ended: int = 0  # auctions gone since the snapshot before
    posted: int = 0  # auctions new since then
    follows: bool = False  # it came soon enough after the one before to tell what ended
    stale: bool = False  # no newer than the house's newest snapshot: not used
    quarantined: bool = False  # it looked cut short: held back, it changed nothing


def load_state(conn: Connection, auction_house_id: int) -> snapshots.HouseState | None:
    """The auctions live on the house after its newest snapshot; None before the first."""
    t = schema.auction_state
    body = conn.execute(select(t.c.body).where(t.c.auction_house_id == auction_house_id)).scalar_one_or_none()
    return None if body is None else snapshots.decode_state(body)


def state_time(conn: Connection, auction_house_id: int) -> int | None:
    """When the house's newest recorded snapshot stands for (Unix seconds); None before the first."""
    t = schema.auction_state
    found = conn.execute(select(t.c.t).where(t.c.auction_house_id == auction_house_id)).scalar_one_or_none()
    return None if found is None else int(db.utc(found).timestamp())


@dataclass(frozen=True)
class Polled:
    """One mapped house's poll."""

    realm: str  # the fixed realm's name
    faction: str
    house_id: int  # Blizzard's
    auction_house_id: int  # ours
    recorded: FeedRecorded | None = None  # None: nothing new since the last snapshot (or it failed)
    error: str | None = None  # why it could not be fetched or read


def poll(
    database: db.Database, version: GameVersion, client_for: Callable[[str], blizzard.Client]
) -> list[Polled]:
    """Fetch and record every open fixed realm's mapped houses (see the module docstring); `client_for`
    gives the API client of a region ("us"). A house that can't be fetched or read is a `Polled.error`."""
    out: list[Polled] = []
    for spec in version.realms:
        if not spec.open or not spec.blizzard_houses or not spec.api_region:
            continue
        client = client_for(spec.api_region)
        for faction, house_id in spec.blizzard_houses:
            with database.begin() as conn:
                ah = prices.auction_house(conn, version.key, spec.name, faction)
                since = state_time(conn, ah)
            polled = Polled(spec.name, faction, house_id, ah)
            try:
                house = client.house(house_id, since)
                if house is None:
                    out.append(polled)
                    continue
                snap = snapshots.parse_blizzard(
                    house.listings, t=house.t, realm=spec.name, faction=faction, commodities=house.commodities
                )
            except (blizzard.FeedError, ValueError) as e:
                out.append(Polled(spec.name, faction, house_id, ah, error=str(e)))
                continue
            with database.begin() as conn:
                recorded = record_auction_snapshot(conn, ah, snap, version)
            out.append(Polled(spec.name, faction, house_id, ah, recorded))
    return out


def newest_scan(conn: Connection, auction_house_id: int) -> tuple[int, dict[int, book.Ladder]] | None:
    """The house's newest accepted Alt Army scan that kept its body (revision 0032 on): its time (Unix
    seconds) and ladders by item; None without one."""
    snap, body = schema.price_snapshots, schema.snapshot_bodies
    row = conn.execute(
        select(snap.c.scanned_at, body.c.body)
        .join(body, body.c.snapshot_id == snap.c.id)
        .where(
            snap.c.auction_house_id == auction_house_id,
            snap.c.source == prices.ALTARMY,
            snap.c.status == "accepted",
            body.c.format == "book",
        )
        .order_by(snap.c.scanned_at.desc(), snap.c.id.desc())
        .limit(1)
    ).first()
    if row is None:
        return None
    _, *lines = gzip.decompress(row.body).decode().split("\n")  # the head: listings, bid only, source
    ladders = {}
    for line in lines:
        item, ladder = line.split(":", 1)
        ladders[int(item)] = book.decode(ladder)
    return int(db.utc(row.scanned_at).timestamp()), ladders


@dataclass(frozen=True)
class Match:
    """How far one of Blizzard's houses agrees with an Alt Army scan (`match`)."""

    shared: float  # the share of the scan's price levels (tails left out) the house lists too
    close: float  # the share of the items both list whose cheapest prices agree within CLOSE
    items: int  # the items both list


def match(scan: Mapping[int, book.Ladder], snap: snapshots.Snapshot) -> Match:
    """`snap` against an Alt Army scan of what may be the same house: taken within the hour, the same
    house shares most of its price levels (the addon pools auctions as `snapshots.ladders` does), another
    house hardly any (`prices._breaks_off`'s test)."""
    house = snapshots.ladders(snap)
    levels = {(item, lv.price) for item, ladder in scan.items() for lv in ladder if not lv.tail}
    listed = {(item, lv.price) for item, ladder in house.items() for lv in ladder if not lv.tail}
    both = [item for item, ladder in scan.items() if ladder and house.get(item)]
    cheapest = [(scan[item][0].price, house[item][0].price) for item in both]
    close = sum(1 for a, b in cheapest if max(a, b) <= CLOSE * min(a, b))
    return Match(
        len(levels & listed) / len(levels) if levels else 0.0,
        close / len(both) if both else 0.0,
        len(both),
    )


def _save_state(
    conn: Connection, auction_house_id: int, snapshot_id: int, state: snapshots.HouseState
) -> None:
    db.upsert(
        conn,
        schema.auction_state,
        [
            {
                "auction_house_id": auction_house_id,
                "snapshot_id": snapshot_id,
                "t": _when(state.t),
                "auctions": len(state.live),
                "body": snapshots.encode_state(state),
            }
        ],
        ["auction_house_id"],
        ["snapshot_id", "t", "auctions", "body"],
    )


def _when(t: int) -> datetime:
    return datetime.fromtimestamp(t, UTC)


def record_auction_snapshot(
    conn: Connection, auction_house_id: int, snap: snapshots.Snapshot, version: GameVersion
) -> FeedRecorded:
    """Store one hourly snapshot of the house (see the module docstring). The caller owns the transaction
    and publishes the price signal when `moved`."""
    at = _when(snap.t)
    before = load_state(conn, auction_house_id)
    with_buyout = len({a.item_id for a in snap.auctions if a.unit_price is not None})
    if snapshots.looks_partial(before, snap):
        snapshot_id = prices._insert_snapshot(
            conn, auction_house_id, prices.BLIZZARD, at, with_buyout, None, None, "quarantined", snap.build
        )
        archive.save_body(conn, snapshot_id, "auctions", archive.encode_auctions(snap))
        return FeedRecorded(with_buyout, 0, quarantined=True)
    d = snapshots.diff(before, snap, version.buckets, version.snapshot_gap)
    if d.stale:
        return FeedRecorded(with_buyout, 0, stale=True)

    snapshot_id = prices._insert_snapshot(
        conn, auction_house_id, prices.BLIZZARD, at, with_buyout, None, None, "accepted", snap.build
    )
    archive.save_body(conn, snapshot_id, "auctions", archive.encode_auctions(snap))
    moved = _record_book(conn, auction_house_id, snapshot_id, at, snapshots.ladders(snap))
    if d.follows:
        _add_flows(conn, auction_house_id, at.date(), snapshots.flows(d))
        _add_ends(conn, auction_house_id, at.date(), snapshots.end_counts(d))
    _save_state(conn, auction_house_id, snapshot_id, d.state)
    if moved:
        prices.bump_price_version(conn, auction_house_id)
    return FeedRecorded(with_buyout, moved, len(d.ended), len(d.posted), follows=d.follows)


def _record_book(
    conn: Connection,
    auction_house_id: int,
    snapshot_id: int,
    at: datetime,
    ladders: Mapping[int, book.Ladder],
) -> int:
    """Write the snapshot's ladders as `record_book` writes a scan's, newest wins per item; the items whose
    price or listing changed."""
    rows = prices._book_rows(conn, auction_house_id)
    current: list[dict[str, object]] = []
    daily = []
    hours = {}
    moved = 0
    vendor = prices.ask_caps(conn, auction_house_id, list(ladders))
    for item_id, ladder in sorted(ladders.items()):
        row = rows.get(item_id)
        if row is not None and row.seen_at > at:
            continue
        before = row.ladder if row is not None else ()
        hour = prices.hour_of(ladder)
        trusted = prices.trusted_ask(
            hour.market, None if row is None else row.sale_price, vendor.get(item_id)
        )
        current.append(
            {
                "item_id": item_id,
                "price": hour.low,
                "quantity": hour.units,
                "ladder": book.encode(book.aged(before, ladder)),
                "listed": True,
                "market_price": hour.market,
                **prices.ewma_columns(row, trusted, at),
            }
        )
        daily.append(prices.Observation(item_id, trusted, at, hour.units))
        hours[item_id] = hour
        was = None if row is None or not row.listed else (row.price, row.market_price)
        if was != (hour.low, hour.market):
            moved += 1
    for item_id, row in sorted(rows.items()):
        if not row.listed or item_id in ladders or row.seen_at > at:
            continue
        current.append(
            {
                "item_id": item_id,
                "price": row.price,
                "quantity": 0,
                "ladder": "",
                "listed": False,
                "market_price": row.market_price,
                **prices.ewma_columns(row, None, at),
            }
        )
        moved += 1
    shared = {"auction_house_id": auction_house_id, "seen_at": at, "snapshot_id": snapshot_id}
    db.upsert(
        conn,
        schema.price_current,
        [{**shared, **r} for r in current],
        ["auction_house_id", "item_id"],
        [*prices.BOOK_COLUMNS, *prices.EWMA_COLUMNS],
    )
    prices.record_daily_observations(conn, auction_house_id, daily)
    prices.record_hours(conn, auction_house_id, at, hours)
    return moved


# price_sales_daily's auction counts, by the outcome they count
_COUNTS = {
    "sold": "auctions_sold",
    "bid_won": "bid_sold",
    "expired": "expired",
    "posted": "posted",
    "relisted": "relisted",
    "ambiguous": "ambiguous",
}


def _add_flows(
    conn: Connection, auction_house_id: int, day: date, flows: Mapping[tuple[int, int, str], snapshots.Tally]
) -> None:
    """Add one snapshot's flows to the day's `price_sales_daily` rows: units bought (bought out or won by
    a bid) and what they went for, units pulled as `cancelled`, a pair counted where any sold, and the
    auctions of each outcome."""
    per_item: dict[int, dict[str, int]] = {}
    for (item_id, _stack, kind), tally in flows.items():
        adds = per_item.setdefault(
            item_id, dict.fromkeys(("units", "copper", "cancelled", *_COUNTS.values()), 0)
        )
        if kind in snapshots.SOLD:
            adds["units"] += tally.units
            adds["copper"] += tally.copper
        if kind == "pulled":
            adds["cancelled"] += tally.units
        if kind in _COUNTS:
            adds[_COUNTS[kind]] += tally.auctions
    if not per_item:
        return
    t = schema.price_sales_daily
    columns = ("units", "copper", "cancelled", "pairs", *_COUNTS.values())
    stored = {
        r.item_id: r
        for r in conn.execute(
            select(t.c.item_id, *(t.c[c] for c in columns)).where(
                t.c.auction_house_id == auction_house_id, t.c.day == day, t.c.item_id.in_(sorted(per_item))
            )
        )
    }
    rows = []
    for item_id, add in sorted(per_item.items()):
        old = stored.get(item_id)
        row: dict[str, object] = {"auction_house_id": auction_house_id, "item_id": item_id, "day": day}
        for c in columns:
            had = 0 if old is None else int(getattr(old, c))
            row[c] = had + (1 if add["units"] else 0) if c == "pairs" else had + add[c]
        rows.append(row)
    db.upsert(conn, t, rows, ["auction_house_id", "item_id", "day"], list(columns))


def _add_ends(
    conn: Connection,
    auction_house_id: int,
    day: date,
    ends: Mapping[tuple[int, int, int, str], snapshots.Tally],
) -> None:
    """Add one snapshot's ended auctions to the day's `auction_ends_daily` rows."""
    if not ends:
        return
    t = schema.auction_ends_daily
    items = sorted({item for item, *_ in ends})
    stored = {
        (r.item_id, r.stack, r.age_h, r.outcome): (r.auctions, r.units)
        for r in conn.execute(
            select(t.c.item_id, t.c.stack, t.c.age_h, t.c.outcome, t.c.auctions, t.c.units).where(
                t.c.auction_house_id == auction_house_id, t.c.day == day, t.c.item_id.in_(items)
            )
        )
    }
    rows = []
    for (item_id, stack, age_h, outcome), tally in sorted(ends.items()):
        auctions, units = stored.get((item_id, stack, age_h, outcome), (0, 0))
        rows.append(
            {
                "auction_house_id": auction_house_id,
                "item_id": item_id,
                "day": day,
                "stack": stack,
                "age_h": age_h,
                "outcome": outcome,
                "auctions": auctions + tally.auctions,
                "units": units + tally.units,
            }
        )
    db.upsert(
        conn,
        t,
        rows,
        ["auction_house_id", "item_id", "day", "stack", "age_h", "outcome"],
        ["auctions", "units"],
    )
