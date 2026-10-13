# Gear tab

Equipment grid across characters, plus item-check, compare, and upgrade workflows.

## Purpose

Compare what each alt is wearing; drop an item to see who can use it and how it scores against equipped gear; get upgrade alerts in the world.

## Layout

Two sub-views, switched with spellbook-style tabs that hang above the panel in the toolbar row
(`UI/TopTabs.lua`, same as Cooldowns). Hovering a tab shows its name.
- **Forever:** square icon tabs: a gold 2×2 grid for **Grid** and gold balance scales for **Upgrade Check**. These are bundled art (`Textures/Icons/GearView*.tga`), made by `scripts/generate-gear-view-icons.py`, because the game has no fitting grid or scales icon.
- **TBC Anniversary:** classic text top tabs.

**Grid** — rows = equipment slots; columns = characters. Side settings for sort, pin/hide, icon
size, and spacing.

Both views (and the compare panel) list only characters of the logged-in character's faction —
opposite-faction alts can't receive gear by mail. Characters with no recorded faction (not
logged in since faction was first captured) are still shown.

**Upgrade Check** — the item-check drop prompt, then the compare panel once an item is focused.
Choosing the tab while holding an item on the cursor checks that item immediately. The same happens when you click the main window's **Gear** side tab while holding an item: it switches to Upgrade Check and loads that item, replacing any item already focused. Clicking the minimap button while holding an item (window closed) opens the window straight into this view with the item loaded. Focusing an item
from elsewhere (loot / quest alerts, links) switches to this tab; right-clicking the focused item
clears it back to the drop prompt. Choosing **Grid** clears the focused item. Hiding the tab while
still on the drop prompt returns to Grid; a focused item stays in Upgrade Check.

## Grid

- Hover tooltips on equipped items; shift-click inserts item links into chat.
- Character ordering: primary/secondary sort, show self first, pin/hide.
- Appearance: icon size (small/medium/large), spacing (compact/normal/comfortable).
- Score-sort row: sort columns by character level, average item level, time played, or gear score (TacoTip / GearScoreTBCClassic when loaded).

## Item check (“who can use this”)

- Drag/drop (or focus) an item to rank characters by likely usability.
- Headers show class / equip / level fit hints.

## Compare panel

- Select a character column (and slot) while an item is focused.
- When a character is auto-selected (or its column clicked), the compare slot is the one with the
  best upgrade. One-hand weapons consider both hands for dual-wield classes, so a one-hander that
  only beats the off-hand opens against the off-hand — matching quest reward / loot alerts.
- Stat delta rows vs equipped piece; dual-wield offhand DPS is scaled to match upgrade scoring.
- All six resistance schools collapse into a single "All Resistances" row when their values match.
- Situational/conditional bonuses (e.g. "Increases X in \<condition\>") are grouped under a header
  row naming the condition, with their stats listed underneath; excluded from the weighted
  score for now.
- Warning lines under the verdict (soulbound, level, proficiency, spec assumptions, different
  server) are red for hard blockers and yellow for cautions. A character on another realm gets a
  red "*Name* is on a different server" line ("ruleset" on WoW Forever). The verdict and warnings
  show only the character's class-colored first name (WoW Forever names are "First Last");
  hovering the name shows the full name, plus " — Realm" when the realm filter shows all realms.
- Loot / quest upgrade alerts only consider characters on the current realm and of the current faction.
- Debug Dump button when `/altarmy debug on` — see [COMPARE_PANEL_DEBUG_DUMP.md](../COMPARE_PANEL_DEBUG_DUMP.md).

## Upgrade scoring and alerts

- Built-in spec scales (Pawn-style weights) for “is this an upgrade?” WoW Forever uses its own scale table (hit and crit merged into single stats, since Forever has no separate spell/physical version of either) rather than TBC's.
- Optional gear-score providers for scoring and missing-data hints.
- Chat alerts (clickable) for loot, Need/Greed rolls, quest rewards, and level-up upgrades for the current character and/or alts.
- Loot / roll alerts announce a given item at most once per 60 seconds (e.g. crafting a stack of the same item alerts once). The window is in-memory only and resets on reload/logout.
- Quest reward overlays on turn-in and quest log (upgrade vs vendor).
- Toggles live under Options → AddOns → AltArmy → **Gear**.

## Data source

DataStore equipment, containers (for usability context), talents (spec warnings), gear score modules. Settings: `AltArmyTBC_GearSettings`. Options: [options.md](options.md).
