# AltArmy TBC — Architecture

High-level structure of the addon: purpose, UI, data layer, and SavedVariables. For the shipped feature catalog see [FEATURES.md](FEATURES.md). For data-layer details see [`AltArmy_TBC/Data/DESIGN.md`](../AltArmy_TBC/Data/DESIGN.md).

## Purpose

AltArmy TBC is an **account-wide alt management** addon for WoW: Forever (the main focus) and TBC Anniversary (the TOC's two interfaces). It:

- Scans and persists character data while you play (event-driven, internal DataStore).
- Shows cross-character dashboards (summary, gear, reputation, cooldowns/lockouts, search, graphs).
- Optionally shares character cards and recipes with guildmates (Guild tab + Search merge).
- Links your own other WoW accounts (`Data/Link/`): their characters are received over Battle.net and kept apart in `AltArmyTBC_LinkedData`, read by the tabs as our own but never shared, exported or uploaded.
- Writes what the Alt Army website reads: the profit export (`Data/ProfitExport.lua`) and the auction house's order book (`Data/Auctions/`); on WoW: Forever the Economy tab costs Waylaid Crates and Craftsman's Writs.

It is **not** an external DataStore consumer. Persistence lives inside the addon under `AltArmy.DataStore`.

## Layout on disk

| Path | Role |
|------|------|
| `AltArmy_TBC/Core.lua` | Main frame shell, toolbar, side tabs wiring, Search mode overlay |
| `AltArmy_TBC/Tabs/` | Per-tab UI |
| `AltArmy_TBC/UI/` | Theme, minimap, options, shared widgets, onboarding dialogs |
| `AltArmy_TBC/Data/` | DataStore, aggregation (`Characters/`), search, guild share, linked accounts (`Link/`), gear, cooldowns, economy, inventory, auction scans (`Auctions/`), recipe data (`Recipes/`), integrations with other addons, the profit export |
| `AltArmy_TBC/Libs/` | Bundled libraries (AceComm, AceSerializer, LibDBIcon, LibDeflate, etc.) |
| `AltArmy_TBC/Media/`, `Textures/` | The addon's own art (icons, textures, quest reward previews) |
| `AltArmy_TBC/Reputation*.lua` | Three pure Reputation grid helpers (faction filter, sort, column windowing) loaded at the root |

Visual language: [`UI/Theme.lua`](../AltArmy_TBC/UI/Theme.lua) — see [UI_DESIGN.md](UI_DESIGN.md).

## Main window

- Native Blizzard window: `PortraitFrameTemplate`, 670 × 484 (the height of Forever's CharacterFrame). It has a close button, and it can be dragged by the title bar and closed with Escape.
- **Font size**: the General options' Look and Feel "Font size" slider (9 to 18) resizes the addon's own font objects (`Theme.FONTS`, made from `Theme.BASE_FONTS`' Blizzard fonts; `Theme.SetFontSize`, `AltArmyTBC_Options.fontSize`), applied at login by the Options panel's PLAYER_LOGIN handler; hidden and not applied while `panel.FONT_SIZE_OPTION` is off in `UI/Options.lua` (text wraps at some sizes until the tabs lay out for them); see docs/UI_DESIGN.md "Typography".
- **Window scale**: the General options' Look and Feel "Window Scale" slider (50% to 200%) is `main:SetScale` on the whole window (`AltArmy.SetWindowScale`, `AltArmy.GetWindowScale`; `AltArmyTBC_Options.windowScale`, 1 = 100%), applied when the window opens before its size; the screen clamps below divide the screen by it (`ScreenSize`). The dialogs (Export, Link account, Bank alt: children of UIParent), the alert toasts and the Options pages are not scaled.
- **Resizing**: a bottom-right grip changes the window's width and height (`StartSizing("BOTTOMRIGHT")`; the stock size is the minimum and the room from the window's top-left corner to the screen's edges the maximum, never wider than 1.5 times the stock width (`MAX_FRAME_WIDTH`) or taller than twice the stock height (`MAX_FRAME_HEIGHT`), set as each drag starts, so a mouse leaving the game window can't drag the grip out of reach; `AltArmyTBC_Options.window` keeps a larger one, clamped to the screen and those maximums when applied on open, and with nothing valid saved opening the window puts it at the stock size; `/altarmy resetsize` restores the stock size). While the window is open, a game window that shrinks under it (`DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED`, or a bigger Window Scale) shrinks it to what the screen holds, never under the stock size, and moves it fully on screen (`FitToScreen`); the saved size is kept, so a bigger game window gets it back on the next open. The content area is anchored to the window's edges and every tab lays itself out again for the width, live during a drag: the stock layouts are kept and named columns take what a wider window adds (`Data/ColumnFit.lua`, pure: `Fit` shares the extra among flex columns by ratio, with optional caps, never shrinking below stock; each tab's doc says which columns grow). Grids of character columns (Gear, Reputation, Currency) keep their column width and show more columns. The toolbar's search slot grows by half of what the window adds, up to 520. A tab's settings side panel keeps one width (`Theme.SETTINGS_PANEL_WIDTH`, 258; `Theme.SettingsPanelLeft`): the content left of it takes the extra. Content in the bottom-right corner keeps `AltArmy.WINDOW_GRIP_INSET` clear of the grip. `AltArmy.OnWindowResized(fn)` registers a listener called once a resize has ended (the grip let go, `resetsize`, the saved size applied), never during the drag (the Graphs tab redraws its plot on every size change instead, live, as a trial; this is its fallback).
- The portrait circle and title (`Alt Army - <Tab>`) follow the active tab.
- Open with `/altarmy` or `/alta`, or the minimap button. `/alta <tab> [view]` opens a tab, or one of its sub-views:
  `summary`, `economy [currency|crates|writs|supply]`, `gear [grid|upgrade]`, `inventory [bags|bank|mail]`,
  `reputation`, `cooldowns [crafting|dungeons]`, `graphs`, `guild` (`UI/MainTabs.lua`'s `slash` and `views`,
  `ParseSlash`; a plural word also works without its "s"). A tab or view that isn't there (Economy off Forever,
  Guild without sharing, Supply Chain behind its flag) does nothing (`AltArmy.OpenMainTabView` in `Core.lua`).
  Every side tab's and sub-view tab's tooltip shows its command in gray (`UI/TabTooltip.lua`).
- **Toolbar row** under the title bar: a search slot and the active tab's settings button. The slot holds the global item/recipe search box (`SearchBoxTemplate`) on Summary (`MainTabs` `headerSearch`) and in Search mode. Reputation (faction filter), Guild (character/profession search), Inventory (item search; its character picker and layout dropdown are a controls row at the top left of the body) and Economy's Currency view (its filter) put their own box in the same slot via `AltArmy.PlaceInToolbarSearchSlot`; Economy's Waylaid Crates and Craftsman's Writs views put a Filter dropdown at the slot's right end via `AltArmy.PlaceInToolbarRight`. Gear, Cooldowns and Graphs show no search. A native **Filter** dropdown (`Theme.CreateFilterDropdown`, entries from `Data/Search/SearchFilterMenu.lua`) appears left of the global search box once it has text; the box has a fixed width.
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
| **Cooldowns** | **Crafting** cooldowns (with stockpile mailing from a bank alt) + **Raids** lockout sub-view; its settings button opens a side panel with the tab's own realm filter and which cooldowns to show and alert on (`AltArmyTBC_Options.cooldowns`; on Forever its own cooldown categories) |
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
| `AltArmyTBC_Options` | Global options (bank alts, the Currency view's character filter (`economy.currency.filter`); the old global realm filter `characterScope` / `realmFilter`, read only to seed each tab's first filter; the Cooldowns tab's settings and filter (`cooldowns`); the auction house scan (`auctionAutoScan`, `auctionScanMode`, `auctionPreferFullScan`); Economy view and sort (`economy`); Inventory layouts and mail sort (`inventory`); window size, scale and font size (`window`, `windowScale`, `fontSize`); minimap button (`minimap`, `showMinimapButton`); `levelHistory`, `autoReadRecipes`, the dismissed prompts, `debug`, etc.) |
| `AltArmyTBC_GearSettings` | Gear tab settings (with its character filter, `filter`) |
| `AltArmyTBC_ReputationSettings` | Reputation tab settings (with its character filter, `filter`) |
| `AltArmyTBC_SummarySettings` | Summary tab settings (its character filter `filter`, whose realm filter the tabs without one use; `groupByRealmFaction`) |
| `AltArmyTBC_SearchSettings` | Search settings |
| `AltArmyTBC_GraphSettings` | Graphs tab settings |
| `AltArmyTBC_GuildData` | Received guild-share payloads |
| `AltArmyTBC_SharingSettings` | Own guild-share preferences (opt-in) |
| `AltArmyTBC_AuctionScans` | Log of Auctionator's price updates and their faction, for the website |
| `AltArmyTBC_AuctionBook` | The auction house's order book from full scans, for the website (`scans`), plus the newest summary scan per realm and faction (`summaries`, in-game only) |
| `AltArmyTBC_LinkedData` | Linked accounts: each link's state and the characters received from it, in the DataStore's own shape (`Data/Link/LinkStore.lua`); kept apart from `AltArmyTBC_Data` so nothing that reads our own characters sees a linked one |

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
- [WOW_FOREVER_COMPAT.md](WOW_FOREVER_COMPAT.md) — whether each optional addon integration has a WoW: Forever build
- [DEV_DUMPS.md](DEV_DUMPS.md) — debugging with dev dumps
- [README.md](README.md) — full docs index
