"""Regenerate AltArmy_TBC/Data/Economy/Writs.lua: WoW Forever's Craftsman's Writs and the crafting trees behind them.

Usage: python scripts/generate-writs.py [--db <website sqlite>] [--build pinned|latest|<build>]
                                        [--out <lua file>] [--check]

A Craftsman's Writ ("Craftsman's Writ: Lesser Wizard's Robe", items 264011..) starts a quest asking for a
crafted item in return for reputation. The item is named in the writ's name only, so it is matched to the
items the client's craft recipes make (exact after normalising case and punctuation, else the nearest by a
small edit distance; several when several recipes make items of that name). Its tier (Journeyman, Expert,
Artisan) is the writ's ItemNameDescription and its quest the writ's StartQuestID, both read from the
wago.tools ItemSparse export of the build (cached by the site's gamedata.py, loaded here by its path); the
site's database keeps neither. The reagent trees under the wanted items (every craft recipe making them or
anything they take, with vendor prices and bonding) come from the database, so the addon can plan the
cheapest way to buy or craft each writ's order.

Which items come with random suffixes ("Green Lens of Holy Wrath"), so that the addon searches the auction
house for them by name without an exact match: Forever's ItemSparse has no such column, so it comes from the
vmangos world database release pinned for Forever (item_template.random_property), from the cache or
downloaded while that release is still the newest.

What the game data lacks: how many units a writ asks for (assumed one craft's output until the addon reads
the quest in game) and the reputation it awards (REP below: community-reported per tier, not in the client).

--build: pinned (default) is the Forever build pinned in the monorepo's site/data/game-data.json; latest asks
wago.tools. --check writes nothing: it exits 1 when --out differs from what the game data gives, and 0 with a
note when the database, the build's cached tables or the cached world database aren't there to check against (it never downloads).
Stdlib only. The monorepo's game_data.py runs this daily (the game-data workflow), and the site's local
`ingest` runs it when it loads Forever data into its SQLite file.
"""
import argparse
import csv
import importlib.util
import os
import re
import sqlite3
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
DEFAULT_DB = os.path.join(ROOT, "..", "site", "data", "altarmy.sqlite")
DEFAULT_OUT = os.path.join(ROOT, "AltArmy_TBC", "Data", "Economy", "Writs.lua")
PINS = os.path.join(ROOT, "..", "site", "data", "game-data.json")
PRODUCT = "wow_classic_beta"

PREFIX = "Craftsman's Writ: "
WRIT_COUNT = 150
RECIPE_BAND = (150, 400)  # craft recipes the trees should reach: a broken ingest fails loudly
MAX_DISTANCE = 2  # edit distance allowed between a writ's name and the item it means
# Reputation per tier: community-reported (forevervsclassic.com, foreverchanges.pro, beta data), not in the client.
REP = {"Journeyman": 75, "Expert": 125, "Artisan": 200}
# The profession skill lines whose recipes count (generate-recipe-data.py's SKILL_LINES): drops test lines.
SKILL_LINES = {40, 129, 164, 165, 171, 185, 186, 197, 202, 333, 755}
TABLES = ("ItemSparse", "ItemNameDescription")


def load_gamedata():
    """The site's stdlib-only gamedata.py (downloads, cache, pins), loaded by its path."""
    path = os.path.join(ROOT, "..", "site", "src", "altarmy_site", "gamedata.py")
    spec = importlib.util.spec_from_file_location("gamedata", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["gamedata"] = module
    spec.loader.exec_module(module)
    return module


def normalize(name):
    """A name as it is compared: lower case, letters and digits only."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def match_candidates(wanted, outputs):
    """The item ids among `outputs` (item id -> name, the items craft recipes make) a writ for `wanted`
    means: every item named exactly like it (case and punctuation aside), else the nearest by edit distance
    up to MAX_DISTANCE when one name is nearest. Sorted by id; empty when nothing is close enough."""
    target = normalize(wanted)
    exact = sorted(i for i, n in outputs.items() if normalize(n) == target)
    if exact:
        return exact
    nearest = {}
    for item, name in outputs.items():
        d = levenshtein(target, normalize(name))
        if d <= MAX_DISTANCE:
            nearest.setdefault(d, {}).setdefault(normalize(name), []).append(item)
    if not nearest:
        return []
    names = nearest[min(nearest)]
    if len(names) > 1:
        sys.exit(f"writ {wanted!r} is equally close to {sorted(names)}")
    return sorted(next(iter(names.values())))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def read_rows(path, wanted_ids=None, key="ID"):
    """The CSV's rows by `key` (only `wanted_ids` when given, as strings)."""
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if wanted_ids is None or r[key] in wanted_ids:
                out[r[key]] = r
    return out


def read_game(db_path):
    """Writs, items, craft recipes and their reagents from the website's database (Forever)."""
    db = sqlite3.connect(f"file:{os.path.abspath(db_path)}?mode=ro", uri=True)
    writs = db.execute(
        "SELECT id, name FROM items WHERE game_version='forever' AND name LIKE ? ORDER BY id", (PREFIX + "%",)
    ).fetchall()
    items = {
        row[0]: {"name": row[1], "buy_price": row[2], "buy_count": row[3], "bonding": row[4], "stack": row[5]}
        for row in db.execute(
            "SELECT id, name, buy_price, buy_count, bonding, stack_size FROM items WHERE game_version='forever'"
        )
    }
    vendor = {row[0] for row in db.execute("SELECT item_id FROM vendor_items WHERE game_version='forever'")}
    recipes = {}
    for spell, name, skill_name, out, count, skill_line in db.execute(
        "SELECT spell_id, name, skill_name, output_item_id, output_count, skill_line FROM recipes"
        " WHERE game_version='forever' AND kind='craft' ORDER BY spell_id"
    ):
        if skill_line in SKILL_LINES and out:
            recipes[spell] = {"name": name, "prof": skill_name, "out": out, "n": count or 1, "reagents": []}
    for spell, item, count in db.execute(
        "SELECT r.spell_id, g.item_id, g.count FROM recipe_reagents g JOIN recipes r"
        " ON r.game_version=g.game_version AND r.id=g.recipe_id WHERE g.game_version='forever'"
        " ORDER BY r.spell_id, g.slot"
    ):
        if spell in recipes:
            recipes[spell]["reagents"].append((item, count))
    db.close()
    return writs, items, vendor, recipes


def plan_data(writs, items, vendor, recipes, sparse, labels):
    """What the Lua module holds: the writ list, the items and recipes their trees reach."""
    by_output = {}
    for spell, r in recipes.items():
        by_output.setdefault(r["out"], []).append(spell)
    outputs = {item: items[item]["name"] for item in by_output if item in items}
    rows = []
    for writ_id, name in writs:
        row = sparse.get(str(writ_id))
        if not row or not int(float(row.get("StartQuestID") or 0)):
            sys.exit(f"{writ_id} {name!r}: no StartQuestID in ItemSparse")
        tier = labels.get(row.get("ItemNameDescriptionID") or "")
        if tier not in REP:
            sys.exit(f"{writ_id} {name!r}: unknown tier {tier!r}")
        candidates = match_candidates(name[len(PREFIX):], outputs)
        if not candidates:
            sys.exit(f"{writ_id} {name!r}: no craft recipe makes an item of that name")
        rows.append({
            "id": writ_id, "quest": int(float(row["StartQuestID"])), "name": name, "short": name[len(PREFIX):],
            "tier": tier, "rep": REP[tier], "items": candidates,
            "count": recipes[by_output[candidates[0]][0]]["n"],
        })
    out_items, out_recipes = trees([item for row in rows for item in row["items"]], items, vendor, recipes)
    if not RECIPE_BAND[0] <= len(out_recipes) <= RECIPE_BAND[1]:
        sys.exit(f"the writs' trees reach {len(out_recipes)} recipes, expected {RECIPE_BAND[0]}-{RECIPE_BAND[1]}")
    return rows, out_items, out_recipes


def trees(roots, items, vendor, recipes):
    """Every item and craft recipe the reagent trees under `roots` reach (read_game's tables): the items with
    their stack size, vendor price (`vendor` copper per `per` units, where a vendor sells them) and `bop`,
    and the recipes by spell id. Also used by generate-waylaid-crates.py for the crates' bundles."""
    by_output = {}
    for spell, r in recipes.items():
        by_output.setdefault(r["out"], []).append(spell)
    used_items, used_recipes = set(), set()
    stack = list(roots)
    while stack:
        item = stack.pop()
        if item in used_items:
            continue
        if item not in items:
            sys.exit(f"item {item} is a reagent but not in the items table")
        used_items.add(item)
        for spell in by_output.get(item, ()):
            used_recipes.add(spell)
            stack.extend(i for i, _ in recipes[spell]["reagents"])
    out_items = {}
    for item in sorted(used_items):
        it = items[item]
        entry = {"name": it["name"], "stack": max(1, it["stack"] or 1)}
        if item in vendor and it["buy_price"]:
            entry["vendor"] = it["buy_price"]
            entry["per"] = max(1, it["buy_count"] or 1)
        if it["bonding"] == 1:
            entry["bop"] = True
        out_items[item] = entry
    out_recipes = {spell: recipes[spell] for spell in sorted(used_recipes)}
    return out_items, out_recipes


def render_trees(module, out_items, out_recipes):
    """Lua lines for `<module>.ITEMS` and `<module>.RECIPES` (trees' output). Also used by
    generate-waylaid-crates.py."""
    out = [f"{module}.ITEMS = {{"]
    for item, entry in out_items.items():
        parts = [f"name = {lua_str(entry['name'])}", f"stack = {entry['stack']}"]
        if "vendor" in entry:
            parts.append(f"vendor = {entry['vendor']}, per = {entry['per']}")
        if entry.get("bop"):
            parts.append("bop = true")
        if entry.get("suffix"):
            parts.append("suffix = true")
        out.append(f"    [{item}] = {{ {', '.join(parts)} }},")
    out += ["}", "", f"{module}.RECIPES = {{"]
    for spell, r in out_recipes.items():
        out.append(
            f"    [{spell}] = {{ out = {r['out']}, n = {r['n']}, prof = {lua_str(r['prof'])},"
            f" name = {lua_str(r['name'])}, reagents = {{"
        )
        reagents = [f"{{ item = {i}, count = {c} }}" for i, c in r["reagents"]]
        for start in range(0, len(reagents), 3):  # three a line keeps lines under 120 characters
            out.append("      " + ", ".join(reagents[start:start + 3]) + ",")
        out.append("    } },")
    return out + ["}"]


def render(build, rows, out_items, out_recipes):
    out = [
        "-- AltArmy TBC — WoW Forever's Craftsman's Writs and the crafting trees behind them (Economy tab).",
        "-- GENERATED by scripts/generate-writs.py from the client's game data: do not edit by hand.",
        "-- LIST: each writ, its quest, tier, reputation (REP: community-reported, not in the game data), the",
        "-- item(s) its name means (`items`: several when several recipes make items of that name) and `count`,",
        "-- one craft's output (an assumption until the addon reads the quest). ITEMS: every item the trees",
        "-- touch (`vendor` copper per `per` units where a vendor sells it; `bop` binds on pickup; `suffix` comes",
        "-- with random suffixes, \"of the Eagle\"). RECIPES: the craft recipes by spell id (`out`, `n` made per",
        "-- cast, `prof`, `reagents`).",
        "",
        "if not AltArmy then return end",
        "",
        "AltArmy.Writs = AltArmy.Writs or {}",
        "local W = AltArmy.Writs",
        "",
        f"W.BUILD = {lua_str(build)}",
        "W.TIERS = { " + ", ".join(lua_str(t) for t in REP) + " }",
        "W.REP = { " + ", ".join(f"{t} = {rep}" for t, rep in REP.items()) + " }",
        "W.LIST = {",
    ]
    for row in rows:
        out.append(
            f"    {{ id = {row['id']}, quest = {row['quest']}, tier = {lua_str(row['tier'])}, rep = {row['rep']},"
            f" items = {{ {', '.join(str(i) for i in row['items'])} }}, count = {row['count']},"
        )
        out.append(f"      name = {lua_str(row['name'])},")
        out.append(f"      short = {lua_str(row['short'])} }},")
    out += ["}", ""]
    out += render_trees("W", out_items, out_recipes)
    out += [
        "",
        "W.ById, W.ByQuest, W.ByOutput = {}, {}, {}",
        "for _, writ in ipairs(W.LIST) do",
        "    W.ById[writ.id] = writ",
        "    W.ByQuest[writ.quest] = writ",
        "end",
        "for spell, recipe in pairs(W.RECIPES) do",
        "    local list = W.ByOutput[recipe.out] or {}",
        "    list[#list + 1] = spell",
        "    W.ByOutput[recipe.out] = list",
        "end",
        "for _, list in pairs(W.ByOutput) do",
        "    table.sort(list)",
        "end",
        "",
    ]
    return "\n".join(out)


def suffixed(world_path, item_ids):
    """The items of `item_ids` that come with random suffixes, by the emulator's world database (vmangos'
    item_template.random_property, set on any of an item's patch rows)."""
    ids = sorted(item_ids)
    if not ids:
        return set()
    db = sqlite3.connect(f"file:{world_path}?mode=ro", uri=True)
    try:
        marks = ",".join("?" * len(ids))
        rows = db.execute(
            f"SELECT DISTINCT entry FROM item_template WHERE random_property != 0 AND entry IN ({marks})", ids
        ).fetchall()
    finally:
        db.close()
    return {row[0] for row in rows}


def build_module(db_path, build, sparse_path, labels_path, world_path=None):
    """The Lua module's text and its writ count, from the database, the build's cached tables and (for the
    random suffixes) the emulator's world database."""
    writs, items, vendor, recipes = read_game(db_path)
    if len(writs) != WRIT_COUNT:
        sys.exit(f"expected {WRIT_COUNT} Craftsman's Writs, found {len(writs)}")
    sparse = read_rows(sparse_path, {str(i) for i, _ in writs})
    labels = {k: r["Description_lang"] for k, r in read_rows(labels_path).items()}
    rows, out_items, out_recipes = plan_data(writs, items, vendor, recipes, sparse, labels)
    if world_path:
        for item in suffixed(world_path, out_items):
            out_items[item]["suffix"] = True
    return render(build, rows, out_items, out_recipes), len(rows)


def read_normalized(path):
    """The file's text with LF line endings (git may check it out with CRLF), or None if it's missing."""
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().replace("\r\n", "\n")
    except FileNotFoundError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--build", default="pinned", help="pinned (default), latest, or a build like 1.60.1.70205")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true", help="exit 1 if --out is out of date; write nothing")
    args = ap.parse_args()
    gamedata = load_gamedata()
    build = args.build
    if build == "pinned":
        build = gamedata.read_pins(Path(PINS))["forever"].build
    elif build == "latest":
        build = gamedata.latest_build(PRODUCT)
    cached = {t: gamedata.REPO_CACHE / "wago" / build / f"{t}.csv" for t in TABLES}
    pin = gamedata.read_pins(Path(PINS))["forever"]
    world = gamedata.cached_world_db(pin.emulator, pin.release, gamedata.REPO_CACHE)
    if args.check:
        missing = [str(p) for p in (Path(args.db), *cached.values(), world) if not p.is_file()]
        if missing:
            print(f"Craftsman's Writs check skipped: no {', '.join(missing)}")
            return
    paths = {t: str(gamedata.download_table(t, build, gamedata.REPO_CACHE)) for t in TABLES}
    world = gamedata.world_db(pin.emulator, gamedata.REPO_CACHE, pin.release)
    text, count = build_module(args.db, build, paths["ItemSparse"], paths["ItemNameDescription"], str(world))
    if args.check:
        if read_normalized(args.out) != text:
            sys.exit(
                f"{os.path.relpath(args.out)} is out of date with the website's game data.\n"
                "Run `python scripts/generate-writs.py` and commit the change."
            )
        return
    if read_normalized(args.out) == text:
        print(f"{args.out}: already up to date ({count} writs)")
        return
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {args.out}: {count} writs")


if __name__ == "__main__":
    main()
