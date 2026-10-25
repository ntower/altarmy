-- AltArmy TBC — Gear tab: "Who can use this?" drop box + equipment grid (slot rows x character columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
if not frame then return end

local GearTab = {}

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GearScoreMod = AltArmy.GearScore
local SD = AltArmy.SummaryData
local SSR = AltArmy.ScoreSortRow
local IU = AltArmy.ItemUsability
local GU = AltArmy.GearUpgrade
local GC = AltArmy.GearCompare
local ItemStats = AltArmy.ItemStats
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local PAD = 4
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local LEFT_PANEL_WIDTH = 120
local LEFT_PANEL_VISIBLE = false  -- set true to show "Who can use this?" drop zone
local MESSAGE_ROW_HEIGHT = 14
local SETTINGS_ROW_HEIGHT = 22
-- Base cell size was 28; icon size (medium 32px) + glow inset in dims.cellSize
local NUM_EQUIPMENT_SLOTS = 19

-- Equipment slot ID -> display name (TBC slots 1-19; ranged slot holds ranged weapons/relics; ammo omitted)
local SLOT_NAMES = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [4] = "Shirt",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Finger 1",
    [12] = "Finger 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged/Relic",
    [19] = "Tabard",
}

-- Display order of rows: Main Hand, Off Hand, Ranged at top; Shirt, Tabard at bottom.
-- Each entry is WoW inventory slot ID (1–19).
local SLOT_ORDER = {
    16, 17, 18,   -- Main Hand, Off Hand, Ranged
    1, 2, 3, 5,   -- Head, Neck, Shoulder, Chest
    15,           -- Back
    9, 10,        -- Wrist, Hands
    6, 7, 8,      -- Waist, Legs, Feet
    11, 12, 13, 14,   -- Finger 1, Finger 2, Trinket 1, Trinket 2
    4, 19,        -- Shirt, Tabard
}

-- State: dropped item link (nil = use default sort by level)
local droppedItemLink = nil
local itemCheckModeActive = false

--- Grid vs Upgrade Check sub-views, switched by spellbook-style tabs hanging above the panel in
--- the toolbar row (UI/TopTabs.lua). "upgrade" covers both the drop prompt and focus compare.
--- Icons are bundled art (scripts/generate-gear-view-icons.py); only Forever's icon tabs show them.
local VIEW = {
    tabs = nil,
    defs = {
        { name = "grid", label = "Grid", icon = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\GearViewGrid" },
        {
            name = "upgrade",
            label = "Upgrade Check",
            icon = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\GearViewUpgradeCheck",
        },
    },
}
local resetGridHorizontalScrollOnRefresh = false

function GearTab.ShouldHideScoreHeader()
    return droppedItemLink ~= nil or itemCheckModeActive
end

local selectedCompareKey = nil
local selectedCompareSlot = nil

local function copyFocusOpts(compareSlot)
    local opts = {}
    if GU and GU.GetOptions then
        for k, v in pairs(GU.GetOptions() or {}) do
            opts[k] = v
        end
    end
    if compareSlot then
        opts.compareSlot = compareSlot
    end
    return opts
end
local hoveredCompareKey = nil
local compareHoverRefs = {}
local comparePanelContext = nil
local soulboundCompareRecheckFrame = nil

local COMPARE_ROW_HEIGHT = 16
local COMPARE_ROW_GAP = 2
local COMPARE_SECTION_GAP = 6
local COMPARE_STAT_ROW_INDENT = 8 -- content inset from the panel split on both sides
local COMPARE_STAT_COL_NAME = 110
local COMPARE_STAT_COL_DELTA = 52
local COMPARE_STAT_COL_WEIGHT = 40
local COMPARE_STAT_HINT_SIZE = 12
local COMPARE_STAT_HINT_GAP = 2
local COMPARE_STAT_COL_WEIGHTED_NAME = 60
local COMPARE_STAT_COL_WEIGHTED_DELTA = 102
local COMPARE_PANEL_SPLIT_GAP = 8
local COMPARE_WARNING_COLOR_BLOCKING = Theme.COLORS.warningBlocking
local COMPARE_WARNING_COLOR_CAUTION = Theme.COLORS.warningCaution
GearTab.COMPARE_WARNING_KIND = {
    MISSING_SPEC = "missing_spec",
    UNPICKED_SPEC = "unpicked_spec",
    WEAPON_LOADOUT = "weapon_loadout",
    DIFFERENT_REALM = "different_realm",
}
local COMPARE_PANEL_PAD = 8
local COMPARE_PANEL_MIN_HEIGHT = 100
local COMPARE_FOCUS_DROP_SIZE = 44
local COMPARE_FOCUS_TITLE_GAP = 6
local COMPARE_FOCUS_HEADER_HEIGHT = COMPARE_FOCUS_DROP_SIZE + 8
local COMPARE_ITEMS_ROW_HEIGHT = COMPARE_FOCUS_HEADER_HEIGHT
local COMPARE_HOVER_COLOR = { 0.82, 0.68, 0.22, 0.32 }
local UPGRADE_BADGE_COLORS = {
    upgrade = { 0.2, 1, 0.2 },
    sidegrade = { 0.9, 0.78, 0.12 },
    upgradeFuture = { 1, 1, 1 },
    sidegradeFuture = { 1, 1, 1 },
    unusable = { 1, 0.45, 0.2 },
}
local UPGRADE_BADGE_TEXT = {
    upgrade = "+",
    sidegrade = "~",
    upgradeFuture = "+",
    sidegradeFuture = "~",
    unusable = "x",
}
local UPGRADE_BADGE_FONT_OBJECT = Theme.FONTS.badge
local UPGRADE_BADGE_FONT_SCALE = 2

local function applyUpgradeBadgeFont(fontString)
    if not fontString then return end
    fontString:SetFontObject(UPGRADE_BADGE_FONT_OBJECT)
    local font, size, flags = fontString:GetFont()
    if font and size then
        fontString:SetFont(font, size * UPGRADE_BADGE_FONT_SCALE, flags)
    end
end
local SELECTED_NEUTRAL_HIGHLIGHT = { 0.82, 0.68, 0.22, 0.42 }
local FOCUS_FADE_ALPHA = 0.45
-- Focus grid: keep a tiny bottom pad so the last icon isn't flush against the scroll chrome.
local FOCUS_GRID_BOTTOM_PAD = 2

-- Gear settings persistence (AltArmyTBC_GearSettings)
local DEFAULT_SCORE_PROVIDER = "level"
local SLOT_LABEL_WIDTH = 125
local SCORE_SORT_BTN_GAP = 2
local SCORE_ROW_LAYOUT_TRIM = 4
local SCORE_ROW_HEADER_BOTTOM_INSET = 6
local UPGRADE_HIGHLIGHT_COLUMN_INSET = 2
local SELECTED_CELL_HIGHLIGHT_INSET = UPGRADE_HIGHLIGHT_COLUMN_INSET + 2
local HEADER_TOP_INSET = 4
local ITEM_CHECK_COMPACT_SECTION_PAD = 4
local ITEM_CHECK_WAITING_HEADER_HEIGHT = 30

function GearTab.ShouldHideMessageHeader()
    return itemCheckModeActive and droppedItemLink == nil
end

function GearTab.GetAvailableScoreProviders()
    return SSR.GetAvailableProviders()
end

function GearTab.ValidateScoreProvider(id)
    return SSR.ValidateProvider(id)
end

function GearTab.GetGearSettings()
    AltArmyTBC_GearSettings = AltArmyTBC_GearSettings or {}
    local s = AltArmyTBC_GearSettings
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    if s.scoreSortDescending == nil then s.scoreSortDescending = true end
    s.scoreProvider = GearTab.ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
    s.characters = s.characters or {}
    AltArmy.CharacterFilter.Ensure(s)
    return s
end

function GearTab.GetSelectedScoreProvider()
    local s = GearTab.GetGearSettings()
    return GearTab.ValidateScoreProvider(s.scoreProvider or DEFAULT_SCORE_PROVIDER)
end

function GearTab.GetScoreProviderLabel(providerId)
    return SSR.GetProviderLabel(providerId)
end

--- Fixed layout: Normal spacing (12px row/column gaps) and medium icons (32px).
function GearTab.GetSpacingGaps()
    return 12, 12
end

function GearTab.GetIconSizePx()
    return 32
end

local ITEM_GLOW_ALPHA = 0.4
local ITEM_ICON_INSET = 2
-- Empty cells show the game's empty-slot art, dimmed so a real item reads brighter
local EMPTY_SLOT_DIM = 0.7
local EMPTY_SLOT_ALPHA = 0.6
-- CENTER→TOPRIGHT: negative x = left, negative y = down
local UPGRADE_BADGE_OFFSET_X = -(ITEM_ICON_INSET + 4)
local UPGRADE_BADGE_OFFSET_Y = -(ITEM_ICON_INSET + 4)
local UPGRADE_BADGE_SIDEGRADE_Y_EXTRA = -10
local UPGRADE_BADGE_UPGRADE_Y_ADJUST = -2
local UPGRADE_BADGE_SIDEGRADE_Y_ADJUST = 2

--- Cell frame size: icon plus inset on each side for rarity glow ring.
function GearTab.GetCellSizePx()
    return GearTab.GetIconSizePx() + 2 * ITEM_ICON_INSET
end

--- Returns rowHeight, columnWidth for current spacing and cell size.
function GearTab.GetSpacingDimensions()
    local rowGap, colGap = GearTab.GetSpacingGaps()
    local cell = GearTab.GetCellSizePx()
    return cell + rowGap, cell + colGap
end

local dims = {}
local CharKey = AltArmy.CharKey

function GearTab.GetScoreRowContentHeight()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    return math.floor(rh / 2)
end

function GearTab.GetScoreRowHeight()
    return GearTab.GetScoreRowContentHeight() - SCORE_ROW_LAYOUT_TRIM
end

function GearTab.GetScoreSortBtnSize()
    return GearTab.GetScoreRowContentHeight()
end

function GearTab.GetFocusedSlotSet()
    if not droppedItemLink or not IU or not IU.GetFocusDisplaySlotsForItem then return nil end
    local slots = IU.GetFocusDisplaySlotsForItem(droppedItemLink)
    if not slots or #slots == 0 then return nil end
    local set = {}
    for i = 1, #slots do
        set[slots[i]] = true
    end
    return set
end

function GearTab.GetFocusedInventorySlots()
    if not droppedItemLink or not GU or not GU.GetFocusInventorySlots then return {} end
    return GU.GetFocusInventorySlots(droppedItemLink)
end

function GearTab.IsMultiSlotFocus()
    return #GearTab.GetFocusedInventorySlots() > 1
end

function GearTab.MakeCompareCellKey(charKey, invSlot)
    if not charKey or not invSlot then return nil end
    return charKey .. "#" .. tostring(invSlot)
end

function GearTab.IsCompareCellSelected(charKey, invSlot)
    if not selectedCompareKey or charKey ~= selectedCompareKey then return false end
    if not selectedCompareSlot or not invSlot then return false end
    return selectedCompareSlot == invSlot
end

function GearTab.HasCompareSelection()
    return selectedCompareKey ~= nil and selectedCompareSlot ~= nil
end

function GearTab.CollectComparePanelContext(list)
    list = list or GearTab.GetDisplayList()
    if not droppedItemLink or not GearTab.HasCompareSelection() or not GC then
        return nil
    end
    local entry = GearTab.GetSelectedCompareEntry(list)
    if not entry then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    if not charData then return nil end
    local technique = GearTab.GetSessionCompareTechnique()
    local equippedLink = GearTab.GetSelectedEquippedCompareLink(list, technique)
    equippedLink = equippedLink or GC.GetEquippedCompareItem(charData, droppedItemLink, {
        technique = technique,
        slot = selectedCompareSlot,
        entry = entry,
    })
    local focusOpts = copyFocusOpts(selectedCompareSlot)
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(
        list, GearTab.GetFocusedInventorySlots(), focusOpts)
    return {
        focusedLink = droppedItemLink,
        equippedLink = equippedLink,
        technique = technique,
        charData = charData,
        entry = entry,
        invSlot = selectedCompareSlot,
        upgradeMaxDelta = upgradeMaxDelta,
        focusOpts = focusOpts,
    }
end

function GearTab.IsDisplaySlotVisible(displayIdx)
    local focused = GearTab.GetFocusedSlotSet()
    if not focused then return true end
    local invSlot = SLOT_ORDER[displayIdx]
    return focused[invSlot] == true
end

function GearTab.GetVisibleDisplaySlots()
    local out = {}
    for slot = 1, NUM_EQUIPMENT_SLOTS do
        if GearTab.IsDisplaySlotVisible(slot) then
            out[#out + 1] = slot
        end
    end
    return out
end

function GearTab.GetScrollableGridHeight()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    local cell = dims.cellSize or GearTab.GetCellSizePx()
    local visibleCount = #GearTab.GetVisibleDisplaySlots()
    if visibleCount <= 0 then
        visibleCount = NUM_EQUIPMENT_SLOTS
    end
    if droppedItemLink then
        -- Content-tight height for the 1–2 visible focus rows: top centering offset,
        -- cells + inter-row gaps, no trailing row-gap, then a small bottom pad.
        local topOffset = (rh - cell) / 2
        return topOffset + (visibleCount - 1) * rh + cell + FOCUS_GRID_BOTTOM_PAD
    end
    return visibleCount * rh + PAD
end

function GearTab.GetSessionCompareTechnique()
    if GU and GU.GetOptions then return GU.GetOptions().technique or "custom" end
    return "custom"
end

function GearTab.ClearCompareSelection()
    selectedCompareKey = nil
    selectedCompareSlot = nil
    hoveredCompareKey = nil
    wipe(compareHoverRefs)
    comparePanelContext = nil
end

function GearTab.PickBestCompareSlotForEntry(entry, list)
    local slots = GearTab.GetFocusedInventorySlots()
    if #slots == 0 then return nil end
    if not entry then return slots[1] end
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(list, slots, focusOpts)
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    local slot = GU and GU.GetBestFocusCompareSlot
        and GU.GetBestFocusCompareSlot(
            entry, charData, droppedItemLink, slots, focusOpts, upgradeMaxDelta)
        or slots[1]
    return GearTab.ResolveEquippableCompareSlot(entry, slot)
end

--- Auto-select after focus: first sorted column when any clear/eventual upgrade exists.
function GearTab.PickInitialCompareSelection(list)
    if not GearTab.HasAnyUpgradeOrEventualUpgrade(list) then
        return nil, nil
    end
    if not list or #list == 0 then return nil, nil end
    local e = list[1]
    local slot = GearTab.PickBestCompareSlotForEntry(e, list)
    if not slot then return nil, nil end
    return CharKey(e.name, e.realm), slot
end

--- Auto-select current character for soulbound focus items.
function GearTab.PickCurrentCharacterCompareSelection(list)
    if not list or #list == 0 then return nil, nil end
    if not DS or not DS.IsCurrentCharacter then return nil, nil end
    local currentEntry
    for i = 1, #list do
        local e = list[i]
        if DS:IsCurrentCharacter(e.name, e.realm) then
            currentEntry = e
            break
        end
    end
    if not currentEntry then return nil, nil end
    local slot = GearTab.PickBestCompareSlotForEntry(currentEntry, list)
    if not slot then return nil, nil end
    return CharKey(currentEntry.name, currentEntry.realm), slot
end

--- Best (character, inventory slot) for in-range upgrade/sidegrade; used by loot alerts.
function GearTab.PickBestCompareSelection(list)
    if not list or #list == 0 or not droppedItemLink then return nil, nil end
    local slots = GearTab.GetFocusedInventorySlots()
    if #slots == 0 then return nil, nil end
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(list, slots, focusOpts)
    local bestKey, bestSlot, bestDelta = nil, nil, 0
    local inRangeUpgrade = GU and GU.FOCUS_CATEGORY
    for i = 1, #list do
        local e = list[i]
        local charData = DS and DS.GetCharacter and DS:GetCharacterFor(e.name, e.realm, e.linkId)
        for s = 1, #slots do
            local invSlot = slots[s]
            local info = GU and GU.ClassifyFocusSlot
                and GU.ClassifyFocusSlot(e, charData, droppedItemLink, invSlot, focusOpts, upgradeMaxDelta)
            if info and inRangeUpgrade
                and (info.category == inRangeUpgrade.UPGRADE_IN_RANGE
                    or info.category == inRangeUpgrade.SIDEGRADE_IN_RANGE)
                and info.delta > bestDelta then
                bestDelta = info.delta
                bestKey = CharKey(e.name, e.realm)
                bestSlot = invSlot
            end
        end
    end
    if bestKey and bestSlot then
        return bestKey, bestSlot
    end
    return nil, nil
end

function GearTab.ComputeFocusUpgradeMaxDelta(list, _slots, focusOpts)
    if not list or not droppedItemLink or not GU or not GU.ComputeUpgradeMaxDeltaForEntries then
        return nil
    end
    return GU.ComputeUpgradeMaxDeltaForEntries(list, droppedItemLink, focusOpts)
end

function GearTab.FormatCompareFocusVsLabel()
    return "vs"
end

--- Returns the prefix text plus the colored first-name segment (for the name hover tooltip).
function GearTab.FormatCompareVerdictPrefix(charName, classFile)
    local namePart = (CC and CC.firstName) and CC.firstName(charName) or (charName or "?")
    if CC and CC.formatName then
        namePart = CC.formatName(namePart, classFile)
    end
    return "Verdict for " .. namePart .. ": ", namePart
end

function GearTab.GetCompareFocusItemName(itemLink)
    itemLink = itemLink or droppedItemLink
    if not itemLink or not DS.HasItemInfoApi() then return nil end
    local name = DS.CompatGetItemInfo(itemLink)
    if name and name ~= "" then return name end
    return nil
end

function GearTab.FormatCompareClickHint(itemLink)
    local name = GearTab.GetCompareFocusItemName(itemLink)
    if name then
        return "Click to compare with " .. name
    end
    return "Click to compare"
end

function GearTab.FormatItemCheckDropMessage()
    return "Drop an item to see who can use it as an upgrade"
end

function GearTab.GetCompareStatContentHeight(rowCount)
    rowCount = tonumber(rowCount) or 0
    if rowCount <= 0 then return 0 end
    return rowCount * COMPARE_ROW_HEIGHT + (rowCount - 1) * COMPARE_ROW_GAP
end

--- Flatten section rows in display order.
function GearTab.FlattenCompareStatRows(sections)
    local rows = {}
    sections = sections or {}
    for s = 1, #sections do
        local sectionRows = sections[s].rows or {}
        for r = 1, #sectionRows do
            rows[#rows + 1] = sectionRows[r]
        end
    end
    return rows
end

--- Split a trailing Weighted/summary row from the scrollable stat rows.
function GearTab.SplitCompareStatRows(rows)
    rows = rows or {}
    local scrollRows = {}
    local weightedRow = nil
    if #rows > 0 and rows[#rows].formatAsWeightedChange then
        weightedRow = rows[#rows]
        for i = 1, #rows - 1 do
            scrollRows[i] = rows[i]
        end
    else
        for i = 1, #rows do
            scrollRows[i] = rows[i]
        end
    end
    return scrollRows, weightedRow
end

--- Pin Weighted at the bottom only when the full list overflows the viewport.
function GearTab.ShouldPinCompareWeightedRow(totalRowCount, viewHeight)
    if not totalRowCount or totalRowCount <= 0 then return false end
    viewHeight = tonumber(viewHeight) or 0
    if viewHeight <= 0 then return false end
    return GearTab.GetCompareStatContentHeight(totalRowCount) > viewHeight
end

function GearTab.HasAnyUpgradeOrEventualUpgrade(list)
    if not list or not droppedItemLink or not GU or not GU.HasAnyFocusUpgradeOrEventual then
        return false
    end
    local focusOpts = GU.GetOptions and GU.GetOptions() or {}
    -- Upgrades, eventual upgrades, and in-range sidegrades (not eventual sidegrades/downgrades/unusable).
    return GU.HasAnyFocusUpgradeOrEventual(list, droppedItemLink, focusOpts)
end

function GearTab.FormatCompareChooseCharacterHintText()
    return "Choose a character above to compare against"
end

function GearTab.FormatCompareNoUpgradeHintText()
    return "This isn't a clear upgrade for any of your characters."
        .. "\nClick an item above to compare anyway"
end

function GearTab.FormatCompareEmptyHintText(hasUpgradeOrEventual)
    if hasUpgradeOrEventual then
        return GearTab.FormatCompareChooseCharacterHintText()
    end
    return GearTab.FormatCompareNoUpgradeHintText()
end

function GearTab.FormatCompareEmptyStateText(hasUpgradeOrEventual)
    return GearTab.FormatCompareEmptyHintText(hasUpgradeOrEventual)
end

--- First visible column after focus sort when upgrades/eventual upgrades exist.
function GearTab.PickBestCompareKey(list)
    return GearTab.PickInitialCompareSelection(list)
end

function GearTab.IsFocusedItemSoulbound()
    return droppedItemLink
        and IU
        and IU.IsBindOnPickup
        and IU.IsBindOnPickup(droppedItemLink)
end

local soulboundCompareRecheckToken = 0

function GearTab.ApplyFocusCompareSelection()
    if GearTab.IsFocusedItemSoulbound() then
        selectedCompareKey, selectedCompareSlot = GearTab.PickCurrentCharacterCompareSelection(
            GearTab.GetDisplayList())
        return
    end
    selectedCompareKey, selectedCompareSlot = GearTab.PickInitialCompareSelection(GearTab.GetDisplayList())
end

function GearTab.ScheduleSoulboundCompareRecheck(itemLink)
    soulboundCompareRecheckToken = soulboundCompareRecheckToken + 1
    local token = soulboundCompareRecheckToken
    local function tryRecheck()
        if token ~= soulboundCompareRecheckToken then return end
        if droppedItemLink ~= itemLink then return end
        if not GearTab.IsFocusedItemSoulbound() then return end
        local key, slot = GearTab.PickCurrentCharacterCompareSelection(GearTab.GetDisplayList())
        if not key then return end
        if selectedCompareKey == key and selectedCompareSlot == slot then return end
        selectedCompareKey, selectedCompareSlot = key, slot
        if frame.RefreshGrid then frame:RefreshGrid() end
    end
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(0, tryRecheck)
    else
        tryRecheck()
    end
    local itemId = tonumber(itemLink and itemLink:match("item:(%d+)"))
    if not itemId or not CreateFrame then return end
    if not soulboundCompareRecheckFrame then
        soulboundCompareRecheckFrame = CreateFrame("Frame")
    end
    soulboundCompareRecheckFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    soulboundCompareRecheckFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    soulboundCompareRecheckFrame:SetScript("OnEvent", function(self, _, receivedId)
        if tonumber(receivedId) ~= itemId then return end
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        tryRecheck()
    end)
end

function GearTab.ApplyFocusedItem(itemLink, _opts)
    if droppedItemLink ~= itemLink then
        resetGridHorizontalScrollOnRefresh = true
    end
    droppedItemLink = itemLink
    hoveredCompareKey = nil
    GearTab.ApplyFocusCompareSelection()
    GearTab.ScheduleSoulboundCompareRecheck(itemLink)
    if GC and GC.LogItemComparisonDebug then
        GC.LogItemComparisonDebug(itemLink)
    end
end

function GearTab.GetSelectedCompareEntry(list)
    if not selectedCompareKey or not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if CharKey(e.name, e.realm) == selectedCompareKey then
            return e
        end
    end
    return nil
end

function GearTab.IsCompareSpecAssumptionWarning(warning)
    return type(warning) == "table"
        and (warning.kind == GearTab.COMPARE_WARNING_KIND.MISSING_SPEC
            or warning.kind == GearTab.COMPARE_WARNING_KIND.UNPICKED_SPEC)
end

local function isCompareEntryCurrentCharacter(entry)
    if not entry or not DS or not DS.IsCurrentCharacter then return false end
    return DS:IsCurrentCharacter(entry.name, entry.realm)
end

function GearTab.GetCompareWarningSeverity(warning, entry)
    if GearTab.IsCompareSpecAssumptionWarning(warning) then
        return "caution"
    end
    if type(warning) == "table"
        and warning.kind == GearTab.COMPARE_WARNING_KIND.WEAPON_LOADOUT then
        return "caution"
    end
    if type(warning) == "table"
        and warning.kind == GearTab.COMPARE_WARNING_KIND.DIFFERENT_REALM then
        return "blocking"
    end
    local kind = IU and IU.GetEquipWarningKind and IU.GetEquipWarningKind(warning)
    if kind == IU.EQUIP_WARNING_KIND.SOULBOUND then
        if isCompareEntryCurrentCharacter(entry) then
            return "caution"
        end
        return "blocking"
    end
    if kind == IU.EQUIP_WARNING_KIND.LEVEL or kind == IU.EQUIP_WARNING_KIND.TRAINING then
        return "caution"
    end
    if kind == IU.EQUIP_WARNING_KIND.NEVER then
        return "blocking"
    end
    local text = IU and IU.GetEquipWarningText and IU.GetEquipWarningText(warning) or warning
    if type(text) == "string" then
        if text:find("must gain ", 1, true) or text:find("must train ", 1, true) then
            return "caution"
        end
        if text:find("can never equip this", 1, true) then
            return "blocking"
        end
    end
    return "blocking"
end

function GearTab.GetCompareWarningColor(warning, entry)
    local kind = IU and IU.GetEquipWarningKind and IU.GetEquipWarningKind(warning)
    if kind == IU.EQUIP_WARNING_KIND.SOULBOUND and isCompareEntryCurrentCharacter(entry) then
        return 1, 1, 1
    end
    local caution = COMPARE_WARNING_COLOR_CAUTION
    local blocking = COMPARE_WARNING_COLOR_BLOCKING
    if GearTab.GetCompareWarningSeverity(warning, entry) == "caution" then
        return caution[1], caution[2], caution[3]
    end
    return blocking[1], blocking[2], blocking[3]
end

function GearTab.SortCompareWarnings(warnings, entry)
    if not warnings or #warnings < 2 then return warnings end
    table.sort(warnings, function(a, b)
        local aSpec = GearTab.IsCompareSpecAssumptionWarning(a)
        local bSpec = GearTab.IsCompareSpecAssumptionWarning(b)
        if aSpec ~= bSpec then
            return not aSpec
        end
        local aBlocking = GearTab.GetCompareWarningSeverity(a, entry) == "blocking"
        local bBlocking = GearTab.GetCompareWarningSeverity(b, entry) == "blocking"
        if aBlocking ~= bBlocking then
            return aBlocking
        end
        local aKind = type(a) == "table" and a.kind or ""
        local bKind = type(b) == "table" and b.kind or ""
        return aKind < bKind
    end)
    return warnings
end

function GearTab.GetCompareWarnings(entry, itemLink, charData)
    local warnings = {}
    if GU and GU.GetCompareSpecWarning then
        local specWarning = GU.GetCompareSpecWarning(entry, charData)
        if specWarning then
            warnings[#warnings + 1] = specWarning
        end
    end
    if entry and itemLink and GU and GU.GetCompareRealmWarning then
        local realmWarning = GU.GetCompareRealmWarning(
            entry, (DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or "",
            DS and DS.IsWowForever)
        if realmWarning then
            warnings[#warnings + 1] = realmWarning
        end
    end
    if entry and itemLink and IU and IU.GetEquipWarnings then
        local equipWarnings = IU.GetEquipWarnings(
            entry.classFile, entry.level, entry.name, itemLink, charData) or {}
        for i = 1, #equipWarnings do
            warnings[#warnings + 1] = equipWarnings[i]
        end
    end
    GearTab.SortCompareWarnings(warnings, entry)
    return warnings
end

function GearTab.EstimateComparePanelHeight(comparison, warningCount, hasVerdict)
    if not comparison then return 0 end
    local leftH = COMPARE_ITEMS_ROW_HEIGHT + 8
    warningCount = tonumber(warningCount) or 0
    local leftRowCount = (hasVerdict and 1 or 0) + warningCount
    if leftRowCount > 0 then
        leftH = leftH + GearTab.GetCompareStatContentHeight(leftRowCount)
    end
    local sections = comparison.sections or {}
    for s = 1, #sections do
        local section = sections[s]
        leftH = leftH + COMPARE_SECTION_GAP + COMPARE_ROW_HEIGHT
        local rowCount = #(section.rows or {})
        if rowCount > 0 then
            leftH = leftH + rowCount * COMPARE_ROW_HEIGHT
        end
    end
    local contentH = leftH
    return math.max(COMPARE_PANEL_MIN_HEIGHT, COMPARE_PANEL_PAD * 2 + contentH)
end

function GearTab.GetCharSetting(name, realm, key)
    local s = GearTab.GetGearSettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

function GearTab.SetCharSetting(name, realm, pin, hide)
    local s = GearTab.GetGearSettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

function GearTab.CanClassEverUseArmor(classFile, subclass)
    return IU and IU.CanClassEverUseArmor(classFile, subclass) or true
end

function GearTab.CanClassEverUseWeapon(classFile, weaponSubclass)
    return IU and IU.CanClassEverUseWeapon(classFile, weaponSubclass) or true
end

function GearTab.GetItemUseInfo(link)
    if IU and IU.GetItemUseInfo then
        return IU.GetItemUseInfo(link)
    end
    return nil, nil, nil
end

function GearTab.CompareBySelectedScore(entryA, entryB, providerId, descending)
    return SSR.Compare(entryA, entryB, providerId, descending)
end

function GearTab.DecorateDisplayEntry(entry)
    SSR.DecorateEntry(entry)
end

--- Build display list: filter hidden; order = pinned (incl. current when pin-current) + non-pinned.
--- Optionally re-sort by "who can use" when item dropped.
function GearTab.GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GearTab.GetGearSettings()
    local currentRealm = DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""
    local showSelfFirst = settings.showSelfFirst ~= false
    local CF = AltArmy.CharacterFilter
    local ctx = CF.Context(currentRealm)

    -- Filter out hidden and filtered out (pin-current-character overrides both for the signed-in character)
    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local BA = AltArmy.BankAlt
        local isBankAlt = BA and BA.Is and BA.Is(e.name, e.realm)
        local isHidden = GearTab.GetCharSetting(e.name, e.realm, "hide") or isBankAlt
            or not CF.Matches(e, settings.filter, ctx)
        if not isHidden or (showSelfFirst and isSelf) then
            visible[#visible + 1] = e
            GearTab.DecorateDisplayEntry(e)
        end
    end

    local providerId = GearTab.GetSelectedScoreProvider()
    local descending = settings.scoreSortDescending ~= false

    -- Split: pinned (manual pin or pin-current-character), non-pinned
    local pinned = {}
    local nonPinned = {}
    for i = 1, #visible do
        local e = visible[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isPinned = GearTab.GetCharSetting(e.name, e.realm, "pin")
        if isPinned or (showSelfFirst and isSelf) then
            pinned[#pinned + 1] = e
        else
            nonPinned[#nonPinned + 1] = e
        end
    end

    table.sort(pinned, function(a, b)
        return GearTab.CompareBySelectedScore(a, b, providerId, descending)
    end)
    table.sort(nonPinned, function(a, b)
        return GearTab.CompareBySelectedScore(a, b, providerId, descending)
    end)

    local list = {}
    for i = 1, #pinned do list[#list + 1] = pinned[i] end
    for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end

    -- When item focused, sort by focus category then upgrade magnitude.
    if not droppedItemLink then return list end
    local upgradeOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    local focusSlots = GearTab.GetFocusedInventorySlots()
    local upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(list, focusSlots, upgradeOpts)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    table.sort(copy, function(a, b)
        if GearTab.IsFocusedItemSoulbound() then
            local aSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(a.name, a.realm)
            local bSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(b.name, b.realm)
            if aSelf ~= bSelf then return aSelf end
        end
        local charA = DS and DS.GetCharacter and DS:GetCharacterFor(a.name, a.realm, a.linkId)
        local charB = DS and DS.GetCharacter and DS:GetCharacterFor(b.name, b.realm, b.linkId)
        if GU and GU.CompareFocusEntries then
            return GU.CompareFocusEntries(
                a, b, charA, charB, droppedItemLink, upgradeOpts, upgradeMaxDelta)
        end
        return (a.name or "") < (b.name or "")
    end)
    return copy
end

function GearTab.GetFocusSummaryForEntry(entry, upgradeMaxDelta)
    if not droppedItemLink or not GU or not GU.SummarizeFocusEntry then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    local opts = GU.GetOptions and GU.GetOptions() or {}
    return GU.SummarizeFocusEntry(entry, charData, droppedItemLink, opts, upgradeMaxDelta)
end

function GearTab.GetFocusColumnDimmed(entry, upgradeMaxDelta)
    if not droppedItemLink or not GU or not GU.GetFocusColumnDimmed then return false end
    if GearTab.IsFocusedItemSoulbound() then
        if DS and DS.IsCurrentCharacter and not DS:IsCurrentCharacter(entry.name, entry.realm) then
            return true
        end
    end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    local opts = GU.GetOptions and GU.GetOptions() or {}
    return GU.GetFocusColumnDimmed(entry, charData, droppedItemLink, opts, upgradeMaxDelta)
end

function GearTab.getUpgradeHighlightHorizontalInset()
    return UPGRADE_HIGHLIGHT_COLUMN_INSET
end

function GearTab.getSelectedHighlightWidth()
    return GearTab.GetCellSizePx() + 2 * SELECTED_CELL_HIGHLIGHT_INSET
end

function GearTab.getUpgradeHighlightBelowHeaderExtent()
    local rh = dims.rowHeight or select(1, GearTab.GetSpacingDimensions())
    local cell = dims.cellSize or GearTab.GetCellSizePx()
    return (rh - cell) / 2 + cell
end

function GearTab.getUpgradeHighlightKind(delta, oldTotal)
    if GU and GU.GetUpgradeHighlightKind then
        return GU.GetUpgradeHighlightKind(delta, oldTotal, GU.GetOptions and GU.GetOptions())
    end
    return nil
end

function GearTab.getFocusColumnAlpha(shouldDim, isSelected)
    if isSelected then return 1 end
    if not droppedItemLink then return 1 end
    if shouldDim then return FOCUS_FADE_ALPHA end
    return 1
end

function GearTab.GetFirstFocusedColumnSlot()
    local visible = GearTab.GetVisibleDisplaySlots()
    if #visible > 0 then
        return SLOT_ORDER[visible[1]]
    end
    local slots = GearTab.GetFocusedInventorySlots()
    return slots[1]
end

local OTHER_WEAPON_HAND = { [16] = 17, [17] = 16 }

--- Redirect a weapon-hand slot to the hand the focused item can actually occupy for
--- this character. Off-hand-only items (shields, held-in-off-hand) resolve to the
--- off-hand even when the main-hand row is targeted, and main-hand-only weapons
--- resolve to the main hand. Non-weapon slots and equippable slots pass through.
function GearTab.ResolveEquippableCompareSlot(entry, invSlot)
    if not droppedItemLink or not invSlot or not entry then return invSlot end
    if not GU or not GU.CanEquipFocusItemInWeaponSlot then return invSlot end
    local otherHand = OTHER_WEAPON_HAND[invSlot]
    if not otherHand then return invSlot end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    if GU.CanEquipFocusItemInWeaponSlot(charData, droppedItemLink, invSlot, entry) then
        return invSlot
    end
    if GU.CanEquipFocusItemInWeaponSlot(charData, droppedItemLink, otherHand, entry) then
        return otherHand
    end
    return invSlot
end

function GearTab.GetCompareEntryByKey(key)
    if not key then return nil end
    local list = GearTab.GetDisplayList()
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if CharKey(e.name, e.realm) == key then return e end
    end
    return nil
end

function GearTab.SelectCompareCell(charKey, invSlot)
    if not charKey or not invSlot then return end
    invSlot = GearTab.ResolveEquippableCompareSlot(
        GearTab.GetCompareEntryByKey(charKey), invSlot)
    if GearTab.IsCompareCellSelected(charKey, invSlot) then
        GearTab.ClearCompareSelection()
    else
        selectedCompareKey = charKey
        selectedCompareSlot = invSlot
    end
    if frame.RefreshGrid then frame:RefreshGrid() end
end

function GearTab.SelectCompareCharacter(key)
    if not key then return end
    local entry = GearTab.GetCompareEntryByKey(key)
    local invSlot = GearTab.PickBestCompareSlotForEntry(entry, GearTab.GetDisplayList())
    if invSlot then
        GearTab.SelectCompareCell(key, invSlot)
    end
end

local function resolveColumnHighlightColor(_kind, selected)
    if not selected then return nil end
    return SELECTED_NEUTRAL_HIGHLIGHT
end

local function layoutCellFillTexture(tex, cell, hInset, r, g, b, a)
    if not tex or not cell then
        if tex then tex:Hide() end
        return
    end
    tex:SetColorTexture(r, g, b, a)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", cell, "TOPLEFT", -hInset, hInset)
    tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", hInset, -hInset)
    tex:Show()
end

function GearTab.layoutCellUpgradeBadge(cell, kind)
    if not cell or not cell.upgradeBadge then return end
    local badge = cell.upgradeBadge
    if not kind then
        badge:Hide()
        return
    end
    local colors = UPGRADE_BADGE_COLORS[kind]
    local text = UPGRADE_BADGE_TEXT[kind]
    if not colors or not text then
        badge:Hide()
        return
    end
    local offsetY = UPGRADE_BADGE_OFFSET_Y
    if kind == "upgrade" or kind == "upgradeFuture" then
        offsetY = offsetY + UPGRADE_BADGE_UPGRADE_Y_ADJUST
    elseif kind == "sidegrade" or kind == "sidegradeFuture" then
        offsetY = offsetY + UPGRADE_BADGE_SIDEGRADE_Y_EXTRA + UPGRADE_BADGE_SIDEGRADE_Y_ADJUST
    end
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", cell, "TOPRIGHT", UPGRADE_BADGE_OFFSET_X, offsetY)
    badge:SetText(text)
    badge:SetTextColor(colors[1], colors[2], colors[3], 1)
    badge:Show()
end

function GearTab.layoutCellFocusHighlight(cell, _kind, selected)
    if not cell or not cell.focusHighlight then return end
    local colors = resolveColumnHighlightColor(nil, selected)
    if not colors then
        cell.focusHighlight:Hide()
        return
    end
    local hInset = SELECTED_CELL_HIGHLIGHT_INSET
    layoutCellFillTexture(
        cell.focusHighlight, cell, hInset,
        colors[1], colors[2], colors[3], colors[4])
end

function GearTab.layoutHeaderSelectionHighlight(headerCol, selected)
    if not headerCol or not headerCol.headerSelectionHighlight or not headerCol.header then return end
    local tex = headerCol.headerSelectionHighlight
    if not selected then
        tex:Hide()
        return
    end
    local colors = SELECTED_NEUTRAL_HIGHLIGHT
    local hInset = SELECTED_CELL_HIGHLIGHT_INSET
    local highlightWidth = GearTab.getSelectedHighlightWidth()
    local headerHeight = headerCol.header:GetHeight() or 0
    if headerHeight <= 0 then headerHeight = 18 end
    tex:SetColorTexture(colors[1], colors[2], colors[3], colors[4])
    tex:ClearAllPoints()
    tex:SetSize(highlightWidth, headerHeight + 2 * hInset)
    tex:SetPoint("CENTER", headerCol.header, "CENTER", 0, 0)
    tex:Show()
end

function GearTab.layoutCellCompareHover(cell, show)
    if not cell or not cell.compareHover then return end
    if not show then
        cell.compareHover:Hide()
        return
    end
    local hInset = GearTab.getUpgradeHighlightHorizontalInset()
    local r, g, b, a = COMPARE_HOVER_COLOR[1], COMPARE_HOVER_COLOR[2], COMPARE_HOVER_COLOR[3], COMPARE_HOVER_COLOR[4]
    layoutCellFillTexture(cell.compareHover, cell, hInset, r, g, b, a)
end

function GearTab.layoutSelectionOutline(_headerCol, gridCol, _focusCells, _show)
    local function hideOutline(o)
        if not o then return end
        for _, tex in pairs(o) do tex:Hide() end
    end
    hideOutline(gridCol and gridCol.selectionOutline)
end

--- Brief fit message for column: nil or "", or "Can not wear plate" / "10 levels ahead" etc.
--- Returns message, color ("red" | "orange" | nil).
function GearTab.GetFitMessage(entry)
    if not droppedItemLink then return nil, nil end
    local reqLevel, armorSubclass, weaponSubclass = GearTab.GetItemUseInfo(droppedItemLink)
    if reqLevel == nil and armorSubclass == nil and weaponSubclass == nil then
        return nil, nil
    end
    reqLevel = reqLevel or 0
    local classFile = (entry.classFile or ""):upper()
    local charLevel = math.floor(tonumber(entry.level) or 0)

    if armorSubclass and armorSubclass ~= "" then
        if not GearTab.CanClassEverUseArmor(classFile, armorSubclass) then
            return "Can not wear " .. armorSubclass:lower(), "red"
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not GearTab.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return "Can not use " .. weaponSubclass:lower(), "red"
        end
    end

    local effective = IU and IU.EffectiveRequiredLevel
        and IU.EffectiveRequiredLevel(classFile, droppedItemLink) or reqLevel
    if effective >= 999 then
        effective = reqLevel
    end
    local delta = charLevel - effective
    local summary = GearTab.GetFocusSummaryForEntry(entry)
    if summary and summary.category and GU and GU.FOCUS_CATEGORY then
        local cat = summary.category
        if cat == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
            or cat == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE then
            return "Upgrade!", "green"
        end
    end
    if delta > 0 then
        return delta == 1 and "1 level ahead" or (delta .. " levels ahead"), "orange"
    elseif delta < 0 then
        local absDelta = math.abs(delta)
        return absDelta == 1 and "1 level behind" or (absDelta .. " levels behind"), "orange"
    end
    return nil, nil
end

--- Resolve item to texture path for display (itemID or link).
function GearTab.GetItemTexture(itemIDOrLink)
    if not itemIDOrLink then return nil end
    if not DS.HasItemInfoApi() then return nil end
    local _, _, _, _, _, _, _, _, _, texture = DS.CompatGetItemInfo(itemIDOrLink)
    return texture
end

function GearTab.SetCompareItemIcon(iconFrame, itemLink)
    if not iconFrame then return end
    iconFrame.itemLink = itemLink
    local texPath = itemLink and GearTab.GetItemTexture(itemLink)
    if texPath and iconFrame.texture then
        iconFrame.texture:SetTexture(texPath)
        iconFrame.texture:SetVertexColor(1, 1, 1, 1)
        iconFrame.texture:Show()
    elseif iconFrame.texture then
        iconFrame.texture:Hide()
    end
end

--- Item quality from GetItemInfo (0=poor, 1=common, 2=uncommon, 3=rare, 4=epic, 5=legendary).
function GearTab.GetItemQuality(itemIDOrLink)
    if not itemIDOrLink or not DS.HasItemInfoApi() then return nil end
    local _, _, quality = DS.CompatGetItemInfo(itemIDOrLink)
    return quality
end

--- Glow color for uncommon–legendary; nil for poor/common or unknown quality.
function GearTab.GetQualityGlowColor(quality)
    if quality == nil or quality < 2 or quality > 5 then return nil end
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r, c.g, c.b
    end
    if quality == 2 then return 0, 1, 0 end
    if quality == 3 then return 0, 0.44, 0.87 end
    if quality == 4 then return 0.64, 0.21, 0.93 end
    return 1, 0.5, 0
end

--- An empty cell shows the game's empty-slot art for its inventory slot, dimmed and without a glow.
--- A cell whose item the client hasn't cached yet still shows nothing. classFile picks the relic art
--- for the ranged slot of the classes that have one.
function GearTab.ApplyItemCellVisual(cell, item, gray, alpha, classFile)
    local fade = alpha or 1
    local texPath = GearTab.GetItemTexture(item)
    local ESA = AltArmy.EmptySlotArt
    local emptyPath = nil
    if item == nil and ESA and ESA.TextureFor then
        emptyPath = ESA.TextureFor(cell.inventorySlot, classFile)
    end
    if texPath then
        cell.texture:SetTexture(texPath)
        cell.texture:Show()
        if gray then
            cell.texture:SetVertexColor(0.5, 0.5, 0.5, fade)
        else
            cell.texture:SetVertexColor(fade, fade, fade, fade)
        end
    elseif emptyPath then
        cell.texture:SetTexture(emptyPath)
        cell.texture:SetVertexColor(EMPTY_SLOT_DIM, EMPTY_SLOT_DIM, EMPTY_SLOT_DIM, EMPTY_SLOT_ALPHA * fade)
        cell.texture:Show()
    else
        cell.texture:SetTexture(nil)
        cell.texture:Hide()
    end

    local gr, gg, gb = GearTab.GetQualityGlowColor(GearTab.GetItemQuality(item))
    if gr and texPath and cell.glow then
        cell.glow:SetColorTexture(gr, gg, gb, ITEM_GLOW_ALPHA * fade)
        if gray then
            cell.glow:SetVertexColor(0.5, 0.5, 0.5, fade)
        else
            cell.glow:SetVertexColor(fade, fade, fade, fade)
        end
        cell.glow:Show()
    elseif cell.glow then
        cell.glow:Hide()
    end
end

local ItemActions = AltArmy.ItemActions

--- Route a left-click on an item cell: Ctrl previews in the Dressing Room, Shift links to chat.
function GearTab.HandleItemCellClick(itemLinkOrID, button)
    if not ItemActions then return end
    local action = ItemActions.GetClickAction(
        button,
        IsShiftKeyDown and IsShiftKeyDown() or false,
        IsControlKeyDown and IsControlKeyDown() or false)
    if action == "preview" then
        ItemActions.PreviewInDressingRoom(itemLinkOrID)
    elseif action == "chatlink" then
        ItemActions.InsertLinkIntoChat(itemLinkOrID)
    end
end

-- ---- Gear layout host (transparent; section panels sit inside with gaps like Graphs tab) ----
local gearLayoutHost = CreateFrame("Frame", nil, frame)
gearLayoutHost:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
gearLayoutHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)

local gearMainSection
local itemCheckSection
local compareStatsSection
local compareStatsInner
local itemCheckInner
local gridHost
local settingsPanel

-- ---- Left panel ----
local leftPanel = CreateFrame("Frame", nil, gearLayoutHost)
leftPanel:SetPoint("TOPLEFT", gearLayoutHost, "TOPLEFT", 0, 0)
leftPanel:SetPoint("BOTTOMLEFT", gearLayoutHost, "BOTTOMLEFT", 0, 0)
leftPanel:SetWidth(LEFT_PANEL_WIDTH)

local labelWho = leftPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
labelWho:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
labelWho:SetText("Who can use this?")

local dropBox = CreateFrame("Frame", "AltArmyTBC_GearDropBox", leftPanel, "BackdropTemplate")
dropBox:SetSize(40, 40)
dropBox:SetPoint("TOPLEFT", labelWho, "BOTTOMLEFT", 0, -4)
dropBox:EnableMouse(true)
Theme.ApplyBackdrop(dropBox, "section")

local dropBoxIcon = dropBox:CreateTexture(nil, "OVERLAY")
dropBoxIcon:SetPoint("CENTER", dropBox, "CENTER", 0, 0)
dropBoxIcon:SetSize(32, 32)
dropBoxIcon:Hide()

function GearTab.tryAcceptCursorItem()
    if not GetCursorInfo then return end
    local itemLink = GearTab.getCursorItemLink()
    if itemLink then
        GearTab.ApplyFocusedItem(itemLink, { manual = true })
        if ClearCursor then ClearCursor() end
        local tex = GearTab.GetItemTexture(itemLink)
        if tex then
            dropBoxIcon:SetTexture(tex)
            dropBoxIcon:Show()
        else
            dropBoxIcon:Hide()
        end
        if frame.RefreshGrid then frame:RefreshGrid() end
        return true
    end
    return false
end

dropBox:SetScript("OnReceiveDrag", function()
    GearTab.tryAcceptCursorItem()
end)
dropBox:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        droppedItemLink = nil
        dropBoxIcon:Hide()
        if frame.RefreshGrid then frame:RefreshGrid() end
        return
    end
    GearTab.tryAcceptCursorItem()
end)
if not LEFT_PANEL_VISIBLE then
    leftPanel:Hide()
end

-- ---- Right panel: slot row headers + scrollable character columns ----
local COLUMN_HEADER_HEIGHT_GEAR = 20
local COLUMN_HEADER_NAME_Y_OFFSET = 1
local SCORE_PROVIDER_DROPDOWN_WIDTH = 200
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT

function GearTab.GetPinnedHeaderHeight()
    if GearTab.ShouldHideMessageHeader() then
        return ITEM_CHECK_WAITING_HEADER_HEIGHT
    end
    -- Focus compare clears the fit-message row; only the character name band is needed.
    if droppedItemLink then
        return COLUMN_HEADER_HEIGHT_GEAR
    end
    if GearTab.ShouldHideScoreHeader() then
        return FIXED_HEADER_ROW_HEIGHT
    end
    return FIXED_HEADER_ROW_HEIGHT + GearTab.GetScoreRowHeight()
end
-- Layout dimensions from spacing + icon size
do
    dims.cellSize = GearTab.GetCellSizePx()
    local rh, cw = GearTab.GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()
end

local rightPanel = CreateFrame("Frame", nil, gearLayoutHost)
if LEFT_PANEL_VISIBLE then
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PAD, 0)
else
    rightPanel:SetPoint("TOPLEFT", gearLayoutHost, "TOPLEFT", 0, 0)
end
rightPanel:SetPoint("BOTTOMRIGHT", gearLayoutHost, "BOTTOMRIGHT", 0, 0)

local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

gearMainSection = Theme.CreateMainContentPanel(rightPanel)
local gearMainInner = Theme.CreatePanelInnerContent(gearMainSection)
gearMainInner:SetClipsChildren(true)

function GearTab.GetHorizontalScrollChromeHeight()
    return HORIZONTAL_SCROLL_BAR_HEIGHT
end

-- Fixed header row: character names + score row; scrolls horizontally with grid
local HEADER_BG_OVERHANG = 6
local HEADER_BG_BOTTOM_INSET = 6
local fixedHeaderRow = CreateFrame("Frame", nil, gearMainInner)
fixedHeaderRow:SetPoint("TOPLEFT", gearMainInner, "TOPLEFT", 0, -HEADER_TOP_INSET)
fixedHeaderRow:SetPoint("TOPRIGHT", gearMainSection, "TOPRIGHT", -SCROLL_GUTTER, 0)
fixedHeaderRow:SetHeight(GearTab.GetPinnedHeaderHeight())
local headerBg = fixedHeaderRow:CreateTexture(nil, "BACKGROUND")
headerBg:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, HEADER_BG_OVERHANG)
headerBg:SetPoint("TOPRIGHT", fixedHeaderRow, "TOPRIGHT", 0, HEADER_BG_OVERHANG)
Theme.StyleGridHeader(headerBg, gearMainSection)
fixedHeaderRow:EnableMouse(true)
local headerCornerColumn = CreateFrame("Frame", nil, fixedHeaderRow)
headerCornerColumn:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, 0)
headerCornerColumn:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, 0)
headerCornerColumn:SetWidth(SLOT_LABEL_WIDTH)
Theme.ApplyGridLabelColumnBackground(headerCornerColumn)
local headerCornerCell = headerCornerColumn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
headerCornerCell:SetPoint("TOPLEFT", headerCornerColumn, "TOPLEFT", 0, 0)
headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
headerCornerCell:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerCornerCell:SetJustifyH("LEFT")
headerCornerCell:SetText("")

function GearTab.GetActiveViewName()
    if droppedItemLink or itemCheckModeActive then
        return "upgrade"
    end
    return "grid"
end

--- Highlight the sub-view tab that matches the current focus / item-check state.
function GearTab.SyncViewTabs()
    if VIEW.tabs then
        VIEW.tabs:SetSelected(GearTab.GetActiveViewName())
    end
end

local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerColumn, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(GearTab.GetPinnedHeaderHeight())
headerHorizontalScroll:SetScrollChild(headerGridContainer)

gridHost = CreateFrame("Frame", nil, gearMainInner)
gridHost:SetClipsChildren(true)
local horizontalScrollBar
local verticalScroll
local verticalScrollBar
local verticalScrollBinding
local scrollTopFade

function GearTab.LayoutVerticalScrollBar()
    if not verticalScrollBar or not verticalScroll or not fixedHeaderRow then return end
    Theme.AnchorVerticalScrollBar(verticalScrollBar, gearMainSection, verticalScroll, { gap = 0 })
    -- Extend track upward over the pinned header (Reputation spans contentArea including header).
    verticalScrollBar:SetPoint("TOPLEFT", fixedHeaderRow, "TOPRIGHT", verticalScrollBar.altArmyAnchorX or 0, 0)
end

function GearTab.LayoutGridHost()
    local chromeH = GearTab.GetHorizontalScrollChromeHeight()
    gridHost:ClearAllPoints()
    gridHost:SetPoint("TOPLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, 0)
    gridHost:SetPoint("TOPRIGHT", gearMainSection, "TOPRIGHT", -SCROLL_GUTTER, 0)
    gridHost:SetPoint("BOTTOMLEFT", gearMainInner, "BOTTOMLEFT", 0, 0)
    gridHost:SetPoint("BOTTOMRIGHT", gearMainSection, "BOTTOMRIGHT", -SCROLL_GUTTER, chromeH)
    if horizontalScrollBar then
        horizontalScrollBar:ClearAllPoints()
        horizontalScrollBar:SetPoint("BOTTOMLEFT", gearMainInner, "BOTTOMLEFT", 0, -4)
        horizontalScrollBar:SetPoint("BOTTOMRIGHT", gearMainSection, "BOTTOMRIGHT", -SCROLL_GUTTER, -4)
        horizontalScrollBar:SetFrameLevel(gearMainSection:GetFrameLevel() + 30)
        horizontalScrollBar:EnableMouse(true)
    end
    GearTab.LayoutVerticalScrollBar()
end

GearTab.LayoutGridHost()

-- Vertical scroll: grid area below pinned header
verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearVerticalScroll", gridHost)
verticalScroll:SetPoint("TOPLEFT", gridHost, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", gridHost, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

local MIN_SCROLL_CHILD_WIDTH = 400
local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

-- Vertical scroll bar (native MinimalScrollBar); the horizontal bar stays our own Slider.
verticalScrollBinding = Theme.CreateVerticalScrollBinding(verticalScroll, {
    parent = gearMainSection,
    name = "AltArmyTBC_GearVerticalScrollBar",
    step = dims.rowHeight * 2,
    onScroll = function()
        if scrollTopFade then scrollTopFade:Update() end
    end,
})
verticalScrollBar = verticalScrollBinding.bar
GearTab.LayoutVerticalScrollBar()

scrollTopFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = fixedHeaderRow,
    scrollFrame = verticalScroll,
    scrollBar = verticalScrollBar,
})

-- Mouse wheel over the scroll child (the ScrollFrame itself is wired by the binding).
function GearTab.OnGearScrollWheel(_, delta)
    verticalScrollBinding.Wheel(delta)
end
verticalScrollChild:SetScript("OnMouseWheel", GearTab.OnGearScrollWheel)

-- Row headers (slot names); scroll with equipment rows
local slotHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
slotHeaderContainer:SetHeight(dims.scrollableGridHeight)
slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
Theme.ApplyGridLabelColumnBackground(slotHeaderContainer)

-- Score row: pinned in header corner (provider selector + sort-direction button)
local scoreSortBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreSortBtn:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreSortBtn:SetSize(GearTab.GetScoreSortBtnSize(), GearTab.GetScoreSortBtnSize())
Theme.SkinButton(scoreSortBtn)

function GearTab.UpdateScoreSortButton()
    local descending = GearTab.GetGearSettings().scoreSortDescending ~= false
    Theme.SetSortArrowButton(scoreSortBtn, descending and "right" or "left")
    if GearTab.ApplyScoreSortLayout then
        GearTab.ApplyScoreSortLayout()
    end
end

scoreSortBtn:SetScript("OnClick", function()
    local s = GearTab.GetGearSettings()
    s.scoreSortDescending = not s.scoreSortDescending
    GearTab.UpdateScoreSortButton()
    if frame.RefreshGrid then frame:RefreshGrid() end
end)
GearTab.UpdateScoreSortButton()

local scoreProviderStaticLabel = headerCornerColumn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
scoreProviderStaticLabel:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 4, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderStaticLabel:SetHeight(GearTab.GetScoreRowContentHeight())
scoreProviderStaticLabel:SetJustifyH("LEFT")
scoreProviderStaticLabel:SetJustifyV("MIDDLE")
scoreProviderStaticLabel:SetText("Level")

local scoreProviderBtn = CreateFrame("Button", nil, headerCornerColumn)
scoreProviderBtn:SetPoint("BOTTOMLEFT", headerCornerColumn, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
scoreProviderBtn:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
scoreProviderBtn:SetHeight(GearTab.GetScoreRowContentHeight())
scoreProviderBtn:Hide()
Theme.SkinDropdownButton(scoreProviderBtn)
local scoreProviderBtnText = scoreProviderBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
scoreProviderBtnText:SetPoint("LEFT", scoreProviderBtn, "LEFT", 6, 0)
scoreProviderBtnText:SetPoint("RIGHT", scoreProviderBtn, "RIGHT",
    scoreProviderBtn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -2, 0)
scoreProviderBtnText:SetJustifyH("LEFT")

local scoreProviderDropdown = CreateFrame("Frame", nil, fixedHeaderRow, "BackdropTemplate")
scoreProviderDropdown:SetPoint("TOPLEFT", scoreProviderBtn, "BOTTOMLEFT", 0, -2)
scoreProviderDropdown:SetWidth(SCORE_PROVIDER_DROPDOWN_WIDTH)
scoreProviderDropdown:SetFrameLevel(fixedHeaderRow:GetFrameLevel() + 100)
scoreProviderDropdown:Hide()
Theme.SkinDropdownPopup(scoreProviderDropdown)
local scoreProviderDropdownButtons = {}

function GearTab.ApplyScoreSortLayout()
    local hideScore = GearTab.ShouldHideScoreHeader()
    if scoreSortBtn then
        scoreSortBtn:SetShown(not hideScore)
    end
    if scoreProviderStaticLabel then
        scoreProviderStaticLabel:SetShown(not hideScore)
    end
    if scoreProviderBtn then
        if hideScore then
            scoreProviderBtn:Hide()
        end
    end
    if hideScore then
        if scoreProviderDropdown then scoreProviderDropdown:Hide() end
        return
    end
    GearTab.UpdateScoreProviderControl()
    local showDirection = not droppedItemLink
    local bottomInset = SCORE_ROW_HEADER_BOTTOM_INSET
    if showDirection then
        scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
        scoreProviderBtn:SetPoint("BOTTOMRIGHT", scoreSortBtn, "BOTTOMLEFT", -SCORE_SORT_BTN_GAP, 0)
    else
        scoreProviderStaticLabel:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", -2, bottomInset)
        scoreProviderBtn:SetPoint("BOTTOMRIGHT", headerCornerColumn, "BOTTOMRIGHT", 0, bottomInset)
    end
end

function GearTab.UpdateScoreProviderControl()
    local providers = GearTab.GetAvailableScoreProviders()
    local selectedId = GearTab.GetSelectedScoreProvider()
    local label = GearTab.GetScoreProviderLabel(selectedId)
    if #providers <= 1 then
        scoreProviderStaticLabel:SetText(label)
        scoreProviderStaticLabel:Show()
        scoreProviderBtn:Hide()
        scoreProviderDropdown:Hide()
        return
    end
    scoreProviderStaticLabel:Hide()
    scoreProviderBtn:Show()
    scoreProviderBtnText:SetText(label)
end

function GearTab.UpdateScoreProviderDropdownSelection()
    local selectedId = GearTab.GetSelectedScoreProvider()
    for i = 1, #scoreProviderDropdownButtons do
        local b = scoreProviderDropdownButtons[i]
        if b.SetDropdownSelected then
            b:SetDropdownSelected(b.providerId == selectedId)
        end
    end
end

function GearTab.RebuildScoreProviderDropdown()
    for i = 1, #scoreProviderDropdownButtons do
        scoreProviderDropdownButtons[i]:Hide()
        scoreProviderDropdownButtons[i]:SetParent(nil)
    end
    wipe(scoreProviderDropdownButtons)
    local providers = GearTab.GetAvailableScoreProviders()
    if #providers <= 1 then
        scoreProviderDropdown:Hide()
        return
    end
    local insets = Theme.GetDropdownPopupInsets()
    scoreProviderDropdown:SetHeight(#providers * SETTINGS_ROW_HEIGHT + insets.top + insets.bottom)
    scoreProviderDropdown:SetWidth(SCORE_PROVIDER_DROPDOWN_WIDTH)
    for idx, provider in ipairs(providers) do
        local b = Theme.CreateDropdownMenuItem(scoreProviderDropdown, {
            index = idx,
            rowHeight = SETTINGS_ROW_HEIGHT,
            padTop = insets.top,
            padSide = insets.left,
            padRight = insets.right,
            text = provider.label,
            selected = provider.id == GearTab.GetSelectedScoreProvider(),
            onClick = function(self)
                GearTab.GetGearSettings().scoreProvider = self.providerId
                GearTab.UpdateScoreProviderDropdownSelection()
                scoreProviderDropdown:Hide()
                GearTab.UpdateScoreProviderControl()
                if frame.RefreshGrid then frame:RefreshGrid() end
            end,
        })
        b.providerId = provider.id
        scoreProviderDropdownButtons[idx] = b
    end
    Theme.FitDropdownPopupWidth(scoreProviderDropdown, scoreProviderDropdownButtons, SCORE_PROVIDER_DROPDOWN_WIDTH)
end

scoreProviderBtn:SetScript("OnClick", function()
    local show = not scoreProviderDropdown:IsShown()
    if show then
        GearTab.UpdateScoreProviderDropdownSelection()
    end
    scoreProviderDropdown:SetShown(show)
end)

-- Slot labels: height dims.cellSize and vertically centered in each row (row height is dims.rowHeight)
local SLOT_LABEL_ROW_OFFSET = (dims.rowHeight - dims.cellSize) / 2
local slotLabels = {}
for slot = 1, NUM_EQUIPMENT_SLOTS do
    local label = slotHeaderContainer:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
    label:SetWidth(SLOT_LABEL_WIDTH - 4)
    label:SetHeight(dims.cellSize)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetText(SLOT_NAMES[SLOT_ORDER[slot]] or ("Slot " .. slot))
    if slot == 1 then
        label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -SLOT_LABEL_ROW_OFFSET)
    else
        label:SetPoint("TOP", slotLabels[slot - 1], "TOP", 0, -dims.rowHeight)
    end
    slotLabels[slot] = label
end

-- Horizontal viewport: same vertical start as slot labels
local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_GearHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, 0)
horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
horizontalScroll:SetHeight(dims.scrollableGridHeight)
horizontalScroll:EnableMouse(true)

-- Grid area: scroll child of horizontalScroll; engine scrolls via SetHorizontalScroll (like vertical)
local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: name + message per character, in fixed header row (scrolls horizontally)
local headerColumnPool = {}
-- Pool of character column frames (cells only; reused)
local columnPool = {}

function GearTab.LayoutPinnedHeader()
    local headerH = GearTab.GetPinnedHeaderHeight()
    if fixedHeaderRow then
        fixedHeaderRow:SetHeight(headerH)
    end
    if headerGridContainer then
        headerGridContainer:SetHeight(headerH)
    end
    if headerCornerCell then
        if GearTab.ShouldHideMessageHeader() then
            headerCornerCell:Hide()
        else
            headerCornerCell:Show()
            headerCornerCell:SetHeight(FIXED_HEADER_ROW_HEIGHT)
        end
    end
    for _, col in pairs(headerColumnPool) do
        col:SetSize(dims.columnWidth, headerH)
    end
    GearTab.ApplyPinnedHeaderColumnVisibility()
    GearTab.ApplyScoreSortLayout()
end

function GearTab.ApplyPinnedHeaderColumnVisibility()
    local hideScore = GearTab.ShouldHideScoreHeader()
    local hideMessage = GearTab.ShouldHideMessageHeader()
    for _, col in pairs(headerColumnPool) do
        if col.message then
            col.message:SetShown(not hideMessage)
        end
        if col.scoreText then
            if hideScore then
                col.scoreText:Hide()
                col.scoreMissingEntry = nil
                if col.scoreHover then
                    col.scoreHover:Hide()
                    col.scoreHover:EnableMouse(false)
                end
            end
        end
    end
end

function GearTab.RefreshCompareHover()
    for _, col in pairs(columnPool) do
        if col:IsShown() and col.compareKey then
            for slot = 1, NUM_EQUIPMENT_SLOTS do
                local cell = col.cells[slot]
                if cell and cell:IsShown() and cell.isFocusCompareCell and cell.inventorySlot then
                    local cellKey = GearTab.MakeCompareCellKey(col.compareKey, cell.inventorySlot)
                    local show = droppedItemLink
                        and hoveredCompareKey == cellKey
                        and not GearTab.IsCompareCellSelected(col.compareKey, cell.inventorySlot)
                    GearTab.layoutCellCompareHover(cell, show)
                end
            end
        end
    end
end

function GearTab.AddCompareHover(key)
    if not key then return end
    compareHoverRefs[key] = (compareHoverRefs[key] or 0) + 1
    if hoveredCompareKey ~= key then
        hoveredCompareKey = key
        GearTab.RefreshCompareHover()
    end
end

function GearTab.RemoveCompareHover(key)
    if not key then return end
    local n = (compareHoverRefs[key] or 0) - 1
    if n <= 0 then
        compareHoverRefs[key] = nil
    else
        compareHoverRefs[key] = n
    end
    local function apply()
        local active = nil
        for k, count in pairs(compareHoverRefs) do
            if count > 0 then
                active = k
                break
            end
        end
        if active ~= hoveredCompareKey then
            hoveredCompareKey = active
            GearTab.RefreshCompareHover()
        end
    end
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(0, apply)
    else
        apply()
    end
end

function GearTab.GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Frame", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, GearTab.GetPinnedHeaderHeight())
        col:EnableMouse(true)
        col.header = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, COLUMN_HEADER_NAME_Y_OFFSET)
        col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, COLUMN_HEADER_NAME_Y_OFFSET)
        col.header:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
        col.header:SetJustifyH("CENTER")
        col.header:SetWordWrap(false)
        col.headerSelectionHighlight = col:CreateTexture(nil, "BACKGROUND", nil, -1)
        col.headerSelectionHighlight:Hide()
        col.message = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetPoint("LEFT", col, "LEFT", 0, 0)
        col.message:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.message:SetHeight(MESSAGE_ROW_HEIGHT)
        col.message:SetJustifyH("CENTER")
        col.message:SetWordWrap(true)
        col.message:SetNonSpaceWrap(true)
        col.scoreText = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        col.scoreText:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreText:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreText:SetHeight(GearTab.GetScoreRowContentHeight())
        col.scoreText:SetJustifyH("CENTER")
        col.scoreText:SetJustifyV("MIDDLE")
        col.scoreHover = CreateFrame("Frame", nil, col)
        col.scoreHover:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_HEADER_BOTTOM_INSET)
        col.scoreHover:SetHeight(GearTab.GetScoreRowContentHeight())
        col.scoreHover:EnableMouse(true)
        col.scoreHover:SetScript("OnEnter", function(self)
            local colFrame = self:GetParent()
            local e = colFrame and colFrame.scoreMissingEntry
            if e and SD and SD.PresentMissingDataTooltip then
                SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile)
            end
        end)
        col.scoreHover:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        col.selectionOutline = {}
        local function makeOutlineEdge(key)
            local tex = col:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(1, 1, 1, 0.95)
            tex:Hide()
            col.selectionOutline[key] = tex
        end
        makeOutlineEdge("top")
        makeOutlineEdge("bottom")
        makeOutlineEdge("left")
        makeOutlineEdge("right")
        col:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            local show = false
            if self.tooltipText and self.tooltipText ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                show = true
            end
            if droppedItemLink and self.compareKey then
                if not show then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                end
                GameTooltip:AddLine(GearTab.FormatCompareClickHint(), 0.7, 0.7, 0.7)
                show = true
            end
            if show then GameTooltip:Show() end
        end)
        col:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not droppedItemLink or not self.compareKey then return end
            local shift = IsShiftKeyDown and IsShiftKeyDown()
            local ctrl = IsControlKeyDown and IsControlKeyDown()
            if shift or ctrl then return end
            GearTab.SelectCompareCharacter(self.compareKey)
        end)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

-- Horizontal scroll bar: create after horizontalScroll/gridContainer exist so OnValueChanged sees them
local scrollGridLeftFade
local scrollHeaderLeftFade
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(gearMainSection, {
    name = "AltArmyTBC_GearHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
        if headerHorizontalScroll then
            if headerHorizontalScroll.UpdateScrollChildRect then
                headerHorizontalScroll:UpdateScrollChildRect()
            end
            headerHorizontalScroll:SetHorizontalScroll(value)
        end
        if scrollGridLeftFade then scrollGridLeftFade:Update() end
        if scrollHeaderLeftFade then scrollHeaderLeftFade:Update() end
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
horizontalScrollBar = horizontalScrollApi.bar
GearTab.LayoutGridHost()

scrollGridLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = horizontalScroll,
    scrollFrame = horizontalScroll,
    scrollBar = horizontalScrollBar,
})
scrollHeaderLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = headerHorizontalScroll,
    scrollFrame = horizontalScroll,
    scrollBar = horizontalScrollBar,
})

-- Item Check mode: header panel + instructions panel below.
itemCheckSection = Theme.CreateMainContentPanel(rightPanel)
itemCheckSection:Hide()
itemCheckInner = Theme.CreatePanelInnerContent(itemCheckSection)
itemCheckInner:EnableMouse(true)

local ITEM_CHECK_STACK_WIDTH = 420
local ITEM_CHECK_STACK_HEIGHT = 180

local itemCheckStack = CreateFrame("Frame", nil, itemCheckInner)
itemCheckStack:SetSize(ITEM_CHECK_STACK_WIDTH, ITEM_CHECK_STACK_HEIGHT)
itemCheckStack:SetPoint("CENTER", itemCheckInner, "CENTER", 0, 0)

local itemCheckMessage = itemCheckStack:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
itemCheckMessage:SetPoint("TOP", itemCheckStack, "TOP", 0, 0)
itemCheckMessage:SetWidth(ITEM_CHECK_STACK_WIDTH)
itemCheckMessage:SetJustifyH("CENTER")
itemCheckMessage:SetWordWrap(true)
itemCheckMessage:SetText(GearTab.FormatItemCheckDropMessage())
if Theme.SetLabelColor then
    Theme.SetLabelColor(itemCheckMessage)
end

local itemCheckDrop = CreateFrame("Frame", nil, itemCheckStack, "BackdropTemplate")
itemCheckDrop:SetSize(44, 44)
itemCheckDrop:SetPoint("TOP", itemCheckMessage, "BOTTOM", 0, -14)
itemCheckDrop:SetPoint("LEFT", itemCheckStack, "LEFT", (ITEM_CHECK_STACK_WIDTH - 44) / 2, 0)
itemCheckDrop:EnableMouse(true)

local itemCheckDropGlow = itemCheckDrop:CreateTexture(nil, "BACKGROUND")
itemCheckDropGlow:SetPoint("TOPLEFT", itemCheckDrop, "TOPLEFT", -5, 5)
itemCheckDropGlow:SetPoint("BOTTOMRIGHT", itemCheckDrop, "BOTTOMRIGHT", 5, -5)
if Theme.ApplySettingsGlow then
    Theme.ApplySettingsGlow(itemCheckDropGlow)
end
itemCheckDropGlow:Hide()

Theme.ApplyBackdrop(itemCheckDrop, "section")

local itemCheckDropHover = itemCheckDrop:CreateTexture(nil, "BACKGROUND")
itemCheckDropHover:SetAllPoints(true)
itemCheckDropHover:SetTexture(Theme.HOVER_TINT_BG or "Interface\\Tooltips\\UI-Tooltip-Background")
itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)

function GearTab.setItemCheckDropHighlighted(on)
    if on then
        itemCheckDropGlow:Show()
        itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0.45)
        local colors = Theme.COLORS
        if colors and itemCheckDrop.SetBackdropColor then
            local bg = colors.btnHoverBg
            local border = colors.btnActiveBorder
            itemCheckDrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            itemCheckDrop:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end
    else
        itemCheckDropGlow:Hide()
        itemCheckDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)
        Theme.ApplyBackdrop(itemCheckDrop, "section")
    end
end

itemCheckDrop:SetScript("OnEnter", function()
    GearTab.setItemCheckDropHighlighted(true)
end)
itemCheckDrop:SetScript("OnLeave", function()
    GearTab.setItemCheckDropHighlighted(false)
end)

local itemCheckDropIcon = itemCheckDrop:CreateTexture(nil, "OVERLAY")
itemCheckDropIcon:SetSize(32, 32)
itemCheckDropIcon:SetPoint("CENTER", itemCheckDrop, "CENTER", 0, 0)
itemCheckDropIcon:Hide()

local itemCheckError = itemCheckStack:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
itemCheckError:SetPoint("TOP", itemCheckDrop, "BOTTOM", 0, -14)
itemCheckError:SetWidth(ITEM_CHECK_STACK_WIDTH)
itemCheckError:SetJustifyH("CENTER")
itemCheckError:SetWordWrap(true)
itemCheckError:SetTextColor(1, 0.4, 0.3, 1)
itemCheckError:Hide()

function GearTab.clearItemCheckError()
    itemCheckError:SetText("")
    itemCheckError:Hide()
end

function GearTab.showItemCheckError(msg)
    itemCheckError:SetText(msg or "")
    itemCheckError:Show()
end

function GearTab.resetItemCheckDrop()
    itemCheckDropIcon:Hide()
    GearTab.clearItemCheckError()
end

function GearTab.getCursorItemLink()
    if not GetCursorInfo then return nil end
    local infoType, param2, itemLink = GetCursorInfo()
    if infoType == "item" and itemLink then return itemLink end
    if infoType == "merchant" and GetMerchantItemLink then
        return GetMerchantItemLink(param2)
    end
    return nil
end

function GearTab.applyItemCheckDrop(itemLink)
    GearTab.ApplyFocusedItem(itemLink, { manual = true })
    GearTab.exitItemCheckMode()
    GearTab.SyncViewTabs()
    if frame.RefreshGrid then frame:RefreshGrid() end
end

function GearTab.tryAcceptItemCheckDrop()
    local itemLink = GearTab.getCursorItemLink()
    if not itemLink then return false end

    local ok, errMsg = true, nil
    if IU and IU.ValidateItemCheckDrop then
        ok, errMsg = IU.ValidateItemCheckDrop(itemLink)
    end
    if not ok then
        itemCheckDropIcon:Hide()
        GearTab.showItemCheckError(errMsg)
        return false
    end

    if ClearCursor then ClearCursor() end
    GearTab.applyItemCheckDrop(itemLink)
    return true
end

itemCheckDrop:SetScript("OnReceiveDrag", GearTab.tryAcceptItemCheckDrop)
itemCheckDrop:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        GearTab.resetItemCheckDrop()
        return
    end
    GearTab.tryAcceptItemCheckDrop()
end)

compareStatsSection = Theme.CreateMainContentPanel(rightPanel)
compareStatsSection:Hide()
compareStatsInner = Theme.CreatePanelInnerContent(compareStatsSection)

local compareItemsRow = CreateFrame("Frame", nil, compareStatsInner)
compareItemsRow:SetPoint("TOPLEFT", compareStatsInner, "TOPLEFT", 0, 0)
compareItemsRow:SetPoint("TOPRIGHT", compareStatsInner, "TOPRIGHT", 0, 0)
compareItemsRow:SetHeight(COMPARE_FOCUS_HEADER_HEIGHT)

local compareFocusRow = CreateFrame("Frame", nil, compareItemsRow)
compareFocusRow:SetHeight(COMPARE_FOCUS_HEADER_HEIGHT)
compareFocusRow:SetPoint("CENTER", compareItemsRow, "CENTER", 0, 0)

local compareFocusDrop = CreateFrame("Frame", nil, compareFocusRow, "BackdropTemplate")
compareFocusDrop:SetSize(COMPARE_FOCUS_DROP_SIZE, COMPARE_FOCUS_DROP_SIZE)
compareFocusDrop:EnableMouse(true)
Theme.ApplyBackdrop(compareFocusDrop, "section")

local compareFocusDropGlow = compareFocusDrop:CreateTexture(nil, "BACKGROUND")
compareFocusDropGlow:SetPoint("TOPLEFT", compareFocusDrop, "TOPLEFT", -5, 5)
compareFocusDropGlow:SetPoint("BOTTOMRIGHT", compareFocusDrop, "BOTTOMRIGHT", 5, -5)
if Theme.ApplySettingsGlow then
    Theme.ApplySettingsGlow(compareFocusDropGlow)
end
compareFocusDropGlow:Hide()

local compareFocusDropHover = compareFocusDrop:CreateTexture(nil, "BACKGROUND")
compareFocusDropHover:SetAllPoints(true)
compareFocusDropHover:SetTexture(Theme.HOVER_TINT_BG or "Interface\\Tooltips\\UI-Tooltip-Background")
compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)

function GearTab.setCompareFocusDropHighlighted(on)
    if on then
        compareFocusDropGlow:Show()
        compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0.45)
        local colors = Theme.COLORS
        if colors and compareFocusDrop.SetBackdropColor then
            local bg = colors.btnHoverBg
            local border = colors.btnActiveBorder
            compareFocusDrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            compareFocusDrop:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end
    else
        compareFocusDropGlow:Hide()
        compareFocusDropHover:SetVertexColor(0.82, 0.68, 0.22, 0)
        Theme.ApplyBackdrop(compareFocusDrop, "section")
    end
end

compareFocusDrop:SetScript("OnEnter", function(self)
    GearTab.setCompareFocusDropHighlighted(true)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if droppedItemLink and droppedItemLink ~= "" then
        GameTooltip:SetHyperlink(droppedItemLink)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Drop an item to check upgrades", 1, 1, 1)
    end
    GameTooltip:Show()
end)
compareFocusDrop:SetScript("OnLeave", function()
    GearTab.setCompareFocusDropHighlighted(false)
    if GameTooltip then GameTooltip:Hide() end
end)

local compareFocusDropIcon = compareFocusDrop:CreateTexture(nil, "OVERLAY")
compareFocusDropIcon:SetSize(32, 32)
compareFocusDropIcon:SetPoint("CENTER", compareFocusDrop, "CENTER", 0, 0)
compareFocusDropIcon:Hide()

local compareFocusVs = compareFocusRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
compareFocusVs:SetText(GearTab.FormatCompareFocusVsLabel())
if Theme.SetLabelColor then
    Theme.SetLabelColor(compareFocusVs)
end
compareFocusVs:Hide()

local compareFocusEquipped = CreateFrame("Frame", nil, compareFocusRow, "BackdropTemplate")
compareFocusEquipped:SetSize(COMPARE_FOCUS_DROP_SIZE, COMPARE_FOCUS_DROP_SIZE)
compareFocusEquipped:EnableMouse(true)
Theme.ApplyBackdrop(compareFocusEquipped, "section")
compareFocusEquipped:Hide()

local compareFocusEquippedIcon = compareFocusEquipped:CreateTexture(nil, "ARTWORK")
compareFocusEquippedIcon:SetPoint("TOPLEFT", compareFocusEquipped, "TOPLEFT", ITEM_ICON_INSET, -ITEM_ICON_INSET)
compareFocusEquippedIcon:SetPoint("BOTTOMRIGHT", compareFocusEquipped, "BOTTOMRIGHT", -ITEM_ICON_INSET, ITEM_ICON_INSET)
compareFocusEquipped.texture = compareFocusEquippedIcon

compareFocusEquipped:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemLink and self.itemLink ~= "" then
        GameTooltip:SetHyperlink(self.itemLink)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Empty slot", 1, 1, 1)
    end
    GameTooltip:Show()
end)
compareFocusEquipped:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
end)

local COMPARE_HEADER_EXTRA_MAX = 2
local compareFocusExtraIcons = {}
local compareEquippedExtraIcons = {}
local DEDUCED_HINT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function attachCompareHeaderDeducedHint(iconFrame)
    if iconFrame.deducedHint then return iconFrame.deducedHint end
    local hint = CreateFrame("Button", nil, iconFrame)
    hint:SetSize(14, 14)
    hint:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 3, 3)
    local tex = hint:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(DEDUCED_HINT_ICON)
    hint:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.hintText or self.hintText == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.hintText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hint:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    hint:Hide()
    iconFrame.deducedHint = hint
    return hint
end

function GearTab.SetCompareHeaderDeducedHint(iconFrame, hintText)
    if not iconFrame then return end
    local hint = attachCompareHeaderDeducedHint(iconFrame)
    if hintText and hintText ~= "" then
        hint.hintText = hintText
        hint:Show()
    else
        hint.hintText = nil
        hint:Hide()
    end
end

local function createCompareHeaderIconFrame(parent)
    local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    iconFrame:SetSize(COMPARE_FOCUS_DROP_SIZE, COMPARE_FOCUS_DROP_SIZE)
    iconFrame:EnableMouse(true)
    Theme.ApplyBackdrop(iconFrame, "section")
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", ITEM_ICON_INSET, -ITEM_ICON_INSET)
    icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -ITEM_ICON_INSET, ITEM_ICON_INSET)
    iconFrame.texture = icon
    iconFrame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink and self.itemLink ~= "" then
            GameTooltip:SetHyperlink(self.itemLink)
        end
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    iconFrame:Hide()
    return iconFrame
end

local function ensureCompareHeaderExtraFrame(pool, index, parent)
    if not pool[index] then
        pool[index] = createCompareHeaderIconFrame(parent)
    end
    return pool[index]
end

function GearTab.HideCompareHeaderExtras()
    for i = 1, #compareFocusExtraIcons do
        compareFocusExtraIcons[i]:Hide()
        GearTab.SetCompareHeaderDeducedHint(compareFocusExtraIcons[i], nil)
    end
    for i = 1, #compareEquippedExtraIcons do
        compareEquippedExtraIcons[i]:Hide()
        GearTab.SetCompareHeaderDeducedHint(compareEquippedExtraIcons[i], nil)
    end
    GearTab.SetCompareHeaderDeducedHint(compareFocusDrop, nil)
    GearTab.SetCompareHeaderDeducedHint(compareFocusEquipped, nil)
end

function GearTab.ApplyCompareFocusHeaderLoadout(loadoutHeader)
    if not loadoutHeader then
        GearTab.HideCompareHeaderExtras()
        return
    end
    local focused = loadoutHeader.focusedLinks or {}
    local equipped = loadoutHeader.equippedLinks or {}
    local focusedHints = loadoutHeader.focusedHints or {}
    local equippedHints = loadoutHeader.equippedHints or {}

    if focused[1] then
        GearTab.updateCompareFocusDrop(focused[1])
        GearTab.SetCompareHeaderDeducedHint(compareFocusDrop, focusedHints[1])
    end
    for i = 1, COMPARE_HEADER_EXTRA_MAX do
        local extraFrame = ensureCompareHeaderExtraFrame(compareFocusExtraIcons, i, compareFocusRow)
        local link = focused[i + 1]
        if link then
            GearTab.SetCompareItemIcon(extraFrame, link)
            GearTab.SetCompareHeaderDeducedHint(extraFrame, focusedHints[i + 1])
            extraFrame:Show()
        else
            GearTab.SetCompareHeaderDeducedHint(extraFrame, nil)
            extraFrame:Hide()
        end
    end

    GearTab.updateCompareFocusEquipped(equipped[1])
    GearTab.SetCompareHeaderDeducedHint(compareFocusEquipped, equippedHints[1])
    for i = 1, COMPARE_HEADER_EXTRA_MAX do
        local extraFrame = ensureCompareHeaderExtraFrame(compareEquippedExtraIcons, i, compareFocusRow)
        local link = equipped[i + 1]
        if link then
            GearTab.SetCompareItemIcon(extraFrame, link)
            GearTab.SetCompareHeaderDeducedHint(extraFrame, equippedHints[i + 1])
            extraFrame:Show()
        else
            GearTab.SetCompareHeaderDeducedHint(extraFrame, nil)
            extraFrame:Hide()
        end
    end
end

local compareFocusError = compareItemsRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
compareFocusError:SetPoint("TOP", compareItemsRow, "BOTTOM", 0, -2)
compareFocusError:SetPoint("LEFT", compareItemsRow, "LEFT", 8, 0)
compareFocusError:SetPoint("RIGHT", compareItemsRow, "RIGHT", -8, 0)
compareFocusError:SetJustifyH("CENTER")
compareFocusError:SetWordWrap(true)
compareFocusError:SetTextColor(1, 0.4, 0.3, 1)
compareFocusError:Hide()

function GearTab.clearCompareFocusError()
    if compareFocusError then
        compareFocusError:SetText("")
        compareFocusError:Hide()
    end
end

function GearTab.showCompareFocusError(msg)
    if compareFocusError then
        compareFocusError:SetText(msg or "")
        compareFocusError:Show()
    end
end

function GearTab.updateCompareFocusDrop(itemLink)
    if not compareFocusDropIcon then return end
    if itemLink then
        local tex = GearTab.GetItemTexture(itemLink)
        if tex then
            compareFocusDropIcon:SetTexture(tex)
            compareFocusDropIcon:Show()
        else
            compareFocusDropIcon:Hide()
        end
    else
        compareFocusDropIcon:Hide()
    end
    GearTab.clearCompareFocusError()
end

function GearTab.tryAcceptCompareFocusDrop()
    local itemLink = GearTab.getCursorItemLink()
    if not itemLink then return false end

    local ok, errMsg = true, nil
    if IU and IU.ValidateItemCheckDrop then
        ok, errMsg = IU.ValidateItemCheckDrop(itemLink)
    end
    if not ok then
        GearTab.updateCompareFocusDrop(droppedItemLink)
        GearTab.showCompareFocusError(errMsg)
        return false
    end

    if ClearCursor then ClearCursor() end
    GearTab.ApplyFocusedItem(itemLink, { manual = true })
    GearTab.updateCompareFocusDrop(itemLink)
    GearTab.SyncViewTabs()
    if frame.RefreshGrid then frame:RefreshGrid() end
    return true
end

compareFocusDrop:SetScript("OnReceiveDrag", GearTab.tryAcceptCompareFocusDrop)
compareFocusDrop:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        droppedItemLink = nil
        GearTab.ClearCompareSelection()
        GearTab.updateCompareFocusDrop(nil)
        GearTab.enterItemCheckMode()
        return
    end
    GearTab.tryAcceptCompareFocusDrop()
end)

local compareEmptyHintArea = CreateFrame("Frame", nil, compareStatsInner)
compareEmptyHintArea:SetPoint("TOPLEFT", compareItemsRow, "BOTTOMLEFT", 0, 0)
compareEmptyHintArea:SetPoint("BOTTOMRIGHT", compareStatsInner, "BOTTOMRIGHT", 0, 0)
compareEmptyHintArea:Hide()

local compareEmptyHint = compareEmptyHintArea:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
compareEmptyHint:SetPoint("LEFT", compareEmptyHintArea, "LEFT", 12, 0)
compareEmptyHint:SetPoint("RIGHT", compareEmptyHintArea, "RIGHT", -12, 0)
compareEmptyHint:SetPoint("CENTER", compareEmptyHintArea, "CENTER", 0, 0)
compareEmptyHint:SetJustifyH("CENTER")
compareEmptyHint:SetJustifyV("MIDDLE")
compareEmptyHint:SetWordWrap(true)
compareEmptyHint:Hide()

local compareLeftPanel = CreateFrame("Frame", nil, compareStatsInner)
compareLeftPanel:SetClipsChildren(true)
local compareRightPanel = CreateFrame("Frame", nil, compareStatsInner)
compareRightPanel:SetClipsChildren(true)

local compareWarningContainer = CreateFrame("Frame", nil, compareLeftPanel)
local compareWarningRows = {}

local compareVerdictRow = CreateFrame("Frame", nil, compareLeftPanel)
compareVerdictRow:SetHeight(COMPARE_ROW_HEIGHT)
compareVerdictRow:Hide()
local compareVerdictPrefix = compareVerdictRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
compareVerdictPrefix:SetJustifyH("RIGHT")
compareVerdictPrefix:SetText("Verdict for ")
local compareVerdictLabel = compareVerdictRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
compareVerdictLabel:SetPoint("RIGHT", compareVerdictRow, "RIGHT", 0, 0)
compareVerdictLabel:SetJustifyH("RIGHT")
compareVerdictPrefix:SetPoint("RIGHT", compareVerdictLabel, "LEFT", 0, 0)

local compareDumpRow = CreateFrame("Frame", nil, compareLeftPanel)
compareDumpRow:SetHeight(SETTINGS_ROW_HEIGHT)
compareDumpRow:Hide()

local compareDumpBtn = CreateFrame("Button", nil, compareDumpRow)
compareDumpBtn:SetSize(52, SETTINGS_ROW_HEIGHT)
compareDumpBtn:SetPoint("TOPRIGHT", compareDumpRow, "TOPRIGHT", 0, 0)
if Theme.SkinButton then
    Theme.SkinButton(compareDumpBtn)
end
local compareDumpLabel = compareDumpBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
compareDumpLabel:SetPoint("CENTER", compareDumpBtn, "CENTER", 0, 0)
compareDumpLabel:SetTextColor(1, 1, 1, 1)
compareDumpLabel:SetText("Dump")
compareDumpBtn:SetScript("OnClick", function()
    GearTab.DumpComparePanelDebug()
end)

function GearTab.DumpComparePanelDebug()
    local D = AltArmy and AltArmy.Debug
    if not D or not D.IsEnabled or not D.IsEnabled() then
        if D and D.NotifyChat then
            D.NotifyChat("Enable debug first: /altarmy debug on")
        end
        return
    end
    local ctx = comparePanelContext or GearTab.CollectComparePanelContext()
    if not ctx then
        if D.NotifyChat then
            D.NotifyChat("Focus an item and select a character column to compare first.")
        end
        return
    end
    if not GC or not GC.SaveComparePanelDump then return end
    local saved = GC.SaveComparePanelDump(
        ctx.focusedLink,
        ctx.equippedLink,
        ctx.technique,
        ctx.charData,
        ctx.entry,
        {
            invSlot = ctx.invSlot,
            upgradeMaxDelta = ctx.upgradeMaxDelta,
            focusOpts = ctx.focusOpts,
            forceRefresh = true,
        })
    if not saved then return end
    if D.NotifyCompareDumpSaved then
        D.NotifyCompareDumpSaved(saved, saved)
    end
end

frame.DumpComparePanelDebug = function()
    GearTab.DumpComparePanelDebug()
end

function GearTab.LayoutCompareDumpRow(anchorBelow)
    if not compareDumpRow then return end
    compareDumpRow:ClearAllPoints()
    local D = AltArmy and AltArmy.Debug
    if not (D and D.IsEnabled and D.IsEnabled()) then
        compareDumpRow:Hide()
        return
    end
    local ref = anchorBelow or compareLeftPanel
    local refTopLeft = anchorBelow and "BOTTOMLEFT" or "TOPLEFT"
    local refTopRight = anchorBelow and "BOTTOMRIGHT" or "TOPRIGHT"
    local y = anchorBelow and -COMPARE_ROW_GAP or 0
    compareDumpRow:SetPoint("TOPLEFT", ref, refTopLeft, 0, y)
    compareDumpRow:SetPoint("TOPRIGHT", ref, refTopRight, -COMPARE_STAT_ROW_INDENT, y)
    compareDumpRow:Show()
end

local compareStatUI = {
    dataRows = {},
    sectionsCache = nil,
    weightedCache = nil,
    weightedPinned = false,
    weightedFooterRow = nil,
}
compareStatUI.scrollApi = Theme.CreateVerticalScrollViewport({
    parent = compareRightPanel,
    gutterEdge = compareRightPanel,
    name = "AltArmyTBC_CompareStatScroll",
    anchorTop = { "TOPLEFT", compareRightPanel, "TOPLEFT", 0, 0 },
    valueStep = COMPARE_ROW_HEIGHT + COMPARE_ROW_GAP,
    wheelStep = (COMPARE_ROW_HEIGHT + COMPARE_ROW_GAP) * 2,
    enableMouse = true,
    enableMouseWheel = true,
})
compareStatUI.scroll = compareStatUI.scrollApi.scroll
compareStatUI.scrollBar = compareStatUI.scrollApi.scrollBar
compareStatUI.container = compareStatUI.scrollApi.child
compareStatUI.weightedFooter = CreateFrame("Frame", nil, compareRightPanel)
compareStatUI.weightedFooter:SetHeight(COMPARE_ROW_HEIGHT)
compareStatUI.weightedFooter:Hide()

function GearTab.LayoutCompareStatScrollArea(pinWeighted)
    local scroll = compareStatUI.scroll
    local footer = compareStatUI.weightedFooter
    if not scroll then return end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", compareRightPanel, "TOPLEFT", 0, 0)
    if pinWeighted and footer then
        footer:ClearAllPoints()
        footer:SetPoint("BOTTOMLEFT", compareRightPanel, "BOTTOMLEFT", 0, 0)
        footer:SetPoint("BOTTOMRIGHT", compareRightPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
        footer:Show()
        scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, COMPARE_ROW_GAP)
    else
        if footer then
            footer:Hide()
        end
        scroll:SetPoint("BOTTOMRIGHT", compareRightPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
    end
    compareStatUI.weightedPinned = pinWeighted and true or false
end

GearTab.LayoutCompareStatScrollArea(false)

function GearTab.updateCompareFocusEquipped(itemLink)
    if not compareFocusEquipped then return end
    GearTab.SetCompareItemIcon(compareFocusEquipped, itemLink)
end

function GearTab.GetSelectedEquippedCompareLink(list, technique)
    if not GearTab.HasCompareSelection() or not GC or not GC.GetEquippedCompareItem then return nil end
    local entry = GearTab.GetSelectedCompareEntry(list)
    if not entry or not droppedItemLink then return nil end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    if not charData then return nil end
    return GC.GetEquippedCompareItem(charData, droppedItemLink, {
        technique = technique or GearTab.GetSessionCompareTechnique(),
        slot = selectedCompareSlot,
        entry = entry,
    })
end

function GearTab.LayoutCompareFocusInline(showCompareTarget, loadoutHeader)
    if not compareFocusDrop or not compareFocusRow then return end
    local gap = COMPARE_FOCUS_TITLE_GAP
    compareFocusDrop:ClearAllPoints()
    compareFocusDrop:SetPoint("LEFT", compareFocusRow, "LEFT", 0, 0)

    local rowW = COMPARE_FOCUS_DROP_SIZE
    local focusAnchor = compareFocusDrop
    local focusExtraCount = 0
    if loadoutHeader and loadoutHeader.focusedLinks then
        focusExtraCount = math.max(0, #loadoutHeader.focusedLinks - 1)
    end
    for i = 1, COMPARE_HEADER_EXTRA_MAX do
        local extraFrame = compareFocusExtraIcons[i]
        if extraFrame then
            extraFrame:ClearAllPoints()
            if i <= focusExtraCount and extraFrame:IsShown() then
                extraFrame:SetPoint("LEFT", focusAnchor, "RIGHT", gap, 0)
                focusAnchor = extraFrame
                rowW = rowW + gap + COMPARE_FOCUS_DROP_SIZE
            end
        end
    end

    if showCompareTarget and compareFocusVs and compareFocusEquipped then
        compareFocusVs:Show()
        compareFocusEquipped:Show()
        compareFocusVs:ClearAllPoints()
        compareFocusEquipped:ClearAllPoints()
        compareFocusVs:SetPoint("LEFT", focusAnchor, "RIGHT", gap, 0)
        compareFocusEquipped:SetPoint("LEFT", compareFocusVs, "RIGHT", gap, 0)
        rowW = rowW + gap + (compareFocusVs:GetStringWidth() or 0) + gap + COMPARE_FOCUS_DROP_SIZE

        local equipAnchor = compareFocusEquipped
        local equipExtraCount = 0
        if loadoutHeader and loadoutHeader.equippedLinks then
            equipExtraCount = math.max(0, #loadoutHeader.equippedLinks - 1)
        end
        for i = 1, COMPARE_HEADER_EXTRA_MAX do
            local extraFrame = compareEquippedExtraIcons[i]
            if extraFrame then
                extraFrame:ClearAllPoints()
                if i <= equipExtraCount and extraFrame:IsShown() then
                    extraFrame:SetPoint("LEFT", equipAnchor, "RIGHT", gap, 0)
                    equipAnchor = extraFrame
                    rowW = rowW + gap + COMPARE_FOCUS_DROP_SIZE
                end
            end
        end
    elseif compareFocusVs and compareFocusEquipped then
        compareFocusVs:Hide()
        compareFocusEquipped:Hide()
        GearTab.HideCompareHeaderExtras()
    end
    compareFocusRow:SetWidth(rowW)
    compareFocusRow:SetPoint("CENTER", compareItemsRow, "CENTER", 0, 0)
end

function GearTab.UpdateCompareFocusHeader(itemLink, equippedLink, loadoutHeader)
    if compareFocusVs then
        compareFocusVs:SetText(GearTab.FormatCompareFocusVsLabel())
    end
    local showCompareTarget = GearTab.HasCompareSelection()
    if loadoutHeader then
        GearTab.ApplyCompareFocusHeaderLoadout(loadoutHeader)
    else
        GearTab.HideCompareHeaderExtras()
        GearTab.updateCompareFocusDrop(itemLink)
        if showCompareTarget then
            GearTab.updateCompareFocusEquipped(equippedLink)
        else
            GearTab.updateCompareFocusEquipped(nil)
        end
    end
    GearTab.LayoutCompareFocusInline(showCompareTarget, loadoutHeader)
    GearTab.LayoutComparePanelBody()
    if compareItemsRow then compareItemsRow:Show() end
end

GearTab.LayoutCompareFocusInline(false)

function GearTab.ShowCompareEmptyHint(list)
    list = list or GearTab.GetDisplayList()
    if compareEmptyHint then
        local hasUpgrade = GearTab.HasAnyUpgradeOrEventualUpgrade(list)
        compareEmptyHint:SetText(GearTab.FormatCompareEmptyHintText(hasUpgrade))
        compareEmptyHint:Show()
    end
    if compareEmptyHintArea then compareEmptyHintArea:Show() end
    if compareWarningContainer then compareWarningContainer:Hide() end
    if compareVerdictRow then compareVerdictRow:Hide() end
    if compareDumpRow then compareDumpRow:Hide() end
    if compareStatUI.scroll then compareStatUI.scroll:Hide() end
    if compareStatUI.scrollBar then compareStatUI.scrollBar:Hide() end
    if compareStatUI.weightedFooter then compareStatUI.weightedFooter:Hide() end
    GearTab.HideCompareWarningRows()
    GearTab.HideCompareStatRows()
end

function GearTab.HideCompareEmptyHint()
    if compareEmptyHint then compareEmptyHint:Hide() end
    if compareEmptyHintArea then compareEmptyHintArea:Hide() end
    if compareStatUI.scroll then compareStatUI.scroll:Show() end
end

function GearTab.ShowCompareEmptyState(itemLink, equippedLink, list)
    GearTab.UpdateCompareFocusHeader(itemLink, equippedLink)
    GearTab.ShowCompareEmptyHint(list)
end

function GearTab.HideCompareEmptyState()
    GearTab.HideCompareEmptyHint()
end

--- Measuring FontString matching compare-panel body text.
function GearTab.GetCompareNameMeasure()
    if not compareStatUI.nameMeasure then
        local fs = compareLeftPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        fs:SetPoint("TOPLEFT", compareLeftPanel, "TOPLEFT", 0, 0)
        fs:SetAlpha(0)
        compareStatUI.nameMeasure = fs
    end
    return compareStatUI.nameMeasure
end

--- Hover hit area over a shortened (first-name) character name inside a right-justified
--- FontString; the tooltip shows the full class-colored name, plus " — realm" when the global
--- realm filter shows all realms. Hidden when nothing was shortened.
function GearTab.GetCompareNameHit(parent)
    if not parent.nameHit then
        local hit = CreateFrame("Frame", nil, parent)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            if not self.fullName then return end
            local RF = AltArmy.RealmFilter
            local GRF = AltArmy.GlobalRealmFilter
            local showRealm = (GRF and GRF.Get and GRF.Get() == "all") or false
            local label = RF and RF.formatColoredCharacterNameRealm
                and RF.formatColoredCharacterNameRealm(
                    self.fullName, self.realm, showRealm, self.classFile, false)
                or self.fullName
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent.nameHit = hit
    end
    return parent.nameHit
end

function GearTab.PositionCompareNameHit(parent, fontString, text, nameText, fullName, classFile, realm)
    local hit = GearTab.GetCompareNameHit(parent)
    hit:Hide()
    if type(text) ~= "string" or type(nameText) ~= "string" or type(fullName) ~= "string" then
        return
    end
    if not CC or not CC.firstName or CC.firstName(fullName) == fullName then return end
    local startIdx = text:find(nameText, 1, true)
    if not startIdx then return end
    local measure = GearTab.GetCompareNameMeasure()
    measure:SetText(text)
    local totalW = measure:GetStringWidth() or 0
    measure:SetText(text:sub(1, startIdx - 1))
    local prefixW = (startIdx > 1) and (measure:GetStringWidth() or 0) or 0
    measure:SetText(nameText)
    local nameW = measure:GetStringWidth() or 0
    if nameW <= 0 then return end
    hit.fullName = fullName
    hit.classFile = classFile
    hit.realm = realm
    hit:ClearAllPoints()
    hit:SetPoint("LEFT", fontString, "RIGHT", -(totalW - prefixW), 0)
    hit:SetSize(nameW, COMPARE_ROW_HEIGHT)
    hit:Show()
end

function GearTab.HideCompareWarningRows()
    for i = 1, #compareWarningRows do
        compareWarningRows[i]:Hide()
    end
end

function GearTab.GetCompareWarningRow(index)
    if not compareWarningRows[index] then
        local row = CreateFrame("Frame", nil, compareWarningContainer)
        row:SetHeight(COMPARE_ROW_HEIGHT)

        local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        label:SetJustifyH("RIGHT")

        row.label = label
        compareWarningRows[index] = row
    end
    return compareWarningRows[index]
end

function GearTab.LayoutComparePanelBody()
    compareLeftPanel:ClearAllPoints()
    compareLeftPanel:SetPoint("TOPLEFT", compareItemsRow, "BOTTOMLEFT", 0, -8)
    compareLeftPanel:SetPoint("BOTTOMLEFT", compareStatsInner, "BOTTOMLEFT", 0, 0)
    compareLeftPanel:SetPoint("RIGHT", compareStatsInner, "CENTER", -COMPARE_PANEL_SPLIT_GAP / 2, 0)

    compareRightPanel:ClearAllPoints()
    compareRightPanel:SetPoint("TOPLEFT", compareLeftPanel, "TOPRIGHT", COMPARE_PANEL_SPLIT_GAP, 0)
    compareRightPanel:SetPoint("BOTTOMRIGHT", compareStatsInner, "BOTTOMRIGHT", 0, 0)

    if compareStatUI.sectionsCache then
        GearTab.RefreshCompareStatWeightedPin()
    elseif compareStatUI.scrollApi then
        compareStatUI.scrollApi.UpdateRange()
    end
end

function GearTab.LayoutComparePanelSections(warnings, verdict, entry)
    GearTab.LayoutComparePanelBody()
    local anchor = compareLeftPanel
    GearTab.HideCompareWarningRows()

    if compareVerdictRow then
        compareVerdictRow:ClearAllPoints()
        if verdict and verdict.label then
            local charName = entry and entry.name or "?"
            local classFile = entry and entry.classFile or nil
            local prefixText, nameText = GearTab.FormatCompareVerdictPrefix(charName, classFile)
            compareVerdictPrefix:SetText(prefixText)
            GearTab.PositionCompareNameHit(
                compareVerdictRow, compareVerdictPrefix, prefixText, nameText, charName, classFile,
                entry and entry.realm)
            compareVerdictLabel:SetText(verdict.label)
            compareVerdictLabel:SetTextColor(verdict.r or 1, verdict.g or 1, verdict.b or 1, 1)
            compareVerdictRow:SetPoint("TOPLEFT", compareLeftPanel, "TOPLEFT", 0, 0)
            compareVerdictRow:SetPoint("TOPRIGHT", compareLeftPanel, "TOPRIGHT", -COMPARE_STAT_ROW_INDENT, 0)
            compareVerdictRow:Show()
            anchor = compareVerdictRow
        else
            compareVerdictRow:Hide()
        end
    end

    local warningCount = warnings and #warnings or 0
    compareWarningContainer:ClearAllPoints()
    if warningCount > 0 then
        if anchor == compareLeftPanel then
            compareWarningContainer:SetPoint("TOPLEFT", compareLeftPanel, "TOPLEFT", 0, 0)
            compareWarningContainer:SetPoint("TOPRIGHT", compareLeftPanel, "TOPRIGHT", -COMPARE_STAT_ROW_INDENT, 0)
        else
            compareWarningContainer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -COMPARE_ROW_GAP)
            compareWarningContainer:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -COMPARE_ROW_GAP)
        end
        for i = 1, warningCount do
            local warning = warnings[i]
            local row = GearTab.GetCompareWarningRow(i)
            local isMissingSpec = type(warning) == "table"
                and warning.kind == GearTab.COMPARE_WARNING_KIND.MISSING_SPEC
            local isUnpickedSpec = type(warning) == "table"
                and warning.kind == GearTab.COMPARE_WARNING_KIND.UNPICKED_SPEC
            local text
            if isMissingSpec or isUnpickedSpec then
                text = warning.text
            else
                text = IU and IU.GetEquipWarningText and IU.GetEquipWarningText(warning) or warning
            end
            row.label:SetText(text)
            if type(warning) == "table" then
                -- Soulbound names the current character (the item's holder), not the compared alt.
                local warningRealm = warning.realm
                if not warningRealm and IU and warning.kind == IU.EQUIP_WARNING_KIND.SOULBOUND then
                    warningRealm = DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()
                end
                GearTab.PositionCompareNameHit(
                    row, row.label, text, warning.nameText, warning.charName, warning.classFile,
                    warningRealm or (entry and entry.realm))
            elseif row.nameHit then
                row.nameHit:Hide()
            end
            local wr, wg, wb = GearTab.GetCompareWarningColor(warning, entry)
            row.label:SetTextColor(wr, wg, wb, 1)
            row:ClearAllPoints()
            if i == 1 then
                row:SetPoint("TOPLEFT", compareWarningContainer, "TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", compareWarningContainer, "TOPRIGHT", 0, 0)
            else
                local prev = compareWarningRows[i - 1]
                row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -COMPARE_ROW_GAP)
                row:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -COMPARE_ROW_GAP)
            end
            row:Show()
        end
        compareWarningContainer:SetHeight(
            GearTab.GetCompareStatContentHeight(warningCount))
        compareWarningContainer:Show()
    else
        compareWarningContainer:SetHeight(0)
        compareWarningContainer:Hide()
    end

    local dumpAnchor
    if warningCount > 0 then
        dumpAnchor = compareWarningRows[warningCount]
    elseif anchor ~= compareLeftPanel then
        dumpAnchor = anchor
    end
    GearTab.LayoutCompareDumpRow(dumpAnchor)
end

function GearTab.UpdateCompareStatScroll(rowCount)
    if not compareStatUI.scrollApi or not compareStatUI.container then return end
    rowCount = tonumber(rowCount) or 0
    local contentH = GearTab.GetCompareStatContentHeight(rowCount)
    compareStatUI.container:SetHeight(math.max(contentH, 1))
    compareStatUI.scrollApi.SetOffset(0)
    compareStatUI.scrollApi.UpdateRange()
end

function GearTab.HideCompareStatRows()
    for i = 1, #compareStatUI.dataRows do
        if compareStatUI.dataRows[i] and compareStatUI.dataRows[i].frame then
            compareStatUI.dataRows[i].frame:Hide()
        end
    end
    if compareStatUI.weightedFooter then
        compareStatUI.weightedFooter:Hide()
    end
    compareStatUI.sectionsCache = nil
    compareStatUI.weightedCache = nil
    compareStatUI.weightedPinned = false
end

local function createCompareStatColumn(parent, left, width, justifyH)
    local fs = parent:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", left, 0)
    fs:SetWidth(width)
    fs:SetHeight(COMPARE_ROW_HEIGHT)
    fs:SetJustifyH(justifyH or "LEFT")
    return fs
end

function GearTab.GetCompareStatRowWidth()
    if compareStatUI.container and compareStatUI.container.GetWidth then
        local w = compareStatUI.container:GetWidth()
        if w and w > 0 then return w end
    end
    if compareRightPanel and compareRightPanel.GetWidth then
        local w = compareRightPanel:GetWidth()
        if w and w > 0 then return w end
    end
    return COMPARE_STAT_ROW_INDENT + COMPARE_STAT_COL_NAME
        + COMPARE_STAT_COL_DELTA + COMPARE_STAT_COL_WEIGHT
end

function GearTab.LayoutCompareStatHint(rowCells, data)
    local hint = rowCells and rowCells.hint
    if not hint then return end
    if not data or not data.offhandHint or data.offhandHint == ""
        or data.formatAsWeightedChange then
        hint.hintText = nil
        hint:Hide()
        return
    end
    local nameFs = rowCells.name
    if not nameFs then
        hint.hintText = nil
        hint:Hide()
        return
    end
    local textWidth = nameFs.GetStringWidth and nameFs:GetStringWidth() or 0
    hint.hintText = data.offhandHint
    hint:ClearAllPoints()
    hint:SetPoint(
        "LEFT",
        nameFs,
        "LEFT",
        textWidth + COMPARE_STAT_HINT_GAP,
        0)
    hint:Show()
end

function GearTab.LayoutCompareStatRowColumns(rowCells, data)
    if not rowCells or not rowCells.name or not rowCells.delta or not rowCells.weight then return end
    local indent = COMPARE_STAT_ROW_INDENT
    local nameFs = rowCells.name
    local deltaFs = rowCells.delta
    local weightFs = rowCells.weight
    if data and data.isHeader then
        nameFs:ClearAllPoints()
        nameFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", indent, 0)
        nameFs:SetWidth(GearTab.GetCompareStatRowWidth() - indent)
        nameFs:SetJustifyH("LEFT")
        deltaFs:ClearAllPoints()
        deltaFs:SetWidth(0)
        deltaFs:SetText("")
        weightFs:ClearAllPoints()
        weightFs:SetWidth(0)
        weightFs:SetText("")
        weightFs:Hide()
        if rowCells.hint then rowCells.hint:Hide() end
        return
    end
    -- The name column takes whatever the row has beyond the fixed delta and weight columns (a wider window).
    local rowW = GearTab.GetCompareStatRowWidth()
    if data and data.formatAsWeightedChange then
        local nameW = math.max(COMPARE_STAT_COL_WEIGHTED_NAME,
            rowW - 2 * indent - COMPARE_STAT_COL_WEIGHTED_DELTA)
        local deltaLeft = indent + nameW
        nameFs:ClearAllPoints()
        nameFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", indent, 0)
        nameFs:SetWidth(nameW)
        nameFs:SetJustifyH("LEFT")
        deltaFs:ClearAllPoints()
        deltaFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", deltaLeft, 0)
        deltaFs:SetWidth(COMPARE_STAT_COL_WEIGHTED_DELTA)
        deltaFs:SetJustifyH("RIGHT")
        weightFs:ClearAllPoints()
        weightFs:SetWidth(0)
        weightFs:SetText("")
        weightFs:Hide()
        GearTab.LayoutCompareStatHint(rowCells, data)
        return
    end
    weightFs:Show()
    local nameW = math.max(COMPARE_STAT_COL_NAME,
        rowW - 2 * indent - COMPARE_STAT_COL_DELTA - COMPARE_STAT_COL_WEIGHT)
    local left = indent
    nameFs:ClearAllPoints()
    nameFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", left, 0)
    nameFs:SetWidth(nameW)
    nameFs:SetJustifyH("LEFT")
    left = left + nameW
    deltaFs:ClearAllPoints()
    deltaFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", left, 0)
    deltaFs:SetWidth(COMPARE_STAT_COL_DELTA)
    deltaFs:SetJustifyH("RIGHT")
    left = left + COMPARE_STAT_COL_DELTA
    weightFs:ClearAllPoints()
    weightFs:SetPoint("TOPLEFT", rowCells.frame, "TOPLEFT", left, 0)
    weightFs:SetWidth(COMPARE_STAT_COL_WEIGHT)
    weightFs:SetJustifyH("RIGHT")
    GearTab.LayoutCompareStatHint(rowCells, data)
end

function GearTab.RelayoutCompareStatRowColumns()
    if not compareStatUI.sectionsCache then return end
    local scrollRows = GearTab.SplitCompareStatRows(
        GearTab.FlattenCompareStatRows(compareStatUI.sectionsCache))
    if not compareStatUI.weightedPinned and compareStatUI.weightedCache then
        scrollRows[#scrollRows + 1] = compareStatUI.weightedCache
    end
    for i = 1, #scrollRows do
        local row = compareStatUI.dataRows[i]
        if row and row.frame and row.frame:IsShown() then
            GearTab.LayoutCompareStatRowColumns(row, scrollRows[i])
        end
    end
    if compareStatUI.weightedPinned and compareStatUI.weightedFooterRow and compareStatUI.weightedCache then
        GearTab.LayoutCompareStatRowColumns(
            compareStatUI.weightedFooterRow, compareStatUI.weightedCache)
    end
end

local function createCompareStatHintCell(rowFrame)
    local hint = CreateFrame("Button", nil, rowFrame)
    hint:SetSize(COMPARE_STAT_HINT_SIZE, COMPARE_STAT_HINT_SIZE)
    local tex = hint:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(DEDUCED_HINT_ICON)
    hint:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.hintText or self.hintText == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.hintText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hint:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    hint:Hide()
    return hint
end

local function createCompareStatRowCells(parent)
    local rowFrame = CreateFrame("Frame", nil, parent)
    rowFrame:SetHeight(COMPARE_ROW_HEIGHT)
    local left = COMPARE_STAT_ROW_INDENT
    local nameCol = createCompareStatColumn(rowFrame, left, COMPARE_STAT_COL_NAME, "LEFT")
    left = left + COMPARE_STAT_COL_NAME
    local deltaCol = createCompareStatColumn(rowFrame, left, COMPARE_STAT_COL_DELTA, "RIGHT")
    left = left + COMPARE_STAT_COL_DELTA
    local weightCol = createCompareStatColumn(rowFrame, left, COMPARE_STAT_COL_WEIGHT, "RIGHT")
    return {
        frame = rowFrame,
        name = nameCol,
        delta = deltaCol,
        weight = weightCol,
        hint = createCompareStatHintCell(rowFrame),
    }
end

function GearTab.GetCompareStatDataRow(index)
    if not compareStatUI.dataRows[index] then
        compareStatUI.dataRows[index] = createCompareStatRowCells(compareStatUI.container)
    end
    return compareStatUI.dataRows[index]
end

function GearTab.GetCompareStatWeightedFooterRow()
    if not compareStatUI.weightedFooterRow then
        compareStatUI.weightedFooterRow = createCompareStatRowCells(compareStatUI.weightedFooter)
        compareStatUI.weightedFooterRow.frame:SetPoint("TOPLEFT", compareStatUI.weightedFooter, "TOPLEFT", 0, 0)
        compareStatUI.weightedFooterRow.frame:SetPoint("TOPRIGHT", compareStatUI.weightedFooter, "TOPRIGHT", 0, 0)
    end
    return compareStatUI.weightedFooterRow
end

function GearTab.FormatCompareNumber(n)
    n = tonumber(n) or 0
    if math.floor(n) == n then return tostring(n) end
    return string.format("%.1f", n)
end

function GearTab.FormatCompareDelta(n)
    local s = GearTab.FormatCompareNumber(n)
    if n > 0 then return "+" .. s end
    return s
end

function GearTab.FormatComparePercentInParens(percent)
    percent = tonumber(percent) or 0
    if percent >= 1000 then
        return "(999+%)"
    end
    if percent < 0 then
        return "(" .. GearTab.FormatCompareDelta(percent) .. "%)"
    end
    return "(" .. GearTab.FormatCompareNumber(percent) .. "%)"
end

function GearTab.FormatCompareWeightedChange(delta, percent)
    local text = GearTab.FormatCompareDelta(delta)
    if percent == nil then return text end
    return text .. " " .. GearTab.FormatComparePercentInParens(percent)
end

function GearTab.GetCompareDeltaColor(delta)
    delta = tonumber(delta) or 0
    if delta > 0 then return 0.2, 1, 0.2 end
    if delta < 0 then return 1, 0.4, 0.3 end
    return 1, 0.82, 0
end

function GearTab.GetCompareWeightedChangeColor(percent, opts)
    if GU and GU.GetWeightedChangeColor then
        return GU.GetWeightedChangeColor(percent, opts)
    end
    return GearTab.GetCompareDeltaColor(percent)
end

function GearTab.FormatCompareWeight(weight)
    if weight == nil then return "" end
    weight = tonumber(weight) or 0
    if weight < 0.005 then return "x0" end
    if weight < 0.05 then
        return "x" .. string.format("%.2f", weight)
    end
    return "x" .. GearTab.FormatCompareNumber(weight)
end

function GearTab.GetCompareWeightColor(weight)
    weight = tonumber(weight) or 0
    if weight < 0.005 then return 0.5, 0.5, 0.5 end
    return 0.82, 0.68, 0.22
end

function GearTab.SetCompareStatDataRow(rowCells, data)
    data = data or {}
    if data.isHeader then
        rowCells.name:SetText(data.label or "?")
        rowCells.name:SetTextColor(0.8, 0.8, 0.8, 1)
        rowCells.delta:SetText("")
        if rowCells.weight then rowCells.weight:SetText("") end
        GearTab.LayoutCompareStatRowColumns(rowCells, data)
        return
    end
    if data.formatAsWeightedChange then
        rowCells.name:SetText("Weighted")
        local nr, ng, nb = GearTab.GetCompareWeightColor(1)
        rowCells.name:SetTextColor(nr, ng, nb, 1)
    else
        rowCells.name:SetText(data.label or "?")
        rowCells.name:SetTextColor(1, 1, 1, 1)
    end
    local delta = data.delta or 0
    if data.formatAsWeightedChange then
        rowCells.delta:SetText(GearTab.FormatCompareWeightedChange(delta, data.percent))
    else
        rowCells.delta:SetText(GearTab.FormatCompareDelta(delta))
    end
    local dr, dg, db
    if data.formatAsWeightedChange then
        local upgradeOpts = GU and GU.GetOptions and GU.GetOptions() or {}
        if data.percent == nil then
            dr, dg, db = GearTab.GetCompareDeltaColor(delta)
        else
            dr, dg, db = GearTab.GetCompareWeightedChangeColor(data.percent, upgradeOpts)
        end
    else
        dr, dg, db = GearTab.GetCompareDeltaColor(delta)
    end
    rowCells.delta:SetTextColor(dr, dg, db, 1)
    if rowCells.weight then
        if data.hideWeight then
            rowCells.weight:SetText("")
        else
            rowCells.weight:SetText(GearTab.FormatCompareWeight(data.weight))
            local wr, wg, wb = GearTab.GetCompareWeightColor(data.weight)
            rowCells.weight:SetTextColor(wr, wg, wb, 1)
        end
    end
    GearTab.LayoutCompareStatRowColumns(rowCells, data)
end

function GearTab.LayoutCompareStatDataRow(rowCells, anchorRow)
    rowCells.frame:ClearAllPoints()
    if not anchorRow then
        rowCells.frame:SetPoint("TOPLEFT", compareStatUI.container, "TOPLEFT", 0, 0)
    else
        rowCells.frame:SetPoint("TOPLEFT", anchorRow, "BOTTOMLEFT", 0, -COMPARE_ROW_GAP)
    end
    rowCells.frame:SetPoint("TOPRIGHT", compareStatUI.container, "TOPRIGHT", 0, 0)
    rowCells.frame:Show()
end

function GearTab.PopulateCompareStatRows(sections)
    compareStatUI.sectionsCache = sections
    local allRows = GearTab.FlattenCompareStatRows(sections)
    local scrollRows, weightedRow = GearTab.SplitCompareStatRows(allRows)
    compareStatUI.weightedCache = weightedRow

    local viewHeight = 0
    if compareRightPanel and compareRightPanel.GetHeight then
        viewHeight = compareRightPanel:GetHeight() or 0
    end
    if viewHeight <= 0 and compareStatUI.scroll and compareStatUI.scroll.GetHeight then
        viewHeight = compareStatUI.scroll:GetHeight() or 0
    end

    local pinWeighted = weightedRow ~= nil
        and GearTab.ShouldPinCompareWeightedRow(#allRows, viewHeight)
    GearTab.LayoutCompareStatScrollArea(pinWeighted)

    local dataRowIndex = 0
    local lastStatAnchor = nil
    local rowsForScroll = scrollRows
    if weightedRow and not pinWeighted then
        rowsForScroll = {}
        for i = 1, #scrollRows do
            rowsForScroll[i] = scrollRows[i]
        end
        rowsForScroll[#rowsForScroll + 1] = weightedRow
    end

    for r = 1, #rowsForScroll do
        dataRowIndex = dataRowIndex + 1
        local dataRow = GearTab.GetCompareStatDataRow(dataRowIndex)
        GearTab.SetCompareStatDataRow(dataRow, rowsForScroll[r])
        GearTab.LayoutCompareStatDataRow(dataRow, lastStatAnchor)
        lastStatAnchor = dataRow.frame
    end
    for i = dataRowIndex + 1, #compareStatUI.dataRows do
        if compareStatUI.dataRows[i] and compareStatUI.dataRows[i].frame then
            compareStatUI.dataRows[i].frame:Hide()
        end
    end

    if pinWeighted and weightedRow then
        local footerRow = GearTab.GetCompareStatWeightedFooterRow()
        GearTab.SetCompareStatDataRow(footerRow, weightedRow)
        footerRow.frame:Show()
        compareStatUI.weightedFooter:Show()
    elseif compareStatUI.weightedFooter then
        compareStatUI.weightedFooter:Hide()
    end

    GearTab.UpdateCompareStatScroll(dataRowIndex)
end

function GearTab.RefreshCompareStatWeightedPin()
    if not compareStatUI.sectionsCache then
        if compareStatUI.scrollApi then
            compareStatUI.scrollApi.UpdateRange()
        end
        return
    end
    GearTab.PopulateCompareStatRows(compareStatUI.sectionsCache)
end

function GearTab.LayoutCompareBottomPanels(mainSection, areaLeft, areaRight)
    compareStatsSection:Show()
    compareStatsSection:ClearAllPoints()
    compareStatsSection:SetPoint("TOPLEFT", mainSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    compareStatsSection:SetPoint("BOTTOMLEFT", areaLeft, "BOTTOMLEFT", 0, 0)
    compareStatsSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
end

function GearTab.ApplyGearLayoutHostBounds()
    gearLayoutHost:ClearAllPoints()
    gearLayoutHost:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if settingsPanel and settingsPanel:IsShown() then
        gearLayoutHost:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        gearLayoutHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
end

function GearTab.GetGearLayoutMode()
    if itemCheckModeActive then return "item_check" end
    if droppedItemLink then return "focus_compare" end
    return "normal"
end

function GearTab.GetGearMainSectionHeight()
    local innerPad = Theme.TAB_CONTENT_PADDING or 8
    if itemCheckModeActive and not droppedItemLink then
        return GearTab.GetPinnedHeaderHeight() + ITEM_CHECK_COMPACT_SECTION_PAD * 2
    end
    local gridH = dims.scrollableGridHeight or GearTab.GetScrollableGridHeight()
    if itemCheckModeActive then
        return GearTab.GetPinnedHeaderHeight() + innerPad * 2
    end
    local chromeH = GearTab.GetHorizontalScrollChromeHeight()
    return GearTab.GetPinnedHeaderHeight() + gridH + chromeH + innerPad * 2
end

function GearTab.LayoutGearPanels()
    GearTab.ApplyGearLayoutHostBounds()
    local mode = GearTab.GetGearLayoutMode()
    local areaLeft = rightPanel
    local areaRight = rightPanel

    gearMainSection:Hide()
    itemCheckSection:Hide()
    compareStatsSection:Hide()

    if mode == "item_check" then
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("TOPRIGHT", areaRight, "TOPRIGHT", 0, 0)
        gearMainSection:SetHeight(GearTab.GetGearMainSectionHeight())
        if gridHost then gridHost:Hide() end

        itemCheckSection:Show()
        itemCheckSection:ClearAllPoints()
        itemCheckSection:SetPoint("TOPLEFT", gearMainSection, "BOTTOMLEFT", 0, -SECTION_GAP)
        itemCheckSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
    elseif mode == "focus_compare" then
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("TOPRIGHT", areaRight, "TOPRIGHT", 0, 0)
        gearMainSection:SetHeight(GearTab.GetGearMainSectionHeight())
        if gridHost then gridHost:Show() end

        GearTab.LayoutCompareBottomPanels(gearMainSection, areaLeft, areaRight)
    else
        gearMainSection:Show()
        gearMainSection:ClearAllPoints()
        gearMainSection:SetPoint("TOPLEFT", areaLeft, "TOPLEFT", 0, 0)
        gearMainSection:SetPoint("BOTTOMRIGHT", areaRight, "BOTTOMRIGHT", 0, 0)
        if gridHost then gridHost:Show() end
    end
    GearTab.LayoutPinnedHeader()
end

GearTab.LayoutGearPanels()

function GearTab.LayoutScrollArea()
    local gridH = dims.scrollableGridHeight or GearTab.GetScrollableGridHeight()
    GearTab.LayoutGridHost()
    if horizontalScroll then
        horizontalScroll:SetHeight(gridH)
    end
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
        slotHeaderContainer:SetHeight(gridH)
        slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
    end
    if verticalScrollChild then
        verticalScrollChild:SetHeight(gridH)
    end
    GearTab.LayoutGearPanels()
end

function GearTab.UpdateComparePanel(list)
    GearTab.HideCompareStatRows()
    comparePanelContext = nil
    if compareDumpRow then compareDumpRow:Hide() end
    if not droppedItemLink then
        if compareItemsRow then compareItemsRow:Hide() end
        GearTab.HideCompareEmptyHint()
        return
    end

    local technique = GearTab.GetSessionCompareTechnique()
    local equippedLink = GearTab.GetSelectedEquippedCompareLink(list, technique)

    if not GearTab.HasCompareSelection() or not GC then
        GearTab.UpdateCompareFocusHeader(droppedItemLink, equippedLink)
        GearTab.ShowCompareEmptyHint(list)
        return
    end

    GearTab.HideCompareEmptyState()
    local ctx = GearTab.CollectComparePanelContext(list)
    if not ctx then
        GearTab.ClearCompareSelection()
        GearTab.ShowCompareEmptyHint(list)
        return
    end
    local entry = ctx.entry
    local charData = ctx.charData
    technique = ctx.technique
    equippedLink = ctx.equippedLink
    local focusOpts = copyFocusOpts(selectedCompareSlot)
    local upgradeMaxDelta = ctx.upgradeMaxDelta
    local comparison = GC.BuildComparison(
        droppedItemLink, equippedLink, technique, charData, entry,
        {
            upgradeMaxDelta = upgradeMaxDelta,
            compareSlot = selectedCompareSlot,
        })
    if not comparison then return end

    local compareWarnings = GearTab.GetCompareWarnings(entry, droppedItemLink, charData)
    local loadoutHeader = GU and GU.BuildWeaponLoadoutHeaderLinks
        and GU.BuildWeaponLoadoutHeaderLinks(droppedItemLink, charData, focusOpts, entry)
    GearTab.UpdateCompareFocusHeader(droppedItemLink, equippedLink, loadoutHeader)
    local verdict = GU and GU.GetFocusVerdictForSlot
        and GU.GetFocusVerdictForSlot(
            entry, charData, droppedItemLink, selectedCompareSlot, focusOpts, upgradeMaxDelta)
    if GU and GU.LogFocusSlotDebug then
        GU.LogFocusSlotDebug(
            entry,
            charData,
            droppedItemLink,
            selectedCompareSlot,
            focusOpts,
            upgradeMaxDelta,
            {
                sessionTechnique = technique,
                equippedCompareLink = equippedLink,
            })
    end
    GearTab.LayoutComparePanelSections(compareWarnings, verdict, entry)
    GearTab.PopulateCompareStatRows(comparison.sections)
    comparePanelContext = ctx
    local itemStats = AltArmy.ItemStats
    local debugMod = AltArmy.Debug
    if itemStats and itemStats.LogStatParseDebug
        and debugMod and debugMod.IsItemStatsEnabled and debugMod.IsItemStatsEnabled() then
        itemStats.LogStatParseDebug(droppedItemLink)
        if equippedLink then
            itemStats.LogStatParseDebug(equippedLink)
        end
    end
end

function GearTab.enterItemCheckMode()
    itemCheckModeActive = true
    GearTab.resetItemCheckDrop()
    if slotHeaderContainer then slotHeaderContainer:Hide() end
    if horizontalScroll then horizontalScroll:Hide() end
    if verticalScrollBinding then verticalScrollBinding.SetAllowShow(false) end
    if horizontalScrollBar then horizontalScrollBar:Hide() end
    if verticalScroll then verticalScroll:EnableMouse(false) end
    GearTab.SyncViewTabs()
    GearTab.LayoutGearPanels()
end

function GearTab.exitItemCheckMode()
    itemCheckModeActive = false
    GearTab.resetItemCheckDrop()
    if slotHeaderContainer then slotHeaderContainer:Show() end
    if horizontalScroll then horizontalScroll:Show() end
    if verticalScrollBinding then verticalScrollBinding.SetAllowShow(true) end
    if horizontalScrollBar then horizontalScrollBar:Show() end
    if verticalScroll then verticalScroll:EnableMouse(true) end
    GearTab.SyncViewTabs()
    GearTab.LayoutGearPanels()
    if frame.RefreshGrid then frame:RefreshGrid() end
end

function GearTab.ShowGridView()
    if droppedItemLink then
        droppedItemLink = nil
        GearTab.ClearCompareSelection()
    end
    if itemCheckModeActive then
        GearTab.exitItemCheckMode()
        return
    end
    GearTab.SyncViewTabs()
    if frame.RefreshGrid then frame:RefreshGrid() end
end

--- Enter Upgrade Check: an item held on the cursor is checked right away; otherwise show the
--- drop prompt.
--- Load the item held on the cursor into Upgrade Check (replacing any focused item). An item
--- that can't be checked opens the drop prompt with the error. Returns false when the cursor
--- holds no item.
function GearTab.LoadCursorItemForUpgradeCheck()
    local cursorLink = GearTab.getCursorItemLink()
    if not cursorLink then return false end
    local ok, errMsg = true, nil
    if IU and IU.ValidateItemCheckDrop then
        ok, errMsg = IU.ValidateItemCheckDrop(cursorLink)
    end
    if ok then
        if ClearCursor then ClearCursor() end
        GearTab.applyItemCheckDrop(cursorLink)
        return true
    end
    if droppedItemLink then
        droppedItemLink = nil
        GearTab.ClearCompareSelection()
    end
    GearTab.enterItemCheckMode()
    GearTab.showItemCheckError(errMsg)
    return true
end

function GearTab.ShowUpgradeCheckView()
    if droppedItemLink or itemCheckModeActive then
        GearTab.SyncViewTabs()
        return
    end
    if GearTab.LoadCursorItemForUpgradeCheck() then return end
    GearTab.enterItemCheckMode()
end

--- Main-window Gear side tab clicked (Core.lua): an item on the cursor goes straight into
--- Upgrade Check, as if the Upgrade Check sub-tab had been clicked.
function frame:OnSideTabClicked()
    GearTab.LoadCursorItemForUpgradeCheck()
end

--- Minimap button (UI/Minimap.lua) opens Gear with the cursor item when one is held.
function frame:HasCursorItem()
    return GearTab.getCursorItemLink() ~= nil
end

function frame:LoadCursorItemForUpgradeCheck()
    return GearTab.LoadCursorItemForUpgradeCheck()
end

-- Tabs hang from the panel top up into the main window's toolbar row (same spot as Cooldowns).
-- Parented to the tab frame so they hide with it.
VIEW.tabs = AltArmy.TopTabs.Create(frame, VIEW.defs, {
    mainTab = "Gear",
    onSelect = function(id)
        if id == GearTab.GetActiveViewName() then
            GearTab.SyncViewTabs()
        elseif id == "upgrade" then
            GearTab.ShowUpgradeCheckView()
        else
            GearTab.ShowGridView()
        end
    end,
})
VIEW.tabs.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)
frame.ViewTabs = VIEW.tabs -- `/alta <tab> <view>` opens only the views that have a tab (Core.lua)

--- `/alta gear grid|upgrade` (Core.lua's OpenMainTabView): as clicking that sub-view tab.
function frame.SetGearView(view)
    if view == "upgrade" then
        GearTab.ShowUpgradeCheckView()
    else
        GearTab.ShowGridView()
    end
end

GearTab.SyncViewTabs()

function frame:FocusItem(link)
    if not link or link == "" then return end
    if itemCheckModeActive then GearTab.exitItemCheckMode() end
    GearTab.ApplyFocusedItem(link)
    GearTab.SyncViewTabs()
    if self.RefreshGrid then self:RefreshGrid() end
end

function frame:GetFocusedItemLink()
    return droppedItemLink
end

function frame:ClearFocus()
    droppedItemLink = nil
    GearTab.ClearCompareSelection()
    GearTab.SyncViewTabs()
    if self.RefreshGrid then self:RefreshGrid() end
end

function GearTab.GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        local upgradeHighlight = col:CreateTexture(nil, "BACKGROUND", nil, -2)
        upgradeHighlight:Hide()
        col.upgradeHighlight = upgradeHighlight
        col.selectionOutline = {}
        local function makeOutlineEdge(key)
            local tex = col:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(1, 1, 1, 0.95)
            tex:Hide()
            col.selectionOutline[key] = tex
        end
        makeOutlineEdge("top")
        makeOutlineEdge("bottom")
        makeOutlineEdge("left")
        makeOutlineEdge("right")
        col.cells = {}
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = CreateFrame("Frame", nil, col)
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:EnableMouse(true)
            local glow = cell:CreateTexture(nil, "BACKGROUND")
            glow:SetAllPoints(cell)
            glow:Hide()
            cell.glow = glow
            local tex = cell:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", cell, "TOPLEFT", ITEM_ICON_INSET, -ITEM_ICON_INSET)
            tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -ITEM_ICON_INSET, ITEM_ICON_INSET)
            cell.texture = tex
            cell.focusHighlight = cell:CreateTexture(nil, "BACKGROUND", nil, -2)
            cell.focusHighlight:Hide()
            cell.compareHover = cell:CreateTexture(nil, "BACKGROUND", nil, -1)
            cell.compareHover:SetColorTexture(
                COMPARE_HOVER_COLOR[1],
                COMPARE_HOVER_COLOR[2],
                COMPARE_HOVER_COLOR[3],
                COMPARE_HOVER_COLOR[4])
            cell.compareHover:Hide()
            cell.upgradeBadge = cell:CreateFontString(nil, "OVERLAY", Theme.FONTS.badge)
            applyUpgradeBadgeFont(cell.upgradeBadge)
            cell.upgradeBadge:SetPoint("CENTER", cell, "TOPRIGHT", UPGRADE_BADGE_OFFSET_X, UPGRADE_BADGE_OFFSET_Y)
            cell.upgradeBadge:SetJustifyH("CENTER")
            cell.upgradeBadge:Hide()
            cell:SetScript("OnMouseUp", function(self, button)
                local colFrame = self:GetParent()
                if droppedItemLink and button == "LeftButton" and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    local shift = IsShiftKeyDown and IsShiftKeyDown()
                    local ctrl = IsControlKeyDown and IsControlKeyDown()
                    if not shift and not ctrl then
                        GearTab.SelectCompareCell(colFrame.compareKey, self.inventorySlot)
                        return
                    end
                end
                local target = self.itemLink or self.itemID
                if not target then return end
                GearTab.HandleItemCellClick(target, button)
            end)
            cell:SetScript("OnEnter", function(self)
                local colFrame = self:GetParent()
                if droppedItemLink and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    GearTab.AddCompareHover(
                        GearTab.MakeCompareCellKey(colFrame.compareKey, self.inventorySlot))
                end
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    if self.itemLink and self.itemLink ~= "" then
                        GameTooltip:SetHyperlink(self.itemLink)
                    elseif self.itemID then
                        GameTooltip:SetItemByID(self.itemID)
                    else
                        GameTooltip:Hide()
                        return
                    end
                    if droppedItemLink and self.isFocusCompareCell then
                        GameTooltip:AddLine(GearTab.FormatCompareClickHint(), 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end
            end)
            cell:SetScript("OnLeave", function(self)
                local colFrame = self:GetParent()
                if droppedItemLink and colFrame and colFrame.compareKey
                    and self.isFocusCompareCell and self.inventorySlot then
                    GearTab.RemoveCompareHover(
                        GearTab.MakeCompareCellKey(colFrame.compareKey, self.inventorySlot))
                end
                if GameTooltip then GameTooltip:Hide() end
            end)
            local cellXOffset = (dims.columnWidth - dims.cellSize) / 2
            local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
            if slot == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -slotLabelRowOffset)
            else
                cell:SetPoint("TOPLEFT", col.cells[slot - 1], "BOTTOMLEFT", 0, -(dims.rowHeight - dims.cellSize))
            end
            col.cells[slot] = cell
        end
        columnPool[index] = col
    end
    return columnPool[index]
end

function GearTab.LayoutVisibleGridRows()
    if not slotLabels or not slotLabels[1] then return end
    local visible = GearTab.GetVisibleDisplaySlots()
    local slotLabelRowOffset = (dims.rowHeight - dims.cellSize) / 2
    local cellXOffset = (dims.columnWidth - dims.cellSize) / 2

    for slot = 1, NUM_EQUIPMENT_SLOTS do
        if slotLabels[slot] then
            slotLabels[slot]:SetShown(false)
        end
    end

    for row = 1, #visible do
        local slot = visible[row]
        local label = slotLabels[slot]
        label:SetShown(true)
        label:SetHeight(dims.cellSize)
        label:ClearAllPoints()
        label:SetPoint("LEFT", slotHeaderContainer, "LEFT", 0, 0)
        if row == 1 then
            label:SetPoint("TOP", slotHeaderContainer, "TOP", 0, -slotLabelRowOffset)
        else
            label:SetPoint("TOP", slotLabels[visible[row - 1]], "TOP", 0, -dims.rowHeight)
        end
    end

    for _, col in pairs(columnPool) do
        for row = 1, #visible do
            local slot = visible[row]
            local cell = col.cells[slot]
            cell:SetSize(dims.cellSize, dims.cellSize)
            cell:ClearAllPoints()
            if row == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", cellXOffset, -slotLabelRowOffset)
            else
                cell:SetPoint(
                    "TOPLEFT",
                    col.cells[visible[row - 1]],
                    "BOTTOMLEFT",
                    0,
                    -(dims.rowHeight - dims.cellSize))
            end
        end
    end
end

function GearTab.UpdateGridWithOffset()
    if not AltArmy.Characters then return end
    local list = GearTab.GetDisplayList()
    local numCols = #list

    for idx, col in pairs(columnPool) do
        if idx > numCols then col:Hide() end
    end
    for idx, col in pairs(headerColumnPool) do
        if idx > numCols then col:Hide() end
    end

    local upgradeMaxDelta
    local focusOpts = GU and GU.GetOptions and GU.GetOptions() or {}
    if droppedItemLink and GU and GU.ComputeUpgradeMaxDeltaForEntries then
        upgradeMaxDelta = GearTab.ComputeFocusUpgradeMaxDelta(
            list,
            GearTab.GetFocusedInventorySlots(),
            focusOpts)
    end

    for c = 1, numCols do
        local entry = list[c]
        local headerCol = GearTab.GetHeaderColumnFrame(c)
        headerCol:ClearAllPoints()
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        headerCol:Show()

        local compareKey = CharKey(entry.name, entry.realm)
        local columnDimmed = GearTab.GetFocusColumnDimmed(entry, upgradeMaxDelta)
        local columnAlpha = GearTab.getFocusColumnAlpha(
            columnDimmed,
            selectedCompareKey == compareKey)
        headerCol.compareKey = compareKey
        local headerSelected = droppedItemLink and selectedCompareKey == compareKey
        GearTab.layoutHeaderSelectionHighlight(headerCol, headerSelected)

        local col = GearTab.GetColumnFrame(c)
        col.compareKey = compareKey
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        col:Show()

        if col.upgradeHighlight then col.upgradeHighlight:Hide() end

        local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
        for slot = 1, NUM_EQUIPMENT_SLOTS do
            local cell = col.cells[slot]
            cell.isFocusCompareCell = false
            cell.inventorySlot = nil
            if not GearTab.IsDisplaySlotVisible(slot) then
                cell:Hide()
                GearTab.layoutCellUpgradeBadge(cell, nil)
                GearTab.layoutCellFocusHighlight(cell, nil, false)
                GearTab.layoutCellCompareHover(cell, false)
            else
                local invSlot = SLOT_ORDER[slot]
                cell.inventorySlot = invSlot
                if droppedItemLink then
                    cell.isFocusCompareCell = true
                end
                local item = charData and DS.GetInventoryItem and DS:GetInventoryItem(charData, invSlot)
                if type(item) == "string" then
                    cell.itemLink = item
                    cell.itemID = nil
                elseif type(item) == "number" then
                    cell.itemLink = nil
                    cell.itemID = item
                else
                    cell.itemLink = nil
                    cell.itemID = nil
                end
                GearTab.ApplyItemCellVisual(cell, item, false, columnAlpha, entry.classFile)
                cell:Show()

                if droppedItemLink then
                    local cellKind = GU and GU.GetFocusCellBadgeKind
                        and GU.GetFocusCellBadgeKind(
                            entry, charData, droppedItemLink, invSlot, focusOpts, upgradeMaxDelta)
                        or nil
                    local selected = GearTab.IsCompareCellSelected(compareKey, invSlot)
                    GearTab.layoutCellUpgradeBadge(cell, cellKind)
                    GearTab.layoutCellFocusHighlight(cell, cellKind, selected)
                    local hoverKey = GearTab.MakeCompareCellKey(compareKey, invSlot)
                    GearTab.layoutCellCompareHover(
                        cell,
                        hoveredCompareKey == hoverKey and not selected)
                else
                    GearTab.layoutCellUpgradeBadge(cell, nil)
                    GearTab.layoutCellFocusHighlight(cell, nil, false)
                    GearTab.layoutCellCompareHover(cell, false)
                end
            end
        end

        GearTab.layoutSelectionOutline(headerCol, col, nil, false)

        local RF = AltArmy.RealmFilter
        local classR, classG, classB = 1, 0.82, 0
        if CC and CC.getRGBOr then
            classR, classG, classB = CC.getRGBOr(entry.classFile, classR, classG, classB)
        end
        headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
        local displayName = entry.name or "?"
        headerCol.header:SetTextColor(classR, classG, classB, columnAlpha)
        if TruncateFontString then
            TruncateFontString(headerCol.header, displayName, dims.columnWidth - 4)
        end
        headerCol.truncated = (headerCol.header:GetText() ~= displayName)
        local showRealmSuffix = AltArmy.CharacterFilter.ShowsOtherRealms(GearTab.GetGearSettings().filter)
            and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
        local hasRealm = entry.realm and entry.realm ~= ""
        local formattedName = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(
                entry.name or "?",
                entry.realm,
                showRealmSuffix,
                entry.classFile
            )
            or displayName
        if droppedItemLink or headerCol.truncated or (showRealmSuffix and hasRealm) then
            headerCol.tooltipText = formattedName
        else
            headerCol.tooltipText = nil
        end

        local fitMsg, fitColor = GearTab.GetFitMessage(entry)
        if GearTab.ShouldHideMessageHeader() or droppedItemLink then
            headerCol.message:SetText("")
            headerCol.message:Hide()
        elseif fitMsg and fitMsg ~= "" then
            headerCol.message:SetText(fitMsg)
            if fitColor == "red" then
                headerCol.message:SetTextColor(1, 0.3, 0.3, 1)
            elseif fitColor == "orange" then
                headerCol.message:SetTextColor(1, 0.6, 0.2, 1)
            elseif fitColor == "green" then
                headerCol.message:SetTextColor(0.2, 1, 0.2, 1)
            else
                headerCol.message:SetTextColor(0.9, 0.9, 0.9, 1)
            end
            headerCol.message:Show()
        else
            headerCol.message:SetText("")
            headerCol.message:Show()
        end

        local providerId = GearTab.GetSelectedScoreProvider()
        local scoreMissing = GearScoreMod and GearScoreMod.IsScoreMissing
            and GearScoreMod.IsScoreMissing(charData, providerId)
        if headerCol.scoreText then
            if GearTab.ShouldHideScoreHeader() then
                headerCol.scoreText:Hide()
                headerCol.scoreMissingEntry = nil
                if headerCol.scoreHover then
                    headerCol.scoreHover:Hide()
                    headerCol.scoreHover:EnableMouse(false)
                end
            else
                if scoreMissing then
                    headerCol.scoreText:SetText("!")
                    headerCol.scoreText:SetTextColor(1, 0.82, 0, columnAlpha)
                    headerCol.scoreMissingEntry = {
                        name = entry.name or "",
                        realm = entry.realm or "",
                        classFile = entry.classFile,
                    }
                    if headerCol.scoreHover then
                        headerCol.scoreHover:Show()
                        headerCol.scoreHover:EnableMouse(true)
                    end
                else
                    local scoreValue = GearScoreMod and GearScoreMod.GetDisplayScore
                        and GearScoreMod.GetDisplayScore(entry, providerId) or 0
                    local scoreDisplay = GearScoreMod and GearScoreMod.FormatDisplayScore
                        and GearScoreMod.FormatDisplayScore(providerId, scoreValue) or "0"
                    headerCol.scoreText:SetText(scoreDisplay)
                    headerCol.scoreMissingEntry = nil
                    if headerCol.scoreHover then
                        headerCol.scoreHover:Hide()
                        headerCol.scoreHover:EnableMouse(false)
                    end
                    local sr, sg, sb
                    if GearScoreMod and GearScoreMod.GetDisplayScoreColor then
                        sr, sg, sb = GearScoreMod.GetDisplayScoreColor(providerId, scoreValue)
                    end
                    if sr and sg and sb then
                        headerCol.scoreText:SetTextColor(sr, sg, sb, columnAlpha)
                    else
                        headerCol.scoreText:SetTextColor(0.9, 0.9, 0.9, columnAlpha)
                    end
                end
                headerCol.scoreText:Show()
            end
        end
    end
end

function frame:RefreshGrid(_self)
    if not AltArmy.Characters then return end
    if GU and GU.ResetFocusPass then
        GU.ResetFocusPass()
    end
    if AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(false, "level")
    end

    GearTab.UpdateScoreSortButton()
    GearTab.LayoutPinnedHeader()

    local list = GearTab.GetDisplayList()
    local numCols = #list
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()
    GearTab.UpdateComparePanel(list)
    GearTab.LayoutScrollArea()
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    for _, col in pairs(columnPool) do
        col:SetHeight(dims.scrollableGridHeight)
    end
    GearTab.LayoutVisibleGridRows()

    local viewWidth = verticalScroll and verticalScroll:GetWidth() or 0
    local gridContentWidth = numCols * dims.columnWidth + PAD
    local gridViewWidth = math.max(0, viewWidth - SLOT_LABEL_WIDTH)

    -- Vertical scroll child: viewport width only; horizontal scroll is inner (grid only)
    if verticalScrollChild and verticalScroll then
        verticalScrollChild:SetWidth(math.max(MIN_SCROLL_CHILD_WIDTH, viewWidth))
        if gridContainer then
            gridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if headerGridContainer then
            headerGridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if verticalScrollBinding then
            verticalScrollChild:SetHeight(dims.scrollableGridHeight)
            verticalScrollBinding.SetStep(dims.rowHeight * 2)
            -- Clamps the kept offset to the new range (scroll survives tab revisits).
            verticalScrollBinding.UpdateRange()
            if droppedItemLink then
                verticalScrollBinding.SetOffset(0)
            end
            verticalScrollBinding.SetAllowShow(not droppedItemLink and not itemCheckModeActive)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollApi:SetRange(0, maxHorzScroll, gridViewWidth)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            if resetGridHorizontalScrollOnRefresh then
                horizontalScrollApi:Reset()
                resetGridHorizontalScrollOnRefresh = false
            else
                horizontalScrollApi:Restore(maxHorzScroll)
            end
        end
    end

    GearTab.UpdateGridWithOffset()
    if scrollGridLeftFade then
        scrollGridLeftFade:Update()
    end
    if scrollHeaderLeftFade then
        scrollHeaderLeftFade:Update()
    end
end

--- Reapply fixed layout dimensions (medium icons, normal spacing).
function GearTab.ApplySpacing()
    dims.cellSize = GearTab.GetCellSizePx()
    local rh, cw = GearTab.GetSpacingDimensions()
    dims.rowHeight, dims.columnWidth = rh, cw
    dims.scrollableGridHeight = GearTab.GetScrollableGridHeight()

    if verticalScrollChild then
        GearTab.LayoutScrollArea()
    end
    GearTab.LayoutGridHost()
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end
    GearTab.LayoutPinnedHeader()
    if slotHeaderContainer then
        slotHeaderContainer:ClearAllPoints()
        slotHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
        slotHeaderContainer:SetHeight(dims.scrollableGridHeight)
        slotHeaderContainer:SetWidth(SLOT_LABEL_WIDTH)
    end
    if headerCornerColumn then
        headerCornerColumn:SetWidth(SLOT_LABEL_WIDTH)
    end
    if headerCornerCell then
        headerCornerCell:SetWidth(SLOT_LABEL_WIDTH - 4)
    end
    if horizontalScroll then
        horizontalScroll:ClearAllPoints()
        horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", SLOT_LABEL_WIDTH, 0)
        horizontalScroll:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
        horizontalScroll:SetHeight(dims.scrollableGridHeight)
    end
    if verticalScrollBinding then
        verticalScrollBinding.SetStep(dims.rowHeight * 2)
    end

    if scoreProviderStaticLabel then
        scoreProviderStaticLabel:SetHeight(GearTab.GetScoreRowContentHeight())
    end
    if scoreProviderBtn then
        scoreProviderBtn:SetHeight(GearTab.GetScoreRowContentHeight())
    end
    if scoreSortBtn then
        local btnSize = GearTab.GetScoreSortBtnSize()
        scoreSortBtn:SetSize(btnSize, btnSize)
    end

    for _, col in pairs(headerColumnPool) do
        col:SetSize(dims.columnWidth, GearTab.GetPinnedHeaderHeight())
        if col.scoreText then
            col.scoreText:SetHeight(GearTab.GetScoreRowContentHeight())
        end
        if col.scoreHover then
            col.scoreHover:SetHeight(GearTab.GetScoreRowContentHeight())
        end
    end
    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
    end

    GearTab.LayoutVisibleGridRows()
end

function GearTab.RefreshGearTabControls()
    GearTab.RebuildScoreProviderDropdown()
    GearTab.UpdateScoreProviderControl()
    GearTab.UpdateScoreSortButton()
end

-- Apply layout when tab is shown (dims initialized at file load)
frame:HookScript("OnHide", function()
    if itemCheckModeActive then
        GearTab.exitItemCheckMode()
    end
end)
frame:SetScript("OnShow", function()
    GearTab.SyncViewTabs()
    GearTab.ApplySpacing()
    GearTab.RefreshGearTabControls()
    if GearScoreMod and GearScoreMod.CaptureCurrentCharacterScore then
        GearScoreMod.CaptureCurrentCharacterScore()
    end
    frame:RefreshGrid()
end)

if ItemStats and ItemStats.SetOnUpdated then
    ItemStats.SetOnUpdated(function(itemId)
        if not droppedItemLink then return end
        local linkId = tonumber(tostring(droppedItemLink):match("item:(%d+)"))
        if linkId ~= itemId then return end
        if frame.RefreshGrid then
            frame:RefreshGrid()
        end
    end)
end

function GearTab.IsGearScoreAddonEvent(addonName)
    if not addonName or addonName == "" then return false end
    if addonName == "TacoTip" then return true end
    if GearScoreMod and GearScoreMod.IsSupportedGearScoreAddon then
        return GearScoreMod.IsSupportedGearScoreAddon(addonName)
    end
    return false
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" then
        if GearScoreMod and GearScoreMod.RefreshProviders then
            GearScoreMod.RefreshProviders("login")
        end
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        GearTab.ApplySpacing()
        GearTab.RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    elseif event == "ADDON_LOADED" and GearTab.IsGearScoreAddonEvent(addonName) then
        if GearScoreMod and GearScoreMod.RefreshProviders then
            GearScoreMod.RefreshProviders("addon-loaded:" .. tostring(addonName))
        end
        GearTab.RefreshGearTabControls()
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Gear settings panel: right 40% of frame when visible (grid 60%, both full height) ----
settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(settingsPanel, "section")
function GearTab.ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.SettingsPanelLeft(w), -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Theme.SettingsPanelLeft(w), SECTION_INSET)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
GearTab.ApplySettingsPanelLayout()
settingsPanel:Hide()

local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
local gearSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
gearSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
gearSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
gearSettingsTitle:SetJustifyH("LEFT")
gearSettingsTitle:SetText("Gear Settings")
Theme.SetTitleColor(gearSettingsTitle)

local sortingContent = CreateFrame("Frame", nil, settingsContent)
sortingContent:SetPoint("TOPLEFT", gearSettingsTitle, "BOTTOMLEFT", 0, -8)
sortingContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)
sortingContent:Show()

-- ---- Filters and pin / hide (on GearTab: no main-chunk locals to spare) ----
GearTab.filterControls = AltArmy.CreateCharacterFilterControls(sortingContent, {
    anchorTo = gearSettingsTitle,
    dropdownParent = settingsPanel,
    getSettings = GearTab.GetGearSettings,
    getCharSetting = GearTab.GetCharSetting,
    setCharSetting = GearTab.SetCharSetting,
    skipBankAlts = true,
    onChange = function()
        if frame.RefreshGrid then frame:RefreshGrid() end
    end,
})

-- Close dropdowns when clicking outside
settingsPanel:SetScript("OnHide", function()
    scoreProviderDropdown:Hide()
    GearTab.filterControls.Close()
end)

function frame:IsGearSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

function frame:ToggleGearSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)

    if showSettings then
        GearTab.ApplySettingsPanelLayout()
    end

    GearTab.ApplyGearLayoutHostBounds()
    GearTab.LayoutGearPanels()

    if showSettings then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        GearTab.filterControls.refresh()
    end

    if frame.RefreshGrid then frame:RefreshGrid() end
end

-- Keep 60/40 split when frame is resized and settings are open
-- The grid follows the window's width (the resize grip): the settings panel keeps its share, and the
-- refresh shows as many character columns as the viewport holds (the columns keep their width).
frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        GearTab.ApplySettingsPanelLayout()
        GearTab.ApplyGearLayoutHostBounds()
        GearTab.LayoutGearPanels()
    elseif droppedItemLink then
        GearTab.LayoutGearPanels()
    end
    if frame:IsVisible() and frame.RefreshGrid then frame:RefreshGrid() end
end)
