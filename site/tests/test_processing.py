from pathlib import Path

import pytest

from altarmy_site import engine, processing, versions


def test_the_curated_list_reads_and_covers_every_group() -> None:
    spells = processing.read(versions.VERSIONS["forever"].processing_csv)
    assert set(spells.values()) == set(processing.GROUPS)
    assert spells[2657] == "smelt"  # Smelt Copper
    assert spells[13361] == "essence"  # Greater Magic Essence


def test_a_bad_row_is_a_value_error_naming_it(tmp_path: Path) -> None:
    bad = tmp_path / "processing.csv"
    bad.write_text("spell_id,group,note\n1,smelt,a\n2,mining,b\n")
    with pytest.raises(ValueError, match="spell 2"):
        processing.read(bad)
    bad.write_text("spell_id,group,note\n1,smelt,a\n1,cloth,b\n")
    with pytest.raises(ValueError, match="listed twice"):
        processing.read(bad)
    assert processing.read(tmp_path / "none.csv") == {}


def test_recipes_are_grouped_by_their_spell() -> None:
    copper = engine.Recipe(3324, "Smelt Copper", 2840, spell_id=2657)
    robe = engine.Recipe(10, "Robe", 1, spell_id=99)
    assert processing.recipe_groups([copper, robe], {2657: "smelt"}) == {3324: "smelt"}
