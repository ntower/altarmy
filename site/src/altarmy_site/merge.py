"""The merge: pooled price statistics per auction house, run hourly (`altarmy-site merge`, a Cloud Run
job).

For every item with `price_daily` rows in the last LOOKBACK_DAYS days:

- `price_daily.median`: the median of that day's Auctionator low and high plus the price in every accepted
  snapshot scanned that (UTC) day, each clamped to the day's low..high.
- `price_current.median_7d`: the median of the item's daily medians on its latest SAMPLE_DAYS days with
  data (one sample per day, so a busy day doesn't outweigh the rest); `avail_7d` the median of those days'
  availability; `scans_7d` how many days that was. Latest days with data rather than the last 7 calendar
  days: one player scans every few days, and a lone overpriced listing must not be the only sample.

A snapshot's price is its market price where it has one (an Alt Army scan: the price a little way into
the listed units), else its minimum buyout.

- `price_current.sale_rate`: the units a day that sold over the last SALES_DAYS days
  (`price_sales_daily`, which Alt Army's scans fill); `sale_price`: by units, the middle price they sold
  for, once MIN_SALES sold.

From the hourly snapshots (`feed.py`), over the last FEED_DAYS days:

- `price_daily.open`/`close`: the market price in the day's first and last hour (`price_hourly`), whose
  market prices are also the day's samples where it has no observations (the snapshots write none).
- `ttl_hours`: the hours by which half the auctions sell (`snapshots.km_median` over `auction_ends_daily`
  and the auctions still live in `auction_state`); `sell_through` the share of auctions that sold rather
  than ran out; `stacks` the same per stack size.
- `resolved_2d`/`resolved_days`: the auctions that ended (sold, won or ran out; for a day of addon scans
  alone, the units bought and cancelled) over today and yesterday, and the days with RESOLVED_MIN of
  them. They open the item's auction figures (`gate`): `normal` with NORMAL_DAYS such days, else
  `launch` in a house's first LAUNCH_DAYS days with RESOLVED_MIN over the two days.

Items without a day in the lookback get NULLs. A merge that changed anything bumps
`auction_houses.price_version`, which moves `store.market_stamp`, so every instance's cached market is
rebuilt.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Sequence
from datetime import date, datetime, time, timedelta

from sqlalchemy import Connection, bindparam, func, select, update

from . import db, prices, schema, snapshots

SAMPLE_DAYS = 7  # the latest days with data that make an item's median
LOOKBACK_DAYS = 30  # how far back those days may be
SALES_DAYS = prices.SALES_DAYS  # the calendar days whose inferred sales count
MIN_SALES = prices.MIN_SALES  # fewer units sold than this say nothing of a price
# Past this many rows price_observations should be partitioned by month: the merge then logs a warning
# tagged PARTITION_ALERT, which a log-based alert policy posts to Discord (deploy/setup.sh `alerts`).
PARTITION_AT = 5_000_000
PARTITION_ALERT = "partition-observations"

FEED_DAYS = 7  # the days of ended auctions that time to sell and sell-through are from
RESOLVED_MIN = 20  # ended auctions in a day (or two, at launch) that open an item's auction figures
NORMAL_DAYS = 2  # ... on this many days of the last week
LAUNCH_DAYS = prices.LAUNCH_DAYS  # a house's first days, when two days with RESOLVED_MIN are enough

Stats = tuple[int | None, int | None, int | None]  # median_7d, avail_7d, scans_7d
# ttl_hours, sell_through, stacks, resolved_2d, resolved_days, gate
Feed = tuple[float | None, float | None, str | None, int | None, int | None, str | None]
NO_FEED: Feed = (None, None, None, None, None, None)
Sales = tuple[int | None, float | None, int | None]  # sale_price, sale_rate, sold_pairs_7d


def median(values: Sequence[int]) -> int:
    """The median, rounded down to whole copper."""
    s = sorted(values)
    mid = len(s) // 2
    return s[mid] if len(s) % 2 else (s[mid - 1] + s[mid]) // 2


def merge(conn: Connection, game_version: str | None = None, *, today: date | None = None) -> dict[int, bool]:
    """Merge every auction house (of `game_version`, else of every version). Returns {id: changed}."""
    t = schema.auction_houses
    query = select(t.c.id).order_by(t.c.id)
    if game_version is not None:
        query = query.where(t.c.game_version == game_version)
    day = today or db.utcnow().date()
    ids: list[int] = list(conn.execute(query).scalars())
    return {ah: merge_auction_house(conn, ah, day) for ah in ids}


def merge_auction_house(conn: Connection, auction_house_id: int, today: date) -> bool:
    """Recompute the auction house's daily medians and 7-day columns; True if anything changed."""
    start = today - timedelta(days=LOOKBACK_DAYS - 1)
    pd, pc = schema.price_daily, schema.price_current
    days = conn.execute(
        select(pd.c.item_id, pd.c.day, pd.c.low, pd.c.high, pd.c.available, pd.c.median)
        .add_columns(pd.c.open, pd.c.close)
        .where(pd.c.auction_house_id == auction_house_id, pd.c.day >= start, pd.c.day <= today)
    ).all()
    samples = _scan_samples(conn, auction_house_id, start, today)
    hours = _hours(conn, auction_house_id, today)
    for key, day_hours in hours.items():
        if key not in samples:
            samples[key] = [h.market for h in day_hours.values()]

    daily_updates = []
    # (day, daily median, available)
    per_item: dict[int, list[tuple[date, int, int | None]]] = defaultdict(list)
    for r in days:
        clamped = [min(max(p, r.low), r.high) for p in samples.get((r.item_id, r.day), ())]
        m = median([r.low, r.high, *clamped])
        per_item[r.item_id].append((r.day, m, r.available))
        slots = hours.get((r.item_id, r.day))
        opened, closed = (r.open, r.close)
        if slots:
            opened, closed = slots[min(slots)].market, slots[max(slots)].market
        if (m, opened, closed) != (r.median, r.open, r.close):
            daily_updates.append({"i": r.item_id, "d": r.day, "m": m, "o": opened, "c": closed})
    if daily_updates:
        conn.execute(
            update(pd)
            .where(
                pd.c.auction_house_id == auction_house_id,
                pd.c.item_id == bindparam("i"),
                pd.c.day == bindparam("d"),
            )
            .values(median=bindparam("m"), open=bindparam("o"), close=bindparam("c")),
            daily_updates,
        )

    sold = _sales(conn, auction_house_id, today)
    fed = _feed(conn, auction_house_id, today)
    current_updates = []
    sales_updates = []
    feed_updates = []
    for r in conn.execute(
        select(pc.c.item_id, pc.c.median_7d, pc.c.avail_7d, pc.c.scans_7d)
        .add_columns(pc.c.sale_price, pc.c.sale_rate, pc.c.sold_pairs_7d)
        .add_columns(pc.c.ttl_hours, pc.c.sell_through, pc.c.stacks, pc.c.resolved_2d, pc.c.resolved_days)
        .add_columns(pc.c.gate)
        .where(pc.c.auction_house_id == auction_house_id)
    ):
        stats = _stats(per_item.get(r.item_id, []))
        if stats != (r.median_7d, r.avail_7d, r.scans_7d):
            current_updates.append({"i": r.item_id, "m": stats[0], "a": stats[1], "s": stats[2]})
        sales = sold.get(r.item_id, (None, None, None))
        if sales != (r.sale_price, r.sale_rate, r.sold_pairs_7d):
            sales_updates.append({"i": r.item_id, "p": sales[0], "r": sales[1], "n": sales[2]})
        stated = fed.get(r.item_id, NO_FEED)
        if stated != (r.ttl_hours, r.sell_through, r.stacks, r.resolved_2d, r.resolved_days, r.gate):
            feed_updates.append(
                dict(zip(("i", "t", "s", "k", "r2", "rd", "g"), (r.item_id, *stated), strict=True))
            )
    if current_updates:
        conn.execute(
            update(pc)
            .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
            .values(median_7d=bindparam("m"), avail_7d=bindparam("a"), scans_7d=bindparam("s")),
            current_updates,
        )
    if sales_updates:
        conn.execute(
            update(pc)
            .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
            .values(sale_price=bindparam("p"), sale_rate=bindparam("r"), sold_pairs_7d=bindparam("n")),
            sales_updates,
        )

    if feed_updates:
        conn.execute(
            update(pc)
            .where(pc.c.auction_house_id == auction_house_id, pc.c.item_id == bindparam("i"))
            .values(
                ttl_hours=bindparam("t"),
                sell_through=bindparam("s"),
                stacks=bindparam("k"),
                resolved_2d=bindparam("r2"),
                resolved_days=bindparam("rd"),
                gate=bindparam("g"),
            ),
            feed_updates,
        )

    changed = bool(daily_updates or current_updates or sales_updates or feed_updates)
    if changed:
        prices.bump_price_version(conn, auction_house_id)
    return changed


def _stats(days: list[tuple[date, int, int | None]]) -> Stats:
    latest = sorted(days, reverse=True)[:SAMPLE_DAYS]
    if not latest:
        return None, None, None
    available = [a for _, _, a in latest if a is not None]
    return median([m for _, m, _ in latest]), median(available) if available else None, len(latest)


def _sales(conn: Connection, auction_house_id: int, today: date) -> dict[int, Sales]:
    """{item_id: (sale price, units sold a day, pairs of scans they sold in)} over the SALES_DAYS days up
    to `today`, for items that sold at all. The sale price is, by units, the middle of the days' average
    prices; None under MIN_SALES units."""
    t = schema.price_sales_daily
    rows = conn.execute(
        select(t.c.item_id, t.c.units, t.c.copper, t.c.pairs)
        .where(
            t.c.auction_house_id == auction_house_id,
            t.c.day > today - timedelta(days=SALES_DAYS),
            t.c.day <= today,
            t.c.units > 0,
        )
        .order_by(t.c.item_id, t.c.day)
    )
    days: dict[int, list[tuple[int, int]]] = defaultdict(list)  # (average price, units)
    pairs: dict[int, int] = defaultdict(int)
    for r in rows:
        days[r.item_id].append((r.copper // r.units, r.units))
        pairs[r.item_id] += r.pairs
    out: dict[int, Sales] = {}
    for item_id, sold in days.items():
        units = sum(u for _, u in sold)
        out[item_id] = (_middle(sold) if units >= MIN_SALES else None, units / SALES_DAYS, pairs[item_id])
    return out


def _hours(
    conn: Connection, auction_house_id: int, today: date
) -> dict[tuple[int, date], dict[int, prices.Hour]]:
    """{(item_id, day): {hour: Hour}} of the house's `price_hourly` rows."""
    t = schema.price_hourly
    rows = conn.execute(
        select(t.c.item_id, t.c.day, t.c.hours).where(
            t.c.auction_house_id == auction_house_id,
            t.c.day > today - timedelta(days=prices.HOURLY_DAYS),
            t.c.day <= today,
        )
    )
    out = {}
    for r in rows:
        unpacked = prices.unpack_hours(r.hours)
        if unpacked:
            out[(r.item_id, r.day)] = unpacked
    return out


def _feed(conn: Connection, auction_house_id: int, today: date) -> dict[int, Feed]:
    """{item_id: Feed} from the ended auctions and the day's sales of the last FEED_DAYS days."""
    since = today - timedelta(days=FEED_DAYS)
    ends = schema.auction_ends_daily
    events: dict[int, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    censored: dict[int, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    stacks: dict[int, dict[int, list[int]]] = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    for r in conn.execute(
        select(ends.c.item_id, ends.c.stack, ends.c.age_h, ends.c.outcome, ends.c.auctions).where(
            ends.c.auction_house_id == auction_house_id, ends.c.day > since, ends.c.day <= today
        )
    ):
        if r.outcome in snapshots.SOLD:
            events[r.item_id][r.age_h] += r.auctions
            stacks[r.item_id][r.stack][0] += r.auctions
        elif r.outcome != "ambiguous":
            censored[r.item_id][r.age_h] += r.auctions
            if r.outcome == "expired":
                stacks[r.item_id][r.stack][1] += r.auctions
    state = schema.auction_state
    body = conn.execute(
        select(state.c.body).where(state.c.auction_house_id == auction_house_id)
    ).scalar_one_or_none()
    if body is not None:
        for (item_id, age), n in snapshots.live_ages(snapshots.decode_state(body)).items():
            censored[item_id][age] += n

    sales = schema.price_sales_daily
    resolved: dict[int, dict[date, int]] = defaultdict(dict)
    through: dict[int, list[int]] = defaultdict(lambda: [0, 0])
    for r in conn.execute(
        select(sales).where(
            sales.c.auction_house_id == auction_house_id, sales.c.day > since, sales.c.day <= today
        )
    ):
        ended = r.auctions_sold + r.bid_sold + r.expired
        counted = ended + r.posted + r.relisted + r.ambiguous
        resolved[r.item_id][r.day] = ended if counted else r.units + r.cancelled
        through[r.item_id][0] += r.auctions_sold + r.bid_sold
        through[r.item_id][1] += r.expired

    launch = prices.in_launch(conn, auction_house_id, today)
    out: dict[int, Feed] = {}
    for item_id in set(events) | set(censored) | set(resolved):
        by_day = resolved.get(item_id, {})
        recent = by_day.get(today, 0) + by_day.get(today - timedelta(days=1), 0)
        days = sum(1 for n in by_day.values() if n >= RESOLVED_MIN)
        gate = "normal" if days >= NORMAL_DAYS else "launch" if launch and recent >= RESOLVED_MIN else None
        sold, expired = through.get(item_id, [0, 0])
        per_stack = stacks.get(item_id, {})
        out[item_id] = (
            snapshots.km_median(events.get(item_id, {}), censored.get(item_id, {})),
            snapshots.sell_through(sold, expired),
            ",".join(f"{k}:{v[0]}/{v[1]}" for k, v in sorted(per_stack.items())) or None,
            recent if by_day else None,
            days if by_day else None,
            gate,
        )
    return out


def _middle(priced: list[tuple[int, int]]) -> int:
    """The price of the middle unit of (price, units) pairs."""
    half = sum(u for _, u in priced) / 2
    seen = 0
    for price, units in sorted(priced):
        seen += units
        if seen >= half:
            return price
    raise ValueError("no units")


def _scan_samples(
    conn: Connection, auction_house_id: int, start: date, today: date
) -> dict[tuple[int, date], list[int]]:
    """{(item_id, day): prices} from the accepted snapshots scanned in the window."""
    snap, obs = schema.price_snapshots, schema.price_observations
    since = datetime.combine(start, time(), db.utcnow().tzinfo)
    until = datetime.combine(today + timedelta(days=1), time(), db.utcnow().tzinfo)
    rows = conn.execute(
        select(
            obs.c.item_id,
            snap.c.scanned_at,
            func.coalesce(obs.c.market_price, obs.c.min_buyout).label("min_buyout"),
        )
        .join(snap, snap.c.id == obs.c.snapshot_id)
        .where(
            snap.c.auction_house_id == auction_house_id,
            snap.c.status == "accepted",
            snap.c.scanned_at >= since,
            snap.c.scanned_at < until,
        )
    )
    out: dict[tuple[int, date], list[int]] = defaultdict(list)
    for r in rows:
        out[(r.item_id, db.utc(r.scanned_at).date())].append(int(r.min_buyout))
    return out


def observation_count(conn: Connection) -> int:
    """Rows in `price_observations`: partition it by month once this passes PARTITION_AT."""
    return int(conn.execute(select(func.count()).select_from(schema.price_observations)).scalar_one())
