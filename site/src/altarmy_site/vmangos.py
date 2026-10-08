"""Which items vendors sell, and where things stand in the cities, from vmangos' open-source vanilla (1.12)
world database.

DB2 does not say what vendors sell (that is server-side data), so `scripts/build_vendor_items.py` uses
this to regenerate `data/forever/vendor_items.csv` and `vendor_recipes.csv`, which ingest loads. The price
comes from DB2's BuyPrice.
`scripts/build_cities.py` reads the spawns of auctioneers, vendors, mailboxes and crafting stations around
each city (see `cities`). Coordinates are always bound as parameters: a negative one pasted into SQL
after a minus sign would start a comment.
"""

from __future__ import annotations

import csv
import sqlite3
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import astuple, dataclass, fields, replace
from pathlib import Path

from . import gamedata
from .ingest import ZoneBox, spawn_zone

# Items with unlimited stock and no condition (reputation, event, ...), sold by a vendor that spawns in
# the world, either directly or through a vendor template. A creature spawn can pick from up to five ids.
VENDOR_ITEMS_SQL = """
WITH spawned(entry) AS (
    SELECT id FROM creature UNION SELECT id2 FROM creature UNION SELECT id3 FROM creature
    UNION SELECT id4 FROM creature UNION SELECT id5 FROM creature
),
sold(item) AS (
    SELECT v.item FROM npc_vendor v JOIN spawned s ON s.entry = v.entry
    WHERE v.maxcount = 0 AND v.condition_id = 0
    UNION
    SELECT v.item FROM npc_vendor_template v
    JOIN creature_template ct ON ct.vendor_id = v.entry
    JOIN spawned s ON s.entry = ct.entry
    WHERE v.maxcount = 0 AND v.condition_id = 0
)
SELECT sold.item,
       (SELECT name FROM item_template it WHERE it.entry = sold.item ORDER BY patch DESC LIMIT 1)
FROM sold ORDER BY sold.item
"""

# Recipe items (item class 9) a spawned vendor sells without a condition, whatever the stock: a recipe with
# limited stock is still one anybody can go and buy.
ITEM_CLASS_RECIPE = 9
VENDOR_RECIPES_SQL = """
WITH spawned(entry) AS (
    SELECT id FROM creature UNION SELECT id2 FROM creature UNION SELECT id3 FROM creature
    UNION SELECT id4 FROM creature UNION SELECT id5 FROM creature
),
sold(item) AS (
    SELECT v.item FROM npc_vendor v JOIN spawned s ON s.entry = v.entry
    WHERE v.condition_id = 0
    UNION
    SELECT v.item FROM npc_vendor_template v
    JOIN creature_template ct ON ct.vendor_id = v.entry
    JOIN spawned s ON s.entry = ct.entry
    WHERE v.condition_id = 0
)
SELECT sold.item,
       (SELECT name FROM item_template it WHERE it.entry = sold.item ORDER BY patch DESC LIMIT 1)
FROM sold
WHERE EXISTS (SELECT 1 FROM item_template it WHERE it.entry = sold.item AND it.class = ?)
ORDER BY sold.item
"""

LATEST_PATCH = 10  # vmangos' content patches run 0 (1.2) to 10 (1.12); rows are kept per patch
NPC_VENDOR = 0x4  # creature_template.npc_flags
NPC_AUCTIONEER = 0x1000
MOVE_WAYPOINTS = 2  # creature.movement_type: 0 stands, 1 wanders nearby, 2 walks a waypoint route
GO_SPELL_FOCUS = 8  # gameobject_template.type; data0 is the SpellFocusObject id
GO_MAILBOX = 19


@dataclass(frozen=True)
class Spawn:
    """A creature or game object standing in the world."""

    guid: int
    entry: int
    name: str
    x: float
    y: float
    z: float
    data0: int = 0  # game objects: a spell focus's kind (1 anvil, 3 forge, 4 cooking fire, ...)


def city_centre(conn: sqlite3.Connection, tele: str) -> tuple[int, float, float, float]:
    """(map, x, y, z) of a `game_tele` point (e.g. "Orgrimmar"); ValueError if there is none."""
    row = conn.execute(
        "SELECT map, position_x, position_y, position_z FROM game_tele WHERE name = ?", (tele,)
    ).fetchone()
    if row is None:
        raise ValueError(f"no game_tele point named {tele!r}")
    return int(row[0]), float(row[1]), float(row[2]), float(row[3])


_NEAR = """
(({t}.position_x - ?) * ({t}.position_x - ?) + ({t}.position_y - ?) * ({t}.position_y - ?)
 + ({t}.position_z - ?) * ({t}.position_z - ?)) <= ?
"""


def _near(t: str, x: float, y: float, z: float, radius: float) -> tuple[str, tuple[float, ...]]:
    return _NEAR.format(t=t), (x, x, y, y, z, z, radius * radius)


def _unique(spawns: Iterable[Spawn]) -> list[Spawn]:
    """One spawn per entry and spot: vmangos repeats some for different patch ranges."""
    seen: dict[tuple[int, int, int, int], Spawn] = {}
    for s in spawns:
        seen.setdefault((s.entry, round(s.x), round(s.y), round(s.z)), s)
    return sorted(seen.values(), key=lambda s: s.guid)


def npcs_near(
    conn: sqlite3.Connection, map_id: int, x: float, y: float, z: float, radius: float, flag: int
) -> list[Spawn]:
    """Creatures spawned within `radius` yards (in 3D) whose newest template has the `npc_flags` bit
    `flag`. One who walks a waypoint route (Thunder Bluff's Chepi, Orgrimmar's Felika) stands at
    `route_middle` instead of where they spawn."""
    near, args = _near("c", x, y, z, radius)
    rows = conn.execute(
        f"""
        SELECT c.guid, t.entry, t.name, c.position_x, c.position_y, c.position_z, c.movement_type
        FROM creature c JOIN creature_template t ON t.entry = c.id
        WHERE t.patch = (
            SELECT MAX(patch) FROM creature_template n WHERE n.entry = t.entry AND n.patch <= ?
        )
          AND c.map = ? AND c.patch_min <= ? AND c.patch_max >= ? AND (t.npc_flags & ?) != 0 AND {near}
        """,
        (LATEST_PATCH, map_id, LATEST_PATCH, LATEST_PATCH, flag, *args),
    ).fetchall()
    spawns = []
    for g, e, n, px, py, pz, move in rows:
        s = Spawn(int(g), int(e), str(n), float(px), float(py), float(pz))
        if move == MOVE_WAYPOINTS:
            s = route_middle(conn, s)
        spawns.append(s)
    return _unique(spawns)


def route_middle(conn: sqlite3.Connection, s: Spawn) -> Spawn:
    """`s` moved to the point of their waypoint route nearest the route's middle (the first such point on
    a tie): a spot on the path, where they pass by. The route is the spawn's own (`creature_movement`, by
    guid), else their template's (`creature_movement_template`, by entry); without one they stay put."""
    points = (
        conn.execute(
            "SELECT position_x, position_y, position_z FROM creature_movement WHERE id = ? ORDER BY point",
            (s.guid,),
        ).fetchall()
        or conn.execute(
            "SELECT position_x, position_y, position_z FROM creature_movement_template WHERE entry = ?"
            " ORDER BY point",
            (s.entry,),
        ).fetchall()
    )
    if not points:
        return s
    mx, my, mz = (sum(float(p[i]) for p in points) / len(points) for i in range(3))
    px, py, pz = min(points, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2 + (p[2] - mz) ** 2)
    return replace(s, x=float(px), y=float(py), z=float(pz))


def objects_near(
    conn: sqlite3.Connection, map_id: int, x: float, y: float, z: float, radius: float, go_type: int
) -> list[Spawn]:
    """Game objects of `go_type` spawned within `radius` yards (in 3D), with their newest template."""
    near, args = _near("o", x, y, z, radius)
    rows = conn.execute(
        f"""
        SELECT o.guid, t.entry, t.name, o.position_x, o.position_y, o.position_z, t.data0
        FROM gameobject o JOIN gameobject_template t ON t.entry = o.id
        WHERE t.patch = (
            SELECT MAX(patch) FROM gameobject_template n WHERE n.entry = t.entry AND n.patch <= ?
        )
          AND o.map = ? AND o.patch_min <= ? AND o.patch_max >= ? AND t.type = ? AND {near}
        """,
        (LATEST_PATCH, map_id, LATEST_PATCH, LATEST_PATCH, go_type, *args),
    )
    return _unique(
        Spawn(int(g), int(e), str(n), float(px), float(py), float(pz), int(d0))
        for g, e, n, px, py, pz, d0 in rows
    )


def vendor_stock(conn: sqlite3.Connection, entries: Iterable[int]) -> dict[int, list[int]]:
    """What each vendor (creature entry) sells without limit or condition, directly or through its vendor
    template; vendors selling nothing so are left out."""
    wanted = sorted(set(entries))
    if not wanted:
        return {}
    marks = ",".join("?" * len(wanted))
    rows = conn.execute(
        f"""
        SELECT v.entry, v.item FROM npc_vendor v
        WHERE v.entry IN ({marks}) AND v.maxcount = 0 AND v.condition_id = 0
        UNION
        SELECT t.entry, v.item FROM npc_vendor_template v
        JOIN creature_template t ON t.vendor_id = v.entry
        WHERE t.entry IN ({marks}) AND v.maxcount = 0 AND v.condition_id = 0
        ORDER BY 1, 2
        """,
        (*wanted, *wanted),
    )
    out: dict[int, list[int]] = {}
    for entry, item in rows:
        out.setdefault(int(entry), []).append(int(item))
    return out


def vendor_factions(conn: sqlite3.Connection, entries: Iterable[int]) -> dict[int, int]:
    """The faction (`Faction` id: whose reputation their prices follow) of each creature entry, from its
    newest template and that faction template's newest build; creatures without one are left out."""
    wanted = sorted(set(entries))
    if not wanted:
        return {}
    marks = ",".join("?" * len(wanted))
    rows = conn.execute(
        f"""
        SELECT t.entry, ft.faction_id
        FROM creature_template t JOIN faction_template ft ON ft.id = t.faction
        WHERE t.entry IN ({marks})
          AND t.patch = (
            SELECT MAX(patch) FROM creature_template n WHERE n.entry = t.entry AND n.patch <= ?
          )
          AND ft.build = (SELECT MAX(build) FROM faction_template n WHERE n.id = ft.id)
        ORDER BY 1
        """,
        (*wanted, LATEST_PATCH),
    )
    return {int(entry): int(faction) for entry, faction in rows}


def vendor_items(conn: sqlite3.Connection) -> list[tuple[int, str]]:
    """(item id, name) of every item a vendor sells without limit."""
    return [(int(i), str(name or "")) for i, name in conn.execute(VENDOR_ITEMS_SQL)]


def vendor_recipes(conn: sqlite3.Connection) -> list[tuple[int, str]]:
    """(item id, name) of every recipe item a vendor sells without a condition, limited stock included."""
    rows = conn.execute(VENDOR_RECIPES_SQL, (ITEM_CLASS_RECIPE,))
    return [(int(i), str(name or "")) for i, name in rows]


# What trainers charge, and the skill they ask for. They list a server-side "teach" spell whose learn effect
# names the spell taught (the newest build of each spell_template row); rows that ended before vmangos' last
# build (1.12.1, 5875) are fees that later patches changed. A profession recipe's required skill
# (`reqskillvalue`) is the same at every trainer; 0 is a class spell's. The recipes that come with the
# profession (SkillLineAbility's AcquireMethod 1) are listed by no trainer.
EFFECT_LEARN_SPELL = 36
LATEST_BUILD = 5875
TRAINER_COSTS_SQL = """
WITH newest AS (
    SELECT s.entry, s.effect1, s.effectTriggerSpell1, s.effect2, s.effectTriggerSpell2,
           s.effect3, s.effectTriggerSpell3
    FROM spell_template s
    WHERE s.build = (SELECT MAX(build) FROM spell_template n WHERE n.entry = s.entry)
),
offered(spell, cost, req) AS (
    SELECT spell, spellcost, reqskillvalue FROM npc_trainer WHERE build_max >= :latest
    UNION ALL
    SELECT spell, spellcost, reqskillvalue FROM npc_trainer_template WHERE build_max >= :latest
),
taught(spell, cost, req) AS (
    SELECT CASE
             WHEN n.effect1 = :learn AND n.effectTriggerSpell1 > 0 THEN n.effectTriggerSpell1
             WHEN n.effect2 = :learn AND n.effectTriggerSpell2 > 0 THEN n.effectTriggerSpell2
             WHEN n.effect3 = :learn AND n.effectTriggerSpell3 > 0 THEN n.effectTriggerSpell3
             ELSE o.spell
           END,
           o.cost,
           o.req
    FROM offered o LEFT JOIN newest n ON n.entry = o.spell
)
SELECT spell, MIN(cost), MIN(req) FROM taught GROUP BY spell ORDER BY spell
"""


def trainer_costs(conn: sqlite3.Connection) -> list[tuple[int, int, int]]:
    """(spell id, copper, required skill) of every spell a trainer teaches, at the least any trainer asks
    (the skill is 0 for what needs none: class spells)."""
    rows = conn.execute(TRAINER_COSTS_SQL, {"latest": LATEST_BUILD, "learn": EFFECT_LEARN_SPELL})
    return [(int(spell), int(cost or 0), int(req or 0)) for spell, cost, req in rows]


# --- where recipe items come from -------------------------------------------------------------------
MAX_DROPS = 3  # drop sources listed per item; the rest are counted in a "more" row
WORLD_DROP_AT = 20  # more creatures than this dropping an item: a world drop, not a list
MAX_REF_DEPTH = 3  # reference loot tables pointing at others
ALLIANCE_MASK, HORDE_MASK = 2, 4  # faction_template masks
ALLIANCE_RACES = 1 | 4 | 8 | 64  # human, dwarf, night elf, gnome (quest_template.RequiredRaces)
HORDE_RACES = 2 | 16 | 32 | 128  # orc, undead, tauren, troll
GO_CHEST = 3  # gameobject_template.type; data1 is its loot id
MAP_COMMON = 0  # map_template.map_type: the open world; others are instances and battlegrounds
QUEST_REWARDS = [f"RewItemId{i}" for i in range(1, 5)] + [f"RewChoiceItemId{i}" for i in range(1, 7)]


@dataclass(frozen=True)
class ItemSource:
    """Somewhere an item comes from: a row of `recipe_item_sources.csv` (see `schema.item_sources`)."""

    item_id: int
    kind: str  # vendor | drop | object | container | world_drop | quest | more
    name: str = ""
    zone: str = ""
    side: str = ""  # alliance | horde: a vendor or quest only that faction can use; "" both
    chance: float = 0.0  # percent
    count: int = 0  # world_drop: creatures dropping it; more: sources not listed
    levels: str = ""
    limited: bool = False  # vendor: limited stock
    area: int = 0  # vendor: the zone map it stands on (AreaTable id, frontend/public/maps); 0 if none
    map_x: float = 0.0  # vendor: where on that map, percent
    map_y: float = 0.0


@dataclass(frozen=True)
class _Creature:
    name: str
    faction: int
    level_min: int
    level_max: int
    loot_id: int


def _newest(rows: Iterable[Sequence[object]]) -> dict[int, tuple[object, ...]]:
    """(entry, patch, *values) rows -> each entry's values from its newest patch up to `LATEST_PATCH`."""
    out: dict[int, tuple[int, tuple[object, ...]]] = {}
    for entry, patch, *values in rows:
        e, p = int(str(entry)), int(str(patch))
        if p <= LATEST_PATCH and (e not in out or p >= out[e][0]):
            out[e] = (p, tuple(values))
    return {e: v for e, (_, v) in out.items()}


def _sides(conn: sqlite3.Connection) -> dict[int, str]:
    """faction_template id -> the side an NPC of it serves: "horde" if hostile to the Alliance only,
    "alliance" if hostile to the Horde only, else ""."""
    newest: dict[int, tuple[int, int]] = {}
    for fid, build, hostile in conn.execute("SELECT id, build, hostile_mask FROM faction_template"):
        if fid not in newest or build > newest[fid][0]:
            newest[fid] = (build, hostile)
    out = {}
    for fid, (_, hostile) in newest.items():
        a, h = bool(hostile & ALLIANCE_MASK), bool(hostile & HORDE_MASK)
        out[fid] = "horde" if a and not h else "alliance" if h and not a else ""
    return out


@dataclass(frozen=True)
class _Spot:
    """Where a creature or object stands: its zone, and on that zone's map (0 when not on one)."""

    zone: str
    area: int = 0  # the zone map's AreaTable id
    map_x: float = 0.0  # percent, 0 left to 100 right
    map_y: float = 0.0  # percent, 0 top to 100 bottom


def map_coords(box: ZoneBox, x: float, y: float) -> tuple[float, float]:
    """(map x, map y) of a world position on a zone map, in percent with one decimal: world y runs right to
    left, world x bottom to top (as `timing.Zone.map_coords`)."""
    _, _, x0, y0, x1, y1, _ = box
    return round(100 * (y1 - y) / (y1 - y0), 1), round(100 * (x1 - x) / (x1 - x0), 1)


def _zones(
    conn: sqlite3.Connection, table: str, ids: Sequence[str], zones: Sequence[ZoneBox]
) -> dict[int, _Spot]:
    """Entry -> the zone most of its spawns in `table` (creature or gameobject) stand in: the zone map
    around the spawn in the open world, else the instance's name ("" for a spawn neither names), with
    the first of those spawns (by guid) on that zone's map."""
    maps = {
        m: (int(str(t)), str(n))
        for m, (t, n) in _newest(
            conn.execute("SELECT entry, patch, map_type, map_name FROM map_template")
        ).items()
    }
    counts: dict[int, Counter[str]] = {}
    first: dict[tuple[int, str], _Spot] = {}
    rows = conn.execute(
        f"SELECT {', '.join(ids)}, map, position_x, position_y FROM {table} "
        "WHERE patch_min <= ? AND patch_max >= ? ORDER BY guid",
        (LATEST_PATCH, LATEST_PATCH),
    )
    for *entries, map_id, x, y in rows:
        kind, name = maps.get(map_id, (MAP_COMMON, ""))
        spot = _Spot(name)
        if kind == MAP_COMMON:
            box = spawn_zone(zones, map_id, x, y)
            spot = _Spot(box[1], box[6], *map_coords(box, x, y)) if box else _Spot("")
        for e in entries:
            if e:
                counts.setdefault(e, Counter())[spot.zone] += 1
                first.setdefault((e, spot.zone), spot)
    return {e: first[e, c.most_common(1)[0][0]] for e, c in counts.items()}


_LootRow = tuple[int, float, int, int, int]  # item, chance, group, mincountOrRef, maxcount


def _loot(conn: sqlite3.Connection, table: str) -> dict[int, list[_LootRow]]:
    """A loot table's rows per entry (quest drops' negative chances made positive)."""
    out: dict[int, list[_LootRow]] = {}
    rows = conn.execute(
        f"SELECT entry, item, ChanceOrQuestChance, groupid, mincountOrRef, maxcount FROM {table} "
        "WHERE patch_min <= ? AND patch_max >= ?",
        (LATEST_PATCH, LATEST_PATCH),
    )
    for entry, item, chance, group, ref, most in rows:
        out.setdefault(entry, []).append((item, abs(float(chance)), group, ref, most))
    return out


def _chances(rows: Sequence[_LootRow]) -> list[tuple[_LootRow, float]]:
    """Each row's chance in percent: a grouped row without one shares what the group's others leave."""
    explicit: dict[int, float] = {}
    equal: Counter[int] = Counter()
    for _, chance, group, _, _ in rows:
        if group and not chance:
            equal[group] += 1
        else:
            explicit[group] = explicit.get(group, 0.0) + chance
    out = []
    for r in rows:
        _, chance, group, _, _ = r
        if not chance and group:
            chance = max(0.0, 100.0 - explicit.get(group, 0.0)) / equal[group]
        out.append((r, chance))
    return out


class _Loot:
    """Item chances (percent) of loot entries, reference tables followed."""

    def __init__(self, refs: Mapping[int, list[_LootRow]]) -> None:
        self.refs = refs
        self.memo: dict[int, dict[int, float]] = {}

    def items(self, rows: Sequence[_LootRow], depth: int = 0) -> dict[int, float]:
        out: dict[int, float] = {}
        for (item, _, _, ref, most), chance in _chances(rows):
            if ref < 0:
                if depth < MAX_REF_DEPTH:
                    for i, c in self._ref(-ref, depth + 1).items():
                        out[i] = out.get(i, 0.0) + chance / 100 * max(1, most) * c
            else:
                out[item] = out.get(item, 0.0) + chance
        return {i: min(100.0, c) for i, c in out.items()}

    def _ref(self, entry: int, depth: int) -> dict[int, float]:
        if entry not in self.memo:
            self.memo[entry] = {}  # a reference back to itself ends here
            self.memo[entry] = self.items(self.refs.get(entry, []), depth)
        return self.memo[entry]


def _creatures(conn: sqlite3.Connection) -> dict[int, _Creature]:
    rows = conn.execute(
        "SELECT entry, patch, name, faction, level_min, level_max, loot_id FROM creature_template"
    )
    return {
        e: _Creature(str(n), int(str(f)), int(str(lo)), int(str(hi)), int(str(loot)))
        for e, (n, f, lo, hi, loot) in _newest(rows).items()
    }


def recipe_item_sources(conn: sqlite3.Connection, zones: Sequence[ZoneBox]) -> list[ItemSource]:
    """Where every recipe item (item class 9) comes from in vanilla's world: the spawned vendors selling
    it (without a condition), the quests rewarding it, and what drops it: the `MAX_DROPS` likeliest of
    the spawned creatures, chests and containers, the rest counted in one "more" row, the creatures
    replaced by one "world_drop" row when more than `WORLD_DROP_AT` drop it. Per item: vendors, quests,
    then drops. `zones`: the client's zone maps (`ingest.zone_boxes`)."""
    items = _newest(conn.execute("SELECT entry, patch, name, class FROM item_template"))
    recipes = {i for i, (_, cls) in items.items() if cls == ITEM_CLASS_RECIPE}
    sides = _sides(conn)
    creatures = _creatures(conn)
    spawned = _zones(conn, "creature", ["id", "id2", "id3", "id4", "id5"], zones)
    out: dict[int, list[ItemSource]] = {}

    def add(source: ItemSource) -> None:
        if source not in out.setdefault(source.item_id, []):
            out[source.item_id].append(source)

    # vendors
    sold = conn.execute(
        """
        SELECT v.entry, v.item, v.maxcount FROM npc_vendor v WHERE v.condition_id = 0
        UNION
        SELECT ct.entry, v.item, v.maxcount FROM npc_vendor_template v
        JOIN creature_template ct ON ct.vendor_id = v.entry
        WHERE v.condition_id = 0
        """
    )
    vendors = sorted(
        (item, creatures[entry].name, entry, most)
        for entry, item, most in sold
        if item in recipes and entry in creatures and entry in spawned
    )
    for item, name, entry, most in vendors:
        side = sides.get(creatures[entry].faction, "")
        at = spawned[entry]
        add(
            ItemSource(item, "vendor", name, at.zone, side, 0.0, 0, "", most > 0, at.area, at.map_x, at.map_y)
        )

    # quests, placed where their giver stands, else in the zone they are filed under
    quests = _newest(
        conn.execute(
            f"SELECT entry, patch, Title, ZoneOrSort, QuestLevel, RequiredRaces, {', '.join(QUEST_REWARDS)} "
            "FROM quest_template"
        )
    )
    givers: dict[int, int] = {}
    relations = conn.execute(
        "SELECT id, quest FROM creature_questrelation WHERE patch_min <= ? AND patch_max >= ? ORDER BY id",
        (LATEST_PATCH, LATEST_PATCH),
    )
    for creature, quest in relations:
        if creature in spawned and creature in creatures:
            givers.setdefault(quest, creature)
    areas = {int(a): str(n) for a, n in conn.execute("SELECT entry, name FROM area_template")}
    for qid in sorted(quests):
        title, *numbers = quests[qid]
        if str(title).startswith("<"):  # <UNUSED>, <NYI>, ...: never in the game
            continue
        zone_or_sort, level, races, *rewards = (int(str(v or 0)) for v in numbers)
        for item in dict.fromkeys(rewards):
            if item not in recipes:
                continue
            giver = givers.get(qid)
            zone = (spawned[giver].zone if giver else "") or areas.get(zone_or_sort, "")
            side = "alliance" if races & ALLIANCE_RACES and not races & HORDE_RACES else ""
            side = "horde" if races & HORDE_RACES and not races & ALLIANCE_RACES else side
            if not races and giver:
                side = sides.get(creatures[giver].faction, "")
            add(ItemSource(item, "quest", str(title), zone, side, levels=str(level) if level > 0 else ""))

    # drops: spawned creatures, chests and containers
    loot = _Loot(_loot(conn, "reference_loot_template"))
    looters: dict[int, list[int]] = {}
    for entry, c in sorted(creatures.items()):
        if c.loot_id and entry in spawned:
            looters.setdefault(c.loot_id, []).append(entry)
    dropped: dict[int, list[tuple[ItemSource, _Creature]]] = {}
    creature_loot = _loot(conn, "creature_loot_template")
    for loot_id, entries in sorted(looters.items()):
        for item, chance in loot.items(creature_loot.get(loot_id, [])).items():
            if item in recipes and chance > 0:
                for e in entries:
                    c = creatures[e]
                    drop = ItemSource(item, "drop", c.name, spawned[e].zone, chance=chance)
                    dropped.setdefault(item, []).append((drop, c))

    others: dict[int, list[ItemSource]] = {}
    placed = _zones(conn, "gameobject", ["id"], zones)
    object_loot = _loot(conn, "gameobject_loot_template")
    objects = _newest(conn.execute("SELECT entry, patch, name, type, data1 FROM gameobject_template"))
    for entry, (go_name, go_type, go_loot) in sorted(objects.items()):
        if int(str(go_type)) == GO_CHEST and entry in placed:
            for item, chance in loot.items(object_loot.get(int(str(go_loot)), [])).items():
                if item in recipes and chance > 0:
                    chest = ItemSource(item, "object", str(go_name), placed[entry].zone, chance=chance)
                    others.setdefault(item, []).append(chest)
    for container, rows in sorted(_loot(conn, "item_loot_template").items()):
        for item, chance in loot.items(rows).items():
            if item in recipes and chance > 0 and container in items:
                box = ItemSource(item, "container", str(items[container][0]), chance=chance)
                others.setdefault(item, []).append(box)

    for item in sorted(set(dropped) | set(others)):
        found = dropped.get(item, [])
        if len({d.name for d, _ in found}) > WORLD_DROP_AT:
            # the chests and lockboxes holding it share the world drop's loot: nothing more to say
            span = f"{min(c.level_min for _, c in found)}-{max(c.level_max for _, c in found)}"
            add(ItemSource(item, "world_drop", count=len({d.name for d, _ in found}), levels=span))
            continue
        best: dict[tuple[str, str], ItemSource] = {}
        for d, _ in found:  # creatures sharing a name and zone are one source
            if (d.name, d.zone) not in best or d.chance > best[d.name, d.zone].chance:
                best[d.name, d.zone] = d
        listed = list(best.values())
        chests: dict[tuple[str, str], list[ItemSource]] = {}
        for d in others.get(item, []):  # a chest standing in several zones is one source, placed nowhere
            chests.setdefault((d.kind, d.name), []).append(d)
        for same in chests.values():
            zone = same[0].zone if len({d.zone for d in same}) == 1 else ""
            listed.append(replace(max(same, key=lambda d: d.chance), zone=zone))
        listed.sort(key=lambda d: (-d.chance, d.name, d.zone))
        for d in listed[:MAX_DROPS]:
            add(ItemSource(d.item_id, d.kind, d.name, d.zone, chance=round(d.chance, 2)))
        if len(listed) > MAX_DROPS:
            add(ItemSource(item, "more", count=len(listed) - MAX_DROPS))

    return [s for item in sorted(out) for s in out[item]]


def write_sources_csv(rows: Sequence[ItemSource], path: Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow([f.name for f in fields(ItemSource)])
        w.writerows([int(v) if isinstance(v, bool) else v for v in astuple(r)] for r in rows)


def download_world_db(cache_dir: Path, release: str | None = None) -> Path:
    """vmangos' world database: `release` (else the newest), cached (`gamedata.world_db`)."""
    return gamedata.world_db("vmangos", cache_dir, release)


def write_csv(rows: list[tuple[int, str]], path: Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["item_id", "name"])
        w.writerows(rows)


def write_trainer_costs_csv(
    rows: list[tuple[int, int, int]], path: Path, shifts: Mapping[int, int] | None = None
) -> None:
    """`trainer_costs`' rows, each with how far the game moved the spell's colours down from the emulator's
    (`ingest.yellow_shifts`; 0 when not), which ingest takes off the skill the trainer asks for."""
    shifts = shifts or {}
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["spell_id", "cost", "req_skill", "yellow_shift"])
        w.writerows((spell, cost, req, shifts.get(spell, 0)) for spell, cost, req in rows)
