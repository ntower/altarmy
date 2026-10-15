"""Command line interface: the site's jobs (ingest, migrate, prune, merge; all but migrate record
their runs in `job_runs`), `serve` (the API and built front end, for development), `watch` (uploads the
addon files to a server), `admin` (the site admin claim on Firebase accounts) and `alert-relay` (the
Discord relay, `alerts`).

`--game-version` (tbc | forever) picks the game's data and wago.tools product. Every version shares one
database: `--db` (a SQLite file), else `DATABASE_URL`, else data/altarmy.sqlite.
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from collections.abc import Iterable, Mapping
from datetime import datetime, timedelta
from pathlib import Path
from typing import TYPE_CHECKING

from sqlalchemy import Connection, select

from . import (
    addon_crates,
    auth,
    cloudlog,
    db,
    feed,
    gamedata,
    ingest,
    jobs,
    launch,
    merge,
    prices,
    schema,
    signals,
    signin,
    snapshots,
    versions,
    watch,
    wowfiles,
)
from .versions import GameVersion

if TYPE_CHECKING:
    from fastapi import FastAPI


def _version(args: argparse.Namespace) -> GameVersion:
    return versions.get(args.game_version)


def _database(args: argparse.Namespace) -> db.Database:
    """`--db`, else DATABASE_URL, else the default SQLite file (absolute, so the server's threads agree)."""
    if args.db:
        return db.Database(db.sqlite_url(Path(args.db).resolve()))
    url = db.default_url()
    return db.Database(url if url != db.sqlite_url(db.DEFAULT_DB) else db.sqlite_url(db.DEFAULT_DB.resolve()))


def cmd_ingest(args: argparse.Namespace) -> None:
    v = _version(args)
    if args.force and not args.only_if_new:
        sys.exit("--force goes with --only-if-new (without it, ingest always reloads)")
    if args.only_if_new:  # the hosted job: the pinned build, unless already loaded (or --force)
        launch.run_ingest(args.database, v, Path(args.cache), force=args.force)
    else:
        with jobs.recording(args.database, "ingest", v.key) as run:
            build = args.build or ingest.pinned_build(v)
            if build == "latest":
                build = ingest.latest_build(v.wago_product)
            with args.database.begin() as conn:
                stats = ingest.update(
                    conn,
                    v.key,
                    build,
                    Path(args.cache),
                    v.disenchant_csv,
                    v.vendor_csv,
                    v.vendor_recipes_csv,
                    v.sources_csv,
                    v.trainer_costs_csv,
                )
            run.say(f"Ingested {v.label} build {build}: {stats}")
    # The addon's Waylaid Crates table comes from this game data (only for a local SQLite ingest).
    note = addon_crates.regenerate(args.database, v.key)
    if note:
        print(note)


def cmd_migrate(args: argparse.Namespace) -> None:
    """Migrate to the newest revision (a hosted deploy runs this once, before the new service starts)."""
    with args.database.begin() as conn:
        db.upgrade(conn)
        db.register_versions(conn)
        revision = db.current_revision(conn)
    print(f"Database at revision {revision}.")


def cmd_prune(args: argparse.Namespace) -> None:
    with jobs.recording(args.database, "prune") as run:
        with args.database.begin() as conn:
            prices.prune(conn)
        run.say(f"Pruned price observations older than {prices.KEEP_DAYS} days.")


def cmd_merge(args: argparse.Namespace) -> None:
    with jobs.recording(args.database, "merge") as run:
        with args.database.begin() as conn:
            changed = merge.merge(conn)
            observations = merge.observation_count(conn)
            moved = _price_versions(conn, [ah for ah, c in changed.items() if c])
        run.say(
            f"Merged {len(changed)} auction houses of every game version ({sum(changed.values())} changed); "
            f"{observations} price observations stored."
        )
        if observations >= merge.PARTITION_AT:
            run.warn(
                f"price_observations has {observations} rows (limit {merge.PARTITION_AT}): "
                "partition it by month.",
                alert=merge.PARTITION_ALERT,
                observations=observations,
            )
        run.say(_signal(signals.from_env(), moved))


def cmd_feed_load(args: argparse.Namespace) -> None:
    """Record saved auction snapshots (bodies as Blizzard serves them) for one house, an hour apart."""
    version = versions.get(args.game_version)
    start = (
        datetime.fromisoformat(args.start)
        if args.start
        else db.utcnow() - timedelta(hours=len(args.files) - 1)
    )
    start = db.utc(start)
    moved: set[int] = set()
    with args.database.begin() as conn:
        ah = prices.auction_house(conn, version.key, version.realm_name(args.realm), args.faction)
        for i, path in enumerate(args.files):
            t = int((start + timedelta(minutes=args.step * i)).timestamp())
            try:
                snap = snapshots.parse_blizzard(
                    Path(path).read_bytes(), t=t, realm=args.realm, faction=args.faction
                )
            except ValueError as e:
                sys.exit(f"{path}: {e}")
            got = feed.record_auction_snapshot(conn, ah, snap, version)
            print(
                f"{path}: {got.items} items, {got.moved} moved, {got.ended} ended, {got.posted} posted"
                + (" (stale)" if got.stale else " (held back: cut short)" if got.quarantined else "")
            )
            if got.moved:
                moved.add(ah)
        versions_moved = _price_versions(conn, moved)
    print(_signal(signals.from_env(), versions_moved))


def _price_versions(conn: Connection, auction_house_ids: Iterable[int]) -> dict[str, dict[int, int]]:
    """{game version: {auction house id: price version}} of these auction houses, to signal."""
    t = schema.auction_houses
    rows = conn.execute(
        select(t.c.id, t.c.game_version, t.c.price_version).where(t.c.id.in_(list(auction_house_ids)))
    )
    out: dict[str, dict[int, int]] = {}
    for r in rows:
        out.setdefault(r.game_version, {})[r.id] = r.price_version
    return out


def _signal(to: signals.Signals, moved: Mapping[str, Mapping[int, int]]) -> str:
    """Publish the committed price versions (see `signals`); what to say about it."""
    if isinstance(to, signals.NoSignals):
        return "No price signals: no Firebase project."
    sent = sum(signals.publish_all(to, version, houses) for version, houses in sorted(moved.items()))
    wanted = sum(len(h) for h in moved.values())
    said = f"{sent} price signal{'' if sent == 1 else 's'} sent"
    return f"{said} ({wanted - sent} failed)." if sent < wanted else f"{said}."


def cmd_serve(args: argparse.Namespace) -> None:
    """The API (and the built front end, if any) on one port: `npm run dev` runs it behind Vite, signed in
    against the Firebase Auth emulator. Migrates the database first."""
    try:
        import uvicorn

        from .api import DEFAULT_DIST, create_app
    except ImportError:
        sys.exit('The server needs FastAPI, uvicorn and firebase-admin: pip install -e ".[ui]"')
    try:
        app = create_app(versions.VERSIONS, database=args.database)
    except ValueError as e:
        sys.exit(str(e))
    with args.database.begin() as conn:
        for v in versions.VERSIONS.values():
            if db.count_rows(conn, "recipes", v.key) == 0:
                flag = "" if v.key == versions.DEFAULT_VERSION else f" --game-version {v.key}"
                print(f"No {v.label} game data yet: run `altarmy-site{flag} ingest`.")
    if not (DEFAULT_DIST / "index.html").is_file():
        print(f"Front end not built ({DEFAULT_DIST} missing): `npm run dev` serves it through Vite instead.")
    print(f"Alt Army website API on http://{args.host}:{args.port} (Ctrl+C to stop)")
    if not args.reload:
        uvicorn.run(app, host=args.host, port=args.port)
        return
    # uvicorn reloads only an app it can import again: each worker builds its own with `serve_app`, on the
    # database this process migrated, named in the environment the worker inherits
    os.environ["DATABASE_URL"] = args.database.url.render_as_string(hide_password=False)
    package = Path(__file__).resolve().parent
    uvicorn.run(
        "altarmy_site.cli:serve_app",
        factory=True,
        host=args.host,
        port=args.port,
        reload=True,
        reload_dirs=[str(package)],
    )


def serve_app() -> FastAPI:
    """`serve --reload`'s app, built again in each reloaded worker (`DATABASE_URL`, already migrated)."""
    from .api import create_app

    return create_app(versions.VERSIONS, database=db.Database(db.default_url(), migrate=False))


def cmd_admin(args: argparse.Namespace) -> None:
    """Grant, revoke or list the site admin claim on Firebase accounts (no database). Needs Firebase Auth
    admin rights: Application Default Credentials, or the Auth emulator when FIREBASE_AUTH_EMULATOR_HOST
    is set."""
    if args.action != "list" and not args.email:
        sys.exit(f"admin {args.action} needs the account's email.")
    project = args.project
    if not project:
        try:
            project = auth.FirebaseConfig.from_env().project_id
        except ValueError as e:
            sys.exit(str(e))
    try:
        roster: auth.AdminRoster = auth.FirebaseVerifier(project)
    except ImportError:
        sys.exit('Managing admins needs firebase-admin: pip install -e ".[ui]"')
    try:
        if args.action == "list":
            found = roster.admins()
            for uid, email in found:
                print(f"{email or '(no email)'} ({uid})")
            print(f"{len(found)} admins in {project}.")
            return
        uid = roster.set_admin(args.email, args.action == "grant")
    except auth.AccountError as e:
        sys.exit(f"{project}: {e}")
    done = "Granted" if args.action == "grant" else "Revoked"
    print(
        f"{done} admin for {args.email} ({uid}) in {project}. It applies to sign-in tokens issued from now:"
        " sign out and in to see it."
    )


def cmd_alert_relay(args: argparse.Namespace) -> None:
    """Cloud Monitoring's notifications to Discord (no database): the Cloud Run service `altarmy-alerts`."""
    try:
        import uvicorn

        from .alerts import create_relay_app
    except ImportError:
        sys.exit('The relay needs FastAPI and uvicorn: pip install -e ".[ui]"')
    try:
        app = create_relay_app()
    except KeyError:
        sys.exit(
            "Set DISCORD_WEBHOOK_URL (the Discord channel's webhook) and RELAY_PASSWORD (the channel's)."
        )
    # on Cloud Run `main` has set up JSON logs, which uvicorn's own config would replace
    config = None if cloudlog.cloud_run_name() else uvicorn.config.LOGGING_CONFIG
    uvicorn.run(app, host=args.host, port=args.port, log_config=config)


def _ask(prompt: str, env: str, secret: bool = False) -> str:
    """A value from the environment (for running unattended), else asked for on the terminal."""
    value = os.environ.get(env)
    if value:
        return value
    return getpass.getpass(prompt) if secret else input(prompt)


def watch_credentials(
    server: str,
    path: Path,
    *,
    fresh: bool = False,
    create: bool = False,
    transport: signin.Transport = signin.urllib_transport,
) -> signin.Credentials:
    """The watcher's sign-in to `server`: the one saved in `path`, else (or with `fresh`) an email and
    password asked for once (`create`: a new account). Only the refresh token is saved."""
    config = signin.fetch_config(server, transport)

    def remember(session: signin.Session) -> None:
        signin.save(path, server, session)

    saved = None if fresh or create else signin.load_saved(path, server)
    if saved is not None:
        email, token = saved
        return signin.Credentials(config, email, token, transport, on_change=remember)
    email = _ask("Email: ", "ALTARMY_EMAIL")
    password = _ask("Password: ", "ALTARMY_PASSWORD", secret=True)
    if create:
        if _ask("Password again: ", "ALTARMY_PASSWORD", secret=True) != password:
            raise signin.SignInError("The passwords don't match.")
        session = signin.sign_up(config, email, password, transport)
    else:
        session = signin.sign_in(config, email, password, transport)
    remember(session)
    print(f"Signed in as {session.email}.")
    return signin.Credentials.of(config, session, transport=transport, on_change=remember)


def cmd_watch(args: argparse.Namespace) -> None:
    """Upload the addon files to a server whenever WoW rewrites them (no local database)."""
    signin.move_old_settings()
    roots = [Path(r) for r in args.wow_root] if args.wow_root else wowfiles.WOW_ROOTS
    state = Path(args.state)
    auth_path = Path(args.auth)
    server = args.server.rstrip("/")
    found = watch.find_files(roots)
    if not found:
        sys.exit(
            f"No Alt Army or Auctionator files under {', '.join(str(r) for r in roots)}; pass --wow-root."
        )
    try:
        creds = watch_credentials(server, auth_path, fresh=args.sign_in, create=args.create_account)
        print(f"Watching {len(found)} files for {server} as {creds.email} (Ctrl+C to stop).")
        if args.once:
            if not watch.sync_once(roots, server, creds, state):
                print("Nothing changed since the last upload.")
        else:
            watch.run(roots, server, creds, state, interval=args.interval)
            raise signin.SignedOut("the sign-in stopped working")  # run returns only then
    except signin.SignedOut as e:
        signin.save(auth_path, server, None)
        sys.exit(f"Signed out ({e}): run again to sign in.")
    except (watch.UploadFailed, signin.SignInError, signin.Unreachable) as e:
        sys.exit(str(e))
    except KeyboardInterrupt:
        pass


def main(argv: list[str] | None = None) -> None:
    cloudlog.configure()  # on Cloud Run (the jobs): JSON logs, a failure's traceback for Error Reporting
    p = argparse.ArgumentParser(prog="altarmy-site")
    p.add_argument(
        "--game-version",
        choices=list(versions.VERSIONS),
        default=versions.DEFAULT_VERSION,
        help="which game's data to use (default: %(default)s)",
    )
    p.add_argument("--db", help="SQLite database file (default: DATABASE_URL, else data/altarmy.sqlite)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("ingest", help="download DB2 tables from wago.tools and build the database")
    s.add_argument("--build", help='a build version, or "latest" (default: the pinned build)')
    s.add_argument(
        "--cache", default=str(gamedata.REPO_CACHE), help="download cache (default: the repo's .cache/)"
    )
    s.add_argument(
        "--only-if-new",
        action="store_true",
        help="load the pinned build (data/game-data.json), unless the database already has it",
    )
    s.add_argument(
        "--force",
        action="store_true",
        help="with --only-if-new: reload the pinned build even if the database already has it",
    )
    s.set_defaults(fn=cmd_ingest)

    s = sub.add_parser("migrate", help="migrate the database to the newest schema revision")
    s.set_defaults(fn=cmd_migrate)

    s = sub.add_parser("prune", help=f"drop price observations older than {prices.KEEP_DAYS} days")
    s.set_defaults(fn=cmd_prune)

    s = sub.add_parser(
        "merge",
        help="recompute daily medians and the 7-day price statistics (every game version)",
    )
    s.set_defaults(fn=cmd_merge)

    s = sub.add_parser(
        "feed-load",
        help="record saved auction snapshots (bodies Blizzard's auctions endpoint served) for one house",
    )
    s.add_argument(
        "--realm", required=True, help="the realm as the snapshot names it (a fixed realm's alias works)"
    )
    s.add_argument("--faction", required=True, choices=list(versions.FACTIONS))
    s.add_argument("--start", help="UTC time of the first, ISO 8601 (default: an hour apart, ending now)")
    s.add_argument("--step", type=int, default=60, help="minutes between them (default: %(default)s)")
    s.add_argument("files", nargs="+")
    s.set_defaults(fn=cmd_feed_load)

    s = sub.add_parser(
        "admin", help="grant, revoke or list the site admin claim on Firebase accounts (needs the [ui] extra)"
    )
    s.add_argument("action", choices=["grant", "revoke", "list"])
    s.add_argument("email", nargs="?", help="the account's email (grant, revoke)")
    s.add_argument("--project", help="the Firebase project (default: FIREBASE_PROJECT_ID)")
    s.set_defaults(fn=cmd_admin, needs_db=False)

    s = sub.add_parser("serve", help="serve the API and the built front end (needs the [ui] extra)")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=8600)
    s.add_argument("--reload", action="store_true", help="restart when the Python code changes (development)")
    s.set_defaults(fn=cmd_serve)

    s = sub.add_parser(
        "watch", help="upload the addon files to the Alt Army website whenever WoW rewrites them"
    )
    s.add_argument("--server", required=True, help="e.g. https://alt-army.com")
    s.add_argument(
        "--sign-in",
        action="store_true",
        help="ask for the email and password even if a sign-in is saved (ALTARMY_EMAIL, ALTARMY_PASSWORD"
        " answer instead when set)",
    )
    s.add_argument("--create-account", action="store_true", help="create an account on the site, then watch")
    s.add_argument("--auth", default=str(signin.DEFAULT_AUTH), help="the saved sign-in (a refresh token)")
    s.add_argument("--interval", type=float, default=15, help="seconds between checks (default: 15)")
    s.add_argument("--once", action="store_true", help="upload what changed, then exit")
    s.add_argument("--state", default=str(watch.DEFAULT_STATE), help="which files were sent (JSON)")
    s.add_argument("--wow-root", action="append", help="a WoW install folder (repeatable)")
    s.set_defaults(fn=cmd_watch, needs_db=False)

    s = sub.add_parser("alert-relay", help="post Cloud Monitoring's Pub/Sub notifications to Discord")
    s.add_argument("--host", default="0.0.0.0")
    s.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")))
    s.set_defaults(fn=cmd_alert_relay, needs_db=False)

    args = p.parse_args(argv)
    if not getattr(args, "needs_db", True):
        args.fn(args)
        return
    args.database = _database(args)
    try:
        args.fn(args)
    finally:
        args.database.dispose()


if __name__ == "__main__":
    main()
