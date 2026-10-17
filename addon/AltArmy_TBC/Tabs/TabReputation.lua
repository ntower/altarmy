-- AltArmy TBC — Reputation tab: factions (rows) × characters (columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Reputation
if not frame then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local RepSort = AltArmy.ReputationFactionSort
local RGW = AltArmy.ReputationGridWindow
local SSR = AltArmy.ScoreSortRow
local SD = AltArmy.SummaryData
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local ZI = AltArmy.ZygorIntegration
local PAD = 4
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local FACTION_LABEL_WIDTH = 120
local REP_ROW_HEIGHT = 47
local REP_BAR_HEIGHT = 20
local REP_STANDING_ROW_HEIGHT = 14
local REP_STANDING_BAR_GAP = 1
local REP_CELL_CONTENT_SHIFT_DOWN = 5
-- Vertically center standing + gap + bar in the cell (matches faction label centered in the row).
local REP_CELL_CONTENT_TOP_PAD = (REP_ROW_HEIGHT - REP_STANDING_ROW_HEIGHT - REP_STANDING_BAR_GAP - REP_BAR_HEIGHT) / 2
local MISSING_DATA_TEXT_R, MISSING_DATA_TEXT_G, MISSING_DATA_TEXT_B = 0.78, 0.68, 0.4
-- Match TabGear header: name row + message row (Reputation uses only one text line, centered in full height)
local MESSAGE_ROW_HEIGHT = 14
local COLUMN_HEADER_HEIGHT_GEAR = 20
local COLUMN_HEADER_NAME_Y_OFFSET = 1
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT
-- Sorting row (provider selector + per-column value), mirrors the Gear tab's score row.
local SCORE_ROW_HEIGHT = 20         -- extra header height for the sorting row (Gear: GetScoreRowHeight)
local SCORE_ROW_CONTENT_HEIGHT = 24 -- control/value height (Gear: GetScoreRowContentHeight)
local SCORE_ROW_BOTTOM_INSET = 6    -- (Gear: SCORE_ROW_HEADER_BOTTOM_INSET)
local ZYGOR_BTN_SIZE = 16
local ZYGOR_BTN_GAP = 4
local function GetHeaderHeight()
    return FIXED_HEADER_ROW_HEIGHT + SCORE_ROW_HEIGHT
end
local COLUMN_WIDTH = 75
local REP_BAR_FULL_WIDTH = COLUMN_WIDTH - 12
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20
local MIN_SCROLL_CHILD_WIDTH = 400
local GRID_SPLIT_FRACTION = 0.6

local function GetReputationSettings()
    AltArmyTBC_ReputationSettings = AltArmyTBC_ReputationSettings or {}
    local s = AltArmyTBC_ReputationSettings
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    if s.scoreSortDescending == nil then s.scoreSortDescending = true end
    s.scoreProvider = SSR.ValidateProvider(s.scoreProvider or SSR.DEFAULT_PROVIDER)
    s.characters = s.characters or {}
    return s
end

local CharKey = AltArmy.CharKey

local function GetCharSetting(name, realm, key)
    local s = GetReputationSettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

local function SetCharSetting(name, realm, pin, hide)
    local s = GetReputationSettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

-- Session-only: sort columns by reputation with this faction.
-- Clicking the active row toggles high-first <-> low-first; clicking another row switches to it.
local factionSortFactionID = nil
local factionSortHighFirst = true

-- Toggle the faction-rep column sort: same faction flips direction (no reset); a new faction
-- switches to it (high first). Used by both the faction row text and its sort button.
local function ToggleFactionSort(fid)
    if not fid then return end
    if factionSortFactionID == fid then
        factionSortHighFirst = not factionSortHighFirst
    else
        factionSortFactionID = fid
        factionSortHighFirst = true
    end
    if frame.RefreshGrid then
        frame:RefreshGrid()
    end
end

-- Session-only: sort faction rows by this character's rep (column header click).
-- Same column: high first -> low first -> off; other column: switch (high first).
local columnSortName = nil
local columnSortRealm = nil
local columnSortHighFirst = true

local lastFactionRows = {}

local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GetReputationSettings()
    local currentRealm = DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""
    local showSelfFirst = settings.showSelfFirst ~= false

    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        local isSelf = DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local BA = AltArmy.BankAlt
        local isBankAlt = BA and BA.Is and BA.Is(e.name, e.realm)
        local isHidden = GetCharSetting(e.name, e.realm, "hide") or isBankAlt
        if not isHidden or (showSelfFirst and isSelf) then
            visible[#visible + 1] = e
            SSR.DecorateEntry(e)
        end
    end

    local providerId = settings.scoreProvider or SSR.DEFAULT_PROVIDER
    local descending = settings.scoreSortDescending ~= false

    local function scoreCompare(a, b)
        return SSR.Compare(a, b, providerId, descending)
    end

    local function sortPair(a, b)
        if factionSortFactionID then
            return RepSort.CompareByFactionRep(DS, a, b, factionSortFactionID, factionSortHighFirst, scoreCompare)
        end
        return scoreCompare(a, b)
    end

    -- Always group pinned characters first, then non-pinned, each in the active sort order.
    -- This holds for every sort mode, including the faction-rep column sort.
    local function isPinnedEntry(e)
        return GetCharSetting(e.name, e.realm, "pin")
    end
    local function isSelfEntry(e)
        return DS and DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
    end
    local list = RepSort.BuildSortedDisplayList(visible, isPinnedEntry, isSelfEntry, showSelfFirst, sortPair)

    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.FilterList then
        list = GRF.FilterList(list, currentRealm)
    end
    return list
end

local function OnReputationHeaderColumnClick(self, button)
    if button ~= "LeftButton" then return end
    local idx = self.reputationHeaderColumnIndex
    if not idx then return end
    local list = GetDisplayList()
    local e = list[idx]
    if not e then return end
    local sn = e.name or ""
    local sr = e.realm or ""
    if columnSortName == sn and columnSortRealm == sr then
        if columnSortHighFirst then
            columnSortHighFirst = false
        else
            columnSortName = nil
            columnSortRealm = nil
        end
    else
        columnSortName = sn
        columnSortRealm = sr
        columnSortHighFirst = true
    end
    if frame and frame.RefreshGrid then frame:RefreshGrid() end
end

local factionFilterEdit

local function FilterReputationFactionRows(rows, filterText)
    local f = AltArmy.ReputationFactionFilter
    if f and f.filterRows then
        return f.filterRows(rows, filterText)
    end
    return rows
end

local function GetDisplayFactionRows()
    local filterText = factionFilterEdit and factionFilterEdit:GetText() or ""
    local base = FilterReputationFactionRows(lastFactionRows, filterText)
    if not base or #base == 0 or not columnSortName then return base end
    local sorted = {}
    for i = 1, #base do
        sorted[i] = base[i]
    end
    local entry = { name = columnSortName, realm = columnSortRealm or "" }
    table.sort(sorted, function(ra, rb)
        return RepSort.CompareFactionRowsForCharacter(DS, entry, ra, rb, columnSortHighFirst)
    end)
    return sorted
end

local dims = {
    rowHeight = REP_ROW_HEIGHT,
    columnWidth = COLUMN_WIDTH,
    scrollableGridHeight = REP_ROW_HEIGHT + PAD,
}

-- Faction name column offsets each row by (rowHeight - label line height) / 2; grid first row must match.
local REP_FACTION_LABEL_TEXT_HEIGHT = 14
local REP_FACTION_LABEL_HOVER_HEIGHT = REP_FACTION_LABEL_TEXT_HEIGHT + 8
local REP_FIRST_ROW_HEADER_GAP_TRIM = 12
-- Match the score row's sort button size/appearance.
local FACTION_SORT_BTN_SIZE = SCORE_ROW_CONTENT_HEIGHT
local function GetFirstRowLabelVerticalOffset()
    local centered = (dims.rowHeight - REP_FACTION_LABEL_TEXT_HEIGHT) / 2
    return math.max(0, centered - REP_FIRST_ROW_HEADER_GAP_TRIM)
end
-- Grid first row uses a tighter frame anchor than the label row; trim is applied via cell content padding.
local REP_FIRST_ROW_CELL_Y = -2

local tabContentPanel = Theme.CreateMainContentPanel(frame)
tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)
tabContentInner:SetClipsChildren(true)

local rightPanel = CreateFrame("Frame", nil, tabContentInner)
rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)

local contentArea = CreateFrame("Frame", nil, rightPanel)
contentArea:SetClipsChildren(true)
local function LayoutContentArea(horizontalScrollBar)
    contentArea:ClearAllPoints()
    contentArea:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -PAD)
    contentArea:SetPoint("TOPRIGHT", tabContentPanel, "TOPRIGHT", -SCROLL_GUTTER, 0)
    contentArea:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER,
        HORIZONTAL_SCROLL_BAR_HEIGHT)
    if horizontalScrollBar then
        horizontalScrollBar:ClearAllPoints()
        horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", 0, -4)
        horizontalScrollBar:SetPoint("BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, -4)
        horizontalScrollBar:SetFrameLevel(tabContentPanel:GetFrameLevel() + 30)
        horizontalScrollBar:EnableMouse(true)
    end
end
LayoutContentArea(nil)

local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(GetHeaderHeight() + dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

local scrollTopSpacer = CreateFrame("Frame", nil, verticalScrollChild)
scrollTopSpacer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
scrollTopSpacer:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
scrollTopSpacer:SetHeight(GetHeaderHeight())

local fixedHeaderRow = CreateFrame("Frame", nil, contentArea)
fixedHeaderRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(GetHeaderHeight())
fixedHeaderRow:SetFrameLevel(contentArea:GetFrameLevel() + 20)
local HEADER_BG_OVERHANG = 6
local HEADER_BG_BOTTOM_INSET = 6
local headerBg = fixedHeaderRow:CreateTexture(nil, "BACKGROUND")
headerBg:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, HEADER_BG_OVERHANG)
headerBg:SetPoint("TOPRIGHT", fixedHeaderRow, "TOPRIGHT", 0, HEADER_BG_OVERHANG)
Theme.StyleGridHeader(headerBg)
fixedHeaderRow:EnableMouse(true)

-- Grid corner: score-sort controls (the faction filter moved to the toolbar row).
local headerCornerFrame = CreateFrame("Frame", nil, fixedHeaderRow)
headerCornerFrame:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, 0)
headerCornerFrame:SetSize(FACTION_LABEL_WIDTH, GetHeaderHeight())
Theme.ApplyGridLabelColumnBackground(headerCornerFrame)

-- Lives in the main toolbar row (where Summary's item search sits), not in the grid corner.
-- Same search box as Summary's item search (native SearchBoxTemplate: magnifier, clear button).
factionFilterEdit = Theme.CreateSearchBox(frame, {
    name = "AltArmyTBC_ReputationFactionFilterEdit",
    placeholder = "Filter faction",
})
if AltArmy.PlaceInToolbarSearchSlot then
    AltArmy.PlaceInToolbarSearchSlot(factionFilterEdit, frame)
end

-- HookScript keeps SearchBoxTemplate's own handlers (clear button, Instructions placeholder).
factionFilterEdit:HookScript("OnTextChanged", function(box)
    Theme.UpdateEditBoxPlaceholderVisibility(box)
    if frame.RefreshGrid then
        frame:RefreshGrid()
    end
end)
factionFilterEdit:HookScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)
factionFilterEdit:HookScript("OnEscapePressed", function(box)
    Theme.ClearEditBoxText(box)
end)

-- Sorting row controls (provider selector + sort-direction) in the bottom band of the corner.
local scoreSortControls = SSR.CreateCornerControls(headerCornerFrame, {
    btnSize = SCORE_ROW_CONTENT_HEIGHT,
    bottomInset = SCORE_ROW_BOTTOM_INSET,
    dropdownParent = fixedHeaderRow,
    dropdownWidth = 200,
    getProviderId = function() return GetReputationSettings().scoreProvider end,
    setProviderId = function(id) GetReputationSettings().scoreProvider = id end,
    getDescending = function() return GetReputationSettings().scoreSortDescending ~= false end,
    setDescending = function(v) GetReputationSettings().scoreSortDescending = v end,
    -- Hide the direction button while a faction-rep sort is overriding the score sort.
    isDirectionShown = function() return factionSortFactionID == nil end,
    -- Clicking the score selector cancels the faction sort and returns to score sorting.
    -- Re-activating always starts descending (don't reuse or toggle the previous direction).
    -- Returning true consumes that first click so the dropdown menu does not also open.
    onProviderActivate = function()
        if factionSortFactionID ~= nil then
            factionSortFactionID = nil
            GetReputationSettings().scoreSortDescending = true
            if frame.RefreshGrid then frame:RefreshGrid() end
            return true
        end
        return false
    end,
    onChange = function()
        if frame.RefreshGrid then frame:RefreshGrid() end
    end,
})

local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerFrame, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(GetHeaderHeight())
headerHorizontalScroll:SetScrollChild(headerGridContainer)

-- Parent to the unclipped outer panel: tabContentInner clips, and the gutter extends past its padded edge.
local scrollTopFade
local verticalScrollBinding = Theme.CreateVerticalScrollBinding(verticalScroll, {
    parent = tabContentPanel,
    name = "AltArmyTBC_ReputationVerticalScrollBar",
    step = dims.rowHeight * 2,
    onScroll = function()
        if scrollTopFade then scrollTopFade:Update() end
    end,
})
local verticalScrollBar = verticalScrollBinding.bar
verticalScrollBar:SetFrameLevel(tabContentPanel:GetFrameLevel() + 30)
Theme.AnchorVerticalScrollBar(verticalScrollBar, tabContentPanel, contentArea, { gap = 0 })

scrollTopFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = fixedHeaderRow,
    scrollFrame = verticalScroll,
    scrollBar = verticalScrollBar,
})

verticalScrollChild:SetScript("OnMouseWheel", function(_, delta)
    verticalScrollBinding.Wheel(delta)
end)

local factionHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
factionHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -GetHeaderHeight())
factionHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
factionHeaderContainer:SetWidth(FACTION_LABEL_WIDTH)
Theme.ApplyGridLabelColumnBackground(factionHeaderContainer)

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", FACTION_LABEL_WIDTH, -GetHeaderHeight())
horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
horizontalScroll:EnableMouse(true)

local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

-- Header column pool: same layout as TabGear (name row + message row; Reputation leaves message empty)
local headerColumnPool = {}
local function GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Button", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, GetHeaderHeight())
        Theme.BindInteractableHover(col, {
            bandHeight = COLUMN_HEADER_HEIGHT_GEAR,
            onEnter = function(self)
                if self.tooltipText and self.tooltipText ~= "" and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                    GameTooltip:Show()
                end
            end,
            onLeave = function()
                if GameTooltip then GameTooltip:Hide() end
            end,
        })
        if col.RegisterForClicks then
            col:RegisterForClicks("LeftButtonUp")
        end
        col.header = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, COLUMN_HEADER_NAME_Y_OFFSET)
        col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, COLUMN_HEADER_NAME_Y_OFFSET)
        col.header:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
        col.header:SetJustifyH("CENTER")
        col.header:SetJustifyV("MIDDLE")
        col.header:SetWordWrap(false)
        col.message = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetPoint("LEFT", col, "LEFT", 0, 0)
        col.message:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.message:SetHeight(MESSAGE_ROW_HEIGHT)
        col.message:SetJustifyH("CENTER")
        col.message:SetWordWrap(true)
        col.message:SetNonSpaceWrap(true)
        -- Sorting row: per-column value for the selected sort metric (bottom band).
        col.scoreText = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        col.scoreText:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_BOTTOM_INSET)
        col.scoreText:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_BOTTOM_INSET)
        col.scoreText:SetHeight(SCORE_ROW_CONTENT_HEIGHT)
        col.scoreText:SetJustifyH("CENTER")
        col.scoreText:SetJustifyV("MIDDLE")
        col.scoreHover = CreateFrame("Frame", nil, col)
        col.scoreHover:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, SCORE_ROW_BOTTOM_INSET)
        col.scoreHover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, SCORE_ROW_BOTTOM_INSET)
        col.scoreHover:SetHeight(SCORE_ROW_CONTENT_HEIGHT)
        col.scoreHover:EnableMouse(false)
        col.scoreHover:SetScript("OnEnter", function(self)
            local e = self.scoreMissingEntry
            if e and SD and SD.PresentMissingDataTooltip then
                SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile)
            end
        end)
        col.scoreHover:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnMouseUp", OnReputationHeaderColumnClick)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

local function RepCellContentTopPad()
    local base = math.floor(REP_CELL_CONTENT_TOP_PAD + 0.5) + REP_CELL_CONTENT_SHIFT_DOWN
    return math.max(0, base - REP_FIRST_ROW_HEADER_GAP_TRIM)
end

local function ApplyRepCellContentLayout(cell)
    local topPad = RepCellContentTopPad()
    cell.standing:ClearAllPoints()
    cell.standing:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -topPad)
    cell.standing:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -topPad)
end

local function CreateRepCell(col, rowH, colW)
    local cell = CreateFrame("Frame", nil, col)
    local innerW = colW - 8
    cell:SetSize(innerW, rowH)
    cell.standing = cell:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    ApplyRepCellContentLayout(cell)
    cell.standing:SetHeight(REP_STANDING_ROW_HEIGHT)
    cell.standing:SetJustifyH("CENTER")
    cell.standing:SetWordWrap(false)
    cell.barBg = cell:CreateTexture(nil, "BACKGROUND")
    cell.barBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    cell.barBg:SetPoint("TOPLEFT", cell.standing, "BOTTOMLEFT", 0, -REP_STANDING_BAR_GAP)
    cell.barBg:SetPoint("TOPRIGHT", cell.standing, "BOTTOMRIGHT", 0, -REP_STANDING_BAR_GAP)
    cell.barBg:SetHeight(REP_BAR_HEIGHT)
    cell.barFill = cell:CreateTexture(nil, "ARTWORK")
    cell.barFill:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    cell.barFill:SetPoint("BOTTOMLEFT", cell.barBg, "BOTTOMLEFT", 0, 0)
    cell.barFill:SetHeight(REP_BAR_HEIGHT)
    -- Progress numbers sit on top of the bar (same band as the fill).
    cell.progress = cell:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    cell.progress:SetPoint("TOPLEFT", cell.barBg, "TOPLEFT", 2, 0)
    cell.progress:SetPoint("BOTTOMRIGHT", cell.barBg, "BOTTOMRIGHT", -2, 0)
    cell.progress:SetJustifyH("CENTER")
    cell.progress:SetJustifyV("MIDDLE")
    cell.progress:SetWordWrap(false)
    cell:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local e = self.missingDataTooltipEntry
        if e and SD and SD.PresentMissingDataTooltip then
            if SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile) then
                return
            end
        end
        if not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1)
        if self.tooltipLines then
            for _, line in ipairs(self.tooltipLines) do
                if type(line) == "table" and line.text then
                    GameTooltip:AddLine(line.text, line.r or 0.9, line.g or 0.9, line.b or 0.9, line.wrap == true)
                else
                    GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
                end
            end
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return cell
end

local columnPool = {}
local function GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        col.cells = {}
        columnPool[index] = col
    end
    return columnPool[index]
end

local function EnsureCell(col, rowIndex)
    if not col.cells[rowIndex] then
        col.cells[rowIndex] = CreateRepCell(col, dims.rowHeight, dims.columnWidth)
    end
    return col.cells[rowIndex]
end

local ApplyColumnWindow
local repGridScrollDragging = false

local scrollGridLeftFade
local scrollHeaderLeftFade
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentPanel, {
    name = "AltArmyTBC_ReputationHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        local scrollVal = math.floor(value + 0.5)
        horizontalScroll:SetHorizontalScroll(scrollVal)
        if headerHorizontalScroll then
            headerHorizontalScroll:SetHorizontalScroll(scrollVal)
        end
        ApplyColumnWindow(false)
        if scrollGridLeftFade then scrollGridLeftFade:Update() end
        if scrollHeaderLeftFade then scrollHeaderLeftFade:Update() end
    end,
    onDragStart = function()
        repGridScrollDragging = true
    end,
    onDragEnd = function()
        repGridScrollDragging = false
        ApplyColumnWindow(true)
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar
LayoutContentArea(horizontalScrollBar)

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

local factionLabelPool = {}
local function GetFactionLabelRow(i)
    if not factionLabelPool[i] then
        local row = CreateFrame("Button", nil, factionHeaderContainer)
        Theme.BindInteractableHover(row, {
            bandHeight = REP_FACTION_LABEL_HOVER_HEIGHT,
            bandCenter = true,
            bandYOffset = 2,
            -- Full faction name when the label is truncated.
            onEnter = function(self)
                if self.truncated and self.factionName and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.factionName, 1, 1, 1)
                    GameTooltip:Show()
                end
            end,
            onLeave = function()
                if GameTooltip then GameTooltip:Hide() end
            end,
        })
        if row.RegisterForClicks then
            row:RegisterForClicks("LeftButtonUp")
        end
        row.text = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        row.text:SetPoint("LEFT", row, "LEFT", 0, 2)
        row.text:SetPoint("RIGHT", row, "RIGHT", 0, 2)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("MIDDLE")
        row.text:SetWordWrap(false)
        -- Sort direction button, shown only on the actively-sorted faction row.
        row.sortBtn = CreateFrame("Button", nil, row)
        row.sortBtn:SetSize(FACTION_SORT_BTN_SIZE, FACTION_SORT_BTN_SIZE)
        row.sortBtn:SetPoint("RIGHT", row, "RIGHT", -2, 2)
        Theme.SkinButton(row.sortBtn)
        row.sortBtn.text = row.sortBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        row.sortBtn.text:SetPoint("CENTER", row.sortBtn, "CENTER", 0, 0)
        row.sortBtn.text:SetTextColor(1, 0.82, 0, 1)
        row.sortBtn:Hide()
        if row.sortBtn.RegisterForClicks then
            row.sortBtn:RegisterForClicks("LeftButtonUp")
        end
        row.sortBtn:SetScript("OnClick", function(self)
            ToggleFactionSort(self:GetParent().factionID)
        end)
        -- Zygor guide icon: shown only when a loadable guide exists for this faction.
        -- Hit area is full row height; hover tint matches the faction-name band.
        row.zygorBtn = CreateFrame("Button", nil, row)
        row.zygorBtn:SetSize(ZYGOR_BTN_SIZE, REP_ROW_HEIGHT)
        row.zygorBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.zygorBtn.icon = row.zygorBtn:CreateTexture(nil, "ARTWORK")
        row.zygorBtn.icon:SetSize(ZYGOR_BTN_SIZE, ZYGOR_BTN_SIZE)
        row.zygorBtn.icon:SetPoint("CENTER", row.zygorBtn, "CENTER", 0, 2)
        row.zygorBtn:Hide()
        if row.zygorBtn.RegisterForClicks then
            row.zygorBtn:RegisterForClicks("LeftButtonUp")
        end
        row.zygorBtn:SetScript("OnClick", function(self)
            local parent = self:GetParent()
            if parent and parent.zygorGuideTitle and ZI and ZI.OpenGuide then
                ZI.OpenGuide(parent.zygorGuideTitle)
            end
        end)
        Theme.BindInteractableHover(row.zygorBtn, {
            bandHeight = REP_FACTION_LABEL_HOVER_HEIGHT,
            bandCenter = true,
            bandYOffset = 2,
            onEnter = function(self)
                if not GameTooltip then return end
                local parent = self:GetParent()
                local fname = (parent and parent.factionName) or "faction"
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Load Zygor guide: " .. fname, 1, 1, 1)
                GameTooltip:Show()
            end,
            onLeave = function()
                if GameTooltip then GameTooltip:Hide() end
            end,
        })
        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            -- Child Zygor button owns its click; don't also toggle faction sort.
            if self.zygorBtn and self.zygorBtn:IsShown() and self.zygorBtn.IsMouseOver
                and self.zygorBtn:IsMouseOver() then
                return
            end
            ToggleFactionSort(self.factionID)
        end)
        factionLabelPool[i] = row
    end
    return factionLabelPool[i]
end

local function StandingDisplayText(standing)
    if not standing or standing == "" then return "—" end
    local lower = standing:lower()
    return lower:sub(1, 1):upper() .. lower:sub(2)
end

--- "Standing: " uses tooltip default color; standing name uses bar/standing color.
local function RepTooltipStandingLine(standing)
    local shown = StandingDisplayText(standing)
    local r, g, b = DS.GetReputationBarColorsForStanding(standing)
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return "Standing: " .. hex .. shown .. "|r"
end

local function RepCellTooltipTitleClassColored(entry, factionName)
    local n = (entry and entry.name) or "?"
    local r, g, b = 1, 0.82, 0
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(entry and entry.classFile, r, g, b)
    end
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return hex .. n .. "|r — " .. (factionName or "?")
end

local COLUMN_WINDOW_BUFFER = 2
local currentList = {}
local currentFactionRows = {}
local currentNumRows = 0
local gridPopulateCtx = nil
local shownFirst, shownLast = nil, nil

local function UpdateFactionLabels(factionRows, numRows)
    for _, lab in pairs(factionLabelPool) do
        lab:Hide()
    end

    local filterQuery = factionFilterEdit and factionFilterEdit:GetText() or ""
    for r = 1, numRows do
        local row = GetFactionLabelRow(r)
        local fr = factionRows[r]
        row.factionID = fr and fr.factionID
        row:SetSize(FACTION_LABEL_WIDTH, dims.rowHeight)
        row:ClearAllPoints()
        if r == 1 then
            row:SetPoint("TOPLEFT", factionHeaderContainer, "TOPLEFT", 0, -GetFirstRowLabelVerticalOffset())
        else
            row:SetPoint("TOPLEFT", factionLabelPool[r - 1], "BOTTOMLEFT", 0, 0)
        end

        local isSorted = fr and factionSortFactionID and factionSortFactionID == fr.factionID
        local name = (fr and fr.name) or "?"
        row.factionName = name

        local zygorTitle = nil
        if ZI and ZI.GetGuideForFaction and fr and fr.factionID then
            zygorTitle = ZI.GetGuideForFaction(fr.factionID)
        end
        row.zygorGuideTitle = zygorTitle
        local hasZygor = zygorTitle ~= nil

        if isSorted then
            row.text:SetTextColor(1, 0.82, 0, 1)
            row.sortBtn.text:SetText(factionSortHighFirst and ">" or "<")
            row.sortBtn:Show()
        else
            row.text:SetTextColor(1, 1, 1, 1)
            row.sortBtn:Hide()
        end

        row.zygorBtn:ClearAllPoints()
        if hasZygor then
            local texPath = ZI and ZI.GetIconTexturePath and ZI.GetIconTexturePath()
            if texPath and row.zygorBtn.icon then
                row.zygorBtn.icon:SetTexture(texPath)
            end
            row.zygorBtn:SetSize(ZYGOR_BTN_SIZE, dims.rowHeight)
            -- Anchor to the row (not sortBtn) so full-height hit area stays row-aligned.
            local rightInset = 2
            if isSorted then
                rightInset = 2 + FACTION_SORT_BTN_SIZE + ZYGOR_BTN_GAP
            end
            row.zygorBtn:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
            row.zygorBtn:Show()
        else
            row.zygorBtn:Hide()
        end

        local baseMax = FACTION_LABEL_WIDTH - 6
        local nameMax = baseMax
        if isSorted then
            nameMax = nameMax - (FACTION_SORT_BTN_SIZE + 4)
        end
        if hasZygor then
            nameMax = nameMax - (ZYGOR_BTN_SIZE + ZYGOR_BTN_GAP)
        end
        local shownName = name
        if TruncateFontString then
            shownName = TruncateFontString(row.text, name, nameMax) or name
        else
            row.text:SetText(name)
        end
        row.truncated = (shownName ~= name)
        -- Highlight filter matches in green (after truncation so width is measured on plain text);
        -- matches are found in the full name so one cut off by "..." still highlights its visible part.
        local GTD = AltArmy.GuildTabData
        if filterQuery ~= "" and GTD and GTD.FormatTruncatedTextWithSearchHighlight then
            row.text:SetText(GTD.FormatTruncatedTextWithSearchHighlight(name, shownName, filterQuery))
        end
        row:Show()
    end
end

local function PopulateHeaderColumn(c, entry, ctx)
    local headerCol = GetHeaderColumnFrame(c)
    headerCol:ClearAllPoints()
    headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD, 0)

    local classR, classG, classB = 1, 0.82, 0
    if CC and CC.getRGBOr then
        classR, classG, classB = CC.getRGBOr(entry.classFile, classR, classG, classB)
    end
    headerCol.reputationHeaderColumnIndex = c
    local displayName = entry.name or "?"
    local isColSorted = columnSortName
        and entry.name == columnSortName
        and (entry.realm or "") == (columnSortRealm or "")
    if isColSorted then
        classR, classG, classB = 1, 0.82, 0
    end
    headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
    local hdrSuffix = isColSorted and Theme.GetSortArrowSuffix(not columnSortHighFirst) or ""
    local baseHeaderMax = dims.columnWidth - 4
    local headerMax = (hdrSuffix ~= "") and (baseHeaderMax - 14) or baseHeaderMax
    headerCol.header:SetTextColor(classR, classG, classB, 1)
    local shown = displayName
    if TruncateFontString then
        shown = TruncateFontString(headerCol.header, displayName, headerMax)
    else
        headerCol.header:SetText(displayName)
    end
    if hdrSuffix ~= "" then
        headerCol.header:SetText(shown .. hdrSuffix)
    end
    headerCol.truncated = (shown ~= displayName)
    local RF = ctx.RF
    local showRealmSuffix = ctx.showRealmSuffix
    local hasRealm = entry.realm and entry.realm ~= ""
    if headerCol.truncated or (showRealmSuffix and hasRealm) then
        headerCol.tooltipText = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(
                entry.name or "?",
                entry.realm,
                showRealmSuffix,
                entry.classFile
            )
            or displayName
    else
        headerCol.tooltipText = nil
    end

    headerCol.message:SetText("")
    headerCol.message:SetTextColor(0.9, 0.9, 0.9, 1)
    headerCol.message:Show()

    SSR.ApplyColumnScore(headerCol.scoreText, headerCol.scoreHover, entry, ctx.scoreProviderId, false, {
        playedUnitStyle = "full",
    })
end

local function PopulateGridColumn(c, entry, factionRows, numRows, _ctx)
    local col = GetColumnFrame(c)
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)

    local charData = DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    local hasRep = charData and DS.HasModuleData and DS:HasModuleData(charData, "reputations")

    for r = 1, numRows do
        local cell = EnsureCell(col, r)
        cell:ClearAllPoints()
            if r == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", 4, REP_FIRST_ROW_CELL_Y)
        else
            cell:SetPoint("TOPLEFT", col.cells[r - 1], "BOTTOMLEFT", 0, 0)
        end
        ApplyRepCellContentLayout(cell)
        cell:Show()
        cell.barBg:Show()
        cell.barFill:Show()
        cell.missingDataTooltipEntry = nil

        local factionID = factionRows[r] and factionRows[r].factionID
        local fname = factionRows[r] and factionRows[r].name or "?"
        cell.tooltipTitle = (entry.name or "?") .. " — " .. fname
        cell.tooltipLines = nil

        if not hasRep then
            cell.standing:SetText("—")
            cell.standing:SetTextColor(0.6, 0.6, 0.6, 1)
            cell.progress:SetText("No data")
            cell.progress:SetTextColor(0.55, 0.55, 0.55, 1)
            cell.barFill:SetVertexColor(0.35, 0.35, 0.35, 1)
            cell.barFill:SetWidth(RGW.BarFillWidth(0, REP_BAR_FULL_WIDTH))
            cell.tooltipLines = { "Reputation data not collected for this character." }
        elseif not factionID then
            cell.standing:SetText("—")
            cell.progress:SetText("")
            cell.barFill:SetVertexColor(0.3, 0.3, 0.3, 1)
            cell.barFill:SetWidth(RGW.BarFillWidth(0, REP_BAR_FULL_WIDTH))
        else
            local rawRep = charData.Reputations[factionID]
            local isV1Legacy = type(rawRep) == "number"
            local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(charData, factionID)
            if not standing then
                cell.standing:SetText("")
                cell.standing:SetTextColor(0.7, 0.7, 0.7, 1)
                cell.progress:SetText("")
                cell.progress:SetTextColor(0.7, 0.7, 0.7, 1)
                cell.barBg:Hide()
                cell.barFill:Hide()
                cell.tooltipTitle = RepCellTooltipTitleClassColored(entry, fname)
                cell.tooltipLines = { "Not yet discovered" }
            elseif isV1Legacy then
                cell.standing:SetText("")
                cell.standing:SetTextColor(0.92, 0.92, 0.92, 1)
                cell.progress:SetText("(missing data)")
                cell.progress:SetTextColor(MISSING_DATA_TEXT_R, MISSING_DATA_TEXT_G, MISSING_DATA_TEXT_B, 1)
                cell.barBg:Hide()
                cell.barFill:Hide()
                cell.tooltipTitle = nil
                cell.tooltipLines = nil
                cell.missingDataTooltipEntry = {
                    name = entry.name or "",
                    realm = entry.realm or "",
                    classFile = entry.classFile,
                }
            else
                cell.standing:SetText(StandingDisplayText(standing))
                local br, bgc, bb = DS.GetReputationBarColorsForStanding(standing)
                cell.standing:SetTextColor(br, bgc, bb, 1)
                cell.progress:SetText(DS.FormatReputationPercentText(rate, standing))
                cell.progress:SetTextColor(0.92, 0.92, 0.92, 1)
                cell.barFill:SetVertexColor(br, bgc, bb, 1)
                local pct = tonumber(rate) or 0
                cell.barFill:SetWidth(RGW.BarFillWidth(pct, REP_BAR_FULL_WIDTH))
                cell.tooltipTitle = RepCellTooltipTitleClassColored(entry, fname)
                cell.tooltipLines = {
                    RepTooltipStandingLine(standing),
                    "Progress: " .. DS.FormatReputationProgressTextExact(standing, repEarned, nextLevel),
                }
            end
        end
    end

    for rr = numRows + 1, #(col.cells or {}) do
        if col.cells[rr] then col.cells[rr]:Hide() end
    end
end

ApplyColumnWindow = function(force)
    if not horizontalScroll or not gridPopulateCtx then return end
    local numCols = #currentList
    local viewW = horizontalScroll:GetWidth() or 0
    local offset = math.floor((horizontalScroll:GetHorizontalScroll() or 0) + 0.5)
    local first, last = RGW.GetVisibleColumnRange(
        offset, viewW, dims.columnWidth, numCols, COLUMN_WINDOW_BUFFER)

    if force then
        shownFirst, shownLast = nil, nil
    elseif shownFirst and shownLast and first == shownFirst and last == shownLast then
        return
    end

    -- While dragging, populate columns entering the window but defer hides until release.
    -- Off-screen columns are clipped by the scroll frame; hiding mid-drag caused empty gaps.
    if not repGridScrollDragging then
        if shownFirst and shownLast then
            for c = shownFirst, shownLast do
                if c < first or c > last or c > numCols then
                    local col = columnPool[c]
                    if col then col:Hide() end
                    local hdr = headerColumnPool[c]
                    if hdr then hdr:Hide() end
                end
            end
        end
        for idx, col in pairs(columnPool) do
            if idx > numCols then col:Hide() end
        end
        for idx, col in pairs(headerColumnPool) do
            if idx > numCols then col:Hide() end
        end
    end

    for c = first, last do
        local entry = currentList[c]
        if entry then
            local needsPopulate = force or not shownFirst or c < shownFirst or c > shownLast
            if needsPopulate then
                PopulateHeaderColumn(c, entry, gridPopulateCtx)
                PopulateGridColumn(c, entry, currentFactionRows, currentNumRows, gridPopulateCtx)
            end
            GetHeaderColumnFrame(c):Show()
            GetColumnFrame(c):Show()
        end
    end

    shownFirst, shownLast = first, last
end

local function BuildPopulateCtx(list)
    local RF = AltArmy.RealmFilter
    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then
        realmFilter = GRF.Get()
    end
    local showRealmSuffix = (realmFilter == "all")
        and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
    return {
        scoreProviderId = GetReputationSettings().scoreProvider or SSR.DEFAULT_PROVIDER,
        realmFilter = realmFilter,
        showRealmSuffix = showRealmSuffix,
        RF = RF,
    }
end

function frame:RefreshGrid(_self)
    if not AltArmy.Characters then return end
    if AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(false, "level")
    end

    if scoreSortControls and scoreSortControls.Update then
        scoreSortControls:Update()
    end

    if DS and DS.GetCurrentReputationFactionRows then
        lastFactionRows = DS:GetCurrentReputationFactionRows()
    else
        lastFactionRows = {}
    end
    currentList = GetDisplayList()
    currentFactionRows = GetDisplayFactionRows()
    currentNumRows = #currentFactionRows
    gridPopulateCtx = BuildPopulateCtx(currentList)
    dims.scrollableGridHeight = math.max(dims.rowHeight + PAD, currentNumRows * dims.rowHeight + PAD)

    if verticalScrollChild then
        verticalScrollChild:SetHeight(GetHeaderHeight() + dims.scrollableGridHeight)
    end
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end

    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        for r, cell in pairs(col.cells or {}) do
            cell:SetSize(dims.columnWidth - 8, dims.rowHeight)
            if r == 1 then
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", 4, REP_FIRST_ROW_CELL_Y)
            else
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col.cells[r - 1], "BOTTOMLEFT", 0, 0)
            end
            ApplyRepCellContentLayout(cell)
        end
    end

    for _, lab in pairs(factionLabelPool) do
        lab:SetHeight(dims.rowHeight)
    end

    local numCols = #currentList
    local viewWidth = verticalScroll and verticalScroll:GetWidth() or 0
    local gridContentWidth = numCols * dims.columnWidth + PAD
    local gridViewWidth = math.max(0, viewWidth - FACTION_LABEL_WIDTH)

    if verticalScrollChild and verticalScroll then
        verticalScrollChild:SetWidth(math.max(MIN_SCROLL_CHILD_WIDTH, viewWidth))
        if gridContainer then
            gridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if headerGridContainer then
            headerGridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if horizontalScroll and horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        if headerHorizontalScroll and headerHorizontalScroll.UpdateScrollChildRect then
            headerHorizontalScroll:UpdateScrollChildRect()
        end
        -- Clamps the kept offset to the new range (scroll survives tab revisits).
        verticalScrollBinding.SetStep(dims.rowHeight * 2)
        verticalScrollBinding.UpdateRange()
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollApi:SetRange(0, maxHorzScroll, gridViewWidth)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            horizontalScrollApi:Restore(maxHorzScroll)
        end
    end

    UpdateFactionLabels(currentFactionRows, currentNumRows)
    ApplyColumnWindow(true)
    if scrollTopFade then
        scrollTopFade:Update()
    end
    if scrollGridLeftFade then
        scrollGridLeftFade:Update()
    end
    if scrollHeaderLeftFade then
        scrollHeaderLeftFade:Update()
    end
end

frame:SetScript("OnShow", function()
    frame:RefreshGrid()
end)

frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_FACTION" or event == "PLAYER_ENTERING_WORLD" then
        if frame:IsShown() then
            frame:RefreshGrid()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Settings panel (60% grid / 40% settings) ----
local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(settingsPanel, "section")
local function ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * GRID_SPLIT_FRACTION + SECTION_GAP, SECTION_INSET)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
ApplySettingsPanelLayout()
settingsPanel:Hide()

local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
local repSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
repSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
repSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
repSettingsTitle:SetJustifyH("LEFT")
repSettingsTitle:SetText("Reputation Settings")
Theme.SetTitleColor(repSettingsTitle)

local repCharListRefresh = function() end

local sortingContent = CreateFrame("Frame", nil, settingsContent)
sortingContent:SetPoint("TOPLEFT", repSettingsTitle, "BOTTOMLEFT", 0, -8)
sortingContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)

local PIN_CURRENT_CHAR_HELP = {
    title = "Pin current character",
    lines = {
        "When enabled, your current character is automatically pinned, "
            .. "causing it to show ahead of non-pinned characters.",
        'This will override the "Hide" setting.',
    },
}

local showSelfFirstRow = Theme.CreateLabeledCheckbox(sortingContent, {
    point = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Pin current character",
    fullWidthHover = true,
    onClick = function(checked)
        GetReputationSettings().showSelfFirst = checked
        frame:RefreshGrid()
    end,
})
Theme.AttachSettingsHelpIcon(showSelfFirstRow, PIN_CURRENT_CHAR_HELP)
local showSelfFirstCheck = showSelfFirstRow.check

if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent, showSelfFirstRow, {
        gutterEdge = settingsPanel,
        getSettings = GetReputationSettings,
        getCharSetting = GetCharSetting,
        setCharSetting = SetCharSetting,
        onChange = function()
            frame:RefreshGrid()
        end,
    })
    if refresh then repCharListRefresh = refresh end
    -- luacheck: pop
end

settingsPanel:SetScript("OnHide", function()
    if scoreSortControls and scoreSortControls.dropdown then
        scoreSortControls.dropdown:Hide()
    end
end)

function frame:IsReputationSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

function frame:ToggleReputationSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySettingsPanelLayout()
    end
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if showSettings then
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
    rightPanel:ClearAllPoints()
    rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)
    if showSettings then
        local s = GetReputationSettings()
        showSelfFirstCheck:SetChecked(s.showSelfFirst)
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if repCharListRefresh then repCharListRefresh() end
    end
    frame:RefreshGrid()
end

frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        ApplySettingsPanelLayout()
        tabContentPanel:ClearAllPoints()
        tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
        rightPanel:ClearAllPoints()
        rightPanel:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
        rightPanel:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)
        frame:RefreshGrid()
    end
end)
