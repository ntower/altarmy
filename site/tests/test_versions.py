"""Game versions: lookup, data files and addon folders."""

import re
from pathlib import Path

import pytest

from altarmy_site import engine, gamedata, versions, watch, wowfiles
from altarmy_site.engine import Item, Market, Recipe
from altarmy_site.versions import VERSIONS

from .addon_fixtures import ADDON_TOC, RECIPE_DATA


def test_get_and_build_versions() -> None:
    assert versions.get("tbc").wago_product == "wow_anniversary"
    assert versions.get("forever").wago_product == "wow_classic_beta"
    with pytest.raises(ValueError, match="forever, tbc"):
        versions.get("retail")
    assert versions.version_of_build("2.5.6.69795") == "tbc"
    assert versions.version_of_build("1.60.1.69977") == "forever"
    assert versions.version_of_build("") == "forever"


def test_addon_toc_lists_every_version_interface() -> None:
    """The addon's TOC loads in exactly the clients the site serves; a game patch moving one needs both."""
    lines = ADDON_TOC.read_text(encoding="utf-8").splitlines()
    interface = next(line for line in lines if line.startswith("## Interface:"))
    toc = {int(n) for n in interface.removeprefix("## Interface:").split(",")}
    assert toc == {v.interface for v in VERSIONS.values()}


def test_addon_recipe_data_was_made_from_the_pinned_builds() -> None:
    """The site loads and the addon ships the same build: game_data.py moves the pin and regenerates both."""
    pins = gamedata.read_pins()
    for key, path in RECIPE_DATA.items():
        built = re.search(r'^local BUILD = "([^"]+)"', path.read_text(encoding="utf-8"), re.MULTILINE)
        assert built is not None, path
        assert built.group(1) == pins[key].build, f"{path.name} is not at the pinned build"


def test_each_version_has_its_own_files() -> None:
    tbc, forever = VERSIONS["tbc"], VERSIONS["forever"]
    assert tbc.disenchant_csv == Path("data/tbc/disenchant.csv")
    assert forever.vendor_csv == Path("data/forever/vendor_items.csv")
    assert forever.cities_dir == Path("data/forever/cities")
    assert tbc.flavor_folders == ("_anniversary_",)
    assert forever.flavor_folders == ("_forever_", "_classic_beta_")
    assert (tbc.interface, forever.interface) == (20506, 16001)


def test_find_files_only_in_the_versions_flavor_folders(tmp_path: Path) -> None:
    found = {}
    for flavor in ("_anniversary_", "_classic_beta_"):
        sv = tmp_path / flavor / "WTF" / "Account" / "ME" / "SavedVariables"
        sv.mkdir(parents=True)
        (sv / "AltArmy_TBC.lua").write_text("")
        (sv / "Auctionator.lua").write_text("")
        found[flavor] = sv
    tbc = VERSIONS["tbc"].flavor_folders
    assert wowfiles.find_altarmy_files([tmp_path], tbc) == [found["_anniversary_"] / "AltArmy_TBC.lua"]
    assert wowfiles.find_auctionator_files([tmp_path], ("_classic_beta_",)) == [
        found["_classic_beta_"] / "Auctionator.lua"
    ]
    assert len(wowfiles.find_altarmy_files([tmp_path])) == 2  # no flavors: every install folder


def test_market_charges_the_versions_postage() -> None:
    items = {1: Item(1, "Linen Cloth", stack_size=20), 2: Item(2, "Bolt", sell_price=100)}
    bolt = Recipe(1, "Bolt", 2, 1, ((1, 45),), "Tailoring")
    assert Market(items, [bolt], {1: 1}).postage(1, 45) == 3 * engine.MAIL_POSTAGE  # three stacks
    assert Market(items, [bolt], {1: 1}, mail_postage=50).postage(1, 45) == 150


def test_a_character_trains_the_ranks_their_level_allows() -> None:
    forever = versions.VERSIONS["forever"]
    assert forever.trainable_cap(5) == 75  # Apprentice
    assert forever.trainable_cap(19) == 150  # Expert asks for 20
    assert forever.trainable_cap(35) == 300
    assert forever.trainable_cap(0) == forever.max_skill  # level unknown: every rank
    assert versions.VERSIONS["tbc"].trainable_cap(70) == 375


def test_an_auctions_deposit_is_at_least_forevers_minimum() -> None:
    forever = versions.VERSIONS["forever"]
    assert forever.ah_deposit(500, 3) == 3 * 300  # 5% of 500 per 2 hours, for a day's auction each
    assert forever.ah_deposit(10, 3) == 3 * 100  # 6c each: the 1s minimum an auction
    assert forever.ah_deposit(10, 45, stack=20) == 120 + 120 + 100  # two full stacks and the 5 left
    assert forever.ah_deposit(0, 1) == 100  # nothing a vendor pays still costs the minimum
    assert versions.VERSIONS["tbc"].ah_deposit(10, 3) == 3 * 6  # no minimum there


# Forever's live realms: "<cluster> <region><n> Realm <n> <ruleset>", coalesced by region and ruleset
US3, US5 = "CAMWOW US2 Realm 3 PvE", "CAMWOW US2 Realm 5 PvE"
SHARD3 = "CAMWOW US3 Realm 1 PvE"  # another shard of the region: its players play with US2's


def test_a_forever_realm_is_its_regions_fixed_realm_of_its_ruleset() -> None:
    forever = VERSIONS["forever"]
    assert forever.realm_name(US3) == forever.realm_name(US5) == "Americas Normal"
    assert forever.realm_name(SHARD3) == "Americas Normal"
    assert forever.realm_name("CAMWOW EU4 Realm 1 PvE") == "Europe Normal"
    assert forever.realm_name("CAMWOW EU4 Realm 4 PvP") == "Europe PvP"
    assert forever.realm_name("CAMWOW EU4 Realm 10 RP") == "Europe RP"
    assert forever.realm_name("CAMWOW US2 Realm 3 RPPvP") == "Americas RP-PvP"
    assert forever.realm_name("CAMWOW US3 Realm 1 RPPvP") == "Americas RP-PvP"
    spec = forever.canonical_realm(US3)
    assert spec is not None
    assert (spec.key, spec.region, spec.ruleset) == ("americas-normal", "americas", "normal")
    assert forever.realm_name("Americas Normal") == "Americas Normal"  # the fixed realm's own name


def test_a_forever_realm_of_an_unknown_region_or_ruleset_is_its_coalesced_group() -> None:
    forever = VERSIONS["forever"]
    assert forever.canonical_realm("CAMWOW ZZ1 Realm 2 PvE") is None
    assert forever.realm_name("CAMWOW ZZ1 Realm 2 PvE") == forever.realm_name("CAMWOW ZZ1 Realm 7 PvE")
    assert forever.realm_name("CAMWOW ZZ1 Realm 2 PvE") == forever.realm_name("CAMWOW ZZ2 Realm 1 PvE")
    assert forever.realm_name("CAMWOW ZZ1 Realm 2 PvE") == "CAMWOW ZZ PvE"
    assert forever.realm_name("CAMWOW US2 Realm 2 Arena") == "CAMWOW US Arena"
    assert forever.realm_name("Classic Beta PvE") == "Classic Beta PvE"  # another shape: as it is


def test_every_region_has_each_ruleset_and_tbc_realms_stay_as_they_are() -> None:
    forever = VERSIONS["forever"]
    assert {(s.region, s.ruleset) for s in forever.realms} == {
        (r, s) for r in ("americas", "europe", "asia") for s in ("normal", "pvp", "rp", "rppvp", "hardcore")
    }
    assert not any(s.open for s in forever.realms if s.ruleset == "hardcore")
    assert VERSIONS["tbc"].realm_name("CAMWOW US2 Realm 3 PvE") == "CAMWOW US2 Realm 3 PvE"


def test_the_live_forever_client_folder_is_watched() -> None:
    assert VERSIONS["forever"].flavor_folders[0] == "_forever_"
    saved = Path("World of Warcraft/_forever_/WTF/Account/A/SavedVariables/AltArmy_TBC.lua")
    assert watch.version_of(saved) == "forever"
