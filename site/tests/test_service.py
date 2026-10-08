import os
import threading
from collections.abc import Sequence
from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import Connection

from altarmy_site import altarmy, book, db, engine, ingest, prices, service, store, talents, timing, users
from altarmy_site.altarmy import Character, Profession
from altarmy_site.engine import ALL_EXITS, Filters
from altarmy_site.service import Selection

from .conftest import FOREVER, ME, scanned, set_prices
from .test_altarmy import ALTARMY_SV


def chars(*names: str) -> list[Character]:
    return [c for c in altarmy.parse_characters(ALTARMY_SV) if not names or c.name in names]


def touch(path: Path) -> None:
    """Move the mtime forward a second (a rewrite within the clock's resolution may not change it)."""
    st = path.stat()
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))


def test_search_ranks_known_recipes_or_whole_professions(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))

    profitable = Filters(min_profit=0)
    (r,) = service.search(base, chars("Tailor Guy"), "none", profitable)
    assert r.profit == 200
    assert service.search(base, chars("Tailor Guy"), "none", Filters(min_profit=201)) == []
    assert service.search(base, chars("Tailor Guy"), "none", Filters(max_cost=299)) == []
    assert service.search(base, chars("Tailor Guy"), "none", profitable, exits=frozenset({"ah"})) == []
    assert service.search(base, chars("Frell", "Ally Alt"), "none", profitable) == []
    (browsed,) = service.search(base, [], "none", profitable)  # no characters: every recipe, nobody named
    assert (browsed.recipe.name, browsed.crafter, browsed.postage) == ("Green Robe", "", 0)

    (tailor,) = chars("Tailor Guy")
    novice = replace(tailor, professions=(Profession("Tailoring", 1, 75, frozenset()),))
    assert service.search(base, [novice], "none", profitable) == []
    unlearned = service.search(base, [novice], "all", profitable)
    assert [r.recipe.name for r in unlearned] == ["Green Robe"]


def test_search_and_evaluate_without_trivial_recipes(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))
    (tailor,) = chars("Tailor Guy")  # Tailoring 50: the robe turns grey at 60
    (robe,) = base.recipes
    profitable = Filters(min_profit=0)
    assert len(service.search(base, [tailor], "none", profitable, include_trivial=False)) == 1

    (p,) = [p for p in tailor.professions if p.name == "Tailoring"]
    veteran = replace(tailor, professions=(replace(p, rank=60, max_rank=150),))
    assert len(service.search(base, [veteran], "none", profitable)) == 1
    assert service.search(base, [veteran], "none", profitable, include_trivial=False) == []
    assert service.evaluate(base, [veteran], "none", ALL_EXITS, robe.id, {}, include_trivial=False) is None


def test_evaluate_applies_choices(db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))  # vendors sell thread for 11c
    best = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {})
    assert best is not None
    assert (best.cost, best.tree.inputs[1].source) == (211, "vendor")
    chosen = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {"r.1": "ah"})
    assert chosen is not None
    assert (chosen.cost, chosen.tree.inputs[1].source) == (300, "ah")
    assert service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 999, {}) is None
    assert service.evaluate(base, chars("Frell"), "none", ALL_EXITS, 100, {}) is None


def test_legacy_talents_reach_the_engine(
    db2_paths: dict[str, Path], conn: Connection, vendor_csv: Path
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER, vendor_csv=vendor_csv)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))  # vendors sell thread for 11c
    (tailor,) = chars("Tailor Guy")
    barterer = replace(tailor, talents=((talents.BARTERING, 2),))
    got = service.evaluate(base, [barterer], "none", ALL_EXITS, 100, {})
    assert got is not None
    assert (got.cost, got.tree.inputs[1].discount) == (200 + 10, 10)  # 11c less 10%, rounded up
    (crafter,) = service.as_crafters([replace(tailor, talents=((talents.WORKING_OVERTIME, 5),))])
    assert crafter.skill_bonus == pytest.approx(0.2)


def test_search_and_evaluate_never_sell_blocked_items_on_the_ah(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    # the robe: 950 on the AH beats 500 at a vendor
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100, 3: 1000}))
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters())
    assert r.best_exit == "ah"
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters(), no_ah=frozenset({3}))
    assert (r.best_exit, [e.kind for e in r.exits]) == ("vendor", ["vendor"])
    got = service.evaluate(base, chars("Tailor Guy"), "none", ALL_EXITS, 100, {}, no_ah=frozenset({3}))
    assert got is not None
    assert got.best_exit == "vendor"


def test_search_without_min_profit_keeps_losses(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 100, 2: 100}))  # 10 linen > the robe
    assert service.search(base, chars("Tailor Guy"), "none", Filters(min_profit=0)) == []
    (r,) = service.search(base, chars("Tailor Guy"), "none", Filters())
    assert r.profit < 0


@pytest.mark.parametrize(
    ("realms", "realm", "faction", "key"),
    [
        (["ClassicBetaPvE", "ClassicBetaPvP2"], "Classic Beta PvE", "Horde", "ClassicBetaPvE"),
        (["ClassicBetaPvE", "ClassicBetaPvP2"], "Classic Beta PvP 2", "Alliance", "ClassicBetaPvP2"),
        (["Dreamscythe Alliance", "Dreamscythe Horde"], "Dreamscythe", "Horde", "Dreamscythe Horde"),
        (["Defias Pillager Alliance"], "Defias Pillager", "Alliance", "Defias Pillager Alliance"),
        (["Atiesh"], "Dreamscythe", "Horde", None),
    ],
)
def test_match_auctionator_realm(realms: list[str], realm: str, faction: str, key: str | None) -> None:
    assert service.match_auctionator_realm(realms, realm, faction) == key


def test_selection_defaults_to_biggest_group_then_remembers(conn: Connection) -> None:
    assert service.selection(conn, ME, FOREVER, []) is None
    assert service.selected_characters(conn, ME, FOREVER) == (None, [])
    store.save_characters(conn, ME, FOREVER, chars())
    assert service.selection(conn, ME, FOREVER, chars()) == Selection("Dreamscythe", "Horde")

    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")
    sel, selected = service.selected_characters(conn, ME, FOREVER)
    assert sel == Selection("Classic Beta PvE", "Horde")
    assert [c.name for c in selected] == ["Tailor Guy"]
    with pytest.raises(ValueError, match="Nowhere"):
        service.select(conn, ME, FOREVER, "Nowhere", "Horde")

    store.save_characters(conn, ME, FOREVER, chars("Frell"))  # the selected realm is gone from the file
    assert service.selection(conn, ME, FOREVER, chars("Frell")) == Selection("Dreamscythe", "Horde")


def current(conn: Connection) -> dict[int, int]:
    """The selected realm/faction's current prices."""
    return prices.load_current(conn, service.selected_auction_house(conn, ME, FOREVER))


def test_market_cache_reloads_only_after_invalidate(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {})
    cache = service.MarketCache(database, FOREVER)
    first = cache.get(ah)
    assert cache.get(ah) is first
    assert cache.get(None) is not first  # one market per auction house
    prices.set_price(conn, ah, 1, 5)
    assert cache.get(ah).prices == {}
    cache.invalidate()
    assert cache.get(ah).prices == {1: 5}
    assert len(cache.get(ah).recipes) == 1


def test_market_cache_sees_other_processes_changes_after_its_ttl(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    """Another instance (or an ingest job) changed prices or game data: the stamp check reloads."""
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    now = [0.0]
    cache = service.MarketCache(database, FOREVER, clock=lambda: now[0])
    first = cache.get(ah)
    prices.set_price(conn, ah, 1, 7)  # as another instance's upload would
    now[0] += service.STAMP_TTL / 2
    assert cache.get(ah) is first  # checked at most every STAMP_TTL seconds
    now[0] += service.STAMP_TTL
    assert cache.get(ah).prices == {1: 7}
    second = cache.get(ah)
    now[0] += service.STAMP_TTL * 2
    assert cache.get(ah) is second  # nothing changed: kept
    db.set_build(conn, FOREVER, "1.60.2.1")  # a game data update
    now[0] += service.STAMP_TTL * 2
    third = cache.get(ah)
    assert third is not second
    db.set_build(conn, FOREVER, "1.60.2.1")  # the same build loaded again (ingest --force)
    now[0] += service.STAMP_TTL * 2
    assert cache.get(ah) is not third


def test_market_cache_checks_at_once_for_a_newer_price_version(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    """The front end heard of new prices (a price signal): its request must not get the old market, even
    within STAMP_TTL of the last check."""
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    now = [0.0]
    cache = service.MarketCache(database, FOREVER, clock=lambda: now[0])
    first = cache.get(ah)
    known = prices.price_version(conn, ah)
    assert known is not None
    assert cache.get(ah, at_least=known) is first  # the version it has: no check
    prices.set_price(conn, ah, 1, 7)  # as another instance's upload would
    assert cache.get(ah) is first  # within the TTL
    assert cache.get(ah, at_least=known + 1).prices == {1: 7}


def test_market_cache_keeps_no_market_a_rebuild_read_before_an_invalidate(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An upload invalidates the house while another request is rebuilding it from what it read before the
    upload: that request gets its market, but it is not kept, and the next request reads the new prices."""
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    cache = service.MarketCache(database, FOREVER)
    loading, release = threading.Event(), threading.Event()
    load = store.load_priced

    def slow(*args: Any, **kwargs: Any) -> store.Priced:
        got = load(*args, **kwargs)
        loading.set()
        release.wait(5)
        return got

    monkeypatch.setattr(store, "load_priced", slow)
    out: list[engine.Market] = []
    worker = threading.Thread(target=lambda: out.append(cache.get(ah)))
    worker.start()
    assert loading.wait(5)
    prices.set_price(conn, ah, 1, 7)  # the upload, committed after that rebuild read
    cache.invalidate([ah])
    release.set()
    worker.join(5)
    assert out[0].prices == {1: 5}  # the request that was rebuilding gets what it read
    monkeypatch.setattr(store, "load_priced", load)
    assert cache.get(ah).prices == {1: 7}  # but it was not kept


def test_market_cache_serves_the_market_it_has_while_another_request_checks_it(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    now = [0.0]
    cache = service.MarketCache(database, FOREVER, clock=lambda: now[0])
    first = cache.get(ah)
    other = cache.get(None)
    now[0] += service.STAMP_TTL * 2  # due a check
    house = cache._houses[ah]
    with house.building:  # another request checking or rebuilding it
        assert cache.get(ah) is first  # not blocked: the market there is
        assert cache.get(None) is other  # nor is another house
        known = prices.price_version(conn, ah)
        assert known is not None
        # one who knows of newer prices waits for the rebuild instead (here: times out on the held lock)
        waiter = threading.Thread(target=lambda: cache.get(ah, at_least=known + 1), daemon=True)
        waiter.start()
        waiter.join(0.2)
        assert waiter.is_alive()
    waiter.join(5)
    assert not waiter.is_alive()


def test_market_cache_hands_out_a_token_of_what_the_market_was_built_from(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 5})
    cache = service.MarketCache(database, FOREVER)
    first = cache.get_held(ah)
    cache.invalidate()
    again = cache.get_held(ah)
    assert again.priced is not first.priced and again.token == first.token  # rebuilt from the same data
    prices.set_price(conn, ah, 1, 7)
    cache.invalidate()
    assert cache.get_held(ah).token != first.token
    assert cache.get_held(None).token != first.token  # another house


def test_flights_run_identical_work_once_at_a_time() -> None:
    flights = service.Flights()
    cached: dict[str, int] = {}
    made: list[int] = []
    started, go = threading.Event(), threading.Event()

    def work() -> int:
        if "x" not in cached:  # what the first one leaves, the others find
            started.set()
            go.wait(5)
            made.append(1)
            cached["x"] = 42
        return cached["x"]

    got: list[int] = []
    threads = [threading.Thread(target=lambda: got.append(flights.run("k", work))) for _ in range(5)]
    threads[0].start()
    assert started.wait(5)
    for t in threads[1:]:
        t.start()
    go.set()
    for t in threads:
        t.join(5)
    assert got == [42] * 5 and made == [1]
    assert flights.run("other", lambda: 7) == 7  # another key runs at once


def test_flights_pass_the_first_callers_error_to_those_waiting() -> None:
    flights = service.Flights()
    started, go = threading.Event(), threading.Event()

    def fails() -> int:
        started.set()
        go.wait(5)
        raise ValueError("no")

    errors: list[str] = []

    def call(work: Any) -> None:
        try:
            flights.run("k", work)
        except ValueError as e:
            errors.append(str(e))

    first = threading.Thread(target=call, args=(fails,))
    first.start()
    assert started.wait(5)
    waiting = threading.Event()
    leading = flights._running["k"]
    real_result = leading.result

    def result(timeout: float | None = None) -> None:
        waiting.set()  # the second caller is waiting on the first
        return real_result(timeout)

    leading.result = result  # type: ignore[method-assign]
    second = threading.Thread(target=call, args=(lambda: 1,))
    second.start()
    assert waiting.wait(5)
    go.set()
    first.join(5)
    second.join(5)
    assert errors == ["no", "no"]  # the waiter got the first caller's error, not its own result
    assert flights.run("k", lambda: 3) == 3  # nothing left behind: the key runs again


def test_market_cache_keeps_the_listings_with_its_market(
    db2_paths: dict[str, Path], conn: Connection, database: db.Database
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    now = db.utcnow()
    ah = scanned(conn, {1: [(20, 3)]}, now)
    cache = service.MarketCache(database, FOREVER)
    priced = cache.get_priced(ah)
    assert priced.market is cache.get(ah)  # the one rankings are cached on
    first = priced.listings[1]
    assert (first.min_buyout, first.quantity, first.ladder) == (20, 3, (book.Level(20, 3, 1),))
    assert priced.watched == 0.0
    later = now + timedelta(minutes=1)
    scanned(conn, {1: [(20, 7)]}, later)
    cache.invalidate()
    again = cache.get_priced(ah)
    assert (again.listings[1].quantity, again.listings[1].ladder) == (7, (book.Level(20, 7, 1, age=1),))
    assert round(again.watched * 60) == 1  # the two scans a minute apart
    assert cache.get_priced(None).listings == {}


def test_price_confidence_is_for_the_plans_ah_sale() -> None:
    recipe = engine.Recipe(1, "Green Robe", 3, output_count=2)
    tree = engine.Node(3, "Green Robe", 1, 100)
    sale = engine.Result(recipe, 100, 500, "ah", tree, crafts=5)
    # 10 seen sold over the week in two pairs of scans of a house watched long enough; the plan sells 2 x 5
    sold = {
        3: prices.Listing(
            900, 50, sale_rate=10 / 7, sale_price=900, median_7d=900, scans_7d=5, sold_pairs_7d=2
        )
    }
    watched = prices.WATCHED_ENOUGH_HOURS
    got = service.price_confidence(sale, sold, watched)
    assert got is not None and (got.level, got.units, got.sold) == ("high", 10, 10)
    more = service.price_confidence(replace(sale, crafts=6), sold, watched)
    assert more is not None and more.level == "medium"  # sells 12
    assert service.price_confidence(replace(sale, best_exit="vendor"), sold, watched) is None
    assert service.price_confidence(sale, {}, watched) is None  # nothing known of it on the AH
    unlisted = {3: prices.Listing(900, 0, listed=False, median_7d=900, scans_7d=5)}
    assert service.confident(sale, sold, watched, "high")
    assert not service.confident(sale, sold, 1.0, "high")  # hardly watched: not yet
    assert not service.confident(sale, unlisted, watched, "medium")
    assert service.confident(sale, unlisted, watched, "low")
    assert service.confident(replace(sale, best_exit="vendor"), unlisted, watched, "high")  # off the AH


def test_a_sale_is_slow_when_what_is_listed_ahead_outlasts_two_days() -> None:
    recipe = engine.Recipe(1, "Green Robe", 3, output_count=1)
    sale = engine.Result(recipe, 100, 500, "ah", engine.Node(3, "Green Robe", 1, 100), crafts=10)
    ladder = (book.Level(800, 20, 2), book.Level(900, 30, 3), book.Level(2000, 500, 9))

    def listed(rate: float | None) -> dict[int, prices.Listing]:
        return {3: prices.Listing(800, 550, ladder, rate)}

    # 50 listed at or under 900 sell first, then the plan's 10: at 40 a day, a day and a half
    assert service.days_to_sell(sale, listed(40.0), 900) == 1.5
    assert not service.slow_to_sell(sale, listed(40.0), 900)
    assert service.days_to_sell(sale, listed(20.0), 900) == 3.0
    assert service.slow_to_sell(sale, listed(20.0), 900)
    assert service.days_to_sell(sale, listed(20.0), 799) == 0.5  # undercutting everyone
    # nothing known of its sales: not flagged slow (the price confidence says so)
    assert service.days_to_sell(sale, listed(None), 900) is None
    assert not service.slow_to_sell(sale, listed(None), 900)
    assert not service.slow_to_sell(sale, {3: prices.Listing(800, 2)}, 900)
    vendored = replace(sale, best_exit="vendor")
    assert service.days_to_sell(vendored, listed(1.0), 900) is None
    assert not service.slow_to_sell(vendored, listed(1.0), 900)


def test_selection_falls_back_to_the_freshest_scanned_realm(conn: Connection) -> None:
    assert service.selection(conn, ME, FOREVER, []) is None
    set_prices(conn, {1: 20}, realm="Dreamscythe", faction="Horde")
    set_prices(conn, {1: 30})  # Classic Beta PvE Horde, later
    set_prices(conn, {1: 40}, realm="", faction="")  # the unnamed auction house never counts
    assert service.selection(conn, ME, FOREVER, []) == Selection("Classic Beta PvE", "Horde")

    service.select(conn, ME, FOREVER, "Dreamscythe", "Horde")  # a realm with prices but no characters
    assert service.selected_characters(conn, ME, FOREVER) == (Selection("Dreamscythe", "Horde"), [])
    with pytest.raises(ValueError, match=r"Nowhere \(both factions\)"):
        service.select(conn, ME, FOREVER, "Nowhere", "")
    with pytest.raises(ValueError):
        service.select(conn, ME, FOREVER, "", "")


def test_an_import_forgets_a_selected_realm_it_has_no_characters_on(conn: Connection) -> None:
    set_prices(conn, {1: 20}, realm="Elsewhere")
    service.select(conn, ME, FOREVER, "Elsewhere", "Horde")
    service.replace_characters(conn, ME, FOREVER, chars())
    assert service.selected_characters(conn, ME, FOREVER)[0] == Selection("Dreamscythe", "Horde")

    service.select(conn, ME, FOREVER, "Classic Beta PvE", "Horde")
    service.replace_characters(conn, ME, FOREVER, chars())  # still there: kept
    assert service.selected_characters(conn, ME, FOREVER)[0] == Selection("Classic Beta PvE", "Horde")


def test_delete_characters(conn: Connection) -> None:
    service.replace_characters(conn, ME, FOREVER, chars())
    service.delete_character(conn, ME, FOREVER, "Classic Beta PvE", "Tailor Guy")
    assert "Tailor Guy" not in [c.name for c in store.load_characters(conn, ME, FOREVER)]
    with pytest.raises(FileNotFoundError):
        service.delete_character(conn, ME, FOREVER, "Classic Beta PvE", "Tailor Guy")


# --- profit per hour ----------------------------------------------------------------------------------
def test_time_model_follows_the_users_settings(conn: Connection, cities: Path) -> None:
    maps = store.load_cities(cities)
    assert [c.name for c in service.faction_cities(maps, "Horde")] == ["Orgrimmar", "Thunder Bluff"]
    assert [c.name for c in service.faction_cities(maps, "")] == ["Orgrimmar", "Stormwind", "Thunder Bluff"]
    model = service.time_model(conn, ME, FOREVER, maps, "Horde")
    assert (model.city.name, model.config) == ("Orgrimmar", timing.DEFAULT_CONFIG)  # the estimate's city
    assert [c.name for c in model.fastest] == ["Orgrimmar", "Thunder Bluff"]  # timed in whichever is fastest
    assert service.time_model(conn, ME, FOREVER, maps, "Alliance").city.name == "Stormwind"
    users.update_settings(conn, ME, FOREVER, time_city="Thunder Bluff", time_config='{"batch": 5}')
    model = service.time_model(conn, ME, FOREVER, maps, "Horde")
    assert (model.city.name, model.config.batch) == ("Thunder Bluff", 5)
    users.update_settings(conn, ME, FOREVER, time_city="Booty Bay")  # neutral: never used
    assert service.time_model(conn, ME, FOREVER, maps, "Horde").city.name == "Orgrimmar"
    with pytest.raises(ValueError, match="Booty Bay"):
        service.set_time(conn, ME, FOREVER, maps, "Booty Bay", {})
    users.update_settings(conn, ME, FOREVER, time_city="Stormwind")
    assert service.time_model(conn, ME, FOREVER, maps, "Horde").city.name == "Orgrimmar"  # not a Horde city
    assert service.time_model(conn, ME, FOREVER, {}, "Horde").city is timing.ANYWHERE  # no presets


def test_by_rate_puts_the_best_per_hour_first() -> None:
    fast = engine.Recipe(1, "Fast", 3, 1, ((1, 1),), "Tailoring")
    slow = engine.Recipe(2, "Slow", 4, 1, ((1, 1),), "Tailoring", cast_time_ms=60_000)
    items = {
        1: engine.Item(1, "Cloth"),
        3: engine.Item(3, "Fast Thing", sell_price=100),
        4: engine.Item(4, "Slow Thing", sell_price=200),
    }
    model = engine.TimeModel(timing.DEFAULT_CONFIG, timing.ANYWHERE)
    market = engine.Market(items, [fast, slow], {1: 10}, time=model)
    by_profit = service.search(market, [], "none", engine.Filters(), time=model)
    assert [r.recipe.name for r in by_profit] == ["Slow", "Fast"]
    assert [r.recipe.name for r in service.by_rate(by_profit)] == ["Fast", "Slow"]


def test_by_skill_puts_the_cheapest_skill_point_first() -> None:
    def recipe(i: int, name: str, low: int, high: int, cloth: int = 1) -> engine.Recipe:
        return engine.Recipe(
            i, name, 10 + i, 1, ((1, cloth),), "Tailoring", spell_id=i, trivial_low=low, trivial_high=high
        )

    recipes = [
        recipe(1, "Orange", 55, 70),  # +5, a sure skill point
        recipe(2, "Yellow", 50, 60),  # -7, a sure one: 7c a point
        recipe(3, "Green", 40, 60),  # -5 at half a chance: 10c a point
        recipe(4, "Grey", 20, 50),  # -1, but no skill point
        recipe(5, "Sure", 0, 0, cloth=2),  # -10, thresholds unknown: a sure point, as dear as Green's
    ]
    sells = {1: 15, 2: 3, 3: 5, 4: 9, 5: 10}
    items = {1: engine.Item(1, "Cloth")} | {
        10 + i: engine.Item(10 + i, r.name, sell_price=sells[i]) for i, r in enumerate(recipes, 1)
    }
    tailor = engine.Crafter("Tailor", (("Tailoring", 50, 75),), frozenset({1, 2, 3, 4, 5}))
    market = engine.Market(items, recipes, {1: 10}, crafters=[tailor], exits=frozenset({"vendor"}))
    ranked = market.rank(min_profit=-(10**18))
    assert [r.recipe.name for r in service.by_skill(ranked)] == ["Orange", "Yellow", "Sure", "Green", "Grey"]


def test_a_skill_run_ranks_each_recipe_as_the_first_run_of_its_climb(
    db2_paths: dict[str, Path], conn: Connection
) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    base = store.load_market(conn, FOREVER, set_prices(conn, {1: 20, 2: 100}))
    (tailor,) = chars("Tailor Guy")
    novice = replace(tailor, professions=(Profession("Tailoring", 20, 75, frozenset({900})),))
    skilled = frozenset({"Tailor Guy"})
    (one,) = service.search(base, [novice], "none", Filters(), skill_crafters=skilled)
    assert one.crafts == 1
    (run,) = service.search(
        base, [novice], "none", Filters(), skill_crafters=skilled, skill_run=engine.SkillRuns()
    )
    # the robe, the only recipe, up to grey at 60: orange to 30, then the falling chance takes ~130 crafts
    # in all, so the climb is one run up to the 100-craft ceiling, then another of the robe
    assert (run.stop_reason, run.overtaken_by) == ("ceiling", "")
    assert 50 < run.crafts <= 100 and 30 < run.stop_skill < 60
    assert run.cost == run.crafts * one.cost
    after = [(r.recipe and r.recipe.id, r.start_skill) for r in run.climb_after]
    assert after == [(100, run.stop_skill)]
    assert run.climb_after[-1].reason == "trivial" and run.climb_after[-1].stop_skill == 60
    assert run.climb_cost is not None
    got = service.evaluate(
        base,
        [novice],
        "none",
        ALL_EXITS,
        100,
        {},
        skill_crafters=skilled,
        skill_run=engine.SkillRuns(ceiling=10),
    )
    assert got is not None
    assert (got.crafts, got.stop_skill, got.stop_reason) == (10, 30, "ceiling")


def test_search_ranks_one_profession_when_asked() -> None:
    recipes = [
        engine.Recipe(1, "Robe", 11, 1, ((1, 1),), "Tailoring"),
        engine.Recipe(2, "Stew", 12, 1, ((1, 1),), "Cooking"),
    ]
    items = {1: engine.Item(1, "Cloth"), 11: engine.Item(11, "Robe", sell_price=50)}
    items[12] = engine.Item(12, "Stew", sell_price=40)
    market = engine.Market(items, recipes, {1: 10})
    assert [r.recipe.name for r in service.search(market, [], "none", engine.Filters())] == ["Robe", "Stew"]
    tailoring = service.search(market, [], "none", engine.Filters(), skill_name="Tailoring")
    assert [r.recipe.name for r in tailoring] == ["Robe"]


def test_favorites_first_keeps_each_part_in_order() -> None:
    recipes = [engine.Recipe(i, f"R{i}", 10 + i, 1, ((1, 1),), "Tailoring") for i in range(1, 5)]
    items = {1: engine.Item(1, "Cloth")} | {
        10 + i: engine.Item(10 + i, f"T{i}", sell_price=100 * i) for i in range(1, 5)
    }
    ranked = service.search(engine.Market(items, recipes, {1: 10}), [], "none", engine.Filters())
    assert [r.recipe.id for r in ranked] == [4, 3, 2, 1]
    assert [r.recipe.id for r in service.favorites_first(ranked, frozenset({1, 3}))] == [3, 1, 4, 2]
    assert service.favorites_first(ranked, frozenset()) == ranked


def enchanter(*recipes: int) -> Character:
    enchanting = Profession("Enchanting", 150, 150, frozenset(recipes))
    return Character("R", "Enchy", "Horde", "MAGE", 60, (enchanting,))


def test_knows_arcane_salvager_when_any_character_learned_it() -> None:
    assert service.knows_arcane_salvager([tailor(), enchanter(service.ARCANE_SALVAGER_SPELL)])
    assert not service.knows_arcane_salvager([tailor(), enchanter(7418)])
    assert not service.knows_arcane_salvager([])


def test_search_and_evaluate_count_the_arcane_salvager() -> None:
    # A green robe of cloth disenchanted into one dust: 950 net, 1045 at an Arcane Salvager.
    green, dust = 4, 5
    items = {
        1: engine.Item(1, "Cloth"),
        green: engine.Item(green, "Robe", quality=2, item_level=20, class_id=4),
        dust: engine.Item(dust, "Dust"),
    }
    recipe = engine.Recipe(10, "Robe", green, 1, ((1, 1),), "Enchanting", spell_id=901)
    de = [engine.DisenchantRow(4, 2, 15, 25, dust, 1.0, 1, 1)]
    base = engine.Market(items, [recipe], {1: 10, dust: 1000}, de)
    who = [enchanter(901)]

    def revenue(salvager: bool) -> int:
        (r,) = service.search(base, who, "none", Filters(), arcane_salvager=salvager)
        e = service.evaluate(base, who, "none", ALL_EXITS, 10, {}, arcane_salvager=salvager)
        assert e is not None and e.revenue == r.revenue
        return r.revenue

    assert (revenue(False), revenue(True)) == (950, 1045)


# --- reputation: the city a plan pays best in -----------------------------------------------------------
ORGRIMMAR, THUNDER_BLUFF = 76, 81
HONORED_UP = {6: 10, 7: 10, 8: 10}
CLOTH, THREAD, ROBE_ITEM = 1, 2, 3
ROBE = engine.Recipe(10, "Robe", ROBE_ITEM, 1, ((CLOTH, 10), (THREAD, 1)), "Tailoring", spell_id=900)
WALK = timing.TimeConfig(run_speed=7.0, detour=1.0)  # 7 yd is a second


def rep_city(name: str, vendor_x: float, faction: int, anvil: bool = True) -> timing.CityMap:
    """A Horde city: the auction house, a mailbox 5 s away, an anvil there too, and `faction`'s thread
    seller `vendor_x` yards out."""
    places = [
        timing.Location("ah", "ah", "Auctioneer", 0, 0, 0),
        timing.Location("mailbox:1", "mailbox", "Mailbox", 35, 0, 0),
        timing.Location("vendor:1", "vendor", "Thread Seller", vendor_x, 0, 0),
    ]
    if anvil:
        places.append(timing.Location("anvil:1", "anvil", "Anvil", 35, 0, 0))
    return timing.CityMap(
        name,
        "Horde",
        places,
        "ah",
        {"vendor:1": frozenset({THREAD})},
        vendor_reputations={"vendor:1": faction},
    )


def tailor(*standings: tuple[int, int]) -> Character:
    tailoring = Profession("Tailoring", 300, 300, frozenset({900}))
    return Character("R", "Tailor", "Horde", "MAGE", 60, (tailoring,), reputations=standings)


def rep_base(thread: int, robe: int = 500, recipe: engine.Recipe = ROBE) -> engine.Market:
    """Cloth at 20c on the AH, thread at a vendor, the robe sold to a vendor."""
    items = {
        CLOTH: engine.Item(CLOTH, "Cloth", stack_size=20),
        THREAD: engine.Item(THREAD, "Thread", vendor_price=thread, stack_size=20),
        ROBE_ITEM: engine.Item(ROBE_ITEM, "Robe", sell_price=robe),
    }
    return engine.Market(items, [recipe], {CLOTH: 20}, reputation_discounts=HONORED_UP)


def best_plan(
    base: engine.Market, who: Character, near: timing.CityMap, far: timing.CityMap
) -> engine.Result:
    """The robe as the search ranks it for `who`, left to pick between the two cities."""
    model = engine.TimeModel(WALK, near, (near, far))
    (r,) = service.search(base, [who], "none", Filters(), time=model)
    return r


def test_cities_are_grouped_by_what_their_vendors_charge() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)

    def groups(*standings: tuple[int, int]) -> list[list[str]]:
        crafters = [engine.Crafter("Tailor", (), frozenset(), reputations=standings)]
        return [[c.name for c in g] for g in service.city_groups([org, tb], crafters, HONORED_UP)]

    assert groups() == [["Orgrimmar", "Thunder Bluff"]]
    assert groups((THUNDER_BLUFF, 5)) == [["Orgrimmar", "Thunder Bluff"]]  # Friendly: nothing off
    assert groups((THUNDER_BLUFF, 6)) == [["Orgrimmar"], ["Thunder Bluff"]]
    assert groups((THUNDER_BLUFF, 6), (ORGRIMMAR, 8)) == [["Orgrimmar", "Thunder Bluff"]]  # 10% in both
    assert service.city_groups([org, tb], [], HONORED_UP) == [(org, tb)]  # browsing: nobody's standing


def test_a_small_saving_is_not_worth_a_long_run() -> None:
    # Honored in Thunder Bluff, where the thread seller is 1000 s out: 10c off a thread doesn't pay for it.
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=100), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.cost, r.tree.inputs[1].rep_discount) == ("Orgrimmar", 10 * (200 + 100), 0)
    (other,) = r.alternatives  # the same session in Thunder Bluff: cheaper, and far slower
    assert other.timing is not None
    assert (other.timing.city, other.cost) == ("Thunder Bluff", 10 * (200 + 90))
    assert r.rate is not None and other.rate is not None and r.rate > other.rate


def test_the_cheaper_city_wins_when_it_pays_more_per_hour() -> None:
    # The robe barely profits at list price (10c a craft); 29c off the thread nearly quadruples that, for
    # ten seconds more of running.
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=290), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * (500 - 200 - 261))
    assert [a.profit for a in r.alternatives] == [10 * 10]


def test_a_plan_that_loses_everywhere_goes_where_it_loses_least() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=400), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * (500 - 200 - 360))  # -60 a craft, not -100


def test_a_plan_that_profits_in_one_city_only_goes_there() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 7000, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=310), tailor((THUNDER_BLUFF, 6)), org, tb)  # -10 a craft, or +21
    assert r.timing is not None
    assert (r.timing.city, r.profit) == ("Thunder Bluff", 10 * 21)


def test_a_city_without_the_plans_station_is_passed_over() -> None:
    forged = replace(ROBE, station="anvil")
    org = rep_city("Orgrimmar", 70, ORGRIMMAR)
    tb = rep_city("Thunder Bluff", 140, THUNDER_BLUFF, anvil=False)
    r = best_plan(rep_base(thread=290, recipe=forged), tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.timing is not None
    assert (r.timing.city, r.timing.missing) == ("Orgrimmar", frozenset())


def test_the_same_plan_everywhere_is_timed_in_the_quickest_city_lazily() -> None:
    # Thread is cheaper still on the AH: no vendor buy, so the cities differ in nothing but the running.
    org, tb = rep_city("Orgrimmar", 700, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)
    base = rep_base(thread=100)
    base.prices[THREAD] = 50
    r = best_plan(base, tailor((THUNDER_BLUFF, 6)), org, tb)
    assert r.alternatives == () and "timing" not in vars(r)  # nothing timed to rank it
    assert r.time_model is not None
    assert [c.name for c in r.time_model.fastest] == ["Orgrimmar", "Thunder Bluff"]
    assert r.timing is not None and r.timing.city == "Thunder Bluff"  # the robe sells at the nearer vendor


def test_a_recipe_the_cities_price_alike_is_planned_once(monkeypatch: pytest.MonkeyPatch) -> None:
    # The sash takes no thread: what it costs has nothing to do with whose vendor sells thread for less.
    sash = engine.Recipe(11, "Sash", 4, 1, ((CLOTH, 5),), "Tailoring", spell_id=901)
    base = rep_base(thread=290)
    base.items[4] = engine.Item(4, "Sash", sell_price=300)
    base.recipes.append(sash)
    who = replace(
        tailor((THUNDER_BLUFF, 6)), professions=(Profession("Tailoring", 300, 300, frozenset({900, 901})),)
    )
    org, tb = rep_city("Orgrimmar", 700, ORGRIMMAR), rep_city("Thunder Bluff", 70, THUNDER_BLUFF)
    model = engine.TimeModel(WALK, org, (org, tb))
    planned: list[int] = []
    evaluate = engine.Market.evaluate

    def counted(
        self: engine.Market, recipe: engine.Recipe, *args: Any, **kwargs: Any
    ) -> engine.Result | None:
        planned.append(recipe.id)
        return evaluate(self, recipe, *args, **kwargs)

    monkeypatch.setattr(engine.Market, "evaluate", counted)
    by_id = {r.recipe.id: r for r in service.search(base, [who], "none", Filters(), time=model)}
    assert sorted(planned) == [10, 10, 11]  # the robe in both cities, the sash once
    got = by_id[11]
    assert got.alternatives == () and "timing" not in vars(got)
    assert got.time_model is not None and [c.name for c in got.time_model.fastest] == [
        "Orgrimmar",
        "Thunder Bluff",
    ]
    assert got.timing is not None and got.timing.city == "Thunder Bluff"  # the nearer vendor to sell it to
    assert by_id[10].timing is not None and by_id[10].timing.city == "Thunder Bluff"
    planned.clear()
    session = service.session_model(model, [org, tb], None)
    again = service.evaluate(base, [who], "none", ALL_EXITS, 11, {}, time=session, crafts=WALK.batch)
    assert again == got and planned == [11]
    assert again is not None and again.timing is not None and again.timing.city == "Thunder Bluff"


def test_without_standings_the_ranking_is_the_plain_one() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    r = best_plan(rep_base(thread=290), tailor(), org, tb)
    assert r.time_model is not None and r.time_model.city is org
    assert (r.alternatives, "timing" in vars(r), r.profit) == ((), False, 100)


def test_evaluate_gives_the_ranked_result() -> None:
    org, tb = rep_city("Orgrimmar", 70, ORGRIMMAR), rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    base, who = rep_base(thread=290), tailor((THUNDER_BLUFF, 6))
    model = engine.TimeModel(WALK, org, (org, tb))
    (r,) = service.search(base, [who], "none", Filters(), time=model)
    session = service.session_model(model, [org, tb], None)
    got = service.evaluate(base, [who], "none", ALL_EXITS, ROBE.id, {}, time=session, crafts=WALK.batch)
    assert got is not None and got == r
    assert got.timing is not None and got.timing.city == "Thunder Bluff"
    assert [a.profit for a in got.alternatives] == [a.profit for a in r.alternatives]
    # asked for a city, it is planned and priced there alone
    there = service.session_model(model, [org, tb], "Orgrimmar")
    got = service.evaluate(base, [who], "none", ALL_EXITS, ROBE.id, {}, time=there, crafts=WALK.batch)
    assert got is not None and got.timing is not None
    assert (got.timing.city, got.profit, got.alternatives) == ("Orgrimmar", 100, ())


def test_a_saved_city_prices_the_plan_there() -> None:
    tb = rep_city("Thunder Bluff", 140, THUNDER_BLUFF)
    (r,) = service.search(
        rep_base(thread=290), [tailor((THUNDER_BLUFF, 6))], "none", Filters(), time=engine.TimeModel(WALK, tb)
    )
    assert (r.profit, r.alternatives) == (10 * 39, ())


def test_likely_profit_counts_unsold_units_at_the_fallback_exit() -> None:
    # ten robes: the AH nets 950 each, a vendor pays 500; the market took 3 lately, 2 listed at or under 1000
    items = {1: engine.Item(1, "Cloth"), 10: engine.Item(10, "Robe", sell_price=500, class_id=4)}
    robe = engine.Recipe(1, "Robe", 10, 1, ((1, 1),), "Tailoring")
    market = engine.Market(items, [robe], {1: 100}, sell_prices={10: 1000})
    (r,) = market.rank(crafts=10)
    assert (r.best_exit, r.profit) == ("ah", 10 * 950 - 1000)
    ladder = (book.Level(900, 1, 1), book.Level(1000, 1, 1), book.Level(1500, 5, 1))
    listing = prices.Listing(900, 7, ladder, 3 / 7, "altarmy", True, sale_price=1000)
    likely = service.likely(r, {10: listing}, 1000)
    assert (likely.depth_units, likely.excess_units, likely.exit) == (3, 7, "ah")
    assert likely.profit == r.profit - 7 * (950 - 500)
    # a vendor sale is what it is; so is another source's price
    vendor = replace(r, best_exit="vendor", revenue=5000)
    assert service.likely(vendor, {10: listing}, 1000) == service.Likely(vendor.profit, "vendor", 0, 0)
    other = replace(listing, source="auctionator")
    assert service.likely(r, {10: other}, 1000).profit == r.profit
    # when even the capped sale loses to the vendor, the vendor is the likely exit
    swamped = replace(listing, sale_rate=0.0, ladder=())
    assert service.likely(r, {10: swamped}, 1000) == service.Likely(10 * 500 - 1000, "vendor", 0, 10)


def test_the_auction_house_counts_only_what_its_market_takes_whichever_exit_pays_best() -> None:
    items = {1: engine.Item(1, "Cloth"), 10: engine.Item(10, "Robe", sell_price=500, class_id=4)}
    robe = engine.Recipe(1, "Robe", 10, 1, ((1, 1),), "Tailoring")
    (r,) = engine.Market(items, [robe], {1: 100}, sell_prices={10: 1000}).rank(crafts=10)
    ladder = (book.Level(900, 1, 1), book.Level(1000, 1, 1), book.Level(1500, 5, 1))
    listing = prices.Listing(900, 7, ladder, 3 / 7, "altarmy", True, sale_price=1000)
    assert service.ah_sale(r, {10: listing}, 1000) == service.AhSale(r.profit - 7 * (950 - 500), 3, 7)
    # depth 0: every unit goes to the vendor
    swamped = replace(listing, sale_rate=0.0, ladder=())
    assert service.ah_sale(r, {10: swamped}, 1000) == service.AhSale(10 * 500 - 1000, 0, 10)
    # another source's price is counted as it is
    other = replace(listing, source="auctionator")
    assert service.ah_sale(r, {10: other}, 1000) == service.AhSale(r.profit, 0, 0)
    # another exit paying best changes nothing about what the AH makes
    vendor = replace(r, best_exit="vendor", revenue=5000)
    assert service.ah_sale(vendor, {10: listing}, 1000) == service.ah_sale(r, {10: listing}, 1000)
    # nothing to say without an AH exit
    no_ah = replace(vendor, sell_options=[engine.SellOption("vendor", vendor.profit)])
    assert service.ah_sale(no_ah, {10: listing}, 1000) is None


def test_likely_profit_is_the_better_of_playing_it_safe_and_the_auction_house() -> None:
    items = {1: engine.Item(1, "Cloth"), 10: engine.Item(10, "Robe", sell_price=500, class_id=4)}
    robe = engine.Recipe(1, "Robe", 10, 1, ((1, 1),), "Tailoring")
    (r,) = engine.Market(items, [robe], {1: 100}, sell_prices={10: 1000}).rank(crafts=10)
    for sold, listed in ((3 / 7, 7), (0.0, 0), (1.0, 20)):
        ladder = (book.Level(1000, listed, 1),) if listed else ()
        listing = prices.Listing(1000, listed, ladder, sold, "altarmy", True, sale_price=1000)
        sale = service.ah_sale(r, {10: listing}, 1000)
        safe = service.safe_profit(r)
        assert sale is not None and safe is not None
        assert service.likely(r, {10: listing}, 1000).profit == max(sale.profit, safe[1])


def test_an_essence_conversion_sells_safely() -> None:
    convert = engine.Recipe(1_000_000_001, "Greater Essence", 2, 1, ((1, 3),), "", kind="convert")
    assert convert.is_conversion
    sale = engine.Result(convert, 300, 1000, "ah", engine.Node(2, "Greater Essence", 1, 300))
    sale.sell_options = [engine.SellOption("ah", 700)]
    thin = prices.Listing(1000, 0, (), 0.0, "altarmy", True, sale_price=1000)
    # enchanting materials sell: no depth cap, and not an auction house play
    assert service.likely(sale, {2: thin}, 1000) == service.Likely(700, "ah", 0, 0)
    assert service.ah_sale(sale, {2: thin}, 1000) is None
    assert service.safe_profit(sale) == ("convert", 700)


def test_a_gathered_material_is_worth_what_it_would_sell_for() -> None:
    items = {1: engine.Item(1, "Cloth", sell_price=3), 2: engine.Item(2, "Thread"), 3: engine.Item(3, "Dust")}
    market = engine.Market(items, [], {}, sell_prices={1: 100})
    assert service.gather_values(market, [1, 2, 3, 9]) == {1: 95, 2: 1, 3: 1, 9: 1}  # AH net, else 1c
    vendor_only = engine.Market(items, [], {})
    assert service.gather_values(vendor_only, [1]) == {1: 3}  # what a vendor pays


def ladder(cap: int = 300) -> tuple[engine.Market, Character]:
    """Three Tailoring recipes one after another (grey at 30, 55 and 80), a trainer's each, the first known by
    a tailor at 1: the second can be learned at 25 and the third at 50 (where they turn yellow)."""
    items = {
        1: engine.Item(1, "Cloth"),
        **{10 + i: engine.Item(10 + i, n, sell_price=1) for i, n in ((1, "A"), (2, "B"), (3, "C"))},
    }
    recipes = [
        engine.Recipe(
            100 + i, n, 10 + i, 1, ((1, 1),), "Tailoring", spell_id=900 + i, trivial_low=lo, trivial_high=hi
        )
        for i, (n, lo, hi) in enumerate((("A", 1, 30), ("B", 25, 55), ("C", 50, 80)), start=1)
    ]
    who = Character("R", "T", "Horde", "MAGE", 60, (Profession("Tailoring", 1, cap, frozenset({901})),))
    return engine.Market(items, recipes, {1: 20}), who


def ranked_runs(base: engine.Market, who: Character) -> list[engine.Result]:
    run = engine.SkillRuns()
    return service.by_skill(
        service.search(base, [who], "train", Filters(), skill_crafters=frozenset({who.name}), skill_run=run)
    )


def chain_of(
    base: engine.Market,
    who: Character,
    first: engine.Result,
    steps: int = 2,
    done: Sequence[engine.Result] = (),
) -> list[engine.Result]:
    none: frozenset[int] = frozenset()
    return service.skill_chain(
        base,
        [who],
        "train",
        ALL_EXITS,
        none,
        False,
        None,
        frozenset({who.name}),
        False,
        engine.SkillRuns(),
        first=first,
        steps=steps,
        done=done,
    )


def test_the_skill_chain_is_the_rest_of_the_climb() -> None:
    base, who = ladder()
    first = ranked_runs(base, who)[0]
    assert first.recipe.name == "A"
    # B from 25, then C from 50 (two runs of it: past the 100-craft ceiling near grey)
    chain = chain_of(base, who, first, steps=8)
    assert [r.recipe.name for r in chain] == ["B", "C", "C"]
    assert [r.recipe.name for r in chain_of(base, who, first, steps=1)] == ["B"]
    # each run planned from where the one before stops, for its own crafts
    assert chain[0].skill_chance == pytest.approx(
        engine.skill_up_chance(
            chain[0].recipe, engine.Crafter("T", (("Tailoring", first.stop_skill, 300),), frozenset())
        )
    )
    assert [r.crafts for r in chain] == [s.crafts for s in first.climb_after]
    assert [r.stop_skill for r in chain] == [s.stop_skill for s in first.climb_after]
    assert [r.stop_reason for r in chain] == ["rival", "ceiling", "trivial"] and chain[-1].stop_skill == 80
    assert chain[0].overtaken_by == "C" and chain[1].overtaken_by == ""
    # a run with nothing after it has no chain
    assert chain_of(base, who, replace(first, climb_after=())) == []


def test_a_longer_skill_chain_continues_from_a_shorter_one() -> None:
    base, who = ladder()
    first = ranked_runs(base, who)[0]
    short = chain_of(base, who, first, steps=1)
    longer = chain_of(base, who, first, steps=2, done=short)
    assert longer[0] is short[0]
    assert [(r.recipe.name, r.stop_skill) for r in longer] == [
        (r.recipe.name, r.stop_skill) for r in chain_of(base, who, first, steps=2)
    ]


def overlapping(rank: int = 25) -> tuple[engine.Market, Character]:
    """Three Tailoring recipes a tailor at `rank` knows, all giving points there: Stone (1 cloth; yellow
    from 20, grey at 60), Maul (3 cloth; 15 to 70) and Robe (6 cloth; 10 to 80). Stone is the cheapest point
    while it gives one, so as ranked every other recipe's climb comes back to it."""
    items = {
        1: engine.Item(1, "Cloth"),
        **{10 + i: engine.Item(10 + i, n, sell_price=1) for i, n in ((1, "Stone"), (2, "Maul"), (3, "Robe"))},
    }
    recipes = [
        engine.Recipe(
            100 + i, n, 10 + i, 1, ((1, k),), "Tailoring", spell_id=900 + i, trivial_low=lo, trivial_high=hi
        )
        for i, (n, k, lo, hi) in enumerate(
            (("Stone", 1, 20, 60), ("Maul", 3, 15, 70), ("Robe", 6, 10, 80)), start=1
        )
    ]
    known = frozenset({901, 902, 903})
    who = Character("R", "T", "Horde", "MAGE", 60, (Profession("Tailoring", rank, 300, known),))
    return engine.Market(items, recipes, {1: 20}, exits=frozenset({"vendor", engine.KEEP_EXIT})), who


def start_of(
    base: engine.Market,
    who: Character,
    learning: engine.Learning | engine.Unlearned = "train",
    run: engine.SkillRuns | None = None,
) -> engine.Result | None:
    none: frozenset[int] = frozenset()
    run = run or engine.SkillRuns()
    return service.strategy_start(
        base, [who], learning, ALL_EXITS, none, False, None, frozenset({who.name}), False, run, "Tailoring",
    )  # fmt: skip


def climbed(r: engine.Result) -> list[str]:
    """The recipes of a run's climb, the run itself first."""
    return [r.recipe.name, *(s.recipe.name for s in r.climb_after if s.recipe is not None)]


def test_a_strategy_starts_with_the_first_run_of_its_cheapest_climb() -> None:
    base, who = overlapping()
    ranked = ranked_runs(base, who)
    got = start_of(base, who)
    assert got is not None
    assert (got.recipe, got.crafts, got.stop_skill, got.climb_cost) == (
        ranked[0].recipe,
        ranked[0].crafts,
        ranked[0].stop_skill,
        ranked[0].climb_cost,
    )
    # copper alone: a craft is worth nothing, so the climb is chosen by less
    cheapest = start_of(base, who, run=engine.SkillRuns(craft_value=0.0))
    assert cheapest is not None and cheapest.climb_cost is not None and got.climb_cost is not None
    assert cheapest.climb_cost < got.climb_cost


def test_a_strategy_without_patterns_learns_only_what_trainers_teach() -> None:
    base, who = ladder()
    base.recipes[1] = replace(base.recipes[1], source="recipe")  # B is taught by a pattern
    both = start_of(base, who, engine.Learning("train", 0, frozenset({"trainer", "recipe"})))
    trainer = start_of(base, who, engine.Learning("train", 0, frozenset({"trainer"})))
    assert both is not None and "B" in climbed(both)
    assert trainer is not None and "B" not in climbed(trainer)


def test_a_climb_is_planned_with_a_talent_set_to_another_rank() -> None:
    base, who = overlapping()
    raised = service.with_talent([who, replace(who, name="Other")], "T", talents.WORKING_OVERTIME, 5)
    assert raised[0].talents == ((talents.WORKING_OVERTIME, 5),) and raised[1].talents == ()
    again = service.with_talent(raised, "T", talents.WORKING_OVERTIME, 2)
    assert again[0].talents == ((talents.WORKING_OVERTIME, 2),)  # replaced, not added
    assert service.with_talent(again, "T", talents.WORKING_OVERTIME, 0)[0].talents == ()  # none at 0
    plain, overtime = start_of(base, who), start_of(base, raised[0])
    assert plain is not None and overtime is not None
    assert plain.climb is not None and overtime.climb is not None
    end = min(plain.climb.runs[-1].stop_skill, overtime.climb.runs[-1].stop_skill)
    crafts, fewer = plain.climb.crafts_by(end), overtime.climb.crafts_by(end)
    assert crafts is not None and fewer is not None and fewer < crafts


def test_runs_are_ranked_by_the_climb_they_start() -> None:
    base, who = ladder()
    ranked = ranked_runs(base, who)
    # at 1 only A gives a point: the others are learned on the way
    assert [r.recipe.name for r in ranked] == ["A"]
    (a,) = ranked
    assert a.climb_cost is not None and a.climb_unknown == 0
    assert [(s.recipe and s.recipe.name) for s in a.climb_after] == ["B", "C", "C"]
    assert a.overtaken_by == "B" and a.stop_reason == "rival"
    # at 26 A and B both give a point: each ranked as the cheapest climb starting with it
    at26 = replace(who, professions=(Profession("Tailoring", 26, 300, frozenset({901, 902})),))
    both = ranked_runs(base, at26)
    assert {r.recipe.name for r in both} == {"A", "B"}
    costs = [r.climb_cost for r in both]
    assert all(c is not None for c in costs) and costs == sorted(costs)  # type: ignore[type-var]


def test_a_recipe_learned_on_the_way_is_priced_as_its_run_will_be_planned() -> None:
    # C (learned at 50) takes a bolt: 1000 on the AH, or woven from cloth by Weaving (learned at 200). The
    # alt weaves at 1: nobody can weave a bolt on the way, so C's craft costs what buying the bolt does.
    base, who = ladder()
    weave = engine.Recipe(
        200,
        "Bolt",
        2,
        1,
        ((1, 1),),
        "Weaving",
        spell_id=990,
        learn_skill=200,
        trivial_low=200,
        trivial_high=250,
    )
    base.items[2] = engine.Item(2, "Bolt")
    base.recipes[2] = replace(base.recipes[2], reagents=((2, 1),))
    base.recipes.append(weave)
    base.prices[2] = 1000
    alt = Character("R", "W", "Horde", "MAGE", 60, (Profession("Weaving", 1, 300, frozenset()),))
    later = service.later_recipes(
        base,
        [who, alt],
        "train",
        ALL_EXITS,
        frozenset(),
        frozenset({"T"}),
        False,
        "Tailoring",
        engine.SkillRuns(),
        None,
    )
    by_name = {c.recipe.name: c for c in later}
    assert set(by_name) == {"B", "C"} and by_name["C"].from_skill == 50
    assert by_name["C"].cost > 900  # the bolt bought, not woven
    # what the chain will plan it at: the climber at 50, everything else as it is
    there = service.at_skill([who, alt], "T", "Tailoring", 50)
    n = engine.useful_crafts(base.recipes[2], service.as_crafters(there)[0])
    planned = service.evaluate(
        base,
        there,
        "train",
        ALL_EXITS,
        103,
        {},
        include_trivial=False,
        crafts=n,
        skill_crafters=frozenset({"T"}),
    )
    assert planned is not None and by_name["C"].cost == pytest.approx(-planned.profit / n)


def test_known_recipes_only_climb_without_learning_on_the_way() -> None:
    base, who = ladder()
    run = engine.SkillRuns()
    (a,) = service.search(base, [who], "none", Filters(), skill_crafters=frozenset({"T"}), skill_run=run)
    assert {s.recipe and s.recipe.name for s in a.climb_after} <= {"A"}
    assert (a.climb_after[-1] if a.climb_after else a).stop_skill == 30


def test_a_hypothetical_character_knows_what_trainers_teach_up_to_their_skill() -> None:
    def recipe(
        rid: int, learn: int, source: engine.Source = "trainer", skill: str = "Tailoring"
    ) -> engine.Recipe:
        return engine.Recipe(
            rid, f"R{rid}", 10, 1, ((1, 1),), skill, spell_id=900 + rid, learn_skill=learn, source=source
        )

    recipes = [
        recipe(1, 1),  # comes with the profession
        recipe(2, 40),  # a trainer's, from 40
        recipe(3, 100),  # a trainer's, from 100
        recipe(4, 20, "recipe"),  # a pattern: never assumed
        recipe(5, 1, skill="Blacksmithing"),
        engine.Recipe(6, "Flip", 10, 1, ((1, 1),), "", kind="flip"),  # anyone's: not a profession's
    ]
    who = service.hypothetical_character(
        recipes, "Realm", "Horde", "Your character", "tailoring", 45, 300, 60
    )
    assert (who.realm, who.faction, who.name, who.class_file, who.level) == (
        "Realm",
        "Horde",
        "Your character",
        "",
        60,
    )
    assert [(p.name, p.rank, p.max_rank) for p in who.professions] == [("Tailoring", 45, 300)]
    assert who.known_recipes == {901, 902}
    at_1 = service.hypothetical_character(recipes, "Realm", "Horde", "You", "Tailoring", 1, 300, 60)
    assert at_1.known_recipes == {901}
    with pytest.raises(ValueError, match="Cooking"):
        service.hypothetical_character(recipes, "Realm", "Horde", "You", "Cooking", 1, 300, 60)


def test_at_skill_raises_only_the_crafters_profession() -> None:
    _, who = ladder()
    other = replace(who, name="Other")
    alchemy = Profession("Alchemy", 5, 300, frozenset())
    who = replace(who, professions=(*who.professions, alchemy))
    raised, same = service.at_skill([who, other], "T", "tailoring", 40)
    assert [(p.name, p.rank) for p in raised.professions] == [("Tailoring", 40), ("Alchemy", 5)]
    assert same == other
    assert service.at_skill([raised], "T", "Tailoring", 10) == [raised]  # never lowered


def test_a_climb_counts_the_patterns_the_climber_must_buy() -> None:
    base, who = ladder()
    pattern_b = replace(base.recipes[1], source="recipe")
    base.recipes[1] = pattern_b
    vendor = store.Place("vendor", "Borya", "Orgrimmar", "horde", 0, 0, "", False)
    taught = {902: [store.RecipeItem(5, "Pattern: B", (vendor,), 300)]}
    assert service.needs_pattern(pattern_b, who) and not service.needs_pattern(base.recipes[2], who)
    costs = service.climb_learn_costs(base, who, "Tailoring", taught, "Horde")
    assert costs == {102: 300}
    assert service.climb_learn_costs(base, who, "Tailoring", {}, "Horde") == {102: None}
    run = engine.SkillRuns()
    skilled = frozenset({"T"})

    def climb(learn: dict[int, float | None] | None) -> engine.Result:
        (a,) = service.search(
            base, [who], "train", Filters(), skill_crafters=skilled, skill_run=run, learn_costs=learn
        )
        return a

    free, paid, unknown = climb(None), climb(costs), climb({102: None})
    assert free.climb_cost is not None and paid.climb_cost is not None
    uses_b = any(s.recipe is not None and s.recipe.name == "B" for s in paid.climb_after)
    assert (
        paid.climb_cost == pytest.approx(free.climb_cost + 300)
        if uses_b
        else paid.climb_cost >= free.climb_cost
    )
    assert unknown.climb_unknown <= 1
    # evaluated alone, a run is the one ranked
    got = service.evaluate(
        base, [who], "train", ALL_EXITS, 101, {}, skill_crafters=skilled, skill_run=run, learn_costs=costs
    )
    assert got is not None and (got.crafts, got.stop_skill, got.climb_cost) == (
        paid.crafts,
        paid.stop_skill,
        paid.climb_cost,
    )


def test_learn_cost_counts_a_pattern_the_climber_must_buy() -> None:
    robe = engine.Recipe(1, "Robe", 10, 1, ((1, 1),), "Tailoring", spell_id=900, source="recipe")
    trained = replace(robe, id=2, spell_id=901, source="trainer")
    result = engine.Result(robe, 100, 0, "vendor", engine.Node(10, "Robe", 1, 100), crafter="Novice")
    novice = Character("R", "Novice", "Horde", "MAGE", 20, (Profession("Tailoring", 20, 75, frozenset()),))
    vendor = store.Place("vendor", "Borya", "Orgrimmar", "horde", 0, 0, "", False)
    pattern = store.RecipeItem(5, "Pattern: Robe", (vendor,), 120)
    taught = {900: [pattern]}
    assert service.learn_cost(result, [novice], taught, {}, "Horde") == 120
    assert service.learn_cost(result, [novice], taught, {5: 90}, "Horde") == 90  # cheaper on the AH
    assert (
        service.learn_cost(result, [novice], taught, {}, "Alliance") is None
    )  # their vendor serves the Horde
    assert service.learn_cost(result, [novice], {}, {}, "Horde") is None  # nothing says what it costs
    knows = replace(novice, professions=(Profession("Tailoring", 20, 75, frozenset({900})),))
    assert service.learn_cost(result, [knows], taught, {}, "Horde") == 0
    assert service.learn_cost(replace(result, recipe=trained), [novice], {}, {}, "Horde") == 0  # fee unknown
    fee = replace(trained, train_cost=600)
    assert service.learn_cost(replace(result, recipe=fee), [novice], {}, {}, "Horde") == 600  # the trainer's
    learned = replace(novice, professions=(Profession("Tailoring", 20, 75, frozenset({901})),))
    assert service.learn_cost(replace(result, recipe=fee), [learned], {}, {}, "Horde") == 0
    # ranked by what a point costs with the pattern, unknown prices last
    cheap = replace(result, cost=50, skill_ups=1.0)
    dear = replace(result, recipe=replace(robe, id=3), cost=10, skill_ups=1.0)
    unknown = replace(result, recipe=replace(robe, id=4), cost=1, skill_ups=1.0)
    costs = {1: 0, 3: 100, 4: None}
    ordered = service.by_skill([unknown, dear, cheap], lambda r: costs[r.recipe.id])
    assert [r.recipe.id for r in ordered] == [1, 3, 4]


def _sale(best_exit: str, exits: list[engine.Exit], inputs: tuple[engine.Node, ...] = ()) -> engine.Result:
    recipe = engine.Recipe(1, "Green Robe", 3, 1, ((1, 10),), "Tailoring")
    return engine.Result(
        recipe, 300, 950, best_exit, engine.Node(3, "Green Robe", 1, 300, inputs=inputs), exits
    )


AH = engine.Exit("ah", 950)
VENDOR = engine.Exit("vendor", 500)
WATCHED = prices.WATCHED_ENOUGH_HOURS
SEEN = prices.Listing(1000, 50, source="altarmy", listed=True, median_7d=1000, scans_7d=5)
SOLD = replace(SEEN, sale_rate=2.0, sale_price=1000, sold_pairs_7d=3)


def test_a_vendor_sale_is_steady_and_an_ah_sale_as_sure_as_its_price() -> None:
    market = engine.Market({}, [], {})

    def verdict(
        r: engine.Result, listing: prices.Listing | None, watched: float = WATCHED
    ) -> service.Verdict:
        return service.verdict(r, {3: listing} if listing else {}, watched, market, disenchant_verified=False)

    assert verdict(_sale("vendor", [VENDOR]), None) == service.Verdict("steady", (), ())
    assert verdict(_sale("ah", [AH, VENDOR]), SOLD) == service.Verdict("steady", (), ())
    # watched long enough, and nothing seen sold
    assert verdict(_sale("ah", [AH]), SEEN) == service.Verdict("unproven", ("unsold",), ())
    assert verdict(_sale("ah", [AH]), SEEN, watched=0) == service.Verdict("likely", ("unwatched",), ())
    lone = replace(SEEN, quantity=1, scans_7d=1)
    assert verdict(_sale("ah", [AH]), lone, watched=0) == service.Verdict(
        "unproven", ("lone", "thin", "few_days", "unwatched"), ()
    )
    assert verdict(_sale("ah", [AH]), None).level == "unproven"  # nothing known of it


def test_a_disenchant_is_as_sure_as_its_main_materials_and_never_steady_unchecked() -> None:
    dust = engine.Material(5, "Dust", 1.0, 1, 2, 900)
    speck = engine.Material(6, "Speck", 0.1, 1, 1, 100)  # under a quarter of the value: not weighed
    sale = _sale("disenchant", [engine.Exit("disenchant", 1000, (dust, speck))])
    market = engine.Market({}, [], {})
    listings = {5: replace(SOLD, min_buyout=600), 6: replace(SEEN, quantity=1, scans_7d=1)}
    got = service.verdict(sale, listings, WATCHED, market, disenchant_verified=False)
    assert got == service.Verdict("likely", ("disenchant_unchecked",), ())
    assert service.verdict(sale, listings, WATCHED, market, disenchant_verified=True).level == "steady"
    unsure = {**listings, 5: SEEN}
    assert service.verdict(sale, unsure, 0.0, market, disenchant_verified=True) == service.Verdict(
        "likely", ("unwatched",), ()
    )


def test_buying_short_or_from_a_fresh_listing_makes_a_verdict_less_sure() -> None:
    linen = engine.Node(1, "Linen", 10, 200, source="ah")
    fresh = {1: (book.Level(20, 5, 1, age=0), book.Level(25, 100, 1, age=2))}
    market = engine.Market({}, [], {}, books=fresh)
    sale = _sale("ah", [AH], (linen,))
    assert service.verdict(sale, {3: SOLD}, WATCHED, market, False) == service.Verdict(
        "likely", (), ("just_listed",)
    )
    short = _sale("ah", [AH], (replace(linen, short=3),))
    settled = engine.Market({}, [], {}, books={1: (book.Level(20, 5, 1, age=1),)})
    assert service.verdict(short, {3: SOLD}, WATCHED, settled, False) == service.Verdict(
        "likely", (), ("short",)
    )
    both = _sale("ah", [AH], (replace(linen, short=3),))
    assert service.verdict(both, {3: SEEN}, 0.0, market, False) == service.Verdict(
        "unproven", ("unwatched",), ("short", "just_listed")
    )


def test_the_gold_sorts() -> None:
    def made(i: int, cost: int, revenue: int, crafts: int = 1) -> engine.Result:
        recipe = engine.Recipe(i, f"R{i}", 10 + i, 1, ((1, 1),), "Tailoring")
        return engine.Result(recipe, cost, revenue, "vendor", engine.Node(10 + i, "", 1, cost), crafts=crafts)

    a, b, c = made(1, 100, 300), made(2, 1000, 1500), made(3, 10, 200, crafts=10)
    assert [r.recipe.id for r in service.by_roi([a, b, c])] == [3, 1, 2]
    assert [r.recipe.id for r in service.by_spend([a, b, c])] == [3, 1, 2]
    assert [r.recipe.id for r in service.by_profit_each([a, b, c])] == [2, 1, 3]
    SO = engine.SellOption
    a.sell_options = [SO("ah", 500), SO("vendor", -50)]
    b.sell_options = [SO("disenchant", 300), SO("vendor", 100)]
    c.sell_options = [SO("ah", 900)]
    a.exits = [engine.Exit("ah", 525), engine.Exit("vendor", 5)]
    c.exits = [engine.Exit("ah", 91)]
    assert [r.recipe.id for r in service.by_safe([a, b, c])] == [2, 1, 3]  # c has no safe exit: last
    assert [r.recipe.id for r in service.by_safe([a, b, c], ascending=True)] == [1, 2, 3]  # still last
    nowhere = engine.Market({}, [], {})
    assert [r.recipe.id for r in service.by_ah([a, b, c], {}, nowhere)] == [3, 1, 2]
    assert [r.recipe.id for r in service.by_ah([a, b, c], {}, nowhere, ascending=True)] == [1, 3, 2]
    assert (service.safe_profit(b), service.safe_profit(c)) == (("disenchant", 300), None)
    assert service.at_least_verdict("likely", "steady") and not service.at_least_verdict("likely", "unproven")


def test_the_coach_picks_the_first_sure_profitable_craft_or_says_why_none() -> None:
    market = engine.Market({}, [], {})

    def run(i: int, profit: int, best_exit: str = "vendor") -> engine.Result:
        recipe = engine.Recipe(i, f"R{i}", 10 + i, 1, ((1, 1),), "Tailoring")
        exits = [engine.Exit(best_exit, profit + 100)]
        return engine.Result(
            recipe, 100, profit + 100, best_exit, engine.Node(10 + i, f"R{i}", 1, 100), exits
        )

    sure, small = run(1, 30_000), run(2, 500)
    listings: dict[int, prices.Listing] = {}
    pick, why = service.coach_pick([sure, small], listings, WATCHED, market, False)
    assert (pick, why) == (sure, None)
    pick, why = service.coach_pick([small], listings, WATCHED, market, False)
    assert pick is None and why == service.CoachNone("below_floor", small)
    # an AH sale on a thin market is never picked; nor an unproven one on a house nobody watched
    thin = run(3, 50_000, "ah")
    lone = {13: replace(SEEN, quantity=1, scans_7d=1)}
    pick, why = service.coach_pick([thin], lone, 0.0, market, False)
    assert pick is None and why == service.CoachNone("all_thin", None)
    seen = {13: SEEN}
    pick, why = service.coach_pick([thin], seen, 0.0, market, False)
    assert pick is None and why == service.CoachNone("no_watched_sales", None)
    assert service.coach_pick([], {}, WATCHED, market, False) == (None, service.CoachNone("nothing", None))


def smelting_ladder() -> tuple[engine.Market, Character]:
    """`ladder`'s Tailoring, B needing a bar only Mining smelts (from ore), beside a Blacksmithing sword of
    bars no Tailoring plan needs; the tailor at 1 also mines and smiths."""
    base, who = ladder()
    items = {
        **base.items,
        2: engine.Item(2, "Ore"),
        20: engine.Item(20, "Bar"),
        30: engine.Item(30, "Sword", sell_price=50),
    }
    recipes = [replace(r, reagents=((1, 1), (20, 1))) if r.name == "B" else r for r in base.recipes] + [
        engine.Recipe(200, "Bar", 20, 1, ((2, 2),), "Mining", spell_id=800),
        engine.Recipe(300, "Sword", 30, 1, ((20, 3),), "Blacksmithing", spell_id=700),
    ]
    miner = replace(
        who,
        professions=(
            Profession("Blacksmithing", 1, 300, frozenset({700})),
            Profession("Mining", 50, 300, frozenset({800})),
            *who.professions,
        ),
    )
    return engine.Market(items, recipes, {1: 20, 2: 3}), miner


def test_skill_markets_plan_one_profession_as_the_whole_game_does() -> None:
    base, who = smelting_ladder()
    assert [r.name for r in service.skill_scope(base, "tailoring")] == ["A", "B", "C", "Bar"]

    def market(scope: str | None) -> engine.Market:
        # every Tailoring recipe at hand, whatever it asks
        return service._market(
            base, [who], "all", ALL_EXITS, frozenset(), False, None, frozenset({who.name}), scope=scope
        )

    def runs(m: engine.Market) -> list[tuple[object, ...]]:
        ranked = m.rank(min_profit=-(10**9), skill_name="Tailoring", skill_run=engine.SkillRuns())
        return [
            (r.recipe.id, r.crafts, r.cost, r.profit, r.stop_skill, r.climb_cost, r.climb_after, r.tree)
            for r in ranked
        ]

    whole, scoped = market(None), market("Tailoring")
    assert [r.name for r in whole.recipes] == ["A", "B", "C", "Bar", "Sword"]
    assert [r.name for r in scoped.recipes] == ["A", "B", "C", "Bar"]
    assert runs(scoped) == runs(whole)
    # A starts the climb (the others ask for more skill), which goes on with B and its smelted bars
    (only,) = scoped.rank(min_profit=-(10**9), skill_name="Tailoring", skill_run=engine.SkillRuns())
    assert [s.recipe.name for s in only.climb_after if s.recipe] == ["B", "C", "C"]
    # as the workspace asks: the ranking and its chain plan the same runs
    (first,) = service.search(
        base,
        [who],
        "train",
        Filters(),
        skill_crafters=frozenset({who.name}),
        skill_name="Tailoring",
        skill_run=engine.SkillRuns(),
    )
    assert first.recipe.name == "A"
    assert [r.recipe.name for r in chain_of(base, who, first, steps=8)] == ["B", "C", "C"]


def test_no_runs_when_nothing_gives_the_climber_a_first_point() -> None:
    base, who = ladder()
    # knowing nothing, and the trainer's first recipe asks for 1: a climb starts
    novice = replace(who, professions=(Profession("Tailoring", 1, 300, frozenset()),))
    (crafter,) = service.as_crafters([novice])
    assert engine.can_start_climb(base.recipes, crafter, "Tailoring")
    # each recipe asks for more than they have and they know none of them: nothing to start with
    late = engine.Market(
        base.items, [replace(r, trivial_low=r.trivial_low + 10) for r in base.recipes], base.prices
    )
    (crafter,) = service.as_crafters([novice])
    assert not engine.can_start_climb(late.recipes, crafter, "Tailoring")
    assert ranked_runs(late, novice) == []
    # at the cap, nothing either
    capped = replace(who, professions=(Profession("Tailoring", 300, 300, frozenset({901})),))
    assert not engine.can_start_climb(base.recipes, service.as_crafters([capped])[0], "Tailoring")


def test_later_recipes_are_worked_out_again_whenever_an_input_moves() -> None:
    # they are kept per base market by their inputs (`_derived`): each input that changes what they are must
    # be in the key, or a later request would get another's
    base, who = ladder()
    skilled = frozenset({who.name})
    exits = frozenset({"vendor", engine.KEEP_EXIT})
    plain = engine.TimeModel(timing.TimeConfig(), timing.ANYWHERE)
    asked: dict[str, Any] = {
        "chars": [who],
        "unlearned": engine.Learning("train", 0, frozenset({"trainer", "recipe"})),
        "exits": exits,
        "no_ah": frozenset(),
        "skill_crafters": skilled,
        "arcane_salvager": False,
        "skill_name": "Tailoring",
        "skill_run": engine.SkillRuns(),
        "gathered": None,
        "time": plain,
    }

    def fresh(a: dict[str, Any]) -> list[engine.Candidate]:
        learning = engine.Learning.of(a["unlearned"])
        return service._later_recipes(
            base, a["chars"], learning, a["exits"], a["no_ah"], a["skill_crafters"], a["arcane_salvager"],
            a["skill_name"], a["gathered"], a["time"],
        )  # fmt: skip

    first = service.later_recipes(base, **asked)
    assert first == fresh(asked) and first  # B and C, learned on the way
    at30 = replace(who, professions=(Profession("Tailoring", 30, 300, frozenset({901, 902})),))
    variants: list[dict[str, Any]] = [
        {"chars": [at30]},
        {"unlearned": engine.Learning("train", 0, frozenset({"recipe"}))},
        {"exits": frozenset({"vendor"})},
        {"no_ah": frozenset({1})},
        {"gathered": {1: 5}},
        {"arcane_salvager": True},
        {"skill_name": "tailoring"},
        {"time": engine.TimeModel(replace(timing.TimeConfig(), time_value=100_000), timing.ANYWHERE)},
    ]
    moved = 0
    for change in variants:
        a = {**asked, **change}
        expected = fresh(a)
        assert service.later_recipes(base, **a) == expected, change
        moved += expected != first
    assert moved >= 2  # the fixture tells some of them apart: the check means something
    # what is handed out is a copy: changing it changes nothing kept
    service.later_recipes(base, **asked).clear()
    assert service.later_recipes(base, **asked) == first


def test_later_recipes_leave_out_what_never_climbs() -> None:
    base, who = ladder()

    def later(market: engine.Market) -> list[str]:
        found = service._later_recipes(
            market, [who], engine.Learning("train", 0, frozenset({"trainer", "recipe"})),
            frozenset({"vendor", engine.KEEP_EXIT}), frozenset(), frozenset({who.name}), False, "Tailoring",
            None, engine.TimeModel(timing.TimeConfig(), timing.ANYWHERE),
        )  # fmt: skip
        return sorted(c.recipe.name for c in found)

    def changed(name: str, **change: Any) -> engine.Market:
        recipes = [replace(r, **change) if r.name == name else r for r in base.recipes]
        return engine.Market(base.items, recipes, base.prices)

    assert later(base) == ["B", "C"]
    assert later(changed("B", cooldown_ms=engine.CLIMB_COOLDOWN_MS)) == ["C"]  # an hour a craft
    assert later(changed("C", num_skill_ups=0)) == ["B"]  # gives no point
