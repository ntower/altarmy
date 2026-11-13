-- AltArmy TBC — Economy tab, Craftsman's Writs view: every writ's order with what it costs to buy on the
-- auction house or to craft the cheapest way (Data/Economy/CraftPlan.lua) by the realm's characters, and
-- the steps to do it in the row's tooltip. Fills frame.WritsView; laid out like the Waylaid Crates view in
-- TabEconomy.lua. Writs: Data/Economy/Writs.lua; rows and sorting: Data/Economy/WritCosts.lua (pure);
-- the orders the game told us: Data/Economy/WritOrders.lua.
-- luacheck: globals GameTooltip GetItemIcon GetServerTime

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame or not frame.WritsView then return end

local Theme = AltArmy.Theme
local W = AltArmy.WaylaidCosts -- the Economy tab's options and the scan age text
local WC = AltArmy.WritCosts
local Writs = AltArmy.Writs
local Book = AltArmy.AuctionBook
local DS = AltArmy.DataStore
local ET = AltArmy.EconomyTooltip -- the rows' tooltips (UI/EconomyTooltip.lua)
if not (Theme and W and WC and Writs and Book and DS and ET and AltArmy.CraftPlan and AltArmy.CraftContext
    and AltArmy.ColumnFit and frame.CreateScanFooter and frame.CreateEmptyState and frame.AddLevelEntries
    and frame.ToggleLevel) then
    return
end

local panel = frame.WritsView
local inner = Theme.CreatePanelInnerContent(panel)

local UI = {
    PAD = 4,
    ROW_HEIGHT = 20,
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    STATUS_HEIGHT = 22,
    ICON_SIZE = 14,
    -- 626 at the stock window; the fitted widths. A wider window gives the writ column most of the extra and
    -- the money columns a little each, as the Waylaid Crates view does (Data/ColumnFit.lua; FitColumns).
    colWidths = { writ = 190, rep = 36, writPrice = 100, buy = 100, craft = 100, perRep = 100 },
    stockWidths = { writ = 190, rep = 36, writPrice = 100, buy = 100, craft = 100, perRep = 100 },
    flex = { writ = 0.6, writPrice = 0.1, buy = 0.1, craft = 0.1, perRep = 0.1 },
    caps = { writPrice = 140, buy = 140, craft = 140, perRep = 140 },
    sortKeys = W.WRITS_SORT_KEYS,
    sortLabels = { writ = "Craftsman's Writ", rep = "Rep", writPrice = "Writ Price", buy = "Fill via AH",
        craft = "Fill via Craft", perRep = "Total / Rep" },
    sortJustify = { writ = "LEFT", rep = "RIGHT", writPrice = "RIGHT", buy = "RIGHT", craft = "RIGHT",
        perRep = "RIGHT" },
    -- MoneyCells: the coins lined up down the column.
    moneyCols = { writPrice = true, buy = true, craft = true, perRep = true },
    headerButtons = {},
    rowPool = {},
    activeRows = {},
    cache = nil, -- { scan, book }: the decoded scan, kept until a newer one arrives
    classOf = {}, -- character name -> class file (CraftContext.Build)
    WRIT_COLOR = "|cff0070dd", -- the writs are rare items
}

local function TotalColWidth()
    local w = 0
    for _, sk in ipairs(UI.sortKeys) do
        w = w + UI.colWidths[sk]
    end
    return w
end

--- "~" before a cost that rests on an estimate, or on units the auction house is short of.
local function Mark(approx, short)
    return (approx or (short or 0) > 0) and "~" or ""
end

local function ItemIcon(itemID)
    if GetItemIcon then return GetItemIcon(itemID) end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return nil
end

local function WritLabel(row)
    local icon = ItemIcon(row.id)
    local prefix = icon and ("|T" .. icon .. ":" .. UI.ICON_SIZE .. ":" .. UI.ICON_SIZE .. ":0:0|t ") or ""
    local text = prefix .. UI.WRIT_COLOR .. row.short .. "|r"
    if (row.held or 0) > 0 then
        text = text .. " |cffaaaaaa(" .. row.held .. " held)|r"
    end
    return text
end

-- Bottom row, as on the Waylaid view (TabEconomy.lua's CreateScanFooter): the scan's age on the left
-- (coloured by how stale the prices are), the scan button centred while the auction house is open, the
-- automatic scan checkbox on the right.
local footer = frame.CreateScanFooter(inner)
local statusLabel = footer.status
frame.UpdateWritsScanButton = footer.UpdateScanButton

-- No scan of this auction house yet: the Waylaid view's message and checkbox, in place of the table.
local emptyState = frame.CreateEmptyState(inner, "Craftsman's Writ")

-- "Filter" dropdown in the main toolbar row (where the header search sits), parented to this view's panel so
-- it shows only here. Its entries are re-read on every open and toggle.
UI.filter = Theme.CreateFilterDropdown({
    parent = panel,
    text = "Filter",
    getEntries = function()
        local o = W.EnsureOptions()
        -- The levels at the bottom: the writs have no Apprentice level.
        return frame.AddLevelEntries({
            { kind = "checkbox", key = "hideUnavailable", label = "Hide unavailable writs",
                checked = o.writsOnlyAvailable, enabled = true },
            { kind = "checkbox", key = "hideUncraftable", label = "Hide writs I can not fulfill via crafting",
                checked = o.writsOnlyCraftable, enabled = true },
        }, W.WRIT_TIERS, o.writsHiddenTiers, W.WritTierLabel)
    end,
    onToggle = function(key, checked)
        local o = W.EnsureOptions()
        if frame.ToggleLevel(key, checked, o.writsHiddenTiers) then
            if frame.RefreshWrits then frame.RefreshWrits() end
            return
        end
        if key == "hideUncraftable" then
            o.writsOnlyCraftable = checked and true or false
        elseif key == "hideUnavailable" then
            o.writsOnlyAvailable = checked and true or false
        else
            return
        end
        if frame.RefreshWrits then frame.RefreshWrits() end
    end,
})
if UI.filter and AltArmy.PlaceInToolbarRight then
    AltArmy.PlaceInToolbarRight(UI.filter.button, panel, -4) -- off the window's edge
end
panel:HookScript("OnHide", function()
    if UI.filter and UI.filter.Close then UI.filter.Close() end
end)

local headerRow = CreateFrame("Frame", nil, inner)
headerRow:SetHeight(UI.HEADER_HEIGHT)
headerRow:SetWidth(TotalColWidth())
headerRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)

local function UpdateHeaderSortIndicators()
    local o = W.EnsureOptions()
    for _, sk in ipairs(UI.sortKeys) do
        local btn = UI.headerButtons[sk]
        Theme.SetSortHeaderLabel(btn.label, UI.sortLabels[sk], sk == o.writsSortKey, o.writsSortAscending)
    end
end

do
    local hx = 0
    for _, sk in ipairs(UI.sortKeys) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
        btn:SetSize(UI.colWidths[sk], UI.HEADER_HEIGHT)
        btn:RegisterForClicks("LeftButtonUp")
        local key = sk
        btn:SetScript("OnClick", function()
            local o = W.EnsureOptions()
            if o.writsSortKey == key then
                o.writsSortAscending = not o.writsSortAscending
            else
                o.writsSortKey = key
                o.writsSortAscending = true -- money cheapest first; names A-Z
            end
            if frame.RefreshWrits then frame.RefreshWrits() end
        end)
        local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", UI.sortJustify[sk] == "RIGHT" and -4 or 0, 0)
        label:SetHeight(UI.HEADER_HEIGHT)
        label:SetJustifyH(UI.sortJustify[sk])
        btn.label = label
        Theme.BindInteractableHover(btn)
        UI.headerButtons[sk] = btn
        hx = hx + UI.colWidths[sk]
    end
end

local listViewport = CreateFrame("Frame", nil, inner)
listViewport:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP))
listViewport:SetPoint("BOTTOM", statusLabel, "TOP", 0, UI.PAD)
listViewport:SetPoint("RIGHT", panel, "RIGHT", -Theme.VerticalScrollBarGutter(), 0)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    valueStep = UI.ROW_HEIGHT,
    wheelStep = UI.ROW_HEIGHT * 3,
    enableMouseWheel = true,
    childWidth = TotalColWidth(),
})
local scrollChild = viewport.child

headerRow:SetFrameLevel((inner:GetFrameLevel() or 0) + 10)
local headerFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = headerRow,
    scrollFrame = viewport.scroll,
    scrollBar = viewport.scrollBar,
    headerBottomInset = 2,
})
viewport.OnScroll(function()
    if headerFade then headerFade:Update() end
end)

-- The filter left nothing: a message in the empty table.
UI.noRowsLabel = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
UI.noRowsLabel:SetPoint("CENTER", listViewport, "CENTER", 0, 20)
UI.noRowsLabel:SetText("No writs left: the filters hide them all.")
UI.noRowsLabel:Hide()

local function ReleaseRows()
    for i = #UI.activeRows, 1, -1 do
        local row = UI.activeRows[i]
        UI.activeRows[i] = nil
        row:Hide()
        UI.rowPool[#UI.rowPool + 1] = row
    end
end

local function ShowRowTooltip(row)
    local rd = row.rowData
    if not rd then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        ET.SetItem(GameTooltip, rd.id)
    else
        GameTooltip:SetText(rd.name)
    end
    ET.AddWritLines(GameTooltip, rd, { classOf = UI.classOf, scanTime = UI.cache and UI.cache.scan.t,
        summary = UI.cache and UI.cache.scan.summary, now = GetServerTime and GetServerTime() or time(),
        clickHint = true })
    GameTooltip:Show()
end

-- At the auction house with Auctionator: search what the best route buys as a temporary shopping list.
local function OnRowClick(row)
    local rd = row.rowData
    local AZ = AltArmy.AuctionatorSearch
    if rd and AZ and AZ.IsAvailable() then
        AZ.Search(WC.SearchTerms(rd, Writs.ITEMS))
    end
end

local function PoolRow()
    local row = table.remove(UI.rowPool)
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(UI.ROW_HEIGHT)
    Theme.InstallRowHoverHighlight(row)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", OnRowClick)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) viewport.Wheel(delta) end)
    row.cells = {}
    local x = 0
    for _, sk in ipairs(UI.sortKeys) do
        local cell
        if UI.moneyCols[sk] then
            cell = AltArmy.MoneyCell.Create(row, Theme.FONTS.body, UI.colWidths[sk] - 4, UI.ROW_HEIGHT)
        else
            cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            cell:SetWidth(UI.colWidths[sk] - 4)
            cell:SetJustifyH(UI.sortJustify[sk])
            cell:SetWordWrap(false)
        end
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        row.cells[sk] = cell
        x = x + UI.colWidths[sk]
    end
    return row
end

local function CurrentScan()
    local realm = GetRealmName and GetRealmName() or ""
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    return Book.Newest(realm, faction), realm, faction
end

--- The header's buttons and a row's cells at the current column widths.
local function PlaceCells(cells, container, isHeader)
    local x = 0
    for _, sk in ipairs(UI.sortKeys) do
        local cell = cells[sk]
        if cell then
            cell:ClearAllPoints()
            if isHeader then
                cell:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
                cell:SetSize(UI.colWidths[sk], UI.HEADER_HEIGHT)
            else
                cell:SetPoint("LEFT", container, "LEFT", x, 0)
                cell:SetWidth(UI.colWidths[sk] - 4)
            end
        end
        x = x + UI.colWidths[sk]
    end
end

--- Fit the columns to the list's width (what it has beyond the stock total goes to the flex columns; a
--- narrower list keeps the stock widths) and lay the header and every pooled row out again when one moved.
local function FitColumns(width)
    local fitted = AltArmy.ColumnFit.Fit(UI.stockWidths, UI.flex, width, UI.caps)
    local changed = false
    for sk, w in pairs(fitted) do
        if UI.colWidths[sk] ~= w then
            UI.colWidths[sk] = w
            changed = true
        end
    end
    if not changed then return end
    headerRow:SetWidth(TotalColWidth())
    PlaceCells(UI.headerButtons, headerRow, true)
    for _, row in ipairs(UI.rowPool) do PlaceCells(row.cells, row) end
    for _, row in ipairs(UI.activeRows) do PlaceCells(row.cells, row) end
end

local function RefreshWrits()
    ReleaseRows()
    FitColumns(viewport.scroll:GetWidth())
    local scan, realm, faction = CurrentScan()
    if not scan then
        UI.cache = nil
        emptyState.Show(realm, faction)
        footer.Hide()
        headerRow:Hide()
        listViewport:Hide()
        return
    end
    if not UI.cache or UI.cache.scan ~= scan then
        UI.cache = { scan = scan, book = Book.Decode(scan.items) }
    end
    local book = UI.cache.book
    emptyState.Hide()
    headerRow:Show()
    listViewport:Show()
    local ctx
    ctx, UI.classOf = AltArmy.CraftContext.Build(DS, realm, faction, book, Writs)
    local orders = AltArmy.WritOrders and AltArmy.WritOrders.Orders() or nil
    local o = W.EnsureOptions()
    local rows = WC.Filter(WC.BuildRows(book, Writs, orders, ctx),
        { hideUncraftable = o.writsOnlyCraftable, hideUnavailable = o.writsOnlyAvailable,
            hiddenTiers = o.writsHiddenTiers })
    table.sort(rows, function(a, b) return WC.Compare(a, b, o.writsSortKey, o.writsSortAscending) end)
    UpdateHeaderSortIndicators()

    local now = GetServerTime and GetServerTime() or time()
    statusLabel:SetText(W.AgeText(scan.t, now, AltArmy.SummaryData.GetTimeString, scan.summary))
    local level = W.AgeLevel(scan.t, now)
    local color = level == "old" and Theme.COLORS.warningBlocking
        or level == "stale" and Theme.COLORS.warningCaution
        or { 1, 1, 1 }
    statusLabel:SetTextColor(color[1], color[2], color[3], 1)
    footer.Show()
    footer.SetSummary(scan.summary)

    local totalW = TotalColWidth()
    scrollChild:SetSize(totalW, math.max(1, #rows) * UI.ROW_HEIGHT)
    UI.noRowsLabel:SetShown(#rows == 0)
    local y = 0
    for _, rd in ipairs(rows) do
        local row = PoolRow()
        UI.activeRows[#UI.activeRows + 1] = row
        row.rowData = rd
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetWidth(totalW)
        y = y - UI.ROW_HEIGHT
        local c = row.cells
        c.writ:SetText(WritLabel(rd))
        c.writPrice:SetMoney(rd.writPrice)
        c.rep:SetText(tostring(rd.rep))
        c.buy:SetMoney(rd.buy, Mark(rd.buyApprox, rd.buyShort))
        c.craft:SetMoney(rd.craft, Mark(rd.craftApprox, rd.craftShort))
        c.perRep:SetCost(rd.perRep) -- a negative is a gain, in green
    end
    viewport.UpdateRange()
    if headerFade then headerFade:Update() end
end
frame.RefreshWrits = RefreshWrits

-- The columns follow the list's width (the window's resize grip).
viewport.scroll:HookScript("OnSizeChanged", function()
    if panel:IsVisible() then RefreshWrits() end
end)
