# AltArmy TBC — Features

Shipped features in the current codebase. Per-tab detail: [tabs/](tabs/). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Roadmap: [FEATURE_IDEAS.md](FEATURE_IDEAS.md).

## What the addon does

AltArmy TBC is an account-wide alt management addon for WoW: Forever (the main focus) and TBC Anniversary that:

- Collects and persists character data automatically while you play.
- Presents cross-character information in tabbed dashboards.
- Supports item and recipe search across characters, with recipe skill, difficulty and source filters from built-in recipe data (optional guildmate recipes).
- Shows what each Waylaid Crate costs per point of Merchant's Favor, filled from the auction house or crafted by your characters, and what each Craftsman's Writ's order costs to buy or to craft with your characters (WoW Forever). A Supply Chain view explaining alt-army.com's crafting planner is built but off behind `AltArmy.FeatureFlags.economySupplyChain`.
- Tracks profession cooldown readiness (on WoW Forever its shared transmute cooldown, Mooncloth, the Salt Shaker, Comprehension's Study and the Legacy talent Dedicated Study), stockpile mailing, and raid/heroic lockouts.
- Graphs leveling progress over calendar and played time.
- Optionally shares character cards and recipes with guildmates.
- Provides configurable filters, sorting, pin/hide, bank-alt flags, and alerts.
- Keeps each character's data under its unique character ID, shown with its full name. WoW Forever characters that share a first name ("Frell Blast", "Frell Ofelements") stay separate. A paid name change keeps the character's data, pins, hides and bank-alt flag.

## UI design system

- Native Blizzard look on both WoW Forever and TBC Anniversary. AltArmy uses Blizzard's own templates and atlases for panels, buttons, scrollbars, checkboxes, dropdowns, inputs and list highlights, so Forever's reskin (and reskin addons) apply automatically.
- Everything goes through `AltArmy_TBC/UI/Theme.lua`, with capability detection in `UI/NativeUI.lua` and a flat-theme fallback (see [UI_DESIGN.md](UI_DESIGN.md)).

## Main UI and access

- The main frame is a native Blizzard window (portrait, title bar, close button, rock background), the character sheet's size at first. It can be moved and closed with Escape, and made taller from the grip at its bottom-right corner (up to twice the stock height; the size is kept); `/altarmy resetsize` restores the stock size. The grip changes the width only with the Debug page's **Window width resize**, until every tab reflows. **Window Scale** (Options → General → Look and Feel, 50% to 200%) scales the whole window.
- Tabs are icon flyouts on the right edge; hovering one shows its name. The portrait icon and title show the active tab.
- Open with `/altarmy` or `/alta`; `/alta <tab> [view]` opens one tab or sub-view (`/alta economy crates`, `/alta cooldowns dungeons`).
- Minimap button (left-click toggle, drag to move).
- The toolbar item/recipe search box is on the Summary tab. Typing in it switches into Search mode. Reputation (faction filter), Guild (character and profession search), Inventory (item search; its character picker and layout dropdown are a controls row at the top of its body) and Economy's Currency view (its filter) use the same toolbar spot for their own box; Economy's Waylaid Crates and Craftsman's Writs views put a Filter dropdown at its right end. Gear, Cooldowns and Graphs have no toolbar search. Clicking any side tab leaves Search mode.
- One toolbar settings button opens the active tab's settings panel (Summary, Gear, Economy's Currency view, Reputation, Cooldowns, Graphs, Search).
- `/altarmy networth [all] [scale]` — vendor + Auctionator AH value across characters (Auctionator required).

## Tabs

| Tab | Doc |
|-----|-----|
| [Summary](tabs/summary.md) | Character overview, totals, missing-data warnings, bank-alt icons |
| [Economy](tabs/economy.md) | WoW Forever only (the side tab is hidden elsewhere): Currency × character grid; Waylaid Crate costs per Merchant's Favor, filled via the AH or crafting; Craftsman's Writ orders priced to buy or craft; the alt-army.com crafting planner guide (Supply Chain) waits behind a feature flag |
| [Gear](tabs/gear.md) | Equipment grid, item check, compare panel, upgrade scoring / alerts |
| [Inventory](tabs/inventory.md) | One character's bags, bank and mail as slot grids like the stock windows (per-bag blocks or one combined grid; inbox rows or an item grid) |
| [Reputation](tabs/reputation.md) | Faction matrix, score-sort, optional Zygor guide links |
| [Cooldowns](tabs/cooldowns.md) | Crafting cooldowns + Raids lockouts, stockpile send / send-all |
| [Search](tabs/search.md) | Items and recipes (toolbar Search mode) |
| [Graphs](tabs/graphs.md) | Level progress charts and history imports |
| [Guild](tabs/guild.md) | Opt-in guild data sharing (conditional tab) |

Not a tab: the [Options](tabs/options.md) pages (Interface → AddOns → AltArmy) and the slash commands.

## Cross-cutting

### Realm filtering and character visibility

- **Character filters** at the top of the Summary, Gear, Reputation and Currency settings panels (`UI/CharacterFilterControls.lua`, `Data/Characters/CharacterFilter.lua`), each tab's own, saved as `filter` in its settings:
  - **Realm filter**: This realm, this faction (always on); This realm, opposite faction and Other realms (off by default); Include linked accounts (on by default; offered only once there is a linked account). Its summary reads "All" when every option it offers is on, "All realms" when all but Include linked accounts are, else "This faction" or, with the opposite faction, "This realm", then ", Other realms" and ", Linked accounts" when those are on.
  - **Level filter**: a slider with two handles, the lowest and the highest level shown (1 to 60 on WoW Forever, 1 to 70 on TBC Anniversary; every level by default). Drag either handle, or click the bar to move the nearer one there.
  - **Class filter**: every class, in its class colour (all on by default).
  - **Pin individual characters**: Current character (pins whichever character is logged in, overriding the filters and Hide), then each character. **Hide individual characters**: each character. Both list the characters the realm filter shows (never left out by level or class), grouped by realm and faction as the Summary's sections are (by name within each), each group under a divider row naming it (a line, "Realm — Faction" centered, a line; Current character, in no group, comes first), scroll past 12 rows, and pinning one unhides it and the other way round. Bank alts, always hidden on Gear, Reputation and Currency, are not listed there.
  - A tab's first filter starts from the old global "Characters shown" choice (`AltArmyTBC_Options.characterScope`, else `realmFilter`), which nothing writes any more.
- The Cooldowns tab's settings panel has its own **Realm filter** and **Group characters** (no level, class, pin or hide filters), which its cooldown alerts follow too.
- Search, Inventory, Graphs, the gear compare panel and `/networth` follow the **Summary tab's realm filter** (`GlobalRealmFilter`).

### Linked accounts

Your other WoW accounts (the same Battle.net login) send their characters to this one, which shows them read-only beside yours: Summary ("Online" while that account is on it; in the totals while shown, never in missing-data warnings, main star or bank icon), Search (items and recipes, shown and sorted as your own), Cooldowns and raid lockouts, and `/networth` (gold and items, each linked character its own line). Never counted as yours: mail alerts, gear upgrade alerts, guild sharing (a linked account shares itself), the profit export and the website upload. Kept in its own SavedVariable, `AltArmyTBC_LinkedData` (`Data/Link/LinkStore.lua`), checked unit by unit (`LinkValidate.lua`) against a whitelist of what is sent (`LinkDomains.lua`: of level history only each milestone's played times, for the Graphs tab; no auction data, mail text or UI state). Linking and syncing (Options → Sharing → Linked accounts): your other accounts online with Alt Army are listed; Link on one asks the other, which shows a dialog (`UI/LinkAccountDialog.lua`), both showing the same 4-digit code; once accepted, both send each other a manifest of per-domain hashes and ask for what changed (`Data/Link/LinkSession.lua`, `LinkSync.lua`), over Battle.net game data (`LinkTransport.lua`, prefix `AltArmyLink`, chunked by `LinkCodec.lua`); a character's changes (money, bags, gear, recipes, ...) follow 20 s after it first changes, and deleting characters tells linked accounts 20 s after the last deletion; Unlink tells the other account (at once, or when it is next online). A link is named after the character it linked from (the client gives an addon no game account name); Rename names it (`LinkStore.SetName`, kept on this account only). Only game accounts on your own Battle.net account are ever answered. Nothing is sent in combat. `/altarmy debug link fake [n]` and `clear` link copies of this account's characters to try the display without a second client. A character saved before the addon stored GUIDs is sent once it logs in again.
### Bank alts

- Per-character bank-alt flag in Options (Characters).
- Auto-detect suggest dialog; Summary bank icon; optional hide-from-Summary.
- Stockpile mailing workflows assume a bank-alt source.

### Alerts and reminders

- **Cooldowns:** a chat line and a sound when a cooldown is ready, per cooldown (Alert when ready in the tab's settings panel, with TBC's specialization-only choices), for the characters that panel's realm filter shows.
- **Gear upgrades:** chat (and clickable links) for loot, Need/Greed, quest rewards, and level-up upgrades for you or same-realm, same-faction alts; quest-reward overlays on turn-in / quest log.
- **Mail expiry:** login chat when any character’s soonest mail returns within 5 days.

### First-login notices

One-time dialogs shown at most once each (guild-share prompt, bank-alt suggestion, RestedXP quest-reward conflict, link your accounts) go through a shared onboarding queue that shows at most one a session (the first by priority); the others wait for a later login.

### Optional addon integrations

| Addon | Used for |
|-------|----------|
| Auctionator | `/altarmy networth` AH pricing; Economy → Waylaid Crates row click searches the crate and its cheaper fill (the bundle, or a craft's reagents), Craftsman's Writs row click the writ, its order and the craft's reagents (temporary shopping list, at the auction house) |
| TacoTip / GearScoreTBCClassic | Gear score providers for score-sort and upgrades |
| RestedXP (RXPGuides) | Level history import; quest-reward conflict dialog |
| Questie / NovaInstanceTracker | Level history import into Graphs |
| Zygor Guides | Reputation tab guide links |

### Export for the Alt Army website

`/altarmy export` (the only way in; no button) shows the account's characters,
professions and learned recipes as one copyable string for the Alt Army website, which ranks profitable
crafts for them; a note above it says which characters still lack data the export carries, and what to do.
See [tabs/options.md](tabs/options.md#export-for-the-alt-army-website). Bundles LibDeflate
(zlib license) for the compression.

### Auction house scan for the Alt Army website

On WoW Forever only, an **Alt Army scan** button sits above the auction house window; `/altarmy scan` does
the same. Elsewhere (TBC Anniversary) the button, the Auction House options section, the automatic scan and
the reading of other addons' full scans are all off, whatever the client's API offers
(`AuctionScan.HasFullApi` and `HasSummaryApi`, which `HasApi` ORs, check `DataStore.IsWowForever` first).

- A **full scan** reads every listing and saves, per item, how many units are listed at each price.
  The website prices crafts from that, so one odd listing no longer decides what an item costs.
- The game allows one full scan every 15 minutes per account. During that wait, or if the game refuses the
  full scan, the button runs a **summary scan** instead: each item's cheapest price and how many units are
  listed. It has no cooldown and is faster, but cannot say how many units sit at each price.
- The scan mode (Options → General → Auction House): **Prefer full scans** (the default, as above), **Only
  full scans** (nothing during the cooldown: the button is disabled and the automatic scan does nothing) or
  **Only summary scans**.
- Summary scans are kept apart from full scans (the newest one per realm and faction) and are never uploaded
  to the website, which only gets full scans. A summary never replaces a stored full scan.
- When the full scan is cooling down and no summary scan is possible, the button counts the wait down. Its
  tooltip says which kind of scan a click runs now.
- **Scan automatically:** Options → General → **Auction House** can start the scan by itself a second after
  the auction house opens (off by default). The settings icon right of the button opens that option. A visit
  within the 15-minute cooldown runs a summary scan; one where another addon already started a full scan,
  or within 2 minutes of that auction house's last scan (full or summary), is skipped. The button still
  scans then.
- A full scan started by another addon (Auctionator's full scan option) is saved too, and spends the same
  cooldown.
- Keep the auction house open until the button stops showing progress: a scan that was cut short is dropped.
- A scan Alt Army starts (the button, `/altarmy scan` or the automatic scan) says in chat whether it is a
  full or summary scan when it starts, and when it ends: how many listings (or items) were saved, or that it
  was cut short and nothing was saved. Another addon's full scan is saved quietly, and replaces a summary
  scan of ours that is still running.
- The last 3 scans per realm and faction are kept, for 7 days. Seller names are never saved.
- The scan is uploaded with the rest of Alt Army's data (Alt Army Sync, or the site's Upload page after a
  `/reload` or logout).
- In game, the [Economy](tabs/economy.md) tab's **Waylaid Crates** view prices every Waylaid Crate per point of Merchant's Favor,
  filled from the newest scan, full or summary, or crafted by your characters, and can turn on the automatic scan too; its
  **Craftsman's Writs** view prices every writ's order bought on the auction house or crafted by your characters.

### Data collection and persistence

Stored under `AltArmyTBC_Data`, `AltArmyTBC_Options`, tab settings tables, `AltArmyTBC_GuildData`, `AltArmyTBC_SharingSettings`, `AltArmyTBC_AuctionScans`, `AltArmyTBC_AuctionBook` and `AltArmyTBC_LinkedData` (see [ARCHITECTURE.md](ARCHITECTURE.md)).

Core domains include: character basics, containers/bank, equipment, currencies, professions/recipes, cooldowns/specialization, lockouts, reputations, mail, auctions/bids, talents, level history.

Scanning is event-driven with delayed rescans where needed.

### Built-in recipe data

AltArmy ships a table of every profession recipe for each client (TBC Anniversary and WoW Forever; only the one for the running client loads). It gives each recipe's profession, crafted item, required skill, difficulty bands and where it is learned (trainer, quest, vendor, reputation, drop, or with the profession). Search and the Guild tab use it for the skill column, difficulty colors and filters, without any other addon.

When a character learns a recipe with the profession window closed, AltArmy recognizes it (from the learn event or the system chat line, in any client language), adds it to that character's recipes with its difficulty color, and shares it with guildmates. The profession window no longer has to be reopened; the Summary warning appears only for a recipe it can't recognize.

On WoW Forever, AltArmy also reads a character's recipes by itself, so no profession window ever has to be opened. It reads only professions whose recipes are missing or out of date (those the Summary warning points at): about 10 seconds after login, and a few seconds after learning a recipe it couldn't recognize. A recipe it recognizes is stored without a read. Reading only those keeps the profession window's opening sound to when it is needed. Each read opens that profession's window out of sight, with no click, through a link to the character's own profession; the window is closed again once it has been read. Reads wait until the character is out of combat, not typing, and has no window open. Only professions the game lets players link can be read this way: Fishing, Mining, Herbalism, Skinning and the mage's Comprehension still need their window opened. On Forever the Summary warning for an alt's missing recipes in a profession that can be read says only to log in with it. Turn it off under Options > General > Advanced if it gets in the way of another profession addon.

The tables are generated from the game client's data (wago.tools) and open-source server data. A daily GitHub workflow (`game-data`, at the monorepo root) regenerates them when a new client build or a new release of the server databases changes them, commits to main and releases the addon; a game patch (a build whose major.minor.patch moved) opens a pull request instead, since the TOC's interface needs a person. See `AltArmy_TBC/Data/DESIGN.md` ("Recipe data").
