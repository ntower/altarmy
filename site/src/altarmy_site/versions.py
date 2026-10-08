"""The game versions the app supports: TBC Anniversary and WoW: Forever.

Alt Army runs on both clients and writes the same `AltArmy_TBC.lua` on each; only the WoW flavor folder
(`_anniversary_`, `_classic_beta_`) tells them apart. Every version shares one database, keyed by `key`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

GameVersionKey = Literal["tbc", "forever"]
DATA_DIR = Path("data")
# Alt Army Sync bundles this module: it imports nothing of the package (tests/test_sync_imports.py)
AH_CUT = 0.05  # auction house cut taken from the sale price (deposit ignored)
MAIL_POSTAGE = 30  # copper per attached item


@dataclass(frozen=True)
class ProfessionRank:
    """A rank a profession trainer teaches: from `train_at` skill and character `level`, it lets the skill
    go up to `cap`."""

    name: str
    train_at: int
    level: int
    cap: int


# Vanilla's and TBC's ranks: each is taught 25 points before the one below it caps
PROFESSION_RANKS = (
    ProfessionRank("Apprentice", 1, 5, 75),
    ProfessionRank("Journeyman", 50, 10, 150),
    ProfessionRank("Expert", 125, 20, 225),
    ProfessionRank("Artisan", 200, 35, 300),
    ProfessionRank("Master", 275, 50, 375),
)


@dataclass(frozen=True)
class GameVersion:
    key: GameVersionKey
    label: str
    wago_product: str  # wago.tools product whose DB2 tables describe this client
    flavor_folders: tuple[str, ...]  # WoW install subfolders whose WTF holds this client's SavedVariables
    data_dir: Path  # hand-maintained CSVs: disenchant.csv, vendor_items.csv
    interface: int  # the client's interface number (## Interface in addon TOCs)
    max_level: int  # the level cap
    max_skill: int  # the highest profession skill rank
    ah_cut: float = AH_CUT
    # whether the version's disenchant table has been checked in game: until it is, a disenchant's sale is
    # never more than likely (`service.verdict`)
    disenchant_verified: bool = False
    mail_postage: int = MAIL_POSTAGE  # copper per attachment
    # Prices come from the Alt Army addon's full scans (and prices set by hand) alone: `prices.record_book`
    first_party_prices: bool = False
    # (standing, percent off) at a vendor for the buyer's standing with the vendor's faction (5 Friendly,
    # 6 Honored, 7 Revered, 8 Exalted; see `reputation`); standings not listed get nothing off
    reputation_discounts: tuple[tuple[int, int], ...] = ()

    @property
    def profession_ranks(self) -> tuple[ProfessionRank, ...]:
        """The profession ranks a trainer teaches here, up to `max_skill`."""
        return tuple(r for r in PROFESSION_RANKS if r.cap <= self.max_skill)

    def trainable_cap(self, level: int) -> int:
        """The highest skill a character of `level` can train a profession to: the cap of the highest rank
        whose level they have (`max_skill` when the level is unknown, 0)."""
        if level <= 0:
            return self.max_skill
        return max((r.cap for r in self.profession_ranks if r.level <= level), default=0)

    @property
    def disenchant_csv(self) -> Path:
        return self.data_dir / "disenchant.csv"

    @property
    def vendor_csv(self) -> Path:
        return self.data_dir / "vendor_items.csv"

    @property
    def vendor_recipes_csv(self) -> Path:
        """Recipe items vendors sell, limited stock included (Forever only: `vmangos.vendor_recipes`)."""
        return self.data_dir / "vendor_recipes.csv"

    @property
    def sources_csv(self) -> Path:
        """Where recipe items come from: vendors, drops, quests (Forever: `vmangos.recipe_item_sources`)."""
        return self.data_dir / "recipe_item_sources.csv"

    @property
    def trainer_costs_csv(self) -> Path:
        """What trainers charge to teach each spell (Forever: `vmangos.trainer_costs`)."""
        return self.data_dir / "trainer_costs.csv"

    @property
    def cities_dir(self) -> Path:
        """City presets for timing crafts (`timing.CityMap` JSON), from scripts/build_cities.py."""
        return self.data_dir / "cities"


VERSIONS: dict[str, GameVersion] = {
    "forever": GameVersion(
        key="forever",
        label="WoW: Forever",
        wago_product="wow_classic_beta",
        flavor_folders=("_classic_beta_",),
        data_dir=DATA_DIR / "forever",
        interface=16001,
        max_level=60,
        max_skill=300,
        first_party_prices=True,
        reputation_discounts=((6, 10), (7, 10), (8, 10)),  # vanilla's: 10% from Honored, no more after
    ),
    "tbc": GameVersion(
        key="tbc",
        label="TBC Anniversary",
        wago_product="wow_anniversary",
        flavor_folders=("_anniversary_",),
        data_dir=DATA_DIR / "tbc",
        interface=20506,
        max_level=70,
        max_skill=375,
    ),
}
DEFAULT_VERSION: GameVersionKey = "forever"


def get(key: str) -> GameVersion:
    """The version named `key`; ValueError listing the known ones otherwise."""
    try:
        return VERSIONS[key]
    except KeyError:
        raise ValueError(f"unknown game version {key!r}; expected one of {', '.join(VERSIONS)}") from None


def version_of_build(build: str) -> GameVersionKey:
    """Which version a DB2 build belongs to: 2.x is TBC, anything else (1.60.x) is Forever."""
    return "tbc" if build.startswith("2.") else "forever"
