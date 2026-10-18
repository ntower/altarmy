"""Vendor runs: gold made between vendors and the auction house, the half that needs no price history.

- Listed under what a vendor pays (`under_vendor`): units on the AH cheaper than a vendor gives for them,
  bought and sold to any vendor. A level that has not survived `suspects.LISTED_UNDER_AGE` scans is
  flagged: a fresh one may be gone before anyone gets there, or the vendor price may be wrong.
- Bought from a vendor, sold on the AH (`resells`): what spawned vendors sell (`vendor_offers.csv`, from
  vmangos: `vmangos.vendor_offers`) for less than the AH pays after its cut and the deposit, for as many
  units as a limited vendor stocks, else a share of what the market takes in a day, posted in the stack size
  that sold best; only items whose AH sale counts (`Market.ah_open`).

Pure apart from reading the offers file (once per file, as `processing` does).
"""

from __future__ import annotations

import csv
import functools
import math
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from . import engine, prices, suspects
from .versions import GameVersion

POST_SHARE = 1 / 3  # as `service.POST_SHARE`: of a day's units bought, what one seller posts
POST_HOURS = 24  # the auction a post is for


@dataclass(frozen=True)
class Offer:
    """An item a vendor sells: a row of `vendor_offers.csv` (`vmangos.VendorOffer`)."""

    item_id: int
    vendor: int
    name: str
    side: str  # alliance | horde | "" both
    max_count: int  # 0 unlimited
    restock_s: int
    zone: str
    area: int
    map_x: float
    map_y: float


def read_offers(path: Path) -> tuple[Offer, ...]:
    """The offers in a `vendor_offers.csv`; none without the file."""
    if not path.is_file():
        return ()
    with open(path, newline="", encoding="utf-8") as f:
        return tuple(
            Offer(
                int(r["item_id"]),
                int(r["vendor"]),
                r["name"],
                r["side"],
                int(r["max_count"]),
                int(r["restock_s"]),
                r["zone"],
                int(r["area"]),
                float(r["map_x"]),
                float(r["map_y"]),
            )
            for r in csv.DictReader(f)
        )


@functools.cache
def offers_at(path: Path) -> tuple[Offer, ...]:
    """`read_offers`, once per file for the process's life."""
    return read_offers(path)


@dataclass(frozen=True)
class UnderVendor:
    item_id: int
    units: int  # listed under what a vendor pays
    cheapest: int  # the cheapest such listing's unit price
    vendor: int  # what a vendor pays a unit
    profit: int  # buying them all and selling them to a vendor
    fresh: bool  # the cheapest such level is new: it may be gone, or the vendor price wrong


def under_vendor(market: engine.Market, listings: Mapping[int, prices.Listing]) -> list[UnderVendor]:
    """The items listed under what a vendor pays (see the module), the most profit first."""
    out = []
    for item_id, listing in listings.items():
        item = market.items.get(item_id)
        if item is None or item.sell_price <= 0 or not listing.listed:
            continue
        under = [lv for lv in listing.ladder if lv.price < item.sell_price and not lv.tail]
        if not under:
            continue
        units = sum(lv.quantity for lv in under)
        profit = sum((item.sell_price - lv.price) * lv.quantity for lv in under)
        out.append(
            UnderVendor(
                item_id,
                units,
                under[0].price,
                item.sell_price,
                profit,
                under[0].age < suspects.LISTED_UNDER_AGE,
            )
        )
    return sorted(out, key=lambda u: (-u.profit, u.item_id))


@dataclass(frozen=True)
class Resell:
    offer: Offer
    unit_cost: int  # what the vendor charges a unit
    sell_price: int  # what the AH sale counts on a unit
    margin: int  # a unit's profit: the AH's net, less the cost and the deposit
    units: int  # a run's: the stock of a limited vendor, else a share of a day's sales
    profit: int  # margin x units


def deposit(version: GameVersion, vendor_sell_price: int, stack: int = 1) -> int:
    """A unit's share of the deposit posting it in a day's auctions of `stack` costs
    (`GameVersion.ah_deposit`, estimated: at least the auction's minimum over its units)."""
    return math.ceil(version.ah_deposit(vendor_sell_price, stack, stack, POST_HOURS) / max(1, stack))


def resells(
    market: engine.Market,
    listings: Mapping[int, prices.Listing],
    offers: Iterable[Offer],
    buy_prices: Mapping[int, int],
    faction: str,
    version: GameVersion,
) -> list[Resell]:
    """The offers (see the module) a character of `faction` can buy from, each vendor's own, the most
    profit first. `buy_prices` is what a vendor charges a unit of each item (DB2's)."""
    side = faction.lower()
    out = []
    for o in offers:
        if o.side and o.side != side:
            continue
        item = market.items.get(o.item_id)
        cost = buy_prices.get(o.item_id)
        price = market.sell_prices.get(o.item_id)
        if item is None or not item.tradable or cost is None or cost <= 0 or price is None:
            continue
        if market.ah_open is not None and o.item_id not in market.ah_open:
            continue
        listing = listings.get(o.item_id)
        stack = min(prices.best_stack(listing) or 1, item.stack_size) if listing is not None else 1
        margin = engine.ah_net(price, market.ah_cut) - cost - deposit(version, item.sell_price, stack)
        if margin <= 0:
            continue
        a_day = prices.demand(listing, days=1) if listing is not None else None
        units = o.max_count or (int(a_day * POST_SHARE) if a_day else 0)
        if units <= 0:
            continue
        out.append(Resell(o, cost, price, margin, units, margin * units))
    return sorted(out, key=lambda r: (-r.profit, r.offer.item_id, r.offer.vendor))


def by_zone(runs: Sequence[Resell]) -> list[tuple[str, list[Resell]]]:
    """The resells as one run per zone, the zone worth most first."""
    zones: dict[str, list[Resell]] = {}
    for r in runs:
        zones.setdefault(r.offer.zone, []).append(r)
    return sorted(zones.items(), key=lambda z: (-sum(r.profit for r in z[1]), z[0]))
