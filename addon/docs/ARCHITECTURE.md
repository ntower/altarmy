# AltArmy TBC — Architecture

High-level structure of the addon: purpose, UI, data layer, and SavedVariables. For the shipped feature catalog see [FEATURES.md](FEATURES.md). For data-layer details see [`AltArmy_TBC/Data/DESIGN.md`](../AltArmy_TBC/Data/DESIGN.md).

## Purpose

AltArmy TBC is an **account-wide alt management** addon for TBC Classic. It:

- Scans and persists character data while you play (event-driven, internal DataStore).
- Shows cross-character dashboards (summary, gear, reputation, cooldowns/lockouts, search, graphs).
- Optionally shares character cards and recipes with guildmates (Guild tab + Search merge).

It is **not** an external DataStore consumer. Persistence lives inside the addon under `AltArmy.DataStore`.

## Layout on disk

| Path | Role |
|------|------|
| `AltArmy_TBC/Core.lua` | Main frame shell, toolbar, side tabs wiring, Search mode overlay |
| `AltArmy_TBC/Tabs/` | Per-tab UI |
| `AltArmy_TBC/UI/` | Theme, minimap, options, shared widgets, onboarding dialogs |
| `AltArmy_TBC/Data/` | DataStore, aggregation, search, guild share, gear/cooldown logic |
| `AltArmy_TBC/Libs/` | Bundled libraries (AceComm, LibDBIcon, etc.) |

Visual language: [`UI/Theme.lua`](../AltArmy_TBC/UI/Theme.lua) — see [UI_DESIGN.md](UI_DESIGN.md).

## Main window

- Native Blizzard window: `PortraitFrameTemplate`, 670 × 484 (the height of Forever's CharacterFrame). It has a close button, and it can be dragged by the title bar and closed with Escape.
- **Resizing is built but off** until every tab reflows: the Debug options' **Window resize** (`AltArmyTBC_Options.debug.windowResize`, also `/altarmy debug resize on|off`; `AltArmy.ApplyWindowResize` in `Core.lua`) turns it on, and then a bottom-right grip resizes the window (the stock size is the minimum; `AltArmyTBC_Options.window` keeps a larger one, clamped to the screen when applied; `/altarmy resetsize` restores the stock size). The content area is anchored to the window's edges: the Inventory views already reflow their grids and the Mail columns to the width, the other tabs keep their fixed layouts. Content in the bottom-right corner keeps `AltArmy.WINDOW_GRIP_INSET` clear of the grip. With it off there is no grip, the window is at its stock size (the saved size is kept, not applied), and `resetsize` is not a command.
- The portrait circle and title (`Alt Army - <Tab>`) follow the active tab.
- Open with `/altarmy` or `/alta`, or the minimap button. `/alta <tab> [view]` opens a tab, or one of its sub-views:
  `summary`, `economy [currency|crates|writs|supply]`, `gear [grid|upgrade]`, `inventory [bags|bank|mail]`,
  `reputation`, `cooldowns [crafting|dungeons]`, `graphs`, `guild` (`UI/MainTabs.lua`'s `slash` and `views`,
  `ParseSlash`; a plural word also works without its "s"). A tab or view that isn't there (Economy off Forever,
  Guild without sharing, Supply Chain behind its flag) does nothing (`AltArmy.OpenMainTabView` in `Core.lua`).
  Every side tab's and sub-view tab's tooltip shows its command in gray (`UI/TabTooltip.lua`).
- **Toolbar row** under the title bar: a search slot and the active tab's settings button. The slot holds the global item/recipe search box (`SearchBoxTemplate`) on Summary (`MainTabs` `headerSearch`) and in Search mode. Reputation (faction filter) and Guild (character/profession search) put their own box in the same slot via `AltArmy.PlaceInToolbarSearchSlot`; Inventory puts its character picker and layout dropdown at the slot's right end via `AltArmy.PlaceInToolbarRight`. Gear, Cooldowns and Graphs show no search. A native **Filter** dropdown (`Theme.CreateFilterDropdown`, entries from `Data/Search/SearchFilterMenu.lua`) appears left of the global search box once it has text; the box has a fixed width.
- Typing in the search box switches the window into **Search mode**, which has no side tab of its own.
- Template availability per client is detected in `UI/NativeUI.lua`, so missing templates fall back to the themed look.

### Side tabs

The tabs are icon flyouts on the right edge (`UI/SideTabs.lua`), anchored like CharacterFrame's mode tabs. Hovering one shows its name.
- Forever: `LargeSideTabButtonTemplate`.
- TBC Anniversary: classic spellbook skill-line tabs.

The order, icons, titles, and each tab's settings button action live in `UI/MainTabs.lua`.

| Tab | Notes |
|-----|--------|
| **Summary** | Character list overview |
| **Gear** | Equipment grid, item check, compare / upgrades |
| **Economy** | **Currency** grid (default), **Waylaid Crates** buy-or-craft costs per Merchant's Favor, **Craftsman's Writs** buy-or-craft costs (`Tabs/TabEconomyWrits.lua`) + **Supply Chain** (alt-army.com, off behind `AltArmy.FeatureFlags.economySupplyChain`) sub-views; WoW Forever only, hidden elsewhere by `Tabs/TabEconomy.lua` |
| **Inventory** | One character's **Bags**, **Bank** and **Mail** sub-views drawn like the stock windows (`Tabs/TabInventory.lua` shell; `TabInventoryBags.lua`, `TabInventoryMail.lua`; slots from `UI/ItemSlotButton.lua`) |
| **Reputation** | Faction × character matrix |
| **Cooldowns** | Crafting cooldowns + **Raids** lockout sub-view |
| **Graphs** | Level progress over time |
| **Guild** | Shown only when guild sharing is enabled and the realm has a guilded character |

Cross-character item lookup is **Search**; one character's containers are the **Inventory** tab.

## Data strategy

- **Internal DataStore** (`AltArmy.DataStore`) owns `AltArmyTBC_Data` and scans on WoW events (with delayed rescans where the client loads late).
- Higher layers (`SummaryData`, `Characters`, search/gear helpers) read through DataStore APIs; tabs should not write SavedVariables for character domains.
- Optional addons (Auctionator, TacoTip, GearScoreTBCClassic, RestedXP, Questie, NovaInstanceTracker, Zygor) enrich features when present; they are not required to load AltArmy.
- Recipe metadata (profession, required skill, difficulty, sources) is generated data shipped in `Data/Recipes/`, one table per client; see `AltArmy_TBC/Data/DESIGN.md` ("Recipe data").

See [DESIGN.md](../AltArmy_TBC/Data/DESIGN.md) and [DATA_VERSIONS.md](../AltArmy_TBC/Data/DATA_VERSIONS.md).

## SavedVariables

Declared in `AltArmy_TBC.toc`:

| Variable | Role |
|----------|------|
| `AltArmyTBC_Data` | Account-wide character / domain data |
| `AltArmyTBC_Options` | Global options (realm filter, bank alts, cooldowns, automatic auction house scan, Economy view and sort, Inventory layouts and mail sort (`inventory`), window size (`window`, used only with the Debug options' Window resize), debug, etc.) |
| `AltArmyTBC_GearSettings` | Gear tab settings |
| `AltArmyTBC_ReputationSettings` | Reputation tab settings |
| `AltArmyTBC_SummarySettings` | Summary tab settings |
| `AltArmyTBC_SearchSettings` | Search settings |
| `AltArmyTBC_GraphSettings` | Graphs tab settings |
| `AltArmyTBC_GuildData` | Received guild-share payloads |
| `AltArmyTBC_SharingSettings` | Own guild-share preferences (opt-in) |
| `AltArmyTBC_AuctionScans` | Log of Auctionator's price updates and their faction, for the website |
| `AltArmyTBC_AuctionBook` | The auction house's order book from full scans, for the website (`scans`), plus the newest summary scan per realm and faction (`summaries`, in-game only) |

## Blizzard's code and taint

Lua run from an addon is tainted, and so is every value it writes. When Blizzard's secure code reads such a value, its own execution becomes tainted and its next protected call fails with `ADDON_ACTION_BLOCKED`, often far from the write: the player's cast bar stopped showing (`PlayerCastingBarFrame:Show()`) because the talents frame, built from a tab-spacing variable the addon had tainted, handed the taint on. Rules that follow:

- Never assign a Blizzard global (`UISpecialFrames = UISpecialFrames or {}` taints the whole table; insert into it when it exists).
- Never call a Blizzard UI function that writes into a Blizzard frame on the player's behalf: no `ShowUIPanel` on Blizzard windows (`OwnRecipeRead` closes the trade skill with `C_TradeSkillUI.CloseTradeSkill` instead), no `SendMailFrame_*` (the Cooldowns stockpile send calls `SendMail`). Prefer the `C_*` and plain client APIs, `hooksecurefunc` and `HookScript`, which leave Blizzard's state alone.
- A Blizzard mixin method that writes shared state is off limits even on the addon's own frames: `TabSystemButtonMixin:SetSquareMode` rewrites a variable every tab system in the client reads, so `UI/TopTabs.lua` draws its square icon tabs itself.
- `/altarmy taint` shows which values on the cast bar's path are tainted and by which addon, every global and foreign table field this addon tainted, and anything in its SavedVariables the client cannot write (see [DEV_DUMPS.md](DEV_DUMPS.md)).

## Document map

- [FEATURES.md](FEATURES.md) — shipped features
- [FEATURE_IDEAS.md](FEATURE_IDEAS.md) — roadmap
- [tabs/](tabs/) — per-tab detail
- [README.md](README.md) — full docs index
