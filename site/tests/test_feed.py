"""The hourly auction snapshots in the price store (`feed.record_auction_snapshot`)."""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import Connection, select

from altarmy_site import book, cli, db, feed, merge, prices, schema, snapshots, uploads, versions

from .conftest import FOREVER as FOREVER_KEY
from .conftest import ME
from .snapshot_fixtures import FOREVER, HOUR, T0, auction, snap

ORE, BAR = 2770, 2840


def house(conn: Connection) -> int:
    return prices.auction_house(conn, FOREVER_KEY, "Normal", "Horde")


def record(conn: Connection, ah: int, s: snapshots.Snapshot) -> feed.FeedRecorded:
    return feed.record_auction_snapshot(conn, ah, s, FOREVER)


def current(conn: Connection, ah: int) -> dict[int, tuple[object, ...]]:
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.quantity, pc.c.listed, pc.c.ladder).where(
            pc.c.auction_house_id == ah
        )
    )
    return {r.item_id: tuple(r)[1:] for r in rows}


def sales(conn: Connection, ah: int) -> dict[int, dict[str, int]]:
    t = schema.price_sales_daily
    cols = (
        "units",
        "copper",
        "cancelled",
        "pairs",
        "auctions_sold",
        "bid_sold",
        "expired",
        "posted",
        "relisted",
        "ambiguous",
    )
    rows = conn.execute(select(t.c.item_id, *(t.c[c] for c in cols)).where(t.c.auction_house_id == ah))
    return {r.item_id: {c: getattr(r, c) for c in cols if getattr(r, c)} for r in rows}


def at(t: int) -> datetime:
    return datetime.fromtimestamp(t, UTC)


def test_a_snapshot_stores_each_items_ladder(conn: Connection) -> None:
    ah = house(conn)
    got = record(
        conn,
        ah,
        snap(T0, auction(1, ORE, unit=64, qty=3), auction(2, ORE, unit=167, qty=20), auction(3, BAR, bid=5)),
    )
    assert (got.items, got.moved, got.follows, got.stale, got.quarantined) == (1, 1, False, False, False)
    assert current(conn, ah) == {ORE: (64, 23, True, "64*3*1*0,167*20*1*0")}
    snap_row = conn.execute(
        select(schema.price_snapshots.c.source, schema.price_snapshots.c.item_count)
    ).one()
    assert tuple(snap_row) == ("blizzard_api", 1)
    assert prices.price_version(conn, ah) == 1
    assert feed.load_state(conn, ah) is not None


def test_snapshots_an_hour_apart_count_what_sold(conn: Connection) -> None:
    ah = house(conn)
    record(
        conn,
        ah,
        snap(
            T0,
            auction(1, ORE, unit=64, qty=3),
            auction(2, ORE, unit=167, qty=20),
            auction(3, ORE, unit=300, qty=1),
        ),
    )
    got = record(
        conn, ah, snap(T0 + HOUR, auction(2, ORE, unit=167, qty=20), auction(4, ORE, unit=150, qty=5))
    )
    assert (got.follows, got.ended, got.posted) == (True, 2, 1)
    # 1 (64) gone under 167, still listed: bought; 3 (300) gone from behind it: pulled
    assert sales(conn, ah) == {
        ORE: {"units": 3, "copper": 192, "cancelled": 1, "pairs": 1, "auctions_sold": 1, "posted": 1}
    }
    assert current(conn, ah)[ORE][:3] == (150, 25, True)


def test_an_item_no_longer_listed_is_unlisted(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=64), auction(2, BAR, unit=500)))
    got = record(conn, ah, snap(T0 + HOUR, auction(2, BAR, unit=500)))
    assert current(conn, ah)[ORE] == (64, 0, False, "")
    assert got.moved == 1


def test_a_stale_snapshot_changes_nothing(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=64)))
    got = record(conn, ah, snap(T0, auction(1, ORE, unit=99)))
    assert got.stale
    assert current(conn, ah)[ORE][0] == 64


def test_a_snapshot_cut_short_is_held_back(conn: Connection) -> None:
    ah = house(conn)
    full = [auction(i, ORE, unit=100 + i, left="VERY_LONG") for i in range(1, 101)]
    record(conn, ah, snap(T0, *full))
    got = record(conn, ah, snap(T0 + HOUR, *full[:30]))
    assert got.quarantined
    statuses: list[str] = list(
        conn.execute(select(schema.price_snapshots.c.status).order_by(schema.price_snapshots.c.id))
        .scalars()
        .all()
    )
    assert statuses == ["accepted", "quarantined"]
    # the next good snapshot is told apart against the last good one: nothing ended
    later = record(conn, ah, snap(T0 + 2 * HOUR, *full))
    assert later.ended == 0 and not later.follows  # two hours after the last good one


def test_hours_and_ends_are_recorded(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(9, ORE, unit=300, left="VERY_LONG")))
    record(
        conn,
        ah,
        snap(T0 + HOUR, auction(1, ORE, unit=100, qty=5), auction(9, ORE, unit=300, left="VERY_LONG")),
    )
    record(conn, ah, snap(T0 + 2 * HOUR, auction(9, ORE, unit=300, left="VERY_LONG")))
    t = schema.price_hourly
    hours: str = conn.execute(
        select(t.c.hours).where(t.c.auction_house_id == ah, t.c.item_id == ORE)
    ).scalar_one()
    unpacked = prices.unpack_hours(hours)
    assert unpacked[at(T0).hour] == prices.Hour(300, 300, 1, 1)
    assert unpacked[at(T0 + HOUR).hour] == prices.Hour(100, 100, 6, 2)
    e = schema.auction_ends_daily
    ends = conn.execute(select(e.c.item_id, e.c.stack, e.c.age_h, e.c.outcome, e.c.auctions, e.c.units)).all()
    assert [tuple(r) for r in ends] == [(ORE, 5, 1, "sold", 1, 5)]


def test_a_newer_addon_scan_wins_and_an_older_one_is_passed_over(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=64, qty=3)))
    later = book.Scan(T0 + 600, "Normal", "Horde", 1, 0, "own", {ORE: (book.Level(70, 2, 1),)})
    prices.record_book(conn, ah, later, scanned_at=at(T0 + 600))
    assert current(conn, ah)[ORE][:2] == (70, 2)
    earlier = book.Scan(T0 - 600, "Normal", "Horde", 1, 0, "own", {ORE: (book.Level(10, 2, 1),)})
    assert prices.record_book(conn, ah, earlier, scanned_at=at(T0 - 600)).stale
    # and the next snapshot wins again
    record(conn, ah, snap(T0 + HOUR, auction(1, ORE, unit=64, qty=3)))
    assert current(conn, ah)[ORE][:2] == (64, 3)


def test_addon_scans_count_no_sales_while_the_feed_is_live(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=64, qty=3), auction(2, ORE, unit=167, qty=20)))
    pair = [
        book.Scan(
            T0 + 600, "Normal", "Horde", 2, 0, "own", {ORE: (book.Level(64, 3, 1), book.Level(167, 20, 1))}
        ),
        book.Scan(T0 + 1200, "Normal", "Horde", 1, 0, "own", {ORE: (book.Level(167, 20, 1),)}),
    ]
    for s in pair:
        prices.record_book(conn, ah, s, scanned_at=at(s.t))
    assert sales(conn, ah) == {}  # the next snapshot counts the 3 that went
    record(conn, ah, snap(T0 + HOUR, auction(2, ORE, unit=167, qty=20)))
    assert sales(conn, ah)[ORE]["units"] == 3


def test_addon_scans_count_sales_without_a_feed(conn: Connection) -> None:
    ah = house(conn)
    first = book.Scan(
        T0, "Normal", "Horde", 2, 0, "own", {ORE: (book.Level(64, 3, 1), book.Level(167, 20, 1))}
    )
    then = book.Scan(T0 + 600, "Normal", "Horde", 1, 0, "own", {ORE: (book.Level(167, 20, 1),)})
    for s in (first, then):
        prices.record_book(conn, ah, s, scanned_at=at(s.t))
    assert sales(conn, ah)[ORE]["units"] == 3


def test_snapshots_count_as_watched_hours(conn: Connection) -> None:
    ah = house(conn)
    for h in range(4):
        record(conn, ah, snap(T0 + h * HOUR, auction(1, ORE, unit=64, left="VERY_LONG")))
    assert prices.watched_hours(conn, ah, at(T0 + 4 * HOUR)) == 3.0


def test_snapshot_prices_are_read_like_scans(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=100, qty=3), auction(2, ORE, unit=167, qty=20)))
    assert prices.load_books(conn, ah, credible=False) == {
        ORE: (book.Level(100, 3, 1), book.Level(167, 20, 1))
    }
    buy, sell = prices.load_buy_and_sell(conn, ah, first_party=True)
    assert buy == {ORE: 100} and sell == {ORE: 167}
    listing = prices.load_listings(conn, ah)[ORE]
    assert prices.sale_depth(listing, 167) == 23


def test_prune_keeps_two_weeks_of_hours(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=64)))
    prices.prune(conn, at(T0) + timedelta(days=prices.HOURLY_DAYS))
    assert conn.execute(select(schema.price_hourly.c.item_id)).all() != []
    prices.prune(conn, at(T0) + timedelta(days=prices.HOURLY_DAYS + 1))
    assert conn.execute(select(schema.price_hourly.c.item_id)).all() == []


# --- the merge over the snapshots ---------------------------------------------------------------------
def pc_row(conn: Connection, ah: int, item: int) -> Any:
    pc = schema.price_current
    return conn.execute(select(pc).where(pc.c.auction_house_id == ah, pc.c.item_id == item)).one()


def sells_twenty(conn: Connection, ah: int, start: int) -> None:
    """An hour before `start` one dear auction; at `start` 20 cheap ones posted; an hour later all bought."""
    keep = auction(999, ORE, unit=5000, left="VERY_LONG")
    cheap = [auction(start + i, ORE, unit=100 + i, left="VERY_LONG") for i in range(20)]
    record(conn, ah, snap(start - HOUR, keep))
    record(conn, ah, snap(start, keep, *cheap))
    record(conn, ah, snap(start + HOUR, keep))


def test_the_time_weighted_price_decays_by_half_lives(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, ORE, unit=100, left="VERY_LONG")))
    record(conn, ah, snap(T0 + 24 * HOUR, auction(2, ORE, unit=200, left="VERY_LONG")))
    row = pc_row(conn, ah, ORE)
    assert row.ewma_24h == 150  # a day later: half the old price, half the new
    assert row.ewma_72h == round(100 * 0.5 ** (1 / 3) + 200 * (1 - 0.5 ** (1 / 3)))
    assert prices.ewma(None, None, 70, at(T0), prices.EWMA_SHORT) == 70


def test_the_merge_reads_time_to_sell_and_sell_through(conn: Connection) -> None:
    ah = house(conn)
    sells_twenty(conn, ah, T0)
    merge.merge(conn, FOREVER_KEY, today=at(T0 + HOUR).date())
    row = pc_row(conn, ah, ORE)
    assert row.ttl_hours == 1.0  # all 20 sold in their first hour; the dear one is still up
    assert row.sell_through == 1.0
    assert row.stacks == "1:20/0"
    assert (row.resolved_2d, row.resolved_days, row.gate) == (20, 1, "launch")


def test_two_days_of_sales_open_the_normal_gate(conn: Connection) -> None:
    ah = house(conn)
    sells_twenty(conn, ah, T0)
    sells_twenty(conn, ah, T0 + 24 * HOUR)
    merge.merge(conn, FOREVER_KEY, today=at(T0 + 25 * HOUR).date())
    assert pc_row(conn, ah, ORE).gate == "normal"


def test_after_launch_one_day_of_sales_opens_nothing(conn: Connection) -> None:
    ah = house(conn)
    record(conn, ah, snap(T0 - 30 * 24 * HOUR, auction(1, BAR, unit=500, left="VERY_LONG")))
    sells_twenty(conn, ah, T0)
    merge.merge(conn, FOREVER_KEY, today=at(T0 + HOUR).date())
    assert pc_row(conn, ah, ORE).gate is None


def test_the_merge_reads_open_close_and_medians_from_the_hours(conn: Connection) -> None:
    ah = house(conn)
    for h, price in enumerate((100, 300, 200)):
        record(conn, ah, snap(T0 + h * HOUR, auction(h + 1, ORE, unit=price, left="VERY_LONG")))
    merge.merge(conn, FOREVER_KEY, today=at(T0).date())
    pd = schema.price_daily
    day = conn.execute(select(pd.c.low, pd.c.high, pd.c.median, pd.c.open, pd.c.close)).one()
    assert tuple(day) == (100, 300, 200, 100, 200)


# --- asks that can't be trusted -----------------------------------------------------------------------
SKIN = 4000  # a grey skin a vendor pays 25c for


def test_an_ask_counts_at_most_so_far_over_sales_or_the_vendor() -> None:
    assert prices.trusted_ask(900, sale_price=400, vendor=25) == 800
    assert prices.trusted_ask(900, sale_price=None, vendor=5) == 500
    assert prices.trusted_ask(900, sale_price=None, vendor=None) == 900
    assert prices.trusted_ask(300, sale_price=400, vendor=None) == 300


def test_a_troll_listing_moves_neither_the_day_nor_the_time_weighted_price(conn: Connection) -> None:
    conn.execute(
        schema.items.insert().values(
            game_version=FOREVER_KEY, id=SKIN, name="Smooth Raptor Skin", sell_price=25
        )
    )
    ah = house(conn)
    record(conn, ah, snap(T0, auction(1, SKIN, unit=150, qty=5, left="VERY_LONG")))
    troll = 99_999_990_000
    record(conn, ah, snap(T0 + HOUR, auction(2, SKIN, unit=troll, left="VERY_LONG")))
    row = pc_row(conn, ah, SKIN)
    assert row.market_price == troll  # what is asked, as it is
    assert row.ewma_24h <= 25 * prices.ASK_OVER_VENDOR
    pd = schema.price_daily
    assert (
        conn.execute(select(pd.c.high).where(pd.c.item_id == SKIN)).scalar_one()
        == 25 * prices.ASK_OVER_VENDOR
    )
    _, sell = prices.load_buy_and_sell(conn, ah, first_party=True)
    assert sell[SKIN] == row.ewma_24h


# --- the fixed realms ---------------------------------------------------------------------------------
def test_each_fixed_realm_has_an_alliance_and_a_horde_house(conn: Connection) -> None:
    t = schema.auction_houses
    houses = conn.execute(select(t.c.realm, t.c.faction).where(t.c.game_version == FOREVER_KEY)).all()
    assert {(r.realm, r.faction) for r in houses} == {
        (f"{region} {ruleset}", faction)
        for region in ("Americas", "Europe", "Asia")
        for ruleset in ("Normal", "PvP", "RP", "RP-PvP", "Hardcore")
        for faction in ("Alliance", "Horde")
    }


def test_a_realm_name_is_a_fixed_realm_by_name_or_alias() -> None:
    pvp = versions.RealmSpec("pvp", "PvP", "PvP", aliases=("Nightslayer",), region="americas", ruleset="pvp")
    version = replace(FOREVER, realms=(pvp,))
    assert version.realm_name("night slayer") == "PvP"
    assert version.realm_name("PVP") == "PvP"
    assert version.realm_name("Classic Beta PvE") == "Classic Beta PvE"  # not a fixed realm: as it is
    assert version.realm_name("CAMWOW US2 Realm 3 PvP") == "PvP"  # a coalesced realm: its region's ruleset
    assert version.realm_name("CAMWOW EU4 Realm 3 PvP") == "CAMWOW EU PvP"  # no fixed realm of its region
    assert version.canonical_realm("Elsewhere") is None


def test_coverage_lists_the_fixed_houses_first(conn: Connection) -> None:
    scanned_house = prices.auction_house(conn, FOREVER_KEY, "Classic Beta PvE", "Horde")
    record(conn, scanned_house, snap(T0, auction(1, ORE, unit=64)))
    got = prices.coverage(conn, FOREVER_KEY, at(T0 + HOUR))
    assert [(c.realm, c.faction, c.realm_key) for c in got][:3] == [
        ("Americas Normal", "Alliance", "americas-normal"),
        ("Americas Normal", "Horde", "americas-normal"),
        ("Americas PvP", "Alliance", "americas-pvp"),
    ]
    hardcore = next(c for c in got if c.realm == "Americas Hardcore")
    assert not hardcore.open
    beta = got[-1]
    assert (beta.realm, beta.realm_key, beta.feed, beta.launch) == ("Classic Beta PvE", None, True, True)


def test_an_addon_scan_under_a_fixed_realms_other_name_lands_on_its_house(
    conn: Connection, monkeypatch: pytest.MonkeyPatch
) -> None:
    normal = versions.RealmSpec("normal", "Normal", "Normal", aliases=("Doomhowl",))
    monkeypatch.setitem(versions.VERSIONS, FOREVER_KEY, replace(FOREVER, realms=(normal,)))
    scan = book.Scan(T0, "Doomhowl", "Horde", 1, 0, "own", {ORE: (book.Level(70, 2, 1),)})
    (got,) = uploads._record_books(conn, ME, FOREVER_KEY, [scan], at(T0 + 60))
    assert got.auction_house_id == prices.find_auction_house(conn, FOREVER_KEY, "Normal", "Horde")


def test_an_addon_scan_on_a_coalesced_realm_lands_on_its_regions_house(conn: Connection) -> None:
    scan = book.Scan(T0, "CAMWOW US2 Realm 3 PvE", "Horde", 1, 0, "own", {ORE: (book.Level(70, 2, 1),)})
    (got,) = uploads._record_books(conn, ME, FOREVER_KEY, [scan], at(T0 + 60))
    assert got.auction_house_id == prices.find_auction_house(conn, FOREVER_KEY, "Americas Normal", "Horde")


# --- the local loader ---------------------------------------------------------------------------------
FIXTURES = Path(__file__).parent / "fixtures" / "snapshots"


def test_feed_load_records_saved_snapshots_an_hour_apart(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    dbfile = str(tmp_path / "f.sqlite")
    files = [str(FIXTURES / f"hour{i}.json") for i in range(3)]
    cli.main(
        [
            "--db",
            dbfile,
            "feed-load",
            "--realm",
            "Normal",
            "--faction",
            "Horde",
            "--start",
            "2025-11-04T12:00:00+00:00",
            *files,
        ]
    )
    out = capsys.readouterr().out
    assert "hour1.json: 3 items" in out and "2 ended, 2 posted" in out
    cli.main(["--db", dbfile, "merge"])
    database = db.Database(db.sqlite_url(dbfile))
    with database.begin() as conn:
        ah = prices.find_auction_house(conn, FOREVER_KEY, "Normal", "Horde")
        assert ah is not None
        got = sales(conn, ah)
        assert got[ORE]["units"] == 40 and got[ORE]["auctions_sold"] == 2  # 1 and 2 bought
        assert got[BAR]["expired"] == 1
        assert got[SKIN]["relisted"] == 1
        pd = schema.price_daily
        high: int = conn.execute(
            select(pd.c.high).where(pd.c.auction_house_id == ah, pd.c.item_id == SKIN)
        ).scalar_one()
        assert high < 99_999_990_000  # the troll never reached the day's figures
    database.dispose()
