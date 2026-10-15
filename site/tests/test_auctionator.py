import contextlib
import gzip
import random
import zlib
from datetime import date

import pytest

from altarmy_site import altarmy, auctionator, book, paste, snapshots
from altarmy_site.auctionator import DayStats, ItemPrice

from .addon_fixtures import AUCTION_BOOK, PROFIT_EXPORT
from .snapshot_fixtures import auction, body
from .test_altarmy import ALTARMY_SV

FOREVER = "forever"  # (conftest imports this module, so it can't import conftest's)


def _cbor_head(major: int, n: int) -> bytes:
    if n < 24:
        return bytes([major << 5 | n])
    if n < 0x100:
        return bytes([major << 5 | 24, n])
    if n < 0x10000:
        return bytes([major << 5 | 25]) + n.to_bytes(2, "big")
    return bytes([major << 5 | 26]) + n.to_bytes(4, "big")


def _cbor(v: object) -> bytes:
    """Just enough CBOR encoding to mimic Auctionator (keys are byte strings, like the addon writes)."""
    if isinstance(v, int):
        return _cbor_head(0, v)
    if isinstance(v, str):
        b = v.encode()
        return _cbor_head(2, len(b)) + b
    if isinstance(v, list):
        return _cbor_head(4, len(v)) + b"".join(_cbor(x) for x in v)
    assert isinstance(v, dict)
    return _cbor_head(5, len(v)) + b"".join(_cbor(k) + _cbor(x) for k, x in v.items())


def _lua_escape(b: bytes) -> bytes:
    out = bytearray()
    for c in b:
        if c == 0x22:
            out += b'\\"'
        elif c == 0x5C:
            out += b"\\\\"
        elif c == 0x0A:
            out += b"\\n"
        elif c == 0x0D:
            out += b"\\r"
        elif c == 0:
            out += b"\\000"
        else:
            out.append(c)
    return bytes(out)


def _saved_variables(realms: dict[str, dict[str, object]]) -> bytes:
    lines = [b"", b"AUCTIONATOR_CONFIG = {", b'["x"] = "y",', b"}", b"AUCTIONATOR_PRICE_DATABASE = {"]
    lines.append(b'["__dbversion"] = 8,')
    for realm, data in realms.items():
        lines.append(b'["' + realm.encode() + b'"] = "' + _lua_escape(_cbor(data)) + b'",')
    lines += [b"}", b"AUCTIONATOR_POSTING_HISTORY = {", b"}", b""]
    return b"\n".join(lines)


def _entry(price: int) -> dict[str, object]:
    return {"a": {"2457": 3}, "l": [], "h": {"2457": price}, "m": price}


def test_parse_price_database_handles_escapes_and_key_kinds() -> None:
    realm = {
        "version": 1,
        "1": _entry(45),
        "2": _entry(0x0A0D),  # bytes that Lua escapes as \n and \r
        "3": _entry(0x2200),  # a quote and a NUL
        "g:4:0:0": _entry(300),  # gear keyed with item level: counts as item 4
        "g:4:60:0": _entry(250),  # cheapest variant wins
        "p:39": _entry(999),  # battle pet: ignored
    }
    parsed = auctionator.parse_price_database(
        _saved_variables({"Realm A": realm, "Realm B": {"1": _entry(7)}})
    )
    buyouts = {realm: auctionator.min_buyouts(items) for realm, items in parsed.items()}
    assert buyouts == {"Realm A": {1: 45, 2: 0x0A0D, 3: 0x2200, 4: 250}, "Realm B": {1: 7}}


def test_parse_keeps_the_daily_history() -> None:
    realm: dict[str, object] = {
        # day 2457 = 2026-09-23: seen at 900 then 700 (l only holds a low below h); 2458: once, 800
        "1": {"a": {"2457": 12, "2458": 5}, "l": {"2457": 700}, "h": {"2457": 900, "2458": 800}, "m": 800},
        "2": {"l": [], "h": {"1866": 40}, "m": 40},  # no "a": databases from before December 2020
        "3": {"a": [], "l": [], "h": [], "m": 55},  # no history left (Auctionator prunes old days)
        # gear variants: cheapest m; per day the highest high, lowest low and the summed availability
        "g:4:0:0": {"a": {"2458": 1}, "l": [], "h": {"2458": 300}, "m": 300},
        "g:4:60:0": {"a": {"2458": 2}, "l": {"2458": 200}, "h": {"2458": 260}, "m": 250},
    }
    got = auctionator.parse_price_database(_saved_variables({"R": realm}))["R"]
    assert got[1] == ItemPrice(
        800, {date(2026, 9, 23): DayStats(900, 700, 12), date(2026, 9, 24): DayStats(800, 800, 5)}
    )
    assert got[1].last_seen == date(2026, 9, 24)
    assert got[2] == ItemPrice(40, {date(2025, 2, 9): DayStats(40, 40, None)})
    assert (got[3], got[3].last_seen) == (ItemPrice(55), None)
    assert got[4] == ItemPrice(250, {date(2026, 9, 24): DayStats(300, 200, 3)})


def test_parse_rejects_file_without_price_database() -> None:
    with pytest.raises(ValueError, match="AUCTIONATOR_PRICE_DATABASE"):
        auctionator.parse_price_database(b"AUCTIONATOR_CONFIG = {\n}\n")


@pytest.mark.parametrize(
    "blob",
    [
        bytes([0x81]) * 5000 + b"\x00",  # arrays nested 5000 deep
        _cbor({"1": _entry(5)})[:-3],  # truncated
        bytes([0xA1, 0x01, 0xF8]),  # a simple value Auctionator never writes
    ],
    ids=["deep", "truncated", "unknown-simple"],
)
def test_malformed_cbor_is_a_value_error(blob: bytes) -> None:
    text = b'AUCTIONATOR_PRICE_DATABASE = {\n["Realm"] = "' + _lua_escape(blob) + b'",\n}\n'
    with pytest.raises(ValueError):
        auctionator.parse_price_database(text)


def test_truncated_lua_table_is_a_value_error() -> None:
    with pytest.raises(ValueError):
        auctionator.parse_price_database(b'AUCTIONATOR_PRICE_DATABASE = {\n["Realm')


def _mangled(seeds: list[bytes], rng: random.Random) -> bytes:
    b = bytearray(rng.choice(seeds))
    if rng.random() < 0.4:
        return bytes(b[: rng.randrange(len(b))])
    for _ in range(rng.randrange(1, 8)):
        b[rng.randrange(len(b))] = rng.randrange(256)
    return bytes(b)


def test_mangled_files_only_raise_value_error() -> None:
    """Uploads are untrusted: whatever the bytes, parsing either succeeds or raises ValueError (a 400)."""
    rng = random.Random(1)
    prices = [_saved_variables({"R": {"1": _entry(5), "g:2:3": _entry(7)}, "S": {"4": {"m": 1}}})]
    export = PROFIT_EXPORT.read_bytes().strip()
    export_lines = b"V|2|20506|x\nC|R|N|Horde|MAGE|70|Player-1-A\nP|Tailoring|375|375|1,2,3\nC|R|M||PRIEST|1|"
    scans = AUCTION_BOOK.read_bytes()
    feed = body(auction(1, 2589, unit=50, qty=20, bid=800), auction(2, 2589, bid=10, left="SHORT"))
    state = snapshots.encode_state(
        snapshots.diff(
            None,
            snapshots.parse_blizzard(feed, t=1, realm="R", faction="Horde"),
            {"LONG": (0, 9), "SHORT": (0, 1)},
            9,
        ).state
    )
    for _ in range(1500):
        with contextlib.suppress(ValueError):
            book.read(_mangled([scans], rng))
        with contextlib.suppress(ValueError):
            auctionator.parse_price_database(_mangled(prices, rng))
        with contextlib.suppress(ValueError):
            altarmy.parse_characters(_mangled([ALTARMY_SV], rng))
        # the paste export: mangled as pasted, and mangled inside the compression
        with contextlib.suppress(ValueError):
            paste.decode(_mangled([export], rng).decode("latin-1"))
        with contextlib.suppress(ValueError):
            paste.decode(_deflated(_mangled([export_lines], rng)))
        # the hourly auction snapshots, and the auction state stored between them
        with contextlib.suppress(ValueError):
            snapshots.parse_blizzard(_mangled([feed], rng), t=1, realm="R", faction="Horde")
        with contextlib.suppress(ValueError):
            snapshots.decode_state(_mangled([state], rng))
        with contextlib.suppress(ValueError):
            snapshots.decode_state(gzip.compress(_mangled([gzip.decompress(state)], rng)))


def _deflated(lines: bytes) -> str:
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return paste.PREFIX + paste.encode_for_print(c.compress(lines) + c.flush())
