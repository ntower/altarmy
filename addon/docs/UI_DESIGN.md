# AltArmy UI Design System

AltArmy looks like a built-in Blizzard window. It uses the same templates, texture files and atlases as the stock UI.

This matters on WoW Forever, which reskins those assets in place: reusing them means AltArmy follows Forever's art, the player's Classic/Modern layout choice, and any reskin addon that targets Blizzard templates. On TBC Anniversary the same names draw the Classic art.

Background research is in [WOW_FOREVER_NATIVE_UI_RESEARCH.md](WOW_FOREVER_NATIVE_UI_RESEARCH.md).

## Single source of truth

- **`AltArmy_TBC/UI/Theme.lua`:** every panel, button, scrollbar, checkbox, dropdown, input and row hover goes through a `Theme.*` helper. Tab files must not copy-paste chrome.
- **`AltArmy_TBC/UI/NativeUI.lua`:** detects which Blizzard templates and atlases the client has (`NativeUI.GetCaps()`). Each helper checks the relevant capability and falls back to the legacy flat theme (see [Legacy fallback](#legacy-fallback)) when it's missing.

## Main window

| Piece | Implementation |
|-------|----------------|
| Shell | `PortraitFrameTemplate`, 670 × 484 (Forever's `CHARACTER_FRAME_HEIGHT`). A bottom-right resize grip (the chat window's `UI-ChatIM-SizeGrabber` art) is built but off unless the Debug options' **Window resize** is on (`/altarmy debug resize on`). Provides the rock background, NineSlice border, close button, portrait circle and title bar. |
| Title / portrait | `SetTitle("Alt Army - <Tab>")` and `SetPortraitToAsset(icon)` on every tab switch. Both come from `UI/MainTabs.lua`. |
| Tabs | `UI/SideTabs.lua`: icon flyouts anchored like CharacterFrame's mode tabs. Forever uses `LargeSideTabButtonTemplate`; TBC uses spellbook skill-line tab art. On Forever, Reputation and Graphs use CharacterFrame's own Reputation / Statistics side-tab icons (`INV_SideTab_*_c60`). Guild shows the player's guild crest (`UI/GuildCrest.lua`), falling back to the tabard icon. |
| Sub-view tabs | `UI/TopTabs.lua`: spellbook-style tabs hanging from a panel top into the toolbar row Forever uses `TabSystemTemplate` + `TabSystemTopButtonTemplate` square icon tabs, added without an icon and dressed up by `TopTabs.lua` itself (`TopTabs.SQUARE`: the spellbook tab atlases and width), because Blizzard's `SetSquareMode` writes a tab-spacing variable shared by every tab system and tainted from an addon (see [ARCHITECTURE.md](ARCHITECTURE.md#blizzards-code-and-taint)). TBC doesn't load TabSystem, so it uses classic text top tabs (`PanelTopTabButtonTemplate` + `PanelTemplates_SelectTab`). Anchor the tab row's BOTTOMLEFT at the tab frame's TOPLEFT + `AltArmy.MainToolbarInsetX`. Economy's Currency sub-view uses CharacterFrame's Currency side-tab icon (`Interface\Icons\INV_SideTab_Currency_c60`); Economy is Forever-only, so it needs no bundled copy. |
| Toolbar | A row under the title bar, right of the portrait: a search slot (Summary's item search, or the Reputation / Guild tab's own filter; Inventory's character picker and layout dropdown sit at its right end), the active tab's settings button, and the search-mode Filter dropdown. |

## Helper → native art

| Helper | Native result | Capability |
|--------|---------------|------------|
| `ApplyBackdrop(f, "section" \| "graph")`, `CreatePanel`, `CreateTabContentPanel` | `InsetFrameTemplate` NineSlice layout drawn onto the frame at BORDER, over a tiled `UI-Background-Marble` | `nineSlice` |
| `ApplyBackdrop(f, "content")`, `CreateMainContentPanel` | Tiled `UI-Background-Marble` only, no border — every main-window tab's page panels (including the Gear and Graphs sub-sections), so the portrait window's border is the single outline. Small controls (item drop wells, settings popouts) and dialog bodies still use `section`. | `nineSlice` |
| `ApplyBackdrop(f, "window" \| "dialog")` | `Dialog` NineSlice layout over a tiled `UI-DialogBox-Background-Dark` | `nineSlice` |
| `ApplyBackdrop(f, "tooltip")` | `TooltipDefaultLayout` with the GameTooltip center tint | `nineSlice` |
| `SkinButton`, `SkinDangerButton` | `UIPanelButtonTemplate` art (the `UI-Panel-Button-Up/Down/Disabled/Highlight` slices). Template buttons keep their own art; plain buttons get it drawn on. Toggles use `LockHighlight`. Danger buttons use red label text. | `nineSlice` |
| `CreateVerticalScrollBinding`, `CreateVerticalScrollViewport`, `AnchorVerticalScrollBar` | A real `MinimalScrollBar` bound to the ScrollFrame by `ScrollUtil.InitScrollFrameWithScrollBar`. It hides itself when nothing overflows. Callers use the binding API (`GetOffset`, `SetOffset`, `UpdateRange`, `Wheel`, `AddOnScroll`, `SetAllowShow`), never the bar or the ScrollFrame's scroll scripts. | `minimalScrollBar` |
| `SetupScrollBar`, `CreateHorizontalScrollBar` | Horizontal bars: `MinimalScrollBar` art rotated 90° and drawn on our Slider, with arrow steppers at each end (there is no native horizontal Minimal template). Like the native bar, an arrow is grayed out (desaturated) and does nothing while the bar is already at that end, or when there is nothing to scroll. | `minimalScrollBar` |
| Search results list | `WowScrollBoxList` + `CreateDataProvider` + `MinimalScrollBar`. Virtualized by Blizzard's list view. Row pools come from `UI/ScrollRows.xml`. | `scrollBoxList` |
| `CreateThemeCheckbox`, `CreateLabeledCheckbox` | `UICheckButtonTemplate`, grown by `NATIVE_CHECKBOX_PAD` (4px) because the art has transparent padding | `checkButton` |
| `CreateSingleSelectDropdown`, `CreateMultiSelectCheckboxDropdown`, `SkinDropdownButton`, `SkinDropdownPopup` | `WowStyle1DropdownTemplate` / `MenuStyle1` art: text holder, arrow and menu background. The selected row gets a radio check. Forever uses the mainline atlases, TBC the `-classic-` ones (preferred by `WOW_PROJECT_ID`, falling back to whichever family the client has, since Forever reports project 18, not mainline). Popups reserve the native menu insets (`GetDropdownPopupInsets`; rows × height + top + bottom). | `wowStyleDropdown` |
| `CreateFilterDropdown` | The real `WowStyle1FilterDropdownTemplate` ("Filter" button, as in the Professions window) driven by `SetupMenu` / Blizzard_Menu checkboxes, dividers and buttons. Without the template: a skinned trigger and a popup rebuilt from the same entries. Used by the Search-mode toolbar. | `filterDropdown` |
| `ApplyInputTextures` | `InputBoxTemplate` border (`common-search-border-left/middle/right`) | `inputBox` |
| `CreateSearchBox` | `SearchBoxTemplate`, with a built-in magnifier, clear button and `Instructions` placeholder. Without the template, the fallback box draws the same pieces: magnifier, placeholder, and a clear (x) button inside the right edge that shows only while there is text. Hook its scripts with `HookScript`. Every search box (items/recipes, Reputation faction filter, Guild character and recipe searches) uses it so they look and behave the same. | `searchBox` |
| `InstallHoverTint`, `BindInteractableHover` | Additive `UI-QuestTitleHighlight` list glow | `nineSlice` |
| `StyleGridHeader`, `ApplyGridLabelColumnBackground` | Tiled inset background, so pinned headers stay opaque over scrolling rows | `nineSlice` |
| Pinned scroll fades | Neutral shadow (`NATIVE_SCROLL_SHADOW`) | `nineSlice` |
| `ItemSlotButton.Create` (`UI/ItemSlotButton.lua`) | `ItemButtonTemplate`'s pieces drawn by hand: `UI-Quickslot2` slot art, `WhiteIconFrame` quality border, `NumberFontNormal` count; the empty well is retail's `bags-item-slot64` atlas, else the classic `UI-Backpack-EmptySlot` texture | `bagSlotAtlas` |

Rules:
- **Use atlases and texture paths, never bundled art, for chrome.** The textures under `AltArmy_TBC/Textures/` are for content, such as the compare arrow and quest reward markers.
  - `Textures/Economy/SupplyChain*.tga` are alt-army.com screenshots for the Economy tab's Supply Chain carousel, at native size. To replace them: `python scripts/convert-economy-screenshots.py [--src <folder with the PNGs>]` (requires Pillow), then update `IMAGES` in `Tabs/TabEconomySupplyChain.lua` if a size changed.
  - **One exception:** `Textures/Icons/INV_SideTab_Reputation2_c60.blp` and `INV_SideTab_Stats_c60.blp` are byte-identical copies of Forever's CharacterFrame side-tab icons (fileDataIDs 8197103 / 8197104).
  - Only TBC Anniversary uses them, because those files don't exist in its game data. Forever keeps loading its own copies from `Interface\Icons`.
  - To re-extract them after a game update, with a local Forever install: `python scripts/extract-casc-files.py wow_classic_beta <outdir> interface/icons/inv_sidetab_reputation2_c60.blp interface/icons/inv_sidetab_stats_c60.blp`. The script is a read-only reader of the local CASC storage.
  - **Second exception:** `Textures/Icons/GearViewGrid.tga` and `GearViewUpgradeCheck.tga` are the Gear tab's Grid / Upgrade Check sub-view tab icons. They're drawn in code in the retail icon style (gold bevelled metal on a dark painted background), because no built-in grid or scales icon exists in Forever, TBC Anniversary or MoP Classic. To change them, edit and rerun `python scripts/generate-gear-view-icons.py [--preview out.png]` (requires Pillow).
- **Don't tint native chrome.** `SetBackdropColor` / `SetBackdropBorderColor` do nothing on native panels, because no backdrop is set. Where the tint itself carries meaning (the options attention flash), use `Theme.ApplyLegacyBackdrop`.
- **New Blizzard templates:** add a capability to `NativeUI.DetectCaps()` and give the helper a fallback before using the template in a tab.

## Text colors

`Theme.COLORS` still defines the text and signal roles: `title`, `label`, `value`, `groupHeader`, and `green` / `red` / `yellow`. Chrome roles (`panelBg`, `btn*`, `scroll*`, …) are used only by the legacy fallback.

`Theme.BUTTON_TEXT` holds the native button label colors: normal gold, highlight white, disabled gray, danger red.

## Typography

Use `Theme.FONTS.<role>` for every FontString, font object and EditBox font. A spec (`spec/UI/ThemeFonts_spec.lua`) fails on new `"GameFont…"` literals in UI code.

Like native panels (Character, Reputation, Skills), all AltArmy text is 12pt, including grids, column headers, footnotes and button labels. Only Gear upgrade badges and quest-reward glyphs use a 10pt base. Sizes are the same on Forever and TBC Anniversary: Small 10, Normal/Highlight 12, Med3 14, Large 16.

| Role | Font object | Use for |
|------|-------------|---------|
| `title` | `GameFontNormalMed3` (14) | Panel, settings and dialog titles |
| `heading` | `GameFontNormal` (12, gold) | Section, group and column headers, labels, compact button and tab labels |
| `body` | `GameFontHighlight` (12, white) | Grid cells, list rows, values, footnotes and hints, settings and checkbox text, dropdowns, inputs |
| `muted` | `GameFontDisable` (12) | Unavailable rows, graph axis labels, inline empty notes |
| `emptyState` | `GameFontDisableLarge` (16) | Centered empty-state messages that replace a table or graph (Graphs hint, Cooldowns views) |
| `headline` | `GameFontHighlightLarge` | Dialog headline |
| `pageTitle` | `GameFontNormalHuge` | Interface Options page header |
| `badge` | `GameFontNormalSmall` (10, drawn ×2) | Gear upgrade glyphs on item icons |
| `count` | `NumberFontNormal` (outlined) | Stack counts on item slots (`UI/ItemSlotButton.lua`), as `ItemButtonTemplate` draws them |

The title bar text comes from the template (`GameFontNormal`).

## Spacing

- **Window gutter:** 8px between the NineSlice border and the content area. Content starts at y −60, below the toolbar.
- **Panel padding:** 6–8px inside inset panels.
- **Panel gap:** 4px between adjacent sections (`Theme.SECTION_GAP`).
- **Row height:** 18–20px for list rows and option rows.

## Legacy fallback

When a capability is missing, helpers use the original dark/bronze flat theme: `BackdropTemplate` with `ChatFrameBackground` + `UI-Tooltip-Border`, colored from `Theme.COLORS`. Forever has every capability. TBC Anniversary has all of them except the main-window `sideTabs` / `topTabs` pieces, which have their own classic fallbacks (see [Main window](#main-window)). Elsewhere the fallback only protects against client changes. It is not a user-selectable skin.
