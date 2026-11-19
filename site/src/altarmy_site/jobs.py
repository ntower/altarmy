"""Runs of the scheduled CLI jobs (ingest, merge, prune) in `job_runs`, for the Admin page.

A job wraps its work in `recording`, which writes a row when it starts and completes it when it ends
(with what the job said, and whether it succeeded), each in a transaction of its own around the job's.
Functions taking a `Connection` never commit.
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy import ColumnElement, Connection, RowMapping, func, or_, select
from sqlalchemy.exc import OperationalError, ProgrammingError

from . import db, schema

# How often each job is scheduled (deploy/setup.sh `scheduler`): a job is late after LATE_FACTOR of it.
# `schema.JOBS` also names the removed ahledger job, whose old runs stay in `job_runs`.
CADENCE: dict[str, timedelta] = {
    "ingest": timedelta(days=1),
    "merge": timedelta(hours=1),
    "prune": timedelta(days=1),
    "feed": timedelta(hours=1),
}
LATE_FACTOR = 2
TIMEOUT = timedelta(minutes=30)  # a job's task timeout (deploy/deploy.sh): an unfinished run older died
SUMMARY_MAX = 4000  # characters of a run's summary kept (the end, where failures are)


@dataclass(frozen=True)
class JobRun:
    id: int
    job: str
    game_version: str | None  # None: the job covers every version
    started_at: datetime
    finished_at: datetime | None  # None while it runs (or if it died without a word)
    ok: bool | None
    summary: str


def start(conn: Connection, job: str, game_version: str | None = None, *, now: datetime | None = None) -> int:
    """Record that `job` started; returns the run's id."""
    t = schema.job_runs
    run_id: int = conn.execute(
        t.insert()
        .values(job=job, game_version=game_version, started_at=now or db.utcnow(), summary="")
        .returning(t.c.id)
    ).scalar_one()
    return run_id


def finish(conn: Connection, run_id: int, ok: bool, summary: str, *, now: datetime | None = None) -> None:
    """Record how the run ended, keeping the last SUMMARY_MAX characters of `summary`."""
    t = schema.job_runs
    if len(summary) > SUMMARY_MAX:
        summary = "…" + summary[-(SUMMARY_MAX - 1) :]
    conn.execute(
        t.update().where(t.c.id == run_id).values(finished_at=now or db.utcnow(), ok=ok, summary=summary)
    )


@dataclass
class Run:
    """What a recorded job says: printed, and kept as the run's summary."""

    lines: list[str] = field(default_factory=list)

    def say(self, text: str) -> None:
        print(text)
        self.lines.append(text)

    def warn(self, text: str, *, alert: str, **fields: object) -> None:
        """Say `text` as one JSON line, which Cloud Logging reads as a WARNING entry carrying `alert` (what
        a log-based alert policy matches; deploy/setup.sh `alerts`) and `fields`."""
        print(json.dumps({"severity": "WARNING", "message": text, "alert": alert, **fields}))
        self.lines.append(text)


@contextmanager
def recording(database: db.Database, job: str, game_version: str | None = None) -> Iterator[Run]:
    """Record a run of `job` around the block: ok unless it raised (`sys.exit` with a message or a
    non-zero code counts as failing, as it does for Cloud Run). The exception is re-raised. Before the
    migration that adds `job_runs` has run (a deploy defines the jobs first), the job runs unrecorded."""
    run = Run()
    try:
        with database.begin() as conn:
            run_id: int | None = start(conn, job, game_version)
    except (OperationalError, ProgrammingError) as e:
        print(f"Not recording this run: {type(e).__name__}")
        run_id = None
    try:
        yield run
    except BaseException as e:
        if run_id is not None:
            ok, said = _outcome(e)
            with database.begin() as conn:
                finish(conn, run_id, ok, "\n".join([*run.lines, said] if said else run.lines))
        raise
    if run_id is not None:
        with database.begin() as conn:
            finish(conn, run_id, True, "\n".join(run.lines))


def _outcome(e: BaseException) -> tuple[bool, str]:
    """Whether a job that ended with `e` succeeded, and what to add to its summary."""
    if isinstance(e, SystemExit):
        if e.code is None or e.code == 0:
            return True, ""
        return False, e.code if isinstance(e.code, str) else f"Exit code {e.code}"
    return False, f"{type(e).__name__}: {e}"


def _run(r: RowMapping) -> JobRun:
    return JobRun(
        id=r["id"],
        job=r["job"],
        game_version=r["game_version"],
        started_at=db.utc(r["started_at"]),
        finished_at=None if r["finished_at"] is None else db.utc(r["finished_at"]),
        ok=r["ok"],
        summary=r["summary"],
    )


def _for_version(game_version: str) -> ColumnElement[bool]:
    t = schema.job_runs
    return or_(t.c.game_version == game_version, t.c.game_version.is_(None))


def recent(conn: Connection, game_version: str, limit: int = 50) -> list[JobRun]:
    """The newest runs of `game_version`'s jobs and of those covering every version."""
    t = schema.job_runs
    rows = conn.execute(
        select(t)
        .where(_for_version(game_version))
        .order_by(t.c.started_at.desc(), t.c.id.desc())
        .limit(limit)
    ).mappings()
    return [_run(r) for r in rows]


def latest(conn: Connection, game_version: str) -> dict[str, JobRun]:
    """Each job's newest run for `game_version` (or every version); jobs that never ran are missing."""
    t = schema.job_runs
    newest = (
        select(func.max(t.c.id).label("id")).where(_for_version(game_version)).group_by(t.c.job).subquery()
    )
    rows = conn.execute(select(t).join(newest, newest.c.id == t.c.id)).mappings()
    return {run.job: run for run in map(_run, rows)}


def running(run: JobRun, now: datetime) -> bool:
    """Whether the run is still going: unfinished, and not older than a job may run (else it died)."""
    return run.finished_at is None and now - run.started_at < TIMEOUT


def late(job: str, last_started: datetime | None, now: datetime) -> bool:
    """Whether the job should have run again by `now` (it never ran, or not for LATE_FACTOR cadences)."""
    return last_started is None or now - last_started > LATE_FACTOR * CADENCE[job]
