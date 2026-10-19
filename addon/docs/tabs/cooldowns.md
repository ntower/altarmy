# Cooldowns tab

Profession cooldown overview and raid/heroic lockouts.

## Purpose

Know which crafts are ready, whether mats are on hand, mail stockpile reagents from a bank alt, and track instance lockouts.

## Settings panel

The toolbar's settings button opens a panel on the right of the tab, 40% of its width, as on the Summary, Gear and Reputation tabs. Both views narrow to the rest and scroll sideways (a bar under the list) once their columns no longer fit. Everything is saved in `AltArmyTBC_Options.cooldowns`.

- **Realm filter**: the same choices as the Summary's (this realm and faction always; this realm's other faction, other realms, linked accounts), but the tab's own. It applies to both views and to the alerts. Other realms' names carry their realm. The first filter starts from the Summary's, which the tab followed until it had its own.
- **Group characters** (on by default, Crafting only): a heading per realm and faction, this realm and faction first, as the Summary's sections. Each section is sorted by the column sort. Clicking a heading folds its section away or back (remembered in `collapsedGroups`). Folded rows aren't offered to Send Materials. Names then leave out the realm, which the heading gives.
- **Show in UI**: which cooldowns the Crafting list shows.
- **Alert when ready**: which cooldowns announce when ready (see Alerts). A cooldown hidden from the list still alerts.

Both dropdowns list one entry per cooldown, A to Z: on TBC Anniversary its crafts (Brilliant Glass, Primal Mooncloth, Shadowcloth, Spellcloth, Transmute, Void Sphere / Prismatic Sphere), without WoW Forever's Study and Dedicated Study. On TBC Anniversary a cooldown that a specialization changes has two entries, for example **Transmute (all specs)** and **Transmute (Master of Transmutation only)**; ticking one unticks the other. Unticking both turns the cooldown off. The same goes for Spellcloth (Spellfire Tailor), Shadowcloth (Shadoweave Tailor) and Primal Mooncloth (Mooncloth Tailor). On WoW Forever the dropdowns list only Dedicated Study, Mooncloth, Salt Shaker, Study and Transmute, with no specialization entries. Study reads **Study (mage)** and Dedicated Study **Dedicated Study (legacy talent)**. A dropdown's popup widens to fit its longest entry. Its button names what is ticked by the plain cooldown names: **All**, **None**, **All but** the one left out, or the ticked ones.

## Sub-views

Persisted as Crafting vs **Raids** (`AltArmyTBC_Options.cooldowns.activeView`).

You switch between them with spellbook-style tabs that hang above the panel in the toolbar row (`UI/TopTabs.lua`, Blizzard's `TabSystemTopButtonTemplate`). Hovering a tab shows its name.
- **Forever:** square icon tabs (alchemy flask for Crafting, a dungeon key for Dungeons).
- **TBC Anniversary:** classic text top tabs (`PanelTopTabButtonTemplate`), because its client doesn't load Blizzard's newer tab system.

### Crafting

Columns: recipe/category, character, mats availability, time remaining. Sortable by recipe, character, mats, and time. Live refresh while the tab is open.

Alchemy transmutes and enchanting spheres share one cooldown per group, so the list shows **one row per character** for each group. By default (**Auto**) that row uses the recipe they last crafted if they still know it, otherwise Primal Might then Arcanite (transmutes; Arcanite then Legionite on WoW Forever) or Void Sphere then Prismatic Sphere.

**Transmutes on WoW Forever** follow its game data's shared transmute cooldown: Arcanite and Legionite (47 hours), the eight elemental transmutes (23 hours), Refined Scale of Onyxia (2 hours) and Elemental Fire (10 minutes). The lockout lasts as long as the transmute cast says, and the row shows what the game reports. Iron to Gold and Mithril to Truesilver have their own 1-hour cooldowns there, outside the group, so they get no row. Mats come from a reagent list built into the addon for each of these transmutes, because Forever's recipe scan doesn't capture reagents.

Click the Recipe cell on a grouped row to pick **Auto** or a specific recipe that character knows (listed A–Z after Auto). The cell becomes a search field with Cancel (same pattern as adding a character to a guild group). Matching text in the dropdown is highlighted in green. A manual pick is saved per character and wins over last-cast until you choose Auto again. Single-recipe rows (Spellcloth, Shadowcloth, Primal Mooncloth, Brilliant Glass, Mooncloth, Salt Shaker, Research, Dedicated Study) are not pickable.

**Study (WoW Forever):** the mage-only Comprehension profession's 1-hour cooldown (the "Research" spellbook entry, crafted as **Study**), listed under its spell's name. A character gets a Study row once their Comprehension recipes have been scanned. The timer updates when you open Comprehension or cast Study. Mats, the tooltip and stockpile send use Study's reagent (1× Light Feather). That list is built into the addon, because Forever's recipe scan doesn't capture reagents.

**Dedicated Study (WoW Forever):** the Legacy talent's 23-hour cooldown (spell 1225469: +1 skill in your lowest tradeskill). A character gets a row once their Legacy talents have been scanned with it learned (`char.legacyTalents.spells`). The timer is read at login and after each cast. It needs no materials, so its row shows a gray em dash in the Mats cell, a tooltip without reagents, and no Send checkbox.

**Mooncloth (WoW Forever):** Tailoring's Mooncloth keeps its long cooldown there (95 hours; none on TBC Anniversary). A tailor who knows it gets a row. The timer updates when you open Tailoring or craft it. Mats use a built-in list (2× Felcloth).

**Salt Shaker (WoW Forever):** the Salt Shaker item's use, which turns Deeprock Salt into Refined Deeprock Salt, has a 71-hour cooldown. Any character whose last bags or bank scan holds a Salt Shaker gets a row. The timer is read from the item at login and after each use. Mats use a built-in list (1× Deeprock Salt).

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

When a cooldown becomes ready, a chat line ("Alt Army Transmute cooldown ready — Name") and a sound, once per ready cooldown until it is used again. Checked 5 seconds after login and every 30 seconds. Set per cooldown with **Alert when ready** in the settings panel, for the characters its realm filter shows; a linked account's characters never alert.

## Data source

`CooldownData`, `LockoutData`, DataStore professions / lockouts / containers / mail. Stockpile planning: `StockpilePlan`.
