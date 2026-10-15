"""Auction snapshots in the shape Blizzard's connected-realm auctions endpoint serves, for tests."""

from __future__ import annotations

import json
from typing import Any

from altarmy_site import snapshots, versions

FOREVER = versions.get("forever")
T0 = 1_762_257_600  # 2025-11-04 12:00 UTC, on the hour
HOUR = 3600


def auction(
    auction_id: int,
    item: int,
    *,
    unit: int | None = None,
    qty: int = 1,
    buyout: int | None = None,
    bid: int | None = None,
    left: str = "LONG",
) -> dict[str, Any]:
    """One auction: a `unit` price makes a stack buyout of `unit * qty` (Classic's shape)."""
    out: dict[str, Any] = {"id": auction_id, "item": {"id": item}, "quantity": qty, "time_left": left}
    if unit is not None:
        out["buyout"] = unit * qty
    if buyout is not None:
        out["buyout"] = buyout
    if bid is not None:
        out["bid"] = bid
    return out


def body(*auctions: dict[str, Any]) -> bytes:
    return json.dumps({"id": 6, "name": "Horde Auction House", "auctions": list(auctions)}).encode()


def snap(t: int, *auctions: dict[str, Any]) -> snapshots.Snapshot:
    return snapshots.parse_blizzard(body(*auctions), t=t, realm="Normal", faction="Horde")


def run(*snaps: snapshots.Snapshot) -> list[snapshots.Diff]:
    """Each snapshot diffed against the state the ones before it left."""
    state: snapshots.HouseState | None = None
    out = []
    for s in snaps:
        d = snapshots.diff(state, s, FOREVER.buckets, FOREVER.snapshot_gap)
        out.append(d)
        state = d.state
    return out


def outcomes(d: snapshots.Diff) -> dict[int, str]:
    """Each ended auction's outcome, by auction id."""
    return {e.live.auction.id: e.outcome for e in d.ended}
