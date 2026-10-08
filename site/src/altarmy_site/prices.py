"""Price sources and the price store. All money is integer copper.

Every source (an uploaded Auctionator scan, a manual price) records a snapshot for one auction house
(`record_snapshot`). A snapshot writes observations only for items it tells something new about, and those
move `price_current`, which the engine reads: the newest price per auction house and item. Auctionator's
per-day history also fills `price_daily`, pooled across uploaders. Observations are pruned after
`KEEP_DAYS`; daily rows are kept. `merge.py` fills the 7-day columns, which set the sell price
(`load_buy_and_sell`) and the baseline an uploaded scan is screened against (`screen`): one whose prices
are mostly far off it is quarantined and changes nothing.

The quantity listed is kept current without being news (`_restocked`): it flags thin markets, and
moves no price.

Where a version's prices are first-party (`GameVersion.first_party_prices`: Forever), they come from the
Alt Army addon's full scans (`record_book`): per item a ladder of the units listed at each price
(`book.py`), kept in `price_current.ladder`. Buying walks the ladder (`load_books`), an item missing from
a scan is no longer listed, and the units gone off the cheap end between two scans are counted as sales
(`price_sales_daily`), which the merge turns into `sale_price`. Only 'altarmy' and hand-set snapshots
are read there (`FIRST_PARTY`).
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Literal

from sqlalchemy import ColumnElement, Connection, bindparam, case, delete, func, select, update

from . import book, db, schema
from .auctionator import ItemPrice

KEEP_DAYS = 180  # observations older than this are pruned (price_daily is kept)
AUCTIONATOR = "auctionator"
HAND_SET = ("manual", "csv")  # sources whose price is used as it is, never capped by the 7-day median
THIN_UNITS = 5  # fewer units listed than this: a sale there rests on a thin market
ALTARMY = "altarmy"  # the Alt Army addon's full scans (`record_book`)
FIRST_PARTY = (ALTARMY, *HAND_SET)  # the sources read where prices are first-party
SALES_GAP = timedelta(minutes=30)  # scans further apart than this say nothing of what sold between them
SALES_DAYS = 7  # the calendar days whose inferred sales count (the merge's `sale_rate`, `confidence`)
MIN_SALES = 5  # fewer units sold than this say nothing of a price
# Price confidence (`confidence`): an item's median from fewer days than this is a guess, and this many
# hours of back-to-back scans (`watched_hours`) without a sale say it doesn't sell
CONFIDENT_SCAN_DAYS = 3
WATCHED_ENOUGH_HOURS = 3.0
MIN_LEVELS = 50  # fewer price levels in the scan before than this: too few to judge a scan's continuity by
MIN_SHARED = 0.25  # quarantine a scan that has under this share of the price levels of one SALES_GAP before
STRAY = 0.5  # a level first seen in the newest scan under this share of the usual price is not counted on

# Screening an uploaded scan against the 7-day medians (normal scans have at most ~5% of items this far off)
WILD_RATIO = 4.0  # a price more than this many times off its median, either way, is wild
MIN_COMPARED = 20  # fewer comparable items than this: not enough to judge
MIN_BASELINE_DAYS = 3  # an item's median counts as a baseline once it has this many days
BASE_WILD_SHARE = 0.1  # quarantine above this share of wild prices, plus TRUST_WILD_SHARE * trust
TRUST_WILD_SHARE = 0.2


@dataclass(frozen=True)
class Observation:
    """One item's price in a snapshot."""

    item_id: int
    min_buyout: int
    seen_at: datetime  # when that price was on the auction house
    quantity: int | None = None
    listings: int | None = None


# --- auction houses --------------------------------------------------------------------------------
def find_auction_house(conn: Connection, game_version: str, realm: str, faction: str) -> int | None:
    """The auction house a realm/faction's characters use: their faction's, else one the realm shares."""
    t = schema.auction_houses
    for f in dict.fromkeys((faction, "")):
        found = conn.execute(
            select(t.c.id).where(t.c.game_version == game_version, t.c.realm == realm, t.c.faction == f)
        ).scalar_one_or_none()
        if found is not None:
            return int(found)
    return None


def auction_house(conn: Connection, game_version: str, realm: str, faction: str) -> int:
    """The auction house keyed (version, realm, faction), created if new. Faction "" means shared."""
    t = schema.auction_houses
    key = {"game_version": game_version, "realm": realm, "faction": faction}
    db.upsert(conn, t, [key], list(key))
    found: int = conn.execute(
        select(t.c.id).where(t.c.game_version == game_version, t.c.realm == realm, t.c.faction == faction)
    ).scalar_one()
    return found


def unnamed_auction_house(conn: Connection, game_version: str) -> int:
    """Where prices go when no realm is known (CLI use without characters)."""
    return auction_house(conn, game_version, "", "")


def auctionator_auction_house(conn: Connection, game_version: str, key: str, realm: str, faction: str) -> int:
    """The auction house Auctionator's `key` prices for a realm/faction's characters: their faction's if
    the key names it (split auction houses, "Dreamscythe Horde"), else one both factions share. Records
    the key as an alias."""
    split = bool(faction) and key.endswith(f" {faction}")
    ah = auction_house(conn, game_version, realm, faction if split else "")
    _add_alias(conn, ah, AUCTIONATOR, key)
    return ah


def find_auction_house_by_key(conn: Connection, game_version: str, key: str) -> int | None:
    """The auction house that has Auctionator realm `key` as an alias, if any."""
    t, a = schema.auction_houses, schema.realm_aliases
    found = conn.execute(
        select(t.c.id)
        .join(a, a.c.auction_house_id == t.c.id)
        .where(t.c.game_version == game_version, a.c.kind == AUCTIONATOR, a.c.value == key)
        .order_by(t.c.id)
        .limit(1)
    ).scalar_one_or_none()
    return None if found is None else int(found)


def find_auction_house_by_alias(conn: Connection, game_version: str, realm: str, faction: str) -> int | None:
    """The auction house a realm/faction's characters use when it was named after Auctionator's key (a
    scan uploaded before the characters): the key forms `service.match_auctionator_realm` tries."""
    nospace = realm.replace(" ", "")
    for key in dict.fromkeys((f"{nospace} {faction}", nospace, f"{realm} {faction}", realm)):
        found = find_auction_house_by_key(conn, game_version, key)
        if found is not None:
            return found
    return None


def auction_house_for_auctionator_key(conn: Connection, game_version: str, key: str) -> int:
    """The auction house an Auctionator realm key names: a known alias, else parsed from the key (a
    trailing faction means a split auction house; the realm is then as Auctionator spells it)."""
    found = find_auction_house_by_key(conn, game_version, key)
    if found is not None:
        return found
    realm, _, faction = key.rpartition(" ")
    if faction not in ("Horde", "Alliance") or not realm:
        realm, faction = key, ""
    return auctionator_auction_house(conn, game_version, key, realm, faction)


def price_version(conn: Connection, auction_house_id: int | None) -> int | None:
    """Bumped whenever the auction house's prices changed: a snapshot that moved a current price
    (`record_snapshot`) or a merge that changed its 7-day columns. The front end refetches when it moves
    (`/api/status`, and the Firestore price signal, `signals.py`). None: no such auction house."""
    if auction_house_id is None:
        return None
    t = schema.auction_houses
    found = conn.execute(select(t.c.price_version).where(t.c.id == auction_house_id)).scalar_one_or_none()
    return None if found is None else int(found)


@dataclass(frozen=True)
class Coverage:
    """How well an auction house is scanned."""

    auction_house_id: int
    realm: str
    faction: str  # "" if both factions share it
    prices: int  # items with a current price
    last_scan: datetime | None  # the newest accepted scan
    last_scan_items: int  # items in it
    scans_7d: int  # accepted scans in the last 7 days
    uploaders_7d: int  # distinct users who sent them
    watched_hours: float = 0.0  # how long its sales were watched lately (`watched_hours`)


def coverage(conn: Connection, game_version: str, now: datetime | None = None) -> list[Coverage]:
    """Every named auction house of the version, by realm then faction."""
    now = db.utc(now or db.utcnow())
    since = now - timedelta(days=7)
    t, pc, snap = schema.auction_houses, schema.price_current, schema.price_snapshots
    accepted = snap.c.status == "accepted"
    counts: dict[int, int] = dict(
        conn.execute(
            select(pc.c.auction_house_id, func.count())
            .join(t, t.c.id == pc.c.auction_house_id)
            .where(t.c.game_version == game_version)
            .group_by(pc.c.auction_house_id)
        ).all()
    )
    recent = {
        r[0]: (int(r[1]), int(r[2]))
        for r in conn.execute(
            select(snap.c.auction_house_id, func.count(), func.count(snap.c.uploader_uid.distinct()))
            .where(accepted, snap.c.scanned_at >= since)
            .group_by(snap.c.auction_house_id)
        )
    }
    newest = (
        select(snap.c.auction_house_id, func.max(snap.c.id).label("id"))
        .where(accepted)
        .group_by(snap.c.auction_house_id)
        .subquery()
    )
    last = {
        r.auction_house_id: (db.utc(r.scanned_at), int(r.item_count))
        for r in conn.execute(
            select(snap.c.auction_house_id, snap.c.scanned_at, snap.c.item_count).join(
                newest, newest.c.id == snap.c.id
            )
        )
    }
    out = []
    for r in conn.execute(
        select(t.c.id, t.c.realm, t.c.faction)
        .where(t.c.game_version == game_version, t.c.realm != "")
        .order_by(t.c.realm, t.c.faction)
    ):
        scan, items = last.get(r.id, (None, 0))
        scans, uploaders = recent.get(r.id, (0, 0))
        out.append(
            Coverage(
                r.id,
                r.realm,
                r.faction,
                int(counts.get(r.id, 0)),
                scan,
                items,
                scans,
                uploaders,
                round(watched_hours(conn, r.id, now), 1),
            )
        )
    return out


def freshest_auction_house(conn: Connection, game_version: str) -> tuple[str, str] | None:
    """The (realm, faction) of the named auction house with the newest accepted snapshot; None if no named
    auction house of the version has one."""
    t, snap = schema.auction_houses, schema.price_snapshots
    found = conn.execute(
        select(t.c.realm, t.c.faction)
        .join(snap, snap.c.auction_house_id == t.c.id)
        .where(t.c.game_version == game_version, t.c.realm != "", snap.c.status == "accepted")
        .order_by(snap.c.scanned_at.desc(), snap.c.id.desc())
        .limit(1)
    ).first()
    return None if found is None else (str(found.realm), str(found.faction))


def game_version_of(conn: Connection, auction_house_id: int) -> str | None:
    t = schema.auction_houses
    found = conn.execute(select(t.c.game_version).where(t.c.id == auction_house_id)).scalar_one_or_none()
    return None if found is None else str(found)


def _add_alias(conn: Connection, auction_house_id: int, kind: str, value: str) -> None:
    row = {"auction_house_id": auction_house_id, "kind": kind, "value": value}
    db.upsert(conn, schema.realm_aliases, [row], list(row))


# --- recording -------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Recorded:
    moved: int  # items whose current price moved
    quarantined: bool = False  # the scan was held back: it changed nothing
    screened: bool = False  # it was compared with enough of the baseline to judge the uploader by


def screen(
    observations: Sequence[Observation], baseline: Mapping[int, int], scanned_at: datetime, trust: float
) -> bool | None:
    """Whether to quarantine a scan: too many of its prices seen on the scan day are more than WILD_RATIO
    off the item's 7-day median (`baseline`). The share allowed shrinks with the uploader's `trust`
    (0..1). None when fewer than MIN_COMPARED items can be compared."""
    scan_day = db.utc(scanned_at).date()
    ratios = [
        o.min_buyout / baseline[o.item_id]
        for o in observations
        if baseline.get(o.item_id, 0) > 0 and db.utc(o.seen_at).date() == scan_day
    ]
    if len(ratios) < MIN_COMPARED:
        return None
    wild = sum(1 for r in ratios if r > WILD_RATIO or r < 1 / WILD_RATIO)
    return wild / len(ratios) > BASE_WILD_SHARE + TRUST_WILD_SHARE * max(0.0, min(1.0, trust))


def baseline(conn: Connection, auction_house_id: int) -> dict[int, int]:
    """{item_id: 7-day median} for items with at least MIN_BASELINE_DAYS days of it."""
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.median_7d).where(
            pc.c.auction_house_id == auction_house_id,
            pc.c.median_7d.is_not(None),
            pc.c.scans_7d >= MIN_BASELINE_DAYS,
        )
    )
    return {r.item_id: int(r.median_7d) for r in rows}


def _insert_snapshot(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    item_count: int,
    received_at: datetime | None,
    uploader_uid: str | None,
    status: str,
) -> int:
    snap = schema.price_snapshots
    snapshot_id: int = conn.execute(
        snap.insert()
        .values(
            auction_house_id=auction_house_id,
            source=source,
            uploader_uid=uploader_uid,
            scanned_at=db.utc(scanned_at),
            received_at=db.utc(received_at or db.utcnow()),
            item_count=item_count,
            status=status,
        )
        .returning(snap.c.id)
    ).scalar_one()
    return snapshot_id


def record_snapshot(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    observations: Sequence[Observation],
    *,
    received_at: datetime | None = None,
    uploader_uid: str | None = None,
) -> int:
    """Store a snapshot and whatever it adds to `price_current`. Returns how many items it moved; if any,
    the auction house's `price_version` is bumped.

    An observation is news when the auction house has no price for the item, when it was seen on a later
    day, or when it was seen no earlier and its price differs. A newer quantity alone updates
    `price_current` in place and is not news. Re-sending the same scan writes nothing."""
    snapshot_id = _insert_snapshot(
        conn, auction_house_id, source, scanned_at, len(observations), received_at, uploader_uid, "accepted"
    )
    current = _current(conn, auction_house_id)
    _update_quantities(
        conn, auction_house_id, [o for o in observations if _restocked(o, current.get(o.item_id))]
    )
    news = [o for o in observations if _is_news(o, current.get(o.item_id))]
    if not news:
        return 0
    conn.execute(
        schema.price_observations.insert(),
        [
            {
                "snapshot_id": snapshot_id,
                "item_id": o.item_id,
                "min_buyout": o.min_buyout,
                "quantity": o.quantity,
                "listings": o.listings,
            }
            for o in news
        ],
    )
    pc = schema.price_current
    rows = [
        {
            "auction_house_id": auction_house_id,
            "item_id": o.item_id,
            "price": o.min_buyout,
            "seen_at": db.utc(o.seen_at),
            "snapshot_id": snapshot_id,
            "quantity": o.quantity,
            "ladder": None,
            "listed": None,
            "market_price": None,
        }
        for o in news
    ]
    updated = ["price", "seen_at", "snapshot_id", "quantity", "ladder", "listed", "market_price"]
    db.upsert(conn, pc, rows, ["auction_house_id", "item_id"], updated)
    bump_price_version(conn, auction_house_id)
    return len(news)


def bump_price_version(conn: Connection, auction_house_id: int) -> None:
    t = schema.auction_houses
    conn.execute(update(t).where(t.c.id == auction_house_id).values(price_version=t.c.price_version + 1))


@dataclass(frozen=True)
class _Current:
    price: int
    seen_at: datetime
    quantity: int | None


def _current(conn: Connection, auction_house_id: int) -> dict[int, _Current]:
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.seen_at, pc.c.quantity).where(
            pc.c.auction_house_id == auction_house_id
        )
    )
    return {r.item_id: _Current(r.price, db.utc(r.seen_at), r.quantity) for r in rows}


def _is_news(o: Observation, current: _Current | None) -> bool:
    if current is None:
        return True
    new_seen = db.utc(o.seen_at)
    changed = o.min_buyout != current.price
    return new_seen.date() > current.seen_at.date() or (new_seen >= current.seen_at and changed)


def _restocked(o: Observation, current: _Current | None) -> bool:
    """Not news, but seen no earlier with another quantity listed."""
    return (
        current is not None
        and not _is_news(o, current)
        and db.utc(o.seen_at) >= current.seen_at
        and o.quantity is not None
        and o.quantity != current.quantity
    )


def _update_quantities(conn: Connection, auction_house_id: int, observations: Sequence[Observation]) -> None:
    if not observations:
        return
    pc = schema.price_current
    conn.execute(
        update(pc)
        .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
        .values(quantity=bindparam("q")),
        [{"i": o.item_id, "q": o.quantity} for o in observations],
    )


def auctionator_observations(item_prices: Mapping[int, ItemPrice], scanned_at: datetime) -> list[Observation]:
    """Observations for one realm of Auctionator's database. An item was seen at the scan time if its
    newest day is the scan's day (Auctionator counts days in local time, as does this process), else at
    the start of that day; the quantity is that day's."""
    scan = db.utc(scanned_at)
    scan_day = scan.astimezone().date()
    out = []
    for item_id, p in sorted(item_prices.items()):
        last = p.last_seen
        if last is None or last >= scan_day:
            seen_at, quantity = scan, p.days[last].available if last is not None else None
        else:
            seen_at, quantity = datetime.combine(last, time(), scan.tzinfo), p.days[last].available
        out.append(Observation(item_id, p.min_buyout, seen_at, quantity))
    return out


def record_daily(conn: Connection, auction_house_id: int, item_prices: Mapping[int, ItemPrice]) -> int:
    """Upsert Auctionator's per-day history into `price_daily`, from the newest day already stored on
    (earlier days no longer change). A day several uploaders saw pools them: the lowest low, the highest
    high, the most available. Returns the rows written."""
    pd = schema.price_daily
    newest = conn.execute(
        select(func.max(pd.c.day)).where(pd.c.auction_house_id == auction_house_id)
    ).scalar_one_or_none()
    stored: dict[tuple[int, date], tuple[int, int, int | None]] = {}
    if newest is not None:
        for r in conn.execute(
            select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available).where(
                pd.c.auction_house_id == auction_house_id, pd.c.day >= newest
            )
        ):
            stored[(r.item_id, r.day)] = (r.low, r.high, r.available)
    rows = []
    for item_id, p in item_prices.items():
        for day, s in p.days.items():
            if newest is not None and day < newest:
                continue
            low, high, available = s.low, s.high, s.available
            old = stored.get((item_id, day))
            if old is not None:
                low, high = min(low, old[0]), max(high, old[1])
                available = max((a for a in (available, old[2]) if a is not None), default=None)
            row = {"low": low, "high": high, "available": available}
            rows.append({"auction_house_id": auction_house_id, "item_id": item_id, "day": day, **row})
    db.upsert(conn, pd, rows, ["auction_house_id", "item_id", "day"], ["low", "high", "available"])
    return len(rows)


def record_auctionator(
    conn: Connection,
    auction_house_id: int,
    item_prices: Mapping[int, ItemPrice],
    scanned_at: datetime,
    uploader_uid: str | None = None,
    trust: float | None = None,
) -> Recorded:
    """One realm of an Auctionator scan: a snapshot plus its daily history. With the uploader's `trust`,
    the scan is screened first (see `screen`); a quarantined one is kept as a snapshot row only."""
    observations = auctionator_observations(item_prices, scanned_at)
    got = record_screened(conn, auction_house_id, AUCTIONATOR, scanned_at, observations, uploader_uid, trust)
    if not got.quarantined:
        record_daily(conn, auction_house_id, item_prices)
    return got


def record_screened(
    conn: Connection,
    auction_house_id: int,
    source: str,
    scanned_at: datetime,
    observations: Sequence[Observation],
    uploader_uid: str | None = None,
    trust: float | None = None,
) -> Recorded:
    """A snapshot, screened first with `trust` (None: not screened); a quarantined one is kept as a
    snapshot row only."""
    verdict = None
    if trust is not None:
        verdict = screen(observations, baseline(conn, auction_house_id), scanned_at, trust)
    if verdict:
        count = len(observations)
        _insert_snapshot(conn, auction_house_id, source, scanned_at, count, None, uploader_uid, "quarantined")
        return Recorded(0, quarantined=True, screened=True)
    moved = record_snapshot(
        conn, auction_house_id, source, scanned_at, observations, uploader_uid=uploader_uid
    )
    return Recorded(moved, screened=verdict is not None)


# --- the order book --------------------------------------------------------------------------------
@dataclass(frozen=True)
class BookRecorded:
    items: int  # items in the scan
    moved: int  # of them (and of those it no longer lists), items whose price or listing changed
    stale: bool = False  # no newer than the auction house's newest scan: not used
    quarantined: bool = False  # held back: it changed nothing
    screened: bool = False  # it was compared with enough to judge the uploader by


@dataclass(frozen=True)
class _BookRow:
    price: int
    seen_at: datetime
    source: str
    ladder: book.Ladder  # () unless the row is a scan's and listed
    listed: bool
    market_price: int | None


def _book_rows(conn: Connection, auction_house_id: int) -> dict[int, _BookRow]:
    pc, snap = schema.price_current, schema.price_snapshots
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.seen_at, pc.c.ladder, pc.c.listed, pc.c.market_price)
        .add_columns(snap.c.source)
        .join(snap, snap.c.id == pc.c.snapshot_id)
        .where(pc.c.auction_house_id == auction_house_id)
    )
    out = {}
    for r in rows:
        listed = r.source == ALTARMY and bool(r.listed)
        ladder = book.decode(r.ladder) if listed and r.ladder else ()
        out[r.item_id] = _BookRow(r.price, db.utc(r.seen_at), r.source, ladder, listed, r.market_price)
    return out


def _newest_book(conn: Connection, auction_house_id: int) -> datetime | None:
    snap = schema.price_snapshots
    found = conn.execute(
        select(func.max(snap.c.scanned_at)).where(
            snap.c.auction_house_id == auction_house_id,
            snap.c.source == ALTARMY,
            snap.c.status == "accepted",
        )
    ).scalar_one_or_none()
    return None if found is None else db.utc(found)


def _breaks_off(rows: Mapping[int, _BookRow], scan: book.Scan) -> bool | None:
    """Whether the scan shares too few price levels with the book of a moment ago to be the same auction
    house's; None when that book is too small to tell."""
    before = [(item, lv.price) for item, row in rows.items() for lv in row.ladder if not lv.tail]
    if len(before) < MIN_LEVELS:
        return None
    now = {(item, lv.price) for item, ladder in scan.items.items() for lv in ladder}
    return sum(1 for level in before if level in now) / len(before) < MIN_SHARED


def record_book(
    conn: Connection,
    auction_house_id: int,
    scan: book.Scan,
    *,
    scanned_at: datetime | None = None,
    uploader_uid: str | None = None,
    trust: float | None = None,
) -> BookRecorded:
    """Store one Alt Army scan of the auction house, taken at `scanned_at` (default: the scan's own time).

    A scan no newer than the house's newest is not used (whoever uploads it, and however often). With the
    uploader's `trust` it is screened first: its market prices against the 7-day medians (`screen`), and,
    right after another scan, its price levels against that one's (`_breaks_off`); a quarantined scan is
    kept as a snapshot row only.

    Every item's ladder replaces the one before, its levels aged; an item the scan no longer has is
    unlisted. An item is news (an observation, and the price version moves) when its cheapest or its
    market price changed or it was listed or unlisted. Units gone since a scan at most SALES_GAP before
    are added to the day's sales. An item with a newer price (set by hand since) is left alone."""
    at = db.utc(scanned_at or datetime.fromtimestamp(scan.t, db.utcnow().tzinfo))
    newest = _newest_book(conn, auction_house_id)
    if newest is not None and at <= newest:
        return BookRecorded(len(scan.items), 0, stale=True)
    rows = _book_rows(conn, auction_house_id)
    follows = newest is not None and at - newest <= SALES_GAP
    markets = {i: book.market_price(ladder) or ladder[0].price for i, ladder in scan.items.items() if ladder}

    verdict = None
    if trust is not None:
        seen = [Observation(i, m, at) for i, m in sorted(markets.items())]
        verdict = screen(seen, baseline(conn, auction_house_id), at, trust)
        broken = _breaks_off(rows, scan) if follows else None
        if broken is not None:
            verdict = bool(verdict) or broken
    if verdict:
        _insert_snapshot(
            conn, auction_house_id, ALTARMY, at, len(scan.items), None, uploader_uid, "quarantined"
        )
        return BookRecorded(len(scan.items), 0, quarantined=True, screened=True)

    snapshot_id = _insert_snapshot(
        conn, auction_house_id, ALTARMY, at, len(scan.items), None, uploader_uid, "accepted"
    )
    current: list[dict[str, object]] = []
    news: list[dict[str, object]] = []
    daily_rows = []
    sales: dict[int, book.Sold] = {}
    for item_id, ladder in sorted(scan.items.items()):
        row = rows.get(item_id)
        if not ladder or (row is not None and row.seen_at > at):
            continue
        before = row.ladder if row is not None else ()
        if follows and before:
            sales[item_id] = book.sold_between(before, ladder)
        units, market = book.quantity(ladder), markets[item_id]
        current.append(
            {
                "item_id": item_id,
                "price": ladder[0].price,
                "quantity": units,
                "ladder": book.encode(book.aged(before, ladder)),
                "listed": True,
                "market_price": market,
            }
        )
        daily_rows.append(Observation(item_id, market, at, units))
        was = None if row is None or not row.listed else (row.price, row.market_price)
        if was != (ladder[0].price, market):
            news.append(
                {
                    "snapshot_id": snapshot_id,
                    "item_id": item_id,
                    "min_buyout": ladder[0].price,
                    "quantity": units,
                    "listings": sum(lv.listings for lv in ladder),
                    "market_price": market,
                }
            )
    gone = 0
    for item_id, row in sorted(rows.items()):
        if not row.listed or item_id in scan.items or row.seen_at > at:
            continue
        if follows and row.ladder:
            sales[item_id] = book.sold_between(row.ladder, ())
        current.append(
            {
                "item_id": item_id,
                "price": row.price,
                "quantity": 0,
                "ladder": "",
                "listed": False,
                "market_price": row.market_price,
            }
        )
        gone += 1

    shared = {"auction_house_id": auction_house_id, "seen_at": at, "snapshot_id": snapshot_id}
    db.upsert(
        conn,
        schema.price_current,
        [{**shared, **r} for r in current],
        ["auction_house_id", "item_id"],
        ["price", "seen_at", "snapshot_id", "quantity", "ladder", "listed", "market_price"],
    )
    if news:
        conn.execute(schema.price_observations.insert(), news)
    record_daily_observations(conn, auction_house_id, daily_rows)
    _add_sales(conn, auction_house_id, at.date(), sales)
    moved = len(news) + gone
    if moved:
        bump_price_version(conn, auction_house_id)
    return BookRecorded(len(scan.items), moved, screened=verdict is not None)


def _add_sales(conn: Connection, auction_house_id: int, day: date, sales: Mapping[int, book.Sold]) -> None:
    """Add what sold (and was cancelled) between one pair of scans to the day's `price_sales_daily` rows,
    counting the pair for each item seen bought in it."""
    sales = {i: s for i, s in sales.items() if s.units or s.cancelled}
    if not sales:
        return
    t = schema.price_sales_daily
    stored = {
        r.item_id: (r.units, r.copper, r.cancelled, r.pairs)
        for r in conn.execute(
            select(t.c.item_id, t.c.units, t.c.copper, t.c.cancelled, t.c.pairs).where(
                t.c.auction_house_id == auction_house_id, t.c.day == day, t.c.item_id.in_(sorted(sales))
            )
        )
    }
    rows = []
    for item_id, s in sorted(sales.items()):
        units, copper, cancelled, pairs = stored.get(item_id, (0, 0, 0, 0))
        rows.append(
            {
                "auction_house_id": auction_house_id,
                "item_id": item_id,
                "day": day,
                "units": units + s.units,
                "copper": copper + s.copper,
                "cancelled": cancelled + s.cancelled,
                "pairs": pairs + (1 if s.units else 0),
            }
        )
    db.upsert(
        conn, t, rows, ["auction_house_id", "item_id", "day"], ["units", "copper", "cancelled", "pairs"]
    )


def load_books(
    conn: Connection, auction_house_id: int | None, *, credible: bool = True
) -> dict[int, book.Ladder]:
    """{item_id: ladder} of what the auction house's newest scan lists; empty for None. With `credible`,
    without the levels first seen in that scan that are under STRAY of the item's 7-day median (where it
    has MIN_BASELINE_DAYS days of one; before that, under STRAY of the next level's price): a stray cheap
    listing is gone before anyone gets there. An item left without levels is left out."""
    if auction_house_id is None:
        return {}
    pc, snap = schema.price_current, schema.price_snapshots
    rows = conn.execute(
        select(pc.c.item_id, pc.c.ladder, pc.c.median_7d, pc.c.scans_7d)
        .join(snap, snap.c.id == pc.c.snapshot_id)
        .where(
            pc.c.auction_house_id == auction_house_id,
            snap.c.source == ALTARMY,
            pc.c.listed.is_(True),
            pc.c.ladder != "",
        )
        .order_by(pc.c.item_id)
    )
    out = {}
    for r in rows:
        ladder = book.decode(r.ladder)
        if credible and r.median_7d and (r.scans_7d or 0) >= MIN_BASELINE_DAYS:
            ladder = tuple(lv for lv in ladder if lv.age > 0 or lv.price >= STRAY * r.median_7d)
        elif credible:
            ladder = tuple(
                lv
                for lv, above in zip(ladder, (*ladder[1:], None), strict=True)
                if lv.age > 0 or lv.tail or above is None or lv.price >= STRAY * above.price
            )
        if ladder:
            out[r.item_id] = ladder
    return out


def book_sell_price(market: int, listed: bool, reference: int | None, sale_price: int | None) -> int:
    """What a sale counts as where prices are first-party: the lower of what is asked (the market price,
    while listed) and what the item goes for (what it sold for lately, else its 7-day median). Without
    either, the last market price."""
    usual = sale_price if sale_price is not None else reference
    asked = [market] if listed else []
    return min([*asked, *([usual] if usual is not None else [])], default=market)


def record_daily_observations(
    conn: Connection, auction_house_id: int, observations: Sequence[Observation]
) -> int:
    """Pool observations into `price_daily` on their UTC day, as `record_daily` pools uploaders: the
    lowest low, the highest high, the most available. Returns the rows written."""
    pd = schema.price_daily
    days: dict[tuple[int, date], tuple[int, int, int | None]] = {}
    for o in observations:
        key = (o.item_id, db.utc(o.seen_at).date())
        low, high, available = days.get(key, (o.min_buyout, o.min_buyout, o.quantity))
        days[key] = (min(low, o.min_buyout), max(high, o.min_buyout), _most(available, o.quantity))
    if not days:
        return 0
    items = sorted({item for item, _ in days})
    stored = {
        (r.item_id, r.day): (r.low, r.high, r.available)
        for r in conn.execute(
            select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available).where(
                pd.c.auction_house_id == auction_house_id,
                pd.c.item_id.in_(items),
                pd.c.day >= min(day for _, day in days),
            )
        )
    }
    rows = []
    for (item_id, day), (low, high, available) in sorted(days.items()):
        old = stored.get((item_id, day))
        if old is not None:
            low, high, available = min(low, old[0]), max(high, old[1]), _most(available, old[2])
        row = {"low": low, "high": high, "available": available}
        rows.append({"auction_house_id": auction_house_id, "item_id": item_id, "day": day, **row})
    db.upsert(conn, pd, rows, ["auction_house_id", "item_id", "day"], ["low", "high", "available"])
    return len(rows)


def _most(a: int | None, b: int | None) -> int | None:
    return max((x for x in (a, b) if x is not None), default=None)


def prune(conn: Connection, now: datetime | None = None, keep_days: int = KEEP_DAYS) -> None:
    """Drop observations of snapshots older than `keep_days`, and those snapshots unless `price_current`
    still points at them."""
    cutoff = db.utc(now or db.utcnow()) - timedelta(days=keep_days)
    snap, obs, pc = schema.price_snapshots, schema.price_observations, schema.price_current
    old = select(snap.c.id).where(snap.c.scanned_at < cutoff)
    conn.execute(delete(obs).where(obs.c.snapshot_id.in_(old)))
    conn.execute(delete(snap).where(snap.c.scanned_at < cutoff, snap.c.id.not_in(select(pc.c.snapshot_id))))


# --- reading ---------------------------------------------------------------------------------------
def load_current(conn: Connection, auction_house_id: int | None) -> dict[int, int]:
    """{item_id: price} for the auction house; empty for None."""
    if auction_house_id is None:
        return {}
    pc = schema.price_current
    rows = conn.execute(select(pc.c.item_id, pc.c.price).where(pc.c.auction_house_id == auction_house_id))
    return {r.item_id: r.price for r in rows}


def load_buy_and_sell(
    conn: Connection, auction_house_id: int | None, *, first_party: bool = False
) -> tuple[dict[int, int], dict[int, int]]:
    """({item_id: buy price}, {item_id: sell price}) for the auction house; empty for None. Reagents cost
    the cheapest listing; a craft sells at the lower of the cheapest listing and the 7-day median
    (`sell_price`), so a lone overpriced listing doesn't count as the going rate. Prices set by hand are
    used as they are.

    With `first_party` only Alt Army's scans and hand-set prices are read. A scanned item's buy price is
    its cheapest level worth counting on (`load_books`; none if it is not listed: it cannot be bought) and
    its sell price `book_sell_price`."""
    if auction_house_id is None:
        return {}, {}
    pc, snap = schema.price_current, schema.price_snapshots
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.median_7d, snap.c.source)
        .add_columns(pc.c.listed, pc.c.market_price, pc.c.sale_price)
        .join(snap, snap.c.id == pc.c.snapshot_id)
        .where(pc.c.auction_house_id == auction_house_id)
    ).all()
    buy: dict[int, int] = {}
    sell: dict[int, int] = {}
    books = load_books(conn, auction_house_id) if first_party else {}
    for r in rows:
        if first_party and r.source == ALTARMY:
            if r.item_id in books:
                buy[r.item_id] = books[r.item_id][0].price
            market = r.price if r.market_price is None else r.market_price
            sell[r.item_id] = book_sell_price(market, bool(r.listed), r.median_7d, r.sale_price)
        elif not first_party or r.source in HAND_SET:
            buy[r.item_id] = r.price
            sell[r.item_id] = sell_price(r.price, r.median_7d, r.source)
    return buy, sell


def sell_price(price: int, median_7d: int | None, source: str) -> int:
    """What a sale counts as: the lower of the cheapest listing and the 7-day median; a price set by hand
    as it is."""
    if source in HAND_SET or median_7d is None:
        return price
    return min(price, median_7d)


@dataclass(frozen=True)
class Listing:
    """What the auction house has of an item: its cheapest listing and the units listed (None: unknown).
    From Alt Army's scans also every price level listed, and the units that sold a day lately (None:
    unknown)."""

    min_buyout: int
    quantity: int | None
    ladder: book.Ladder = ()
    sale_rate: float | None = None
    # what says how far its price can be trusted (`confidence`)
    source: str = ""
    listed: bool | None = None  # False: the newest scan had none (since `seen_at`); None: not a scan's
    seen_at: datetime | None = None
    median_7d: int | None = None
    scans_7d: int | None = None  # the days that median is from
    sale_price: int | None = None
    market_price: int | None = (
        None  # what is asked: the price 15% into the units listed (`book.market_price`)
    )
    sold_pairs_7d: int | None = None  # the pairs of scans its sales were seen in lately


def sale_depth(listing: Listing, sell_price: int | None) -> int | None:
    """How many units of an item its market has shown it takes at `sell_price`: the more of those seen sold
    over the last week and those listed at or under the price (a crude depth, until a model of what sells
    replaces it); None for a price from another source than Alt Army's scans, which says nothing of it."""
    if listing.source != ALTARMY:
        return None
    sold = round((listing.sale_rate or 0.0) * SALES_DAYS)
    ahead = sum(lv.quantity for lv in listing.ladder if sell_price is not None and lv.price <= sell_price)
    return max(sold, ahead)


def load_listings(conn: Connection, auction_house_id: int | None) -> dict[int, Listing]:
    """{item_id: Listing} for the auction house; empty for None."""
    if auction_house_id is None:
        return {}
    pc, snap = schema.price_current, schema.price_snapshots
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.quantity, pc.c.ladder, pc.c.sale_rate, snap.c.source)
        .add_columns(pc.c.listed, pc.c.seen_at, pc.c.median_7d, pc.c.scans_7d, pc.c.sale_price)
        .add_columns(pc.c.market_price, pc.c.sold_pairs_7d)
        .join(snap, snap.c.id == pc.c.snapshot_id)
        .where(pc.c.auction_house_id == auction_house_id)
    )
    return {
        r.item_id: Listing(
            r.price,
            r.quantity,
            book.decode(r.ladder) if r.ladder else (),
            r.sale_rate,
            r.source,
            r.listed,
            db.utc(r.seen_at),
            r.median_7d,
            r.scans_7d,
            r.sale_price,
            r.market_price,
            r.sold_pairs_7d,
        )
        for r in rows
    }


def watched_hours(conn: Connection, auction_house_id: int | None, now: datetime | None = None) -> float:
    """How long the auction house was watched over the last SALES_DAYS days: the hours between its
    accepted Alt Army scans taken at most SALES_GAP apart, the only stretches whose sales are seen."""
    if auction_house_id is None:
        return 0.0
    snap = schema.price_snapshots
    now = db.utc(now or db.utcnow())
    rows = conn.execute(
        select(snap.c.scanned_at)
        .where(
            snap.c.auction_house_id == auction_house_id,
            snap.c.source == ALTARMY,
            snap.c.status == "accepted",
            snap.c.scanned_at > now - timedelta(days=SALES_DAYS),
        )
        .order_by(snap.c.scanned_at)
    )
    times = [db.utc(r.scanned_at) for r in rows]
    gaps = (b - a for a, b in zip(times, times[1:], strict=False))
    return sum((g for g in gaps if g <= SALES_GAP), timedelta()) / timedelta(hours=1)


ConfidenceLevel = Literal["high", "medium", "low"]
# Why: `hand_set` a price set by hand; `sold` enough sales seen; `few_sold` fewer than the plan sells (or
# seen while the house was hardly watched); `one_pair` all seen in one pair of scans (maybe one buyer);
# `unlisted` none listed and no sales seen; `few_days` its median is from too few days; `unsold` watched
# long enough to see sales and too few came; `unwatched` listed in depth but sales unknown; `thin` it
# rests on few listed units
ConfidenceReason = Literal[
    "hand_set", "sold", "few_sold", "one_pair", "unlisted", "few_days", "unsold", "unwatched", "thin"
]
# Every doubt about a price, each on its own (`Confidence.flags`), most actionable first: `lone` a listing or
# few that never sold (an asking price, not a price); `thin` few listed for what the plan sells; `sold_out`
# none listed, though some sold; `unlisted` none listed and none sold; `few_days` its median is from too few
# days; `unwatched` the house was hardly watched lately, so sales are unknown; `one_pair` its sales were all
# seen in one pair of scans
ConfidenceFlag = Literal["lone", "thin", "sold_out", "unlisted", "few_days", "unwatched", "one_pair"]


@dataclass(frozen=True)
class Confidence:
    """How far an item's AH sell price can be trusted, and why."""

    level: ConfidenceLevel
    reason: ConfidenceReason
    sold: int  # units seen sold over the last SALES_DAYS days
    units: int  # what the plan sells
    listed: int | None  # units listed now (None: unknown)
    scan_days: int  # the days its median is from
    watched_hours: float
    unlisted_since: datetime | None  # when it was last seen gone, if the newest scan had none
    flags: tuple[ConfidenceFlag, ...] = ()  # every doubt, most actionable first
    sold_pairs: int = 0  # the pairs of scans its sales were seen in


def confidence(listing: Listing, units: int, watched: float) -> Confidence:
    """How far `listing`'s sell price can be trusted for a sale of `units`, the auction house watched
    `watched` hours lately (`watched_hours`). Sales seen say most: enough to cover the plan, seen in at
    least two pairs of scans of a house watched WATCHED_ENOUGH_HOURS, is high; fewer, or all in one pair, or
    hardly watched, medium. Without them a price is low when nothing is listed, its median is from under
    CONFIDENT_SCAN_DAYS days, the house was watched WATCHED_ENOUGH_HOURS with too few sales, or it rests
    on a thin market (`thin_market`); else medium. A price set by hand is high. Whatever the level, `flags`
    lists every doubt."""
    sold = round((listing.sale_rate or 0.0) * SALES_DAYS)
    unlisted = listing.listed is False
    listed = 0 if unlisted else listing.quantity
    days = listing.scans_7d or 0
    pairs = listing.sold_pairs_7d or 0
    hand_set = listing.source in HAND_SET
    doubts: dict[ConfidenceFlag, bool] = {
        "lone": not unlisted and listed is not None and listed < THIN_UNITS and sold == 0,
        "thin": not unlisted and thin_market(listed, units),
        "sold_out": unlisted and sold > 0,
        "unlisted": unlisted and sold == 0,
        "few_days": listing.median_7d is None or days < CONFIDENT_SCAN_DAYS,
        "unwatched": watched < WATCHED_ENOUGH_HOURS,
        "one_pair": sold > 0 and pairs == 1,
    }
    flags = () if hand_set else tuple(f for f, doubt in doubts.items() if doubt)

    def says(level: ConfidenceLevel, reason: ConfidenceReason) -> Confidence:
        since = listing.seen_at if unlisted else None
        return Confidence(level, reason, sold, units, listed, days, round(watched, 1), since, flags, pairs)

    if hand_set:
        return says("high", "hand_set")
    if listing.sale_price is not None:
        if sold < units:
            return says("medium", "few_sold")
        if pairs >= 2 and watched >= WATCHED_ENOUGH_HOURS:
            return says("high", "sold")
        return says("medium", "one_pair") if pairs == 1 else says("medium", "few_sold")
    if unlisted:
        return says("low", "unlisted")
    if listing.median_7d is None or days < CONFIDENT_SCAN_DAYS:
        return says("low", "few_days")
    if watched >= WATCHED_ENOUGH_HOURS:
        return says("low", "unsold")
    if thin_market(listed, units):
        return says("low", "thin")
    return says("medium", "unwatched")


def thin_market(quantity: int | None, sold: int) -> bool:
    """Whether a sale of `sold` units rests on a thin market: fewer listed than THIN_UNITS or than it
    sells. Unknown quantities are not flagged."""
    return quantity is not None and (quantity < THIN_UNITS or quantity < sold)


def count_current(conn: Connection, auction_house_id: int | None) -> int:
    if auction_house_id is None:
        return 0
    pc = schema.price_current
    return int(
        conn.execute(
            select(func.count()).select_from(pc).where(pc.c.auction_house_id == auction_house_id)
        ).scalar_one()
    )


@dataclass(frozen=True)
class SnapshotStats:
    """One source's snapshots of a game version lately, for the Admin page."""

    source: str
    snapshots_24h: int
    snapshots_7d: int
    quarantined_7d: int
    items_7d: int  # items in those snapshots
    newest_received_at: datetime


def snapshot_stats(conn: Connection, game_version: str, now: datetime | None = None) -> list[SnapshotStats]:
    """Per source (by name), the snapshots `game_version`'s auction houses received in the last week."""
    snap, t = schema.price_snapshots, schema.auction_houses
    now = db.utc(now or db.utcnow())
    day, week = now - timedelta(days=1), now - timedelta(days=7)

    def count(condition: ColumnElement[bool]) -> ColumnElement[int]:
        return func.sum(case((condition, 1), else_=0))

    rows = conn.execute(
        select(
            snap.c.source,
            count(snap.c.received_at >= day),
            func.count(),
            count(snap.c.status == "quarantined"),
            func.sum(snap.c.item_count),
            func.max(snap.c.received_at),
        )
        .join(t, t.c.id == snap.c.auction_house_id)
        .where(t.c.game_version == game_version, snap.c.received_at >= week)
        .group_by(snap.c.source)
        .order_by(snap.c.source)
    ).all()
    return [
        SnapshotStats(source, int(d), int(w), int(q), int(items or 0), db.utc(newest))
        for source, d, w, q, items, newest in rows
    ]


def last_import(conn: Connection, auction_house_id: int | None, source: str = AUCTIONATOR) -> str | None:
    """When the newest snapshot from `source` for the auction house arrived, as UTC text."""
    if auction_house_id is None:
        return None
    snap = schema.price_snapshots
    newest = conn.execute(
        select(func.max(snap.c.received_at)).where(
            snap.c.auction_house_id == auction_house_id, snap.c.source == source
        )
    ).scalar_one_or_none()
    return db.timestamp_text(newest)


def daily(conn: Connection, auction_house_id: int, item_id: int) -> list[tuple[date, int, int, int | None]]:
    """An item's price history: (day, low, high, available), oldest first."""
    pd = schema.price_daily
    rows = conn.execute(
        select(pd.c.day, pd.c.low, pd.c.high, pd.c.available)
        .where(pd.c.auction_house_id == auction_house_id, pd.c.item_id == item_id)
        .order_by(pd.c.day)
    )
    return [(r.day, r.low, r.high, r.available) for r in rows]


# --- sources ---------------------------------------------------------------------------------------
def set_price(
    conn: Connection, auction_house_id: int, item_id: int, price: int, source: str = "manual"
) -> None:
    """One price, seen now."""
    now = db.utcnow()
    record_snapshot(conn, auction_house_id, source, now, [Observation(item_id, price, now)])
