# AltArmy TBC — Features

Shipped features in the current codebase. Per-tab detail: [tabs/](tabs/). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Roadmap: [FEATURE_IDEAS.md](FEATURE_IDEAS.md).

## What the addon does

AltArmy TBC is an account-wide alt management addon for TBC Classic that:

- Collects and persists character data automatically while you play.
- Presents cross-character information in tabbed dashboards.
- Supports item and recipe search across characters, with recipe skill, difficulty and source filters from built-in recipe data (optional guildmate recipes).
- Shows what each Waylaid Crate costs per point of Merchant's Favor, filled from the auction house or crafted by your characters, what each Craftsman's Writ's order costs to buy or to craft with your characters, and explains alt-army.com's crafting planner (WoW Forever).
- Tracks profession cooldown readiness (including WoW Forever's Comprehension "Research" and the Legacy talent Dedicated Study), stockpile mailing, and raid/heroic lockouts.
- Graphs leveling progress over calendar and played time.
- Optionally shares character cards and recipes with guildmates.
- Provides configurable filters, sorting, pin/hide, bank-alt flags, and alerts.
- Keeps each character's data under its unique character ID, shown with its full name. WoW Forever characters that share a first name ("Frell Blast", "Frell Ofelements") stay separate. A paid name change keeps the character's data, pins, hides and bank-alt flag.

## UI design system

- Native Blizzard look on both WoW Forever and TBC Anniversary. AltArmy uses Blizzard's own templates and atlases for panels, buttons, scrollbars, checkboxes, dropdowns, inputs and list highlights, so Forever's reskin (and reskin addons) apply automatically.
- Everything goes through `AltArmy_TBC/UI/Theme.lua`, with capability detection in `UI/NativeUI.lua` and a flat-theme fallback (see [UI_DESIGN.md](UI_DESIGN.md)).

## Main UI and access

- The main frame is a native Blizzard window (portrait, title bar, close button, rock background), as tall as the character sheet. It can be moved and closed with Escape.
- Tabs are icon flyouts on the right edge; hovering one shows its name. The portrait icon and title show the active tab.
- Open with `/altarmy` or `/alta`.
- Minimap button (left-click toggle, drag to move).
- The toolbar item/recipe search box is on the Summary tab. Typing in it switches into Search mode. Reputation and Guild use the same toolbar spot for their own filter; Inventory puts its character picker and layout dropdown there. Gear, Economy, Cooldowns and Graphs have no toolbar search. Clicking any side tab leaves Search mode.
- One toolbar settings button opens the active tab's settings (Summary, Gear, Reputation, Search panels; Cooldowns opens its Options page).
- `/altarmy networth [all] [scale]` — vendor + Auctionator AH value across characters (Auctionator required).

## Tabs

| Tab | Doc |
|-----|-----|
| [Summary](tabs/summary.md) | Character overview, totals, missing-data warnings, bank-alt icons |
| [Gear](tabs/gear.md) | Equipment grid, item check, compare panel, upgrade scoring / alerts |
| [Economy](tabs/economy.md) | Currency × character grid; Waylaid Crate costs per Merchant's Favor, filled via the AH or crafting; Craftsman's Writ orders priced to buy or craft; alt-army.com crafting planner guide (WoW Forever only) |
| [Inventory](tabs/inventory.md) | One character's bags, bank and mail as slot grids like the stock windows (per-bag blocks or one combined grid; inbox rows or an item grid) |
| [Reputation](tabs/reputation.md) | Faction matrix, score-sort, optional Zygor guide links |
| [Cooldowns](tabs/cooldowns.md) | Crafting cooldowns + Raids lockouts, stockpile send / send-all |
| [Search](tabs/search.md) | Items and recipes (toolbar Search mode) |
| [Graphs](tabs/graphs.md) | Level progress charts and history imports |
| [Guild](tabs/guild.md) | Opt-in guild data sharing (conditional tab) |
| [Options](tabs/options.md) | Options pages (AddOns → AltArmy) + slash commands |

## Cross-cutting

### Realm filtering and character visibility

- Global realm filter: current realm only, or all realms.
- Applied across Summary, Gear, Reputation, Search, Cooldowns, and Graphs.
- Per-tab pin/hide (and related sort) settings on major matrix/list tabs.

### Bank alts

- Per-character bank-alt flag in Options (Characters).
- Auto-detect suggest dialog; Summary bank icon; optional hide-from-Summary.
- Stockpile mailing workflows assume a bank-alt source.

### Alerts and reminders

- **Cooldowns:** chat, raid-warning style, or both; per-category reminder intervals; optional specialization-dependent visibility.
- **Gear upgrades:** chat (and clickable links) for loot, Need/Greed, quest rewards, and level-up upgrades for you or same-realm, same-faction alts; quest-reward overlays on turn-in / quest log.
- **Mail expiry:** login chat when any character’s soonest mail returns within 5 days.

### First-login notices

One-time dialogs shown at most once each (guild-share prompt, bank-alt suggestion, RestedXP quest-reward conflict) are sequenced through a shared onboarding queue so only one shows at a time.

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
(`AuctionScan.HasApi` checks `DataStore.IsWowForever` first).

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

Stored under `AltArmyTBC_Data`, `AltArmyTBC_Options`, tab settings tables, `AltArmyTBC_GuildData`, `AltArmyTBC_SharingSettings`, and `AltArmyTBC_AuctionBook` (see [ARCHITECTURE.md](ARCHITECTURE.md)).

Core domains include: character basics, containers/bank, equipment, currencies, professions/recipes, cooldowns/specialization, lockouts, reputations, mail, auctions/bids, talents, level history.

Scanning is event-driven with delayed rescans where needed.

### Built-in recipe data

AltArmy ships a table of every profession recipe for each client (TBC Anniversary and WoW Forever; only the one for the running client loads). It gives each recipe's profession, crafted item, required skill, difficulty bands and where it is learned (trainer, quest, vendor, reputation, drop, or with the profession). Search and the Guild tab use it for the skill column, difficulty colors and filters, without any other addon.

When a character learns a recipe with the profession window closed, AltArmy recognizes it (from the learn event or the system chat line, in any client language), adds it to that character's recipes with its difficulty color, and shares it with guildmates. The profession window no longer has to be reopened; the Summary warning appears only for a recipe it can't recognize.

On WoW Forever, AltArmy also reads a character's recipes by itself, so no profession window ever has to be opened. It reads only professions whose recipes are missing or out of date (those the Summary warning points at): about 10 seconds after login, and a few seconds after learning a recipe it couldn't recognize. A recipe it recognizes is stored without a read. Reading only those keeps the profession window's opening sound to when it is needed. Each read opens that profession's window out of sight, with no click, through a link to the character's own profession; the window is closed again once it has been read. Reads wait until the character is out of combat, not typing, and has no window open. Only professions the game lets players link can be read this way: Fishing, Mining, Herbalism, Skinning and the mage's Comprehension still need their window opened. On Forever the Summary warning for an alt's missing recipes in a profession that can be read says only to log in with it. Turn it off under Options > General > Advanced if it gets in the way of another profession addon.

The tables are generated from the game client's data (wago.tools) and open-source server data. A daily GitHub workflow opens a pull request when a new client build or a new release of the server databases changes recipes. See `AltArmy_TBC/Data/DESIGN.md` ("Recipe data").
