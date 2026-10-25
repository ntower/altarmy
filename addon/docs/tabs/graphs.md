# Graphs tab

Multi-character leveling progress charts.

## Purpose

See time per level and cumulative played time across alts; compare characters on one plot.

## Metrics and options

- **Time per level** and **cumulative played** (dropdown).
- Multi-character comparison list with select-all, of every character (the Summary's filters don't apply), grouped by realm and faction as the Summary's sections are (by name within each, each group under a divider row naming it, "Realm — Faction", so the rows don't name the realm); characters with too little data to draw are listed greyed out under "Not enough data:" at the very end, ungrouped and without their realms.
- Zoom by drag-selecting a level range.
- Optional shrink-outliers for slow level bands; optional rolling average; logarithmic axis where relevant.

Drawing techniques (line pools, axes, hit targets): [GRAPH_RENDERING_TECHNIQUES.md](../GRAPH_RENDERING_TECHNIQUES.md). Implementation: `UI/GraphCore.lua`, `Tabs/GraphLogic.lua`, `Tabs/TabGraph.lua`.

## Level history data

- Milestones with calendar `reachedAt` and cumulative played at each level-up (`DataStoreLevelHistory` / `LevelProgressData`).
- One-time imports when addons are present: Questie, NovaInstanceTracker, RestedXP profiles.
- Orphan imports for characters not yet scanned live are stored until first login merge.

## Settings

`AltArmyTBC_GraphSettings`.

The toolbar's settings button shows and hides the right column (the options and the Compare list). Unlike other tabs it starts shown; hidden, the graph takes the whole tab. Not saved across sessions.

## Window resize

The right column (options and Compare) widens a little with the window, up to 260 px, so long names stop truncating; the plot takes the rest. The plot is drawn at the graph frame's size and redrawn on its every `OnSizeChanged`, so it follows the window's grip live while it is dragged (a trial of the rebuild's speed; `AltArmy.OnWindowResized`, called once the drag ends, is the fallback if it stutters).
