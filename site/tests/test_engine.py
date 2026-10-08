import itertools
import math
import random
from collections.abc import Sequence
from dataclasses import replace
from typing import Any

import pytest

from altarmy_site import book, engine, timing
from altarmy_site.engine import (
    ALL_EXITS,
    ALL_SOURCES,
    KEEP_EXIT,
    MAIL_POSTAGE,
    Crafter,
    DisenchantRow,
    Filters,
    Item,
    Learning,
    Market,
    Material,
    Memo,
    Node,
    Option,
    Recipe,
    Result,
    SellOption,
    Source,
    Step,
    TimeModel,
    Unlearned,
    ah_net,
    can_learn,
    can_skill_up,
    crafts_quantile,
    expected_skill_ups,
    plan_steps,
    profession_closure,
    reach_chances,
    recipes_for_characters,
    recipes_for_professions,
    skill_up_chance,
)

LINEN, THREAD, BOLT, GREEN, DUST = 1, 2, 3, 4, 5


def make_market(
    prices: dict[int, int],
    recipes: list[Recipe] | None = None,
    disenchant: list[DisenchantRow] | None = None,
    thread_vendor_price: int | None = None,
    crafters: Sequence[Crafter] = (),
    unlearned: Learning | Unlearned = "none",
    exits: frozenset[str] = ALL_EXITS,
    no_ah: frozenset[int] = frozenset(),
    extra_items: Sequence[Item] = (),
    time: TimeModel | None = None,
    reputation_discounts: dict[int, int] | None = None,
) -> Market:
    items = {
        LINEN: Item(LINEN, "Linen Cloth"),
        THREAD: Item(THREAD, "Coarse Thread", vendor_price=thread_vendor_price),
        BOLT: Item(BOLT, "Bolt of Linen"),
        GREEN: Item(GREEN, "Green Robe", quality=2, item_level=20, class_id=4, sell_price=500),
        DUST: Item(DUST, "Strange Dust"),
        **{i.id: i for i in extra_items},
    }
    recipes = (
        recipes
        if recipes is not None
        else [
            Recipe(10, "Green Robe", GREEN, 1, ((LINEN, 10), (THREAD, 1)), "Tailoring"),
        ]
    )
    return Market(
        items,
        recipes,
        prices,
        disenchant,
        crafters=crafters,
        unlearned=unlearned,
        exits=exits,
        no_ah=no_ah,
        time=time,
        reputation_discounts=reputation_discounts,
    )


def must_evaluate(m: Market, recipe: Recipe) -> Result:
    res = m.evaluate(recipe)
    assert res is not None
    return res


def test_vendor_profit() -> None:
    m = make_market({LINEN: 20, THREAD: 100})
    res = must_evaluate(m, m.recipes[0])
    assert res.cost == 300
    assert res.best_exit == "vendor"
    assert res.profit == 200


def test_ah_net_of_cut_beats_vendor() -> None:
    m = make_market({LINEN: 20, THREAD: 100, GREEN: 1000})
    res = must_evaluate(m, m.recipes[0])
    assert res.best_exit == "ah"
    assert res.revenue == ah_net(1000) == 950


def test_sells_at_the_sell_price_and_buys_at_the_price() -> None:
    # A lone 333g listing: the 7-day median says the robe sells for 1000.
    m = Market(
        make_market({}).items,
        make_market({}).recipes,
        {LINEN: 20, THREAD: 100, GREEN: 3_330_000},
        sell_prices={LINEN: 10, GREEN: 1000},
    )
    res = must_evaluate(m, m.recipes[0])
    assert res.cost == 10 * 20 + 100  # bought at the current price
    assert res.best_exit == "ah"
    assert res.revenue == ah_net(1000)


def test_sell_prices_default_to_the_prices() -> None:
    m = make_market({LINEN: 20, THREAD: 100, GREEN: 1000})
    assert m.sell_prices == m.prices


def test_disenchant_materials_are_valued_at_the_sell_price() -> None:
    de = [DisenchantRow(4, 2, 15, 25, DUST, 1.0, 1, 1)]
    base = make_market({}, disenchant=de)
    m = Market(base.items, base.recipes, {DUST: 5000}, de, sell_prices={DUST: 1000})
    assert m.disenchant_value(base.items[GREEN]) == ah_net(1000)


def test_disenchant_expected_value() -> None:
    de = [DisenchantRow(4, 2, 15, 25, DUST, 0.75, 1, 2)]  # 0.75 * 1.5 dust
    m = make_market({LINEN: 20, THREAD: 100, DUST: 1000}, disenchant=de)
    res = must_evaluate(m, m.recipes[0])
    assert res.best_exit == "disenchant"
    assert res.revenue == int(0.75 * 1.5 * ah_net(1000))
    assert res.steps[-1] == Step("sell", GREEN, "Green Robe", 1, res.revenue, via="disenchant")


def test_disenchant_exit_lists_expected_materials() -> None:
    de = [
        DisenchantRow(4, 2, 15, 25, DUST, 0.75, 1, 2),
        DisenchantRow(4, 2, 15, 25, THREAD, 0.25, 1, 1),  # unpriced: listed, but worth nothing
    ]
    m = make_market({LINEN: 20, DUST: 1000}, [], disenchant=de)
    (exit,) = [e for e in m.exits_for(GREEN) if e.kind == "disenchant"]
    assert exit.materials == (
        Material(DUST, "Strange Dust", 0.75, 1, 2, int(0.75 * 1.5 * ah_net(1000)), 0.75 * 1.5),
        Material(THREAD, "Coarse Thread", 0.25, 1, 1, None, 0.25),
    )
    assert exit.value == int(0.75 * 1.5 * ah_net(1000))
    assert all(e.materials == () for e in m.exits_for(GREEN) if e.kind != "disenchant")


def test_the_arcane_salvager_adds_a_tenth_of_a_disenchant() -> None:
    # A 10% chance of a second roll: 1.1 times the expected materials, each still 1-2 a roll.
    de = [DisenchantRow(4, 2, 15, 25, DUST, 0.75, 1, 2)]
    base = make_market({LINEN: 20, DUST: 1000}, [], disenchant=de)
    m = Market(base.items, [], base.prices, de, arcane_salvager=True)
    expected = 1.1 * 0.75 * 1.5 * ah_net(1000)
    assert m.disenchant_value(m.items[GREEN]) == int(expected)
    assert m.disenchant_materials(m.items[GREEN]) == [
        Material(DUST, "Strange Dust", 0.75, 1, 2, int(expected), 1.1 * 0.75 * 1.5)
    ]
    assert base.disenchant_value(base.items[GREEN]) == int(0.75 * 1.5 * ah_net(1000))


def test_a_flip_gains_from_the_arcane_salvager() -> None:
    (flip,) = flips(flip_market(arcane_salvager=True))
    assert must_evaluate(flip_market(arcane_salvager=True), flip).revenue == int(1.1 * 950)


def test_disenchant_ignores_wrong_item_level() -> None:
    de = [DisenchantRow(4, 2, 30, 40, DUST, 1.0, 1, 1)]
    m = make_market({LINEN: 20, THREAD: 100, DUST: 400}, disenchant=de)
    assert must_evaluate(m, m.recipes[0]).best_exit == "vendor"


def test_no_disenchant_for_an_item_flagged_so() -> None:
    # Lesser Magic Wand: a green weapon in a disenchant bracket, but ItemSparse flags it NO_DISENCHANT.
    de = [DisenchantRow(4, 2, 15, 25, DUST, 1.0, 1, 1)]
    base = make_market({}, disenchant=de)
    items = {**base.items, GREEN: replace(base.items[GREEN], disenchantable=False)}
    m = Market(items, base.recipes, {LINEN: 20, THREAD: 100, DUST: 400}, de)
    assert m.disenchant_value(items[GREEN]) is None
    assert m.disenchant_materials(items[GREEN]) == []
    assert [e.kind for e in m.exits_for(GREEN)] == ["vendor"]
    assert must_evaluate(m, m.recipes[0]).best_exit == "vendor"


def test_vendor_sold_reagent_needs_no_ah_price() -> None:
    m = make_market({LINEN: 20}, thread_vendor_price=10)
    res = must_evaluate(m, m.recipes[0])
    assert res.cost == 210
    assert res.steps[1] == Step("buy", THREAD, "Coarse Thread", 1, -10, via="vendor")
    assert res.tree.inputs[1].source == "vendor"


def test_buys_reagent_from_cheaper_of_vendor_and_ah() -> None:
    cheaper_ah = make_market({LINEN: 20, THREAD: 5}, thread_vendor_price=10)
    assert must_evaluate(cheaper_ah, cheaper_ah.recipes[0]).steps[1].via == "ah"
    cheaper_vendor = make_market({LINEN: 20, THREAD: 50}, thread_vendor_price=10)
    res = must_evaluate(cheaper_vendor, cheaper_vendor.recipes[0])
    assert (res.cost, res.steps[1].via) == (210, "vendor")
    tie = make_market({LINEN: 20, THREAD: 10}, thread_vendor_price=10)
    assert must_evaluate(tie, tie.recipes[0]).steps[1].via == "vendor"  # unlimited supply, no AH trip


def test_missing_reagent_price_skips_recipe() -> None:
    m = make_market({LINEN: 20})  # no thread price
    assert m.evaluate(m.recipes[0]) is None


def test_chain_crafts_cheaper_intermediate() -> None:
    recipes = [
        Recipe(11, "Bolt of Linen", BOLT, 1, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Tailoring"),
    ]
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, recipes)
    res = must_evaluate(m, recipes[1])
    assert res.cost == 3 * 20 + 5  # crafting bolts (20) beats buying them (100)
    assert res.steps == [
        Step("buy", LINEN, "Linen Cloth", 6, -60, via="ah"),
        Step("buy", THREAD, "Coarse Thread", 1, -5, via="ah"),
        Step("craft", BOLT, "Bolt of Linen", 3, via="Bolt of Linen"),
        Step("craft", GREEN, "Green Robe", 1, via="Green Robe"),
        Step("sell", GREEN, "Green Robe", 1, 500, via="vendor"),
    ]


def test_steps_craft_whole_batches_of_multi_output_reagents() -> None:
    recipes = [
        Recipe(11, "Bolts x2", BOLT, 2, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Tailoring"),
    ]
    m = make_market({LINEN: 10, THREAD: 5}, recipes)
    steps = must_evaluate(m, recipes[1]).steps
    assert steps[0] == Step("buy", LINEN, "Linen Cloth", 4, -40, via="ah")  # two crafts of 2 bolts
    assert steps[2] == Step("craft", BOLT, "Bolt of Linen", 4, via="Bolts x2")


def test_steps_merge_repeated_reagents() -> None:
    recipes = [
        Recipe(11, "Bolt of Linen", BOLT, 1, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 1), (LINEN, 3)), "Tailoring"),
    ]
    m = make_market({LINEN: 10}, recipes)
    steps = must_evaluate(m, recipes[1]).steps
    assert steps[0] == Step("buy", LINEN, "Linen Cloth", 5, -50, via="ah")
    assert steps[0].paths == ("r.0.0", "r.1")  # both tree nodes it stands for, in walk order


def test_steps_name_the_tree_paths_they_cover() -> None:
    recipes = [
        Recipe(11, "Bolt of Linen", BOLT, 1, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Tailoring"),
    ]
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, recipes)
    steps = must_evaluate(m, recipes[1]).steps
    assert [(s.action, s.paths) for s in steps] == [
        ("buy", ("r.0.0",)),
        ("buy", ("r.1",)),
        ("craft", ("r.0",)),
        ("craft", ("r",)),
        ("sell", ("sell",)),
    ]


def test_tree_links_reagents_to_the_crafts_that_use_them() -> None:
    recipes = [
        Recipe(11, "Bolt of Linen", BOLT, 1, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Tailoring"),
    ]
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, recipes)
    assert must_evaluate(m, recipes[1]).tree == Node(
        GREEN,
        "Green Robe",
        1,
        65,
        via="Green Robe",
        crafts=1,
        made=1,
        inputs=(
            Node(
                BOLT,
                "Bolt of Linen",
                3,
                60,
                via="Bolt of Linen",
                crafts=3,
                made=3,
                inputs=(Node(LINEN, "Linen Cloth", 6, 60, source="ah"),),
            ),
            Node(THREAD, "Coarse Thread", 1, 5, source="ah"),
        ),
    )


def test_tree_crafts_whole_batches_of_multi_output_reagents() -> None:
    recipes = [
        Recipe(11, "Bolts x2", BOLT, 2, ((LINEN, 2),), "Tailoring"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Tailoring"),
    ]
    m = make_market({LINEN: 10, THREAD: 5}, recipes)
    bolt = must_evaluate(m, recipes[1]).tree.inputs[0]
    assert (bolt.quantity, bolt.crafts, bolt.made, bolt.cost) == (3, 2, 4, 40)
    assert bolt.inputs == (Node(LINEN, "Linen Cloth", 4, 40, source="ah"),)


def test_chain_cycle_terminates() -> None:
    recipes = [
        Recipe(11, "A from B", LINEN, 1, ((THREAD, 1),)),
        Recipe(12, "B from A", THREAD, 1, ((LINEN, 1),)),
    ]
    m = make_market({}, recipes)
    assert m.evaluate(recipes[0]) is None


def test_rank_sorted_by_profit() -> None:
    recipes = [
        Recipe(10, "Cheap", GREEN, 1, ((LINEN, 1),), "Tailoring"),
        Recipe(11, "Mid", GREEN, 1, ((LINEN, 30),), "Tailoring"),
        Recipe(12, "Loser", GREEN, 1, ((LINEN, 60),), "Tailoring"),
    ]
    m = make_market({LINEN: 10}, recipes)
    ranked = m.rank()
    assert [r.recipe.name for r in ranked] == ["Cheap", "Mid"]  # Loser costs 600 vs 500 vendor


def test_only_allowed_exits_are_used() -> None:
    prices = {LINEN: 20, THREAD: 100, GREEN: 1000}
    assert must_evaluate(make_market(prices), ROBE).best_exit == "ah"
    res = must_evaluate(make_market(prices, exits=frozenset({"vendor"})), ROBE)
    assert (res.best_exit, res.revenue) == ("vendor", 500)
    assert [e.kind for e in res.exits] == ["vendor"]
    assert make_market(prices, exits=frozenset({"disenchant"})).evaluate(ROBE) is None


def test_items_never_sold_on_the_ah_use_the_other_exits() -> None:
    prices = {LINEN: 20, THREAD: 100, GREEN: 1000}
    res = must_evaluate(make_market(prices, no_ah=frozenset({GREEN})), ROBE)
    assert (res.best_exit, res.revenue) == ("vendor", 500)
    assert [e.kind for e in res.exits] == ["vendor"]
    only_ah = make_market(prices, exits=frozenset({"ah"}), no_ah=frozenset({GREEN}))
    assert only_ah.evaluate(ROBE) is None


def test_items_never_sold_on_the_ah_can_still_be_bought_there() -> None:
    res = must_evaluate(make_market({LINEN: 20, THREAD: 100}, no_ah=frozenset({THREAD})), ROBE)
    assert res.steps[1] == Step("buy", THREAD, "Coarse Thread", 1, -100, via="ah")


def test_filters_bounds_are_inclusive_and_optional() -> None:
    res = must_evaluate(make_market({LINEN: 20, THREAD: 100}), ROBE)  # cost 300, profit 200, roi 2/3
    assert Filters().accepts(res)
    assert Filters(min_cost=300, max_cost=300, min_profit=200, max_profit=200).accepts(res)
    assert not Filters(max_cost=299).accepts(res)
    assert not Filters(min_cost=301).accepts(res)
    assert not Filters(min_profit=201).accepts(res)
    assert not Filters(max_profit=199).accepts(res)
    assert Filters(min_roi=0.6, max_roi=0.7).accepts(res)
    assert not Filters(min_roi=0.7).accepts(res)
    assert not Filters(max_roi=0.6).accepts(res)


def test_recipes_for_professions_ignores_case() -> None:
    recipes = [
        Recipe(10, "Robe", GREEN, 1, ((LINEN, 1),), "Tailoring"),
        Recipe(11, "Bolt", BOLT, 1, ((LINEN, 2),), "Mining"),
        Recipe(12, "Other", DUST, 1, ((LINEN, 2),), "Enchanting"),
    ]
    got = recipes_for_professions(recipes, ["tailoring", "MINING"])
    assert [r.name for r in got] == ["Robe", "Bolt"]


def test_recipes_for_characters_known_trainable_or_whole_professions() -> None:
    recipes = [
        Recipe(10, "Robe", GREEN, 1, ((LINEN, 1),), "Tailoring", spell_id=900, trivial_low=200),
        Recipe(
            11,
            "Bolt",
            BOLT,
            1,
            ((LINEN, 2),),
            "Tailoring",
            spell_id=901,
            trivial_low=90,
            learn_skill=70,
            source="recipe",
        ),  # fmt: skip
        Recipe(12, "Cloak", GREEN, 1, ((LINEN, 3),), "Tailoring", spell_id=903, trivial_low=71),
        Recipe(13, "Dust", DUST, 1, ((LINEN, 2),), "Enchanting", spell_id=902),
    ]
    tailor = crafter("Tailor", ("Tailoring", 50), known=frozenset({900}))

    def names(unlearned: Learning | Unlearned) -> list[str]:
        return [r.name for r in recipes_for_characters(recipes, [tailor], unlearned)]

    assert names("none") == ["Robe"]
    assert names("train") == ["Robe"]
    assert names(Learning("train", 19)) == ["Robe"]
    assert names(Learning("train", 20)) == [
        "Robe",
        "Bolt",
    ]  # its pattern requires 70; the cloak is yellow from 71
    assert names(Learning("train", 20, frozenset({"trainer"}))) == ["Robe"]  # not what recipe items teach
    assert names("all") == ["Robe", "Bolt", "Cloak"]


def test_required_skill_is_the_recipe_items_else_where_it_turns_yellow() -> None:
    assert Recipe(1, "Taught by a pattern", GREEN, trivial_low=90, learn_skill=70).required_skill == 70
    assert Recipe(1, "Trainer's", GREEN, min_skill=1, trivial_low=90).required_skill == 90
    assert Recipe(1, "Trainer's", GREEN, min_skill=95, trivial_low=90).required_skill == 95


def test_can_learn_to_train_needs_the_profession_within_the_look_ahead() -> None:
    bolt = Recipe(11, "Bolt", BOLT, skill_name="Tailoring", learn_skill=70)
    soon = Learning("train", 20)
    assert can_learn(bolt, crafter("Close", ("Tailoring", 50)), soon)
    assert not can_learn(bolt, crafter("Far", ("Tailoring", 49)), soon)
    assert can_learn(bolt, crafter("Far", ("Tailoring", 49)), Learning("train", 21))
    assert can_learn(bolt, crafter("Far", ("Tailoring", 49)), "all")
    assert not can_learn(bolt, crafter("Close", ("Tailoring", 69)), "train")
    assert can_learn(bolt, crafter("Close", ("Tailoring", 69)), Learning("train", 1))
    assert can_learn(bolt, crafter("Ready", ("Tailoring", 70)), "train")
    assert not can_learn(bolt, crafter("Past", ("Tailoring", 300)), "none")
    assert not can_learn(bolt, crafter("Smith", ("Blacksmithing", 300)), soon)


def test_can_learn_to_train_only_from_the_chosen_sources() -> None:
    ready = crafter("Ready", ("Tailoring", 70))
    by_source = {
        source: Recipe(11, "Bolt", BOLT, skill_name="Tailoring", learn_skill=70, source=source)
        for source in ALL_SOURCES
    }

    def learnable(*sources: Source) -> list[str]:
        learning = Learning("train", 0, frozenset(sources))
        return sorted(s for s, r in by_source.items() if can_learn(r, ready, learning))

    assert sorted(s for s, r in by_source.items() if can_learn(r, ready, "train")) == ["recipe", "trainer"]
    assert learnable("bop") == ["bop"]
    assert learnable("trainer", "recipe", "bop") == ["bop", "recipe", "trainer"]
    assert learnable() == []
    # every recipe of the profession, whatever teaches it
    assert all(can_learn(r, ready, Learning("all", 0, frozenset())) for r in by_source.values())


def test_learning_normalized_keeps_the_look_ahead_and_sources_only_when_training() -> None:
    assert Learning("all", 5, frozenset({"bop"})).normalized() == Learning("all")
    assert Learning("none", 5).normalized() == Learning("none")
    picky = Learning("train", 5, frozenset({"bop"}))
    assert picky.normalized() == picky
    assert Learning.of("train") == Learning("train") and Learning.of(picky) is picky


def test_chain_subcrafts_through_an_alts_known_recipe() -> None:
    recipes = [
        Recipe(11, "Smelt Bolt", BOLT, 1, ((LINEN, 2),), "Mining", spell_id=1),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Blacksmithing", spell_id=2),
    ]
    prices = {LINEN: 10, THREAD: 5, BOLT: 100}
    market = make_market(
        prices, recipes_for_characters(recipes, [crafter("Alt", known=frozenset({1, 2}))], "none")
    )
    assert must_evaluate(market, recipes[1]).cost == 3 * 20 + 5


def test_chain_only_subcrafts_through_selected_professions() -> None:
    recipes = [
        Recipe(11, "Smelt Bolt", BOLT, 1, ((LINEN, 2),), "Mining"),
        Recipe(12, "Green Robe", GREEN, 1, ((BOLT, 3), (THREAD, 1)), "Blacksmithing"),
    ]
    prices = {LINEN: 10, THREAD: 5, BOLT: 100}

    smith_only = make_market(prices, recipes_for_professions(recipes, ["Blacksmithing"]))
    (res,) = smith_only.rank(min_profit=-(10**9))
    assert res.cost == 3 * 100 + 5  # must buy bolts
    assert [s.action for s in res.steps] == ["buy", "buy", "craft", "sell"]

    both = make_market(prices, recipes_for_professions(recipes, ["Blacksmithing", "Mining"]))
    res = must_evaluate(both, recipes[1])
    assert res.cost == 3 * 20 + 5
    assert Step("craft", BOLT, "Bolt of Linen", 3, via="Smelt Bolt") in res.steps


# --- mailing to an enchanter -----------------------------------------------------------------------
ROBE = Recipe(10, "Green Robe", GREEN, 1, ((LINEN, 10), (THREAD, 1)), "Tailoring", spell_id=900)
DE_ROWS = [DisenchantRow(4, 2, 15, 25, DUST, 1.0, 1, 1)]  # one dust
DE_PRICES = {LINEN: 20, THREAD: 100, DUST: 1000}  # dust nets 950, beating the 500c vendor price


def crafter(name: str, *professions: tuple[str, int], known: frozenset[int] = frozenset()) -> Crafter:
    """A crafter with (profession, rank) pairs, each capped at 375."""
    return Crafter(name, tuple((p, rank, 375) for p, rank in professions), known)


TAILOR = crafter("Tailor", ("Tailoring", 50), known=frozenset({900}))


def de_market(
    *crafters: Crafter, unlearned: Learning | Unlearned = "none", prices: dict[int, int] = DE_PRICES
) -> Market:
    return make_market(prices, [ROBE], disenchant=DE_ROWS, crafters=crafters, unlearned=unlearned)


def test_disenchant_is_free_when_the_crafter_enchants() -> None:
    both = crafter("Both", ("Enchanting", 10), ("Tailoring", 50), known=frozenset({900}))
    res = must_evaluate(de_market(both), ROBE)
    assert (res.best_exit, res.cost, res.postage, res.mail_to) == ("disenchant", 300, 0, "")
    assert "mail" not in [s.action for s in res.steps]


def test_disenchant_is_free_when_any_crafter_enchants() -> None:
    both = crafter("Both", ("Enchanting", 10), ("Tailoring", 50), known=frozenset({900}))
    res = must_evaluate(de_market(TAILOR, both), ROBE)
    assert (res.postage, res.mail_to) == (0, "")


def test_disenchant_mails_to_the_best_enchanter() -> None:
    low = crafter("Aaron", ("Enchanting", 10))
    high = crafter("Zed", ("Enchanting", 90))
    res = must_evaluate(de_market(TAILOR, low, high), ROBE)
    assert (res.best_exit, res.mail_to, res.postage) == ("disenchant", "Zed", MAIL_POSTAGE)
    assert res.cost == 300 + MAIL_POSTAGE
    assert res.revenue == 950
    (de,) = [e for e in res.exits if e.kind == "disenchant"]
    assert (de.postage, de.mail_to) == (MAIL_POSTAGE, "Zed")
    assert [s.action for s in res.steps] == ["buy", "buy", "craft", "mail", "sell"]
    assert res.steps[3] == Step("mail", GREEN, "Green Robe", 1, -MAIL_POSTAGE, via="Zed", who="Tailor")
    assert res.steps[3].paths == ("r",)  # the output's mail belongs to the recipe's craft


def test_disenchant_ties_between_enchanters_go_to_the_first_name() -> None:
    res = must_evaluate(
        de_market(TAILOR, crafter("Zed", ("Enchanting", 5)), crafter("Amy", ("Enchanting", 5))), ROBE
    )
    assert res.mail_to == "Amy"


def test_disenchant_is_dropped_without_an_enchanter() -> None:
    res = must_evaluate(de_market(TAILOR), ROBE)
    assert res.best_exit == "vendor"
    assert "disenchant" not in [e.kind for e in res.exits]


def test_postage_can_tip_the_best_exit_to_the_ah() -> None:
    # dust nets 950 by disenchanting, the robe nets 950 on the AH: postage makes the AH better
    prices = {**DE_PRICES, GREEN: 1000}
    res = must_evaluate(de_market(TAILOR, crafter("Enc", ("Enchanting", 1)), prices=prices), ROBE)
    assert (res.best_exit, res.postage, res.mail_to, res.cost) == ("ah", 0, "", 300)
    assert "mail" not in [s.action for s in res.steps]


def test_no_crafters_means_free_disenchanting() -> None:
    res = must_evaluate(de_market(), ROBE)
    assert (res.best_exit, res.postage, res.mail_to) == ("disenchant", 0, "")


def test_unlearned_recipe_can_be_crafted_by_anyone_with_the_profession() -> None:
    novice_tailor = crafter("Novice", ("Tailoring", 1))
    both = crafter("Both", ("Enchanting", 10), ("Tailoring", 1))
    assert must_evaluate(de_market(novice_tailor, both, unlearned="all"), ROBE).postage == 0
    # someone knows it, so only they craft it
    res = must_evaluate(de_market(TAILOR, both, unlearned="all"), ROBE)
    assert (res.postage, res.mail_to) == (MAIL_POSTAGE, "Both")


def test_recipe_to_train_soon_is_crafted_by_whoever_is_close_enough() -> None:
    robe = replace(ROBE, learn_skill=40)
    novice, close = crafter("Novice", ("Tailoring", 1)), crafter("Close", ("Tailoring", 20))
    train = Learning("train", 20)
    market = make_market(DE_PRICES, [robe], disenchant=DE_ROWS, crafters=(novice, close), unlearned=train)
    assert must_evaluate(market, robe).crafter == "Close"


# --- mailing intermediates between crafters ---------------------------------------------------------
SCRAPS, LEATHER, MAUL, COPPER = 6, 7, 8, 9
CURE = Recipe(20, "Light Leather", LEATHER, 1, ((SCRAPS, 3),), "Leatherworking", spell_id=950)
MAUL_RECIPE = Recipe(
    21, "Heavy Copper Maul", MAUL, 1, ((LEATHER, 2), (COPPER, 1)), "Blacksmithing", spell_id=951
)
SMITHY = crafter("Smithy", ("Blacksmithing", 50), known=frozenset({951}))
LEATHERY = crafter("Leathery", ("Leatherworking", 50), known=frozenset({950}))
BOTH = crafter("Both", ("Blacksmithing", 50), ("Leatherworking", 50), known=frozenset({950, 951}))


def maul_market(
    *crafters: Crafter,
    leather_price: int = 100,
    recipes: Sequence[Recipe] = (CURE, MAUL_RECIPE),
    include_trivial: bool = True,
    extra_items: Sequence[Item] = (),
    time: TimeModel | None = None,
    skill_crafters: frozenset[str] = frozenset(),
    unlearned: Learning | Unlearned = "none",
    exits: frozenset[str] = ALL_EXITS,
) -> Market:
    items = {
        SCRAPS: Item(SCRAPS, "Ruined Leather Scraps", stack_size=20),
        LEATHER: Item(LEATHER, "Light Leather", stack_size=20),
        MAUL: Item(MAUL, "Heavy Copper Maul", class_id=2, sell_price=1000),
        COPPER: Item(COPPER, "Copper Bar", stack_size=20),
        **{i.id: i for i in extra_items},
    }
    prices = {SCRAPS: 5, LEATHER: leather_price, COPPER: 10}
    return Market(
        items,
        list(recipes),
        prices,
        crafters=crafters,
        include_trivial=include_trivial,
        time=time,
        skill_crafters=skill_crafters,
        unlearned=unlearned,
        exits=exits,
    )


def test_intermediate_is_crafted_by_another_character_and_mailed() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY), MAUL_RECIPE)
    assert res.crafter == "Smithy"
    assert res.cost == 2 * 15 + MAIL_POSTAGE + 10  # scraps for 2 leather, one stack mailed, copper
    leather = res.tree.inputs[0]
    assert (leather.crafter, leather.mail_to, leather.postage) == ("Leathery", "Smithy", MAIL_POSTAGE)
    assert [s.paths for s in res.steps if s.item_id == LEATHER] == [("r.0",), ("r.0",)]  # craft and mail
    assert res.steps == [  # each character's buys, crafts and mails together, the one who mails first
        Step("buy", SCRAPS, "Ruined Leather Scraps", 6, -30, "ah", "Leathery"),
        Step("craft", LEATHER, "Light Leather", 2, via="Light Leather", who="Leathery"),
        Step("mail", LEATHER, "Light Leather", 2, -MAIL_POSTAGE, "Smithy", "Leathery"),
        Step("buy", COPPER, "Copper Bar", 1, -10, "ah", "Smithy"),
        Step("craft", MAUL, "Heavy Copper Maul", 1, via="Heavy Copper Maul", who="Smithy"),
        Step("sell", MAUL, "Heavy Copper Maul", 1, 1000, "vendor", "Smithy"),
    ]


def test_steps_finish_a_self_contained_character_before_switching() -> None:
    # copper (Smithy's) is the first reagent, but Leathery can do everything now and Smithy can't
    reversed_maul = replace(MAUL_RECIPE, reagents=((COPPER, 1), (LEATHER, 2)))
    res = must_evaluate(maul_market(SMITHY, LEATHERY, recipes=(CURE, reversed_maul)), reversed_maul)
    assert [(s.who, s.action) for s in res.steps] == [
        ("Leathery", "buy"),
        ("Leathery", "craft"),
        ("Leathery", "mail"),
        ("Smithy", "buy"),
        ("Smithy", "craft"),
        ("Smithy", "sell"),
    ]


def test_steps_return_to_a_character_only_when_they_must() -> None:
    # Leathery cures leather and mails it; Smithy makes the maul and mails it back; Leathery wraps it
    # (needing more scraps) and sells: Leathery buys all their scraps in their first block
    wrap = Recipe(22, "Wrapped Maul", 10, 1, ((MAUL, 1), (SCRAPS, 2)), "Leatherworking", spell_id=952)
    leathery = replace(LEATHERY, known_spells=frozenset({950, 952}))
    wrapped = Item(10, "Wrapped Maul", class_id=2, sell_price=2000)
    m = maul_market(SMITHY, leathery, recipes=(CURE, MAUL_RECIPE, wrap), extra_items=[wrapped])
    res = must_evaluate(m, wrap)
    assert res.steps == [
        Step("buy", SCRAPS, "Ruined Leather Scraps", 8, -40, "ah", "Leathery"),
        Step("craft", LEATHER, "Light Leather", 2, via="Light Leather", who="Leathery"),
        Step("mail", LEATHER, "Light Leather", 2, -MAIL_POSTAGE, "Smithy", "Leathery"),
        Step("buy", COPPER, "Copper Bar", 1, -10, "ah", "Smithy"),
        Step("craft", MAUL, "Heavy Copper Maul", 1, via="Heavy Copper Maul", who="Smithy"),
        Step("mail", MAUL, "Heavy Copper Maul", 1, -MAIL_POSTAGE, "Leathery", "Smithy"),
        Step("craft", 10, "Wrapped Maul", 1, via="Wrapped Maul", who="Leathery"),
        Step("sell", 10, "Wrapped Maul", 1, 2000, "vendor", "Leathery"),
    ]


def test_buys_the_intermediate_when_crafting_and_mailing_costs_more() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY, leather_price=20), MAUL_RECIPE)
    assert res.cost == 2 * 20 + 10  # 40 beats 30 of scraps + 30 postage
    assert res.tree.inputs[0] == Node(LEATHER, "Light Leather", 2, 40, source="ah", crafter="Smithy")
    assert "mail" not in [s.action for s in res.steps]


def test_one_character_with_both_professions_mails_nothing() -> None:
    res = must_evaluate(maul_market(BOTH), MAUL_RECIPE)
    assert (res.crafter, res.cost) == ("Both", 2 * 15 + 10)
    assert "mail" not in [s.action for s in res.steps]


def test_picks_the_final_crafter_who_needs_no_mail() -> None:
    res = must_evaluate(maul_market(SMITHY, BOTH), MAUL_RECIPE)
    assert (res.crafter, res.cost) == ("Both", 2 * 15 + 10)


def test_postage_is_per_stack() -> None:
    m = maul_market()
    assert (m.postage(LEATHER, 20), m.postage(LEATHER, 25), m.postage(MAUL, 2)) == (30, 60, 60)


def test_no_characters_means_no_postage_in_chains() -> None:
    res = must_evaluate(maul_market(), MAUL_RECIPE)
    assert (res.crafter, res.cost) == ("", 2 * 15 + 10)


# --- alternatives the user can switch to ------------------------------------------------------------
def test_nodes_list_their_options_cheapest_first() -> None:
    m = make_market({LINEN: 10, THREAD: 5}, thread_vendor_price=3)
    thread = must_evaluate(m, ROBE).tree.inputs[1]
    assert thread.options == (Option("vendor", 3, source="vendor"), Option("ah", 5, source="ah"))
    assert thread.option == "vendor"
    assert must_evaluate(m, ROBE).tree.options == ()  # the recipe's own craft has none


def test_craft_options_name_the_recipe_and_cheapest_crafter() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY), MAUL_RECIPE)
    assert res.tree.inputs[0].options == (
        Option("craft:20", 2 * 15 + MAIL_POSTAGE, via="Light Leather", crafter="Leathery"),
        Option("ah", 200, source="ah"),
    )


def test_choosing_to_craft_a_bought_reagent_adds_its_chain() -> None:
    m = maul_market(SMITHY, LEATHERY, leather_price=20)
    res = m.evaluate(MAUL_RECIPE, {"r.0": "craft:20"})
    assert res is not None
    leather = res.tree.inputs[0]
    assert (leather.via, leather.crafter, leather.mail_to) == ("Light Leather", "Leathery", "Smithy")
    assert (leather.option, leather.inputs[0].item_id) == ("craft:20", SCRAPS)
    assert res.cost == 2 * 15 + MAIL_POSTAGE + 10
    assert [s.action for s in res.steps] == ["buy", "craft", "mail", "buy", "craft", "sell"]


def test_choosing_to_buy_a_crafted_reagent_drops_its_chain() -> None:
    res = maul_market(SMITHY, LEATHERY).evaluate(MAUL_RECIPE, {"r.0": "ah"})
    assert res is not None
    assert res.tree.inputs[0] == Node(LEATHER, "Light Leather", 2, 200, source="ah", crafter="Smithy")
    assert res.cost == 200 + 10


def test_choices_below_a_choice_apply() -> None:
    m = maul_market(SMITHY, LEATHERY, leather_price=20)
    res = m.evaluate(MAUL_RECIPE, {"r.0": "craft:20", "r.0.0": "nonsense"})
    assert res is not None
    assert res.tree.inputs[0].inputs[0].source == "ah"  # an unknown key keeps the cheapest


def test_unknown_choices_are_ignored() -> None:
    m = maul_market(SMITHY, LEATHERY)
    assert m.evaluate(MAUL_RECIPE, {"r.0": "craft:999", "sell": "ah"}) == m.evaluate(MAUL_RECIPE)


def test_sell_options_rank_each_exit_by_its_best_profit() -> None:
    res = must_evaluate(de_market(TAILOR, crafter("Enc", ("Enchanting", 1))), ROBE)
    assert res.sell_options == [
        SellOption("disenchant", 950 - 300 - MAIL_POSTAGE),
        SellOption("vendor", 500 - 300),
    ]


def test_choosing_an_exit_sells_that_way() -> None:
    m = de_market(TAILOR, crafter("Enc", ("Enchanting", 1)))
    res = m.evaluate(ROBE, {"sell": "vendor"})
    assert res is not None
    assert (res.best_exit, res.profit, res.mail_to) == ("vendor", 200, "")
    assert res.sell_options == must_evaluate(m, ROBE).sell_options


# --- skillups -----------------------------------------------------------------------------------------
def test_can_skill_up_below_grey_and_under_the_cap() -> None:
    recipe = Recipe(
        1, "Rough Sharpening Stone", 1, skill_name="Blacksmithing", trivial_low=15, trivial_high=55
    )

    def smith(rank: int, cap: int = 75) -> Crafter:
        return Crafter("Smith", (("Blacksmithing", rank, cap),), frozenset())

    assert can_skill_up(recipe, smith(1))  # orange
    assert can_skill_up(recipe, smith(20))  # yellow
    assert can_skill_up(recipe, smith(54))  # green
    assert not can_skill_up(recipe, smith(55))  # grey
    assert not can_skill_up(recipe, smith(40, cap=40))  # must train first
    assert not can_skill_up(recipe, crafter("Tailor", ("Tailoring", 1)))  # not their profession
    unknown = replace(recipe, trivial_low=0, trivial_high=0)
    assert can_skill_up(unknown, smith(299, cap=300))  # thresholds unknown: a point a craft
    assert not can_skill_up(unknown, smith(300, cap=300))  # but never past the cap
    assert not can_skill_up(replace(recipe, num_skill_ups=0), smith(1))  # DB2 says it gives none


def test_skill_up_chance_falls_from_yellow_to_grey() -> None:
    recipe = Recipe(
        1, "Rough Sharpening Stone", 1, skill_name="Blacksmithing", trivial_low=15, trivial_high=55
    )

    def smith(rank: int, cap: int = 75) -> Crafter:
        return Crafter("Smith", (("Blacksmithing", rank, cap),), frozenset())

    assert skill_up_chance(recipe, smith(1)) == 1.0  # orange
    assert skill_up_chance(recipe, smith(15)) == 1.0  # just yellow
    assert skill_up_chance(recipe, smith(35)) == 0.5
    assert skill_up_chance(recipe, smith(54)) == pytest.approx(1 / 40)  # green, nearly grey
    assert skill_up_chance(recipe, smith(55)) == 0.0  # grey
    assert skill_up_chance(recipe, smith(40, cap=40)) == 0.0  # must train first
    assert skill_up_chance(recipe, crafter("Tailor", ("Tailoring", 1))) == 0.0  # not their profession
    assert skill_up_chance(replace(recipe, trivial_low=0, trivial_high=0), smith(299, cap=300)) == 1.0
    assert skill_up_chance(replace(recipe, num_skill_ups=0), smith(1)) == 0.0
    assert skill_up_chance(replace(recipe, trivial_low=55), smith(54)) == 1.0  # orange up to grey


def test_working_overtime_adds_to_the_skill_up_chance_but_never_to_grey() -> None:
    recipe = Recipe(
        1, "Rough Sharpening Stone", 1, skill_name="Blacksmithing", trivial_low=15, trivial_high=55
    )

    def smith(rank: int, cap: int = 75) -> Crafter:
        return Crafter("Smith", (("Blacksmithing", rank, cap),), frozenset(), skill_bonus=0.2)

    assert skill_up_chance(recipe, smith(35)) == pytest.approx(0.7)
    assert skill_up_chance(recipe, smith(54)) == pytest.approx(0.2 + 1 / 40)
    assert skill_up_chance(recipe, smith(1)) == 1.0  # orange: capped
    assert skill_up_chance(recipe, smith(15)) == 1.0
    assert skill_up_chance(recipe, smith(55)) == 0.0  # grey
    assert skill_up_chance(recipe, smith(40, cap=40)) == 0.0  # must train first
    plain = replace(smith(35), skill_bonus=0.0)
    assert expected_skill_ups(recipe, smith(35), 1) == pytest.approx(0.7)
    assert expected_skill_ups(recipe, smith(35), 10) > expected_skill_ups(recipe, plain, 10)
    assert expected_skill_ups(recipe, smith(35), 1000) == pytest.approx(20)  # never past grey
    assert expected_skill_ups(recipe, smith(33, cap=35), 50) == pytest.approx(2)  # nor the cap
    assert expected_skill_ups(recipe, smith(55), 10) == 0.0


def test_expected_skill_ups_fall_as_the_skill_rises() -> None:
    recipe = Recipe(
        1, "Rough Sharpening Stone", 1, skill_name="Blacksmithing", trivial_low=15, trivial_high=55
    )

    def smith(rank: int, cap: int = 75) -> Crafter:
        return Crafter("Smith", (("Blacksmithing", rank, cap),), frozenset())

    assert expected_skill_ups(recipe, smith(35), 1) == 0.5
    # each expected point takes 1/40 off the next craft's chance: 0.5 + 0.4875 + 0.4753...
    assert expected_skill_ups(recipe, smith(35), 3) == pytest.approx(0.5 + 0.4875 + 0.4875 * 39 / 40)
    assert expected_skill_ups(recipe, smith(35), 1000) == pytest.approx(20)  # never past grey
    assert expected_skill_ups(recipe, smith(1), 5) == 5  # orange: a point a craft
    # orange up to 15, then yellow: 14 sure points, then 0.975 of the rest
    assert expected_skill_ups(recipe, smith(1), 15) == pytest.approx(14 + 1)
    assert expected_skill_ups(recipe, smith(1), 16) == pytest.approx(15 + 39 / 40)
    assert expected_skill_ups(recipe, smith(1, cap=10), 50) == 9  # stops at the profession's cap
    assert expected_skill_ups(recipe, smith(33, cap=35), 50) == pytest.approx(2)
    assert expected_skill_ups(recipe, smith(55), 10) == 0.0  # grey
    unknown = replace(recipe, trivial_low=0, trivial_high=0)
    assert expected_skill_ups(unknown, smith(70), 10) == 5  # a point a craft up to the cap
    assert expected_skill_ups(recipe, None, 7) == 7  # nobody's skill is known


GREY_AT_60 = replace(MAUL_RECIPE, trivial_low=40, trivial_high=60)
VETERAN = crafter("Veteran", ("Blacksmithing", 75), ("Leatherworking", 50), known=frozenset({950, 951}))


def test_without_trivial_recipes_only_a_crafter_who_skills_up_makes_it() -> None:
    both = maul_market(SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60))
    assert must_evaluate(both, GREY_AT_60).crafter == "Veteran"  # no mail: most profitable
    skillups = maul_market(SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60), include_trivial=False)
    res = must_evaluate(skillups, GREY_AT_60)
    assert res.crafter == "Smithy"
    # the grey sub-craft of Light Leather still happens
    assert res.tree.inputs[0].crafter in ("Leathery", "Veteran")


def test_without_trivial_recipes_one_grey_for_everyone_is_dropped() -> None:
    m = maul_market(LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60), include_trivial=False)
    assert m.evaluate(GREY_AT_60) is None
    assert GREY_AT_60 not in [r.recipe for r in m.rank(min_profit=-(10**9))]


def test_without_characters_trivial_recipes_are_kept() -> None:
    m = maul_market(recipes=(CURE, GREY_AT_60), include_trivial=False)
    assert must_evaluate(m, GREY_AT_60).crafter == ""


NOVICE_SMITH = crafter("Novice", ("Blacksmithing", 45), known=frozenset({951}))


def test_the_lowest_skilled_of_the_characters_skilled_up_makes_it() -> None:
    # Veteran would make it most profitably (no mail), but the lowest skill among those chosen wins
    m = maul_market(
        SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60), skill_crafters=frozenset({"Smithy", "Veteran"})
    )
    assert must_evaluate(m, GREY_AT_60).crafter == "Smithy"
    chosen = frozenset({"Smithy", "Novice"})
    m = maul_market(SMITHY, NOVICE_SMITH, LEATHERY, recipes=(CURE, GREY_AT_60), skill_crafters=chosen)
    res = must_evaluate(m, GREY_AT_60)
    assert res.crafter == "Novice"
    assert res.tree.inputs[0].crafter == "Leathery"  # sub-crafts still by anyone


def test_a_recipe_that_skills_up_none_of_the_chosen_characters_is_dropped() -> None:
    # grey for Veteran; Smithy could skill up on it but isn't being skilled up
    m = maul_market(
        SMITHY,
        LEATHERY,
        VETERAN,
        recipes=(CURE, GREY_AT_60),
        include_trivial=False,
        skill_crafters=frozenset({"Veteran"}),
    )
    assert m.evaluate(GREY_AT_60) is None
    assert GREY_AT_60 not in [r.recipe for r in m.rank(min_profit=-(10**9))]
    # skipping the grey one, the lowest who can still skill up
    m = maul_market(
        SMITHY,
        LEATHERY,
        VETERAN,
        recipes=(CURE, GREY_AT_60),
        include_trivial=False,
        skill_crafters=frozenset({"Veteran", "Smithy"}),
    )
    assert must_evaluate(m, GREY_AT_60).crafter == "Smithy"


def test_a_character_skilled_up_can_learn_what_an_alt_already_knows() -> None:
    # Veteran knows the maul; Novice, skilled up, doesn't but could train it
    trained = replace(GREY_AT_60, learn_skill=40)
    novice = crafter("Novice", ("Blacksmithing", 45))
    train = Learning("train")
    m = maul_market(
        VETERAN, novice, recipes=(CURE, trained), skill_crafters=frozenset({"Novice"}), unlearned=train
    )
    assert must_evaluate(m, trained).crafter == "Novice"
    # nobody else gets it just for being able to learn it
    m = maul_market(VETERAN, novice, recipes=(CURE, trained), unlearned=train)
    assert must_evaluate(m, trained).crafter == "Veteran"
    # nor does a skill crafter who can't train it yet, or when nothing unlearned counts
    later = replace(trained, learn_skill=60)
    m = maul_market(
        VETERAN, novice, recipes=(CURE, later), skill_crafters=frozenset({"Novice"}), unlearned=train
    )
    assert m.evaluate(later) is None
    m = maul_market(VETERAN, novice, recipes=(CURE, trained), skill_crafters=frozenset({"Novice"}))
    assert m.evaluate(trained) is None


def test_a_character_skilled_up_may_learn_a_sub_craft_an_alt_knows() -> None:
    smith = crafter("Smith", ("Blacksmithing", 50), ("Leatherworking", 1), known=frozenset({951}))
    m = maul_market(
        smith,
        LEATHERY,
        skill_crafters=frozenset({"Smith"}),
        unlearned=Learning("train", 0, frozenset({"trainer"})),
    )
    res = must_evaluate(m, MAUL_RECIPE)
    assert res.crafter == "Smith"
    assert res.tree.inputs[0].crafter == "Smith"  # cured at home: no postage


def _smith(rank: int, cap: int = 375) -> Crafter:
    return Crafter("Smith", (("Blacksmithing", rank, cap),), frozenset())


def _recipe(i: int, low: int, high: int) -> Recipe:
    return Recipe(i, f"R{i}", 100 + i, 1, ((COPPER, 1),), "Blacksmithing", trivial_low=low, trivial_high=high)


def _climb(crafter: Crafter, *candidates: engine.Candidate, ceiling: int = 1000) -> engine.Climb:
    """Near grey a point takes many crafts: a high ceiling keeps the runs whole."""
    return engine.plan_climb(crafter, "Blacksmithing", candidates, ceiling)


def _route(plan: engine.ClimbPlan | None) -> list[tuple[str, int, int]]:
    """A plan's runs as (recipe, from, to)."""
    assert plan is not None
    return [(r.recipe.name, r.start_skill, r.stop_skill) for r in plan.runs if r.recipe is not None]


def test_a_climb_says_what_it_comes_to_by_each_skill() -> None:
    """Crafts at a craft's net cost and patterns as bought, not the spares and grind that choose the plan."""
    early = engine.Candidate(_recipe(1, 80, 100), 10.0)
    later = engine.Candidate(_recipe(2, 80, 100), 5.0, from_skill=30, learn=100.0)
    plan = _climb(_smith(10, 60), early, later).best
    assert _route(plan) == [("R1", 10, 30), ("R2", 30, 60)]
    assert plan is not None
    assert plan.spent_by(20) == (100.0, 0)  # orange: a point a craft
    assert plan.spent_by(50) == (20 * 10.0 + 100.0 + 20 * 5.0, 0)
    assert plan.spent_by(61) is None  # past where it ends
    unknown = _climb(_smith(10, 60), replace(early, learn=None)).best
    assert unknown is not None and unknown.spent_by(60) == (500.0, 1)


def _brute_cost(crafter: Crafter, candidates: Sequence[engine.Candidate], start: int, end: int) -> float:
    """The cheapest climb from `start` to `end` found by trying every recipe at every level: each stretch of
    one recipe costs its expected crafts, its spare materials (`engine.SPARE_Z` standard deviations of its
    crafts, when it costs anything), the grind of its points (`engine.GRIND` x the cheapest point there x the
    square of the crafts a point wastes) and its pattern."""
    best = math.inf

    # the smallest point at each level, spent or earned
    def cheapest_at(lvl: int) -> float:
        return min(
            (
                abs(c.cost / engine._chance_at(c.recipe, crafter, lvl))
                for c in candidates
                if lvl >= c.from_skill and engine._chance_at(c.recipe, crafter, lvl) > 0
            ),
            default=0.0,
        )

    cheapest = {lvl: cheapest_at(lvl) for lvl in range(start, end)}
    for picks in itertools.product(range(len(candidates)), repeat=end - start):
        total, ok = 0.0, True
        for idx, group in itertools.groupby(enumerate(picks, start), key=lambda x: x[1]):
            levels = [lvl for lvl, _ in group]
            c = candidates[idx]
            chances = [engine._chance_at(c.recipe, crafter, lvl) for lvl in levels]
            if any(p <= 0 for p in chances) or levels[0] < c.from_skill:
                ok = False
                break
            crafts = sum(1 / p for p in chances)
            spread = math.sqrt(sum((1 - p) / p**2 for p in chances))
            grind = sum(
                engine.GRIND * cheapest[lvl] * (1 / p - 1) ** 2
                for lvl, p in zip(levels, chances, strict=True)
            )
            total += c.cost * crafts + max(c.cost, 0.0) * engine.SPARE_Z * spread + grind + (c.learn or 0)
        if ok:
            best = min(best, total)
    return best


# GREY_AT_60: orange below 40, then a point at (60 - skill) / 20 a craft
def test_a_climb_switches_once_a_recipe_falls_behind_and_never_back() -> None:
    # The chain the planner used to give: a belt (yellow 70, grey 110), then pants (75-115) costing more a
    # craft. Both fall evenly over 40 points, the pants 5 later, so once the pants give the cheaper point
    # (past 100) they always do: the belt, then the pants, and never the belt again. The switch comes a
    # little early: the belt's last points before grey would need many spares, and grinding.
    belt = engine.Candidate(
        Recipe(1, "Belt", 101, 1, (), "Blacksmithing", trivial_low=70, trivial_high=110), 100.0
    )
    pants = engine.Candidate(
        Recipe(2, "Pants", 102, 1, (), "Blacksmithing", trivial_low=75, trivial_high=115), 160.0
    )
    route = _route(_climb(_smith(84), belt, pants).best)
    assert [name for name, _, _ in route] == ["Belt", "Pants"]
    (_, start, switch), (_, again, end) = route
    assert (start, end) == (84, 115) and switch == again and 90 <= switch <= 100
    # pants at 121 give the cheaper point from 87, and three points of belt don't pay for a run's spares
    dear = replace(pants, cost=121.0)
    assert [name for name, _, _ in _route(_climb(_smith(84), belt, dear).best)] == ["Pants"]


def test_a_climb_is_the_cheapest_way_up() -> None:
    # every way of crafting three recipes level by level, against the plan
    a = engine.Candidate(_recipe(1, 30, 50), 100.0)
    b = engine.Candidate(_recipe(2, 38, 46), 120.0)
    c = engine.Candidate(_recipe(3, 42, 60), 160.0, from_skill=36, learn=200)
    smith = _smith(32, cap=41)
    best = _climb(smith, a, b, c, ceiling=1000).best
    assert best is not None
    assert _route(best)[0][1] == 32 and _route(best)[-1][2] == 41
    assert best.cost == pytest.approx(_brute_cost(smith, (a, b, c), 32, 41))


def test_a_short_detour_must_pay_for_the_spare_materials_it_adds() -> None:
    # A from 40 (100 a craft, yellow 30, grey 70). B, learned at 44, is orange until 46 and cheaper per point
    # there (and gives a point at 46 too); switching to it for three points and back splits A's run, whose
    # spares then cost ~124 more.
    a = engine.Candidate(_recipe(1, 30, 70), 100.0)
    near = engine.Candidate(_recipe(2, 46, 47), 152.0, from_skill=44)  # saves ~25 over A: not worth it
    assert _route(_climb(_smith(40), a, near).best) == [("R1", 40, 70)]
    cheap = engine.Candidate(_recipe(2, 46, 47), 80.0, from_skill=44)  # saves ~240: worth it
    assert _route(_climb(_smith(40), a, cheap).best) == [("R1", 40, 44), ("R2", 44, 47), ("R1", 47, 70)]


def test_the_last_points_before_grey_are_left_to_another_recipe_unless_it_costs_far_more() -> None:
    # A is cheap (10 a craft) but its last points before grey at 60 take up to 20 crafts each; B (yellow 50,
    # grey 90) costs 200 a craft. In copper alone A's grind to 59 is still cheaper (10 and 20 crafts at 10
    # against ~260 a point): the grind is what hands those points to B.
    a = engine.Candidate(_recipe(1, 40, 60), 10.0)
    b = engine.Candidate(_recipe(2, 50, 90), 200.0)
    route = _route(_climb(_smith(45), a, b).best)
    assert [n for n, _, _ in route] == ["R1", "R2"] and route[0][2] <= 57
    # no hard cutoff: with B dear enough, A goes on to grey (its last point, at 1 in 20, weighs ~37 of its
    # points: B's must cost more)
    dear = engine.Candidate(_recipe(2, 50, 90), 20000.0)
    assert _route(_climb(_smith(45), a, dear).best)[0] == ("R1", 45, 60)


def test_the_grind_counts_the_chance_after_talents() -> None:
    # Working Overtime's 20% keeps A's chance up to the end: it goes further before B takes over
    a = engine.Candidate(_recipe(1, 40, 60), 10.0)
    b = engine.Candidate(_recipe(2, 50, 90), 200.0)
    plain = _route(_climb(_smith(45), a, b).best)
    overtime = _route(_climb(replace(_smith(45), skill_bonus=0.2), a, b).best)
    assert overtime[0][0] == "R1" and overtime[0][2] > plain[0][2]


def test_a_pattern_is_bought_only_when_it_pays_for_itself() -> None:
    # A alone gets there (grey at 100); B's orange points save a few thousand at most
    a = engine.Candidate(_recipe(1, 30, 100), 100.0)
    pricey = engine.Candidate(_recipe(2, 50, 90), 60.0, learn=100_000)
    assert _route(_climb(_smith(40), a, pricey).best)[0][0] == "R1"
    cheap = engine.Candidate(_recipe(2, 50, 90), 60.0, learn=50)
    assert _route(_climb(_smith(40), a, cheap).best)[0][0] == "R2"
    # a pattern of unknown price comes after every plan whose costs are known
    unknown = engine.Candidate(_recipe(2, 50, 90), 1.0, learn=None)
    climb = _climb(_smith(40), a, unknown)
    assert climb.best is not None and climb.best.unknown == 0
    assert _route(climb.best)[0][0] == "R1"
    forced = climb.first(2)
    assert forced is not None and forced.unknown == 1


def test_a_recipe_learned_on_the_way_joins_the_climb_there() -> None:
    later = engine.Candidate(_recipe(4, 50, 70), 10.0, from_skill=45)
    route = _route(_climb(_smith(30), engine.Candidate(GREY_AT_60, 100.0), later).best)
    assert route == [("Heavy Copper Maul", 30, 45), ("R4", 45, 70)]


def test_a_run_says_why_it_stops_and_how_many_crafts_to_buy_for() -> None:
    maul = engine.Candidate(GREY_AT_60, 100.0)
    belt = engine.Candidate(_recipe(2, 50, 70), 150.0)
    plan = _climb(_smith(30), maul, belt).best
    assert plan is not None
    first, then = plan.runs
    assert (first.recipe, first.reason, first.rival) == (GREY_AT_60, "rival", belt.recipe)
    assert first.start_skill == 30 and then.start_skill == first.stop_skill
    # orange to 40 (a craft a point), then a point at (60 - skill) / 20 a craft
    expected = sum(1 / engine._chance_at(GREY_AT_60, _smith(30), s) for s in range(30, first.stop_skill))
    assert first.crafts == round(expected)
    assert first.crafts_p80 >= first.crafts
    assert len(first.reach) >= first.crafts_p80 + engine.REACH_MORE
    assert first.reach[first.crafts_p80 - 1] >= 0.8
    assert first.reach[-1] >= engine.REACH_TOP  # far enough for the most the Skill options ask for
    assert (then.reason, then.rival, then.stop_skill) == ("trivial", None, 70)
    # alone it runs until it is about to turn grey
    alone = _climb(_smith(30), maul).best
    assert alone is not None and [(r.reason, r.stop_skill) for r in alone.runs] == [("trivial", 60)]
    # or to the cap
    capped = _climb(_smith(30, cap=35), maul).best
    assert capped is not None and [(r.reason, r.crafts, r.stop_skill) for r in capped.runs] == [
        ("cap", 5, 35)
    ]


def test_a_run_longer_than_the_ceiling_goes_on_as_another() -> None:
    unknown = replace(GREY_AT_60, trivial_low=0, trivial_high=0)  # a point every craft, for ever
    plan = _climb(_smith(30, cap=60), engine.Candidate(unknown, 100.0), ceiling=12).best
    assert plan is not None
    assert all(r.crafts <= 12 for r in plan.runs)
    assert {r.reason for r in plan.runs[:-1]} == {"ceiling"}
    assert plan.runs[-1].reason == "cap" and plan.runs[-1].stop_skill == 60


def test_a_profitable_recipe_is_crafted_until_its_grind_outweighs_what_it_earns() -> None:
    earns = engine.Candidate(GREY_AT_60, -100.0)
    plan = _climb(_smith(30), earns, engine.Candidate(_recipe(2, 50, 70), 150.0)).best
    assert plan is not None
    # earning gold per point beats spending it, well past where a craft costing as much would stop...
    costs = _climb(
        _smith(30), engine.Candidate(GREY_AT_60, 100.0), engine.Candidate(_recipe(2, 50, 70), 150.0)
    ).best
    assert costs is not None and plan.runs[0].stop_skill > costs.runs[0].stop_skill
    # ...but its last points, at 1 in 10 and 1 in 20, are a grind even so
    assert plan.runs[0].stop_skill == 58
    dear = _climb(_smith(30), earns, engine.Candidate(_recipe(2, 50, 70), 100_000.0)).best
    assert dear is not None and dear.runs[0].stop_skill == 60


def test_each_recipe_first_plans_the_rest_of_the_climb() -> None:
    maul = engine.Candidate(GREY_AT_60, 100.0)
    belt = engine.Candidate(_recipe(2, 50, 70), 150.0)
    climb = _climb(_smith(30), maul, belt)
    best, other = climb.first(GREY_AT_60.id), climb.first(2)
    assert best is not None and other is not None
    assert climb.best == best and best.cost < other.cost
    assert other.runs[0].recipe == belt.recipe and other.runs[0].start_skill == 30
    assert climb.first(999) is None
    # a recipe that can't give the first point can't go first
    assert _climb(_smith(30), maul, engine.Candidate(_recipe(5, 50, 70), 1.0, from_skill=40)).first(5) is None


def test_a_run_split_at_the_ceiling_buys_its_pattern_once() -> None:
    # A: a craft a point all the way (orange to the cap), 1 a craft and a 400 pattern; B: 5 a craft. A all the
    # way (150 + 400) beats A then B; split into runs of at most 100 crafts, its pattern still counts once.
    a = engine.Candidate(_recipe(1, 200, 300), 1.0, learn=400)
    b = engine.Candidate(_recipe(2, 200, 300), 5.0)
    plan = _climb(_smith(0, cap=150), a, b, ceiling=100).best
    assert plan is not None
    assert [(r.recipe and r.recipe.name, r.start_skill, r.stop_skill, r.reason) for r in plan.runs] == [
        ("R1", 0, 100, "ceiling"),
        ("R1", 100, 150, "cap"),
    ]
    assert plan.cost == pytest.approx(150 + 400)


def test_useful_crafts_are_those_for_every_point_a_recipe_can_give() -> None:
    # orange to 40 (10 crafts from 30), then (60 - s) / 20: 20/20 + 20/19 + ... + 20/1
    expected = 10 + sum(20 / (60 - s) for s in range(40, 60))
    assert engine.useful_crafts(GREY_AT_60, _smith(30)) == round(expected) == 82
    assert engine.useful_crafts(GREY_AT_60, _smith(30), most=50) == 50  # at most a ceiling's
    assert engine.useful_crafts(GREY_AT_60, _smith(55), from_skill=58) == round(20 / 2 + 20 / 1)
    assert engine.useful_crafts(GREY_AT_60, _smith(60)) == 1  # grey: none, but at least one


def test_a_climb_prices_a_recipe_up_the_ladders_its_runs_buy_from() -> None:
    # The maul's copper is listed at 10 for one unit, then at 1000: one craft looks cheap, a run of them
    # isn't. The belt's copper is a vendor's, at 50.
    belt = Recipe(
        22,
        "Copper Belt",
        10,
        1,
        ((LEATHER, 1),),
        "Blacksmithing",
        spell_id=952,
        trivial_low=50,
        trivial_high=70,
    )
    novice = replace(NOVICE_SMITH, known_spells=frozenset({951, 952}))
    ladder = (book.Level(10, 1, 1), book.Level(1000, 500, 5))
    m = maul_market(
        novice,
        LEATHERY,
        recipes=(CURE, GREY_AT_60, belt),
        skill_crafters=frozenset({"Novice"}),
        extra_items=(Item(10, "Copper Belt", sell_price=1),),
        exits=frozenset({"vendor", KEEP_EXIT}),
    )
    m.books = {COPPER: ladder}
    crafter = m._by_name["Novice"]
    (maul,) = [c for c in m._candidates("Blacksmithing", crafter, {}) if c.recipe.id == GREY_AT_60.id]
    one = must_evaluate(m, GREY_AT_60)
    assert maul.cost > -one.profit * 5  # a craft of a run, not the first craft alone
    n = engine.useful_crafts(GREY_AT_60, crafter)
    run = m.evaluate(GREY_AT_60, crafts=n)
    assert run is not None and maul.cost == pytest.approx(-run.profit / n)


def test_a_recipe_the_climber_cant_craft_yet_is_no_run() -> None:
    # learned at 60 by anyone with the profession ("all"), but not a point to the novice at 45 yet
    later = replace(
        GREY_AT_60, id=23, name="Later", spell_id=953, learn_skill=60, trivial_low=60, trivial_high=80
    )
    m = maul_market(
        NOVICE_SMITH,
        LEATHERY,
        recipes=(CURE, GREY_AT_60, later),
        skill_crafters=frozenset({"Novice"}),
        unlearned="all",
    )
    assert m.evaluate(later) is not None  # as a craft, as ever
    assert m.evaluate(later, skill_run=engine.SkillRuns()) is None
    ranked = [r.recipe.name for r in m.rank(min_profit=-(10**9), skill_run=engine.SkillRuns())]
    assert "Later" not in ranked and "Heavy Copper Maul" in ranked


def test_a_recipe_giving_no_skill_points_is_never_climbed() -> None:
    pointless = replace(_recipe(1, 80, 100), num_skill_ups=0)
    assert expected_skill_ups(pointless, _smith(10), 50) == 0.0
    assert expected_skill_ups(pointless, None, 50) == 0.0  # nor for nobody in particular
    assert engine.useful_crafts(pointless, _smith(10)) == 1
    climb = _climb(
        _smith(10, 60), engine.Candidate(pointless, 1.0), engine.Candidate(_recipe(2, 80, 100), 9.0)
    )
    assert _route(climb.best) == [("R2", 10, 60)]
    assert not engine.can_start_climb([pointless], _smith(10), "Blacksmithing")


def test_a_recipe_with_an_hour_long_cooldown_is_no_climb_candidate() -> None:
    # a transmute a climber can cast once an hour: never a climb's run, though it is still a craft
    slow = replace(GREY_AT_60, cooldown_ms=engine.CLIMB_COOLDOWN_MS)
    m = maul_market(NOVICE_SMITH, LEATHERY, recipes=(CURE, slow), skill_crafters=frozenset({"Novice"}))
    assert m.evaluate(slow) is not None
    assert m.evaluate(slow, skill_run=engine.SkillRuns()) is None
    assert not engine.can_start_climb([slow], NOVICE_SMITH, "Blacksmithing")
    quick = replace(GREY_AT_60, cooldown_ms=engine.CLIMB_COOLDOWN_MS - 1)  # ten minutes is fine
    m = maul_market(NOVICE_SMITH, LEATHERY, recipes=(CURE, quick), skill_crafters=frozenset({"Novice"}))
    assert m.evaluate(quick, skill_run=engine.SkillRuns()) is not None


def test_crafts_quantile_buys_for_unlucky_runs() -> None:
    smith = Crafter("Smith", (("Blacksmithing", 30, 375),), frozenset())
    assert crafts_quantile(GREY_AT_60, smith, 10, q=0.8) == 10  # orange: every craft a point
    yellow = Crafter("Smith", (("Blacksmithing", 40, 375),), frozenset())
    assert crafts_quantile(GREY_AT_60, yellow, 10, q=0.8) > 14  # the expected crafts from 40 to 50
    assert crafts_quantile(GREY_AT_60, yellow, 10, q=0.8, ceiling=12) == 12
    assert crafts_quantile(GREY_AT_60, yellow, 0) == 1


def test_reach_chances_give_the_odds_of_getting_there_after_each_craft() -> None:
    smith = Crafter("Smith", (("Blacksmithing", 30, 375),), frozenset())
    assert reach_chances(GREY_AT_60, smith, 3, 5) == (0.0, 0.0, 1.0, 1.0, 1.0)  # orange: every craft a point
    yellow = Crafter("Smith", (("Blacksmithing", 40, 375),), frozenset())
    odds = reach_chances(GREY_AT_60, yellow, 10, 40)
    assert list(odds) == sorted(odds) and odds[-1] < 1
    n = crafts_quantile(GREY_AT_60, yellow, 10, q=0.8)
    assert odds[n - 2] < 0.8 <= odds[n - 1]
    assert reach_chances(GREY_AT_60, yellow, 0, 2) == (1.0, 1.0)


def test_a_ranking_of_runs_plans_each_as_the_first_run_of_the_cheapest_climb() -> None:
    # Novice at 45 skilling up blacksmithing, keeping what nobody buys: the maul (70 a craft, a point at
    # (60 - skill) / 20) against a belt (200 a craft) that stays orange until 50.
    belt = Recipe(
        22,
        "Copper Belt",
        10,
        1,
        ((COPPER, 20),),
        "Blacksmithing",
        spell_id=952,
        trivial_low=50,
        trivial_high=70,
    )
    novice = replace(NOVICE_SMITH, known_spells=frozenset({951, 952}))
    unsold = (Item(10, "Copper Belt"), Item(MAUL, "Heavy Copper Maul", class_id=2, sell_price=0))
    m = maul_market(
        novice,
        LEATHERY,
        recipes=(CURE, GREY_AT_60, belt),
        skill_crafters=frozenset({"Novice"}),
        extra_items=unsold,
        exits=frozenset({"vendor", KEEP_EXIT}),
    )
    one = must_evaluate(m, GREY_AT_60)
    run = m.evaluate(GREY_AT_60, skill_run=engine.SkillRuns())
    assert run is not None
    assert (run.stop_reason, run.overtaken_by, run.overtaken_by_item) == ("rival", "Copper Belt", 10)
    assert 1 < run.crafts < 20
    assert run.skill_ups == pytest.approx(expected_skill_ups(GREY_AT_60, novice, run.crafts))
    assert run.crafts_p80 >= run.crafts
    # the rest of its climb: the belt from where the maul stops, to grey
    assert [(r.recipe and r.recipe.name, r.start_skill) for r in run.climb_after] == [
        ("Copper Belt", run.stop_skill)
    ]
    assert run.climb_cost is not None and run.climb_unknown == 0
    assert one.crafts == 1 and one.climb_cost is None and one.climb_after == ()
    ranked = {r.recipe.name: r for r in m.rank(min_profit=-(10**9), skill_run=engine.SkillRuns())}
    assert ranked["Heavy Copper Maul"].crafts == run.crafts  # the same plan as evaluated alone
    assert ranked["Heavy Copper Maul"].climb_cost == run.climb_cost
    belt_first = ranked["Copper Belt"].climb_cost
    assert belt_first is not None and belt_first >= run.climb_cost
    assert m.evaluate(GREY_AT_60, crafts=3).crafts == 3  # type: ignore[union-attr]  # without runs: as asked


def _maul_and_belt() -> tuple[Market, Recipe]:
    """Novice at 45 skilling up blacksmithing, keeping what nobody buys: the maul (a point at
    (60 - skill) / 20 from 40) is the cheaper start, until the belt (orange until 50, grey at 70) takes
    over."""
    belt = Recipe(
        22,
        "Copper Belt",
        10,
        1,
        ((COPPER, 20),),
        "Blacksmithing",
        spell_id=952,
        trivial_low=50,
        trivial_high=70,
    )
    novice = replace(NOVICE_SMITH, known_spells=frozenset({951, 952}))
    unsold = (Item(10, "Copper Belt"), Item(MAUL, "Heavy Copper Maul", class_id=2, sell_price=0))
    m = maul_market(
        novice,
        LEATHERY,
        recipes=(CURE, GREY_AT_60, belt),
        skill_crafters=frozenset({"Novice"}),
        extra_items=unsold,
        exits=frozenset({"vendor", KEEP_EXIT}),
    )
    return m, belt


def test_a_climb_never_crafts_a_banned_recipe() -> None:
    m, belt = _maul_and_belt()
    unbanned = m.evaluate(GREY_AT_60, skill_run=engine.SkillRuns())
    assert unbanned is not None and unbanned.stop_reason == "rival" and unbanned.climb_without == frozenset()
    # without the belt the maul's run goes on until it is about to turn grey, and nothing follows it
    no_belt = engine.SkillRuns(banned=frozenset({belt.id}))
    alone = m.evaluate(GREY_AT_60, skill_run=no_belt)
    assert alone is not None
    assert (alone.stop_reason, alone.stop_skill, alone.overtaken_by) == ("trivial", 60, "")
    assert alone.crafts > unbanned.crafts and alone.climb_after == ()
    assert alone.climb_without == frozenset({belt.id})
    # the belt's climb never comes back to a banned maul, and the banned recipe gets no run of its own
    no_maul = engine.SkillRuns(banned=frozenset({GREY_AT_60.id}))
    belt_run = m.evaluate(belt, skill_run=no_maul)
    assert belt_run is not None
    assert all(r.recipe != GREY_AT_60 for r in belt_run.climb_after)
    assert m.evaluate(GREY_AT_60, skill_run=no_maul) is None
    ranked = m.rank(min_profit=-(10**9), skill_run=no_maul)
    assert [r.recipe.name for r in ranked] == ["Copper Belt"]
    # each set of bans has its climb: asking again without any gives the run as before
    again = m.evaluate(GREY_AT_60, skill_run=engine.SkillRuns())
    assert again is not None and (again.crafts, again.climb_cost) == (unbanned.crafts, unbanned.climb_cost)
    # a later run given as it is ignores the bans: it was planned already
    given = engine.SkillRun(7, 52, "rival", None, 9, (0.5,) * 29, GREY_AT_60, 45)
    assert m.evaluate(GREY_AT_60, skill_run=no_maul, stretch=given) is not None


def test_a_given_run_is_planned_as_it_is() -> None:
    novice = replace(NOVICE_SMITH, known_spells=frozenset({951}))
    m = maul_market(novice, LEATHERY, recipes=(CURE, GREY_AT_60), skill_crafters=frozenset({"Novice"}))
    given = engine.SkillRun(7, 52, "rival", None, 9, (0.5,) * 29, GREY_AT_60, 45)
    res = m.evaluate(GREY_AT_60, skill_run=engine.SkillRuns(), stretch=given)
    assert res is not None
    assert (res.crafts, res.stop_skill, res.stop_reason, res.crafts_p80) == (7, 52, "rival", 9)
    assert res.climb_cost is None and res.climb_after == ()


def test_a_pattern_the_climber_must_buy_is_counted_in_the_climb() -> None:
    novice = replace(NOVICE_SMITH, known_spells=frozenset({951}))
    free = maul_market(novice, LEATHERY, recipes=(CURE, GREY_AT_60), skill_crafters=frozenset({"Novice"}))
    paid = maul_market(novice, LEATHERY, recipes=(CURE, GREY_AT_60), skill_crafters=frozenset({"Novice"}))
    paid.learn_costs = {GREY_AT_60.id: 500}
    a = free.evaluate(GREY_AT_60, skill_run=engine.SkillRuns())
    b = paid.evaluate(GREY_AT_60, skill_run=engine.SkillRuns())
    assert a is not None and b is not None and a.climb_cost is not None and b.climb_cost is not None
    assert b.climb_cost == pytest.approx(a.climb_cost + 500)


def test_keep_exit_ranks_a_craft_nobody_buys_when_skilling_up() -> None:
    worthless = Item(MAUL, "Heavy Copper Maul", class_id=2, sell_price=0)
    keep = frozenset({"vendor", KEEP_EXIT})
    m = maul_market(
        SMITHY, LEATHERY, extra_items=(worthless,), exits=keep, skill_crafters=frozenset({"Smithy"})
    )
    res = must_evaluate(m, MAUL_RECIPE)
    assert (res.best_exit, res.revenue, res.profit) == (KEEP_EXIT, 0, -res.cost)
    # only while skilling up, and only when asked for
    assert maul_market(SMITHY, LEATHERY, extra_items=(worthless,), exits=keep).evaluate(MAUL_RECIPE) is None
    without = maul_market(SMITHY, LEATHERY, extra_items=(worthless,), skill_crafters=frozenset({"Smithy"}))
    assert without.evaluate(MAUL_RECIPE) is None
    # a vendor who pays wins
    paid = maul_market(SMITHY, LEATHERY, exits=keep, skill_crafters=frozenset({"Smithy"}))
    assert must_evaluate(paid, MAUL_RECIPE).best_exit == "vendor"


def test_a_final_crafter_picked_by_the_user_makes_it_even_if_grey() -> None:
    m = maul_market(SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60))
    assert must_evaluate(m, GREY_AT_60).crafter == "Veteran"  # most profitable
    picked = Market(
        m.items, m.recipes, m.prices, crafters=m.crafters, include_trivial=False, final_crafter="Smithy"
    )
    assert must_evaluate(picked, GREY_AT_60).crafter == "Smithy"
    grey = Market(
        m.items, m.recipes, m.prices, crafters=m.crafters, include_trivial=False, final_crafter="Veteran"
    )
    assert must_evaluate(grey, GREY_AT_60).crafter == "Veteran"
    nobody = Market(m.items, m.recipes, m.prices, crafters=m.crafters, final_crafter="Leathery")
    assert nobody.evaluate(GREY_AT_60) is None  # no blacksmith


def test_result_carries_the_crafters_skill_up_chance() -> None:
    both = must_evaluate(maul_market(SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60)), GREY_AT_60)
    assert (both.crafter, both.skill_chance, both.skill_ups) == ("Veteran", 0.0, 0.0)  # grey for them
    skillups = maul_market(SMITHY, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60), include_trivial=False)
    res = skillups.evaluate(GREY_AT_60, crafts=4)
    assert res is not None
    assert (res.crafter, res.skill_chance) == ("Smithy", 0.5)  # 50 of 40..60
    # each expected point takes 1/20 off the next craft's chance
    assert res.skill_ups == pytest.approx(0.5 * (1 - 0.95**4) / 0.05)
    anyone = must_evaluate(maul_market(recipes=(CURE, GREY_AT_60)), GREY_AT_60)
    assert (anyone.skill_chance, anyone.skill_ups) == (1.0, 1.0)  # nobody's skill is known
    assert res.skill_ups_bonus == 0.0  # no Working Overtime


def test_result_says_how_many_skill_ups_working_overtime_adds() -> None:
    overtime = replace(SMITHY, skill_bonus=0.2)
    m = maul_market(overtime, LEATHERY, VETERAN, recipes=(CURE, GREY_AT_60), include_trivial=False)
    res = m.evaluate(GREY_AT_60, crafts=4)
    assert res is not None
    assert res.crafter == "Smithy"
    assert res.skill_chance == pytest.approx(0.7)
    without = expected_skill_ups(GREY_AT_60, SMITHY, 4)
    assert res.skill_ups == pytest.approx(expected_skill_ups(GREY_AT_60, overtime, 4))
    assert res.skill_ups_bonus == pytest.approx(res.skill_ups - without)
    assert res.skill_ups_bonus > 0


# --- Legacy talents -------------------------------------------------------------------------------------

STEW = Recipe(20, "Stew", GREEN, 1, ((LINEN, 1),), "Cooking", spell_id=920)


def test_bartering_discounts_the_buyers_vendor_purchases() -> None:
    barterer = replace(TAILOR, name="Barterer", vendor_discount=10)
    m = make_market({LINEN: 20}, [ROBE], thread_vendor_price=100, crafters=[barterer])
    res = must_evaluate(m, ROBE)
    assert res.cost == 10 * 20 + 90
    assert res.tree.inputs[1].discount == 10
    (thread,) = [s for s in res.steps if s.item_id == THREAD]
    assert (thread.value, thread.via, thread.discount) == (-90, "vendor", 10)
    (linen,) = [s for s in res.steps if s.item_id == LINEN]
    assert linen.discount == 0  # bought on the AH: no discount


def test_bartering_rounds_the_unit_price_up() -> None:
    m = make_market(
        {LINEN: 20}, [ROBE], thread_vendor_price=15, crafters=[replace(TAILOR, vendor_discount=5)]
    )
    assert must_evaluate(m, ROBE).tree.inputs[1].cost == 15  # 14.25 -> 15


def test_bartering_can_make_the_vendor_cheaper_than_the_ah() -> None:
    m = make_market({LINEN: 20, THREAD: 95}, [ROBE], thread_vendor_price=100, crafters=[TAILOR])
    assert must_evaluate(m, ROBE).tree.inputs[1].source == "ah"
    m = make_market(
        {LINEN: 20, THREAD: 95},
        [ROBE],
        thread_vendor_price=100,
        crafters=[replace(TAILOR, vendor_discount=10)],
    )
    assert must_evaluate(m, ROBE).tree.inputs[1].source == "vendor"


def test_the_barterer_does_the_craft() -> None:
    barterer = replace(TAILOR, name="Zed", vendor_discount=10)
    m = make_market({LINEN: 20}, [ROBE], thread_vendor_price=100, crafters=[TAILOR, barterer])
    assert must_evaluate(m, ROBE).crafter == "Zed"


def cook(name: str, chance: float = 0.0) -> Crafter:
    return replace(
        crafter(name, ("Cooking", 300), ("Tailoring", 50), known=frozenset({900, 920})),
        extra_results=(("Cooking", chance),) if chance else (),
    )


def test_master_chef_adds_the_expected_extra_result_to_the_revenue() -> None:
    m = make_market({LINEN: 20}, [STEW], crafters=[cook("Chef", 0.3)], exits=frozenset({"vendor"}))
    res = must_evaluate(m, STEW)
    assert res.revenue == round(500 * 1.3)
    assert res.bonus_output == 0.3
    assert res.steps[-1].action == "sell"
    assert (res.steps[-1].quantity, res.steps[-1].bonus) == (1, 0.3)
    assert res.cost == 20  # the extra result is free


def test_master_chef_only_helps_cooking() -> None:
    m = make_market(
        {LINEN: 20, THREAD: 100}, [ROBE], crafters=[cook("Chef", 0.3)], exits=frozenset({"vendor"})
    )
    res = must_evaluate(m, ROBE)
    assert (res.revenue, res.bonus_output) == (500, 0.0)


def test_the_master_chef_does_the_cooking() -> None:
    m = make_market(
        {LINEN: 20}, [STEW], crafters=[cook("Cook"), cook("Zed", 0.5)], exits=frozenset({"vendor"})
    )
    res = must_evaluate(m, STEW)
    assert (res.crafter, res.revenue) == ("Zed", 750)


# --- one memo per ranking ---------------------------------------------------------------------------
BOLT_RECIPE = Recipe(11, "Bolt of Linen", BOLT, 1, ((LINEN, 2),), "Tailoring")
BOLT_ROBE = Recipe(10, "Green Robe", GREEN, 1, ((BOLT, 2), (THREAD, 1)), "Tailoring")
BOLT_TUNIC = Recipe(12, "Linen Tunic", GREEN, 1, ((BOLT, 2),), "Tailoring")


def test_evaluations_share_a_memo_across_recipes() -> None:
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, [BOLT_RECIPE, BOLT_ROBE, BOLT_TUNIC])
    memo: Memo = {}
    robe = m.evaluate(BOLT_ROBE, memo=memo)
    known = len(memo)
    tunic = m.evaluate(BOLT_TUNIC, memo=memo)
    assert robe is not None and tunic is not None
    assert len(memo) == known  # the tunic's bolts were already worked out for the robe
    assert tunic.tree.inputs[0] == robe.tree.inputs[0]
    assert tunic.cost == 40


def test_rank_matches_fresh_evaluations() -> None:
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, [BOLT_RECIPE, BOLT_ROBE, BOLT_TUNIC])
    ranked = m.rank(min_profit=-(10**9))
    fresh = sorted((must_evaluate(m, r) for r in m.recipes), key=lambda r: -r.profit)
    assert [(r.recipe.id, r.cost, r.revenue, r.best_exit, r.tree) for r in ranked] == [
        (r.recipe.id, r.cost, r.revenue, r.best_exit, r.tree) for r in fresh
    ]
    assert [r.sell_options for r in ranked] == [r.sell_options for r in fresh]


def test_chain_cycle_buys_the_item_directly() -> None:
    recipes = [
        ROBE,
        Recipe(11, "Linen from Thread", LINEN, 1, ((THREAD, 1),), "Tailoring"),
        Recipe(12, "Thread from Linen", THREAD, 1, ((LINEN, 1),), "Tailoring"),
    ]
    m = make_market({LINEN: 20, THREAD: 20}, recipes)
    res = must_evaluate(m, ROBE)
    assert res.cost == 200 + 20
    linen, thread = res.tree.inputs
    assert (linen.option, linen.options[0].key) == ("ah", "ah")
    assert all(o.cost >= 200 for o in linen.options)  # a chain through itself is never cheaper
    assert (thread.option, thread.options[0].key) == ("ah", "ah")
    assert len(m.rank(min_profit=-(10**9))) == 3  # and the walk terminates


def test_self_loop_recipe_is_not_an_option() -> None:
    recharge = Recipe(11, "Recharge", THREAD, 2, ((THREAD, 1), (LINEN, 1)), "Tailoring")
    m = make_market({LINEN: 20, THREAD: 100}, [ROBE, recharge])
    thread = must_evaluate(m, ROBE).tree.inputs[1]
    assert [o.key for o in thread.options] == ["ah"]


# --- steps are built when read ----------------------------------------------------------------------
def test_steps_are_built_on_first_access() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY), MAUL_RECIPE)
    assert "steps" not in vars(res)
    first = res.steps
    assert res.steps is first
    assert first == plan_steps(
        res.tree, res.best_exit, res.revenue, res.mail_to, res.postage, res.bonus_output
    )


def test_rank_does_not_schedule_steps(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[int] = []
    schedule = engine._schedule

    def counted(*args: Any) -> Any:
        calls.append(1)
        return schedule(*args)

    monkeypatch.setattr(engine, "_schedule", counted)
    ranked = maul_market(SMITHY, LEATHERY).rank()
    assert ranked and calls == []
    assert ranked[0].steps
    assert len(calls) == 1


def test_results_compare_without_their_steps() -> None:
    m = maul_market(SMITHY, LEATHERY)
    a, b = must_evaluate(m, MAUL_RECIPE), must_evaluate(m, MAUL_RECIPE)
    assert a.steps
    assert a == b


# --- soulbound items stay with whoever made them ----------------------------------------------------
BOUND_LEATHER = Item(LEATHER, "Light Leather", stack_size=20, tradable=False)
BOUND_ROBE = Item(GREEN, "Green Robe", quality=2, item_level=20, class_id=4, sell_price=500, tradable=False)


def test_soulbound_intermediate_is_not_mailed() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY, extra_items=[BOUND_LEATHER]), MAUL_RECIPE)
    leather = res.tree.inputs[0]
    assert (leather.source, res.cost) == ("ah", 200 + 10)
    assert [o.key for o in leather.options] == ["ah"]
    assert "mail" not in [s.action for s in res.steps]
    # whoever can craft it themself still does
    res = must_evaluate(maul_market(BOTH, extra_items=[BOUND_LEATHER]), MAUL_RECIPE)
    assert (res.tree.inputs[0].via, res.cost) == ("Light Leather", 2 * 15 + 10)


def test_soulbound_craft_is_not_mailed_to_an_enchanter() -> None:
    enchanter = crafter("Enc", ("Enchanting", 1))
    m = make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=[TAILOR, enchanter], extra_items=[BOUND_ROBE])
    res = must_evaluate(m, ROBE)
    assert (res.best_exit, [e.kind for e in res.exits]) == ("vendor", ["vendor"])
    both = crafter("Both", ("Enchanting", 10), ("Tailoring", 50), known=frozenset({900}))
    m = make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=[both], extra_items=[BOUND_ROBE])
    assert (must_evaluate(m, ROBE).best_exit, must_evaluate(m, ROBE).postage) == ("disenchant", 0)


def test_soulbound_items_have_no_ah_exit() -> None:
    m = make_market({LINEN: 20, THREAD: 100, GREEN: 100_000}, extra_items=[BOUND_ROBE])
    assert [e.kind for e in m.exits_for(GREEN)] == ["vendor"]


# --- time: profit per hour --------------------------------------------------------------------------
# On foot at 7 yd/s with no detour: 7 yd is a second. The auction house is the hub; a mailbox 5 s away, an
# anvil 10 s away, a vendor selling thread 100 s away and one selling nothing we need 3 s away.
TOWN = timing.CityMap(
    "Town",
    "Horde",
    [
        timing.Location("ah", "ah", "Auctioneer", 0, 0, 0),
        timing.Location("mailbox:1", "mailbox", "Mailbox", 35, 0, 0),
        timing.Location("anvil:1", "anvil", "Anvil", 70, 0, 0),
        timing.Location("vendor:1", "vendor", "Thread Seller", 700, 0, 0),
        timing.Location("vendor:2", "vendor", "Junk Seller", 0, 21, 0),
    ],
    "ah",
    {"vendor:1": frozenset({THREAD}), "vendor:2": frozenset()},
)
GOLD = 10_000


def timed(gold_per_hour: float = 0, batch: int = 10) -> TimeModel:
    cfg = timing.TimeConfig(run_speed=7.0, detour=1.0, batch=batch, time_value=round(gold_per_hour * GOLD))
    return TimeModel(cfg, TOWN)


ANVIL_MAUL = replace(MAUL_RECIPE, cast_time_ms=3000, station="anvil")
BOLT_RECIPES = [BOLT_RECIPE, BOLT_ROBE, BOLT_TUNIC]
BOLT_PRICES = {LINEN: 10, THREAD: 5, BOLT: 100}


def plan(r: Result) -> tuple[object, ...]:
    return (
        r.recipe.id,
        r.cost,
        r.revenue,
        r.best_exit,
        r.crafter,
        r.mail_to,
        r.tree,
        r.steps,
        r.sell_options,
    )


def enchanters() -> list[Crafter]:
    return [TAILOR, crafter("Aaron", ("Enchanting", 10)), crafter("Zed", ("Enchanting", 90))]


def test_time_worth_nothing_changes_no_plan() -> None:
    for untimed, with_time in [
        (maul_market(SMITHY, LEATHERY), maul_market(SMITHY, LEATHERY, time=timed(0))),
        (
            make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=enchanters()),
            make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=enchanters(), time=timed(0)),
        ),
        (make_market(BOLT_PRICES, BOLT_RECIPES), make_market(BOLT_PRICES, BOLT_RECIPES, time=timed(0))),
    ]:
        a, b = untimed.rank(min_profit=-(10**9)), with_time.rank(min_profit=-(10**9))
        assert [plan(r) for r in a] == [plan(r) for r in b]
        assert all(r.seconds > 0 for r in b)


def test_time_value_prefers_the_auction_house_to_a_long_run() -> None:
    prices = {LINEN: 20, THREAD: 100}
    assert must_evaluate(make_market(prices, thread_vendor_price=90), ROBE).tree.inputs[1].source == "vendor"
    res = must_evaluate(make_market(prices, thread_vendor_price=90, time=timed(100)), ROBE)
    thread = res.tree.inputs[1]
    assert (thread.source, thread.option, thread.cost) == ("ah", "ah", 100)
    assert res.cost == 300  # money stays whole copper
    assert [o.key for o in thread.options] == ["ah", "vendor"]  # best for money and time together first
    assert thread.options[1].seconds > thread.options[0].seconds


def test_time_value_avoids_mailing_an_intermediate() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY, time=timed(100)), MAUL_RECIPE)
    assert res.tree.inputs[0].source == "ah"  # 200c of leather beats 60c and a switch to Leathery
    assert res.cost == 2 * 100 + 10
    assert "mail" not in [s.action for s in res.steps]


def test_time_value_can_change_the_exit() -> None:
    m = make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=enchanters(), time=timed(100))
    res = must_evaluate(m, ROBE)
    assert res.best_exit == "vendor"  # disenchanting pays more but needs a mail and a switch to Zed
    assert [o.kind for o in res.sell_options] == ["vendor", "disenchant"]


def test_steps_and_nodes_carry_their_seconds() -> None:
    cfg = timed(0).config
    m = maul_market(SMITHY, LEATHERY, time=timed(0), recipes=(CURE, ANVIL_MAUL))
    res = must_evaluate(m, ANVIL_MAUL)
    seconds = {(s.action, s.item_id): s.seconds for s in res.steps}
    assert seconds["buy", SCRAPS] == pytest.approx(cfg.ah_buy * 6 / 20)  # six scraps: 0.3 of a stack
    assert seconds["craft", LEATHER] == pytest.approx(2 * cfg.craft_overhead)  # instant casts
    mail = 0.1 * cfg.mail_attach + 0.1 * (cfg.mail_send + cfg.mail_open)  # a batch: one stack in one mail
    assert seconds["mail", LEATHER] == pytest.approx(mail)
    assert seconds["craft", MAUL] == pytest.approx(3.0 + cfg.craft_overhead)
    assert seconds["sell", MAUL] == pytest.approx(cfg.vendor_sell)
    assert [s.station for s in res.steps if s.action == "craft"] == ["", "anvil"]
    assert res.tree.seconds > sum(seconds.values()) - seconds["sell", MAUL]  # plus shared trips, the switch


def test_a_partial_stack_takes_a_whole_click() -> None:
    cfg = timed(0).config  # batch 10
    one = replace(ROBE, reagents=((LINEN, 1), (THREAD, 1)))
    linen = Item(LINEN, "Linen Cloth", stack_size=20)  # thread stacks by 1
    m = make_market({LINEN: 20, THREAD: 100}, [one], extra_items=[linen], time=timed(0))
    buys = {s.item_id: s.seconds for s in must_evaluate(m, one).steps if s.action == "buy"}
    assert buys[LINEN] == pytest.approx(cfg.ah_buy / 10)  # 10 linen a batch: one stack, one click
    assert buys[THREAD] == pytest.approx(cfg.ah_buy)  # a click per thread


def test_timing_is_exact_and_lazy() -> None:
    cfg = timed(0).config
    m = maul_market(SMITHY, LEATHERY, time=timed(0), recipes=(CURE, ANVIL_MAUL))
    res = must_evaluate(m, ANVIL_MAUL)
    assert "timing" not in vars(res)
    t = res.timing
    assert t is not None and res.timing is t
    assert (t.city, t.batch) == ("Town", 10)
    assert t.breakdown["switch"] == cfg.switch_character
    by_who: dict[str, list[str]] = {}
    for leg in t.legs:
        by_who.setdefault(leg.who, []).append(leg.to_id)
    assert by_who["Leathery"] == ["mailbox:1"]  # buy scraps at the AH, collect, craft and mail at the box
    assert by_who["Smithy"] == ["mailbox:1", "anvil:1", "vendor:2"]  # collect, forge, sell; done there
    smithy = 5 + 5 + (70**2 + 21**2) ** 0.5 / 7
    assert t.breakdown["travel"] == pytest.approx(5 + smithy)
    # a search each for scraps and copper; a batch buys 3 stacks of scraps and 1 of copper (10 bars: a click)
    assert t.breakdown["ah"] == pytest.approx(2 * cfg.ah_search + (3 + 1) * cfg.ah_buy)
    assert res.rate == t.per_hour(res.profit)
    assert t.total_seconds == pytest.approx(sum(t.breakdown.values()))


def test_ah_purchases_are_collected_from_the_mailbox_in_one_trip() -> None:
    cfg = timed(0).config
    res = must_evaluate(
        make_market({LINEN: 20, THREAD: 100}, time=timed(0)), ROBE
    )  # linen and thread on the AH
    t = res.timing
    assert t is not None
    assert [leg.to_id for leg in t.legs] == ["mailbox:1", "vendor:2"]  # collect both, then sell nearby
    assert t.breakdown["mail"] == pytest.approx(2 * cfg.mail_open)  # one mail per item, however many bought


def test_a_character_collects_an_alts_mail_even_without_ah_purchases() -> None:
    copper = Item(COPPER, "Copper Bar", stack_size=20, vendor_price=10)  # Smithy buys nothing on the AH
    m = maul_market(SMITHY, LEATHERY, time=timed(0), extra_items=[copper])
    res = must_evaluate(m, MAUL_RECIPE)
    assert [(s.who, s.action, s.via) for s in res.steps if s.action == "buy"] == [
        ("Leathery", "buy", "ah"),
        ("Smithy", "buy", "vendor"),
    ]
    t = res.timing
    assert t is not None
    assert [leg.to_id for leg in t.legs if leg.who == "Smithy"][0] == "mailbox:1"  # the leather Leathery sent


def test_rank_does_not_time(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[int] = []
    time_blocks = timing.time_blocks

    def counted(*args: Any) -> Any:
        calls.append(1)
        return time_blocks(*args)

    monkeypatch.setattr(timing, "time_blocks", counted)
    ranked = maul_market(SMITHY, LEATHERY, time=timed(10)).rank()
    assert ranked and calls == []
    assert ranked[0].rate is not None
    assert len(calls) == 1


def test_rank_matches_fresh_evaluations_with_time() -> None:
    m = make_market(BOLT_PRICES, BOLT_RECIPES, time=timed(50))
    ranked = m.rank(min_profit=-(10**9))
    fresh = sorted((must_evaluate(m, r) for r in m.recipes), key=lambda r: -r.profit)
    assert [plan(r) for r in ranked] == [plan(r) for r in fresh]
    assert [r.seconds for r in ranked] == [r.seconds for r in fresh]


def test_no_time_model_means_no_timing() -> None:
    res = must_evaluate(maul_market(SMITHY, LEATHERY), MAUL_RECIPE)
    assert (res.seconds, res.timing, res.rate) == (0.0, None, None)
    assert all(s.seconds == 0.0 for s in res.steps)


# --- a session: N crafts, spelled out ---------------------------------------------------------------
def test_a_session_crafts_whole_batches_for_all_its_crafts() -> None:
    bolts = Recipe(11, "Bolt of Linen", BOLT, 2, ((LINEN, 2),), "Tailoring")  # two bolts a craft
    robe = Recipe(10, "Green Robe", GREEN, 1, ((BOLT, 1), (THREAD, 1)), "Tailoring")
    m = make_market({LINEN: 10, THREAD: 5, BOLT: 100}, [bolts, robe])
    one = must_evaluate(m, robe)
    assert (one.crafts, one.cost, one.tree.inputs[0].crafts) == (1, 20 + 5, 1)  # a spare bolt per robe
    res = m.evaluate(robe, crafts=20)
    assert res is not None
    assert (res.crafts, res.tree.inputs[0].crafts) == (20, 10)  # ten bolt crafts make the 20 bolts
    assert (res.cost, res.revenue) == (10 * 20 + 20 * 5, 20 * 500)
    assert [(s.action, s.quantity) for s in res.steps if s.item_id in (BOLT, GREEN)] == [
        ("craft", 20),
        ("craft", 20),
        ("sell", 20),
    ]


def test_a_session_scales_master_chef_extras() -> None:
    stew = Recipe(30, "Stew", GREEN, 1, ((LINEN, 1),), "Cooking")
    chef = replace(crafter("Chef", ("Cooking", 50), known=frozenset({0})), extra_results=(("Cooking", 0.5),))
    m = make_market({LINEN: 20}, [stew], crafters=[chef], exits=frozenset({"vendor"}))
    res = m.evaluate(stew, crafts=10)
    assert res is not None
    assert (res.bonus_output, res.revenue) == (5.0, 15 * 500)


def test_detailed_steps_say_where_to_go() -> None:
    m = maul_market(SMITHY, LEATHERY, time=timed(0), recipes=(CURE, ANVIL_MAUL))
    res = must_evaluate(m, ANVIL_MAUL)
    details = engine.detailed_steps(res)
    said: list[tuple[object, ...]] = []
    for d in details:
        if d.kind == "step":
            assert d.step is not None
            s = res.steps[d.step]
            said.append((d.who, s.action, s.item_id))
        elif d.kind == "go":
            said.append((d.who, "go", d.location_id, tuple((i, q) for i, _, q in d.retrieve)))
        elif d.kind == "start":
            said.append((d.who, "start", d.location_id))
        else:
            said.append((d.who, "switch"))
    assert said == [
        ("Leathery", "start", "ah"),  # everyone starts at the hub, the auction house
        ("Leathery", "buy", SCRAPS),
        ("Leathery", "go", "mailbox:1", ((SCRAPS, 6),)),
        ("Leathery", "craft", LEATHER),
        ("Leathery", "mail", LEATHER),  # from the mailbox Leathery stands at
        ("Smithy", "switch"),
        ("Smithy", "start", "ah"),
        ("Smithy", "buy", COPPER),
        ("Smithy", "go", "mailbox:1", ((COPPER, 1), (LEATHER, 2))),  # the AH's copper and Leathery's leather
        ("Smithy", "go", "anvil:1", ()),
        ("Smithy", "craft", MAUL),
        ("Smithy", "go", "vendor:2", ()),
        ("Smithy", "sell", MAUL),
    ]
    assert sorted(d.step for d in details if d.step is not None) == list(range(len(res.steps)))
    switch = next(d for d in details if d.kind == "switch")
    assert switch.seconds == timed(0).config.switch_character
    assert all(d.seconds == 0 for d in details if d.kind == "start")
    runs = {d.location_id: d.seconds for d in details if d.kind == "go" and d.who == "Smithy"}
    assert runs["anvil:1"] == pytest.approx(5.0)  # from the mailbox (35 yd) to the anvil (70 yd): 5 s


def test_a_disenchant_sale_says_how_long_the_disenchanting_takes() -> None:
    cfg = timed(0).config
    enchanter = crafter("Both", ("Enchanting", 10), ("Tailoring", 50), known=frozenset({900}))
    m = make_market(DE_PRICES, [ROBE], DE_ROWS, crafters=[enchanter], time=timed(0))
    res = m.evaluate(ROBE, crafts=4)
    assert res is not None and res.best_exit == "disenchant"
    sale = res.steps[-1]
    assert sale.lead_seconds == pytest.approx(4 * cfg.disenchant)  # four robes to disenchant
    assert sale.seconds > sale.lead_seconds  # and the dust to post


def test_detailed_steps_need_a_timing() -> None:
    assert engine.detailed_steps(must_evaluate(maul_market(SMITHY, LEATHERY), MAUL_RECIPE)) == []


# --- reputation: what a vendor charges this buyer in this city ------------------------------------------
ORGRIMMAR, DARKSPEAR = 76, 530
HONORED_UP = {6: 10, 7: 10, 8: 10}  # vanilla: 10% off from Honored
# Two vendors sell thread: a troll 10 s from the auction house and an orc 100 s away. A third, of a faction
# nobody has a reputation with, sells nothing we need.
REP_TOWN = timing.CityMap(
    "Rep Town",
    "Horde",
    [
        timing.Location("ah", "ah", "Auctioneer", 0, 0, 0),
        timing.Location("mailbox:1", "mailbox", "Mailbox", 35, 0, 0),
        timing.Location("vendor:1", "vendor", "Troll Seller", 70, 0, 0),
        timing.Location("vendor:2", "vendor", "Orc Seller", 700, 0, 0),
        timing.Location("vendor:3", "vendor", "Junk Seller", 0, 21, 0),
    ],
    "ah",
    {"vendor:1": frozenset({THREAD}), "vendor:2": frozenset({THREAD}), "vendor:3": frozenset()},
    vendor_reputations={"vendor:1": DARKSPEAR, "vendor:2": ORGRIMMAR},
)


def rep_market(
    *standings: tuple[int, int],
    city: timing.CityMap | None = REP_TOWN,
    bartering: int = 0,
    thread: int = 100,
    prices: dict[int, int] | None = None,
) -> Market:
    """The robe's market for a tailor with those (faction, standing) pairs, thread at a vendor."""
    tailor = replace(TAILOR, reputations=standings, vendor_discount=bartering)
    model = None if city is None else TimeModel(timed(0).config, city)
    return make_market(
        prices or {LINEN: 20},
        [ROBE],
        thread_vendor_price=thread,
        crafters=[tailor],
        time=model,
        reputation_discounts=HONORED_UP,
    )


def thread_buy(res: Result) -> Step:
    (step,) = [s for s in res.steps if s.item_id == THREAD]
    return step


def test_an_honored_buyer_pays_less_at_that_factions_vendor() -> None:
    res = must_evaluate(rep_market((ORGRIMMAR, 6)), ROBE)
    assert res.cost == 10 * 20 + 90
    assert (res.tree.inputs[1].rep_discount, res.tree.inputs[1].discount) == (10, 0)
    buy = thread_buy(res)
    assert (buy.value, buy.via, buy.rep_discount, buy.discount) == (-90, "vendor", 10, 0)
    assert engine.reputation_faction(res, "Tailor", THREAD) == ORGRIMMAR
    (linen,) = [s for s in res.steps if s.item_id == LINEN]
    assert linen.rep_discount == 0  # bought on the AH


@pytest.mark.parametrize("standings", [(), ((ORGRIMMAR, 5),), ((81, 8),)])
def test_no_discount_below_the_standing_or_with_another_faction(
    standings: tuple[tuple[int, int], ...],
) -> None:
    # Friendly is not enough (vanilla), and Thunder Bluff's vendors aren't here
    res = must_evaluate(rep_market(*standings), ROBE)
    assert (res.cost, thread_buy(res).rep_discount) == (10 * 20 + 100, 0)
    assert engine.reputation_faction(res, "Tailor", THREAD) == 0


def test_reputation_adds_to_bartering() -> None:
    res = must_evaluate(rep_market((ORGRIMMAR, 8), bartering=10), ROBE)
    buy = thread_buy(res)
    assert (buy.value, buy.discount, buy.rep_discount) == (-80, 10, 10)
    assert engine.vendor_price(15, 5, 10) == 13  # 12.75 -> 13: rounded up, like Bartering alone


def test_the_price_needs_a_city() -> None:
    # No time model (the CLI's ranking), or no presets: nobody knows whose vendor it is.
    assert must_evaluate(rep_market((ORGRIMMAR, 6), city=None), ROBE).cost == 300
    res = must_evaluate(rep_market((ORGRIMMAR, 6), city=timing.ANYWHERE), ROBE)
    assert (res.cost, thread_buy(res).rep_discount) == (300, 0)


def test_the_route_buys_where_the_price_holds() -> None:
    def vendors_visited(res: Result) -> list[str]:
        t = res.timing
        assert t is not None
        return [st.location_id for st in t.stops if st.phase == "gather"]

    # Honored with the orcs: past the troll to the orc seller, where the thread is cheaper
    orc = must_evaluate(rep_market((ORGRIMMAR, 6)), ROBE)
    assert vendors_visited(orc) == ["ah", "vendor:2"]
    went = [d.location_id for d in engine.detailed_steps(orc) if d.kind == "go"]
    assert "vendor:2" in went and "vendor:1" not in went
    # Honored with the trolls: the near one
    assert vendors_visited(must_evaluate(rep_market((DARKSPEAR, 6)), ROBE)) == ["ah", "vendor:1"]
    # with both, either gives the price: the nearer
    both = must_evaluate(rep_market((ORGRIMMAR, 6), (DARKSPEAR, 7)), ROBE)
    assert vendors_visited(both) == ["ah", "vendor:1"]
    assert engine.reputation_faction(both, "Tailor", THREAD) == DARKSPEAR
    # with neither, the nearest seller
    assert vendors_visited(must_evaluate(rep_market(), ROBE)) == ["ah", "vendor:1"]


def test_a_plan_can_be_costed_and_timed_in_another_city() -> None:
    # A town whose only thread seller is a troll, next to the auction house.
    troll_town = timing.CityMap(
        "Troll Town",
        "Horde",
        [
            timing.Location("ah", "ah", "Auctioneer", 0, 0, 0),
            timing.Location("vendor:9", "vendor", "T", 7, 0, 0),
        ],
        "ah",
        {"vendor:9": frozenset({THREAD})},
        vendor_reputations={"vendor:9": DARKSPEAR},
    )
    m = rep_market((ORGRIMMAR, 6))
    res = must_evaluate(m, ROBE)
    assert engine.cost_in(res, REP_TOWN, m.items) == res.cost == 290  # where it was planned
    assert engine.cost_in(res, troll_town, m.items) == 300  # the orcs' discount doesn't hold there
    there = engine.time_result(res, TimeModel(timed(0).config, troll_town))
    assert [st.location_id for st in there.stops if st.phase == "gather"] == ["ah", "vendor:9"]
    both = must_evaluate(rep_market((ORGRIMMAR, 6), (DARKSPEAR, 6), bartering=10), ROBE)
    assert engine.cost_in(both, troll_town, m.items) == both.cost == 280  # Bartering goes along


def test_city_prices_tell_cities_that_charge_differently_apart() -> None:
    orc: dict[int, int] = {ORGRIMMAR: 10}
    troll: dict[int, int] = {DARKSPEAR: 10}
    nobody: dict[int, int] = {}
    assert engine.city_prices(REP_TOWN, [nobody]) == frozenset()
    assert engine.city_prices(REP_TOWN, [orc, nobody, troll]) == {(0, THREAD, 10), (2, THREAD, 10)}
    assert engine.city_prices(TOWN, [orc, troll]) == frozenset()  # its vendors follow no reputation


def test_recipes_using_follows_chains_of_any_depth() -> None:
    dye = Recipe(30, "Dye", 40, 1, ((THREAD, 1),), "Tailoring")
    dyed_bolt = Recipe(31, "Dyed Bolt", 41, 1, ((40, 1), (BOLT, 1)), "Tailoring")
    cloak = Recipe(32, "Cloak", 42, 1, ((41, 2),), "Tailoring")
    recipes = [cloak, BOLT_RECIPE, BOLT_TUNIC, dyed_bolt, dye]
    # thread goes into the dye, the dye into the dyed bolt, that into the cloak; bolts and tunics need none
    assert engine.recipes_using(recipes, {THREAD}) == {30, 31, 32}
    assert engine.recipes_using(recipes, {LINEN}) == {11, 12, 31, 32}
    assert engine.recipes_using(recipes, set()) == frozenset()


def test_rank_can_be_kept_to_some_recipes() -> None:
    m = make_market(BOLT_PRICES, BOLT_RECIPES)
    everything = m.rank(min_profit=-(10**9))
    some = m.rank(min_profit=-(10**9), only={BOLT_ROBE.id, BOLT_TUNIC.id})
    assert [r.recipe.id for r in some] == [r.recipe.id for r in everything if r.recipe.id != BOLT_RECIPE.id]
    assert [plan(r) for r in some] == [plan(r) for r in everything if r.recipe.id != BOLT_RECIPE.id]
    assert m.rank(only=set()) == []


def test_a_reputation_discount_can_beat_the_auction_house() -> None:
    prices = {LINEN: 20, THREAD: 95}
    assert must_evaluate(rep_market(prices=prices), ROBE).tree.inputs[1].source == "ah"
    assert must_evaluate(rep_market((ORGRIMMAR, 6), prices=prices), ROBE).tree.inputs[1].source == "vendor"


def test_the_trip_to_a_far_discount_counts_when_time_has_a_value() -> None:
    # The orc seller is 100 s out: at 100g an hour the trip costs far more than the 10c saved, but the
    # price is still the orc's if the thread is bought from a vendor at all.
    tailor = replace(TAILOR, reputations=((ORGRIMMAR, 6),))
    model = TimeModel(timed(100).config, REP_TOWN)
    m = make_market(
        {LINEN: 20, THREAD: 100},
        [ROBE],
        thread_vendor_price=100,
        crafters=[tailor],
        time=model,
        reputation_discounts=HONORED_UP,
    )
    thread = must_evaluate(m, ROBE).tree.inputs[1]
    assert (thread.source, [o.key for o in thread.options]) == ("ah", ["ah", "vendor"])
    assert thread.options[1].cost == 90


# --- the order book: buying walks the ladder -----------------------------------------------------
ORE, EARTH, BAR, BLADE = 20, 21, 22, 23


def ladder(*levels: tuple[int, int]) -> book.Ladder:
    return tuple(book.Level(price, quantity, 1) for price, quantity in levels)


def book_market(
    books: dict[int, book.Ladder],
    recipes: list[Recipe],
    prices: dict[int, int] | None = None,
    sell_prices: dict[int, int] | None = None,
) -> Market:
    items = {
        ORE: Item(ORE, "Copper Ore"),
        EARTH: Item(EARTH, "Elemental Earth"),
        BAR: Item(BAR, "Copper Bar"),
        BLADE: Item(BLADE, "Copper Blade", sell_price=5),
    }
    cheapest = {i: levels[0].price for i, levels in books.items()}
    return Market(
        items,
        recipes,
        {**cheapest, **(prices or {})},
        books=books,
        sell_prices={BLADE: 100_000, **(sell_prices or {})},
    )


def test_a_lone_cheap_listing_is_one_cheap_unit() -> None:
    blade = Recipe(1, "Blade", BLADE, 1, ((EARTH, 2),), "Blacksmithing")
    m = book_market({EARTH: ladder((700, 1), (12000, 3))}, [blade])
    res = must_evaluate(m, blade)
    assert res.cost == 700 + 12000  # 1.27g, not two at 7s
    assert res.tree.inputs[0].cost == 12700
    assert res.short == 0


def test_a_batch_costs_about_the_wall_behind_a_few_cheap_units() -> None:
    blade = Recipe(1, "Blade", BLADE, 1, ((ORE, 10),), "Blacksmithing")
    m = book_market({ORE: ladder((64, 3), (167, 5000))}, [blade])
    res = m.evaluate(blade, crafts=20)
    assert res is not None
    assert res.cost == 3 * 64 + 197 * 167
    one = must_evaluate(m, blade)
    assert one.cost == 3 * 64 + 7 * 167


def test_an_item_no_scan_lists_cannot_be_bought() -> None:
    blade = Recipe(1, "Blade", BLADE, 1, ((ORE, 1), (EARTH, 1)), "Blacksmithing")
    m = book_market({ORE: ladder((167, 5000))}, [blade], sell_prices={EARTH: 12000})
    assert m.evaluate(blade) is None  # Elemental Earth sells for something, but none is listed


def test_needing_more_than_is_listed_is_short() -> None:
    blade = Recipe(1, "Blade", BLADE, 1, ((EARTH, 5),), "Blacksmithing")
    m = book_market({EARTH: ladder((700, 1), (12000, 2))}, [blade])
    res = must_evaluate(m, blade)
    assert res.cost == 700 + 4 * 12000
    assert res.tree.inputs[0].short == 2
    assert res.short == 2


def test_an_item_without_a_ladder_costs_its_flat_price() -> None:
    blade = Recipe(1, "Blade", BLADE, 1, ((ORE, 10), (EARTH, 1)), "Blacksmithing")
    m = book_market({EARTH: ladder((700, 1))}, [blade], prices={ORE: 100})
    assert must_evaluate(m, blade).cost == 1000 + 700


def test_branches_buying_the_same_item_share_its_ladder() -> None:
    bar = Recipe(2, "Smelt Copper", BAR, 1, ((ORE, 1),), "Mining")
    blade = Recipe(1, "Blade", BLADE, 1, ((ORE, 1), (BAR, 1)), "Blacksmithing")
    m = book_market({ORE: ladder((10, 1), (100, 50))}, [blade, bar])
    res = must_evaluate(m, blade)
    # the one cheap unit is bought once: the blade's ore, then the bar's at the next price
    assert res.cost == 10 + 100
    direct, crafted = res.tree.inputs
    assert (direct.cost, direct.source) == (10, "ah")
    assert (crafted.cost, crafted.via, crafted.inputs[0].cost) == (100, "Smelt Copper", 100)
    assert res.tree.cost == 110
    assert {o.key: o.cost for o in crafted.options} == {"craft:2": 100}
    assert sum(-s.value for s in res.steps if s.action == "buy") == 110


def test_how_many_are_needed_decides_between_buying_and_crafting() -> None:
    bar = Recipe(2, "Smelt Copper", BAR, 1, ((ORE, 1),), "Mining")
    blade = Recipe(1, "Blade", BLADE, 1, ((BAR, 1),), "Blacksmithing")
    m = book_market({BAR: ladder((50, 1), (400, 50)), ORE: ladder((100, 500))}, [blade, bar])
    assert must_evaluate(m, blade).tree.inputs[0].source == "ah"  # one bar at 50
    session = m.evaluate(blade, crafts=10)
    assert session is not None
    assert session.tree.inputs[0].via == "Smelt Copper"  # ten bars: 50 + 9 x 400 against 10 x 100 of ore
    assert session.cost == 1000


LESSER, GREATER, WAND = 20, 21, 22
UPGRADE = Recipe(
    1_000_000_960, "Greater Magic Essence", GREATER, 1, ((LESSER, 3),), spell_id=960, kind="convert"
)
DOWNGRADE = Recipe(
    1_000_000_961, "Lesser Magic Essence", LESSER, 3, ((GREATER, 1),), spell_id=961, kind="convert"
)
WAND_RECIPE = Recipe(30, "Greater Magic Wand", WAND, 1, ((GREATER, 1),), "Enchanting", spell_id=930)
ESSENCES = (Item(LESSER, "Lesser Magic Essence"), Item(GREATER, "Greater Magic Essence"), Item(WAND, "Wand"))
# 3 lesser cost 300; a greater sells for 500 (475 after the cut)
ESSENCE_PRICES = {LESSER: 100, GREATER: 500, WAND: 2000}


def essence_market(prices: dict[int, int] = ESSENCE_PRICES, **kwargs: Any) -> Market:
    items = {i.id: i for i in ESSENCES}
    return Market(items, [UPGRADE, DOWNGRADE, WAND_RECIPE], prices, **kwargs)


def test_a_conversion_ranks_on_its_price_asymmetry() -> None:
    ranked = {r.recipe.id: r for r in essence_market().rank(min_profit=-(10**9))}
    up = ranked[UPGRADE.id]
    assert (up.cost, up.revenue, up.best_exit, up.crafter) == (300, 475, "ah", "")
    assert ranked[DOWNGRADE.id].profit == 3 * 95 - 500
    assert (up.skill_chance, up.skill_ups) == (0.0, 0.0)


def test_conversions_rank_only_when_disenchant_is_a_way_to_sell() -> None:
    assert essence_market(exits=frozenset({"vendor", "ah"})).evaluate(UPGRADE) is None
    assert UPGRADE not in [r.recipe for r in essence_market(exits=frozenset({"ah"})).rank()]
    # selling the output on the AH is what a conversion is for, as disenchanting values its materials
    reliable = must_evaluate(essence_market(exits=frozenset({"vendor", "disenchant"})), UPGRADE)
    assert (reliable.best_exit, reliable.profit) == ("ah", 175)
    blocked = essence_market(exits=frozenset({"vendor", "disenchant"}), no_ah=frozenset({GREATER}))
    assert blocked.evaluate(UPGRADE) is None


def test_conversions_never_rank_when_skilling_up() -> None:
    def ranked(**kwargs: Any) -> list[Recipe]:
        return [r.recipe for r in essence_market(**kwargs).rank(min_profit=-(10**9))]

    assert UPGRADE in ranked()
    assert UPGRADE not in ranked(include_trivial=False)
    assert UPGRADE not in ranked(crafters=[TAILOR], skill_crafters=frozenset({"Tailor"}))
    assert not can_skill_up(UPGRADE, TAILOR)
    assert skill_up_chance(UPGRADE, TAILOR) == 0.0
    assert expected_skill_ups(UPGRADE, None, 5) == expected_skill_ups(UPGRADE, TAILOR, 5) == 0.0


def test_anyone_can_convert() -> None:
    assert recipes_for_characters([UPGRADE, WAND_RECIPE], [TAILOR], "none") == [UPGRADE]
    assert must_evaluate(essence_market(crafters=[TAILOR]), UPGRADE).crafter == "Tailor"


def test_a_chain_converts_a_reagent_when_that_is_cheaper() -> None:
    res = must_evaluate(essence_market(), WAND_RECIPE)
    (greater,) = res.tree.inputs
    assert (greater.option, greater.cost, greater.convert) == (f"craft:{UPGRADE.id}", 300, True)
    assert [(o.key, o.convert) for o in greater.options] == [(f"craft:{UPGRADE.id}", True), ("ah", False)]
    crafts = [s for s in res.steps if s.action == "craft"]
    assert [(s.name, s.convert) for s in crafts] == [("Greater Magic Essence", True), ("Wand", False)]


def test_a_conversion_only_buys_what_it_converts() -> None:
    # Lesser essences aren't listed: making them from greater ones to turn back into a greater is no plan
    assert essence_market({GREATER: 100}).evaluate(UPGRADE) is None


ENCHANTER = crafter("Enchy", ("Enchanting", 100))


def flip_market(green: book.Ladder | None = None, crafters: Sequence[Crafter] = (), **kwargs: Any) -> Market:
    """The robe disenchants into one dust (950 net); `green` lists robes on the AH (default: 2 at 600)."""
    green = green if green is not None else ladder((600, 2))
    items = {
        GREEN: Item(GREEN, "Green Robe", quality=2, item_level=20, class_id=4, sell_price=500),
        DUST: Item(DUST, "Strange Dust"),
        LINEN: Item(LINEN, "Linen Cloth"),
        THREAD: Item(THREAD, "Coarse Thread"),
    }
    return Market(
        items,
        [ROBE],
        {**DE_PRICES, GREEN: green[0].price},
        DE_ROWS,
        books={GREEN: green},
        crafters=crafters,
        **kwargs,
    )


def flips(m: Market) -> list[Recipe]:
    return [r for r in m.recipes if r.kind == "flip"]


def test_a_flip_buys_listed_gear_to_disenchant() -> None:
    m = flip_market()
    (flip,) = flips(m)
    assert (flip.id, flip.output_item_id, flip.reagents) == (
        engine.FLIP_ID_BASE + GREEN,
        GREEN,
        ((GREEN, 1),),
    )
    res = must_evaluate(m, flip)
    assert (res.cost, res.revenue, res.best_exit) == (600, 950, "disenchant")
    assert [e.kind for e in res.exits] == ["disenchant"]  # never resold to a vendor or on the AH
    assert (res.skill_chance, res.skill_ups) == (0.0, 0.0)
    assert [(s.action, s.via) for s in res.steps] == [("buy", "ah"), ("sell", "disenchant")]
    assert res.tree.flip


def test_only_listed_disenchantable_gear_is_flipped() -> None:
    m = Market(
        {
            GREEN: Item(GREEN, "Green Robe", quality=2, item_level=20, class_id=4),
            BOLT: Item(BOLT, "Bolt of Linen", quality=2, item_level=20, class_id=7),  # a trade good
            DUST: Item(DUST, "Strange Dust"),
        },
        [],
        {GREEN: 600, BOLT: 600, DUST: 1000},
        DE_ROWS,
    )
    assert [r.output_item_id for r in flips(m)] == [GREEN]
    unpriced = Market(
        {GREEN: Item(GREEN, "Green Robe", quality=2, item_level=20, class_id=4)}, [], {}, DE_ROWS
    )
    assert flips(unpriced) == []
    no_de = replace(m.items[GREEN], disenchantable=False)
    assert flips(Market({GREEN: no_de}, [], {GREEN: 600, DUST: 1000}, DE_ROWS)) == []


def test_a_flip_ranks_only_when_disenchanting_and_not_skilling_up() -> None:
    def ranked(**kwargs: Any) -> list[str]:
        return [r.recipe.kind for r in flip_market(**kwargs).rank(min_profit=-(10**9))]

    assert "flip" in ranked()
    assert "flip" not in ranked(exits=frozenset({"vendor", "ah"}))
    assert "flip" not in ranked(include_trivial=False)
    assert "flip" not in ranked(crafters=[ENCHANTER], skill_crafters=frozenset({"Enchy"}))


def test_a_flip_buys_the_session_up_the_listings_but_never_more_than_listed() -> None:
    m = flip_market(ladder((600, 2), (700, 5)))
    (flip,) = flips(m)
    res = m.evaluate(flip, crafts=10)
    assert res is not None
    assert (res.crafts, res.cost, res.short) == (7, 2 * 600 + 5 * 700, 0)
    assert res.revenue == 7 * 950
    assert must_evaluate(flip_market(), flip).crafts == 1


def test_a_flip_is_never_a_way_to_get_a_reagent() -> None:
    m = flip_market()
    keys = {o.key for n in m.rank(min_profit=-(10**9)) for i in n.tree.inputs for o in i.options}
    assert not any(k == f"craft:{engine.FLIP_ID_BASE + GREEN}" for k in keys)


def test_a_flip_needs_an_enchanter_and_mails_to_one() -> None:
    (flip,) = flips(flip_market())
    assert flip_market(crafters=[TAILOR]).evaluate(flip) is None
    res = must_evaluate(flip_market(crafters=[TAILOR, ENCHANTER]), flip)
    assert res.crafter == "Enchy" and res.postage == 0  # the enchanter buys it: nothing to mail


# An enchant: reagents in, no item out. Yellow at 120, grey at 160.
ENCHANT = Recipe(
    20,
    "Enchant Bracer - Minor Health",
    0,
    1,
    ((DUST, 2),),
    "Enchanting",
    spell_id=970,
    trivial_low=120,
    trivial_high=160,
    kind="enchant",
)
SKILL_ONLY = ALL_EXITS | {"skill"}


def enchant_market(*crafters: Crafter, **kwargs: Any) -> Market:
    """Dust at 100 on the AH, and Enchy (Enchanting 100) who knows the enchant unless `crafters` are given."""
    crafters = crafters or (replace(ENCHANTER, known_spells=frozenset({970})),)
    items = {DUST: Item(DUST, "Strange Dust")}
    return Market(items, [ENCHANT], {DUST: 100}, crafters=crafters, **kwargs)


def test_an_enchant_is_not_ranked_unless_skill_only_is_a_way_to_sell() -> None:
    assert enchant_market().rank(min_profit=-(10**9)) == []
    assert enchant_market().evaluate(ENCHANT) is None


def test_an_enchant_costs_its_reagents_and_makes_nothing() -> None:
    m = enchant_market(exits=SKILL_ONLY)
    (res,) = m.rank(min_profit=-(10**9), crafts=5)
    assert (res.cost, res.revenue, res.profit, res.roi) == (1000, 0, -1000, -1.0)
    assert (res.best_exit, res.crafter, res.postage, res.mail_to) == ("skill", "Enchy", 0, "")
    assert (res.skill_chance, res.skill_ups) == (1.0, 5.0)
    assert [(o.kind, o.profit) for o in res.sell_options] == [("skill", -1000)]
    assert (res.tree.item_id, res.tree.name, res.tree.enchant, res.tree.made) == (0, ENCHANT.name, True, 5)


def test_an_enchants_steps_end_with_the_cast() -> None:
    res = must_evaluate(enchant_market(exits=SKILL_ONLY), ENCHANT)
    assert [(s.action, s.name, s.quantity, s.enchant) for s in res.steps] == [
        ("buy", "Strange Dust", 2, False),
        ("craft", ENCHANT.name, 1, True),
    ]


def test_a_trivial_enchant_is_never_ranked() -> None:
    grey = replace(ENCHANTER, professions=(("Enchanting", 160, 375),), known_spells=frozenset({970}))
    m = enchant_market(grey, exits=SKILL_ONLY, include_trivial=True)
    assert m.rank(min_profit=-(10**9)) == []
    # nor for a crafter the user picked
    assert enchant_market(grey, exits=SKILL_ONLY, final_crafter="Enchy").evaluate(ENCHANT) is None


def test_an_enchant_is_done_by_whoever_it_can_skill_up() -> None:
    grey = replace(ENCHANTER, name="Grey", professions=(("Enchanting", 200, 375),))
    low = replace(ENCHANTER, known_spells=frozenset({970}))
    m = enchant_market(replace(grey, known_spells=frozenset({970})), low, exits=SKILL_ONLY)
    assert must_evaluate(m, ENCHANT).crafter == "Enchy"


def test_an_enchant_is_no_way_to_get_an_item_and_not_anyones() -> None:
    assert not ENCHANT.anyone and ENCHANT.is_enchant
    assert recipes_for_characters([ENCHANT], [TAILOR], "none") == []
    assert engine.recipes_using([ENCHANT], {DUST}) == frozenset({ENCHANT.id})


def test_a_craft_is_never_sold_for_skill_only() -> None:
    m = make_market({LINEN: 20, THREAD: 100}, exits=frozenset({"skill"}))
    assert m.evaluate(m.recipes[0]) is None


def test_an_enchant_is_timed_without_a_sale() -> None:
    model = TimeModel(timing.TimeConfig(), timing.ANYWHERE)
    res = must_evaluate(enchant_market(exits=SKILL_ONLY, time=model), ENCHANT)
    assert res.sell_seconds == 0
    assert res.timing is not None and res.timing.total_seconds > 0


def test_a_gathered_reagent_costs_what_selling_it_would_have_made() -> None:
    m = make_market({LINEN: 20, THREAD: 100})
    gathered = Market(m.items, m.recipes, m.prices, gathered={LINEN: 4})
    res = must_evaluate(gathered, gathered.recipes[0])
    linen = res.tree.inputs[0]
    assert (linen.source, linen.cost, linen.option) == ("gather", 40, "gather")
    assert [o.key for o in linen.options] == ["gather", "ah"]
    assert res.cost == 40 + 100
    gather = next(s for s in res.steps if s.item_id == LINEN)
    assert (gather.action, gather.quantity, gather.value) == ("gather", 10, -40)
    # a vendor selling it cheaper still wins
    cheap = make_market({THREAD: 100}, thread_vendor_price=11)
    by_vendor = Market(cheap.items, cheap.recipes, cheap.prices, gathered={THREAD: 50, LINEN: 4})
    assert must_evaluate(by_vendor, by_vendor.recipes[0]).tree.inputs[1].source == "vendor"


def test_given_flips_are_the_ones_the_market_would_make() -> None:
    m = flip_market()
    made = flips(m)
    assert len(made) == 1 and m.flips == tuple(made)
    # a market given them (from one with the same items and prices) has the very same recipes and plans
    again = flip_market(flips=m.flips)
    assert again.recipes == m.recipes
    assert must_evaluate(again, made[0]) == must_evaluate(m, made[0])
    # whatever flips `recipes` held are dropped for the given ones
    assert flips(Market(m.items, m.recipes, m.prices, m.disenchant, books=m.books, flips=())) == []


def test_a_crafters_skill_is_their_first_listing_of_the_profession_in_any_case() -> None:
    c = Crafter("Dup", (("Tailoring", 10, 75), ("tailoring", 99, 300), ("Mining", 5, 75)), frozenset())
    assert c.skill("TAILORING") == (10, 75) and c.skill("mining") == (5, 75) and c.skill("Cooking") is None
    assert replace(c, professions=(("Cooking", 3, 75),)).skill("Tailoring") is None  # follows a replace
    assert c == Crafter("Dup", c.professions, frozenset()) and hash(c) == hash(replace(c))


def test_recipes_for_characters_keeps_the_given_order() -> None:
    trainer: frozenset[Source] = frozenset({"trainer"})
    recipes = [
        Recipe(1, "Robe", GREEN, 1, ((LINEN, 1),), "Tailoring", spell_id=901, trivial_low=40),
        Recipe(2, "Bar", BOLT, 1, ((LINEN, 1),), "Mining", spell_id=902, trivial_low=1),
        Recipe(3, "Known", BOLT, 1, ((LINEN, 1),), "Cooking", spell_id=903),
        Recipe(4, "Vest", GREEN, 1, ((LINEN, 1),), "tailoring", spell_id=904, trivial_low=60),
        Recipe(5, "Flip", GREEN, 1, ((GREEN, 1),), kind="flip"),
        Recipe(6, "Shirt", GREEN, 1, ((LINEN, 1),), "Tailoring", spell_id=906, trivial_low=5),
    ]
    tailor = crafter("T", ("Tailoring", 50), known=frozenset({903}))
    miner = crafter("M", ("Mining", 1))
    for unlearned in ("none", "all", Learning("train", 0, trainer), Learning("train", 20, trainer)):
        naive = [
            r
            for r in recipes
            if r.anyone
            or r.spell_id in tailor.known_spells
            or any(can_learn(r, c, unlearned) for c in (tailor, miner))
        ]
        assert recipes_for_characters(recipes, [tailor, miner], unlearned) == naive
    assert [r.id for r in recipes_for_characters(recipes, [tailor, miner], "all")] == [1, 2, 3, 4, 5, 6]
    now = recipes_for_characters(recipes, [tailor, miner], Learning("train", 0, trainer))
    assert [r.id for r in now] == [1, 2, 3, 5, 6]


def test_markets_of_the_same_prices_share_their_climbs() -> None:
    m, belt = _maul_and_belt()
    runs = engine.SkillRuns()
    store = engine.ClimbStore()
    first, second = (
        engine.Market(
            m.items,
            m.recipes,
            m.prices,
            crafters=m.crafters,
            exits=m.exits,
            skill_crafters=m.skill_crafters,
            climbs=store,
        )
        for _ in range(2)
    )
    smith = m._by_name["Novice"]
    climb = first._climb("Blacksmithing", smith, runs, {})
    assert second._climb("Blacksmithing", smith, runs, {}) is climb
    # a ban is another climb, the same as worked out afresh without the recipe
    no_belt = replace(runs, banned=frozenset({belt.id}))
    without = second._climb("Blacksmithing", smith, no_belt, {})
    assert without is not climb
    kept = [c for c in first._candidates("Blacksmithing", smith, {}) if c.recipe.id != belt.id]
    fresh = engine.plan_climb(smith, "Blacksmithing", kept, runs.ceiling)
    assert without.best == fresh.best and without._finish == fresh._finish


def test_the_climbs_inner_loop_costs_runs_as_a_run_costs_them() -> None:
    """`Climb._cheapest_from` inlines `_Usable.cost` and `_cheaper`: it picks what they pick, to the bit."""

    def reference(climb: engine.Climb, u: Any, start: int) -> Any:
        found: Any = None
        for stop in range(u.hi, start, -1):
            run, (rest, _) = u.cost(start, stop), climb._finish[stop]
            total = (run[0] + rest[0], run[1] + rest[1])
            if found is None or engine._cheaper(total, found[0]):
                found = (total, (u, stop))
        return found

    rng = random.Random(1234)
    for _ in range(150):
        rank, cap = rng.randint(1, 40), rng.randint(45, 90)
        smith = replace(_smith(rank, cap), skill_bonus=rng.choice((0.0, 0.0, 0.08, 0.2)))
        candidates = []
        for i in range(rng.randint(2, 9)):
            low = rng.randint(0, 70)
            recipe = replace(_recipe(i, low, low + rng.randint(1, 30)), id=900 + i)
            # few distinct costs, so plans tie
            cost = float(rng.choice((-30, -5, 0, 5, 12, 12, 40, 75, 200))) / rng.choice((1, 3, 7))
            learn = rng.choice((0, 0, 0, 150.0, None))
            candidates.append(engine.Candidate(recipe, cost, rng.choice((0, 0, rng.randint(1, 60))), learn))
        climb = engine.plan_climb(smith, "Blacksmithing", candidates, rng.choice((5, 20, 1000)))
        for u in climb._usable:
            for start in range(u.lo, min(u.hi, climb.end)):  # the levels the climb finishes from
                got, want = climb._cheapest_from(u, start), reference(climb, u, start)
                assert (got is None) == (want is None)
                if got is not None:
                    assert (got[0][0], got[0][1].hex(), got[1]) == (want[0][0], want[0][1].hex(), want[1])


def test_a_market_of_a_professions_closure_plans_its_recipes_as_the_whole_game_does() -> None:
    """`profession_closure` is all a market needs to plan a profession: random recipe graphs across
    professions (chains, shared reagents, cycles, unpriced items), each profession's every recipe planned
    on a market of its closure exactly as on the whole one."""
    professions = ("Tailoring", "Mining", "Blacksmithing", "Alchemy")
    for seed in range(40):
        rng = random.Random(seed)
        items = {i: Item(i, f"I{i}", sell_price=rng.randint(0, 50), stack_size=20) for i in range(1, 41)}
        recipes = []
        for rid in range(1, 31):
            out = rng.randint(1, 40)
            reagents = tuple(
                (i, rng.randint(1, 3)) for i in rng.sample(range(1, 41), rng.randint(1, 3)) if i != out
            )
            if reagents:
                skill = rng.choice(professions)
                recipes.append(
                    Recipe(rid, f"R{rid}", out, rng.randint(1, 2), reagents, skill, spell_id=1000 + rid)
                )
        prices = {i: rng.randint(5, 200) for i in range(1, 41) if rng.random() < 0.7}
        crafter = Crafter(
            "C", tuple((p, 50, 300) for p in professions), frozenset(r.spell_id for r in recipes)
        )
        whole = Market(items, recipes, prices, crafters=[crafter])
        for profession in professions:
            closure = profession_closure(recipes, profession)
            scoped = Market(items, closure, prices, crafters=[crafter], flips=whole.flips)
            for r in recipes:
                if r.skill_name == profession:
                    assert r in closure
                    for crafts in (1, 5):
                        assert scoped.evaluate(r, crafts=crafts) == whole.evaluate(r, crafts=crafts), (
                            seed,
                            r,
                        )
