"""Addon files users upload (from the browser or the CLI watcher): parse, store what they tell us, keep a
history. Functions taking a `Connection` never commit.

An Alt Army file replaces the uploader's characters of that game version. Where the version's prices are
first-party (Forever), it also carries the addon's auction house scans (`book.py`): each is recorded for
the auction house of the realm and faction it names, whoever uploads it, so auction houses pool everyone's
scans and the newest wins (`prices.record_book`). A scan already recorded, or older than the house's
newest, is passed over: the file holds the last few scans and is sent again whenever it changes. An
Auctionator file is refused there.

Elsewhere (TBC) an Auctionator file records a snapshot for every realm it has prices for (the newest
`seen_at` wins, see `prices.record_snapshot`).

Every scan is screened first: a quarantined one changes nothing and lowers the uploader's trust
(`prices.screen`, `users.adjust_trust`). The file itself is never stored.
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import ColumnElement, Connection, case, func, select

from . import altarmy, auctionator, book, db, paste, prices, schema, service, store, users, versions

MAX_BYTES = 32 * 2**20  # decompressed; the biggest real file (TBC Auctionator.lua) is about 5 MB
RATE_LIMIT = 60  # uploads per user per hour
SCAN_WINDOW = timedelta(days=30)  # a file's modified time is trusted this far back
GZIP_MAGIC = b"\x1f\x8b"


class RateLimited(Exception):
    pass


class TooLarge(Exception):
    pass


@dataclass(frozen=True)
class RealmPrices:
    key: str  # Auctionator's realm key ("Dreamscythe Horde"), or an Alt Army scan's realm and faction
    auction_house_id: int
    realm: str
    faction: str
    items: int  # items priced in the scan
    moved: int  # of them, items whose current price changed
    quarantined: bool = False  # the scan was far off recent prices and not used


FIRST_PARTY_ONLY = (
    "Prices for {label} come from Alt Army's own auction house scan now: press Alt Army scan at the "
    "auction house, then upload your Alt Army data."
)


@dataclass(frozen=True)
class Imported:
    kind: str  # altarmy | auctionator
    characters: int = 0
    groups: tuple[tuple[str, str, int], ...] = ()  # (realm, faction, characters)
    realms: tuple[RealmPrices, ...] = ()

    @property
    def auction_house_ids(self) -> frozenset[int]:
        return frozenset(r.auction_house_id for r in self.realms)

    @property
    def moved_auction_house_ids(self) -> frozenset[int]:
        """The auction houses whose current prices this upload moved (their price version was bumped)."""
        return frozenset(r.auction_house_id for r in self.realms if r.moved and not r.quarantined)

    @property
    def detail(self) -> str:
        scans = "; ".join(_realm_detail(r) for r in self.realms)
        if self.kind == "altarmy":
            where = ", ".join(f"{r} ({f or 'no faction'}): {n}" for r, f, n in self.groups)
            chars = f"{self.characters} characters" + (f" on {where}" if where else "")
            return f"{chars}. Auction house scans: {scans}" if scans else chars
        return scans or "No realm in the file has prices."


def _realm_detail(r: RealmPrices) -> str:
    if r.quarantined:
        return f"{r.key}: {r.items} prices not used: they differ widely from recent scans"
    return f"{r.key}: {r.items} prices, {r.moved} changed"


@dataclass(frozen=True)
class UploadRow:
    id: int
    game_version: str
    kind: str
    via: str
    size: int
    received_at: datetime
    outcome: str
    detail: str
    user_uid: str = ""


@dataclass(frozen=True)
class UploadStats:
    """Every user's uploads of a game version lately, for the Admin page."""

    accepted_24h: int
    rejected_24h: int
    accepted_7d: int
    rejected_7d: int
    uploaders_7d: int  # distinct users


def decompress(data: bytes, limit: int = MAX_BYTES) -> bytes:
    """`data` as it was before gzip (plain data passes through); TooLarge past `limit` bytes."""
    if not data.startswith(GZIP_MAGIC):
        if len(data) > limit:
            raise TooLarge
        return data
    d = zlib.decompressobj(wbits=31)
    try:
        out = d.decompress(data, limit + 1)
    except zlib.error as e:
        raise ValueError(f"not a valid gzip file: {e}") from e
    if len(out) > limit:
        raise TooLarge
    return out


def scan_time(modified_at: datetime | None, now: datetime) -> datetime:
    """When the file's scan was taken: its modified time, never in the future nor before SCAN_WINDOW."""
    if modified_at is None:
        return now
    return min(max(db.utc(modified_at), now - SCAN_WINDOW), now)


def ingest(
    conn: Connection,
    user_uid: str,
    game_version: str,
    kind: str,
    data: bytes,
    modified_at: datetime | None,
    *,
    now: datetime | None = None,
) -> Imported:
    """Store an uploaded file of `kind`; ValueError if it is not one, or an Auctionator file where
    prices are first-party."""
    now = now or db.utcnow()
    if kind == "altarmy":
        return ingest_altarmy(conn, user_uid, game_version, data, now=now)
    if kind == "auctionator":
        version = versions.get(game_version)
        if version.first_party_prices:
            raise ValueError(FIRST_PARTY_ONLY.format(label=version.label))
        return ingest_auctionator(conn, user_uid, game_version, data, scan_time(modified_at, now))
    raise ValueError(f"unknown upload kind {kind!r}")


def ingest_altarmy(
    conn: Connection, user_uid: str, game_version: str, data: bytes, *, now: datetime | None = None
) -> Imported:
    """The file's characters and, where prices are first-party, its auction house scans."""
    chars = altarmy.parse_characters(data, versions.get(game_version).retail_bags)
    scans = book.read(data) if versions.get(game_version).first_party_prices else []
    got = _save_characters(conn, user_uid, game_version, chars)
    realms = _record_books(conn, user_uid, game_version, scans, db.utc(now or db.utcnow()))
    return Imported("altarmy", got.characters, got.groups, realms)


def _record_books(
    conn: Connection, user_uid: str, game_version: str, scans: list[book.Scan], now: datetime
) -> tuple[RealmPrices, ...]:
    """Record the scans, oldest first; those passed over as stale are left out."""
    recorded = []
    version = versions.get(game_version)
    for scan in scans:
        # a fixed realm's other names land on its auction house
        ah = prices.auction_house(conn, game_version, version.realm_name(scan.realm), scan.faction)
        at = scan_time(datetime.fromtimestamp(scan.t, now.tzinfo), now)
        trust = users.trust(conn, user_uid)
        got = prices.record_book(conn, ah, scan, scanned_at=at, uploader_uid=user_uid, trust=trust)
        if got.stale:
            continue
        if got.screened:
            users.adjust_trust(conn, user_uid, quarantined=got.quarantined)
        key = f"{scan.realm} {scan.faction}"
        recorded.append(RealmPrices(key, ah, scan.realm, scan.faction, got.items, got.moved, got.quarantined))
    if recorded:
        prices.prune(conn)
    return tuple(recorded)


def ingest_paste(conn: Connection, user_uid: str, game_version: str, text: str) -> Imported:
    """Store the Alt Army addon's paste export (characters, as `ingest_altarmy`); ValueError if it is bad
    or from another game's client."""
    export = paste.decode(text, MAX_BYTES)
    if export.game_version != game_version:
        made_by = versions.VERSIONS.get(export.game_version or "")
        if made_by is None:
            raise ValueError(
                f"This export is from a client this site doesn't serve (interface {export.interface})."
            )
        served = versions.VERSIONS[game_version].label
        raise ValueError(f"This is a {made_by.label} export; this site serves {served}.")
    # the export carries no bags or bank: what each character held stays as the last file upload had it
    return _save_characters(conn, user_uid, game_version, export.characters, keep_holdings=True)


def _save_characters(
    conn: Connection,
    user_uid: str,
    game_version: str,
    chars: list[altarmy.Character],
    keep_holdings: bool = False,
) -> Imported:
    service.replace_characters(conn, user_uid, game_version, chars, keep_holdings)
    service.bump_data_version(conn, user_uid, game_version)
    groups = tuple((g.realm, g.faction, len(g.characters)) for g in altarmy.groups(chars))
    return Imported("altarmy", characters=len(chars), groups=groups)


def ingest_auctionator(
    conn: Connection,
    user_uid: str,
    game_version: str,
    data: bytes,
    scanned_at: datetime,
) -> Imported:
    realms = auctionator.parse_price_database(data)
    groups = altarmy.groups(store.load_characters(conn, user_uid, game_version))
    recorded = []
    for key, item_prices in sorted(realms.items()):
        if not item_prices:
            continue
        ah = _auction_house(conn, game_version, key, [(g.realm, g.faction) for g in groups])
        trust = users.trust(conn, user_uid)
        got = prices.record_auctionator(conn, ah, item_prices, scanned_at, uploader_uid=user_uid, trust=trust)
        if got.screened:
            users.adjust_trust(conn, user_uid, quarantined=got.quarantined)
        realm, faction = _name(conn, ah)
        recorded.append(RealmPrices(key, ah, realm, faction, len(item_prices), got.moved, got.quarantined))
    if recorded:
        prices.prune(conn)
        service.bump_data_version(conn, user_uid, game_version)
    return Imported("auctionator", realms=tuple(recorded))


def _auction_house(conn: Connection, game_version: str, key: str, groups: list[tuple[str, str]]) -> int:
    """The auction house an Auctionator key prices: one that already has the key as an alias, else the
    one of the uploader's characters it matches (named as the characters' realm), else parsed from the
    key. The alias comes first so a realm never splits into two auction houses."""
    known = prices.find_auction_house_by_key(conn, game_version, key)
    if known is not None:
        return known
    for realm, faction in groups:
        if service.match_auctionator_realm([key], realm, faction) == key:
            return prices.auctionator_auction_house(conn, game_version, key, realm, faction)
    return prices.auction_house_for_auctionator_key(conn, game_version, key)


def _name(conn: Connection, auction_house_id: int) -> tuple[str, str]:
    t = schema.auction_houses
    row = conn.execute(select(t.c.realm, t.c.faction).where(t.c.id == auction_house_id)).one()
    return str(row.realm), str(row.faction)


# --- history ---------------------------------------------------------------------------------------
def record_upload(
    conn: Connection,
    user_uid: str,
    game_version: str,
    kind: str,
    via: str,
    size: int,
    outcome: str,
    detail: str,
    *,
    now: datetime | None = None,
) -> None:
    conn.execute(
        schema.uploads.insert().values(
            user_uid=user_uid,
            game_version=game_version,
            kind=kind,
            via=via,
            size=size,
            received_at=now or db.utcnow(),
            outcome=outcome,
            detail=detail[:1000],
        )
    )


def check_rate(conn: Connection, user_uid: str, *, now: datetime | None = None) -> None:
    """RateLimited if the user has uploaded RATE_LIMIT files within the past hour."""
    t = schema.uploads
    since = (now or db.utcnow()) - timedelta(hours=1)
    count = conn.execute(
        select(func.count()).where(t.c.user_uid == user_uid, t.c.received_at > since)
    ).scalar_one()
    if count >= RATE_LIMIT:
        raise RateLimited


def _recent(conn: Connection, where: ColumnElement[bool], limit: int) -> list[UploadRow]:
    t = schema.uploads
    rows = conn.execute(
        select(
            t.c.id,
            t.c.game_version,
            t.c.kind,
            t.c.via,
            t.c.size,
            t.c.received_at,
            t.c.outcome,
            t.c.detail,
            t.c.user_uid,
        )
        .where(where)
        .order_by(t.c.received_at.desc(), t.c.id.desc())
        .limit(limit)
    )
    return [UploadRow(r[0], r[1], r[2], r[3], r[4], db.utc(r[5]), r[6], r[7], r[8]) for r in rows]


def recent(conn: Connection, user_uid: str, limit: int = 20) -> list[UploadRow]:
    """The user's newest uploads first."""
    return _recent(conn, schema.uploads.c.user_uid == user_uid, limit)


@dataclass(frozen=True)
class ImportStatus:
    """Where a user's characters of one game version came from, from their upload history."""

    imported_at: datetime | None  # the newest accepted Alt Army upload: when the characters were gathered
    imported_via: str | None  # how it came: browser | watcher | paste
    auto_import_at: (
        datetime | None
    )  # the newest accepted upload (either kind) the watcher or Alt Army Sync sent


def import_status(conn: Connection, user_uid: str, game_version: str) -> ImportStatus:
    t = schema.uploads
    mine = (t.c.user_uid == user_uid) & (t.c.game_version == game_version) & (t.c.outcome == "accepted")
    last = conn.execute(
        select(t.c.received_at, t.c.via)
        .where(mine, t.c.kind == "altarmy")
        .order_by(t.c.received_at.desc(), t.c.id.desc())
        .limit(1)
    ).first()
    auto: datetime | None = conn.execute(
        select(func.max(t.c.received_at)).where(mine, t.c.via == "watcher")
    ).scalar_one()
    return ImportStatus(
        imported_at=None if last is None else db.utc(last[0]),
        imported_via=None if last is None else last[1],
        auto_import_at=None if auto is None else db.utc(auto),
    )


def recent_all(conn: Connection, game_version: str, limit: int = 50) -> list[UploadRow]:
    """Every user's newest uploads of `game_version` first (the Admin page)."""
    return _recent(conn, schema.uploads.c.game_version == game_version, limit)


def stats(conn: Connection, game_version: str, now: datetime | None = None) -> UploadStats:
    """How many uploads of `game_version` were accepted and rejected in the last day and week, and by how
    many users."""
    t = schema.uploads
    now = db.utc(now or db.utcnow())
    day, week = now - timedelta(days=1), now - timedelta(days=7)

    def count(outcome: str, since: datetime) -> ColumnElement[int]:
        return func.coalesce(
            func.sum(case(((t.c.outcome == outcome) & (t.c.received_at >= since), 1), else_=0)), 0
        )

    row = conn.execute(
        select(
            count("accepted", day),
            count("rejected", day),
            count("accepted", week),
            count("rejected", week),
            func.count(func.distinct(t.c.user_uid)),
        ).where(t.c.game_version == game_version, t.c.received_at >= week)
    ).one()
    return UploadStats(*(int(v) for v in row))
