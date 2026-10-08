"""Alt Army's order book in the price store (`prices.record_book` and what is read back)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import Connection, select

from altarmy_site import book, prices, schema
from altarmy_site.book import Level

from .conftest import FOREVER, ME

T0 = datetime(2026, 9, 29, 12, 0, tzinfo=UTC)
ORE, EARTH, BAR = 2770, 7067, 2840


def ladder(*levels: tuple[int, int]) -> book.Ladder:
    return tuple(Level(price, quantity, 1) for price, quantity in levels)


def scan(items: dict[int, book.Ladder], at: datetime = T0) -> book.Scan:
    return book.Scan(int(at.timestamp()), "Classic Beta PvE", "Horde", 10, 0, "own", items)


def house(conn: Connection) -> int:
    return prices.auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")


def current(conn: Connection, ah: int) -> dict[int, tuple[object, ...]]:
    pc = schema.price_current
    rows = conn.execute(
        select(pc.c.item_id, pc.c.price, pc.c.quantity, pc.c.market_price, pc.c.listed, pc.c.ladder).where(
            pc.c.auction_house_id == ah
        )
    )
    return {r.item_id: tuple(r)[1:] for r in rows}


def version(conn: Connection, ah: int) -> int:
    got = prices.price_version(conn, ah)
    assert got is not None
    return got


def test_a_scan_stores_each_items_ladder(conn: Connection) -> None:
    ah = house(conn)
    got = prices.record_book(
        conn, ah, scan({ORE: ladder((64, 3), (167, 5020)), EARTH: ladder((700, 1))}), uploader_uid=ME
    )
    assert (got.items, got.moved, got.stale, got.quarantined) == (2, 2, False, False)
    assert current(conn, ah) == {
        ORE: (64, 5023, 167, True, "64*3*1*0,167*5020*1*0"),
        EARTH: (700, 1, 700, True, "700*1*1*0"),
    }
    assert version(conn, ah) == 1
    snap = schema.price_snapshots
    row = conn.execute(select(snap.c.source, snap.c.uploader_uid, snap.c.item_count, snap.c.scanned_at)).one()
    assert (row.source, row.uploader_uid, row.item_count) == ("altarmy", ME, 2)


def test_an_item_gone_from_a_scan_is_no_longer_listed(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((167, 10)), EARTH: ladder((700, 1))}))
    got = prices.record_book(conn, ah, scan({ORE: ladder((167, 10))}, T0 + timedelta(minutes=20)))
    assert got.moved == 1
    assert current(conn, ah)[EARTH] == (700, 0, 700, False, "")
    assert current(conn, ah)[ORE][3] is True
    assert EARTH not in prices.load_books(conn, ah)
    assert list(prices.load_books(conn, ah)) == [ORE]


def test_levels_age_and_the_same_scan_again_changes_nothing(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5020))}))
    later = T0 + timedelta(minutes=20)
    got = prices.record_book(conn, ah, scan({ORE: ladder((167, 5000), (170, 5))}, later))
    assert got.moved == 1  # the cheapest listing went
    assert current(conn, ah)[ORE][4] == "167*5000*1*1,170*5*1*0"
    before = version(conn, ah)
    again = prices.record_book(conn, ah, scan({ORE: ladder((167, 5000), (170, 5))}, later))
    assert (again.stale, again.moved) == (True, 0)
    assert version(conn, ah) == before
    snapshots = conn.execute(select(schema.price_snapshots.c.id)).all()
    assert len(snapshots) == 2


def test_an_older_scan_than_the_newest_is_not_used(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((167, 10))}, T0 + timedelta(minutes=30)))
    got = prices.record_book(conn, ah, scan({ORE: ladder((50, 10))}, T0))
    assert got.stale
    assert current(conn, ah)[ORE][0] == 167


def test_only_a_changed_price_is_news(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((167, 10)), BAR: ladder((300, 5))}))
    before = version(conn, ah)
    got = prices.record_book(
        conn, ah, scan({ORE: ladder((167, 8)), BAR: ladder((300, 5))}, T0 + timedelta(minutes=20))
    )
    assert got.moved == 0
    assert version(conn, ah) == before
    assert current(conn, ah)[ORE][1] == 8  # the quantity follows all the same
    obs = schema.price_observations
    assert len(conn.execute(select(obs.c.item_id)).all()) == 2  # the first scan's


def test_a_newer_hand_set_price_holds(conn: Connection) -> None:
    ah = house(conn)
    prices.set_price(conn, ah, ORE, 999)
    prices.record_book(conn, ah, scan({ORE: ladder((167, 10))}, T0))  # scanned before the price was set
    assert current(conn, ah)[ORE][0] == 999
    prices.record_book(conn, ah, scan({ORE: ladder((167, 10))}, datetime.now(UTC) + timedelta(minutes=1)))
    assert current(conn, ah)[ORE][0] == 167


def test_sales_are_inferred_between_scans_close_together(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5020)), BAR: ladder((300, 5), (400, 5))}))
    prices.record_book(
        conn,
        ah,
        scan({ORE: ladder((167, 5000)), BAR: ladder((300, 5), (400, 1))}, T0 + timedelta(minutes=20)),
    )
    sales = schema.price_sales_daily
    rows = {r.item_id: (r.units, r.copper, r.cancelled) for r in conn.execute(select(sales))}
    assert rows == {ORE: (23, 3 * 64 + 20 * 167, 0), BAR: (0, 0, 4)}
    prices.record_book(conn, ah, scan({ORE: ladder((167, 4990))}, T0 + timedelta(minutes=40)))
    rows = {r.item_id: (r.units, r.copper, r.cancelled) for r in conn.execute(select(sales))}
    assert rows[ORE] == (33, 3 * 64 + 30 * 167, 0)
    assert rows[BAR] == (0, 0, 10)  # gone altogether: no telling
    # the pairs of scans each item was seen selling in: ore in both, the bars in none
    pairs = {r.item_id: r.pairs for r in conn.execute(select(sales))}
    assert pairs == {ORE: 2, BAR: 0}


def test_cheap_levels_first_seen_before_a_baseline_are_not_counted_on(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((150, 10), (160, 40))}))
    # a fresh listing at under half the next level's price: gone before anyone gets there
    later = T0 + timedelta(hours=2)
    prices.record_book(conn, ah, scan({ORE: ladder((60, 1), (150, 10), (160, 40))}, later))
    assert [lv.price for lv in prices.load_books(conn, ah)[ORE]] == [150, 160]
    assert [lv.price for lv in prices.load_books(conn, ah, credible=False)[ORE]] == [60, 150, 160]
    # once it has stayed a scan, it counts
    prices.record_book(
        conn, ah, scan({ORE: ladder((60, 1), (150, 10), (160, 40))}, later + timedelta(hours=2))
    )
    assert [lv.price for lv in prices.load_books(conn, ah)[ORE]] == [60, 150, 160]
    # an undercut near the next price is no stray
    prices.record_book(conn, ah, scan({ORE: ladder((140, 1), (150, 10))}, later + timedelta(hours=4)))
    assert [lv.price for lv in prices.load_books(conn, ah)[ORE]] == [140, 150]


def test_scans_far_apart_infer_no_sales(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5020))}))
    prices.record_book(conn, ah, scan({ORE: ladder((167, 5000))}, T0 + timedelta(hours=3)))
    assert conn.execute(select(schema.price_sales_daily)).all() == []


def test_the_daily_history_follows_the_market_price(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5020))}))
    prices.record_book(conn, ah, scan({ORE: ladder((150, 4000))}, T0 + timedelta(minutes=20)))
    assert prices.daily(conn, ah, ORE) == [(T0.date(), 150, 167, 5023)]


def test_a_scan_far_off_the_baseline_is_quarantined(conn: Connection) -> None:
    ah = house(conn)
    items = {i: ladder((1000, 10)) for i in range(1, 31)}
    prices.record_book(conn, ah, scan(items))
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=1000, scans_7d=3))
    wild = {i: ladder((9000, 10)) for i in range(1, 31)}
    got = prices.record_book(conn, ah, scan(wild, T0 + timedelta(hours=2)), uploader_uid=ME, trust=1.0)
    assert (got.quarantined, got.screened, got.moved) == (True, True, 0)
    assert current(conn, ah)[1][0] == 1000
    fine = {i: ladder((1100, 10)) for i in range(1, 31)}
    got = prices.record_book(conn, ah, scan(fine, T0 + timedelta(hours=2)), uploader_uid=ME, trust=1.0)
    assert (got.quarantined, got.screened, got.moved) == (False, True, 30)


def test_a_scan_that_shares_nothing_with_the_one_just_before_is_quarantined(conn: Connection) -> None:
    ah = house(conn)
    items = {i: ladder((1000 + i, 10), (2000 + i, 10)) for i in range(1, 41)}
    prices.record_book(conn, ah, scan(items))
    other = {i: ladder((1500 + i, 10), (2500 + i, 10)) for i in range(1, 41)}
    got = prices.record_book(conn, ah, scan(other, T0 + timedelta(minutes=16)), uploader_uid=ME, trust=1.0)
    assert got.quarantined
    got = prices.record_book(conn, ah, scan(other, T0 + timedelta(hours=6)), uploader_uid=ME, trust=1.0)
    assert not got.quarantined  # hours later a new book is no surprise


def test_unscreened_without_trust(conn: Connection) -> None:
    ah = house(conn)
    items = {i: ladder((1000 + i, 10)) for i in range(1, 41)}
    prices.record_book(conn, ah, scan(items))
    other = {i: ladder((1500 + i, 10)) for i in range(1, 41)}
    got = prices.record_book(conn, ah, scan(other, T0 + timedelta(minutes=16)))
    assert (got.quarantined, got.screened) == (False, False)


# --- reading -------------------------------------------------------------------------------------
def test_books_leave_out_fresh_listings_far_below_the_usual_price(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((167, 5000)), EARTH: ladder((11000, 3))}))
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=pc.c.market_price, scans_7d=3))
    prices.record_book(
        conn,
        ah,
        scan({ORE: ladder((64, 3), (167, 5000)), EARTH: ladder((700, 1))}, T0 + timedelta(minutes=20)),
    )
    books = prices.load_books(conn, ah)
    assert [(lv.price, lv.quantity) for lv in books[ORE]] == [(167, 5000)]
    assert EARTH not in books  # its only listing is a fresh stray
    everything = prices.load_books(conn, ah, credible=False)
    assert [(lv.price, lv.quantity) for lv in everything[ORE]] == [(64, 3), (167, 5000)]
    assert [(lv.price, lv.quantity) for lv in everything[EARTH]] == [(700, 1)]


def test_a_cheap_listing_that_survived_a_scan_counts(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5000))}))
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=167, scans_7d=3))
    prices.record_book(conn, ah, scan({ORE: ladder((64, 3), (167, 5000))}, T0 + timedelta(minutes=20)))
    assert [lv.price for lv in prices.load_books(conn, ah)[ORE]] == [64, 167]


def test_the_sell_price_is_the_lowest_of_what_is_asked_and_what_sells() -> None:
    assert prices.book_sell_price(market=167, listed=True, reference=150, sale_price=None) == 150
    assert prices.book_sell_price(market=167, listed=True, reference=150, sale_price=140) == 140
    assert prices.book_sell_price(market=120, listed=True, reference=150, sale_price=140) == 120
    assert prices.book_sell_price(market=167, listed=True, reference=None, sale_price=None) == 167
    # not listed: what it used to go for, never the last listing alone if anything better is known
    assert prices.book_sell_price(market=500, listed=False, reference=150, sale_price=None) == 150
    assert prices.book_sell_price(market=500, listed=False, reference=None, sale_price=None) == 500


def test_first_party_prices_ignore_other_sources(conn: Connection) -> None:
    ah = house(conn)
    prices.record_snapshot(conn, ah, "ahledger", T0, [prices.Observation(BAR, 5, T0)])  # an old row
    prices.record_book(conn, ah, scan({ORE: ladder((100, 3), (167, 5020))}, T0 + timedelta(minutes=1)))
    prices.set_price(conn, ah, EARTH, 999)
    buy, sell = prices.load_buy_and_sell(conn, ah, first_party=True)
    assert buy == {ORE: 100, EARTH: 999}
    assert sell == {ORE: 167, EARTH: 999}
    books = prices.load_books(conn, ah)
    assert list(books) == [ORE]
    assert set(prices.load_buy_and_sell(conn, ah)[0]) == {ORE, EARTH, BAR}


def test_sale_depth_is_the_more_of_seen_sold_and_listed_at_or_under_the_price() -> None:
    ladder = (Level(100, 5, 1), Level(150, 10, 2))
    listing = prices.Listing(100, 15, ladder, sale_rate=1.0, source=prices.ALTARMY)
    assert prices.sale_depth(listing, 120) == max(round(prices.SALES_DAYS), 5)  # a week's sales
    assert prices.sale_depth(listing, 150) == 15  # everything listed at or under the price
    assert prices.sale_depth(listing, None) == round(prices.SALES_DAYS)
    assert prices.sale_depth(prices.Listing(100, 15, ladder, source=prices.ALTARMY), 99) == 0
    # a price from another source says nothing of how deep the market is
    assert prices.sale_depth(prices.Listing(100, 15, ladder, sale_rate=1.0, source="manual"), 150) is None
