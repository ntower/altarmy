# Search tab

Toolbar Search mode: find items and recipes across characters (and optionally guildmates).

## Purpose

Locate items in bags, bank, and mail snapshots; find known recipes; filter recipes by required skill, difficulty and source.

## Access

- The toolbar search box is shown on the Summary tab (and stays while in Search mode); typing switches into Search mode.
- There is no side tab for Search. In Search mode the tab the search started from (Summary) stays highlighted, and clicking any side tab clears the query and leaves Search. Closing Search settings with an empty search box also returns to that tab.
- A native **Filter** dropdown (the Professions-window style) appears left of the search box once it has at least one character; the search box keeps a fixed width. Its menu has **Items**, **Recipes** and **Guild recipes** checkboxes (Guild recipes only when a character on the realm is in a guild; greyed out while Recipes is off), then **Advanced** (silver gear icon), which opens the Search settings side panel. The toolbar settings button also opens Search settings and is highlighted while recipe filters are active ("Filters Active", shown left of the Filter button).

## Results

- Categories: Items, Recipes (toggles).
- Virtualized list for large result sets.
- Item rows: grouped with aggregate totals; location suffixes (Bags / Bank / Mail / equipped / keyring).
- Delayed “You may also be interested in” section (broader text / tooltip-aware matching).
- Shift-click: item links; recipe/spell links when available.

## Settings

- Realm filter guidance (respects the Summary tab's realm filter).
- Recipe filters (built-in recipe data): required skill range, difficulty bands, and sources (trainer, vendor, quest, drop, reputation, starter). A recipe with several sources stays while any of them is enabled.
- Guildmates' recipes merged into recipe results, whether shared through the addon or (on WoW Forever) read from the server while they are online (`GuildLinkRead`), and whatever the player's own sharing setting; presence / whisper helpers.
- Specialist yield-bonus markers (alchemy / cloth).

## Data source

Search index/engine over DataStore containers, mail, professions/recipes; guild recipes via guild-share receive store. Recipe skill, difficulty and source come from the built-in recipe data (`Data/Recipes`, see `AltArmy_TBC/Data/DESIGN.md`). Settings: `AltArmyTBC_SearchSettings`.
