"""Alt Army's paste export: the string the addon shows, decoded to characters.

The addon's golden addon/spec/fixtures/profit_export_v2.txt (made by AltArmy_TBC/Data/ProfitExport.lua) is
read straight from the addon, so the two sides can't drift apart unnoticed. The site's own
tests/fixtures/altarmy_export_v1.txt is the golden string of format v1, which older addons still write.
"""

import zlib
from pathlib import Path

import pytest

from altarmy_site import paste
from altarmy_site.altarmy import Character, Profession

from .addon_fixtures import PROFIT_EXPORT

GOLDEN = PROFIT_EXPORT.read_text(encoding="utf-8")
GOLDEN_V1 = (Path(__file__).parent / "fixtures" / "altarmy_export_v1.txt").read_text(encoding="utf-8")
FRELL_PROFESSIONS = (
    Profession("Cooking", 1, 75, frozenset()),
    Profession("Enchanting", 300, 375, frozenset({7418, 7420})),
    Profession("Tailoring", 375, 375, frozenset({26745, 26746})),
)
FRELL_TALENTS = ((1225457, 3), (1225459, 2))


def encoded(lines: str) -> str:
    """What the addon would show for `lines` (raw DEFLATE, LibDeflate's printable encoding)."""
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return paste.PREFIX + paste.encode_for_print(c.compress(lines.encode()) + c.flush())


def test_decodes_the_addons_golden_export() -> None:
    got = paste.decode(GOLDEN)
    assert (got.interface, got.build) == (20506, "2.5.6.69795")
    assert got.account_id == "0a1b2c3d4e5f6789"
    assert got.characters == [
        Character("Classic Beta PvE", "Tailor Guy", "", "PRIEST", 20, ()),
        Character("Dreamscythe", "Alchemist", "Horde", "ROGUE", 12, ()),
        Character(
            "Dreamscythe",
            "Frell Ofelements",
            "Horde",
            "MAGE",
            70,
            FRELL_PROFESSIONS,
            FRELL_TALENTS,
            guid="Player-5826-0A1B2C3D",
            reputations=((76, 6), (530, 5)),  # Honored with Orgrimmar, Friendly with the Darkspear Trolls
        ),
    ]


def test_decodes_format_v1_from_older_addons() -> None:
    got = paste.decode(GOLDEN_V1)
    assert got.characters == [
        Character("Classic Beta PvE", "Tailor Guy", "", "PRIEST", 20, ()),
        Character("Dreamscythe", "Frell", "Horde", "MAGE", 70, FRELL_PROFESSIONS, FRELL_TALENTS),
    ]


def test_print_encoding_round_trips() -> None:
    for data in (b"", b"a", b"ab", b"abc", bytes(range(256))):
        assert paste.decode_for_print(paste.encode_for_print(data)) == data


def test_surrounding_whitespace_is_ignored() -> None:
    assert paste.decode(f"  \n{GOLDEN}\r\n ").interface == 20506


def test_version_of_the_client() -> None:
    assert paste.decode(GOLDEN).game_version == "tbc"
    assert paste.decode(encoded("V|1|16001|1.60.1")).game_version == "forever"
    assert paste.decode(encoded("V|1|30400|3.4.0")).game_version is None


@pytest.mark.parametrize(
    "text",
    [
        "",
        "hello",
        "AAX2:abc",  # a newer format
        "AAX1:***",  # not the print alphabet
        GOLDEN[:-12],  # truncated
        "AAX1:" + "a" * 40,  # not DEFLATE
    ],
)
def test_bad_strings_raise_value_error(text: str) -> None:
    with pytest.raises(ValueError):
        paste.decode(text)


@pytest.mark.parametrize(
    "lines",
    [
        "C|R|N|Horde|MAGE|1",  # no version line
        "V|3|20506|x",  # unknown export version
        "V|2|20506|x\nC|R|N|Horde|MAGE|1",  # v2 without the GUID
        "V|1|20506|x\nC|R|N|Horde|MAGE|1|Player-1-A",  # v1 with one
        "V|1|20506|x\nP|Tailoring|1|75|1",  # a profession before any character
        "V|1|20506|x\nC|R|N|Horde|MAGE|lots",
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nP|Tailoring|1|75|1,x",
        "V|1|20506|x\nZ|what",
        "V|1|20506|x\nT|1225457|3",  # a talent before any character
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nT|1225457|x",
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nT|1225457",
        "V|1|20506|x\nR|76|6",  # a reputation before any character
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nR|76|x",
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nR|76",
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nR|76|9",  # no such standing
        "V|1|20506|x\nC|R|N|Horde|MAGE|1\nR|76|0",
    ],
)
def test_malformed_lines_raise_value_error(lines: str) -> None:
    with pytest.raises(ValueError):
        paste.decode(encoded(lines))


def test_the_version_line_may_name_the_account() -> None:
    assert paste.decode(encoded("V|2|16001|x\nC|R|A|Horde|MAGE|30|")).account_id is None
    assert paste.decode(encoded("V|2|16001|x|0a1b2c3d4e5f6789\nC|R|A|Horde|MAGE|30|")).account_id == (
        "0a1b2c3d4e5f6789"
    )
    assert paste.decode(encoded("V|2|16001|x|not ok\nC|R|A|Horde|MAGE|30|")).account_id is None
    with pytest.raises(ValueError):
        paste.decode(encoded("V|2|16001|x|a|b\nC|R|A|Horde|MAGE|30|"))


def test_talents_belong_to_the_character_before_them() -> None:
    got = paste.decode(
        encoded("V|1|16001|x\nC|R|A|Horde|MAGE|30\nT|1225459|1\nT|1225457|5\nT|7|0\nC|R|B|Horde|MAGE|1")
    )
    assert [c.talents for c in got.characters] == [((1225457, 5), (1225459, 1)), ()]


def test_reputations_belong_to_the_character_before_them() -> None:
    got = paste.decode(
        encoded("V|2|16001|x\nC|R|A|Horde|MAGE|30|\nR|530|8\nR|76|6\nR|909|7\nC|R|B|Horde|MAGE|1|")
    )
    # by faction id; a faction that isn't a city's (the Darkmoon Faire) is passed over
    assert [c.reputations for c in got.characters] == [((76, 6), (530, 8)), ()]


def test_an_export_naming_characters_by_guid_asks_for_a_newer_addon() -> None:
    # Addon 2.1.3 keys characters by GUID and its v1 export wrote that key where the name belongs.
    guid = encoded("V|1|16001|x\nC|R|Player-5826-0A1B2C3D|Horde|MAGE|30")
    with pytest.raises(ValueError, match="update the Alt Army addon"):
        paste.decode(guid)


def test_size_is_capped() -> None:
    huge = "V|1|20506|x\n" + "C|R|N|Horde|MAGE|1\n" * 20_000
    with pytest.raises(ValueError, match="too large"):
        paste.decode(encoded(huge), max_bytes=100_000)
