# AltArmy Refactoring Opportunities

A code-review snapshot of remaining refactoring opportunities across the addon's
~82,800 lines of source (the `AltArmy_TBC/Data`, `AltArmy_TBC/Tabs`, and
`AltArmy_TBC/UI` layers; excluding bundled `Libs/` and the `busted/` test framework).

The codebase is generally well-organized: `Theme.lua` provides a styling layer, logic is
partly separated from UI (e.g. `GraphLogic.lua`, `StockpilePlan.lua`, `SearchListModel.lua`), and
modules are cohesive. Shared text/sort/identity helpers and the safe-wave UI factories are already
extracted: `Theme.CreateHorizontalScrollBar`, `Theme.CreateVerticalScrollBinding`,
`Theme.CreateSettingsPanelContent`, `AltArmy.CreateCharacterFilterControls`
([`UI/CharacterFilterControls.lua`](../AltArmy_TBC/UI/CharacterFilterControls.lua)) and
`AltArmy.HorizontalListScroll` ([`UI/HorizontalListScroll.lua`](../AltArmy_TBC/UI/HorizontalListScroll.lua),
the Cooldowns lists' sideways scroll). Search rows are virtualized by Blizzard's `WowScrollBoxList`
and its settings panel lives in `Tabs/TabSearchSettings.lua`; the Options page has shed
`GearUpgradeOptions`, `LinkedAccountsOptions` and `InventoryOptions`. The main remaining
opportunities are **cross-cutting UI duplication** and a few **oversized files/functions** that mix
concerns, several of which have roughly doubled since this document was first written.

> Line numbers are approximate and reflect the codebase as of 2026-10-20.

## Suggested order of attack

1. **`TabCooldowns` mail/stockpile flow** → a testable non-UI module. The file has grown fastest and
   the attach engine is the riskiest code to keep in a tab.
2. **Shared UI factories (remaining)** — scrollable grid + sort settings panel shell.
3. **Theme constants + tokens** — centralize the tab constants (now in three styles); adopt or delete
   unused color helpers.
4. **File splits** — `DataStore` deferred timers, `DataStoreProfessions`, `Options` sub-tabs, `TabGraph`.
5. **Cleanup** — remove dead code; dedupe bag/bank and logout-sentinel constants. Optionally move
   `TabSummary`'s faux-scroll row pool to `WowScrollBoxList`.

---

## 1. Repeated UI scaffolding (high impact, medium risk)

Horizontal scrollbar, vertical scroll binding, settings-panel content and the character filter
controls are already shared. `TabSearch` rows are virtualized by `WowScrollBoxList`; `TabSummary`
still uses its own faux-scroll offset model (`rowPool`, ~654–842, offset read ~939). Remaining
structural duplication:

| Item | Notes | Suggested extraction |
|------|-------|----------------------|
| **Scrollable character grid** | Still duplicated | `Theme.CreateScrollableGrid(opts)` |
| **Character sort settings panel** | Thin shell still duplicated; the content and controls are already shared | `AltArmy.UI.CharacterSortSettingsPanel(frame, opts)` |

**Detail:**

- **Scrollable character grid:** `TabGear` (~1401–1860: vertical scroll child at 1439, horizontal
  bar at 1851) and `TabReputation` (~249–560: vertical scroll at 249, horizontal bar at 543) are two
  skins of the same two-axis scroll grid (vertical scroll child, fixed header row, horizontal scroll
  synced to header, scrollbars, fades, wheel handlers). Gear also embeds score-provider / item-check
  chrome in that span; Reputation has faction-filter / corner-control differences.
  `TabEconomyCurrency` carries a third copy of the same layout constants (its local `UI` table).
- **Character sort settings panel:** `TabGear` (~4059–4140) and `TabReputation` (~1109–1194) still
  duplicate the panel shell (`BackdropTemplate` + `Theme.ApplyBackdrop(..., "section")`), the
  `ApplySettingsPanelLayout` anchoring at `GRID_SPLIT_FRACTION`, the `Is…SettingsShown` /
  `Toggle…Settings` pair and the `OnSizeChanged` hook. Both already fill the panel with
  `Theme.CreateSettingsPanelContent` and `AltArmy.CreateCharacterFilterControls` — remaining work is
  a thin wrapper over saved-var key + refresh callback.

---

## 2. Oversized files / functions to split

| File | Lines | Notes |
|------|------:|-------|
| `Tabs/TabGear.lua` | 4,140 | Dominated by grid + compare/item-check UI. Shrinks once §1 grid/settings helpers land; also a Lua 5.1 locals-pressure risk. |
| `Tabs/TabCooldowns.lua` | 3,615 | Doubled since the Raids view split out (`TabCooldownsRaids.lua`, 367). Mixes list UI with the live mail attach engine: `TryAdvanceAttachSeq` (~2292–2416) and `RunSendStockpile` (~2431–2590, forward-declared at 500) and the stockpile row loop (~2714) could move to a non-UI module beside `Data/Cooldowns/StockpilePlan.lua`, which already holds the pure planning half. |
| `UI/Options.lua` | 2,721 | Mixes defaults, tab strip, sub-tabs, char list, debug hints and slash commands. `GearUpgradeOptions.lua` / `LinkedAccountsOptions.lua` show the sub-panel split to continue. |
| `Data/DataStore/DataStoreProfessions.lua` | 2,150 | Owns scanning, reagent capture, cooldown persistence, action-bar scans (`OwnRecipeRead.lua`, 903, is already apart). Split into scan/reagents/cooldown submodules. |
| `Tabs/TabGraph.lua` | 1,775 | `RebuildGraph` (assigned ~1300) and the compare-selector panel could move to their own modules; `GraphLogic.lua` (741) and `UI/GraphCore.lua` (590) already take the pure and drawing halves. |
| `Tabs/TabSearch.lua` | 1,616 | Rows virtualized by `WowScrollBoxList` (`Tabs/SearchListModel.lua`), settings in `TabSearchSettings.lua`; further shrink via dead-anchor cleanup (§4). |
| `Tabs/TabReputation.lua` | 1,194 | Shrinks once §1 grid/settings helpers land. |
| `Tabs/TabSummary.lua` | 1,183 | Faux-scroll row pool (§1). |
| `Data/DataStore/DataStore.lua` | 1,160 | Single `OnEvent` handles ~38 event branches inline; **8 near-identical deferred-timer frames** (~625–657: bag/equipment/late/tradeSkill/craft/reagent-retry×2/cooldownAfterCast, each re-armed with its own `OnUpdate` closure at ~720–931) → one `RunAfterDelay(delay, fn)` helper. |
| `Data/DataStore/DataStoreLevelHistory.lua` | 1,042 | Mixes runtime recording with one-time Questie/RXP/NIT imports (`ImportLevelHistoryFromQuestie` ~562, RXP backfill) + `MigratePhantomLevelHistoryImports` (~237). |

---

## 3. Inconsistency / correctness-adjacent items

- **Theme helpers defined but unused:** `Theme.SetGroupHeaderColor` (~1708),
  `Theme.ApplyDropdownBackground` (~2932) and deprecated `Theme.StyleScrollThumb` (~791; production
  uses `StyleScrollKnob` via `SetupScrollBar`) have no callers outside `Theme.lua`. Adopt or delete.
- **Muted grey hardcoded as `0.5, 0.5, 0.5`** in about twenty places (`TabCooldowns` mat counts,
  `TabEconomyCurrency` cells, `TabGear` fades and weights, `TabSummary` / `Options` class-colour
  fallbacks, "Click to configure" tooltip lines in `BankAlt`, `GuildTabData`, `TabEconomy*`, `TabGuild`).
  `Theme.COLORS.muted` exists but is a font-object token (`GameFontDisable`), not an RGB triple.
  → Add an RGB `Theme.COLORS.mutedRGB` (or `Theme.SetMutedColor(fontString)` / a tooltip helper) and adopt it.
- **Bag/bank constants redefined:** [`Data/Search/SearchData.lua`](../AltArmy_TBC/Data/Search/SearchData.lua)
  (~22–25) re-declares `BANK_CONTAINER`, `KEYRING_CONTAINER`, `MIN_BANK_BAG_ID` and `MAX_BANK_BAG_ID`,
  all of which `DataStoreContainers` already exports on `DS` (~83–87).

---

## 4. Dead / unused code

- `GraphCore.CreateTooltipBase` (`UI/GraphCore.lua` ~488) — never called.
- `DS:ScanBagsAndLog` (`DataStoreContainers.lua` ~494) — duplicate of `ScanCurrentCharacterBags`,
  no production callers.
- `DS:GetStoredRestXp` (`DataStoreCharacter.lua` ~168) — only referenced by tests.
- `TabGear` left panel ("Who can use this?") gated behind `LEFT_PANEL_VISIBLE = false` (~24, 1299, 1332).
- `LevelProgressData.WATCH_NAMES_LOWER` (~38) — all entries commented out, but still consulted (~218)
  and iterated (~315).
- `TabSearch` (~291) / `TabSummary` (~376–420) build list widgets on `frame` then reparent to the
  scroll child — leftover migration artifact with dead initial anchors.

---

## 5. Magic numbers worth centralizing

Layout constants now appear in three styles: bare `local`s (`TabGear`, `TabReputation`,
`TabCooldowns`, `TabCooldownsRaids`), a per-tab `local UI = {}` table (`TabEconomy`,
`TabEconomyCurrency`, `TabEconomySupplyChain`, `TabEconomyWrits`), and `HorizontalListScroll.BAR_HEIGHT`.
Recurring and not in `Theme`: `PAD = 4`, `HORIZONTAL_SCROLL_BAR_HEIGHT = 20` (also
`HorizontalListScroll.BAR_HEIGHT`), `ROW_HEIGHT = 20`, `GRID_SPLIT_FRACTION = 0.6` (`TabCooldowns`
~3423 spells it out as "the other tabs' GRID_SPLIT_FRACTION"), `MIN_SCROLL_CHILD_WIDTH = 400`, hint
width `520` (`Options.lua` ×7, `GearUpgradeOptions`).

In Data: `MAX_LOGOUT_SENTINEL = 5000000000` (triplicated: `Characters.lua`, `SummaryData.lua`,
`DataStoreCharacter.lua`), `86400` (seconds/day: `SummaryData`, `CooldownData`, `DataStoreMail`),
`1.5` (rest cap multiplier, twice in `DataStoreCharacter`), `0.10` (post-cast scan delay, twice in
`DataStore`). The rest bubble is already `DS.REST_BUBBLE_SECONDS`.

→ Promote to `Theme.*` and `DS.*` constants.
