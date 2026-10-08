-- AltArmy TBC — Economy tab (WoW Forever only): the Currency grid (Tabs/TabEconomyCurrency.lua fills
-- frame.CurrencyView), Waylaid Crates' costs per Merchant's Favor (filled from the Alt Army auction scan or by
-- crafting: Data/Economy/WaylaidCosts.lua, CraftPlan.lua), and the Supply Chain page
-- about alt-army.com (Tabs/TabEconomySupplyChain.lua fills frame.SupplyChainView).
-- luacheck: globals GameTooltip GetItemIcon GetServerTime C_CurrencyInfo

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
if not (Theme and W and Crates and Book) then return end

W.EnsureOptions()

local UI = {
    PAD = 4,
    ROW_HEIGHT = 20,
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    STATUS_HEIGHT = 22, -- fits the scan button
    ICON_SIZE = 14,
    -- Sums to 626: the list viewport's width (window 670, content insets, panel padding, scrollbar gutter).
    -- The same widths as the Craftsman's Writs view's columns.
    colWidths = { crate = 190, favor = 36, price = 100, buy = 100, craft = 100, perFavor = 100 },
    sortKeys = W.SORT_KEYS,
    sortLabels = nil, -- set below: two name the Merchant's Favor icon
    sortJustify = { crate = "LEFT", favor = "RIGHT", price = "RIGHT", buy = "RIGHT", craft = "RIGHT",
        perFavor = "RIGHT" },
    headerButtons = {},
    rowPool = {},
    activeRows = {},
    cache = nil, -- { scan, book }: the decoded scan, kept until a newer one arrives
    CRAFTED_COLOR = "|cff1eff00",
    GATHERED_COLOR = "|cffffffff",
    -- The tooltip's greyed-out text (the dearer way, the bundles not picked): as dark as its hints.
    DIM = 0.5,
    DIM_CODE = "|cff808080",
    classOf = {}, -- character name -> class file (CraftContext.Build)
}

-- Merchant's Favor (currency 3402): its icon from the game, else the one Forever gives it.
local FAVOR_CURRENCY, FAVOR_ICON = 3402, 135725
local function FavorIcon()
    local CI = C_CurrencyInfo
    local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(FAVOR_CURRENCY)
    local icon = info and info.iconFileID or FAVOR_ICON
    return "|T" .. icon .. ":" .. UI.ICON_SIZE .. ":" .. UI.ICON_SIZE .. ":0:0|t"
end
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

local function Money(copper)
    if copper == nil then return "—" end
    if copper < 0 then return "-" .. AltArmy.SummaryData.GetMoneyString(-copper) end
    return AltArmy.SummaryData.GetMoneyString(copper)
end

--- A cost that rests on an estimate, or on units the auction house is short of, with a ~ before it.
local function MoneyMarked(copper, approx, short)
    if copper == nil then return "—" end
    local text = Money(copper)
    if approx or (short or 0) > 0 then text = "~" .. text end
    return text
end

--- A character's name in their class colour (white when their class isn't known).
local function CharName(name)
    local CC = AltArmy.ClassColor
    if not CC then return name end
    return CC.formatName(name, UI.classOf[name])
end

local function ItemName(itemID)
    local entry = Crates.ITEMS and Crates.ITEMS[itemID]
    return entry and entry.name or ("item " .. tostring(itemID))
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

    -- Same setting as Options → General → Auction House. CreateLabeledCheckbox stretches its row to its
    -- parent's right edge: a holder sized to the checkbox and label keeps it right-aligned.
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
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
        btn.label:SetText(Theme.FormatSortHeaderLabel(UI.sortLabels[sk], sk == o.waylaidSortKey,
            o.waylaidSortAscending))
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

-- "Filter" dropdown in the main toolbar row (as on the Craftsman's Writs view), parented to this view's panel
-- so it shows only here. Its entries are re-read on every open and toggle.
UI.filter = Theme.CreateFilterDropdown({
    parent = waylaidPanel,
    text = "Filter",
    getEntries = function()
        local o = W.EnsureOptions()
        return {
            { kind = "checkbox", key = "hideUnavailable", label = "Hide unavailable crates",
                checked = o.waylaidOnlyAvailable, enabled = true },
            { kind = "checkbox", key = "hideUncraftable", label = "Hide crates I can not fulfill via crafting",
                checked = o.waylaidOnlyCraftable, enabled = true },
        }
    end,
    onToggle = function(key, checked)
        local o = W.EnsureOptions()
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
local empty = CreateFrame("Frame", nil, inner)
empty:SetSize(440, 120)
empty:SetPoint("CENTER", inner, "CENTER", 0, 20)
local emptyLabel = empty:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
emptyLabel:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
emptyLabel:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, 0)
emptyLabel:SetJustifyH("CENTER")
emptyLabel:SetWordWrap(true)
-- CreateLabeledCheckbox stretches its row to its parent's right edge: give it a narrow holder to center.
local checkHolder = CreateFrame("Frame", nil, empty)
checkHolder:SetSize(340, Theme.CHAR_LIST_ROW_HEIGHT)
checkHolder:SetPoint("TOP", emptyLabel, "BOTTOM", 0, -18)
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

local function ReleaseRows()
    for i = #UI.activeRows, 1, -1 do
        local row = UI.activeRows[i]
        UI.activeRows[i] = nil
        row:Hide()
        UI.rowPool[#UI.rowPool + 1] = row
    end
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

--- A step's tooltip line: its text, and its cost (nil for a craft: it costs nothing more). Counts read "3x"
--- (a craft's is its casts).
local function StepText(step)
    local name = ItemName(step.item)
    if step.kind == "craft" then
        return "Craft " .. step.casts .. "x " .. name .. " on " .. CharName(step.who), nil
    end
    local left = "Buy " .. step.qty .. "x " .. name
    if step.kind == "vendor" then
        left = left .. " from a vendor on " .. CharName(step.who)
    else
        left = left .. " on the auction house"
    end
    return left, MoneyMarked(step.cost, step.approx, step.short)
end

--- A bundle's tooltip line: what it costs on the auction house and to craft, or why it can't be had.
--- With both prices, the dearer one is grey (a tie greys the craft, as on the fulfil lines).
local function BundleText(opt)
    local GREY = UI.DIM_CODE
    local both = opt.cost and opt.craft
    local parts = {}
    if opt.cost then
        local text = "AH " .. MoneyMarked(opt.cost, opt.approx)
        if both and opt.best ~= "buy" then text = GREY .. text .. "|r" end
        parts[#parts + 1] = text
    elseif opt.listed > 0 then
        parts[#parts + 1] = "only " .. opt.listed .. " listed"
    else
        parts[#parts + 1] = "not listed"
    end
    if opt.craft then
        local text = "craft " .. MoneyMarked(opt.craft, opt.craftApprox, opt.craftShort)
        if both and opt.best ~= "craft" then text = GREY .. text .. "|r" end
        parts[#parts + 1] = text
    end
    return table.concat(parts, ", ")
end

--- Over a guessed reward's Favor cell: what the guess is.
local function ShowGuessTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText("Educated Guess")
    GameTooltip:AddLine("This early into Forever, we don't have reliable information on how much this rewards. "
        .. "Alt Army will be updated as the game matures.", 1, 1, 1, true)
    GameTooltip:Show()
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
    if rd.favor then
        GameTooltip:AddDoubleLine("Turn-in reward", rd.favor .. " " .. FavorIcon() .. " and " .. Money(rd.goldBack),
            1, 0.82, 0, 1, 1, 1)
    end
    AddCostLine("Crate on the auction house", rd.price and Money(rd.price))
    if rd.random then
        GameTooltip:AddLine("Its shipment is random until you read the label, so there is no fill cost.",
            0.7, 0.7, 0.7, true)
    else
        -- With both ways priced, the dearer line is grey, label and cost (a tie greys the craft: the row buys);
        -- its crafter's name then loses the class colour, which would show through the grey.
        local both = rd.buy and rd.craft
        local buyC = both and rd.best ~= "buy" and UI.DIM or 1
        local craftC = both and rd.best ~= "craft" and UI.DIM or 1
        if rd.buy then
            GameTooltip:AddDoubleLine("Fill via AH", MoneyMarked(rd.buy, rd.buyApprox), buyC, buyC, buyC,
                buyC, buyC, buyC)
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
        if rd.total then
            GameTooltip:AddDoubleLine("Total cost", Money(rd.total), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Total cost per " .. FavorIcon(), Money(rd.perFavor), 1, 0.82, 0, 1, 1, 1)
        end
        if #rd.options > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Fill it with any one of these bundles:", 1, 0.82, 0)
            for _, opt in ipairs(rd.options) do
                local left = opt.count .. " x " .. opt.name
                -- Only the cheapest bundle is white: the others are grey, name and costs.
                local right = BundleText(opt)
                local c = opt == rd.bundle and 1 or UI.DIM
                GameTooltip:AddDoubleLine(left, right, c, c, c, c, c, c)
            end
        end
        if rd.best == "craft" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("To craft " .. rd.bundle.count .. "x " .. rd.bundle.name .. ":", 1, 0.82, 0)
            for _, step in ipairs(rd.steps or {}) do
                local left, right = StepText(step)
                if right then
                    GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
                else
                    GameTooltip:AddLine(left, 1, 1, 1)
                end
            end
        end
        if rd.best == "craft" and (rd.craftShort or 0) > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("~ " .. rd.craftShort .. " unit(s) are not listed: priced at the dearest listing.",
                0.9, 0.6, 0.2, true)
        end
    end
    local AZ = AltArmy.AuctionatorSearch
    if AZ and AZ.IsAvailable() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to search with Auctionator", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- At the auction house with Auctionator: search the crate and what its cheapest fill buys as a temporary
-- shopping list.
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
    -- While hovered, the tooltip follows the cursor: over a guessed reward's Favor cell it explains the guess
    -- (a check per frame, only while this row is under the mouse; a child frame there would take the row's
    -- highlight, click and wheel).
    local function onUpdate(self)
        local cell = self.cells.favor
        local guess = self.rowData and self.rowData.favorGuess and cell.IsMouseOver and cell:IsMouseOver() or false
        if guess ~= self.overGuess then
            self.overGuess = guess
            if guess then ShowGuessTooltip(self) else ShowRowTooltip(self) end
        end
    end
    row:SetScript("OnEnter", function(self)
        self.overGuess = nil
        self:SetScript("OnUpdate", onUpdate)
        onUpdate(self)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
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

local function ShowEmpty(realm, faction)
    local S = AltArmy.AuctionScan
    emptyLabel:SetText("No auction house scan yet for " .. realm .. " (" .. faction .. ").\n\n"
        .. "Visit an auction house and press the Alt Army scan button above it (or type /altarmy scan) "
        .. "to see what each Waylaid Crate costs to buy and fill.")
    autoScanRow.check:SetChecked(S and S.IsAutoScanEnabled and S.IsAutoScanEnabled() or false)
    empty:Show()
    statusLabel:Hide()
    footer.SetSummary(false)
    UI.scanBtn:Hide()
    UI.autoScanHolder:Hide()
    headerRow:Hide()
    listViewport:Hide()
end

local function RefreshWaylaid()
    ReleaseRows()
    local scan, realm, faction = CurrentScan()
    if not scan then
        UI.cache = nil
        ShowEmpty(realm, faction)
        return
    end
    if not UI.cache or UI.cache.scan ~= scan then
        UI.cache = { scan = scan, book = Book.Decode(scan.items) }
    end
    empty:Hide()
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
        { hideUnavailable = o.waylaidOnlyAvailable, hideUncraftable = o.waylaidOnlyCraftable })
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
        c.favor:SetText(rd.favor and (rd.favor .. (rd.favorGuess and "?" or "")) or "—")
        c.price:SetText(Money(rd.price))
        c.buy:SetText(MoneyMarked(rd.buy, rd.buyApprox))
        c.craft:SetText(MoneyMarked(rd.craft, rd.craftApprox, rd.craftShort))
        if rd.perFavor then
            c.perFavor:SetText(Money(rd.perFavor))
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
