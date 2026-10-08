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
if not (Theme and W and WC and Writs and Book and DS and AltArmy.CraftPlan and AltArmy.CraftContext
    and frame.CreateScanFooter) then return end

local panel = frame.WritsView
local inner = Theme.CreatePanelInnerContent(panel)

local UI = {
    PAD = 4,
    ROW_HEIGHT = 20,
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    STATUS_HEIGHT = 22,
    ICON_SIZE = 14,
    colWidths = { writ = 190, rep = 36, writPrice = 100, buy = 100, craft = 100, perRep = 100 }, -- 626
    sortKeys = W.WRITS_SORT_KEYS,
    sortLabels = { writ = "Craftsman's Writ", rep = "Rep", writPrice = "Writ Price", buy = "Fill via AH",
        craft = "Fill via Craft", perRep = "Total / Rep" },
    sortJustify = { writ = "LEFT", rep = "RIGHT", writPrice = "RIGHT", buy = "RIGHT", craft = "RIGHT",
        perRep = "RIGHT" },
    headerButtons = {},
    rowPool = {},
    activeRows = {},
    cache = nil, -- { scan, book }: the decoded scan, kept until a newer one arrives
    classOf = {}, -- character name -> class file (CraftContext.Build)
    WRIT_COLOR = "|cff0070dd", -- the writs are rare items
    -- The tooltip's greyed-out text (the dearer way to fulfil): as dark as its hints, as on the Waylaid view.
    DIM = 0.5,
}

local function TotalColWidth()
    local w = 0
    for _, sk in ipairs(UI.sortKeys) do
        w = w + UI.colWidths[sk]
    end
    return w
end

local function Money(copper)
    if copper == nil then return "—" end
    return AltArmy.SummaryData.GetMoneyString(copper)
end

--- A cost that rests on an estimate, or on units the auction house is short of, with a ~ before it.
local function MoneyMarked(copper, approx, short)
    if copper == nil then return "—" end
    local text = Money(copper)
    if approx or (short or 0) > 0 then text = "~" .. text end
    return text
end

local function ItemIcon(itemID)
    if GetItemIcon then return GetItemIcon(itemID) end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return nil
end

local function ItemName(itemID)
    local entry = Writs.ITEMS[itemID]
    return entry and entry.name or ("item " .. tostring(itemID))
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

-- "Filter" dropdown in the main toolbar row (where the header search sits), parented to this view's panel so
-- it shows only here. Its entries are re-read on every open and toggle.
UI.filter = Theme.CreateFilterDropdown({
    parent = panel,
    text = "Filter",
    getEntries = function()
        local o = W.EnsureOptions()
        return {
            { kind = "checkbox", key = "hideUnavailable", label = "Hide unavailable writs",
                checked = o.writsOnlyAvailable, enabled = true },
            { kind = "checkbox", key = "hideUncraftable", label = "Hide writs I can not fulfill via crafting",
                checked = o.writsOnlyCraftable, enabled = true },
        }
    end,
    onToggle = function(key, checked)
        local o = W.EnsureOptions()
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
        btn.label:SetText(Theme.FormatSortHeaderLabel(UI.sortLabels[sk], sk == o.writsSortKey, o.writsSortAscending))
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

--- A character's name in their class colour (white when their class isn't known).
local function CharName(name)
    local CC = AltArmy.ClassColor
    if not CC then return name end
    return CC.formatName(name, UI.classOf[name])
end

--- A step's tooltip line: its text, and its cost (nil for a craft: it costs nothing more). Counts read "3x"
--- (a craft's is its casts). `plain`: names without their class colour (a greyed-out line).
local function StepText(step, plain)
    local name = ItemName(step.item)
    local who = plain and step.who or CharName(step.who)
    if step.kind == "craft" then
        return "Craft " .. step.casts .. "x " .. name .. " on " .. who, nil
    end
    local left = "Buy " .. step.qty .. "x " .. name
    if step.kind == "vendor" then
        left = left .. " from a vendor on " .. who
    else
        left = left .. " on the auction house"
    end
    return left, MoneyMarked(step.cost, step.approx, step.short)
end

--- A tooltip cost line: the cost in white, or "n/a" in grey when there is none.
local function AddCostLine(label, cost)
    if cost then
        GameTooltip:AddDoubleLine(label, cost, 1, 1, 1, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine(label, "n/a", 1, 1, 1, 0.7, 0.7, 0.7)
    end
end

--- A fulfil line with no way to fulfil that way: label and "n/a" both grey, as a dearer way's line is.
local function AddUnavailableLine(label)
    GameTooltip:AddDoubleLine(label, "n/a", UI.DIM, UI.DIM, UI.DIM, UI.DIM, UI.DIM, UI.DIM)
end

local function ShowRowTooltip(row)
    local rd = row.rowData
    if not rd then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(rd.id)
    else
        GameTooltip:SetText(rd.name)
    end
    GameTooltip:AddLine(" ")
    local wants = "Wants " .. rd.count .. "x " .. ItemName(rd.item)
    GameTooltip:AddLine(wants, 1, 0.82, 0, true)
    GameTooltip:AddDoubleLine(rd.tier .. " writ", "+" .. rd.rep .. " reputation", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    AddCostLine("Writ on the auction house", rd.writPrice and Money(rd.writPrice))
    -- With both ways priced, the dearer line is grey, label and cost (a tie greys the craft: the writ buys),
    -- and so are the craft's steps when crafting is the dearer way; a greyed line's names lose their class
    -- colour, which would show through the grey.
    local both = rd.buy and rd.craft
    local buyC = both and rd.best ~= "buy" and UI.DIM or 1
    local craftC = both and rd.best ~= "craft" and UI.DIM or 1
    if rd.buy then
        GameTooltip:AddDoubleLine("Fill via AH", MoneyMarked(rd.buy, rd.buyApprox, rd.buyShort),
            buyC, buyC, buyC, buyC, buyC, buyC)
    else
        AddUnavailableLine("Fill via AH")
    end
    if rd.craft then
        local who = craftC < 1 and rd.who or CharName(rd.who)
        GameTooltip:AddDoubleLine("Fill via craft on " .. who,
            MoneyMarked(rd.craft, rd.craftApprox, rd.craftShort), craftC, craftC, craftC, craftC, craftC, craftC)
    else
        AddUnavailableLine("Fill via craft")
    end
    if rd.bestCost and rd.writPrice then
        GameTooltip:AddDoubleLine("Total cost", Money(rd.bestCost + rd.writPrice), 1, 0.82, 0, 1, 1, 1)
        if rd.perRep then
            GameTooltip:AddDoubleLine("Total cost per rep", Money(rd.perRep), 1, 0.82, 0, 1, 1, 1)
        end
    end
    if rd.craft then
        GameTooltip:AddLine(" ")
        local r, g, b = 1, 0.82, 0
        if craftC < 1 then r, g, b = craftC, craftC, craftC end
        GameTooltip:AddLine("To craft " .. rd.count .. "x " .. ItemName(rd.item) .. ":", r, g, b)
        for _, step in ipairs(rd.steps or {}) do
            local left, right = StepText(step, craftC < 1)
            if right then
                GameTooltip:AddDoubleLine(left, right, craftC, craftC, craftC, craftC, craftC, craftC)
            else
                GameTooltip:AddLine(left, craftC, craftC, craftC)
            end
        end
    end
    local short = (rd.best == "craft" and rd.craftShort or rd.buyShort) or 0
    if short > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("~ " .. short .. " unit(s) are not listed: priced at the dearest listing.",
            0.9, 0.6, 0.2, true)
    elseif rd.best and (rd.best == "craft" and rd.craftApprox or rd.buyApprox) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("~ An estimate: the scan folded the dearer listings together.", 0.9, 0.6, 0.2, true)
    end
    local AZ = AltArmy.AuctionatorSearch
    if AZ and AZ.IsAvailable() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to search with Auctionator", 0.5, 0.5, 0.5)
    end
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
        local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        cell:SetWidth(UI.colWidths[sk] - 4)
        cell:SetJustifyH(UI.sortJustify[sk])
        cell:SetWordWrap(false)
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

local function RefreshWrits()
    ReleaseRows()
    local scan, realm, faction = CurrentScan()
    local book = {}
    if scan then
        if not UI.cache or UI.cache.scan ~= scan then
            UI.cache = { scan = scan, book = Book.Decode(scan.items) }
        end
        book = UI.cache.book
    else
        UI.cache = nil
    end
    local ctx
    ctx, UI.classOf = AltArmy.CraftContext.Build(DS, realm, faction, book, Writs)
    local orders = AltArmy.WritOrders and AltArmy.WritOrders.Orders() or nil
    local o = W.EnsureOptions()
    local rows = WC.Filter(WC.BuildRows(book, Writs, orders, ctx),
        { hideUncraftable = o.writsOnlyCraftable, hideUnavailable = o.writsOnlyAvailable })
    table.sort(rows, function(a, b) return WC.Compare(a, b, o.writsSortKey, o.writsSortAscending) end)
    UpdateHeaderSortIndicators()

    local color = { 1, 1, 1 }
    if scan then
        local now = GetServerTime and GetServerTime() or time()
        statusLabel:SetText(W.AgeText(scan.t, now, AltArmy.SummaryData.GetTimeString, scan.summary))
        local level = W.AgeLevel(scan.t, now)
        color = level == "old" and Theme.COLORS.warningBlocking
            or level == "stale" and Theme.COLORS.warningCaution
            or color
    else
        -- Short, to leave the middle to the scan button: the docs and the empty cells say the rest.
        statusLabel:SetText("No scan yet: vendor and craft routes only")
        color = Theme.COLORS.warningCaution
    end
    statusLabel:SetTextColor(color[1], color[2], color[3], 1)
    footer.Show()
    footer.SetSummary(scan and scan.summary)

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
        c.writPrice:SetText(Money(rd.writPrice))
        c.rep:SetText(tostring(rd.rep))
        c.buy:SetText(MoneyMarked(rd.buy, rd.buyApprox, rd.buyShort))
        c.craft:SetText(MoneyMarked(rd.craft, rd.craftApprox, rd.craftShort))
        if rd.perRep then
            c.perRep:SetText(Money(rd.perRep))
            c.perRep:SetTextColor(1, 1, 1, 1)
        else
            c.perRep:SetText("—")
            c.perRep:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
    viewport.UpdateRange()
    if headerFade then headerFade:Update() end
end
frame.RefreshWrits = RefreshWrits
