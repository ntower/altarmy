from __future__ import annotations

import gzip
import json

import pytest

from altarmy_site import book, snapshots
from altarmy_site.snapshots import HouseState, Live, Tally

from .snapshot_fixtures import FOREVER, HOUR, T0, auction, body, outcomes, run, snap


# --- reading ---------------------------------------------------------------------------------------
def test_reads_a_classic_snapshot() -> None:
    s = snap(
        T0,
        auction(1, 2589, unit=50, qty=20, bid=800, left="VERY_LONG"),
        auction(2, 2589, buyout=101, qty=2),  # 50.5 a unit: rounded up
        auction(3, 2589, bid=10, left="SHORT"),  # no buyout
        auction(4, 2589, buyout=0, bid=10),  # Blizzard's "no buyout"
    )
    assert s.t == T0 and (s.realm, s.faction) == ("Normal", "Horde")
    assert [(a.id, a.item_id, a.quantity, a.unit_price, a.bid, a.time_left) for a in s.auctions] == [
        (1, 2589, 20, 50, 800, "VERY_LONG"),
        (2, 2589, 2, 51, None, "LONG"),
        (3, 2589, 1, None, 10, "SHORT"),
        (4, 2589, 1, None, 10, "LONG"),
    ]


def test_reads_a_commodity_unit_price() -> None:
    raw = {
        "auctions": [{"id": 9, "item": {"id": 2589}, "quantity": 5, "unit_price": 40, "time_left": "LONG"}]
    }
    s = snapshots.parse_blizzard(json.dumps(raw).encode(), t=T0, realm="R", faction="Alliance")
    assert s.auctions[0].unit_price == 40


def test_an_empty_house_has_no_auctions() -> None:
    assert snapshots.parse_blizzard(b"{}", t=T0, realm="R", faction="Horde").auctions == ()


@pytest.mark.parametrize(
    "raw",
    [
        b"not json",
        b"\xff\xfe\x00",
        b"[]",
        b'{"auctions": {}}',
        b'{"auctions": [1]}',
        b'{"auctions": [{"id": 1, "quantity": 1, "time_left": "LONG"}]}',
        b'{"auctions": [{"id": 1, "item": {"id": 2}, "quantity": 0, "time_left": "LONG"}]}',
        b'{"auctions": [{"id": 1, "item": {"id": 2}, "quantity": 1, "time_left": "FOREVER"}]}',
        b'{"auctions": [{"id": 1, "item": {"id": 2}, "quantity": 1, "buyout": -5, "time_left": "LONG"}]}',
        b'{"auctions": [{"id": 1, "item": {"id": 2}, "quantity": 1, "buyout": 1.5, "time_left": "LONG"}]}',
        b'{"auctions": [{"id": true, "item": {"id": 2}, "quantity": 1, "time_left": "LONG"}]}',
        body(auction(1, 2, unit=5), auction(1, 2, unit=6)),
        b"[" * 100_000,
    ],
    ids=lambda raw: raw[:24].decode("latin-1"),
)
def test_a_malformed_snapshot_is_a_value_error(raw: bytes) -> None:
    with pytest.raises(ValueError):
        snapshots.parse_blizzard(raw, t=T0, realm="R", faction="Horde")


# --- ladders -----------------------------------------------------------------------------------------
def test_ladders_pool_auctions_like_the_addon() -> None:
    s = snap(
        T0,
        auction(1, 10, unit=5, qty=20),
        auction(2, 10, unit=5, qty=10),
        auction(3, 10, unit=7, qty=1),
        auction(4, 10, bid=3),  # no buyout: not on the ladder
        auction(5, 11, unit=99),
    )
    assert snapshots.ladders(s) == {
        10: (book.Level(5, 30, 2), book.Level(7, 1, 1)),
        11: (book.Level(99, 1, 1),),
    }


def test_ladders_pool_the_rest_past_twelve_levels_in_a_tail() -> None:
    s = snap(T0, *(auction(i, 10, unit=100 + i, qty=2) for i in range(1, 16)))
    ladder = snapshots.ladders(s)[10]
    assert len(ladder) == 13
    assert ladder[11] == book.Level(112, 2, 1)
    assert ladder[12] == book.Level(113, 6, 3, tail=True)
    assert book.decode(book.encode(ladder)) == ladder


# --- what ended ---------------------------------------------------------------------------------------
def test_the_first_snapshot_says_nothing_ended() -> None:
    (d,) = run(snap(T0, auction(1, 10, unit=100)))
    assert not d.follows and not d.stale and d.ended == () and d.posted == ()
    assert d.state.live[1].first_seen is None  # up since before the feed began


def test_an_auction_gone_under_the_cheapest_left_was_sold() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(2, 10, unit=120)),
    )
    assert d.follows and outcomes(d) == {1: "sold"}


def test_an_auction_gone_from_behind_a_cheaper_one_was_pulled() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(1, 10, unit=100)),
    )
    assert outcomes(d) == {2: "pulled"}


def test_a_newer_cheaper_auction_tells_nothing_about_the_ones_gone() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100), auction(2, 10, unit=120)),
        # 1 went, and an undercut at 90 was posted after it: the floor is still 120, so 1 was sold
        snap(T0 + HOUR, auction(2, 10, unit=120), auction(3, 10, unit=90)),
    )
    assert outcomes(d) == {1: "sold"}
    assert [p.auction.id for p in d.posted] == [3]


def test_an_auction_without_a_buyout_gone_early_was_pulled() -> None:
    _, d = run(
        snap(T0, auction(1, 10, bid=50), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(2, 10, unit=120)),
    )
    assert outcomes(d) == {1: "pulled"}


def test_a_short_auction_gone_ran_out() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100, left="SHORT"), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(2, 10, unit=120)),
    )
    assert outcomes(d) == {1: "expired"}


def test_an_auction_run_out_with_a_raised_bid_was_won() -> None:
    _, _, d = run(
        snap(T0, auction(1, 10, unit=100, bid=50, left="MEDIUM"), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(1, 10, unit=100, bid=70, left="SHORT"), auction(2, 10, unit=120)),
        snap(T0 + 2 * HOUR, auction(2, 10, unit=120)),
    )
    assert outcomes(d) == {1: "bid_won"}


def test_an_auction_that_may_have_run_out_is_ambiguous() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100, left="MEDIUM"), auction(2, 10, unit=120)),
        snap(T0 + HOUR, auction(2, 10, unit=120)),
    )
    assert outcomes(d) == {1: "ambiguous"}


def test_an_item_gone_altogether_is_ambiguous() -> None:
    _, d = run(snap(T0, auction(1, 10, unit=100)), snap(T0 + HOUR))
    assert outcomes(d) == {1: "ambiguous"}


def test_an_auction_taken_down_and_posted_again_alike_is_relisted() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100, qty=5)),
        snap(T0 + HOUR, auction(7, 10, unit=100, qty=5), auction(8, 10, unit=100, qty=5)),
    )
    assert outcomes(d) == {1: "relisted"}
    assert [p.auction.id for p in d.posted] == [8]  # one of the two is new stock


def test_every_bucket_seen_narrows_when_an_auction_ends() -> None:
    first = snap(T0, auction(1, 10, unit=100, left="LONG"), auction(2, 10, unit=120, left="VERY_LONG"))
    then = snap(
        T0 + HOUR, auction(1, 10, unit=100, left="MEDIUM"), auction(2, 10, unit=120, left="VERY_LONG")
    )
    gone = snap(T0 + 2 * HOUR, auction(2, 10, unit=120, left="VERY_LONG"))
    # LONG at T0 and MEDIUM an hour later: it ends after T0 + 2 h, so gone by then it was bought
    assert outcomes(run(first, then, gone)[2]) == {1: "sold"}
    # seen MEDIUM alone, it could have run out
    assert outcomes(run(then, gone)[1]) == {1: "ambiguous"}


def test_a_long_gap_says_nothing_ended() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100), auction(2, 10, unit=120)),
        snap(T0 + FOREVER.snapshot_gap + 1, auction(2, 10, unit=120), auction(3, 10, unit=130)),
    )
    assert not d.follows and d.ended == () and d.posted == ()
    assert d.state.live[3].first_seen is None  # posted some time in the gap


def test_a_snapshot_no_newer_than_the_state_is_stale() -> None:
    first, d = run(snap(T0, auction(1, 10, unit=100)), snap(T0, auction(2, 10, unit=100)))
    assert d.stale and d.state is first.state


def test_hours_up_count_from_the_first_snapshot_an_auction_was_in() -> None:
    _, _, _, d = run(
        snap(T0, auction(2, 10, unit=120, left="VERY_LONG")),
        snap(
            T0 + HOUR, auction(1, 10, unit=100, left="VERY_LONG"), auction(2, 10, unit=120, left="VERY_LONG")
        ),
        snap(
            T0 + 2 * HOUR,
            auction(1, 10, unit=100, left="VERY_LONG"),
            auction(2, 10, unit=120, left="VERY_LONG"),
        ),
        snap(T0 + 3 * HOUR, auction(2, 10, unit=120, left="VERY_LONG")),
    )
    (e,) = d.ended
    assert (e.outcome, e.age_h) == ("sold", 2)
    assert d.state.live[2].first_seen is None  # in the feed's first snapshot


def test_a_snapshot_with_half_the_auctions_is_held_back() -> None:
    (d,) = run(snap(T0, *(auction(i, 10, unit=100 + i) for i in range(1, 101))))
    assert snapshots.looks_partial(
        d.state, snap(T0 + HOUR, *(auction(i, 10, unit=100 + i) for i in range(1, 41)))
    )
    assert not snapshots.looks_partial(
        d.state, snap(T0 + HOUR, *(auction(i, 10, unit=100 + i) for i in range(1, 61)))
    )
    assert not snapshots.looks_partial(None, snap(T0))
    small = HouseState(T0, {k: v for k, v in d.state.live.items() if k <= 10})
    assert not snapshots.looks_partial(small, snap(T0 + HOUR))


# --- counting ----------------------------------------------------------------------------------------
def test_flows_count_auctions_units_and_what_sold_went_for() -> None:
    _, _, d = run(
        snap(
            T0,
            auction(1, 10, unit=100, qty=5),
            auction(2, 10, unit=90, qty=1, bid=40, left="MEDIUM"),
            auction(3, 10, unit=200),
        ),
        snap(
            T0 + HOUR,
            auction(1, 10, unit=100, qty=5),
            auction(2, 10, unit=90, bid=60, left="SHORT"),
            auction(3, 10, unit=200),
        ),
        snap(T0 + 2 * HOUR, auction(3, 10, unit=200), auction(4, 10, unit=150, qty=5)),
    )
    assert snapshots.flows(d) == {
        (10, 5, "sold"): Tally(1, 5, 500),
        (10, 1, "bid_won"): Tally(1, 1, 60),
        (10, 5, "posted"): Tally(1, 5, 0),
    }
    assert snapshots.end_counts(d) == {}  # both were up before the feed began: their ages are unknown


def test_end_counts_are_by_hours_up() -> None:
    _, _, d = run(
        snap(T0, auction(9, 10, unit=300, left="VERY_LONG")),
        snap(T0 + HOUR, auction(1, 10, unit=100, qty=5), auction(9, 10, unit=300, left="VERY_LONG")),
        snap(T0 + 2 * HOUR, auction(9, 10, unit=300, left="VERY_LONG")),
    )
    assert snapshots.end_counts(d) == {(10, 5, 1, "sold"): Tally(1, 5, 0)}


def test_sell_through_is_sold_against_run_out() -> None:
    assert snapshots.sell_through(3, 1) == 0.75
    assert snapshots.sell_through(0, 0) is None


def test_time_to_sell_is_the_kaplan_meier_median() -> None:
    # 5 auctions: 2 sell in their 1st hour, 1 more in the 2nd; one ran out in the 1st, one is still up at 3 h
    # S(1) = 1 - 2/5 = 0.6; S(2) = 0.6 * (1 - 1/2) = 0.3: half have sold by hour 2
    assert snapshots.km_median({1: 2, 2: 1}, {1: 1, 3: 1}) == 2.0
    assert snapshots.km_median({}, {1: 4}) is None
    assert snapshots.km_median({4: 1}, {1: 3}) == 4.0  # censoring early lifts the share of the rest


def test_live_ages_censor_what_is_still_up() -> None:
    state = HouseState(
        T0 + 3 * HOUR,
        {
            1: Live(snapshots.Auction(1, 10, 1, 100, None, "LONG"), T0, T0, T0, None),
            2: Live(snapshots.Auction(2, 10, 1, 100, None, "LONG"), None, T0, T0, None),
        },
    )
    assert snapshots.live_ages(state) == {(10, 3): 1}


# --- the stored state -------------------------------------------------------------------------------
def test_the_state_round_trips() -> None:
    _, d = run(
        snap(T0, auction(1, 10, unit=100, bid=5, left="MEDIUM"), auction(2, 11, bid=7)),
        snap(
            T0 + HOUR,
            auction(1, 10, unit=100, bid=9, left="SHORT"),
            auction(2, 11, bid=7),
            auction(3, 12, unit=1),
        ),
    )
    assert snapshots.decode_state(snapshots.encode_state(d.state)) == d.state


@pytest.mark.parametrize(
    "blob",
    [
        b"",
        b"nonsense",
        gzip.compress(b"x"),
        gzip.compress(b"1\n1,2,3"),
        gzip.compress(b"1\n1,2,3,,,NEVER,,1,2,"),
    ],
)
def test_an_unreadable_state_is_a_value_error(blob: bytes) -> None:
    with pytest.raises(ValueError):
        snapshots.decode_state(blob)
