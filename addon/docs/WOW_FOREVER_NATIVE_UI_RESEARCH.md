# WoW Forever native UI — research

Research for a possible UI/UX rework: making AltArmy look and feel like the built-in WoW Forever client UI (window frames, buttons, tabs, lists, dropdowns). The research below is from source and web checks (2026-09-23). The rework it led to has shipped (see [Rework decisions](#rework-decisions-2026-09-23) and [Not yet done](#not-yet-done)); the current look is documented in [UI_DESIGN.md](UI_DESIGN.md) (`AltArmy_TBC/UI/Theme.lua`). Only some points have been confirmed in the live client so far, e.g. TabSystem missing on TBC. For addon-API compatibility, see [WOW_FOREVER_COMPATIBILITY_RESEARCH.md](WOW_FOREVER_COMPATIBILITY_RESEARCH.md) and [WOW_FOREVER_COMPAT.md](WOW_FOREVER_COMPAT.md).

## TL;DR

- Forever's UI code is the **retail (Mainline, Midnight-era) FrameXML** plus Forever-specific overrides. Blizzard's internal name for Forever is **"Camelot"**.
- Forever doesn't add new template names. It **reskins the retail art in place**: the same texture names (atlases) and NineSlice layouts, with Forever-drawn art and small offset fixes.
- So an addon built from **stock Blizzard templates and atlas names looks native on Forever automatically**. Hand-drawn backdrops (AltArmy today) don't.
- Nearly every template we'd use **also exists on TBC Anniversary 2.5.6**, where it draws with Classic art. AltArmy's single `.toc` (`## Interface: 20506, 16001`) can therefore look native on both clients. Only a few Forever/retail-only pieces need a fallback.

## Primary source: Blizzard's UI code

[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/branches) mirrors Blizzard's UI code per game version:

| Branch | Build (at check time) | Use |
|---|---|---|
| `forever` | 1.60.1 (69977) | WoW Forever |
| `classic_anniversary` | 2.5.6 (69795) | TBC Anniversary |

To browse locally: `git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source.git`. Grep for `name="<TemplateName>"` to find a template's XML.

### How Forever differs from retail

- Blizzard's `.toc` files (the load lists inside each Blizzard_* folder) treat Forever as a variant of retail ("mainline"). For example, `Blizzard_Minimap.toc` loads `[Game]\MinimapConstants.lua [AllowLoadGameType camelot]` next to `[Family]\MinimapConstants.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`. So files marked for "mainline" also load on Forever unless they explicitly exclude it.
- There are 48 `Camelot/` override folders, e.g. `Blizzard_SharedXML/Camelot`, `Blizzard_UIPanels_Game/Camelot` (Character, Reputation, Skills, Bank, Container frames), `Blizzard_Minimap/Camelot/Skin.lua`.
- `Blizzard_SharedXML/Camelot/NineSliceLayoutOverrides.lua` says it outright: *"the art made for Camelot doesn't match the exact size of the Mainline Standard art and needs to be offset differently."* It patches corner offsets of `UI-Frame-Metal-*` pieces in every `NineSliceLayouts` entry. Anything using those layouts (`ButtonFrameTemplate`, `PortraitFrameTemplate`, …) inherits the fix.
- `Blizzard_SharedXML/Camelot/SharedUIPanelTemplates.lua` re-anchors `UIPanelCloseButtonDefaultAnchors` and side-tab icon offsets for the Camelot art.
- Forever-only template: `ColoredProgressBarTemplate` (`Blizzard_SharedXML/Camelot/ProgressBars/`). It uses the `common-stat-bar-BG` / `common-stat-bar-white` / `common-stat-bar-Mask` atlases.

**Implication:** reference art through `SetAtlas("<atlas name>")` and inherit templates. Don't ship BLP files or hard-code texture file paths, or the Forever reskin gets bypassed.

## Template / API availability

Checked by grepping both branches for the template definition. **Caveat:** a template file existing in a branch doesn't mean the client loads it. Also check the branch's `.toc` (see Modern tab bar), or check `NativeUI.GetCaps()` in-game.

| Element | Template / API | Forever | TBC 2.5.6 | Notes |
|---|---|---|---|---|
| Main window | `ButtonFrameTemplate`, `PortraitFrameTemplate`, `PortraitFrameFlatTemplate`, `PortraitFrameBaseTemplate` | ✅ | ✅ | `ButtonFrameTemplate_HidePortrait(frame)` for no portrait |
| Plain panel | `DefaultPanelTemplate`, `DefaultPanelFlatTemplate` | ✅ | ✅ | |
| Inset content area | `InsetFrameTemplate` | ✅ | ✅ | |
| Close button | `UIPanelCloseButton`, `UIPanelCloseButtonDefaultAnchors` | ✅ | ✅ | Forever re-anchors it for its art |
| Bottom / top tabs | `PanelTabButtonTemplate`, `PanelTopTabButtonTemplate` + `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab` | ✅ | ✅ | Classic-style tab strip |
| Modern tab bar | `TabSystemTemplate`, `TabSystemButtonTemplate` | ✅ | ❌ | Dragonflight-style tab system (used in retail's newer windows). The TBC source tree ships the files, but `Blizzard_SharedXML_TBC.toc` doesn't load them (Wrath / Cata / Mists do). This was confirmed in-game. |
| Side tabs | `LargeSideTabButtonTemplate` | ✅ | ❌ | Used by Forever's CharacterFrame |
| Scrolling lists | `WowScrollBoxList` + `MinimalScrollBar` / `WowTrimScrollBar`; `CreateDataProvider`, `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar` | ✅ | ✅ | Replaces hand-rolled row pooling |
| Dropdowns | `WowStyle1DropdownTemplate`, `WowStyle1FilterDropdownTemplate` (`DropdownButton` + `SetupMenu`) | ✅ | ✅ | |
| Context menus | `MenuUtil.CreateContextMenu`, `MenuUtil.CreateButtonMenu` | ✅ | ✅ | Replaces `UIDropDownMenu_*` |
| Search box | `SearchBoxTemplate` | ✅ | ✅ | |
| Buttons | `UIPanelButtonTemplate`, `UIPanelDynamicResizeButtonTemplate`, `SharedButtonSmallTemplate`, `SharedGoldRedButtonSmallTemplate` | ✅ | ✅ | |
| Checkbox | `UICheckButtonTemplate`, `SettingsCheckboxTemplate` | ✅ | ✅ | |
| Slider | `MinimalSliderWithSteppersTemplate` | ✅ | ✅ | |
| Column headers | `ColumnDisplayTemplate` | ✅ | ✅ | |
| Layout helpers | `VerticalLayoutFrame`, `ResizeLayoutFrame` | ✅ | ✅ | |
| Progress bar (Forever art) | `ColoredProgressBarTemplate` | ✅ | ❌ | Forever-only; needs a fallback |
| Options UI | `Settings.RegisterVerticalLayoutCategory` (native controls), `Settings.RegisterCanvasLayoutCategory` (custom canvas) | ✅ | ✅ | AltArmy already uses Canvas |
| Addon compartment | `AddonCompartmentFrame`; `.toc` `## AddonCompartmentFunc` | ✅ | ❌ | Loads for mainline, so it's on Forever; keep LibDBIcon for TBC |

## Blizzard's own Forever windows as references

These are the closest models for AltArmy's tabs, and they're built only from the templates above:

- **`Blizzard_UIPanels_Game/Camelot/ReputationFrame.xml`**: `WowScrollBoxList` + `MinimalScrollBar` list, `WowStyle1DropdownTemplate` filter, `ColoredProgressBarTemplate` bars, `SharedGoldRedButtonSmallTemplate` button, `CallbackRegistrantTemplate`. A direct model for the Reputation tab.
- **`Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml`**: `PortraitFrameBaseTemplate` shell, `UIPanelCloseButtonDefaultAnchors`, `LargeSideTabButtonTemplate` side tabs, stat categories in a ScrollBox (`CharacterStatsPaneScrollBoxTemplate`), `VerticalLayoutFrame`. A model for Gear / Summary layouts.
- **`Blizzard_UIPanels_Game/Camelot/SkillsFrame.xml`**: `SkillsEntryTemplate` / `SkillsBarTemplate` rows. A model for profession rows.
- **`Blizzard_Menu/11_0_0_MenuImplementationGuide.lua`**: Blizzard's own worked examples for the Menu system.

## What the community is doing

- Most Forever UI addons so far go the **other direction**, putting Classic art back over what players call Forever's "modern flat and unadorned frames": [ClassicUI Forever](https://www.curseforge.com/wow/addons/classicui-forever), [standujar/forever-classic-ui](https://github.com/standujar/forever-classic-ui) (partial skins of 16 windows; restores Classic Era BLPs; hooks into Edit Mode), [Classic UI for Forever](https://www.curseforge.com/wow/addons/classic-ui-for-forever). Forever's Layout menu also ships "Modern" and "Classic" presets ([wowhead](https://www.wowhead.com/forever/news/updated-character-panel-ui-in-wow-forever-explains-stats-in-detail-383013), [warcrafttavern](https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/)).
  - This supports using stock templates: AltArmy then follows the player's chosen look (and any reskin addon that targets Blizzard templates) instead of forcing its own.
- Cross-version addons already on Forever that build on Blizzard's modern toolkit: Auctionator and Baganator/Syndicator (plusmouse). Baganator ships a default "Blizzard" skin alongside ElvUI / GW2 skins ([Patreon post](https://www.patreon.com/posts/skins-for-105871197), [CurseForge](https://www.curseforge.com/wow/addons/baganator)). Its source repo wasn't publicly clonable at check time.
- [Royaleint/Foundry](https://github.com/Royaleint/Foundry) (MIT) wraps the Settings API, Menu system, ScrollBox and tooltip hooks with less boilerplate. It doesn't provide window frames, tabs or buttons, and doesn't document which game versions it supports.
- [DragonUI PR #459](https://github.com/NeticSoul/DragonUI/pull/459) is a worked example of applying `PortraitFrameTemplate` and `InsetFrameTemplate` NineSlice chrome to a custom frame. Gotcha: stripping textures only reaches the frame's own regions and `NineSlice`, not child frames like `CloseButton` / `PortraitContainer`.

## Implications for an AltArmy rework

- **Theme.lua is the seam.** Tabs already go through `Theme.CreatePanel`, `Theme.SkinButton`, `Theme.SetupScrollBar`, `Theme.CreateTabContentPanel`, etc. A "native" mode can swap what those helpers build (inherit templates instead of `BackdropTemplate` + palette) without rewriting each tab first.
- **Dropdowns:** `UIDropDownMenu_*` (used today) is kept only for backward compatibility on the retail-based client and is otherwise deprecated ([Patch 11.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_11.0.0/API_changes)). Move to `WowStyle1DropdownTemplate` / `MenuUtil` ([Menu implementation guide](https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide)), which works on both clients.
- **Lists:** ScrollBox + DataProvider replaces custom scroll frames and row pools. It also shifts per-row locals out of the large `Tabs/Tab*.lua` main chunks, which helps with the Lua 5.1 200-local limit (see [CLAUDE.md](../CLAUDE.md)).
- **Forever-only pieces:** check before use, e.g. `if C_XMLUtil.GetTemplateInfo("ColoredProgressBarTemplate") then … end` (or `pcall` around `CreateFrame`), and fall back on TBC. Same for the addon compartment vs LibDBIcon.
- **Art:** use `SetAtlas` names, never bundled textures. Treat custom palette colors as an accent, not the frame chrome.
- **Resolved:** whether to keep the dark/bronze theme as an option (like Baganator's skins). We went fully native with no toggle (see below). Still unchecked: how the reskin addons above treat third-party windows built from Blizzard templates.

## Rework decisions (2026-09-23)

The rework goes **fully native**: the dark/bronze theme is removed, with no toggle.

- **Shell:** `PortraitFrameTemplate`, which provides:
  - the tiled `UI-Background-Rock` background and the NineSlice border
  - the close button
  - the portrait circle, which shows the active tab's icon (`SetPortraitToAsset`), and the title (`SetTitle`)
- **Size:** 670 × 484. The height matches Forever's `CHARACTER_FRAME_HEIGHT` (`Blizzard_UIPanels_Game/Camelot/CharacterFrameConstants.lua`, 631 × 484).
- **Main tabs:** icon flyouts on the right edge, anchored like CharacterFrame's `ModeTabs` (`TOPLEFT` → frame `TOPRIGHT`, y −30). Hovering a tab shows its name in a tooltip.
  - Forever: `LargeSideTabButtonTemplate`, which draws the `common-sidetab*` atlases.
  - TBC Anniversary has neither the template nor the atlases, so it falls back to the classic spellbook skill-line tab art.
- **Sub-view tabs** (Cooldowns, Gear): `UI/TopTabs.lua`, spellbook-style tabs hanging from the panel top.
  - Forever: `TabSystemTemplate` + `TabSystemTopButtonTemplate` square icon tabs.
  - TBC Anniversary doesn't load TabSystem, so it uses classic text tabs (`PanelTopTabButtonTemplate` + `PanelTemplates_SelectTab`).
- **Toolbar row** under the title bar holds:
  - the `SearchBoxTemplate` global search
  - the active tab's settings button
  - the search-mode category checkboxes
- **Controls:** the `Theme.lua` helpers are rewritten behind their current signatures:
  - vertical scroll bars: real `MinimalScrollBar` frames bound with `ScrollUtil.InitScrollFrameWithScrollBar` (`Theme.CreateVerticalScrollBinding` / `CreateVerticalScrollViewport`)
  - horizontal scroll bars: still our own Slider painted with the `MinimalScrollBar` atlases rotated 90°, because there is no horizontal Minimal template (only the unskinned `HorizontalScrollBarTemplate`)
  - Search results: a virtualized `WowScrollBoxList` + `CreateDataProvider` (see [Scroll containers and virtualization](#scroll-containers-and-virtualization))
  - dropdowns: `WowStyle1FilterDropdownTemplate` for the search Filter; the rest are drawn with the `WowStyle1DropdownTemplate` atlases (see [Not yet done](#not-yet-done))
  - checkboxes: `UICheckButtonTemplate`
  - text inputs: `InputBoxTemplate` / `SearchBoxTemplate`
  - buttons: `UIPanelButtonTemplate`
  - panels: `InsetFrameTemplate`
  - collapsible sections (Options → General, `Theme.CreateCollapsibleSection`): modelled on the Settings panel's own expandable section, `SettingsExpandableSectionTemplate` (Blizzard_Settings_Shared, used by the Keybindings page; present on Forever and TBC Anniversary). We draw its art, the `Options_ListExpand_Left` / `_Options_ListExpand_Middle` / `Options_ListExpand_Right` (`_Right_Expanded` when open) atlases, and follow its structure: one frame holding the header and its controls, its height worked out from the controls' fixed heights (as `GetExtent` does) rather than measured. Under the mouse the bar's atlases are drawn again in the HIGHLIGHT layer (ADD blend, 35% alpha) and the label turns from gold to white. The template itself can't be used on a canvas page: it is abstract (`OnExpandedChanged`, `GetExtent` must be implemented) and reads its state from the Settings list's ScrollBox through `GetElementData`, so it only works inside a vertical-layout category. The profession list's `ListHeaderVisualTemplate` is a different, list-row style and is missing on TBC Anniversary
- **Fonts:** a role → Blizzard font object map, taken from Forever's CharacterFrame / ReputationFrame usage.
- **Capability layer:** `AltArmy_TBC/UI/NativeUI.lua` (`HasTemplate`, `HasAtlas`, `GetCaps`) chooses between a template and its fallback.

## Scroll containers and virtualization

Two kinds of built-in scroll container are used. Both ship in `Blizzard_SharedXML_TBC.toc`, so they work the same on TBC Anniversary and Forever (`NativeUI` caps `minimalScrollBar` and `scrollBoxList`).

- **ScrollFrame + `MinimalScrollBar`:** used by every tab except Search, and by the options lists. `ScrollUtil.InitScrollFrameWithScrollBar` wires the bar.
  - It *replaces* (`SetScript`) the ScrollFrame's `OnVerticalScroll`, `OnScrollRangeChanged` and `OnMouseWheel` scripts. Code that runs on scroll registers with the binding's `onScroll` / `AddOnScroll` instead. That is a bar `OnScroll` callback, and it fires once per offset change from any source (wheel, drag, arrows, code).
  - Nested ScrollFrames (Summary, Search) may not fire `OnScrollRangeChanged`, so `UpdateRange()` runs ScrollUtil's range handler by hand.
- **`WowScrollBoxList` + DataProvider:** used by Search. It is virtualized. Only elements in view get frames, and a frame whose element stays in view is not re-initialized while scrolling. That replaced our own `VirtualList` row pool. Differences from the old pool:
  - No buffer rows. Rows are acquired synchronously as they scroll in, so none are left blank.
  - Frame pools are keyed by template, so each row kind has its own empty template in `UI/ScrollRows.xml`. The children are still built in Lua.
  - It has no sticky headers, no multi-row overlays and no 2D scroll. Search keeps its sticky section headers as overlays, which follow `GetDerivedScrollOffset()` on `OnScroll`. The headers have no background, so the page background shows through. The list box starts below the first header's block and leaves that spacer out, so rows never scroll underneath a pinned header. The Total column's group overlays are re-anchored on `OnDataRangeChanged`. Horizontal scroll is still an outer ScrollFrame.
  - `Update()` fires `OnScroll` *before* it runs the row initializers, then `OnDataRangeChanged`, then `OnUpdate`. So decorations that depend on filled frames go in `OnDataRangeChanged`.
- Summary also culls rows to the viewport, but faux-scroll style: a fixed row pool on the ScrollFrame, with the offset choosing the first row. The native bar only changed where that offset comes from.

## Not yet done

These are left over from the implications above and are deferred (all three still open as of 2026-10-20):

- **Native horizontal scroll bars:** an XML template inheriting `HorizontalScrollBarTemplate` with the `MinimalScrollBar` children would drop `Theme.CreateHorizontalScrollBar`'s manual drag math.
- **Addon compartment:** add `AddonCompartmentFrame` / `## AddonCompartmentFunc` on Forever, keeping LibDBIcon for TBC.
- **Real dropdowns:** `Theme.CreateSingleSelectDropdown`, `Theme.CreateMultiSelectCheckboxDropdown` and the Gear / `ScoreSortRow` provider lists are our own buttons painted with the `WowStyle1DropdownTemplate` / `MenuStyle1` atlases. Only `Theme.CreateFilterDropdown` uses the real template + `MenuUtil`. Switching the rest would let reskin addons pick them up.

Tried and dropped: Reputation-tab bars on `ColoredProgressBarTemplate` (Forever stat-bar art). We preferred the existing flat bars, so they stay.

## Sources

- [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) — `forever` and `classic_anniversary` branches (cloned and grepped 2026-09-23)
- [ClassicUI Forever](https://www.curseforge.com/wow/addons/classicui-forever), [Classic UI for Forever](https://www.curseforge.com/wow/addons/classic-ui-for-forever), [standujar/forever-classic-ui](https://github.com/standujar/forever-classic-ui)
- [Warcraft Tavern: ClassicUI Forever](https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/)
- [Wowhead: Forever character panel](https://www.wowhead.com/forever/news/updated-character-panel-ui-in-wow-forever-explains-stats-in-detail-383013)
- [WoW Forever addons guide](https://wowforevergame.wiki/classic-plus/wow-forever-addons-guide/) (interface 16001, shared 12.1.5 API set)
- [Warcraft Wiki: Patch 11.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_11.0.0/API_changes), [Blizzard Menu implementation guide](https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide), [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment)
- [Royaleint/Foundry](https://github.com/Royaleint/Foundry)
- [Baganator](https://www.curseforge.com/wow/addons/baganator), [Skins for Baganator](https://www.patreon.com/posts/skins-for-105871197)
- [NeticSoul/DragonUI PR #459](https://github.com/NeticSoul/DragonUI/pull/459)
