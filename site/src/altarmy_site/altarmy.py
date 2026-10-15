"""Read characters, professions and learned recipes from the Alt Army addon's SavedVariables.

The file is account-wide (WTF/Account/<acct>/SavedVariables/AltArmy_TBC.lua). Characters live in
`AltArmyTBC_Data.Characters[realm][key]`; each profession has `rank`, `maxRank` and
`Recipes[recipeID] = {color, primaryRecipeID?, resultItemID?, name?}`. WoW: Forever characters also have
`legacyTalents.spells[spellID] = rank` (their Legacy talents, addon data version 2). Every character has
`Reputations[factionID] = {s = standing, ...}`, of which the city factions' standings are read (they
discount vendor prices: `reputation`).

The key is the character's GUID since the addon's character data v3 (a name before that, and still for
entries of characters not logged in since), so the name is the entry's `name` field: the full name
("Frell Ofelements"; on Forever the addon joins `UnitName`'s first name and surname), else the key. Older
files can hold one character twice: entries with the same `guid`, or the same name, are one character, and
the most recently updated wins. A bare first name ("Frell", saved by addons before v3, possibly from several
characters) is not matched with a full one. Entries never scanned (no name, faction or class: the addon
made one while the name still read "Unknown") are skipped.

Recipe ids are craft spell ids (they match `recipes.spell_id`). On TBC clients one recipe can be stored
under several alias keys that all share a `primaryRecipeID`; Enchanting rows only carry `color`.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from typing import Literal

from .luasv import LuaTable, LuaValue, parse_assignments
from .reputation import city_standings


@dataclass(frozen=True)
class Profession:
    name: str
    rank: int
    max_rank: int
    recipe_ids: frozenset[int]


Place = Literal["bags", "bank"]

# container ids by where they are (the addon's `DS._BuildBagRoles`; keyrings are left out): WoW: Forever's
# retail ids, and the Classic ones
RETAIL_BAGS = (frozenset(range(0, 6)), frozenset(range(6, 15)))
CLASSIC_BAGS = (frozenset(range(0, 5)), frozenset({-1, *range(5, 12)}))


@dataclass(frozen=True, order=True)
class Holding:
    """Units of an item a character holds in one place, soulbound or not (the addon's containers v4 say
    which copies are; older data reads every copy as unbound)."""

    item_id: int
    count: int
    place: Place
    bound: bool = False


@dataclass(frozen=True)
class Character:
    realm: str
    name: str
    faction: str  # Horde | Alliance ("" if never scanned)
    class_file: str  # e.g. PALADIN
    level: int
    professions: tuple[Profession, ...]  # sorted by name
    # Legacy talents (WoW: Forever) as (spell id, rank), ranks above 0, sorted by spell id; see `talents`
    talents: tuple[tuple[int, int], ...] = ()
    guid: str = ""  # UnitGUID("player"); "" for characters the addon saved before it stored GUIDs
    # standings with the city factions as (faction id, standing 1 Hated .. 8 Exalted), sorted by faction id;
    # a faction not listed is Neutral, or was never seen (see `reputation`)
    reputations: tuple[tuple[int, int], ...] = ()
    # what they hold in their bags and bank, by item, place and bound, sorted (see `Holding`), and when each
    # was last scanned (the game server's Unix time; None when the addon didn't say)
    holdings: tuple[Holding, ...] = ()
    bags_at: int | None = None
    bank_at: int | None = None

    @property
    def known_recipes(self) -> frozenset[int]:
        return frozenset().union(*(p.recipe_ids for p in self.professions))


@dataclass(frozen=True)
class Group:
    """The characters of one realm and faction: they share an auction house and can mail each other."""

    realm: str
    faction: str
    characters: tuple[Character, ...]


def groups(chars: Iterable[Character]) -> list[Group]:
    """Realm/faction groups sorted by realm then faction. Characters without a faction are left out."""
    by_key: dict[tuple[str, str], list[Character]] = {}
    for c in chars:
        if c.faction:
            by_key.setdefault((c.realm, c.faction), []).append(c)
    return [Group(realm, faction, tuple(cs)) for (realm, faction), cs in sorted(by_key.items())]


def crafters(chars: Iterable[Character]) -> dict[int, list[str]]:
    """Recipe id -> names of the characters who know it."""
    out: dict[int, list[str]] = {}
    for c in chars:
        for rid in sorted(c.known_recipes):
            out.setdefault(rid, []).append(c.name)
    return out


def parse_characters(data: bytes, retail_bags: bool = True) -> list[Character]:
    """All characters in the file, sorted by realm then name; their holdings read with the container ids of
    a retail client (`retail_bags`: WoW: Forever's) or a Classic one."""
    root = parse_assignments(data).get("AltArmyTBC_Data")
    if not isinstance(root, dict):
        raise ValueError("no AltArmyTBC_Data in file (is this Alt Army's AltArmy_TBC.lua?)")
    chars: list[Character] = []
    for realm, by_key in _table(root.get("Characters")).items():
        entries = {
            str(key): c
            for key, char in _table(by_key).items()
            if (c := _table(char)).get("name") or c.get("faction") or c.get("classFile")
        }
        for key in _one_per_character(entries):
            c = entries[key]
            chars.append(
                Character(
                    realm=str(realm),
                    name=_name(key, c),
                    faction=_str(c.get("faction")),
                    class_file=_str(c.get("classFile")),
                    level=_int(c.get("level")),
                    professions=tuple(
                        sorted(
                            (_profession(str(n), _table(p)) for n, p in _table(c.get("Professions")).items()),
                            key=lambda p: p.name,
                        )
                    ),
                    talents=_talents(_table(c.get("legacyTalents"))),
                    guid=_str(c.get("guid")),
                    reputations=_reputations(_table(c.get("Reputations"))),
                    holdings=_holdings(
                        _table(c.get("Containers")), RETAIL_BAGS if retail_bags else CLASSIC_BAGS
                    ),
                    bags_at=_time(c.get("bagsScannedAt")),
                    bank_at=_time(c.get("bankScannedAt")),
                )
            )
    return sorted(chars, key=lambda c: (c.realm, c.name))


def _name(key: str, char: LuaTable) -> str:
    """The character's name: its `name` field, else (entries saved before the addon stored one) its key."""
    return _str(char.get("name")) or key


def _one_per_character(entries: dict[str, LuaTable]) -> list[str]:
    """The keys of one realm's entries, less those that are an older copy of another (see the module doc)."""

    def same(a: str, b: str) -> bool:
        ga, gb = _str(entries[a].get("guid")), _str(entries[b].get("guid"))
        return (ga != "" and ga == gb) or _name(a, entries[a]) == _name(b, entries[b])

    def newer(a: str, b: str) -> bool:
        return (_int(entries[a].get("lastUpdate")), a) > (_int(entries[b].get("lastUpdate")), b)

    return [a for a in entries if not any(b != a and same(a, b) and newer(b, a) for b in entries)]


def _talents(legacy: LuaTable) -> tuple[tuple[int, int], ...]:
    """`legacyTalents.spells` (spell id -> rank). Data version 1 has no `spells`: it was read from the class
    talent config, so it gives none."""
    got = {}
    for spell_id, rank in _table(legacy.get("spells")).items():
        if isinstance(spell_id, int) and not isinstance(spell_id, bool) and _int(rank) > 0:
            got[spell_id] = _int(rank)
    return tuple(sorted(got.items()))


def _reputations(saved: LuaTable) -> tuple[tuple[int, int], ...]:
    """`Reputations[factionID] = {s = standing, ...}` (the addon's reputation data v2; v1 rows are bare
    numbers and give nothing), kept for the city factions only."""
    return city_standings(
        (faction, _int(_table(row).get("s")))
        for faction, row in saved.items()
        if isinstance(faction, int) and not isinstance(faction, bool)
    )


def _holdings(containers: LuaTable, ids: tuple[frozenset[int], frozenset[int]]) -> tuple[Holding, ...]:
    """`Containers[bagID].items[slot] = {itemID, count, bound}` summed per item, place and bound."""
    got: dict[tuple[int, Place, bool], int] = {}
    for bag_id, bag in containers.items():
        place: Place | None = "bags" if bag_id in ids[0] else "bank" if bag_id in ids[1] else None
        if place is None or isinstance(bag_id, bool):
            continue
        for slot in _table(_table(bag).get("items")).values():
            row = _table(slot)
            item, count = _int(row.get("itemID")), _int(row.get("count")) or 1
            if item > 0:
                key = (item, place, row.get("bound") is True)
                got[key] = got.get(key, 0) + count
    return tuple(sorted(Holding(i, n, p, b) for (i, p, b), n in got.items()))


def _time(v: LuaValue) -> int | None:
    return _int(v) or None


def _profession(name: str, prof: LuaTable) -> Profession:
    ids = set()
    for key, row in _table(prof.get("Recipes")).items():
        primary = _table(row).get("primaryRecipeID")
        rid = primary if isinstance(primary, int) else key
        if isinstance(rid, int) and not isinstance(rid, bool):
            ids.add(rid)
    return Profession(name, _int(prof.get("rank")), _int(prof.get("maxRank")), frozenset(ids))


def _table(v: LuaValue) -> LuaTable:
    return v if isinstance(v, dict) else {}


def _str(v: LuaValue) -> str:
    return v if isinstance(v, str) else ""


def _int(v: LuaValue) -> int:
    return int(v) if isinstance(v, int | float) and not isinstance(v, bool) else 0
