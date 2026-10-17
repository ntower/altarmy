"""Uploaded addon files: characters replace the uploader's, scans pool per auction house."""

import gzip
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import Connection, select

from altarmy_site import book, prices, schema, service, store, uploads, users
from altarmy_site.auth import User

from .addon_fixtures import PROFIT_EXPORT
from .conftest import FOREVER, ME, book_scan, saved_book
from .test_altarmy import ALTARMY_SV
from .test_auctionator import _entry, _saved_variables

NOW = datetime(2026, 9, 24, 20, 0, tzinfo=UTC)
OTHER = "other-user"
PASTE = PROFIT_EXPORT.read_text(encoding="utf-8")


@pytest.fixture
def other(conn: Connection) -> str:
    users.ensure_user(conn, User(OTHER, "free"))
    return OTHER


def scan(realms: dict[str, dict[str, object]]) -> bytes:
    return _saved_variables(realms)


def test_altarmy_upload_replaces_only_the_uploaders_characters(conn: Connection, other: str) -> None:
    store.save_characters(conn, other, FOREVER, store.load_characters(conn, ME, FOREVER))  # nothing yet
    got = uploads.ingest(conn, ME, FOREVER, "altarmy", ALTARMY_SV, None, now=NOW)
    assert got.characters == 4
    assert got.groups == (
        ("Classic Beta PvE", "Alliance", 1),
        ("Classic Beta PvE", "Horde", 1),
        ("Dreamscythe", "Horde", 2),
    )
    assert "4 characters" in got.detail
    assert store.count_characters(conn, ME, FOREVER) == 4
    assert store.count_characters(conn, other, FOREVER) == 0
    assert service.data_version(conn, ME, FOREVER) == 1


def of_account(account: str, data: bytes = ALTARMY_SV) -> bytes:
    return data.replace(
        b"AltArmyTBC_Data = {\n", f'AltArmyTBC_Data = {{\n["accountId"] = "{account}",\n'.encode()
    )


def test_each_wow_accounts_file_keeps_the_others_characters(conn: Connection) -> None:
    uploads.ingest(conn, ME, FOREVER, "altarmy", of_account("aaaa"), None, now=NOW)
    other = b'AltArmyTBC_Data = {\n["Characters"] = {\n["Dreamscythe"] = {\n["Player-9-B"] = {\n'
    other += (
        b'["name"] = "Second Box",\n["faction"] = "Horde",\n["classFile"] = "WARRIOR",\n["level"] = 30,\n'
    )
    other += b"},\n},\n},\n}\n"
    got = uploads.ingest(conn, ME, FOREVER, "altarmy", of_account("bbbb", other), None, now=NOW)
    assert got.characters == 1
    assert store.count_characters(conn, ME, FOREVER) == 5  # both accounts' characters
    uploads.ingest(conn, ME, FOREVER, "altarmy", of_account("aaaa"), None, now=NOW)  # again: replaces its own
    assert store.count_characters(conn, ME, FOREVER) == 5


def with_scans(*scans: book.Scan) -> bytes:
    """An AltArmy_TBC.lua holding the usual characters and these auction house scans."""
    return ALTARMY_SV + saved_book(*scans)


def test_an_alt_army_upload_records_the_scans_it_carries(conn: Connection) -> None:
    first = book_scan({1: [(20, 5)], 2: [(100, 1)]}, NOW - timedelta(minutes=40))
    second = book_scan({1: [(15, 2), (20, 5)]}, NOW - timedelta(minutes=20))
    other = book_scan({1: [(9, 1)]}, NOW - timedelta(minutes=30), "Dreamscythe", "Alliance")
    got = uploads.ingest(conn, ME, FOREVER, "altarmy", with_scans(first, other, second), None, now=NOW)
    assert got.characters == 4
    assert [(r.key, r.realm, r.faction, r.items, r.moved) for r in got.realms] == [
        ("Classic Beta PvE Horde", "Classic Beta PvE", "Horde", 2, 2),
        ("Dreamscythe Alliance", "Dreamscythe", "Alliance", 1, 1),
        ("Classic Beta PvE Horde", "Classic Beta PvE", "Horde", 1, 2),  # linen cheaper, thread gone
    ]
    assert got.detail.startswith("4 characters on ")
    assert got.detail.endswith(
        "Auction house scans: Classic Beta PvE Horde: 2 prices, 2 changed; "
        "Dreamscythe Alliance: 1 prices, 1 changed; Classic Beta PvE Horde: 1 prices, 2 changed"
    )
    horde = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    assert horde is not None and got.moved_auction_house_ids == {horde, got.realms[1].auction_house_id}
    assert prices.load_buy_and_sell(conn, horde, first_party=True)[0] == {1: 15}
    snap = schema.price_snapshots
    rows = conn.execute(select(snap.c.source, snap.c.uploader_uid, snap.c.scanned_at)).all()
    assert {(r.source, r.uploader_uid) for r in rows} == {("altarmy", ME)}
    assert service.data_version(conn, ME, FOREVER) == 1


def test_scans_already_recorded_are_passed_over(conn: Connection, other: str) -> None:
    first = book_scan({1: [(20, 5)]}, NOW - timedelta(minutes=40))
    uploads.ingest(conn, ME, FOREVER, "altarmy", with_scans(first), None, now=NOW)
    ah = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    version = prices.price_version(conn, ah)
    again = uploads.ingest(conn, ME, FOREVER, "altarmy", with_scans(first), None, now=NOW)
    assert again.realms == () and again.detail.endswith("(Horde): 2")  # only the characters
    # another uploader's older scan of the same house changes nothing either
    older = book_scan({1: [(5, 5)]}, NOW - timedelta(minutes=50))
    assert uploads.ingest(conn, other, FOREVER, "altarmy", with_scans(older), None, now=NOW).realms == ()
    newer = book_scan({1: [(30, 5)]}, NOW - timedelta(minutes=10))
    (realm,) = uploads.ingest(conn, other, FOREVER, "altarmy", with_scans(first, newer), None, now=NOW).realms
    assert realm.moved == 1
    assert prices.load_current(conn, ah) == {1: 30}
    assert prices.price_version(conn, ah) == (version or 0) + 1
    assert len(conn.execute(select(schema.price_snapshots.c.id)).all()) == 2


def test_a_scans_time_is_its_own_and_never_the_future(conn: Connection) -> None:
    ahead = book_scan({1: [(20, 5)]}, NOW + timedelta(hours=3))
    uploads.ingest(conn, ME, FOREVER, "altarmy", with_scans(ahead), None, now=NOW)
    at: datetime = conn.execute(select(schema.price_snapshots.c.scanned_at)).scalar_one()
    assert at.replace(tzinfo=UTC) == NOW


def test_tbc_ignores_the_scans_and_forever_refuses_auctionator(conn: Connection) -> None:
    got = uploads.ingest(
        conn, ME, "tbc", "altarmy", with_scans(book_scan({1: [(20, 5)]}, NOW)), None, now=NOW
    )
    assert got.realms == () and got.characters == 4
    assert conn.execute(select(schema.price_snapshots.c.id)).all() == []
    data = scan({"Dreamscythe Horde": {"1": _entry(5)}})
    with pytest.raises(ValueError, match="come from Alt Army's own auction house scan"):
        uploads.ingest(conn, ME, FOREVER, "auctionator", data, None, now=NOW)
    assert (
        uploads.ingest(conn, ME, "tbc", "auctionator", data, None, now=NOW).realms[0].realm == "Dreamscythe"
    )


def test_a_scan_far_off_recent_prices_is_quarantined_and_costs_trust(conn: Connection, other: str) -> None:
    usual = book_scan({i: [(100, 10)] for i in range(1, 31)}, NOW - timedelta(hours=5))
    uploads.ingest(conn, ME, FOREVER, "altarmy", with_scans(usual), None, now=NOW)
    ah = prices.find_auction_house(conn, FOREVER, "Classic Beta PvE", "Horde")
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=100, scans_7d=5))  # as the merge job would
    wild = book_scan({i: [(10_000, 10)] for i in range(1, 31)}, NOW - timedelta(hours=1))
    got = uploads.ingest(conn, other, FOREVER, "altarmy", with_scans(wild), None, now=NOW)
    (realm,) = got.realms
    assert realm.quarantined and realm.moved == 0
    assert got.detail.endswith(
        "Classic Beta PvE Horde: 30 prices not used: they differ widely from recent scans"
    )
    assert set(prices.load_current(conn, ah).values()) == {100}
    assert users.trust(conn, other) == 0.5
    assert got.moved_auction_house_ids == frozenset()


def test_a_malformed_book_refuses_the_file(conn: Connection) -> None:
    bad = ALTARMY_SV + b'\nAltArmyTBC_AuctionBook = {\n["scans"] = 5,\n}\n'
    with pytest.raises(ValueError, match="auction house scans"):
        uploads.ingest(conn, ME, FOREVER, "altarmy", bad, None, now=NOW)


def test_uploads_pool_and_the_newest_scan_wins(conn: Connection, other: str) -> None:
    def latest(price: int) -> bytes:  # no day history: seen at the file's scan time
        return scan({"Dreamscythe Horde": {"1": {"m": price}}})

    uploads.ingest(conn, ME, "tbc", "auctionator", latest(5), NOW - timedelta(hours=2), now=NOW)
    uploads.ingest(conn, other, "tbc", "auctionator", latest(9), NOW - timedelta(hours=1), now=NOW)
    ah = prices.find_auction_house(conn, "tbc", "Dreamscythe", "Horde")
    assert prices.load_current(conn, ah) == {1: 9}  # another user's newer scan
    uploads.ingest(conn, ME, "tbc", "auctionator", latest(7), NOW - timedelta(hours=3), now=NOW)
    assert prices.load_current(conn, ah) == {1: 9}  # an older file doesn't win


def test_a_wildly_off_scan_is_quarantined_and_costs_trust(conn: Connection, other: str) -> None:
    def latest(price: int) -> bytes:
        return scan({"Dreamscythe Horde": {str(i): {"m": price} for i in range(1, 31)}})

    uploads.ingest(conn, ME, "tbc", "auctionator", latest(100), NOW - timedelta(hours=2), now=NOW)
    ah = prices.find_auction_house(conn, "tbc", "Dreamscythe", "Horde")
    pc = schema.price_current
    conn.execute(pc.update().values(median_7d=100, scans_7d=5))  # as the merge job would

    got = uploads.ingest(conn, other, "tbc", "auctionator", latest(10_000), NOW - timedelta(hours=1), now=NOW)
    (realm,) = got.realms
    assert realm.quarantined and realm.moved == 0
    assert got.detail == "Dreamscythe Horde: 30 prices not used: they differ widely from recent scans"
    assert set(prices.load_current(conn, ah).values()) == {100}
    assert users.trust(conn, other) == 0.5

    got = uploads.ingest(conn, ME, "tbc", "auctionator", latest(110), NOW, now=NOW)
    assert not got.realms[0].quarantined
    assert users.trust(conn, ME) == 1.0  # capped


def test_trust_halves_on_quarantine_and_recovers(conn: Connection, other: str) -> None:
    assert users.trust(conn, other) == 1.0
    assert users.adjust_trust(conn, other, quarantined=True) == 0.5
    assert users.adjust_trust(conn, other, quarantined=True) == 0.25
    assert users.adjust_trust(conn, other, quarantined=False) == pytest.approx(0.35)
    assert users.trust(conn, "nobody") == 1.0


def test_a_pasted_export_replaces_the_characters(conn: Connection) -> None:
    got = uploads.ingest_paste(conn, ME, "tbc", PASTE)
    assert (got.kind, got.characters) == ("altarmy", 3)
    assert got.groups == (("Dreamscythe", "Horde", 2),)  # a character never scanned has no faction group
    assert [c.name for c in store.load_characters(conn, ME, "tbc")] == [
        "Tailor Guy",
        "Alchemist",
        "Frell Ofelements",
    ]
    assert service.data_version(conn, ME, "tbc") == 1


def test_a_pasted_export_of_the_other_game_is_refused(conn: Connection) -> None:
    with pytest.raises(ValueError, match="This is a TBC Anniversary export; this site serves WoW: Forever"):
        uploads.ingest_paste(conn, ME, FOREVER, PASTE)
    assert store.count_characters(conn, ME, FOREVER) == 0


def test_scan_time_is_clamped() -> None:
    assert uploads.scan_time(None, NOW) == NOW
    assert uploads.scan_time(NOW + timedelta(days=1), NOW) == NOW
    assert uploads.scan_time(NOW - timedelta(days=90), NOW) == NOW - uploads.SCAN_WINDOW
    assert uploads.scan_time(NOW - timedelta(hours=1), NOW) == NOW - timedelta(hours=1)


def test_bad_files_raise_value_error(conn: Connection) -> None:
    with pytest.raises(ValueError, match="AltArmyTBC_Data"):
        uploads.ingest(conn, ME, FOREVER, "altarmy", b"Foo = {}", None, now=NOW)
    with pytest.raises(ValueError, match="AUCTIONATOR_PRICE_DATABASE"):
        uploads.ingest(conn, ME, "tbc", "auctionator", ALTARMY_SV, None, now=NOW)


def test_history_and_rate_limit(conn: Connection) -> None:
    for i in range(uploads.RATE_LIMIT):
        uploads.check_rate(conn, ME, now=NOW)
        uploads.record_upload(conn, ME, FOREVER, "altarmy", "browser", 10, "accepted", f"#{i}", now=NOW)
    with pytest.raises(uploads.RateLimited):
        uploads.check_rate(conn, ME, now=NOW)
    uploads.check_rate(conn, ME, now=NOW + timedelta(hours=1, seconds=1))  # an hour later
    recent = uploads.recent(conn, ME)
    assert len(recent) == 20 and recent[0].detail.startswith("#")
    assert uploads.recent(conn, "local-nobody") == []


def test_import_status_from_the_upload_history(conn: Connection) -> None:
    assert uploads.import_status(conn, ME, FOREVER) == uploads.ImportStatus(None, None, None)
    earlier, later = NOW - timedelta(days=2), NOW - timedelta(hours=1)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "watcher", 10, "accepted", "", now=earlier)
    uploads.record_upload(conn, ME, FOREVER, "auctionator", "watcher", 10, "accepted", "", now=later)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "paste", 10, "accepted", "", now=later)
    uploads.record_upload(conn, ME, FOREVER, "altarmy", "browser", 10, "rejected", "bad", now=NOW)
    uploads.record_upload(conn, ME, "tbc", "altarmy", "watcher", 10, "accepted", "", now=NOW)
    users.ensure_user(conn, User("someone-else", "linked"))
    uploads.record_upload(conn, "someone-else", FOREVER, "altarmy", "watcher", 10, "accepted", "", now=NOW)
    status = uploads.import_status(conn, ME, FOREVER)
    # The characters came from the newest accepted Alt Army upload; the watcher sent a price scan later.
    assert status == uploads.ImportStatus(imported_at=later, imported_via="paste", auto_import_at=later)


def test_decompress_limits_the_size() -> None:
    assert uploads.decompress(gzip.compress(b"x" * 100), 1000) == b"x" * 100
    assert uploads.decompress(b"plain", 1000) == b"plain"
    with pytest.raises(uploads.TooLarge):
        uploads.decompress(gzip.compress(b"x" * 5000), 1000)
    with pytest.raises(uploads.TooLarge):
        uploads.decompress(b"y" * 5000, 1000)
    with pytest.raises(ValueError, match="gzip"):
        uploads.decompress(b"\x1f\x8b" + b"not gzip", 1000)


def test_every_users_uploads_and_their_counts(conn: Connection, other: str) -> None:
    def upload(uid: str, version: str, outcome: str, detail: str, days: int) -> None:
        when = NOW - timedelta(days=days)
        uploads.record_upload(conn, uid, version, "auctionator", "watcher", 10, outcome, detail, now=when)

    upload(ME, FOREVER, "accepted", "mine", 0)
    upload(other, FOREVER, "rejected", "bad", 6)
    upload(other, FOREVER, "accepted", "old", 8)
    upload(other, "tbc", "accepted", "tbc", 0)
    got = uploads.recent_all(conn, FOREVER)
    assert [(u.user_uid, u.detail) for u in got] == [(ME, "mine"), (other, "bad"), (other, "old")]
    assert uploads.recent_all(conn, FOREVER, limit=1)[0].detail == "mine"
    assert uploads.stats(conn, FOREVER, NOW) == uploads.UploadStats(1, 0, 1, 1, 2)
    assert uploads.stats(conn, "tbc", NOW + timedelta(days=30)) == uploads.UploadStats(0, 0, 0, 0, 0)
