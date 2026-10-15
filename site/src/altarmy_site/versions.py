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
class RealmSpec:
    """One of a version's fixed realms. Each has an Alliance and a Horde auction house (`FACTIONS`), whose
    rows `db.register_versions` creates. A realm name in an upload is this realm when it is `name` or one
    of `aliases` (`canonical_realm`), the names Blizzard and the client give it."""

    key: str  # normal, pvp, rp, hardcore: stable, for paths
    label: str
    name: str  # the auction houses' realm
    aliases: tuple[str, ...] = ()
    open: bool = True  # False until the realm opens (Hardcore, a couple of months after launch)


FACTIONS = ("Alliance", "Horde")  # each fixed realm's auction houses; the neutral one is left out


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
    # An item sells on the AH only once enough of its auctions have ended (`merge`'s gate,
    # `engine.Market.ah_open`); until then crafts sell to a vendor
    gated_prices: bool = False
    # the client numbers its containers as retail does (WoW: Forever's Enum.BagIndex: bags 0-5, bank tabs
    # 6-14), else as Classic (bags 0-4, the bank -1 and bank bags 5-11): where `altarmy` reads holdings
    retail_bags: bool = False
    # (standing, percent off) at a vendor for the buyer's standing with the vendor's faction (5 Friendly,
    # 6 Honored, 7 Revered, 8 Exalted; see `reputation`); standings not listed get nothing off
    reputation_discounts: tuple[tuple[int, int], ...] = ()
    # The hourly auction snapshots (`snapshots`): each time-left bucket's (more than, at most) seconds left,
    # Classic's until a Forever snapshot shows them; the durations an auction can be posted for, in hours;
    # and the longest gap between two snapshots that still tells what ended in between
    time_left_buckets: tuple[tuple[str, int, int], ...] = (
        ("SHORT", 0, 1800),
        ("MEDIUM", 1800, 7200),
        ("LONG", 7200, 28800),
        ("VERY_LONG", 28800, 86400),
    )
    auction_hours: tuple[int, ...] = (2, 8, 24)
    # What posting costs: this share of what a vendor pays for the stack, per 2 hours it is up (vanilla's,
    # until checked in game: 5% for 2 hours, 60% for 24)
    ah_deposit_rate: float = 0.05
    snapshot_gap: int = 4500  # seconds: an hour and a quarter, so a late snapshot still follows
    # the fixed realms, whose auction houses always exist (empty: realms come from uploads, as on TBC)
    realms: tuple[RealmSpec, ...] = ()

    def canonical_realm(self, name: str) -> RealmSpec | None:
        """The fixed realm a realm name stands for (its name or an alias, ignoring case and spaces)."""
        wanted = _squash(name)
        for spec in self.realms:
            if wanted in {_squash(n) for n in (spec.name, *spec.aliases)}:
                return spec
        return None

    def realm_name(self, name: str) -> str:
        """The auction houses' realm for a realm name: the fixed realm's, else the name as it is."""
        spec = self.canonical_realm(name)
        return name if spec is None else spec.name

    @property
    def buckets(self) -> dict[str, tuple[int, int]]:
        """`time_left_buckets` by name, as `snapshots.diff` takes them."""
        return {name: (lo, hi) for name, lo, hi in self.time_left_buckets}

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
    def vendor_overrides_csv(self) -> Path:
        """What vendors really pay or charge where the build's DB2 is wrong (written by hand: `ingest`)."""
        return self.data_dir / "vendor_overrides.csv"

    @property
    def vendor_offers_csv(self) -> Path:
        """Everything spawned vendors sell, limited stock included, with where they stand (Forever:
        `vmangos.vendor_offers`; Vendor runs)."""
        return self.data_dir / "vendor_offers.csv"

    @property
    def processing_csv(self) -> Path:
        """The recipes Process trade goods ranks, by group (written by hand: `processing`)."""
        return self.data_dir / "processing.csv"

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
        gated_prices=True,
        retail_bags=True,
        reputation_discounts=((6, 10), (7, 10), (8, 10)),  # vanilla's: 10% from Honored, no more after
        # The launch realms' own names go in their aliases on launch day
        realms=(
            RealmSpec("normal", "Normal", "Normal"),
            RealmSpec("pvp", "PvP", "PvP"),
            RealmSpec("rp", "RP", "RP"),
            RealmSpec("hardcore", "Hardcore", "Hardcore", open=False),
        ),
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


def _squash(name: str) -> str:
    return "".join(name.split()).lower()
