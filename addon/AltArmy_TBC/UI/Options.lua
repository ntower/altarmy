-- AltArmy TBC — Options panel (Interface > AddOns > AltArmy).

local Theme = AltArmy.Theme
-- Two-column layout: character list + other settings (left), character settings (right).
-- SavedVariables: AltArmyTBC_Options (showMinimapButton legacy; minimap.hide / minimap.minimapPos for LibDBIcon).

-- ---------------------------------------------------------------------------
-- Defaults / minimap helpers
-- ---------------------------------------------------------------------------

local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
        AltArmy.firstRun = true
    end
    if AltArmy.MigrateMinimapSavedVars then
        AltArmy.MigrateMinimapSavedVars(AltArmyTBC_Options)
    else
        if AltArmyTBC_Options.showMinimapButton == nil then
            AltArmyTBC_Options.showMinimapButton = true
        end
    end
    if AltArmy and AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Ensure then
        AltArmy.GlobalRealmFilter.Ensure()
    end
    if AltArmy and AltArmy.BankAlt and AltArmy.BankAlt.Ensure then
        AltArmy.BankAlt.Ensure()
    end
    if AltArmy and AltArmy.CooldownData and AltArmy.CooldownData.EnsureCooldownOptions then
        AltArmy.CooldownData.EnsureCooldownOptions()
    end
    if AltArmy and AltArmy.GearUpgrade and AltArmy.GearUpgrade.EnsureGearUpgradeOptions then
        AltArmy.GearUpgrade.EnsureGearUpgradeOptions()
    end
    if AltArmy and AltArmy.Debug and AltArmy.Debug.Ensure then
        AltArmy.Debug.Ensure()
    end
end

local function minimapShown()
    local m = AltArmyTBC_Options.minimap
    if m and m.hide ~= nil then
        return not m.hide
    end
    return AltArmyTBC_Options.showMinimapButton ~= false
end

local function applyMinimapOption()
    ensureDefaults()
    if AltArmy.SetMinimapButtonShown then
        AltArmy.SetMinimapButtonShown(minimapShown())
    end
end

ensureDefaults()
applyMinimapOption()

--- InterfaceOptions checkboxes do not include the caption in their hit rect; forward label clicks.
function AltArmy.WireCheckboxLabelClick(checkButton, fontString)
    if not checkButton or not fontString then return end
    local hit = CreateFrame("Button", nil, checkButton)
    hit:SetFrameStrata(checkButton:GetFrameStrata() or "MEDIUM")
    hit:SetFrameLevel((checkButton:GetFrameLevel() or 0) + 5)
    hit:EnableMouse(true)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnClick", function()
        if not checkButton:IsEnabled() then return end
        checkButton:Click()
    end)
    local function layout()
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", fontString, "TOPLEFT", -6, 6)
        hit:SetPoint("BOTTOMRIGHT", fontString, "BOTTOMRIGHT", 6, -6)
    end
    layout()
end

-- ---------------------------------------------------------------------------
-- Class icon helpers
-- Uses Interface\WorldStateFrame\Icons-Classes with CLASS_ICON_TCOORDS,
-- both guaranteed to exist in TBC Classic. Falls back to a class-colored
-- square when tcoords are unavailable (e.g. unknown class).
-- ---------------------------------------------------------------------------

-- Class color lookup via AltArmy.ClassColor (classFile -> r, g, b).
local CC = AltArmy.ClassColor

local CLASS_ICON_SHEET = "Interface\\WorldStateFrame\\Icons-Classes"

local function SetCharIcon(icon, iconFallback, classFile)
    local tcoords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
    if tcoords then
        icon:SetTexture(CLASS_ICON_SHEET)
        icon:SetTexCoord(tcoords[1], tcoords[2], tcoords[3], tcoords[4])
        icon:Show()
        iconFallback:Hide()
    else
        icon:SetTexture(nil)
        icon:Hide()
        if CC and CC.getRGBOr then
            local r, g, b = CC.getRGBOr(classFile, 0.5, 0.5, 0.5)
            iconFallback:SetColorTexture(r, g, b, 0.9)
        else
            iconFallback:SetColorTexture(0.5, 0.5, 0.5, 0.9)
        end
        iconFallback:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Character list helpers
-- ---------------------------------------------------------------------------

local function IsCurrentCharacter(name, realm)
    local DS = AltArmy.DataStore
    return DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(name, realm)
end

local function GetSortedCharacters()
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter then return {} end
    local list = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        list[#list + 1] = {
            name      = charData.name or charName,
            realm     = realm,
            classFile = charData.classFile or "",
        }
    end)
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.realm < b.realm
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Options panel
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame")
AltArmy.OptionsPanel = panel
panel.name = "AltArmy"

panel.okay = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.cancel = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.default = function()
    AltArmyTBC_Options.showMinimapButton = true
    if AltArmyTBC_Options.minimap then
        AltArmyTBC_Options.minimap.hide = false
    end
    applyMinimapOption()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(true)
    end
    if AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Set then
        AltArmy.GlobalRealmFilter.Set("currentRealm")
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if AltArmy.CooldownData and AltArmy.CooldownData.ResetCooldownOptionsToDefaults then
        AltArmy.CooldownData.ResetCooldownOptionsToDefaults()
    end
    if panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
    if panel.RefreshGearUpgradeOptionsFromVars then
        panel.RefreshGearUpgradeOptionsFromVars()
    end
    if AltArmy.AuctionScan and AltArmy.AuctionScan.SetAutoScanEnabled then
        AltArmy.AuctionScan.SetAutoScanEnabled(false)
        AltArmy.AuctionScan.SetScanMode("prefer_full")
    end
    if panel.RefreshAuctionOptions then
        panel.RefreshAuctionOptions()
    end
    if AltArmy.OwnRecipeRead and AltArmy.OwnRecipeRead.SetEnabled then
        AltArmy.OwnRecipeRead.SetEnabled(true)
    end
    if panel.RefreshAdvancedOptions then
        panel.RefreshAdvancedOptions()
    end
end
panel.refresh = function()
    ensureDefaults()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(minimapShown())
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
    if panel.RefreshGearUpgradeOptionsFromVars then
        panel.RefreshGearUpgradeOptionsFromVars()
    end
    if panel.RefreshAuctionOptions then
        panel.RefreshAuctionOptions()
    end
    if panel.RefreshAdvancedOptions then
        panel.RefreshAdvancedOptions()
    end
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

local header = panel:CreateFontString(nil, "ARTWORK", Theme.FONTS.pageTitle)
header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
header:SetText("Alt Army")
Theme.SetTitleColor(header)

local LEFT_INSET = 16
local COL_GAP    = 20

-- ---------------------------------------------------------------------------
-- Tab strip (General / Characters / Gear / Cooldowns / Debug)
-- ---------------------------------------------------------------------------

local TAB_BAR_Y = -42
local TAB_CONTENT_TOP = -72
local TAB_BTN_W = 96
local TAB_BTN_H = 22

local tabGeneral = CreateFrame("Frame", nil, panel)
local tabCharacters = CreateFrame("Frame", nil, panel)
local tabCooldowns = CreateFrame("Frame", nil, panel)
local tabGearUpgrades = CreateFrame("Frame", nil, panel)
local tabDebug = CreateFrame("Frame", nil, panel)
tabGeneral:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_CONTENT_TOP)
tabGeneral:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
tabCharacters:SetAllPoints(tabGeneral)
tabCooldowns:SetAllPoints(tabGeneral)
tabGearUpgrades:SetAllPoints(tabGeneral)
tabDebug:SetAllPoints(tabGeneral)

local tabButtons = {}
local activeOptionsTab = "general"

local RefreshDebugCheckboxes
local RefreshDebugTabVisibility

local function SetActiveOptionsTab(which)
    activeOptionsTab = which
    tabGeneral:SetShown(which == "general")
    tabCharacters:SetShown(which == "characters")
    tabCooldowns:SetShown(which == "cooldowns")
    tabGearUpgrades:SetShown(which == "gearUpgrades")
    tabDebug:SetShown(which == "debug")
    for id, btn in pairs(tabButtons) do
        if btn and btn.SetSelected then
            btn:SetSelected(id == which)
        elseif btn and btn.SetAlpha then
            btn:SetAlpha(id == which and 1 or 0.55)
        end
    end
    if which == "gearUpgrades" then
        if AltArmy.BuildGearUpgradeOptionsUI then
            AltArmy.BuildGearUpgradeOptionsUI(panel)
        end
        if panel.UpdateGearUpgradeScrollRange then
            panel.UpdateGearUpgradeScrollRange()
        end
        if panel.RefreshGearUpgradeOptionsFromVars then
            panel.RefreshGearUpgradeOptionsFromVars()
        end
    end
    if which == "debug" and RefreshDebugCheckboxes then
        RefreshDebugCheckboxes()
    end
    if which == "general" and panel.RefreshGuildSharingControls then
        panel.RefreshGuildSharingControls()
    end
    if which == "characters" and panel.RefreshCharGuildShareDropdown then
        panel.RefreshCharGuildShareDropdown()
    end
end

local tabBar = CreateFrame("Frame", nil, panel)
tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_INSET, TAB_BAR_Y)
tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, TAB_BAR_Y)
tabBar:SetHeight(TAB_BTN_H)
local tabIds = { "general", "characters", "gearUpgrades", "cooldowns" }
local tabLabels = {
    general = "General",
    characters = "Characters",
    gearUpgrades = "Gear",
    cooldowns = "Cooldowns",
    debug = "Debug",
}
for i, id in ipairs(tabIds) do
    local b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetSize(TAB_BTN_W, TAB_BTN_H)
    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i - 1) * (TAB_BTN_W + 4), 0)
    b:SetText(tabLabels[id] or id)
    Theme.SkinButton(b, true)
    b:SetScript("OnClick", function()
        SetActiveOptionsTab(id)
    end)
    tabButtons[id] = b
end

do
    local b = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    b:SetSize(TAB_BTN_W, TAB_BTN_H)
    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 4 * (TAB_BTN_W + 4), 0)
    b:SetText("Debug")
    Theme.SkinButton(b, true)
    b:SetScript("OnClick", function()
        SetActiveOptionsTab("debug")
    end)
    b:Hide()
    tabButtons["debug"] = b
end

-- ---------------------------------------------------------------------------
-- Debug tab (scrollable — content exceeds the Interface Options canvas)
-- ---------------------------------------------------------------------------

local DEBUG_SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local debugViewport = Theme.CreateVerticalScrollViewport({
    name = "AltArmyTBC_DebugOptionsScroll",
    parent = tabDebug,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", tabDebug, "TOPLEFT", 0, -4 },
    anchorBottom = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -DEBUG_SCROLL_GUTTER, 4 },
    wheelStep = 40,
    valueStep = 20,
    enableMouseWheel = true,
    wheelOnChild = false,
    wheelSource = "slider",
    minScrollToShow = 1,
})
local debugScrollChild = debugViewport.child
local debugSearchRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugScrollChild,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Search query timing",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetSearchEnabled then
            AltArmy.Debug.SetSearchEnabled(checked)
        end
    end,
})
panel.debugSearchCheckbox = debugSearchRow.check

local debugSearchHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugSearchHint:SetPoint("TOPLEFT", debugSearchRow, "BOTTOMLEFT", 0, -8)
debugSearchHint:SetWidth(520)
debugSearchHint:SetJustifyH("LEFT")
debugSearchHint:SetText(
    "Logs search phase timings (lookup/expand/sort/enrich/filter), recipe UI (sort/collapse), "
        .. "scroll paint, and index-build timing in chat.")

local debugCooldownsRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugSearchHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Profession cooldown scans",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetCooldownsEnabled then
            AltArmy.Debug.SetCooldownsEnabled(checked)
        end
    end,
})
panel.debugCooldownsCheckbox = debugCooldownsRow.check

local debugCooldownsHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugCooldownsHint:SetPoint("TOPLEFT", debugCooldownsRow, "BOTTOMLEFT", 0, -8)
debugCooldownsHint:SetWidth(520)
debugCooldownsHint:SetJustifyH("LEFT")
debugCooldownsHint:SetText("Logs cooldown persistence when opening profession windows (e.g. Tailoring).")

local debugLevelHistoryRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugCooldownsHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Level history tracking",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetLevelHistoryEnabled then
            AltArmy.Debug.SetLevelHistoryEnabled(checked)
        end
    end,
})
panel.debugLevelHistoryCheckbox = debugLevelHistoryRow.check

local deleteAllHistoryConfirmPending = false

local debugDeleteAllHistoryBtn = CreateFrame("Button", nil, debugScrollChild, "UIPanelButtonTemplate")
debugDeleteAllHistoryBtn:SetSize(160, 22)
debugDeleteAllHistoryBtn:SetPoint("TOPLEFT", debugLevelHistoryRow, "BOTTOMLEFT", 0, -12)
debugDeleteAllHistoryBtn:SetText("Delete all history")
Theme.SkinDangerButton(debugDeleteAllHistoryBtn)
panel.debugDeleteAllHistoryBtn = debugDeleteAllHistoryBtn

local function ResetDeleteAllHistoryButton()
    deleteAllHistoryConfirmPending = false
    if panel.debugDeleteAllHistoryBtn then
        panel.debugDeleteAllHistoryBtn:SetText("Delete all history")
        panel.debugDeleteAllHistoryBtn:Enable()
    end
end

debugDeleteAllHistoryBtn:SetScript("OnClick", function(self)
    if deleteAllHistoryConfirmPending then
        deleteAllHistoryConfirmPending = false
        local DS = AltArmy and AltArmy.DataStore
        if DS and DS.DeleteAllLevelHistory then
            DS:DeleteAllLevelHistory()
        end
        self:SetText("Delete all history")
    else
        deleteAllHistoryConfirmPending = true
        self:SetText("Really Delete?")
    end
end)

local debugLevelHistoryHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugLevelHistoryHint:SetPoint("TOPLEFT", debugDeleteAllHistoryBtn, "BOTTOMLEFT", 0, -12)
debugLevelHistoryHint:SetWidth(520)
debugLevelHistoryHint:SetJustifyH("LEFT")
debugLevelHistoryHint:SetText("Logs level history import checks, decisions, and stored milestone summaries.")

local debugItemComparisonRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugLevelHistoryHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Item comparison details",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetItemComparisonEnabled then
            AltArmy.Debug.SetItemComparisonEnabled(checked)
        end
    end,
})
panel.debugItemComparisonCheckbox = debugItemComparisonRow.check

local debugItemComparisonHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugItemComparisonHint:SetPoint("TOPLEFT", debugItemComparisonRow, "BOTTOMLEFT", 0, -8)
debugItemComparisonHint:SetWidth(520)
debugItemComparisonHint:SetJustifyH("LEFT")
debugItemComparisonHint:SetText(
    "Logs every comparison algorithm for each equippable alt when you loot an item or run /altarmy debug item.")

local debugItemStatsRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugItemComparisonHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Item stat parsing details",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetItemStatsEnabled then
            AltArmy.Debug.SetItemStatsEnabled(checked)
        end
    end,
})
panel.debugItemStatsCheckbox = debugItemStatsRow.check

local debugItemStatsHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugItemStatsHint:SetPoint("TOPLEFT", debugItemStatsRow, "BOTTOMLEFT", 0, -8)
debugItemStatsHint:SetWidth(520)
debugItemStatsHint:SetJustifyH("LEFT")
debugItemStatsHint:SetText(
    "Logs API vs tooltip stat parsing when comparing items. Use /altarmy debug stats with an item on the cursor.")

local debugGuildShareVerboseRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugItemStatsHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Guild sharing traffic (verbose)",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetGuildShareVerbose then
            AltArmy.Debug.SetGuildShareVerbose(checked)
        end
    end,
})
panel.debugGuildShareVerboseCheckbox = debugGuildShareVerboseRow.check

local debugGuildShareVerboseHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugGuildShareVerboseHint:SetPoint("TOPLEFT", debugGuildShareVerboseRow, "BOTTOMLEFT", 0, -8)
debugGuildShareVerboseHint:SetWidth(520)
debugGuildShareVerboseHint:SetJustifyH("LEFT")
debugGuildShareVerboseHint:SetText(
    "Prints every guild-share message sent/received to chat.")

local clearManualGroupsConfirmPending = false

local debugClearManualGroupsBtn = CreateFrame("Button", nil, debugScrollChild, "UIPanelButtonTemplate")
debugClearManualGroupsBtn:SetSize(200, 22)
debugClearManualGroupsBtn:SetPoint("TOPLEFT", debugGuildShareVerboseHint, "BOTTOMLEFT", 0, -12)
debugClearManualGroupsBtn:SetText("Clear manual groups")
Theme.SkinDangerButton(debugClearManualGroupsBtn)
panel.debugClearManualGroupsBtn = debugClearManualGroupsBtn

local function ResetClearManualGroupsButton()
    clearManualGroupsConfirmPending = false
    if panel.debugClearManualGroupsBtn then
        panel.debugClearManualGroupsBtn:SetText("Clear manual groups")
        panel.debugClearManualGroupsBtn:Enable()
    end
end

debugClearManualGroupsBtn:SetScript("OnClick", function(self)
    if clearManualGroupsConfirmPending then
        clearManualGroupsConfirmPending = false
        local GMG = AltArmy and AltArmy.GuildManualGroups
        if GMG and GMG.ClearAll then
            GMG.ClearAll()
        end
        if AltArmy.RefreshGuildTab then
            AltArmy.RefreshGuildTab()
        end
        self:SetText("Clear manual groups")
    else
        clearManualGroupsConfirmPending = true
        self:SetText("Really clear?")
    end
end)

local debugClearManualGroupsHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugClearManualGroupsHint:SetPoint("TOPLEFT", debugClearManualGroupsBtn, "BOTTOMLEFT", 0, -12)
debugClearManualGroupsHint:SetWidth(520)
debugClearManualGroupsHint:SetJustifyH("LEFT")
debugClearManualGroupsHint:SetText(
    "Deletes every local manual main/alt grouping (user and note-accepted). Does not affect shared Alt Army data.")

-- Clear auction data (two clicks, like Clear manual groups); state on the button to spare main-chunk locals.
panel.debugClearAuctionBtn = CreateFrame("Button", nil, debugScrollChild, "UIPanelButtonTemplate")
panel.debugClearAuctionBtn:SetSize(200, 22)
panel.debugClearAuctionBtn:SetPoint("TOPLEFT", debugClearManualGroupsHint, "BOTTOMLEFT", 0, -12)
panel.debugClearAuctionBtn:SetText("Clear auction data")
Theme.SkinDangerButton(panel.debugClearAuctionBtn)
panel.debugClearAuctionBtn.Reset = function(self)
    self.confirmPending = false
    self:SetText("Clear auction data")
    self:Enable()
end
panel.debugClearAuctionBtn:SetScript("OnClick", function(self)
    if not self.confirmPending then
        self.confirmPending = true
        self:SetText("Really clear?")
        return
    end
    self:Reset()
    local B = AltArmy and AltArmy.AuctionBook
    local count = B and B.Clear and B.Clear() or 0
    local econ = AltArmy.TabFrames and AltArmy.TabFrames.Economy
    if econ and econ.RefreshWaylaid and econ:IsShown() then
        econ.RefreshWaylaid()
    end
    if AltArmy.Debug and AltArmy.Debug.NotifyChat then
        AltArmy.Debug.NotifyChat(string.format("Cleared %d auction house scan(s).", count))
    end
end)

local debugClearAuctionHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugClearAuctionHint:SetPoint("TOPLEFT", panel.debugClearAuctionBtn, "BOTTOMLEFT", 0, -12)
debugClearAuctionHint:SetWidth(520)
debugClearAuctionHint:SetJustifyH("LEFT")
debugClearAuctionHint:SetText(
    "Deletes every stored auction house scan (all realms and factions) used by Economy > Waylaid Crates "
        .. "and the Alt Army website. The client's 15-minute full-scan cooldown is kept.")

local debugShowZygorMissingRow = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugClearAuctionHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Show Zygor guides (trial placeholders)",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetShowZygorMissingGuides then
            AltArmy.Debug.SetShowZygorMissingGuides(checked)
        end
        if AltArmy.Debug and AltArmy.Debug.RefreshZygorDependentUi then
            AltArmy.Debug.RefreshZygorDependentUi()
        end
    end,
})
panel.debugShowZygorMissingCheckbox = debugShowZygorMissingRow.check

local debugShowZygorMissingHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
debugShowZygorMissingHint:SetPoint("TOPLEFT", debugShowZygorMissingRow, "BOTTOMLEFT", 0, -8)
debugShowZygorMissingHint:SetWidth(520)
debugShowZygorMissingHint:SetJustifyH("LEFT")
debugShowZygorMissingHint:SetText(
    "On the Reputation tab, show Zygor guide icons even when Zygor only has trial placeholder "
        .. "guides (they cannot be opened). Paid Zygor installs show icons without this.")

-- Window resize (on panel, to spare main-chunk locals). Also /altarmy debug resize on|off.
panel.debugWindowResizeCheckbox = Theme.CreateLabeledCheckbox(debugScrollChild, {
    point = "TOPLEFT",
    relativeTo = debugShowZygorMissingHint,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -16,
    text = "Window resize",
    fullWidthHover = true,
    onClick = function(checked)
        if AltArmy.Debug and AltArmy.Debug.SetWindowResizeEnabled then
            AltArmy.Debug.SetWindowResizeEnabled(checked)
        end
    end,
}).check

panel.debugWindowResizeHint = debugScrollChild:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
panel.debugWindowResizeHint:SetPoint("TOPLEFT", panel.debugWindowResizeCheckbox, "BOTTOMLEFT", 0, -8)
panel.debugWindowResizeHint:SetWidth(520)
panel.debugWindowResizeHint:SetJustifyH("LEFT")
panel.debugWindowResizeHint:SetText(
    "Shows the main window's resize grip (bottom right) and opens it at its saved size; /altarmy resetsize "
        .. "restores the stock size. Only the Inventory tab reflows so far. Off puts the window back to its "
        .. "stock size and keeps the saved one.")

local function UpdateDebugScrollRange()
    local top = debugScrollChild:GetTop()
    local bottom = panel.debugWindowResizeHint:GetBottom()
    if top and bottom then
        debugScrollChild:SetHeight(math.max(1, top - bottom + 16))
    else
        debugScrollChild:SetHeight(900)
    end
    if debugViewport and debugViewport.UpdateRange then
        debugViewport.UpdateRange()
    end
end
panel.UpdateDebugScrollRange = UpdateDebugScrollRange

tabDebug:HookScript("OnShow", function()
    UpdateDebugScrollRange()
end)

function RefreshDebugCheckboxes()
    local D = AltArmy and AltArmy.Debug
    if not D or not D.Ensure then return end
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if panel.debugSearchCheckbox then
        panel.debugSearchCheckbox:SetChecked(d.search == true)
    end
    if panel.debugCooldownsCheckbox then
        panel.debugCooldownsCheckbox:SetChecked(d.cooldowns == true)
    end
    if panel.debugLevelHistoryCheckbox then
        panel.debugLevelHistoryCheckbox:SetChecked(d.levelHistory == true)
    end
    if panel.debugItemComparisonCheckbox then
        panel.debugItemComparisonCheckbox:SetChecked(d.itemComparison == true)
    end
    if panel.debugItemStatsCheckbox then
        panel.debugItemStatsCheckbox:SetChecked(d.itemStats == true)
    end
    if panel.debugGuildShareVerboseCheckbox then
        panel.debugGuildShareVerboseCheckbox:SetChecked(d.guildShareVerbose == true)
    end
    if panel.debugShowZygorMissingCheckbox then
        panel.debugShowZygorMissingCheckbox:SetChecked(d.showZygorMissingGuides == true)
    end
    if panel.debugWindowResizeCheckbox then
        panel.debugWindowResizeCheckbox:SetChecked(d.windowResize == true)
    end
    ResetDeleteAllHistoryButton()
    ResetClearManualGroupsButton()
    panel.debugClearAuctionBtn:Reset()
    UpdateDebugScrollRange()
end
panel.RefreshDebugCheckboxes = RefreshDebugCheckboxes

function RefreshDebugTabVisibility()
    local D = AltArmy and AltArmy.Debug
    local btn = tabButtons["debug"]
    if not D or not D.IsEnabled or not btn then return end
    if D.IsEnabled() then
        btn:Show()
    else
        btn:Hide()
        if activeOptionsTab == "debug" then
            SetActiveOptionsTab("general")
        end
    end
end
panel.RefreshDebugTabVisibility = RefreshDebugTabVisibility

RefreshDebugTabVisibility()

-- ---------------------------------------------------------------------------
-- General tab: collapsible sections (General, Guild, Auction House) in a scroll area, since Guild and
-- Auction House open together can outgrow the Interface Options canvas.
-- ---------------------------------------------------------------------------

local GENERAL_SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local generalViewport = Theme.CreateVerticalScrollViewport({
    name = "AltArmyTBC_GeneralOptionsScroll",
    parent = tabGeneral,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", tabGeneral, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -GENERAL_SCROLL_GUTTER, 4 },
    wheelStep = 40,
    valueStep = 20,
    enableMouseWheel = true,
    wheelOnChild = false,
    wheelSource = "slider",
    minScrollToShow = 1,
})
local generalScrollChild = generalViewport.child

local LayoutGeneralSections -- defined once every section is built
local function onSectionToggled()
    if LayoutGeneralSections then
        LayoutGeneralSections()
    end
end

local generalSection = Theme.CreateCollapsibleSection(generalScrollChild, {
    text = "General",
    defaultExpanded = true,
    onToggle = onSectionToggled,
})
local guildSection = Theme.CreateCollapsibleSection(generalScrollChild, {
    text = "Guild",
    defaultExpanded = true,
    onToggle = onSectionToggled,
})
local auctionSection = Theme.CreateCollapsibleSection(generalScrollChild, {
    text = "Auction House",
    defaultExpanded = true,
    onToggle = onSectionToggled,
})
-- Advanced: last, closed at first. On panel, not a main-chunk local (Lua 5.1's 200-local limit).
panel.advancedSection = Theme.CreateCollapsibleSection(generalScrollChild, {
    text = "Advanced",
    defaultExpanded = false,
    onToggle = onSectionToggled,
})

local minimapRow = Theme.CreateLabeledCheckbox(generalSection.content, {
    point = "TOPLEFT",
    relativeTo = generalSection.content,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Show Minimap Button",
    fullWidthHover = true,
    onClick = function(checked)
        AltArmyTBC_Options.showMinimapButton = checked
        if AltArmyTBC_Options.minimap then
            AltArmyTBC_Options.minimap.hide = not checked
        end
        applyMinimapOption()
    end,
})
panel.minimapCheckbox = minimapRow.check

local REALM_FILTER_MENU = {
    { value = "currentRealm", label = "View characters on current realm only" },
    { value = "all",          label = "View characters on all realms at once" },
}

local function realmFilterEntries()
    local out = {}
    for i = 1, #REALM_FILTER_MENU do
        local entry = REALM_FILTER_MENU[i]
        out[i] = { id = entry.value, label = entry.label }
    end
    return out
end

local REALM_FILTER_ROW_HEIGHT = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24
local realmFilterRow = CreateFrame("Frame", nil, generalSection.content)
realmFilterRow:SetPoint("TOPLEFT", minimapRow, "BOTTOMLEFT", 0, -14)
realmFilterRow:SetPoint("RIGHT", generalSection.content, "RIGHT", 0, 0)
realmFilterRow:SetHeight(REALM_FILTER_ROW_HEIGHT)

local realmFilterColumn = CreateFrame("Frame", nil, realmFilterRow)
realmFilterColumn:SetPoint("TOP", realmFilterRow, "TOP", 0, 0)
realmFilterColumn:SetPoint("BOTTOM", realmFilterRow, "BOTTOM", 0, 0)
realmFilterColumn:SetPoint("LEFT", realmFilterRow, "LEFT", 0, 0)
realmFilterColumn:SetPoint("RIGHT", realmFilterRow, "CENTER", -8, 0)

local realmFilterDropdown = Theme.CreateSingleSelectDropdown({
    parent = realmFilterColumn,
    point = "TOPLEFT",
    relativeTo = realmFilterColumn,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    rowHeight = REALM_FILTER_ROW_HEIGHT,
    dropdownParent = tabGeneral,
    getEntries = realmFilterEntries,
    getSelectedId = function()
        local G = AltArmy.GlobalRealmFilter
        if G and G.Get then
            G.Ensure()
            return G.Get()
        end
        return "all"
    end,
    onSelect = function(id)
        local G = AltArmy.GlobalRealmFilter
        if G and G.Set then
            G.Set(id)
        end
    end,
})
realmFilterDropdown.button:ClearAllPoints()
realmFilterDropdown.button:SetPoint("TOPLEFT", realmFilterColumn, "TOPLEFT", 0, 0)
realmFilterDropdown.button:SetPoint("BOTTOMRIGHT", realmFilterColumn, "BOTTOMRIGHT", 0, 0)
realmFilterDropdown.popup:ClearAllPoints()
realmFilterDropdown.popup:SetPoint("TOPLEFT", realmFilterDropdown.button, "BOTTOMLEFT", 0, -2)
realmFilterDropdown.popup:SetPoint("TOPRIGHT", realmFilterDropdown.button, "BOTTOMRIGHT", 0, -2)

local function RefreshRealmFilterDropdown()
    if realmFilterDropdown and realmFilterDropdown.Update then
        realmFilterDropdown:Update()
    end
end

RefreshRealmFilterDropdown()
panel.realmFilterDropdown = realmFilterDropdown
panel.RefreshRealmFilterDropdown = RefreshRealmFilterDropdown

-- Guild sharing settings (only shown when the guildShare feature flag is on).
local GUILD_SHARING_ROW_GAP = 16
local GUILD_TOP_ROW_HEIGHT = 22 -- the share checkbox and Manage exceptions

local function setGuildSharingCheckboxCaptionMuted(fontString, muted)
    if not fontString then return end
    if muted then
        fontString:SetTextColor(0.5, 0.5, 0.5)
    else
        fontString:SetTextColor(1, 1, 1)
    end
end

local function showSharingRequiredTooltip(owner, opts)
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.PresentSharingRequiredTooltip then
        GSS.PresentSharingRequiredTooltip(owner, "ANCHOR_RIGHT", opts)
        return
    end
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(
        (GSS and GSS.SHARING_REQUIRED_CONTROL_TOOLTIP)
            or "Turn on guild sharing to enable this option.",
        1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function hideSharingRequiredTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

--- Keep mouse enabled while disabled so a "turn on sharing" tooltip can still show.
local function setGuildSharingCheckboxEnabled(row, enabled)
    if not row then return end
    row._sharingRequiredTooltip = not enabled
    if enabled then
        row.check:Enable()
        setGuildSharingCheckboxCaptionMuted(row.label, false)
    else
        row.check:Disable()
        setGuildSharingCheckboxCaptionMuted(row.label, true)
    end
    if row.hoverRegion then row.hoverRegion:EnableMouse(true) end
end

local function attachSharingRequiredTooltip(frame, isActive)
    if not frame or not frame.HookScript then return end
    frame:HookScript("OnEnter", function(self)
        if isActive and isActive() then
            showSharingRequiredTooltip(self)
        end
    end)
    frame:HookScript("OnLeave", function()
        hideSharingRequiredTooltip()
    end)
end

--- Overlay so disabled buttons (which may not receive OnEnter) still show the tooltip.
--- opts: showConfigureHint (boolean), onClick (function).
local function createSharingRequiredHoverOverlay(anchor, opts)
    if not anchor then return nil end
    opts = opts or {}
    local overlay = CreateFrame("Frame", nil, anchor:GetParent() or anchor)
    overlay:SetAllPoints(anchor)
    overlay:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 0) + 5)
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay:SetScript("OnEnter", function(self)
        showSharingRequiredTooltip(self, {
            showConfigureHint = opts.showConfigureHint == true,
        })
    end)
    overlay:SetScript("OnLeave", function()
        hideSharingRequiredTooltip()
    end)
    if opts.onClick then
        overlay:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            hideSharingRequiredTooltip()
            opts.onClick()
        end)
    end
    return overlay
end

local refreshGuildSharingDependentControls

local guildSharingBlock = CreateFrame("Frame", nil, guildSection.content)
guildSharingBlock:SetPoint("TOPLEFT", guildSection.content, "TOPLEFT", 0, 0)
guildSharingBlock:SetPoint("RIGHT", guildSection.content, "RIGHT", 0, 0)
guildSharingBlock:SetHeight(1)

local GUILD_SHARING_HALF_GAP = 8

--- Split a row into left/right halves. Never anchor TOPLEFT to CENTER — CENTER includes
--- vertical midpoint and drops the right column by ~half the row height.
local function anchorGuildSharingLeftHalf(frame, parent, gap)
    gap = gap or GUILD_SHARING_HALF_GAP
    frame:ClearAllPoints()
    frame:SetPoint("TOP", parent, "TOP", 0, 0)
    frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    frame:SetPoint("LEFT", parent, "LEFT", 0, 0)
    frame:SetPoint("RIGHT", parent, "CENTER", -gap, 0)
end

local function anchorGuildSharingRightHalf(frame, parent, gap)
    gap = gap or GUILD_SHARING_HALF_GAP
    frame:ClearAllPoints()
    frame:SetPoint("TOP", parent, "TOP", 0, 0)
    frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    frame:SetPoint("LEFT", parent, "CENTER", gap, 0)
    frame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
end

local function anchorGuildSharingLeftCaption(fontString, parent, gap)
    gap = gap or GUILD_SHARING_HALF_GAP
    fontString:ClearAllPoints()
    fontString:SetPoint("TOP", parent, "TOP", 0, 0)
    fontString:SetPoint("LEFT", parent, "LEFT", 0, 0)
    fontString:SetPoint("RIGHT", parent, "CENTER", -gap, 0)
end

local function anchorGuildSharingRightCaption(fontString, parent, gap)
    gap = gap or GUILD_SHARING_HALF_GAP
    fontString:ClearAllPoints()
    fontString:SetPoint("TOP", parent, "TOP", 0, 0)
    fontString:SetPoint("LEFT", parent, "CENTER", gap, 0)
    fontString:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
end

local guildShareTopRow = CreateFrame("Frame", nil, guildSharingBlock)
guildShareTopRow:SetPoint("TOPLEFT", guildSharingBlock, "TOPLEFT", 0, 0)
guildShareTopRow:SetPoint("RIGHT", guildSharingBlock, "RIGHT", 0, 0)
guildShareTopRow:SetHeight(GUILD_TOP_ROW_HEIGHT)

local guildShareEnableColumn = CreateFrame("Frame", nil, guildShareTopRow)
anchorGuildSharingLeftHalf(guildShareEnableColumn, guildShareTopRow)

local guildShareEnableRow = Theme.CreateLabeledCheckbox(guildShareEnableColumn, {
    point = "TOPLEFT",
    relativeTo = guildShareEnableColumn,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Share my characters with my guild",
    fullWidthHover = true,
    rightInset = 0,
    onClick = function(checked)
        local GSS = AltArmy.GuildShareSettings
        if GSS then
            GSS.SetSharingEnabled(checked)
            if checked and GSS.EnsureDefaultMainIfMissing then
                GSS.EnsureDefaultMainIfMissing()
            end
        end
        if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
        if AltArmy.RefreshSearchCategoryBar then AltArmy.RefreshSearchCategoryBar() end
        if refreshGuildSharingDependentControls then refreshGuildSharingDependentControls() end
        if panel.RefreshCharGuildShareDropdown then panel.RefreshCharGuildShareDropdown() end
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
    end,
})
panel.guildShareEnableCheckbox = guildShareEnableRow.check
do
    local GSO = AltArmy.GuildShareOnboarding
    if GSO and GSO.GetSharingDisclosureTooltip and Theme.AttachSettingsHelpIcon then
        Theme.AttachSettingsHelpIcon(guildShareEnableRow, GSO.GetSharingDisclosureTooltip())
    end
end

-- Hit region covering the share checkbox for attention flashes from Characters tab.
local guildShareEnableFocusRegion = CreateFrame("Frame", nil, guildShareTopRow)
guildShareEnableFocusRegion:EnableMouse(false)
anchorGuildSharingLeftHalf(guildShareEnableFocusRegion, guildShareTopRow)

local guildManageExceptionsBtn = CreateFrame("Button", nil, guildSharingBlock, "UIPanelButtonTemplate")
guildManageExceptionsBtn:SetSize(140, 22)
guildManageExceptionsBtn:SetPoint("LEFT", guildShareTopRow, "CENTER", GUILD_SHARING_HALF_GAP, 0)
guildManageExceptionsBtn:SetPoint("TOP", guildShareTopRow, "TOP", 0, 0)
guildManageExceptionsBtn:SetText("Manage exceptions")
Theme.SkinButton(guildManageExceptionsBtn)
guildManageExceptionsBtn:SetScript("OnClick", function()
    if not guildManageExceptionsBtn:IsEnabled() then return end
    SetActiveOptionsTab("characters")
end)
local guildManageExceptionsSharingOverlay = createSharingRequiredHoverOverlay(guildManageExceptionsBtn)

local guildSharingTail = CreateFrame("Frame", nil, guildSharingBlock)
guildSharingTail:SetPoint("RIGHT", guildSharingBlock, "RIGHT", 0, 0)

local layoutGuildSharingTail
local GUILD_IDENTITY_CONTROL_HEIGHT = 22
local GUILD_IDENTITY_LABEL_HEIGHT = 14
local GUILD_IDENTITY_CONTROL_GAP = 2
local GUILD_IDENTITY_ROW_HEIGHT = GUILD_IDENTITY_LABEL_HEIGHT
    + GUILD_IDENTITY_CONTROL_GAP + GUILD_IDENTITY_CONTROL_HEIGHT
local GUILD_CHAT_CHECK_ROW_HEIGHT = Theme.CHAR_LIST_ROW_HEIGHT or 20
local GUILD_CHAT_CHANNELS_LABEL_HEIGHT = GUILD_IDENTITY_LABEL_HEIGHT
local GUILD_CHAT_CHANNELS_CONTROL_HEIGHT = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24
local GUILD_CHAT_CHANNELS_ROW_HEIGHT = GUILD_CHAT_CHANNELS_LABEL_HEIGHT
    + GUILD_IDENTITY_CONTROL_GAP + GUILD_CHAT_CHANNELS_CONTROL_HEIGHT
local GUILD_SUBHEADING_HEIGHT = 16 -- "Data retention", "Chat"
local GUILD_TWO_CHECK_ROW_HEIGHT = GUILD_CHAT_CHECK_ROW_HEIGHT + 4
--- The Guild section's content, top to bottom: the share row, the identity row, Data retention, Chat
--- and its channels (each row's height and the gaps between them, as laid out below).
local GUILD_CONTENT_HEIGHT = GUILD_TOP_ROW_HEIGHT
    + GUILD_SHARING_ROW_GAP + GUILD_IDENTITY_ROW_HEIGHT
    + GUILD_SHARING_ROW_GAP + GUILD_SUBHEADING_HEIGHT + 8 + GUILD_TWO_CHECK_ROW_HEIGHT
    + GUILD_SHARING_ROW_GAP + GUILD_SUBHEADING_HEIGHT + 8 + GUILD_TWO_CHECK_ROW_HEIGHT
    + GUILD_SHARING_ROW_GAP + GUILD_CHAT_CHANNELS_ROW_HEIGHT
-- Real heights: WoW doesn't re-resolve a frame without one when what it hangs from moves, so rows
-- anchored to a zero-height tail kept a stale position and overlapped the section header.
guildSharingBlock:SetHeight(GUILD_CONTENT_HEIGHT)
guildSharingTail:SetHeight(GUILD_CONTENT_HEIGHT - GUILD_TOP_ROW_HEIGHT - GUILD_SHARING_ROW_GAP)

local guildIdentityRow = CreateFrame("Frame", nil, guildSharingTail)
guildIdentityRow:SetPoint("TOPLEFT", guildSharingTail, "TOPLEFT", 0, 0)
guildIdentityRow:SetPoint("RIGHT", guildSharingTail, "RIGHT", 0, 0)
guildIdentityRow:SetHeight(GUILD_IDENTITY_ROW_HEIGHT)

local guildIdentityLabelRow = CreateFrame("Frame", nil, guildIdentityRow)
guildIdentityLabelRow:SetPoint("TOPLEFT", guildIdentityRow, "TOPLEFT", 0, 0)
guildIdentityLabelRow:SetPoint("RIGHT", guildIdentityRow, "RIGHT", 0, 0)
guildIdentityLabelRow:SetHeight(GUILD_IDENTITY_LABEL_HEIGHT)

local guildMainLabel = guildIdentityLabelRow:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
anchorGuildSharingLeftCaption(guildMainLabel, guildIdentityLabelRow)
guildMainLabel:SetJustifyH("LEFT")
guildMainLabel:SetWordWrap(true)
guildMainLabel:SetText("What is your main character?")

local guildDisplayLabel = guildIdentityLabelRow:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
anchorGuildSharingRightCaption(guildDisplayLabel, guildIdentityLabelRow)
guildDisplayLabel:SetJustifyH("LEFT")
guildDisplayLabel:SetWordWrap(true)
guildDisplayLabel:SetText("What should people call you?")

local guildIdentityControlRow = CreateFrame("Frame", nil, guildIdentityRow)
guildIdentityControlRow:SetPoint("TOPLEFT", guildIdentityLabelRow, "BOTTOMLEFT", 0, -GUILD_IDENTITY_CONTROL_GAP)
guildIdentityControlRow:SetPoint("RIGHT", guildIdentityRow, "RIGHT", 0, 0)
guildIdentityControlRow:SetHeight(GUILD_IDENTITY_CONTROL_HEIGHT)

local guildMainControlColumn = CreateFrame("Frame", nil, guildIdentityControlRow)
anchorGuildSharingLeftHalf(guildMainControlColumn, guildIdentityControlRow)

local guildDisplayControlColumn = CreateFrame("Frame", nil, guildIdentityControlRow)
anchorGuildSharingRightHalf(guildDisplayControlColumn, guildIdentityControlRow)

local guildDisplayEdit
local guildChatChannelsDropdown

local guildMainDropdown = Theme.CreateSingleSelectDropdown({
    parent = guildMainControlColumn,
    dropdownParent = panel,
    rowHeight = GUILD_IDENTITY_CONTROL_HEIGHT,
    point = "TOPLEFT",
    relativePoint = "TOPLEFT",
    getEntries = function()
        local GSO = AltArmy.GuildShareOnboarding
        local GSS = AltArmy.GuildShareSettings
        local DS = AltArmy.DataStore
        if not GSO or not GSO.BuildRealmCharEntries or not DS or not DS.GetCharacters then
            return {}
        end
        local realm = GSS and GSS._CurrentRealm and GSS._CurrentRealm() or ""
        return GSO.BuildRealmCharEntries(DS:GetCharacters(realm) or {})
    end,
    getSelectedId = function()
        local GSS = AltArmy.GuildShareSettings
        return GSS and GSS.GetMain and GSS.GetMain() or nil
    end,
    onSelect = function(id)
        local GSS = AltArmy.GuildShareSettings
        local oldMain = GSS and GSS.GetMain and GSS.GetMain() or nil
        local oldDisplay = GSS and GSS.GetDisplayName and GSS.GetDisplayName() or nil
        if GSS and GSS.SetMain then GSS.SetMain(nil, id) end
        local DS = AltArmy.DataStore
        local realm = GSS and GSS._CurrentRealm and GSS._CurrentRealm() or ""
        local realmChars = DS and DS.GetCharacters and DS:GetCharacters(realm) or nil
        local syncDisplay = not GSS or not GSS.ShouldSyncDisplayNameWithMain
            or GSS.ShouldSyncDisplayNameWithMain(oldMain, oldDisplay, realmChars)
        if id and syncDisplay then
            local firstName = (GSS and GSS.FirstName and GSS.FirstName(id)) or id
            if guildDisplayEdit and Theme.SetEditBoxText then
                Theme.SetEditBoxText(guildDisplayEdit, firstName)
            end
            if GSS and GSS.SetDisplayName then
                GSS.SetDisplayName(nil, firstName)
            end
        end
        if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
    end,
})
guildMainDropdown.button:ClearAllPoints()
guildMainDropdown.button:SetPoint("TOPLEFT", guildMainControlColumn, "TOPLEFT", 0, 0)
guildMainDropdown.button:SetPoint("BOTTOMRIGHT", guildMainControlColumn, "BOTTOMRIGHT", 0, 0)
guildMainDropdown.popup:ClearAllPoints()
guildMainDropdown.popup:SetPoint("TOPLEFT", guildMainDropdown.button, "BOTTOMLEFT", 0, -2)
guildMainDropdown.popup:SetPoint("TOPRIGHT", guildMainDropdown.button, "BOTTOMRIGHT", 0, -2)

-- Hit region covering the main-character label + dropdown for attention flashes.
local guildMainFocusRegion = CreateFrame("Frame", nil, guildIdentityRow)
guildMainFocusRegion:EnableMouse(false)
anchorGuildSharingLeftHalf(guildMainFocusRegion, guildIdentityRow)

guildDisplayEdit = CreateFrame("EditBox", nil, guildDisplayControlColumn)
guildDisplayEdit:SetPoint("TOPLEFT", guildDisplayControlColumn, "TOPLEFT", 0, 0)
guildDisplayEdit:SetPoint("BOTTOMRIGHT", guildDisplayControlColumn, "BOTTOMRIGHT", 0, 0)
guildDisplayEdit:SetFontObject(Theme.FONTS.body)
guildDisplayEdit:SetAutoFocus(false)
guildDisplayEdit:SetTextInsets(6, 6, 0, 0)
local guildDisplayMaxLen = AltArmy.GuildShareSettings
    and AltArmy.GuildShareSettings.DISPLAY_NAME_MAX_LENGTH
if guildDisplayEdit.SetMaxLetters and guildDisplayMaxLen then
    guildDisplayEdit:SetMaxLetters(guildDisplayMaxLen)
end
Theme.ApplyInputTextures(guildDisplayEdit)
guildDisplayEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
guildDisplayEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
local function applyGuildDisplayNameFromEdit(box, broadcast)
    local GSS = AltArmy.GuildShareSettings
    if not (GSS and GSS.SetDisplayName) then return end
    local text = box:GetText() or ""
    local nextName = GSS.NormalizeDisplayName and GSS.NormalizeDisplayName(text) or text
    local prevName = GSS.GetDisplayName and GSS.GetDisplayName() or nil
    if nextName == prevName then
        if broadcast then
            local Comm = AltArmy.GuildShareComm
            if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
        end
        return
    end
    GSS.SetDisplayName(nil, text)
    if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
    if broadcast then
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
    end
end
guildDisplayEdit:SetScript("OnTextChanged", function(box, userInput)
    if userInput == false then return end
    applyGuildDisplayNameFromEdit(box, false)
end)
guildDisplayEdit:SetScript("OnEditFocusLost", function(box)
    applyGuildDisplayNameFromEdit(box, true)
end)

local guildDataRetentionHeader = Theme.CreateOptionsSectionLabel(guildSharingTail, {
    relativeTo = guildIdentityRow,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -GUILD_SHARING_ROW_GAP,
    text = "Data retention",
    justifyH = "LEFT",
})

guildDataRetentionHeader:SetHeight(GUILD_SUBHEADING_HEIGHT)

local guildDataRetentionRow = CreateFrame("Frame", nil, guildSharingTail)
guildDataRetentionRow:SetPoint("TOPLEFT", guildDataRetentionHeader, "BOTTOMLEFT", 0, -8)
guildDataRetentionRow:SetPoint("RIGHT", guildSharingTail, "RIGHT", 0, 0)
guildDataRetentionRow:SetHeight(GUILD_TWO_CHECK_ROW_HEIGHT)

local guildDataRetentionLeft = CreateFrame("Frame", nil, guildDataRetentionRow)
anchorGuildSharingLeftHalf(guildDataRetentionLeft, guildDataRetentionRow)

local guildAutoDeleteRow = Theme.CreateLabeledCheckbox(guildDataRetentionLeft, {
    point = "TOPLEFT",
    relativeTo = guildDataRetentionLeft,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Auto-delete old data",
    fullWidthHover = true,
    onClick = function(checked)
        local GSS = AltArmy.GuildShareSettings
        if GSS and GSS.SetAutoDeleteOldDataEnabled then
            GSS.SetAutoDeleteOldDataEnabled(checked)
        end
        if checked then
            local Comm = AltArmy.GuildShareComm
            if Comm and Comm.PurgeStaleReceived then
                Comm.PurgeStaleReceived()
            end
        end
        if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
    end,
})
panel.guildAutoDeleteCheckbox = guildAutoDeleteRow.check
do
    local GSS = AltArmy.GuildShareSettings
    if Theme.AttachSettingsHelpIcon then
        Theme.AttachSettingsHelpIcon(guildAutoDeleteRow, {
            title = "Auto-delete old data",
            lines = {
                (GSS and GSS.AUTO_DELETE_OLD_DATA_TOOLTIP)
                    or "Data shared by others will be automatically deleted if it's more than 6 months old.",
            },
        })
    end
end
attachSharingRequiredTooltip(guildAutoDeleteRow.hoverRegion, function()
    return guildAutoDeleteRow._sharingRequiredTooltip == true
end)
attachSharingRequiredTooltip(guildAutoDeleteRow.check, function()
    return guildAutoDeleteRow._sharingRequiredTooltip == true
end)

local guildChatHeader = Theme.CreateOptionsSectionLabel(guildSharingTail, {
    relativeTo = guildDataRetentionRow,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -GUILD_SHARING_ROW_GAP,
    text = "Chat",
    justifyH = "LEFT",
})

guildChatHeader:SetHeight(GUILD_SUBHEADING_HEIGHT)

local guildChatChecksRow = CreateFrame("Frame", nil, guildSharingTail)
guildChatChecksRow:SetPoint("TOPLEFT", guildChatHeader, "BOTTOMLEFT", 0, -8)
guildChatChecksRow:SetPoint("RIGHT", guildSharingTail, "RIGHT", 0, 0)
guildChatChecksRow:SetHeight(GUILD_TWO_CHECK_ROW_HEIGHT)

local guildChatLeftColumn = CreateFrame("Frame", nil, guildChatChecksRow)
anchorGuildSharingLeftHalf(guildChatLeftColumn, guildChatChecksRow)

local guildChatRightColumn = CreateFrame("Frame", nil, guildChatChecksRow)
anchorGuildSharingRightHalf(guildChatRightColumn, guildChatChecksRow)

local guildChatInsertRow = Theme.CreateLabeledCheckbox(guildChatLeftColumn, {
    point = "TOPLEFT",
    relativeTo = guildChatLeftColumn,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Show guildmate mains in chat",
    fullWidthHover = true,
    onClick = function(checked)
        local GSS = AltArmy.GuildShareSettings
        if GSS then GSS.SetChatInsertionEnabled(checked) end
        if refreshGuildSharingDependentControls then refreshGuildSharingDependentControls() end
    end,
})
panel.guildChatInsertCheckbox = guildChatInsertRow.check
attachSharingRequiredTooltip(guildChatInsertRow.hoverRegion, function()
    return guildChatInsertRow._sharingRequiredTooltip == true
end)
attachSharingRequiredTooltip(guildChatInsertRow.check, function()
    return guildChatInsertRow._sharingRequiredTooltip == true
end)

local guildChatClassColorRow = Theme.CreateLabeledCheckbox(guildChatRightColumn, {
    point = "TOPLEFT",
    relativeTo = guildChatRightColumn,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Color character names by class color",
    fullWidthHover = true,
    onClick = function(checked)
        local GSS = AltArmy.GuildShareSettings
        if GSS and GSS.SetChatInsertionClassColorEnabled then
            GSS.SetChatInsertionClassColorEnabled(checked)
        end
    end,
})
panel.guildChatClassColorCheckbox = guildChatClassColorRow.check

local guildChatChannelsRow = CreateFrame("Frame", nil, guildSharingTail)
guildChatChannelsRow:SetPoint("TOPLEFT", guildChatChecksRow, "BOTTOMLEFT", 0, -GUILD_SHARING_ROW_GAP)
guildChatChannelsRow:SetPoint("RIGHT", guildSharingTail, "RIGHT", 0, 0)
guildChatChannelsRow:SetHeight(GUILD_CHAT_CHANNELS_ROW_HEIGHT)

local guildChatChannelsLabelRow = CreateFrame("Frame", nil, guildChatChannelsRow)
guildChatChannelsLabelRow:SetPoint("TOPLEFT", guildChatChannelsRow, "TOPLEFT", 0, 0)
guildChatChannelsLabelRow:SetPoint("RIGHT", guildChatChannelsRow, "RIGHT", 0, 0)
guildChatChannelsLabelRow:SetHeight(GUILD_CHAT_CHANNELS_LABEL_HEIGHT)

local guildChatChannelsLabel = guildChatChannelsLabelRow:CreateFontString(
    nil, "ARTWORK", Theme.FONTS.body)
anchorGuildSharingLeftCaption(guildChatChannelsLabel, guildChatChannelsLabelRow)
guildChatChannelsLabel:SetJustifyH("LEFT")
guildChatChannelsLabel:SetWordWrap(true)
guildChatChannelsLabel:SetText("Which channels?")

local guildChatChannelsControlRow = CreateFrame("Frame", nil, guildChatChannelsRow)
guildChatChannelsControlRow:SetPoint(
    "TOPLEFT", guildChatChannelsLabelRow, "BOTTOMLEFT", 0, -GUILD_IDENTITY_CONTROL_GAP)
guildChatChannelsControlRow:SetPoint("RIGHT", guildChatChannelsRow, "RIGHT", 0, 0)
guildChatChannelsControlRow:SetHeight(GUILD_CHAT_CHANNELS_CONTROL_HEIGHT)

local guildChatChannelsColumn = CreateFrame("Frame", nil, guildChatChannelsControlRow)
anchorGuildSharingLeftHalf(guildChatChannelsColumn, guildChatChannelsControlRow)

guildChatChannelsDropdown = Theme.CreateMultiSelectCheckboxDropdown({
    parent = guildChatChannelsColumn,
    dropdownParent = panel,
    rowHeight = GUILD_CHAT_CHANNELS_CONTROL_HEIGHT,
    relativeTo = guildChatChannelsColumn,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    keys = (AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.CHAT_INSERTION_CHANNEL_ORDER) or {},
    labels = (AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.CHAT_INSERTION_CHANNEL_LABELS) or {},
    getRowLabel = function(key)
        local GSS = AltArmy.GuildShareSettings
        if GSS and GSS.FormatChatInsertionChannelDetailLabel then
            return GSS.FormatChatInsertionChannelDetailLabel(key)
        end
        if GSS and GSS.FormatChatInsertionChannelColoredLabel then
            return GSS.FormatChatInsertionChannelColoredLabel(key)
        end
        local labels = GSS and GSS.CHAT_INSERTION_CHANNEL_LABELS
        return labels and labels[key] or key
    end,
    getFilter = function()
        local GSS = AltArmy.GuildShareSettings
        return GSS and GSS.GetChatInsertionChannels and GSS.GetChatInsertionChannels() or {}
    end,
    setEnabled = function(key, checked)
        local GSS = AltArmy.GuildShareSettings
        if GSS and GSS.SetChatInsertionChannelEnabled then
            GSS.SetChatInsertionChannelEnabled(key, checked)
        end
    end,
    formatSummary = function(keys, labels, filter)
        local GSS = AltArmy.GuildShareSettings
        if GSS and GSS.FormatChatInsertionChannelSummary then
            return GSS.FormatChatInsertionChannelSummary(keys, labels, filter)
        end
        return ""
    end,
    formatSummaryDisabled = function(keys, labels, filter)
        filter = filter or {}
        local selected = {}
        for _, key in ipairs(keys) do
            if filter[key] ~= false then
                selected[#selected + 1] = labels[key] or key
            end
        end
        if #selected == 0 then
            return "None"
        end
        return table.concat(selected, ", ")
    end,
})
if guildChatChannelsDropdown and guildChatChannelsDropdown.button then
    guildChatChannelsDropdown.button:ClearAllPoints()
    guildChatChannelsDropdown.button:SetPoint("TOPLEFT", guildChatChannelsColumn, "TOPLEFT", 0, 0)
    guildChatChannelsDropdown.button:SetPoint("BOTTOMRIGHT", guildChatChannelsColumn, "BOTTOMRIGHT", 0, 0)
end

local guildChatChannelsSharingOverlay = guildChatChannelsDropdown
    and guildChatChannelsDropdown.button
    and createSharingRequiredHoverOverlay(guildChatChannelsDropdown.button)

function refreshGuildSharingDependentControls()
    local GSS = AltArmy.GuildShareSettings
    local sharingOn = GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled() == true
    local chatOn = GSS and GSS.IsChatInsertionEnabled and GSS.IsChatInsertionEnabled() == true
    -- Dependent controls only usable while sharing is on.
    setGuildSharingCheckboxEnabled(guildAutoDeleteRow, sharingOn)
    setGuildSharingCheckboxEnabled(guildChatInsertRow, sharingOn)
    -- Class-color checkbox needs both sharing and chat insertion.
    setGuildSharingCheckboxEnabled(guildChatClassColorRow, sharingOn and chatOn)
    if guildChatChannelsDropdown and guildChatChannelsDropdown.SetEnabled then
        guildChatChannelsDropdown:SetEnabled(sharingOn and chatOn)
    end
    if guildManageExceptionsBtn then
        if sharingOn then
            guildManageExceptionsBtn:Enable()
        else
            guildManageExceptionsBtn:Disable()
        end
    end
    if guildManageExceptionsSharingOverlay then
        guildManageExceptionsSharingOverlay:SetShown(not sharingOn)
    end
    if guildChatChannelsSharingOverlay then
        -- Overlay only while sharing is off (disabled buttons may not receive OnEnter).
        guildChatChannelsSharingOverlay:SetShown(not sharingOn)
    end
    if sharingOn then
        hideSharingRequiredTooltip()
    end
    if panel.RefreshCharGuildShareDropdown then
        panel.RefreshCharGuildShareDropdown()
    end
end

refreshGuildSharingDependentControls()

function layoutGuildSharingTail()
    guildSharingTail:ClearAllPoints()
    guildSharingTail:SetPoint("TOPLEFT", guildShareTopRow, "BOTTOMLEFT", 0, -GUILD_SHARING_ROW_GAP)
    guildSharingTail:SetPoint("RIGHT", guildSharingBlock, "RIGHT", 0, 0)
end

local function RefreshGuildSharingControls()
    local D = AltArmy.Debug
    local flagOn = D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()
    local shown = flagOn and true or false
    if shown ~= guildSection.IsShown() then
        guildSection.SetShown(shown)
        if LayoutGeneralSections then
            LayoutGeneralSections()
        end
    end
    if shown then
        local GSS = AltArmy.GuildShareSettings
        if GSS then
            guildShareEnableRow.check:SetChecked(GSS.IsSharingEnabled())
            if guildAutoDeleteRow and guildAutoDeleteRow.check
                and GSS.IsAutoDeleteOldDataEnabled then
                guildAutoDeleteRow.check:SetChecked(GSS.IsAutoDeleteOldDataEnabled())
            end
            guildChatInsertRow.check:SetChecked(GSS.IsChatInsertionEnabled())
            if guildChatClassColorRow and guildChatClassColorRow.check
                and GSS.IsChatInsertionClassColorEnabled then
                guildChatClassColorRow.check:SetChecked(GSS.IsChatInsertionClassColorEnabled())
            end
            local mainName = GSS.GetMain and GSS.GetMain() or nil
            if guildMainDropdown and guildMainDropdown.Update then
                guildMainDropdown:Update()
            end
            if guildDisplayEdit and not (guildDisplayEdit.HasFocus and guildDisplayEdit:HasFocus()) then
                local displayText = GSS.GetDisplayName and (GSS.GetDisplayName() or mainName or "") or ""
                if guildDisplayEdit:GetText() ~= displayText then
                    if Theme.SetEditBoxText then
                        Theme.SetEditBoxText(guildDisplayEdit, displayText)
                    else
                        guildDisplayEdit:SetText(displayText)
                    end
                end
            end
            if guildChatChannelsDropdown then
                guildChatChannelsDropdown:refresh()
            end
            if refreshGuildSharingDependentControls then refreshGuildSharingDependentControls() end
        end
        if panel.RefreshCharGuildShareDropdown then panel.RefreshCharGuildShareDropdown() end
        layoutGuildSharingTail()
    end
end
panel.RefreshGuildSharingControls = RefreshGuildSharingControls
layoutGuildSharingTail()

-- Auction House section: the Alt Army scan (Data/Auctions/AuctionScan.lua). Only on clients with the full
-- scan (WoW Forever); TBC Anniversary's auction house has none.
-- The automatic scan checkbox and the scan mode dropdown sit side by side, half the width each: a checkbox
-- row stretches to its parent's right edge, so each gets a half-width holder (on panel, not main-chunk
-- locals: Lua 5.1's 200-local limit).
panel.auctionLeftHolder = CreateFrame("Frame", nil, auctionSection.content)
panel.auctionLeftHolder:SetPoint("TOPLEFT", auctionSection.content, "TOPLEFT", 0, 0)
panel.auctionLeftHolder:SetPoint("TOPRIGHT", auctionSection.content, "TOP", -4, 0)
panel.auctionLeftHolder:SetHeight(Theme.CHAR_LIST_ROW_HEIGHT)
panel.auctionRightHolder = CreateFrame("Frame", nil, auctionSection.content)
panel.auctionRightHolder:SetPoint("TOPLEFT", auctionSection.content, "TOP", 4, 0)
panel.auctionRightHolder:SetPoint("TOPRIGHT", auctionSection.content, "TOPRIGHT", 0, 0)
panel.auctionRightHolder:SetHeight(Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24)
local autoScanRow = Theme.CreateLabeledCheckbox(panel.auctionLeftHolder, {
    point = "TOPLEFT",
    relativeTo = panel.auctionLeftHolder,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Scan AH automatically",
    fullWidthHover = true,
    onClick = function(checked)
        local S = AltArmy.AuctionScan
        if S and S.SetAutoScanEnabled then
            S.SetAutoScanEnabled(checked)
        end
    end,
})
panel.auctionAutoScanCheckbox = autoScanRow.check

-- Which scans run (AuctionScan.GetScanMode): full scans (every listing, 15-minute cooldown) and/or summary
-- scans (cheapest price per item, no cooldown). Kept on panel, not as main-chunk locals (Lua 5.1's 200-local
-- limit). The help icon sits at the holder's right; the dropdown fills the rest.
panel.AUCTION_SCAN_MODES = {
    { id = "prefer_full", label = "Prefer full scans" },
    { id = "only_full", label = "Only full scans" },
    { id = "only_summary", label = "Only summary scans" },
}
panel.auctionScanModeDropdown = Theme.CreateSingleSelectDropdown({
    parent = panel.auctionRightHolder,
    point = "TOPLEFT",
    relativeTo = panel.auctionRightHolder,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    rowHeight = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24,
    dropdownParent = tabGeneral,
    getEntries = function() return panel.AUCTION_SCAN_MODES end,
    getSelectedId = function()
        local S = AltArmy.AuctionScan
        return S and S.GetScanMode and S.GetScanMode() or "prefer_full"
    end,
    onSelect = function(id)
        local S = AltArmy.AuctionScan
        if S and S.SetScanMode then
            S.SetScanMode(id)
        end
    end,
})
panel.auctionScanModeHelp = Theme.AttachSettingsHelpIcon(panel.auctionRightHolder, {
    title = "Auction house scans",
    lines = {
        "A full scan lets us determine how many items are available at each cost. However, it is slower, "
            .. "and the game allows one every 15 minutes.",
        "A summary scan is fast and has no cooldown, but collects only each item's lowest price, so "
            .. "calculations and tooltips are less accurate.",
    },
})
do
    local dd = panel.auctionScanModeDropdown
    dd.button:ClearAllPoints()
    dd.button:SetPoint("TOPLEFT", panel.auctionRightHolder, "TOPLEFT", 0, 0)
    dd.button:SetPoint("BOTTOMRIGHT", panel.auctionRightHolder, "BOTTOMRIGHT", -20, 0)
    dd.popup:ClearAllPoints()
    dd.popup:SetPoint("TOPLEFT", dd.button, "BOTTOMLEFT", 0, -2)
    dd.popup:SetPoint("TOPRIGHT", dd.button, "BOTTOMRIGHT", 0, -2)
end

local function RefreshAuctionOptions()
    local S = AltArmy.AuctionScan
    panel.auctionAutoScanCheckbox:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)
    if panel.auctionScanModeDropdown.Update then
        panel.auctionScanModeDropdown:Update()
    end
end
panel.RefreshAuctionOptions = RefreshAuctionOptions
do
    local S = AltArmy.AuctionScan
    auctionSection.SetShown(S and S.HasApi and S.HasApi() or false)
end

-- Each section's content height, from its rows (as Blizzard's Settings sections compute theirs).
-- Advanced section: reading recipes in the background (Data/DataStore/OwnRecipeRead.lua). Only on clients
-- where it can (WoW Forever). Rows on panel, not main-chunk locals (Lua 5.1's 200-local limit).
panel.autoReadRecipesRow = Theme.CreateLabeledCheckbox(panel.advancedSection.content, {
    point = "TOPLEFT",
    relativeTo = panel.advancedSection.content,
    relativePoint = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Read recipes from profession links",
    fullWidthHover = true,
    onClick = function(checked)
        local R = AltArmy.OwnRecipeRead
        if R and R.SetEnabled then
            R.SetEnabled(checked)
        end
    end,
})
Theme.AttachSettingsHelpIcon(panel.autoReadRecipesRow, {
    title = "Read recipes from profession links",
    lines = {
        "When enabled, Alt Army will gather profession data using profession links. This lets it gather data "
            .. "in the background without you having to open the spell book.",
        "You'll only need to disable this if you're seeing flashes or sounds of the UI opening which are "
            .. "annoying you, or if this is causing bad interactions with other addons.",
    },
})

function panel.RefreshAdvancedOptions()
    local R = AltArmy.OwnRecipeRead
    panel.autoReadRecipesRow.check:SetChecked(not (R and R.IsEnabled) or R.IsEnabled())
end
panel.RefreshAdvancedOptions()
do
    local R = AltArmy.OwnRecipeRead
    panel.advancedSection.SetShown(R and R.HasApi and R.HasApi() or false)
end

generalSection.SetContentHeight(Theme.CHAR_LIST_ROW_HEIGHT + 14 + REALM_FILTER_ROW_HEIGHT)
guildSection.SetContentHeight(GUILD_CONTENT_HEIGHT)
auctionSection.SetContentHeight(math.max(Theme.CHAR_LIST_ROW_HEIGHT, Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24))
panel.advancedSection.SetContentHeight(Theme.CHAR_LIST_ROW_HEIGHT)

--- Where the General tab's section frames and the Guild rows actually are, for `/altarmy debug layout`
--- (a dev dump: see docs/DEV_DUMPS.md).
local function regionReport(region)
    if not region then return "missing" end
    local out = {
        top = region.GetTop and region:GetTop(),
        bottom = region.GetBottom and region:GetBottom(),
        left = region.GetLeft and region:GetLeft(),
        height = region.GetHeight and region:GetHeight(),
        shown = region.IsShown and region:IsShown(),
        points = {},
    }
    for i = 1, (region.GetNumPoints and region:GetNumPoints() or 0) do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
        local relName = relativeTo and relativeTo.GetDebugName and relativeTo:GetDebugName() or tostring(relativeTo)
        out.points[i] = string.format("%s -> %s %s (%s, %s)", tostring(point), tostring(relName),
            tostring(relativePoint), tostring(x), tostring(y))
    end
    return out
end

function panel.DumpGeneralLayout()
    local D = AltArmy.Debug
    if not (D and D.Dump) then return end
    D.Dump("optionsLayout", {
        scrollChild = regionReport(generalScrollChild),
        guildFrame = regionReport(guildSection.frame),
        guildHeader = regionReport(guildSection.header),
        guildContent = regionReport(guildSection.content),
        guildBlock = regionReport(guildSharingBlock),
        guildTopRow = regionReport(guildShareTopRow),
        guildEnableColumn = regionReport(guildShareEnableColumn),
        guildEnableRow = regionReport(guildShareEnableRow),
        guildTail = regionReport(guildSharingTail),
        guildIdentityRow = regionReport(guildIdentityRow),
        guildRetentionHeader = regionReport(guildDataRetentionHeader),
        guildRetentionRow = regionReport(guildDataRetentionRow),
        guildChatHeader = regionReport(guildChatHeader),
        guildChatChecksRow = regionReport(guildChatChecksRow),
        guildChatChannelsRow = regionReport(guildChatChannelsRow),
        auctionFrame = regionReport(auctionSection.frame),
        guildExpanded = guildSection.IsExpanded(),
        guildContentHeight = GUILD_CONTENT_HEIGHT,
    })
end

local generalSections = { generalSection, guildSection, auctionSection, panel.advancedSection }
local stackGeneralSections = Theme.StackCollapsibleSections(generalSections, { parent = generalScrollChild, gap = 8 })

--- Stack the sections and size the scroll area to them.
function LayoutGeneralSections()
    generalScrollChild:SetHeight(math.max(1, stackGeneralSections() + 8))
    if generalViewport.UpdateRange then
        generalViewport.UpdateRange()
    end
end
LayoutGeneralSections()

--- The section a flashed control lives in, and the control (see AltArmy.OpenInterfaceOptions).
local GENERAL_FLASH_TARGETS = {
    main = { section = guildSection, region = guildMainFocusRegion },
    guildShare = { section = guildSection, region = guildShareEnableFocusRegion },
    autoDelete = { section = guildSection, region = guildAutoDeleteRow },
    autoScan = { section = auctionSection, region = autoScanRow },
    scanMode = { section = auctionSection, region = panel.auctionRightHolder },
}

--- Show `flash`'s control: open only the section it is in (the others close), scroll it into view and
--- flash it. False if it is not on the General tab.
local function FocusGeneralControl(flash)
    local target = GENERAL_FLASH_TARGETS[flash]
    if not target then
        return false
    end
    for _, section in ipairs(generalSections) do
        section.SetExpanded(section == target.section, true)
    end
    LayoutGeneralSections()
    if generalViewport.SetOffset then
        generalViewport.SetOffset(0)
    end
    local function reveal()
        local top, rowTop, rowBottom = generalScrollChild:GetTop(), target.region:GetTop(), target.region:GetBottom()
        local viewHeight = generalViewport.scroll:GetHeight() or 0
        if top and rowTop and rowBottom and top - rowBottom > viewHeight and generalViewport.SetOffset then
            generalViewport.SetOffset(math.max(0, top - rowTop - 24))
        end
        if Theme.FlashAttentionHighlight then
            Theme.FlashAttentionHighlight(target.region)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, reveal) -- positions settle on the next frame
    else
        reveal()
    end
    return true
end

-- Host frame for UI/CooldownOptions.lua (loaded after this file)
panel.tabCooldownsHost = tabCooldowns
panel.tabGearUpgradesHost = tabGearUpgrades

-- ---------------------------------------------------------------------------
-- Selection state
-- ---------------------------------------------------------------------------

local selectedEntry        = nil   -- { name, realm, classFile } or nil
local deleteConfirmPending = false

-- Forward declarations
local RefreshCharacterList
local UpdateCharSettings

local function ResolveCharacterClassFile(name, realm)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacter then return nil end
    local charData = DS:GetCharacter(name, realm)
    return charData and charData.classFile or nil
end

local function SelectCharacterEntry(name, realm, classFile)
    if not name or not realm then
        selectedEntry = nil
        return
    end
    selectedEntry = {
        name = name,
        realm = realm,
        classFile = classFile or ResolveCharacterClassFile(name, realm),
    }
end

-- ---------------------------------------------------------------------------
-- Character scroll list (left column)
-- ---------------------------------------------------------------------------

local ROW_HEIGHT  = 20
local ROW_SPACING = 2
local ROW_STRIDE  = ROW_HEIGHT + ROW_SPACING
local ICON_SIZE   = 16
local LIST_HEIGHT = 220
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

local charListFrame = CreateFrame("Frame", nil, tabCharacters, "BackdropTemplate")
Theme.ApplyBackdrop(charListFrame, "section")
charListFrame:SetPoint("TOPLEFT", tabCharacters, "TOPLEFT", 0, 0)
charListFrame:SetPoint("RIGHT",   tabCharacters, "CENTER", -COL_GAP / 2, 0)
charListFrame:SetHeight(LIST_HEIGHT)

-- ScrollFrame clips the visible area; scrollChild holds all rows.
local charListViewport = Theme.CreateVerticalScrollViewport({
    parent = charListFrame,
    gutterEdge = charListFrame,
    anchorTop = { "TOPLEFT", charListFrame, "TOPLEFT", 4, -4 },
    anchorBottom = { "BOTTOMRIGHT", charListFrame, "BOTTOMRIGHT", -SCROLL_GUTTER, 4 },
    wheelStep = ROW_STRIDE * 3,
    valueStep = ROW_STRIDE,
    enableMouseWheel = true,
    wheelOnChild = false,
    wheelSource = "slider",
    fallbackViewHeight = LIST_HEIGHT - 8,
})
local scrollChild = charListViewport.child

-- Row pool — rows are Buttons parked under charListFrame when pooled.
local rowPool    = {}
local activeRows = {}

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)

        Theme.InstallRowHoverHighlight(row)

        local selBg = row:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints(row)
        selBg:SetVertexColor(0, 0, 0, 0)
        selBg:Hide()
        row.selBg = selBg
        row.altArmyRowBg = selBg
        Theme.InstallRowAccentBar(row)

        -- Race/class icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon = icon

        -- Fallback colored square when no race texture is available
        local iconFallback = row:CreateTexture(nil, "ARTWORK")
        iconFallback:SetSize(ICON_SIZE, ICON_SIZE)
        iconFallback:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.iconFallback = iconFallback

        -- Name – Realm label (stretches full width; no delete button in the row)
        local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        label:SetPoint("LEFT",  icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", row,  "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
    end
    row:SetParent(scrollChild)
    row:Show()
    activeRows[#activeRows + 1] = row
    return row
end

local function ReleaseAllRows()
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:SetParent(charListFrame)
        rowPool[#rowPool + 1] = row
    end
    activeRows = {}
end

local function RefreshCharacterList_impl()
    ReleaseAllRows()
    local chars = GetSortedCharacters()

    local totalH = math.max(1, #chars * ROW_STRIDE)
    scrollChild:SetHeight(totalH)
    charListViewport:UpdateRange()

    for i, entry in ipairs(chars) do
        local row = AcquireRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_STRIDE)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_STRIDE)
        row:SetHeight(ROW_HEIGHT)

        -- Class icon
        SetCharIcon(row.icon, row.iconFallback, entry.classFile)

        local RF = AltArmy.RealmFilter
        if RF and RF.formatColoredCharacterNameRealm then
            row.label:SetTextColor(1, 1, 1, 1)
            row.label:SetText(RF.formatColoredCharacterNameRealm(
                entry.name or "",
                entry.realm,
                true,
                entry.classFile
            ))
        else
            local r, g, b = 1, 1, 1
            if CC and CC.getRGBOr then
                r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
            end
            row.label:SetTextColor(r, g, b, 1)
            row.label:SetText((entry.name or "") .. " - " .. (entry.realm or ""))
        end

        -- Selection highlight
        local isSelected = selectedEntry
            and selectedEntry.name  == entry.name
            and selectedEntry.realm == entry.realm
        row.selBg:SetShown(isSelected == true)
        Theme.SetRowSelected(row, isSelected == true)

        -- Click: select this character and update the right pane
        local capName  = entry.name
        local capRealm = entry.realm
        local capClass = entry.classFile
        row:SetScript("OnClick", function()
            SelectCharacterEntry(capName, capRealm, capClass)
            UpdateCharSettings()
            RefreshCharacterList()
        end)
    end
end

RefreshCharacterList = RefreshCharacterList_impl

-- ---------------------------------------------------------------------------
-- Right column: Character Settings pane
-- ---------------------------------------------------------------------------

-- "Choose a character to begin" shown when nothing is selected
local charSettingPrompt = tabCharacters:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
charSettingPrompt:SetPoint("TOPLEFT", tabCharacters, "TOP", COL_GAP / 2, 0)
charSettingPrompt:SetText("Choose a character to begin")
charSettingPrompt:Show()

-- "{Name} options" shown when a character is selected (name is class-colored).
local charSettingHeader = tabCharacters:CreateFontString(nil, "ARTWORK", Theme.FONTS.title)
charSettingHeader:SetPoint("TOPLEFT", tabCharacters, "TOP", COL_GAP / 2, 0)
charSettingHeader:SetPoint("RIGHT", tabCharacters, "RIGHT", -16, 0)
charSettingHeader:SetJustifyH("LEFT")
charSettingHeader:Hide()

local function formatCharSettingHeader(entry)
    local titleRgb = Theme.COLORS and Theme.COLORS.title
    if CC and CC.formatNameWithSuffix then
        return CC.formatNameWithSuffix(entry.name, entry.classFile, " options", titleRgb)
    end
    return (entry.name or "?") .. " options"
end

local function setCharSettingHeader(entry)
    if not entry then
        charSettingHeader:Hide()
        return
    end
    charSettingHeader:SetText(formatCharSettingHeader(entry))
    -- White base so embedded class/title color codes render as authored.
    charSettingHeader:SetTextColor(1, 1, 1, 1)
    charSettingHeader:Show()
end

local BANK_ALT_HELP = {
    title = "Bank alt",
    lines = {
        "Hidden in Gear and Reputation tabs",
        "Skipped for gear upgrade checks",
        "Still appears in Summary, Cooldowns, Graphs, and Search",
    },
}

local function RefreshBankAltDependents()
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    RefreshCharacterList()
    local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
    if gearFrame and gearFrame.RefreshGrid then
        gearFrame:RefreshGrid()
    end
    local repFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Reputation
    if repFrame and repFrame.RefreshGrid then
        repFrame:RefreshGrid()
    end
end

local function isGuildShareOptionsEnabled()
    local D = AltArmy and AltArmy.Debug
    return D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()
end

local charGuildShareLabel = tabCharacters:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
charGuildShareLabel:SetPoint("TOPLEFT", charSettingHeader, "BOTTOMLEFT", 0, -12)
charGuildShareLabel:SetPoint("RIGHT", tabCharacters, "RIGHT", -16, 0)
charGuildShareLabel:SetJustifyH("LEFT")
charGuildShareLabel:SetText("Guild data sharing")
charGuildShareLabel:Hide()

local charGuildShareDropdown = Theme.CreateSingleSelectDropdown({
    parent = tabCharacters,
    dropdownParent = panel,
    relativeTo = charGuildShareLabel,
    relativePoint = "BOTTOMLEFT",
    y = -4,
    getEntries = function()
        local GSS = AltArmy.GuildShareSettings
        return GSS and GSS.GetCharacterShareModeEntries and GSS.GetCharacterShareModeEntries() or {}
    end,
    getSelectedId = function()
        if not selectedEntry then return "default" end
        local GSS = AltArmy.GuildShareSettings
        return GSS and GSS.GetCharacterShareMode(selectedEntry.name, selectedEntry.realm) or "default"
    end,
    onSelect = function(mode)
        if not selectedEntry then return end
        local GSS = AltArmy.GuildShareSettings
        local guildName = GSS and GSS._CurrentGuild and GSS._CurrentGuild() or nil
        if mode == "share" and not guildName then return end
        if GSS and GSS.SetCharacterShareMode then
            GSS.SetCharacterShareMode(selectedEntry.name, selectedEntry.realm, mode)
        end
        if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
    end,
})
charGuildShareDropdown.button:ClearAllPoints()
charGuildShareDropdown.button:SetPoint("TOPLEFT", charGuildShareLabel, "BOTTOMLEFT", 0, -4)
charGuildShareDropdown.button:SetPoint("RIGHT", tabCharacters, "RIGHT", -16, 0)
charGuildShareDropdown.button:Hide()
charGuildShareDropdown.popup:ClearAllPoints()
charGuildShareDropdown.popup:SetPoint("TOPLEFT", charGuildShareDropdown.button, "BOTTOMLEFT", 0, -2)
charGuildShareDropdown.popup:SetPoint("TOPRIGHT", charGuildShareDropdown.button, "BOTTOMRIGHT", 0, -2)
local charGuildShareSharingOverlay = createSharingRequiredHoverOverlay(charGuildShareDropdown.button, {
    showConfigureHint = true,
    onClick = function()
        if AltArmy.OpenInterfaceOptions then
            AltArmy.OpenInterfaceOptions("general", { flash = "guildShare" })
        end
    end,
})

local function RefreshCharGuildShareDropdown()
    if charGuildShareDropdown and charGuildShareDropdown.Update then
        charGuildShareDropdown:Update()
    end
    local GSS = AltArmy.GuildShareSettings
    local sharingOn = GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled() == true
    if charGuildShareDropdown and charGuildShareDropdown.SetEnabled then
        charGuildShareDropdown:SetEnabled(sharingOn)
    end
    local shown = charGuildShareDropdown.button and charGuildShareDropdown.button:IsShown()
    if charGuildShareSharingOverlay then
        charGuildShareSharingOverlay:SetShown(shown and not sharingOn)
    end
    setGuildSharingCheckboxCaptionMuted(charGuildShareLabel, shown and not sharingOn)
end
panel.RefreshCharGuildShareDropdown = RefreshCharGuildShareDropdown

local bankAltRow = Theme.CreateLabeledCheckbox(tabCharacters, {
    point = "TOPLEFT",
    relativeTo = charSettingHeader,
    relativePoint = "BOTTOMLEFT",
    x = 0,
    y = -12,
    text = "Bank alt",
    fullWidthHover = true,
    rightInset = 16,
    onClick = function(checked)
        if not selectedEntry then return end
        local BA = AltArmy.BankAlt
        if BA and BA.Set then
            BA.Set(selectedEntry.name, selectedEntry.realm, checked)
        end
        RefreshBankAltDependents()
    end,
})
Theme.AttachSettingsHelpIcon(bankAltRow, BANK_ALT_HELP)
local bankAltCheck = bankAltRow.check
bankAltRow:Hide()

local function layoutCharSettingRows()
    bankAltRow:ClearAllPoints()
    if charGuildShareLabel:IsShown() then
        bankAltRow:SetPoint("TOPLEFT", charGuildShareDropdown.button, "BOTTOMLEFT", 0, -12)
    else
        bankAltRow:SetPoint("TOPLEFT", charSettingHeader, "BOTTOMLEFT", 0, -12)
    end
    bankAltRow:SetPoint("RIGHT", tabCharacters, "RIGHT", -16, 0)
end

-- Delete button shown whenever any character is selected;
-- disabled with "Can't delete self" when the current character is selected.
local charSettingDeleteBtn = CreateFrame("Button", nil, tabCharacters, "UIPanelButtonTemplate")
charSettingDeleteBtn:SetSize(160, 22)
charSettingDeleteBtn:SetPoint("BOTTOMLEFT", charListFrame, "BOTTOMRIGHT", COL_GAP, 0)
charSettingDeleteBtn:SetText("Delete Data")
charSettingDeleteBtn:Hide()
Theme.SkinDangerButton(charSettingDeleteBtn)

charSettingDeleteBtn:SetScript("OnClick", function(self)
    if deleteConfirmPending then
        -- Second click: commit delete
        deleteConfirmPending = false
        if AltArmy.DataStore and AltArmy.DataStore.DeleteCharacter and selectedEntry then
            AltArmy.DataStore:DeleteCharacter(selectedEntry.name, selectedEntry.realm)
        end
        selectedEntry = nil
        RefreshCharacterList()
        UpdateCharSettings()
    else
        -- First click: enter confirm mode
        deleteConfirmPending = true
        self:SetText("Really Delete?")
    end
end)

UpdateCharSettings = function()
    local hasSelection = selectedEntry ~= nil
    local isSelf = hasSelection
        and IsCurrentCharacter(selectedEntry.name, selectedEntry.realm)
    local showGuildShare = hasSelection and isGuildShareOptionsEnabled()
    charSettingPrompt:SetShown(not hasSelection)
    setCharSettingHeader(selectedEntry)
    charGuildShareLabel:SetShown(showGuildShare)
    if charGuildShareDropdown and charGuildShareDropdown.button then
        charGuildShareDropdown.button:SetShown(showGuildShare)
    end
    if showGuildShare then
        RefreshCharGuildShareDropdown()
    end
    layoutCharSettingRows()
    bankAltRow:SetShown(hasSelection)
    charSettingDeleteBtn:SetShown(hasSelection)
    -- Reset confirm state whenever the selection changes
    deleteConfirmPending = false
    if hasSelection then
        local BA = AltArmy.BankAlt
        if bankAltCheck and BA and BA.Is then
            bankAltCheck:SetChecked(BA.Is(selectedEntry.name, selectedEntry.realm))
        end
    elseif bankAltCheck then
        bankAltCheck:SetChecked(false)
    end
    if isSelf then
        charSettingDeleteBtn:SetText("Can't delete self")
        charSettingDeleteBtn:Disable()
    else
        charSettingDeleteBtn:SetText("Delete Data")
        charSettingDeleteBtn:Enable()
    end
end

SetActiveOptionsTab("general")

-- ---------------------------------------------------------------------------
-- Panel show/hide hooks
-- ---------------------------------------------------------------------------

-- Apply General / Characters / Cooldowns after Interface Options has actually shown our panel
-- (OpenToCategory often does not re-fire OnShow; IsShown() may be false until a later frame).
local tabApplyFrame = CreateFrame("Frame", nil, panel)
tabApplyFrame:Hide()

local pendingOptionsFocus = nil

local function optionsHostIsOpen()
    local iof = _G.InterfaceOptionsFrame
    if not iof or not iof.IsShown then
        return true
    end
    return iof:IsShown()
end

local function applyOptionsFocus(focus)
    if not focus then return end
    local tabId = focus.tab or "general"
    if tabId == "debug" and AltArmy.Debug and not AltArmy.Debug.IsEnabled() then
        tabId = "general"
    end
    SetActiveOptionsTab(tabId)
    if tabId == "cooldowns" and panel.RefreshCooldownOptionsFromVars then
        panel.RefreshCooldownOptionsFromVars()
    end
    if tabId == "gearUpgrades" then
        if AltArmy.BuildGearUpgradeOptionsUI then
            AltArmy.BuildGearUpgradeOptionsUI(panel)
        end
        if panel.RefreshGearUpgradeOptionsFromVars then
            panel.RefreshGearUpgradeOptionsFromVars()
        end
    end
    if tabId == "debug" and panel.RefreshDebugCheckboxes then
        panel.RefreshDebugCheckboxes()
    end
    if focus.name and focus.realm then
        SelectCharacterEntry(focus.name, focus.realm, focus.classFile)
        UpdateCharSettings()
        RefreshCharacterList()
    end
    if focus.flash == "bankAlt" and Theme.FlashAttentionHighlight and bankAltRow then
        Theme.FlashAttentionHighlight(bankAltRow)
    elseif focus.flash then
        -- General tab controls sit in collapsible sections: open the right one first.
        FocusGeneralControl(focus.flash)
    end
end

local function scheduleApplyOptionsFocus(focus)
    if not focus then return end
    pendingOptionsFocus = focus
    tabApplyFrame:SetScript("OnUpdate", nil)
    tabApplyFrame:Hide()
    tabApplyFrame.attempts = 0
    tabApplyFrame:Show()
    tabApplyFrame:SetScript("OnUpdate", function(self)
        self.attempts = self.attempts + 1
        if panel:IsShown() and optionsHostIsOpen() then
            local toApply = pendingOptionsFocus
            pendingOptionsFocus = nil
            applyOptionsFocus(toApply)
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        if self.attempts > 300 then
            pendingOptionsFocus = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

panel:SetScript("OnHide", function()
    selectedEntry        = nil
    deleteConfirmPending = false
    pendingOptionsFocus  = nil
    tabApplyFrame:SetScript("OnUpdate", nil)
    tabApplyFrame:Hide()
    UpdateCharSettings()
end)

panel:HookScript("OnShow", function()
    RefreshCharacterList()
    UpdateCharSettings()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(minimapShown())
    end
    if panel.RefreshRealmFilterDropdown then
        panel.RefreshRealmFilterDropdown()
    end
    if panel.RefreshGuildSharingControls then
        panel.RefreshGuildSharingControls()
    end
    if panel.RefreshAuctionOptions then
        panel.RefreshAuctionOptions()
    end
    if panel.RefreshAdvancedOptions then
        panel.RefreshAdvancedOptions()
    end
end)

-- ---------------------------------------------------------------------------
-- Register with WoW's options system on login
-- ---------------------------------------------------------------------------

local function registerOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AltArmy")
        Settings.RegisterAddOnCategory(category)
        panel.altArmySettingsCategory = category
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        if InterfaceAddOnsList_Update then
            InterfaceAddOnsList_Update()
        end
    end
end

local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        reg:UnregisterEvent("PLAYER_LOGIN")
        registerOptionsPanel()
        RefreshCharacterList()
        UpdateCharSettings()
        if panel.minimapCheckbox then
            panel.minimapCheckbox:SetChecked(minimapShown())
        end
        if panel.RefreshRealmFilterDropdown then
            panel.RefreshRealmFilterDropdown()
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        if panel.RefreshDebugCheckboxes then
            panel.RefreshDebugCheckboxes()
        end
        if panel.RefreshGuildSharingControls then
            panel.RefreshGuildSharingControls()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command: open the main AltArmy UI
-- ---------------------------------------------------------------------------

SLASH_ALTARMY1, SLASH_ALTARMY2 = "/altarmy", "/alta"
SlashCmdList.ALTARMY = function(msg)
    local trimmed = (msg or ""):match("^%s*(.-)%s*$") or ""
    local lower = trimmed:lower()
    if lower == "export" then
        if AltArmy.ProfitExportDialog then
            AltArmy.ProfitExportDialog.Show()
        end
        return
    end
    if lower == "resetsize" and AltArmy.Debug and AltArmy.Debug.IsWindowResizeEnabled
        and AltArmy.Debug.IsWindowResizeEnabled() then
        if AltArmy.ResetWindowSize then
            AltArmy.ResetWindowSize()
        end
        return
    end
    if lower == "scan" then
        local scan = AltArmy.AuctionScan
        local ok, reason = false, "missing"
        if scan and scan.Start then
            ok, reason = scan.Start()
        end
        local said = {
            missing = "This client has no auction house scan.",
            closed = "Open the auction house first.",
            busy = "A scan is already running.",
            error = "The game refused the scan. Try again in a moment.",
        }
        local text = not ok and said[reason] or nil -- a scan that starts says so itself
        if reason == "cooldown" then
            local left = scan.CooldownLeft()
            if left > 0 then
                text = string.format("The game allows the next full scan in %d:%02d.", math.floor(left / 60),
                    left % 60)
            else
                text = "This client can't run the kind of scan set in Options (Auction House)."
            end
        end
        if text and AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("|cff00ccff[Alt Army]|r " .. text)
        end
        return
    end
    if lower == "taint" then
        local report = AltArmy.Debug and AltArmy.Debug.DumpTaint and AltArmy.Debug.DumpTaint()
        local dlg = AltArmy.ProfitExportDialog
        if report and dlg and dlg.ShowText then
            dlg.ShowText("Taint report", "Ctrl+C copies this report; paste it to whoever is debugging.", report)
        elseif not report and AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("|cff00ccff[Alt Army]|r This client cannot report taint.")
        end
        return
    end
    if lower == "debug on" then
        if AltArmy.Debug and AltArmy.Debug.SetEnabled then
            AltArmy.Debug.SetEnabled(true)
            if AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Debug options enabled")
            end
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.RefreshGrid then
            gearFrame:RefreshGrid()
        end
        return
    end
    if lower == "debug off" then
        if AltArmy.Debug and AltArmy.Debug.SetEnabled then
            AltArmy.Debug.SetEnabled(false)
            if AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Debug options disabled")
            end
        end
        if panel.RefreshDebugTabVisibility then
            panel.RefreshDebugTabVisibility()
        end
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.RefreshGrid then
            gearFrame:RefreshGrid()
        end
        return
    end
    if lower == "debug resize on" or lower == "debug resize off" then
        local on = lower == "debug resize on"
        if AltArmy.Debug and AltArmy.Debug.SetWindowResizeEnabled then
            AltArmy.Debug.SetWindowResizeEnabled(on)
            if AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat(on and "Window resize enabled" or "Window resize disabled")
            end
        end
        if panel.RefreshDebugCheckboxes then
            panel.RefreshDebugCheckboxes()
        end
        return
    end
    if lower == "debug remigrate recipes" then
        local DS = AltArmy and AltArmy.DataStore
        if not DS or not DS.RemigrateRecipePrimaryIdsDebug then
            if AltArmy.Debug and AltArmy.Debug.NotifyChat then
                AltArmy.Debug.NotifyChat("Recipe migration is unavailable.")
            end
            return
        end
        local updated = DS:RemigrateRecipePrimaryIdsDebug()
        if AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat(string.format(
                "Recipe primaryRecipeID migration re-ran (%d profession recipe group(s) updated).",
                updated
            ))
        end
        return
    end
    local debugMailName = trimmed:match("^[Dd]ebug [Mm]ail%s+(.+)$")
    if debugMailName then
        local MA = AltArmy and AltArmy.MailAlerts
        if MA and MA.DebugAnnounceForCharacter then
            MA.DebugAnnounceForCharacter(debugMailName)
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Mail alerts are unavailable.")
        end
        return
    end
    if lower == "debug mail" then
        local MA = AltArmy and AltArmy.MailAlerts
        if MA and MA.DebugAnnounceForCharacter then
            MA.DebugAnnounceForCharacter("")
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Mail alerts are unavailable.")
        end
        return
    end
    local debugLevelUp = trimmed:match("^[Dd]ebug [Ll]evelup%s+(%d+)$")
    if debugLevelUp then
        local GA = AltArmy and AltArmy.GearUpgradeAlerts
        if GA and GA.SimulateLevelUp then
            GA.SimulateLevelUp(tonumber(debugLevelUp))
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Gear upgrade alerts are unavailable.")
        end
        return
    end
    local debugItemLink = trimmed:match("^[Dd]ebug [Ii]tem%s+(.+)$")
    if debugItemLink then
        local GA = AltArmy and AltArmy.GearUpgradeAlerts
        if GA and GA.SimulateSelfLoot then
            GA.SimulateSelfLoot(debugItemLink)
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Gear upgrade alerts are unavailable.")
        end
        return
    end
    if lower == "debug bankdetect" then
        local dialog = AltArmy and AltArmy.BankAltSuggestDialog
        if dialog and dialog.ShowDebug then
            if not dialog.ShowDebug() then
                local D = AltArmy and AltArmy.Debug
                if D and D.NotifyChat then
                    D.NotifyChat("Bank alt detection dialog is unavailable.")
                end
            end
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Bank alt detection dialog is unavailable.")
        end
        return
    end
    if lower == "debug rxpquestconflict" then
        local dialog = AltArmy and AltArmy.RestedXpQuestRewardConflictDialog
        if dialog and dialog.ShowDebug then
            if not dialog.ShowDebug() then
                local D = AltArmy and AltArmy.Debug
                if D and D.NotifyChat then
                    D.NotifyChat("RestedXP quest reward conflict dialog is unavailable.")
                end
            end
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("RestedXP quest reward conflict dialog is unavailable.")
        end
        return
    end
    if lower == "debug dump" or lower == "debug dumpcompare" then
        local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if gearFrame and gearFrame.DumpComparePanelDebug then
            gearFrame:DumpComparePanelDebug()
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Open the Gear tab with a focused item and compare selection.")
        end
        return
    end
    if lower == "debug layout" then
        local optionsPanel = AltArmy.OptionsPanel
        if optionsPanel and optionsPanel.DumpGeneralLayout then
            optionsPanel.DumpGeneralLayout()
        end
        return
    end
    if lower == "debug apicheck" then
        local AC = AltArmy and AltArmy.ApiCheck
        if AC and AC.RunAndReport then
            AC.RunAndReport()
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("API check is unavailable.")
        end
        return
    end
    if lower == "debug ahprobe" then
        local probe = AltArmy and AltArmy.AuctionProbe
        if probe and probe.Start then
            probe.Start()
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("The auction house probe is unavailable.")
        end
        return
    end
    local debugStatsLink = trimmed:match("^[Dd]ebug [Ss]tats%s+(.+)$")
    if not debugStatsLink and lower == "debug stats" then
        if GetCursorInfo then
            local infoType, _, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                debugStatsLink = itemLink
            end
        end
    end
    if debugStatsLink or lower == "debug stats" then
        local IS = AltArmy and AltArmy.ItemStats
        local D = AltArmy and AltArmy.Debug
        if not IS or not IS.LogStatParseDebug then
            if D and D.NotifyChat then
                D.NotifyChat("Item stat parsing is unavailable.")
            end
            return
        end
        if not D or not D.IsItemStatsEnabled or not D.IsItemStatsEnabled() then
            if D and D.NotifyChat then
                D.NotifyChat("Enable Debug > Item stat parsing first (/altarmy debug on).")
            end
            return
        end
        if not debugStatsLink then
            if D and D.NotifyChat then
                D.NotifyChat("Put an item on the cursor or pass an item link: /altarmy debug stats <link>")
            end
            return
        end
        IS.LogStatParseDebug(debugStatsLink, { forceRefresh = true })
        return
    end
    if lower == "debug guildshare onboard" or lower == "debug guildshare onboarding" then
        local GSO = AltArmy and AltArmy.GuildShareOnboarding
        local D = AltArmy and AltArmy.Debug
        if GSO and GSO.ShowDebug then
            if not GSO.ShowDebug() then
                if D and D.NotifyChat then
                    D.NotifyChat("Guild share onboarding dialog is unavailable.")
                end
            end
        elseif D and D.NotifyChat then
            D.NotifyChat("Guild share onboarding dialog is unavailable.")
        end
        return
    end
    if lower == "debug guildshare test" then
        local Comm = AltArmy and AltArmy.GuildShareComm
        local D = AltArmy and AltArmy.Debug
        if not Comm or not Comm.InjectTestPresence then
            if D and D.NotifyChat then D.NotifyChat("Guild sharing is unavailable.") end
            return
        end
        local ok, reason = Comm.InjectTestPresence()
        if D and D.NotifyChat then
            if ok then
                D.NotifyChat("Injected synthetic guildmates. Recipes show in Search (with a (guild) tag);"
                    .. " the Guild tab lists them when you are in a guild with sharing enabled.")
            else
                D.NotifyChat("Test injection failed (" .. tostring(reason) .. ").")
            end
        end
        return
    end
    if lower == "networth" or lower:match("^networth%s+") then
        local NW = AltArmy and AltArmy.NetWorth
        local scaleArg = lower:match("^networth%s+(.+)$")
        if NW and NW.PrintSummaryFromArg then
            NW.PrintSummaryFromArg(scaleArg)
        elseif AltArmy.Debug and AltArmy.Debug.NotifyChat then
            AltArmy.Debug.NotifyChat("Net worth is unavailable.")
        end
        return
    end
    do
        local sendAllN = trimmed:match("^[Ss]endall%s+(%d+)$")
        local sendAllBare = lower == "sendall"
        if sendAllN or sendAllBare then
            local n = sendAllN and tonumber(sendAllN) or nil
            if not n or n < 1 then
                if AltArmy.Debug and AltArmy.Debug.NotifyChat then
                    AltArmy.Debug.NotifyChat("Usage: /alta sendall <n>")
                else
                    local chat = _G.DEFAULT_CHAT_FRAME
                    if chat and chat.AddMessage then
                        chat:AddMessage("|cfffecc00Alt Army|r Usage: /alta sendall <n>")
                    end
                end
                return
            end
            if AltArmy.ShowMainTab then
                AltArmy.ShowMainTab("Cooldowns")
            elseif AltArmy.MainFrame then
                AltArmy.MainFrame:Show()
            end
            local cdFrame = AltArmy.TabFrames and AltArmy.TabFrames.Cooldowns
            if cdFrame and cdFrame.SetCooldownsView then
                cdFrame.SetCooldownsView("crafting")
            end
            if cdFrame and cdFrame.StartSendAllStockpile then
                cdFrame:StartSendAllStockpile(n)
            else
                if AltArmy.Debug and AltArmy.Debug.NotifyChat then
                    AltArmy.Debug.NotifyChat("Send-all stockpile is unavailable.")
                end
            end
            return
        end
    end
    -- `/alta economy crates`: a tab, and maybe one of its views (UI/MainTabs.lua); one not there does nothing.
    local MainTabs = AltArmy.MainTabs
    local tabName, viewName, valid
    if MainTabs and MainTabs.ParseSlash then
        tabName, viewName, valid = MainTabs.ParseSlash(trimmed)
    end
    if tabName then
        if valid and AltArmy.OpenMainTabView then
            AltArmy.OpenMainTabView(tabName, viewName)
        end
        return
    end
    if AltArmy and AltArmy.MainFrame then
        AltArmy.MainFrame:Show()
    end
end

AltArmy.OptionsPanel = panel

--- @param initialTab string|nil "general" (default), "characters", "cooldowns", or "debug"
--- @param opts table|nil { name, realm, flash = "main"|"bankAlt"|"guildShare"|"autoDelete"|"autoScan"|"scanMode" }
--- A flashed General tab control's section is opened first (Guild: main, guildShare, autoDelete;
--- Auction House: autoScan, scanMode).
function AltArmy.OpenInterfaceOptions(initialTab, opts)
    opts = opts or {}
    local tab = initialTab or "general"
    if tab == "debug" and not (AltArmy.Debug and AltArmy.Debug.IsEnabled()) then
        tab = "general"
    end
    local focus = {
        tab = tab,
        name = opts.name,
        realm = opts.realm,
        flash = opts.flash,
    }
    if Settings and Settings.OpenToCategory and panel.altArmySettingsCategory then
        Settings.OpenToCategory(panel.altArmySettingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
    if panel:IsShown() and optionsHostIsOpen() then
        applyOptionsFocus(focus)
    else
        scheduleApplyOptionsFocus(focus)
    end
end
