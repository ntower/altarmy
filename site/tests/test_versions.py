"""Game versions: lookup, data files and addon folders."""

import re
from pathlib import Path

import pytest

from altarmy_site import engine, gamedata, versions, wowfiles
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
    assert forever.flavor_folders == ("_classic_beta_",)
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
