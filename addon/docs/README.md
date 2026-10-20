# AltArmy documentation

Product and engineering docs for the AltArmy addon (WoW: Forever first; TBC Anniversary supported).

## Maintaining these docs

When you change **user-visible** behavior, update the matching docs in the **same task**. See [CLAUDE.md](../CLAUDE.md) for the code → doc mapping. Significant features only — skip debug-only slash commands, placeholders, and pixel-level UI tweaks.

## Product docs

| Doc                                  | Purpose                                                                                                   |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| [FEATURES.md](FEATURES.md)           | Shipped feature catalog (start here for “what does it do?”)                                               |
| [FEATURE_IDEAS.md](FEATURE_IDEAS.md) | Roadmap: unbuilt and partial ideas                                                                        |
| [ARCHITECTURE.md](ARCHITECTURE.md)   | High-level structure, tabs, SavedVariables, DataStore                                                     |
| [tabs/](tabs/)                       | Per-tab detail (Summary, Economy, Gear, Inventory, Reputation, Cooldowns, Search, Graphs, Guild, Options) |

## Design and engineering

| Doc                                                                            | Purpose                                                                                                      |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| [UI_DESIGN.md](UI_DESIGN.md)                                                   | Theme palette and shared UI conventions                                                                      |
| [GRAPH_RENDERING_TECHNIQUES.md](GRAPH_RENDERING_TECHNIQUES.md)                 | How the Graphs tab draws lines/axes (WoW widget techniques)                                                  |
| [COMPARE_PANEL_DEBUG_DUMP.md](COMPARE_PANEL_DEBUG_DUMP.md)                     | Gear compare Dump button / SavedVariables debugging                                                          |
| [DEV_DUMPS.md](DEV_DUMPS.md)                                                   | `AltArmy.Debug.Dump` — general-purpose live-client debug capture into SavedVariables                         |
| [GOLD_ECONOMY_HISTORY_RESEARCH.md](GOLD_ECONOMY_HISTORY_RESEARCH.md)           | Research for a possible gold-history feature                                                                 |
| [WOW_FOREVER_COMPATIBILITY_RESEARCH.md](WOW_FOREVER_COMPATIBILITY_RESEARCH.md) | Log of the addon's WoW Forever compatibility work, from the research ahead of its beta to what is still open |
| [WOW_FOREVER_COMPAT.md](WOW_FOREVER_COMPAT.md)                                 | Audit: do the optional third-party addon integrations still work on WoW Forever                              |
| [WOW_FOREVER_NATIVE_UI_RESEARCH.md](WOW_FOREVER_NATIVE_UI_RESEARCH.md)         | Research: matching Forever's built-in UI look via Blizzard templates/atlases (TBC + Forever availability)    |
| [REFACTORING_OPPORTUNITIES.md](REFACTORING_OPPORTUNITIES.md)                   | Code-review snapshot of remaining refactors                                                                  |

## Data layer (next to code)

| Doc                                                                          | Purpose                                  |
| ---------------------------------------------------------------------------- | ---------------------------------------- |
| [../AltArmy_TBC/Data/DESIGN.md](../AltArmy_TBC/Data/DESIGN.md)               | Data folder layout, layering, namespaces |
| [../AltArmy_TBC/Data/DATA_VERSIONS.md](../AltArmy_TBC/Data/DATA_VERSIONS.md) | SavedVariables module version changelog  |

## Root tooling docs

- [../TESTING.md](../TESTING.md) — Busted unit tests
- [../LINTING.md](../LINTING.md) — Luacheck + Lua 5.1 compile pass
