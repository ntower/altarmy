# Options and slash commands

The game's Options → AddOns entry and user-facing slash commands.

## Options pages

**AltArmy** in the AddOns list expands into its pages (`UI/Options.lua`): General, Sharing, Characters, Gear, Cooldowns and, while debug options are on, Debug. They are sub-pages of the AltArmy entry, as Auctionator's, Consumable Connoisseur's and RareScanner's are: `Settings.RegisterCanvasLayoutSubcategory` under the `Settings.RegisterCanvasLayoutCategory` entry, or `parent = "AltArmy"` with `InterfaceOptions_AddCategory` on clients without the Settings API. The AltArmy entry itself shows the version and points at its pages.

| Page | Contents |
|-----|----------|
| **General** | Collapsible sections, drawn like the Keybindings page's (all but Advanced start open): **General** (minimap show/hide; **Characters shown**, which characters every tab lists (`GlobalRealmFilter`'s scope, `AltArmyTBC_Options.characterScope`): Characters on the same realm and same faction (always), Characters on the same realm of the opposite faction and Characters on other realms (both off by default; a saved "all realms" turns both on; `realmFilter` follows other realms), and once a linked account exists Characters from linked accounts (if they match the filters above) (on by default)), **Auction House** (side by side, half the width each: the **Scan AH automatically** checkbox (scan when the auction house opens) and the scan mode dropdown (`AltArmyTBC_Options.auctionScanMode`): **Prefer full scans** (the default: a full scan when the game allows one, a summary scan otherwise), **Only full scans** (no scan during the 15-minute cooldown: the scan buttons are disabled and the automatic scan does nothing) or **Only summary scans**; a saved "Prefer full scans" checkbox turned off reads as Only summary scans. Its help icon explains that a full scan knows how many units sit at each price but is slower and allowed once every 15 minutes, while a summary scan is fast but less accurate. The Economy tab's summary-scan info tooltip opens the Options here with the dropdown flashed (`flash = "scanMode"`); WoW Forever only) and **Advanced**, last and closed at first (**Read recipes from profession links**, on by default: reads the character's missing or out-of-date recipes (and online guildmates') through profession links in the background, at login and after learning one, so no profession window has to be opened; its help icon says so, and that it only needs turning off if flashes or sounds of the UI opening annoy the player, or it causes bad interactions with other addons; with it off, the Summary warning names each profession window to open, even for alts; WoW Forever only). Scrolls when the open sections outgrow the panel |
| **Sharing** | **Guild** (guild data sharing: main, display name, data retention, chat; shown while guild sharing is available), then **Linked accounts** (WoW: Forever only, for now: `UI/LinkedAccountsOptions.lua`; each link with its characters, when it last synced, Sync now and Unlink (click twice); each other account of yours online with Alt Army that isn't linked, with Link, then the code to compare while the other account accepts), in its own scroll area. Guild prompts that open Options (`flash = "main"`, `"guildShare"`, `"autoDelete"`) open this page whatever page they name (`panel.FlashTargetPage`). |
| **Characters** | Per-character bank-alt flags; delete character data (self-delete protected + confirmation) |
| **Gear** | Gear upgrade notification toggles (current character / alts; loot, quest rewards, etc.) |
| **Cooldowns** | One collapsible section per category (all start closed), drawn like the General page's: UI visibility, alerts, reminder intervals; specialization-related options. On WoW Forever, shows a "work in progress" banner and only the Dedicated Study (Legacy talent, first), Transmute and Research (Comprehension) categories (the others are TBC-specific crafts), and hides the "Only if Master of Transmutation" toggles; a saved value for them is ignored there |
| **Debug** | Listed after `/altarmy debug on` (a page can't be taken out of the list, so after `debug off` it stays until reload and says debug options are off); search timing, cooldown scan logging, item stats, guild share verbose, **Clear auction data** (deletes stored auction house scans; keeps the scan cooldown), **Window resize** (the main window's resize grip, not ready for every tab yet), etc. |

Shared theme with the main UI ([UI_DESIGN.md](../UI_DESIGN.md)).

Options opened on a particular control (for example from the Alt Army scan button's settings icon, or from the guild-sharing prompts) open its page, open only the section it is in (the others close), scroll it into view and flash it.

## Minimap

- Left-click: open/close main window.
- Left-click while holding an item (window closed): opens the window on **Gear → Upgrade Check** with that item loaded for comparison. The next click closes the window as usual.
- Drag: reposition (LibDBIcon).
- Show/hide under General options.

## Slash commands

| Command | Action |
|---------|--------|
| `/altarmy` / `/alta` | Open main UI |
| `/altarmy networth [all] [scale]` | Net worth (vendor + Auctionator); `all` = all realms; scale 0–1 (default 0.9) |
| `/altarmy export` | Export for the Alt Army website (see below; there is no button for it) |
| `/altarmy scan` | Scan the open auction house (same as the **Alt Army scan** button): the kind the scan mode allows now (Options → General → Auction House) |
| `/altarmy debug on` / `off` | Add the Debug options page / turn it off and enable/suppress debug logging |
| `/altarmy debug resize on` / `off` | Show/hide the main window's resize grip (the Debug options' **Window resize**); while on, `/altarmy resetsize` restores the stock size |

Additional `debug …` subcommands exist for developers (mail alerts, compare dump, guild share inject, etc.); they are not part of the product feature surface.

## Export for the Alt Army website

Only `/altarmy export` opens it. An **Export** dialog with one selected line of text (starts with `AAX1:`) and
"Copy this string into the alt army website to upload your data": press Ctrl+C and paste it on the Upload tab of
the Alt Army website (alt-army-prod.web.app), which then knows your characters without a SavedVariables
upload or `/reload`. It holds every saved character's realm, full name, GUID, faction, class, level, professions
(rank and max), learned recipe ids, Legacy talents and standing with the eight city factions (the site discounts
vendor prices by reputation), plus the client's interface number and build so the site can tell TBC
Anniversary from Forever. The string is LibDeflate-compressed text built by `Data/ProfitExport.lua`; its
format is documented there, and `spec/fixtures/profit_export_v2.txt` (format v2) is the golden string the site's parser is
tested against.

When some of that is known not to have been gathered yet, a gold note above the string lists each such
character with what to do, worded like the Summary tab's `!` tooltip (log in with this character, open your
Tailoring window, open your Reputation panel, /reload…), up to eight characters and then how many more. It
checks only what the export carries (`SummaryData.GetExportMissingDataInfo`: a GUID, the professions and their
recipes, Legacy talents on Forever, city reputations), so missing bags or gear don't show there. The string is
still given: the site takes what is there.

## Related UI

- Bank-alt suggest dialog (auto-detect).
- Guild share onboarding.
- RestedXP quest-reward conflict dialog when RXP and AltArmy upgrade overlays would clash.
