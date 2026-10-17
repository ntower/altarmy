# Summary tab

Character overview list for the account (respecting the global realm filter).

## Purpose

See levels, rest XP, money, played time, and last online at a glance; pin/hide characters; spot missing gathered data.

## Layout

- Scrollable character table with a totals row.
- Settings panel for pin/hide and related display options.
- Global realm filter (Options / General) limits which characters appear.

## Columns

| Column | Notes |
|--------|--------|
| Name | Class-colored with class icon; a faction badge (its faction on hover) right after it on a character of the opposite faction (listed when Options shows that faction or other realms); then a Battle.net badge on a linked account's character (its account and when it was received on hover; such rows are read-only, left out of the totals, and get no missing-data warning, main star or bank icon); bank-alt icon when flagged |
| Level | Fractional level support |
| Rest XP | Rested experience (cap and accumulation rate widened by the WoW Forever "Well Rested" Legacy Talent, when captured — see [Legacy Talents](../WOW_FOREVER_COMPATIBILITY_RESEARCH.md#legacy-talents-2026-09-21)). A character with a rank in Well Rested shows a green up arrow before the percentage; hovering the cell shows a tooltip with the talent's rank and what it adds |
| Money | Bags + mail gold |
| Played | Time played |
| Last online | Relative last logout |
| Warning | Single `!` when data has not been gathered yet (tooltip lists actions) |

Click headers to sort ascending/descending.

## Character visibility

- Pin / hide via Summary settings.
- Bank alts: icon on the name column; optional hide-from-Summary (Options → Characters).
- Click bank-alt icon to jump to Options for that character.

## Missing data

One gold `!` per character with a de-duped action list (`GetMissingDataInfo`). Covers never-gathered modules, stale reputation schema, professions needing an open window (on WoW Forever, where recipes are read at login, an alt's missing recipes only ask to log in with it, except for professions that can't be read that way: Fishing, Mining, Herbalism and Skinning; Comprehension, which has no window to open, is never asked for), talents, etc. See the summary-missing-data Cursor skill for the design contract.

## Data source

`SummaryData` / `Characters` over DataStore character, money, mail gold, and related modules. Settings: `AltArmyTBC_SummarySettings`.
