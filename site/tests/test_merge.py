from datetime import UTC, date, datetime, timedelta

from sqlalchemy import Connection, select

from altarmy_site import book, merge, prices, schema, store
from altarmy_site.auctionator import DayStats, ItemPrice
from altarmy_site.prices import Observation

from .conftest import FOREVER

TODAY = date(2026, 9, 24)
NOON = datetime(2026, 9, 24, 12, 0, tzinfo=UTC)


def daily_medians(conn: Connection, ah: int, item_id: int) -> dict[date, int | None]:
    pd = schema.price_daily
    rows = conn.execute(
        select(pd.c.day, pd.c.median).where(pd.c.auction_house_id == ah, pd.c.item_id == item_id)
    )
    return {r.day: r.median for r in rows}


def seven_day(conn: Connection, ah: int, item_id: int) -> tuple[int | None, int | None, int | None]:
    pc = schema.price_current
    row = conn.execute(
        select(pc.c.median_7d, pc.c.avail_7d, pc.c.scans_7d).where(
            pc.c.auction_house_id == ah, pc.c.item_id == item_id
        )
    ).one()
    return row.median_7d, row.avail_7d, row.scans_7d


def test_median() -> None:
    assert merge.median([5]) == 5
    assert merge.median([1, 9, 3]) == 3
    assert merge.median([100, 201]) == 150  # rounded down to whole copper


def test_daily_median_uses_the_days_scans_within_low_and_high(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_daily(conn, ah, {1: ItemPrice(100, {TODAY: DayStats(200, 100, 5)})})
    for hour, price in ((9, 170), (10, 180), (11, 900)):
        at = NOON.replace(hour=hour)
        prices.record_snapshot(conn, ah, "auctionator", at, [Observation(1, price, at)])
    merge.merge_auction_house(conn, ah, TODAY)
    # of low 100, high 200 and the scans 170, 180 and 900 (clamped to 200)
    assert daily_medians(conn, ah, 1) == {TODAY: 180}


def test_seven_day_columns_use_the_items_latest_seven_days_with_data(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    days = {
        TODAY - timedelta(days=40): DayStats(9000, 9000, 1),  # before the lookback
        TODAY - timedelta(days=20): DayStats(9000, 9000, 1),  # an eighth, older day
        # scanned every few days, as one player does
        **{
            TODAY - timedelta(days=n): DayStats(p, p, 4)
            for n, p in ((18, 100), (15, 105), (12, 110), (9, 120))
        },
        TODAY - timedelta(days=6): DayStats(110, 110, 8),
        TODAY - timedelta(days=3): DayStats(130, 130, 5),
        TODAY: DayStats(3_330_000, 3_330_000, 1),  # a lone overpriced listing
    }
    prices.record_daily(conn, ah, {1: ItemPrice(3_330_000, days)})
    prices.record_snapshot(conn, ah, "auctionator", NOON, [Observation(1, 3_330_000, NOON)])
    assert merge.merge_auction_house(conn, ah, TODAY) is True
    # of 100, 105, 110, 120, 110, 130 and 3,330,000; availability of 4, 4, 4, 4, 8, 5, 1
    assert seven_day(conn, ah, 1) == (110, 4, 7)


def test_items_without_recent_days_get_no_seven_day_values(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    old = TODAY - timedelta(days=30)
    prices.record_daily(conn, ah, {1: ItemPrice(50, {old: DayStats(50, 50, 2)})})
    prices.record_snapshot(conn, ah, "manual", NOON, [Observation(1, 50, NOON)])
    merge.merge_auction_house(conn, ah, TODAY)
    assert seven_day(conn, ah, 1) == (None, None, None)


def test_merge_bumps_the_price_version_only_when_something_changed(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_daily(conn, ah, {1: ItemPrice(100, {TODAY: DayStats(100, 100, 1)})})
    prices.record_snapshot(conn, ah, "auctionator", NOON, [Observation(1, 100, NOON)])
    before = store.market_stamp(conn, FOREVER, ah)
    assert merge.merge_auction_house(conn, ah, TODAY) is True
    after = store.market_stamp(conn, FOREVER, ah)
    assert after != before
    assert merge.merge_auction_house(conn, ah, TODAY) is False
    assert store.market_stamp(conn, FOREVER, ah) == after


def test_merge_covers_every_auction_house_of_the_version(conn: Connection) -> None:
    a = prices.auction_house(conn, FOREVER, "A", "")
    b = prices.auction_house(conn, FOREVER, "B", "")
    tbc = prices.auction_house(conn, "tbc", "C", "")
    for ah in (a, b, tbc):
        prices.record_daily(conn, ah, {1: ItemPrice(100, {TODAY: DayStats(100, 100, 1)})})
        prices.record_snapshot(conn, ah, "auctionator", NOON, [Observation(1, 100, NOON)])
    merged = merge.merge(conn, FOREVER, today=TODAY)
    assert {ah: merged[ah] for ah in (a, b)} == {a: True, b: True}
    assert not any(changed for ah, changed in merged.items() if ah not in (a, b))  # the fixed realms' houses
    assert seven_day(conn, tbc, 1) == (None, None, None)


def test_quarantined_snapshots_do_not_count(conn: Connection) -> None:
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_daily(conn, ah, {1: ItemPrice(100, {TODAY: DayStats(200, 100, 1)})})
    at = NOON.replace(hour=9)
    prices.record_snapshot(conn, ah, "auctionator", at, [Observation(1, 150, at)])
    snap = schema.price_snapshots
    bad: int = conn.execute(
        snap.insert()
        .values(
            auction_house_id=ah,
            source="auctionator",
            scanned_at=NOON,
            received_at=NOON,
            item_count=1,
            status="quarantined",
        )
        .returning(snap.c.id)
    ).scalar_one()
    conn.execute(schema.price_observations.insert().values(snapshot_id=bad, item_id=1, min_buyout=200))
    merge.merge_auction_house(conn, ah, TODAY)
    assert daily_medians(conn, ah, 1) == {TODAY: 150}  # of 100, 200 and 150 only


# --- Alt Army's order book -----------------------------------------------------------------------
def book_scan(items: dict[int, list[tuple[int, int]]], at: datetime) -> book.Scan:
    ladders = {i: tuple(book.Level(p, q, 1) for p, q in levels) for i, levels in items.items()}
    return book.Scan(int(at.timestamp()), "Classic Beta PvE", "Horde", 1, 0, "own", ladders)


def sales(conn: Connection, ah: int, item_id: int) -> tuple[int | None, float | None]:
    pc = schema.price_current
    row = conn.execute(
        select(pc.c.sale_price, pc.c.sale_rate).where(pc.c.auction_house_id == ah, pc.c.item_id == item_id)
    ).one()
    return row.sale_price, row.sale_rate


def sold_pairs(conn: Connection, ah: int, item_id: int) -> int | None:
    pc = schema.price_current
    found: int | None = conn.execute(
        select(pc.c.sold_pairs_7d).where(pc.c.auction_house_id == ah, pc.c.item_id == item_id)
    ).scalar_one()
    return found


def test_a_scans_market_price_makes_the_median_not_its_cheapest_listing(conn: Connection) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    prices.record_book(conn, ah, book_scan({1: [(64, 3), (167, 5000)]}, NOON))
    merge.merge_auction_house(conn, ah, TODAY)
    assert daily_medians(conn, ah, 1) == {TODAY: 167}
    assert seven_day(conn, ah, 1) == (167, 5003, 1)


def test_sales_of_the_last_week_make_the_sale_price_and_rate(conn: Connection) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    prices.record_book(conn, ah, book_scan({1: [(100, 50)], 2: [(100, 50)]}, NOON))
    t = schema.price_sales_daily
    rows = [
        (1, TODAY - timedelta(days=8), 500, 500 * 900, 9),  # too long ago
        (1, TODAY - timedelta(days=3), 10, 10 * 100, 1),
        (1, TODAY - timedelta(days=1), 30, 30 * 120, 2),
        (1, TODAY, 2, 2 * 500, 1),
        (2, TODAY, merge.MIN_SALES - 1, (merge.MIN_SALES - 1) * 100, 1),  # too few to tell a price by
    ]
    for item, day, units, copper, pairs in rows:
        conn.execute(
            t.insert().values(
                auction_house_id=ah,
                item_id=item,
                day=day,
                units=units,
                copper=copper,
                cancelled=0,
                pairs=pairs,
            )
        )
    before = prices.price_version(conn, ah)
    assert merge.merge_auction_house(conn, ah, TODAY)
    # by units, the middle sale went for 120: 10 at 100, 30 at 120, 2 at 500
    assert sales(conn, ah, 1) == (120, 42 / 7)
    assert sales(conn, ah, 2) == (None, (merge.MIN_SALES - 1) / 7)
    assert (sold_pairs(conn, ah, 1), sold_pairs(conn, ah, 2)) == (4, 1)  # the pairs of scans they sold in
    assert prices.price_version(conn, ah) == (before or 0) + 1
    assert not merge.merge_auction_house(conn, ah, TODAY)


def test_sales_that_age_out_are_forgotten(conn: Connection) -> None:
    ah = prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    prices.record_book(conn, ah, book_scan({1: [(100, 50)]}, NOON))
    conn.execute(
        schema.price_sales_daily.insert().values(
            auction_house_id=ah, item_id=1, day=TODAY, units=10, copper=1000, cancelled=0
        )
    )
    merge.merge_auction_house(conn, ah, TODAY)
    assert sales(conn, ah, 1) == (100, 10 / 7)
    merge.merge_auction_house(conn, ah, TODAY + timedelta(days=7))
    assert sales(conn, ah, 1) == (None, None)
    assert sold_pairs(conn, ah, 1) is None


def test_a_quarantined_snapshot_leaves_the_market_stamp_alone(conn: Connection) -> None:
    # it changes nothing a market reads, so cached markets and their rankings stay
    ah = prices.unnamed_auction_house(conn, FOREVER)
    prices.record_snapshot(conn, ah, "manual", NOON, [Observation(1, 50, NOON)])
    before = store.market_stamp(conn, FOREVER, ah)
    snap = schema.price_snapshots
    conn.execute(
        snap.insert().values(
            auction_house_id=ah,
            source="altarmy",
            scanned_at=NOON,
            received_at=NOON,
            item_count=1,
            status="quarantined",
        )
    )
    assert store.market_stamp(conn, FOREVER, ah) == before
    prices.record_snapshot(conn, ah, "manual", NOON, [Observation(1, 60, NOON)])
    assert store.market_stamp(conn, FOREVER, ah) != before  # an accepted one moves it
