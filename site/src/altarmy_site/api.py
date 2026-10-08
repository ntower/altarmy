"""FastAPI JSON API for the React front end, which it also serves once built (frontend/dist).

Money is integer copper on the wire; the front end formats it. Handlers are plain `def` so FastAPI runs
them in its threadpool, so a slow request never stalls the others.
Each handler opens its own connection from the shared `db.Database` (never shared across threads).

Every route but /api/config and /api/versions has a user (`CurrentUser`): whoever the Firebase ID token
sent as a bearer token says (401 without one). Every tier, anonymous guests included, gets every route.
The watcher and Alt Army Sync sign in to the same Firebase project with an email and password (`signin`),
so their uploads carry an ID token like the browser's. Every request is rate-limited
per client IP and per user (`ratelimit`), and no /api response may be cached (Firebase Hosting's CDN sits
in front).
"""

from __future__ import annotations

import json
import logging
from collections.abc import Awaitable, Callable, Collection, Hashable, Iterable, Iterator, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from datetime import UTC, datetime
from functools import partial
from pathlib import Path, PurePath
from typing import Annotated, Literal, cast

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    FastAPI,
    Form,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import Connection
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.types import Scope

from . import (
    altarmy,
    auth,
    cloudlog,
    db,
    engine,
    jobs,
    launch,
    prices,
    ratelimit,
    reputation,
    service,
    store,
    talents,
    timing,
    uploads,
    users,
    versions,
)
from . import signals as price_signals
from .versions import GameVersion, GameVersionKey

DEFAULT_DIST = Path(__file__).resolve().parents[2] / "frontend" / "dist"
# The runs `/api/rank` says follow the one crafted now (`RankResponse.chain`), unless `chain_length` asks for
# more, up to `MAX_SKILL_CHAIN`
SKILL_CHAIN = 2
MAX_SKILL_CHAIN = 40
# The skill workspace's strategies, side by side in this order (`RankResponse.strategies`, `_strategy`): the
# climb as recommended (`engine.MIN_CHANCE`, each craft worth `engine.CRAFT_VALUE`), the cheapest in copper
# alone (at any chance of a point), and one up recipes trainers teach alone (no patterns to buy or farm)
Strategy = Literal["recommended", "cheapest", "no_patterns"]
STRATEGIES: tuple[Strategy, ...] = ("recommended", "cheapest", "no_patterns")
# The ranks of the Legacy talents a skill climb may be planned with in place of the climber's own (the skill
# workspace's sliders: `working_overtime`, `bartering`, `master_chef`)
WORKING_OVERTIME_RANKS = talents.LEGACY_TALENTS[talents.WORKING_OVERTIME].max_rank
BARTERING_RANKS = talents.LEGACY_TALENTS[talents.BARTERING].max_rank
MASTER_CHEF_RANKS = talents.LEGACY_TALENTS[talents.MASTER_CHEF].max_rank

# "skill": an enchant cast for the skill point alone (`engine.SKILL_EXIT`); only when asked for
ExitKind = Literal["vendor", "ah", "disenchant", "skill", "keep"]
ALL_EXIT_KINDS: tuple[ExitKind, ...] = ("vendor", "ah", "disenchant")
# What may teach a recipe "to train" unless the request says otherwise (as `engine.DEFAULT_SOURCES`, ordered)
DEFAULT_SOURCES: tuple[engine.Source, ...] = ("trainer", "recipe")


# --- models ----------------------------------------------------------------------------------------
class SelectionModel(BaseModel):
    """A realm and faction: whose recipes count and which auction house prices them."""

    realm: str
    faction: str


class Status(BaseModel):
    build: str | None
    items: int
    recipes: int
    prices: int  # current prices of the selection's auction house
    characters: int
    selection: SelectionModel | None
    auction_house_id: int | None  # the selection's auction house (the unnamed one without characters)
    data_version: int  # bumped when an upload or edit changed the user's data: refetch characters, results
    price_version: (
        int | None
    )  # the auction house's, bumped by each merge that moved its statistics: refetch results


class MaterialOut(BaseModel):
    """One possible disenchant result."""

    item_id: int
    name: str
    chance: float  # 0..1
    min_count: int
    max_count: int
    value: int | None  # expected net AH copper per disenchant; None if unpriced
    expected: float  # expected units per disenchant, the Arcane Salvager's roll included


class ExitOut(BaseModel):
    kind: str  # vendor | ah | disenchant | skill (an enchant's: nothing is sold)
    value: int  # copper per item, after cuts
    materials: list[MaterialOut]  # disenchant only: what it yields
    postage: int  # copper per item to mail it to the character who can use this exit
    mail_to: str  # that character; "" if the crafter can use it themselves


class StepOut(BaseModel):
    action: Literal["buy", "gather", "craft", "mail", "sell"]
    item_id: int
    name: str
    quantity: int
    value: int  # copper for the whole step: negative when buying or mailing, positive when selling
    via: str  # buy: vendor | ah; craft: recipe name; mail: recipient; sell: vendor | ah | disenchant
    who: str  # the character doing it; "" if no characters are known
    paths: list[str]  # the tree paths (choice keys) of the nodes it stands for; ["sell"] for the sale
    discount: int = 0  # buy from a vendor: percent off from the buyer's Legacy talents (Bartering)
    rep_discount: int = 0  # buy from a vendor: percent off for the buyer's standing with its faction
    rep_faction: str = ""  # that faction (Orgrimmar, Darkspear Trolls, ...); "" without such a discount
    bonus: float = 0.0  # sell: expected extra units on top of quantity (Master Chef), counted in value
    seconds: float = 0.0  # play time per craft this step takes (clicks, casts); travel is in the timing
    lead_seconds: float = 0.0  # a disenchant sale: the disenchanting's share of `seconds` (then posting)
    station: str = ""  # craft: the station it is cast at (anvil, cooking_fire, loom, ...); "" anywhere
    convert: bool = False  # craft: an essence conversion (the item's Use spell), not a profession craft
    enchant: bool = False  # craft: an enchant: `name` is the spell's, no item is made (`item_id` 0)


class OptionOut(BaseModel):
    """One way to get a node's items; POST it back as a choice by `key`."""

    key: str  # vendor | ah | craft:<recipe id>
    cost: int  # copper for the node's quantity this way, with postage
    source: str  # vendor | ah if bought
    via: str  # recipe name if crafted
    crafter: str  # who crafts it (the cheapest character for that recipe)
    seconds: float = 0.0  # estimated play time per craft this way, shared trips included
    convert: bool = False  # crafted by an essence conversion


class SellOptionOut(BaseModel):
    kind: str  # vendor | ah | disenchant | skill
    profit: int  # the best profit selling this way


class NodeOut(BaseModel):
    """One item in a craft's reagent tree: bought (no inputs) or crafted from its inputs, possibly by
    another character who then mails it on."""

    item_id: int
    name: str
    quantity: int  # units this branch needs
    cost: int  # copper spent on them, including postage
    via: str  # recipe name if crafted, "" if bought
    crafts: int  # recipe runs if crafted
    made: int  # units those crafts produce (may exceed quantity)
    source: str  # vendor | ah if bought, "" if crafted
    crafter: str  # who buys or crafts it
    mail_to: str  # who it is mailed to (the parent's crafter); "" if not mailed
    postage: int  # copper for that mail
    discount: int = 0  # bought from a vendor: percent off the buyer gets (Bartering)
    rep_discount: int = 0  # bought from a vendor: percent off for the buyer's standing with its faction
    rep_faction: str = ""  # that faction; "" without such a discount
    seconds: float = 0.0  # estimated play time per craft for this branch, shared trips included
    options: list[OptionOut]  # every way to get these items, cheapest first; empty for the recipe's craft
    option: str  # the key of the option taken; "" for the recipe's craft
    convert: bool = False  # crafted by an essence conversion
    flip: bool = False  # a flip's root: nothing is crafted, its one input (bought) is what is sold
    enchant: bool = False  # an enchant's root: no item (`item_id` 0), named after the spell
    short: int = 0  # bought on the AH: units more than its ladder lists (priced at its dearest level)
    inputs: list[NodeOut]


def _node_out(n: engine.Node, faction: Callable[[str, int, int], str]) -> NodeOut:
    """`faction(who, item id, percent)` names the faction a reputation discount comes from."""
    return NodeOut(
        item_id=n.item_id,
        name=n.name,
        quantity=n.quantity,
        cost=n.cost,
        via=n.via,
        crafts=n.crafts,
        made=n.made,
        source=n.source,
        crafter=n.crafter,
        mail_to=n.mail_to,
        postage=n.postage,
        discount=n.discount,
        rep_discount=n.rep_discount,
        rep_faction=faction(n.crafter, n.item_id, n.rep_discount),
        seconds=n.seconds,
        options=[OptionOut(**asdict(o)) for o in n.options],
        option=n.option,
        convert=n.convert,
        flip=n.flip,
        enchant=n.enchant,
        short=n.short,
        inputs=[_node_out(i, faction) for i in n.inputs],
    )


class ItemCount(BaseModel):
    item_id: int
    count: int


class EffectOut(BaseModel):
    """A green tooltip line."""

    trigger: str  # Use, Equip, Chance on hit
    text: str


class LevelOut(BaseModel):
    """The units listed at one unit price."""

    price: int
    quantity: int
    # False: first seen in the newest scan and far under the usual price, so plans don't count on it
    # (it may be gone before you get there)
    counted: bool
    more: bool  # pools every dearer level too (`price` is the cheapest of them)
    listings: int  # the auctions at that price
    age: int  # the scans before the newest that already had it (0: just listed)


class ItemInfo(BaseModel):
    """Everything an item tooltip shows."""

    id: int
    name: str
    quality: int  # 0 poor .. 5 legendary
    class_id: int  # 2 weapon, 4 armor, ...
    subclass_name: str | None
    inventory_type: int  # equip slot, 0 if not equippable
    bonding: int  # 1 on pickup, 2 on equip, 3 on use, 4 quest item
    item_delay: int  # weapon speed, ms
    container_slots: int
    required_level: int
    required_skill: str | None
    required_skill_rank: int
    description: str | None
    sell_price: int
    icon: str | None  # wow.zamimg.com icon name
    # computed at ingest (itemstats.py); 0 and empty until the version's game data is updated
    armor: int
    dmg_min: int
    dmg_max: int
    dps: float
    stats: list[str]  # white lines, in game order: "+18 Strength", "+25 Fire Resistance"
    effects: list[EffectOut]  # green lines, in game order
    ah_price: int | None  # the cheapest listing
    # what selling it on the AH counts as: the lower of what is asked a little way into the listed units
    # and what it goes for (what sold lately, else the 7-day median; hand-set prices as they are), so a
    # lone listing, cheap or overpriced, isn't taken for the going rate
    ah_sell_price: int | None
    ah_quantity: int | None  # units listed; None if unknown
    ah_levels: list[LevelOut] = []  # every price level listed, cheapest first (Alt Army's scans)
    vendor_price: int | None  # per unit, if a vendor sells it
    # what the auction house's market for it says (Alt Army's scans; None from other sources): what is
    # asked (the price 15% into the units listed), what it usually goes for (the 7-day median, from
    # `scans_7d` days) and what it sold for, the units seen sold over the last week and the pairs of
    # scans they were seen in, whether the newest scan listed it (False: gone since `seen_at`)
    market_price: int | None = None
    median_7d: int | None = None
    scans_7d: int | None = None
    sale_price: int | None = None
    sold_7d: int = 0
    sold_pairs_7d: int | None = None
    listed: bool | None = None
    seen_at: datetime | None = None
    stack_size: int = 1


class LegOut(BaseModel):
    """One run across the city."""

    who: str  # the character running; "" if no characters are known
    from_id: str
    from_name: str
    to_id: str
    to_name: str
    seconds: float


class TimingOut(BaseModel):
    """How long the result's session (its `crafts`) takes in a city, and what that makes per hour."""

    city: str
    fixed_seconds: float  # travel, character switches, AH searches
    per_craft_seconds: float  # the crafts' own: casts, buys, posts, mail
    total_seconds: float  # the whole session
    per_hour: int  # copper profit per hour of play
    breakdown: dict[str, float]  # the session's seconds: travel, switch, ah, vendor, mail, craft, disenchant
    legs: list[LegOut]  # every run, in order
    unsold: list[int]  # vendor items no vendor in the city sells (timed at the nearest vendor)
    missing: list[str]  # crafting stations (anvil, moonwell, ...) the plan needs and the city lacks
    deployed: list[str]  # stations new in Forever (loom, ...) the plan needs: counted as set down on the spot


class CityTimingOut(BaseModel):
    """The result in one city: as planned there when the cities were compared, else (the user's city is
    set, or `city` was asked for) its plan with the vendor buys at that city's prices."""

    city: str
    total_seconds: float
    per_hour: int
    profit: int  # vendors charge a character by their reputation, so it differs between cities
    missing: list[str]  # crafting stations the plan needs and the city lacks: it can't be crafted there


class LocationOut(BaseModel):
    id: str
    kind: str  # ah | mailbox | vendor | a crafting station (anvil, ...)
    name: str
    map_x: float | None  # on the city's zone map, percent; None if the preset has no zone
    map_y: float | None
    map_area: int | None  # the zone map's AreaTable id (frontend/public/maps/<id>.jpg); None if unknown


class DetailOut(BaseModel):
    """One line of a session spelled out."""

    kind: Literal["switch", "start", "go", "step"]
    who: str
    step: int | None  # step: an index into `steps`
    location: LocationOut | None  # start: where the character stands (no time); go: where to
    retrieve: list[ItemCount]  # go to the mailbox: what waits there
    seconds: float  # go: the run there


class RankResult(BaseModel):
    recipe_id: int
    recipe: str
    # craft: a profession recipe; convert: an essence conversion; flip: gear bought on the AH to disenchant
    # (those two need no profession: anyone does them); enchant: a profession's spell enchanting an item,
    # which makes none (`output_item_id` 0, `output_name` the spell's) and is never sold (`best_exit`
    # skill)
    kind: Literal["craft", "convert", "flip", "enchant"] = "craft"
    profession: str
    crafters: list[str]  # selected characters who know the recipe; empty if nobody has learned it
    crafter: str  # who does the cheapest craft (may not have learned it, with `unlearned`)
    output_item_id: int
    output_name: str
    output_count: int
    cost: int  # reagents plus all postage
    revenue: int
    profit: int
    roi: float
    best_exit: str
    slow: bool  # the AH sale may take over service.SLOW_DAYS at the rate it sold lately (informational)
    days_to_sell: float | None  # how long that sale may take; None if unknown or not sold on the AH
    short: int  # units the plan buys on the AH beyond what is listed (counted at the dearest price)
    postage: int  # copper to mail the output to whoever sells it (included in cost)
    mail_to: str  # who the output is mailed to; "" if the crafter sells it
    bonus_output: float = 0.0  # expected extra units from the crafter's talents (Master Chef), all crafts
    skill_chance: float  # that the first craft gives the crafter a skill point (1 without characters)
    confidence: ConfidenceOut | None = None  # how far the AH sell price can be trusted; None off the AH
    # the skill points the crafter can expect from all crafts, each craft's chance falling as the skill rises
    skill_ups: float
    skill_ups_bonus: float = 0.0  # the part of `skill_ups` owed to Working Overtime
    # what the crafter's Working Overtime adds to every chance of a point while the recipe isn't grey
    skill_bonus: float = 0.0
    exits: list[ExitOut]
    reagents: list[ItemCount]
    steps: list[StepOut]  # per character: buys, crafts (intermediates first), mails; then the sale
    tree: NodeOut  # the recipe's craft, with reagents as inputs
    sell_options: list[SellOptionOut]  # each exit's best profit, best first
    timing: TimingOut | None = None  # this plan in the user's city, or where it pays best per hour
    cities: list[CityTimingOut] = []  # the recipe in each city the selection's faction crafts in
    # the one of those paying most per hour (losing least, if none profits); None without city presets
    best_city: str | None = None
    crafts: int = 1  # what cost, revenue, profit, steps and tree are for: a session (the user's batch)
    details: list[DetailOut] = []  # the steps with where to go in between
    # what the session is likely to make (`service.likely`): an AH sale counts on the units the market has
    # shown it takes (`depth_units`); the rest (`excess_units`) go to the best other exit, which is
    # `likely_exit` when it then pays better
    # what the crafter must spend to learn the recipe (its pattern, or a trainer's fee; 0 when known or
    # free); None when nothing says
    learn_cost: int | None = 0
    # what about buying the reagents is in doubt (`service.buy_flags`): short, just_listed
    buy_flags: list[str] = []
    likely_profit: int
    likely_exit: str
    depth_units: int = 0
    excess_units: int = 0
    # the gold list's two ways to sell. Playing it safe (`service.safe_profit`): the better of a vendor and
    # disenchanting, or an essence conversion's sale (`safe_exit` convert); None when neither is open.
    # The auction house (`service.ah_sale`), whichever exit pays best: counting on the units its market
    # has shown it takes (`ah_depth_units`), the rest (`ah_excess_units`) at the best other exit; None when
    # it can't be sold there. `likely_profit` is the better of the two.
    safe_profit: int | None = None
    safe_exit: str | None = None
    ah_profit: int | None = None
    ah_depth_units: int = 0
    ah_excess_units: int = 0
    # the skill the recipe is learned at (0: a trainer's, at no skill DB2 knows) and where it turns yellow
    # and grey (green halfway between); 0 when unknown
    learn_skill: int = 0
    trivial_low: int = 0
    trivial_high: int = 0
    # with `runs` (`engine.Climb`): the skill the crafts take the crafter to, why they stop there (rival:
    # the climb goes on with `overtaken_by`, another recipe's output, cheaper from there; trivial: the recipe
    # is about to turn grey; cap; ceiling: the most crafts a run asks for, the climb going on with the same
    # recipe if it can), the crafts that get there four times in five; 0 / "" without a run.
    # `overtaken_by_item`: that output's item id (in `items`; 0 for an enchant or without a rival)
    stop_skill: int = 0
    stop_reason: str = ""
    overtaken_by: str = ""
    overtaken_by_item: int = 0
    crafts_p80: int = 0
    # the chance of reaching `stop_skill` after each of 1, 2, ... crafts (past the end, at least the last)
    reach_chances: list[float] = Field(default_factory=list)
    # the crafts each of the run's points is expected to take, in order: where its last points get slow
    point_crafts: list[float] = Field(default_factory=list)
    # a run that starts a climb: what the whole climb with it first is chosen by (`ClimbPlan.cost`: crafts
    # at their cost and craft value, spare materials, effort, the patterns of known price); None for a
    # later run of a climb or without a run
    climb_cost: int | None = None
    # ... and how many patterns that climb buys have no known price (counted before the copper), and the
    # skill it reaches (the cap, or where nothing gives a point any more)
    climb_unknown: int = 0
    climb_end: int = 0
    # a run that starts a climb: what the climb is expected to come to by each profession rank's cap it
    # reaches above the crafter's skill now (`ClimbPlan.spent_by`)
    milestones: list[MilestoneOut] = []


class MilestoneOut(BaseModel):
    """What a climb is expected to come to by the time it reaches `skill`: its crafts (spent less what
    selling what they make brings back, so negative when they earn) and its patterns, `unknown` of which have
    no known price (not counted), and the crafts it is expected to take to get there."""

    skill: int
    cost: int
    unknown: int = 0
    crafts: int = 0


class ConfidenceOut(BaseModel):
    """How far a result's AH sell price can be trusted (`prices.confidence`), and the numbers behind it."""

    level: prices.ConfidenceLevel
    reason: prices.ConfidenceReason
    sold: int  # units seen sold over the last prices.SALES_DAYS days
    units: int  # what the plan sells
    listed: int | None  # units listed now; None if unknown
    scan_days: int  # the days its 7-day median is from
    watched_hours: float  # hours of back-to-back scans of the auction house lately, when sales are seen
    unlisted_since: datetime | None  # set when the newest scan had none: since when
    flags: list[prices.ConfidenceFlag] = []  # every doubt about the price, most actionable first
    sold_pairs: int = 0  # the pairs of scans its sales were seen in


class PlaceOut(BaseModel):
    """Somewhere a recipe item comes from (vanilla's world data: Forever may differ)."""

    kind: Literal["vendor", "drop", "object", "container", "world_drop", "quest", "more"]
    name: str  # the vendor, creature, object, container item or quest; "" for world_drop and more
    zone: str  # "" if unknown
    side: Literal["alliance", "horde", ""]  # who it serves ("" both)
    chance: float  # drop chance, percent; 0 if not a drop
    count: int  # world_drop: how many creatures drop it; more: sources not listed
    levels: str  # world_drop: the creatures' levels, quest: its level ("30-40"); "" otherwise
    limited: bool  # vendor: limited stock
    area: int = 0  # vendor: the zone map it stands on (frontend/public/maps/<area>.jpg); 0 if none
    map_x: float = 0.0  # vendor: where on that map, percent
    map_y: float = 0.0


class RecipeItemOut(BaseModel):
    item_id: int
    name: str
    places: list[PlaceOut]  # none known: one of Forever's own recipe items, or one nobody tracked
    price: int | None = (
        None  # the least it costs: from a vendor serving the selection's faction, or on the AH
    )
    limited: bool = False  # a vendor sells it in limited stock


class LearnOut(BaseModel):
    """Where to learn a recipe nobody has learned."""

    source: engine.Source  # trainer, recipe (an item anyone can get), bop (a bind on pickup item)
    skill: int  # the profession skill it needs
    profession: str
    items: list[RecipeItemOut]  # the items teaching it (none for a trainer's)
    train_cost: int = 0  # a trainer's: what the cheapest trainer asks; 0 if free or nothing says


class RankResponse(BaseModel):
    results: list[RankResult]  # the first `top` matches
    total: int  # how many recipes matched the filters
    items: dict[int, ItemInfo]  # every item the results mention, for tooltips
    # recipe id -> where to learn it, for the results nobody selected has learned ("not learned")
    learn: dict[int, LearnOut] = {}
    classes: dict[str, str]  # selected character name -> class file (e.g. PALADIN), for class colours
    # with `sort=skill`, `runs`, one profession and one character skilled up: the rest of the cheapest
    # climb starting with the first result's run, up to `chain_length` runs
    chain: list[RankResult] = []
    # as `chain`, with the recommended strategy: each strategy's climb (`STRATEGIES`), what picking it gives
    strategies: list[StrategyOut] = []
    # the hours the selected auction house was watched this week (`prices.watched_hours`): what any
    # item's "seen sold" counts are measured against
    watched_hours: float = 0.0


class StrategyOut(BaseModel):
    """One strategy's climb (`STRATEGIES`): its first run and the runs after it (`SKILL_CHAIN` at most)."""

    key: Strategy
    run: RankResult
    chain: list[RankResult]


class EvaluateRequest(BaseModel):
    """Re-cost one recipe with some of its sources or its exit picked by the user."""

    recipe_id: int
    unlearned: engine.Unlearned = "none"  # as /api/rank's
    look_ahead: int = Field(default=0, ge=0, le=engine.MAX_LOOK_AHEAD)  # as /api/rank's
    sources: list[engine.Source] = list(DEFAULT_SOURCES)  # as /api/rank's
    include_trivial: bool = True  # False: only a crafter it can give a skillup does the final craft
    skill_crafters: list[str] = []  # as /api/rank's
    crafter: str | None = None  # who does the final craft (default: as /api/rank picks)
    exits: list[ExitKind] = list(ALL_EXIT_KINDS)
    arcane_salvager: bool = False  # as /api/rank's
    # tree path ("r.0", "r.0.1"; "sell" for the exit) -> option key (or exit kind); unknown keys are ignored
    choices: dict[str, str]
    # that many crafts at once; None: the user's batch, as ranked (or the run, with `runs`)
    copies: int | None = Field(default=None, ge=1, le=1000)
    runs: bool = False  # as /api/rank's: plan the run, unless `copies` is given
    strategy: Strategy = "recommended"  # as /api/rank's
    # as /api/rank's: the one character skilled up's Legacy talents at these ranks instead
    working_overtime: int | None = Field(default=None, ge=0, le=WORKING_OVERTIME_RANKS)
    bartering: int | None = Field(default=None, ge=0, le=BARTERING_RANKS)
    master_chef: int | None = Field(default=None, ge=0, le=MASTER_CHEF_RANKS)
    # with `runs`: the recipe whose run the chain follows (the first of /api/rank's results with this
    # `strategy`) and `recipe_id`'s place in that chain (1: the run after it), planned at the skill it starts
    # from as the chain has it
    chain_from: int | None = None
    chain_at: int | None = Field(default=None, ge=1, le=MAX_SKILL_CHAIN)
    gathered: list[int] = []  # as /api/rank's
    city: str | None = None  # time and route the session in this city (the selection's faction's)
    price_version: int | None = None  # the auction house's price version the front end knows of
    # as /api/rank's, for the recipe's profession: the one name in `skill_crafters` is a character nobody
    # uploaded, with that profession at this skill
    climber_skill: int | None = Field(default=None, ge=1)


class EvaluateResponse(BaseModel):
    result: RankResult
    items: dict[int, ItemInfo]  # every item the result mentions, for tooltips
    watched_hours: float = 0.0  # as RankResponse's


class TimeConfigModel(BaseModel):
    """Seconds per action, crafts per session, what an hour of play is worth (copper) and running speed."""

    ah_search: float
    ah_buy: float
    ah_post: float
    vendor_buy: float
    vendor_sell: float
    mail_send: float
    mail_attach: float
    mail_open: float
    mail_attachments: int
    switch_character: float
    disenchant: float
    craft_overhead: float
    batch: int
    time_value: int
    run_speed: float
    detour: float


class CityOut(BaseModel):
    name: str
    faction: str  # Horde | Alliance
    hub: str  # where every character starts and ends
    locations: int
    vendors: int


class TimeSettings(BaseModel):
    cities: list[CityOut]  # where the selection's faction crafts: its cities (every one for a shared AH)
    city: str | None  # the user's pick; None: the faction's default
    active: str | None  # the city plans are timed in; None: each in whichever of `cities` is fastest
    config: TimeConfigModel
    defaults: TimeConfigModel


class TimeSettingsIn(BaseModel):
    city: str | None = None  # None: the faction's default
    config: dict[str, float] = {}  # settings that differ from the defaults (the rest are reset)


class AhBlockedItem(BaseModel):
    item_id: int
    added_at: str  # "YYYY-MM-DD HH:MM:SS", UTC


class AhBlocked(BaseModel):
    """Items never sold on the AH: only vendored or disenchanted."""

    items: list[AhBlockedItem]  # newest first
    details: dict[int, ItemInfo]  # for tooltips


class FavoriteRecipe(BaseModel):
    recipe_id: int
    added_at: str  # "YYYY-MM-DD HH:MM:SS", UTC


class Favorites(BaseModel):
    """Recipes the user marked as favorites: /api/rank lists them first."""

    recipes: list[FavoriteRecipe]  # newest first


class ProfessionOut(BaseModel):
    name: str
    rank: int
    max_rank: int
    recipes: int  # learned recipes


class TalentOut(BaseModel):
    """A Legacy talent (WoW: Forever) that changes profits."""

    spell_id: int
    name: str
    rank: int
    max_rank: int


class VendorDiscountOut(BaseModel):
    """What a character's reputation takes off at a city faction's vendors."""

    faction: str  # Orgrimmar, Darkspear Trolls, ...
    percent: int


class CharacterOut(BaseModel):
    name: str
    class_file: str  # e.g. PALADIN
    level: int
    professions: list[ProfessionOut]
    talents: list[TalentOut] = []  # the Legacy talents the engine knows, as the addon saw them
    vendor_discounts: list[VendorDiscountOut] = []  # from their standings, as the addon saw them


class GroupOut(BaseModel):
    realm: str
    faction: str
    characters: list[CharacterOut]


class Characters(BaseModel):
    groups: list[GroupOut]  # by realm, then faction
    selection: SelectionModel | None
    imported_at: str | None = None  # "YYYY-MM-DD HH:MM:SS" UTC: the newest accepted Alt Army upload
    imported_via: Literal["browser", "watcher", "paste"] | None = None  # how that upload came
    auto_import_at: str | None = None  # the newest accepted upload from the watcher or Alt Army Sync
    # whether any of them can craft an Arcane Salvager: the search's default for disenchanting at one
    arcane_salvager: bool = False


class ProfessionRankOut(BaseModel):
    """A profession rank: taught from `train_at` skill and character `level`, the skill goes up to `cap`."""

    name: str
    train_at: int
    level: int
    cap: int


class VersionOut(BaseModel):
    """A game version the app serves; pass its `key` as `game_version` to the other routes."""

    key: GameVersionKey
    label: str  # e.g. TBC Anniversary
    build: str | None  # the DB2 build loaded, None before the first game data download
    recipes: int
    ah_cut: float  # the auction house's cut of a sale (0.05: 5%)
    # the ranks a profession trainer teaches, lowest first (`versions.ProfessionRank`)
    profession_ranks: list[ProfessionRankOut]


class FirebaseOut(BaseModel):
    """The Firebase web config the front end signs in with (public values)."""

    api_key: str
    auth_domain: str
    project_id: str
    emulator_url: str | None  # the Firebase Auth emulator, when developing
    firestore_emulator_host: str | None = None  # host:port of the Firestore emulator (price signals)


class ConfigOut(BaseModel):
    firebase: FirebaseOut


class Me(BaseModel):
    uid: str
    tier: auth.Tier  # free: an anonymous session; linked: signed in with an email
    admin: bool  # the Firebase custom claim: the Admin page


class CoverageOut(BaseModel):
    """How well one auction house is scanned, so uploaders see where scans are needed."""

    auction_house_id: int
    realm: str
    faction: str  # "" if both factions share it
    prices: int  # items with a current price
    last_scan: str | None  # the newest accepted scan, "YYYY-MM-DD HH:MM:SS" UTC
    last_scan_items: int  # items in that scan
    scans_7d: int  # accepted scans in the last 7 days
    uploaders_7d: int  # how many users sent them
    watched_hours: float = 0.0  # hours of scans at most 30 minutes apart lately: when its sales are seen


UploadKind = Literal["altarmy", "auctionator"]
FileVia = Literal["browser", "watcher"]  # how a file upload was sent
UploadVia = Literal["browser", "watcher", "paste"]  # paste: the Alt Army addon's export string


class GroupCount(BaseModel):
    realm: str
    faction: str
    characters: int


class RealmPricesOut(BaseModel):
    key: str  # an Alt Army scan's realm and faction (TBC: Auctionator's realm key)
    auction_house_id: int
    realm: str
    faction: str
    items: int  # items priced in the scan
    moved: int  # of them, items whose current price changed
    quarantined: bool  # far off this auction house's recent prices, so not used


class UploadResult(BaseModel):
    kind: UploadKind
    detail: str  # a one-line summary
    characters: int  # altarmy: characters imported
    groups: list[GroupCount]  # altarmy: by realm and faction
    realms: list[RealmPricesOut]  # the auction house scans recorded (those already known are left out)


class UploadOut(BaseModel):
    id: int
    game_version: str
    kind: UploadKind
    via: UploadVia
    size: int  # bytes, decompressed
    received_at: str  # "YYYY-MM-DD HH:MM:SS" UTC
    outcome: Literal["accepted", "rejected"]
    detail: str


class JobStatusOut(BaseModel):
    """A scheduled job's newest run (every field but `job` and `late` None if it never ran)."""

    job: str
    game_version: str | None  # None: the run covered every version
    last_started: str | None
    last_finished: str | None  # None while running
    ok: bool | None  # None while running
    late: bool  # it should have run again by now (or never ran)
    summary: str


class JobRunOut(BaseModel):
    id: int
    job: str
    game_version: str | None
    started_at: str
    finished_at: str | None
    ok: bool | None
    summary: str


class AdminUploadOut(UploadOut):
    user_uid: str


class UploadStatsOut(BaseModel):
    accepted_24h: int
    rejected_24h: int
    accepted_7d: int
    rejected_7d: int
    uploaders_7d: int
    recent: list[AdminUploadOut]  # every user's newest, newest first


class SnapshotStatsOut(BaseModel):
    source: str
    snapshots_24h: int
    snapshots_7d: int
    quarantined_7d: int
    items_7d: int
    newest_received_at: str


class IngestionOut(BaseModel):
    """What the ingestion jobs and uploads have been doing (the Admin page)."""

    now: str  # the server's time, which `late` was judged at
    jobs: list[JobStatusOut]  # every scheduled job, in jobs.CADENCE order
    runs: list[JobRunOut]  # the newest runs, newest first
    uploads: UploadStatsOut
    snapshots: list[SnapshotStatsOut]  # per source, by name
    can_run: list[str]  # the jobs Run now can start here (none where nothing launches them)


class JobStartedOut(BaseModel):
    job: str
    game_version: str
    detail: str  # what to tell the admin


# --- app state and helpers -------------------------------------------------------------------------
@dataclass
class AppState:
    """One game version's cached markets, plus what every version shares."""

    version: GameVersion
    database: db.Database  # shared by every version
    cache: service.MarketCache
    rank_cache: service.RankCache
    flights: service.Flights  # rankings under way (`_ranked`)
    signals: price_signals.Signals  # shared by every version
    launcher: launch.Launcher | None  # starts jobs on demand (the Admin page); shared by every version
    _cities: Mapping[str, timing.CityMap] | None = None

    @property
    def key(self) -> str:
        return self.version.key

    @property
    def cities(self) -> Mapping[str, timing.CityMap]:
        """The version's city presets, read on first use (a bad file is a 500 then, not a failed start)."""
        if self._cities is None:
            self._cities = store.load_cities(self.version.cities_dir)
        return self._cities


def _states(request: Request) -> dict[str, AppState]:
    states: dict[str, AppState] = request.app.state.wow
    return states


def _state(
    request: Request,
    game_version: Annotated[GameVersionKey, Query(description="which game's data: tbc or forever")],
) -> AppState:
    return _states(request)[game_version]


State = Annotated[AppState, Depends(_state)]


@dataclass(frozen=True)
class AuthState:
    database: db.Database
    verifier: auth.TokenVerifier
    firebase: auth.FirebaseConfig
    per_ip: ratelimit.RateLimiter
    per_uid: ratelimit.RateLimiter
    accounts: auth.AccountAdmin | None = None  # deletes sign-in accounts


def _too_many(retry: float) -> HTTPException:
    return HTTPException(
        429, "Too many requests: slow down.", headers={"Retry-After": str(max(1, round(retry)))}
    )


def _limit_user(a: AuthState, user: auth.User) -> auth.User:
    retry = a.per_uid.hit(user.uid)
    if retry is not None:
        raise _too_many(retry)
    return user


def _auth(request: Request) -> AuthState:
    state: AuthState = request.app.state.auth
    return state


_bearer = HTTPBearer(auto_error=False, description="Firebase ID token")


def _current_user(
    request: Request, credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)]
) -> auth.User:
    """Whoever the bearer token says (401 without one). Against the Auth emulator (development only: it
    accepts unsigned tokens, so it never serves a real site) everyone is an admin."""
    a = _auth(request)
    if credentials is None:
        raise HTTPException(401, "Sign in first.", headers={"WWW-Authenticate": "Bearer"})
    try:
        user = auth.user_from_claims(a.verifier.verify(credentials.credentials))
    except auth.InvalidToken as e:
        raise HTTPException(401, f"Invalid sign-in token: {e}", headers={"WWW-Authenticate": "Bearer"}) from e
    if a.firebase.emulator_host:
        user = replace(user, admin=True)
    _limit_user(a, user)
    with a.database.begin() as conn:
        users.ensure_user(conn, user)
    return user


CurrentUser = Annotated[auth.User, Depends(_current_user)]


def _admin_user(user: CurrentUser) -> auth.User:
    """The current user if they are a site admin (the Firebase `admin` claim), else 403."""
    if not user.admin:
        raise HTTPException(403, "Admins only.")
    return user


AdminUser = Annotated[auth.User, Depends(_admin_user)]


@contextmanager
def _connect(state: AppState) -> Iterator[Connection]:
    """A connection in a transaction, committed when the block succeeds."""
    with state.database.begin() as conn:
        yield conn


@contextmanager
def _http_errors() -> Iterator[None]:
    """Map domain errors to HTTP. Order matters: FileNotFoundError (nothing by that name) is an OSError."""
    try:
        yield
    except FileNotFoundError as e:
        raise HTTPException(404, str(e)) from e
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    except OSError as e:
        raise HTTPException(500, str(e)) from e


def _selection_model(sel: service.Selection | None) -> SelectionModel | None:
    return None if sel is None else SelectionModel(realm=sel.realm, faction=sel.faction)


def _status(state: AppState, conn: Connection, user: auth.User) -> Status:
    gv, uid = state.key, user.uid
    sel, _ = service.selected_characters(conn, uid, gv)
    ah = service.auction_house_of(conn, gv, sel)
    return Status(
        build=db.get_build(conn, gv),
        items=db.count_rows(conn, "items", gv),
        recipes=db.count_rows(conn, "recipes", gv),
        prices=prices.count_current(conn, ah),
        characters=store.count_characters(conn, uid, gv),
        selection=_selection_model(sel),
        auction_house_id=ah,
        data_version=service.data_version(conn, uid, gv),
        price_version=prices.price_version(conn, ah),
    )


def _vendor_price(market: engine.Market, item_id: int) -> int | None:
    item = market.items.get(item_id)  # the cached market may predate the database
    return None if item is None else item.vendor_price


# --- routes ----------------------------------------------------------------------------------------
router = APIRouter(prefix="/api")


@router.get("/status")
def get_status(state: State, user: CurrentUser) -> Status:
    """Counts, the selection and the versions the front end polls to notice uploads and merges."""
    with _connect(state) as conn:
        return _status(state, conn, user)


def _characters(state: AppState, conn: Connection, user: auth.User) -> Characters:
    chars = store.load_characters(conn, user.uid, state.key)
    sel = service.selection(conn, user.uid, state.key, chars)
    imported = uploads.import_status(conn, user.uid, state.key)
    discounts = dict(state.version.reputation_discounts)
    return Characters(
        groups=[
            GroupOut(
                realm=g.realm,
                faction=g.faction,
                characters=[
                    CharacterOut(
                        name=c.name,
                        class_file=c.class_file,
                        level=c.level,
                        professions=[
                            ProfessionOut(
                                name=p.name, rank=p.rank, max_rank=p.max_rank, recipes=len(p.recipe_ids)
                            )
                            for p in c.professions
                        ],
                        talents=[
                            TalentOut(spell_id=t.spell_id, name=t.name, rank=rank, max_rank=t.max_rank)
                            for t, rank in talents.known(c.talents)
                        ],
                        vendor_discounts=[
                            VendorDiscountOut(faction=reputation.CITY_FACTIONS[f], percent=percent)
                            for f, percent in reputation.vendor_discounts(c.reputations, discounts)
                        ],
                    )
                    for c in g.characters
                ],
            )
            for g in altarmy.groups(chars)
        ],
        selection=_selection_model(sel),
        imported_at=db.timestamp_text(imported.imported_at),
        imported_via=cast(UploadVia | None, imported.imported_via),
        auto_import_at=db.timestamp_text(imported.auto_import_at),
        arcane_salvager=service.knows_arcane_salvager(chars),
    )


@router.get("/characters")
def get_characters(state: State, user: CurrentUser) -> Characters:
    with _connect(state) as conn:
        return _characters(state, conn, user)


@router.delete("/characters")
def delete_character(state: State, user: CurrentUser, realm: str, name: str) -> Characters:
    """Delete one of your characters (404 if you have none of that realm and name)."""
    with _http_errors(), _connect(state) as conn:
        service.delete_character(conn, user.uid, state.key, realm, name)
        return _characters(state, conn, user)


@router.get("/professions")
def get_professions(state: State) -> list[str]:
    """Every profession the game version's recipes belong to, by name."""
    with _connect(state) as conn:
        return store.profession_names(conn, state.key)


@router.put("/selection")
def put_selection(state: State, user: CurrentUser, body: SelectionModel) -> Status:
    """Switch realm/faction."""
    with _http_errors(), _connect(state) as conn:
        service.select(conn, user.uid, state.key, body.realm, body.faction)
        return _status(state, conn, user)


@router.get("/rank")
def get_rank(
    state: State,
    user: CurrentUser,
    unlearned: Annotated[
        engine.Unlearned,
        Query(
            description="recipes nobody has learned: none, those a character can train (see `look_ahead` "
            "and `sources`), or every recipe of their professions (all)"
        ),
    ] = "none",
    look_ahead: Annotated[
        int,
        Query(
            ge=0,
            le=engine.MAX_LOOK_AHEAD,
            description="with unlearned=train: how much more skill than a character has a recipe may need "
            "(0: only what they can train now)",
        ),
    ] = 0,
    sources: Annotated[
        Sequence[engine.Source],
        Query(
            description="with unlearned=train: what may teach the recipe: a trainer, a recipe item that can "
            "be traded (recipe), one that binds on pickup (bop)"
        ),
    ] = DEFAULT_SOURCES,
    include_trivial: Annotated[
        bool, Query(description="also recipes that can't give the crafter a skillup (grey or at the cap)")
    ] = True,
    skill_crafters: Annotated[
        list[str] | None,
        Query(
            description="the characters being skilled up: the final craft is done only by one of them, the "
            "lowest-skilled in the recipe's profession (default: anyone)"
        ),
    ] = None,
    exits: Annotated[Sequence[ExitKind], Query(description="ways the crafts may be sold")] = ALL_EXIT_KINDS,
    arcane_salvager: Annotated[
        bool,
        Query(
            description="disenchant at an Arcane Salvager: a 10% chance of a second disenchant's materials"
        ),
    ] = False,
    min_cost: Annotated[int | None, Query(description="copper")] = None,
    max_cost: Annotated[int | None, Query(description="copper")] = None,
    min_profit: Annotated[int | None, Query(description="copper")] = None,
    max_profit: Annotated[int | None, Query(description="copper")] = None,
    min_roi: Annotated[float | None, Query(description="profit / cost (0.5 = 50%)")] = None,
    max_roi: Annotated[float | None, Query(description="profit / cost (0.5 = 50%)")] = None,
    min_confidence: Annotated[
        prices.ConfidenceLevel | None,
        Query(description="only AH sales whose sell price is trusted at least this much (others all pass)"),
    ] = None,
    professions: Annotated[
        list[str] | None, Query(description="only recipes of these professions (default: every one)")
    ] = None,
    sort: Annotated[
        Literal["profit", "rate", "skill", "likely", "all_sell", "roi", "spend", "profit_each", "safe", "ah"],
        Query(
            description="profit per session (the batch; all_sell is the same), per hour of play, cheapest "
            "skill point, likely profit (`likely_profit`), ROI, least spent, profit per unit made, or the "
            "profit selling it all safely (a vendor or disenchanting: `safe`) or on the auction house "
            "(`ah`), those it isn't open to last"
        ),
    ] = "profit",
    order: Annotated[
        Literal["desc", "asc"],
        Query(description="`safe` and `ah` only: best first, or worst first (those not open to it last)"),
    ] = "desc",
    gathered: Annotated[
        list[int] | None,
        Query(description="items the user gathers: had for what selling them would make, instead of bought"),
    ] = None,
    runs: Annotated[
        bool,
        Query(
            description="with skill_crafters: rank each recipe as a run, the crafts until another recipe "
            "would give the one skilled up a cheaper skill point, not as the user's batch"
        ),
    ] = False,
    strategy: Annotated[
        Strategy,
        Query(
            description="with runs: how a climb is planned (`STRATEGIES`): as recommended, cheapest (copper "
            "alone, whatever the crafts), or no patterns (only recipes trainers teach)"
        ),
    ] = "recommended",
    working_overtime: Annotated[
        int | None,
        Query(
            ge=0,
            le=WORKING_OVERTIME_RANKS,
            description="with one character skilled up: plan as if they had Working Overtime at this rank",
        ),
    ] = None,
    bartering: Annotated[
        int | None,
        Query(
            ge=0,
            le=BARTERING_RANKS,
            description="with one character skilled up: plan as if they had Bartering at this rank",
        ),
    ] = None,
    master_chef: Annotated[
        int | None,
        Query(
            ge=0,
            le=MASTER_CHEF_RANKS,
            description="with one character skilled up: plan as if they had Master Chef at this rank",
        ),
    ] = None,
    top: Annotated[int, Query(ge=1)] = 50,
    price_version: Annotated[
        int | None, Query(description="the auction house's price version the front end knows of")
    ] = None,
    chain_length: Annotated[
        int,
        Query(ge=1, le=MAX_SKILL_CHAIN, description="with sort=skill and runs: the runs the chain may hold"),
    ] = SKILL_CHAIN,
    climber_skill: Annotated[
        int | None,
        Query(
            ge=1,
            description="rank for a character nobody uploaded instead of the selection's: the one name in "
            "skill_crafters, with the one profession in professions at this skill, knowing what comes "
            "with it and what its trainers teach up to there",
        ),
    ] = None,
) -> RankResponse:
    """What the selected realm/faction's characters can craft, the user's favorites first (not with
    `sort=skill`), then most profitable first (each a session of the user's batch of crafts, or with
    `sort=rate` per hour of play in the user's city, or with `sort=skill` cheapest expected skill point first
    (`skill_ups`), those that give none last); without characters, every recipe, crafted by one unnamed
    character (nothing is mailed). Bounds are inclusive and on the session's numbers; an omitted bound is
    unbounded (so losses are included unless `min_profit` is set)."""
    s = _selected(state, user, price_version)
    skilled = frozenset(skill_crafters or ())
    # One profession is ranked alone (most of the work skipped); several are narrowed from the full ranking.
    skill_name = professions[0] if professions and len(professions) == 1 else None
    if climber_skill is not None:
        s = _hypothetical(state, s, skilled, skill_name, climber_skill)
    s = _with_talents(s, skilled, working_overtime, bartering, master_chef)
    base, chars, no_ah = s.base, s.chars, s.no_ah
    # Without characters the ranking depends on nobody but the time settings: browsing users with the same
    # ones share it, as do those skilling up the same made-up character. The bounds and the profession
    # filter only narrow the cached, unbounded ranking, so moving them never ranks again; nor does sorting
    # it by rate or skill.
    whose = user.uid if chars and climber_skill is None else ""
    asked = engine.Learning(unlearned, look_ahead, frozenset(sources)).normalized()
    learning, planned = _strategy(strategy, asked)
    run = planned if runs and skilled else None
    chars = _trained_up(state, chars, skilled, skill_name, runs)
    gather = service.gather_values(base, gathered) if gathered else None
    climb_costs = _climb_learn_costs(state, s, skill_name, skilled) if run is not None else None

    def key_of(learning: engine.Learning, run: engine.SkillRuns | None) -> tuple[Hashable, ...]:
        return (
            whose,
            skill_name.lower() if skill_name else None,
            run,
            frozenset(gathered or ()),
            tuple(chars),
            learning,
            include_trivial,
            skilled,
            frozenset(exits),
            arcane_salvager,
            no_ah,
            s.time.key,
        )

    key = key_of(learning, run)
    matches = _ranked(
        state,
        key,
        s.token,
        lambda: service.search(
            base,
            chars,
            learning,
            engine.Filters(),
            frozenset(exits),
            no_ah,
            include_trivial,
            s.time,
            skilled,
            arcane_salvager,
            skill_name=skill_name,
            skill_run=run,
            gathered=gather,
            learn_costs=climb_costs,
        ),
    )
    if sort in ("rate", "skill"):
        ranked = matches

        def ordered() -> list[engine.Result]:
            if sort == "rate":
                return service.by_rate(ranked)
            costs = _learn_costs(state, s, ranked)  # what learning each recipe costs counts too
            return service.by_skill(ranked, lambda r: costs.get(r.recipe.id, 0))

        matches = _ranked(state, (key, sort), s.token, ordered)
    elif sort == "likely":  # cheap: ordered per request
        matches = service.by_likely(matches, s.listings, base)
    elif sort == "ah":
        matches = service.by_ah(matches, s.listings, base, ascending=order == "asc")
    elif sort == "safe":
        matches = service.by_safe(matches, ascending=order == "asc")
    elif sort in ("roi", "spend", "profit_each"):
        matches = {"roi": service.by_roi, "spend": service.by_spend, "profit_each": service.by_profit_each}[
            sort
        ](matches)
    filters = engine.Filters(min_cost, max_cost, min_profit, max_profit, min_roi, max_roi)
    matches = [r for r in matches if filters.accepts(r)]
    if min_confidence is not None:
        matches = [r for r in matches if service.confident(r, s.listings, s.watched, min_confidence)]
    if professions:
        wanted = {p.lower() for p in professions}
        matches = [r for r in matches if r.recipe.skill_name.lower() in wanted]
    if s.favorites and sort != "skill":  # a climb goes cheapest point first, favorite or not
        matches = service.favorites_first(matches, s.favorites)
    results = matches[:top]
    crafters = altarmy.crafters(chars)
    costs = _learn_costs(state, s, results)
    out = [_result_out(r, base, crafters, s, costs.get(r.recipe.id, 0)) for r in results]
    chain: list[engine.Result] = []
    strategies: list[tuple[Strategy, engine.Result, list[engine.Result]]] = []

    def chain_of(
        key: Hashable, learning: engine.Learning, run: engine.SkillRuns, first: engine.Result, length: int
    ) -> list[engine.Result]:
        # the longest chain worked out yet, continued when a longer one is asked for and it didn't end
        # (an ended chain is marked under its own key)
        chain_key = (key, "chain", first.recipe.id)
        ended_key = (key, "chain-ended", first.recipe.id)

        def short() -> list[engine.Result] | None:
            # what there is of it when it is too short and may go on, else None
            found = state.rank_cache.get(chain_key, s.token)
            if found is None:
                return []
            ended = state.rank_cache.get(ended_key, s.token) is not None
            return found if len(found) < length and not ended else None

        def work() -> list[engine.Result]:
            done = short()
            if done is not None:
                found = service.skill_chain(
                    base,
                    chars,
                    learning,
                    frozenset(exits),
                    no_ah,
                    include_trivial,
                    s.time,
                    skilled,
                    arcane_salvager,
                    run,
                    first=first,
                    steps=length,
                    gathered=gather,
                    done=done,
                )
                state.rank_cache.put(chain_key, s.token, found)
                if len(found) < length:
                    state.rank_cache.put(ended_key, s.token, [])
            return state.rank_cache.get(chain_key, s.token) or []

        if short() is None:
            return (state.rank_cache.get(chain_key, s.token) or [])[:length]
        # identical requests at once work it out once
        return state.flights.run((chain_key, s.token, length), work)[:length]

    if sort == "skill" and skill_name and run is not None and len(skilled) == 1 and matches:
        first = matches[0]
        chain = chain_of(key, learning, run, first, chain_length)
        if strategy == "recommended":
            strategies.append(("recommended", first, chain[:SKILL_CHAIN]))
            for other in STRATEGIES[1:]:
                other_learning, other_run = _strategy(other, asked)
                other_key = key_of(other_learning, other_run)
                # the cheapest climb's first run, as picking the strategy ranks it first
                started = _ranked(
                    state,
                    (other_key, "start"),
                    s.token,
                    partial(
                        _strategy_start,
                        base,
                        chars,
                        other_learning,
                        frozenset(exits),
                        no_ah,
                        include_trivial,
                        s.time,
                        skilled,
                        arcane_salvager,
                        other_run,
                        skill_name,
                        gather,
                        climb_costs,
                    ),
                )
                if started:
                    other_chain = chain_of(other_key, other_learning, other_run, started[0], SKILL_CHAIN)
                    strategies.append((other, started[0], other_chain))

    def chain_out_of(first: engine.Result, runs: list[engine.Result]) -> list[RankResult]:
        costs = _learn_costs(state, s, runs)
        got = [_result_out(r, base, crafters, s, costs.get(r.recipe.id, 0)) for r in runs]
        _learned_on_the_way(first.recipe.id, got)
        return got

    chain_out = chain_out_of(matches[0], chain) if chain else []
    strategies_costs = _learn_costs(state, s, [r for _, r, _ in strategies])
    strategies_out = [
        StrategyOut(
            key=name,
            run=_result_out(r, base, crafters, s, strategies_costs.get(r.recipe.id, 0)),
            chain=chain_out_of(r, c),
        )
        for name, r, c in strategies
    ]
    shown = [*results, *chain, *(r for _, first, c in strategies for r in (first, *c))]
    shown_out = [*out, *chain_out, *(r for o in strategies_out for r in (o.run, *o.chain))]
    return RankResponse(
        total=len(matches),
        classes={c.name: c.class_file for c in chars},
        items=_item_infos(state, s, shown),
        results=out,
        learn=_learn(state, s, [r for r, o in zip(shown, shown_out, strict=True) if _not_learned(o)]),
        chain=chain_out,
        strategies=strategies_out,
        watched_hours=s.watched,
    )


def _strategy(strategy: Strategy, learning: engine.Learning) -> tuple[engine.Learning, engine.SkillRuns]:
    """The recipes a climb planned by `strategy` may learn and how it weighs its crafts (`SkillRuns`):
    cheapest counts copper alone, at any chance of a point; the others count each craft as worth
    `engine.CRAFT_VALUE` and craft at no less than `engine.MIN_CHANCE` (unless nothing gives a point that
    often); no patterns learns only what trainers teach."""
    if strategy == "cheapest":
        return learning, engine.SkillRuns(craft_value=0.0, min_chance=0.0)
    if strategy == "no_patterns":
        return replace(learning, sources=frozenset({"trainer"})).normalized(), engine.SkillRuns()
    return learning, engine.SkillRuns()


def _strategy_start(
    base: engine.Market,
    chars: Sequence[altarmy.Character],
    learning: engine.Learning,
    exits: frozenset[str],
    no_ah: frozenset[int],
    include_trivial: bool,
    time: engine.TimeModel,
    skilled: frozenset[str],
    arcane_salvager: bool,
    run: engine.SkillRuns,
    skill_name: str,
    gathered: Mapping[int, int] | None,
    learn_costs: Mapping[int, float | None] | None,
) -> list[engine.Result]:
    """`service.strategy_start` as a ranking (the rank cache's): none or that one run."""
    found = service.strategy_start(
        base,
        chars,
        learning,
        exits,
        no_ah,
        include_trivial,
        time,
        skilled,
        arcane_salvager,
        run,
        skill_name,
        gathered=gathered,
        learn_costs=learn_costs,
    )
    return [found] if found is not None else []


def _with_talents(
    s: Selected,
    skilled: frozenset[str],
    working_overtime: int | None,
    bartering: int | None,
    master_chef: int | None = None,
) -> Selected:
    """`s` with the one character skilled up at these ranks of Working Overtime, Bartering and Master Chef
    (None: as they are); as it is without exactly one."""
    if len(skilled) != 1:
        return s
    (name,) = skilled
    chars = s.chars
    asked = (
        (talents.WORKING_OVERTIME, working_overtime),
        (talents.BARTERING, bartering),
        (talents.MASTER_CHEF, master_chef),
    )
    for spell_id, rank in asked:
        if rank is not None:
            chars = service.with_talent(chars, name, spell_id, rank)
    return s if chars is s.chars else replace(s, chars=chars)


@router.post("/evaluate")
def evaluate(state: State, user: CurrentUser, body: EvaluateRequest) -> EvaluateResponse:
    """One recipe as /api/rank would give it (a session of the user's batch of crafts), with the user's
    `choices` of sources and exit applied, and for `copies` crafts or in `city` if given. With `chain_at`, a
    run of `chain_from`'s chain, as /api/rank's `chain` has it (or for `copies` crafts at the skill it starts
    from)."""
    s = _selected(state, user, body.price_version)
    with _http_errors():
        time = service.session_model(s.time, s.cities, body.city)
    learning, planned = _strategy(
        body.strategy, engine.Learning(body.unlearned, body.look_ahead, frozenset(body.sources))
    )
    run = planned if body.runs and body.copies is None else None
    recipe_skill = next((r.skill_name for r in s.base.recipes if r.id == body.recipe_id), None)
    skilled = frozenset(body.skill_crafters)
    if body.climber_skill is not None:
        s = _hypothetical(state, s, skilled, recipe_skill or None, body.climber_skill)
    s = _with_talents(s, skilled, body.working_overtime, body.bartering, body.master_chef)
    exits = frozenset(body.exits)
    gathered = service.gather_values(s.base, body.gathered) if body.gathered else None
    # a run planned for its crafts too: its skill points are the run's, past the uploaded cap
    chars = _trained_up(state, s.chars, skilled, recipe_skill, body.runs)
    stretch: engine.SkillRun | None = None
    taken: frozenset[int] = frozenset()  # the recipes the climb took up before this run: learned by then
    if body.chain_at is not None:
        if not body.runs or body.chain_from is None or len(skilled) != 1:
            raise HTTPException(400, "A run of a chain needs runs, chain_from and one character skilled up.")
        # the run the chain follows, as /api/rank ranks it
        first = service.evaluate(
            s.base,
            chars,
            learning,
            exits,
            body.chain_from,
            {},
            s.no_ah,
            body.include_trivial,
            time,
            s.time.config.batch,
            skilled,
            "",
            body.arcane_salvager,
            skill_run=planned,
            gathered=gathered,
            learn_costs=_climb_learn_costs(state, s, recipe_skill, skilled),
        )
        before = first.climb_after[: body.chain_at - 1] if first is not None else ()
        found = (
            first.climb_after[body.chain_at - 1]
            if first is not None and len(first.climb_after) >= body.chain_at
            else None
        )
        if first is None or found is None or found.recipe is None or found.recipe.id != body.recipe_id:
            raise HTTPException(404, "That run is no longer part of the climb.")
        # as `service.skill_chain` plans it: the climber at the skill it starts from
        chars = service.at_skill(chars, first.crafter, found.recipe.skill_name, found.start_skill)
        taken = frozenset({first.recipe.id, *(b.recipe.id for b in before if b.recipe is not None)})
        if body.copies is None:
            stretch, run = found, planned
    r = service.evaluate(
        s.base,
        chars,
        learning,
        exits,
        body.recipe_id,
        body.choices,
        s.no_ah,
        body.include_trivial,
        time,
        stretch.crafts if stretch is not None else body.copies or s.time.config.batch,
        skilled,
        body.crafter or "",
        body.arcane_salvager,
        skill_run=run,
        gathered=gathered,
        learn_costs=(
            _climb_learn_costs(state, s, recipe_skill, skilled)
            if run is not None and stretch is None
            else None
        ),
        stretch=stretch,
        scope=body.runs and bool(skilled),  # a skill climb's run, planned as /api/rank plans it
    )
    if r is None:
        raise HTTPException(404, "These characters can't craft and sell that recipe.")
    out = _result_out(
        r, s.base, altarmy.crafters(s.chars), s, _learn_costs(state, s, [r]).get(r.recipe.id, 0)
    )
    if r.recipe.id in taken:
        _learned_by_then(out)
    return EvaluateResponse(result=out, items=_item_infos(state, s, [r]), watched_hours=s.watched)


EVENTS = logging.getLogger("altarmy_site.events")
# What the front end may say happened: whether Next up, the skill checklist and gathering get used decides
# what is built next. Nothing about who: no user, realm or character.
EventName = Literal[
    "aim_chosen", "next_up_shown", "row_opened", "copy_steps", "gather_toggled", "coach_shown"
]


class EventIn(BaseModel):
    name: EventName
    # a few words of context (the profession, the aim); never anything about the user
    props: dict[Annotated[str, Field(max_length=32)], str | int | bool] = Field(default={}, max_length=8)


@router.post("/events", status_code=204)
def post_event(state: State, user: CurrentUser, body: EventIn) -> None:
    """Note that something happened in the front end: one JSON log line, anonymous."""
    props = {k: v[:64] if isinstance(v, str) else v for k, v in body.props.items()}
    EVENTS.info(json.dumps({**props, "event": body.name, "game_version": state.key}))


@dataclass(frozen=True)
class Selected:
    """What a search runs on: the selection's market (priced by its auction house), characters,
    never-on-the-AH items, the user's time model and the cities the selection's faction crafts in."""

    base: engine.Market
    listings: Mapping[int, prices.Listing]  # what the auction house lists, for the sale flags
    chars: list[altarmy.Character]
    no_ah: frozenset[int]
    favorites: frozenset[int]  # recipe ids
    time: engine.TimeModel
    cities: list[timing.CityMap]
    faction: str = ""  # the selection's (Horde, Alliance); "" without one
    watched: float = 0.0  # `prices.watched_hours` of the auction house
    token: Hashable = None  # what the market was built from (`service.Held.token`): the rank cache's key
    selection: service.Selection | None = None  # the realm and faction selected; None without one


def _hypothetical(
    state: AppState, s: Selected, skilled: frozenset[str], profession: str | None, skill: int
) -> Selected:
    """`s` for a character nobody uploaded (`service.hypothetical_character`) in place of the selection's
    characters: the one name in `skilled`, with `profession` at `skill`. Everything that looks the one
    skilled up by name in `Selected.chars` then finds them."""
    if s.selection is None:
        raise HTTPException(400, "Pick a realm first.")
    if skill > state.version.max_skill:
        raise HTTPException(400, f"The skill can't be over {state.version.max_skill}.")
    if len(skilled) != 1:
        raise HTTPException(400, "climber_skill needs exactly one name in skill_crafters.")
    if profession is None:
        raise HTTPException(400, "climber_skill needs exactly one profession.")
    (name,) = skilled
    with _http_errors():
        who = service.hypothetical_character(
            s.base.recipes,
            s.selection.realm,
            s.selection.faction,
            name,
            profession,
            skill,
            state.version.max_skill,
            state.version.max_level,
        )
    return replace(s, chars=[who])


def _ranked(
    state: AppState, key: Hashable, token: Hashable, make: Callable[[], list[engine.Result]]
) -> list[engine.Result]:
    """`make()`, kept in the rank cache under `key` for markets of `token` (`service.Held`); identical
    requests at once (several tabs, a refetch) make it once, the others waiting for it."""
    found = state.rank_cache.get(key, token)
    if found is not None:
        return found

    def work() -> list[engine.Result]:
        got = state.rank_cache.get(key, token)
        if got is None:
            got = make()
            state.rank_cache.put(key, token, got)
        return got

    return state.flights.run((key, token), work)


def _selected(state: AppState, user: auth.User, price_version: int | None = None) -> Selected:
    """`price_version`: the one the front end knows of (see `MarketCache.get`)."""
    with _connect(state) as conn:
        sel, chars = service.selected_characters(conn, user.uid, state.key)
        ah = service.auction_house_of(conn, state.key, sel)
        no_ah = _no_ah(state, conn, user)
        favorites = frozenset(i for i, _ in store.load_favorites(conn, user.uid, state.key))
        faction = sel.faction if sel else ""
        model = service.time_model(conn, user.uid, state.key, state.cities, faction)
    held = state.cache.get_held(ah, at_least=price_version)
    priced = held.priced
    return Selected(
        priced.market,
        priced.listings,
        chars,
        no_ah,
        favorites,
        model,
        service.faction_cities(state.cities, faction),
        faction,
        priced.watched,
        held.token,
        sel,
    )


def _item_infos(
    state: AppState, s: Selected, results: Sequence[engine.Result], more: Collection[int] = ()
) -> dict[int, ItemInfo]:
    """Tooltip details for every item the results mention, and `more`."""
    item_ids = (
        {s.item_id for r in results for s in r.steps}
        | {i for r in results for i, _ in r.recipe.reagents}
        | {m.item_id for r in results for e in r.exits for m in e.materials}
        | {r.overtaken_by_item for r in results if r.overtaken_by_item}
        | set(more)
    )
    with _connect(state) as conn:
        return _item_details(state, conn, store.Priced(s.base, dict(s.listings), s.watched), item_ids)


def _not_learned(r: RankResult) -> bool:
    """The results table's "not learned": a profession's recipe the plan has someone learn (nobody knows
    it, or only another character than the one skilled up who crafts it)."""
    return r.kind in ("craft", "enchant") and bool(r.crafter) and r.crafter not in r.crafters


def _learned_on_the_way(first: int, chain: Sequence[RankResult]) -> None:
    """A chain's runs of a recipe the climb already took up (the run crafted now, `first`, or one before in
    the chain): learned by then, so nothing to learn or pay for again."""
    seen = {first}
    for r in chain:
        if r.recipe_id in seen:
            _learned_by_then(r)
        seen.add(r.recipe_id)


def _learned_by_then(r: RankResult) -> None:
    """`r`, a run of a recipe its climb took up before: its crafter knows it by then."""
    if r.crafter:
        r.learn_cost = 0
        r.crafters = sorted({*r.crafters, r.crafter})


def _trained_up(
    state: AppState,
    chars: list[altarmy.Character],
    skilled: frozenset[str],
    skill_name: str | None,
    climbing: bool,
) -> list[altarmy.Character]:
    """For a climb (`runs` asked for, one character skilled up; planned for some copies too), `chars` with
    the climber's profession capped at the highest skill their level lets them train to: they are assumed
    to train each rank as they come to it (the skill workspace reminds them where, from `/api/versions`'
    `profession_ranks`), but not one their level doesn't allow yet."""
    if not climbing or len(skilled) != 1:
        return chars
    (name,) = skilled
    who = next((c for c in chars if c.name == name), None)
    cap = state.version.trainable_cap(who.level if who is not None else 0)
    return service.trained_up(chars, name, skill_name, cap)


def _climb_learn_costs(
    state: AppState, s: Selected, skill_name: str | None, skilled: frozenset[str]
) -> dict[int, float | None] | None:
    """What learning each recipe of `skill_name`'s profession (every profession's, without one) costs the one
    character skilled up (`service.climb_learn_costs`), for a climb; None unless one character is."""
    if len(skilled) != 1:
        return None
    (name,) = skilled
    who = next((c for c in s.chars if c.name == name), None)
    if who is None:
        return None
    wanted = skill_name.lower() if skill_name else None
    spells = {
        r.spell_id
        for r in s.base.recipes
        if (wanted is None or r.skill_name.lower() == wanted) and service.needs_pattern(r, who)
    }
    taught = {}
    if spells:
        with _connect(state) as conn:
            taught = store.load_recipe_items(conn, state.key, spells)
    return service.climb_learn_costs(s.base, who, skill_name, taught, s.faction)


def _learn_costs(state: AppState, s: Selected, results: Sequence[engine.Result]) -> dict[int, int | None]:
    """What learning each result's recipe costs its crafter (`service.learn_cost`), by recipe id, those that
    cost nothing left out; the patterns are looked up only for the recipes a crafter must buy one for."""
    known = {r.recipe.id: service.learn_cost(r, s.chars, {}, {}, s.faction) for r in results}
    out: dict[int, int | None] = {rid: cost for rid, cost in known.items() if cost}
    unknown = [r for r in results if known[r.recipe.id] is None]
    if not unknown:
        return out
    with _connect(state) as conn:
        taught = store.load_recipe_items(conn, state.key, {r.recipe.spell_id for r in unknown})
    out.update(
        {r.recipe.id: service.learn_cost(r, s.chars, taught, s.base.prices, s.faction) for r in unknown}
    )
    return out


def _learn(state: AppState, s: Selected, results: Sequence[engine.Result]) -> dict[int, LearnOut]:
    """Where to learn each result's recipe, leaving out places that serve only the other faction."""
    if not results:
        return {}
    with _connect(state) as conn:
        taught = store.load_recipe_items(conn, state.key, {r.recipe.spell_id for r in results})
    faction = s.faction
    other = {"horde": "alliance", "alliance": "horde"}.get(faction.lower(), "")
    return {
        r.recipe.id: LearnOut(
            source=r.recipe.source,
            skill=r.recipe.required_skill,
            profession=r.recipe.skill_name,
            train_cost=r.recipe.train_cost if r.recipe.source == "trainer" else 0,
            items=[
                RecipeItemOut(
                    item_id=i.item_id,
                    name=i.name,
                    places=[PlaceOut(**asdict(p)) for p in i.places if not other or p.side != other],
                    price=service.pattern_price([i], s.base.prices, faction),
                    limited=any(p.kind == "vendor" and p.limited and p.side != other for p in i.places),
                )
                for i in taught.get(r.recipe.spell_id, [])
            ],
        )
        for r in results
    }


def _item_details(
    state: AppState, conn: Connection, priced: store.Priced, item_ids: Iterable[int]
) -> dict[int, ItemInfo]:
    details = store.load_item_details(conn, state.key, item_ids)
    base = priced.market
    out = {}
    for i, d in details.items():
        listing = priced.listings.get(i)
        counted = {lv.price for lv in base.books.get(i, ())}
        item = base.items.get(i)
        out[i] = ItemInfo(
            **asdict(d),
            ah_price=listing.min_buyout if listing else None,
            ah_sell_price=base.sell_prices.get(i),
            ah_quantity=listing.quantity if listing else None,
            ah_levels=[
                LevelOut(
                    price=lv.price,
                    quantity=lv.quantity,
                    counted=lv.price in counted,
                    more=lv.tail,
                    listings=lv.listings,
                    age=lv.age,
                )
                for lv in (listing.ladder if listing else ())
            ],
            vendor_price=_vendor_price(base, i),
            market_price=listing.market_price if listing else None,
            median_7d=listing.median_7d if listing else None,
            scans_7d=listing.scans_7d if listing else None,
            sale_price=listing.sale_price if listing else None,
            sold_7d=round((listing.sale_rate or 0.0) * prices.SALES_DAYS) if listing else 0,
            sold_pairs_7d=listing.sold_pairs_7d if listing else None,
            listed=listing.listed if listing else None,
            seen_at=listing.seen_at if listing else None,
            stack_size=item.stack_size if item else 1,
        )
    return out


def _timing_out(t: timing.Timing, profit: int, city: timing.CityMap) -> TimingOut:
    def name(loc_id: str) -> str:
        return city.location(loc_id).name

    return TimingOut(
        city=t.city,
        fixed_seconds=t.fixed_seconds,
        per_craft_seconds=t.per_craft_seconds,
        total_seconds=t.total_seconds,
        per_hour=t.per_hour(profit),
        breakdown=dict(t.breakdown),
        legs=[
            LegOut(
                who=leg.who,
                from_id=leg.from_id,
                from_name=name(leg.from_id),
                to_id=leg.to_id,
                to_name=name(leg.to_id),
                seconds=leg.seconds,
            )
            for leg in t.legs
        ],
        unsold=sorted(t.unsold),
        missing=sorted(t.missing),
        deployed=sorted(t.deployed),
    )


def _timed_city(model: engine.TimeModel, t: timing.Timing) -> timing.CityMap:
    """The city a timing was worked out in: the model's own, or with `fastest` the one that won."""
    return next(c for c in (model.city, *model.fastest) if c.name == t.city)


def _cities_out(
    r: engine.Result, base: engine.Market, cities: Sequence[timing.CityMap]
) -> list[CityTimingOut]:
    """The result in each city: as planned there if it was (the cities it is timed in, or an alternative's:
    `service.best_of`), else its plan timed there with the vendor buys at that city's prices
    (`engine.cost_in`)."""
    if r.time_model is None:
        return []
    out = []
    for city in cities:
        plan, profit = r, r.revenue - engine.cost_in(r, city, base.items)
        for planned in (r, *r.alternatives):
            model = planned.time_model
            if model is not None and city in (model.fastest or (model.city,)):
                plan, profit = planned, planned.profit
                break
        t = plan.timing
        if t is None or t.city != city.name:
            assert plan.time_model is not None
            t = engine.time_result(plan, replace(plan.time_model, city=city, fastest=()))
        out.append(
            CityTimingOut(
                city=city.name,
                total_seconds=t.total_seconds,
                per_hour=t.per_hour(profit),
                profit=profit,
                missing=sorted(t.missing),
            )
        )
    return out


def _best_city(cities: Sequence[CityTimingOut]) -> str | None:
    """The city paying most per hour (see `service.city_worth`); None if none has every station."""
    possible = [c for c in cities if not c.missing]
    if not possible:
        return None
    return max(possible, key=lambda c: service.city_worth(True, c.profit, c.per_hour, c.total_seconds)).city


def _milestones(climb: engine.ClimbPlan | None) -> list[MilestoneOut]:
    """What `climb` comes to by each profession rank's cap above where it starts that it reaches."""
    if climb is None or not climb.runs:
        return []
    out = []
    for rank in versions.PROFESSION_RANKS:
        spent = climb.spent_by(rank.cap) if rank.cap > climb.runs[0].start_skill else None
        crafts = climb.crafts_by(rank.cap)
        if spent is not None and crafts is not None:
            out.append(
                MilestoneOut(skill=rank.cap, cost=round(spent[0]), unknown=spent[1], crafts=round(crafts))
            )
    return out


def _result_out(
    r: engine.Result,
    base: engine.Market,
    crafters: dict[int, list[str]],
    s: Selected,
    learn_cost: int | None = 0,
) -> RankResult:
    listings = s.listings
    per_city = _cities_out(r, base, s.cities)
    sure = service.price_confidence(r, listings, s.watched)
    sell_price = base.sell_prices.get(r.recipe.output_item_id)
    likely = service.likely(r, listings, sell_price)
    safe = service.safe_profit(r)
    ah = service.ah_sale(r, listings, sell_price)
    t = r.timing

    def faction(who: str, item_id: int, percent: int) -> str:
        """The faction whose standing takes `percent` off that vendor buy in the result's city."""
        if not percent:
            return ""
        return reputation.CITY_FACTIONS.get(engine.reputation_faction(r, who, item_id), "")

    return RankResult(
        recipe_id=r.recipe.id,
        recipe=r.recipe.name,
        kind=cast(Literal["craft", "convert", "flip", "enchant"], r.recipe.kind),
        profession=r.recipe.skill_name,
        crafters=crafters.get(r.recipe.spell_id, []),
        crafter=r.crafter,
        output_item_id=r.recipe.output_item_id,
        output_name=r.recipe.name
        if r.recipe.is_enchant
        else base.items[r.recipe.output_item_id].name
        if r.recipe.output_item_id in base.items
        else "?",
        output_count=r.recipe.output_count,
        cost=r.cost,
        revenue=r.revenue,
        profit=r.profit,
        roi=r.roi,
        best_exit=r.best_exit,
        slow=service.slow_to_sell(r, listings, base.sell_prices.get(r.recipe.output_item_id)),
        days_to_sell=service.days_to_sell(r, listings, base.sell_prices.get(r.recipe.output_item_id)),
        short=r.short,
        postage=r.postage,
        mail_to=r.mail_to,
        bonus_output=r.bonus_output,
        skill_chance=r.skill_chance,
        skill_bonus=round(r.skill_bonus, 4),
        confidence=ConfidenceOut(**asdict(sure)) if sure else None,
        skill_ups=r.skill_ups,
        skill_ups_bonus=r.skill_ups_bonus,
        exits=[
            ExitOut(
                kind=e.kind,
                value=e.value,
                materials=[MaterialOut(**asdict(m)) for m in e.materials],
                postage=e.postage,
                mail_to=e.mail_to,
            )
            for e in r.exits
        ],
        reagents=[ItemCount(item_id=i, count=c) for i, c in r.recipe.reagents],
        steps=[
            StepOut(
                action=cast(Literal["buy", "gather", "craft", "mail", "sell"], s.action),
                item_id=s.item_id,
                name=s.name,
                quantity=s.quantity,
                value=s.value,
                via=s.via,
                who=s.who,
                paths=list(s.paths),
                discount=s.discount,
                rep_discount=s.rep_discount,
                rep_faction=faction(s.who, s.item_id, s.rep_discount),
                bonus=s.bonus,
                seconds=s.seconds,
                station=s.station,
                lead_seconds=s.lead_seconds,
                convert=s.convert,
                enchant=s.enchant,
            )
            for s in r.steps
        ],
        tree=_node_out(r.tree, faction),
        learn_cost=learn_cost,
        buy_flags=list(service.buy_flags(r, s.base)),
        likely_profit=likely.profit,
        likely_exit=likely.exit,
        depth_units=likely.depth_units,
        excess_units=likely.excess_units,
        safe_profit=None if safe is None else safe[1],
        safe_exit=None if safe is None else safe[0],
        ah_profit=None if ah is None else ah.profit,
        ah_depth_units=0 if ah is None else ah.depth_units,
        ah_excess_units=0 if ah is None else ah.excess_units,
        learn_skill=r.recipe.learn_skill,
        trivial_low=r.recipe.trivial_low,
        trivial_high=r.recipe.trivial_high,
        stop_skill=r.stop_skill,
        stop_reason=r.stop_reason,
        overtaken_by=r.overtaken_by,
        overtaken_by_item=r.overtaken_by_item,
        crafts_p80=r.crafts_p80,
        reach_chances=[round(c, 4) for c in r.reach_chances],
        point_crafts=[round(c, 2) for c in r.point_crafts],
        climb_cost=round(r.climb_cost) if r.climb_cost is not None else None,
        climb_unknown=r.climb_unknown,
        climb_end=r.climb.runs[-1].stop_skill if r.climb is not None and r.climb.runs else 0,
        milestones=_milestones(r.climb),
        sell_options=[SellOptionOut(**asdict(o)) for o in r.sell_options],
        timing=None
        if t is None or r.time_model is None
        else _timing_out(t, r.profit, _timed_city(r.time_model, t)),
        cities=per_city,
        best_city=_best_city(per_city),
        crafts=r.crafts,
        details=_details_out(r),
    )


def _details_out(r: engine.Result) -> list[DetailOut]:
    city = engine.timed_city(r)
    if city is None:
        return []

    area = city.zone.area if city.zone is not None and city.zone.area else None

    def where(loc_id: str) -> LocationOut:
        loc = city.location(loc_id)
        coords = city.map_coords(loc_id)
        return LocationOut(
            id=loc.id,
            kind=loc.kind,
            name=loc.name,
            map_x=coords[0] if coords else None,
            map_y=coords[1] if coords else None,
            map_area=area,
        )

    return [
        DetailOut(
            kind=cast(Literal["switch", "start", "go", "step"], d.kind),
            who=d.who,
            step=d.step,
            location=where(d.location_id) if d.kind in ("start", "go") else None,
            retrieve=[ItemCount(item_id=i, count=q) for i, _, q in d.retrieve],
            seconds=d.seconds,
        )
        for d in engine.detailed_steps(r)
    ]


def _time_settings(state: AppState, conn: Connection, user: auth.User) -> TimeSettings:
    sel, _ = service.selected_characters(conn, user.uid, state.key)
    faction = sel.faction if sel else ""
    model = service.time_model(conn, user.uid, state.key, state.cities, faction)
    saved = users.get_settings(conn, user.uid, state.key).time_city
    cities = service.faction_cities(state.cities, faction)
    return TimeSettings(
        cities=[
            CityOut(
                name=c.name,
                faction=c.faction,
                hub=c.hub.name,
                locations=len(c.locations),
                vendors=len(c.vendor_items),
            )
            for c in cities
        ],
        city=saved if saved in state.cities else None,
        active=None if model.fastest else model.city.name,
        config=TimeConfigModel(**asdict(model.config)),
        defaults=TimeConfigModel(**asdict(timing.DEFAULT_CONFIG)),
    )


@router.get("/time")
def get_time(state: State, user: CurrentUser) -> TimeSettings:
    """The user's time settings: the cities the selection's faction crafts in, the one plans are timed
    in, and the seconds per action."""
    with _connect(state) as conn:
        return _time_settings(state, conn, user)


@router.put("/time")
def put_time(state: State, user: CurrentUser, body: TimeSettingsIn) -> TimeSettings:
    """Save the user's city (None: the faction's default) and time settings (those not given are reset
    to the defaults); 400 for an unknown city or a bad setting."""
    with _connect(state) as conn, _http_errors():
        service.set_time(conn, user.uid, state.key, state.cities, body.city, body.config)
        return _time_settings(state, conn, user)


def _no_ah(state: AppState, conn: Connection, user: auth.User) -> frozenset[int]:
    return frozenset(i for i, _ in store.load_ah_blocked(conn, user.uid, state.key))


def _ah_blocked(state: AppState, conn: Connection, user: auth.User) -> AhBlocked:
    blocked = store.load_ah_blocked(conn, user.uid, state.key)
    priced = state.cache.get_priced(service.selected_auction_house(conn, user.uid, state.key))
    return AhBlocked(
        items=[AhBlockedItem(item_id=i, added_at=added) for i, added in blocked],
        details=_item_details(state, conn, priced, (i for i, _ in blocked)),
    )


@router.get("/ah-blocked")
def get_ah_blocked(state: State, user: CurrentUser) -> AhBlocked:
    with _connect(state) as conn:
        return _ah_blocked(state, conn, user)


@router.put("/ah-blocked/{item_id}")
def block_ah(state: State, user: CurrentUser, item_id: int) -> AhBlocked:
    """Never sell `item_id` on the AH: /api/rank and /api/evaluate only vendor or disenchant it."""
    with _connect(state) as conn:
        store.set_ah_blocked(conn, user.uid, state.key, item_id, True)
        return _ah_blocked(state, conn, user)


@router.delete("/ah-blocked/{item_id}")
def unblock_ah(state: State, user: CurrentUser, item_id: int) -> AhBlocked:
    """Allow selling `item_id` on the AH again."""
    with _connect(state) as conn:
        store.set_ah_blocked(conn, user.uid, state.key, item_id, False)
        return _ah_blocked(state, conn, user)


def _favorites(state: AppState, conn: Connection, user: auth.User) -> Favorites:
    favorites = store.load_favorites(conn, user.uid, state.key)
    return Favorites(recipes=[FavoriteRecipe(recipe_id=i, added_at=added) for i, added in favorites])


@router.get("/favorites")
def get_favorites(state: State, user: CurrentUser) -> Favorites:
    with _connect(state) as conn:
        return _favorites(state, conn, user)


@router.put("/favorites/{recipe_id}")
def add_favorite(state: State, user: CurrentUser, recipe_id: int) -> Favorites:
    """Mark `recipe_id` as a favorite: /api/rank lists it first."""
    with _connect(state) as conn:
        store.set_favorite(conn, user.uid, state.key, recipe_id, True)
        return _favorites(state, conn, user)


@router.delete("/favorites/{recipe_id}")
def remove_favorite(state: State, user: CurrentUser, recipe_id: int) -> Favorites:
    """Unmark `recipe_id` as a favorite."""
    with _connect(state) as conn:
        store.set_favorite(conn, user.uid, state.key, recipe_id, False)
        return _favorites(state, conn, user)


# --- uploads ----------------------------------------------------------------------------------------
def _database(request: Request) -> db.Database:
    return _auth(request).database


def _upload_out(u: uploads.UploadRow) -> UploadOut:
    return UploadOut(
        id=u.id,
        game_version=u.game_version,
        kind=cast(UploadKind, u.kind),
        via=cast(UploadVia, u.via),
        size=u.size,
        received_at=db.timestamp_text(u.received_at) or "",
        outcome=cast(Literal["accepted", "rejected"], u.outcome),
        detail=u.detail,
    )


def _read_upload(file: UploadFile) -> bytes:
    """The file's bytes, un-gzipped; 413 past uploads.MAX_BYTES either way."""
    raw = file.file.read(uploads.MAX_BYTES + 1)
    try:
        return uploads.decompress(raw, uploads.MAX_BYTES)
    except uploads.TooLarge:
        raise HTTPException(413, f"Files are limited to {uploads.MAX_BYTES // 2**20} MB.") from None


@router.post("/uploads")
def post_upload(
    state: State,
    user: CurrentUser,
    background: BackgroundTasks,
    file: UploadFile,
    kind: Annotated[UploadKind, Form()],
    modified_at: Annotated[int | None, Form(description="the file's modified time, ms since 1970")] = None,
    via: Annotated[FileVia, Form()] = "browser",
) -> UploadResult:
    """Import an addon's SavedVariables file (plain or gzipped). Alt Army replaces your characters of this
    game version and, on WoW: Forever, records the auction house scans the addon took. An Auctionator file
    is refused (400) where prices come from those scans alone."""
    database = state.database
    with database.begin() as conn:
        try:
            uploads.check_rate(conn, user.uid)
        except uploads.RateLimited:
            raise HTTPException(429, "Too many uploads: try again in an hour.") from None

    def reject(size: int, why: str) -> None:
        with database.begin() as conn:
            uploads.record_upload(conn, user.uid, state.key, kind, via, size, "rejected", why)

    try:
        data = _read_upload(file)
    except HTTPException as e:
        reject(uploads.MAX_BYTES, str(e.detail))
        raise
    except ValueError as e:
        reject(0, str(e))
        raise HTTPException(400, str(e)) from e
    modified = None if modified_at is None else datetime.fromtimestamp(modified_at / 1000, UTC)
    try:
        with database.begin() as conn:
            got = uploads.ingest(conn, user.uid, state.key, kind, data, modified)
            uploads.record_upload(conn, user.uid, state.key, kind, via, len(data), "accepted", got.detail)
            moved = {ah: prices.price_version(conn, ah) for ah in got.moved_auction_house_ids}
    except ValueError as e:
        reject(len(data), str(e))
        raise HTTPException(400, str(e)) from e
    if got.auction_house_ids:
        state.cache.invalidate(got.auction_house_ids)
    # committed: browsers watching these auction houses refetch (after the response, off its latency)
    background.add_task(
        price_signals.publish_all, state.signals, state.key, {a: v for a, v in moved.items() if v is not None}
    )
    return _upload_result(got)


class PasteRequest(BaseModel):
    text: str  # the string the Alt Army addon's export shows (starts with AAX1:)


@router.post("/uploads/paste")
def post_paste(state: State, user: CurrentUser, body: PasteRequest) -> UploadResult:
    """Import the Alt Army addon's export string: replaces your characters of this game version, as an
    AltArmy_TBC.lua upload would. 400 if it is damaged or from the other game's client."""
    database = state.database
    with database.begin() as conn:
        try:
            uploads.check_rate(conn, user.uid)
        except uploads.RateLimited:
            raise HTTPException(429, "Too many uploads: try again in an hour.") from None
    size = len(body.text)

    def reject(why: str) -> None:
        with database.begin() as conn:
            uploads.record_upload(conn, user.uid, state.key, "altarmy", "paste", size, "rejected", why)

    if size > uploads.MAX_BYTES:
        reject("too large")
        raise HTTPException(413, f"Exports are limited to {uploads.MAX_BYTES // 2**20} MB.")
    try:
        with database.begin() as conn:
            got = uploads.ingest_paste(conn, user.uid, state.key, body.text)
            uploads.record_upload(conn, user.uid, state.key, "altarmy", "paste", size, "accepted", got.detail)
    except ValueError as e:
        reject(str(e))
        raise HTTPException(400, str(e)) from e
    return _upload_result(got)


def _upload_result(got: uploads.Imported) -> UploadResult:
    return UploadResult(
        kind=cast(UploadKind, got.kind),
        detail=got.detail,
        characters=got.characters,
        groups=[GroupCount(realm=r, faction=f, characters=n) for r, f, n in got.groups],
        realms=[RealmPricesOut(**asdict(r)) for r in got.realms],
    )


@router.get("/uploads")
def get_uploads(request: Request, user: CurrentUser) -> list[UploadOut]:
    """Your newest uploads (every game version), newest first."""
    with _database(request).begin() as conn:
        return [_upload_out(u) for u in uploads.recent(conn, user.uid)]


# --- admin -----------------------------------------------------------------------------------------
def _text(dt: datetime) -> str:
    return db.timestamp_text(dt) or ""


@router.get("/admin/ingestion")
def get_admin_ingestion(state: State, user: AdminUser) -> IngestionOut:
    """The version's job runs, every user's uploads and snapshots per source (admins)."""
    now = db.utcnow()
    with _connect(state) as conn:
        newest = jobs.latest(conn, state.key)
        runs = jobs.recent(conn, state.key)
        counts = uploads.stats(conn, state.key, now)
        recent = uploads.recent_all(conn, state.key)
        snapshots = prices.snapshot_stats(conn, state.key, now)
    statuses = []
    for job in jobs.CADENCE:
        run = newest.get(job)
        if run is None:
            statuses.append(
                JobStatusOut(
                    job=job,
                    game_version=None,
                    last_started=None,
                    last_finished=None,
                    ok=None,
                    late=True,
                    summary="",
                )
            )
            continue
        statuses.append(
            JobStatusOut(
                job=job,
                game_version=run.game_version,
                last_started=_text(run.started_at),
                last_finished=db.timestamp_text(run.finished_at),
                ok=run.ok,
                late=jobs.late(job, run.started_at, now),
                summary=run.summary,
            )
        )
    return IngestionOut(
        now=_text(now),
        jobs=statuses,
        runs=[
            JobRunOut(
                id=r.id,
                job=r.job,
                game_version=r.game_version,
                started_at=_text(r.started_at),
                finished_at=db.timestamp_text(r.finished_at),
                ok=r.ok,
                summary=r.summary,
            )
            for r in runs
        ],
        uploads=UploadStatsOut(
            accepted_24h=counts.accepted_24h,
            rejected_24h=counts.rejected_24h,
            accepted_7d=counts.accepted_7d,
            rejected_7d=counts.rejected_7d,
            uploaders_7d=counts.uploaders_7d,
            recent=[AdminUploadOut(**_upload_out(u).model_dump(), user_uid=u.user_uid) for u in recent],
        ),
        snapshots=[
            SnapshotStatsOut(
                source=s.source,
                snapshots_24h=s.snapshots_24h,
                snapshots_7d=s.snapshots_7d,
                quarantined_7d=s.quarantined_7d,
                items_7d=s.items_7d,
                newest_received_at=_text(s.newest_received_at),
            )
            for s in snapshots
        ],
        can_run=["ingest"] if state.launcher is not None else [],
    )


@router.post("/admin/jobs/ingest", status_code=202)
def run_ingest_job(state: State, user: AdminUser) -> JobStartedOut:
    """Start the version's game data ingest now, as the daily schedule does: the pinned build, unless it is
    loaded already (admins). 409 while a run of it is still going, 501 where nothing can start jobs."""
    if state.launcher is None:
        raise HTTPException(501, "Jobs can't be started from this server.")
    now = db.utcnow()
    with _connect(state) as conn:
        last = jobs.latest(conn, state.key).get("ingest")
    if last is not None and jobs.running(last, now):
        raise HTTPException(409, f"The {state.version.label} ingest is still running.")
    try:
        detail = state.launcher.ingest(state.version)
    except launch.LaunchError as e:
        raise HTTPException(502, str(e)) from e
    return JobStartedOut(job="ingest", game_version=state.key, detail=detail)


# --- coverage --------------------------------------------------------------------------------------
@router.get("/coverage")
def get_coverage(state: State, user: CurrentUser) -> list[CoverageOut]:
    """Each named auction house's scans: where uploads are needed. Open to every tier."""
    with _connect(state) as conn:
        found = prices.coverage(conn, state.key)
    return [
        CoverageOut(
            auction_house_id=c.auction_house_id,
            realm=c.realm,
            faction=c.faction,
            prices=c.prices,
            last_scan=db.timestamp_text(c.last_scan),
            last_scan_items=c.last_scan_items,
            scans_7d=c.scans_7d,
            uploaders_7d=c.uploaders_7d,
            watched_hours=c.watched_hours,
        )
        for c in found
    ]


# --- who and how -----------------------------------------------------------------------------------
@router.get("/config")
def get_config(request: Request) -> ConfigOut:
    """The Firebase project the front end signs in with."""
    fb = _auth(request).firebase
    return ConfigOut(
        firebase=FirebaseOut(
            api_key=fb.api_key,
            auth_domain=fb.auth_domain,
            project_id=fb.project_id,
            emulator_url=f"http://{fb.emulator_host}" if fb.emulator_host else None,
            firestore_emulator_host=fb.firestore_emulator_host,
        ),
    )


@router.get("/me")
def get_me(user: CurrentUser) -> Me:
    return Me(uid=user.uid, tier=user.tier, admin=user.admin)


@router.delete("/me", status_code=204)
def delete_me(request: Request, user: CurrentUser) -> None:
    """Delete your account: your characters, settings, AH blocks and upload history, then the
    sign-in account itself. Prices you uploaded stay in the pool, no longer linked to you."""
    a = _auth(request)
    if a.accounts is None:
        raise HTTPException(501, "Account deletion is not configured.")
    with a.database.begin() as conn:  # rolled back if the sign-in account can't be deleted
        users.delete_user(conn, user.uid)
        try:
            a.accounts.delete_user(user.uid)
        except auth.AccountError as e:
            raise HTTPException(502, f"Could not delete the sign-in account: {e}") from e


@router.get("/versions")
def get_versions(request: Request) -> list[VersionOut]:
    """The game versions served, each with the build its data comes from."""
    out = []
    for state in _states(request).values():
        with _connect(state) as conn:
            build, recipes = db.get_build(conn, state.key), db.count_rows(conn, "recipes", state.key)
        out.append(
            VersionOut(
                key=state.version.key,
                label=state.version.label,
                build=build,
                recipes=recipes,
                ah_cut=state.version.ah_cut,
                profession_ranks=[
                    ProfessionRankOut(name=r.name, train_at=r.train_at, level=r.level, cap=r.cap)
                    for r in state.version.profession_ranks
                ],
            )
        )
    return out


class _SpaFiles(StaticFiles):
    """The built front end, with index.html for the app's own pages (/addon, /manage, ...): any path
    without a file extension outside /api that has no file of its own."""

    async def get_response(self, path: str, scope: Scope) -> Response:
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as e:
            parts = PurePath(path).parts  # StaticFiles passes an OS path (backslashes on Windows)
            if e.status_code != 404 or (parts and ("." in parts[-1] or parts[0] == "api")):
                raise
            return await super().get_response("index.html", scope)


def create_app(
    game_versions: Mapping[str, GameVersion] = versions.VERSIONS,
    *,
    database: db.Database | None = None,
    static_dir: Path | None = DEFAULT_DIST,
    verifier: auth.TokenVerifier | None = None,
    firebase: auth.FirebaseConfig | None = None,
    accounts: auth.AccountAdmin | None = None,
    limits: ratelimit.Limits | None = None,
    signals: price_signals.Signals | None = None,
    launcher: launch.Launcher | None = None,
) -> FastAPI:
    """Build the app for `game_versions`, each with its own data files, sharing `database` (default:
    `DATABASE_URL`, else data/altarmy.sqlite). Touches no database or network, so tests and the
    OpenAPI export can call it freely. It never migrates its default database: each deploy does, once
    (`altarmy-site migrate`), and `altarmy-site serve` passes a database that migrates.

    The Firebase project comes from the environment (`auth.FirebaseConfig.from_env`, ValueError without
    `FIREBASE_PROJECT_ID`) unless `firebase` is given. Tokens are verified with firebase-admin unless a
    `verifier` is given (tests pass a fake one), which also deletes accounts unless `accounts` is given.
    Requests are rate-limited with `limits` (default `ratelimit.HOSTED_LIMITS`). Price signals go to the
    Firebase project's Firestore unless `signals` is given (`signals.for_project`). The Admin page's Run
    now starts jobs with `launcher`, else `launch.from_env`'s. On Cloud Run, logs become JSON lines
    (`cloudlog`), so an unhandled exception is an Error Reporting event."""
    cloudlog.configure()
    database = database or db.Database(db.default_url(), migrate=False)
    firebase = firebase or auth.FirebaseConfig.from_env()
    verifier = verifier or auth.FirebaseVerifier(firebase.project_id)
    if accounts is None and isinstance(verifier, auth.AccountAdmin):
        accounts = verifier
    limits = limits or ratelimit.HOSTED_LIMITS
    signals = signals or price_signals.for_project(firebase.project_id)
    launcher = launcher or launch.from_env(database)
    per_ip = ratelimit.RateLimiter(limits.per_ip, limits.window)
    per_uid = ratelimit.RateLimiter(limits.per_uid, limits.window)
    app = FastAPI(title="Alt Army website", version="0.1.0")
    app.state.auth = AuthState(database, verifier, firebase, per_ip, per_uid, accounts)

    @app.middleware("http")
    async def api_headers_and_ip_limit(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        if not request.url.path.startswith("/api/"):
            return await call_next(request)
        peer = request.client.host if request.client else None
        retry = per_ip.hit(ratelimit.client_ip(request.headers, peer))
        if retry is not None:
            e = _too_many(retry)
            response: Response = JSONResponse({"detail": e.detail}, 429, headers=e.headers)
        else:
            response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    app.state.wow = {
        key: AppState(
            v,
            database,
            service.MarketCache(database, v.key, ah_cut=v.ah_cut, mail_postage=v.mail_postage),
            service.RankCache(),
            service.Flights(),
            signals,
            launcher,
        )
        for key, v in game_versions.items()
    }
    app.include_router(router)
    if static_dir is not None and (static_dir / "index.html").is_file():
        app.mount("/", _SpaFiles(directory=static_dir, html=True), name="frontend")
    else:

        @app.get("/", include_in_schema=False)
        def build_hint() -> dict[str, str]:
            return {"detail": "The front end is not built. Run `npm ci` and `npm run build` in frontend/."}

    return app
