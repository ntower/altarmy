"""Starting a scheduled job on demand: the Admin page's Run now (`POST /api/admin/jobs/ingest`).

Hosted, the API starts the environment's Cloud Run job (`CloudRunJobs`: the jobs `deploy/deploy.sh` defines,
with `CLOUD_RUN_LOCATION` and `JOB_PREFIX` set on the service; its service account needs `roles/run.invoker`
on them, `deploy/setup.sh job-runner ENV`), never the job's work itself: a job has more memory than the
service, and Cloud Run throttles an instance's CPU once it has answered. In development (a SQLite
database) the work runs in a thread of the API (`InProcessJobs`). Either way the run is recorded in
`job_runs` like a scheduled one (`jobs.recording`), so the Admin page shows it.
"""

from __future__ import annotations

import logging
import os
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

from . import addon_crates, db, gamedata, jobs, service
from .versions import GameVersion

log = logging.getLogger(__name__)

RUN_API = "https://run.googleapis.com/v2"


class LaunchError(Exception):
    """The job could not be started; the message says why."""


class Launcher(Protocol):
    def ingest(self, version: GameVersion) -> str:
        """Start the version's ingest job without waiting for it; returns what to tell the admin.
        Raises LaunchError if it could not be started."""
        ...


STALE_OVERRIDES_ALERT = "stale-vendor-overrides"


def run_ingest(database: db.Database, version: GameVersion, cache_dir: Path, *, force: bool = False) -> None:
    """The ingest job's work, recorded: load the version's pinned build unless the database already has it,
    loaded by this ingest code (`service.update_game_data`), or always with `force`."""
    with jobs.recording(database, "ingest", version.key) as run:
        with database.begin() as conn:
            build, updated, stats = service.update_game_data(conn, version, cache_dir, only_if_new=not force)
        run.say(
            f"Ingested {version.label} build {build}: {stats}"
            if updated
            else f"{version.label} build {build} already loaded."
        )
        if updated and stats.get("vendor_overrides_stale"):
            run.warn(
                f"{stats['vendor_overrides_stale']} vendor price overrides of {version.label} are stale: DB2 "
                "moved under them (data/<version>/vendor_overrides.csv)",
                alert=STALE_OVERRIDES_ALERT,
            )


class InProcessJobs:
    """Runs the work in a thread of this process (development), one job at a time."""

    def __init__(self, database: db.Database, cache_dir: Path) -> None:
        self.database = database
        self.cache_dir = cache_dir
        self._busy = threading.Lock()

    def ingest(self, version: GameVersion) -> str:
        if not self._busy.acquire(blocking=False):
            raise LaunchError("A job started here is still running.")
        threading.Thread(
            target=self._ingest, args=(version,), name=f"ingest-{version.key}", daemon=True
        ).start()
        return f"Started the {version.label} ingest on this server."

    def _ingest(self, version: GameVersion) -> None:
        try:
            run_ingest(self.database, version, self.cache_dir)
            note = addon_crates.regenerate(self.database, version.key)  # as `altarmy-site ingest` does
            if note:
                log.info(note)
        except BaseException:  # recorded as failed in job_runs; a thread has nobody else to tell
            log.exception("the %s ingest failed", version.key)
        finally:
            self._busy.release()


# POST url -> (HTTP status, response text)
Transport = Callable[[str], tuple[int, str]]


def _google_post(url: str) -> tuple[int, str]:
    """POST with the runtime's Google credentials (Cloud Run's service account, else Application Default
    Credentials). google-auth and requests come with firebase-admin (the `ui` extra)."""
    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    session = AuthorizedSession(credentials)  # type: ignore[no-untyped-call]
    response = session.post(url, json={}, timeout=30)
    return response.status_code, response.text


class CloudRunJobs:
    """Starts the environment's Cloud Run jobs (`<prefix>-ingest-<version>`) through the Cloud Run Admin
    API, as Cloud Scheduler does; `location` is `projects/<project>/locations/<region>`."""

    def __init__(self, location: str, prefix: str, transport: Transport | None = None) -> None:
        self.location = location
        self.prefix = prefix
        self._post = transport or _google_post

    def job_url(self, job: str) -> str:
        return f"{RUN_API}/{self.location}/jobs/{self.prefix}-{job}:run"

    def ingest(self, version: GameVersion) -> str:
        name = f"{self.prefix}-ingest-{version.key}"
        try:
            status, text = self._post(self.job_url(f"ingest-{version.key}"))
        except Exception as e:  # no credentials, no network
            raise LaunchError(f"Could not reach Cloud Run: {e}") from e
        if status == 403:
            raise LaunchError(
                f"This service may not start {name}: grant it roles/run.invoker (deploy/setup.sh job-runner)."
            )
        if status == 404:
            raise LaunchError(f"There is no Cloud Run job {name}.")
        if not 200 <= status < 300:
            raise LaunchError(f"Cloud Run would not start {name} ({status}): {text[:300]}")
        return f"Started {name}: its run shows up here once its container is up."


def from_env(database: db.Database, cache_dir: Path = gamedata.REPO_CACHE) -> Launcher | None:
    """Cloud Run jobs with `CLOUD_RUN_LOCATION` and `JOB_PREFIX` set (the hosted service), else in-process
    on a SQLite database (development), else none: a hosted service must not run a job's work itself."""
    location, prefix = os.environ.get("CLOUD_RUN_LOCATION"), os.environ.get("JOB_PREFIX")
    if location and prefix:
        return CloudRunJobs(location, prefix)
    if database.is_sqlite:
        return InProcessJobs(database, cache_dir)
    return None
