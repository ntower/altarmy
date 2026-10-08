import csv
import json
from pathlib import Path

import pytest
from sqlalchemy import Connection, func, select
from sqlalchemy.engine import Row

from altarmy_site import db, ingest, prices, schema, spelltext, store

from .conftest import FOREVER, set_prices, write_csv


def item(conn: Connection, item_id: int, game_version: str = FOREVER) -> Row[tuple[object, ...]]:
    t = schema.items
    return conn.execute(select(t).where(t.c.game_version == game_version, t.c.id == item_id)).one()


def count(conn: Connection, table: str) -> int:
    return int(conn.execute(select(func.count()).select_from(schema.metadata.tables[table])).scalar_one())


def test_build_db_loads_items_and_recipes(db2_paths: dict[str, Path], conn: Connection) -> None:
    stats = ingest.build_db(db2_paths, conn, FOREVER)
    assert stats == {"items": 3, "recipes": 1, "disenchant_rows": 0, "vendor_items": 0}

    robe = item(conn, 3)
    assert (robe.name, robe.quality, robe.item_level, robe.class_id, robe.sell_price) == (
        "Green Robe",
        2,
        20,
        4,
        500,
    )

    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.id, recipe.name, recipe.skill_name, recipe.output_item_id) == (
        100,
        "Green Robe",
        "Tailoring",
        3,
    )
    assert recipe.min_skill == 25 and recipe.output_count == 1

    rr = schema.recipe_reagents
    reagents = [tuple(r) for r in conn.execute(select(rr.c.slot, rr.c.item_id, rr.c.count))]
    assert sorted(reagents) == [(0, 1, 10), (1, 2, 1)]


def test_build_db_loads_cast_time_and_station(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.cast_time_ms, recipe.station) == (3000, "anvil")  # SpellMisc -> SpellCastTimes; focus 1


def test_build_db_loads_the_skill_the_recipe_item_requires(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the robe item teaches the robe's craft spell (on learn, through ItemXItemEffect) and requires 50
    assert conn.execute(select(schema.recipes.c.learn_skill)).scalar_one() == 50


def test_spawn_zone_guesses_the_zone_from_overlapping_maps() -> None:
    zones: list[ingest.ZoneBox] = [
        (0, "Eastern Kingdoms", -50000, -50000, 50000, 50000, 0),  # a continent never counts
        (0, "Elwynn Forest", 0, 0, 3000, 3000, 12),
        (0, "Stormwind City", 2000, 2000, 3500, 3500, 1519),  # a city, drawn off its map's centre
        (0, "Westfall", -2500, 0, 500, 3000, 40),
    ]

    def zone(x: float, y: float, map_id: int = 0) -> str | None:
        box = ingest.spawn_zone(zones, map_id, x, y)
        return box[1] if box else None

    assert zone(2100, 2100) == "Stormwind City"  # near the city map's edge, still the city
    assert zone(1500, 1500) == "Elwynn Forest"
    assert zone(400, 1500) == "Elwynn Forest"  # in both, well inside neither: nearer Elwynn's middle
    assert zone(-1000, 1500) == "Westfall"
    assert zone(-10000, 1500) is None  # only the continent's
    assert zone(1500, 1500, map_id=1) is None


def test_learn_skills_take_the_lowest_rank_of_the_items_teaching_a_spell(tmp_path: Path) -> None:
    effects = write_csv(  # TBC's shape: each effect names its item
        tmp_path / "ItemEffect.csv",
        ["ID", "TriggerType", "SpellID", "ParentItemID"],
        [
            {"ID": 1, "TriggerType": 0, "SpellID": 483, "ParentItemID": 10},  # "Learning", on use
            {"ID": 2, "TriggerType": 6, "SpellID": 700, "ParentItemID": 10},
            {"ID": 3, "TriggerType": 6, "SpellID": 700, "ParentItemID": 11},  # another pattern, lower
            {"ID": 4, "TriggerType": 6, "SpellID": 701, "ParentItemID": 12},  # requires no skill
            {"ID": 5, "TriggerType": 0, "SpellID": 702, "ParentItemID": 13},  # not a recipe item
        ],
    )
    ranks = {10: 75, 11: 60, 12: 0, 13: 40}
    assert ingest.learn_skills({"ItemEffect": effects}, ranks) == {700: 60}


def test_build_db_loads_what_teaches_a_recipe(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the item teaching the robe's craft spell binds on equip: a recipe that can be traded
    assert conn.execute(select(schema.recipes.c.source)).scalar_one() == "recipe"


def test_learn_sources_are_bind_on_pickup_only_when_every_teaching_item_is(tmp_path: Path) -> None:
    effects = write_csv(
        tmp_path / "ItemEffect.csv",
        ["ID", "TriggerType", "SpellID", "ParentItemID"],
        [
            {"ID": 1, "TriggerType": 6, "SpellID": 700, "ParentItemID": 10},  # binds on pickup
            {"ID": 2, "TriggerType": 6, "SpellID": 700, "ParentItemID": 11},  # the same recipe, tradable
            {"ID": 3, "TriggerType": 6, "SpellID": 701, "ParentItemID": 12},  # binds on pickup
            {"ID": 4, "TriggerType": 6, "SpellID": 702, "ParentItemID": 13},  # a quest item
            {"ID": 5, "TriggerType": 6, "SpellID": 703, "ParentItemID": 14},  # never binds
            {"ID": 7, "TriggerType": 6, "SpellID": 705, "ParentItemID": 15},  # an item the game lacks
            {"ID": 8, "TriggerType": 6, "SpellID": 706, "ParentItemID": 16},  # binds on pickup, a vendor's
            {"ID": 6, "TriggerType": 0, "SpellID": 704, "ParentItemID": 10},  # a Use effect teaches nothing
        ],
    )
    bonding = {10: 1, 11: 2, 12: 1, 13: 4, 14: 0, 16: 1}
    assert ingest.learn_sources({"ItemEffect": effects}, bonding) == {
        700: "recipe",
        701: "bop",
        702: "bop",
        703: "recipe",
        706: "bop",
    }
    # a recipe a vendor sells is there for anyone to buy, bound or not: only looted ones stay "bop"
    assert ingest.learn_sources({"ItemEffect": effects}, bonding, frozenset({16, 99}))[706] == "recipe"


def test_build_db_loads_the_items_teaching_each_recipe(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ri = schema.recipe_items
    assert [tuple(r) for r in conn.execute(select(ri.c.spell_id, ri.c.item_id))] == [(900, 3)]


def test_recipe_items_are_every_item_the_game_has_teaching_a_spell(tmp_path: Path) -> None:
    effects = write_csv(
        tmp_path / "ItemEffect.csv",
        ["ID", "TriggerType", "SpellID", "ParentItemID"],
        [
            {"ID": 1, "TriggerType": 6, "SpellID": 700, "ParentItemID": 11},
            {"ID": 2, "TriggerType": 6, "SpellID": 700, "ParentItemID": 10},  # the other faction's copy
            {"ID": 3, "TriggerType": 6, "SpellID": 701, "ParentItemID": 15},  # an item the game lacks
            {"ID": 4, "TriggerType": 0, "SpellID": 702, "ParentItemID": 10},  # a Use effect
        ],
    )
    assert ingest.recipe_items({"ItemEffect": effects}, {10: 1, 11: 2}) == [(700, 10), (700, 11)]


def test_build_db_loads_where_recipe_items_come_from(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    columns = ["item_id", "kind", "name", "zone", "side", "chance", "count", "levels", "limited"]
    sources = write_csv(
        tmp_path / "recipe_item_sources.csv",
        columns,
        [
            {
                "item_id": 3,
                "kind": "vendor",
                "name": "Kendor",
                "zone": "Stormwind",
                "side": "alliance",
                "chance": 0,
                "count": 0,
                "levels": "",
                "limited": 1,
            },
            {
                "item_id": 3,
                "kind": "drop",
                "name": "Defias Pillager",
                "zone": "Westfall",
                "side": "",
                "chance": 2.5,
                "count": 0,
                "levels": "",
                "limited": 0,
            },
        ],
    )
    ingest.build_db(db2_paths, conn, FOREVER, sources_csv=sources)
    t = schema.item_sources
    rows = conn.execute(select(t.c.seq, t.c.kind, t.c.name, t.c.chance, t.c.limited).order_by(t.c.seq)).all()
    assert [tuple(r) for r in rows] == [
        (0, "vendor", "Kendor", 0.0, True),
        (1, "drop", "Defias Pillager", 2.5, False),
    ]

    bad = write_csv(
        tmp_path / "bad.csv", columns, [{"item_id": 3, "kind": "stolen", "side": "", "chance": 0}]
    )
    with pytest.raises(ValueError, match="stolen"):
        ingest.item_sources(bad, FOREVER)


def test_build_db_counts_a_vendors_bind_on_pickup_recipe_as_a_normal_one(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    def source(vendor_csv: Path | None = None, vendor_recipes_csv: Path | None = None) -> str:
        ingest.build_db(
            db2_paths, conn, FOREVER, vendor_csv=vendor_csv, vendor_recipes_csv=vendor_recipes_csv
        )
        return str(conn.execute(select(schema.recipes.c.source)).scalar_one())

    sparse = db2_paths["ItemSparse"]
    rows = list(ingest._rows(sparse))
    for r in rows:
        if r["ID"] == "3":
            r["Bonding"] = "1"  # the item teaching the robe now binds on pickup
    write_csv(sparse, list(rows[0]), [dict(r) for r in rows])
    assert source() == "bop"
    limited = write_csv(
        tmp_path / "vendor_recipes.csv", ["item_id", "name"], [{"item_id": 3, "name": "Robe"}]
    )
    assert source(vendor_recipes_csv=limited) == "recipe"
    assert source(vendor_csv=limited) == "recipe"  # as does one with unlimited stock


def test_build_db_charges_a_trainers_recipe_what_the_trainer_asks(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    fees = write_csv(
        tmp_path / "trainer_costs.csv",
        ["spell_id", "cost", "req_skill"],
        [{"spell_id": 900, "cost": 600, "req_skill": 40}],
    )

    def recipe() -> tuple[str, int, int]:
        ingest.build_db(db2_paths, conn, FOREVER, trainer_costs_csv=fees)
        row = conn.execute(
            select(schema.recipes.c.source, schema.recipes.c.train_cost, schema.recipes.c.learn_skill)
        ).one()
        return str(row.source), int(row.train_cost), int(row.learn_skill)

    assert recipe() == ("recipe", 0, 50)  # an item teaches it: no trainer's fee, learned at the item's rank
    effects = db2_paths["ItemEffect"]
    rows: list[dict[str, object]] = [
        dict(r, TriggerType="0") if r["SpellID"] == "900" else dict(r) for r in ingest._rows(effects)
    ]
    write_csv(effects, list(rows[0]), rows)  # no item teaches the robe any more: a trainer does
    assert recipe() == ("trainer", 600, 40)  # at the skill the trainer asks for
    # a recipe that comes with the profession: no trainer lists it, and it is known from the first point
    abilities = db2_paths["SkillLineAbility"]
    rows = [dict(r, AcquireMethod="1") if r["Spell"] == "900" else dict(r) for r in ingest._rows(abilities)]
    write_csv(abilities, list(rows[0]), rows)
    assert recipe() == ("trainer", 0, 1)
    assert ingest.trainer_costs(None) == {}
    # a trainer_costs.csv from before the skill column still reads
    old = write_csv(tmp_path / "old.csv", ["spell_id", "cost"], [{"spell_id": 900, "cost": 600}])
    assert ingest.trainer_costs(old) == {900: (600, 0)}


def test_yellow_shifts_are_how_far_the_game_moved_a_recipe_down_against_the_reference(tmp_path: Path) -> None:
    header = ["ID", "Spell", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh"]

    def abilities(name: str, rows: list[tuple[int, int, int]]) -> Path:
        return write_csv(
            tmp_path / name,
            header,
            [
                {
                    "ID": i,
                    "Spell": spell,
                    "TrivialSkillLineRankLow": low,
                    "TrivialSkillLineRankHigh": low + 10,
                }
                for i, (spell, low, _) in enumerate(rows)
            ],
        )

    game = abilities("game.csv", [(1, 110, 0), (2, 100, 0), (3, 0, 0), (4, 70, 0), (5, 50, 0), (5, 60, 0)])
    reference = abilities(
        "ref.csv", [(1, 135, 0), (2, 100, 0), (3, 40, 0), (4, 55, 0), (5, 80, 0), (6, 9, 0)]
    )
    # Bolt of Silk Cloth's yellow moved 135 -> 110; unmoved, no thresholds (0) or moved up: nothing; a spell
    # on several rows counts its lowest yellow on each side
    assert ingest.yellow_shifts(game, reference) == {1: -25, 5: -30}


def test_build_db_learns_a_trainers_recipe_earlier_by_its_yellow_shift(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    effects = db2_paths["ItemEffect"]
    rows: list[dict[str, object]] = [
        dict(r, TriggerType="0") if r["SpellID"] == "900" else dict(r) for r in ingest._rows(effects)
    ]
    write_csv(effects, list(rows[0]), rows)  # a trainer teaches the robe

    def learned(req: int, shift: int) -> int:
        fees = write_csv(
            tmp_path / "trainer_costs.csv",
            ["spell_id", "cost", "req_skill", "yellow_shift"],
            [{"spell_id": 900, "cost": 600, "req_skill": req, "yellow_shift": shift}],
        )
        ingest.build_db(db2_paths, conn, FOREVER, trainer_costs_csv=fees)
        return int(conn.execute(select(schema.recipes.c.learn_skill)).scalar_one())

    assert learned(125, -25) == 100  # the game moved its colours down: the trainer teaches it as much earlier
    assert learned(125, 0) == 125
    assert learned(20, -25) == 1  # never below the first point
    assert learned(0, -25) == 0  # nothing said where it is learned: still nothing
    assert ingest.trainer_costs(write_csv(tmp_path / "t.csv", ["spell_id", "cost", "req_skill"], [
        {"spell_id": 900, "cost": 600, "req_skill": 125}
    ])) == {900: (600, 125)}  # fmt: skip


def test_craft_stations_are_the_foci_profession_spells_need(db2_paths: dict[str, Path]) -> None:
    assert ingest.craft_stations(db2_paths) == {1: "Anvil"}  # the robe's; the forge and fire go unused


def test_zone_boxes_are_the_whole_map_assignments(tmp_path: Path) -> None:
    uma = write_csv(
        tmp_path / "UiMapAssignment.csv",
        [
            "UiMin_0",
            "UiMin_1",
            "UiMax_0",
            "UiMax_1",
            "Region_0",
            "Region_1",
            "Region_2",
            "Region_3",
            "Region_4",
            "Region_5",
            "ID",
            "UiMapID",
            "MapID",
            "AreaID",
        ],
        [
            {
                "UiMin_0": 0,
                "UiMin_1": 0,
                "UiMax_0": 1,
                "UiMax_1": 1,
                "Region_0": 1000,
                "Region_1": -5000,
                "Region_2": -1e6,
                "Region_3": 2000,
                "Region_4": -4000,
                "Region_5": 1e6,
                "ID": 1,
                "UiMapID": 1454,
                "MapID": 1,
                "AreaID": 1637,
            },
            # a corner of a map (a sub-zone overlay): not the whole map
            {
                "UiMin_0": 0.5,
                "UiMin_1": 0,
                "UiMax_0": 1,
                "UiMax_1": 1,
                "Region_0": 0,
                "Region_1": 0,
                "Region_2": 0,
                "Region_3": 1,
                "Region_4": 1,
                "Region_5": 1,
                "ID": 2,
                "UiMapID": 1454,
                "MapID": 1,
                "AreaID": 1637,
            },
        ],
    )
    names = write_csv(tmp_path / "UiMap.csv", ["Name_lang", "ID"], [{"Name_lang": "Orgrimmar", "ID": 1454}])
    assert ingest.zone_boxes(uma, names) == [(1, "Orgrimmar", 1000.0, -5000.0, 2000.0, -4000.0, 1637)]


def test_build_db_without_cast_time_or_focus_reads_zero(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    paths = {
        **db2_paths,
        "SpellMisc": write_csv(
            tmp_path / "NoMisc.csv", ["ID", "SpellID", "CastingTimeIndex", "DifficultyID"], []
        ),
        "SpellCastingRequirements": write_csv(
            tmp_path / "NoReq.csv", ["ID", "SpellID", "RequiresSpellFocus"], []
        ),
    }
    ingest.build_db(paths, conn, FOREVER)
    recipe = conn.execute(select(schema.recipes)).one()
    assert (recipe.cast_time_ms, recipe.station) == (0, "")


def test_build_db_gives_no_skill_points_without_thresholds_or_skill_ups(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    def skill_ups(**changes: object) -> int:
        abilities = db2_paths["SkillLineAbility"]
        rows: list[dict[str, object]] = [
            {**r, **changes} if r["Spell"] == "900" else dict(r) for r in ingest._rows(abilities)
        ]
        write_csv(abilities, list(rows[0]), rows)
        ingest.build_db(db2_paths, conn, FOREVER)
        return int(conn.execute(select(schema.recipes.c.num_skill_ups)).scalar_one())

    assert skill_ups() == 1  # a client without the column: a point a craft
    assert skill_ups(NumSkillUps="1") == 1
    assert skill_ups(NumSkillUps="0") == 0  # DB2 says it gives none
    # no thresholds at all: the game shows it grey (Forever's First Aid Kit, camp furnishings)
    assert skill_ups(NumSkillUps="1", TrivialSkillLineRankLow="0", TrivialSkillLineRankHigh="0") == 0


def test_build_db_loads_the_longest_cooldown(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    header = ["ID", "DifficultyID", "CategoryRecoveryTime", "RecoveryTime", "StartRecoveryTime", "SpellID"]
    rows: list[dict[str, object]] = [
        {"ID": 1, "DifficultyID": 1, "CategoryRecoveryTime": 0, "RecoveryTime": 999, "SpellID": 900},
        {
            "ID": 2,
            "DifficultyID": 0,
            "CategoryRecoveryTime": 3_600_000,
            "RecoveryTime": 600_000,
            "SpellID": 900,
        },
    ]
    paths = {**db2_paths, "SpellCooldowns": write_csv(tmp_path / "SpellCooldowns.csv", header, rows)}
    ingest.build_db(paths, conn, FOREVER)
    assert conn.execute(select(schema.recipes.c.cooldown_ms)).scalar_one() == 3_600_000
    # the normal difficulty's row wins whatever the order
    as_read = [{k: str(v) for k, v in r.items()} for r in rows]
    assert ingest.cooldowns(reversed(as_read)) == {900: 3_600_000}
    # without the table (a client that doesn't serve it) nothing has a cooldown
    ingest.build_db(db2_paths, conn, FOREVER)
    assert conn.execute(select(schema.recipes.c.cooldown_ms)).scalar_one() == 0


def test_build_db_loads_tooltip_fields(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    robe = item(conn, 3)._mapping
    assert {k: robe[k] for k in TOOLTIP_COLUMNS} == {
        "bonding": 2,
        "required_level": 12,
        "inventory_type": 20,
        "item_delay": 0,
        "container_slots": 0,
        "subclass_name": "Cloth",
        "required_skill": "Tailoring",
        "required_skill_rank": 50,
        "description": "Soft and green.",
        "icon": "inv_chest_cloth_39",
        "armor": 46,
        "dmg_min": 0,
        "dmg_max": 0,
        "dps": 0.0,
        "stats": '["+9 Intellect"]',
        "effects": json.dumps(ROBE_EFFECTS),
    }
    assert (item(conn, 1).icon, item(conn, 2).icon) == ("inv_fabric_linen_01", None)  # 2: not in the manifest
    linen = item(conn, 1)
    assert (linen.subclass_name, linen.required_skill, linen.description) == (None, None, None)
    assert (linen.armor, linen.dps, linen.stats, linen.effects) == (0, 0.0, "[]", "[]")


SPELL_POWER_LINE = "Increases damage and healing done by magical spells and effects by up to 6."
ROBE_EFFECTS = [
    {"trigger": "Equip", "text": SPELL_POWER_LINE},
    {"trigger": "Use", "text": "Restores 1050 to 1750 health. (2 Min Cooldown)"},
]

TOOLTIP_COLUMNS = {
    "bonding",
    "required_level",
    "inventory_type",
    "item_delay",
    "container_slots",
    "subclass_name",
    "required_skill",
    "required_skill_rank",
    "description",
    "icon",
    "armor",
    "dmg_min",
    "dmg_max",
    "dps",
    "stats",
    "effects",
}


def _robe_row(db2_paths: dict[str, Path], **changes: object) -> tuple[list[str], dict[str, object]]:
    """The fixture's ItemSparse header and its Green Robe row with `changes` applied."""
    rows = _read(db2_paths["ItemSparse"])
    robe: dict[str, object] = {**next(r for r in rows if r["ID"] == "3"), **changes}
    return list(rows[0]), robe


def test_build_db_loads_weapon_damage(db2_paths: dict[str, Path], conn: Connection, tmp_path: Path) -> None:
    # A rare one-hand dagger (subclass 15) at ilvl 20: 10 DPS at speed 1.8 with a 40% spread is 14-22.
    header, dagger = _robe_row(
        db2_paths,
        Display_lang="Dagger",
        OverallQualityID=3,
        InventoryType=13,
        ItemDelay=1800,
        DmgVariance=0.4,
    )
    paths = {
        **db2_paths,
        "Item": write_csv(
            tmp_path / "Dagger.csv",
            ["ID", "ClassID", "SubclassID", "IconFileDataID"],
            [{"ID": 3, "ClassID": 2, "SubclassID": 15}],
        ),
        "ItemSparse": write_csv(tmp_path / "DaggerSparse.csv", header, [dagger]),
        "ItemDamageOneHand": write_csv(
            tmp_path / "ItemDamageOneHand.csv",
            ["ID", "ItemLevel", "Quality_0", "Quality_1", "Quality_2", "Quality_3"],
            [{"ID": 20, "ItemLevel": 20, "Quality_2": 8.0, "Quality_3": 10.0}],
        ),
    }
    ingest.build_db(paths, conn, FOREVER)
    got = item(conn, 3)
    assert (got.armor, got.dmg_min, got.dmg_max, got.dps, got.stats) == (0, 14, 22, 10.0, "[]")


def test_build_db_reads_the_no_disenchant_flag(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    header, robe = _robe_row(db2_paths, Flags_0=0x8000 | 0x40)  # ITEM_FLAG_NO_DISENCHANT, plus another
    paths = {**db2_paths, "ItemSparse": write_csv(tmp_path / "NoDE.csv", [*header, "Flags_0"], [robe])}
    ingest.build_db(paths, conn, FOREVER)
    assert item(conn, 3).disenchantable is False


def test_build_db_items_are_disenchantable_without_the_flag(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)  # the fixture has no Flags_0 column
    assert item(conn, 3).disenchantable is True


def test_build_db_without_stat_tables_reads_empty(db2_paths: dict[str, Path], conn: Connection) -> None:
    gone = ("RandPropPoints", "ItemArmorTotal", "ItemEffect", "Spell")
    paths = {k: v for k, v in db2_paths.items() if k not in gone}
    ingest.build_db(paths, conn, FOREVER)
    robe = item(conn, 3)
    assert (robe.armor, robe.stats, robe.effects) == (0, "[]", "[]")


def test_build_db_reads_tbc_item_effects_by_parent_item(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    # TBC's ItemEffect names the item itself and there is no ItemXItemEffect; a chance-on-hit effect
    # and an equip effect with a cooldown (not shown on Equip lines).
    paths = {
        **db2_paths,
        "ItemEffect": write_csv(
            tmp_path / "TbcItemEffect.csv",
            ["ID", "LegacySlotIndex", "TriggerType", "CoolDownMSec", "SpellID", "ParentItemID"],
            [
                {
                    "ID": 1,
                    "LegacySlotIndex": 1,
                    "TriggerType": 1,
                    "CoolDownMSec": 5000,
                    "SpellID": 950,
                    "ParentItemID": 3,
                },
                {"ID": 2, "LegacySlotIndex": 0, "TriggerType": 2, "SpellID": 950, "ParentItemID": 3},
            ],
        ),
    }
    del paths["ItemXItemEffect"]
    ingest.build_db(paths, conn, "tbc", max_level=70)
    assert json.loads(item(conn, 3, "tbc").effects)[1:] == [
        {"trigger": "Chance on hit", "text": "Restores 1050 to 1750 health."},
        {"trigger": "Equip", "text": "Restores 1050 to 1750 health."},
    ]


def test_spell_data_follows_references_and_prefers_the_normal_difficulty(
    db2_paths: dict[str, Path], tmp_path: Path
) -> None:
    paths = {
        **db2_paths,
        "Spell": write_csv(
            tmp_path / "Spell2.csv",
            ["ID", "Description_lang"],
            [
                {"ID": 950, "Description_lang": "$@spelldesc951 for $951d."},
                {"ID": 951, "Description_lang": "Heals $s1"},
                {"ID": 952, "Description_lang": "unrelated"},
            ],
        ),
        "SpellEffect": write_csv(
            tmp_path / "SpellEffect2.csv",
            ["ID", "SpellID", "EffectIndex", "EffectBasePointsF", "DifficultyID", "EffectAuraPeriod"],
            [
                {"ID": 1, "SpellID": 951, "EffectBasePointsF": 5, "DifficultyID": 2},
                {"ID": 2, "SpellID": 951, "EffectBasePointsF": 7, "DifficultyID": 0},
                {"ID": 3, "SpellID": 951, "EffectBasePointsF": 9, "DifficultyID": 3},
            ],
        ),
        "SpellMisc": write_csv(
            tmp_path / "SpellMisc2.csv",
            ["ID", "SpellID", "DurationIndex", "DifficultyID", "CastingTimeIndex"],
            [{"ID": 1, "SpellID": 951, "DurationIndex": 9}],
        ),
    }
    data = ingest.spell_data(paths, [950])
    assert set(data.descriptions) == {950, 951}
    assert data.effects[951][0].base == 7
    assert data.durations == {951: 30000}
    assert spelltext.expand(data.descriptions[950], 950, data) == "Heals 7 for 30 sec."


def test_build_db_shows_ratings_raw_at_other_level_caps(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path
) -> None:
    header, robe = _robe_row(
        db2_paths, StatModifier_bonusStat_0=32, StatPercentEditor_0=7000
    )  # 21 crit rating
    paths = {**db2_paths, "ItemSparse": write_csv(tmp_path / "Rating.csv", header, [robe])}
    ingest.build_db(paths, conn, "tbc", max_level=70)
    assert (
        json.loads(item(conn, 3, "tbc").effects)[0]["text"] == "Increases your critical strike rating by 21."
    )
    ingest.build_db(paths, conn, FOREVER, max_level=60)
    assert (
        json.loads(item(conn, 3).effects)[0]["text"]
        == "Improves your chance to get a critical strike by 1.5%."
    )


def _read(path: Path) -> list[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def test_build_db_preserves_prices_and_other_versions(db2_paths: dict[str, Path], conn: Connection) -> None:
    ah = set_prices(conn, {1: 45})
    ingest.build_db(db2_paths, conn, "tbc")
    ingest.build_db(db2_paths, conn, FOREVER)
    ingest.build_db(db2_paths, conn, FOREVER)  # idempotent rebuild
    assert prices.load_current(conn, ah) == {1: 45}
    assert count(conn, "recipes") == 2  # one per version
    assert store.load_market(conn, "tbc", None).items.keys() == {1, 2, 3}


def test_build_db_loads_disenchant_csv(db2_paths: dict[str, Path], conn: Connection, tmp_path: Path) -> None:
    de = write_csv(
        tmp_path / "de.csv",
        [
            "item_class",
            "quality",
            "min_ilvl",
            "max_ilvl",
            "result_item_id",
            "chance",
            "min_count",
            "max_count",
        ],
        [
            {
                "item_class": 4,
                "quality": 2,
                "min_ilvl": 15,
                "max_ilvl": 25,
                "result_item_id": 9,
                "chance": 0.75,
                "min_count": 1,
                "max_count": 2,
            }
        ],
    )
    assert ingest.build_db(db2_paths, conn, FOREVER, de)["disenchant_rows"] == 1
    ((row),) = store.load_market(conn, FOREVER, None).disenchant
    assert (row.result_item_id, row.chance, row.max_count) == (9, 0.75, 2)


def test_build_db_loads_vendor_items(db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path) -> None:
    assert ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)["vendor_items"] == 2
    assert sorted(conn.execute(select(schema.vendor_items.c.item_id)).scalars()) == [2, 99]
    thread = item(conn, 2)
    assert (thread.buy_price, thread.buy_count) == (51, 5)
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)  # rebuild replaces, not appends
    assert count(conn, "vendor_items") == 2


def test_int_parsing_is_forgiving() -> None:
    assert ingest._int("12") == 12
    assert ingest._int("3.0") == 3
    assert ingest._int("") == 0
    assert ingest._int(None, 7) == 7
    assert ingest._int("abc", 5) == 5


def test_update_downloads_builds_and_records_build(
    db2_paths: dict[str, Path], conn: Connection, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[tuple[str, Path]] = []

    def fake_download_all(build: str, cache_dir: Path) -> dict[str, Path]:
        calls.append((build, cache_dir))
        return db2_paths

    monkeypatch.setattr(ingest, "download_all", fake_download_all)
    stats = ingest.update(conn, FOREVER, "1.2.3.4", tmp_path / "cache")
    assert calls == [("1.2.3.4", tmp_path / "cache")]
    assert stats["recipes"] == 1
    assert db.get_build(conn, FOREVER) == "1.2.3.4"


@pytest.mark.parametrize(
    ("row", "count"),
    [
        ({"EffectBasePointsF": "3"}, 3),  # Forever: the (average) count as a float
        (
            {"EffectBasePointsF": "0", "EffectBasePoints": "2", "EffectDieSides": "1"},
            3,
        ),  # TBC Thorium Grenade
        ({"EffectBasePointsF": "0", "EffectBasePoints": "199", "EffectDieSides": "1"}, 200),  # Thorium Shells
        (
            {"EffectBasePointsF": "0", "EffectBasePoints": "0", "EffectDieSides": "5"},
            3,
        ),  # Heavy Dynamite: 1-5
        ({"EffectBasePointsF": "0", "EffectBasePoints": "1", "EffectDieSides": "3"}, 3),  # Iron Grenade: 2-4
        ({"EffectBasePointsF": "0", "EffectBasePoints": "0", "EffectDieSides": "0"}, 1),
        ({"EffectBasePointsF": ""}, 1),  # no count columns at all
    ],
)
def test_output_count_from_either_clients_spell_effect(row: dict[str, str], count: int) -> None:
    assert ingest.output_count(row) == count


def test_build_db_reads_tbc_style_output_counts(db2_paths: dict[str, Path], conn: Connection) -> None:
    write_csv(
        db2_paths["SpellEffect"],
        [
            "ID",
            "Effect",
            "EffectItemType",
            "EffectBasePointsF",
            "EffectBasePoints",
            "EffectDieSides",
            "SpellID",
        ],
        [
            {
                "ID": 1,
                "Effect": 24,
                "EffectItemType": 3,
                "EffectBasePointsF": 0,
                "EffectBasePoints": 2,
                "EffectDieSides": 1,
                "SpellID": 900,
            }
        ],
    )
    ingest.build_db(db2_paths, conn, FOREVER)
    assert conn.execute(select(schema.recipes.c.output_count)).scalar_one() == 3


def _extend_csv(path: Path, rows: list[dict[str, object]]) -> Path:
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        header = list(reader.fieldnames or [])
        existing: list[dict[str, object]] = list(reader)
    header += [k for r in rows for k in r if k not in header]
    return write_csv(path, list(dict.fromkeys(header)), [*existing, *rows])


DE_HEADER = [
    "item_class",
    "quality",
    "min_ilvl",
    "max_ilvl",
    "result_item_id",
    "chance",
    "min_count",
    "max_count",
]


@pytest.fixture
def essence_paths(db2_paths: dict[str, Path]) -> dict[str, Path]:
    """Adds 10 Lesser Magic Essence and 11 Greater Magic Essence, each with a Use spell turning it into the
    other the way the client does (the used item is consumed: 1 lesser + 2 reagents -> 1 greater; 1 greater
    -> 3 lesser), and Linen Cloth (1) a consumed Use spell creating thread: not enchanting materials."""
    _extend_csv(db2_paths["Item"], [{"ID": 10, "ClassID": 7}, {"ID": 11, "ClassID": 7}])
    _extend_csv(
        db2_paths["ItemSparse"],
        [
            {"ID": 10, "Display_lang": "Lesser Magic Essence", "OverallQualityID": 2, "Stackable": 20},
            {"ID": 11, "Display_lang": "Greater Magic Essence", "OverallQualityID": 2, "Stackable": 20},
        ],
    )
    _extend_csv(
        db2_paths["SpellName"],
        [{"ID": 960, "Name_lang": "Greater Magic Essence"}, {"ID": 961, "Name_lang": "Lesser Magic Essence"}],
    )
    _extend_csv(
        db2_paths["SpellEffect"],
        [
            {"ID": 10, "Effect": 24, "EffectItemType": 11, "EffectBasePointsF": 1, "SpellID": 960},
            {"ID": 11, "Effect": 24, "EffectItemType": 10, "EffectBasePointsF": 3, "SpellID": 961},
            {"ID": 12, "Effect": 24, "EffectItemType": 2, "EffectBasePointsF": 1, "SpellID": 962},
        ],
    )
    _extend_csv(
        db2_paths["SpellReagents"], [{"ID": 10, "SpellID": 960, "Reagent_0": 10, "ReagentCount_0": 2}]
    )
    _extend_csv(
        db2_paths["ItemEffect"],
        [
            {"ID": 10, "TriggerType": 0, "Charges": -1, "SpellID": 960},
            {"ID": 11, "TriggerType": 0, "Charges": -1, "SpellID": 961},
            {"ID": 12, "TriggerType": 0, "Charges": -1, "SpellID": 962},
        ],
    )
    _extend_csv(
        db2_paths["ItemXItemEffect"],
        [
            {"ID": 10, "ItemEffectID": 10, "ItemID": 10},
            {"ID": 11, "ItemEffectID": 11, "ItemID": 11},
            {"ID": 12, "ItemEffectID": 12, "ItemID": 1},
        ],
    )
    return db2_paths


@pytest.fixture
def essence_de(tmp_path: Path) -> Path:
    """Robes disenchant into either essence."""
    return write_csv(
        tmp_path / "essence_de.csv",
        DE_HEADER,
        [
            {
                "item_class": 4,
                "quality": 2,
                "min_ilvl": 5,
                "max_ilvl": 15,
                "result_item_id": 10,
                "chance": 0.2,
                "min_count": 1,
                "max_count": 2,
            },
            {
                "item_class": 4,
                "quality": 2,
                "min_ilvl": 16,
                "max_ilvl": 20,
                "result_item_id": 11,
                "chance": 0.2,
                "min_count": 1,
                "max_count": 2,
            },
        ],
    )


def test_build_db_loads_essence_conversions(
    essence_paths: dict[str, Path], essence_de: Path, conn: Connection
) -> None:
    assert ingest.build_db(essence_paths, conn, FOREVER, essence_de)["recipes"] == 3
    market = store.load_market(conn, FOREVER, None)
    conversions = {r.spell_id: r for r in market.recipes if r.kind == "convert"}
    assert sorted(conversions) == [960, 961]
    up, down = conversions[960], conversions[961]
    assert (up.id, up.name, up.skill_name, up.output_item_id, up.output_count, up.reagents) == (
        ingest.CONVERSION_ID_BASE + 960,
        "Greater Magic Essence",
        "",
        11,
        1,
        ((10, 3),),  # the essence used and the two more the spell takes
    )
    assert (down.output_item_id, down.output_count, down.reagents) == (10, 3, ((11, 1),))
    (craft,) = [r for r in market.recipes if r.kind == "craft"]
    assert craft.id == 100


def test_build_db_has_no_conversions_without_disenchant_results(
    essence_paths: dict[str, Path], conn: Connection
) -> None:
    assert ingest.build_db(essence_paths, conn, FOREVER)["recipes"] == 1


def test_a_use_spell_not_consuming_its_item_is_no_conversion(
    essence_paths: dict[str, Path], essence_de: Path, conn: Connection
) -> None:
    # Greater's Use effect keeps its item (Charges 0)
    with open(essence_paths["ItemEffect"], newline="", encoding="utf-8") as f:
        rows: list[dict[str, object]] = list(csv.DictReader(f))
    for r in rows:
        if r["ID"] == "11":
            r["Charges"] = 0
    write_csv(essence_paths["ItemEffect"], list(rows[0]), rows)
    ingest.build_db(essence_paths, conn, FOREVER, essence_de)
    spells: list[int] = list(
        conn.execute(select(schema.recipes.c.spell_id).where(schema.recipes.c.kind == "convert")).scalars()
    )
    assert spells == [960]


@pytest.fixture
def enchant_paths(db2_paths: dict[str, Path]) -> dict[str, Path]:
    """Adds Enchanting with two spells that enchant an item (SpellEffect 53) and create none: 970 takes 2
    Linen Cloth, 971 has no reagents."""
    _extend_csv(db2_paths["SkillLine"], [{"ID": 333, "DisplayName_lang": "Enchanting"}])
    _extend_csv(
        db2_paths["SkillLineAbility"],
        [
            {
                "ID": 110,
                "SkillLine": 333,
                "Spell": 970,
                "MinSkillLineRank": 1,
                "TrivialSkillLineRankLow": 20,
                "TrivialSkillLineRankHigh": 60,
            },
            {"ID": 111, "SkillLine": 333, "Spell": 971},
        ],
    )
    _extend_csv(db2_paths["SpellName"], [{"ID": 970, "Name_lang": "Enchant Bracer - Minor Health"}])
    _extend_csv(
        db2_paths["SpellEffect"],
        [{"ID": 20, "Effect": 53, "SpellID": 970}, {"ID": 21, "Effect": 53, "SpellID": 971}],
    )
    _extend_csv(db2_paths["SpellReagents"], [{"ID": 20, "SpellID": 970, "Reagent_0": 1, "ReagentCount_0": 2}])
    return db2_paths


def test_build_db_loads_enchants_as_recipes_making_no_item(
    enchant_paths: dict[str, Path], conn: Connection
) -> None:
    assert ingest.build_db(enchant_paths, conn, FOREVER)["recipes"] == 2
    market = store.load_market(conn, FOREVER, None)
    (enchant,) = [r for r in market.recipes if r.kind == "enchant"]
    assert (enchant.id, enchant.spell_id, enchant.name, enchant.skill_name) == (
        110,
        970,
        "Enchant Bracer - Minor Health",
        "Enchanting",
    )
    assert (enchant.output_item_id, enchant.output_count, enchant.reagents) == (0, 1, ((1, 2),))
    assert (enchant.trivial_low, enchant.trivial_high, enchant.source) == (20, 60, "trainer")
