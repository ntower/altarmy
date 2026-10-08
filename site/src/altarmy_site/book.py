"""The auction house's order book, from the Alt Army addon's full scans (`AltArmyTBC_AuctionBook` in
`AltArmy_TBC.lua`, written by the addon's `Data/Auctions/AuctionScan.lua` and `AuctionBook.lua`).

A scan holds, per item, a ladder: the units listed at each unit price, cheapest first. At most the
addon's 12 levels, then one tail level pooling the rest at its cheapest price. Prices are copper. With a
ladder, what `qty` units cost is a walk up it (`cost`), so a lone cheap listing is one cheap unit and not
the item's price; `market_price` is the price a little way into the book; `sold_between` infers what sold
between two scans from the units gone off the cheap end.

Pure and standard library only. Uploads are untrusted: anything malformed is a ValueError.
`tests/fixtures/auction_book_v1.lua` is a copy of the addon's golden `spec/fixtures/auction_book_v1.lua`,
so change both together.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from .luasv import LuaValue, parse_assignment

GLOBAL = "AltArmyTBC_AuctionBook"
FACTIONS = ("Horde", "Alliance")
MAX_SCANS = 64  # the addon keeps 3 per realm and faction
MAX_ITEMS = 100_000
MAX_LEVELS = 32  # the addon writes 12 and a tail
MAX_COPPER = 10**12  # 100 million gold: more is corrupt data
MAX_UNITS = 10**9
MAX_REALM = 64
DEPTH = 0.15  # how far into the listed units the market price is read


@dataclass(frozen=True)
class Level:
    """The units listed at one unit price."""

    price: int
    quantity: int
    listings: int
    tail: bool = False  # pools every level past the addon's limit, at the cheapest of their prices
    age: int = 0  # scans before this one that already had units at this price


Ladder = tuple[Level, ...]  # cheapest first


@dataclass(frozen=True)
class Scan:
    """One full scan of one auction house. Only complete scans are read."""

    t: int  # Unix seconds, the game server's time
    realm: str
    faction: str  # Horde | Alliance
    listings: int  # listings read, those without a buyout included
    bid_only: int  # listings without a buyout: counted, not priced
    source: str  # own | heard
    items: dict[int, Ladder]


@dataclass(frozen=True)
class Sold:
    """What happened to the units gone between two scans."""

    units: int  # gone off the cheap end: bought
    copper: int  # what they were listed for
    cancelled: int  # gone from behind cheaper listings, or with nothing left to tell by


# --- reading ---------------------------------------------------------------------------------------
def read(data: bytes) -> list[Scan]:
    """The complete scans in an `AltArmy_TBC.lua`, oldest first; [] if it has no book. ValueError if the
    book is malformed."""
    try:
        log = parse_assignment(data, GLOBAL)
    except (IndexError, RecursionError) as e:
        raise ValueError("the auction house scans are cut off or nested too deeply") from e
    if log is None:
        return []
    scans = log.get("scans") if isinstance(log, dict) else None
    if not isinstance(scans, dict):
        raise ValueError("the auction house scans are not a list")
    if len(scans) > MAX_SCANS:
        raise ValueError(f"more than {MAX_SCANS} auction house scans")
    out = [_scan(entry) for entry in scans.values()]
    return sorted((s for s in out if s is not None), key=lambda s: s.t)


def _scan(entry: LuaValue) -> Scan | None:
    if not isinstance(entry, dict):
        raise ValueError("an auction house scan is not a table")
    if entry.get("complete") is not True:
        return None
    realm, faction, source = entry.get("realm"), entry.get("faction"), entry.get("source")
    if not isinstance(realm, str) or not 0 < len(realm) <= MAX_REALM:
        raise ValueError("an auction house scan has no realm")
    if faction not in FACTIONS:
        raise ValueError(f"an auction house scan's faction is {faction!r}")
    if not isinstance(source, str):
        raise ValueError("an auction house scan has no source")
    items = entry.get("items")
    if not isinstance(items, str):
        raise ValueError("an auction house scan has no items")
    return Scan(
        _whole(entry.get("t"), "time", 1, 2**40),
        realm,
        str(faction),
        _whole(entry.get("listings"), "listing count", 0, MAX_UNITS),
        _whole(entry.get("bidOnly", 0), "bid count", 0, MAX_UNITS),
        source[:16],
        _items(items),
    )


def _whole(value: LuaValue, what: str, low: int, high: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError(f"an auction house scan's {what} is {value!r}")
    return value


def _items(text: str) -> dict[int, Ladder]:
    out: dict[int, Ladder] = {}
    if not text:
        return out
    entries = text.split(";")
    if len(entries) > MAX_ITEMS:
        raise ValueError(f"more than {MAX_ITEMS} items in an auction house scan")
    for entry in entries:
        key, sep, levels = entry.partition(":")
        item_id = _number(key, "item", MAX_UNITS)
        if not sep or item_id in out:
            raise ValueError(f"bad item in an auction house scan: {entry[:40]!r}")
        out[item_id] = _ladder(levels, fields=3)
    return out


def _number(text: str, what: str, high: int, low: int = 1) -> int:
    if not text.isascii() or not text.isdigit() or len(text) > 15:
        raise ValueError(f"bad {what} in an auction house scan: {text[:40]!r}")
    value = int(text)
    if not low <= value <= high:
        raise ValueError(f"bad {what} in an auction house scan: {text[:40]!r}")
    return value


def _ladder(text: str, fields: int) -> Ladder:
    """A ladder from its text, each level of `fields` numbers: strictly cheapest first, a tail only last."""
    parts = text.split(",")
    if len(parts) > MAX_LEVELS:
        raise ValueError(f"more than {MAX_LEVELS} price levels for an item")
    levels: list[Level] = []
    for part in parts:
        if levels and levels[-1].tail:
            raise ValueError("a price level follows the tail")
        tail = part.startswith("~")
        numbers = part[1:].split("*") if tail else part.split("*")
        if len(numbers) != fields:
            raise ValueError(f"bad price level: {part[:40]!r}")
        price = _number(numbers[0], "price", MAX_COPPER)
        if levels and price <= levels[-1].price:
            raise ValueError("price levels are not cheapest first")
        quantity = _number(numbers[1], "quantity", MAX_UNITS)
        listings = _number(numbers[2], "listing count", MAX_UNITS)
        age = _number(numbers[3], "age", MAX_UNITS, low=0) if fields > 3 else 0
        levels.append(Level(price, quantity, listings, tail, age))
    return tuple(levels)


# --- text (how a ladder is stored) -------------------------------------------------------------------
def encode(ladder: Ladder) -> str:
    """`<price>*<units>*<listings>*<age>,...`, the tail marked `~`; "" for no listings."""
    return ",".join(
        f"{'~' if lv.tail else ''}{lv.price}*{lv.quantity}*{lv.listings}*{lv.age}" for lv in ladder
    )


def decode(text: str) -> Ladder:
    """The ladder `encode` wrote; ValueError otherwise."""
    return _ladder(text, fields=4) if text else ()


# --- prices ------------------------------------------------------------------------------------------
def quantity(ladder: Ladder) -> int:
    """Units listed."""
    return sum(lv.quantity for lv in ladder)


def cost(ladder: Ladder, qty: int) -> tuple[int, int] | None:
    """(copper for `qty` units bought cheapest first, units short); None when nothing is listed. Units
    the book is short of cost the highest level's price: they are not there to buy."""
    if not ladder:
        return None
    total, left = 0, qty
    for lv in ladder:
        take = min(left, lv.quantity)
        total += take * lv.price
        left -= take
        if left <= 0:
            return total, 0
    return total + left * ladder[-1].price, left


def market_price(ladder: Ladder) -> int | None:
    """The unit price DEPTH of the way into the listed units: past a few stray cheap listings, well
    before the overpriced end. None when nothing is listed."""
    if not ladder:
        return None
    target = quantity(ladder) * DEPTH
    seen = 0
    for lv in ladder:
        seen += lv.quantity
        if seen >= target:
            return lv.price
    return ladder[-1].price


def aged(before: Ladder, after: Ladder) -> Ladder:
    """`after` with each level's age: one more than the level at that price in `before`, else 0."""
    ages = {lv.price: lv.age + 1 for lv in before if not lv.tail}
    return tuple(replace(lv, age=0 if lv.tail else ages.get(lv.price, 0)) for lv in after)


def sold_between(before: Ladder, after: Ladder) -> Sold:
    """What the units gone between two scans of an item tell. A buyer takes the cheapest, so units gone
    at or below the cheapest price still listed were bought; units gone from behind it were cancelled
    (or expired). With nothing left listed there is no telling, and new cheaper listings sold nothing.
    Tails pool many prices and are not counted. A listing new since the first scan and cheaper than anything
    in it doesn't count for the cheapest still listed: posted in between, it can't have been there when the
    units it undercut went."""
    still = {lv.price: lv.quantity for lv in after if not lv.tail}
    was = {lv.price for lv in before if not lv.tail}
    cheapest_before = min(was, default=None)
    floor = min(
        (
            lv.price
            for lv in after
            if lv.price in was or cheapest_before is None or lv.price >= cheapest_before
        ),
        default=None,
    )
    units = copper = cancelled = 0
    for lv in before:
        if lv.tail:
            continue
        gone = lv.quantity - still.get(lv.price, 0)
        if gone <= 0:
            continue
        if floor is not None and lv.price <= floor:
            units += gone
            copper += gone * lv.price
        else:
            cancelled += gone
    return Sold(units, copper, cancelled)
