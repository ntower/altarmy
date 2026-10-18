from altarmy_site import book, engine, prices, vendorruns, versions
from altarmy_site.vendorruns import Offer

FOREVER = versions.get("forever")
CHEAP, FLASK, PATTERN = 1, 2, 3


def market(ah_open: frozenset[int] | None = None) -> engine.Market:
    items = {
        CHEAP: engine.Item(CHEAP, "Cheap Ring", sell_price=500),
        FLASK: engine.Item(FLASK, "Flask", sell_price=10, stack_size=20),
        PATTERN: engine.Item(PATTERN, "Pattern", sell_price=100),
    }
    return engine.Market(items, [], {}, sell_prices={FLASK: 400, PATTERN: 9000}, ah_open=ah_open)


def listing(*levels: book.Level, rate: float = 0.0, stacks: str | None = None) -> prices.Listing:
    units = sum(lv.quantity for lv in levels)
    return prices.Listing(levels[0].price, units, levels, rate, prices.BLIZZARD, True, stacks=stacks)


def test_listings_under_what_a_vendor_pays_are_bought_and_vendored() -> None:
    got = vendorruns.under_vendor(
        market(),
        {CHEAP: listing(book.Level(300, 2, 1, age=0), book.Level(450, 1, 1, age=5), book.Level(600, 4, 1))},
    )
    (u,) = got
    assert (u.units, u.cheapest, u.vendor, u.profit) == (3, 300, 500, 2 * 200 + 50)
    assert u.fresh  # its cheapest level is new


def test_what_vendors_sell_for_less_than_the_auction_house_pays() -> None:
    offers = [
        Offer(FLASK, 10, "Grocer", "", 0, 0, "Orgrimmar", 1, 0.0, 0.0),
        Offer(PATTERN, 11, "Trader", "horde", 1, 3600, "Barrens", 2, 0.0, 0.0),
        Offer(PATTERN, 12, "Quartermaster", "alliance", 1, 3600, "Westfall", 3, 0.0, 0.0),
    ]
    buy = {FLASK: 300, PATTERN: 2000}
    listings = {FLASK: listing(book.Level(400, 9, 9), rate=6.0, stacks="5:6/0")}
    got = vendorruns.resells(market(), listings, offers, buy, "Horde", FOREVER)
    assert [(r.offer.name, r.units) for r in got] == [("Trader", 1), ("Grocer", 2)]  # a third of 6 a day
    trader, grocer = got
    assert trader.margin == engine.ah_net(9000) - 2000 - 100  # the 1s minimum deposit
    assert grocer.margin == engine.ah_net(400) - 300 - 20  # posted in fives: 1s over 5 units
    # posted one at a time, the minimum deposit eats the flask's margin
    singly = {FLASK: listing(book.Level(400, 9, 9), rate=6.0)}
    assert [r.offer.name for r in vendorruns.resells(market(), singly, offers, buy, "Horde", FOREVER)] == [
        "Trader"
    ]
    assert [z for z, _ in vendorruns.by_zone(got)] == ["Barrens", "Orgrimmar"]
    # an item whose AH sale doesn't count yet is left out
    assert (
        vendorruns.resells(market(frozenset({FLASK})), listings, offers, buy, "Horde", FOREVER)[0].offer.name
        == "Grocer"
    )


def test_the_generated_offers_read() -> None:
    offers = vendorruns.read_offers(FOREVER.vendor_offers_csv)
    assert len(offers) > 1000
    assert {o.side for o in offers} == {"", "alliance", "horde"}
