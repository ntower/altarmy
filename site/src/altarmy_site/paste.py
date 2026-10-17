"""Decode the Alt Army addon's paste export: characters, professions and learned recipes as one string,
pasted on the main page or the Upload page instead of uploading AltArmy_TBC.lua (no /reload needed).

The addon (`AltArmy_TBC/Data/ProfitExport.lua`) writes "AAX1:" plus LibDeflate's printable encoding of raw
DEFLATE of these lines:

    V|2|<interface>|<build>[|<account id>]        the client, so the export says which game it is from,
                                                  and the WoW account (newer addons; see `altarmy`)
    C|<realm>|<name>|<faction>|<CLASS_FILE>|<level>|<guid>
    P|<profession>|<rank>|<maxRank>|<recipe ids>  belongs to the C line before it; ids comma-separated
    T|<spell id>|<rank>                           a Legacy talent (WoW: Forever) of the C line before it
    R|<faction id>|<standing>                     its standing (1 Hated .. 8 Exalted) with a city faction

Recipe ids are craft spell ids with aliases already resolved, as `altarmy.parse_characters` reads them.
Talents are the addon's `legacyTalents.spells` (see `talents` for the ones that change profits).
Reputations are the addon's `Reputations` for the city factions (`reputation.CITY_FACTIONS`: they discount
vendor prices); a line for any other faction is passed over, and older addons write none.
The name is the full name and the GUID `UnitGUID("player")`, empty for characters the addon saved before it
stored GUIDs. Format v1, which older addons still write, has no GUID; addon 2.1.3 (which keys characters by
GUID) wrote the GUID as the name there, which is refused.
The string is untrusted: anything wrong raises ValueError (the API's 400).
"""

from __future__ import annotations

import re
import zlib
from dataclasses import dataclass

from . import versions
from .altarmy import Character, Profession, account_id
from .reputation import EXALTED, HATED, city_standings

PREFIX = "AAX1:"
# Fields of a C line (with the "C") per format version.
CHARACTER_FIELDS = {"1": 6, "2": 7}
MAX_BYTES = 32 * 2**20  # decompressed, as for uploaded files
_GUID = re.compile(r"Player-\d+-[0-9A-Fa-f]+")  # UnitGUID("player")

# LibDeflate's EncodeForPrint alphabet: 6 bits per character, little-endian.
_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
_VALUE = {c: i for i, c in enumerate(_ALPHABET)}


@dataclass(frozen=True)
class Export:
    interface: int  # the client's interface number, e.g. 20506
    build: str  # e.g. 2.5.6.69795
    characters: list[Character]  # sorted by realm then name
    account_id: str | None = None  # the WoW account the export is from (None from older addons)

    @property
    def game_version(self) -> str | None:
        """The game version whose client made the export; None for a client this app doesn't serve."""
        return next((v.key for v in versions.VERSIONS.values() if v.interface == self.interface), None)


def encode_for_print(data: bytes) -> str:
    """LibDeflate:EncodeForPrint (for tests and tools; the addon does the encoding)."""
    out = []
    i = 0
    while i + 3 <= len(data):
        n = data[i] | data[i + 1] << 8 | data[i + 2] << 16
        out.append("".join(_ALPHABET[n >> s & 63] for s in (0, 6, 12, 18)))
        i += 3
    n, bits = 0, 0
    for b in data[i:]:
        n |= b << bits
        bits += 8
    while bits > 0:
        out.append(_ALPHABET[n & 63])
        n >>= 6
        bits -= 6
    return "".join(out)


def decode_for_print(text: str) -> bytes:
    """LibDeflate:DecodeForPrint; ValueError on a character it can't have produced."""
    try:
        values = [_VALUE[c] for c in text]
    except KeyError as e:
        raise ValueError(f"unexpected character {e.args[0]!r} in the export") from None
    out = bytearray()
    whole = len(values) - len(values) % 4
    for i in range(0, whole, 4):
        n = values[i] | values[i + 1] << 6 | values[i + 2] << 12 | values[i + 3] << 18
        out += bytes((n & 255, n >> 8 & 255, n >> 16 & 255))
    n, bits = 0, 0
    for v in values[whole:]:
        n |= v << bits
        bits += 6
    while bits >= 8:
        out.append(n & 255)
        n >>= 8
        bits -= 8
    return bytes(out)


def decode(text: str, max_bytes: int = MAX_BYTES) -> Export:
    """The export in `text` (surrounding and embedded whitespace ignored)."""
    text = "".join(text.split())
    if not text.startswith(PREFIX):
        raise ValueError(
            "not an Alt Army export: copy the whole string the addon shows (it starts with AAX1:)"
        )
    raw = decode_for_print(text[len(PREFIX) :])
    inflate = zlib.decompressobj(-15)
    try:
        body = inflate.decompress(raw, max_bytes + 1)
    except zlib.error as e:
        raise ValueError(f"the export is damaged ({e}): copy it again") from None
    if len(body) > max_bytes:
        raise ValueError("the export is too large")
    if not inflate.eof:
        raise ValueError("the export is cut short: copy the whole string again")
    try:
        lines = body.decode("utf-8").split("\n")
    except UnicodeDecodeError:
        raise ValueError("the export is damaged: copy it again") from None
    return _parse(lines)


def _parse(lines: list[str]) -> Export:
    head = lines[0].split("|")
    if len(head) not in (4, 5) or head[0] != "V":
        raise ValueError("the export has no version line")
    character_fields = CHARACTER_FIELDS.get(head[1])
    if character_fields is None:
        raise ValueError(f"export format {head[1]!r} is not supported: update the site or the addon")
    interface = _int(head[2], "interface")
    chars: list[Character] = []
    current: tuple[list[str], list[Profession], dict[int, int], list[tuple[int, int]]] | None = None
    for line in lines[1:]:
        fields = line.split("|")
        if fields[0] == "C" and len(fields) == character_fields:
            if current is not None:
                chars.append(_character(*current))
            current = ((fields[1:] + [""])[:6], [], {}, [])
        elif fields[0] == "P" and len(fields) == 5:
            if current is None:
                raise ValueError("the export lists a profession before any character")
            name, rank, max_rank, ids = fields[1:]
            recipe_ids = frozenset(_int(i, "recipe id") for i in ids.split(",") if i)
            current[1].append(Profession(name, _int(rank, "rank"), _int(max_rank, "max rank"), recipe_ids))
        elif fields[0] == "T" and len(fields) == 3:
            if current is None:
                raise ValueError("the export lists a talent before any character")
            talent_rank = _int(fields[2], "talent rank")
            if talent_rank > 0:
                current[2][_int(fields[1], "talent")] = talent_rank
        elif fields[0] == "R" and len(fields) == 3:
            if current is None:
                raise ValueError("the export lists a reputation before any character")
            standing = _int(fields[2], "standing")
            if not HATED <= standing <= EXALTED:
                raise ValueError(f"bad standing {fields[2]!r} in the export")
            current[3].append((_int(fields[1], "faction"), standing))
        elif line.strip():
            raise ValueError(f"unexpected line in the export: {line[:40]!r}")
    if current is not None:
        chars.append(_character(*current))
    account = account_id(head[4]) if len(head) == 5 else None
    return Export(interface, head[3], sorted(chars, key=lambda c: (c.realm, c.name)), account)


def _character(
    fields: list[str],
    professions: list[Profession],
    talents: dict[int, int],
    reputations: list[tuple[int, int]],
) -> Character:
    realm, name, faction, class_file, level, guid = fields
    if _GUID.fullmatch(name):
        # Addon 2.1.3 keys characters by GUID, and its v1 export wrote the key instead of the name.
        raise ValueError(
            "the export names characters by their id: update the Alt Army addon and export again"
        )
    return Character(
        realm,
        name,
        faction,
        class_file,
        _int(level, "level"),
        tuple(sorted(professions, key=lambda p: p.name)),
        tuple(sorted(talents.items())),
        guid,
        city_standings(reputations),
    )


def _int(text: str, what: str) -> int:
    if not text.isascii() or not text.isdigit() or len(text) > 12:
        raise ValueError(f"bad {what} {text[:20]!r} in the export")
    return int(text)
