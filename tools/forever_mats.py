#!/usr/bin/env python3
"""Which crafting materials should WoW: Forever make more valuable than Classic did, and which of them are
listed near what a vendor pays right now?

Standard library only. Run it from anywhere, with any Python 3.11+ (the site's venv will do):

    python tools/forever_mats.py                    # live vendor check of your selected realm (alt-army.com)
    python tools/forever_mats.py --prices local --realm "Americas Normal" --faction Horde
    python tools/forever_mats.py --prices none      # the demand ranking alone, no prices
    python tools/forever_mats.py --explain "Jade"   # every recipe behind one material's score

How it works
------------
1. Recipes. Forever's come from the site's development database (site/data/altarmy.sqlite, loaded from the
   pinned client build by `altarmy-site ingest`); vanilla 1.12's from the pinned vmangos world database
   (.cache/emulators/vmangos/<release>/mangos.sqlite, spell_template + skill_line_ability, build <= 5875).
   Recipes are matched by spell id: Forever kept vanilla's ids, so a Forever recipe whose id vanilla lacks
   is new (ids over 1,000,000 are Forever's own; lower ones are Season of Discovery or holiday leftovers),
   and a vanilla recipe Forever lacks was removed (the Alchemy healing potions, which came back as First
   Aid recipes under new ids: removed and new net out by themselves).

2. Each recipe gets a weight U = end-use demand + skill-up demand, computed the same way on both sides:
   - end use: how widely it is learned (trainer 1, tradable recipe 0.7, bind-on-pickup recipe 0.35) times
     what its output is for (consumables and enchants 1 x level factor, gear by quality x level, bags 0.5,
     intermediates 0: they are valued through what consumes them), divided by the units a craft makes;
   - skill-up: the crafts an average leveller is expected to make of it on the way up (at each skill point
     the recipes that can give it share the point by accessibility x (chance / cost)^2), scaled to 0..1;
   - Forever only: a Craftsman's Writ that asks for the output adds a little.

3. A material's demand on each side is the sum over recipes of U x the units a craft takes, plus demand
   pushed down through processing (smelting, bolts of cloth, cured hides and Forever's new intermediates:
   dyes, Sulfuric Acid, Sandpaper, Heavy Thorium and Azerothium Bars, Legionite), plus a little for each
   Waylaid Crate bundle it can fill (shared between the crate's options). The gain is Forever's demand less
   vanilla's (new recipes, changed reagents and removed recipes all net in), and the lift that gain over
   vanilla's demand: a material vanilla barely used that new recipes want lifts the most.

4. Prices: the vendor check (what the auction house lists vs what a vendor pays). An item counts as cheap
   when units are listed at or under --max-ratio x the vendor price; for items a vendor pays nothing or a
   copper for (dusts, essences, shards), when listed at or under --below-median x their own 7-day median.

Everything is a heuristic over game data: it says which materials gained uses, not what players will pay.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # the monorepo
SITE = "https://alt-army.com"
GAME_VERSION = "forever"
MAX_SKILL = 300  # Forever's highest profession skill (site versions.py)
VANILLA_BUILD = 5875  # 1.12.1: vmangos keeps one row per build; the newest at or under this is vanilla's

# the professions whose recipes count (skill line ids, the same in vanilla and Forever)
PROFESSIONS = {
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    185: "Cooking",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
    129: "First Aid",
    40: "Poisons",
    356: "Fishing",
    182: "Herbalism",
    393: "Skinning",
}
FOREVER_IDS = 1_000_000  # a new recipe's spell id at or over this is Forever's own; under it SoD/holiday
SLOW_COOLDOWN_MS = 3_600_000  # an hour or more between casts: transmutes, Mooncloth (never a skill path)
ACCESS = {"trainer": 1.0, "recipe": 0.7, "bop": 0.35}
QUALITY_VALUE = {0: 0.05, 1: 0.1, 2: 0.3, 3: 0.6, 4: 1.0, 5: 1.0}
CONSUMABLE_CLASSES = {0, 6}  # consumables, projectiles
GEAR_CLASSES = {2, 4}  # weapons, armour
CONTAINER_CLASS = 1
TRADE_GOODS = 7
QUALITY_NAMES = {0: "poor", 1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary"}
CRATE = "Waylaid Crate: "
WRIT = "Craftsman's Writ: "
BUNDLE_LINE = re.compile(r"^- (\d+) (.+?)(?:\|r)?\s*$")
PROPAGATE_DEPTH = 5
# slow-cooldown transmutes that are how their (vanilla) product is made: their demand passes down too. The
# elemental transmutes are left out: elementals are farmed, and they would pass demand round in circles.
TRANSMUTED = ("Arcanite Bar", "Mooncloth")


# --- the data ----------------------------------------------------------------------------------------
@dataclass
class Item:
    id: int
    name: str
    quality: int
    item_level: int
    required_level: int
    class_id: int
    subclass_name: str
    sell_price: int  # what a vendor pays for one
    buy_price: int  # what a vendor would charge for buy_count (only means something if one sells it)
    buy_count: int
    bonding: int  # 1 bind on pickup, 4 quest item
    use_text: str
    stack_size: int


@dataclass
class Recipe:
    spell_id: int
    name: str
    skill_line: int
    kind: str  # craft | enchant
    source: str  # trainer | recipe | bop (Forever's; vanilla's taken from Forever where shared)
    learn: int  # skill it is learned at (0 unknown)
    yellow: int
    grey: int
    output: int  # item id, 0 for an enchant
    output_count: float
    skill_ups: bool
    slow: bool
    reagents: dict[int, int]


@dataclass
class Contribution:
    label: str  # what put it there: "new", "changed", "removed", "same", "crate", "via <item>"
    recipe: str
    amount: float  # Forever's demand less vanilla's


@dataclass
class Material:
    item_id: int
    forever: float = 0.0
    vanilla: float = 0.0
    new: float = 0.0  # from recipes vanilla didn't have
    changed: float = 0.0  # from recipes both have (reagents, output counts or weights that moved)
    removed: float = 0.0  # from vanilla recipes Forever dropped (negative)
    propagated: float = 0.0  # through processing (its products' demand), net
    crates: float = 0.0  # Waylaid Crate bundles (Forever only)
    new_uses: int = 0  # new recipes taking it directly
    vanilla_uses: int = 0  # vanilla recipes taking it directly
    contributions: list[Contribution] = field(default_factory=list)

    @property
    def gain(self) -> float:
        return self.forever - self.vanilla

    def lift(self, k: float) -> float:
        return self.gain / (self.vanilla + k)

    def score(self, k: float) -> float:
        """The gain, damped where it is small next to what vanilla already asked for."""
        lift = self.lift(k)
        return self.gain * lift / (1 + lift) if lift > 0 else self.gain


def pins() -> dict[str, dict[str, str]]:
    return json.loads((ROOT / "site" / "data" / "game-data.json").read_text(encoding="utf-8"))


def default_vmangos() -> Path:
    pin = pins()[GAME_VERSION]
    return ROOT / ".cache" / "emulators" / pin["emulator"] / pin["release"] / "mangos.sqlite"


def use_text(effects: str | None) -> str:
    try:
        parsed = json.loads(effects or "[]")
    except ValueError:
        return ""
    for effect in parsed if isinstance(parsed, list) else []:
        if isinstance(effect, dict) and effect.get("trigger") == "Use":
            return str(effect.get("text") or "")
    return ""


def load_forever(db: Path) -> tuple[dict[int, Item], dict[int, Recipe], str]:
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    build_row = conn.execute("SELECT build FROM game_versions WHERE id = ?", (GAME_VERSION,)).fetchone()
    build = build_row["build"] if build_row else "?"
    items = {
        r["id"]: Item(
            r["id"],
            r["name"],
            r["quality"] or 0,
            r["item_level"] or 0,
            r["required_level"] or 0,
            r["class_id"] or 0,
            r["subclass_name"] or "",
            r["sell_price"] or 0,
            r["buy_price"] or 0,
            r["buy_count"] or 1,
            r["bonding"] or 0,
            use_text(r["effects"]),
            r["stack_size"] or 1,
        )
        for r in conn.execute("SELECT * FROM items WHERE game_version = ?", (GAME_VERSION,))
    }
    reagents: dict[int, dict[int, int]] = defaultdict(dict)
    for r in conn.execute(
        "SELECT recipe_id, item_id, count FROM recipe_reagents WHERE game_version = ?", (GAME_VERSION,)
    ):
        reagents[r["recipe_id"]][r["item_id"]] = reagents[r["recipe_id"]].get(r["item_id"], 0) + r["count"]
    recipes: dict[int, Recipe] = {}
    for r in conn.execute("SELECT * FROM recipes WHERE game_version = ?", (GAME_VERSION,)):
        if r["skill_line"] not in PROFESSIONS or r["kind"] not in ("craft", "enchant"):
            continue
        got = reagents.get(r["id"], {})
        if not got:
            continue
        recipes[r["spell_id"]] = Recipe(
            spell_id=r["spell_id"],
            name=r["name"],
            skill_line=r["skill_line"],
            kind=r["kind"],
            source=r["source"] or "trainer",
            learn=r["learn_skill"] or 0,
            yellow=r["trivial_low"] or 0,
            grey=r["trivial_high"] or 0,
            output=r["output_item_id"] or 0,
            output_count=max(1.0, float(r["output_count"] or 1)),
            skill_ups=(r["num_skill_ups"] if r["num_skill_ups"] is not None else 1) > 0,
            slow=(r["cooldown_ms"] or 0) >= SLOW_COOLDOWN_MS,
            reagents=got,
        )
    conn.close()
    return items, recipes, build


def newest_rows(conn: sqlite3.Connection, query: str, key: str) -> dict[int, sqlite3.Row]:
    """One row per `key`: the newest build at or under vanilla's."""
    out: dict[int, sqlite3.Row] = {}
    for r in conn.execute(query, (VANILLA_BUILD,)):
        out[r[key]] = r  # ordered by build: the last one wins
    return out


def load_vanilla(path: Path, forever: dict[int, Recipe]) -> tuple[dict[int, Recipe], set[int]]:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    skills = newest_rows(
        conn,
        "SELECT spell_id, skill_id, min_value, max_value, build FROM skill_line_ability "
        "WHERE build <= ? ORDER BY build",
        "spell_id",
    )
    skills = {s: r for s, r in skills.items() if r["skill_id"] in PROFESSIONS}
    spells = newest_rows(
        conn, "SELECT * FROM spell_template WHERE build <= ? ORDER BY build", "entry"
    )
    vanilla_items = {r[0] for r in conn.execute("SELECT DISTINCT entry FROM item_template")}
    # what teaches each spell: a recipe item casts a learning spell (effect 36) that teaches it
    learned_by: dict[int, int] = {}  # learning spell -> the spell it teaches
    for s in spells.values():
        for n in (1, 2, 3):
            if s[f"effect{n}"] == 36 and s[f"effectTriggerSpell{n}"]:
                learned_by[s["entry"]] = s[f"effectTriggerSpell{n}"]
    taught: dict[int, list[int]] = defaultdict(list)  # spell -> the bonding of each item teaching it
    for r in conn.execute(
        "SELECT entry, bonding, spellid_1, spellid_2, spellid_3, spellid_4, spellid_5 FROM item_template "
        "WHERE class = 9"
    ):
        for n in range(1, 6):
            spell = learned_by.get(r[f"spellid_{n}"] or 0)
            if spell:
                taught[spell].append(r["bonding"] or 0)
    conn.close()

    def vanilla_source(spell_id: int) -> str:
        bondings = taught.get(spell_id)
        if not bondings:
            return "trainer"
        return "bop" if all(b in (1, 4) for b in bondings) else "recipe"

    recipes: dict[int, Recipe] = {}
    for spell_id, sk in skills.items():
        s = spells.get(spell_id)
        if s is None:
            continue
        reagents: dict[int, int] = {}
        for n in range(1, 9):
            item, count = s[f"reagent{n}"], s[f"reagentCount{n}"]
            if item and count and item > 0 and count > 0:
                reagents[item] = reagents.get(item, 0) + count
        if not reagents:
            continue
        output, count, kind = 0, 1.0, ""
        for n in (1, 2, 3):
            if s[f"effect{n}"] == 24 and s[f"effectItemType{n}"]:
                # vanilla makes basePoints + a roll of baseDice..dieSides: count the roll's average
                low = max(1, s[f"effectBaseDice{n}"] or 0)
                high = max(low, s[f"effectDieSides{n}"] or 0)
                output, kind = s[f"effectItemType{n}"], "craft"
                count = max(1.0, s[f"effectBasePoints{n}"] + (low + high) / 2.0)
                break
            if s[f"effect{n}"] == 53:
                kind = "enchant"
        if not kind:
            continue
        shared = forever.get(spell_id)
        yellow, grey = sk["min_value"] or 0, sk["max_value"] or 0
        if shared is not None and shared.learn:  # keep Forever's gap between learning and yellow
            learn = max(1, yellow - max(0, shared.yellow - shared.learn))
        else:
            learn = 0
        recipes[spell_id] = Recipe(
            spell_id=spell_id,
            name=s["name"],
            skill_line=sk["skill_id"],
            kind=kind,
            source=shared.source if shared else vanilla_source(spell_id),
            learn=learn,
            yellow=yellow,
            grey=grey,
            output=output,
            output_count=count,
            skill_ups=grey > 0,
            slow=shared.slow if shared else False,
            reagents=reagents,
        )
    return recipes, vanilla_items


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def crate_bundles(items: dict[int, Item], used: set[int]) -> list[tuple[str, list[tuple[int, int]]]]:
    """Each Waylaid Crate and the bundles that fill it: (item, count), one of them per crate. A name two
    tradable items share (Dark Iron Ore) goes to the one a recipe uses, else the highest id."""
    tradable: dict[str, list[int]] = defaultdict(list)
    for it in items.values():
        if it.bonding == 0:
            tradable[it.name].append(it.id)
    crates = []
    for it in items.values():
        if not it.name.startswith(CRATE):
            continue
        options = []
        for line in it.use_text.replace("|cnIQ1:", "\n").splitlines():
            m = BUNDLE_LINE.match(line.strip())
            ids = tradable.get(m.group(2), []) if m else []
            if m and ids:
                pick = max(ids, key=lambda i: (i in used, i))
                options.append((pick, int(m.group(1))))
        if options:
            crates.append((it.name, options))
    return crates


def writ_targets(items: dict[int, Item], recipes: dict[int, Recipe]) -> set[int]:
    def normal(name: str) -> str:
        return re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()

    made: dict[str, set[int]] = defaultdict(set)
    for r in recipes.values():
        if r.output in items:
            made[normal(items[r.output].name)].add(r.output)
    out: set[int] = set()
    for it in items.values():
        if it.name.startswith(WRIT):
            out |= made.get(normal(it.name[len(WRIT) :]), set())
    return out


# --- recipe weights ----------------------------------------------------------------------------------
@dataclass
class Weights:
    skill: float = 0.5  # the skill-up term at its full (an average leveller crafting it >= skill_norm times)
    skill_norm: float = 30.0
    min_chance: float = 0.1  # a recipe is no option for a point it gives at under this chance
    crate: float = 0.01  # per unit of a crate bundle, shared between the crate's options
    writ: float = 0.05  # a Craftsman's Writ asking for the output
    sod: float = 0.5  # a new recipe under Forever's own ids (Season of Discovery, holiday): may not be live
    lift_k: float = 1.0


def end_use(r: Recipe, items: dict[int, Item]) -> tuple[str, float]:
    """(what the output is for, how much demand that makes before accessibility)."""
    if r.kind == "enchant":
        level = min(1.0, 0.3 + 0.7 * r.yellow / MAX_SKILL)
        return "enchant", 1.0 * level
    out = items.get(r.output)
    if out is None:
        return "unknown", 0.2
    req = out.required_level or max(0, out.item_level - 5)
    level = min(1.0, max(0.0, req / 60))
    if out.class_id in CONSUMABLE_CLASSES or (out.class_id == TRADE_GOODS and out.use_text):
        return "consumable", 0.3 + 0.7 * level
    if out.class_id in GEAR_CLASSES:
        return "gear", QUALITY_VALUE.get(out.quality, 0.3) * max(0.1, min(1.0, (req - 10) / 50)) ** 1.5
    if out.class_id == CONTAINER_CLASS:
        return "bag", 0.5
    if out.class_id in (TRADE_GOODS, 5):  # reagents: valued through what takes them
        return "intermediate", 0.0
    return "other", 0.2


def start_skill(r: Recipe) -> int:
    if r.learn:
        return min(r.learn, r.yellow) if r.yellow else r.learn
    return max(1, r.yellow - 25)  # unknown (new trainer recipes): assume it is orange a while before yellow


def chance(r: Recipe, skill: int) -> float:
    if skill < r.yellow:
        return 1.0
    if skill >= r.grey or r.grey <= r.yellow:
        return 0.0
    return (r.grey - skill) / (r.grey - r.yellow)


def skill_crafts(
    recipes: dict[int, Recipe], unit_price: dict[int, float], w: Weights
) -> dict[int, float]:
    """The crafts an average leveller makes of each recipe on the way to the cap: at every skill point the
    recipes that can give it share the point by accessibility x (chance / cost)^2, and a share s of a point
    at chance p is s / p crafts."""
    by_line: dict[int, list[Recipe]] = defaultdict(list)
    cost: dict[int, float] = {}
    for r in recipes.values():
        if not r.skill_ups or r.slow or r.grey <= 0:
            continue
        by_line[r.skill_line].append(r)
        cost[r.spell_id] = max(1.0, sum(n * unit_price.get(i, 1.0) for i, n in r.reagents.items()))
    crafts: dict[int, float] = defaultdict(float)
    for line in by_line.values():
        for skill in range(1, MAX_SKILL):
            options = []
            for r in line:
                if start_skill(r) <= skill:
                    p = chance(r, skill)
                    if p >= w.min_chance:
                        options.append((r, p, ACCESS.get(r.source, 0.5) * (p / cost[r.spell_id]) ** 2))
            total = sum(x for _, _, x in options)
            if total <= 0:
                continue
            for r, p, x in options:
                crafts[r.spell_id] += x / total / p
    return crafts


def recipe_weight(
    r: Recipe, items: dict[int, Item], crafts: dict[int, float], writs: set[int], w: Weights, new_sod: bool
) -> tuple[float, float, str]:
    """(demand per craft from end use, from skilling up, what it's for)."""
    use, value = end_use(r, items)
    access = ACCESS.get(r.source, 0.5)
    end = access * value
    if r.output in writs:
        end += access * w.writ
    end /= r.output_count  # end use wants items; a craft making more of them needs fewer crafts
    skill = w.skill * min(1.0, crafts.get(r.spell_id, 0.0) / w.skill_norm)
    if new_sod:
        end, skill = end * w.sod, skill * w.sod
    return end, skill, use


# --- material demand ---------------------------------------------------------------------------------
def processing_whitelist(
    data_dir: Path, recipes: dict[int, Recipe], items: dict[int, Item], vanilla_items: set[int]
) -> dict[int, Recipe]:
    """{item: the recipe its demand is pushed down through}: smelting, bolts of cloth, cured hides (never
    leather made from lesser leather: that runs back down to scraps) and Forever's new trade goods made
    from other trade goods (the dyes, Sulfuric Acid, Sandpaper, Heavy Thorium and Azerothium Bars,
    Legionite, Engineering's new parts), and the transmutes that make Arcanite and Mooncloth."""
    allowed: set[int] = set()
    for row in read_csv(data_dir / "processing.csv"):
        if row["group"] in ("smelt", "cloth") or (row["group"] == "leather" and row["note"].startswith("Cured")):
            allowed.add(int(row["spell_id"]))
    used = {i for r in recipes.values() for i in r.reagents}
    out: dict[int, Recipe] = {}
    for r in sorted(recipes.values(), key=lambda r: (r.source != "trainer", r.spell_id)):
        out_item = items.get(r.output)
        new_good = (
            out_item is not None
            and r.output not in vanilla_items
            and out_item.class_id == TRADE_GOODS
            and not out_item.use_text
            and r.output in used
            and all(i in items and items[i].class_id in (TRADE_GOODS, 5) for i in r.reagents)
        )
        transmuted = out_item is not None and out_item.name in TRANSMUTED
        if (r.spell_id in allowed or new_good or transmuted) and r.output and r.output not in out:
            out[r.output] = r
    return out


def demand(
    recipes: dict[int, Recipe],
    weights: dict[int, tuple[float, float, str]],
) -> dict[int, dict[int, float]]:
    """{item: {spell: demand}} taken directly by each recipe."""
    out: dict[int, dict[int, float]] = defaultdict(dict)
    for r in recipes.values():
        end, skill, _ = weights[r.spell_id]
        per_craft = end + skill
        if per_craft <= 0:
            continue
        for item, n in r.reagents.items():
            out[item][r.spell_id] = out[item].get(r.spell_id, 0.0) + per_craft * n
    return out


def push_down(
    direct: dict[int, float], producers: dict[int, Recipe]
) -> dict[int, dict[int, float]]:
    """{item: {through item: demand}}: what processing passes down from its products' demand."""
    out: dict[int, dict[int, float]] = defaultdict(lambda: defaultdict(float))
    frontier = {i: d for i, d in direct.items() if d}
    for _ in range(PROPAGATE_DEPTH):
        nxt: dict[int, float] = defaultdict(float)
        for item, d in frontier.items():
            p = producers.get(item)
            if p is None:
                continue
            for j, n in p.reagents.items():
                if j == item:
                    continue
                share = d * n / p.output_count
                out[j][item] += share
                nxt[j] += share
        if not nxt:
            break
        frontier = nxt
    return out


# --- prices ------------------------------------------------------------------------------------------
@dataclass
class Price:
    item_id: int
    name: str
    sell_price: int
    ah_price: int  # cheapest listing, per unit
    quantity: int  # units listed
    seen_at: str
    ladder: list[Level] | None = None  # cheapest first; None unknown
    market_price: int | None = None  # the price 15% into the units listed
    median_7d: int | None = None
    sale_price: int | None = None  # what it was seen selling for this week


@dataclass(frozen=True)
class Level:
    price: int  # per unit
    units: int
    tail: bool = False  # pools every level past the addon's 12, at the cheapest of their prices
    counted: bool = True  # False: a stray cheap listing new in the newest scan (the site doesn't count on it)


@dataclass
class PriceBook:
    realm: str
    faction: str
    rows: dict[int, Price]
    details: callable | None = None  # fetches an item's ladder and medians (live), filling the Price


STRAY = 0.5  # the site's prices.STRAY: a level new in the newest scan under this x the median is a stray


def decode_ladder(text: str | None, median: int | None) -> list[Level]:
    """price_current.ladder (`<price>*<units>*<listings>*<age>`, the tail marked `~`), with the levels the
    site wouldn't count on (new in the newest scan and under STRAY x the 7-day median) marked."""
    out = []
    for part in (text or "").split(","):
        bits = part.lstrip("~").split("*")
        if len(bits) >= 2 and bits[0].isdigit() and bits[1].isdigit():
            price, age = int(bits[0]), int(bits[3]) if len(bits) >= 4 and bits[3].isdigit() else 1
            stray = bool(median) and age == 0 and price < STRAY * median
            out.append(Level(price, int(bits[1]), part.startswith("~"), not stray))
    return sorted(out, key=lambda lv: (lv.price, lv.tail))


def local_prices(db: Path, realm: str, faction: str) -> PriceBook:
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    house = conn.execute(
        "SELECT id FROM auction_houses WHERE game_version = ? AND lower(realm) = lower(?) "
        "AND lower(faction) = lower(?)",
        (GAME_VERSION, realm, faction),
    ).fetchone()
    if house is None:
        houses = conn.execute(
            "SELECT h.realm, h.faction, count(pc.item_id) n FROM auction_houses h "
            "LEFT JOIN price_current pc ON pc.auction_house_id = h.id WHERE h.game_version = ? "
            "GROUP BY h.id HAVING n > 0",
            (GAME_VERSION,),
        ).fetchall()
        sys.exit(
            f"no auction house {realm!r} {faction!r} in {db}; with prices: "
            + ", ".join(f"{h['realm']} {h['faction']} ({h['n']})" for h in houses)
        )
    rows = {}
    for r in conn.execute(
        "SELECT i.id, i.name, i.sell_price, pc.price, pc.quantity, pc.seen_at, pc.ladder, pc.market_price, "
        "pc.median_7d, pc.sale_price FROM price_current pc JOIN price_snapshots s ON s.id = pc.snapshot_id "
        "JOIN items i ON i.id = pc.item_id AND i.game_version = ? "
        "WHERE pc.auction_house_id = ? AND (pc.listed IS NULL OR pc.listed != 0) "
        "AND s.source IN ('altarmy', 'blizzard_api', 'manual', 'csv')",
        (GAME_VERSION, house["id"]),
    ):
        ladder = decode_ladder(r["ladder"], r["median_7d"]) or None
        rows[r["id"]] = Price(
            r["id"], r["name"], r["sell_price"] or 0, r["price"], r["quantity"] or 0, str(r["seen_at"]),
            ladder, r["market_price"], r["median_7d"], r["sale_price"],
        )
    conn.close()
    return PriceBook(realm, faction, rows)


class Live:
    """alt-army.com, signed in with Alt Army Sync's saved refresh token (read, never written)."""

    def __init__(self, site: str, sync_file: Path) -> None:
        self.site = site.rstrip("/")
        try:
            self.refresh_token = json.loads(sync_file.read_text(encoding="utf-8"))["refresh_token"]
        except (OSError, ValueError, KeyError):
            sys.exit(f"no Alt Army Sync sign-in in {sync_file}: sign in with Alt Army Sync, or use --prices local")
        config = self._get_json(f"{self.site}/api/config", auth=False)
        self.api_key = config["firebase"]["api_key"]
        self.token, self.expires = "", 0.0

    def _id_token(self) -> str:
        if time.monotonic() < self.expires:
            return self.token
        body = urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": self.refresh_token})
        req = urllib.request.Request(
            f"https://securetoken.googleapis.com/v1/token?key={self.api_key}",
            data=body.encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded", "Referer": f"{self.site}/"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                got = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            sys.exit(f"signing in failed ({e.code}): sign in again in Alt Army Sync")
        self.token = got["id_token"]
        self.expires = time.monotonic() + int(got.get("expires_in", 3600)) - 300
        return self.token

    def _get_json(self, url: str, auth: bool = True) -> dict:
        for attempt in range(5):
            headers = {"Accept": "application/json"}
            if auth:
                headers["Authorization"] = f"Bearer {self._id_token()}"
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as resp:
                    return json.loads(resp.read())
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt < 4:
                    time.sleep(float(e.headers.get("Retry-After") or 5))
                    continue
                raise
        raise RuntimeError("unreachable")

    def api(self, path: str, **params: object) -> dict:
        query = urllib.parse.urlencode({"game_version": GAME_VERSION, **params})
        return self._get_json(f"{self.site}/api/{path}?{query}")

    def vendor_check(self) -> PriceBook:
        rows: dict[int, Price] = {}
        page, last, realm, faction = 1, 1, "", ""
        while page <= last:
            got = self.api("vendorcheck", sort="percent", order="asc", page=page)
            realm, faction = got["realm"], got["faction"]
            last = max(1, math.ceil(got["total"] / got["page_size"]))
            for it in got["items"]:
                rows[it["id"]] = Price(
                    it["id"], it["name"], it["sell_price"] or 0, it["ah_price"], it["ah_quantity"] or 0,
                    it.get("seen_at") or "",
                )
            print(f"\r  vendor check page {page}/{last}", end="", file=sys.stderr, flush=True)
            page += 1
        print(file=sys.stderr)
        return PriceBook(realm, faction, rows, details=self.details)

    def details(self, p: Price) -> None:
        got = self.api(f"vendorcheck/items/{p.item_id}")
        p.ladder = sorted(
            (
                Level(lv["price"], lv["quantity"], bool(lv.get("more")), bool(lv.get("counted", True)))
                for lv in got.get("ah_levels") or []
            ),
            key=lambda lv: (lv.price, lv.tail),
        ) or None
        p.market_price = got.get("market_price")
        p.median_7d = got.get("median_7d")
        p.sale_price = got.get("sale_price")
        time.sleep(0.6)  # 120 requests a minute per user


# --- the cross ---------------------------------------------------------------------------------------
@dataclass
class Cheap:
    basis: str  # "vendor" or "median"
    reference: int  # the vendor price or the median the item is judged against
    threshold: int  # listed at or under this counts
    ratio: float  # cheapest listing / reference
    units: int  # units listed at or under the threshold
    cost: int  # copper to buy all of them
    exact: bool  # from the ladder (False: from the cheapest listing and the units listed alone)
    more: bool  # the ladder's pooled tail starts under the threshold: some of its units may be cheap too
    everything: bool  # every unit listed is that cheap (against a median: the median may be stale)


def reference_price(p: Price) -> int:
    """What an item a vendor pays ~nothing for is judged against, as the site's sell price reads it: what
    it was seen selling for, else the lower of the market price and the 7-day median."""
    if p.sale_price:
        return p.sale_price
    known = [x for x in (p.market_price, p.median_7d) if x]
    return min(known) if known else 0


def cheapness(p: Price, args: argparse.Namespace) -> Cheap | None:
    if p.sell_price >= args.min_vendor:
        basis, reference, limit = "vendor", p.sell_price, args.max_ratio
    else:
        reference = reference_price(p)
        if reference <= 0:
            return None
        basis, limit = "median", args.below_median
    threshold = int(reference * limit)
    if p.ladder:
        levels = [lv for lv in p.ladder if lv.counted]
        if not levels:
            return None
        cheapest = levels[0].price
        under = [lv for lv in levels if lv.price <= threshold and not lv.tail]
        more = any(lv.tail and lv.price <= threshold for lv in levels)
        units, cost = sum(lv.units for lv in under), sum(lv.price * lv.units for lv in under)
        everything = units == sum(lv.units for lv in levels)
        exact = True
    else:
        if p.ah_price is None:
            return None
        cheapest, more, exact = p.ah_price, False, False
        units, cost, everything = p.quantity, p.quantity * p.ah_price, True
    if cheapest > threshold or units < args.min_units:
        return None
    return Cheap(basis, reference, threshold, cheapest / reference, units, cost, exact, more, everything)


def money(copper: float | int | None) -> str:
    if copper is None:
        return "-"
    c = int(round(copper))
    g, rest = divmod(abs(c), 10000)
    s, cc = divmod(rest, 100)
    sign = "-" if c < 0 else ""
    if g:
        return f"{sign}{g}g{s:02d}s"
    if s:
        return f"{sign}{s}s{cc:02d}c"
    return f"{sign}{cc}c"


# --- main --------------------------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Materials new WoW: Forever recipes want more of than vanilla did, crossed with what the "
        "auction house lists near vendor price.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--prices", choices=("live", "local", "none"), default="live",
                    help="live: alt-army.com's vendor check of your selected realm (Alt Army Sync's sign-in); "
                    "local: the development database's prices; none: the demand ranking alone")
    ap.add_argument("--site", default=SITE)
    ap.add_argument("--sync-file", type=Path, default=Path.home() / ".altarmy" / "sync.json")
    ap.add_argument("--db", type=Path, default=ROOT / "site" / "data" / "altarmy.sqlite",
                    help="the site's development database (Forever's recipes; local prices)")
    ap.add_argument("--vmangos", type=Path, default=None, help="vanilla's world database (default: the pin's)")
    ap.add_argument("--data-dir", type=Path, default=ROOT / "site" / "data" / "forever")
    ap.add_argument("--realm", default="Americas Normal", help="--prices local: the realm")
    ap.add_argument("--faction", default="Horde", help="--prices local: the faction")
    ap.add_argument("--max-ratio", type=float, default=1.5,
                    help="cheap: listed at or under this x what a vendor pays")
    ap.add_argument("--min-vendor", type=int, default=5,
                    help="items a vendor pays less copper than this are judged against their 7-day median")
    ap.add_argument("--below-median", type=float, default=0.8,
                    help="cheap (items vendors pay ~nothing for): listed at or under this x the 7-day median")
    ap.add_argument("--min-units", type=int, default=5, help="at least this many units cheap")
    ap.add_argument("--min-gain", type=float, default=0.5, help="materials gaining less demand than this are left out")
    ap.add_argument("--max-details", type=int, default=80,
                    help="live: at most this many items' order books fetched (about 2s each)")
    ap.add_argument("--top", type=int, default=40, help="rows per table")
    ap.add_argument("--include-vendor-sold", action="store_true",
                    help="keep materials a vendor sells without limit (they can't gain value)")
    ap.add_argument("--csv", type=Path, help="write every material with its scores and prices here")
    ap.add_argument("--explain", metavar="ITEM", help="an item id or name: every recipe behind its score")
    ap.add_argument("--recipes-csv", type=Path, help="write every recipe's classification and weight here")
    w = Weights()
    ap.add_argument("--w-skill", type=float, default=w.skill)
    ap.add_argument("--w-crate", type=float, default=w.crate)
    ap.add_argument("--w-writ", type=float, default=w.writ)
    ap.add_argument("--w-sod", type=float, default=w.sod)
    ap.add_argument("--lift-k", type=float, default=w.lift_k)
    args = ap.parse_args(argv)
    w = Weights(skill=args.w_skill, crate=args.w_crate, writ=args.w_writ, sod=args.w_sod, lift_k=args.lift_k)

    vmangos = args.vmangos or default_vmangos()
    for path in (args.db, vmangos):
        if not path.exists():
            sys.exit(f"missing {path}")
    items, forever, build = load_forever(args.db)
    vanilla, vanilla_items = load_vanilla(vmangos, forever)

    # prices first: the skill model costs recipes with them where it can
    book: PriceBook | None = None
    if args.prices == "live":
        print(f"Fetching the vendor check from {args.site} ...", file=sys.stderr)
        book = Live(args.site, args.sync_file).vendor_check()
    elif args.prices == "local":
        book = local_prices(args.db, args.realm, args.faction)

    vendor_sold = {int(r["item_id"]) for r in read_csv(args.data_dir / "vendor_items.csv")}
    limited = {int(r["item_id"]) for r in read_csv(args.data_dir / "vendor_offers.csv") if r["max_count"] not in ("", "0")}
    unit_price: dict[int, float] = {}
    for it in items.values():
        if it.id in vendor_sold and it.buy_price:
            unit_price[it.id] = it.buy_price / max(1, it.buy_count)
        else:
            unit_price[it.id] = max(1.0, it.sell_price * 4.0)
    if book:
        for p in book.rows.values():
            seen = p.median_7d or p.market_price or p.ah_price
            if seen and p.item_id not in vendor_sold:
                unit_price[p.item_id] = float(seen)

    writs = writ_targets(items, forever)
    f_crafts = skill_crafts(forever, unit_price, w)
    v_crafts = skill_crafts(vanilla, unit_price, w)
    f_weights = {
        s: recipe_weight(r, items, f_crafts, writs, w, s not in vanilla and s < FOREVER_IDS)
        for s, r in forever.items()
    }
    v_weights = {s: recipe_weight(r, items, v_crafts, set(), w, False) for s, r in vanilla.items()}

    f_direct = demand(forever, f_weights)
    v_direct = demand(vanilla, v_weights)
    crates = crate_bundles(items, {i for r in forever.values() for i in r.reagents})
    crate_demand: dict[int, list[tuple[str, float]]] = defaultdict(list)
    for name, options in crates:
        for item, count in options:
            crate_demand[item].append((name, w.crate * count / len(options)))

    f_total_direct = {i: sum(d.values()) + sum(x for _, x in crate_demand.get(i, ())) for i, d in f_direct.items()}
    for i, xs in crate_demand.items():
        f_total_direct.setdefault(i, sum(x for _, x in xs))
    v_total_direct = {i: sum(d.values()) for i, d in v_direct.items()}
    f_producers = processing_whitelist(args.data_dir, forever, items, vanilla_items)
    v_producers = {i: vanilla[r.spell_id] for i, r in f_producers.items() if r.spell_id in vanilla}
    f_prop = push_down(f_total_direct, f_producers)
    v_prop = push_down(v_total_direct, v_producers)

    def name_of(i: int) -> str:
        return items[i].name if i in items else f"item {i}"

    new_uses: dict[int, int] = defaultdict(int)  # Forever recipes vanilla lacks taking it directly
    for spell, r in forever.items():
        if spell not in vanilla:
            for i in r.reagents:
                new_uses[i] += 1
    vanilla_uses: dict[int, int] = defaultdict(int)
    for r in vanilla.values():
        for i in r.reagents:
            vanilla_uses[i] += 1
    mats: dict[int, Material] = {}
    for i in set(f_direct) | set(v_direct) | set(f_prop) | set(v_prop) | set(crate_demand):
        m = Material(i)
        for spell, d in f_direct.get(i, {}).items():
            r = forever[spell]
            if spell in vanilla:
                before = v_direct.get(i, {}).get(spell, 0.0)
                m.changed += d - before
                label = "changed" if forever[spell].reagents != vanilla[spell].reagents else "same"
                m.contributions.append(Contribution(label, r.name, d - before))
            else:
                m.new += d
                m.contributions.append(Contribution("new", r.name, d))
        m.new_uses = new_uses.get(i, 0)
        m.vanilla_uses = vanilla_uses.get(i, 0)
        for spell, d in v_direct.get(i, {}).items():
            if spell not in forever:
                m.removed -= d
                m.contributions.append(Contribution("removed", vanilla[spell].name, -d))
            elif i not in forever[spell].reagents:
                m.changed -= d
                m.contributions.append(Contribution("changed", vanilla[spell].name, -d))
        for crate, d in crate_demand.get(i, ()):
            m.crates += d
            m.contributions.append(Contribution("crate", crate, d))
        for via in set(f_prop.get(i, {})) | set(v_prop.get(i, {})):
            d = f_prop.get(i, {}).get(via, 0.0) - v_prop.get(i, {}).get(via, 0.0)
            m.propagated += d
            m.contributions.append(Contribution("via", name_of(via), d))
        m.forever = sum(f_direct.get(i, {}).values()) + m.crates + sum(f_prop.get(i, {}).values())
        m.vanilla = sum(v_direct.get(i, {}).values()) + sum(v_prop.get(i, {}).values())
        mats[i] = m

    def flags(i: int) -> str:
        it = items.get(i)
        out = []
        if i not in vanilla_items:
            out.append("NEW")
        if i in vendor_sold:
            out.append("VENDOR")
        elif i in limited:
            out.append("LIMITED")
        if it and it.bonding in (1, 4):
            out.append("BOP")
        return ",".join(out)

    def buyable(i: int) -> bool:
        it = items.get(i)
        return (
            it is not None
            and it.bonding not in (1, 4)
            and (args.include_vendor_sold or i not in vendor_sold)
        )

    # -- the header
    counts: dict[str, int] = defaultdict(int)
    for s, r in forever.items():
        if s not in vanilla:
            counts["new (Forever's own)" if s >= FOREVER_IDS else "new (SoD/holiday ids)"] += 1
        elif r.reagents != vanilla[s].reagents:
            counts["changed reagents"] += 1
        elif r.output_count != vanilla[s].output_count:
            counts["changed output count"] += 1
        else:
            counts["same"] += 1
    counts["removed"] = sum(1 for s in vanilla if s not in forever)
    counts["moved profession (also counted above)"] = sum(
        1 for s, r in forever.items() if s in vanilla and r.skill_line != vanilla[s].skill_line
    )
    print(f"Forever build {build} ({len(forever)} profession recipes) vs vanilla 1.12 ({len(vanilla)}; {vmangos.parent.name})")
    print("  " + ", ".join(f"{k}: {v}" for k, v in counts.items()))

    if args.recipes_csv:
        with args.recipes_csv.open("w", encoding="utf-8", newline="") as f:
            out = csv.writer(f)
            out.writerow(["spell_id", "name", "profession", "status", "source", "use", "end_per_craft",
                          "skill_per_craft", "leveller_crafts", "output", "reagents"])
            for s, r in sorted(forever.items()):
                end, skill, use = f_weights[s]
                status = "new" if s not in vanilla else ("changed" if r.reagents != vanilla[s].reagents else "same")
                out.writerow([s, r.name, PROFESSIONS[r.skill_line], status, r.source, use, round(end, 4),
                              round(skill, 4), round(f_crafts.get(s, 0.0), 1), name_of(r.output) if r.output else "",
                              "; ".join(f"{n} {name_of(i)}" for i, n in r.reagents.items())])
        print(f"  wrote {args.recipes_csv}")

    if args.explain:
        target = args.explain.strip()
        found = [i for i in mats if str(i) == target] or [
            i for i in mats if target.lower() in name_of(i).lower()
        ]
        if not found:
            sys.exit(f"no material matches {target!r}")
        for i in sorted(found, key=lambda i: -mats[i].score(w.lift_k))[:5]:
            m = mats[i]
            print(f"\n{name_of(i)} ({i}){' ' + flags(i) if flags(i) else ''}: Forever {m.forever:.2f} vs vanilla {m.vanilla:.2f}, "
                  f"gain {m.gain:+.2f}, lift {m.lift(w.lift_k):+.2f}, score {m.score(w.lift_k):+.2f}")
            print(f"  new {m.new:+.2f} ({m.new_uses} recipes), changed {m.changed:+.2f}, removed {m.removed:+.2f}, "
                  f"processing {m.propagated:+.2f}, crates {m.crates:+.2f}; vanilla recipes {m.vanilla_uses}")
            for c in sorted(m.contributions, key=lambda c: -abs(c.amount)):
                if abs(c.amount) >= 0.005:
                    print(f"    {c.amount:+7.3f}  {c.label:8} {c.recipe}")
        return 0

    def classic(i: int) -> bool:
        return i in vanilla_items

    def lift_text(m: Material) -> str:
        return f"{m.lift(w.lift_k):5.1f}" if classic(m.item_id) else "  new"

    def rank_key(m: Material) -> tuple[int, float]:
        """New materials first (by gain: they have no Classic demand to compare with), then Classic ones by
        lift: how much more Forever's recipes want them than vanilla's did."""
        return (0, -m.gain) if not classic(m.item_id) else (1, -m.lift(w.lift_k))

    ranked = sorted(
        (m for m in mats.values() if m.gain >= args.min_gain and buyable(m.item_id)),
        key=rank_key,
    )

    def drivers(m: Material, n: int = 3) -> str:
        top = sorted((c for c in m.contributions if c.amount > 0), key=lambda c: -c.amount)[:n]
        return "; ".join(f"{c.recipe}" + ("" if c.label == "new" else f" [{c.label}]") for c in top)

    cheap: dict[int, Cheap] = {}
    if book:
        if book.details:
            # the order book and medians for the items that may be cheap: those listed at or under the
            # vendor threshold, and those judged against their median (it is only in the details)
            short = []
            for m in ranked:
                p = book.rows.get(m.item_id)
                if p is None:
                    continue
                if p.sell_price >= args.min_vendor and p.ah_price > p.sell_price * args.max_ratio:
                    continue
                short.append(p)
            short.sort(key=lambda p: p.sell_price >= args.min_vendor)  # stable: rank order within each
            if len(short) > args.max_details:
                left = short[args.max_details :]
                blind = sum(p.sell_price < args.min_vendor for p in left)
                print(f"  --max-details {args.max_details}: {len(left) - blind} lower-ranked items judged on "
                      f"their cheapest listing alone, {blind} a vendor pays ~nothing for not judged at all "
                      "(no median without their order book)", file=sys.stderr)
            for n, p in enumerate(short[: args.max_details], 1):
                print(f"\r  order books {n}/{min(len(short), args.max_details)}", end="", file=sys.stderr, flush=True)
                try:
                    book.details(p)
                except urllib.error.HTTPError as e:
                    print(f"\n  {p.name}: {e.code}", file=sys.stderr)
            print(file=sys.stderr)
        for m in ranked:
            p = book.rows.get(m.item_id)
            if p is not None:
                c = cheapness(p, args)
                if c is not None:
                    cheap[m.item_id] = c
        seen = max((p.seen_at for p in book.rows.values()), default="")
        print(f"Prices: {book.realm} {book.faction}, {len(book.rows)} items listed, newest scan {seen}")

    def table(title: str, rows: list[Material]) -> None:
        print(f"\n{title} ({len(rows)}, top {min(len(rows), args.top)})")
        print(f"{'#':>3} {'lift':>5} {'gain':>7} {'new':>4} {'old':>4}  {'item':32} {'flags':10} drivers")
        for n, m in enumerate(rows[: args.top], 1):
            print(f"{n:>3} {lift_text(m)} {m.gain:+7.2f} {m.new_uses:>4} {m.vanilla_uses:>4}  "
                  f"{name_of(m.item_id)[:32]:32} {flags(m.item_id)[:10]:10} {drivers(m)[:90]}")

    print("\nlift: how much more Forever's recipes want it than vanilla's (+1.0 = twice as much); gain: the extra "
          "demand (weighted crafts x units); new/old: recipes taking it directly in Forever-only / vanilla recipes. "
          + ("Bind-on-pickup and unknown items left out." if args.include_vendor_sold
             else "Vendor-sold, bind-on-pickup and unknown items left out."))
    table("Classic materials Forever wants more of", [m for m in ranked if classic(m.item_id)])
    table("New Forever materials (no Classic demand or price to compare)", [m for m in ranked if not classic(m.item_id)])

    if book:
        rows = [m for m in ranked if m.item_id in cheap]
        print(f"\nBuy candidates: listed cheap now ({len(rows)}; cheap = at least {args.min_units} units at or under "
              f"{args.max_ratio}x what a vendor pays, or {args.below_median}x the 7-day median where a vendor pays under "
              f"{args.min_vendor}c)")
        print(f"{'#':>3} {'lift':>5}  {'item':32} {'flags':11} {'cheapest':>9} {'ref':>9} {'basis':6} "
              f"{'x ref':>5} {'units':>10} {'cost':>10}  drivers")
        for n, m in enumerate(rows[: args.top], 1):
            c, p = cheap[m.item_id], book.rows[m.item_id]
            units = f"{c.units}" + ("?" if not c.exact else "+" if c.more else "") + (" all" if c.everything else "")
            print(f"{n:>3} {lift_text(m)}  {name_of(m.item_id)[:32]:32} {flags(m.item_id):11} "
                  f"{money(p.ah_price):>9} {money(c.reference):>9} {c.basis:6} {c.ratio:5.2f} {units:>10} "
                  f"{money(c.cost):>10}  {drivers(m, 2)[:70]}")
        if any(not cheap[m.item_id].exact for m in rows):
            print("  units marked ? are every unit listed (no order book fetched): fewer may be that cheap")
        print("  units marked + : more may be that cheap in the order book's pooled tail; all: every unit listed "
              "is that cheap (against a median, the median may just be out of date)")

    if args.csv:
        with args.csv.open("w", encoding="utf-8", newline="") as f:
            out = csv.writer(f)
            out.writerow(["item_id", "name", "flags", "score", "gain", "lift", "forever", "vanilla", "new", "changed",
                          "removed", "processing", "crates", "new_uses", "vanilla_uses", "vendor_pays", "ah_cheapest",
                          "units_listed", "median_7d", "market_price", "cheap_basis", "cheap_ratio", "cheap_units",
                          "cheap_cost", "drivers"])
            for m in sorted(mats.values(), key=lambda m: -m.score(w.lift_k)):
                p = book.rows.get(m.item_id) if book else None
                c = cheap.get(m.item_id)
                it = items.get(m.item_id)
                out.writerow([
                    m.item_id, name_of(m.item_id), flags(m.item_id), round(m.score(w.lift_k), 4), round(m.gain, 4),
                    round(m.lift(w.lift_k), 4), round(m.forever, 4), round(m.vanilla, 4), round(m.new, 4),
                    round(m.changed, 4), round(m.removed, 4), round(m.propagated, 4), round(m.crates, 4),
                    m.new_uses, m.vanilla_uses, it.sell_price if it else "", p.ah_price if p else "",
                    p.quantity if p else "", (p.median_7d or "") if p else "", (p.market_price or "") if p else "",
                    c.basis if c else "", round(c.ratio, 3) if c else "", c.units if c else "", c.cost if c else "",
                    drivers(m, 5),
                ])
        print(f"\nWrote {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
