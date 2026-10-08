from pathlib import Path

import pytest
from sqlalchemy import Connection, insert, update

from altarmy_site import altarmy, ingest, itemstats, schema, store

from .conftest import FOREVER, ME, scanned, set_prices
from .test_altarmy import ALTARMY_SV


def test_load_item_details_returns_requested_items(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    got = store.load_item_details(conn, FOREVER, [3, 1, 42])
    assert set(got) == {1, 3}
    robe = got[3]
    assert (robe.name, robe.quality, robe.subclass_name, robe.required_skill) == (
        "Green Robe",
        2,
        "Cloth",
        "Tailoring",
    )
    assert got[1].icon == "inv_fabric_linen_01"
    assert (robe.armor, robe.stats) == (46, ("+9 Intellect",))
    assert (robe.effects[0].trigger, robe.effects[0].text[:36]) == (
        "Equip",
        "Increases damage and healing done by",
    )
    assert robe.effects[1] == itemstats.Effect("Use", "Restores 1050 to 1750 health. (2 Min Cooldown)")
    assert (got[1].armor, got[1].dps, got[1].stats, got[1].effects) == (0, 0.0, (), ())
    assert store.load_item_details(conn, FOREVER, []) == {}


def test_load_item_details_tolerates_bad_json(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    t = schema.items
    conn.execute(update(t).where(t.c.id == 3).values(stats="not json", effects='[{"trigger": "Use"}, 5]'))
    robe = store.load_item_details(conn, FOREVER, [3])[3]
    assert (robe.stats, robe.effects) == ((), ())


def test_load_recipe_items_lists_teaching_items_with_their_places(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    src = {
        "game_version": FOREVER,
        "item_id": 3,
        "zone": "",
        "side": "",
        "chance": 0.0,
        "levels": "",
        "limited": False,
    }
    conn.execute(
        insert(schema.item_sources),
        [
            {**src, "seq": 1, "kind": "more", "name": "", "count": 4},
            {
                **src,
                "seq": 0,
                "kind": "drop",
                "name": "Defias Pillager",
                "zone": "Westfall",
                "chance": 2.5,
                "count": 0,
            },
        ],
    )
    got = store.load_recipe_items(conn, FOREVER, [900, 901])
    assert got == {
        900: [
            store.RecipeItem(
                3,
                "Green Robe",
                (
                    store.Place("drop", "Defias Pillager", "Westfall", "", 2.5, 0, "", False),
                    store.Place("more", "", "", "", 0.0, 4, "", False),
                ),
            )
        ]
    }


def test_load_item_details_handles_many_ids(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    assert set(store.load_item_details(conn, FOREVER, range(5000))) == {1, 2, 3}


def test_load_market_prices_vendor_items_per_unit(
    db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    items = store.load_market(conn, FOREVER, None).items
    assert items[2].vendor_price == 11  # 51c per stack of 5, rounded up
    assert items[1].vendor_price is None  # not sold by vendors
    assert (items[1].stack_size, items[3].stack_size) == (20, 1)  # robe: no Stackable -> 1


def test_load_market_keeps_spell_ids(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    (recipe,) = store.load_market(conn, FOREVER, None).recipes
    assert recipe.spell_id == 900
    assert (recipe.trivial_low, recipe.trivial_high) == (30, 60)
    assert (recipe.cast_time_ms, recipe.station) == (3000, "anvil")
    assert (recipe.num_skill_ups, recipe.cooldown_ms) == (1, 0)


def test_characters_round_trip_and_replace(conn: Connection) -> None:
    chars = altarmy.parse_characters(ALTARMY_SV)
    store.save_characters(conn, ME, FOREVER, chars)
    store.save_characters(conn, ME, "tbc", chars[:2])
    assert store.load_characters(conn, ME, FOREVER) == chars
    assert any(c.talents for c in store.load_characters(conn, ME, FOREVER))  # Legacy talents too
    assert any(c.reputations for c in store.load_characters(conn, ME, FOREVER))  # and standings
    store.save_characters(conn, ME, FOREVER, chars[:1])
    assert store.load_characters(conn, ME, FOREVER) == chars[:1]
    assert store.load_characters(conn, ME, "tbc") == chars[:2]  # each version has its own characters


def test_ah_blocked_round_trip_survives_ingest(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    assert store.load_ah_blocked(conn, ME, FOREVER) == []
    store.set_ah_blocked(conn, ME, FOREVER, 3, True)
    store.set_ah_blocked(conn, ME, FOREVER, 3, True)  # already there: kept once
    store.set_ah_blocked(conn, ME, FOREVER, 1, True)
    ingest.build_db(db2_paths, conn, FOREVER)
    assert sorted(i for i, _ in store.load_ah_blocked(conn, ME, FOREVER)) == [1, 3]
    assert store.load_ah_blocked(conn, ME, "tbc") == []
    store.set_ah_blocked(conn, ME, FOREVER, 1, False)
    store.set_ah_blocked(conn, ME, FOREVER, 42, False)  # not there: nothing to do
    ((item_id, added_at),) = store.load_ah_blocked(conn, ME, FOREVER)
    assert item_id == 3
    assert len(added_at) == len("2026-09-24 20:53:16")  # UTC text


def test_favorites_round_trip_survives_ingest(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    assert store.load_favorites(conn, ME, FOREVER) == []
    store.set_favorite(conn, ME, FOREVER, 7, True)
    store.set_favorite(conn, ME, FOREVER, 7, True)  # already there: kept once
    store.set_favorite(conn, ME, FOREVER, 8, True)
    ingest.build_db(db2_paths, conn, FOREVER)
    assert sorted(i for i, _ in store.load_favorites(conn, ME, FOREVER)) == [7, 8]
    assert store.load_favorites(conn, ME, "tbc") == []
    store.set_favorite(conn, ME, FOREVER, 8, False)
    store.set_favorite(conn, ME, FOREVER, 42, False)  # not there: nothing to do
    ((recipe_id, added_at),) = store.load_favorites(conn, ME, FOREVER)
    assert recipe_id == 7
    assert len(added_at) == len("2026-09-24 20:53:16")  # UTC text


def test_load_market_prices_from_one_auction_house(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    here = set_prices(conn, {1: 20})
    there = set_prices(conn, {1: 99}, realm="Elsewhere")
    assert store.load_market(conn, FOREVER, here).prices == {1: 20}
    assert store.load_market(conn, FOREVER, there).prices == {1: 99}
    assert store.load_market(conn, FOREVER, None).prices == {}
    assert store.load_market(conn, "tbc", here).items == {}  # game data is per version


def test_profession_names(
    db2_paths: dict[str, Path], conn: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert store.profession_names(conn, FOREVER) == []
    ingest.build_db(db2_paths, conn, FOREVER)
    assert store.profession_names(conn, FOREVER) == ["Tailoring"]
    assert store.profession_names(conn, "tbc") == []
    monkeypatch.setattr(store, "HIDDEN_PROFESSIONS", frozenset({"Tailoring"}))
    assert store.profession_names(conn, FOREVER) == []


def test_profession_names_leave_out_conversions(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    conn.execute(
        insert(schema.recipes).values(
            game_version=FOREVER,
            id=ingest.CONVERSION_ID_BASE + 960,
            spell_id=960,
            name="Greater Magic Essence",
            kind="convert",
            skill_line=0,
            skill_name="",
            output_item_id=1,
        )
    )
    assert store.profession_names(conn, FOREVER) == ["Tailoring"]


def test_delete_one_character(conn: Connection) -> None:
    chars = altarmy.parse_characters(ALTARMY_SV)
    store.save_characters(conn, ME, FOREVER, chars)
    first = chars[0]
    assert store.delete_character(conn, ME, FOREVER, first.realm, first.name)
    assert not store.delete_character(conn, ME, FOREVER, first.realm, first.name)
    assert len(store.load_characters(conn, ME, FOREVER)) == len(chars) - 1


def test_load_market_marks_soulbound_items_not_tradable(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    t = schema.items
    conn.execute(update(t).where(t.c.game_version == FOREVER, t.c.id == 3).values(bonding=1))
    items = store.load_market(conn, FOREVER, None).items
    assert (items[1].tradable, items[3].tradable) == (True, False)  # the fixture's robe is BoE


def test_load_market_marks_items_that_cannot_be_disenchanted(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    t = schema.items
    conn.execute(update(t).where(t.c.game_version == FOREVER, t.c.id == 3).values(disenchantable=False))
    items = store.load_market(conn, FOREVER, None).items
    assert (items[1].disenchantable, items[3].disenchantable) == (True, False)


def test_load_priced_says_how_deep_each_disenchant_materials_market_is(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the robe (item 3: armor, green, level 20) disenchants into linen (item 1), which the AH lists 5 of
    row = {"item_class": 4, "quality": 2, "min_ilvl": 15, "max_ilvl": 25, "result_item_id": 1, "chance": 1.0}
    conn.execute(insert(schema.disenchant).values(game_version=FOREVER, min_count=1, max_count=1, **row))
    ah = scanned(conn, {1: [(100, 5)], 2: [(50, 3)]})
    priced = store.load_priced(conn, FOREVER, ah)
    assert priced.market.sell_depth == {1: 5}  # only what a disenchant makes
    assert store.load_market(conn, FOREVER, ah).sell_depth == {}  # nothing asked of the listings


def test_load_cities_reads_every_preset(cities: Path, tmp_path: Path) -> None:
    got = store.load_cities(cities)
    assert list(got) == ["Booty Bay", "Orgrimmar", "Stormwind", "Thunder Bluff"]
    assert (got["Orgrimmar"].faction, got["Booty Bay"].faction) == ("Horde", "")
    assert store.load_cities(tmp_path / "nowhere") == {}
    (cities / "Broken.json").write_text("{", encoding="utf-8")
    with pytest.raises(ValueError, match="Broken.json"):
        store.load_cities(cities)
