"""The Alt Army addon's auction house order book (`book.py`)."""

from __future__ import annotations

import pytest

from altarmy_site import book
from altarmy_site.book import Level

from .addon_fixtures import AUCTION_BOOK as FIXTURE


def ladder(*levels: tuple[int, int]) -> book.Ladder:
    return tuple(Level(price, quantity, 1) for price, quantity in levels)


def saved(scans: str) -> bytes:
    return f'AltArmyTBC_AuctionBook = {{\n["version"] = 1,\n["scans"] = {{\n{scans}}},\n}}\n'.encode()


def scan(items: str = "2770:64*1*1", **changes: str) -> str:
    fields = {
        "t": "1790726574",
        "realm": '"Classic PvE"',
        "faction": '"Horde"',
        "complete": "true",
        "listings": "1",
        "bidOnly": "0",
        "source": '"own"',
        "items": f'"{items}"',
        **changes,
    }
    return "{\n" + "".join(f'["{k}"] = {v},\n' for k, v in fields.items()) + "},\n"


# --- reading -------------------------------------------------------------------------------------
def test_reads_the_addons_golden_book() -> None:
    first, second = book.read(FIXTURE.read_bytes())
    assert (first.t, first.realm, first.faction, first.source) == (
        1790725000,
        "Classic Beta PvE",
        "Horde",
        "heard",
    )
    assert first.items == {2770: (Level(167, 60, 3),), 7067: (Level(12000, 2, 2),)}
    assert (second.t, second.listings, second.bid_only, second.source) == (1790726574, 25, 1, "own")
    assert second.items[2770] == (Level(64, 3, 2), Level(167, 5020, 2))
    assert second.items[7067] == (Level(700, 1, 1), Level(10199, 1, 1), Level(12000, 2, 1))
    assert len(second.items[14048]) == 13
    assert second.items[14048][-1] == Level(113, 6, 2, tail=True)
    assert sorted(second.items) == [2589, 2770, 5631, 7067, 14048]


def test_a_file_without_a_book_has_no_scans() -> None:
    assert book.read(b'AltArmyTBC_Data = {\n["Characters"] = {\n},\n}\n') == []
    assert book.read(b"") == []


def test_scans_come_oldest_first() -> None:
    data = saved(scan(t="3000") + scan(t="1000") + scan(t="2000"))
    assert [s.t for s in book.read(data)] == [1000, 2000, 3000]


def test_an_incomplete_scan_is_left_out() -> None:
    assert book.read(saved(scan(complete="false") + scan(t="5"))) == book.read(saved(scan(t="5")))
    assert len(book.read(saved(scan(complete="nil")))) == 0


def test_a_neutral_houses_scan_is_left_out() -> None:
    # The addon files a neutral (Blackwater) auction house's scans under "Neutral"; the site never offers that
    # house (versions.NEUTRAL), so its scans are skipped like incomplete ones, not refused with the upload.
    assert book.read(saved(scan(faction='"Neutral"') + scan(t="5"))) == book.read(saved(scan(t="5")))


def test_an_empty_scan_is_read() -> None:
    (got,) = book.read(saved(scan(items="")))
    assert got.items == {}


@pytest.mark.parametrize(
    "bad",
    [
        scan(items="2770"),
        scan(items="2770:"),
        scan(items="abc:64*1*1"),
        scan(items="2770:64*1"),
        scan(items="2770:64*1*1*1"),
        scan(items="2770:0*1*1"),
        scan(items="2770:64*0*1"),
        scan(items="2770:64*1*0"),
        scan(items="2770:-64*1*1"),
        scan(items="0:64*1*1"),
        scan(items="2770:64*1*1;2770:65*1*1"),  # an item twice
        scan(items="2770:167*1*1,64*1*1"),  # not cheapest first
        scan(items="2770:64*1*1,64*2*1"),  # a price twice
        scan(items="2770:~64*1*1,65*1*1"),  # a tail before a level
        scan(items="2770:64*1*1,~60*1*1"),  # a tail cheaper than the levels
        scan(items="2770:1e3*1*1"),
        scan(items="2770:64*1*1;"),
        scan(items="2770:" + ",".join(f"{p}*1*1" for p in range(1, 40))),  # too many levels
        scan(items="2770:99999999999999*1*1"),
        scan(items="1"),
        scan(items="{}"),
        scan(t='"soon"'),
        scan(t="-5"),
        scan(t="1.5"),
        scan(realm='""'),
        scan(realm="5"),
        scan(realm='"' + "x" * 65 + '"'),
        scan(faction='"Pirates"'),
        scan(faction="nil"),
        scan(listings='"many"'),
        scan(bidOnly="-1"),
        scan(source="5"),
        "5,\n",
    ],
)
def test_a_malformed_scan_is_a_value_error(bad: str) -> None:
    with pytest.raises(ValueError):
        book.read(saved(bad))


def test_a_malformed_book_is_a_value_error() -> None:
    for data in (
        b"AltArmyTBC_AuctionBook = 5\n",
        b'AltArmyTBC_AuctionBook = {\n["scans"] = 5,\n}\n',
        b'AltArmyTBC_AuctionBook = {\n["scans"] = {\n',
        b"AltArmyTBC_AuctionBook = {" * 200,
    ):
        with pytest.raises(ValueError):
            book.read(data)


def test_too_many_scans_is_a_value_error() -> None:
    with pytest.raises(ValueError):
        book.read(saved("".join(scan(t=str(i + 1)) for i in range(book.MAX_SCANS + 1))))


# --- text ----------------------------------------------------------------------------------------
def test_a_ladder_survives_its_text() -> None:
    levels = (Level(64, 3, 2, age=4), Level(167, 5020, 2), Level(200, 9, 3, tail=True, age=1))
    assert book.encode(levels) == "64*3*2*4,167*5020*2*0,~200*9*3*1"
    assert book.decode(book.encode(levels)) == levels
    assert book.decode("") == ()
    assert book.encode(()) == ""


def test_bad_ladder_text_is_a_value_error() -> None:
    for text in ("64", "64*1*1*1*1", "a*1*1", "64*1*1,,", "64*1*1*-1"):
        with pytest.raises(ValueError):
            book.decode(text)


# --- buying --------------------------------------------------------------------------------------
def test_buying_walks_the_ladder() -> None:
    earth = ladder((700, 1), (10199, 1), (12000, 2))
    assert book.cost(earth, 1) == (700, 0)
    assert book.cost(earth, 2) == (700 + 10199, 0)
    assert book.cost(earth, 4) == (700 + 10199 + 24000, 0)


def test_a_few_cheap_units_barely_move_a_batch() -> None:
    ore = ladder((64, 3), (167, 5020))
    got = book.cost(ore, 200)
    assert got == (3 * 64 + 197 * 167, 0)
    assert got[0] / 200 > 165


def test_buying_more_than_is_listed_is_short() -> None:
    assert book.cost(ladder((700, 1), (12000, 2)), 5) == (700 + 4 * 12000, 2)


def test_nothing_listed_cannot_be_bought() -> None:
    assert book.cost((), 1) is None
    assert book.cost(ladder((700, 1)), 0) == (0, 0)


def test_units_listed() -> None:
    assert book.quantity(ladder((64, 3), (167, 5020))) == 5023
    assert book.quantity(()) == 0


# --- the market price ----------------------------------------------------------------------------
def test_the_market_price_looks_past_a_lone_cheap_listing() -> None:
    assert book.market_price(ladder((64, 3), (167, 5020))) == 167
    assert book.market_price(ladder((700, 1), (10199, 1), (12000, 2))) == 700  # 15% of 4 units is the first
    assert book.market_price(ladder((700, 1), (10199, 3), (12000, 20))) == 10199
    assert book.market_price(ladder((500, 10))) == 500
    assert book.market_price(()) is None


# --- ages ----------------------------------------------------------------------------------------
def test_a_level_ages_with_every_scan_it_survives() -> None:
    before = (Level(64, 3, 2, age=2), Level(167, 5020, 2, age=0))
    after = ladder((60, 1), (64, 1), (167, 5000))
    assert [(lv.price, lv.age) for lv in book.aged(before, after)] == [(60, 0), (64, 3), (167, 1)]
    assert [lv.age for lv in book.aged((), after)] == [0, 0, 0]


# --- inferred sales ------------------------------------------------------------------------------
def test_units_gone_from_the_cheap_end_were_sold() -> None:
    before = ladder((64, 3), (167, 5020))
    after = ladder((167, 5000))
    assert book.sold_between(before, after) == book.Sold(units=23, copper=3 * 64 + 20 * 167, cancelled=0)


def test_units_gone_from_behind_the_cheapest_were_cancelled() -> None:
    before = ladder((100, 10), (150, 10), (200, 10))
    after = ladder((100, 10), (200, 4))
    assert book.sold_between(before, after) == book.Sold(units=0, copper=0, cancelled=16)


def test_an_undercut_market_sold_nothing() -> None:
    before = ladder((100, 10))
    after = ladder((90, 5), (100, 10))
    assert book.sold_between(before, after) == book.Sold(0, 0, 0)


def test_a_fresh_undercut_does_not_turn_sales_into_cancellations() -> None:
    # 6 at 100 went (and none at 120): sold, though a cheaper listing (at 90) came up in between
    before = ladder((100, 10), (120, 5))
    after = ladder((90, 3), (100, 4), (120, 5))
    assert book.sold_between(before, after) == book.Sold(units=6, copper=600, cancelled=0)
    # what went from behind a level still listed was still cancelled
    after = ladder((90, 3), (100, 10), (120, 1))
    assert book.sold_between(before, after) == book.Sold(units=0, copper=0, cancelled=4)


def test_an_emptied_market_says_nothing_of_sales() -> None:
    assert book.sold_between(ladder((100, 10)), ()) == book.Sold(units=0, copper=0, cancelled=10)


def test_the_tail_is_not_counted() -> None:
    before = (Level(100, 10, 1), Level(300, 50, 5, tail=True))
    after = (Level(100, 4, 1), Level(310, 20, 3, tail=True))
    assert book.sold_between(before, after) == book.Sold(units=6, copper=600, cancelled=0)
