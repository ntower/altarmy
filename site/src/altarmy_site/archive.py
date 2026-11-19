"""The long-term archive of prices: every UTC day's snapshots (with their full scans), daily prices and
daily sales, written once the day has settled to gzipped JSON lines in a folder or a Cloud Storage bucket.
The database keeps only what the everyday work reads (`prices.prune` drops a day only once it is
archived); the archive keeps everything, for one-off analyses (DuckDB or BigQuery read the files as they
are).

Per day `D` (`YYYY/MM/YYYY-MM-DD`):

- `snapshots/D.jsonl.gz`: one line per snapshot scanned that day (any source, quarantined ones too):
  its house (`game_version`, `realm`, `faction`), `source`, `status`, `scanned_at`, `received_at`,
  `build`, `item_count`, `observations` (`[item, min_buyout, quantity, listings, market_price]`: the news
  it brought) and an Alt Army scan's full scan (`snapshot_bodies`): `book` (`listings`, `bid_only`,
  `source`, `items`: `[{item, levels: [[price, units, listings, tail]]}]`; None for a feed snapshot, whose
  auctions are in `auctions/`). Who uploaded it is never written.
- `price_daily/D.jsonl.gz`, `price_sales_daily/D.jsonl.gz`: the day's rows of those tables, with their
  house.
- `auctions/D.jsonl.gz`: one line per hourly feed snapshot of the day (`feed.py`) with a body: its `id`
  (the snapshot's, as in `snapshots/`), house, `status`, `scanned_at` and `auctions` (`[id, item,
  quantity, unit_price, bid, time_left]`).

A day is archived once SETTLED_DAYS have passed (an upload may carry a scan up to 30 days old, and the
merge rewrites the last 30 days' daily rows), oldest first, each day's files written before
`archive_progress` moves past it in the same transaction; writing a day again writes the same files. The
feed's auctions settle sooner and go on a track of their own (`run_auctions`, progress row `AUCTIONS`):
a snapshot is recorded at the hour it stands for, so its day is done once it is over, and a large house's
day of snapshots is about 30 MB, too much to keep in the database for SETTLED_DAYS. Archived after
FEED_SETTLED_DAYS, its bodies are pruned then.
"""

from __future__ import annotations

import gzip
import json
import shutil
import tempfile
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import IO, Any, Protocol

from sqlalchemy import Connection, func, select

from . import book, db, schema, snapshots

SETTLED_DAYS = 32  # a day this old changes no more (uploads.scan_time: at most 30 days back)
FEED_SETTLED_DAYS = 2  # a day of feed snapshots this old changes no more (a late hourly run included)
PROGRESS = "days"  # archive_progress's row for the days (`run`)
AUCTIONS = "auctions"  # its row for the feed's auctions (`run_auctions`), and their files' folder
TABLES = ("snapshots", "price_daily", "price_sales_daily")  # the files of a day


# --- full scans (snapshot_bodies) -------------------------------------------------------------------
def encode_book(scan: book.Scan) -> bytes:
    """An Alt Army scan as stored: `listings,bid_only,source`, then `item:ladder` per item, gzipped."""
    lines = [f"{scan.listings},{scan.bid_only},{scan.source}"]
    lines += [f"{item}:{book.encode(ladder)}" for item, ladder in sorted(scan.items.items())]
    return gzip.compress("\n".join(lines).encode(), mtime=0)


def decode_book(blob: bytes) -> dict[str, Any]:
    """The scan `encode_book` stored, as the archive writes it."""
    head, *rest = gzip.decompress(blob).decode().split("\n")
    listings, bid_only, source = head.split(",", 2)
    items = []
    for line in rest:
        item, ladder = line.split(":", 1)
        levels = [[lv.price, lv.quantity, lv.listings, lv.tail] for lv in book.decode(ladder)]
        items.append({"item": int(item), "levels": levels})
    return {"listings": int(listings), "bid_only": int(bid_only), "source": source, "items": items}


def encode_auctions(snap: snapshots.Snapshot) -> bytes:
    """A feed snapshot's auctions as stored: `id,item,quantity,unit_price,bid,time_left`, gzipped."""
    lines = [
        f"{a.id},{a.item_id},{a.quantity},{_opt(a.unit_price)},{_opt(a.bid)},{a.time_left}"
        for a in sorted(snap.auctions, key=lambda a: a.id)
    ]
    return gzip.compress("\n".join(lines).encode(), mtime=0)


def decode_auctions(blob: bytes) -> list[list[int | str | None]]:
    """The auctions `encode_auctions` stored, as the archive writes them."""
    text = gzip.decompress(blob).decode()
    out: list[list[int | str | None]] = []
    for line in text.split("\n") if text else ():
        id_, item, quantity, unit, bid, time_left = line.split(",")
        out.append([int(id_), int(item), int(quantity), _int(unit), _int(bid), time_left])
    return out


def _opt(value: int | None) -> str:
    return "" if value is None else str(value)


def _int(text: str) -> int | None:
    return int(text) if text else None


def save_body(conn: Connection, snapshot_id: int, format: str, body: bytes) -> None:
    """Keep a snapshot's full scan until the archive has it."""
    conn.execute(schema.snapshot_bodies.insert().values(snapshot_id=snapshot_id, format=format, body=body))


# --- where the files go -----------------------------------------------------------------------------
class Sink(Protocol):
    def put(self, name: str, path: Path) -> None:
        """Store the file at `path` as `name` (a relative path), replacing any there."""


@dataclass(frozen=True)
class Folder:
    root: Path

    def put(self, name: str, path: Path) -> None:
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


@dataclass(frozen=True)
class Bucket:
    """A Cloud Storage bucket (google-cloud-storage, which firebase-admin brings: the `ui` extra), with
    Application Default Credentials."""

    bucket: str
    prefix: str = ""

    def put(self, name: str, path: Path) -> None:
        from google.cloud import storage

        blob = storage.Client().bucket(self.bucket).blob(self.prefix + name)
        blob.upload_from_filename(str(path), content_type="application/gzip")


def sink_for(url: str) -> Sink:
    """`gs://bucket/prefix/` for a bucket, else a folder."""
    if url.startswith("gs://"):
        bucket, _, prefix = url.removeprefix("gs://").partition("/")
        if not bucket:
            raise ValueError(f"no bucket in {url!r}")
        return Bucket(bucket, prefix if not prefix or prefix.endswith("/") else prefix + "/")
    return Folder(Path(url))


# --- progress ---------------------------------------------------------------------------------------
def archived_through(conn: Connection, track: str = PROGRESS) -> date | None:
    """The last day the archive holds (every day up to it) on the track (`PROGRESS` or `AUCTIONS`), or None
    before the first."""
    t = schema.archive_progress
    through: date | None = conn.execute(select(t.c.through).where(t.c.name == track)).scalar_one_or_none()
    return through


def set_through(conn: Connection, day: date, now: datetime | None = None, track: str = PROGRESS) -> None:
    db.upsert(
        conn,
        schema.archive_progress,
        [{"name": track, "through": day, "updated_at": db.utc(now or db.utcnow())}],
        ["name"],
        ["through", "updated_at"],
    )


def pending_days(conn: Connection, today: date) -> list[date]:
    """The settled days not archived yet, oldest first: from the day after the last archived, else from
    the oldest day anything was recorded on."""
    last = today - timedelta(days=SETTLED_DAYS)
    through = archived_through(conn)
    first = through + timedelta(days=1) if through is not None else _oldest_day(conn)
    if first is None or first > last:
        return []
    return [first + timedelta(days=n) for n in range((last - first).days + 1)]


def pending_auction_days(conn: Connection, today: date) -> list[date]:
    """The days of feed snapshots settled (FEED_SETTLED_DAYS) and not archived yet, oldest first: from the
    day after the last archived, else from the oldest feed snapshot kept with its auctions."""
    last = today - timedelta(days=FEED_SETTLED_DAYS)
    through = archived_through(conn, AUCTIONS)
    if through is not None:
        first: date | None = through + timedelta(days=1)
    else:
        snap, bodies = schema.price_snapshots, schema.snapshot_bodies
        oldest = conn.execute(
            select(func.min(snap.c.scanned_at))
            .join(bodies, bodies.c.snapshot_id == snap.c.id)
            .where(bodies.c.format == AUCTIONS)
        ).scalar_one_or_none()
        first = None if oldest is None else db.utc(oldest).date()
    if first is None or first > last:
        return []
    return [first + timedelta(days=n) for n in range((last - first).days + 1)]


def _oldest_day(conn: Connection) -> date | None:
    snap, pd, ps = schema.price_snapshots, schema.price_daily, schema.price_sales_daily
    found: list[date] = []
    scanned = conn.execute(select(func.min(snap.c.scanned_at))).scalar_one_or_none()
    if scanned is not None:
        found.append(db.utc(scanned).date())
    for t in (pd, ps):
        day = conn.execute(select(func.min(t.c.day))).scalar_one_or_none()
        if day is not None:
            found.append(day)
    return min(found) if found else None


# --- writing ----------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Written:
    day: date
    snapshots: int
    price_daily: int
    price_sales_daily: int


def names(day: date) -> dict[str, str]:
    """Each table's file for the day."""
    return {t: f"{t}/{day:%Y/%m}/{day.isoformat()}.jsonl.gz" for t in TABLES}


def write_day(conn: Connection, sink: Sink, day: date) -> Written:
    """Write the day's files (empty ones too) to the sink."""
    counts: dict[str, int] = {}
    with tempfile.TemporaryDirectory() as tmp:
        for table, name in names(day).items():
            path = Path(tmp) / f"{table}.jsonl.gz"
            rows = _snapshot_lines(conn, day) if table == "snapshots" else _daily_lines(conn, table, day)
            with gzip.open(path, "wt", encoding="utf-8") as out:
                counts[table] = _write_lines(out, rows)
            sink.put(name, path)
    return Written(day, counts["snapshots"], counts["price_daily"], counts["price_sales_daily"])


def run(database: db.Database, sink: Sink, today: date | None = None) -> list[Written]:
    """Archive every settled day not archived yet, oldest first, a transaction each."""
    today = today or db.utcnow().date()
    with database.begin() as conn:
        days = pending_days(conn, today)
    written = []
    for day in days:
        with database.begin() as conn:
            written.append(write_day(conn, sink, day))
            set_through(conn, day)
    return written


@dataclass(frozen=True)
class WrittenAuctions:
    day: date
    snapshots: int


def auctions_name(day: date) -> str:
    """The day's file of feed auctions."""
    return f"{AUCTIONS}/{day:%Y/%m}/{day.isoformat()}.jsonl.gz"


def write_auctions_day(conn: Connection, sink: Sink, day: date) -> WrittenAuctions:
    """Write the day's feed auctions (an empty file too) to the sink."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "auctions.jsonl.gz"
        with gzip.open(path, "wt", encoding="utf-8") as out:
            n = _write_lines(out, _auction_lines(conn, day))
        sink.put(auctions_name(day), path)
    return WrittenAuctions(day, n)


def run_auctions(database: db.Database, sink: Sink, today: date | None = None) -> list[WrittenAuctions]:
    """Archive every settled day of feed auctions not archived yet, oldest first, a transaction each."""
    today = today or db.utcnow().date()
    with database.begin() as conn:
        days = pending_auction_days(conn, today)
    written = []
    for day in days:
        with database.begin() as conn:
            written.append(write_auctions_day(conn, sink, day))
            set_through(conn, day, track=AUCTIONS)
    return written


def _write_lines(out: IO[str], rows: Iterable[dict[str, Any]]) -> int:
    n = 0
    for row in rows:
        out.write(json.dumps(row, separators=(",", ":"), default=_json) + "\n")
        n += 1
    return n


def _json(value: object) -> str:
    if isinstance(value, datetime):
        return db.utc(value).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(f"{type(value).__name__} is not archived")


def _bounds(day: date) -> tuple[datetime, datetime]:
    start = datetime.combine(day, time(), db.utcnow().tzinfo)
    return start, start + timedelta(days=1)


def _snapshot_lines(conn: Connection, day: date) -> Iterator[dict[str, Any]]:
    snap, ah = schema.price_snapshots, schema.auction_houses
    obs, bodies = schema.price_observations, schema.snapshot_bodies
    start, end = _bounds(day)
    rows = conn.execute(
        select(snap, ah.c.game_version, ah.c.realm, ah.c.faction)
        .join(ah, ah.c.id == snap.c.auction_house_id)
        .where(snap.c.scanned_at >= start, snap.c.scanned_at < end)
        .order_by(snap.c.id)
    ).all()
    for r in rows:
        observed = conn.execute(
            select(obs.c.item_id, obs.c.min_buyout, obs.c.quantity, obs.c.listings, obs.c.market_price)
            .where(obs.c.snapshot_id == r.id)
            .order_by(obs.c.item_id)
        ).all()
        body = conn.execute(
            select(bodies.c.body).where(bodies.c.snapshot_id == r.id, bodies.c.format == "book")
        ).one_or_none()
        line: dict[str, Any] = {
            "id": r.id,
            "game_version": r.game_version,
            "realm": r.realm,
            "faction": r.faction,
            "source": r.source,
            "status": r.status,
            "scanned_at": r.scanned_at,
            "received_at": r.received_at,
            "build": r.build,
            "item_count": r.item_count,
            "observations": [list(o) for o in observed],
            "book": None if body is None else decode_book(body.body),
        }
        yield line


def _auction_lines(conn: Connection, day: date) -> Iterator[dict[str, Any]]:
    snap, ah, bodies = schema.price_snapshots, schema.auction_houses, schema.snapshot_bodies
    start, end = _bounds(day)
    rows = conn.execute(
        select(
            snap.c.id,
            snap.c.status,
            snap.c.scanned_at,
            ah.c.game_version,
            ah.c.realm,
            ah.c.faction,
            bodies.c.body,
        )
        .join(ah, ah.c.id == snap.c.auction_house_id)
        .join(bodies, bodies.c.snapshot_id == snap.c.id)
        .where(snap.c.scanned_at >= start, snap.c.scanned_at < end, bodies.c.format == AUCTIONS)
        .order_by(snap.c.id)
    )
    for r in rows:
        yield {
            "id": r.id,
            "game_version": r.game_version,
            "realm": r.realm,
            "faction": r.faction,
            "status": r.status,
            "scanned_at": r.scanned_at,
            "auctions": decode_auctions(r.body),
        }


def _daily_lines(conn: Connection, table: str, day: date) -> Iterator[dict[str, Any]]:
    """House by house, so each read is the (house, day) index's: the table holds DAILY_KEEP_DAYS of days."""
    t, ah = getattr(schema, table), schema.auction_houses
    houses = conn.execute(select(ah.c.id, ah.c.game_version, ah.c.realm, ah.c.faction).order_by(ah.c.id))
    for h in houses.all():
        rows = conn.execute(
            select(t).where(t.c.auction_house_id == h.id, t.c.day == day).order_by(t.c.item_id)
        )
        for r in rows:
            yield {**r._mapping, "game_version": h.game_version, "realm": h.realm, "faction": h.faction}
