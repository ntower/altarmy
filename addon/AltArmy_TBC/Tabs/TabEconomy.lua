-- AltArmy TBC — Economy tab (WoW Forever only): the Currency grid (Tabs/TabEconomyCurrency.lua fills
-- frame.CurrencyView), Waylaid Crates' costs per Merchant's Favor (filled from the Alt Army auction scan or by
-- crafting: Data/Economy/WaylaidCosts.lua, CraftPlan.lua), and the Supply Chain page
-- about alt-army.com (Tabs/TabEconomySupplyChain.lua fills frame.SupplyChainView).
-- luacheck: globals GameTooltip GetItemIcon GetServerTime

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame then return end

local DS = AltArmy.DataStore
if not (DS and DS.IsWowForever) then
    -- Waylaid Crates, the full auction scan and alt-army.com's prices exist only on WoW Forever.
    if AltArmy.MainSideTabs then
        AltArmy.MainSideTabs:SetTabShown("Economy", false)
    end
    frame.SupplyChainView = nil
    frame.CurrencyView = nil
    return
end

local Theme = AltArmy.Theme
local W = AltArmy.WaylaidCosts
local Crates = AltArmy.WaylaidCrates
local Book = AltArmy.AuctionBook
local ET = AltArmy.EconomyTooltip
if not (Theme and W and Crates and Book and ET and AltArmy.ColumnFit) then return end

W.EnsureOptions()

local UI = {
    PAD = 4,
    ROW_HEIGHT = 20,
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    STATUS_HEIGHT = 22, -- fits the scan button
    ICON_SIZE = 14,
    -- Sums to 626: the list viewport's width (window 670, content insets, panel padding, scrollbar gutter).
    -- The same widths as the Craftsman's Writs view's columns. colWidths holds the fitted widths: a wider
    -- window gives the crate column (the text that gets cut off) most of the extra and the money columns a
    -- little each, so their coins stop dropping (Data/ColumnFit.lua; FitColumns).
    colWidths = { crate = 190, favor = 36, price = 100, buy = 100, craft = 100, perFavor = 100 },
    stockWidths = { crate = 190, favor = 36, price = 100, buy = 100, craft = 100, perFavor = 100 },
    flex = { crate = 0.6, price = 0.1, buy = 0.1, craft = 0.1, perFavor = 0.1 },
    caps = { price = 140, buy = 140, craft = 140, perFavor = 140 },
    sortKeys = W.SORT_KEYS,
    sortLabels = nil, -- set below: two name the Merchant's Favor icon
    sortJustify = { crate = "LEFT", favor = "RIGHT", price = "RIGHT", buy = "RIGHT", craft = "RIGHT",
        perFavor = "RIGHT" },
    -- MoneyCells: the coins lined up down the column.
    moneyCols = { price = true, buy = true, craft = true, perFavor = true },
    headerButtons = {},
    rowPool = {},
    activeRows = {},
    cache = nil, -- { scan, book }: the decoded scan, kept until a newer one arrives
    CRAFTED_COLOR = "|cff1eff00",
    GATHERED_COLOR = "|cffffffff",
    classOf = {}, -- character name -> class file (CraftContext.Build)
}

-- Merchant's Favor's icon (UI/EconomyTooltip.lua, which also writes the rows' tooltips).
local FavorIcon = ET.FavorIcon
UI.sortLabels = {
    crate = "Waylaid Crate",
    favor = FavorIcon(),
    price = "Crate Price",
    buy = "Fill via AH",
    craft = "Fill via Craft",
    perFavor = "Total / " .. FavorIcon(),
}

local VIEW = {
    active = "currency",
    tabs = nil,
    defs = {
        -- Forever's CharacterFrame Currency side-tab icon.
        { name = "currency", label = "Currency", icon = "Interface\\Icons\\INV_SideTab_Currency_c60" },
        { name = "waylaid", label = "Waylaid Crates", icon = "Interface\\Icons\\INV_Crate_01" },
        { name = "writs", label = "Craftsman's Writs", icon = "Interface\\Icons\\INV_Scroll_03" },
    },
}
UI.supplyEnabled = AltArmy.FeatureFlags and AltArmy.FeatureFlags.economySupplyChain and true or false
if UI.supplyEnabled then
    VIEW.defs[#VIEW.defs + 1] = { name = "supply", label = "Supply Chain", icon = "Interface\\Icons\\INV_Misc_Map_01" }
end

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
    local icon = GetItemIcon and GetItemIcon(itemID)
    if not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    return icon
end

local function CrateLabel(row)
    local color = row.kind == "Gathered" and UI.GATHERED_COLOR or UI.CRAFTED_COLOR
    local icon = ItemIcon(row.id)
    local prefix = icon and ("|T" .. icon .. ":" .. UI.ICON_SIZE .. ":" .. UI.ICON_SIZE .. "|t ") or ""
    return prefix .. color .. (row.short or row.name) .. "|r"
end

-- Panels: one per sub-view, same anchors; only the active one is shown.
local currencyPanel = Theme.CreateMainContentPanel(frame)
currencyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
currencyPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
local waylaidPanel = Theme.CreateMainContentPanel(frame)
waylaidPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
waylaidPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
-- Behind a feature flag: without the panel, Tabs/TabEconomySupplyChain.lua builds nothing.
local supplyPanel
if UI.supplyEnabled then
    supplyPanel = Theme.CreateMainContentPanel(frame)
    supplyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
    supplyPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
    supplyPanel:Hide()
end
local writsPanel = Theme.CreateMainContentPanel(frame)
writsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.TAB_SECTION_INSET, -Theme.TAB_SECTION_INSET)
writsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.TAB_SECTION_INSET, Theme.TAB_SECTION_INSET)
waylaidPanel:Hide()
writsPanel:Hide()
frame.CurrencyView = currencyPanel
frame.WaylaidView = waylaidPanel
frame.WritsView = writsPanel -- filled by Tabs/TabEconomyWrits.lua, which exports frame.RefreshWrits
frame.SupplyChainView = supplyPanel

local inner = Theme.CreatePanelInnerContent(waylaidPanel)

--- The bottom row the auction house views share (Waylaid Crates, Craftsman's Writs), built on `parent`: scan
--- age on the left (the view sets and colours it), the scan button centred while the auction house is open,
--- the automatic scan checkbox on the right. The button shows only while the age label is shown.
local function CreateScanFooter(parent)
    local footer = {}
    local status = parent:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    status:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    status:SetHeight(UI.STATUS_HEIGHT)
    status:SetJustifyH("LEFT")
    footer.status = status

    -- After a summary scan: an info icon beside the age, and a tooltip over both saying what that means; a
    -- click opens the Options on the scan mode dropdown.
    local info = parent:CreateTexture(nil, "ARTWORK")
    info:SetTexture("Interface\\Common\\help-i")
    info:SetSize(UI.ICON_SIZE, UI.ICON_SIZE)
    info:SetPoint("LEFT", status, "RIGHT", 2, 0)
    info:Hide()
    local hover = CreateFrame("Frame", nil, parent)
    hover:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT", 0, 0)
    hover:SetHeight(UI.STATUS_HEIGHT)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Summary scan", 1, 1, 1)
        GameTooltip:AddLine("A summary scan collects only the lowest price for each item, not how many are "
            .. "listed at each price. As a result, the numbers shown may be too optimistic.",
            0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Click to configure", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hover:SetScript("OnMouseUp", function()
        GameTooltip:Hide()
        if AltArmy.OpenInterfaceOptions then
            AltArmy.OpenInterfaceOptions("general", { flash = "scanMode" })
        end
    end)
    hover:Hide()

    --- Show the info icon and its tooltip when the scan shown is a summary scan.
    function footer.SetSummary(isSummary)
        info:SetShown(isSummary and status:IsShown() and true or false)
        hover:SetShown(info:IsShown())
    end

    -- Same setting as Options → General → Economy. CreateLabeledCheckbox stretches its row to its
    -- parent's right edge: a holder sized to the checkbox and label keeps it right-aligned.
    local holder = CreateFrame("Frame", nil, parent)
    -- clear of the window's resize grip in the corner
    holder:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(AltArmy.WINDOW_GRIP_INSET or 16), 0)
    holder:SetHeight(UI.STATUS_HEIGHT)
    local check = Theme.CreateLabeledCheckbox(holder, {
        point = "LEFT",
        relativeTo = holder,
        relativePoint = "LEFT",
        text = "Auto scan when opening AH",
        onClick = function(checked)
            local S = AltArmy.AuctionScan
            if S and S.SetAutoScanEnabled then S.SetAutoScanEnabled(checked) end
        end,
    })
    holder:SetWidth(Theme.CHAR_LIST_CHECKBOX_SIZE + 2 + check.label:GetStringWidth() + 4)
    footer.autoScanHolder, footer.autoScanCheck = holder, check

    -- While the auction house is open: scan now, or the cooldown left (same text as the auction house button).
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(110, UI.STATUS_HEIGHT)
    btn:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    btn:SetMotionScriptsWhileDisabled(true)
    Theme.SkinButton(btn)
    btn:Hide()
    footer.scanBtn = btn

    function footer.UpdateScanButton()
        local S = AltArmy.AuctionScan
        local Btn = AltArmy.AuctionScanButton
        local show = S and S.HasApi() and S.IsOpen() and Btn and Btn.Label and status:IsShown()
        btn:SetShown(show and true or false)
        if not show then return end
        local text, enabled = Btn.Label(S.State(), S.Progress(), S.CooldownLeft(), S.NextKind() ~= nil)
        btn:SetText(enabled and "Scan now" or text)
        btn:SetEnabled(enabled)
    end

    --- Show the age label and the checkbox (synced with the setting) and update the button.
    function footer.Show()
        status:Show()
        holder:Show()
        local S = AltArmy.AuctionScan
        check.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)
        footer.UpdateScanButton()
    end

    function footer.Hide()
        status:Hide()
        btn:Hide()
        holder:Hide()
        footer.SetSummary(false)
    end

    btn:SetScript("OnClick", function()
        local S = AltArmy.AuctionScan
        if S then S.Start() end
        footer.UpdateScanButton()
    end)
    local elapsed = 0
    btn:SetScript("OnUpdate", function(_, dt) -- the cooldown's countdown
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            footer.UpdateScanButton()
        end
    end)
    return footer
end
frame.CreateScanFooter = CreateScanFooter

local footer = CreateScanFooter(inner)
local statusLabel = footer.status
UI.scanBtn = footer.scanBtn
UI.autoScanHolder = footer.autoScanHolder
UI.autoScanCheck = footer.autoScanCheck
local UpdateScanButton = footer.UpdateScanButton

local headerRow = CreateFrame("Frame", nil, inner)
headerRow:SetHeight(UI.HEADER_HEIGHT)
headerRow:SetWidth(TotalColWidth())
headerRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)

local function UpdateHeaderSortIndicators()
    local o = W.EnsureOptions()
    for _, sk in ipairs(UI.sortKeys) do
        local btn = UI.headerButtons[sk]
        Theme.SetSortHeaderLabel(btn.label, UI.sortLabels[sk], sk == o.waylaidSortKey, o.waylaidSortAscending)
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
            if o.waylaidSortKey == key then
                o.waylaidSortAscending = not o.waylaidSortAscending
            else
                o.waylaidSortKey = key
                -- Money columns start cheapest first; names A-Z.
                o.waylaidSortAscending = true
            end
            if frame.RefreshWaylaid then frame.RefreshWaylaid() end
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
listViewport:SetPoint("RIGHT", waylaidPanel, "RIGHT", -Theme.VerticalScrollBarGutter(), 0)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = waylaidPanel,
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

-- A scan with no Waylaid Crates listed: a message in the empty table.
UI.noCratesLabel = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
UI.noCratesLabel:SetPoint("CENTER", listViewport, "CENTER", 0, 20)
UI.noCratesLabel:SetText("No crates left: the filters hide them all.")
UI.noCratesLabel:Hide()

--- The Filter menu's level checkboxes, appended to `entries` under a divider: one per tier of `tiers`
--- (lowest first), keyed "tier:<tier>", ticked unless named in `hidden` (a set of tier names unticked).
--- Shared with the Craftsman's Writs view (TabEconomyWrits.lua).
local function AddLevelEntries(entries, tiers, hidden)
    entries[#entries + 1] = { kind = "divider", key = "levelsDivider" }
    for _, tier in ipairs(tiers) do
        entries[#entries + 1] = { kind = "checkbox", key = "tier:" .. tier, label = tier,
            checked = not hidden[tier], enabled = true }
    end
    return entries
end
frame.AddLevelEntries = AddLevelEntries

--- A Filter menu toggle of a level checkbox: updates `hidden` and returns true; false for any other key.
local function ToggleLevel(key, checked, hidden)
    local tier = type(key) == "string" and key:match("^tier:(.+)$")
    if not tier then return false end
    hidden[tier] = (not checked) or nil
    return true
end
frame.ToggleLevel = ToggleLevel


-- "Filter" dropdown in the main toolbar row (as on the Craftsman's Writs view), parented to this view's panel
-- so it shows only here. Its entries are re-read on every open and toggle.
UI.filter = Theme.CreateFilterDropdown({
    parent = waylaidPanel,
    text = "Filter",
    getEntries = function()
        local o = W.EnsureOptions()
        return AddLevelEntries({
            { kind = "checkbox", key = "hideUnavailable", label = "Hide unavailable crates",
                checked = o.waylaidOnlyAvailable, enabled = true },
            { kind = "checkbox", key = "hideUncraftable", label = "Hide crates I can not fulfill via crafting",
                checked = o.waylaidOnlyCraftable, enabled = true },
        }, W.CRATE_TIERS, o.waylaidHiddenTiers)
    end,
    onToggle = function(key, checked)
        local o = W.EnsureOptions()
        if ToggleLevel(key, checked, o.waylaidHiddenTiers) then
            if frame.RefreshWaylaid then frame.RefreshWaylaid() end
            return
        end
        if key == "hideUnavailable" then
            o.waylaidOnlyAvailable = checked and true or false
        elseif key == "hideUncraftable" then
            o.waylaidOnlyCraftable = checked and true or false
        else
            return
        end
        if frame.RefreshWaylaid then frame.RefreshWaylaid() end
    end,
})
if UI.filter and AltArmy.PlaceInToolbarRight then
    AltArmy.PlaceInToolbarRight(UI.filter.button, waylaidPanel, -4) -- off the window's edge
end
waylaidPanel:HookScript("OnHide", function()
    if UI.filter and UI.filter.Close then UI.filter.Close() end
end)

-- No scan of this auction house yet: a message and the automatic scan checkbox, in place of the table.
-- `what` names what the view prices ("Waylaid Crate"; the Writs view builds one too, TabEconomyWrits.lua).
local function CreateEmptyState(parent, what)
    local empty = CreateFrame("Frame", nil, parent)
    empty:SetSize(440, 120)
    empty:SetPoint("CENTER", parent, "CENTER", 0, 20)
    local label = empty:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
    label:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(true)
    -- CreateLabeledCheckbox stretches its row to its parent's right edge: give it a narrow holder to center.
    local checkHolder = CreateFrame("Frame", nil, empty)
    checkHolder:SetSize(340, Theme.CHAR_LIST_ROW_HEIGHT)
    checkHolder:SetPoint("TOP", label, "BOTTOM", 0, -18)
    local autoScanRow = Theme.CreateLabeledCheckbox(checkHolder, {
        point = "TOPLEFT",
        relativeTo = checkHolder,
        relativePoint = "TOPLEFT",
        text = "Scan the auction house automatically when it opens",
        onClick = function(checked)
            local S = AltArmy.AuctionScan
            if S and S.SetAutoScanEnabled then S.SetAutoScanEnabled(checked) end
        end,
    })
    empty:Hide()

    local state = {}
    --- Show the message for this realm and faction, the checkbox synced with the setting.
    function state.Show(realm, faction)
        local S = AltArmy.AuctionScan
        label:SetText("No auction house scan yet for " .. realm .. " (" .. faction .. ").\n\n"
            .. "Visit an auction house and press the Alt Army scan button to see what each " .. what
            .. " costs to buy and fill.")
        autoScanRow.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)
        empty:Show()
    end
    function state.Hide()
        empty:Hide()
    end
    return state
end
frame.CreateEmptyState = CreateEmptyState

local emptyState = CreateEmptyState(inner, "Waylaid Crate")

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
    ET.AddCrateLines(GameTooltip, rd, { classOf = UI.classOf, scanTime = UI.cache and UI.cache.scan.t,
        summary = UI.cache and UI.cache.scan.summary, now = GetServerTime and GetServerTime() or time(),
        clickHint = true })
    GameTooltip:Show()
end

-- At the auction house with Auctionator: search the crate and both ways to fill it (bought and crafted, the
-- cheaper first) as a temporary shopping list.
local function OnRowClick(row)
    local rd = row.rowData
    local AZ = AltArmy.AuctionatorSearch
    if rd and AZ and AZ.IsAvailable() then
        AZ.Search(W.SearchTerms(rd, Crates.ITEMS))
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
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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

local function ShowEmpty(realm, faction)
    emptyState.Show(realm, faction)
    footer.Hide()
    headerRow:Hide()
    listViewport:Hide()
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

local function RefreshWaylaid()
    ReleaseRows()
    FitColumns(viewport.scroll:GetWidth())
    local scan, realm, faction = CurrentScan()
    if not scan then
        UI.cache = nil
        ShowEmpty(realm, faction)
        return
    end
    if not UI.cache or UI.cache.scan ~= scan then
        UI.cache = { scan = scan, book = Book.Decode(scan.items) }
    end
    emptyState.Hide()
    statusLabel:Show()
    UI.autoScanHolder:Show()
    headerRow:Show()
    listViewport:Show()

    local o = W.EnsureOptions()
    local ctx
    if AltArmy.CraftContext and AltArmy.CraftPlan then
        ctx, UI.classOf = AltArmy.CraftContext.Build(DS, realm, faction, UI.cache.book, Crates)
    end
    local rows = W.FilterRows(W.BuildRows(UI.cache.book, Crates, scan.summary, ctx),
        { hideUnavailable = o.waylaidOnlyAvailable, hideUncraftable = o.waylaidOnlyCraftable,
            hiddenTiers = o.waylaidHiddenTiers })
    table.sort(rows, function(a, b) return W.Compare(a, b, o.waylaidSortKey, o.waylaidSortAscending) end)
    UpdateHeaderSortIndicators()

    local now = GetServerTime and GetServerTime() or time()
    statusLabel:SetText(W.AgeText(scan.t, now, AltArmy.SummaryData.GetTimeString, scan.summary))
    footer.SetSummary(scan.summary)
    local level = W.AgeLevel(scan.t, now)
    local ageColor = level == "old" and Theme.COLORS.warningBlocking
        or level == "stale" and Theme.COLORS.warningCaution
        or { 1, 1, 1 }
    statusLabel:SetTextColor(ageColor[1], ageColor[2], ageColor[3], 1)
    UpdateScanButton()
    local S = AltArmy.AuctionScan
    UI.autoScanCheck.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)

    local totalW = TotalColWidth()
    scrollChild:SetSize(totalW, math.max(1, #rows) * UI.ROW_HEIGHT)
    UI.noCratesLabel:SetShown(#rows == 0)
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
        c.crate:SetText(CrateLabel(rd))
        c.favor:SetText(rd.favor and tostring(rd.favor) or "—")
        c.price:SetMoney(rd.price)
        c.buy:SetMoney(rd.buy, Mark(rd.buyApprox))
        c.craft:SetMoney(rd.craft, Mark(rd.craftApprox, rd.craftShort))
        if rd.perFavor then
            c.perFavor:SetMoney(rd.perFavor)
            c.perFavor:SetTextColor(1, 1, 1, 1)
        else
            c.perFavor:SetText("—")
            c.perFavor:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
    viewport.UpdateRange()
    if headerFade then headerFade:Update() end
end
frame.RefreshWaylaid = RefreshWaylaid

-- The columns follow the list's width (the window's resize grip).
viewport.scroll:HookScript("OnSizeChanged", function()
    if waylaidPanel:IsVisible() then RefreshWaylaid() end
end)

local function SetActiveEconomyView(which)
    if not W.VIEWS[which] or (which == "supply" and not supplyPanel) then
        which = "currency"
    end
    VIEW.active = which
    W.EnsureOptions().activeView = which
    if which ~= "currency" and frame.HideEconomySettings then
        frame.HideEconomySettings()
    end
    currencyPanel:SetShown(which == "currency")
    waylaidPanel:SetShown(which == "waylaid")
    writsPanel:SetShown(which == "writs")
    if supplyPanel then supplyPanel:SetShown(which == "supply") end
    if VIEW.tabs then
        VIEW.tabs:SetSelected(which)
    end
    if which == "currency" then
        if frame.RefreshCurrency then frame.RefreshCurrency() end
    elseif which == "waylaid" then
        RefreshWaylaid()
    elseif which == "writs" then
        if frame.RefreshWrits then frame.RefreshWrits() end
    elseif frame.LayoutSupplyChain then
        frame.LayoutSupplyChain()
    end
    -- The toolbar settings button belongs to the Currency view only.
    if AltArmy.UpdateSearchSettingsButtonGlow then AltArmy.UpdateSearchSettingsButtonGlow() end
end
frame.GetEconomyView = function() return VIEW.active end
frame.SetEconomyView = SetActiveEconomyView

-- Sub-view tabs hang from the panel top into the main window's toolbar row (as on Gear and Cooldowns).
VIEW.tabs = AltArmy.TopTabs.Create(frame, VIEW.defs, {
    mainTab = "Economy",
    onSelect = function(id)
        if VIEW.active ~= id then
            SetActiveEconomyView(id)
        end
    end,
})
VIEW.tabs.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)
frame.ViewTabs = VIEW.tabs -- `/alta <tab> <view>` opens only the views that have a tab (Core.lua)

frame:SetScript("OnShow", function()
    SetActiveEconomyView(W.EnsureOptions().activeView)
end)

-- A finished scan (ours or another addon's) fills the table while it is open.
do
    local S = AltArmy.AuctionScan
    if S and S.OnChange then
        S.OnChange(function(state)
            -- Idle also follows the auction house opening or closing (the scan button comes and goes).
            if not frame:IsShown() then return end
            if writsPanel:IsShown() then
                if state == "idle" then
                    if frame.RefreshWrits then frame.RefreshWrits() end
                elseif frame.UpdateWritsScanButton then
                    frame.UpdateWritsScanButton()
                end
                return
            end
            if not waylaidPanel:IsShown() then return end
            if state == "idle" then
                RefreshWaylaid()
            else
                UpdateScanButton()
            end
        end)
    end
end
