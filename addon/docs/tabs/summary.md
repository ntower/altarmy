# Summary tab

Character overview list for the account (narrowed by the Summary settings' character filters).

## Purpose

See levels, rest XP, money, played time, and last online at a glance; pin/hide characters; spot missing gathered data.

## Layout

- Scrollable character table with a totals row (one total for everything listed).
- Settings panel: **Realm filter**, **Group characters**, **Level filter**, **Class filter**, **Pin individual characters** and **Hide individual characters** (see [Realm filtering](../FEATURES.md#realm-filtering-and-character-visibility)).
- The Summary's realm filter is also the one Search, Inventory, Graphs and the gear compare panel use (Cooldowns has its own).
- **Group characters** (on by default): the list is split into a section per realm and faction, each under a header ("Realm — Faction (n)"): this realm and faction first, then this realm's other faction, then other realms A to Z. Clicking a header folds its section away (a plus icon) or back (a minus icon), remembered in `collapsedGroups`. Headers stick to the top of the list while their section scrolls under them, until the next one pushes them out (`Data/Characters/CharacterSections.lua`, as Search's section headers). Names then leave out the realm, which the header gives. Sorting by a column sorts within each section.

## Columns

| Column | Notes |
|--------|--------|
| Name | Class-colored with class icon; bank-alt icon when flagged. A linked account's character is read-only: counted in the totals while shown, with no missing-data warning, main star or bank icon |
| Level | Fractional level support |
| Rest XP | Rested experience (cap and accumulation rate widened by the WoW Forever "Well Rested" Legacy Talent, when captured — see [Legacy Talents](../WOW_FOREVER_COMPATIBILITY_RESEARCH.md#legacy-talents-2026-09-21)). A character with a rank in Well Rested shows a green up arrow before the percentage; hovering the cell shows a tooltip with the talent's rank and what it adds |
| Money | Bags + mail gold |
| Played | Time played |
| Last online | Relative last logout |
| Warning | Single `!` when data has not been gathered yet (tooltip lists actions) |

Click headers to sort ascending/descending.

A wider window widens Name by all of the extra, so the grid always fills the list; the other columns keep their width and the headers keep their short labels ("Lvl", "Online").

## Character visibility

- Pin and hide via the Summary settings' Pin individual characters and Hide individual characters dropdowns.
- Bank alts: icon on the name column; optional hide-from-Summary (Options → Characters).
- Click bank-alt icon to jump to Options for that character.

## Missing data

One gold `!` per character with a de-duped action list (`GetMissingDataInfo`). Covers never-gathered modules, stale reputation schema, professions needing an open window (on WoW Forever, where recipes are read at login, an alt's missing recipes only ask to log in with it, except for professions that can't be read that way: Fishing, Mining, Herbalism and Skinning; Comprehension, which has no window to open, is never asked for), talents, etc. See the summary-missing-data Cursor skill for the design contract.

## Data source

`SummaryData` / `Characters` over DataStore character, money, mail gold, and related modules. Settings: `AltArmyTBC_SummarySettings` (`filter`, `groupByRealmFaction`, `collapsedGroups`, sort, pin / hide).
