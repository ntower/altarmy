# AltArmy Refactoring Opportunities

A code-review snapshot of remaining refactoring opportunities across the addon's
~41,600 lines of source (the `AltArmy_TBC/Data`, `AltArmy_TBC/Tabs`, and
`AltArmy_TBC/UI` layers; excluding bundled `Libs/` and the `busted/` test framework).

The codebase is generally well-organized: `Theme.lua` provides a styling layer, logic is
partly separated from UI (e.g. `GraphLogic.lua`), and modules are cohesive. Shared text/
sort/identity helpers, the safe-wave UI factories (horizontal scrollbar, vertical scroll
viewport, theme checkbox) are already extracted; Search rows are virtualized by Blizzard's `WowScrollBoxList`. The main
remaining opportunities are **cross-cutting UI duplication** and a few **oversized
files/functions** that mix concerns.

> Line numbers are approximate and reflect the codebase as of July 2026.

## Suggested order of attack

1. **Shared UI factories (remaining)** — scrollable grid + sort settings panel shell.
2. **Theme constants + tokens** — centralize magic numbers; adopt or delete unused color helpers.
3. **File splits** — `TabCooldowns`, `DataStore` deferred timers, `Options` sub-tabs.
4. **Cleanup** — remove dead code; dedupe bag/bank constants. Optionally move `TabSummary`'s faux-scroll row pool to `WowScrollBoxList`.

---

## 1. Repeated UI scaffolding (high impact, medium risk)

Horizontal scrollbar, vertical scroll viewport, and theme checkbox factories are already in
[`UI/Theme.lua`](../AltArmy_TBC/UI/Theme.lua). `TabSearch` rows are virtualized by Blizzard's
`WowScrollBoxList`; `TabSummary` still uses its own faux-scroll offset model. Remaining structural duplication:

| Item | Notes | Suggested extraction |
|------|-------|----------------------|
| **Scrollable character grid** | Still duplicated | `Theme.CreateScrollableGrid(opts)` |
| **Character sort settings panel** | Thin shell still duplicated; heavy list UI already shared | `AltArmy.UI.CharacterSortSettingsPanel(frame, opts)` |

**Detail:**

- **Scrollable character grid:** `TabGear` (~1269–1831) and `TabReputation` (~238–584) are two
  skins of the same two-axis scroll grid (vertical scroll child, fixed header row, horizontal
  scroll synced to header, scrollbars, fades, wheel handlers). Gear also embeds score-provider /
  item-check chrome in that span; Reputation has faction-filter / corner-control differences.
  Horizontal scrollbar chrome is already shared via `Theme.CreateHorizontalScrollBar`.
- **Character sort settings panel:** `TabGear` (~3724–3833) and `TabReputation` (~1039–1153)
  still duplicate the panel shell, pin/self-first checkbox wiring, and toggle/`OnSizeChanged`.
  The controls are already shared via `Theme.CreateSettingsPanelContent` and
  `AltArmy.CreateCharacterFilterControls` — remaining work is a thin wrapper over saved-var key +
  refresh callback.

---

## 2. Oversized files / functions to split

| File | Lines | Notes |
|------|------:|-------|
| `TabGear.lua` | 3,833 | Dominated by grid + compare/item-check UI. Shrinks once §1 grid/settings helpers land; also a Lua 5.1 locals-pressure risk. |
| `TabSearch.lua` | 2,039 | Rows virtualized by `WowScrollBoxList` (element list from `Tabs/SearchListModel.lua`); further shrink via settings-panel / dead-anchor cleanup. |
| `Options.lua` | 1,752 | Mixes defaults, tab strip, sub-tabs, char list, slash commands. `CooldownOptions` already demonstrates the cleaner host-panel split to mirror. |
| `TabCooldowns.lua` | 1,633 | Mixes list UI with live bag/mail attach logic. `TryAdvanceAttachSeq` (~1161–1285) plus `RunSendStockpile` (~1300–1449) and related mail/stockpile flow could move to a testable non-UI module. |
| `TabGraph.lua` | 1,608 | `RebuildGraph` (~1198+) and compare-selector panel could move to their own modules. |
| `DataStoreProfessions.lua` | 1,452 | Owns scanning, reagent capture, cooldown persistence, action-bar scans. Split into scan/reagents/cooldown submodules. |
| `TabReputation.lua` | 1,153 | Shrinks once §1 grid/settings helpers land. |
| `DataStoreLevelHistory.lua` | 1,025 | Mixes runtime recording with one-time Questie/RXP/NIT imports + migration. |
| `DataStore.lua` | 707 | Single `OnEvent` handles ~30 event branches inline; **8 near-identical deferred-timer frames** (~253–287: bag/equipment/late/tradeSkill/craft/reagent-retry×2/cooldownAfterCast) → one `RunAfterDelay(delay, fn)` helper. |

---

## 3. Inconsistency / correctness-adjacent items

- **Theme tokens defined but unused:** `SetGroupHeaderColor`, `ApplyDropdownBackground`,
  deprecated `StyleScrollThumb` (production uses `StyleScrollKnob` via `SetupScrollBar`).
  Meanwhile muted gray is still hardcoded as `0.5,0.5,0.5` in places such as `CooldownOptions`
  and `Core`.
  → Add `Theme.COLORS.muted` + `SetMutedColor` and adopt the existing helpers (or delete them).
- **Bag/bank constants redefined:** `SearchData` (~7–10) re-declares `BANK_CONTAINER`,
  `KEYRING_CONTAINER`, and bank bag id bounds already exported on `DS`.

---

## 4. Dead / unused code

- `GraphCore.CreateTooltipBase` (~488) — never called.
- `DataStoreContainers.ScanBagsAndLog` (~293) — duplicate of `ScanCurrentCharacterBags`,
  no production callers.
- `DataStoreCharacter.GetStoredRestXp` — only referenced by tests.
- `TabGear` left panel ("Who can use this?") gated behind `LEFT_PANEL_VISIBLE = false`.
- `LevelProgressData.WATCH_NAMES_LOWER` — all entries commented out, but still iterated.
- `TabSearch`/`TabSummary` build list widgets on `frame` then reparent to the scroll child —
  leftover migration artifact with dead initial anchors.

---

## 5. Magic numbers worth centralizing

Recurring across tabs and not in `Theme`: `PAD = 4`, `HORIZONTAL_SCROLL_BAR_HEIGHT = 20`,
`ROW_HEIGHT = 18/20`, `GRID_SPLIT_FRACTION = 0.6`, `MIN_SCROLL_CHILD_WIDTH = 400`, hint
width `520`.

In Data: `MAX_LOGOUT_SENTINEL = 5000000000` (triplicated), `28800` (rest bubble), `86400`
(seconds/day), `1.5` (rest cap multiplier), `0.10` (post-cast scan delay).

→ Promote to `Theme.*` and `DS.*` constants.
