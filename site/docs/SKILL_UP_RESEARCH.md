# Skill-up planner: research, comparisons and bugs

How the skill workspace's climb (`engine.Climb`) compares with the other profession-levelling planners, what is
wrong with it, and what to change. Researched 2026-10-07 against the local dev database (WoW: Forever build
1.60.1.70245, Classic Beta PvE Horde, auction house 4) and foreverwowcraft.com's plans for the same house. Line
numbers refer to `main` at d12385f.

The two questions this answers:

1. **Flaws in predicting the cheapest sequence**, doubling back to a recipe included.
2. **The "obscene crafts on a recipe's last points" problem**, which `GRIND` does not stop.

UI comparisons come second (section 6).

Unless a row says otherwise, figures are for the hypothetical climber ("Your character", trained up to 300, no
talents) as `/api/rank` builds one, with the UI's skill exits (vendor, disenchant, keep, plus `skill` for
Enchanting and Engineering). **Default** sources are trainer + normal recipes (the UI's default, bind on pickup
excluded); **trainer** sources are trainer recipes only (FWC's `recipes=trainer`). Copper is the climb's own:
crafts' net cost plus patterns, as `ClimbPlan.spent_by` counts it, without spares or grind, unless it says "DP
objective".

---

## 1. Summary

**The search is sound; the objective and some inputs are not.** Every recipe in every FWC route is one of our
climb's candidates, used inside its learn and grey levels, and no FWC route beat our DP on our own objective
(section 3). The DP does double back when it pays, and a re-solve with patterns charged once found no cheaper
revisiting plan hidden on this data. What goes wrong is what the DP is asked to minimise (profit and a relative
grind), what it is fed (thresholds, learn levels, prices at the wrong quantity) and how its plans are presented.

Recommendations, in priority order:

1. **Fix the data bugs that make climbs wrong outright** (section 4):
   - Recipes with no DB2 thresholds (0/0) are planned as orange to 300 (C2). First Aid's climb is about 200×
     too cheap (4.3k copper against about 857k). Treat `trivial_high == 0` as "gives no points" (not every
     `trivial_high <= trivial_low`: 134 recipes have yellow = grey > 0, see C2).
   - Trainer learn levels are vanilla's, but Forever moved those recipes' colours 20–45 points lower (C3). 121
     trainer recipes are "learned" only after they turn yellow and 45 only at or after grey; the user's own
     characters know such recipes 5–25 points below the stored level. Verify one in game, then shift.
   - Recipe cooldowns are ignored (U1, not run through the verifiers but plain in the client data): the Alchemy
     climb plans ~95 crafts of Transmute: Mithril to Truesilver, a 1-hour cooldown.
   - `NumSkillUps = 0` is ignored (C18, low).
2. **Stop profit from paying the climb to grind** (C1, the main cause of the obscene last points): in the climb
   objective only, floor a craft's net cost at 10% of its material spend. About 10 lines; +10g over 32 test climbs
   for −6% crafts, and every profit-driven tail goes (Cooking 40 crafts on a point → 6.7, Enchanting 17.5 → 2.7).
3. **Replace `GRIND · cheapest · (1/p − 1)²` with an absolute per-craft effort term** (section 5): a copper value
   per craft (default about 50c, or 10g/h of play) with a convex risk shape. Tested two ways on our own climbs; both
   cost *less* gold than today's plans and remove every avoidable point over 10 crafts. It also removes the grind
   scale bug (C5). About 30–40 lines in `engine.Climb` and `Market._candidates`.
4. **Value disenchant output for the quantity made** (C4). With any enchanter alt, a 2-unit, one-scan Illusion Dust
   listing prices ~200 dust, and Tailoring's climb flips from 394g spent to 1,422g "earned".
5. **Fix how options are compared** (C9, C21, C22): options are banned from the whole climb, so a banned climb can
   dead-end early and, sorted by a cost that covers fewer levels, be badged Recommended.
6. **Credit skill points from same-profession sub-crafts** (C6): Engineering's blasting powders and Tailoring's
   bolts. Linen Bag 1→60 plans 94 bags where about 56 are needed.
7. **Make the shown figures agree** (C10, C13, C14, C15, C19): milestones run 9–15% above the sum of the cards in
   Leatherworking and Blacksmithing, the card's "per skill point" is up to 1.57× too large on one-point runs, and a
   run that ends because its recipe turns grey says another recipe "becomes a cheaper option".
8. **Say when a climb hits a wall** (C7, C8): with trainer-only sources climbs end at 220 (Leatherworking), 245
   (Tailoring), 280 (Cooking), 295 (Blacksmithing) after forced 20–40-craft points, and nothing tells the player.
9. **UI, without redesign** (section 6): label the options button, a tail line with a crafts range ("the last 4
   points take ~83 of these ~211 crafts; usually 158–275"), difficulty marks (orange/yellow/green/grey numbers),
   a "Copy for Auctionator" button, per-run totals, then a collapsible whole-climb table.
10. **Measure Forever's skill-up curve** (C12). Linear (ours) against vmangos-style 75%/25% steps moves a 40-wide
    band's last point from 40 crafts to 4; nobody has measured it. The addon already saves each recipe's live colour
    and the site throws it away; a per-craft (skill before, gained 0/1) log would settle the curve.

**Doubling back, in one paragraph.** The DP's state is the skill level alone, so any recipe can be taken up again,
and our plans do it where it pays (Elixir of Minor Defense around a one-craft Mana Well; Dark Leather Gloves around
Hillman's Shoulders; Flying Tiger Goggles around Heavy Dynamite). What it gets wrong is charging the pattern again
on the return, counting an unknown-price pattern twice (so it never returns to one), restarting spares, and never
seeing the one real reason to come back that FWC sees: a reagent's cheap listings running out (C13, C14, C16). None
of these hid a cheaper plan on the dev data; they mostly corrupt the milestones. FWC's frequent returns (0–10 a
route in the skill plans of section 3, up to 13 in its profit plans) are artefacts of its flat odds, and each return
to a green tail costs 40–90 crafts under the standard formula. So the answer to "are we missing profitable returns?"
is: not on this data; the return worth modelling is ladder depletion (C13), and the cheap fix is counting patterns once
(C14).

---

## 2. The algorithms

### 2.1 Alt Army (`engine.Climb`, engine.py:460-613)

- **Model.** A backward dynamic program over integer skill levels from the climber's skill to `end` (the cap, or the
  first level no candidate gives a point at). `finish[s] = min over (u covering s, stop) of legcost(u, s, stop) ⊕
  finish[stop]`, compared lexicographically on (patterns of unknown price, copper). Exact under its cost model.
- **Leg cost** (`_Usable.cost`, inlined in `_cheapest_from`):
  `cost·E[crafts] + max(cost, 0)·SPARE_Z·sd + Σ GRIND·cheapest[l]·(1/p − 1)² + learn`, with `SPARE_Z` 0.84 (p80),
  `GRIND` 0.1 and `cheapest[l]` the smallest |cost/p| of any candidate at level l.
- **Candidate price.** `Candidate.cost = −profit/n` from one `Market.evaluate` of n = `useful_crafts` (every point
  the recipe can give, capped at 100), reagents bought up the AH ladders, output sold at the best skill exit.
  `later_recipes` adds recipes learnable on the way, priced at the skill they unlock.
- **Chance.** `(grey − s)/(grey − yellow)`, orange 1, plus Working Overtime. Expected crafts, variance, p80 and
  `reach_chances` are exact for that chance model.
- **Output.** Each leg is cut into runs of at most `RUN_CEILING` (100) expected crafts. Options are further climbs
  that never craft the earlier options' recipes; the chain re-plans each later run at the skill it starts from.
- **Speed.** O(candidates × levels²): 29–113 ms per solve in CPython on the dev data. Candidate pricing dominates.

**Pros**: plans globally and is exactly optimal for its objective; knows the character (known recipes, talents,
reputation, alts mailing); buys up real order-book ladders; prices patterns and trainer fees; exact probabilities;
re-plans from the uploaded skill.

**Cons**: profit is credited per craft (C1); the grind is relative and collapses (C5); one price per candidate at
one quantity (C10); no shared ladders across legs (C13); no sub-craft points (C6); no kept products (C16); no
cooldowns (U1); a fixed horizon that must be climbed whatever the last points cost (C7).

### 2.2 foreverwowcraft.com (FWC)

Closed source (no repository found on GitHub or the web; the page's JS names a Python generator, `fwc.py`). A static
site: every route is precomputed about 47 minutes after each scan, 928 plan files per house (8 professions × 4
variants × up to 2 companion professions).

- **Odds: flat bands.** Orange 100%, yellow 75%, green 25%, grey 0, with green at the midpoint of yellow and grey.
  This reproduces every segment's crafts to within 1% over 36 plans. A green point never costs more than 4 crafts.
- **Route: a per-level greedy on marginal cost.** At each skill it takes the recipe with the cheapest cost per
  expected point, where the next craft's reagents are quoted deeper in each ladder given what the route already
  bought. On alchemy-trainer-skill no level of 299 has a cheaper alternative under its own prices; the exceptions in
  the profit routes are all ladder depletion. Segment boundaries fall anywhere and it doubles back often (profit
  routes: Alchemy 7 returns, Blacksmithing 13, Engineering 13; the skill routes of section 3: 0–10).
- **Prices.** Spot ladders; units beyond the listing at the dearest listed price × 1.25 ("scarcity 25%"); profit
  routes sell at `p × AH × 0.95 + (1 − p) × vendor` with p a sell chance by item kind (90/80/35/50%), adjusted for
  166 items by 7 days of sales. Skill routes value products at the vendor or disenchant price. Vendor prices are
  DB2's BuyPrice per unit without dividing by the stack count (Empty Vial 20c against our 4c).
- **Patterns** are evaluated as whole-route deltas (re-plan with and without; kept when the saving is positive).
  Trainer fees are not counted.
- **Extras we lack**: points from same-profession sub-crafts (`sub_points`: 39 of 289 Engineering points), kept
  products (`transfers`: a product a later segment consumes is valued at what it would otherwise cost), explicit
  gaps, vendor discounts applied after planning (reputation 5/10/15/20% from Friendly, multiplied with Bartering;
  ours is 10% from Honored, added; neither is verified on Forever).

**Pros**: fast, honest about gaps and thin listings ("ah, only N listed"), sub-craft points and kept products,
shared-ladder quoting, an Auctionator export. **Cons**: the flat odds hide the tails (its routes need 1.3–2.2×
the crafts it states under the standard formula, and every route has a 30–70-craft point); a greedy can't plan
ahead for patterns; no characters or known recipes; buys far past the book (184 Gromsblood from 1 listed); misses
recipes it can't price (Solid and Dense Grinding Stone); no cooldowns.

### 2.3 WowCraft (wowcraft.io, open source)

https://github.com/MalteNilsson/WoWCraft at 5bb334b. Next.js, all planning client-side on static JSON, TBC and
Vanilla data from Wowhead, AH prices from TSM refreshed hourly by a GitHub Action. We ran its planner unchanged
under Node on its own data.

- **Odds**: the standard linear formula (same as ours, no talents).
- **Route**: described as "backward dynamic programming", but it is a **single-path backward greedy** over 5-point
  batches aligned to multiples of 5. Each batch picks the cheapest material cost per point over its 5 points (with
  a 20% preference for a "chain recipe" whose output a later step uses), then adds the pattern amortised to grey.
  Doubles back freely; the UI then charges the pattern again.
- **Profit modes** hit our exact problem: a profitable craft has negative cost, so lower chances look better. They
  patched it with a hard floor: in profit modes a chance under 10% is rejected (`MIN_SKILL_UP_CHANCE_PROFIT_MODE`).
- **Bugs** (verified by running it): vendor reagents priced at the AH whenever any listing exists (Silken Thread at
  155g from one listing); per-level mode ignores its own phase-2 switch (fixing it saves 8–29% on several
  professions); chain recipes double-count; `orange: 0` read as missing; the rod at the target always crafted;
  difficulty colours shifted one band.

**Pros**: instant recompute, compact route list with inline alternatives, a chance-vs-skill chart, honest caveat
notes. **Cons**: no character input, one global price mode, a 5-point greedy, the bugs above, and in cost mode the
same "cheap intermediate to grey" tail as ours (Coarse Grinding Stone 99→100: 25 crafts).

### 2.4 Others

| Project | What | Plan model | Near-grey guard | Notes worth taking |
|---|---|---|---|---|
| **SkillUp Forever** (Forever addon, github.com/cjber/skillup-forever) | In-game route and costs | Greedy per point, re-planned at every skill change | Prices a point at its **90% quantile**; profit **clamped to 0** | Reads live `maxTrivialLevel`/`numSkillUps`; lists what would carry a stopped route on; "prices based on N days" |
| **Skillwright** (Forever addon, github.com/vBaustad/Skillwright) | Make-now card, route, shopping | **Backward DP over (rank, recipe in hand)** with a switch penalty of 3× the cheapest point | **25% chance floor**, multi-pass so no level goes unplanned; net cost floored at **10% of materials** | Estimates trainer learn ranks (`yellow − min(grey − yellow, 40)`) and flags them; tools and stations as steps; "or make this instead" |
| **Cole Profession Planner** (TBC addon) | Workbench | Greedy over 5-point blocks; switching needs 12% savings | Block scoring; a recipe switched away from is "retired" and reused only when nothing else works (no doubling back) | Crafted stock reused by later steps; **pattern opportunities** ("buying X would save ~Y") |
| **LazyProf** (Classic/TBC addon) | Route with alternatives | Myopic greedy with breakpoints | Green recipes excluded by default | Every step lists all candidates and **any can be pinned**, re-planning the rest |
| **CraftWise** (Forever addon) | Ranked table | None | — | **Measures the chance** from the player's own crafts, falling back to the formula, and says which |
| CheapSkill, WoWfessions, CraftRoute, Calg's (addons, no source) | Routes or tables | Greedy or manual refresh | Various | Cooldown recipes left out or planned once; route against the community guide; netted shopping list |
| wowtbc.gg Forever guide | Static guide | Hand-made with AH prices | — | "Used later" and "Stop at X" tags |

AzerothCore switched its emulator from fixed steps to the linear formula in September 2026 on player-observed craft
counts; vmangos (our data source) still uses 75%/25% steps. Blizzard never published the formula.

### 2.5 Comparison

| | Alt Army | FWC | WowCraft | Skillwright | SkillUp Forever |
|---|---|---|---|---|---|
| Plan model | Backward DP over level, exact | Per-level greedy, marginal ladder quotes | 5-point backward greedy | Backward DP over (rank, recipe) | Greedy per point |
| Odds | Linear + talents | Flat 100/75/25 | Linear | Linear | Linear, live grey |
| Doubling back | Yes; pattern recharged | Yes, often (band artefacts) | Yes; UI recharges pattern | Yes, costs a switch | Yes |
| Near-grey guard | `GRIND` (relative, collapses) | None (flat odds hide it) | 10% floor in profit modes | 25% floor + 10% net floor | 90% quantile + profit clamp |
| Time or effort cost | No (`time_value` unused in climbs) | No | No | Fast mode (separate) | No |
| AH buying | Ladder per candidate, from the bottom | Ladder shared along the route, ×1.25 past it | Min buyout (vendor items too) | AH price | 7-day median |
| Sub-craft skill points | No | Yes | No (sub-crafting off) | — | No |
| Kept products | No | Yes | Chain preference only | — | — |
| Cooldowns | No | No | Blacklisted by hand | — | — |
| Character aware | Yes (skill, recipes, talents, rep, alts) | No | No | Yes | Yes (in game) |
| Speed | 30–110 ms per solve, server | Precomputed | Instant, client | In game | In game |

---

## 3. Route comparison on Classic Beta PvE Horde

### 3.1 Method

Our routes are the top-ranked climbs from skill 1 as `/api/rank` builds them; FWC's are its skill-focus plans
(`<prof>-trainer-skill` against our trainer variant, `<prof>-plans-skill` against our default). In skill focus FWC,
like us, values products at the vendor or disenchant price.

**The two scans agree**: over 120 AH reagents the median price ratio is 1.00 (10th–90th percentile 0.96–1.25; the
outliers are FWC's 25% premium on deep purchases). FWC's scan was at 22:54 UTC on build 1.60.1.70009, ours ~50
minutes later on 70245. So differences come from the models.

Each route is priced under four models:

| Model | Crafts per point | Per-craft cost | Patterns, fees |
|---|---|---|---|
| **DP** | 1/p, standard odds, our thresholds | our `Candidate.cost` (priced for `useful_crafts`) | once per recipe; "DP objective" adds spares and grind, per leg |
| **EXACT** | as DP | each leg re-planned for round(E[crafts]) at its start skill (what `skill_chain` does) | once per recipe |
| **FWC odds × our prices** | FWC's flat bands, FWC's thresholds | our `Candidate.cost` | ours |
| **FWC model** | flat bands | FWC's own per-craft net (estimated for recipes it never used) | FWC's patterns, no fees |

The FWC model on FWC's own routes reproduces its published nets exactly (alchemy-trainer-skill 133.49g).

### 3.2 Totals (gold, over the skill range both routes cover)

| Profession | Sources | Range | Route | DP spent | EXACT | FWC odds × our prices | FWC model | Crafts, std / flat | Worst point (crafts) |
|---|---|---|---|---:|---:|---:|---:|---|---:|
| Alchemy | trainer | 1–300 | ours | **94.3** | **94.0** | 105.6 | 139.7 | 445 / 508 | 6.7 |
| | | | FWC | 108.2 | 108.2 | **97.8** | **133.5** | 810 / 574 | 40 |
| Alchemy | default | 1–300 | ours | **57.4** | **56.3** | 56.6 | 82.2 | 408 / 445 | 6.7 |
| | | | FWC | 59.8 | 59.6 | **52.8** | **62.0** | 630 / 472 | 40 |
| Blacksmithing | trainer | 1–290 | ours | **2,593** | **2,420** | **2,836** | **~3,100†** | 467 / 489 | 13.3 |
| | | | FWC | 11,908 | 11,285 | 6,366 | 7,860 | 865 / 541 | 40 |
| Blacksmithing | default | 1–290 | ours | **1,102** | **986** | **1,330** | n/a† | 424 / 452 | 13.3 |
| | | | FWC | 9,942 | 9,708 | 6,190 | 8,476 | 701 / 485 | 40 |
| Cooking | trainer | 1–280 | ours | 38.6 | 40.9 | 27.4 | 34.2 | 507 / 459 | 40 |
| | | | FWC | **37.7** | **40.2** | **26.3** | **33.0** | 616 / 488 | 40 |
| Cooking | default | 1–300 | ours | **−2.3** | **−2.3** | **−0.7** | **1.2** | 627 / 510 | 40 |
| | | | FWC | 1.6 | 1.5 | 1.9 | 3.0 | 646 / 532 | 40 |
| Enchanting | trainer | 1–300 | ours | **629** | **600** | 866 | 844 | 429 / 504 | 4.0 |
| | | | FWC | 925 | 928 | **361** | **338** | 1,053 / 554 | 40 |
| Enchanting | default | 1–300 | ours | **78.3** | **73.9** | **82.7** | 88.8 | 433 / 440 | 17.5 |
| | | | FWC | 116.6 | 115.8 | 117.7 | **69.2** | 542 / 482 | 40 |
| Engineering | trainer, The Mortar banned | 1–290 | ours | 592.5 | 575.6 | 441.3 | 545.5 | 504 / 552 | 20 |
| | | | FWC | **544.9** | **543.3** | **280.5** | **344.4** | 829 / 608 | 40 |
| Engineering | default | 1–290 | ours | **135.2** | **127.1** | **154.4** | **164.5** | 418 / 490 | 6.0 |
| | | | FWC | 544.9 | 543.3 | 280.5 | 344.4 | 829 / 608 | 40 |
| First Aid | trainer, First Aid Kit banned | 1–210 | ours | **7.6** | **7.6** | **4.5** | 6.8 | 521 / 427 | 60 |
| | | | FWC | 9.7 | 10.1 | 4.6 | **4.4** | 868 / 454 | 70 |
| First Aid | default, First Aid Kit banned | 1–300 | ours | **68.0** | **55.7** | n/a§ | n/a§ | 575 / – | 10 |
| | | | FWC | 112.1 | 112.9 | 85.3 | 89.0 | 1,136 / 683 | 70 |
| Leatherworking | trainer | 1–220 | ours | **279.2** | **264.6** | 219.5 | 190.1 | 403 / 404 | 20 |
| | | | FWC | 291.4 | 275.6 | **204.5** | **182.2** | 609 / 437 | 30 |
| Leatherworking | default | 1–250 | ours | **330.5** | **210.9** | **354.7** | **~200** | 310 / 343 | 4.0 |
| | | | FWC | 1,175 | 1,068 | 626.9 | 694.0 | 635 / 427 | 30 |
| Tailoring | trainer | 1–245 | ours | **1,742** | **1,708** | 750.0 | 848.4 | 830 / 662 | 30 |
| | | | FWC | 1,924 | 1,879 | **693.7** | **805.9** | 1,592 / 731 | 35 |
| Tailoring | default | 1–245 | ours | **138.8** | **131.5** | **151.6** | **181.2** | 346 / 370 | 8.8 |
| | | | FWC | 1,281 | 1,253 | 490.1 | 569.1 | 1,127 / 538 | 35 |

† FWC has no price for Dense Grinding Stone; one of our legs is left out of its model there (trainer: estimate with
it added; default: not usable). Our First Aid and Engineering trainer routes as shipped rest on the 0/0-threshold bug
(C2); the rows above ban those recipes (First Aid Kit 52641, The Mortar: Reloaded 7296). § With those banned, our
First Aid default climb finishes 261→300 on Toxin Study, which is also 0/0 in our data (FWC: learn 140, grey 145), so
that row still rests on C2 and FWC's odds can't price it.

Reading it:

- **Under our model (DP, EXACT) ours is cheaper in 14 of 16 comparable cases.** The two exceptions (Cooking trainer,
  0.7–0.9g; Engineering trainer with The Mortar banned, 32–48g) are trades the grind made on purpose: with `GRIND = 0`
  the DP reproduces FWC's copper (Cooking trainer at GRIND 0: 37.7g, 607 crafts, against FWC's 37.7g, 616). On the
  DP's full objective (spares and grind included, not shown in the table) ours still wins both: Cooking 1,341 against
  1,352, Engineering 7,943 against 12,525.
- **Under FWC's model each route tends to win on its own terms**, but ours is cheaper *even under FWC's model* in
  Engineering, Leatherworking default, Tailoring default and Blacksmithing trainer. FWC's greedy is not optimal for
  its own objective.
- **The odds model explains most of the gap.** FWC's worst point is 30–70 crafts in every route under standard odds;
  ours is 4–7 except at walls (trainer-only Tailoring, Leatherworking, Blacksmithing, Cooking, First Aid) and on
  profitable grinds (Cooking 40, Enchanting 17.5). FWC spends 73–894 crafts per route on points that take over 10
  crafts each; ours 0–225, and 12 of 16 at 0–40.

### 3.3 Alchemy, trainer recipes only

DP model (standard odds, our per-craft cost), the fee or pattern added at the first level a recipe is used. FWC's
crafts under standard odds, its own flat count in brackets.

| Skill | Ours | Crafts | Copper | FWC | Crafts std (flat) | Copper, our prices |
|---|---|---:|---:|---|---:|---:|
| 1–10 | Elixir of Minor Force | 9.0 | −81c | Elixir of Minor Defense | 9.0 (9.0) | 243c |
| 10–15 | Elixir of Minor Force | 11.4 | −103c | same | 11.4 (14.7) | −103c |
| 15–20 | Elixir of Minor Defense | 5.0 | 135c | same | 5.0 (5.0) | 135c |
| 20–21 | Mana Well | 1.0 | 20c | Elixir of Minor Defense | 1.0 (1.0) | 27c |
| 21–85 | Elixir of Minor Defense | 88.0 | 2,375c | same | 88.0 (100.7) | 2,375c |
| 85–95 | Lesser Discolored Healing Potion | 11.3 | 1,755c | **Elixir of Minor Defense to grey** | **117.2 (40.0)** | 3,163c |
| 95–101 | Lesser Discolored Healing Potion | 8.8 | 1,355c | same | 8.8 (8.0) | 1,355c |
| 101–130 | Elixir of Wisdom (450c fee) | 30.3 | 9,489c | Lesser Discolored, then Swim Speed Potion | 32.1 (30.3) | 10,335c |
| 130–163 | Fire Oil | 40.1 | 8,057c | same | 40.1 (45.3) | 8,057c |
| 163–175 | Elixir of Fire Power | 13.4 | 11,450c | **Fire Oil to grey**, then Fire Power | **58.0 (34.7)** | 15,938c |
| 175–190 | Greater Discolored Healing Potion | 18.5 | 9,111c | same | 18.5 (20.0) | 9,111c |
| 190–218 | Draught of Water Walking | 47.1 | 3.68g | Greater Discolored, Water Walking, **back to Greater Discolored to grey**, Water Walking | 130.6 (58.7) | 7.32g |
| 218–250 | Catseye Draught | 56.0 | 24.0g | **Water Walking to grey**, Elixir of Defense, Catseye, Restorative, **back to Elixir of Defense to grey** | 176.0 (88.1) | 34.5g |
| 250–259 | Stonescale Oil (1.35g fee) | 19.3 | 9,642c | same | 19.3 (22.7) | 9,642c |
| 259–260 | Draught of Detect Demon (1.26g fee) | 1.0 | 1.96g | Stonescale Oil to grey | 10.0 (4.0) | −2,000c |
| 260–300 | Draught of Detect Demon | 84.8 | 59.37g | same | 84.8 (91.7) | 60.63g |
| **Total** | | **445** | **94.3g** | | **810 (574)** | **108.2g** |

(Rows 101–130, 163–175, 190–250 merge 2–3 rows of the source table; their figures are sums.)

Our route doubles back once (Elixir of Minor Defense around Mana Well's single point) and leaves Minor Defense at
85, where its standard odds have fallen to 25%; FWC runs it to grey (147 crafts). FWC's last segment costs more
mostly because of its 25% scarcity premium on ~184 Gromsblood (1 listed).

### 3.4 Alchemy, trainer + recipe

| Skill | Ours | Crafts | Copper | FWC | Crafts std (flat) | Copper, our prices |
|---|---|---:|---:|---|---:|---:|
| 1–21 | Minor Force, Minor Defense, Mana Well | 26.4 | −29c | Minor Defense, Minor Force, Minor Defense | 26.4 (29.7) | 302c |
| 21–83 | Elixir of Minor Defense | 81.0 | 2,187c | Minor Defense, then Rage Potion | 69.2 (68.7) | 2,937c |
| 83–107 | Rage Potion | 28.8 | 4,358c | Rage Potion, **back to Minor Defense to grey**, Rage Potion | 114.8 (43.0) | 5,944c |
| 107–130 | Elixir of Wisdom | 24.3 | 7,702c | Rage Potion, Wisdom, Swim Speed | 25.5 (24.0) | 8,551c |
| 130–164 | Fire Oil | 43.0 | 8,567c | same | 43.0 (49.3) | 8,567c |
| 164–175 | Elixir of Ogre Strength | 11.0 | 9,621c | Fire Oil to grey, Fire Power | 55.1 (30.7) | 1.54g |
| 175–199 | Greater Discolored, Water Walking | 28.6 | 1.70g | same mix | 32.0 (32.0) | 1.72g |
| 199–225 | Nature Protection Potion | 29.5 | 3.42g | Water Walking, Detect Lesser Invisibility | 33.5 (33.0) | 4.64g |
| 225–275 | Transmute: Mithril to Truesilver | 94.8 | 3.47g | Iron to Gold, Stonescale Oil, Iron to Gold | 108.2 (115.0) | 4.47g |
| 275–280 | Draught of Detect Demon | 7.2 | 6.27g | **Iron to Gold to grey** | **91.3 (20.0)** | 3.35g |
| 280–300 | Detect Demon, Elixir of Greater Defense | 33.4 | 39.26g | Detect Demon, Greater Defense | 30.6 (26.7) | 41.50g |
| **Total** | | **408** | **57.4g** | | **630 (472)** | **59.8g** |

Both routes run a 1-hour-cooldown transmute about 95–109 times (U1).

**Why FWC's per-craft prices run 7–75% above ours** for the same recipes: it charges DB2's vial BuyPrice per vial
without dividing by the stack of 5 (Empty Vial 20c against 4c, Crystal Vial 2,500c against 500c; our reading fits
the usual 4:1 buy-to-vendor-sell ratio; this adds 23.5g to its trainer route), its 25% premium past the listing,
and 1–2c on cheap herbs. Thresholds agree; learn levels differ in both directions (Minor Force 10 in FWC, 1 in
ours; Water Walking 175 and Restorative Potion 210 in FWC where ours falls back to yellow, 190 and 225).

### 3.5 Other professions, briefly

- **Blacksmithing.** Close to 175. Above 200 FWC goes into Truesilver Champion and Prefect's Waistguard (2,336g for
  30 crafts, Golden Pearls bought far past ~20 listed) and never uses the late thorium weapons because it can't
  price Solid or Dense Grinding Stone. Both routes buy thousands of unlisted units (Thorium Bars: 3,421 short in our
  trainer route against 16 listed).
- **Cooking.** Both have a 40-craft point. Ours grinds Lean Venison 180→190 (117 crafts for 10 points, earning
  151c a craft: C1); FWC grinds Goblin Deviled Clams 202→205.
- **Enchanting.** FWC's wand route looks cheap only under flat odds (361g against our 866g); under standard odds it
  costs 925g against our 629g because it runs each wand to grey. Ours earns on Minor Wizard Oil 5–64 but grinds its
  last point at 17.5 crafts (C1).
- **Engineering.** FWC credits 39 of 289 points to intermediates (Rough Blasting Powder, Heavy Blasting Powder); we
  credit none (C6). With The Mortar banned, FWC grinds Mithril Gyro-Shot to grey (98 crafts, 62.3g) where ours
  switches to Salt Shaker (14.7 crafts, 125.9g): our grind paid 63.6g to skip 83 crafts, ~77s a craft. In Cooking
  the same term pays ~0.8c a craft. That 10,000× swing is C5.
- **First Aid.** Our shipped route is fiction (First Aid Kit 154→300 at p = 1, C2). Banned, ours costs 7.6g to 210
  against FWC's 10.1g; both grind Silk Bandage to grey (60 crafts on the last point).
- **Leatherworking.** Trainer: identical from 176 to 220, both ending on Nightscape Headband with 20 crafts on the
  last point (FWC counts 4). Ours stops at 220 (C8); FWC jumps the 220–235 gap. Default: FWC's Deviate Scale Cloak
  65–125 buys 1,090 Deviate Scales short against 110 listed.
- **Tailoring.** Trainer: identical from 201 to 245, the same four 5-point legs each ending at 30–35 crafts a
  point. **The 245 wall is in FWC's data too** (its Black Mageweave Vest is also learned at 205 against yellow 185),
  so C3 isn't ours alone.

---

## 4. Bugs and flaws in our algorithm

Every item below was checked by three independent verifiers that tried to refute it (reproducing on the dev
database, the live dev API or synthetic climbs). "Upheld 3/3" means none refuted it. Where the verifiers corrected
the original claim, the corrected version is given. IDs: **C** confirmed, **X** contested, **U** found by the
research but not put to the verifiers.

### 4.1 Confirmed: high

**C1. Profit is credited per craft, so a money-maker's wasted low-chance crafts earn money and the grind can't stop
it.** Upheld 3/3. The main cause of the obscene last points (section 5).

- **Where**: engine.py:2169-2196 (`Market._candidates`: `Candidate.cost = −profit/n`, copper only); 419-427 and
  527-552 (`cost × crafts`); 490-503 (`cheapest`, grind); 315-322 (`GRIND`).
- **Mechanism**: a point at chance p costs `cost/p`; with cost < 0 that runs to −∞ as p falls. Spares use
  `max(cost, 0)` and vanish. The only brake is `0.1 · cheapest[l] · (1/p − 1)²`, scaled by the cheapest point at the
  level, which has nothing to do with this recipe's margin, so the DP grinds until 1/p ≈ 10·|cost|/cheapest. The
  profit doesn't depend on skill (the craft sells the same once grey), so the climb is planning a gold farm.
- **Evidence** (dev data, default sources, from 1):
  - Cooking: Lean Venison 110→190, 211 crafts, 40 on 189→190, at −151.5c a craft. At 189 the point counts as
    −6,059c against a 608c grind (cheapest = 4c); Rockscale Cod gives that point in 1 craft for 8c. Lean Wolf Steak
    190→205 again ends with 40 crafts on one point. Total 627 crafts.
  - Enchanting: Minor Wizard Oil 5→64 (−82c a craft), 17.5 crafts on 63→64, against Enchant Bracer - Minor Spirit
    at 1 craft for 29c.
  - First Aid: Simple Poultice 90→154, 10 crafts a point. Tailoring: Linen Bag 1→62, 8.8. Engineering: Rough
    Dynamite, 6.
  - The profit is real at that volume (Lean Venison 207c a craft at 100 crafts, 206c at 211, 0 short): the
    defect is crediting skill-independent profit to a skill-up decision and charging nothing per craft.
- **Not a fix on its own**: flooring cost at 0 leaves Cooking's 40-craft point (a 0-cost candidate also zeroes
  `cheapest`). Plain +20c a craft leaves it too.
- **Fix**: in the climb objective only, `max(cost, 0.1 × gross) + k` per craft (section 5). Keep real profit for
  display.

**C2. Recipes with no DB2 thresholds (0/0) are planned as orange to the cap.** Upheld 3/3.

- **Where**: engine.py:204-212 (`can_skill_up` returns True on `not trivial_high` before the cap check), 215-225,
  228-261, 264-272; ingest.py:759-760.
- **Scenario**: First Aid from 1 ends with First Aid Kit 154→300, 146 crafts at p = 1: 4,285c and 415 crafts in
  all. With the 0/0 recipes banned the real climb is 856,924c over 587 crafts. From 150: 4,574c against 857,169c.
  At 300/300 `skill_up_chance` still reports 100%.
- **Evidence**: rows 52641 (First Aid Kit), 57024 (Toxin Study), 57036 (Plague Doctor's Laboratory), 7296 (The
  Mortar: Reloaded), 59526 (Winter Boots) are 0/0 in 1.60.1.70245. SkillUp Forever's changelog (build 70205) says
  Winter Boots and the ten camp furnishings, First Aid Kit and Toxin Study among them, "no longer give skill-ups",
  and its generator drops rows with grey ≤ yellow. In the user's SavedVariables every 0/0 recipe with a recorded
  colour is grey (Lodestone, Camp Chair, Study at Comprehension 24, Incense Candle, Fish Bowl). First Aid Kit's own
  colour isn't recorded.
- **Reach**: among climbable professions it breaks First Aid. Engineering's The Mortar is never cheapest with
  default sources (it is in the trainer climb, 278→300); Winter Boots is bop.
- **Fix**: treat `trivial_high == 0` (no thresholds) as "gives no points" (`_chance_at` 0, `can_skill_up` False, cap
  checked first); keep the recipe for the gold list; a test that a 0/0 recipe gets no span.
- **Don't widen it to `trivial_high <= trivial_low`** without checking in game. In the eight climbable professions
  134 recipes have yellow = grey > 0 (Filigreed gowns 80/80, the Blacksmithing chain shirts 85/85, Cured Thick Hide
  175/175, Rugged Leather 225/225, the 300/300 stations). Today they are orange up to that skill and grey from it,
  which is what the formula says; SkillUp Forever's generator drops them as giving nothing. Most never get a span
  (trainer ones with `learn_skill` 0 or at/above the threshold), but some are planned: Inlaid Mithril Cylinder
  Plans (trainer, learn 200, 205/205) is the Recommended first run for Engineering at 200 in C21 and a 3-point leg
  of Engineering from 150. One in-game check (that recipe, or a Filigreed pattern, below its threshold) settles
  which reading is right.

**C3. Trainer learn levels are vanilla's, but Forever moved those recipes' colours 20–45 points lower.** Upheld
3/3.

- **Where**: ingest.py:592-598 (`req_skill` from vmangos' `npc_trainer`), 745-765 (`learn_skill = learned_at or
  trainer_skill`); vmangos.py:251-265; engine.py:121-125 (`required_skill`); engine.py:2183, service.py:1214-1217,
  1259-1279 (candidate start, `later_recipes`, the hypothetical climber's known recipes).
- **Evidence**:
  - Forever's yellow moved against TBC's by −25 on ~372 recipes, −35 on 59, −45 on 42. Of trainer recipes whose
    yellow moved, 121 of ~236 have `learn_skill` above yellow; of unmoved ones, 0 of ~219. Item-taught recipes moved
    with the colours (only ~7 of ~369 have learn above yellow).
  - 45 trainer recipes are learnable only at or after grey: Bolt of Silk Cloth (learn 125, yellow 110, grey 120),
    Heavy Sharpening Stone (125/100/115), Formal White Shirt (170/145/155), Iron Buckle (learn 150, grey 130).
  - **The user's characters know such recipes below the stored level** (38 character-recipe pairs): Frell Blast,
    Tailoring 150, knows Silk Headband and White Swashbuckler's Shirt (160); Frell Ofelements, Leatherworking 158,
    knows Frost Leather Cloak and Green Leather Bracers (180); Frell Hathnofury, Blacksmithing 70, knows Rough Bronze
    Boots (95) and Runed Copper Bracers (90). Every pair fits "learn level minus the recipe's yellow shift".
- **Effect**: ~120 recipes lose their orange stretch, 45 are never candidates, `later_recipes` take them up too
  late, and walls sharpen: the trainer-only Tailoring climb is forced onto Robe of Power 198→205 (78 crafts, down to
  1 in 30) because Black Mageweave Leggings is assumed unlearnable until 205 though it is yellow from 185. Shifting
  learn levels by the colour shift: Tailoring default −6.2% (3,940,146c → 3,695,078c), Tailoring trainer 17.4M → 2.0M
  and reaching 255 instead of 245; Leatherworking default −8.0% (13,179,927c → 12,130,104c; not re-run by the
  verifiers).
- **Fix**: verify one in game (Bolt of Silk Cloth or Black Mageweave Leggings). Then shift every trainer recipe whose
  colours moved by the same delta, clamped to ≥ 1 (not only those above yellow: Heavy Copper Broadsword, learn 90,
  yellow 110, is known at 70). Better: have the addon record `GetTrainerServiceSkillReq` at a trainer, and treat a
  known recipe's character skill as an upper bound. Meanwhile flag learn ≥ grey as a data error.
- **Related data gap** (not verified separately): the other way round, many trainer recipes have `learn_skill` 0
  (15 of 45 Alchemy, 33/115 Blacksmithing, 38/112 Leatherworking, 11/92 Tailoring, 10/16 First Aid), so
  `required_skill` falls back to yellow and hides their orange levels. FWC has learn levels for them. And the reverse
  disagreement: FWC learns Elixir of Minor Force at 10 and Linen Bag at 45 where ours says 1 (they come with the
  profession in our data); if FWC is right, our first Alchemy and Tailoring runs can't be crafted as planned. Check
  one in game.

**C4. Disenchant sell-back is valued at the materials' AH price for any number of units.** Upheld 3/3.

- **Where**: engine.py:1581-1586 (`_expected`), 1607-1610 (`disenchant_value`), 1612-1626 (`exits_for`), 2079
  (`revenue = exit.value × units`).
- **Scenario**: Tailoring from 1 with any enchanter alt: 3,940,146c → −14,218,966c (a 1,422g "profit"). It
  disenchants 66 Wizardweave Turbans at 249,375c each (vendor 12,768c), selling ~204 Illusion Dust at 100,000c while
  the AH lists exactly 2 (one listing, `scans_7d` 1, no sales). Leatherworking 13.18M → 8.14M. The disenchant money
  also feeds C1: Brown Linen Pants 30→85 with 35 crafts on its last point.
- **Notes**: the hypothetical climber has no enchanter, so it is unaffected; it hits users with an enchanter alt.
  The low-level green tails rest on deep Strange Dust markets, so their tails are C1, not this. Unpriced material
  rows (Greater Eternal Essence, Large Brilliant Shard) are silently dropped, which undervalues instead.
- **Fix**: walk each material's sell-side depth for the run's quantity, capped like the gold list's depth (units
  seen sold plus listed at or under the price), or take min(sell price, 7-day median, price at depth); apply
  `prices.confidence` (cut low-confidence materials); treat a disenchant whose main result is unpriced as unpriced.
  WowCraft's cheaper guard is worth noting: in its AH mode it gives no AH credit to an item with fewer than 4
  auctions or a margin over 500%.

### 4.2 Confirmed: medium

**C5. The grind scale `cheapest[l]` collapses, and unused candidates change the plan.** Upheld 2/3.

- **Where**: engine.py:492-496 (`cheapest = min |cost/p|` over every candidate), 503.
- **Mechanism**: the minimum includes the candidate being ground (a break-even recipe switches off its own penalty),
  profitable ones through `abs()`, and ones whose pattern price is unknown, which the lexicographic order never lets
  the plan use. So the objective isn't independent of irrelevant alternatives.
- **Evidence**: synthetic: a 0c recipe grinds to grey with 30 crafts on its last point while an alternative gives
  each point for 10c; adding a never-used 0.01c candidate with an unknown pattern moves a recipe's stop from 36 to
  39 (6 → 15 crafts on the last point). Dev data: Cooking's scale is ~4c over 150–205 (set by Spotted Yellowtail and
  Tasty Lion Steak), First Aid's worst point moves 10 → 7 when only unused candidates are removed, Alchemy's 275–300
  split moves 288 → 287 when unused unknown-pattern recipes are dropped.
- **Dissent**: one verifier found the real-data effect modest (fixing only this changes Engineering's worst point
  6.0 → 4.3 and shifts Alchemy and Blacksmithing by a level, for more copper) and the big tails are C1. Agreed: this
  is not the main cause, but it is why the grind's price per avoided craft swings from 3c (Cooking) to 5.6g
  (Blacksmithing trainer from 150).
- **Fix**: superseded by replacing the scale with an absolute per-craft value (section 5). If GRIND stays: compute
  the scale over known-price, positive-cost candidates other than the one ground, with a floor.

**C6. Points from same-profession sub-crafts the climber makes are never credited.** Upheld 3/3.

- **Where**: engine.py:2059-2071 (`expected_skill_ups` of the root only), 2169-2188, 419-427 and 460-504 (spans use
  the root recipe's chance).
- **Evidence** (Monte Carlo of the run as played, root-only simulation matching the planner): Rough Dynamite 1→56
  plans 86 crafts (with 86 Rough Blasting Powder in its tree), ~70 needed; Heavy Dynamite 125→139 plans 23 crafts
  (46 Heavy Blasting Powder, orange at 125), ~7–8 needed, ~650c of the leg's ~970c loss buys unneeded crafts; Linen Bag
  1→60 plans 94 bags with 282 Bolts of Linen Cloth, ~56 needed (about 34 points come from the bolts). Leatherworking,
  Blacksmithing and Alchemy intermediates are grey when made, so only early Engineering and Tailoring are affected.
  FWC credits these (`sub_points`).
- **Harm**: overstated "Craft until", crafts to buy for, p80 and reach chances; the DP can't see the intermediate as
  a skill source. The gold at stake is small (the Rough Dynamite and Linen Bag legs are profitable).
- **Fix**: when pricing a candidate, record per root craft how many crafts of each climbed-profession sub-recipe the
  climber makes; points per root craft at l = `p_root(l) + Σ kᵢ·pᵢ(l)`, used for crafts per point, variance and the
  effort term. First step: count them in `_run`'s crafts and reach, and say "N points come from making its X".

**C7. The DP must reach `Climb.end`; where one recipe covers the last levels, near-grey points are ground
silently.** Upheld 2/3.

- **Where**: engine.py:506-511 (`end` the only terminal), 515-524, 597-602; api.py:1831-1840 (`_milestones` drops
  unreached ranks without a word); lib/skill.ts (only rival/ceiling/trivial/cap wordings).
- **Scenario** (trainer-only from 1): Cooking ends at 280 (Spider Sausage 274→280, 98 crafts, 40 on 279→280);
  Tailoring ends at 245 (Robe of Power 198→205, 78 crafts; Shadoweave Boots and two more 5-point legs at ~68 crafts
  each, ~952g for the last 15 points); Blacksmithing ends at 295 (Inlaid Thorium Hammer 270→295, 95 crafts, 25 on
  the last point, ~3,124g); Leatherworking at 220.
- **What is and isn't wrong**: the forced grind is a constant every plan through the wall pays, so it never changes
  the plan; it inflates `climb_cost` (Tailoring 64,470g objective against 1,742g spent), which is never shown. The
  dissenting verifier called it documented design and a UX gap; with default sources every profession reaches 300
  with no forced point. The real defect is presentation: nothing says "the climb ends at 245 with these sources",
  "nothing else gives a point from 200 to 204", or which pattern bridges the wall.
- **Fix**: flag forced stretches and `end < cap` on the result and say so; re-solve with recipe sources and name the
  patterns that bridge the wall with the copper and crafts saved; a "stop here" terminal only for true dead ends,
  where the last points lead nowhere.

**C8. Recipes with an unpriceable reagent are silently dropped from the candidates, lowering the horizon.** Upheld
2/3.

- **Where**: engine.py:2184-2188, service.py:1238-1241 (`evaluate` returns None, the recipe vanishes), engine.py:506-509.
- **Scenario**: Leatherworking trainer from 1 ends at 220 with Nightscape Headband 205→220 (20 crafts on the last
  point). 34 of the 37 trainer recipes that would give points past 220 need a reagent nobody lists (Turtle Scale,
  Thick Wolfhide, Heart of Fire, Worn Dragonscale; Cured Thick Hide is craftable but its Thick Hide isn't listed),
  stranding three priced ones past the gap. Pricing just those reagents at a fallback (last-seen median or
  BuyPrice, via the existing `gathered` option) moves the end to 270. Turtle Scale even has an unlisted last-seen
  median (200c) that the engine ignores. Tailoring's (245) and Blacksmithing's (295) ends don't move.
- **Dissent**: CLAUDE.md documents the exclusion; default sources reach 300; pricing unbuyable reagents would invent
  costs. Agreed on the last point: the fix worth doing is disclosure.
- **Fix**: note when a climb ends below the cap, naming the recipes left out and the reagents they lack ("farm or
  find N Turtle Scale"); optionally keep them as candidates flagged "unknown reagent price", like unknown patterns.
  Skillwright's approach is a middle way: plan by cost up to the first rank it can't price, then by crafts beyond
  it, and label the join ("cost known to rank N").

**C9. "Show me other options" bans earlier options from the whole climb, so later options can dead-end and still be
badged Recommended.** Upheld 3/3.

- **Where**: service.py:516-584 (`climb_options`), engine.py:2151-2167 (bans apply to every leg), 506-509;
  SkillWorkspace.tsx:69-74, 520, 962 (`byClimbCost`, `i === 0` badged).
- **Scenario** (hypothetical climber, `/api/rank top=4` as the workspace calls it):
  - Cooking at 150, trainer: Goblin Deviled Clams (13,381,470, reaches 280), Dry Pork Ribs (7,661,448, ends at 160),
    Crab Cake (7,538,397, ends at 155). The UI badges **Crab Cake** Recommended.
  - Tailoring at 150, trainer: Azure Silk Pants (19.4M, ends at 165) is badged over Small Silk Pack (644.6M, reaches
    245).
  - First Aid at 200, trainer: option 2 Silk Bandage runs 200→208 in 86 crafts then 90 crafts for ~1.6 points and
    ends at 210.
  - The same recipes as unbanned `first(r)` climbs all reach the same end within a fraction of a percent
    (Clams 13,381,470, Ribs 13,388,718, Crab Cake 13,396,404).
- **Notes**: banning for the whole climb is documented intent; the bug is comparing climbs of different lengths by
  cost. With default sources Cooking at 150 orders correctly. The single-column view still crafts the server's best.
  The opposite failure shows up too: on Alchemy from 1 (default) the three options differ only in their first 1–2
  crafts and cost within 0.1% of each other (676,227 / 676,309 / 676,746c), so the side-by-side view offers no real
  choice there (section 6.2, item 8).
- **Fix**: make the options the next-cheapest first runs (`matches[1..3]`, each its own `first(r)` climb, de-duplicated
  by first recipe), or ban earlier options only from the first leg; compare by (skill reached desc, unknown, cost);
  never badge one that reaches less than the best; annotate "dead end at N".

**C10. Candidates are priced at `useful_crafts` (up to 100) and charged flat for legs of any length.** Upheld 3/3.

- **Where**: engine.py:433-448 (`useful_crafts`), 2183-2188 and service.py:1237-1241 (priced once), 2058-2059 (the
  shown run re-planned at its own crafts), 379-393 (`spent_by`), book.cost (short units at the dearest level).
- **Scenario**: Leatherworking from 1: the 300 milestone reads 1,318g while the chain cards add up to 1,122g
  (−14.9%); Blacksmithing −9.4%; Enchanting −5.7%; Engineering −3.4%; all 16 cases lower. Per leg: Rugged Armor Kit
  230→236 priced at 22,416c a craft (66 crafts, 143 Rugged Leather short at a single 10,000c listing) but 1,500c a
  craft for the 10 it needs; Nightscape Headband 21,840 against 8,989; Wicked Leather Gauntlets 59,957 against
  31,607.
- **Effect on plans**: small and mixed (a fixed-point re-solve at true quantities: Leatherworking −4.9%, others
  −0.4% to +0.1%). The cards aren't the truth either: each prices its run from an untouched ladder (C13), so the
  real cost lies between the two figures. The sure harm is two disagreeing numbers on one screen.
- **Fix**: price candidates at a few quantity buckets (5, 15, 40, 100, 250 crafts) and interpolate, or re-price the
  chosen legs and re-solve (2–3 passes); take milestones and cards from one pricing; price units beyond the ladder at
  a median-based figure, not the dearest outlier.

**C11. Unknown pattern prices are avoided at any copper cost, and the cost of avoiding them is never shown.**
Upheld 2/3.

- **Where**: engine.py:396-401 (`_Cost`, lexicographic `_cheaper`), 427, 530; service.py:1371-1383, 1398-1412;
  api.py:1948 (`climb_cost` None whenever `climb_unknown`).
- **Scenario** (from 1, default): Blacksmithing pays 22,607,639c; allowing Plans: Thorium Leggings 276→300 gives
  11,995,686c plus the pattern (those 24 points: 5.94M against 16.56M for Ornate Thorium Handaxe and Huge Thorium
  Battleaxe), **~1,060g**. Engineering 1,946,389c against 1,441,148c with Schematic: Thorium Shells; Alchemy 573,505c
  against 378,064c with Recipe: Greater Stoneshield Potion.
- **Correction**: these patterns are not reputation- or condition-locked vendor recipes, as first claimed. They are
  tradeable world drops (one `world_drop` source each) not listed on this house's AH (they are listed on house 2).
  The dissenting verifier: avoiding an unbuyable pattern is right. Agreed as the default.
- **Fix**: keep the default, but surface it ("Plans: Thorium Leggings, a world drop not on the AH, would save
  ~1,060g"); let a user mark a pattern as owned or give it a price; optionally use another house's price or a finite,
  configurable penalty.

**C12. The site discards the live per-recipe difficulty the addon already uploads.** Upheld 2/3. A missed
opportunity, not a wrong output.

- **Where**: altarmy.py:159-166 (`_profession` keeps ids only); addon `DataStoreProfessions.lua`:1012-1025 (saves
  `color` from `GetRecipeInfo().relativeDifficulty`).
- **Evidence**: on the user's file the colours agree with the DB2 thresholds in 225 cases (Forever's −25 shift
  included); the 4 that disagree (Frell Hathnofury, Blacksmithing 75) all fit colours read at 74, so a colour's skill
  must be saved with it; every 0/0 recipe is grey (C2). The chance curve inside a band is unmeasured, and it decides
  the tails: under the linear formula a 40-wide band's last point is 40 crafts, under flat 75/25 steps 4; Working
  Overtime added (+0.2) turns the last 5 green points from 91 crafts into 18.5, multiplied (×1.2) into 76.
- **Dissent**: colours alone can't measure the curve; it needs per-craft logging. Agreed: store colours (cheap
  validation of thresholds and learn levels) and add the log.
- **Fix**: store each known recipe's colour with the rank it was read at (and `maxTrivialLevel`/`numSkillUps` if
  Forever's `GetRecipeInfo` returns them; unverified); an admin report of disagreements; have the addon log (recipe,
  skill before, gained 0/1) per craft and upload counts. A few hundred green-band crafts settle linear against steps.

**C13. Chain runs each walk every AH ladder from the bottom.** Upheld 3/3.

- **Where**: service.py:1318-1368 (`skill_chain`), engine.py:1834-1863 (`_share_books` shares only within one tree),
  2169-2196.
- **Scenario**: Leatherworking from 1, bought run after run: 1,450.7g against the cards' 1,200.8g of AH spend
  (+20.8%), 175.5g of it Rugged Leather for Runic Leather Headband. Blacksmithing +99.1g (4.3%); Enchanting +4.6g;
  Engineering +5.1g; Tailoring +1.3g.
- **Correction**: the 187 listed Rugged Leather cost only 11.5g in all; most of the gap is the cheap units counted
  again and then re-priced at the single 10,000c listing used for every short unit. So sharing alone won't settle the
  size; short-unit pricing (C10) matters as much.
- **Fix**: carry `taken: dict[item, units]` from run to run in `skill_chain` and price each stretch past it, as
  `_share_books` does; for the DP, re-price the chosen legs with shared ladders and re-solve if a leg rises by more
  than some percentage.

### 4.3 Confirmed: low

**C14. Coming back to a recipe pays its pattern again, counts an unknown pattern twice and restarts spares.**
Upheld 3/3.

- **Where**: engine.py:419-427, 527-552 (per leg); 468-470 (documented approximation); 379-393 (`spent_by` per leg);
  396-401.
- **Evidence**: synthetic (`revisit_demo.py`): A 0→40 costs 3,232c where A–B–A with the pattern once costs 2,913c;
  with an unknown pattern the DP never returns (a second unknown outweighs any copper), overpaying 5,830c when B pays.
  On dev data a learn-once re-solve over 8 professions × 5 start skills found **no changed plan**, so the plan bias is
  latent. **The milestones are live wrong**: Cooking trainer from 150 shows 33,423c at 225 with Spider Sausage's
  4,000c fee counted twice (~12% high), while the chain cards zero the repeat (`_learned_on_the_way`). Leatherworking
  (Dark Leather Gloves 900c) and Engineering (Flying Tiger Goggles 360c) likewise, negligibly.
- **Fix**: count learn and unknown once per distinct recipe in `spent_by` and `ClimbPlan.cost`; optionally solve,
  mark used patterns bought, re-solve and keep the cheaper (2–3 solves at ~100 ms).

**C15. Legs are cut into runs front to back, and a run ending at grey is labelled `rival`.** Upheld 3/3.

- **Where**: engine.py:577-587 (`_pieces`, greedy), 595-602 (`_run` checks a following piece before grey).
- **Scenario**: Lean Venison 110→190 (211 crafts) becomes 110→181 (98), 181→189 (73) and 189→190 (40 crafts, p80
  64), the last labelled `rival` naming Lean Wolf Steak, so the card says "at which point Lean Wolf Steak becomes a
  cheaper option" though Lean Venison is simply grey at 190. 10 of 14 runs that end at their recipe's grey across the
  recommended climbs from 1 are mislabelled (Elixir of Minor Force 1→15, Robe of Power 198→205, Black Mageweave
  Gloves 215→225). `trivial` can only appear on a climb's last run.
- **Note**: the split doesn't cause the 40 crafts (C1 does); it isolates them on their own card, buying spares for
  that piece's own p80.
- **Fix**: check `stop >= trivial_high` before `rival` and keep the next recipe as extra information; optionally
  split legs into roughly equal pieces, or say "the last N points take ~M crafts".

**C16. A run's output is always sold, even when a later run needs it.** Upheld 2/3.

- **Where**: engine.py:2077-2079, 460-504 (no inventory), service.py:1318-1368.
- **Scenario**: Leatherworking default: 45 Cured Light Hide vendored at 110c, then 70 crafted again (~540c, 45
  crafts); Alchemy trainer: 80 Fire Oil vendored at 12c, then 26 bought at 60c (1,248c); Engineering trainer: 114 Gold
  Power Cores vendored at 250c, then 24 crafted again (~2,100c); First Aid: Linen Bandages vendored and bought back at
  the same price.
- **Dissent**: 0.005–0.18% of a climb; no plan choice changes. Agreed: mostly a step-list oddity ("keep N for run X").
- **Fix**: post-process the chain: keep units a later run needs, credit the earlier run at the later run's unit cost
  and drop them from the later shopping list; optionally re-solve once.

**C17. Learning a sub-recipe is never charged when a candidate's tree crafts it.** Upheld 2/3.

- **Where**: engine.py:2184-2188 (only the root's `learn_costs`); service.py:1420-1438.
- **Scenario**: Alchemy's Elixir of Greater Defense crafts 18 Stonescale Oil (13,500c fee); Blacksmithing's thorium
  axes use Dense Grinding Stone (10,000c), Mithril Spurs and Ebon Shiv Solid Grinding Stone (2,250c); Leatherworking
  uses Heavy Leather (1,800c), Cured Medium Hide (650c), Medium Leather (500c) and Fine Leather Gloves (200c pattern).
  Uncharged: Alchemy 13,725c, Blacksmithing 12,340c. It can flip a buy-or-craft choice (Medium Leather: crafting saves
  482c and skips a 500c fee).
- **Dissent**: ≤ 2% of a climb (Alchemy), < 0.3% elsewhere; no recommended sequence changes once charged once per
  climb.
- **Fix**: charge each unknown sub-recipe's learn cost once per climb, the first time it is used; at least list it as
  a learn step.

**C18. `NumSkillUps = 0` is ignored.** Upheld 3/3.

- **Where**: ingest.py:745-766; engine.py:204-225.
- **Evidence**: 20 rows in 1.60.1.70245's SkillLineAbility have real thresholds and `NumSkillUps = 0` (not 31 as
  first claimed): 12 rockets, 4 bomb satchels, 3 blacksmith hammers and Occult Poison I. Every other recipe with
  thresholds (~2,512) is 1, as is every TBC row. (An earlier note that "NumSkillUps is 1 for every recipe" was wrong.)
  All 19 profession ones are bop with unknown pattern prices, so they only bite an uploaded character who has learned
  one: a known Purple Rocket Cluster is planned 224→240 (23 crafts at 4,733c) and from 225 is the Recommended first
  option. That 0 means "no point" is inferred (TrinityCore multiplies the gain by it), not tested in game.
- **Fix**: ingest the column; treat 0 as no skill-up (keep for the gold list).

**C19. The card's "per skill point" divides by a fixed-n expectation, not by the run's points.** Upheld 3/3.

- **Where**: engine.py:2071 (`expected_skill_ups(recipe, crafter, n)` with n = round(E[crafts to stop])), 228-261;
  SkillWorkspace.tsx:66; lib/skill.ts:10-11.
- **Scenario**: Lean Venison 189→190 and Lean Wolf Steak 204→205 (40 crafts) show `skill_ups` 0.637 (exactly
  1 − (1 − 1/40)⁴⁰), so the card's figure is 1.57× the truth (+7,664c a point shown against 4,880c). Over 111 runs,
  5 are off by more than 10%; runs crossing into yellow are ~3% the other way. Display only: options sort by
  `climb_cost`.
- **Fix**: for results with a `stop_skill`, `skill_ups = stop_skill − start_skill` and scale `skill_ups_bonus`; keep
  the expectation for gold sessions and typed counts.

**C20. Climbs assume every profession rank is trained on time, ignoring the character level it needs.** Upheld 3/3.

- **Where**: api.py:1633-1646 (`_trained_up`), service.py:1299-1316, versions.py:33-37.
- **Scenario**: a level-15 Tailor at 150/150 is ranked Small Silk Pack 150→170 and on, though Expert needs level 20.
  The Train reminders state the level, but the plan and its costs assume it. Rank fees aren't counted. The hypothetical
  climber is unaffected; no current crafting character is stuck at such a cap. Forever's level gates are vanilla's,
  unverified.
- **Fix**: raise `max_rank` only to the highest rank whose level the character has, or say "the climb stops at 150
  until level 20".

**C21. Recommended can show a higher cost to 300 than the option beside it.** Upheld 2/3.

- **Where**: SkillWorkspace.tsx:71-74, 962 (sorted and badged by `climb_cost`, which includes spares and grind);
  api.py:1831-1840 (milestones from `spent_by`, without them).
- **Scenario**: Engineering at 200, default: Recommended Plans: Inlaid Mithril Cylinder (climb_cost 2,094,052, 300
  milestone 1,900,843c) beside Iron Grenade (2,096,719, 1,898,369c): 24.7g more on screen. One inversion at the
  Recommended position in 40 cases (also between later columns: Enchanting 200, Blacksmithing 75).
- **Dissent**: by design (the risk terms choose plans; no shown price includes them). Agreed it's a presentation
  issue: the badge rests on a number the page never shows.
- **Fix**: say what Recommended weighs, or order and badge by the shown milestone with `climb_cost` as tiebreak. Goes
  away if the objective's effort term becomes something the page can show (section 5).

**C22. When every option crosses an unknown-price pattern, no option is badged Recommended.** Upheld 2/3.

- **Where**: api.py:1948, SkillWorkspace.tsx:71-74, 962.
- **Scenario**: default sources: Tailoring at 1, 75, 150, 200, 250 and Leatherworking at 1, 75, 150, 200: every option
  has `climb_cost` None and "+1 pattern of unknown price", so no badge, while the page still offers "Reset to
  recommended" and crafts the server's best.
- **Fix**: send the copper and `climb_unknown` separately and badge the first whenever the server's (unknown, cost)
  order puts it first.

### 4.4 Contested (not confirmed)

**X1. No disenchanting skill check: an enchanter of any skill is credited with disenchanting any item level.**
Upheld by 1 of 3; **two verifiers refuted it with client data, and on Forever it is very likely not a bug.**

- The claim: `_disenchanter` (engine.py:1628-1640) checks only `enchanting > 0`, and vanilla requires skill by item
  level (ilvl 61+ needs 225), so an Enchanting-1 alt "can't" disenchant most of a climb's output (Tailoring: 11 of 15
  disenchant legs).
- The refutation: Forever's ItemDisenchantLoot at the pinned build has `SkillRequired` 0 on all 54 rows (Classic Era
  1.15.9: 0 on all 50); only TBC Anniversary 2.5.6 fills in 1–300. vmangos' disenchant check never compares skill with
  item level. Forever guides say anything can be disenchanted from Enchanting 1.
- Leftover: it would matter only if the skill climb were served for the `tbc` version; if fixed, read `SkillRequired`
  from ItemDisenchantLoot rather than hard-coding a table.

### 4.5 Found but not put to the verifiers

**U1. Recipe cooldowns are not modelled.** Reported independently by four of the research reports.

- Nothing reads SpellCooldowns. In 1.60.1.70245: Transmute: Mithril to Truesilver and Iron to Gold 1 h
  (3,600,000 ms); elemental transmutes 23 h; Arcanite 47 h; Mooncloth 95 h; Refined Scale of Onyxia 2 h; 16 profession
  spells in all.
- The Alchemy default climb plans Transmute: Mithril to Truesilver 225→275, 94.8 crafts (~95 hours of cooldown), and
  every objective fix tested pushes more of Alchemy onto it (R3 without the exclusion moves 255→278 onto the
  transmute). FWC has the same bug (109 Iron to Gold). CheapSkill and WowCraft leave cooldown recipes out.
- **Fix**: ingest RecoveryTime and CategoryRecoveryTime into `recipes` (a revision); leave recipes with a cooldown of
  an hour or more out of climbs (or cap their crafts and annotate "~N h of cooldowns"). Prerequisite for section 5.
  (The addon's own cooldown tracker, `Data/Cooldowns/CooldownData.lua`, already lists Transmute: Mithril to
  Truesilver among the transmutes.)

**U2. Switching recipes is free** (no per-run fixed cost: orange legs have no variance, so no spares, and no grind).
The DP takes one-craft detours to save a few copper (Alchemy: Minor Defense 15→20, Mana Well 20→21 to save 7c,
Minor Defense 21→83). Each costs a shopping trip in game and a full card on screen. Skillwright charges 3 points'
worth; a 1-point switch cost took 1-point legs to 0 for +0.4% gold in one test. Add only after the tail fix: on its
own it lengthens tails (+104g, tails unchanged).

**U3. Required tools are not modelled.** Enchanting's rods and Engineering's spanners are prerequisites for the
recipes that need them; CLAUDE.md says rods aren't modelled. WowCraft and Skillwright insert them as steps.

**U4. Units beyond the listing cost the dearest listed price, flat, with no supply limit.** Plans buy what doesn't
exist (Blacksmithing trainer: 3,421 Thorium Bars short against 16 listed; Detect Demon: 171 Gromsblood against 1).
`short` is flagged per node but not on steps or cards. Ties into C10 and C13.

**U5. Prices are static over the climb**, and the plan from 1 assumes today's listings for materials bought weeks
later. Fine for the next run, optimistic for the tail. Not worth modelling; worth saying.

**U6. Smaller assumptions** (from the reference report, not tested): limited-stock vendor patterns are priced as
always in stock; an unknown trainer fee counts as 0; `climb_options` solves in the first city group's market only;
and a chain run opened with `chain_at` after prices moved can point at another recipe (the 404 "That run is no
longer part of the climb").

### 4.6 Suspicions checked and set aside

- **The search misses cheaper routes.** No: every FWC route was feasible for our DP and none beat it on our objective.
  Where FWC was cheaper in copper (Cooking trainer, Engineering trainer), our grind paid for fewer crafts on purpose.
- **Doubling back is blocked.** No: the DP revisits where it pays. A learn-once re-solve over 32–40 real climbs found
  no hidden cheaper revisiting plan (C14 is about milestones and a latent bias).
- **Re-planning mid-run (an MDP or closed-loop policy) would help.** No: per-level costs add up and skill-ups are
  memoryless, so the plan already is the optimal policy. Re-planning each leg from its midpoint switched recipe in 0
  of 157 legs. Plan from 1 restricted to 150+ equals the plan from 150 in 13 of 16 climbs (the rest differ by a
  boundary point).
- **A whole-climb risk measure** (CVaR, quantile or mean + λ·sd of the total). No: the total's standard deviation is
  3–15% of its mean, while one run's last 3 points have a 95th percentile ~2× their mean. The risk users feel is per
  point.
- **Raising `GRIND`, a per-point 90% quantile, `SPARE_Z` as a risk slider, or the profit clamp at 0 on its own.**
  All tested worse (section 5.3).
- **Buying for p50 and re-checking instead of p80.** Halves leftovers but adds ~0.6 AH trips per heavy run. Keep
  p80 and the user-set target.
- **Disenchant skill requirement on Forever** (X1). Forever's client data has none.
- **"NumSkillUps is always 1"** (an early note). Wrong: see C18.

---

## 5. The last-point problem

### 5.1 Why it happens

Sorting every "heavy" point (over 5 expected crafts, p < 20%) in the 16 climbs from skill 1:

| Kind | What it means | Default sources | Trainer only |
|---|---|---:|---:|
| **Profit** | the run earns per craft, and another recipe gives that point in fewer crafts | 337 crafts | 70 |
| **Copper** | the run is cheap, and another recipe gives the point in fewer crafts at a higher price | 68 | 50 |
| **Forced** | nothing else the climber may craft gives that point in fewer crafts | **0** | **596** |
| Heavy-point crafts / all crafts | | 405 / 3,581 (11%) | 717 / 3,989 (18%) |

So **with the UI's default sources every obscene tail is a choice the objective makes**, 83% of them from profitable
crafts (C1); with trainer-only sources most are forced by the data (C3, C7, C8).

The four causes:

1. **Profit outruns the grind (C1).** A point at chance p earns |c|/p, linear in 1/p; the grind is quadratic but
   scaled by `cheapest`, not by |c|. The DP stays while `0.1·s·(k − 1)² < |c|·k` with k = 1/p, i.e. until
   k ≈ 10·|c|/s.
2. **The scale is relative and collapses (C5).** A cheap craft against a dear alternative tolerates more crafts the
   dearer the alternative: with the alternative R× the price per point, the DP stays while `1/p < 1 + √(10(R − 1))`
   (R = 2: 4.2 crafts; 10: 10.5; 27: 17.1; 100: 32.5). Rough Grinding Stone (5c a craft) against Runed Copper Belt
   (17.8s, R ≈ 27) gets 13.3 crafts on its last point. In copper that is honest (12 more crafts to save 17s); only
   time makes it bad, and nothing in the objective counts time.
3. **Forced walls (C3, C7, C8).** The DP must reach `end`; where one recipe covers the levels, its tail is paid
   whatever the objective says.
4. **Cooldowns (U1)**: a transmute's 6.7-craft point is cheap in copper and costs hours.

The other side of the same constant: at high skill `cheapest` is gold, so the grind overpays. The price the
baseline pays per avoided craft ranges from 3c (Cooking default) through 5.3s (Engineering default) and 29s
(Blacksmithing default) to 1.7g (Enchanting trainer from 150) and 5.6g (Blacksmithing trainer from 150), a factor
of about 20,000. Over the 16 trainer-only climbs it costs 791g of real copper to save 1,264 crafts.

### 5.2 A decomposed example: Lean Venison, Cooking from 1, default sources

The climb runs Strider Stew 50→110, then **Lean Venison 110→190: 211 expected crafts**, shown as runs 110→181 (98
crafts), 181→189 (73) and **189→190 (40 crafts, p80 64)**, then Lean Wolf Steak 190→205 (133 crafts, again 40 on
204→205). Lean Venison costs ~38c to make and vendors for ~190c: −151.5c a craft at every skill, grey or not.

The point 189→190 (yellow 150, grey 190, so p = 1/40):

| Term in the DP | Value |
|---|---:|
| Crafts: 40 × −151.5c | −6,059c |
| Spares: `max(cost, 0)` × … | 0 |
| Grind: 0.1 × `cheapest[189]` (4.00c, set by Tasty Lion Steak / Spotted Yellowtail) × 39² | +608c |
| **Leg cost for this point** | **−5,450c** |

Alternatives at 189: Rockscale Cod gives the point in 1 craft for 8c; Lean Wolf Steak at p = 0.4 (2.5 crafts,
−1.6s a point); Tasty Lion Steak in 1 craft at −4c (unknown pattern). Leaving Lean Venison one point early and
switching to Lean Wolf Steak changes the objective by **+5,286c** (+5,894 crafts' copper, −608 grind) for −37.5
crafts, so the DP stays. Its implied threshold, 10 × 152 / 4 ≈ 380 crafts a point, is never reached: the run goes to
grey.

The stop-early frontier (one banned-recipe solve, crafts saved / profit given up): stop at 189 → −38 crafts, +59s;
at 187 → −66, +1g 6s; at 186 → −74, +1g 20s; at 183 → −89, +1g 47s. A flat ~1.6s per craft saved, about the run's
own profit per craft: "keep crafting for the money, or move on".

Under the fixes in 5.4 Cooking's route becomes Crispy Lizard Tail, Goblin Deviled Clams and Jungle Stew (R3: worst
point 6.7 crafts, 627 → 349 crafts for +3.9g) or Goblin Deviled Clams, Jungle Stew and Clam Chowder (R5: worst point
1.4, 627 → 306 crafts for +5.3g).

### 5.3 Approaches evaluated

Two independent experiments re-implemented `engine.Climb` with pluggable terms; each reproduced all 32 engine plans
(8 professions × {trainer, default} × start {1, 150}) leg for leg at the same cost, and scored every rule on the true
outcome (real copper, expected crafts), never on its own objective. Default climbs, 16, baseline 8,574g and 5,464
crafts, worst point 40, 834 crafts on points under 25%:

| Rule | Δ gold | Δ crafts | Worst point | Verdict |
|---|---:|---:|---:|---|
| `GRIND` × 3 / × 10 | +179g / +413g | −374 / −744 | 40 / 20 | No: overpays at high skill, tails stay |
| Fix the scale only (known price, positive cost) | +71g | −15 | 40 | Right in principle, not a fix |
| Profit clamped to 0 (SkillUp Forever) | +5g | **+567** | **70** | Worse alone: zeroes the scale, ties go to the longest run |
| **Net cost ≥ 10% of gross (Skillwright's floor)** | **+8.8g** | **−618** | 13.3 | The cheapest single fix; leaves Rough Grinding Stone |
| +20c / +100c a craft | +1.2g / +10.1g | −223 / −857 | 40 / 10 | 20c too weak against 152c profit |
| Time value 20g/h, `GRIND` 0 | −49g | −13.5% | 8 avoidable points > 5 crafts | Dominates baseline; trainer-only tails remain |
| Chance floor 10% where another recipe covers (WowCraft) | +3.5g | −313 | 10 | Many 5–10-craft points left |
| Chance floor 25% (Skillwright) | n/a* | −797 | 5 | *Takes on unknown-price patterns (4 → 6); a cliff |
| A point ≤ 4× the best chance's crafts | +15g | −746 | 5 | Pays any price to avoid a point |
| 90% quantile per point (SkillUp Forever) | +242g | +68 | 40 | No: scales every green point alike, doubles profit |
| Switch cost 3× cheapest point (Skillwright) | +104g | −75 | 40 | Separate concern (U2); lengthens tails alone |
| `SPARE_Z` 0.84 → 2.33 | up to +5% | ≤ −5% | worse in 2/16 | No: profitable runs pay no spares |
| **R3**: floor 10% + λ per craft + `λ·(1/p − 1)²`, λ = 50c | **−64.5g** | **−768** | 10 | Recommended shape (one experiment) |
| **R5**: floor 10% + 10g/h × entropic effort, η = 0.2, `GRIND` 0 | **−48g** | **−17%** (−942) | 0 avoidable points > 5 crafts | Recommended shape (other experiment) |

Trainer-only climbs: R3 −858g (+207 crafts, worst point stays forced at 60); R5 −67g, −0.7 h, −3% crafts, 0 avoidable
points over 5 crafts; `GRIND` × 10 +1,276g.

Product-side approaches (no plan change), from the same data:

- **A tail line and a crafts range on the run.** Points over 3 crafts each carry 26–100% of a heavy run's crafts and
  73–100% of its variance; after the card's "~N times", 43% of heavy runs haven't reached the stop and need ~23 more
  crafts on average (45 for Lean Venison, Lean Wolf Steak, Spider Sausage). "Craft until 190 (~211 times)" hides a
  p10–p90 of 158–275. `reach_chances` already holds the range.
- **"Stop early and switch"** with crafts saved and gold paid, from one banned-recipe solve per heavy run (9 of 103
  runs): −38 to −89 crafts per run at 0.45–1.6s per craft saved (5.2). Doesn't touch forced tails.
- **A forced-wall note** ("nothing else you can learn gives a point between 200 and 204; the next trainer recipes
  unlock at 205; allowing patterns avoids this"). All 596 forced heavy-point crafts are trainer-only.
- **A user "max crafts per point"** (soft K, multi-pass): K = 5 costs little (Cooking from −2.3g / 627 crafts /
  worst 40 to +1.3g / 398 / 5) but pushes Blacksmithing and Leatherworking onto unknown-price patterns at K = 3, which look like savings and
  aren't.
- **"Try K crafts, then switch"**: never better than switching at once under the linear formula (memoryless); worth
  saying only as a hedge until the curve is measured.

### 5.4 Recommendation

**Prerequisites**: C2 (0/0 thresholds), U1 (cooldowns) and ideally C3 (learn levels). Every objective fix leans harder
on whatever is cheap and orange, which today means First Aid Kit to 300 and the 1-hour transmutes.

**Step 1, ship alone: the 10% floor.** In `Market._candidates` and `service.later_recipes`, give `Candidate` a
`gross` (`one.cost / n`) and price the DP at `max(cost, 0.1 × gross)`; `spent_by`, milestones and cards keep the real
copper. About 10 lines; +9–10g over 32 climbs, −6% crafts, avoidable points over 10 crafts 16 → 2. Cooking 40 → 6.7,
Enchanting 17.5 → 2.7, First Aid 10 → 3.5, Linen Bag 8.8 → 5. Rough Grinding Stone keeps its 13.3.

**Step 2: replace the grind with an absolute per-craft effort term.** Both experiments converged on the same
structure and both forms beat today's plans on gold *and* crafts:

```
R3: point cost = (max(cost, 0.1·gross) + λ) / p  +  λ·(1/p − 1)²      λ = 50c a craft
R5: point cost =  max(cost, 0.1·gross) / p       +  κ_r·g_η(p)        κ_r = time_value × seconds per craft
                                                                       (10g/h by default), η = 0.2
    g_η(p) = ln(p·e^η / (1 − (1 − p)·e^η)) / η    ≈ 1/p + (η/2)·Var; infinite below p = 1 − e^(−η) ≈ 18%,
                                                   so a finite stand-in (e.g. 10⁴ + 1/p) where nothing else covers
Both: spares on the floored cost and the pattern as now; GRIND and cheapest removed.
```

- **What they share**: one exchange rate between copper and crafts everywhere (so the 20,000× swing goes), a convex
  penalty that makes a 1-in-k point cost roughly λ·k², and no `cheapest` (so C5 goes). Both are additive per level,
  so the DP, the prefix sums and the solve time stay as they are, and the plan stays time-consistent.
- **R3** is simpler: a flat λ, no dependence on cast times. Results hold for any λ from 20c to 200c (default climbs on
  the clean set, without cooldown transmutes and 0/0 recipes: −49g to −71g, −644 to −1,210 crafts). Worst point 10.
- **R5** prices time: κ per recipe from `TimeConfig.time_value` × cast time (Forever's casts run 3 s for potions to
  45–60 s for gear), so it also prefers short casts. Its pole is a smooth chance floor at ~18% that never trades
  against unknown-price patterns (unlike a hard floor). Zero avoidable points over 5 crafts on both source variants;
  dominates the baseline (less gold and less time) at every time value from 5 to 20g/h with η = 0.2 (at 2g/h the
  trainer-only climbs take 0.14 h longer). Needs `cast_time_ms` checked in game for
  one long cast.
- **Which**: on the same 16 default climbs (same baseline, each from its own solver that reproduces the engine) R3
  saves more gold (−64.5g against −48g) and R5 more crafts (−942 against −768), and only R5 leaves no avoidable point
  over 5 crafts (R3's worst point is 10). The trainer-only figures (R3 −858g, R5 −67g) come from different case sets
  (R3's leaves out the cooldown transmutes and 0/0 recipes) and can't be compared. Run both solvers (still in the
  scratchpad) on one clean set before choosing; absent that, R5's shape if cast times check out in game, R3
  otherwise. An exponential-utility variant tested at θ = 0.02 (a ~2% pole) was too weak; the entropic form needs η
  around 0.2.
- **Where**: `engine.Candidate` (`gross`, `seconds`), `Market._candidates` (engine.py:2169-2196),
  `service.later_recipes` (service.py:1129-1242), `Climb.__init__` (engine.py:460-510: swap `cheapest`/`grind` for
  the effort prefix sums), `_Usable.cost` and `_cheapest_from` (same arithmetic; the test comparing them,
  test_engine.py:988, must be updated), `SkillRuns` gains the knob, which must go into `Market._climb`'s key and
  `ClimbKey`. About 30–40 lines plus tests.
- **The knob in the UI**: a three-way "Cheapest / Balanced / Fewest crafts" in the skill Options (0 / ~10 / ~50 g/h,
  or λ 0 / 50c / 2s), default Balanced. Stored under the skill search's keys.

**Step 3: product, independent of the model.** The tail line and crafts range, the forced-wall note (C7) and, once
C2 and C15 are fixed, the "stop early and switch" line (all three in 5.3's product list, and items 3, 5 and 11 of
section 6.2). The model change makes tails rare; these handle the ones that remain
and the forced ones it can't touch.

**Step 4: measure the curve (C12).** If Forever uses vmangos-style steps, no point costs more than 4 crafts and most
of this problem disappears; both R3 and R5 still behave sensibly there.

**Don't**: raise `GRIND`; use a median or gross grind scale (expensive, still relative); a whole-climb risk measure;
a per-point quantile; an MDP; a hard 25% floor whose fallback ignores the unknown-pattern count.

---

## 6. UIs

### 6.1 Each project

**Alt Army.** One centred card says what to craft now, how far, and why it stops ("Craft until 83 skill (~81 times),
at which point Rage Potion becomes a cheaper option"), with the chain of later runs under it, side-by-side options,
and a run panel with an executable per-character checklist, flow chart, market depth and Copy steps.

| Pros | Cons |
|---|---|
| Answers "what now?" in one sentence, with why it stops | The whole climb is hard to see: 2 cards, then +3 per *Show more* (~4 clicks to 300) |
| Knows the character (skill, recipes, talents, alts, reputation); works without data (hypothetical climber) | Four cost figures, none labelled: per point on cards, milestones, the chain's sum, the hidden `climb_cost` (67.6g, 57.4g and 56.3g for Alchemy from 1) |
| Honest about chance: "~", a buy-for count to a chosen confidence, a floored %, odds for any typed count | No total for a run; gross spend is only in the Market header, net only in the sell step |
| Executable checklist: map pins, where to learn (vendors, quests, drops), per-step source and exit overrides | No orange/yellow/green/grey anywhere, though `learn_skill`, `trivial_low`, `trivial_high` reach the browser |
| Deep market view; train reminders where ranks fall due; frozen price version with Refresh | *Show me other options* is a swap icon with only a tooltip for a label; only the first run can be swapped |
| Shareable, readable URLs | Large craft counts appear without comment; 1-craft detours take a full card |
| | No climb-wide shopping list, pattern list or AH export; wording nits ("train" for a bought pattern, "a Alchemy trainer", the colon in "What to craft next:") |

**foreverwowcraft.com.** One static page per plan: KPI tiles, an Auctionator import, a Sequence table (skill range,
recipe, difficulty as four coloured numbers, crafts, profit), a per-5-skill chunk table, recipes to buy, shopping,
intermediates, sell afterwards, a skill-range slider.

| Pros | Cons |
|---|---|
| Whole 1–300 route on one page with totals and a shopping list | Nine dense tables, no hierarchy |
| **Auctionator shopping-list import** for the route or any sub-range ("Copied 16 items…" toast) | No character, skill or known recipes; the route is cut, not re-planned |
| Difficulty as four coloured numbers, as players know them | Flat odds make it look 1.3–2.2× cheaper; no uncertainty |
| Explicit gaps, "only N listed", stated methodology, localised names | Buys 184 from 1 listed at a silent premium; "net" means different things per mode; ads |

**WowCraft.** A left sidebar of route rows (colour bar, "N×", icon, name, cost, "start → end" pill, sticky total),
inline alternatives per row, a main panel with a chance-vs-skill chart and range selector, a two-thumb skill slider.

| Pros | Cons |
|---|---|
| Compact route list with a total; alternatives one click away | No character input; one global price mode |
| Chance-vs-skill chart with average attempts | Difficulty colours shifted a band and read at the wrong skill; step 1 at skills the player can't use |
| Instant recompute; honest caveat notes; shareable URLs | Materials list is bare quantities; no "why it stops"; blur on every drag; ads |

**Addons** (in game): SkillUp Forever shows "62% · 45s" (chance · cost per point) on each row and a threshold bar
with "you are here", keeps an Auctionator list in sync and lists what would carry a stopped route on. Skillwright
has a make-now card with have/need and flags estimated learn ranks. Cole lists **pattern opportunities** ("buying X
would save ~Y over these skills") and states how the plan was chosen. LazyProf lets any step's alternative be
**pinned**, re-planning the rest. CraftWise says whether each % was measured or from the formula.

### 6.2 Elements to incorporate, ranked

By value to a player per unit of effort; none changes the layout. Effort is front-end time: **XS** under an hour,
**S** half a day to a day, **M** two to three days, **L** more. "No server" means `/api/rank` already returns
everything needed (chain runs are full `RankResult`s with steps, cost, revenue, crafts and `crafts_p80`, and
`chain_length` already goes to 40).

| # | Element | From | Where | Effort |
|---|---|---|---|---|
| 1 | **Label the options button**: "Other options (3)" instead of the swap icon | WowCraft, LazyProf | SkillWorkspace.tsx ~line 1006 | XS |
| 2 | **Wording fixes**: "You'll need to learn this recipe (cost included)" or branch on `learn[id].source`; "an" before vowels (cap card, learn step); drop the colon in "What to craft next:"; "net for the run" in skill mode | — | SkillWorkspace.tsx `TRAIN_NOTE`, StepList, RecipeFlow | XS |
| 3 | **Tail line and crafts range** on the card and panel: "The last 4 points take ~83 of these ~211 crafts"; "~211 times, usually 158–275"; optionally "100% → 25% per craft". The range needs no server; a `point_crafts` (or `last_point_crafts`) field makes the tail line exact | SkillUp Forever, WowCraft | lib/skill.ts (`craftsRange`, `tailNote`), `OptionCard`/`RunText`; `SkillRun`, api.py ~425 | S |
| 4 | **Difficulty marks**: `10 · 55 · 75 · 95` in orange/yellow/green/grey under the recipe, or a thin band strip with the run bracketed. Colour each mark at its own threshold; drop the first when `learn_skill` is 0 | FWC, SkillUp Forever | new `DifficultyMarks` beside SkillBar.tsx, `OptionCard`, run panel; colours in lib/wow.ts | S |
| 5 | **Say when the climb ends below the cap or a stretch is forced** (C7, C8): "No other recipe gives a point from 200 to 204; the next trainer recipes unlock at 205"; "This climb ends at 245 with these sources; allowing normal recipes reaches 300" | FWC gaps, SkillUp Forever | a `forced`/`climb_end` field on the result; `runText` in lib/skill.ts; milestones | S |
| 6 | **Copy for Auctionator** beside Copy steps: the run's AH buys as `Name^"Item";;;;;;;;;;;;;qty^…` at the *Crafts to buy for* quantity; toast "In Auctionator: Shopping → Import". Check the field layout against Auctionator first; English names only | FWC | `auctionatorList` in lib/skill.ts; SkillWorkspace.tsx ~line 887; free for the gold row's `StepsPanel` | S |
| 7 | **One labelled total per run**: "This run: buy for 3s 84c, sell back 1s 20c, net −2s 64c · ~20 crafts (24 to be 80% sure)"; a hover on milestones saying what they count | FWC KPI tiles | run panel, `Milestones` in SkillWorkspace.tsx | S |
| 8 | **Margin on the side-by-side options**: "+3s over the whole climb" or "About the same as Recommended" within ~1%; fix the badge per C9, C21, C22 | Cole, CraftRoute | options grid and `byClimbCost` in SkillWorkspace.tsx | XS–S |
| 9 | **"How we plan"** popover: linear chance (unverified on Forever), cheapest climb with spares, scan age, what isn't counted yet (sub-craft points, cooldowns). Gives the unreachable `ResultsTable` footnote a home | FWC, Cole, WowCraft, CraftWise | `SkillOptions` in AimSearch.tsx | XS |
| 10 | **Whole-climb table**, collapsible under the chain: skill · recipe · crafts (~exp / 80% sure) · learn · net, a totals row ("13 runs · ~408 crafts (442 to be 80% sure) · 8 recipes (2g 97s) · −56g"), rows opening the existing panel; fetched with `chain_length=40` only when opened; 1-craft detours as muted rows | FWC Sequence, WowCraft, Calg's | new ClimbTable.tsx in the `Chain` component | M |
| 11 | **Stop early and switch** on heavy runs: "Stop at 186 and switch to Lean Wolf Steak: ~74 fewer crafts, 1g 20s less profit". Server: one banned-recipe solve per run whose last point takes over 5 crafts; "switch" re-plans through `chain_from`/`climb_without`. Only after C2 and C15 are fixed | — (our own) | `Climb.stop_options`, `RankResult.stop_early`, run text and panel | 1½–2 days |
| 12 | **"I'm at skill X now"** on the open run: remaining crafts and odds client-side once 3 ships; for the hypothetical climber an "I'm at 83 now" button that moves the path to `hypotheticalPath(…, stop_skill)` | FWC slider, WowCraft inputs | lib/skill.ts `remaining`, run panel; lib/profitRoute.ts | XS–S |
| 13 | **"Only N listed"** on AH buy steps when the plan buys past the book (needs `short` on `StepOut`) | FWC | StepList.tsx, `stepsText`, api.py step conversion | S + small server |
| 14 | **"Used later" tag**: "Keep 40 Fire Oil: used by Elixir of Fire Power at 163", by matching outputs against later runs' reagents; "Keep" in the steps needs the server (C16) | FWC, wowtbc.gg, Cole | ClimbTable.tsx and chain cards | S (tag) |
| 15 | **Climb shopping list to a chosen skill**, AH and vendor grouped, patterns listed apart, with Copy for Auctionator. Use per-run p80 and say so (p80s don't add); net out intermediates | FWC, Skillwright, Calg's, SkillUp Forever | `climbShopping` in lib/skill.ts, ClimbTable.tsx | M |
| 16 | **Pattern opportunities**: "Recipe: X (AH 1g) would save ~3g over 175–199", including C11's unpriced world drops | Cole, FWC | new server field from banned/with-pattern climbs (api.py, service.py); ClimbTable.tsx | M–L |
| 17 | **Pin or swap a later run**: "Other recipes for 83–107" in a chain run's panel, re-planning the rest | WowCraft, LazyProf | run panel, `Chain`; server bans at a deeper run | L |

Considered and left out: FWC's front-page cost-to-300 per profession (a full climb per profession per house);
WowCraft's chance chart (items 3 and 4 carry it in a line; a `reach_chances` sparkline later if asked for); a
"Minimum skill-up chance" option (an algorithm decision, section 5; if added, in `SkillOptions` with a note when the
plan had to go below it); localised item names.

### 6.3 Things to avoid

1. **Making plans look cheaper by changing the odds** (FWC's flat bands). If a cap or floor ever ships, label it as a
   choice and keep the real expected crafts visible.
2. **Buying far past the book in silence** (FWC's 184 from 1 listed). Put `short` on the step (item 13).
3. **Colour bands read at the wrong skill or shifted by one** (WowCraft). Test against a known recipe.
4. **Crafts shown at skills the player can't use yet** (WowCraft's step 1).
5. **Totals that disagree with the planner** (WowCraft's double-charged patterns; our four figures). Any new total
   must say what it counts, and one number should be *the* total.
6. **A bare materials list** without prices, sources or netting.
7. **One global mode for the whole route** (Cost/Vendor/DE/AH, Profit/Skill-up, Fast/Cheap). Our per-item exits and
   per-step overrides are better; a single effort knob (section 5) is a weight, not a mode.
8. **Walls of tables** (FWC's nine). One collapsible table under the cards.
9. **Cutting the route instead of re-planning it** (FWC's slider, discounts after planning).
10. **Animation on every input** (WowCraft's blur while dragging).
11. **Blunt exclusions shown as facts** (hidden greens, a silent 25% floor, retired recipes). Say what was filtered.
12. **Clamping profit to zero in the display.** Keep earned points green; any floor is for choosing only.
13. **Ads and a column of chrome.** The clean single-column workspace is worth keeping.

---

## 7. Sources and how the data was gathered

**Data.**

- Our side: the dev database `site/data/altarmy.sqlite` (read-only copies), market stamp (build, loads, newest
  accepted snapshot, price_version) `1.60.1.70245, 7, 11, 19`, auction house 4 (Classic Beta PvE, Horde). Newest scans
  2026-10-07 23:42:31, 18:10:22 and 14:39:26 server time. Climbs were rebuilt in process exactly as `/api/rank` builds
  them (hypothetical climber, `Learning('train', look_ahead=0)`, skill exits, `runs`, `sort=skill`, default
  `TimeModel`), and checked against the live dev API (`/api/rank?…&chain_length=40&top=4`): every run's stop skill
  matched in all 32 cases.
- FWC: house `classicbetapve--horde`, `scan_newest` 2026-10-07 22:54 UTC, plans generated 23:41 UTC, build
  1.60.1.70009, 883 price ladders.
- Client data: wago.tools SpellCooldowns, SkillLineAbility (1.60.1.70245 against 2.5.6.69795) and ItemDisenchantLoot
  (Forever, Classic Era 1.15.9, TBC 2.5.6), cached under the monorepo's `.cache/wago/`.
- The user's own SavedVariables (a copy) for live recipe colours and known recipes.

**URLs.**

- https://foreverwowcraft.com/?realm=Classic+Beta+PvE&faction=Horde&profession=alchemy&recipes=trainer, and its data:
  `/data/houses.json`, `/data/classicbetapve--horde/manifest.json`, `/data/classicbetapve--horde/plans/<key>.json`
  (`+` URL-encoded as `%2B`).
- https://github.com/MalteNilsson/WoWCraft (5bb334b) and https://wowcraft.io/alchemy.
- https://github.com/cjber/skillup-forever, https://github.com/vBaustad/Skillwright,
  https://github.com/staticcole/cole-profession-planner, https://github.com/kaldown/LazyProf,
  https://github.com/velibkolay/CraftWise; CurseForge pages for Calg's Profession Planner, CheapSkill, WoWfessions and
  CraftRoute; wowtbc.gg's Forever guide; https://github.com/azerothcore/azerothcore-wotlk/pull/27219 (the linear
  formula); https://warcraft.wiki.gg/wiki/Skill_up.
- https://wago.tools/db2/SpellCooldowns/csv?build=1.60.1.70245.

**Scripts and outputs (temporary).** Everything is in this session's scratchpad,
`C:/Users/Nick/AppData/Local/Temp/claude/c--Users-Nick-programming-altarmy-site/22248071-95e5-4cad-821e-92fc4311b1e5/scratchpad/`,
**which is temporary and will be cleared**; copy anything worth keeping. The main pieces:

| Folder | What |
|---|---|
| `reports/` | The eleven source reports this document is built from (`ours_algorithm`, `ours_runs_detail`, `fwc`, `wowcraft`, `others`, `ours_ui`, `compare`, `grind_model`, `grind_product`, `grind_empirical`, `ui_compare`) |
| `ours/` | `run_climbs.py` and `api_check.py` (the 32 climbs and their API check), `probe.py`, `qty2.py`, `revisit.py`, `cheapest.py`, per-climb JSON |
| `fwc/` | FWC's page, `houses.json`, manifest and every plan file; `segs.py`, `recount.py`, `recost.py`, `greedy.py` |
| `compare/` | `compare.py` (both routes under four models), `aggregate.py`, `bands25.txt`, `align.py`, `short.py`, `vendor_diff.py`, `prices.py`, `out/` |
| `wowcraft/`, `wcrun/` | WowCraft's clone and its planner run under Node (`run.mjs`, `fix.mjs`) |
| `others/` | Clones of the other addons; `exp/cheapest_probe.py` |
| `grind_model/` | `solver.py` (the climb with pluggable terms; `verify.py`: 32/32 identical), `capture.py`, `cases.json`, sweeps, `recs.txt`, `grid*.txt`, `consist.py` |
| `grind_emp/` | A second independent solver and case set (`dump.py`, `solver.py`, `keys/*.pkl`), `cases.txt`, `experiments.txt`, `final_clean.txt`, `lam_clean.txt`, `fwc_tails.txt`, `wc_tails.txt` |
| `grind_product/` | `exp.py`, `results.json`, `stop_rule.py`, `shop_sim.py`, `risk.py` |
| `bugs/` | Per-finding repro scripts: `dp-structure/` (walls, options, revisits, sub-craft points, kept products, ladders), `cost-model/` (s1–s11), `probability/` (live colours, thresholds, NumSkillUps, per-point), `plan-vs-display/` |
| `verify/` | The adversarial verifiers' reproduction scripts and outputs, one folder per finding |
| `ui/` | Live `/api/rank` payloads used for the UI review |

Caveats that apply throughout: one scan of one realm; a hypothetical climber without talents; prices held static
over the climb; the linear skill-up formula, which is unverified on Forever (C12); learn levels that are wrong for
many trainer recipes (C3).
