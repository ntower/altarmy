# Reputation tab

Faction × character reputation matrix.

## Purpose

See standing and progress for every tracked faction across alts; sort by faction or by character; optionally open Zygor reputation guides.

## Layout

- Rows = factions; columns = characters.
- Per-cell standing label and progress bar.
- Truncated faction names show the full name in a tooltip on hover.
- Faction name filter (in the main toolbar row, where Summary's item search sits) to reduce visible rows; matching text in faction names is highlighted green (same as other search results), including the visible part of a match cut off by "...".
- Settings panel: the character filters (Realm, Level and Class filter, Pin and Hide individual characters, see [Realm filtering](../FEATURES.md#realm-filtering-and-character-visibility); same as Gear). Saved in `AltArmyTBC_ReputationSettings`.
- Score-sort row (level / iLvl / played / gear score) for column ordering.

## Sorting

- Sort character columns by a selected faction’s value.
- Sort faction rows by a selected character’s value.
- Handles mixed/legacy reputation data and undiscovered factions.

## Integrations

- When Zygor Guides Viewer is installed, faction rows can open matching reputation guides.

## Data source

DataStore reputations (schema v2). Settings: `AltArmyTBC_ReputationSettings`.
