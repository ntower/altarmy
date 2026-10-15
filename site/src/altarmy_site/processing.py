"""Process trade goods: the recipes that turn one trade good into another worth more (ore into bars, hides
and scraps into leather, cloth into bolts, lesser essences into greater and back), by group.

Which recipes count is hand-curated in `data/<version>/processing.csv` (spell_id, group, note), read when
first asked for (as the city presets are), not loaded into the database: a recipe the loaded game data
lacks is left out. Pure apart from reading that file; standard library only.
"""

from __future__ import annotations

import csv
import functools
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Literal, Protocol, get_args

Group = Literal["smelt", "leather", "cloth", "essence"]
GROUPS: tuple[Group, ...] = get_args(Group)


class _Recipe(Protocol):
    @property
    def id(self) -> int: ...
    @property
    def spell_id(self) -> int: ...


def read(path: Path) -> dict[int, Group]:
    """{spell id: group} from a processing CSV; none without the file. A row naming no group of `GROUPS`,
    or a spell twice, is a ValueError naming it."""
    if not path.is_file():
        return {}
    out: dict[int, Group] = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            spell, group = int(row["spell_id"]), (row.get("group") or "").strip()
            if group not in GROUPS:
                raise ValueError(f"{path.name}: spell {spell} has no known group ({group!r})")
            if spell in out:
                raise ValueError(f"{path.name}: spell {spell} is listed twice")
            out[spell] = group
    return out


@functools.cache
def for_path(path: Path) -> Mapping[int, Group]:
    """`read`, once per file for the process's life (the hosted image's files never change)."""
    return read(path)


def recipe_groups(recipes: Iterable[_Recipe], spells: Mapping[int, Group]) -> dict[int, Group]:
    """{recipe id: group} of the `recipes` whose spell is listed."""
    return {r.id: spells[r.spell_id] for r in recipes if r.spell_id in spells}
