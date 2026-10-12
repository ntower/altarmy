"""Sanity checks on the shipped data/forever/disenchant.csv lookup table."""

import csv
from collections import defaultdict
from pathlib import Path

import pytest

from altarmy_site.engine import (
    DISENCHANTABLE_CLASSES,
    DISENCHANTABLE_QUALITIES,
    DisenchantRow,
    Item,
    Market,
)

TABLE = Path(__file__).resolve().parents[1] / "data" / "forever" / "disenchant.csv"

# Classic-era enchanting materials (dusts, essences, shards, Nexus Crystal).
KNOWN_MATS = {
    10938, 10939, 10940, 10978, 10998, 11082, 11083, 11084, 11134, 11135, 11137, 11138, 11139,
    11174, 11175, 11176, 11177, 11178, 14343, 14344, 16202, 16203, 16204, 20725,
}  # fmt: skip


def load_table() -> list[DisenchantRow]:
    with open(TABLE, newline="", encoding="utf-8") as f:
        return [
            DisenchantRow(
                int(r["item_class"]),
                int(r["quality"]),
                int(r["min_ilvl"]),
                int(r["max_ilvl"]),
                int(r["result_item_id"]),
                float(r["chance"]),
                int(r["min_count"]),
                int(r["max_count"]),
            )
            for r in csv.DictReader(f)
        ]


def test_rows_are_well_formed() -> None:
    rows = load_table()
    assert rows
    for d in rows:
        assert d.item_class in DISENCHANTABLE_CLASSES
        assert d.quality in DISENCHANTABLE_QUALITIES
        assert 0 < d.min_ilvl <= d.max_ilvl
        assert 0 < d.chance <= 1
        assert 1 <= d.min_count <= d.max_count
        assert d.result_item_id in KNOWN_MATS


def test_each_bracket_sums_to_one_and_brackets_do_not_overlap() -> None:
    brackets: dict[tuple[int, int], dict[tuple[int, int], float]] = defaultdict(lambda: defaultdict(float))
    for d in load_table():
        brackets[(d.item_class, d.quality)][(d.min_ilvl, d.max_ilvl)] += d.chance
    for key, ranges in brackets.items():
        for rng, total in ranges.items():
            assert total == pytest.approx(1.0, abs=0.001), (key, rng)
        ordered = sorted(ranges)
        for (_, prev_hi), (lo, _) in zip(ordered, ordered[1:], strict=False):
            assert lo > prev_hi, (key, ordered)


def test_green_armor_expected_value() -> None:
    # ilvl 20 green armor: 75% 2-3 Strange Dust, 20% 1-2 Greater Magic Essence, 5% 1 Small Glimmering Shard.
    robe = Item(id=1, name="Green Robe", quality=2, item_level=20, class_id=4)
    market = Market({1: robe}, [], {10940: 100, 10939: 1000, 10978: 2000}, load_table(), ah_cut=0.0)
    assert market.disenchant_value(robe) == int(0.75 * 2.5 * 100 + 0.20 * 1.5 * 1000 + 0.05 * 2000)


def results(class_id: int, quality: int, item_level: int) -> dict[int, tuple[float, int, int]]:
    """Material -> (chance, min count, max count) for one item."""
    item = Item(id=1, name="x", quality=quality, item_level=item_level, class_id=class_id)
    market = Market({1: item}, [], {}, load_table())
    return {m.item_id: (m.chance, m.min_count, m.max_count) for m in market.disenchant_materials(item)}


@pytest.mark.parametrize("item_level", [81, 88, 92])
@pytest.mark.parametrize("class_id", [2, 4])
def test_naxxramas_epics_give_nexus_crystals(class_id: int, item_level: int) -> None:
    assert set(results(class_id, 4, item_level)) == {20725}


@pytest.mark.parametrize(("item_level", "shard"), [(1, 10978), (10, 10978), (66, 14344), (80, 14344)])
def test_rares_cover_low_and_high_item_levels(item_level: int, shard: int) -> None:
    assert results(4, 3, item_level)[shard][0] >= 0.995


@pytest.mark.parametrize("item_level", [21, 25, 26, 30])
def test_forever_green_weapons_of_21_to_30_give_greater_magic_essence(item_level: int) -> None:
    # Forever's own drops (Wowhead's Forever data, as Disenchantry has them): armor keeps the astral essences
    assert results(2, 2, item_level)[10939] == (0.75, 1, 2)
    assert 10939 not in results(4, 2, item_level)


@pytest.mark.parametrize("item_level", [51, 60, 65])
def test_green_weapons_of_51_to_65_split_22_75_3(item_level: int) -> None:
    chances = sorted(c for c, _, _ in results(2, 2, item_level).values())
    assert chances == [0.03, 0.22, 0.75]


def test_green_weapons_start_at_item_level_5() -> None:
    assert results(2, 2, 5)
