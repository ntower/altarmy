import json
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import Connection, func, select

from altarmy_site import (
    auth,
    cli,
    db,
    ingest,
    jobs,
    merge,
    prices,
    schema,
    service,
    signals,
    store,
    versions,
    wowfiles,
)
from altarmy_site.auctionator import DayStats, ItemPrice
from altarmy_site.prices import Observation

from .conftest import FOREVER, SV_DIR, book_scan, set_prices
from .test_auth import FakeRoster
from .test_signals import FakeSignals

T0 = datetime(2026, 9, 20, 12, 0, tzinfo=UTC)


def count(conn: Connection, table: str) -> int:
    return int(conn.execute(select(func.count()).select_from(schema.metadata.tables[table])).scalar_one())


def test_snapshot_stats_per_source(conn: Connection) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    tbc = prices.auction_house(conn, "tbc", "Dreamscythe", "Horde")
    obs = [Observation(1, 10, T0), Observation(2, 20, T0)]
    two_days = T0 - timedelta(days=2)
    prices.record_snapshot(conn, ah, "auctionator", T0, obs, received_at=T0)
    prices.record_snapshot(conn, ah, "auctionator", T0, obs[:1], received_at=two_days)
    prices.record_snapshot(conn, ah, "csv", T0, obs[:1], received_at=T0 - timedelta(days=8))  # too old
    prices.record_snapshot(conn, tbc, "auctionator", T0, obs, received_at=T0)  # another version
    snap = schema.price_snapshots
    conn.execute(snap.update().where(snap.c.received_at == two_days).values(status="quarantined"))
    assert prices.snapshot_stats(conn, FOREVER, T0) == [prices.SnapshotStats("auctionator", 1, 2, 1, 3, T0)]


def test_set_price_records_manual_snapshots(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.set_price(conn, ah, 1, 10)
    prices.set_price(conn, ah, 1, 20)
    assert prices.load_current(conn, ah) == {1: 20}
    assert count(conn, "price_snapshots") == 2
    assert count(conn, "price_observations") == 2
    assert prices.last_import(conn, ah) is None  # no Auctionator scan
    assert prices.last_import(conn, ah, "manual") is not None
    assert prices.count_current(conn, ah) == 1
    assert (prices.count_current(conn, None), prices.load_current(conn, None)) == (0, {})


def test_snapshots_only_record_news(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    scan = [Observation(1, 100, T0, 5), Observation(2, 50, T0)]
    assert prices.record_snapshot(conn, ah, "auctionator", T0, scan) == 2
    assert prices.record_snapshot(conn, ah, "auctionator", T0 + timedelta(hours=1), scan) == 0  # same scan
    assert count(conn, "price_snapshots") == 2  # both arrivals are on record
    assert count(conn, "price_observations") == 2

    later = T0 + timedelta(hours=2)
    moved = [Observation(1, 90, later), Observation(2, 50, T0)]  # item 1 got cheaper, 2 unchanged
    assert prices.record_snapshot(conn, ah, "auctionator", later, moved) == 1
    next_day = T0 + timedelta(days=1)
    assert prices.record_snapshot(conn, ah, "auctionator", next_day, [Observation(2, 50, next_day)]) == 1
    assert prices.load_current(conn, ah) == {1: 90, 2: 50}

    older = [Observation(1, 999, T0 - timedelta(days=3))]  # an old upload never beats a newer price
    assert prices.record_snapshot(conn, ah, "auctionator", T0 - timedelta(days=3), older) == 0
    assert prices.load_current(conn, ah) == {1: 90, 2: 50}
    pc = schema.price_current
    seen: datetime = conn.execute(select(pc.c.seen_at).where(pc.c.item_id == 2)).scalar_one()
    assert db.utc(seen) == next_day


def current_row(conn: Connection, ah: int, item_id: int) -> tuple[int, int | None, int | None]:
    """An item's (price, sell cap, quantity) in price_current. Nothing sets the cap any more."""
    pc = schema.price_current
    row = conn.execute(
        select(pc.c.price, pc.c.sell_cap, pc.c.quantity).where(
            pc.c.auction_house_id == ah, pc.c.item_id == item_id
        )
    ).one()
    return row.price, row.sell_cap, row.quantity


def test_a_quantity_change_updates_current_in_place(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(1, 100, T0, 5)])
    version = prices.price_version(conn, ah)
    later = T0 + timedelta(hours=1)
    assert prices.record_snapshot(conn, ah, "auctionator", later, [Observation(1, 100, later, 2)]) == 0
    assert current_row(conn, ah, 1) == (100, None, 2)
    assert count(conn, "price_observations") == 1  # no observation: the price didn't move
    assert prices.price_version(conn, ah) == version
    earlier = T0 - timedelta(hours=1)  # an older scan never overwrites it
    prices.record_snapshot(conn, ah, "auctionator", earlier, [Observation(1, 100, earlier, 9)])
    assert current_row(conn, ah, 1) == (100, None, 2)


def test_manual_price_holds_until_a_newer_scan(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(1, 100, T0)])
    prices.set_price(conn, ah, 1, 70)  # now: after the scan
    assert prices.load_current(conn, ah) == {1: 70}
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(1, 100, T0)])  # the same old scan again
    assert prices.load_current(conn, ah) == {1: 70}
    fresh = db.utcnow() + timedelta(days=1)
    prices.record_snapshot(conn, ah, "auctionator", fresh, [Observation(1, 80, fresh)])
    assert prices.load_current(conn, ah) == {1: 80}


def test_auctionator_observations_use_each_items_last_day() -> None:
    scan = datetime(2026, 9, 24, 12, 0, tzinfo=UTC)
    today = scan.astimezone().date()
    earlier = today - timedelta(days=3)
    got = prices.auctionator_observations(
        {
            1: ItemPrice(100, {today: DayStats(120, 100, 7), earlier: DayStats(90, 90, 2)}),
            2: ItemPrice(50, {earlier: DayStats(60, 50, 4)}),
            3: ItemPrice(10),  # no history left
        },
        scan,
    )
    assert got == [
        Observation(1, 100, scan, 7),
        Observation(2, 50, datetime.combine(earlier, datetime.min.time(), UTC), 4),
        Observation(3, 10, scan, None),
    ]


def test_record_daily_backfills_then_updates_from_the_newest_day(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    d1, d2, d3 = date(2026, 9, 1), date(2026, 9, 2), date(2026, 9, 3)
    first = {1: ItemPrice(100, {d1: DayStats(120, 100, 7), d2: DayStats(110, 105, 3)})}
    assert prices.record_daily(conn, ah, first) == 2
    # Auctionator later rewrites d1 (ignored: before the newest stored day), d2 (moved on) and adds d3
    second = {1: ItemPrice(90, {d1: DayStats(1, 1, 1), d2: DayStats(115, 95, 4), d3: DayStats(90, 90, None)})}
    assert prices.record_daily(conn, ah, second) == 2
    assert prices.daily(conn, ah, 1) == [(d1, 100, 120, 7), (d2, 95, 115, 4), (d3, 90, 90, None)]


def test_record_daily_pools_uploaders_days(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    d = date(2026, 9, 2)
    prices.record_daily(conn, ah, {1: ItemPrice(100, {d: DayStats(120, 100, 7)})})
    prices.record_daily(conn, ah, {1: ItemPrice(90, {d: DayStats(110, 90, 3)})})  # another uploader
    assert prices.daily(conn, ah, 1) == [(d, 90, 120, 7)]
    prices.record_daily(conn, ah, {1: ItemPrice(100, {d: DayStats(120, 100, 7)})})  # sent again
    assert prices.daily(conn, ah, 1) == [(d, 90, 120, 7)]


def fresh(prices_by_item: dict[int, int], at: datetime = T0) -> list[Observation]:
    return [Observation(i, p, at) for i, p in prices_by_item.items()]


def test_screen_needs_enough_comparable_items() -> None:
    baseline = dict.fromkeys(range(19), 100)
    wild = fresh(dict.fromkeys(range(19), 10000))
    assert prices.screen(wild, baseline, T0, trust=1.0) is None
    stale = fresh(dict.fromkeys(range(40), 10000), at=T0 - timedelta(days=2))  # not seen on the scan day
    assert prices.screen(stale, dict.fromkeys(range(40), 100), T0, trust=1.0) is None


def test_screen_quarantines_when_many_prices_are_wild() -> None:
    baseline = dict.fromkeys(range(100), 100)
    scan = dict.fromkeys(range(100), 100)
    assert prices.screen(fresh(scan), baseline, T0, trust=1.0) is False
    for i in range(20):  # 20% more than 4x off: fine for a trusted uploader, not for a distrusted one
        scan[i] = 401 if i % 2 else 24
    assert prices.screen(fresh(scan), baseline, T0, trust=1.0) is False
    assert prices.screen(fresh(scan), baseline, T0, trust=0.25) is True
    for i in range(40):
        scan[i] = 10_000
    assert prices.screen(fresh(scan), baseline, T0, trust=1.0) is True


def test_screened_auctionator_scan_is_quarantined(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    day = T0.astimezone().date()
    history = {
        i: ItemPrice(100, {day - timedelta(days=n): DayStats(100, 100, 5) for n in range(1, 4)})
        for i in range(1, 31)
    }
    earlier = T0 - timedelta(days=1)
    prices.record_auctionator(conn, ah, history, earlier)
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=100, scans_7d=3))  # as the merge job would
    scaled = {i: ItemPrice(10_000, {day: DayStats(10_000, 10_000, 5)}) for i in range(1, 31)}

    got = prices.record_auctionator(conn, ah, scaled, T0, uploader_uid="u1", trust=1.0)
    assert got == prices.Recorded(moved=0, quarantined=True, screened=True)
    snap = schema.price_snapshots
    assert conn.execute(select(snap.c.status).order_by(snap.c.id)).scalars().all() == [
        "accepted",
        "quarantined",
    ]
    assert set(prices.load_current(conn, ah).values()) == {100}  # nothing moved
    assert prices.daily(conn, ah, 1)[-1][0] == day - timedelta(days=1)  # no daily rows either

    unscreened = prices.record_auctionator(conn, ah, scaled, T0)  # the local sync is not screened
    assert unscreened == prices.Recorded(moved=30)


def test_new_prices_bump_the_price_version(conn: Connection) -> None:
    """Every write that moves a current price bumps the version the front end watches; a repeat doesn't."""
    ah = prices.unnamed_auction_house(conn, FOREVER)
    assert prices.price_version(conn, ah) == 0
    obs = [Observation(1, 10, T0), Observation(2, 20, T0)]
    prices.record_snapshot(conn, ah, "auctionator", T0, obs)
    assert prices.price_version(conn, ah) == 1
    prices.record_snapshot(conn, ah, "auctionator", T0, obs)  # the same scan again: no news
    assert prices.price_version(conn, ah) == 1
    prices.set_price(conn, ah, 1, 11)
    assert prices.price_version(conn, ah) == 2


def test_a_quarantined_scan_keeps_the_price_version(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(i, 100, T0) for i in range(1, 31)])
    conn.execute(schema.price_current.update().values(median_7d=100, scans_7d=3))
    later = T0 + timedelta(hours=1)
    wild = [Observation(i, 10_000, later) for i in range(1, 31)]
    got = prices.record_screened(conn, ah, "auctionator", later, wild, "u1", trust=1.0)
    assert got.quarantined
    assert prices.price_version(conn, ah) == 1


def test_load_prices_sells_at_the_lower_of_now_and_the_median(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(
        conn,
        ah,
        "auctionator",
        T0,
        [Observation(1, 3_330_000, T0), Observation(2, 80, T0), Observation(3, 5, T0)],
    )
    prices.set_price(conn, ah, 4, 500)
    pc = schema.price_current
    for item_id, median in ((1, 4900), (2, 100), (4, 50)):
        conn.execute(pc.update().where(pc.c.item_id == item_id).values(median_7d=median))
    buy, sell = prices.load_buy_and_sell(conn, ah)
    assert buy == {1: 3_330_000, 2: 80, 3: 5, 4: 500}
    # a lone overpriced listing sells at the median; below it, at the price; no median, the price; a price
    # set by hand is used as it is
    assert sell == {1: 4900, 2: 80, 3: 5, 4: 500}
    assert prices.load_buy_and_sell(conn, None) == ({}, {})


def test_listings_say_how_many_are_up(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(1, 30, T0, 50), Observation(2, 9, T0)])
    got = prices.load_listings(conn, ah)
    assert {i: (g.min_buyout, g.quantity, g.source, g.listed) for i, g in got.items()} == {
        1: (30, 50, "auctionator", None),
        2: (9, None, "auctionator", None),
    }
    assert got[1].seen_at == T0
    assert prices.load_listings(conn, None) == {}


def test_watched_hours_add_up_back_to_back_scans(conn: Connection) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    gap = prices.SALES_GAP
    at = [T0, T0 + gap, T0 + 3 * gap, T0 + 3 * gap + timedelta(minutes=6)]  # 30 min + 6 min watched
    for t in at:
        prices.record_book(conn, ah, book_scan({1: [(10, 5)]}, t))
    now = T0 + timedelta(hours=2)
    assert prices.watched_hours(conn, ah, now) == pytest.approx(0.6)
    # a quarantined scan in between watches nothing; other houses and older weeks don't count
    snap = schema.price_snapshots
    conn.execute(snap.update().where(snap.c.scanned_at == T0 + gap).values(status="quarantined"))
    assert prices.watched_hours(conn, ah, now) == pytest.approx(0.1)
    assert prices.watched_hours(conn, ah, now + timedelta(days=prices.SALES_DAYS)) == 0.0
    assert prices.watched_hours(conn, None) == 0.0


def test_price_confidence_rests_on_sales_seen() -> None:
    def sure(listing: prices.Listing, units: int = 1, watched: float = 0.0) -> tuple[str, str]:
        got = prices.confidence(listing, units, watched)
        return got.level, got.reason

    known = prices.Listing(900, 50, source="altarmy", listed=True, median_7d=900, scans_7d=5)
    sold = replace(known, sale_rate=1.0, sale_price=880, sold_pairs_7d=2)  # 7 sold this week, in two pairs
    watched = prices.WATCHED_ENOUGH_HOURS
    assert sure(sold, 7, watched) == ("high", "sold")
    assert sure(sold, 8, watched) == ("medium", "few_sold")
    assert sure(replace(sold, listed=False, quantity=0), 7, watched) == ("high", "sold")  # though none up
    # one buyer in one pair of scans, or a house hardly watched, is no market yet
    assert sure(replace(sold, sold_pairs_7d=1), 7, watched) == ("medium", "one_pair")
    assert sure(sold, 7, watched - 1) == ("medium", "few_sold")
    unlisted = replace(known, listed=False, quantity=0, seen_at=T0)
    assert sure(unlisted) == ("low", "unlisted")
    assert prices.confidence(unlisted, 1, 0.0).unlisted_since == T0
    assert prices.confidence(known, 1, 0.0).unlisted_since is None
    assert sure(replace(known, scans_7d=prices.CONFIDENT_SCAN_DAYS - 1)) == ("low", "few_days")
    assert sure(replace(known, median_7d=None, scans_7d=None)) == ("low", "few_days")
    # watched long enough to have seen sales, and too few came
    assert sure(replace(known, sale_rate=3 / 7), watched=prices.WATCHED_ENOUGH_HOURS) == ("low", "unsold")
    assert sure(known) == ("medium", "unwatched")
    assert sure(replace(known, quantity=prices.THIN_UNITS - 1)) == ("low", "thin")
    assert sure(known, 60) == ("low", "thin")  # sells more than is listed
    assert sure(replace(known, quantity=None)) == ("medium", "unwatched")  # unknown: not thin
    assert sure(prices.Listing(500, 1, source="manual")) == ("high", "hand_set")


def test_price_rules() -> None:
    assert prices.sell_price(100, None, "auctionator") == 100
    assert prices.sell_price(100, 80, "auctionator") == 80
    assert prices.sell_price(100, 120, "auctionator") == 100
    assert prices.sell_price(100, 80, "manual") == 100  # set by hand: as it is
    assert not prices.thin_market(None, 1)  # unknown: no flag
    assert prices.thin_market(prices.THIN_UNITS - 1, 1)
    assert not prices.thin_market(prices.THIN_UNITS, 1)
    assert prices.thin_market(10, 20)  # fewer listed than the plan sells


def test_prune_keeps_what_price_current_points_at(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    old = T0 - timedelta(days=prices.KEEP_DAYS + 10)
    prices.record_snapshot(conn, ah, "auctionator", old, [Observation(1, 10, old), Observation(2, 20, old)])
    prices.record_snapshot(conn, ah, "auctionator", old, [Observation(3, 30, old)])
    prices.record_snapshot(conn, ah, "auctionator", T0, [Observation(1, 11, T0), Observation(3, 31, T0)])
    prices.prune(conn, now=T0)
    snap = schema.price_snapshots
    assert conn.execute(select(func.count()).select_from(snap)).scalar_one() == 2  # item 2's old one stays
    assert count(conn, "price_observations") == 2  # only the fresh snapshot's
    assert prices.load_current(conn, ah) == {1: 11, 2: 20, 3: 31}


def test_auction_houses_split_or_shared(conn: Connection) -> None:
    shared = prices.auctionator_auction_house(conn, FOREVER, "ClassicBetaPvE", "Classic Beta PvE", "Horde")
    assert prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Alliance") == shared
    split = prices.auctionator_auction_house(conn, "tbc", "Dreamscythe Horde", "Dreamscythe", "Horde")
    assert prices.find_auction_house(conn, "tbc", "Dreamscythe", "Horde") == split
    assert prices.find_auction_house(conn, "tbc", "Dreamscythe", "Alliance") is None
    assert prices.find_auction_house(conn, FOREVER, "Dreamscythe", "Horde") is None  # per version
    assert prices.auction_house_for_auctionator_key(conn, "tbc", "Dreamscythe Horde") == split  # an alias
    assert prices.auctionator_auction_house(conn, FOREVER, "ClassicBetaPvE", "Classic Beta PvE", "") == shared
    assert count(conn, "realm_aliases") == 2


def test_load_market_ranks_end_to_end(db2_paths: dict[str, Path], conn: Connection) -> None:
    ingest.build_db(db2_paths, conn, FOREVER)
    ah = set_prices(conn, {1: 20, 2: 100})  # linen, thread
    market = store.load_market(conn, FOREVER, ah)
    (result,) = market.rank()
    assert result.cost == 300
    assert result.profit == 200  # vendors for 500
    assert result.best_exit == "vendor"


def test_find_auctionator_files(tmp_path: Path) -> None:
    sv = tmp_path / "_classic_beta_" / "WTF" / "Account" / "ME" / "SavedVariables"
    sv.mkdir(parents=True)
    (sv / "Auctionator.lua").write_text("")
    (sv / "Other.lua").write_text("")
    assert wowfiles.find_auctionator_files([tmp_path, tmp_path / "missing"]) == [sv / "Auctionator.lua"]


def test_find_altarmy_files(wow_root: Path) -> None:
    assert wowfiles.find_altarmy_files([wow_root]) == [wow_root / SV_DIR / "AltArmy_TBC.lua"]


def test_serve_runs_the_api_with_uvicorn(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    import uvicorn
    from fastapi import FastAPI

    calls: list[tuple[object, str, int]] = []

    def fake_run(app: object, host: str, port: int) -> None:
        calls.append((app, host, port))

    monkeypatch.setattr(uvicorn, "run", fake_run)
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    with pytest.raises(SystemExit, match="FIREBASE_PROJECT_ID"):
        cli.main(["--db", str(tmp_path / "x.sqlite"), "serve"])
    assert calls == []

    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-altarmy")
    cli.main(["--db", str(tmp_path / "x.sqlite"), "serve", "--port", "9123"])
    ((app, host, port),) = calls
    assert isinstance(app, FastAPI)
    assert (host, port) == ("127.0.0.1", 9123)
    assert app.state.auth.database.migrates  # a dev server migrates its own database
    out = capsys.readouterr().out
    assert "No WoW: Forever game data yet: run `altarmy-site ingest`." in out
    assert "No TBC Anniversary game data yet: run `altarmy-site --game-version tbc ingest`." in out


def test_serve_reload_hands_uvicorn_a_factory_on_the_migrated_database(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import uvicorn
    from fastapi import FastAPI

    calls: list[tuple[object, dict[str, object]]] = []

    def fake_run(app: object, **kwargs: object) -> None:
        calls.append((app, kwargs))

    monkeypatch.setattr(uvicorn, "run", fake_run)
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-altarmy")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    path = tmp_path / "x.sqlite"
    cli.main(["--db", str(path), "serve", "--reload"])
    ((app, kwargs),) = calls
    assert app == "altarmy_site.cli:serve_app"
    assert kwargs["factory"] is True and kwargs["reload"] is True
    assert kwargs["reload_dirs"] == [str(Path(cli.__file__).resolve().parent)]
    assert path.is_file()  # migrated before the workers start

    built = cli.serve_app()  # what a reloaded worker builds: the same database, which it never migrates
    assert isinstance(built, FastAPI)
    assert Path(built.state.auth.database.url.database or "") == path.resolve()
    assert not built.state.auth.database.migrates


def test_cli_ingest_uses_the_game_versions_build_and_product(
    db2_paths: dict[str, Path],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    builds: list[str] = []

    def download_all(build: str, cache_dir: Path) -> dict[str, Path]:
        builds.append(build)
        return db2_paths

    monkeypatch.setattr(ingest, "download_all", download_all)
    monkeypatch.setattr(ingest, "latest_build", lambda product: {"wow_anniversary": "2.5.7.1"}[product])
    dbfile = str(tmp_path / "t.sqlite")
    cli.main(["--game-version", "tbc", "--db", dbfile, "ingest"])
    cli.main(["--game-version", "tbc", "--db", dbfile, "ingest", "--build", "latest"])
    assert builds == [ingest.pinned_build(versions.VERSIONS["tbc"]), "2.5.7.1"]
    assert "Ingested TBC Anniversary build 2.5.7.1" in capsys.readouterr().out
    database = db.Database(db.sqlite_url(dbfile))
    with database.begin() as conn:
        assert (db.get_build(conn, "tbc"), db.get_build(conn, FOREVER)) == ("2.5.7.1", None)
    database.dispose()


def test_cli_migrate_prune_and_merge(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    dbfile = str(tmp_path / "m.sqlite")
    cli.main(["--db", dbfile, "migrate"])
    assert "Database at revision" in capsys.readouterr().out
    database = db.Database(db.sqlite_url(dbfile))
    with database.begin() as conn:
        set_prices(conn, {1: 45})
    database.dispose()
    cli.main(["--db", dbfile, "prune"])
    assert "Pruned" in capsys.readouterr().out
    cli.main(["--db", dbfile, "merge"])
    assert "Merged 9 auction houses of every game version (0 changed); 1 price observations stored." in (
        capsys.readouterr().out
    )
    database = db.Database(db.sqlite_url(dbfile))
    with database.begin() as conn:
        runs = jobs.recent(conn, FOREVER)
    database.dispose()
    assert [(r.job, r.ok) for r in runs] == [("merge", True), ("prune", True)]
    assert runs[0].summary.startswith("Merged 9 auction houses")  # the fixed realms' 8, and the tailor's


def test_cli_merge_warns_once_observations_need_partitioning(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    dbfile = str(tmp_path / "m.sqlite")
    cli.main(["--db", dbfile, "migrate"])
    database = db.Database(db.sqlite_url(dbfile))
    with database.begin() as conn:
        set_prices(conn, {1: 45, 2: 50})
    database.dispose()
    monkeypatch.setattr(merge, "PARTITION_AT", 3)
    capsys.readouterr()
    cli.main(["--db", dbfile, "merge"])
    assert merge.PARTITION_ALERT not in capsys.readouterr().out  # 2 rows: under it
    monkeypatch.setattr(merge, "PARTITION_AT", 2)
    cli.main(["--db", dbfile, "merge"])
    alerts = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.startswith("{")]
    assert alerts == [
        {
            "severity": "WARNING",
            "message": "price_observations has 2 rows (limit 2): partition it by month.",
            "alert": merge.PARTITION_ALERT,
            "observations": 2,
        }
    ]


def test_cli_merge_signals_the_auction_houses_it_changed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    fake = FakeSignals()
    monkeypatch.setattr(signals, "from_env", lambda: fake)
    dbfile = str(tmp_path / "m.sqlite")
    cli.main(["--db", dbfile, "migrate"])
    database = db.Database(db.sqlite_url(dbfile))
    today = db.utcnow().date()
    with database.begin() as conn:
        ah = set_prices(conn, {1: 45})
        prices.record_daily(conn, ah, {1: ItemPrice(45, {today: DayStats(45, 45, 1)})})
        version = prices.price_version(conn, ah)
    database.dispose()
    assert version is not None
    cli.main(["--db", dbfile, "merge"])
    assert fake.published == [(ah, FOREVER, version + 1)]
    cli.main(["--db", dbfile, "merge"])  # nothing changed
    assert len(fake.published) == 1
    assert "1 price signal sent" in capsys.readouterr().out


def test_cli_admin_grants_revokes_and_lists(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    roster = FakeRoster({"me@example.com": "u1", "you@example.com": "u2"})
    projects: list[str] = []

    def verifier(project: str) -> FakeRoster:
        projects.append(project)
        return roster

    monkeypatch.setattr(auth, "FirebaseVerifier", verifier)
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    with pytest.raises(SystemExit, match="FIREBASE_PROJECT_ID"):
        cli.main(["admin", "list"])
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-altarmy")
    cli.main(["admin", "grant", "me@example.com"])
    assert "Granted admin for me@example.com (u1) in demo-altarmy." in capsys.readouterr().out
    cli.main(["admin", "grant", "you@example.com", "--project", "other"])
    cli.main(["admin", "revoke", "you@example.com"])
    cli.main(["admin", "list"])
    assert capsys.readouterr().out.endswith("me@example.com (u1)\n1 admins in demo-altarmy.\n")
    assert projects == ["demo-altarmy", "other", "demo-altarmy", "demo-altarmy"]
    with pytest.raises(SystemExit, match="no account has the email nobody@example.com"):
        cli.main(["admin", "grant", "nobody@example.com"])
    with pytest.raises(SystemExit, match="needs the account's email"):
        cli.main(["admin", "grant"])


def test_cli_ingest_only_if_new_skips_a_loaded_build(
    db2_paths: dict[str, Path],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    builds: list[str] = []

    def download_all(build: str, cache_dir: Path) -> dict[str, Path]:
        builds.append(build)
        return db2_paths

    monkeypatch.setattr(ingest, "download_all", download_all)
    monkeypatch.setattr(ingest, "pinned_build", lambda version, *pins: "2.5.7.1")
    dbfile = str(tmp_path / "t.sqlite")
    cli.main(["--game-version", "tbc", "--db", dbfile, "ingest", "--only-if-new"])
    assert "Ingested TBC Anniversary build 2.5.7.1" in capsys.readouterr().out
    cli.main(["--game-version", "tbc", "--db", dbfile, "ingest", "--only-if-new"])
    assert "already loaded" in capsys.readouterr().out
    assert builds == ["2.5.7.1"]
    cli.main(["--game-version", "tbc", "--db", dbfile, "ingest", "--only-if-new", "--force"])
    assert "Ingested TBC Anniversary build 2.5.7.1" in capsys.readouterr().out
    assert builds == ["2.5.7.1", "2.5.7.1"]
    with pytest.raises(SystemExit):
        cli.main(["--game-version", "tbc", "--db", dbfile, "ingest", "--force"])


def test_only_if_new_reloads_a_loaded_build_when_the_ingest_changed(
    conn: Connection, db2_paths: dict[str, Path], tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    builds: list[str] = []

    def download_all(build: str, cache_dir: Path) -> dict[str, Path]:
        builds.append(build)
        return db2_paths

    monkeypatch.setattr(ingest, "download_all", download_all)
    monkeypatch.setattr(ingest, "pinned_build", lambda version, *pins: "2.5.7.1")
    data = tmp_path / "data"
    data.mkdir()
    header = "item_class,quality,min_ilvl,max_ilvl,result_item_id,chance,min_count,max_count\n"
    (data / "disenchant.csv").write_text(header)
    v = replace(versions.get("tbc"), data_dir=data)

    def update() -> bool:
        return service.update_game_data(conn, v, tmp_path / "cache", only_if_new=True)[1]

    assert update()
    assert db.get_fingerprint(conn, "tbc") == ingest.fingerprint(v)
    assert not update()  # same build, same ingest
    (data / "disenchant.csv").write_text(header + "4,2,5,15,10940,1,1,1\n")
    assert update()  # a hand-maintained file changed
    assert not update()
    monkeypatch.setattr(ingest, "fingerprint", lambda version: "new code")
    assert update()  # the ingest code changed
    assert builds == ["2.5.7.1"] * 3


def test_fingerprint_follows_the_data_files_but_not_line_endings(tmp_path: Path) -> None:
    v = replace(versions.get("tbc"), data_dir=tmp_path)
    missing = ingest.fingerprint(v)
    assert len(missing) == 64 and ingest.fingerprint(v) == missing
    (tmp_path / "vendor_items.csv").write_bytes(b"item_id\n1\n")
    lf = ingest.fingerprint(v)
    assert lf != missing
    (tmp_path / "vendor_items.csv").write_bytes(b"item_id\r\n1\r\n")
    assert ingest.fingerprint(v) == lf
    (tmp_path / "vendor_items.csv").write_bytes(b"item_id\n2\n")
    assert ingest.fingerprint(v) != lf


def test_find_saved_variables(wow_root: Path) -> None:
    (wow_root / SV_DIR / "frellscout.lua").write_text("FrellscoutDB = {}")
    assert wowfiles.find_saved_variables("frellscout.lua", [wow_root]) == [
        wow_root / SV_DIR / "frellscout.lua"
    ]
    assert wowfiles.find_saved_variables("frellscout.lua", [wow_root], ("_anniversary_",)) == []


def test_price_confidence_flags_every_doubt_most_actionable_first() -> None:
    def flags(listing: prices.Listing, units: int = 1, watched: float = 0.0) -> tuple[str, ...]:
        return prices.confidence(listing, units, watched).flags

    known = prices.Listing(900, 50, source="altarmy", listed=True, median_7d=900, scans_7d=5)
    assert flags(known, watched=prices.WATCHED_ENOUGH_HOURS) == ()
    assert flags(known) == ("unwatched",)
    # a lone listing that never sold: an asking price, not a price; also thin, too new and unwatched
    lone = replace(known, quantity=1, scans_7d=1)
    assert flags(lone) == ("lone", "thin", "few_days", "unwatched")
    assert prices.confidence(lone, 1, 0.0).reason == "few_days"  # the level keeps its rule
    gone = replace(known, listed=False, quantity=0, sale_rate=2 / 7, sold_pairs_7d=1)
    assert flags(gone, watched=prices.WATCHED_ENOUGH_HOURS) == ("sold_out", "one_pair")
    assert flags(replace(known, listed=False, quantity=0)) == ("unlisted", "unwatched")
    assert prices.confidence(replace(known, sold_pairs_7d=3), 1, 0.0).sold_pairs == 3
