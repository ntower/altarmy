"""The long-term archive (`archive`) and pruning only what it holds (`prices.prune`)."""

from __future__ import annotations

import gzip
import json
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import Connection, func, select

from altarmy_site import archive, cli, db, feed, jobs, prices, schema

from .conftest import FOREVER, book_scan
from .snapshot_fixtures import FOREVER as FOREVER_VERSION
from .snapshot_fixtures import auction, snap

T0 = datetime(2026, 9, 20, 12, 0, tzinfo=UTC)
DAY0 = T0.date()
ORE, BAR = 2770, 2840


def house(conn: Connection) -> int:
    return prices.auction_house(conn, FOREVER, "Normal", "Horde")


def count(conn: Connection, table: str) -> int:
    return int(conn.execute(select(func.count()).select_from(schema.metadata.tables[table])).scalar_one())


def lines(root: Path, table: str, day: date) -> list[dict[str, Any]]:
    with gzip.open(root / archive.names(day)[table], "rt", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def settled(day: date) -> date:
    """The first day on which `day` is archived."""
    return day + timedelta(days=archive.SETTLED_DAYS)


# --- full scans --------------------------------------------------------------------------------------
def test_a_book_round_trips() -> None:
    scan = book_scan({ORE: [(100, 3), (120, 5)], BAR: [(900, 1)]}, T0)
    assert archive.decode_book(archive.encode_book(scan)) == {
        "listings": 3,
        "bid_only": 0,
        "source": "own",
        "items": [
            {"item": ORE, "levels": [[100, 3, 1, False], [120, 5, 1, False]]},
            {"item": BAR, "levels": [[900, 1, 1, False]]},
        ],
    }


def test_auctions_round_trip() -> None:
    s = snap(int(T0.timestamp()), auction(2, ORE, unit=100, qty=3), auction(1, BAR, unit=None, qty=1, bid=50))
    assert archive.decode_auctions(archive.encode_auctions(s)) == [
        [1, BAR, 1, None, 50, "LONG"],
        [2, ORE, 3, 100, None, "LONG"],
    ]
    assert archive.decode_auctions(archive.encode_auctions(snap(int(T0.timestamp())))) == []


def test_every_recorded_scan_keeps_its_book(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, book_scan({ORE: [(100, 3)]}, T0))
    prices.record_book(conn, ah, book_scan({ORE: [(100, 3)]}, T0))  # stale: no snapshot, no body
    bodies = conn.execute(select(schema.snapshot_bodies)).all()
    assert [b.format for b in bodies] == ["book"]
    assert archive.decode_book(bodies[0].body)["items"] == [{"item": ORE, "levels": [[100, 3, 1, False]]}]


def test_a_quarantined_scan_keeps_its_book_too(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, book_scan({i: [(100, 1)] for i in range(1, 61)}, T0))
    # right after, with under a quarter of its levels: it breaks off (`prices._breaks_off`)
    got = prices.record_book(conn, ah, book_scan({ORE: [(100, 3)]}, T0 + timedelta(minutes=10)), trust=0.0)
    assert got.quarantined
    body = conn.execute(select(schema.snapshot_bodies).order_by(schema.snapshot_bodies.c.snapshot_id)).all()[
        -1
    ]
    assert archive.decode_book(body.body)["items"] == [{"item": ORE, "levels": [[100, 3, 1, False]]}]


def test_a_feed_snapshot_keeps_its_auctions(conn: Connection) -> None:
    ah = house(conn)
    feed.record_auction_snapshot(
        conn, ah, snap(int(T0.timestamp()), auction(1, ORE, unit=64)), FOREVER_VERSION
    )
    body = conn.execute(select(schema.snapshot_bodies)).one()
    assert body.format == "auctions"
    assert archive.decode_auctions(body.body) == [[1, ORE, 1, 64, None, "LONG"]]


# --- writing days ------------------------------------------------------------------------------------
def test_sinks() -> None:
    assert archive.sink_for("gs://alt-army-archive") == archive.Bucket("alt-army-archive", "")
    assert archive.sink_for("gs://b/prod") == archive.Bucket("b", "prod/")
    assert archive.sink_for("gs://b/prod/") == archive.Bucket("b", "prod/")
    assert archive.sink_for("out/archive") == archive.Folder(Path("out/archive"))
    with pytest.raises(ValueError):
        archive.sink_for("gs:///x")


def test_only_settled_days_are_pending(conn: Connection) -> None:
    assert archive.pending_days(conn, settled(DAY0)) == []  # nothing recorded
    prices.record_book(conn, house(conn), book_scan({ORE: [(100, 3)]}, T0))
    assert archive.pending_days(conn, settled(DAY0) - timedelta(days=1)) == []
    assert archive.pending_days(conn, settled(DAY0) + timedelta(days=1)) == [DAY0, DAY0 + timedelta(days=1)]
    archive.set_through(conn, DAY0)
    assert archive.pending_days(conn, settled(DAY0) + timedelta(days=1)) == [DAY0 + timedelta(days=1)]


def test_a_day_is_written_whole(database: db.Database, conn: Connection, tmp_path: Path) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, book_scan({ORE: [(100, 3), (120, 5)]}, T0), uploader_uid="someone")
    prices.record_book(conn, ah, book_scan({ORE: [(120, 5)]}, T0 + timedelta(minutes=20)))
    prices.record_book(conn, ah, book_scan({ORE: [(130, 5)]}, T0 + timedelta(days=1)))

    written = archive.run(database, archive.Folder(tmp_path), today=settled(DAY0))
    assert written == [archive.Written(DAY0, 2, 1, 1)]
    with database.begin() as c:
        assert archive.archived_through(c) == DAY0

    first, second = lines(tmp_path, "snapshots", DAY0)
    assert (first["realm"], first["faction"], first["game_version"]) == ("Normal", "Horde", FOREVER)
    assert (first["source"], first["status"], first["item_count"]) == ("altarmy", "accepted", 1)
    assert first["scanned_at"] == T0.isoformat()
    assert first["book"]["items"] == [{"item": ORE, "levels": [[100, 3, 1, False], [120, 5, 1, False]]}]
    assert first["auctions"] is None
    assert [o[:2] for o in first["observations"]] == [[ORE, 100]]
    assert "uploader_uid" not in first and "someone" not in json.dumps(first)
    assert second["book"]["items"] == [{"item": ORE, "levels": [[120, 5, 1, False]]}]

    (daily,) = lines(tmp_path, "price_daily", DAY0)
    assert (daily["item_id"], daily["day"], daily["realm"]) == (ORE, DAY0.isoformat(), "Normal")
    (sold,) = lines(tmp_path, "price_sales_daily", DAY0)
    assert (sold["item_id"], sold["units"]) == (ORE, 3)

    assert archive.run(database, archive.Folder(tmp_path), today=settled(DAY0)) == []  # nothing new
    later = archive.run(database, archive.Folder(tmp_path), today=settled(DAY0) + timedelta(days=2))
    assert [(w.day, w.snapshots) for w in later] == [
        (DAY0 + timedelta(days=1), 1),
        (DAY0 + timedelta(days=2), 0),
    ]
    assert lines(tmp_path, "snapshots", DAY0 + timedelta(days=2)) == []  # an empty day's files are written


def test_a_failed_write_archives_nothing(database: db.Database, conn: Connection) -> None:
    prices.record_book(conn, house(conn), book_scan({ORE: [(100, 3)]}, T0))

    class Broken:
        def put(self, name: str, path: Path) -> None:
            raise OSError("bucket gone")

    with pytest.raises(OSError):
        archive.run(database, Broken(), today=settled(DAY0))
    with database.begin() as c:
        assert archive.archived_through(c) is None


# --- pruning -----------------------------------------------------------------------------------------
def test_nothing_unarchived_is_pruned(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, book_scan({ORE: [(100, 3)]}, T0))
    prices.record_book(conn, ah, book_scan({BAR: [(5, 1)]}, T0 + timedelta(minutes=1)))
    prices.prune(conn, now=T0 + timedelta(days=prices.DAILY_KEEP_DAYS + 30))
    assert (count(conn, "price_snapshots"), count(conn, "snapshot_bodies"), count(conn, "price_daily")) == (
        2,
        2,
        2,
    )


def test_archived_days_are_pruned_as_they_age(conn: Connection) -> None:
    ah = house(conn)
    prices.record_book(conn, ah, book_scan({ORE: [(100, 3)]}, T0))
    prices.record_book(conn, ah, book_scan({ORE: [(110, 3)]}, T0 + timedelta(minutes=1)))
    prices.record_book(conn, ah, book_scan({ORE: [(120, 3)]}, T0 + timedelta(days=1)))
    archive.set_through(conn, DAY0)

    prices.prune(conn, now=T0 + timedelta(days=2))
    # the archived day's full scans go at once; everything else stays while it is young
    assert count(conn, "snapshot_bodies") == 1
    assert (count(conn, "price_snapshots"), count(conn, "price_observations")) == (3, 3)

    prices.prune(conn, now=T0 + timedelta(days=prices.KEEP_DAYS + 1))
    snap = schema.price_snapshots
    rows = conn.execute(select(snap.c.scanned_at).order_by(snap.c.id)).all()
    kept = [db.utc(r.scanned_at) for r in rows]
    # the archived day's snapshots go (price_current points at the newest); the unarchived day's stays
    assert kept == [T0 + timedelta(days=1)]
    assert count(conn, "price_observations") == 1  # only the unarchived day's
    assert count(conn, "price_daily") == 2

    prices.prune(conn, now=T0 + timedelta(days=prices.DAILY_KEEP_DAYS + 2))
    pd = schema.price_daily
    assert conn.execute(select(pd.c.day)).scalars().all() == [DAY0 + timedelta(days=1)]


def test_row_estimate_counts_on_sqlite(conn: Connection) -> None:
    prices.record_book(conn, house(conn), book_scan({ORE: [(100, 3)], BAR: [(5, 1)]}, T0))
    assert db.row_estimate(conn, schema.price_observations) == count(conn, "price_observations")


# --- the job -----------------------------------------------------------------------------------------
def test_cli_prune_archives_first(
    database: db.Database, conn: Connection, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    long_ago = db.utcnow() - timedelta(days=archive.SETTLED_DAYS + 1)
    prices.record_book(conn, house(conn), book_scan({ORE: [(100, 3)]}, long_ago))
    url = str(database.engine.url.database)
    if not database.engine.url.drivername.startswith("sqlite"):
        pytest.skip("the CLI's --db takes a SQLite file")
    out = tmp_path / "archive"
    cli.main(["--db", url, "prune", "--archive", str(out)])
    said = capsys.readouterr().out
    assert f"Archived 2 days ({long_ago.date()} to " in said and "1 snapshots" in said
    assert "Pruned what is archived" in said
    assert lines(out, "snapshots", long_ago.date())[0]["book"] is not None
    with database.begin() as c:
        assert [r.ok for r in jobs.recent(c, FOREVER)] == [True]


def test_cli_prune_without_an_archive_keeps_everything(
    database: db.Database, conn: Connection, capsys: pytest.CaptureFixture[str]
) -> None:
    if not database.engine.url.drivername.startswith("sqlite"):
        pytest.skip("the CLI's --db takes a SQLite file")
    prices.record_book(conn, house(conn), book_scan({ORE: [(100, 3)]}, T0))
    cli.main(["--db", str(database.engine.url.database), "prune"])
    assert "Nothing archived yet" in capsys.readouterr().out
    assert count(conn, "price_snapshots") == 1
