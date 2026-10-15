"""What WoW: Forever's Waylaid Crates and Craftsman's Writs take, by item: the Market section's turn-ins.

A shipment crate ("Waylaid Crate: Apprentice Herbs") is filled with any one bundle its Use text lists ("- 20
Peacebloom"), each named; a writ ("Craftsman's Writ: Lesser Wizard's Robe") asks for the crafted item its
name names. Both are read from the game data the site loads (`items` names and Use texts, the items craft
recipes make), as the addon's generators (`addon/scripts/generate-waylaid-crates.py`, `generate-writs.py`)
read them; the crate's and the writ's reputation and a writ's count are not in the game data, so a writ
counts one unit. Worked out once per game data load (`db.get_loaded`).
"""

from __future__ import annotations

import json
import re
import threading
from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import Connection, select

from . import db, schema

CRATE = "Waylaid Crate: "
WRIT = "Craftsman's Writ: "
BUNDLE_LINE = re.compile(r"^- (\d+) (.+?)(?:\|r)?\s*$")


@dataclass(frozen=True)
class TurnIn:
    """A crate or writ that takes an item, and how many."""

    kind: str  # crate | writ
    name: str  # the crate's or writ's name
    count: int


_cache: dict[tuple[str, str | None, int], dict[int, tuple[TurnIn, ...]]] = {}
_lock = threading.Lock()


def turn_ins(conn: Connection, game_version: str) -> dict[int, tuple[TurnIn, ...]]:
    """{item_id: the crates and writs that take it} for the version's loaded game data."""
    build, loads = db.get_loaded(conn, game_version)
    key = (game_version, build, loads)
    with _lock:
        found = _cache.get(key)
    if found is None:
        found = _read(conn, game_version)
        with _lock:
            _cache.clear()  # one load per version is ever current: keep only this one
            _cache[key] = found
    return found


def _normal(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()


def _read(conn: Connection, game_version: str) -> dict[int, tuple[TurnIn, ...]]:
    items = schema.items
    rows = conn.execute(
        select(items.c.id, items.c.name, items.c.effects, items.c.bonding).where(
            items.c.game_version == game_version
        )
    ).all()
    tradable: dict[str, list[int]] = defaultdict(list)
    for r in rows:
        if r.bonding == 0:
            tradable[r.name].append(r.id)
    out: dict[int, list[TurnIn]] = defaultdict(list)
    for r in rows:
        if not r.name.startswith(CRATE):
            continue
        for line in _use_text(r.effects).replace("|cnIQ1:", "\n").splitlines():
            m = BUNDLE_LINE.match(line.strip())
            ids = tradable.get(m.group(2), []) if m else []
            if m and len(ids) == 1:
                out[ids[0]].append(TurnIn("crate", r.name, int(m.group(1))))
    recipes = schema.recipes
    made: dict[str, set[int]] = defaultdict(set)
    for r in conn.execute(
        select(items.c.id, items.c.name)
        .join(
            recipes,
            (recipes.c.game_version == items.c.game_version) & (recipes.c.output_item_id == items.c.id),
        )
        .where(items.c.game_version == game_version)
    ):
        made[_normal(r.name)].add(r.id)
    for r in rows:
        if r.name.startswith(WRIT):
            for item_id in made.get(_normal(r.name[len(WRIT) :]), ()):
                out[item_id].append(TurnIn("writ", r.name, 1))
    return {i: tuple(sorted(t, key=lambda x: (x.kind, x.name))) for i, t in out.items()}


def _use_text(effects: str | None) -> str:
    try:
        parsed = json.loads(effects or "[]")
    except ValueError:
        return ""
    for effect in parsed if isinstance(parsed, list) else []:
        if isinstance(effect, dict) and effect.get("trigger") == "Use":
            return str(effect.get("text") or "")
    return ""
