import gzip
import json
import threading
from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Connection, insert, select, update

from altarmy_site import (
    altarmy,
    api,
    auth,
    db,
    engine,
    ingest,
    jobs,
    launch,
    merge,
    prices,
    ratelimit,
    schema,
    service,
    store,
    uploads,
)
from altarmy_site.altarmy import Character, Profession
from altarmy_site.api import create_app
from altarmy_site.auctionator import DayStats, ItemPrice
from altarmy_site.versions import GameVersion

from .addon_fixtures import PROFIT_EXPORT
from .conftest import FOREVER, ME, book_scan, saved_book, scanned, set_prices, write_csv
from .test_altarmy import ALTARMY_SV
from .test_auctionator import _entry, _saved_variables
from .test_auth import FakeVerifier
from .test_launch import FakeLauncher
from .test_signals import FakeSignals

FIREBASE = auth.FirebaseConfig("demo-altarmy", "key", "demo-altarmy.firebaseapp.com", None)
EMULATOR = auth.FirebaseConfig(  # as `npm run dev` runs it
    "demo-altarmy", "key", "demo-altarmy.firebaseapp.com", "127.0.0.1:9099", "127.0.0.1:8080"
)
FREE = {"Authorization": "Bearer anonymous:guest"}  # tokens as `FakeVerifier` reads them: an anonymous user
LINKED = {"Authorization": "Bearer google.com:g1"}  # a user with an account
SIGNED_IN = {"Authorization": f"Bearer password:{ME}"}  # the `client` fixture's default: `ME`, linked
ADMIN = {"Authorization": "Bearer password:a1:admin"}  # a linked user with the admin claim


def make_client(
    database: db.Database,
    game_versions: dict[str, GameVersion],
    static_dir: Path,
    *,
    verifier: FakeVerifier | None = None,
    limits: ratelimit.Limits | None = None,
    firebase: auth.FirebaseConfig = FIREBASE,
    launcher: FakeLauncher | None = None,
) -> TestClient:
    """The app with fake tokens (see `FakeVerifier`), asking about Forever unless a request passes another
    game_version, signed in as `ME` unless a request sends other headers."""
    app = create_app(
        game_versions,
        database=database,
        static_dir=static_dir,
        verifier=verifier or FakeVerifier(),
        firebase=firebase,
        limits=limits,
        signals=FakeSignals(),
        launcher=launcher or FakeLauncher(),
    )
    c = TestClient(app)
    c.params = c.params.set("game_version", "forever")
    c.headers.update(SIGNED_IN)
    return c


@pytest.fixture
def client(
    tmp_path: Path, vendor_csv: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> TestClient:
    """Signed in as `ME`; shares the `conn` fixture's database. FREE and LINKED sign in as others."""
    return make_client(database, game_versions, tmp_path / "nodist")


def with_tailor(conn: Connection) -> None:
    """Store the Alt Army test characters and select the realm/faction of the one who knows the robe."""
    store.save_characters(conn, ME, FOREVER, altarmy.parse_characters(ALTARMY_SV))
    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")


@pytest.fixture
def priced(db2_paths: dict[str, Path], conn: Connection) -> Connection:
    """The client's database with game data, prices linen=20, thread=100 on Classic Beta PvE's auction
    house and a selected tailor there who knows the Green Robe."""
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    with_tailor(conn)
    return conn


def test_empty_db(client: TestClient, database: db.Database) -> None:
    status = client.get("/api/status").json()
    assert status["recipes"] == 0
    assert status["build"] is None
    assert (status["characters"], status["selection"], status["data_version"]) == (0, None, 0)
    assert client.get("/api/characters").json() == {
        "groups": [],
        "selection": None,
        "imported_at": None,
        "imported_via": None,
        "auto_import_at": None,
        "arcane_salvager": False,
    }
    assert client.get("/api/rank").json()["results"] == []


def one_craft(client: TestClient) -> None:
    """Rank and evaluate single crafts (a batch of 1), for tests about prices rather than sessions."""
    assert client.put("/api/time", json={"config": {"batch": 1}}).is_success


def test_rank_known_recipes(client: TestClient, priced: Connection) -> None:
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["recipe"] == "Green Robe"
    assert r["profession"] == "Tailoring"
    assert (r["crafters"], r["crafter"]) == (["Tailor Guy"], "Tailor Guy")
    assert body["classes"] == {"Tailor Guy": "MAGE"}
    assert (r["output_name"], r["output_count"]) == ("Green Robe", 1)
    # a session of the time settings' batch (10 crafts by default), as the expanded row plans it
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (10, 3000, 5000, 2000)
    assert r["roi"] == pytest.approx(2 / 3)
    assert r["best_exit"] == "vendor"
    assert [(s["action"], s["name"], s["quantity"], s["value"], s["via"]) for s in r["steps"]] == [
        ("buy", "Linen Cloth", 100, -2000, "ah"),
        ("buy", "Coarse Thread", 10, -1000, "ah"),
        ("craft", "Green Robe", 10, 0, "Green Robe"),
        ("sell", "Green Robe", 10, 5000, "vendor"),
    ]
    assert {"kind": "vendor", "value": 500, "materials": [], "postage": 0, "mail_to": ""} in r["exits"]
    assert (r["postage"], r["mail_to"]) == (0, "")
    tree = r["tree"]
    assert (tree["item_id"], tree["quantity"], tree["cost"], tree["via"], tree["crafts"]) == (
        3,
        10,
        3000,
        "Green Robe",
        10,
    )
    assert [(n["item_id"], n["quantity"], n["cost"], n["source"], n["inputs"]) for n in tree["inputs"]] == [
        (1, 100, 2000, "ah", []),
        (2, 10, 1000, "ah", []),
    ]
    one_craft(client)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (1, 300, 500, 200)


def test_rank_buys_reagents_from_vendors(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    set_prices(conn, {1: 20})  # thread has no AH price, but vendors sell it for 11c
    one_craft(client)
    with_tailor(conn)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["cost"] == 200 + 11
    assert (r["steps"][1]["name"], r["steps"][1]["via"]) == ("Coarse Thread", "vendor")
    assert r["tree"]["inputs"][1]["source"] == "vendor"
    assert (body["items"]["2"]["vendor_price"], body["items"]["1"]["vendor_price"]) == (11, None)


def with_enchanter(conn: Connection) -> None:
    """Add an enchanter (who can't tailor) to the tailor's realm/faction."""
    enchanter = Character(
        "Classic Beta PvE", "Enchy", "Horde", "PRIEST", 20, (Profession("Enchanting", 60, 75, frozenset()),)
    )
    store.save_characters(conn, ME, FOREVER, [*altarmy.parse_characters(ALTARMY_SV), enchanter])


def add_disenchant(conn: Connection, chance: float, min_count: int, max_count: int) -> None:
    """Green armor disenchants into linen."""
    conn.execute(
        schema.disenchant.insert().values(
            game_version=FOREVER,
            item_class=4,
            quality=2,
            min_ilvl=0,
            max_ilvl=1000,
            result_item_id=1,
            chance=chance,
            min_count=min_count,
            max_count=max_count,
        )
    )


def test_rank_sends_disenchant_materials(client: TestClient, priced: Connection) -> None:
    add_disenchant(priced, 0.5, 1, 3)  # robe -> 1-3 linen
    with_enchanter(priced)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    (de,) = [e for e in r["exits"] if e["kind"] == "disenchant"]
    assert de["materials"] == [
        {
            "item_id": 1,
            "name": "Linen Cloth",
            "chance": 0.5,
            "min_count": 1,
            "max_count": 3,
            "value": 19,
            "expected": 1.0,
        }
    ]
    assert all(e["materials"] == [] for e in r["exits"] if e["kind"] != "disenchant")


def test_rank_and_evaluate_count_the_arcane_salvager(client: TestClient, priced: Connection) -> None:
    add_disenchant(priced, 0.5, 1, 3)  # robe -> 1-3 linen, 19c a disenchant; 20.9 with a 10% second roll
    with_enchanter(priced)

    def value(**params: bool) -> int:
        (r,) = client.get("/api/rank", params=params).json()["results"]
        (de,) = [e for e in r["exits"] if e["kind"] == "disenchant"]
        body = {"recipe_id": r["recipe_id"], "choices": {}, **params}
        got = client.post("/api/evaluate", json=body).json()["result"]
        assert [e["value"] for e in got["exits"]] == [e["value"] for e in r["exits"]]
        (material,) = de["materials"]
        assert material["value"] == de["value"]
        return int(de["value"])

    assert value(arcane_salvager=True) == 20
    assert value() == value(arcane_salvager=False) == 19  # not the cached ranking with the salvager


def test_characters_say_whether_anyone_can_make_an_arcane_salvager(
    client: TestClient, conn: Connection
) -> None:
    def enchanter(*recipes: int) -> Character:
        return Character(
            "Realm", "Enchy", "Horde", "MAGE", 60, (Profession("Enchanting", 150, 150, frozenset(recipes)),)
        )

    service.replace_characters(conn, ME, FOREVER, [enchanter(7418)])
    assert client.get("/api/characters").json()["arcane_salvager"] is False
    service.replace_characters(conn, ME, FOREVER, [enchanter(7418, service.ARCANE_SALVAGER_SPELL)])
    assert client.get("/api/characters").json()["arcane_salvager"] is True


def test_rank_mails_disenchants_to_an_enchanter(client: TestClient, priced: Connection) -> None:
    one_craft(client)
    add_disenchant(priced, 1.0, 100, 100)  # robe -> 100 linen
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "vendor"  # nobody on the realm can disenchant

    with_enchanter(priced)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["best_exit"], r["postage"], r["mail_to"], r["cost"]) == ("disenchant", 30, "Enchy", 330)
    assert ("mail", "Green Robe", 1, -30, "Enchy", "Tailor Guy") in [
        (s["action"], s["name"], s["quantity"], s["value"], s["via"], s["who"]) for s in r["steps"]
    ]
    assert [(n["crafter"], n["mail_to"], n["postage"]) for n in r["tree"]["inputs"]] == [
        ("Tailor Guy", "", 0),
        ("Tailor Guy", "", 0),
    ]


def test_rank_sends_reagents_and_item_details(client: TestClient, priced: Connection) -> None:
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert r["reagents"] == [{"item_id": 1, "count": 10}, {"item_id": 2, "count": 1}]
    items = body["items"]
    assert set(items) == {"1", "2", "3"}  # output and reagents; JSON object keys are strings
    assert items["1"]["ah_price"] == 20
    assert items["3"] == {
        "id": 3,
        "name": "Green Robe",
        "quality": 2,
        "class_id": 4,
        "subclass_name": "Cloth",
        "inventory_type": 20,
        "bonding": 2,
        "item_delay": 0,
        "container_slots": 0,
        "required_level": 12,
        "required_skill": "Tailoring",
        "required_skill_rank": 50,
        "description": "Soft and green.",
        "sell_price": 500,
        "icon": "inv_chest_cloth_39",
        "armor": 46,
        "dmg_min": 0,
        "dmg_max": 0,
        "dps": 0.0,
        "stats": ["+9 Intellect"],
        "effects": [
            {
                "trigger": "Equip",
                "text": "Increases damage and healing done by magical spells and effects by up to 6.",
            },
            {"trigger": "Use", "text": "Restores 1050 to 1750 health. (2 Min Cooldown)"},
        ],
        "ah_price": None,
        "ah_sell_price": None,
        "ah_quantity": None,
        "ah_levels": [],
        "vendor_price": None,
        "market_price": None,
        "median_7d": None,
        "scans_7d": None,
        "sale_price": None,
        "sold_7d": 0,
        "sold_pairs_7d": None,
        "listed": None,
        "seen_at": None,
        "stack_size": 1,
    }


def test_rank_lists_options_and_evaluate_applies_choices(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    set_prices(conn, {1: 20, 2: 100})  # vendors sell thread for 11c
    one_craft(client)
    with_tailor(conn)
    (r,) = client.get("/api/rank").json()["results"]
    assert r["tree"]["options"] == []
    assert [{k: v for k, v in o.items() if k != "seconds"} for o in r["tree"]["inputs"][1]["options"]] == [
        {"key": "vendor", "cost": 11, "source": "vendor", "via": "", "crafter": "", "convert": False},
        {"key": "ah", "cost": 100, "source": "ah", "via": "", "crafter": "", "convert": False},
    ]
    assert r["sell_options"] == [{"kind": "vendor", "profit": 500 - 211}]
    assert [(st["action"], st["paths"]) for st in r["steps"]] == [
        ("buy", ["r.0"]),
        ("buy", ["r.1"]),
        ("craft", ["r"]),
        ("sell", ["sell"]),
    ]

    body = {"recipe_id": r["recipe_id"], "choices": {"r.1": "ah"}}
    got = client.post("/api/evaluate", json=body).json()
    assert (got["result"]["cost"], got["result"]["tree"]["inputs"][1]["source"]) == (300, "ah")
    assert set(got["items"]) == {"1", "2", "3"}
    assert client.post("/api/evaluate", json={"recipe_id": 999, "choices": {}}).status_code == 404
    only_ah = {**body, "exits": ["ah"]}  # the robe has no AH price
    assert client.post("/api/evaluate", json=only_ah).status_code == 404


def test_favorites_are_listed_and_ranked_first(client: TestClient, priced: Connection) -> None:
    assert client.get("/api/favorites").json() == {"recipes": []}
    (r,) = client.get("/api/rank").json()["results"]
    added = client.put(f"/api/favorites/{r['recipe_id']}").json()
    assert [f["recipe_id"] for f in added["recipes"]] == [r["recipe_id"]]
    assert added["recipes"][0]["added_at"]
    assert client.get("/api/favorites").json() == added
    assert client.get("/api/favorites", params={"game_version": "tbc"}).json() == {"recipes": []}
    assert [x["recipe_id"] for x in client.get("/api/rank").json()["results"]] == [r["recipe_id"]]
    assert client.delete(f"/api/favorites/{r['recipe_id']}").json() == {"recipes": []}


def test_ah_blocked_items_are_never_sold_on_the_ah(client: TestClient, priced: Connection) -> None:
    set_prices(priced, {3: 1000})  # the robe sells for 950 on the AH, 500 at a vendor
    assert client.get("/api/ah-blocked").json() == {"items": [], "details": {}}
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "ah"

    blocked = client.put("/api/ah-blocked/3").json()
    assert [i["item_id"] for i in blocked["items"]] == [3]
    assert blocked["items"][0]["added_at"]
    robe = blocked["details"]["3"]
    assert (robe["name"], robe["ah_price"]) == ("Green Robe", 1000)
    assert client.get("/api/ah-blocked").json() == blocked
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["best_exit"], [e["kind"] for e in r["exits"]]) == ("vendor", ["vendor"])
    got = client.post("/api/evaluate", json={"recipe_id": r["recipe_id"], "choices": {"sell": "ah"}}).json()
    assert got["result"]["best_exit"] == "vendor"

    assert client.delete("/api/ah-blocked/3").json() == {"items": [], "details": {}}
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "ah"


def test_rank_filters_and_validation(client: TestClient, priced: Connection) -> None:
    def total(**params: str | int | float | list[str]) -> int:
        body = client.get("/api/rank", params=params).json()
        assert len(body["results"]) == body["total"]
        return int(body["total"])

    one_craft(client)
    assert total() == 1  # cost 300, profit 200, roi 2/3, sold to a vendor
    assert total(min_profit=201) == 0
    assert total(min_profit=200, max_profit=200, min_cost=300, max_cost=300) == 1
    assert total(max_profit=199) == 0
    assert total(min_cost=301) == 0
    assert total(max_cost=299) == 0
    assert total(min_roi=0.6, max_roi=0.7) == 1
    assert total(min_roi=0.7) == 0
    assert total(max_roi=0.6) == 0
    assert total(exits=["ah", "disenchant"]) == 0
    assert total(exits=["vendor"]) == 1
    assert client.get("/api/rank", params={"exits": "trade"}).status_code == 422
    assert client.get("/api/rank", params={"top": 0}).status_code == 422
    service.select(priced, ME, FOREVER, "Dreamscythe", "Horde")  # cooks only
    assert total() == 0


def add_conversion(conn: Connection) -> None:
    """A conversion of 3 linen (20 each) into 1 thread (100 on the AH, 95 after the cut)."""
    rid = ingest.CONVERSION_ID_BASE + 960
    conn.execute(
        schema.recipes.insert().values(
            game_version=FOREVER,
            id=rid,
            spell_id=960,
            name="Coarse Thread",
            kind="convert",
            skill_line=0,
            skill_name="",
            output_item_id=2,
        )
    )
    conn.execute(
        schema.recipe_reagents.insert().values(
            game_version=FOREVER, recipe_id=rid, item_id=1, count=3, slot=0
        )
    )


def test_rank_sells_conversions_when_disenchant_is_allowed(client: TestClient, priced: Connection) -> None:
    add_conversion(priced)
    one_craft(client)

    def conversions(**params: bool | list[str]) -> list[dict[str, Any]]:
        results = client.get("/api/rank", params=params).json()["results"]
        return [r for r in results if r["kind"] == "convert"]

    (r,) = conversions(exits=["vendor", "disenchant"])
    assert (r["profession"], r["crafters"], r["crafter"]) == ("", [], "Tailor Guy")
    assert (r["cost"], r["revenue"], r["best_exit"]) == (60, 95, "ah")
    assert [(s["action"], s["convert"]) for s in r["steps"]] == [
        ("buy", False),
        ("craft", True),
        ("sell", False),
    ]
    assert r["tree"]["convert"] is True
    assert conversions(exits=["vendor", "ah"]) == []
    assert conversions(exits=["vendor", "disenchant"], include_trivial=False) == []
    (craft,) = [r for r in client.get("/api/rank").json()["results"] if r["kind"] == "craft"]
    assert craft["recipe"] == "Green Robe"


def test_rank_flips_gear_listed_below_what_it_disenchants_for(client: TestClient, priced: Connection) -> None:
    add_disenchant(priced, 1.0, 2, 2)  # a robe -> 2 linen, 38 net
    with_enchanter(priced)
    set_prices(priced, {3: 30})  # one robe listed at 30: a manual price, so one unit

    def flipped(**params: list[str]) -> list[dict[str, Any]]:
        results = client.get("/api/rank", params=params).json()["results"]
        return [r for r in results if r["kind"] == "flip"]

    (r,) = flipped(exits=["vendor", "disenchant"])
    assert (r["recipe"], r["crafter"], r["crafts"], r["best_exit"]) == (
        "Green Robe",
        "Enchy",
        1,
        "disenchant",
    )
    assert (r["cost"], r["revenue"]) == (30, 38)
    assert r["tree"]["flip"] is True
    assert [s["action"] for s in r["steps"]] == ["buy", "sell"]
    assert flipped(exits=["vendor", "ah"]) == []
    body = {"recipe_id": r["recipe_id"], "choices": {}, "exits": ["vendor", "disenchant"]}
    evaluated = client.post("/api/evaluate", json=body).json()["result"]
    assert (evaluated["kind"], evaluated["profit"]) == ("flip", 8)


def test_rank_unlearned_recipes(client: TestClient, priced: Connection) -> None:
    def novice(skill: int) -> Character:  # knows only a recipe this build lacks
        tailoring = Profession("Tailoring", skill, 75, frozenset({1}))
        return Character("Realm", "Novice", "Horde", "MAGE", 5, (tailoring,))

    def ranked(unlearned: str, **params: int | list[str]) -> list[tuple[str, list[str]]]:
        results = client.get("/api/rank", params={"unlearned": unlearned, **params}).json()["results"]
        return [(r["recipe"], r["crafters"]) for r in results]

    service.replace_characters(priced, ME, FOREVER, [novice(29)])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    assert client.get("/api/rank").json()["results"] == ranked("none") == []
    assert ranked("all") == [("Green Robe", [])]
    assert ranked("all", sources=["trainer"]) == [("Green Robe", [])]  # sources narrow only "train"
    assert ranked("train", look_ahead=20) == []  # its pattern requires 50: 21 short
    service.replace_characters(priced, ME, FOREVER, [novice(30)])
    assert ranked("train", look_ahead=20) == [("Green Robe", [])]  # 20 short
    assert ranked("train", look_ahead=19) == []
    assert ranked("train") == []
    service.replace_characters(priced, ME, FOREVER, [novice(50)])
    assert ranked("train") == [("Green Robe", [])]
    # a recipe item that can be traded teaches it: not a trainer, not a bind on pickup recipe
    assert ranked("train", sources=["trainer", "bop"]) == []
    assert ranked("train", sources=["recipe"]) == [("Green Robe", [])]
    for bad in ({"unlearned": "maybe"}, {"unlearned": "soon"}, {"look_ahead": 51}, {"look_ahead": -1}):
        assert client.get("/api/rank", params=bad).status_code == 422
    assert client.get("/api/rank", params={"sources": ["vendor"]}).status_code == 422


def test_rank_says_where_to_learn_recipes_nobody_has(client: TestClient, priced: Connection) -> None:
    src = {"game_version": FOREVER, "item_id": 3, "chance": 0.0, "count": 0, "levels": "", "limited": False}
    src |= {"area": 0, "map_x": 0.0, "map_y": 0.0}  # a vendor's spot on its zone map
    priced.execute(
        insert(schema.item_sources),
        [
            {**src, "seq": 0, "kind": "vendor", "name": "Kendor", "zone": "Stormwind", "side": "alliance"},
            {
                **src,
                **{"seq": 1, "kind": "vendor", "name": "Borya", "zone": "Orgrimmar", "side": "horde"},
                **{"area": 1637, "map_x": 40.0, "map_y": 60.5},
            },
            {
                **src,
                "seq": 2,
                "kind": "drop",
                "name": "Defias Pillager",
                "zone": "Westfall",
                "side": "",
                "chance": 2.5,
            },
        ],
    )
    tailoring = Profession("Tailoring", 50, 75, frozenset({1}))
    service.replace_characters(
        priced, ME, FOREVER, [Character("Realm", "Novice", "Horde", "MAGE", 5, (tailoring,))]
    )
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    body = client.get("/api/rank", params={"unlearned": "train"}).json()
    (r,) = body["results"]
    assert (r["crafters"], r["crafter"]) == ([], "Novice")
    learn = body["learn"][str(r["recipe_id"])]
    assert (learn["source"], learn["skill"], learn["profession"]) == ("recipe", 50, "Tailoring")
    (taught,) = learn["items"]
    assert (taught["item_id"], taught["name"]) == (3, "Green Robe")
    # the Alliance vendor serves nobody on the Horde
    assert [(p["kind"], p["name"]) for p in taught["places"]] == [
        ("vendor", "Borya"),
        ("drop", "Defias Pillager"),
    ]
    assert (taught["places"][0]["area"], taught["places"][0]["map_x"], taught["places"][0]["map_y"]) == (
        1637,
        40.0,
        60.5,
    )
    # without characters nobody is named: "anyone", nothing to learn
    service.replace_characters(priced, ME, FOREVER, [])
    assert client.get("/api/rank").json()["learn"] == {}


def test_evaluate_takes_the_look_ahead_and_sources(client: TestClient, priced: Connection) -> None:
    tailoring = Profession("Tailoring", 30, 75, frozenset({1}))
    novice = Character("Realm", "Novice", "Horde", "MAGE", 5, (tailoring,))
    service.replace_characters(priced, ME, FOREVER, [novice])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    robe = client.get("/api/rank", params={"unlearned": "all"}).json()["results"][0]["recipe_id"]

    def evaluated(**body: object) -> int:
        full = {"recipe_id": robe, "unlearned": "train", "choices": {}, **body}
        return client.post("/api/evaluate", json=full).status_code

    assert evaluated() == 404  # 20 short of its pattern
    assert evaluated(look_ahead=20) == 200
    assert evaluated(look_ahead=20, sources=["trainer"]) == 404
    assert evaluated(look_ahead=51) == 422


def test_rank_by_skill_reports_the_chance_of_a_skill_point(client: TestClient, priced: Connection) -> None:
    # Tailor Guy has Tailoring 50: the robe is yellow from 30 and grey from 60
    (r,) = client.get("/api/rank", params={"sort": "skill"}).json()["results"]
    assert r["skill_chance"] == pytest.approx(1 / 3)
    # a session of the default batch of 10, each expected point taking 1/30 off the next craft's chance
    assert r["skill_ups"] == pytest.approx(10 * (1 - (29 / 30) ** 10))
    one_craft(client)
    (r,) = client.get("/api/rank", params={"sort": "skill", "professions": ["Tailoring"]}).json()["results"]
    assert r["skill_ups"] == pytest.approx(1 / 3)
    (r,) = client.get("/api/rank").json()["results"]
    assert r["skill_chance"] == pytest.approx(1 / 3)
    assert client.get("/api/rank", params={"sort": "cheapest"}).status_code == 422


def test_rank_and_evaluate_without_trivial_recipes(client: TestClient, priced: Connection) -> None:
    veteran = Character(
        "Realm", "Veteran", "Horde", "MAGE", 60, (Profession("Tailoring", 60, 150, frozenset({900})),)
    )
    service.replace_characters(priced, ME, FOREVER, [veteran])  # the robe is grey from 60
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    (r,) = client.get("/api/rank").json()["results"]
    assert r["skill_chance"] == 0.0
    grey = client.get("/api/rank", params={"include_trivial": False}).json()
    assert (grey["results"], grey["total"]) == ([], 0)
    body = {"recipe_id": r["recipe_id"], "choices": {}}
    assert client.post("/api/evaluate", json=body).status_code == 200
    assert client.post("/api/evaluate", json={**body, "include_trivial": False}).status_code == 404


def test_rank_and_evaluate_for_the_characters_skilled_up(client: TestClient, priced: Connection) -> None:
    def tailor(name: str, rank: int) -> Character:
        return Character(
            "Realm", name, "Horde", "MAGE", 60, (Profession("Tailoring", rank, 150, frozenset({900})),)
        )

    service.replace_characters(priced, ME, FOREVER, [tailor("High", 55), tailor("Low", 40)])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params: dict[str, bool | list[str]] = {"include_trivial": False, "skill_crafters": ["High", "Low"]}
    (r,) = client.get("/api/rank", params=params).json()["results"]
    assert r["crafter"] == "Low"  # the lowest-skilled of those chosen
    (r,) = client.get("/api/rank", params={**params, "skill_crafters": ["High"]}).json()["results"]
    assert r["crafter"] == "High"
    body = {"recipe_id": r["recipe_id"], "choices": {}, "include_trivial": False}
    got = client.post("/api/evaluate", json={**body, "skill_crafters": ["High"]}).json()
    assert got["result"]["crafter"] == "High"
    assert (
        client.post("/api/evaluate", json={**body, "skill_crafters": ["Low"]}).json()["result"]["crafter"]
        == "Low"
    )
    # the user picks who does the final craft
    got = client.post("/api/evaluate", json={**body, "skill_crafters": ["Low"], "crafter": "High"}).json()
    assert got["result"]["crafter"] == "High"
    assert client.post("/api/evaluate", json={**body, "crafter": "Nobody"}).status_code == 404


def test_a_character_skilled_up_is_told_where_to_learn_what_an_alt_knows(
    client: TestClient, priced: Connection
) -> None:
    high = Character(
        "Realm", "High", "Horde", "MAGE", 60, (Profession("Tailoring", 55, 150, frozenset({900})),)
    )
    low = Character("Realm", "Low", "Horde", "MAGE", 60, (Profession("Tailoring", 40, 150, frozenset()),))
    service.replace_characters(priced, ME, FOREVER, [high, low])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params: dict[str, str | int | bool | list[str]] = {
        "unlearned": "train",
        "look_ahead": 10,
        "include_trivial": False,
        "skill_crafters": ["Low"],
    }
    body = client.get("/api/rank", params=params).json()
    (r,) = body["results"]
    assert (r["crafter"], r["crafters"]) == ("Low", ["High"])  # High knows it; Low must learn it
    assert body["learn"][str(r["recipe_id"])]["skill"] == 50


def test_a_trainers_recipe_costs_the_trainers_fee(client: TestClient, priced: Connection) -> None:
    priced.execute(
        update(schema.recipes)
        .where(schema.recipes.c.game_version == FOREVER)
        .values(source="trainer", train_cost=600)
    )
    low = Character("Realm", "Low", "Horde", "MAGE", 60, (Profession("Tailoring", 40, 150, frozenset()),))
    service.replace_characters(priced, ME, FOREVER, [low])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params: dict[str, str | int | list[str]] = {
        "unlearned": "train",
        "look_ahead": 10,
        "skill_crafters": ["Low"],
    }
    body = client.get("/api/rank", params=params).json()
    (r,) = body["results"]
    assert (r["crafter"], r["learn_cost"]) == ("Low", 600)
    learn = body["learn"][str(r["recipe_id"])]
    assert (learn["source"], learn["train_cost"]) == ("trainer", 600)


def test_rankings_outlive_a_rebuild_on_the_same_prices(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []
    search = service.search

    def spy(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", spy)
    state = client.app.state.wow[FOREVER]  # type: ignore[attr-defined]
    first = client.get("/api/rank").json()
    state.cache.invalidate()  # e.g. an upload whose scan was quarantined: nothing a market reads moved
    assert client.get("/api/rank").json() == first and calls == [1]
    set_prices(priced, {1: 25, 2: 100})  # new prices
    state.cache.invalidate()
    client.get("/api/rank")
    assert calls == [1, 1]


def test_identical_rankings_at_once_are_worked_out_once(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []
    started, go = threading.Event(), threading.Event()
    search = service.search

    def slow(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        started.set()
        go.wait(5)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", slow)
    got: list[Any] = []
    first = threading.Thread(target=lambda: got.append(client.get("/api/rank").json()))
    first.start()
    assert started.wait(5)
    second = threading.Thread(target=lambda: got.append(client.get("/api/rank").json()))
    second.start()
    second.join(0.3)  # waiting for the first, not ranking
    go.set()
    first.join(10)
    second.join(10)
    assert calls == [1] and len(got) == 2 and got[0] == got[1]


def test_one_profession_is_ranked_alone(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    asked: list[str | None] = []
    search = service.search

    def spy(*args: Any, **kwargs: Any) -> Any:
        asked.append(kwargs.get("skill_name"))
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", spy)
    assert client.get("/api/rank", params={"professions": ["Tailoring"]}).json()["total"] == 1
    client.get("/api/rank", params={"professions": ["Tailoring", "Cooking"]})
    client.get("/api/rank")
    assert asked == ["Tailoring", None]  # several professions narrow the full ranking, cached for no filter


def test_favorites_never_reorder_the_skill_ranking(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []
    first = service.favorites_first

    def spy(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return first(*args, **kwargs)

    monkeypatch.setattr(service, "favorites_first", spy)
    r = client.get("/api/rank").json()["results"][0]
    client.put(f"/api/favorites/{r['recipe_id']}")
    client.get("/api/rank", params={"sort": "skill"})
    assert calls == []
    client.get("/api/rank")
    assert calls == [1]


SKILL_UP: dict[str, str | bool | list[str]] = {
    "sort": "skill",
    "professions": ["Tailoring"],
    "skill_crafters": ["Tailor Guy"],
    "include_trivial": False,
    "exits": ["vendor", "keep"],
}


def test_a_climb_says_what_it_comes_to_by_each_rank_cap_it_reaches() -> None:
    smith = engine.Crafter("Smith", (("Blacksmithing", 75, 300),), frozenset())
    recipe = engine.Recipe(1, "R", 100, 1, ((1, 1),), "Blacksmithing", trivial_low=270, trivial_high=280)
    climb = engine.plan_climb(smith, "Blacksmithing", [engine.Candidate(recipe, 10.0, learn=None)]).best
    # 75 reached already; the climb ends where the recipe turns grey, before 300
    assert api._milestones(climb) == [
        api.MilestoneOut(skill=150, cost=750, unknown=1),
        api.MilestoneOut(skill=225, cost=1500, unknown=1),
    ]
    assert api._milestones(None) == []


def test_skill_up_ranks_each_recipe_as_the_first_run_of_its_climb(
    client: TestClient, priced: Connection
) -> None:
    # Tailor Guy has Tailoring 50: the robe is yellow from 30, green from 45 and grey from 60; it is the only
    # recipe, so the climb is its run until it turns grey (~30/(60 - s) crafts a point at skill s)
    body = client.get("/api/rank", params={**SKILL_UP, "runs": True}).json()
    (r,) = body["results"]
    assert (r["learn_skill"], r["trivial_low"], r["trivial_high"]) == (50, 30, 60)
    assert (r["crafts"], r["stop_skill"], r["stop_reason"], r["overtaken_by"]) == (88, 60, "trivial", "")
    assert body["chain"] == [] and body["options"] == [r]
    assert r["climb_cost"] is not None and r["climb_cost"] > -r["profit"]  # what it costs, spares too
    assert r["milestones"] == []  # the climb ends at 60, short of the next rank's cap (75)
    assert r["overtaken_by_item"] == 0
    assert r["crafts_p80"] >= r["crafts"]
    assert r["reach_chances"][r["crafts_p80"] - 1] >= 0.8  # the odds of reaching stop_skill by each craft
    novice = Character(
        "Realm", "Novice", "Horde", "MAGE", 5, (Profession("Tailoring", 20, 75, frozenset({900})),)
    )
    service.replace_characters(priced, ME, FOREVER, [novice])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params = {**SKILL_UP, "skill_crafters": ["Novice"], "runs": True}
    ranked = client.get("/api/rank", params=params).json()
    (r,) = ranked["results"]
    # from 20 the robe takes ~130 crafts to grey: more than a run asks for (100), so another run of it follows
    assert r["stop_reason"] == "ceiling" and r["crafts"] <= 100 and r["overtaken_by"] == ""
    (then,) = ranked["chain"]
    assert ranked["option_chains"] == [ranked["chain"]]  # each option's chain: here the one option's
    assert (then["recipe_id"], then["stop_skill"], then["stop_reason"]) == (r["recipe_id"], 60, "trivial")
    assert then["climb_cost"] is None  # a later run of the climb
    assert then["skill_chance"] < 1  # planned from where the first run stops: yellow by then
    body = {
        "recipe_id": r["recipe_id"],
        "choices": {},
        "include_trivial": False,
        "skill_crafters": ["Novice"],
    }
    got = client.post("/api/evaluate", json={**body, "exits": ["vendor", "keep"], "runs": True}).json()
    assert (got["result"]["crafts"], got["result"]["climb_cost"]) == (
        r["crafts"],
        r["climb_cost"],
    )  # as ranked
    got = client.post("/api/evaluate", json={**body, "runs": True, "copies": 12}).json()
    assert got["result"]["crafts"] == 12  # copies asked for win


def test_a_run_of_the_chain_is_planned_again_as_the_chain_has_it(
    client: TestClient, priced: Connection
) -> None:
    novice = Character(
        "Realm", "Novice", "Horde", "MAGE", 5, (Profession("Tailoring", 20, 75, frozenset({900})),)
    )
    service.replace_characters(priced, ME, FOREVER, [novice])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params = {**SKILL_UP, "skill_crafters": ["Novice"], "exits": ["vendor", "keep"], "runs": True}
    ranked = client.get("/api/rank", params=params).json()
    (r,) = ranked["results"]
    (then,) = ranked["chain"]  # the robe again, from where the first run stops
    body = {
        "recipe_id": then["recipe_id"],
        "choices": {},
        "include_trivial": False,
        "skill_crafters": ["Novice"],
        "exits": ["vendor", "keep"],
        "runs": True,
        "chain_from": r["recipe_id"],
        "chain_at": 1,
    }
    got = client.post("/api/evaluate", json=body).json()["result"]
    assert got == then  # at the skill it starts from, not the climber's
    # with a choice, the same run sold another way
    kept = client.post("/api/evaluate", json={**body, "choices": {"sell": "keep"}}).json()["result"]
    assert (kept["best_exit"], kept["crafts"], kept["stop_skill"]) == (
        "keep",
        then["crafts"],
        then["stop_skill"],
    )
    # for some copies: those crafts, still at that skill
    copies = client.post("/api/evaluate", json={**body, "copies": 5}).json()["result"]
    assert copies["crafts"] == 5 and copies["skill_chance"] == then["skill_chance"]
    # a place the chain doesn't have, or another recipe there, is no run
    assert client.post("/api/evaluate", json={**body, "chain_at": 2}).status_code == 404
    assert client.post("/api/evaluate", json={**body, "recipe_id": 999999}).status_code == 404
    # a chain needs the run it follows
    assert client.post("/api/evaluate", json={**body, "chain_from": None}).status_code == 400


def test_a_climb_goes_on_past_the_climbers_rank_cap(client: TestClient, priced: Connection) -> None:
    # capped at 55, they are assumed to train the next rank: the robe's run goes on until it turns grey at 60
    capped = Character(
        "Realm", "Capped", "Horde", "MAGE", 30, (Profession("Tailoring", 50, 55, frozenset({900})),)
    )
    service.replace_characters(priced, ME, FOREVER, [capped])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    params = {**SKILL_UP, "skill_crafters": ["Capped"], "runs": True}
    (r,) = client.get("/api/rank", params=params).json()["results"]
    assert (r["stop_skill"], r["stop_reason"]) == (60, "trivial")
    body = {
        "recipe_id": r["recipe_id"],
        "choices": {},
        "include_trivial": False,
        "skill_crafters": ["Capped"],
    }
    got = client.post("/api/evaluate", json={**body, "exits": ["vendor", "keep"], "runs": True}).json()
    assert got["result"]["stop_skill"] == 60  # as ranked
    # planned for the crafts bought for, the run is trained up too: its skill points past the cap
    copies = client.post(
        "/api/evaluate", json={**body, "exits": ["vendor", "keep"], "runs": True, "copies": r["crafts_p80"]}
    ).json()["result"]
    assert copies["crafts"] == r["crafts_p80"] and copies["skill_ups"] > 5
    # at the cap itself, the run and its crafts still give points (the next rank is assumed trained)
    at_cap = replace(capped, professions=(Profession("Tailoring", 55, 55, frozenset({900})),))
    service.replace_characters(priced, ME, FOREVER, [at_cap])
    (r,) = client.get("/api/rank", params=params).json()["results"]
    assert r["stop_skill"] == 60
    planned = client.post(
        "/api/evaluate", json={**body, "exits": ["vendor", "keep"], "runs": True, "copies": r["crafts_p80"]}
    )
    assert planned.status_code == 200 and planned.json()["result"]["skill_ups"] > 0
    # without runs nothing is assumed: at the cap a batch of crafts gives no point, so nothing ranks
    assert client.get("/api/rank", params={**SKILL_UP, "skill_crafters": ["Capped"]}).json()["results"] == []


def tailoring_options(conn: Connection) -> tuple[int, int, int]:
    """Two more Tailoring recipes beside the Green Robe (10 linen and a thread; yellow from 30, grey at 60),
    each making an item of its own: the Linen Cap (1 linen; yellow from 45, grey at 90) and the Linen Belt
    (2 linen; yellow from 48, grey at 95). A tailor at 50 who knows all three: the cap is the cheapest
    point, the belt the next, the robe the dearest. Their recipe ids (robe, cap, belt)."""
    robe = (
        conn.execute(select(schema.recipes).where(schema.recipes.c.game_version == FOREVER)).mappings().one()
    )
    item = (
        conn.execute(select(schema.items).where(schema.items.c.id == robe["output_item_id"])).mappings().one()
    )
    for n, (name, linen, low, high) in enumerate(
        (("Linen Cap", 1, 45, 90), ("Linen Belt", 2, 48, 95)), start=1
    ):
        conn.execute(insert(schema.items).values({**item, "id": 100 + n, "name": name}))
        conn.execute(
            insert(schema.recipes).values(
                {
                    **robe,
                    "id": robe["id"] + n,
                    "spell_id": 990 + n,
                    "name": name,
                    "output_item_id": 100 + n,
                    "trivial_low": low,
                    "trivial_high": high,
                }
            )
        )
        conn.execute(
            insert(schema.recipe_reagents).values(
                game_version=FOREVER, recipe_id=robe["id"] + n, item_id=1, count=linen, slot=0
            )
        )
    tailor = Character(
        "Realm",
        "Tailor",
        "Horde",
        "MAGE",
        60,
        (Profession("Tailoring", 50, 300, frozenset({900, 991, 992})),),
    )
    service.replace_characters(conn, ME, FOREVER, [tailor])
    set_prices(conn, {1: 20, 2: 100}, realm="Realm")
    return robe["id"], robe["id"] + 1, robe["id"] + 2


def test_each_option_side_by_side_never_comes_back_to_those_before_it(
    client: TestClient, priced: Connection
) -> None:
    robe, cap, belt = tailoring_options(priced)
    params = {**SKILL_UP, "skill_crafters": ["Tailor"], "runs": True}
    body = client.get("/api/rank", params=params).json()
    assert [r["recipe_id"] for r in body["results"]] == [belt, cap, robe]
    first, second, third = body["options"]
    # the best as ranked; the second never crafts the first, the third neither
    assert first == body["results"][0] and first["climb_without"] == []
    assert (second["recipe_id"], second["climb_without"]) == (cap, [belt])
    assert (third["recipe_id"], third["climb_without"]) == (robe, sorted([belt, cap]))
    # as ranked, the cap's run gives way to the belt; passed over, the belt never comes
    assert body["results"][1]["overtaken_by"] == "Linen Belt"
    assert second["overtaken_by"] != "Linen Belt" and second["stop_skill"] > body["results"][1]["stop_skill"]
    assert all(r["recipe_id"] != belt for r in body["option_chains"][1])
    # the robe's run without either goes on until it turns grey, and nothing follows it
    assert (third["stop_reason"], third["stop_skill"]) == ("trivial", 60)
    assert body["option_chains"][2] == []
    # picked, an option is the run and the chain its card shows
    picked = client.get("/api/rank", params={**params, "chain_from": cap, "top": 1}).json()
    assert picked["chain_start"] == second
    assert picked["chain"][: len(body["option_chains"][1])] == body["option_chains"][1]
    assert all(r["recipe_id"] != belt for r in picked["chain"])
    # planned again with what it leaves out, as the card shows it; without, as ranked
    evaluated = {"recipe_id": cap, "choices": {}, "include_trivial": False, "skill_crafters": ["Tailor"]}
    evaluated |= {"exits": ["vendor", "keep"], "runs": True}
    got = client.post("/api/evaluate", json={**evaluated, "climb_without": [belt]}).json()["result"]
    assert (got["crafts"], got["stop_skill"], got["climb_without"]) == (
        second["crafts"],
        second["stop_skill"],
        [belt],
    )
    plain = client.post("/api/evaluate", json=evaluated).json()["result"]
    assert (plain["stop_skill"], plain["climb_without"]) == (body["results"][1]["stop_skill"], [])
    # a banned recipe has no run to plan
    assert client.post("/api/evaluate", json={**evaluated, "climb_without": [cap]}).status_code == 404


def test_a_climb_trains_only_the_ranks_the_climbers_level_allows(
    client: TestClient, priced: Connection
) -> None:
    tailoring_options(priced)  # the Linen Belt gives points until 95
    tailors = [
        Character(
            "Realm",
            name,
            "Horde",
            "MAGE",
            level,
            (Profession("Tailoring", 50, 75, frozenset({900, 991, 992})),),
        )
        for name, level in (("Young", 9), ("Grown", 60))
    ]
    service.replace_characters(priced, ME, FOREVER, tailors)

    def climb_end(name: str) -> tuple[int, str]:
        params = {**SKILL_UP, "skill_crafters": [name], "runs": True, "chain_length": 20}
        body = client.get("/api/rank", params=params).json()
        last = (body["results"][:1] + body["chain"])[-1]
        return last["stop_skill"], last["stop_reason"]

    assert climb_end("Young") == (75, "cap")  # Journeyman asks for level 10
    assert climb_end("Grown")[0] == 95  # trained up as they go


def test_skill_up_keeps_what_no_vendor_buys(client: TestClient, priced: Connection) -> None:
    priced.execute(update(schema.items).where(schema.items.c.id == 3).values(sell_price=0))
    assert client.get("/api/rank", params={**SKILL_UP, "exits": ["vendor"]}).json()["results"] == []
    (r,) = client.get("/api/rank", params=SKILL_UP).json()["results"]
    assert (r["best_exit"], r["revenue"]) == ("keep", 0)


def test_a_climb_is_ranked_once(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[object] = []
    search = service.search

    def spy(*args: Any, **kwargs: Any) -> Any:
        calls.append(kwargs.get("skill_run"))
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", spy)
    client.get("/api/rank", params={**SKILL_UP, "runs": True})
    # the ranking alone: its options and chain are the climbs it worked out
    assert calls == [engine.SkillRuns()]
    ranked = len(calls)
    client.get("/api/rank", params={**SKILL_UP, "runs": True})
    assert len(calls) == ranked  # all cached
    client.get("/api/rank", params={**SKILL_UP})
    assert calls[ranked:] == [None]  # a session of the batch: ranked apart
    client.get("/api/rank", params={"runs": True})  # nobody skilled up: no run
    assert calls[-1] is None


def test_characters_and_selection(client: TestClient, db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    store.save_characters(conn, ME, FOREVER, altarmy.parse_characters(ALTARMY_SV))
    one_craft(client)
    status = client.get("/api/status").json()
    assert status["characters"] == 4
    assert status["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}  # the biggest group

    body = client.get("/api/characters").json()
    assert [(g["realm"], g["faction"], len(g["characters"])) for g in body["groups"]] == [
        ("Classic Beta PvE", "Alliance", 1),
        ("Classic Beta PvE", "Horde", 1),
        ("Dreamscythe", "Horde", 2),
    ]
    assert body["groups"][1]["characters"] == [
        {
            "name": "Tailor Guy",
            "class_file": "MAGE",
            "level": 20,
            "professions": [
                {"name": "Cooking", "rank": 1, "max_rank": 75, "recipes": 0},
                {"name": "Tailoring", "rank": 50, "max_rank": 75, "recipes": 1},
            ],
            "talents": [],
            "vendor_discounts": [],
        }
    ]
    (frell,) = [c for c in body["groups"][2]["characters"] if c["name"] == "Frell"]
    assert frell["talents"] == [
        {"spell_id": 1225457, "name": "Master Chef", "rank": 3, "max_rank": 5},
        {"spell_id": 1225459, "name": "Bartering", "rank": 2, "max_rank": 2},
    ]
    # Honored with Orgrimmar; only Friendly with the Darkspear Trolls, which takes nothing off
    assert frell["vendor_discounts"] == [{"faction": "Orgrimmar", "percent": 10}]
    assert body["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}
    assert client.get("/api/rank").json()["results"] == []  # Dreamscythe only cooks

    res = client.put("/api/selection", json={"realm": "Classic Beta PvE", "faction": "Horde"})
    assert res.status_code == 200
    assert res.json()["selection"] == {"realm": "Classic Beta PvE", "faction": "Horde"}
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["crafters"], r["profit"]) == (["Tailor Guy"], 200)  # priced by that realm's auction house

    res = client.put("/api/selection", json={"realm": "Nowhere", "faction": "Horde"})
    assert res.status_code == 400


def test_serves_built_frontend(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "index.html").write_text("<html>altarmy-site</html>")
    client = make_client(database, game_versions, dist)
    assert "altarmy-site" in client.get("/").text
    assert client.get("/api/status", params={"game_version": "tbc"}).json()["recipes"] == 0


def test_missing_frontend_build_gives_hint(client: TestClient) -> None:
    res = client.get("/")
    assert res.status_code == 200
    assert "npm run build" in res.json()["detail"]


def test_routes_need_a_known_game_version(client: TestClient) -> None:
    client.params = client.params.remove("game_version")
    assert client.get("/api/status").status_code == 422
    assert client.get("/api/status", params={"game_version": "retail"}).status_code == 422


def test_each_game_version_has_its_own_data(client: TestClient, priced: Connection) -> None:
    assert len(client.get("/api/rank").json()["results"]) == 1  # Forever: the tailor's robe
    client.put("/api/ah-blocked/3")
    tbc = {"game_version": "tbc"}
    status = client.get("/api/status", params=tbc).json()
    assert (status["recipes"], status["prices"], status["characters"]) == (0, 0, 0)
    assert client.get("/api/ah-blocked", params=tbc).json()["items"] == []
    assert client.get("/api/rank", params=tbc).json()["results"] == []
    forever, tbc_out = client.get("/api/versions").json()
    assert {k: v for k, v in forever.items() if k != "profession_ranks"} == (
        {"key": "forever", "label": "WoW: Forever", "build": None, "recipes": 1, "ah_cut": 0.05}
    )
    assert {k: v for k, v in tbc_out.items() if k != "profession_ranks"} == (
        {"key": "tbc", "label": "TBC Anniversary", "build": None, "recipes": 0, "ah_cut": 0.05}
    )
    # the trainer's ranks, up to each version's highest skill
    assert [r["name"] for r in forever["profession_ranks"]] == [
        "Apprentice",
        "Journeyman",
        "Expert",
        "Artisan",
    ]
    assert forever["profession_ranks"][2] == {"name": "Expert", "train_at": 125, "level": 20, "cap": 225}
    assert tbc_out["profession_ranks"][-1]["cap"] == 375


# --- users, tiers and prices ------------------------------------------------------------------------
def test_the_config_names_the_emulators_in_development(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dev = make_client(database, game_versions, tmp_path, firebase=EMULATOR)
    assert dev.get("/api/config").json() == {
        "firebase": {
            "api_key": "key",
            "auth_domain": "demo-altarmy.firebaseapp.com",
            "project_id": "demo-altarmy",
            "emulator_url": "http://127.0.0.1:9099",
            "firestore_emulator_host": "127.0.0.1:8080",
        },
    }


def test_users_sign_in_with_a_token(client: TestClient, conn: Connection) -> None:
    assert client.get("/api/config").json()["firebase"]["emulator_url"] is None
    del client.headers["Authorization"]
    assert client.get("/api/versions").status_code == 200  # public
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert client.get("/api/me", headers=FREE).json() == {
        "uid": "guest",
        "tier": "free",
        "admin": False,
    }
    assert client.get("/api/me", headers=LINKED).json()["tier"] == "linked"
    assert not client.get("/api/me", headers=LINKED).json()["admin"]
    u = schema.users
    rows = conn.execute(select(u.c.uid, u.c.tier).order_by(u.c.uid)).all()
    assert [tuple(r) for r in rows] == [
        ("g1", "linked"),
        ("guest", "free"),
        ("me", "linked"),
    ]


def test_guests_rank_evaluate_and_block_like_everyone(client: TestClient, priced: Connection) -> None:
    # a new user without characters browses every recipe of the freshest realm, crafted by nobody
    (browsed,) = client.get("/api/rank", headers=FREE).json()["results"]
    assert (browsed["crafter"], browsed["crafters"]) == ("", [])
    store.save_characters(priced, "guest", FOREVER, altarmy.parse_characters(ALTARMY_SV))
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert client.put("/api/selection", headers=FREE, json=selection).json()["selection"] == selection
    assert [g["realm"] for g in client.get("/api/characters", headers=FREE).json()["groups"]][0] == (
        "Classic Beta PvE"
    )
    (r,) = client.get("/api/rank", headers=FREE).json()["results"]
    assert (r["recipe"], r["tree"]["via"]) == ("Green Robe", "Green Robe")  # with its flow chart
    body = {"recipe_id": r["recipe_id"], "choices": {}}
    assert client.post("/api/evaluate", headers=FREE, json=body).json()["result"]["profit"] == r["profit"]
    assert client.put("/api/ah-blocked/3", headers=FREE).json()["items"][0]["item_id"] == 3
    assert client.delete("/api/ah-blocked/3", headers=FREE).json()["items"] == []


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("POST", "/api/sync"),
        ("PUT", "/api/sources"),
        ("GET", "/api/auctionator/files"),
        ("GET", "/api/altarmy/files"),
        ("POST", "/api/game-data/update"),
        ("POST", "/api/reload"),
    ],
)
def test_the_old_local_file_and_admin_routes_are_gone(client: TestClient, method: str, path: str) -> None:
    res = client.request(method, path, json={} if method == "PUT" else None)
    assert res.status_code in (404, 405)


def test_linked_users_rank_their_own_characters(client: TestClient, priced: Connection) -> None:
    # the tailor is ME's: this user only browses
    assert client.get("/api/rank", headers=LINKED).json()["results"][0]["crafter"] == ""
    store.save_characters(priced, "g1", FOREVER, altarmy.parse_characters(ALTARMY_SV))
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert client.put("/api/selection", headers=LINKED, json=selection).json()["selection"] == selection
    assert client.get("/api/rank", headers=LINKED).json()["total"] == 1
    client.put("/api/ah-blocked/3", headers=LINKED)
    assert store.load_ah_blocked(priced, ME, FOREVER) == []


def scanned_robe(conn: Connection, price: int, median_7d: int) -> int:
    """A scan listing one robe at `price` on the tailor's auction house, whose 7-day median (as the
    merge would fill it) is `median_7d`. Returns the auction house."""
    ah = scanned(conn, {3: [(price, 1)]})
    pc = schema.price_current
    conn.execute(pc.update().where(pc.c.item_id == 3).values(median_7d=median_7d, avail_7d=2, scans_7d=4))
    return ah


def test_rank_sells_at_the_lower_of_now_and_the_seven_day_median(
    client: TestClient, priced: Connection
) -> None:
    one_craft(client)
    scanned_robe(priced, 3_330_000, 1000)  # a lone overpriced listing
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert (r["best_exit"], r["revenue"]) == ("ah", 950)
    robe = body["items"]["3"]
    assert (robe["ah_price"], robe["ah_sell_price"]) == (3_330_000, 1000)


def test_rank_buys_at_the_cheapest_listing_and_says_how_many_are_listed(
    client: TestClient, priced: Connection
) -> None:
    scanned(priced, {1: [(20, 3), (25, 400)], 2: [(100, 50)]})
    body = client.get("/api/rank").json()
    linen = body["items"]["1"]
    assert (linen["ah_price"], linen["ah_quantity"]) == (20, 403)
    assert linen["ah_levels"] == [
        {"price": 20, "quantity": 3, "counted": True, "more": False, "listings": 1, "age": 0},
        {"price": 25, "quantity": 400, "counted": True, "more": False, "listings": 1, "age": 0},
    ]
    (r,) = body["results"]
    buy = next(step for step in r["steps"] if step["item_id"] == 1)
    # up the ladder: the three at 20, the rest at 25
    assert buy["value"] == -(3 * 20 + (buy["quantity"] - 3) * 25)


def test_rank_says_what_each_ah_buy_is_short_of_and_how_long_the_house_was_watched(
    client: TestClient, priced: Connection
) -> None:
    now = db.utcnow()
    for at in (now - timedelta(minutes=20), now):  # one pair of scans, 20 minutes apart
        scanned(priced, {1: [(20, 3)], 2: [(100, 50)]}, at=at)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    linen = next(n for n in r["tree"]["inputs"] if n["item_id"] == 1)
    assert linen["short"] == linen["quantity"] - 3 > 0
    assert sum(n["short"] for n in r["tree"]["inputs"]) == r["short"]
    assert body["watched_hours"] == pytest.approx(1 / 3)
    got = client.post("/api/evaluate", json={"recipe_id": r["recipe_id"], "choices": {}}).json()
    assert got["watched_hours"] == body["watched_hours"]


@pytest.mark.parametrize(("listed", "level", "reason"), [(2, "low", "thin"), (50, "medium", "unwatched")])
def test_rank_says_how_far_an_ah_sell_price_can_be_trusted(
    client: TestClient, priced: Connection, listed: int, level: str, reason: str
) -> None:
    one_craft(client)
    scanned_robe(priced, 1000, 1000)
    scanned(priced, {3: [(1000, listed)]}, db.utcnow() + timedelta(hours=1))
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert (r["best_exit"], r["slow"], r["days_to_sell"], r["short"]) == ("ah", False, None, 0)
    assert (r["confidence"]["level"], r["confidence"]["reason"]) == (level, reason)
    assert (r["confidence"]["listed"], r["confidence"]["units"]) == (listed, 1)
    assert body["items"]["3"]["ah_quantity"] == listed
    # every doubt, most actionable first: two that never sold are a lone listing on a thin market
    flags = ["lone", "thin", "unwatched"] if listed == 2 else ["unwatched"]
    assert (r["confidence"]["flags"], r["confidence"]["sold_pairs"]) == (flags, 0)


def test_rank_says_what_the_market_for_each_item_is(client: TestClient, priced: Connection) -> None:
    scanned_robe(priced, 1200, 1000)
    robe = client.get("/api/rank").json()["items"]["3"]
    assert (robe["market_price"], robe["median_7d"], robe["scans_7d"]) == (1200, 1000, 4)
    assert (robe["sale_price"], robe["sold_7d"], robe["sold_pairs_7d"]) == (None, 0, None)
    assert robe["listed"] is True
    assert robe["seen_at"] is not None
    assert robe["stack_size"] == 1
    linen = client.get("/api/rank").json()["items"]["1"]
    assert (linen["market_price"], linen["listed"], linen["sold_7d"]) == (None, None, 0)  # set by hand


def test_rank_counts_on_only_the_units_the_market_takes(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    # a session of 10 robes, the AH listing one at 1000 (nets 950), a vendor paying 500
    scanned_robe(priced, 1000, 1000)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["best_exit"], r["crafts"]) == ("ah", 10)
    assert (r["depth_units"], r["excess_units"], r["likely_exit"]) == (1, 9, "ah")
    assert r["likely_profit"] == r["profit"] - 9 * (950 - 500)
    calls: list[int] = []
    search = service.search

    def counted(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", counted)
    body = client.get("/api/rank", params={"sort": "likely"}).json()
    assert (body["total"], calls) == (1, [])  # ordered from the cached ranking
    one_craft(client)
    (r,) = client.get("/api/rank").json()["results"]
    assert (r["excess_units"], r["likely_profit"]) == (0, r["profit"])


def test_rank_narrows_to_sell_prices_trusted_enough(client: TestClient, priced: Connection) -> None:
    one_craft(client)
    scanned_robe(priced, 1000, 1000)
    scanned(priced, {1: [(20, 3)]}, db.utcnow() + timedelta(hours=1))  # the robe is gone
    (r,) = client.get("/api/rank").json()["results"]
    assert r["best_exit"] == "ah"  # at what it went for
    assert (r["confidence"]["level"], r["confidence"]["reason"]) == ("low", "unlisted")
    assert r["confidence"]["unlisted_since"] is not None
    assert client.get("/api/rank", params={"min_confidence": "low"}).json()["total"] == 1
    assert client.get("/api/rank", params={"min_confidence": "medium"}).json()["total"] == 0
    vendored = client.get("/api/rank", params={"min_confidence": "high", "exits": ["vendor"]}).json()
    assert vendored["total"] == 1  # a sale off the AH always passes
    assert vendored["results"][0]["confidence"] is None


def test_rank_pages_through_one_search(
    client: TestClient, priced: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []
    search = service.search

    def counted(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", counted)
    assert client.get("/api/rank", params={"top": 1}).json()["total"] == 1
    assert client.get("/api/rank", params={"top": 2}).json()["total"] == 1
    assert len(calls) == 1  # "Show more" reuses the ranking
    assert client.get("/api/rank", params={"top": 1, "min_profit": 10**9}).json()["total"] == 0
    assert client.get("/api/rank", params={"top": 1, "max_cost": 0, "min_roi": 9}).json()["total"] == 0
    assert len(calls) == 1  # the bounds are applied to the cached ranking
    client.get("/api/rank", params={"top": 2, "exits": ["vendor"]})
    assert len(calls) == 2  # the exits change what is ranked
    client.get("/api/rank", params={"top": 2, "unlearned": "all"})
    assert len(calls) == 3  # other parameters rank again
    client.get("/api/rank", params={"top": 1, "sort": "rate"})
    assert len(calls) == 3  # sorting by rate reuses the ranking
    client.get("/api/rank", params={"top": 1, "sort": "skill"})
    assert len(calls) == 3  # so does sorting by skill
    client.put("/api/time", json={"config": {"batch": 3}})
    client.get("/api/rank", params={"top": 1})
    assert len(calls) == 4  # plans depend on the time settings


def test_status_reports_the_price_version(client: TestClient, priced: Connection) -> None:
    assert client.get("/api/status").json()["price_version"] == 2  # the fixture's two prices
    ah = scanned_robe(priced, 1200, 1000)
    scanned = client.get("/api/status").json()["price_version"]
    assert scanned > 2
    prices.record_daily(priced, ah, {3: _item_price(1200)})
    merge.merge(priced, FOREVER)
    assert client.get("/api/status").json()["price_version"] == scanned + 1


def _item_price(price: int) -> ItemPrice:
    return ItemPrice(price, {db.utcnow().date(): DayStats(price, price, 1)})


def test_coverage_lists_each_realms_scans(client: TestClient, conn: Connection) -> None:
    scan = book_scan({1: [(20, 5)]}, db.utcnow(), "Dreamscythe", "Horde")
    assert upload(client, "altarmy", ALTARMY_SV + saved_book(scan), FREE).is_success
    prices.unnamed_auction_house(conn, FOREVER)  # never listed
    tbc = prices.auction_house(conn, "tbc", "Dreamscythe", "Horde")
    (row,) = client.get("/api/coverage", headers=FREE).json()
    assert (row["realm"], row["faction"], row["prices"], row["last_scan_items"]) == (
        "Dreamscythe",
        "Horde",
        1,
        1,
    )
    assert (row["scans_7d"], row["uploaders_7d"], row["watched_hours"]) == (1, 1, 0.0)
    assert row["last_scan"] is not None
    (dream,) = client.get("/api/coverage", params={"game_version": "tbc"}, headers=FREE).json()
    assert (dream["auction_house_id"], dream["last_scan"], dream["scans_7d"]) == (tbc, None, 0)


# --- uploads ------------------------------------------------------------------------------------------
def upload(
    c: TestClient,
    kind: str,
    data: bytes,
    headers: dict[str, str] | None = None,
    *,
    modified_at: int | None = None,
    via: str = "browser",
    filename: str = "x.lua",
    game_version: str | None = None,
) -> Any:
    form: dict[str, str] = {"kind": kind, "via": via}
    if modified_at is not None:
        form["modified_at"] = str(modified_at)
    params = {} if game_version is None else {"game_version": game_version}
    files = {"file": (filename, data)}
    return c.post("/api/uploads", headers=headers or {}, params=params, data=form, files=files)


def test_guests_upload_characters_and_scans(client: TestClient, conn: Connection) -> None:
    scan = book_scan({1: [(20, 5)], 2: [(100, 1)]}, db.utcnow() - timedelta(minutes=5))
    res = upload(client, "altarmy", gzip.compress(ALTARMY_SV + saved_book(scan)), FREE)
    assert res.status_code == 200, res.text
    body = res.json()
    assert (body["kind"], body["characters"]) == ("altarmy", 4)
    assert body["groups"][0] == {"realm": "Classic Beta PvE", "faction": "Alliance", "characters": 1}
    assert store.count_characters(conn, "guest", FOREVER) == 4
    assert len(client.get("/api/characters", headers=FREE).json()["groups"]) == 3
    (realm,) = body["realms"]
    assert realm == {
        "key": "Classic Beta PvE Horde",
        "auction_house_id": realm["auction_house_id"],
        "realm": "Classic Beta PvE",
        "faction": "Horde",
        "items": 2,
        "moved": 2,
        "quarantined": False,
    }
    (covered,) = client.get("/api/coverage", headers=FREE).json()
    assert (covered["realm"], covered["faction"], covered["prices"]) == ("Classic Beta PvE", "Horde", 2)
    history = client.get("/api/uploads", headers=FREE).json()
    assert [(u["kind"], u["outcome"], u["via"]) for u in history] == [("altarmy", "accepted", "browser")]
    assert client.get("/api/status", headers=FREE).json()["data_version"] == 1


def test_an_auctionator_file_is_refused_where_prices_are_alt_armys(client: TestClient) -> None:
    data = _saved_variables({"Dreamscythe Horde": {"1": _entry(20)}})
    res = upload(client, "auctionator", data, FREE)
    assert res.status_code == 400
    assert "Alt Army's own auction house scan" in res.json()["detail"]
    assert upload(client, "auctionator", data, FREE, game_version="tbc").is_success
    history = client.get("/api/uploads", headers=FREE).json()
    assert [(u["game_version"], u["outcome"]) for u in history] == [
        ("tbc", "accepted"),
        ("forever", "rejected"),
    ]


def test_upload_refreshes_the_cached_market(client: TestClient, priced: Connection) -> None:
    one_craft(client)
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 20 + 100
    scan = book_scan({1: [(33, 500)], 2: [(100, 50)]}, db.utcnow() + timedelta(seconds=1))
    assert upload(client, "altarmy", ALTARMY_SV + saved_book(scan)).is_success
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 33 + 100  # linen repriced


def published(client: TestClient) -> list[tuple[int, str, int]]:
    fake: FakeSignals = client.app.state.wow[FOREVER].signals  # type: ignore[attr-defined]
    return fake.published


def test_an_upload_that_moves_prices_signals_the_auction_house(
    client: TestClient, priced: Connection
) -> None:
    ah = service.selected_auction_house(priced, ME, FOREVER)
    assert ah is not None
    before = prices.price_version(priced, ah)
    assert before is not None
    scan = book_scan({1: [(33, 500)]}, db.utcnow() + timedelta(seconds=1))
    data = ALTARMY_SV + saved_book(scan)
    upload(client, "altarmy", data)
    assert published(client) == [(ah, FOREVER, before + 1)]
    upload(client, "altarmy", data)  # the same scan again: nothing moved
    assert published(client) == [(ah, FOREVER, before + 1)]
    upload(client, "altarmy", ALTARMY_SV)  # characters only
    assert len(published(client)) == 1


def test_a_known_price_version_skips_the_markets_ttl(client: TestClient, priced: Connection) -> None:
    """After a price signal the front end asks with the new version: another instance's prices show at
    once, not STAMP_TTL later."""
    one_craft(client)
    assert client.get("/api/rank").json()["results"][0]["cost"] == 10 * 20 + 100
    ah = service.selected_auction_house(priced, ME, FOREVER)
    prices.set_price(priced, ah or 0, 1, 33)  # as another instance's upload would
    version = prices.price_version(priced, ah)
    got = client.get("/api/rank", params={"price_version": version}).json()
    assert got["results"][0]["cost"] == 10 * 33 + 100
    body = {"recipe_id": got["results"][0]["recipe_id"], "choices": {}, "price_version": version}
    assert client.post("/api/evaluate", json=body).json()["result"]["cost"] == 10 * 33 + 100


def test_bad_uploads(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    res = upload(client, "altarmy", b"garbage", LINKED)
    assert res.status_code == 400
    assert "Lua syntax error" in res.json()["detail"]
    (row,) = client.get("/api/uploads", headers=LINKED).json()
    assert (row["outcome"], row["size"]) == ("rejected", 7)
    assert upload(client, "cheese", b"x", LINKED).status_code == 422
    assert upload(client, "altarmy", b"x", {"Authorization": "Bearer nonsense"}).status_code == 401

    monkeypatch.setattr(uploads, "MAX_BYTES", 1000)
    assert upload(client, "altarmy", b"x" * 1001, LINKED).status_code == 413
    assert upload(client, "altarmy", gzip.compress(b"x" * 5000), LINKED).status_code == 413

    monkeypatch.setattr(uploads, "RATE_LIMIT", 3)
    res = upload(client, "altarmy", ALTARMY_SV, LINKED)
    assert res.status_code == 429  # the rejected ones count too


PASTE = PROFIT_EXPORT.read_text(encoding="utf-8")


def test_guests_paste_the_addons_export(client: TestClient) -> None:
    tbc = {"game_version": "tbc"}
    res = client.post("/api/uploads/paste", params=tbc, headers=FREE, json={"text": PASTE})
    assert res.status_code == 200, res.text
    body = res.json()
    assert (body["kind"], body["characters"], body["realms"]) == ("altarmy", 3, [])
    assert body["groups"] == [{"realm": "Dreamscythe", "faction": "Horde", "characters": 2}]
    (row,) = client.get("/api/uploads", headers=FREE).json()
    assert (row["kind"], row["via"], row["outcome"], row["game_version"]) == (
        "altarmy",
        "paste",
        "accepted",
        "tbc",
    )
    chars = client.get("/api/characters", params=tbc, headers=FREE).json()
    assert (chars["imported_at"], chars["imported_via"], chars["auto_import_at"]) == (
        row["received_at"],
        "paste",
        None,
    )


def test_bad_pastes(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    res = client.post(
        "/api/uploads/paste", headers=LINKED, json={"text": PASTE}
    )  # a TBC export, Forever chosen
    assert res.status_code == 400
    assert res.json()["detail"] == "This is a TBC Anniversary export; this site serves WoW: Forever."
    res = client.post("/api/uploads/paste", headers=LINKED, json={"text": "hello"})
    assert res.status_code == 400
    rows = client.get("/api/uploads", headers=LINKED).json()
    assert [(r["via"], r["outcome"]) for r in rows] == [("paste", "rejected")] * 2
    signed_out = {"Authorization": "Bearer nonsense"}
    assert client.post("/api/uploads/paste", headers=signed_out, json={"text": PASTE}).status_code == 401

    monkeypatch.setattr(uploads, "MAX_BYTES", 100)
    assert client.post("/api/uploads/paste", headers=LINKED, json={"text": "x" * 101}).status_code == 413
    monkeypatch.setattr(uploads, "RATE_LIMIT", 3)
    assert client.post("/api/uploads/paste", headers=LINKED, json={"text": PASTE}).status_code == 429


def test_the_watcher_uploads_with_an_email_sign_in(client: TestClient, conn: Connection) -> None:
    signed_in = {"Authorization": "Bearer password:g1"}  # the ID token Alt Army Sync gets from Firebase
    assert upload(client, "altarmy", ALTARMY_SV, signed_in, via="watcher").status_code == 200
    assert store.count_characters(conn, "g1", FOREVER) == 4
    assert (
        upload(client, "altarmy", ALTARMY_SV, {"Authorization": "Bearer ak_old"}).status_code == 401
    )  # no keys
    assert client.get("/api/keys", headers=LINKED).status_code == 404


def test_users_delete_their_account(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database, conn: Connection
) -> None:
    verifier = FakeVerifier()
    client = make_client(database, game_versions, tmp_path / "nodist", verifier=verifier)
    scan = book_scan({1: [(20, 5)]}, db.utcnow(), "Dreamscythe", "Horde")
    upload(client, "altarmy", ALTARMY_SV + saved_book(scan), LINKED)

    verifier.fail = True
    assert client.delete("/api/me", headers=LINKED).status_code == 502
    assert store.count_characters(conn, "g1", FOREVER) == 4  # rolled back with the Firebase failure

    verifier.fail = False
    assert client.delete("/api/me", headers=LINKED).status_code == 204
    assert verifier.deleted == ["g1"]
    assert store.count_characters(conn, "g1", FOREVER) == 0
    assert conn.execute(select(schema.users.c.uid).where(schema.users.c.uid == "g1")).first() is None
    for table in (schema.uploads, schema.user_settings):
        assert conn.execute(select(table)).first() is None
    snap = schema.price_snapshots
    assert conn.execute(select(snap.c.uploader_uid)).scalars().all() == [None]  # pooled prices stay
    assert conn.execute(select(schema.price_current)).first() is not None


def test_rate_limits_per_user_and_ip(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    limits = ratelimit.Limits(per_ip=5, per_uid=2, window=60)
    client = make_client(database, game_versions, tmp_path / "nodist", limits=limits)
    del client.headers["Authorization"]
    ip1 = {"X-Forwarded-For": "203.0.113.1"}
    assert [client.get("/api/me", headers={**LINKED, **ip1}).status_code for _ in range(3)] == [200, 200, 429]
    res = client.get("/api/me", headers={**FREE, **ip1})  # another user from the same address
    assert res.status_code == 200
    assert [client.get("/api/versions", headers=ip1).status_code for _ in range(2)] == [200, 429]
    assert int(client.get("/api/versions", headers=ip1).headers["Retry-After"]) >= 1
    assert client.get("/api/versions", headers={"X-Forwarded-For": "203.0.113.2"}).status_code == 200


def test_api_responses_are_never_cached(client: TestClient) -> None:
    assert client.get("/api/versions").headers["Cache-Control"] == "no-store"


def test_the_default_database_is_never_migrated(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, game_versions: dict[str, GameVersion]
) -> None:
    """Each deploy migrates, once; `altarmy-site serve` passes a database that migrates."""
    monkeypatch.setenv("DATABASE_URL", db.sqlite_url(tmp_path / "site.sqlite"))
    app = create_app(game_versions, verifier=FakeVerifier(), firebase=FIREBASE)
    assert not app.state.auth.database.migrates


def test_needs_a_firebase_project(
    monkeypatch: pytest.MonkeyPatch, game_versions: dict[str, GameVersion]
) -> None:
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    with pytest.raises(ValueError, match="FIREBASE_PROJECT_ID"):
        create_app(game_versions, verifier=FakeVerifier())


def test_professions(client: TestClient, db2_paths: dict[str, Path], conn: Connection) -> None:
    assert client.get("/api/professions").json() == []
    ingest.build_db(db2_paths, conn, FOREVER)
    assert client.get("/api/professions").json() == ["Tailoring"]


def test_browsing_without_characters(
    client: TestClient, db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    set_prices(conn, {1: 20, 2: 100})
    status = client.get("/api/status").json()
    selection = {"realm": "Classic Beta PvE", "faction": "Horde"}
    assert (status["characters"], status["selection"]) == (0, selection)
    body = client.get("/api/rank").json()
    (r,) = body["results"]
    assert (r["crafter"], r["crafters"], r["mail_to"], body["classes"]) == ("", [], "", {})
    assert {s["who"] for s in r["steps"]} == {""}
    assert client.get("/api/rank", params={"professions": ["tailoring"]}).json()["total"] == 1
    assert client.get("/api/rank", params={"professions": ["Cooking"]}).json()["total"] == 0

    set_prices(conn, {1: 30}, realm="Dreamscythe", faction="Horde")
    res = client.put("/api/selection", json={"realm": "Dreamscythe", "faction": "Horde"})
    assert res.json()["selection"] == {"realm": "Dreamscythe", "faction": "Horde"}
    assert client.put("/api/selection", json={"realm": "Nowhere", "faction": ""}).status_code == 400


def test_skilling_up_a_character_nobody_uploaded(
    client: TestClient,
    db2_paths: dict[str, Path],
    conn: Connection,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    you = "Your character"
    params = {**SKILL_UP, "skill_crafters": [you], "runs": True, "unlearned": "train", "climber_skill": 50}
    assert client.get("/api/rank", params=params).status_code == 400  # no realm has prices: nothing to plan
    set_prices(conn, {1: 20, 2: 100})
    # a pattern teaches the robe from 50: not assumed known, so the climb counts the pattern (price unknown)
    body = client.get("/api/rank", params=params).json()
    (r,) = body["results"]
    assert (r["crafter"], r["crafters"], r["learn_cost"]) == (you, [], None)
    assert body["classes"] == {you: ""} and str(r["recipe_id"]) in body["learn"]
    assert (r["stop_skill"], r["stop_reason"]) == (60, "trivial")
    assert {s["who"] for s in r["steps"]} == {you}
    # a trainer teaches it from 40 instead: known by 50 (trained on the way), not at 35 (nor craftable)
    effects = db2_paths["ItemEffect"]
    rows: list[dict[str, object]] = [
        dict(e, TriggerType="0") if e["SpellID"] == "900" else dict(e) for e in ingest._rows(effects)
    ]
    write_csv(effects, list(rows[0]), rows)
    fees = write_csv(
        tmp_path / "trainer_costs.csv",
        ["spell_id", "cost", "req_skill"],
        [{"spell_id": 900, "cost": 600, "req_skill": 40}],
    )
    ingest.build_db(db2_paths, conn, FOREVER, trainer_costs_csv=fees)
    db.set_build(conn, FOREVER, "test")  # a load, as the ingest job counts one: the markets are rebuilt
    client.app.state.wow[FOREVER].cache.invalidate()  # type: ignore[attr-defined]  # not STAMP_TTL later
    body = client.get("/api/rank", params=params).json()
    (r,) = body["results"]
    assert (r["crafters"], r["learn_cost"], r["learn_skill"]) == ([you], 0, 40)
    assert client.get("/api/rank", params={**params, "climber_skill": 35}).json()["results"] == []
    # planned again as ranked, or for some copies
    plan = {"recipe_id": r["recipe_id"], "choices": {}, "skill_crafters": [you], "runs": True}
    plan |= {"include_trivial": False, "exits": ["vendor", "keep"], "climber_skill": 50}
    got = client.post("/api/evaluate", json=plan).json()["result"]
    assert (got["crafter"], got["crafts"], got["climb_cost"]) == (you, r["crafts"], r["climb_cost"])
    assert client.post("/api/evaluate", json={**plan, "copies": 12}).json()["result"]["crafts"] == 12
    # what the request must say
    bad = [
        {**params, "climber_skill": 301},
        {**params, "skill_crafters": [you, "Another"]},
        {**params, "professions": []},
        {**params, "professions": ["Cooking"]},
    ]
    assert [client.get("/api/rank", params=p).status_code for p in bad] == [400] * 4
    assert client.post("/api/evaluate", json={**plan, "climber_skill": 301}).status_code == 400
    # the same made-up character is ranked once for everyone
    calls: list[int] = []
    search = service.search

    def spy(*args: Any, **kwargs: Any) -> Any:
        calls.append(1)
        return search(*args, **kwargs)

    monkeypatch.setattr(service, "search", spy)
    client.get("/api/rank", params=params)
    client.get("/api/rank", params=params, headers=LINKED)
    assert calls == []


def test_serves_the_front_end_for_its_own_pages(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dist = tmp_path / "dist"
    (dist / "assets").mkdir(parents=True)
    (dist / "index.html").write_text("<html>app</html>")
    (dist / "assets" / "app.js").write_text("js")
    client = make_client(database, game_versions, dist)
    pages = (
        "/addon",
        "/profit",
        "/profit/gold",
        "/profit/skill/dreamscythe-horde/Tailor%20Guy/tailoring",
        "/profit/skill/dreamscythe-horde/tailoring/45",
    )
    for page in (*pages, "/manage", "/admin"):
        assert client.get(page).text == "<html>app</html>"
    assert client.get("/assets/app.js").text == "js"
    assert client.get("/assets/missing.js").status_code == 404
    assert client.get("/api/nope").status_code == 404
    assert "app" not in client.get("/api/nope").text


# --- admin -----------------------------------------------------------------------------------------------
def test_the_admin_page_is_for_admins_only(client: TestClient) -> None:
    assert client.get("/api/me", headers=ADMIN).json() == {"uid": "a1", "tier": "linked", "admin": True}
    for headers in (FREE, LINKED, SIGNED_IN):
        assert client.get("/api/admin/ingestion", headers=headers).status_code == 403
    assert client.get("/api/admin/ingestion", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert client.get("/api/admin/ingestion", headers=ADMIN).status_code == 200


def test_everyone_is_an_admin_against_the_auth_emulator(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database
) -> None:
    dev = make_client(database, game_versions, tmp_path, firebase=EMULATOR)
    for headers in (FREE, LINKED, SIGNED_IN):
        assert dev.get("/api/me", headers=headers).json()["admin"]
        assert dev.get("/api/admin/ingestion", headers=headers).status_code == 200
    assert dev.get("/api/admin/ingestion", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_the_admin_page_shows_jobs_uploads_and_snapshots(client: TestClient, conn: Connection) -> None:
    now = db.utcnow()
    run_id = jobs.start(conn, "merge", now=now)
    jobs.finish(conn, run_id, True, "Merged 1 auction houses", now=now)
    jobs.start(conn, "ingest", "tbc", now=now)  # another version's: not shown
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "watcher", 10, "accepted", "2 prices", now=now)
    uploads.record_upload(conn, ME, "tbc", "auctionator", "watcher", 10, "accepted", "", now=now)
    scanned(conn, {1: [(10, 1)]}, now)
    got = client.get("/api/admin/ingestion", headers=ADMIN).json()
    assert got["now"] >= db.timestamp_text(now)
    status = {j["job"]: j for j in got["jobs"]}
    assert list(status) == list(jobs.CADENCE)
    assert status["merge"]["ok"] and not status["merge"]["late"]
    assert status["merge"]["summary"] == "Merged 1 auction houses"
    assert status["ingest"] == {
        "job": "ingest",
        "game_version": None,
        "last_started": None,
        "last_finished": None,
        "ok": None,
        "late": True,
        "summary": "",
    }
    assert [r["job"] for r in got["runs"]] == ["merge"]
    assert got["uploads"]["accepted_24h"] == 1 and got["uploads"]["uploaders_7d"] == 1
    assert [(u["user_uid"], u["detail"]) for u in got["uploads"]["recent"]] == [(ME, "2 prices")]
    ((source, stats),) = [(s["source"], s) for s in got["snapshots"]]
    assert (source, stats["snapshots_24h"], stats["items_7d"]) == ("altarmy", 1, 1)
    assert "feeds" not in got
    assert got["can_run"] == ["ingest"]


def test_admins_start_the_ingest(
    tmp_path: Path, game_versions: dict[str, GameVersion], database: db.Database, conn: Connection
) -> None:
    launcher = FakeLauncher()
    c = make_client(database, game_versions, tmp_path, launcher=launcher)
    for headers in (FREE, LINKED, SIGNED_IN):
        assert c.post("/api/admin/jobs/ingest", headers=headers).status_code == 403
    got = c.post("/api/admin/jobs/ingest", headers=ADMIN)
    assert got.status_code == 202
    assert got.json() == {"job": "ingest", "game_version": FOREVER, "detail": "Started forever."}
    assert c.post("/api/admin/jobs/ingest", headers=ADMIN, params={"game_version": "tbc"}).is_success
    assert launcher.started == [FOREVER, "tbc"]
    run_id = jobs.start(conn, "ingest", FOREVER)  # the run it started is going
    assert c.post("/api/admin/jobs/ingest", headers=ADMIN).status_code == 409
    assert launcher.started == [FOREVER, "tbc"]
    jobs.finish(conn, run_id, True, "")
    assert c.post("/api/admin/jobs/ingest", headers=ADMIN).status_code == 202


def test_the_ingest_says_why_it_could_not_start(
    tmp_path: Path,
    game_versions: dict[str, GameVersion],
    database: db.Database,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    broken = make_client(database, game_versions, tmp_path, launcher=FakeLauncher("No Cloud Run job."))
    got = broken.post("/api/admin/jobs/ingest", headers=ADMIN)
    assert (got.status_code, got.json()["detail"]) == (502, "No Cloud Run job.")
    monkeypatch.setattr(launch, "from_env", lambda database: None)  # a hosted service without the jobs' names
    app = create_app(
        game_versions, database=database, static_dir=None, verifier=FakeVerifier(), firebase=FIREBASE
    )
    nowhere = TestClient(app, headers=ADMIN)
    assert nowhere.post("/api/admin/jobs/ingest", params={"game_version": FOREVER}).status_code == 501
    assert nowhere.get("/api/admin/ingestion", params={"game_version": FOREVER}).json()["can_run"] == []


# --- profit per hour ----------------------------------------------------------------------------------
def test_time_settings_round_trip(client: TestClient, priced: Connection, cities: Path) -> None:
    got = client.get("/api/time").json()
    assert [c["name"] for c in got["cities"]] == ["Orgrimmar", "Thunder Bluff"]  # Horde's; no neutral town
    assert (got["city"], got["active"]) == (None, None)  # whatever is fastest
    assert got["config"] == got["defaults"]
    assert got["defaults"]["batch"] == 10
    put = client.put("/api/time", json={"city": "Thunder Bluff", "config": {"batch": 5, "time_value": 10**6}})
    assert put.status_code == 200
    assert (put.json()["city"], put.json()["active"]) == ("Thunder Bluff", "Thunder Bluff")
    assert (put.json()["config"]["batch"], put.json()["config"]["time_value"]) == (5, 10**6)
    assert client.get("/api/time").json() == put.json()
    for bad in [
        {"city": "Atlantis"},
        {"city": "Booty Bay"},
        {"config": {"batch": 0}},
        {"config": {"nope": 1}},
    ]:
        assert client.put("/api/time", json=bad).status_code == 400
    reset = client.put("/api/time", json={}).json()
    assert (reset["city"], reset["config"]) == (None, reset["defaults"])


def test_rank_reports_profit_per_hour(client: TestClient, priced: Connection, cities: Path) -> None:
    (r,) = client.get("/api/rank").json()["results"]
    t = r["timing"]
    # by default each plan is timed in the fastest Horde city: Thunder Bluff has the anvil and the vendor
    assert (t["city"], r["crafts"]) == ("Thunder Bluff", 10)
    assert t["total_seconds"] == pytest.approx(t["fixed_seconds"] + t["per_craft_seconds"])
    assert t["per_hour"] == round(10 * 200 * 3600 / t["total_seconds"])
    assert set(t["breakdown"]) >= {"travel", "craft", "ah", "vendor"}
    # collect the AH purchases, craft at the anvil, sell the robe to the vendor, and stop there
    assert [leg["to_name"] for leg in t["legs"]] == ["Mailbox", "Anvil", "Thread Seller"]
    assert [c["city"] for c in r["cities"]] == ["Orgrimmar", "Thunder Bluff"]
    assert r["best_city"] == "Thunder Bluff"
    # the robe is crafted at an anvil, which Orgrimmar lacks here: noted, not timed, never the pick
    assert (t["missing"], r["cities"][0]["missing"], r["cities"][1]["missing"]) == ([], ["anvil"], [])
    client.put("/api/time", json={"city": "Orgrimmar"})  # a chosen city is used as it is
    (there,) = client.get("/api/rank").json()["results"]
    assert (there["timing"]["city"], there["timing"]["missing"]) == ("Orgrimmar", ["anvil"])
    assert [leg["to_name"] for leg in there["timing"]["legs"]] == ["Mailbox", "Thread Seller"]
    client.put("/api/time", json={})
    craft = next(s for s in r["steps"] if s["action"] == "craft")
    assert craft["seconds"] == pytest.approx(35) and craft["station"] == "anvil"  # 10 3 s casts at an anvil
    assert r["tree"]["seconds"] > 0 and r["tree"]["inputs"][0]["options"][0]["seconds"] > 0
    by_rate = client.get("/api/rank", params={"sort": "rate"}).json()["results"]
    assert [x["recipe_id"] for x in by_rate] == [r["recipe_id"]]


def test_rank_times_anywhere_without_presets(client: TestClient, priced: Connection) -> None:
    (r,) = client.get("/api/rank").json()["results"]
    assert r["timing"]["city"] == "Anywhere"
    assert r["timing"]["breakdown"]["travel"] == 0
    assert (r["cities"], r["best_city"]) == ([], None)
    assert client.get("/api/time").json()["cities"] == []


def test_evaluate_uses_the_time_settings(client: TestClient, priced: Connection, cities: Path) -> None:
    client.put("/api/time", json={"city": "Thunder Bluff", "config": {"batch": 4}})
    body = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}}).json()
    assert (body["result"]["timing"]["city"], body["result"]["crafts"]) == ("Thunder Bluff", 4)


def test_guests_keep_their_own_time_settings(client: TestClient, conn: Connection) -> None:
    assert client.put("/api/time", json={"config": {"batch": 2}}, headers=FREE).status_code == 200
    assert client.get("/api/time", headers=FREE).json()["config"]["batch"] == 2


def test_evaluate_plans_a_session_spelled_out(client: TestClient, priced: Connection, cities: Path) -> None:
    body = {"recipe_id": 100, "choices": {}, "copies": 20, "city": "Thunder Bluff"}
    r = client.post("/api/evaluate", json=body).json()["result"]
    assert (r["crafts"], r["cost"], r["revenue"], r["profit"]) == (20, 20 * 300, 20 * 500, 20 * 200)
    assert r["timing"]["city"] == "Thunder Bluff"
    assert r["timing"]["per_hour"] == round(20 * 200 * 3600 / r["timing"]["total_seconds"])
    said = []
    for d in r["details"]:
        if d["kind"] == "step":
            s = r["steps"][d["step"]]
            said.append((s["action"], s["name"], s["quantity"]))
        else:
            loc = d["location"]
            said.append((d["kind"], loc["name"], [(i["item_id"], i["count"]) for i in d["retrieve"]]))
    assert said == [
        ("start", "Auctioneer", []),
        ("buy", "Linen Cloth", 200),
        ("buy", "Coarse Thread", 20),
        ("go", "Mailbox", [(1, 200), (2, 20)]),
        ("go", "Anvil", []),
        ("craft", "Green Robe", 20),
        ("go", "Thread Seller", []),
        ("sell", "Green Robe", 20),
    ]
    assert r["details"][0]["seconds"] == 0
    anvil = r["details"][4]["location"]
    assert (anvil["kind"], anvil["map_x"], anvil["map_y"], anvil["map_area"]) == ("anvil", 49.0, 50.0, 1638)
    # without copies or a city: the time settings' batch, exactly as the ranking has it
    (ranked,) = client.get("/api/rank").json()["results"]
    default = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}}).json()["result"]
    assert (default["crafts"], default["details"] != []) == (10, True)
    assert default == ranked


@pytest.fixture
def honored(db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path) -> Connection:
    """Vendors sell thread (11c); the selected tailor is Honored with Thunder Bluff and only Friendly with
    Orgrimmar."""
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    set_prices(conn, {1: 20, 2: 100})
    chars = [
        replace(c, reputations=((76, 5), (81, 6))) if c.name == "Tailor Guy" else c
        for c in altarmy.parse_characters(ALTARMY_SV)
    ]
    store.save_characters(conn, ME, FOREVER, chars)
    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")
    return conn


def test_rank_prices_vendor_buys_by_reputation(client: TestClient, honored: Connection, cities: Path) -> None:
    def thread_of(result: dict[str, Any]) -> tuple[object, ...]:
        s = next(s for s in result["steps"] if s["name"] == "Coarse Thread")
        return (s["via"], s["value"], s["rep_discount"], s["rep_faction"], s["discount"])

    (r,) = client.get("/api/rank").json()["results"]
    assert thread_of(r) == ("vendor", -100, 10, "Thunder Bluff", 0)  # 11c less 10%, rounded up: 10c each
    node = r["tree"]["inputs"][1]
    assert (node["rep_discount"], node["rep_faction"], node["cost"]) == (10, "Thunder Bluff", 100)
    assert (r["timing"]["city"], r["profit"]) == ("Thunder Bluff", 10 * (500 - 200 - 10))
    # each city's own numbers: Orgrimmar's vendor gives a Friendly buyer nothing off
    assert [(c["city"], c["profit"]) for c in r["cities"]] == [("Orgrimmar", 2890), ("Thunder Bluff", 2900)]
    assert r["best_city"] == "Thunder Bluff"
    assert client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}}).json()["result"] == r
    # asked for Orgrimmar, the plan is priced there; the table still says what it makes in Thunder Bluff
    body = {"recipe_id": 100, "choices": {}, "city": "Orgrimmar"}
    there = client.post("/api/evaluate", json=body).json()["result"]
    assert thread_of(there) == ("vendor", -110, 0, "", 0)
    assert [(c["city"], c["profit"]) for c in there["cities"]] == [
        ("Orgrimmar", 2890),
        ("Thunder Bluff", 2900),
    ]
    (tailor,) = client.get("/api/characters").json()["groups"][1]["characters"]
    assert tailor["vendor_discounts"] == [{"faction": "Thunder Bluff", "percent": 10}]


def test_evaluate_refuses_a_city_the_characters_dont_craft_in(
    client: TestClient, priced: Connection, cities: Path
) -> None:
    for city in ("Stormwind", "Booty Bay", "Atlantis"):
        got = client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}, "copies": 5, "city": city})
        assert got.status_code == 400
    assert (
        client.post("/api/evaluate", json={"recipe_id": 100, "choices": {}, "copies": 0}).status_code == 422
    )


def add_enchant(conn: Connection) -> None:
    """An Enchanting enchant taking 2 linen (20 each), yellow at 100 and grey at 140, which Enchy (skill 60)
    on the tailor's realm knows."""
    conn.execute(
        schema.recipes.insert().values(
            game_version=FOREVER,
            id=110,
            spell_id=970,
            name="Enchant Bracer - Minor Health",
            kind="enchant",
            skill_line=333,
            skill_name="Enchanting",
            trivial_low=100,
            trivial_high=140,
            output_item_id=0,
        )
    )
    conn.execute(
        schema.recipe_reagents.insert().values(
            game_version=FOREVER, recipe_id=110, item_id=1, count=2, slot=0
        )
    )
    enchanter = Character(
        "Classic Beta PvE",
        "Enchy",
        "Horde",
        "PRIEST",
        20,
        (Profession("Enchanting", 60, 75, frozenset({970})),),
    )
    store.save_characters(conn, ME, FOREVER, [*altarmy.parse_characters(ALTARMY_SV), enchanter])


def test_rank_and_evaluate_enchants_cast_for_the_skill_point_alone(
    client: TestClient, priced: Connection
) -> None:
    add_enchant(priced)
    one_craft(client)

    def enchants(**params: bool | str | list[str]) -> list[dict[str, Any]]:
        results = client.get("/api/rank", params=params).json()["results"]
        return [r for r in results if r["kind"] == "enchant"]

    assert enchants() == []  # only when asked for
    (r,) = enchants(exits=["vendor", "skill"], sort="skill")
    assert (r["recipe"], r["output_name"], r["output_item_id"]) == (
        "Enchant Bracer - Minor Health",
        "Enchant Bracer - Minor Health",
        0,
    )
    assert (r["profession"], r["crafters"], r["crafter"]) == ("Enchanting", ["Enchy"], "Enchy")
    assert (r["cost"], r["revenue"], r["profit"], r["roi"], r["best_exit"]) == (40, 0, -40, -1.0, "skill")
    assert (r["skill_chance"], r["skill_ups"], r["slow"]) == (1.0, 1.0, False)
    assert [(s["action"], s["name"], s["enchant"]) for s in r["steps"]] == [
        ("buy", "Linen Cloth", False),
        ("craft", "Enchant Bracer - Minor Health", True),
    ]
    assert r["tree"]["enchant"] is True
    # the robe still sells its own way beside it
    both = client.get("/api/rank", params={"exits": ["vendor", "skill"]}).json()["results"]
    assert sorted((b["kind"], b["best_exit"]) for b in both) == [("craft", "vendor"), ("enchant", "skill")]

    body = {"recipe_id": 110, "exits": ["skill"], "choices": {}}
    got = client.post("/api/evaluate", json=body).json()["result"]
    assert (got["kind"], got["profit"], got["best_exit"]) == ("enchant", -40, "skill")
    assert client.post("/api/evaluate", json={**body, "exits": ["vendor"]}).status_code == 404


def test_skill_up_with_a_gathered_reagent(client: TestClient, priced: Connection) -> None:
    calls: list[int] = []
    params = {**SKILL_UP, "runs": True}
    (r,) = client.get("/api/rank", params={**params, "gathered": [1]}).json()["results"]
    linen = next(s for s in r["steps"] if s["item_id"] == 1)
    # what selling it nets, 20 less the cut, for 10 linen a robe over the run
    assert (linen["action"], linen["value"]) == ("gather", -r["crafts"] * 10 * 19)
    (bought,) = client.get("/api/rank", params=params).json()["results"]
    assert bought["cost"] > r["cost"]
    del calls
    body = {"recipe_id": r["recipe_id"], "choices": {}, "skill_crafters": ["Tailor Guy"], "gathered": [1]}
    got = client.post("/api/evaluate", json=body).json()["result"]
    assert next(s for s in got["steps"] if s["item_id"] == 1)["action"] == "gather"


def test_skill_up_counts_the_pattern_and_says_what_comes_next(client: TestClient, priced: Connection) -> None:
    src = {"game_version": FOREVER, "item_id": 3, "chance": 0.0, "count": 0, "levels": "", "limited": True}
    src |= {"area": 0, "map_x": 0.0, "map_y": 0.0, "seq": 0, "kind": "vendor", "name": "Borya"}
    priced.execute(insert(schema.item_sources), [{**src, "zone": "Orgrimmar", "side": "horde"}])
    priced.execute(update(schema.items).where(schema.items.c.id == 3).values(buy_price=2000, buy_count=1))
    low = Character("Realm", "Low", "Horde", "MAGE", 60, (Profession("Tailoring", 40, 150, frozenset()),))
    service.replace_characters(priced, ME, FOREVER, [low])
    set_prices(priced, {1: 20, 2: 100}, realm="Realm")
    # at 40 the robe (learned at 50) can't give them the next point: no run of it to rank, look-ahead or not
    ahead = {**SKILL_UP, "skill_crafters": ["Low"], "runs": True, "unlearned": "train", "look_ahead": 10}
    assert client.get("/api/rank", params=ahead).json()["results"] == []
    low = replace(low, professions=(Profession("Tailoring", 50, 150, frozenset()),))
    service.replace_characters(priced, ME, FOREVER, [low])
    params = {**SKILL_UP, "skill_crafters": ["Low"], "runs": True, "unlearned": "train"}
    body = client.get("/api/rank", params=params).json()
    (r,) = body["results"]
    assert r["learn_cost"] == 2000  # the pattern, from Borya
    (taught,) = body["learn"][str(r["recipe_id"])]["items"]
    assert (taught["price"], taught["limited"]) == (2000, True)
    assert body["chain"] == []  # one recipe: nothing after it
    # the chain follows the run asked for; one the ranking doesn't hold has none
    chained = {**params, "chain_from": r["recipe_id"]}
    assert client.get("/api/rank", params=chained).json()["chain"] == []
    assert client.get("/api/rank", params={**params, "chain_from": 999999}).json()["chain"] == []
    # a longer chain on asking, up to a bound
    assert client.get("/api/rank", params={**params, "chain_length": 8}).json()["chain"] == []
    assert (
        client.get("/api/rank", params={**params, "chain_length": api.MAX_SKILL_CHAIN + 1}).status_code == 422
    )
    service.replace_characters(
        priced, ME, FOREVER, [replace(low, professions=(Profession("Tailoring", 50, 150, frozenset({900})),))]
    )
    (known,) = client.get("/api/rank", params=params).json()["results"]
    assert known["learn_cost"] == 0


def test_events_are_logged_without_who_sent_them(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level("INFO", logger="altarmy_site.events"):
        got = client.post("/api/events", json={"name": "next_up_shown", "props": {"profession": "Tailoring"}})
    assert got.status_code == 204
    (record,) = [r for r in caplog.records if r.name == "altarmy_site.events"]
    line = json.loads(record.getMessage())
    assert line == {"event": "next_up_shown", "game_version": "forever", "profession": "Tailoring"}  # no user
    assert client.post("/api/events", json={"name": "anything"}).status_code == 422


def test_rank_says_what_playing_it_safe_and_the_auction_house_make(
    client: TestClient, priced: Connection
) -> None:
    scanned_robe(priced, 1000, 1000)  # one robe listed, nothing seen sold: the market takes 1 of 10
    (r,) = client.get("/api/rank").json()["results"]
    # ten robes: a vendor pays 500 each; the AH nets 950 for the one it takes, the other nine go to a vendor
    assert (r["safe_profit"], r["safe_exit"]) == (5000 - 3000, "vendor")
    assert (r["ah_profit"], r["ah_depth_units"], r["ah_excess_units"]) == (950 + 9 * 500 - 3000, 1, 9)
    assert (r["likely_profit"], r["likely_exit"]) == (r["ah_profit"], "ah")
    assert "verdict" not in r and r["buy_flags"] == []
    vendor_only = client.get("/api/rank", params={"exits": ["vendor"]}).json()["results"][0]
    assert (vendor_only["safe_profit"], vendor_only["ah_profit"]) == (2000, None)
    for sort in ("all_sell", "roi", "spend", "profit_each", "safe", "ah"):
        assert client.get("/api/rank", params={"sort": sort}).json()["total"] == 1
    for sort in ("safe", "ah"):  # worst first too
        assert client.get("/api/rank", params={"sort": sort, "order": "asc"}).json()["total"] == 1
    assert client.get("/api/rank", params={"sort": "safe", "order": "up"}).status_code == 422


def test_a_recipe_the_climb_took_up_before_is_not_learned_again() -> None:
    def run(recipe_id: int) -> api.RankResult:
        return api.RankResult.model_construct(
            recipe_id=recipe_id, crafter="Low", crafters=[], learn_cost=2000
        )

    belt, pants, again, first_again = run(2), run(3), run(2), run(1)
    api._learned_on_the_way(1, [belt, pants, again, first_again])
    assert [(r.learn_cost, r.crafters) for r in (belt, pants)] == [(2000, []), (2000, [])]  # new to the climb
    assert [(r.learn_cost, r.crafters) for r in (again, first_again)] == [(0, ["Low"]), (0, ["Low"])]
