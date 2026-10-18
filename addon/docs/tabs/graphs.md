# Graphs tab

Multi-character leveling progress charts.

## Purpose

See time per level and cumulative played time across alts; compare characters on one plot.

## Metrics and options

- **Time per level** and **cumulative played** (dropdown).
- Multi-character comparison list with select-all.
- Zoom by drag-selecting a level range.
- Optional shrink-outliers for slow level bands; optional rolling average; logarithmic axis where relevant.

Drawing techniques (line pools, axes, hit targets): [GRAPH_RENDERING_TECHNIQUES.md](../GRAPH_RENDERING_TECHNIQUES.md). Implementation: `UI/GraphCore.lua`, `Tabs/GraphLogic.lua`, `Tabs/TabGraph.lua`.

## Level history data

- Milestones with calendar `reachedAt` and cumulative played at each level-up (`DataStoreLevelHistory` / `LevelProgressData`).
- One-time imports when addons are present: Questie, NovaInstanceTracker, RestedXP profiles.
- Orphan imports for characters not yet scanned live are stored until first login merge.

## Settings

`AltArmyTBC_GraphSettings`. Respects the global realm filter.

## Window resize

The plot is drawn at the graph frame's size and redrawn on its every `OnSizeChanged`, so it follows the window's grip live while it is dragged (a trial of the rebuild's speed; `AltArmy.OnWindowResized`, called once the drag ends, is the fallback if it stutters).
