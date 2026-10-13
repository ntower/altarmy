# Cooldowns tab

Profession cooldown overview and raid/heroic lockouts.

## Purpose

Know which crafts are ready, whether mats are on hand, mail stockpile reagents from a bank alt, and track instance lockouts.

## Sub-views

Persisted as Crafting vs **Raids** (`AltArmyTBC_Options.cooldowns.activeView`).

You switch between them with spellbook-style tabs that hang above the panel in the toolbar row (`UI/TopTabs.lua`, Blizzard's `TabSystemTopButtonTemplate`). Hovering a tab shows its name.
- **Forever:** square icon tabs (alchemy flask for Crafting, a dungeon key for Dungeons).
- **TBC Anniversary:** classic text top tabs (`PanelTopTabButtonTemplate`), because its client doesn't load Blizzard's newer tab system.

### Crafting

Columns: recipe/category, character, mats availability, time remaining. Sortable by recipe, character, mats, and time. Live refresh while the tab is open.

Alchemy transmutes and enchanting spheres share one cooldown per group, so the list shows **one row per character** for each group. By default (**Auto**) that row uses the recipe they last crafted if they still know it, otherwise Primal Might then Arcanite (transmutes) or Void Sphere then Prismatic Sphere.

Click the Recipe cell on a grouped row to pick **Auto** or a specific recipe that character knows (listed A–Z after Auto). The cell becomes a search field with Cancel (same pattern as adding a character to a guild group). Matching text in the dropdown is highlighted in green. A manual pick is saved per character and wins over last-cast until you choose Auto again. Single-recipe rows (Spellcloth, Shadowcloth, Primal Mooncloth, Brilliant Glass, Research, Dedicated Study) are not pickable.

**Research (WoW Forever):** the mage-only Comprehension profession's 1-hour cooldown (the "Research" spellbook entry, crafted as **Study**). A character gets a Research row once their Comprehension recipes have been scanned. The timer updates when you open Comprehension or cast Study. Mats, the tooltip and stockpile send use Study's reagent (1× Light Feather). That list is built into the addon, because Forever's recipe scan doesn't capture reagents.

**Dedicated Study (WoW Forever):** the Legacy talent's 23-hour cooldown (spell 1225469: +1 skill in your lowest tradeskill). A character gets a row once their Legacy talents have been scanned with it learned (`char.legacyTalents.spells`). The timer is read at login and after each cast. It needs no materials, so its row shows a gray em dash in the Mats cell, a tooltip without reagents, and no Send checkbox.

When no character has a tracked crafting cooldown, the table is replaced by a short centered description of the view.

Tooltips: reagent counts, craftability, character-specific material context (bags + bank + mail). Hovering any Recipe cell or a recipe in the picker shows the same recipe tooltip. The hover highlight and picker apply only to grouped rows.

**Stockpile send**

- With the mailbox open, use **Send Materials** then click rows (except the Recipe cell) to prepare mail transfer to that character (same realm).
- Computes feasible quantity from available mats; stack split/merge attachment planning.
- Feedback for missing materials, mailbox state, and send success.
- **Send-all** batch: distribute to multiple selected cooldown rows from one mailbox session.

### Raids

- Per-character heroic and raid lockouts (instance name, difficulty, time remaining / Ready).
- Sort by instance, character, or time (default: soonest reset first).
- When there are no lockouts, the table is replaced by centered text: “Your dungeon lockouts will appear here”
- Lists **active** lockouts only (no “available now / unlocked” planner yet — see [FEATURE_IDEAS.md](../FEATURE_IDEAS.md)).

## Alerts

Cooldown-ready alerts: chat, center-screen raid-warning style, or both; per-category reminder intervals; optional specialization-dependent visibility. Configured under Options → Cooldowns.

## Data source

`CooldownData`, `LockoutData`, DataStore professions / lockouts / containers / mail. Stockpile planning: `StockpilePlan`.
