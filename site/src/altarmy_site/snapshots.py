"""Hourly snapshots of an auction house, as Blizzard's game data API serves them, and what happened to the
auctions between two of them.

A snapshot lists every auction on one house: its id, item, stack size, buyout (or unit price), bid and a
time-left bucket. `diff` carries the live auctions from one snapshot to the next and says how each one
that vanished ended: bought (`sold`), withdrawn by its seller (`pulled`), run out (`expired`), won by a bid
(`bid_won`), taken down and posted again alike (`relisted`), or `ambiguous` when the snapshots can't tell.
A buyout and a withdrawal look the same in the API, so `sold` is inferred the way `book.sold_between` does
it: an auction gone at or under the cheapest price still listed was bought, one gone from behind it was
pulled. Each auction's end is narrowed by every time-left bucket it was seen in (`Live.end_lo`/`end_hi`),
which is what tells an expiry from a sale.

Pure and standard library only (plus `book`, so a snapshot's ladders are the addon's). The feed is
untrusted like an upload: anything malformed is a ValueError.
"""

from __future__ import annotations

import gzip
import json
import math
import zlib
from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Literal, cast, get_args

from . import book

TimeLeft = Literal["SHORT", "MEDIUM", "LONG", "VERY_LONG"]
TIME_LEFT: tuple[TimeLeft, ...] = get_args(TimeLeft)
Outcome = Literal["sold", "pulled", "expired", "bid_won", "relisted", "ambiguous"]
OUTCOMES: tuple[Outcome, ...] = get_args(Outcome)
SOLD: tuple[Outcome, ...] = ("sold", "bid_won")  # the outcomes that are sales
LEVELS = 12  # price levels in a ladder before the tail, as the addon writes them
MAX_AUCTIONS = 1_000_000
MAX_ID = 2**62
PARTIAL_SHARE = 0.5  # a snapshot with under this share of the previous one's auctions is held back
PARTIAL_MIN = 50  # ... once the previous one had this many


@dataclass(frozen=True)
class Auction:
    """One auction as a snapshot shows it."""

    id: int
    item_id: int
    quantity: int
    unit_price: int | None  # the buyout per unit, rounded up; None for an auction without a buyout
    bid: int | None  # the bid on the whole stack, as served
    time_left: TimeLeft


@dataclass(frozen=True)
class Snapshot:
    """Every auction on one auction house at one time."""

    t: int  # Unix seconds it stands for
    realm: str  # as the feed names it
    faction: str  # Alliance | Horde
    auctions: tuple[Auction, ...]
    build: str | None = None  # the game build the snapshot was taken under, when known


@dataclass(frozen=True)
class Live:
    """An auction carried from snapshot to snapshot."""

    auction: Auction  # as last seen
    first_seen: int | None  # when a snapshot first had it; None when it was there before the feed began
    end_lo: int  # it runs out after this (Unix seconds) ...
    end_hi: int  # ... and no later than this, narrowed by every time-left bucket it was seen in
    first_bid: int | None  # its bid when first seen: a bid that rose was bid on


@dataclass(frozen=True)
class HouseState:
    """The auctions live on one house after a snapshot."""

    t: int
    live: Mapping[int, Live] = field(default_factory=dict)  # by auction id


@dataclass(frozen=True)
class Ended:
    """An auction gone between two snapshots, and how it ended."""

    live: Live
    outcome: Outcome
    age_h: int | None  # whole hours it was up, from its first snapshot; None when that is unknown


@dataclass(frozen=True)
class Diff:
    """What one snapshot says against the state before it."""

    state: HouseState  # the state after it (the state before, when the snapshot is stale)
    follows: bool  # it came soon enough after the state before to tell what ended in between
    stale: bool  # no newer than the state before: nothing to record
    ended: tuple[Ended, ...] = ()
    posted: tuple[Live, ...] = ()  # auctions new since the state before, relists left out


@dataclass(frozen=True)
class Tally:
    """Auctions, units and copper of one kind of event."""

    auctions: int = 0
    units: int = 0
    copper: int = 0  # what the sold ones went for: the buyout, or a won bid


# --- reading ---------------------------------------------------------------------------------------
def parse_blizzard(body: bytes, *, t: int, realm: str, faction: str, build: str | None = None) -> Snapshot:
    """A snapshot from the body of Blizzard's connected-realm auctions endpoint. Auctions carry a stack
    `buyout` (Classic) or a `unit_price` (commodities); either is kept per unit. ValueError if malformed."""
    try:
        data = json.loads(body)
    except RecursionError as e:
        raise ValueError("the auction snapshot is nested too deeply") from e
    except UnicodeDecodeError as e:
        raise ValueError("the auction snapshot is not text") from e
    if not isinstance(data, dict):
        raise ValueError("the auction snapshot is not an object")
    entries = data.get("auctions", [])
    if not isinstance(entries, list):
        raise ValueError("the auction snapshot's auctions are not a list")
    if len(entries) > MAX_AUCTIONS:
        raise ValueError(f"more than {MAX_AUCTIONS} auctions in a snapshot")
    seen: set[int] = set()
    auctions = []
    for entry in entries:
        a = _auction(entry)
        if a.id in seen:
            raise ValueError(f"auction {a.id} is listed twice")
        seen.add(a.id)
        auctions.append(a)
    return Snapshot(t, realm, faction, tuple(auctions), build)


def _auction(entry: object) -> Auction:
    if not isinstance(entry, dict):
        raise ValueError("an auction is not an object")
    item = entry.get("item")
    if not isinstance(item, dict):
        raise ValueError("an auction has no item")
    quantity = _whole(entry.get("quantity"), "quantity", 1, book.MAX_UNITS)
    unit = _optional(entry.get("unit_price"), "unit price")
    buyout = _optional(entry.get("buyout"), "buyout")
    if unit is None and buyout is not None:
        unit = math.ceil(buyout / quantity)
    time_left = entry.get("time_left")
    if time_left not in TIME_LEFT:
        raise ValueError(f"an auction's time left is {time_left!r}")
    return Auction(
        _whole(entry.get("id"), "id", 1, MAX_ID),
        _whole(item.get("id"), "item", 1, book.MAX_UNITS),
        quantity,
        unit,
        _optional(entry.get("bid"), "bid"),
        cast(TimeLeft, time_left),
    )


def _whole(value: object, what: str, low: int, high: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError(f"an auction's {what} is {value!r}")
    return value


def _optional(value: object, what: str) -> int | None:
    """A price that may be absent: None for missing or 0 (Blizzard's "no buyout")."""
    if value is None or value == 0:
        return None
    return _whole(value, what, 1, book.MAX_COPPER)


# --- ladders -----------------------------------------------------------------------------------------
def ladders(snapshot: Snapshot) -> dict[int, book.Ladder]:
    """Each item's ladder, pooled as the addon pools a scan: per unit price the units and auctions,
    cheapest first, `LEVELS` levels and then one tail level at the cheapest of the rest. Auctions without
    a buyout can't be bought, so they are left out."""
    by_item: dict[int, Counter[int]] = {}
    listings: dict[int, Counter[int]] = {}
    for a in snapshot.auctions:
        if a.unit_price is None:
            continue
        by_item.setdefault(a.item_id, Counter())[a.unit_price] += a.quantity
        listings.setdefault(a.item_id, Counter())[a.unit_price] += 1
    out: dict[int, book.Ladder] = {}
    for item_id, units in by_item.items():
        prices = sorted(units)
        levels = [book.Level(p, units[p], listings[item_id][p]) for p in prices[:LEVELS]]
        rest = prices[LEVELS:]
        if rest:
            levels.append(
                book.Level(
                    rest[0],
                    sum(units[p] for p in rest),
                    sum(listings[item_id][p] for p in rest),
                    tail=True,
                )
            )
        out[item_id] = tuple(levels)
    return out


# --- what happened between two snapshots ----------------------------------------------------------------
def diff(
    before: HouseState | None, snap: Snapshot, buckets: Mapping[str, tuple[int, int]], max_gap_s: int
) -> Diff:
    """Carry the auctions live in `before` to `snap` and say how each one gone in between ended.

    Only a snapshot within `max_gap_s` of the one before `follows` it: after a longer gap nothing is said
    to have ended or been posted, since anything could have come and gone unseen. An auction gone whose
    end window had passed ran out (`bid_won` if its bid rose, else `expired`); one whose window had not
    begun was bought or pulled (`sold` at or under the item's cheapest price still listed, else `pulled`;
    `pulled` too when it had no buyout); one taken down and posted again alike (same item, stack and unit
    price) is `relisted`; anything else is `ambiguous`."""
    if before is not None and snap.t <= before.t:
        return Diff(before, follows=False, stale=True)
    follows = before is not None and snap.t - before.t <= max_gap_s
    prior: Mapping[int, Live] = before.live if before is not None else {}
    live: dict[int, Live] = {}
    new: list[Live] = []
    for a in snap.auctions:
        lo, hi = _window(a.time_left, snap.t, buckets)
        was = prior.get(a.id)
        if was is not None and was.auction.item_id == a.item_id:
            end_lo, end_hi = max(was.end_lo, lo), min(was.end_hi, hi)
            if end_lo >= end_hi:  # the buckets disagree: trust the newest
                end_lo, end_hi = lo, hi
            live[a.id] = Live(a, was.first_seen, end_lo, end_hi, was.first_bid)
        else:
            entry = Live(a, snap.t if follows else None, lo, hi, a.bid)
            live[a.id] = entry
            new.append(entry)
    state = HouseState(snap.t, live)
    if not follows:
        return Diff(state, follows=False, stale=False)

    gone = sorted((v for k, v in prior.items() if k not in live), key=lambda v: v.auction.id)
    alike: dict[tuple[int, int, int | None], list[Live]] = {}
    for n in sorted(new, key=lambda n: n.auction.id):
        alike.setdefault(_kind(n), []).append(n)
    relisted: set[int] = set()  # the gone auctions posted again
    reposts: set[int] = set()  # the new auctions that are those reposts
    for v in gone:
        twins = alike.get(_kind(v))
        if twins:
            relisted.add(v.auction.id)
            reposts.add(twins.pop(0).auction.id)
    posted = tuple(n for n in new if n.auction.id not in reposts)

    floors = _floors(prior, live)
    ended = []
    for v in gone:
        outcome: Outcome
        if v.auction.id in relisted:
            outcome = "relisted"
        elif v.end_hi <= snap.t:
            outcome = "bid_won" if _bid_rose(v) else "expired"
        elif v.end_lo >= snap.t:
            floor = floors.get(v.auction.item_id)
            if v.auction.unit_price is None:
                outcome = "pulled"
            elif floor is None:
                outcome = "ambiguous"
            else:
                outcome = "sold" if v.auction.unit_price <= floor else "pulled"
        else:
            outcome = "ambiguous"
        ended.append(Ended(v, outcome, _age(v, snap.t)))
    return Diff(state, follows=True, stale=False, ended=tuple(ended), posted=posted)


def _window(time_left: str, t: int, buckets: Mapping[str, tuple[int, int]]) -> tuple[int, int]:
    lo, hi = buckets[time_left]
    return t + lo, t + hi


def _bid_rose(v: Live) -> bool:
    return v.auction.bid is not None and v.first_bid is not None and v.auction.bid > v.first_bid


def _age(v: Live, t: int) -> int | None:
    if v.first_seen is None:
        return None
    return max(1, math.ceil((t - v.first_seen) / 3600))


def _kind(v: Live) -> tuple[int, int, int | None]:
    """What makes two auctions alike: item, stack size and unit price."""
    return v.auction.item_id, v.auction.quantity, v.auction.unit_price


def _floors(prior: Mapping[int, Live], live: Mapping[int, Live]) -> dict[int, int]:
    """Per item, the cheapest unit price still listed that could have stood under the auctions gone: one
    already listed before, or one no cheaper than the item's cheapest before (a newer, cheaper auction was
    posted after the cheap ones went, so it tells nothing about them). Items with nothing left have none."""
    cheapest_before: dict[int, int] = {}
    for v in prior.values():
        p, item = v.auction.unit_price, v.auction.item_id
        if p is not None:
            cheapest_before[item] = min(p, cheapest_before.get(item, p))
    floors: dict[int, int] = {}
    for auction_id, v in live.items():
        p, item = v.auction.unit_price, v.auction.item_id
        if p is None:
            continue
        if auction_id in prior or item not in cheapest_before or p >= cheapest_before[item]:
            floors[item] = min(p, floors.get(item, p))
    return floors


def looks_partial(before: HouseState | None, snap: Snapshot) -> bool:
    """Whether `snap` looks cut short: well under half the auctions of the one before (some realms have
    served empty or half-empty snapshots). Such a snapshot is held back, never diffed."""
    if before is None or len(before.live) < PARTIAL_MIN:
        return False
    return len(snap.auctions) < len(before.live) * PARTIAL_SHARE


# --- counting ----------------------------------------------------------------------------------------
def flows(d: Diff) -> dict[tuple[int, int, str], Tally]:
    """Per (item, stack size, outcome or "posted"): how many auctions and units, and what the sold ones
    went for."""
    out: dict[tuple[int, int, str], Tally] = {}

    def add(item_id: int, quantity: int, kind: str, copper: int) -> None:
        t = out.get((item_id, quantity, kind), Tally())
        out[(item_id, quantity, kind)] = Tally(t.auctions + 1, t.units + quantity, t.copper + copper)

    for e in d.ended:
        a = e.live.auction
        copper = 0
        if e.outcome == "sold" and a.unit_price is not None:
            copper = a.unit_price * a.quantity
        elif e.outcome == "bid_won" and a.bid is not None:
            copper = a.bid
        add(a.item_id, a.quantity, e.outcome, copper)
    for n in d.posted:
        add(n.auction.item_id, n.auction.quantity, "posted", 0)
    return out


def end_counts(d: Diff) -> dict[tuple[int, int, int, str], Tally]:
    """Per (item, stack size, hours up, outcome) of the auctions that ended with a known age: what time to
    sell is worked out from (`km_median`)."""
    out: dict[tuple[int, int, int, str], Tally] = {}
    for e in d.ended:
        if e.age_h is None:
            continue
        a = e.live.auction
        key = (a.item_id, a.quantity, e.age_h, e.outcome)
        t = out.get(key, Tally())
        out[key] = Tally(t.auctions + 1, t.units + a.quantity, 0)
    return out


def sell_through(sold: int, expired: int) -> float | None:
    """The share of auctions that ran their course and sold rather than ran out; None with neither."""
    return sold / (sold + expired) if sold + expired else None


def km_median(events: Mapping[int, int], censored: Mapping[int, int]) -> float | None:
    """The hours by which half the auctions sell (Kaplan-Meier): `events` counts sales by whole hours up,
    `censored` the auctions that left unsold (ran out, pulled, relisted) or are still up, by their hours.
    A censored auction counts as still at risk in its own hour. None when fewer than half ever sell."""
    hours = sorted(set(events) | set(censored))
    at_risk = sum(events.values()) + sum(censored.values())
    survive = 1.0
    for h in hours:
        d = events.get(h, 0)
        if at_risk > 0 and d:
            survive *= 1 - d / at_risk
            if survive <= 0.5:
                return float(h)
        at_risk -= d + censored.get(h, 0)
    return None


def live_ages(state: HouseState) -> Counter[tuple[int, int]]:
    """Per (item, whole hours up) the auctions still live with a known age: censored for time to sell."""
    out: Counter[tuple[int, int]] = Counter()
    for v in state.live.values():
        if v.first_seen is not None:
            out[(v.auction.item_id, max(1, math.ceil((state.t - v.first_seen) / 3600)))] += 1
    return out


# --- storing the live state -------------------------------------------------------------------------------
def encode_state(state: HouseState) -> bytes:
    """The live auctions, gzipped: one line per auction, the state's time first."""
    lines = [str(state.t)]
    for v in sorted(state.live.values(), key=lambda v: v.auction.id):
        a = v.auction
        lines.append(
            ",".join(
                (
                    str(a.id),
                    str(a.item_id),
                    str(a.quantity),
                    _opt(a.unit_price),
                    _opt(a.bid),
                    a.time_left,
                    _opt(v.first_seen),
                    str(v.end_lo),
                    str(v.end_hi),
                    _opt(v.first_bid),
                )
            )
        )
    return gzip.compress("\n".join(lines).encode(), mtime=0)


def decode_state(blob: bytes) -> HouseState:
    """The state `encode_state` wrote; ValueError otherwise."""
    try:
        text = gzip.decompress(blob).decode()
    except (OSError, EOFError, UnicodeDecodeError, zlib.error) as e:
        raise ValueError("the stored auction state is unreadable") from e
    first, *rest = text.split("\n")
    live: dict[int, Live] = {}
    for line in rest:
        f = line.split(",")
        if len(f) != 10:
            raise ValueError(f"bad stored auction: {line[:40]!r}")
        time_left = f[5]
        if time_left not in TIME_LEFT:
            raise ValueError(f"bad stored auction: {line[:40]!r}")
        a = Auction(_int(f[0]), _int(f[1]), _int(f[2]), _int_or_none(f[3]), _int_or_none(f[4]), time_left)
        live[a.id] = Live(a, _int_or_none(f[6]), _int(f[7]), _int(f[8]), _int_or_none(f[9]))
    return HouseState(_int(first), live)


def _opt(n: int | None) -> str:
    return "" if n is None else str(n)


def _int(text: str) -> int:
    try:
        return int(text)
    except ValueError as e:
        raise ValueError(f"bad number in the stored auction state: {text[:20]!r}") from e


def _int_or_none(text: str) -> int | None:
    return None if text == "" else _int(text)
