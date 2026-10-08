"""Download wago.tools DB2 CSVs and load one game version's items and recipes into the database."""

from __future__ import annotations

import csv
import hashlib
import json
from collections.abc import Collection, Iterable, Iterator
from dataclasses import asdict, replace
from pathlib import Path

from sqlalchemy import Connection, delete

from . import db, gamedata, itemstats, schema, spelltext, timing, versions

# The modules whose code decides what a load derives from the DB2 tables (`fingerprint`).
FINGERPRINTED_MODULES = (Path(__file__), Path(itemstats.__file__), Path(spelltext.__file__))
TABLES = [
    "Item",
    "ItemSparse",
    "ItemSubClass",
    "ManifestInterfaceData",
    "SkillLine",
    "SkillLineAbility",
    "SpellName",
    "SpellEffect",
    "SpellReagents",
    "SpellMisc",
    "SpellCastTimes",
    "SpellCastingRequirements",
    "SpellFocusObject",
    # item tooltips (itemstats.py)
    "RandPropPoints",
    "ItemArmorTotal",
    "ItemArmorQuality",
    "ArmorLocation",
    "ItemDamageOneHand",
    "ItemDamageTwoHand",
    "ItemDamageRanged",
    "ItemDamageWand",
    # item spell effects (spelltext.py)
    "ItemEffect",
    "Spell",
    "SpellDuration",
]
# Tables some client lacks (wago.tools answers 4xx): cached as an empty file and read as no rows.
OPTIONAL_TABLES = [
    "ItemArmorShield",  # not in TBC's client
    "ItemXItemEffect",  # Forever links items to effects through it; TBC's ItemEffect names the item
    "SpellAuraOptions",
    "SpellRadius",
    "SpellCooldowns",  # profession spells' cooldowns (transmutes, Mooncloth)
]
EFFECT_CREATE_ITEM = 24
EFFECT_ENCHANT_ITEM = 53  # enchants an item the caster holds: nothing is made
SOULBOUND = (1, 4)  # ItemSparse.Bonding: on pickup, quest item (never traded)
TRIGGER_LEARN = 6  # ItemEffect.TriggerType of the spell a recipe item teaches
ACQUIRE_WITH_SKILL = 1  # SkillLineAbility.AcquireMethod of a recipe learned with the profession itself
TRIGGER_USE = 0
# A conversion's recipe id: clear of SkillLineAbility ids, inside 32 bits
CONVERSION_ID_BASE = 1_000_000_000
MAX_REAGENTS = 8


def latest_build(product: str) -> str:
    """The newest build of a wago.tools product (versions.GameVersion.wago_product)."""
    return gamedata.latest_build(product)


def pinned_build(version: versions.GameVersion, pins: Path = gamedata.PINS) -> str:
    """The build the version's committed data was made from (`data/game-data.json`)."""
    return gamedata.read_pins(pins)[version.key].build


def download(table: str, build: str, cache_dir: Path, optional: bool = False) -> Path:
    """The table's CSV for the build, downloaded once into the cache (`gamedata.download_table`)."""
    return gamedata.download_table(table, build, cache_dir, optional)


def download_all(build: str, cache_dir: Path) -> dict[str, Path]:
    paths = {t: download(t, build, cache_dir) for t in TABLES}
    paths.update({t: download(t, build, cache_dir, optional=True) for t in OPTIONAL_TABLES})
    return paths


def _rows(path: Path) -> Iterator[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def _optional_rows(paths: dict[str, Path], table: str) -> Iterator[dict[str, str]]:
    """The table's rows, or none when it is missing (an older `paths`, the test fixture) or empty (a
    build that does not serve it)."""
    path = paths.get(table)
    if path is not None and path.stat().st_size > 0:
        yield from _rows(path)


def _int(v: str | None, default: int = 0) -> int:
    try:
        return int(float(v)) if v not in (None, "") else default
    except ValueError:
        return default


def _float(v: str | None, default: float = 0.0) -> float:
    try:
        return float(v) if v not in (None, "") else default
    except ValueError:
        return default


def _icon_names(path: Path) -> dict[int, str]:
    """Icon FileDataID -> icon name as Wowhead's CDN spells it (lowercase, no .blp)."""
    return {
        _int(r["ID"]): r["FileName"].lower().removesuffix(".blp")
        for r in _rows(path)
        if r["FilePath"].lower().startswith("interface\\icons")
    }


def output_count(effect: dict[str, str]) -> int:
    """Items one cast of a CreateItem SpellEffect row makes (random counts averaged), at least 1.

    Forever's builds carry the count in `EffectBasePointsF`. TBC's leave that 0 and use the older encoding:
    `EffectBasePoints` plus a roll of 1..`EffectDieSides` (Thorium Grenade: 2 + 1 = 3).
    """
    as_float = round(float(effect.get("EffectBasePointsF") or 0))
    if as_float > 0:
        return as_float
    base, sides = _int(effect.get("EffectBasePoints")), _int(effect.get("EffectDieSides"))
    return max(1, base + (1 + sides) // 2 if sides > 0 else base)


def cast_times(spell_misc: Path, spell_cast_times: Path) -> dict[int, int]:
    """Spell id -> cast time in ms, from SpellMisc's CastingTimeIndex into SpellCastTimes' Base. A spell
    has a SpellMisc row per difficulty; the normal one (DifficultyID 0) wins, else the first."""
    base = {_int(r["ID"]): _int(r["Base"]) for r in _rows(spell_cast_times)}
    out: dict[int, int] = {}
    for r in _rows(spell_misc):
        spell = _int(r["SpellID"])
        if spell not in out or _int(r.get("DifficultyID")) == 0:
            out[spell] = base.get(_int(r["CastingTimeIndex"]), 0)
    return out


def cooldowns(rows: Iterable[dict[str, str]]) -> dict[int, int]:
    """Spell id -> cooldown in ms, from SpellCooldowns: the longer of its own (RecoveryTime) and its
    category's (CategoryRecoveryTime). A spell has a row per difficulty; the normal one (DifficultyID 0)
    wins, else the first."""
    out: dict[int, int] = {}
    normal: set[int] = set()
    for r in rows:
        spell = _int(r["SpellID"])
        if spell in normal or (spell in out and _int(r.get("DifficultyID")) != 0):
            continue
        out[spell] = max(_int(r.get("RecoveryTime")), _int(r.get("CategoryRecoveryTime")))
        if _int(r.get("DifficultyID")) == 0:
            normal.add(spell)
    return out


def spell_stations(requirements: Path, focus_objects: Path) -> dict[int, str]:
    """Spell id -> the crafting station it is cast at (`timing.station_kind` of its SpellFocusObject name)."""
    names = focus_names(focus_objects)
    out = {}
    for r in _rows(requirements):
        focus = _int(r["RequiresSpellFocus"])
        if focus in names:
            out[_int(r["SpellID"])] = timing.station_kind(names[focus])
    return out


def focus_names(focus_objects: Path) -> dict[int, str]:
    """SpellFocusObject id -> name (Anvil, Spinning Wheel, ...)."""
    return {_int(r["ID"]): r["Name_lang"] for r in _rows(focus_objects) if r["Name_lang"]}


def craft_stations(paths: dict[str, Path]) -> dict[int, str]:
    """The spell foci some profession spell (SkillLineAbility) is cast at: id -> name. Leaves out the
    holiday and quest objects (bonfires, firework launchers, ...) nothing is crafted at."""
    crafts = {_int(r["Spell"]) for r in _rows(paths["SkillLineAbility"])}
    used = {
        _int(r["RequiresSpellFocus"])
        for r in _rows(paths["SpellCastingRequirements"])
        if _int(r["SpellID"]) in crafts
    }
    return {i: n for i, n in focus_names(paths["SpellFocusObject"]).items() if i in used}


# (map id, zone map name, min x, min y, max x, max y, area id: AreaTable's, naming Wowhead's zone map)
ZoneBox = tuple[int, str, float, float, float, float, int]


def zone_boxes(ui_map_assignment: Path, ui_map: Path) -> list[ZoneBox]:
    """Each zone map's box in world coordinates (DB2 UiMapAssignment rows that span the whole map, named
    from UiMap), for turning positions into the map percentages players read."""
    names = {_int(r["ID"]): r["Name_lang"] for r in _rows(ui_map)}
    out: list[ZoneBox] = []
    for r in _rows(ui_map_assignment):
        if (r["UiMin_0"], r["UiMin_1"], r["UiMax_0"], r["UiMax_1"]) != ("0", "0", "1", "1"):
            continue
        ui = _int(r["UiMapID"])
        if ui not in names:
            continue
        box = tuple(float(r[f"Region_{i}"]) for i in (0, 1, 3, 4))
        out.append((_int(r["MapID"]), names[ui], box[0], box[1], box[2], box[3], _int(r["AreaID"])))
    return out


def zone_at(zones: Iterable[ZoneBox], map_id: int, x: float, y: float) -> ZoneBox | None:
    """The smallest zone map on `map_id` whose box holds (x, y); None if none does."""
    around = [z for z in zones if z[0] == map_id and z[2] <= x <= z[4] and z[3] <= y <= z[5]]
    return min(around, key=lambda z: (z[4] - z[2]) * (z[5] - z[3])) if around else None


CITY_SIZE = 2000.0  # `spawn_zone`: a zone map's box shorter than this (yards) on both sides is a city's
INNER = 0.25  # `spawn_zone`: how far from its map's centre (a fraction of each side) a spot is well inside


def spawn_zone(zones: Iterable[ZoneBox], map_id: int, x: float, y: float) -> ZoneBox | None:
    """The zone (x, y) on `map_id` most likely stands in, from zone maps alone (their boxes overlap their
    neighbours): a city's map holding it (a city is drawn off its map's centre), else the smallest box
    holding it well inside, else the one it is nearest the centre of (a map is drawn around its zone).
    Continents (AreaID 0) never count; None if no zone map holds it. 69% agree with the zone vmangos files
    the quest givers' quests under (much of the rest a battleground's quests given outside it)."""

    def off(z: ZoneBox) -> tuple[float, float]:
        fx, fy = (x - z[2]) / (z[4] - z[2]) - 0.5, (y - z[3]) / (z[5] - z[3]) - 0.5
        return max(abs(fx), abs(fy)), fx * fx + fy * fy

    around = [z for z in zones if z[0] == map_id and z[6] and z[2] <= x <= z[4] and z[3] <= y <= z[5]]
    around.sort(key=lambda z: (z[4] - z[2]) * (z[5] - z[3]))
    if around and max(around[0][4] - around[0][2], around[0][5] - around[0][3]) < CITY_SIZE:
        return around[0]
    for z in around:
        if off(z)[0] <= INNER:
            return z
    return min(around, key=lambda z: off(z)[1]) if around else None


Rows = Iterable[dict[str, str]]


def _rand_prop_points(
    rows: Rows,
) -> dict[int, tuple[itemstats.Points5, itemstats.Points5, itemstats.Points5]]:
    """Item level -> (epic, superior, good) points per slot group. Forever's client keeps them in the
    `EpicF_n` float columns, TBC's in the integer `Epic_n` ones."""
    out = {}
    for r in rows:
        groups = []
        for name in ("Epic", "Superior", "Good"):
            groups.append(tuple(_int(r.get(f"{name}F_{i}") or r.get(f"{name}_{i}")) for i in range(5)))
        out[_int(r["ID"])] = (groups[0], groups[1], groups[2])
    return out


def _quality_rows(rows: Rows, key: str, prefix: str = "Quality") -> dict[int, itemstats.Quality7]:
    """`key` -> the row's `<prefix>_0..6` (a value per item quality)."""
    return {_int(r[key]): tuple(_float(r.get(f"{prefix}_{q}")) for q in range(7)) for r in rows}


def _armor_total(rows: Rows) -> dict[int, tuple[float, float, float, float]]:
    return {
        _int(r["ItemLevel"]): (
            _float(r["Cloth"]),
            _float(r["Leather"]),
            _float(r["Mail"]),
            _float(r["Plate"]),
        )
        for r in rows
    }


def _armor_location(rows: Rows) -> dict[int, tuple[float, float, float, float]]:
    return {
        _int(r["ID"]): (
            _float(r["Clothmodifier"]),
            _float(r["Leathermodifier"]),
            _float(r["Chainmodifier"]),
            _float(r["Platemodifier"]),
        )
        for r in rows
    }


def game_tables(paths: dict[str, Path]) -> itemstats.GameTables:
    """The stat, armor and damage lookups (every table optional: missing ones leave their numbers 0)."""
    damage = {
        "one_hand": "ItemDamageOneHand",
        "two_hand": "ItemDamageTwoHand",
        "ranged": "ItemDamageRanged",
        "wand": "ItemDamageWand",
    }
    return itemstats.GameTables(
        rand_prop_points=_rand_prop_points(_optional_rows(paths, "RandPropPoints")),
        armor_total=_armor_total(_optional_rows(paths, "ItemArmorTotal")),
        armor_quality=_quality_rows(_optional_rows(paths, "ItemArmorQuality"), "ID", "Qualitymod"),
        armor_location=_armor_location(_optional_rows(paths, "ArmorLocation")),
        shield=_quality_rows(_optional_rows(paths, "ItemArmorShield"), "ItemLevel"),
        damage={k: _quality_rows(_optional_rows(paths, t), "ItemLevel") for k, t in damage.items()},
    )


MAX_STATS = 10  # ItemSparse stat slots


def item_spec(r: dict[str, str], class_id: int, subclass_id: int) -> itemstats.ItemSpec:
    """One ItemSparse row (with its Item class) as the stats module reads it."""
    stats = [
        (_int(r.get(f"StatModifier_bonusStat_{i}"), -1), _int(r.get(f"StatPercentEditor_{i}")))
        for i in range(MAX_STATS)
    ]
    return itemstats.ItemSpec(
        class_id=class_id,
        subclass_id=subclass_id,
        quality=_int(r["OverallQualityID"]),
        item_level=_int(r["ItemLevel"]),
        inventory_type=_int(r["InventoryType"]),
        delay_ms=_int(r["ItemDelay"]),
        dmg_variance=_float(r.get("DmgVariance")),
        stats=tuple(s for s in stats if s[0] >= 0),
    )


ItemEffectRef = tuple[str, int, int]  # trigger, spell id, cooldown ms


def _effects_by_item(paths: dict[str, Path]) -> Iterator[tuple[int, dict[str, str]]]:
    """Every (item id, ItemEffect row). TBC's ItemEffect names its item (`ParentItemID`); Forever's links
    them through ItemXItemEffect."""
    by_id: dict[int, dict[str, str]] = {}
    for r in _optional_rows(paths, "ItemEffect"):
        parent = _int(r.get("ParentItemID"))
        if parent > 0:
            yield parent, r
        else:
            by_id[_int(r["ID"])] = r
    for r in _optional_rows(paths, "ItemXItemEffect"):
        linked = by_id.get(_int(r["ItemEffectID"]))
        if linked is not None:
            yield _int(r["ItemID"]), linked


def item_effects(paths: dict[str, Path]) -> dict[int, list[ItemEffectRef]]:
    """Each item's Use / Equip / Chance on hit effects in slot order."""
    out: dict[int, list[tuple[int, str, int, int]]] = {}
    for item, r in _effects_by_item(paths):
        trigger = spelltext.TRIGGERS.get(_int(r["TriggerType"]))
        if trigger is None:
            continue
        # potions and the like have only a category cooldown
        cooldown = _int(r.get("CoolDownMSec")) or _int(r.get("CategoryCoolDownMSec"))
        out.setdefault(item, []).append(
            (_int(r.get("LegacySlotIndex")), trigger, _int(r["SpellID"]), cooldown)
        )
    return {i: [(t, s, c) for _, t, s, c in sorted(refs)] for i, refs in out.items()}


Conversion = tuple[int, int, int, int, int]  # input item, input count, spell, output item, output count


def conversions(
    paths: dict[str, Path],
    outputs: dict[int, tuple[int, int]],
    reagents: dict[int, list[tuple[int, int]]],
    materials: set[int],
) -> list[Conversion]:
    """Enchanting materials an item's Use spell turns into others (3 Lesser Magic Essence -> 1 Greater, 1
    Greater -> 3 Lesser): a Use effect that consumes the item (negative charges) and casts a spell creating
    an item, the spell's reagents (if any) being more of the same item, input and output both disenchant
    results (`materials`), so openables and the like are left out. The input count is the item used plus
    the reagents."""
    out: dict[tuple[int, int], Conversion] = {}
    for item, r in _effects_by_item(paths):
        spell = _int(r["SpellID"])
        if _int(r["TriggerType"]) != TRIGGER_USE or _int(r.get("Charges")) >= 0 or spell not in outputs:
            continue
        out_item, out_count = outputs[spell]
        extra = reagents.get(spell, [])
        if item not in materials or out_item not in materials or any(i != item for i, _ in extra):
            continue
        out[item, spell] = (item, 1 + sum(c for _, c in extra), spell, out_item, out_count)
    return sorted(out.values(), key=lambda c: c[2])


def learn_skills(paths: dict[str, Path], skill_ranks: dict[int, int]) -> dict[int, int]:
    """Each spell recipe items teach -> the lowest skill rank one of them requires (`skill_ranks`: item
    id -> ItemSparse.RequiredSkillRank). Items requiring no skill are left out."""
    out: dict[int, int] = {}
    for item, r in _effects_by_item(paths):
        rank = skill_ranks.get(item, 0)
        if _int(r["TriggerType"]) == TRIGGER_LEARN and rank > 0:
            spell = _int(r["SpellID"])
            out[spell] = min(rank, out.get(spell, rank))
    return out


def learn_sources(
    paths: dict[str, Path], bonding: dict[int, int], vendor_sold: Collection[int] = ()
) -> dict[int, str]:
    """Each spell recipe items teach -> "recipe" if one of them can be traded or is one a vendor sells
    (`vendor_sold`: anybody can go and buy it, bound or not), else "bop": every one binds on pickup or is a
    quest item and has to be looted or earned (`bonding`: item id -> ItemSparse.Bonding; an item not in it
    does not exist in the game and teaches nothing). A spell not in here has no recipe item: trainers
    teach it."""
    out: dict[int, str] = {}
    for item, r in _effects_by_item(paths):
        if _int(r["TriggerType"]) == TRIGGER_LEARN and item in bonding:
            spell = _int(r["SpellID"])
            bound = bonding[item] in SOULBOUND and item not in vendor_sold
            out[spell] = "bop" if bound and out.get(spell, "bop") == "bop" else "recipe"
    return out


def recipe_items(paths: dict[str, Path], bonding: dict[int, int]) -> list[tuple[int, int]]:
    """(spell, item) for every item teaching a spell, as `learn_sources` reads them: items the game has
    (`bonding`) on learn."""
    out: set[tuple[int, int]] = set()
    for item, r in _effects_by_item(paths):
        if _int(r["TriggerType"]) == TRIGGER_LEARN and item in bonding:
            out.add((_int(r["SpellID"]), item))
    return sorted(out)


ITEM_SOURCE_KINDS = frozenset({"vendor", "drop", "object", "container", "world_drop", "quest", "more"})
SIDES = frozenset({"", "alliance", "horde"})


def item_sources(path: Path | None, game_version: str) -> list[dict[str, object]]:
    """`item_sources` rows from a version's `recipe_item_sources.csv` (`vmangos.recipe_item_sources`), in
    the file's order per item; nothing if there is no such file."""
    if not path or not path.exists():
        return []
    out: list[dict[str, object]] = []
    seq: dict[int, int] = {}
    for r in _rows(path):
        item, kind, side = _int(r["item_id"]), r["kind"], r["side"]
        if kind not in ITEM_SOURCE_KINDS or side not in SIDES:
            raise ValueError(f"{path.name}: bad kind {kind!r} or side {side!r} for item {item}")
        seq[item] = seq.get(item, -1) + 1
        out.append(
            {
                "game_version": game_version,
                "item_id": item,
                "seq": seq[item],
                "kind": kind,
                "name": r["name"],
                "zone": r["zone"],
                "side": side,
                "chance": _float(r["chance"]),
                "count": _int(r["count"]),
                "levels": r["levels"],
                "limited": r["limited"] == "1",
                "area": _int(r.get("area")),
                "map_x": _float(r.get("map_x")),
                "map_y": _float(r.get("map_y")),
            }
        )
    return out


def _effect_base(r: dict[str, str]) -> float:
    """An effect's value: `EffectBasePointsF`, or TBC's `EffectBasePoints` plus an average die roll."""
    as_float = _float(r.get("EffectBasePointsF"))
    if as_float:
        return as_float
    base, sides = _int(r.get("EffectBasePoints")), _int(r.get("EffectDieSides"))
    return base + (1 + sides) / 2 if sides > 0 else base


def spell_data(paths: dict[str, Path], spell_ids: Iterable[int]) -> spelltext.SpellData:
    """What the descriptions of `spell_ids` need, including the spells they inline or quote (to
    `spelltext.MAX_DEPTH`); the normal difficulty's rows win where a spell has several."""
    descriptions = {
        _int(r["ID"]): r["Description_lang"] for r in _optional_rows(paths, "Spell") if r["Description_lang"]
    }
    wanted = set(spell_ids)
    frontier = set(wanted)
    for _ in range(spelltext.MAX_DEPTH + 1):
        refs: set[int] = set()
        for sid in frontier:
            refs |= spelltext.referenced(descriptions.get(sid, ""))
        frontier = refs - wanted
        if not frontier:
            break
        wanted |= frontier

    radius = {_int(r["ID"]): _float(r["Radius"]) for r in _optional_rows(paths, "SpellRadius")}
    effects: dict[int, dict[int, spelltext.EffectValues]] = {}
    normal: set[tuple[int, int]] = set()
    for r in _rows(paths["SpellEffect"]):
        sid = _int(r["SpellID"])
        if sid not in wanted:
            continue
        idx, difficulty = _int(r.get("EffectIndex")), _int(r.get("DifficultyID"))
        if (sid, idx) in normal:
            continue
        if difficulty == 0:
            normal.add((sid, idx))
        effects.setdefault(sid, {})[idx] = spelltext.EffectValues(
            base=_effect_base(r),
            variance=_float(r.get("Variance")),
            period_ms=_int(r.get("EffectAuraPeriod")),
            misc=_int(r.get("EffectMiscValue_0")),
            radius=radius.get(_int(r.get("EffectRadiusIndex_0")), 0.0),
            chain=_int(r.get("EffectChainTargets")),
        )
    duration_ms = {_int(r["ID"]): _int(r["Duration"]) for r in _optional_rows(paths, "SpellDuration")}
    durations: dict[int, int] = {}
    for r in _rows(paths["SpellMisc"]):
        sid = _int(r["SpellID"])
        if sid in wanted and (sid not in durations or _int(r.get("DifficultyID")) == 0):
            durations[sid] = duration_ms.get(_int(r.get("DurationIndex")), 0)
    proc_chance: dict[int, int] = {}
    max_stacks: dict[int, int] = {}
    for r in _optional_rows(paths, "SpellAuraOptions"):
        sid = _int(r["SpellID"])
        if sid in wanted and (sid not in proc_chance or _int(r.get("DifficultyID")) == 0):
            proc_chance[sid] = _int(r["ProcChance"])
            max_stacks[sid] = _int(r["CumulativeAura"])
    blank = spelltext.EffectValues(0.0)
    return spelltext.SpellData(
        descriptions={s: descriptions[s] for s in wanted if s in descriptions},
        effects={s: tuple(e.get(i, blank) for i in range(max(e) + 1)) for s, e in effects.items()},
        durations=durations,
        proc_chance=proc_chance,
        max_stacks=max_stacks,
    )


def item_tooltips(
    paths: dict[str, Path], max_level: int = itemstats.LEVEL_60
) -> dict[int, itemstats.Computed]:
    """Every item's tooltip numbers and lines, by item id: the stats' lines, then its spell effects'
    (Use, Equip, Chance on hit)."""
    tables = game_tables(paths)
    classes = {_int(r["ID"]): (_int(r["ClassID"]), _int(r["SubclassID"])) for r in _rows(paths["Item"])}
    out = {}
    for r in _rows(paths["ItemSparse"]):
        iid = _int(r["ID"])
        cls, sub = classes.get(iid, (0, 0))
        out[iid] = itemstats.compute(item_spec(r, cls, sub), tables, max_level)
    effects = item_effects(paths)
    data = spell_data(paths, {spell for refs in effects.values() for _, spell, _ in refs})
    for iid, refs in effects.items():
        if iid not in out:
            continue
        rendered = (spelltext.render_effect(t, s, c, data, max_level) for t, s, c in refs)
        lines = tuple(e for e in rendered if e is not None)
        if lines:
            out[iid] = replace(out[iid], effects=out[iid].effects + lines)
    return out


NO_TOOLTIP = itemstats.Computed(0, 0, 0, 0.0, (), ())

ITEM_INSERT_COLUMNS = (
    "game_version",
    "id",
    "name",
    "quality",
    "item_level",
    "required_level",
    "class_id",
    "subclass_id",
    "sell_price",
    "buy_price",
    "bonding",
    "inventory_type",
    "item_delay",
    "container_slots",
    "subclass_name",
    "required_skill",
    "required_skill_rank",
    "description",
    "icon",
    "buy_count",
    "stack_size",
    "armor",
    "dmg_min",
    "dmg_max",
    "dps",
    "stats",
    "effects",
    "disenchantable",
)

NO_DISENCHANT = 0x8000  # ItemSparse Flags_0: ITEM_FLAG_NO_DISENCHANT


GAME_DATA_TABLES = (
    schema.recipe_reagents,
    schema.recipes,
    schema.items,
    schema.disenchant,
    schema.vendor_items,
    schema.recipe_items,
    schema.item_sources,
)


def _item_ids(path: Path | None) -> list[int]:
    """The `item_id` column of a data CSV; nothing if there is no such file."""
    return [_int(r["item_id"]) for r in _rows(path)] if path and path.exists() else []


def trainer_costs(path: Path | None) -> dict[int, tuple[int, int]]:
    """Spell -> (what a trainer asks to teach it, the skill they ask for), from a version's
    `trainer_costs.csv` (`vmangos.trainer_costs`; a file from before the skill column reads 0); nothing if
    there is no such file."""
    if not path or not path.exists():
        return {}
    return {_int(r["spell_id"]): (_int(r["cost"]), _int(r.get("req_skill"))) for r in _rows(path)}


def build_db(
    paths: dict[str, Path],
    conn: Connection,
    game_version: str,
    disenchant_csv: Path | None = None,
    vendor_csv: Path | None = None,
    max_level: int = itemstats.LEVEL_60,
    vendor_recipes_csv: Path | None = None,
    sources_csv: Path | None = None,
    trainer_costs_csv: Path | None = None,
) -> dict[str, int]:
    """Rebuild one version's items/recipes/recipe_reagents/disenchant/vendor_items/recipe_items/
    item_sources; prices, characters and other versions are left alone. `max_level` is the version's level
    cap (how ratings are shown). `vendor_recipes_csv` lists the recipe items vendors sell with limited
    stock too: with `vendor_csv`'s they count as normal recipes even when they bind on pickup
    (`learn_sources`). `sources_csv` says where recipe items come from (`item_sources`), `trainer_costs_csv`
    what trainers charge (`recipes.train_cost`, for the recipes trainers teach)."""
    for table in GAME_DATA_TABLES:
        conn.execute(delete(table).where(table.c.game_version == game_version))

    tooltips = item_tooltips(paths, max_level)
    skill_names = {_int(r["ID"]): r["DisplayName_lang"] for r in _rows(paths["SkillLine"])}
    subclass_names = {
        (_int(r["ClassID"]), _int(r["SubClassID"])): r["DisplayName_lang"]
        for r in _rows(paths["ItemSubClass"])
    }
    icons = _icon_names(paths["ManifestInterfaceData"])
    classes = {
        _int(r["ID"]): (_int(r["ClassID"]), _int(r["SubclassID"]), _int(r["IconFileDataID"]))
        for r in _rows(paths["Item"])
    }
    items = []
    skill_ranks: dict[int, int] = {}
    bonding: dict[int, int] = {}
    for r in _rows(paths["ItemSparse"]):
        iid = _int(r["ID"])
        cls, sub, icon = classes.get(iid, (0, 0, 0))
        skill_ranks[iid] = _int(r["RequiredSkillRank"])
        bonding[iid] = _int(r["Bonding"])
        tip = tooltips.get(iid, NO_TOOLTIP)
        items.append(
            (
                game_version,
                iid,
                r["Display_lang"],
                _int(r["OverallQualityID"]),
                _int(r["ItemLevel"]),
                _int(r["RequiredLevel"]),
                cls,
                sub,
                _int(r["SellPrice"]),
                _int(r["BuyPrice"]),
                _int(r["Bonding"]),
                _int(r["InventoryType"]),
                _int(r["ItemDelay"]),
                _int(r["ContainerSlots"]),
                subclass_names.get((cls, sub)),
                skill_names.get(_int(r["RequiredSkill"])),
                _int(r["RequiredSkillRank"]),
                r["Description_lang"] or None,
                icons.get(icon),
                max(1, _int(r.get("VendorStackCount"), 1)),
                max(1, _int(r.get("Stackable"), 1)),
                tip.armor,
                tip.dmg_min,
                tip.dmg_max,
                tip.dps,
                json.dumps(list(tip.stats)),
                json.dumps([asdict(e) for e in tip.effects]),
                not _int(r.get("Flags_0")) & NO_DISENCHANT,
            )
        )
    conn.execute(schema.items.insert(), [dict(zip(ITEM_INSERT_COLUMNS, i, strict=True)) for i in items])

    spell_names = {_int(r["ID"]): r["Name_lang"] for r in _rows(paths["SpellName"])}
    cast_ms = cast_times(paths["SpellMisc"], paths["SpellCastTimes"])
    cool_ms = cooldowns(_optional_rows(paths, "SpellCooldowns"))
    stations = spell_stations(paths["SpellCastingRequirements"], paths["SpellFocusObject"])
    learned_at = learn_skills(paths, skill_ranks)
    fees = trainer_costs(trainer_costs_csv)
    vendor_ids = _item_ids(vendor_csv)
    taught_by = learn_sources(
        paths, bonding, frozenset(vendor_ids) | frozenset(_item_ids(vendor_recipes_csv))
    )

    # spell -> (output item, count); first CreateItem effect wins
    outputs: dict[int, tuple[int, int]] = {}
    enchants: set[int] = set()  # spells enchanting an item
    for r in _rows(paths["SpellEffect"]):
        if _int(r["Effect"]) == EFFECT_ENCHANT_ITEM:
            enchants.add(_int(r["SpellID"]))
        if _int(r["Effect"]) == EFFECT_CREATE_ITEM and _int(r["EffectItemType"]) > 0:
            spell = _int(r["SpellID"])
            if spell not in outputs:
                outputs[spell] = (
                    _int(r["EffectItemType"]),
                    output_count(r),
                )

    reagents: dict[int, list[tuple[int, int]]] = {}
    for r in _rows(paths["SpellReagents"]):
        lst = [(_int(r[f"Reagent_{i}"]), _int(r[f"ReagentCount_{i}"])) for i in range(MAX_REAGENTS)]
        lst = [(i, c) for i, c in lst if i > 0 and c > 0]
        if lst:
            reagents[_int(r["SpellID"])] = lst

    de_rows = []
    if disenchant_csv and disenchant_csv.exists():
        de_rows = [
            {
                "game_version": game_version,
                "item_class": _int(r["item_class"]),
                "quality": _int(r["quality"]),
                "min_ilvl": _int(r["min_ilvl"]),
                "max_ilvl": _int(r["max_ilvl"]),
                "result_item_id": _int(r["result_item_id"]),
                "chance": float(r["chance"]),
                "min_count": _int(r["min_count"]),
                "max_count": _int(r["max_count"]),
            }
            for r in _rows(disenchant_csv)
        ]
    if de_rows:
        conn.execute(schema.disenchant.insert(), de_rows)
    de_results = {r["result_item_id"] for r in de_rows}

    known_items = {i[1] for i in items}
    recipes: dict[int, dict[str, object]] = {}
    recipe_reagents: dict[tuple[int, int], dict[str, object]] = {}
    for r in _rows(paths["SkillLineAbility"]):
        spell = _int(r["Spell"])
        line = _int(r["SkillLine"])
        if spell not in reagents or line not in skill_names:
            continue
        if spell in outputs:
            kind = "craft"
            out_item, out_count = outputs[spell]
            if out_item not in known_items:
                continue
        elif spell in enchants:
            # reagents go in and no item comes out (output item 0): cast only for the skill point
            kind, out_item, out_count = "enchant", 0, 1
        else:
            continue
        rid = _int(r["ID"])
        source = taught_by.get(spell, "trainer")
        fee, trainer_skill = fees.get(spell, (0, 0))
        # a recipe that comes with the profession (AcquireMethod 1) is known from skill 1, for nothing
        if source == "trainer" and _int(r.get("AcquireMethod")) == ACQUIRE_WITH_SKILL:
            fee, trainer_skill = 0, 1
        low, high = _int(r["TrivialSkillLineRankLow"]), _int(r["TrivialSkillLineRankHigh"])
        recipes[rid] = {  # a later row with the same id replaces an earlier one
            "game_version": game_version,
            "id": rid,
            "spell_id": spell,
            "name": spell_names.get(spell, f"Spell {spell}"),
            "kind": kind,
            "skill_line": line,
            "skill_name": skill_names[line],
            "min_skill": _int(r["MinSkillLineRank"]),
            "trivial_low": low,
            "trivial_high": high,
            "output_item_id": out_item,
            "output_count": out_count,
            "cast_time_ms": cast_ms.get(spell, 0),
            "station": stations.get(spell, ""),
            "learn_skill": learned_at.get(spell) or (trainer_skill if source == "trainer" else 0),
            "source": source,
            "train_cost": fee if source == "trainer" else 0,
            # no thresholds at all: the game shows it grey, so it gives no point (First Aid Kit)
            "num_skill_ups": 0 if not low and not high else _int(r.get("NumSkillUps"), 1),
            "cooldown_ms": cool_ms.get(spell, 0),
        }
        for k in [k for k in recipe_reagents if k[0] == rid]:
            del recipe_reagents[k]
        for slot, (i, c) in enumerate(reagents[spell]):
            recipe_reagents[rid, i] = {
                "game_version": game_version,
                "recipe_id": rid,
                "item_id": i,
                "count": c,
                "slot": slot,
            }
    materials = {i for i in known_items if i in de_results}
    for item, in_count, spell, out_item, out_count in conversions(paths, outputs, reagents, materials):
        rid = CONVERSION_ID_BASE + spell
        recipes[rid] = {
            "game_version": game_version,
            "id": rid,
            "spell_id": spell,
            "name": spell_names.get(spell, f"Spell {spell}"),
            "kind": "convert",
            "skill_line": 0,
            "skill_name": "",
            "min_skill": 0,
            "trivial_low": 0,
            "trivial_high": 0,
            "output_item_id": out_item,
            "output_count": out_count,
            "cast_time_ms": cast_ms.get(spell, 0),
            "station": "",
            "learn_skill": 0,
            "source": "trainer",
            "train_cost": 0,
            "num_skill_ups": 0,
            "cooldown_ms": cool_ms.get(spell, 0),
        }
        recipe_reagents[rid, item] = {
            "game_version": game_version,
            "recipe_id": rid,
            "item_id": item,
            "count": in_count,
            "slot": 0,
        }
    n_recipes = len(recipes)
    if recipes:
        conn.execute(schema.recipes.insert(), list(recipes.values()))
    if recipe_reagents:
        conn.execute(schema.recipe_reagents.insert(), list(recipe_reagents.values()))

    n_de = len(de_rows)

    taught = [
        {"game_version": game_version, "spell_id": s, "item_id": i} for s, i in recipe_items(paths, bonding)
    ]
    if taught:
        conn.execute(schema.recipe_items.insert(), taught)
    sources = item_sources(sources_csv, game_version)
    if sources:
        conn.execute(schema.item_sources.insert(), sources)

    n_vendor = 0
    if vendor_ids:
        rows = [{"game_version": game_version, "item_id": i} for i in dict.fromkeys(vendor_ids)]
        db.upsert(conn, schema.vendor_items, rows, ["game_version", "item_id"])
        n_vendor = len(vendor_ids)

    return {"items": len(items), "recipes": n_recipes, "disenchant_rows": n_de, "vendor_items": n_vendor}


def update(
    conn: Connection,
    game_version: str,
    build: str,
    cache_dir: Path,
    disenchant_csv: Path | None = None,
    vendor_csv: Path | None = None,
    vendor_recipes_csv: Path | None = None,
    sources_csv: Path | None = None,
    trainer_costs_csv: Path | None = None,
) -> dict[str, int]:
    """Download `build` (cached per build) and rebuild the version's game data from it, keeping prices."""
    max_level = versions.get(game_version).max_level
    stats = build_db(
        download_all(build, cache_dir),
        conn,
        game_version,
        disenchant_csv,
        vendor_csv,
        max_level,
        vendor_recipes_csv,
        sources_csv,
        trainer_costs_csv,
    )
    data_files = (disenchant_csv, vendor_csv, vendor_recipes_csv, sources_csv, trainer_costs_csv)
    db.set_build(conn, game_version, build, _fingerprint(data_files))
    return stats


def fingerprint(version: versions.GameVersion) -> str:
    """A hash of what a load of `version` makes of a build besides the build itself: the ingest code and
    the version's hand-maintained CSVs. When it differs from the loaded data's (`db.get_fingerprint`),
    `ingest --only-if-new` reloads the same build. Line endings are ignored (a Windows checkout's files)."""
    return _fingerprint(
        (
            version.disenchant_csv,
            version.vendor_csv,
            version.vendor_recipes_csv,
            version.sources_csv,
            version.trainer_costs_csv,
        )
    )


def _fingerprint(data_files: Iterable[Path | None]) -> str:
    h = hashlib.sha256()

    def add(content: bytes | None) -> None:
        if content is None:  # no file: unlike an empty one
            h.update(b"-")
            return
        content = content.replace(b"\r\n", b"\n")
        h.update(f"{len(content)}:".encode())
        h.update(content)

    for module in FINGERPRINTED_MODULES:
        add(module.read_bytes())
    for path in data_files:
        add(path.read_bytes() if path is not None and path.is_file() else None)
    return h.hexdigest()
