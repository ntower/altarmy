# In-game checks

What the site assumes until someone checks it in game, and where the answer goes. The beta ends around
21–22 Oct 2026, so the first list must be done before then; the second waits for launch day (4 Nov 2026).

## Before the beta ends

- [ ] **Disenchant rows.** Disenchant about 20 items whose item level and required level fall in different
  brackets (Hillman's Shoulders among them). Which level picks the row? Fix `data/forever/disenchant.csv` if
  needed (its green weapons at item level 21–30 give Greater Magic Essence, as Forever's own drop data has it,
  not vanilla's astral essences: worth a look too) and set `disenchant_verified` in `versions.py` once it matches.
- [ ] **Disenchant skill.** Can a skill-1 enchanter disenchant a high item-level green? DB2's ItemDisenchantLoot
  says no skill is needed (`docs/SKILL_UP_RESEARCH.md`); vanilla asked for one by item level.
- [ ] **Wands.** What a vendor pays for Lesser and Greater Magic Wand on the current build (DB2 has moved
  between 1c and 2s).
- [ ] **Transmutes.** The cooldowns of Iron to Gold and Mithril to Truesilver (DB2 says 1 hour), and whether
  transmutes share a timer.
- [ ] **Auction house.** The deposit for 2, 8 and 24 hours, and whether a cancel forfeits it
  (`GameVersion.auction_hours`; the deposit model is Phase 1).
- [ ] **Smelts and stations.** Where the Forever-only smelts are learned; whether the Molten Foundry and
  the tanning rack are deployable (`timing.DEPLOYABLE`).
- [ ] **Essences.** That lesser and greater essences convert 3:1 both ways.

## On launch day

- [ ] **The feed.** `python scripts/probe_blizzard_api.py --namespace <Forever's> --list --sample 5 --save
  .cache/probe` (find the namespace first: try the Classic ones and any new one). Record the outcome in
  `docs/HOSTED_PLAN.md`.
- [ ] **The snapshot's shape.** `buyout` per stack or `unit_price`, whether a stack can be bought in part,
  whether `bid` is the starting or the current bid, and whether `Last-Modified` is sent.
- [ ] **Time-left buckets.** From the first hours of snapshots, the bounds of SHORT, MEDIUM, LONG and
  VERY_LONG (`GameVersion.time_left_buckets`, Classic's until then).
- [ ] **Realm names.** Add the launch realms' names to `RealmSpec.aliases` in `versions.py` and deploy, so
  uploads land on the fixed houses.
- [ ] **The neutral house.** That it is left out (it is not polled).
- [ ] Then build the fetcher (the plan's "Later" step), with an OK for its cloud resources.
