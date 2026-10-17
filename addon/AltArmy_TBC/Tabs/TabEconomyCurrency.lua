-- AltArmy TBC — Economy tab, Currency view: currencies (rows) × characters (columns), fills frame.CurrencyView.
-- Grid layout follows Tabs/TabReputation.lua (pinned header with the score-sort row, synced horizontal
-- scroll, column windowing, pin/hide settings panel). Rows and sorting: Data/Economy/CurrencyGrid.lua.
-- luacheck: globals GameTooltip

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame or not frame.CurrencyView then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local G = AltArmy.CurrencyGrid
local SSR = AltArmy.ScoreSortRow
local RGW = AltArmy.ReputationGridWindow
local RepSort = AltArmy.ReputationFactionSort
if not (DS and Theme and G and SSR and RGW and RepSort) then return end

local SD = AltArmy.SummaryData
local CC = AltArmy.ClassColor
local CharKey = AltArmy.CharKey
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString

local UI = {
    PAD = 4,
    LABEL_WIDTH = 150,
    COLUMN_WIDTH = 113, -- 50% wider than Reputation's, so gold / silver / copper fits
    CELL_TEXT_INSET = 2,
    ROW_HEIGHT = 20,
    ICON_SIZE = 14,
    -- Header: name row + message row + score-sort row (same as Reputation / Gear).
    NAME_ROW_HEIGHT = 20,
    MESSAGE_ROW_HEIGHT = 14,
    NAME_Y_OFFSET = 1,
    SCORE_ROW_HEIGHT = 20,
    SCORE_ROW_CONTENT_HEIGHT = 24,
    SCORE_ROW_BOTTOM_INSET = 6,
    HEADER_BG_OVERHANG = 6,
    HEADER_BG_BOTTOM_INSET = 6,
    HORIZONTAL_SCROLL_BAR_HEIGHT = 20,
    MIN_SCROLL_CHILD_WIDTH = 400,
    GRID_SPLIT_FRACTION = 0.6,
    COLUMN_WINDOW_BUFFER = 2,
    SCROLL_GUTTER = Theme.VerticalScrollBarGutter(),
    GOLD = { 1, 0.82, 0 },
    COINS = {
        gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
        silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
        copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
    },
}
UI.HEADER_HEIGHT = UI.NAME_ROW_HEIGHT + UI.MESSAGE_ROW_HEIGHT + UI.SCORE_ROW_HEIGHT

-- Session state: the sort is not saved (same as Reputation).
local state = {
    -- Sort columns by one currency (row label click): same row flips direction, another switches.
    rowSortID = nil,
    rowSortHighFirst = true,
    list = {},
    rows = {},
    ctx = nil,
    shownFirst = nil,
    shownLast = nil,
    dragging = false,
    gridHeight = UI.ROW_HEIGHT + UI.PAD,
}

local pools = { header = {}, column = {}, label = {} }
local W = {} -- widgets

local function Settings()
    return G.EnsureSettings()
end

local function GetCharSetting(name, realm, key)
    local c = Settings().characters[CharKey(name, realm)]
    return c and c[key] == true or false
end

local function SetCharSetting(name, realm, pin, hide)
    Settings().characters[CharKey(name, realm)] = { pin = pin == true, hide = hide == true }
end

local function CharData(entry)
    return DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
end

local function HasData(char)
    return char and DS.HasModuleData and DS:HasModuleData(char, "currencyList") or false
end

--- hasData, amount for one row. Gold is the character's money (copper), recorded at every login.
local function RowAmount(char, currencyID)
    if currencyID == G.GOLD_ID then
        if not (char and DS.HasModuleData and DS:HasModuleData(char, "character")) then return false, nil end
        return true, DS:GetMoney(char)
    end
    if not HasData(char) then return false, nil end
    return true, DS:GetCurrencyListAmount(char, currencyID)
end

local function AmountFor(entry, currencyID)
    local ok, amount = RowAmount(CharData(entry), currencyID)
    if not ok then return nil end
    return amount
end

local function ClassHex(classFile)
    local r, g, b = UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(classFile, r, g, b)
    end
    return string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function Refresh()
    if frame.RefreshCurrency then frame.RefreshCurrency() end
end

local function ToggleRowSort(currencyID)
    if not currencyID then return end
    if state.rowSortID == currencyID then
        state.rowSortHighFirst = not state.rowSortHighFirst
    else
        state.rowSortID = currencyID
        state.rowSortHighFirst = true
    end
    Refresh()
end

local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    local settings = Settings()
    local showSelfFirst = settings.showSelfFirst ~= false
    local BA = AltArmy.BankAlt

    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        local isSelf = DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm)
        local isHidden = GetCharSetting(e.name, e.realm, "hide") or (BA and BA.Is and BA.Is(e.name, e.realm))
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
        if state.rowSortID then
            return G.CompareByAmount(a, b, function(e) return AmountFor(e, state.rowSortID) end,
                state.rowSortHighFirst, scoreCompare)
        end
        return scoreCompare(a, b)
    end
    local list = RepSort.BuildSortedDisplayList(visible,
        function(e) return GetCharSetting(e.name, e.realm, "pin") end,
        function(e) return DS.IsCurrentCharacter and DS:IsCurrentCharacter(e.name, e.realm) end,
        showSelfFirst, sortPair)

    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.FilterList then
        local currentRealm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""
        list = GRF.FilterList(list, currentRealm)
    end
    return list
end

local function FilterText()
    return W.filterEdit and W.filterEdit:GetText() or ""
end

local function GetDisplayRows(list)
    local chars = {}
    for _, e in ipairs(list) do
        local c = CharData(e)
        if c then chars[#chars + 1] = c end
    end
    return G.FilterRows(G.BuildRows(chars, DS:GetCurrencyMeta(), { gold = true }), FilterText())
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local panel = frame.CurrencyView
W.inner = Theme.CreatePanelInnerContent(panel)
W.inner:SetClipsChildren(true)

W.contentArea = CreateFrame("Frame", nil, W.inner)
W.contentArea:SetClipsChildren(true)
local function LayoutContentArea()
    local area = W.contentArea
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", W.inner, "TOPLEFT", 0, -UI.PAD)
    area:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.SCROLL_GUTTER, 0)
    area:SetPoint("BOTTOMLEFT", W.inner, "BOTTOMLEFT", 0, 0)
    area:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.SCROLL_GUTTER, UI.HORIZONTAL_SCROLL_BAR_HEIGHT)
    local bar = W.horizontalScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", W.inner, "BOTTOMLEFT", 0, -4)
        bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.SCROLL_GUTTER, -4)
        bar:SetFrameLevel(panel:GetFrameLevel() + 30)
        bar:EnableMouse(true)
    end
end
LayoutContentArea()

W.verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_CurrencyVerticalScroll", W.contentArea)
W.verticalScroll:SetAllPoints(W.contentArea)
W.verticalScroll:EnableMouse(true)
W.scrollChild = CreateFrame("Frame", nil, W.verticalScroll)
W.scrollChild:SetPoint("TOPLEFT", W.verticalScroll, "TOPLEFT", 0, 0)
W.scrollChild:SetSize(UI.MIN_SCROLL_CHILD_WIDTH, UI.HEADER_HEIGHT + state.gridHeight)
W.scrollChild:EnableMouse(true)
W.verticalScroll:SetScrollChild(W.scrollChild)

-- Pinned header: corner (score-sort controls) + character columns.
W.headerRow = CreateFrame("Frame", nil, W.contentArea)
W.headerRow:SetPoint("TOPLEFT", W.contentArea, "TOPLEFT", 0, 0)
W.headerRow:SetPoint("TOPRIGHT", W.contentArea, "TOPRIGHT", 0, 0)
W.headerRow:SetHeight(UI.HEADER_HEIGHT)
W.headerRow:SetFrameLevel(W.contentArea:GetFrameLevel() + 20)
W.headerRow:EnableMouse(true)
do
    local bg = W.headerRow:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("BOTTOMLEFT", W.headerRow, "BOTTOMLEFT", 0, UI.HEADER_BG_BOTTOM_INSET)
    bg:SetPoint("BOTTOMRIGHT", W.headerRow, "BOTTOMRIGHT", 0, UI.HEADER_BG_BOTTOM_INSET)
    bg:SetPoint("TOPLEFT", W.headerRow, "TOPLEFT", 0, UI.HEADER_BG_OVERHANG)
    bg:SetPoint("TOPRIGHT", W.headerRow, "TOPRIGHT", 0, UI.HEADER_BG_OVERHANG)
    Theme.StyleGridHeader(bg)
end

W.corner = CreateFrame("Frame", nil, W.headerRow)
W.corner:SetPoint("TOPLEFT", W.headerRow, "TOPLEFT", 0, 0)
W.corner:SetSize(UI.LABEL_WIDTH, UI.HEADER_HEIGHT)
Theme.ApplyGridLabelColumnBackground(W.corner)

W.scoreSortControls = SSR.CreateCornerControls(W.corner, {
    btnSize = UI.SCORE_ROW_CONTENT_HEIGHT,
    bottomInset = UI.SCORE_ROW_BOTTOM_INSET,
    dropdownParent = W.headerRow,
    dropdownWidth = 200,
    getProviderId = function() return Settings().scoreProvider end,
    setProviderId = function(id) Settings().scoreProvider = id end,
    getDescending = function() return Settings().scoreSortDescending ~= false end,
    setDescending = function(v) Settings().scoreSortDescending = v end,
    -- A currency sort overrides the score sort: hide its direction button meanwhile.
    isDirectionShown = function() return state.rowSortID == nil end,
    -- Clicking the score selector cancels the currency sort (first click only, descending).
    onProviderActivate = function()
        if state.rowSortID ~= nil then
            state.rowSortID = nil
            Settings().scoreSortDescending = true
            Refresh()
            return true
        end
        return false
    end,
    onChange = Refresh,
})

W.headerScroll = CreateFrame("ScrollFrame", "AltArmyTBC_CurrencyHeaderHorizontalScroll", W.headerRow)
W.headerScroll:SetPoint("TOPLEFT", W.corner, "TOPRIGHT", 0, 0)
W.headerScroll:SetPoint("BOTTOMRIGHT", W.headerRow, "BOTTOMRIGHT", 0, 0)
W.headerScroll:EnableMouse(true)
W.headerGrid = CreateFrame("Frame", nil, W.headerScroll)
W.headerGrid:SetPoint("TOPLEFT", W.headerScroll, "TOPLEFT", 0, 0)
W.headerGrid:SetHeight(UI.HEADER_HEIGHT)
W.headerScroll:SetScrollChild(W.headerGrid)

W.verticalBinding = Theme.CreateVerticalScrollBinding(W.verticalScroll, {
    parent = panel,
    name = "AltArmyTBC_CurrencyVerticalScrollBar",
    step = UI.ROW_HEIGHT * 3,
    onScroll = function()
        if W.topFade then W.topFade:Update() end
    end,
})
W.verticalBinding.bar:SetFrameLevel(panel:GetFrameLevel() + 30)
Theme.AnchorVerticalScrollBar(W.verticalBinding.bar, panel, W.contentArea, { gap = 0 })
W.topFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = W.headerRow,
    scrollFrame = W.verticalScroll,
    scrollBar = W.verticalBinding.bar,
})
W.scrollChild:SetScript("OnMouseWheel", function(_, delta)
    W.verticalBinding.Wheel(delta)
end)

W.labelColumn = CreateFrame("Frame", nil, W.scrollChild)
W.labelColumn:SetPoint("TOPLEFT", W.scrollChild, "TOPLEFT", 0, -UI.HEADER_HEIGHT)
W.labelColumn:SetPoint("BOTTOMLEFT", W.scrollChild, "BOTTOMLEFT", 0, 0)
W.labelColumn:SetWidth(UI.LABEL_WIDTH)
Theme.ApplyGridLabelColumnBackground(W.labelColumn)

W.gridScroll = CreateFrame("ScrollFrame", "AltArmyTBC_CurrencyHorizontalScroll", W.scrollChild)
W.gridScroll:SetPoint("TOPLEFT", W.scrollChild, "TOPLEFT", UI.LABEL_WIDTH, -UI.HEADER_HEIGHT)
W.gridScroll:SetPoint("BOTTOMRIGHT", W.scrollChild, "BOTTOMRIGHT", 0, 0)
W.gridScroll:EnableMouse(true)
W.grid = CreateFrame("Frame", nil, W.gridScroll)
W.grid:SetPoint("TOPLEFT", W.gridScroll, "TOPLEFT", 0, 0)
W.grid:SetHeight(state.gridHeight)
W.gridScroll:SetScrollChild(W.grid)

-- No character has currency data yet: a message in place of the grid.
W.empty = W.inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
W.empty:SetPoint("CENTER", W.inner, "CENTER", 0, 20)
W.empty:SetWidth(420)
W.empty:SetJustifyH("CENTER")
W.empty:SetWordWrap(true)
W.empty:Hide()
UI.EMPTY_TEXT = "No currencies recorded yet.\n\nLog in on each character and Alt Army will record the "
    .. "currencies from its Character window's Currency tab."

-- "Filter currency" box in the main toolbar row (where Summary's item search sits), same as Reputation's
-- faction filter. Parented to the Currency panel so it shows only on this view.
W.filterEdit = Theme.CreateSearchBox(panel, {
    name = "AltArmyTBC_CurrencyFilterEdit",
    placeholder = "Filter currency",
})
if AltArmy.PlaceInToolbarSearchSlot then
    AltArmy.PlaceInToolbarSearchSlot(W.filterEdit, panel)
end
-- HookScript keeps SearchBoxTemplate's own handlers (clear button, placeholder).
W.filterEdit:HookScript("OnTextChanged", function(box)
    Theme.UpdateEditBoxPlaceholderVisibility(box)
    if frame.RefreshCurrency then frame.RefreshCurrency() end
end)
W.filterEdit:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
W.filterEdit:HookScript("OnEscapePressed", function(box) Theme.ClearEditBoxText(box) end)

-- ---------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------

-- Character name headers are not interactive (no sort, no hover band); they only show the
-- cross-realm tooltip.
local function GetHeaderColumn(index)
    local col = pools.header[index]
    if col then return col end
    col = CreateFrame("Frame", nil, W.headerGrid)
    col:SetSize(UI.COLUMN_WIDTH, UI.HEADER_HEIGHT)
    col:EnableMouse(true)
    col:SetScript("OnEnter", function(self)
        if self.tooltipText and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    col:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    col.header = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, UI.NAME_Y_OFFSET)
    col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, UI.NAME_Y_OFFSET)
    col.header:SetHeight(UI.NAME_ROW_HEIGHT)
    col.header:SetJustifyH("CENTER")
    col.header:SetWordWrap(false)
    col.scoreText = col:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    col.scoreText:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, UI.SCORE_ROW_BOTTOM_INSET)
    col.scoreText:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, UI.SCORE_ROW_BOTTOM_INSET)
    col.scoreText:SetHeight(UI.SCORE_ROW_CONTENT_HEIGHT)
    col.scoreText:SetJustifyH("CENTER")
    col.scoreHover = CreateFrame("Frame", nil, col)
    col.scoreHover:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, UI.SCORE_ROW_BOTTOM_INSET)
    col.scoreHover:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, UI.SCORE_ROW_BOTTOM_INSET)
    col.scoreHover:SetHeight(UI.SCORE_ROW_CONTENT_HEIGHT)
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
    pools.header[index] = col
    return col
end

local function ShowCellTooltip(cell)
    if not GameTooltip or not cell.entry or not cell.row then return end
    local e, row = cell.entry, cell.row
    GameTooltip:SetOwner(cell, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(ClassHex(e.classFile) .. (e.name or "?") .. "|r — " .. (row.name or "?"), 1, 1, 1)
    if cell.amount == nil then
        GameTooltip:AddLine("Log in on this character to record its "
            .. (row.isGold and "gold" or "currencies") .. ".", 0.9, 0.9, 0.9, true)
    elseif row.isGold then
        GameTooltip:AddDoubleLine("Amount", SD.GetMoneyString(cell.amount), 1, 0.82, 0, 1, 1, 1)
    else
        local amount = G.FormatAmount(cell.amount)
        if row.max then amount = amount .. " / " .. G.FormatAmount(row.max) end
        GameTooltip:AddDoubleLine("Amount", amount, 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

--- Show the most detailed money string that fits the cell: drop copper, then silver.
local function SetMoneyText(fs, copper)
    local maxW = UI.COLUMN_WIDTH - 2 * UI.CELL_TEXT_INSET
    local variants = G.MoneyVariants(copper, UI.COINS)
    for i, text in ipairs(variants) do
        fs:SetText(text)
        local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        if i == #variants or (w or 0) <= maxW then return end
    end
end

local function GetColumn(index)
    local col = pools.column[index]
    if col then return col end
    col = CreateFrame("Frame", nil, W.grid)
    col:SetWidth(UI.COLUMN_WIDTH)
    col.cells = {}
    pools.column[index] = col
    return col
end

local function EnsureCell(col, r)
    local cell = col.cells[r]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, col)
    cell:SetSize(UI.COLUMN_WIDTH, UI.ROW_HEIGHT)
    cell:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -(r - 1) * UI.ROW_HEIGHT)
    cell:EnableMouse(true)
    cell.text = cell:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    cell.text:SetPoint("TOPLEFT", cell, "TOPLEFT", UI.CELL_TEXT_INSET, 0)
    cell.text:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -UI.CELL_TEXT_INSET, 0)
    cell.text:SetJustifyH("CENTER")
    cell.text:SetWordWrap(false)
    cell:SetScript("OnEnter", ShowCellTooltip)
    cell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    col.cells[r] = cell
    return cell
end

local function ShowLabelTooltip(self)
    if not GameTooltip or not self.row or self.row.isHeader then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    if GameTooltip.SetCurrencyByID and not self.row.isGold and not self.row.name:match("^#") then
        GameTooltip:SetCurrencyByID(self.row.currencyID)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.row.name, 1, 1, 1)
        if self.row.isGold then
            GameTooltip:AddLine("Time is money, friend!", 1, 0.82, 0, true)
        end
    end
    GameTooltip:AddLine("Click to sort characters by this currency.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function GetLabelRow(i)
    local row = pools.label[i]
    if row then return row end
    row = CreateFrame("Button", nil, W.labelColumn)
    row:SetSize(UI.LABEL_WIDTH, UI.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", W.labelColumn, "TOPLEFT", 0, -(i - 1) * UI.ROW_HEIGHT)
    Theme.BindInteractableHover(row, {
        onEnter = ShowLabelTooltip,
        onLeave = function()
            if GameTooltip then GameTooltip:Hide() end
        end,
    })
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(UI.ICON_SIZE, UI.ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.sortBtn = CreateFrame("Button", nil, row)
    row.sortBtn:SetSize(UI.ROW_HEIGHT - 2, UI.ROW_HEIGHT - 2)
    row.sortBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    Theme.SkinButton(row.sortBtn)
    row.sortBtn.text = row.sortBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    row.sortBtn.text:SetPoint("CENTER", row.sortBtn, "CENTER", 0, 0)
    row.sortBtn.text:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
    row.sortBtn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        ToggleRowSort(parent.row and parent.row.currencyID)
    end)
    row.sortBtn:Hide()
    row:SetScript("OnClick", function(self)
        if self.row and not self.row.isHeader then ToggleRowSort(self.row.currencyID) end
    end)
    pools.label[i] = row
    return row
end

-- ---------------------------------------------------------------------------
-- Populate
-- ---------------------------------------------------------------------------

local function UpdateLabels()
    for _, lab in pairs(pools.label) do lab:Hide() end
    for i, r in ipairs(state.rows) do
        local lab = GetLabelRow(i)
        lab.row = r
        lab.text:ClearAllPoints()
        lab.text:SetPoint("RIGHT", lab, "RIGHT", -2, 0)
        local maxW = UI.LABEL_WIDTH - 6
        if r.isHeader then
            lab.icon:Hide()
            lab.sortBtn:Hide()
            lab.text:SetPoint("LEFT", lab, "LEFT", 2, 0)
            lab.text:SetFontObject(Theme.FONTS.heading)
            lab.text:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
            lab:EnableMouse(false)
        else
            lab:EnableMouse(true)
            lab.text:SetFontObject(Theme.FONTS.body)
            if r.icon then
                lab.icon:SetTexture(r.icon)
                lab.icon:Show()
            else
                lab.icon:Hide()
            end
            lab.text:SetPoint("LEFT", lab, "LEFT", 2 + UI.ICON_SIZE + 4, 0)
            maxW = maxW - UI.ICON_SIZE - 4
            local sorted = state.rowSortID == r.currencyID
            if sorted then
                lab.text:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
                lab.sortBtn.text:SetText(state.rowSortHighFirst and ">" or "<")
                lab.sortBtn:Show()
                lab.text:SetPoint("RIGHT", lab.sortBtn, "LEFT", -2, 0)
                maxW = maxW - UI.ROW_HEIGHT
            else
                lab.text:SetTextColor(1, 1, 1, 1)
                lab.sortBtn:Hide()
            end
        end
        local shown = r.name
        if TruncateFontString then
            shown = TruncateFontString(lab.text, r.name, maxW) or r.name
        else
            lab.text:SetText(r.name)
        end
        -- Filter matches in green (after truncation, so a match cut off by "..." still shows its part).
        local query = FilterText()
        local GTD = AltArmy.GuildTabData
        if not r.isHeader and query ~= "" and GTD and GTD.FormatTruncatedTextWithSearchHighlight then
            lab.text:SetText(GTD.FormatTruncatedTextWithSearchHighlight(r.name, shown, query))
        end
        lab:Show()
    end
end

local function PopulateHeaderColumn(c, entry)
    local col = GetHeaderColumn(c)
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", W.headerGrid, "TOPLEFT", (c - 1) * UI.COLUMN_WIDTH + UI.PAD, 0)
    col.columnIndex = c

    local r, g, b = UI.GOLD[1], UI.GOLD[2], UI.GOLD[3]
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
    end
    col.header:SetTextColor(r, g, b, 1)
    local name = entry.name or "?"
    local shown = name
    if TruncateFontString then
        shown = TruncateFontString(col.header, name, UI.COLUMN_WIDTH - 4) or name
    else
        col.header:SetText(name)
    end

    local ctx = state.ctx
    local RF = ctx.RF
    local hasRealm = entry.realm and entry.realm ~= ""
    if shown ~= name or (ctx.showRealmSuffix and hasRealm) then
        col.tooltipText = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(name, entry.realm, ctx.showRealmSuffix, entry.classFile)
            or name
    else
        col.tooltipText = nil
    end
    SSR.ApplyColumnScore(col.scoreText, col.scoreHover, entry, ctx.scoreProviderId, false,
        { playedUnitStyle = "full" })
end

local function PopulateGridColumn(c, entry)
    local col = GetColumn(c)
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", W.grid, "TOPLEFT", (c - 1) * UI.COLUMN_WIDTH + UI.PAD, 0)
    col:SetHeight(state.gridHeight)
    local char = CharData(entry)
    for r, row in ipairs(state.rows) do
        local cell = EnsureCell(col, r)
        cell.entry, cell.row = entry, row
        if row.isHeader then
            cell.text:SetText("")
            cell.amount = nil
            cell:EnableMouse(false)
        else
            cell:EnableMouse(true)
            local hasData, amount = RowAmount(char, row.currencyID)
            cell.amount = amount
            if not hasData then
                cell.text:SetText("—")
                cell.text:SetTextColor(0.5, 0.5, 0.5, 1)
            elseif amount == nil or amount == 0 then
                -- Not in this character's list, or none: both show a grey 0.
                cell.amount = amount or 0
                cell.text:SetText("0")
                cell.text:SetTextColor(0.5, 0.5, 0.5, 1)
            elseif row.isGold then
                SetMoneyText(cell.text, amount)
                cell.text:SetTextColor(1, 1, 1, 1)
            else
                cell.text:SetText(G.FormatAmount(amount))
                cell.text:SetTextColor(1, 1, 1, 1)
            end
        end
        cell:Show()
    end
    for r = #state.rows + 1, #col.cells do
        col.cells[r]:Hide()
    end
end

local function ApplyColumnWindow(force)
    if not state.ctx then return end
    local numCols = #state.list
    local viewW = W.gridScroll:GetWidth() or 0
    local offset = math.floor((W.gridScroll:GetHorizontalScroll() or 0) + 0.5)
    local first, last = RGW.GetVisibleColumnRange(offset, viewW, UI.COLUMN_WIDTH, numCols,
        UI.COLUMN_WINDOW_BUFFER)
    if force then
        state.shownFirst, state.shownLast = nil, nil
    elseif state.shownFirst and first == state.shownFirst and last == state.shownLast then
        return
    end
    -- While dragging, populate entering columns but defer hides until release (as on Reputation).
    if not state.dragging then
        for idx, col in pairs(pools.column) do
            if idx < first or idx > last or idx > numCols then col:Hide() end
        end
        for idx, col in pairs(pools.header) do
            if idx < first or idx > last or idx > numCols then col:Hide() end
        end
    end
    for c = first, last do
        local entry = state.list[c]
        if entry then
            local needs = force or not state.shownFirst or c < state.shownFirst or c > state.shownLast
            if needs then
                PopulateHeaderColumn(c, entry)
                PopulateGridColumn(c, entry)
            end
            GetHeaderColumn(c):Show()
            GetColumn(c):Show()
        end
    end
    state.shownFirst, state.shownLast = first, last
end

do
    local api = Theme.CreateHorizontalScrollBar(panel, {
        name = "AltArmyTBC_CurrencyHorizontalScrollBar",
        thickness = UI.HORIZONTAL_SCROLL_BAR_HEIGHT - UI.PAD * 2,
        onScroll = function(value)
            local v = math.floor(value + 0.5)
            W.gridScroll:SetHorizontalScroll(v)
            W.headerScroll:SetHorizontalScroll(v)
            ApplyColumnWindow(false)
            if W.gridLeftFade then W.gridLeftFade:Update() end
            if W.headerLeftFade then W.headerLeftFade:Update() end
        end,
        onDragStart = function() state.dragging = true end,
        onDragEnd = function()
            state.dragging = false
            ApplyColumnWindow(true)
        end,
        isShown = function() return panel:IsVisible() end,
    })
    W.horizontalScrollApi = api
    W.horizontalScrollBar = api.bar
end
LayoutContentArea()
W.gridLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = W.gridScroll,
    scrollFrame = W.gridScroll,
    scrollBar = W.horizontalScrollBar,
})
W.headerLeftFade = Theme.CreatePinnedHorizontalScrollFade({
    anchorScrollFrame = W.headerScroll,
    scrollFrame = W.gridScroll,
    scrollBar = W.horizontalScrollBar,
})

local function BuildCtx(list)
    local RF = AltArmy.RealmFilter
    local GRF = AltArmy.GlobalRealmFilter
    local realmFilter = GRF and GRF.Get and GRF.Get() or "all"
    return {
        scoreProviderId = Settings().scoreProvider or SSR.DEFAULT_PROVIDER,
        showRealmSuffix = realmFilter == "all" and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list),
        RF = RF,
    }
end

function frame.RefreshCurrency()
    if not panel:IsVisible() or not AltArmy.Characters then return end
    if AltArmy.Characters.InvalidateView then AltArmy.Characters:InvalidateView() end
    if AltArmy.Characters.Sort then AltArmy.Characters:Sort(false, "level") end
    W.scoreSortControls:Update()

    state.list = GetDisplayList()
    state.rows = GetDisplayRows(state.list)
    state.ctx = BuildCtx(state.list)
    local numRows = #state.rows
    local hasRows = numRows > 0
    local query = FilterText():match("^%s*(.-)%s*$") or ""
    W.empty:SetText(query ~= "" and ('No currencies match "' .. query .. '".') or UI.EMPTY_TEXT)
    W.empty:SetShown(not hasRows)
    W.contentArea:SetShown(hasRows)
    W.verticalBinding.bar:SetShown(hasRows)
    if not hasRows then
        W.horizontalScrollBar:Hide()
        return
    end

    state.gridHeight = math.max(UI.ROW_HEIGHT, numRows * UI.ROW_HEIGHT) + UI.PAD
    W.scrollChild:SetHeight(UI.HEADER_HEIGHT + state.gridHeight)
    W.grid:SetHeight(state.gridHeight)

    local numCols = #state.list
    local viewWidth = W.verticalScroll:GetWidth() or 0
    local contentWidth = numCols * UI.COLUMN_WIDTH + UI.PAD
    local gridViewWidth = math.max(0, viewWidth - UI.LABEL_WIDTH)
    W.scrollChild:SetWidth(math.max(UI.MIN_SCROLL_CHILD_WIDTH, viewWidth))
    W.grid:SetWidth(contentWidth)
    W.headerGrid:SetWidth(contentWidth)
    if W.gridScroll.UpdateScrollChildRect then W.gridScroll:UpdateScrollChildRect() end
    if W.headerScroll.UpdateScrollChildRect then W.headerScroll:UpdateScrollChildRect() end
    W.verticalBinding.UpdateRange()
    local maxScroll = math.max(0, contentWidth - gridViewWidth)
    W.horizontalScrollApi:SetRange(0, maxScroll, gridViewWidth)
    W.horizontalScrollBar:SetShown(maxScroll > 0)
    W.horizontalScrollApi:Restore(maxScroll)

    UpdateLabels()
    ApplyColumnWindow(true)
    if W.topFade then W.topFade:Update() end
    if W.gridLeftFade then W.gridLeftFade:Update() end
    if W.headerLeftFade then W.headerLeftFade:Update() end
end

-- TabEconomy.lua's view switch refreshes on show; a finished scan refreshes while it is open.
if DS.OnCurrencyListChanged then
    DS:OnCurrencyListChanged(function()
        if panel:IsVisible() then frame.RefreshCurrency() end
    end)
end

-- ---------------------------------------------------------------------------
-- Settings panel (60% grid / 40% settings), opened by the toolbar settings button
-- ---------------------------------------------------------------------------

W.settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(W.settingsPanel, "section")
W.settingsPanel:Hide()

local function LayoutPanels()
    local inset, gap = Theme.TAB_SECTION_INSET, Theme.SECTION_GAP
    local sp = W.settingsPanel
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    if sp:IsShown() then
        local x = frame:GetWidth() * UI.GRID_SPLIT_FRACTION + gap
        sp:ClearAllPoints()
        sp:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -inset)
        sp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        panel:SetPoint("BOTTOMRIGHT", sp, "BOTTOMLEFT", -gap, 0)
    else
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
end

do
    local content = Theme.CreateSettingsPanelContent(W.settingsPanel)
    local title = content:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    title:SetJustifyH("LEFT")
    title:SetText("Currency Settings")
    Theme.SetTitleColor(title)

    local sorting = CreateFrame("Frame", nil, content)
    sorting:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sorting:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local selfRow = Theme.CreateLabeledCheckbox(sorting, {
        point = "TOPLEFT",
        x = 0,
        y = 0,
        text = "Pin current character",
        fullWidthHover = true,
        onClick = function(checked)
            Settings().showSelfFirst = checked
            Refresh()
        end,
    })
    Theme.AttachSettingsHelpIcon(selfRow, {
        title = "Pin current character",
        lines = {
            "When enabled, your current character is automatically pinned, "
                .. "causing it to show ahead of non-pinned characters.",
            'This will override the "Hide" setting.',
        },
    })
    W.selfCheck = selfRow.check

    if AltArmy.CreateCharacterPinHideList then
        local _, refresh = AltArmy.CreateCharacterPinHideList(sorting, selfRow, {
            gutterEdge = W.settingsPanel,
            getSettings = Settings,
            getCharSetting = GetCharSetting,
            setCharSetting = SetCharSetting,
            onChange = Refresh,
        })
        W.charListRefresh = refresh
    end
end

W.settingsPanel:SetScript("OnHide", function()
    if W.scoreSortControls.dropdown then W.scoreSortControls.dropdown:Hide() end
end)

function frame:IsEconomySettingsAvailable()
    return frame.GetEconomyView and frame.GetEconomyView() == "currency" or false
end

function frame:IsEconomySettingsShown()
    return W.settingsPanel:IsShown()
end

function frame:ToggleEconomySettings()
    local show = not W.settingsPanel:IsShown()
    W.settingsPanel:SetShown(show)
    LayoutPanels()
    if show then
        W.selfCheck:SetChecked(Settings().showSelfFirst)
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if W.charListRefresh then W.charListRefresh() end
    end
    Refresh()
end

--- Leaving the Currency view closes its settings panel (TabEconomy.lua calls this).
function frame.HideEconomySettings()
    if W.settingsPanel:IsShown() then
        W.settingsPanel:Hide()
        LayoutPanels()
    end
end

frame:HookScript("OnSizeChanged", function()
    if W.settingsPanel:IsShown() then
        LayoutPanels()
        Refresh()
    end
end)
