# Economy tab

Every character's currencies side by side, auction-house economics (what each Waylaid Crate costs to buy and fill, from the auction house or by crafting, per point of Merchant's Favor; what each Craftsman's Writ's order costs to buy or to craft), and Alt Army's crafting planner on alt-army.com.

## Purpose

See how much of each currency every alt holds. Find the cheapest way to earn Merchant's Favor from Waylaid Crates, and reputation from Craftsman's Writs, using the auction house scan Alt Army already takes and what the army's characters can craft. Learn what alt-army.com does with that data and how to upload it automatically.

## Availability

**WoW Forever only.** Waylaid Crates, the full auction house scan and alt-army.com's prices exist only there. On TBC Anniversary the side tab is hidden (`Tabs/TabEconomy.lua` checks `DataStore.IsWowForever`), and the tabs below it move up.

## Sub-views

Four sub-views (three while Supply Chain is behind its feature flag), switched with the tabs that hang above the panel in the toolbar row (`UI/TopTabs.lua`, same as Gear and Cooldowns). Currency is first and is the default. The last one used is remembered (`AltArmyTBC_Options.economy.activeView`).

### Currency

A grid of currencies (rows) × characters (columns), like the Reputation tab, with columns half again as wide. Its top tab uses the Character window's own Currency side-tab icon (`INV_SideTab_Currency_c60`).

- **Rows:** **Gold** first, above every header: each character's money in gold, silver and copper. When that is too wide for the column, copper is left out, then silver (hover the cell for the full amount). Then every currency any shown character has, grouped under the same headers and in the same order as the Character window's Currency tab. Each currency row has its icon; hovering it shows the game's currency tooltip.
- **Cells:** how much of that currency the character has, e.g. "1,500". A grey 0 means none. A dash means Alt Army hasn't recorded that character's currencies yet (log in on it once). Hovering a cell shows the amount and, for capped currencies, the cap.
- **Sorting:**
  - The score-sort row under the character names (level / item level / played / gear score, as on Gear and Reputation) orders the columns.
  - Clicking a currency sorts the characters by how much of it they have (click again to flip). Clicking the score selector returns to score sorting.
  - Character names in the header are not clickable.
- **Filter currency** box in the toolbar row, beside the settings button (shown only on this view): shows only the currencies whose name contains the text (case-insensitive; Gold counts as a currency). Headers stay only while one of their currencies matches. Matching text is green, as in other searches. When nothing matches, the grid says so.
- **Settings** (toolbar gear button, shown only on this view): Pin current character, and pin / hide per character, like Reputation. Saved in `AltArmyTBC_Options.economy.currency`. Bank alts are hidden, and the global realm filter applies.
- Characters with no currency data yet still show their gold; their currency cells show a dash.

### Waylaid Crates

A Waylaid Crate is filled with **any one** of the bundles its label lists (for example Apprentice Ore takes 20 Copper Ore or 20 Tin Ore), then turned in for Merchant's Favor and some gold back. The table lists every Waylaid Crate the game has (all 30 shipments and the unread crate), priced from the newest Alt Army scan of the current realm and faction's auction house: a full scan or a summary scan, whichever is newer.

Laid out like the Craftsman's Writs view, with the same column widths:

| Column | Meaning |
|--------|---------|
| Waylaid Crate | The shipment (icon; green for crafted-goods crates, white for gathered goods) |
| (Merchant's Favor icon) | Merchant's Favor for turning the filled crate in (by tier and kind, below). Artisan's are guesses: shown "40?", and hovering the cell says so (titled "Educated Guess": "This early into Forever, we don't have reliable information on how much this rewards. Alt Army will be updated as the game matures.") in place of the row's tooltip |
| Crate Price | The cheapest crate listed (a dash when none is) |
| Fulfill via AH | The cheapest bundle that can be bought in full, bought cheapest-first up the auction house's listings |
| Fulfill via Craft | The cheapest bundle to craft by the realm and faction's characters, its reagents got the cheapest way (vendor, auction house or a further craft), as on the Craftsman's Writs view; a dash when nobody knows a recipe for any bundle |
| Total Cost / (Merchant's Favor icon) | Crate Price + the cheaper fill, less the gold the turn-in gives back, per point of Favor, rounded (negative when the turn-in pays more than it cost) |

The Merchant's Favor icon is the currency's (3402) from the game, else Forever's icon 135725. A cost marked "~" rests on an estimate or on units the auction house is short of (crafting only: the AH column counts only bundles listed in full). A summary scan's costs are not marked.

- Default order: Total Cost / Favor, cheapest first (a saved sort on a column that is gone falls back to it). Every column header sorts, and the choice is saved. Rows missing the value sorted on (a dash) come last in either direction.
- A crate that isn't listed still shows both ways to fill it; its Crate Price and Total Cost / Favor are dashes, and its tooltip's crate price reads "n/a" in grey.
- **Filter** dropdown in the toolbar row (top right, shown only on this view): **Hide unavailable crates** (`waylaidOnlyAvailable`, checked by default) hides the crates not listed on the auction house and those no bundle can be bought in full or crafted for (the unread crate, whose shipment is random, only needs to be listed); **Hide crates I can not fulfill via crafting** (`waylaidOnlyCraftable`, off by default) hides those no character can craft a bundle for.
- A bundle counts for Fulfill via AH only if enough units are listed to buy all of it. When no bundle can be bought or crafted, Total Cost / Favor shows a dash and the crate sorts last.
- The unread **Waylaid Crate** (its shipment is random until the label is read) shows its price only (its Favor is a dash: it depends on the shipment).
- A cost that reaches the scan's dearest listings is a close estimate: those are saved together at their cheapest price. It is not marked.
- **From a summary scan**, which knows only each item's cheapest price and units listed, every fill is priced as count × cheapest price, so the real cost can only be higher. Only the "(summary)" note on the scan's age says so.
- Hovering a row shows the crate's tooltip, then the **turn-in reward** (Merchant's Favor and the gold handed back), the crate's price, both ways to fulfil it (the craft naming the crafter in class colour), the total cost less the gold back and that per Favor, every bundle with its auction house cost ("only N listed" or "not listed") and craft cost, cheapest first (only the cheapest in white; in it, the dearer of its two costs grey), and when the craft is cheaper, its steps (vendor and auction house buys, then the crafts, per character), as on the Craftsman's Writs view.
- **Auctionator search:** with Auctionator installed and the auction house open, clicking a row opens Auctionator's Shopping tab and searches a temporary list ("Alt Army (temporary)") for the crate and what its cheaper fill buys: the bundle at its count, or the craft's vendor and auction house reagents at their quantities (just the crate when no fill can be had), exact names (the same API as Auctionator's crafting-window Search button). The row tooltip then ends with a grey "Click to search with Auctionator"; elsewhere clicking does nothing and the line is hidden (`Data/Integrations/AuctionatorSearch.lua`).
- The row below the table shows, on the left, how old the scan is, in whole minutes rounded to the nearest ("Scanned 12 min ago", "Scanned just now" under a minute; "(summary)" after a summary scan, with an info icon whose tooltip, over the age or the icon, explains that a summary scan collects only each item's lowest price, not how many are listed at each price, so costs of more than one unit may be too optimistic; it ends with a grey "Click to configure", and clicking opens Options → General → Auction House with the scan mode dropdown flashed): white under 15 minutes, yellow up to 30, red after that. On the right, an **Auto scan when opening AH** checkbox (same setting as Options → General → Auction House). While the auction house is open, a **Scan now** button sits in the middle; during the game's 15-minute full-scan cooldown it runs a summary scan, and reads "Scan in m:ss" only when no summary scan is possible (same as the button on the auction house). When the filter hides every crate, the table says so. The table refreshes when a scan finishes while it is open.
#### Turn-in rewards

What turning in a filled crate gives is not in the game data, so `W.REWARDS` in `Data/Economy/WaylaidCosts.lua` holds it by tier and kind. The sealed crate keeps the Waylaid Crate's quality, and a green (crafted) crate gives twice a white (gathered) one.

| Tier | Gathered (white): Favor / gold | Crafted (green): Favor / gold | Source |
|------|-------------------------------|-------------------------------|--------|
| Apprentice | 5 / 2.5s | 10 / 5s | Verified in game |
| Journeyman | 10 / 5s | 20 / 10s | Verified in game |
| Expert | 15 / 7.5s | 30 / 15s | Verified in game |
| Artisan | 20 / 10s | 40 / 20s | **Assumed** (continues the steps above); revisit once one is turned in |

Not yet checked: whether every crate of one tier and kind gives the same. The game data also has blue Sealed Apprentice, Journeyman, Expert and Artisan Crates and a Sealed Elite Crate (white, green and blue), none of which a Waylaid Crate is known to become yet.

**No scan yet** for this realm and faction: the table is replaced by a message to visit an auction house and use the Alt Army scan button, plus a **Scan the auction house automatically when it opens** checkbox. It is the same setting as Options → General → Auction House.

### Craftsman's Writs

A Craftsman's Writ ("Craftsman's Writ: Lesser Wizard's Robe", a rare item that drops from monsters, or comes out of a Sealed Journeyman's / Expert's / Artisan's Writ) starts a quest asking for that crafted item, delivered somewhere for reputation with Azeroth Commerce Authority (Alliance) or Durotar Supply and Logistics (Horde). The table lists all 150 writs, whether or not any is listed or held, with what its order costs to **buy** on the auction house and what it costs to **craft** the cheapest way with the characters of the current realm and faction.

| Column | Meaning |
|--------|---------|
| Craftsman's Writ | The writ (icon, blue) named by what it wants, with "(2 held)" when the realm's characters hold any |
| Rep | Reputation for delivering it: 75 / 125 / 200 by tier (Journeyman / Expert / Artisan, named in the tooltip). Community-reported, not in the game data |
| Writ Price | The writ itself, its cheapest listing on the auction house (writs are tradeable) |
| Fulfill via AH | The order's units bought cheapest-first up the auction house's listings |
| Fulfill via Craft | The order crafted: every reagent from a vendor, the auction house or a craft, whichever is cheapest, recursively |
| Total Cost / Rep | Copper per point of reputation: (the cheaper of the two ways to fulfill it + the writ price) / Rep. A dash when the writ isn't listed or the order can't be fulfilled |

- Default order: Total Cost / Rep, cheapest first. Every column header sorts, and the choice is saved (`AltArmyTBC_Options.economy.writsSortKey`, `writsSortAscending`; a saved sort on a column that no longer exists falls back to Total Cost / Rep). Craftsman's Writ sorts by tier, then name. Rows missing the value sorted on (a dash) come last in either direction.
- Who does the final craft is named in the tooltip ("Fulfill via craft on …"), in their class colour.
- **The order.** The game data names the item but not how many, so each writ is assumed to want one craft's output (one potion, one robe, 200 Crafted Solid Shot) until a character holds its quest: the quest log's objective ("Lesser Wizard's Robe: 0/2") is then read and kept account-wide (`AltArmyTBC_Data.WritOrders[questID] = { item, count, t }`, `Data/Economy/WritOrders.lua`, on `QUEST_ACCEPTED` and `QUEST_LOG_UPDATE`). Where two items share the order's name (Golden Scale Gauntlets), the cheaper is priced.
- **The craft route** (`Data/Economy/CraftPlan.lua`): each reagent is got the cheapest way among a vendor (where one sells it), the auction house (never for a bind-on-pickup reagent) and a craft by any character on the realm and faction who knows a recipe for it (the highest skilled, then A-Z, when several do), the same again for that recipe's reagents, up to 8 crafts deep. Casts are whole; what a cast makes beyond the order isn't credited. When several branches buy the same item on the auction house, their buys walk one ladder, so the plan's cost can end up over the buy it beat. Mail, travel and time are not costed.
- **Vendor discounts.** A vendor buy is priced for the character who will use it (the crafter of the recipe it goes into; the current character when the order is bought outright): Bartering's 5% a rank, plus a flat 10% once that character is Honored with any city faction (Stormwind, Ironforge, Gnomeregan Exiles, Darnassus, Orgrimmar, Darkspear Trolls, Thunder Bluff, Undercity), whoever the vendor is. Vendors aren't checked one by one; the view doesn't say where to go.
- **Marks.** A `~` before a cost means an estimate: units the auction house is short of are priced at its dearest listing (the tooltip says how many), or the scan folded the dearer listings together. A summary scan's costs (count × each item's cheapest price, so the real cost can only be higher) are not marked: only the "(summary)" after the scan's age says so. A dash means no way to price it: nothing listed, nobody can craft it, or a reagent has no source (Gordok Ogre Suit needs the bind-on-pickup Ogre Tannin, so it can only be bought).
- **Filter** dropdown in the toolbar row (top right, shown only on this view), each choice saved: **Hide unavailable writs** (`writsOnlyAvailable`, checked by default) hides the writs not listed on the auction house and those whose order can be neither bought nor crafted; **Hide writs I can not fulfill via crafting** (`writsOnlyCraftable`) hides the rows nobody can craft. When the filters hide every row, the table says so.
- Hovering a row shows the writ's tooltip, the order ("Wants 1x Lesser Wizard's Robe"), tier and reputation, the writ's price and both ways to fulfill it (with both priced, the dearer line grey, label and cost, in the dark grey of the Auctionator hint), the total cost (writ plus the cheaper way) and that per point of reputation, then the steps to craft it ("To craft 1x …:"; greyed out with names uncoloured when crafting is the dearer way, step costs otherwise white): vendor buys per character, auction house buys (each with its cost), then the crafts bottom up ("Craft 2x Bolt of Silk Cloth on Tailorname", no cost; every count reads "3x"). Character names are in their class colour, and a cost there is none of reads "n/a" in grey. With Auctionator at the auction house, clicking a row searches a temporary shopping list for the writ, the item its order wants (at the order's count) and, when a character can craft it, every reagent the craft plan buys (vendor ones too, each at its quantity), as the Waylaid view does.
- The row below the table is the Waylaid view's (one shared builder, `CreateScanFooter` in `Tabs/TabEconomy.lua`): the scan's age on the left, the **Scan now** button in the middle while the auction house is open, the **Auto scan when opening AH** checkbox on the right. **No scan yet** for this realm and faction: as on the Waylaid view, the table and the row below it are replaced by the message to visit an auction house and use the Alt Army scan button (saying what each Craftsman's Writ costs to buy and fill), with the **Scan the auction house automatically when it opens** checkbox.
- **Dev dumps** (while `/altarmy debug on`): every quest-log scan writes `writOrders` (the raw objectives of the writ quests held) and `writTooltips` (the tooltip lines of the writs in the character's bags), so the formats can be checked from the SavedVariables file and the parsing tightened. The quest APIs used are listed under Quests in `/altarmy debug apicheck`.

### Supply Chain

**Hidden for now** behind `AltArmy.FeatureFlags.economySupplyChain` (`Core.lua`, currently `false`). While it is off, the Supply Chain top tab and panel are not created, and a remembered `activeView` of `supply` falls back to Currency.

A scrolling page about alt-army.com's crafting planner:

1. The title **Put your army to work** with a read-only box holding `https://alt-army.com/profit` to copy with Ctrl+C.
2. What the site does: combines your character data, the latest auction house prices, and its item and vendor database to plan the best way to make money or raise your skills.
3. A carousel of three screenshots (flow chart, detailed steps, search results), all drawn 280 pixels tall, with small previous / next arrows fixed at the left and right edges of the page.

## Data source

- Currencies: `DataStore:ScanCurrencyList` (`Data/DataStore/DataStoreCurrencies.lua`) reads `C_CurrencyInfo`'s currency list on login and whenever `CURRENCY_DISPLAY_UPDATE` fires. It expands collapsed headers to read them and collapses them again afterwards. Rows and sorting: `Data/Economy/CurrencyGrid.lua` (pure, unit-tested).

- Prices: `AltArmyTBC_AuctionBook` via `AuctionBook.Newest(realm, faction)` (the newer of the full scan and the summary scan) and `AuctionBook.Decode(items)`.
- Crates and bundles: `Data/Economy/WaylaidCrates.lua`, generated from WoW Forever's game data by `python scripts/generate-waylaid-crates.py` (`npm run crates:generate`). It reads the item table in the site's development database (`../site/data/altarmy.sqlite` in the monorepo), and the crafting trees under the bundle items (`ITEMS`, `RECIPES`, `ByOutput`, as in `Writs.lua`) through `generate-writs.py`'s `read_game`, `trees` and `render_trees`. Keeping it current:
  - The website's `ingest` reruns the generator whenever it loads Forever data into that SQLite file, so a changed crate list shows up here as an uncommitted change.
  - The pre-commit hook (`.githooks/pre-commit`, enabled by `npm install` or `npm run hooks:install`) runs `--check` (`npm run crates:check`) and blocks a commit while the file is out of date. It skips when the database or Python isn't there.
- Costs and sorting: `Data/Economy/WaylaidCosts.lua` (pure, unit-tested; also the Economy tab's saved options for every view, and the turn-in rewards, `W.REWARDS`). The craft route: `Data/Economy/CraftPlan.lua`; who knows which recipe and each character's discount: `Data/Economy/CraftContext.lua` (shared with the Craftsman's Writs view).
- Writs and their crafting trees: `Data/Economy/Writs.lua`, generated by `python scripts/generate-writs.py` (`npm run writs:generate`; `--check` as `npm run writs:check`, in the pre-commit hook beside the crates'): the 150 writs (quest id and tier from the wago.tools ItemSparse and ItemNameDescription exports of the pinned build, cached by the site's `gamedata.py`; the wanted item matched by name among the items craft recipes make; reputation per tier as constants), every item their reagent trees touch (vendor price, bind on pickup) and every craft recipe in them (output, units a cast, reagents), from the site's development database. `ingest` reruns it with the crates generator (`site/src/altarmy_site/addon_crates.py`).
- The craft route: `Data/Economy/CraftPlan.lua` (pure, unit-tested). Rows and sorting: `Data/Economy/WritCosts.lua` (pure, unit-tested). Orders read from the quest log: `Data/Economy/WritOrders.lua` (parsing pure and unit-tested). Who knows which recipe, each character's discount and the writs held come from the DataStore (`Data/Economy/CraftContext.lua`'s `Build`, unit-tested).
- Screenshots: `Textures/Economy/*.tga`, converted from PNGs by `python scripts/convert-economy-screenshots.py`.
