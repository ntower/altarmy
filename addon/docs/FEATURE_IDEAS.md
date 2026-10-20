# AltArmy TBC — Feature Ideas

Possible new features for `AltArmy_TBC`, compared against popular WoW alt/account-management addons. WoW: Forever is the addon's main focus; TBC Anniversary stays supported but is not what drives the roadmap. Status is relative to the current codebase. Shipped details live in [FEATURES.md](FEATURES.md) and [tabs/](tabs/).

## Comparison baseline

Compared against:

- [BagSync](https://www.curseforge.com/wow/addons/bagsync)
- [SavedInstances](https://www.curseforge.com/wow/addons/saved_instances)
- [Altoholic](https://www.wowinterface.com/downloads/info8533-Altoholic.html)
- [OneWoW Alt Tracker](https://www.curseforge.com/wow/addons/onewow-alt-tracker)

## Status

| Idea | Status | Notes |
|---|---|---|
| Leveling timeline analytics | **Shipped** | [tabs/graphs.md](tabs/graphs.md) |
| Lockouts planner | **Partial** | [tabs/cooldowns.md](tabs/cooldowns.md) Raids view lists active lockouts; no “available now” list |
| Mail expiration alerts | **Partial** | Login chat within 5 days; the Inventory tab's Mail view shows a character's waiting items, gold and expiry ([tabs/inventory.md](tabs/inventory.md)); no cross-character attention UI |
| Per-character inventory view | **Shipped** | [tabs/inventory.md](tabs/inventory.md): bags, bank and mail drawn like the stock windows |
| Global tooltip integration | **Not started** | Search already breaks down location *inside* the addon |
| Daily/weekly task tracker | **Not started** | |
| Gold and economy history | **Not started** | Research: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md) |
| Recipe gap intelligence | **Not started** | Recipe search covers *known* recipes only |
| Craft queue and material planner | **Not started** | Cooldown stockpile mailing is the related foundation |
| Character notes and tags | **Partial** | Bank-alt flag only ([FEATURES.md](FEATURES.md)) |
| Actionable suggestion panel | **Not started** | Separate chat alerts exist (cooldowns, mail, gear upgrades) |
| Data freshness indicators | **Partial** | Missing-data `!` and Last Online; no per-domain scan age |
| Guild data sharing | **Shipped** | [tabs/guild.md](tabs/guild.md) |
| Guild recipes from profession links | **Shipped** (WoW Forever; in-game checks pending) | [GUILD_PROFESSION_LINKS_IDEA.md](GUILD_PROFESSION_LINKS_IDEA.md) |
| Export for the Alt Army website | **Shipped** | [tabs/options.md](tabs/options.md#export-for-the-alt-army-website); characters only (no auction prices) |

---

## Highest-value additions

### 1) Lockouts planner — partial

**Shipped:** Cooldowns → Raids view — per-character heroic/raid lockouts, reset timers, sort by instance/character/time.

**Remaining:** “Available now” / “can run tonight” for characters who are *not* locked.

### 2) Daily/weekly task tracker — not started

- Checklist per character for repeatable chores; reset-aware status; optional custom tasks.
- (`SearchTasks.lua` is the Search work queue, not a chore tracker.)

### 3) Global tooltip integration — not started

- On item tooltips *anywhere in-game*, show totals across characters with location breakdown.
- Search already shows Bags / Bank / Mail / equipped / keyring inside the addon. No external `GameTooltip` hook.

### 4) Mail expiration and pending mailbox alerts — partial

**Shipped:** login chat within 5 days; mail gold in Summary; mail items in Search; one character's inbox (items, gold, expiry) in the Inventory tab.

**Remaining:** a cross-character mailbox-attention UI, opt-in / threshold controls.

### 5) Gold and economy history — not started

- Account and per-character gold deltas over time; optional source grouping.
- Related today: Summary gold; `/altarmy networth`. Design notes: [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md).

### 6) Recipe gap intelligence — not started

- Unknown but learnable recipes; “who can learn now” vs skill gate.
- Related: known-recipe Search + difficulty for learned recipes. The built-in recipe data (`Data/Recipes`) already lists every recipe with its required skill and sources, so the remaining work is the UI.

## Differentiator ideas

### Craft queue and material planner — not started

- Queue crafts across alts; missing mats and best source character.
- Related: Cooldowns stockpile send / send-all (cooldown reagents only).

### Character notes and tags — partial

**Shipped:** bank-alt flag with auto-detect, Summary icon, hide-from-Summary.

**Remaining:** freeform notes and general tags (transmute alt, raid-ready, etc.).

### Actionable suggestion panel — not started

- Unify cooldown-ready, lockouts resetting, mail expiring, rested XP into one “next actions” surface.

### Data freshness indicators — partial

**Shipped:** missing-data `!`, Last Online, Guild “shared data outdated.”

**Remaining:** per-domain last-scan display and “stale even though data exists” warnings.

## Suggested remaining work order

### Phase 1

- Lockouts “available now.”
- Mail attention UI.
- Global tooltip integration.

### Phase 2

- Daily/weekly task tracker.
- Gold and economy history.
- Per-domain last-scan freshness.

### Phase 3

- Recipe gap intelligence.
- Craft queue / material planner.
- Actionable suggestion panel.
- General character notes and tags.

## Notes for scoping

- WoW: Forever comes first: prefer what helps there (lockouts, cooldowns, mail, gold all do). TBC Anniversary stays supported, so a Forever-only feature should degrade quietly on TBC (as the Economy tab does) and nothing shared should break there.
- Keep data collection event-driven.
- Add opt-in controls for noisy reminders.
