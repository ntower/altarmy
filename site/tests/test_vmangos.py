import sqlite3
from collections.abc import Iterator
from pathlib import Path

import pytest

from altarmy_site import vmangos

WORLD_SCHEMA = """
CREATE TABLE creature (guid INTEGER, id INTEGER, id2 INTEGER, id3 INTEGER, id4 INTEGER, id5 INTEGER);
CREATE TABLE creature_template (entry INTEGER, patch INTEGER, name TEXT, vendor_id INTEGER);
CREATE TABLE npc_vendor (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER);
CREATE TABLE npc_vendor_template (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER);
CREATE TABLE item_template (entry INTEGER, patch INTEGER, name TEXT, class INTEGER DEFAULT 0);
"""


@pytest.fixture
def world(tmp_path: Path) -> Iterator[sqlite3.Connection]:
    """Vendors 1 (spawned) and 2 (never spawned) sell directly; vendor 3 (spawned as an alternate id)
    sells through vendor template 50."""
    conn = sqlite3.connect(tmp_path / "mangos.sqlite")
    conn.executescript(WORLD_SCHEMA)
    conn.executemany("INSERT INTO creature VALUES (?,?,?,?,?,?)", [(1, 1, 0, 0, 0, 0), (2, 9, 3, 0, 0, 0)])
    conn.executemany(
        "INSERT INTO creature_template VALUES (?,?,?,?)",
        [(1, 0, "Trader", 0), (2, 0, "Ghost Trader", 0), (3, 0, "Supplier", 50), (3, 1, "Supplier", 50)],
    )
    conn.executemany(
        "INSERT INTO npc_vendor VALUES (?,?,?,?)",
        [
            (1, 100, 0, 0),  # unlimited
            (1, 101, 2, 0),  # limited stock
            (1, 102, 0, 7),  # behind a condition (reputation, event, ...)
            (2, 103, 0, 0),  # vendor never spawns
        ],
    )
    conn.executemany("INSERT INTO npc_vendor_template VALUES (?,?,?,?)", [(50, 104, 0, 0), (50, 100, 0, 0)])
    conn.executemany(
        "INSERT INTO item_template (entry, patch, name) VALUES (?,?,?)",
        [(100, 0, "Rune Thred"), (100, 1, "Rune Thread"), (104, 0, "Empty Vial")],
    )
    yield conn
    conn.close()


def test_vendor_items_are_unlimited_unconditional_and_spawned(world: sqlite3.Connection) -> None:
    assert vmangos.vendor_items(world) == [(100, "Rune Thread"), (104, "Empty Vial")]


def test_vendor_recipes_are_recipe_items_of_any_stock_unconditional_and_spawned(
    world: sqlite3.Connection,
) -> None:
    world.executemany(
        "INSERT INTO item_template (entry, patch, name, class) VALUES (?,?,?,?)",
        [
            (200, 0, "Recipe: Stew", 9),
            (201, 0, "Plans: Maul", 9),
            (202, 0, "Pattern: Timbermaw Belt", 9),
            (203, 0, "Recipe: Ghost Pie", 9),
            (204, 0, "Formula: Glow", 9),
        ],
    )
    world.executemany(
        "INSERT INTO npc_vendor VALUES (?,?,?,?)",
        [
            (1, 200, 0, 0),  # unlimited
            (1, 201, 1, 0),  # limited stock: still a vendor's
            (1, 202, 0, 7),  # behind a condition (reputation, event, ...)
            (2, 203, 0, 0),  # vendor never spawns
        ],
    )
    world.execute("INSERT INTO npc_vendor_template VALUES (50, 204, 1, 0)")
    # not the thread and vials: they teach nothing
    assert vmangos.vendor_recipes(world) == [
        (200, "Recipe: Stew"),
        (201, "Plans: Maul"),
        (204, "Formula: Glow"),
    ]


def test_trainer_costs_are_the_least_any_trainer_asks_for_the_spell_taught(world: sqlite3.Connection) -> None:
    world.executescript(
        """
        CREATE TABLE npc_trainer (
            entry INTEGER, spell INTEGER, spellcost INTEGER, reqskillvalue INTEGER, build_max INTEGER
        );
        CREATE TABLE npc_trainer_template (
            entry INTEGER, spell INTEGER, spellcost INTEGER, reqskillvalue INTEGER, build_max INTEGER
        );
        CREATE TABLE spell_template (
            entry INTEGER, build INTEGER, effect1 INTEGER, effectTriggerSpell1 INTEGER, effect2 INTEGER,
            effectTriggerSpell2 INTEGER, effect3 INTEGER, effectTriggerSpell3 INTEGER
        );
        """
    )
    world.executemany(
        "INSERT INTO spell_template VALUES (?,?,?,?,?,?,?,?)",
        [
            (3516, 4222, 36, 3491, 0, 0, 0, 0),  # teaches Big Bronze Knife
            (3517, 4222, 6, 0, 0, 0, 0, 0),  # an older build's teach spell...
            (3517, 5875, 0, 0, 36, 3492, 0, 0),  # ...teaching through its second effect now
        ],
    )
    world.executemany(
        "INSERT INTO npc_trainer VALUES (?,?,?,?,?)",
        [
            (1, 3516, 600, 90, 5875),
            (2, 3516, 900, 90, 5875),  # a dearer trainer
            (3, 3516, 100, 90, 4695),  # a fee a later patch changed
            (1, 7000, 50, 0, 5875),  # listed as the spell itself: no teach spell; a class spell, no skill
        ],
    )
    world.execute("INSERT INTO npc_trainer_template VALUES (60, 3517, 250, 125, 5875)")
    assert vmangos.trainer_costs(world) == [(3491, 600, 90), (3492, 250, 125), (7000, 50, 0)]


def test_write_trainer_costs_csv(tmp_path: Path) -> None:
    path = tmp_path / "trainer_costs.csv"
    vmangos.write_trainer_costs_csv([(3491, 600, 90), (3492, 250, 125)], path, {3492: -25})
    assert path.read_text(encoding="utf-8").splitlines() == [
        "spell_id,cost,req_skill,yellow_shift",
        "3491,600,90,0",
        "3492,250,125,-25",
    ]


def test_write_csv_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "vendor_items.csv"
    vmangos.write_csv([(100, "Rune Thread"), (104, "Vial, Empty")], path)
    assert path.read_text(encoding="utf-8").splitlines() == [
        "item_id,name",
        "100,Rune Thread",
        '104,"Vial, Empty"',
    ]


LOOT = (
    "entry INTEGER, item INTEGER, ChanceOrQuestChance REAL, groupid INTEGER, mincountOrRef INTEGER, "
    "maxcount INTEGER, patch_min INTEGER DEFAULT 0, patch_max INTEGER DEFAULT 10"
)
REWARDS = ", ".join(f"{c} INTEGER DEFAULT 0" for c in vmangos.QUEST_REWARDS)
SOURCES_SCHEMA = f"""
CREATE TABLE creature (guid INTEGER, id INTEGER, id2 INTEGER DEFAULT 0, id3 INTEGER DEFAULT 0,
    id4 INTEGER DEFAULT 0, id5 INTEGER DEFAULT 0, map INTEGER, position_x REAL, position_y REAL,
    patch_min INTEGER DEFAULT 0, patch_max INTEGER DEFAULT 10);
CREATE TABLE creature_template (entry INTEGER, patch INTEGER, name TEXT, faction INTEGER, level_min INTEGER,
    level_max INTEGER, loot_id INTEGER, vendor_id INTEGER DEFAULT 0);
CREATE TABLE faction_template (id INTEGER, build INTEGER, hostile_mask INTEGER);
CREATE TABLE map_template (entry INTEGER, patch INTEGER, map_type INTEGER, map_name TEXT);
CREATE TABLE npc_vendor (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER DEFAULT 0);
CREATE TABLE npc_vendor_template (entry INTEGER, item INTEGER, maxcount INTEGER, condition_id INTEGER);
CREATE TABLE item_template (entry INTEGER, patch INTEGER, name TEXT, class INTEGER);
CREATE TABLE quest_template (entry INTEGER, patch INTEGER, Title TEXT, ZoneOrSort INTEGER, QuestLevel INTEGER,
    RequiredRaces INTEGER, {REWARDS});
CREATE TABLE creature_questrelation (id INTEGER, quest INTEGER, patch_min INTEGER DEFAULT 0,
    patch_max INTEGER DEFAULT 10);
CREATE TABLE area_template (entry INTEGER, name TEXT);
CREATE TABLE gameobject (guid INTEGER, id INTEGER, map INTEGER, position_x REAL, position_y REAL,
    patch_min INTEGER DEFAULT 0, patch_max INTEGER DEFAULT 10);
CREATE TABLE gameobject_template (entry INTEGER, patch INTEGER, name TEXT, type INTEGER, data1 INTEGER);
CREATE TABLE creature_loot_template ({LOOT});
CREATE TABLE reference_loot_template ({LOOT});
CREATE TABLE gameobject_loot_template ({LOOT});
CREATE TABLE item_loot_template ({LOOT});
"""
LOOT_INSERT = "(entry, item, ChanceOrQuestChance, groupid, mincountOrRef, maxcount) VALUES (?,?,?,?,?,?)"
# map 0, in yards: Westfall's box overlaps Duskwood's, both bigger than a city's (the continent never
# counts); map 33 is a dungeon
ZONES = [
    (0, "Eastern Kingdoms", -100000.0, -100000.0, 100000.0, 100000.0, 0),
    (0, "Westfall", 0.0, 0.0, 10000.0, 10000.0, 40),
    (0, "Duskwood", 9000.0, 0.0, 30000.0, 10000.0, 10),
]
MOBS = vmangos.WORLD_DROP_AT + 1


@pytest.fixture
def sources_world(tmp_path: Path) -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(tmp_path / "mangos.sqlite")
    conn.executescript(SOURCES_SCHEMA)
    conn.executemany(
        "INSERT INTO item_template VALUES (?,?,?,?)",
        [
            (500, 0, "Recipe: Stew", 9),
            (501, 0, "Pattern: Cloak", 9),
            (502, 0, "Plans: Helm", 9),
            (503, 0, "Formula: Wand", 9),
            (504, 0, "Schematic: Gun", 9),
            (600, 0, "Lockbox", 15),
        ],
    )
    # hostile to the Horde (4), to the Alliance (2); 35's newest build hostile to neither
    conn.executemany(
        "INSERT INTO faction_template VALUES (?,?,?)",
        [(12, 1, 4), (29, 1, 2), (35, 1, 0), (35, 0, 4), (14, 1, 6)],
    )
    conn.executemany(
        "INSERT INTO map_template VALUES (?,?,?,?)", [(0, 0, 0, "Eastern Kingdoms"), (33, 0, 1, "Deadmines")]
    )
    conn.executemany(
        "INSERT INTO creature_template (entry, patch, name, faction, level_min, level_max, loot_id) "
        "VALUES (?,?,?,?,?,?,?)",
        [
            (1, 0, "Kendor", 12, 30, 30, 0),
            (2, 0, "Borya", 29, 30, 30, 0),
            (3, 0, "Gazlowe", 35, 30, 30, 0),
            (4, 0, "Pillager", 14, 15, 16, 4),
            (5, 0, "Van Cleef", 14, 20, 20, 5),
            (6, 0, "Ghost", 14, 20, 20, 4),  # never spawned
        ]
        + [(100 + i, 0, f"Mob {i}", 14, 10 + i, 12 + i, 100) for i in range(MOBS)],
    )
    conn.executemany(
        "INSERT INTO creature (guid, id, map, position_x, position_y) VALUES (?,?,?,?,?)",
        [
            (1, 1, 0, 5000, 5000),  # well inside Westfall
            (2, 2, 0, 9900, 5000),  # where Westfall and Duskwood overlap, nearer Duskwood's middle
            (3, 3, 0, 5000, 5000),
            (4, 4, 0, 5000, 5000),
            (5, 4, 0, 5200, 5000),
            (6, 4, 0, 20000, 5000),  # one of three spawns in Duskwood: Westfall wins
            (7, 5, 33, 0, 0),
        ]
        + [(200 + i, 100 + i, 0, 5000, 5000) for i in range(MOBS)],
    )
    conn.executemany(  # 502 behind a condition
        "INSERT INTO npc_vendor VALUES (?,?,?,?)",
        [(1, 500, 0, 0), (2, 500, 1, 0), (3, 501, 0, 0), (3, 502, 0, 9)],
    )
    conn.executemany(
        "INSERT INTO quest_template (entry, patch, Title, ZoneOrSort, QuestLevel, RequiredRaces, RewItemId1, "
        "RewChoiceItemId2) VALUES (?,?,?,?,?,?,?,?)",
        [
            (1, 0, "Stew Time", 40, 12, 1, 0, 500),  # humans only, filed under Westfall, no giver
            (2, 0, "<UNUSED>Stew", 40, 12, 0, 500, 0),
            (3, 0, "Cloak Job", -101, 20, 0, 501, 0),  # given by Borya
        ],
    )
    conn.execute("INSERT INTO creature_questrelation (id, quest) VALUES (2, 3)")
    conn.execute("INSERT INTO area_template VALUES (40, 'Westfall')")
    conn.executemany(
        f"INSERT INTO creature_loot_template {LOOT_INSERT}",
        [
            (4, 502, 2.0, 0, 1, 1),
            (5, 0, 50.0, 0, -900, 2),  # rolls reference 900 twice, half the time
            (5, 501, 30.0, 1, 1, 1),
            (5, 502, 0, 1, 1, 1),  # shares the group's remaining 70% with 503
            (5, 503, 0, 1, 1, 1),
            (100, 504, -5.0, 0, 1, 1),  # a quest drop's chance is negative
        ],
    )
    conn.execute(f"INSERT INTO reference_loot_template {LOOT_INSERT}", (900, 504, 10.0, 0, 1, 1))
    conn.executemany(  # two chests of the same name
        "INSERT INTO gameobject_template VALUES (?,?,?,?,?)",
        [(70, 0, "Chest", 3, 71), (72, 0, "Chest", 3, 71)],
    )
    conn.executemany(
        "INSERT INTO gameobject (guid, id, map, position_x, position_y) VALUES (?,?,?,?,?)",
        [(1, 70, 0, 5000, 5000), (2, 72, 0, 20000, 5000)],
    )
    conn.executemany(
        f"INSERT INTO gameobject_loot_template {LOOT_INSERT}",
        [(71, 502, 1.0, 0, 1, 1), (71, 504, 50.0, 0, 1, 1)],
    )
    conn.execute(f"INSERT INTO item_loot_template {LOOT_INSERT}", (600, 502, 0.5, 0, 1, 1))
    yield conn
    conn.close()


def test_recipe_item_sources(sources_world: sqlite3.Connection) -> None:
    by_item: dict[int, list[vmangos.ItemSource]] = {}
    for s in vmangos.recipe_item_sources(sources_world, ZONES):
        by_item.setdefault(s.item_id, []).append(s)
    src = vmangos.ItemSource
    assert by_item[500] == [
        src(500, "vendor", "Borya", "Duskwood", "horde", limited=True, area=10, map_x=50.0, map_y=95.7),
        src(500, "vendor", "Kendor", "Westfall", "alliance", area=40, map_x=50.0, map_y=50.0),
        src(500, "quest", "Stew Time", "Westfall", "alliance", levels="12"),
    ]
    assert by_item[501] == [
        src(501, "vendor", "Gazlowe", "Westfall", area=40, map_x=50.0, map_y=50.0),
        src(501, "quest", "Cloak Job", "Duskwood", "horde", levels="20"),  # where Borya stands, his side
        src(501, "drop", "Van Cleef", "Deadmines", chance=30.0),
    ]
    # the group's 70% left over, shared by two; then the chest (seen in two zones) and the lockbox
    assert by_item[502] == [
        src(502, "drop", "Van Cleef", "Deadmines", chance=35.0),
        src(502, "drop", "Pillager", "Westfall", chance=2.0),
        src(502, "object", "Chest", "", chance=1.0),
        src(502, "more", count=1),
    ]
    assert by_item[503] == [src(503, "drop", "Van Cleef", "Deadmines", chance=35.0)]
    # more creatures than WORLD_DROP_AT: a world drop, the chest holding it left out (and Van Cleef's
    # 50% x 2 rolls x 10% among them)
    assert by_item[504] == [src(504, "world_drop", count=MOBS + 1, levels="10-32")]


def test_write_sources_csv(tmp_path: Path) -> None:
    path = tmp_path / "sources.csv"
    rows = [
        vmangos.ItemSource(
            500, "vendor", "Kendor, the Cook", "Westfall", "alliance", 0.0, 0, "", True, 40, 25.0, 75.5
        )
    ]
    vmangos.write_sources_csv(rows, path)
    assert path.read_text(encoding="utf-8").splitlines() == [
        "item_id,kind,name,zone,side,chance,count,levels,limited,area,map_x,map_y",
        '500,vendor,"Kendor, the Cook",Westfall,alliance,0.0,0,,1,40,25.0,75.5',
    ]
