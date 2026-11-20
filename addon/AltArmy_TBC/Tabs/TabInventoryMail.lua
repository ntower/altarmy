-- AltArmy TBC — Inventory tab, Mail view: fills frame.MailView with one character's mailbox as last seen
-- (and mail predicted from sends and returns). Two layouts: "rows", like the stock inbox, one row per
-- message with its attachment icons, subject, sender, gold and time left; or "grid", the attachments as
-- item slots. Messages: Data/Inventory/InventoryLayout.lua (MailMessages); slots: UI/ItemSlotButton.lua.
-- luacheck: globals GameTooltip

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Inventory
if not frame or not frame.MailView then return end

local DS = AltArmy.DataStore
local Theme = AltArmy.Theme
local IO = AltArmy.InventoryOptions
local IL = AltArmy.InventoryLayout
local ISB = AltArmy.ItemSlotButton
local SD = AltArmy.SummaryData
local PendingIcons = AltArmy.PendingItemIcons
local ColumnFit = AltArmy.ColumnFit
if not (DS and Theme and IO and IL and ISB and SD and PendingIcons and ColumnFit) then return end

local panel = frame.MailView

local UI = {
    HEADER_HEIGHT = 20,
    HEADER_ROW_GAP = 3,
    ROW_HEIGHT = 40, -- one line of attachment icons
    ROW_PAD = 4,
    ICON = 32,
    ICON_GAP = 2,
    ICONS_PER_LINE = 6,
    SLOT = ISB.SIZE,
    GAP = ISB.SPACING,
    STATUS_HEIGHT = 20,
    FOOTER_RIGHT_MARGIN = AltArmy.WINDOW_GRIP_INSET or 16, -- clear of the window's resize grip
    FALLBACK_WIDTH = 600,
    -- Sums to 626 at the stock window size (the list viewport's width; see Tabs/TabEconomy.lua). Money and
    -- Expires are fixed; Items, Subject and From share what a wider window adds (FitColumns, through
    -- Data/ColumnFit.lua), Items in whole icons so more attachments fit a line (IconsPerLine).
    -- colWidths holds the fitted widths, stockWidths the stock ones.
    colWidths = { items = 204, subject = 152, sender = 110, money = 100, expires = 60 },
    stockWidths = { items = 204, subject = 152, sender = 110, money = 100, expires = 60 },
    stretchShare = { items = 0.5, subject = 0.3, sender = 0.2 },
    colKeys = { "items", "subject", "sender", "money", "expires" },
    colLabels = { items = "Items", subject = "Subject", sender = "From", money = "Money", expires = "Expires" },
    colJustify = { items = "LEFT", subject = "LEFT", sender = "LEFT", money = "LEFT", expires = "LEFT" },
    sortable = { subject = true, sender = true, money = true, expires = true },
    GRAY = { 0.6, 0.6, 0.6 },
    COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01", -- the inbox's money icon (DataStoreMail)
    GOLD_ROW_GAP = 20, -- between the item grid and the gold line
    DIVIDER_HEIGHT = 24, -- the "Does not match search" row between the search's matches and the rest
    NO_MATCH_TEXT = "Does not match search",
}

local state = { rows = {}, rowPool = {} }

local function TotalColWidth()
    local w = 0
    for _, key in ipairs(UI.colKeys) do w = w + UI.colWidths[key] end
    return w
end

local inner = Theme.CreatePanelInnerContent(panel)

local status = inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
status:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 0, 0)
status:SetHeight(UI.STATUS_HEIGHT)
status:SetJustifyH("LEFT")
local money = inner:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
money:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -UI.FOOTER_RIGHT_MARGIN, 0)
money:SetHeight(UI.STATUS_HEIGHT)
money:SetJustifyH("RIGHT")
status:SetPoint("RIGHT", money, "LEFT", -Theme.SECTION_GAP, 0)

--- Anchor a header's or row's cells at the current column widths (the subject column follows the window).
local function PlaceCells(container, cells)
    local x = 0
    for _, key in ipairs(UI.colKeys) do
        local cell = cells[key]
        if cell then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", container, "LEFT", x, 0)
            cell:SetWidth(UI.colWidths[key] - 4)
        end
        x = x + UI.colWidths[key]
    end
    container:SetWidth(x)
end

--- Fit the columns to the list's width: Subject and From grow from their stock widths by their share of
--- whatever the list has beyond the stock total (never under it).
local function FitColumns(width)
    local fitted = ColumnFit.Fit(UI.stockWidths, UI.stretchShare, width)
    -- Items grows by whole icons; what is left of its share goes to Subject.
    local pitch = UI.ICON + UI.ICON_GAP
    local itemsExtra = fitted.items - UI.stockWidths.items
    local whole = math.floor(itemsExtra / pitch) * pitch
    fitted.subject = fitted.subject + (itemsExtra - whole)
    fitted.items = UI.stockWidths.items + whole
    for key, w in pairs(fitted) do UI.colWidths[key] = w end
end

--- Attachment icons a line holds at the Items column's fitted width (6 at the stock width).
local function IconsPerLine()
    return math.max(UI.ICONS_PER_LINE, math.floor(UI.colWidths.items / (UI.ICON + UI.ICON_GAP)))
end

--- Header labels with the sort arrow on the sorted column.
local function UpdateHeaderSortIndicators(headerRow)
    local o = IO.EnsureOptions()
    for key, cell in pairs(headerRow.cells) do
        local label = cell.label or cell
        Theme.SetSortHeaderLabel(label, UI.colLabels[key], key == o.mailSortKey, o.mailSortAscending)
    end
end

-- Below the tab's controls row (the character picker and layout dropdown), which doesn't scroll.
local CONTROLS_OFFSET = frame.CONTROLS_OFFSET or 0

-- Column headers (rows layout only): Subject, From, Money and Expires sort the rows (as on Summary).
local headerRow = CreateFrame("Frame", nil, inner)
headerRow:SetHeight(UI.HEADER_HEIGHT)
headerRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -CONTROLS_OFFSET)
headerRow.cells = {}
for _, key in ipairs(UI.colKeys) do
    if UI.sortable[key] then
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetHeight(UI.HEADER_HEIGHT)
        btn:RegisterForClicks("LeftButtonUp")
        local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        label:SetHeight(UI.HEADER_HEIGHT)
        label:SetJustifyH(UI.colJustify[key])
        btn.label = label
        btn:SetScript("OnClick", function()
            if IO.ClickMailSort(IO.EnsureOptions(), key) and frame.RefreshMail then
                frame.RefreshMail()
            end
        end)
        Theme.BindInteractableHover(btn)
        headerRow.cells[key] = btn
    else
        local label = headerRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetJustifyH(UI.colJustify[key])
        label:SetText(UI.colLabels[key])
        headerRow.cells[key] = label
    end
end
PlaceCells(headerRow, headerRow.cells)
UpdateHeaderSortIndicators(headerRow)

local listViewport = CreateFrame("Frame", nil, inner)
listViewport:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(CONTROLS_OFFSET + UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP))
listViewport:SetPoint("BOTTOM", status, "TOP", 0, Theme.SECTION_GAP)
listViewport:SetPoint("RIGHT", panel, "RIGHT", -Theme.VerticalScrollBarGutter(), 0)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    valueStep = UI.ROW_HEIGHT,
    wheelStep = UI.ROW_HEIGHT * 2,
    enableMouseWheel = true,
    childWidth = TotalColWidth(),
})
local child = viewport.child
local gridSlots = ISB.CreatePool(child)

-- Combined items: the gold waiting in the mail, under the grid (a coin slot and the total).
local goldText = child:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
goldText:SetJustifyH("LEFT")
goldText:Hide()

-- Rows layout under a search: between the messages with a matching attachment and the rest.
local noMatchDivider = Theme.CreateLabeledDividerRow(child)
noMatchDivider:SetHeight(UI.DIVIDER_HEIGHT)
noMatchDivider:SetText(UI.NO_MATCH_TEXT)
noMatchDivider:Hide()

local empty = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
empty:SetPoint("CENTER", listViewport, "CENTER", 0, 20)
empty:SetWidth(440)
empty:SetJustifyH("CENTER")
empty:SetWordWrap(true)
empty:Hide()

local Refresh

-- Item ids whose icons were not cached when drawn; the view redraws (once) when they arrive.
local pendingIcons = PendingIcons.Create(function()
    if panel:IsVisible() then Refresh() end
end)
local function TrackPendingIcon(itemID)
    pendingIcons.Track(itemID)
end

local function Money(copper)
    if not copper or copper <= 0 then return "" end
    return SD.GetMoneyString(copper)
end

local function ExpiresColor(level)
    if level == "urgent" then return Theme.COLORS.red end
    if level == "soon" then return Theme.COLORS.yellow end
    return { 1, 1, 1, 1 }
end

--- The lines a message adds under an attachment's tooltip, and the row tooltip's body.
local function MessageLines(tooltip, msg)
    local from = msg.sender and msg.sender ~= "" and ("From " .. (msg.senderLabel or msg.sender)) or nil
    local mark = IL.MessageMark(msg)
    if mark == "returned" then
        from = (from and from .. ", " or "") .. (msg.predicted and "returned, not seen in the mailbox yet"
            or "returned")
    elseif mark == "sent" then
        from = (from and from .. ", " or "") .. "sent, not seen in the mailbox yet"
    end
    if from then tooltip:AddLine(from, UI.GRAY[1], UI.GRAY[2], UI.GRAY[3]) end
    local text, level = IL.FormatDaysLeft(msg.daysLeft)
    if text ~= "" then
        local c = ExpiresColor(level)
        tooltip:AddLine((text == "Expired" and text or ("Expires in " .. text)), c[1], c[2], c[3])
    end
end

local function SlotTooltipExtra(_, tooltip, entry)
    if entry.message then
        MessageLines(tooltip, entry.message)
    elseif (entry.messageCount or 0) > 1 then -- Combine stacks: from several messages
        tooltip:AddLine(string.format("In %d messages", entry.messageCount), UI.GRAY[1], UI.GRAY[2], UI.GRAY[3])
    end
end

local function ShowRowTooltip(row)
    local msg = row.message
    if not msg or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(msg.subject and msg.subject ~= "" and msg.subject or "(no subject)", 1, 1, 1)
    MessageLines(GameTooltip, msg)
    if msg.money > 0 then
        GameTooltip:AddLine(Money(msg.money), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function ReleaseRows()
    for i = #state.rows, 1, -1 do
        local row = state.rows[i]
        state.rows[i] = nil
        row.message = nil
        for _, btn in ipairs(row.icons) do
            ISB.SetEmpty(btn)
            btn:Hide()
        end
        row:Hide()
        state.rowPool[#state.rowPool + 1] = row
    end
end

local function PoolRow()
    local row = table.remove(state.rowPool)
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, child)
    row:SetHeight(UI.ROW_HEIGHT)
    Theme.InstallRowHoverHighlight(row)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) viewport.Wheel(delta) end)
    row.cells = {}
    for _, key in ipairs(UI.colKeys) do
        if key ~= "items" then
            local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            cell:SetJustifyH(UI.colJustify[key])
            cell:SetWordWrap(false)
            row.cells[key] = cell
        end
    end
    row.icons = {}
    return row
end

local function RowIcon(row, i)
    local btn = row.icons[i]
    if not btn then
        btn = ISB.Create(row, { size = UI.ICON })
        btn.tooltipExtra = SlotTooltipExtra
        row.icons[i] = btn
    end
    btn:Show()
    return btn
end

--- Whether a message has an attachment the lowercased search matches.
local function MessageMatches(msg, queryLower)
    for _, item in ipairs(msg.items) do
        if ISB.EntryMatches(item, queryLower) then return true end
    end
    return false
end

--- An item's name for sorting and Combine stacks; one the client has not cached yet redraws on arrival.
local function SlotName(entry)
    local name = ISB.EntryName(entry)
    if not name and entry.itemID then TrackPendingIcon(entry.itemID) end
    return name
end

--- "rows": one inbox row per message; the attachment icons wrap to more lines when there are many. Under a
--- search, the messages with a match come first (each part in the column sort), then a divider, then the rest.
--- Combine stacks merges a message's stacks of one item into one icon with the total.
local function LayoutRows(messages, width, queryLower)
    FitColumns(width)
    PlaceCells(headerRow, headerRow.cells)
    UpdateHeaderSortIndicators(headerRow)
    headerRow:Show()
    local o = IO.EnsureOptions()
    IL.SortMessages(messages, o.mailSortKey, o.mailSortAscending)
    local matched
    if queryLower ~= "" then
        messages, matched = IL.PartitionBySearch(messages, function(msg)
            return MessageMatches(msg, queryLower)
        end)
    end
    local y = 0
    local attachments = 0
    for index, msg in ipairs(messages) do
        if matched and index == matched + 1 then
            noMatchDivider:ClearAllPoints()
            noMatchDivider:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            noMatchDivider:SetWidth(TotalColWidth())
            noMatchDivider:Show()
            y = y + UI.DIVIDER_HEIGHT
        end
        local row = PoolRow()
        state.rows[#state.rows + 1] = row
        row.message = msg
        local items = o.mailCombineStacks and IL.CombineMailStacks(msg.items, SlotName) or msg.items
        local perLine = IconsPerLine()
        local lines = math.max(1, math.ceil(#items / perLine))
        local height = math.max(UI.ROW_HEIGHT, lines * (UI.ICON + UI.ICON_GAP) + UI.ROW_PAD * 2)
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        PlaceCells(row, row.cells)
        attachments = attachments + #msg.items
        for i, item in ipairs(items) do
            local btn = RowIcon(row, i)
            local col = (i - 1) % perLine
            local line = math.floor((i - 1) / perLine)
            btn:ClearAllPoints()
            local pitch = UI.ICON + UI.ICON_GAP
            btn:SetPoint("TOPLEFT", row, "TOPLEFT", col * pitch, -(UI.ROW_PAD + line * pitch))
            local entry = {
                itemID = item.itemID, count = item.count, link = item.link, icon = item.icon, message = msg,
            }
            TrackPendingIcon(ISB.SetItem(btn, entry))
        end
        local subject = msg.subject and msg.subject ~= "" and msg.subject or "(no subject)"
        local mark = IL.MessageMark(msg)
        if mark then
            subject = subject .. " |cff9d9d9d(" .. mark .. ")|r"
        end
        row.cells.subject:SetText(subject)
        row.cells.sender:SetText(msg.senderLabel or msg.sender or "")
        row.cells.money:SetText(Money(msg.money))
        local text, level = IL.FormatDaysLeft(msg.daysLeft)
        local c = ExpiresColor(level)
        row.cells.expires:SetText(text)
        row.cells.expires:SetTextColor(c[1], c[2], c[3], 1)
        y = y + height
    end
    return y, attachments
end

--- "grid": every attachment as an item slot, then the gold in the mail. Under a search, two grids: the
--- matching slots, a "Does not match search" divider, then the rest (each still A to Z).
local function LayoutGrid(messages, width, queryLower)
    headerRow:Hide()
    -- A to Z, then the bigger stack.
    local nameOf = SlotName
    local slots = IL.MailGrid(messages)
    local attachments = #slots
    if IO.EnsureOptions().mailCombineStacks then slots = IL.CombineMailStacks(slots, nameOf) end
    slots = IL.SortMailGrid(slots, nameOf)
    local parts = { slots }
    if queryLower ~= "" then
        local ordered, matched = IL.PartitionBySearch(slots, function(entry)
            return ISB.EntryMatches(entry, queryLower)
        end)
        parts = { {}, {} }
        for i, entry in ipairs(ordered) do
            local part = i <= matched and parts[1] or parts[2]
            part[#part + 1] = entry
        end
    end
    local columns = IL.ColumnsForWidth(width, UI.SLOT, UI.GAP) -- as many as the viewport fits
    local y = 0
    for p, part in ipairs(parts) do
        if p == 2 and #part > 0 then
            if y > 0 then y = y + UI.GAP end
            noMatchDivider:ClearAllPoints()
            noMatchDivider:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            noMatchDivider:SetWidth(width)
            noMatchDivider:Show()
            y = y + UI.DIVIDER_HEIGHT
        end
        local m = IL.GridMetrics(#part, UI.SLOT, UI.GAP, columns)
        for i, entry in ipairs(part) do
            local btn = gridSlots.Acquire()
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", m.x(i), -(y + m.y(i)))
            btn.tooltipExtra = SlotTooltipExtra
            TrackPendingIcon(ISB.SetItem(btn, entry))
        end
        y = y + m.height
    end
    local gold = 0
    for _, msg in ipairs(messages) do gold = gold + (msg.money or 0) end
    local top = y + (#slots > 0 and UI.GOLD_ROW_GAP or 0)
    local coin = gridSlots.Acquire()
    coin:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -top)
    coin.tooltipExtra = nil
    ISB.SetItem(coin, { icon = UI.COIN_ICON, name = "Gold in the mail" })
    goldText:ClearAllPoints()
    goldText:SetPoint("LEFT", coin, "RIGHT", UI.GAP + 2, 0)
    goldText:SetText(SD.GetMoneyString(gold))
    goldText:Show()
    return top + UI.SLOT, attachments
end

--- Ring the attachments whose item matches the tab's search and dim the rest (the grid's gold slot aside).
local function ApplySearch(queryLower)
    for _, row in ipairs(state.rows) do
        for _, btn in ipairs(row.icons) do
            if btn:IsShown() then ISB.ApplySearch(btn, queryLower) end
        end
    end
    for _, btn in ipairs(gridSlots.active) do
        if btn.entry and (btn.entry.itemID or btn.entry.link) then ISB.ApplySearch(btn, queryLower) end
    end
end

local function LastChecked(char)
    local at = DS.GetMailboxLastVisit and DS:GetMailboxLastVisit(char) or 0
    if not at or at <= 0 then return "" end
    return "Mailbox checked: " .. SD.FormatLastOnline(at, false)
end

--- The list's width, and what in the current layout depends on it: how many attachment icons a row's line
--- holds (rows; this fits the columns to the width) or how many slot columns the grid has. A resize that
--- keeps it only moves the cells (Reflow), not a full redraw.
local function ListWidth()
    local width = viewport.scroll:GetWidth()
    if not width or width <= 0 then width = UI.FALLBACK_WIDTH end
    return width
end
local function WidthShape(width)
    if IO.GetLayout(IO.EnsureOptions(), "mail") == "grid" then
        return "grid:" .. IL.ColumnsForWidth(width, UI.SLOT, UI.GAP)
    end
    FitColumns(width)
    return "rows:" .. IconsPerLine()
end

local function Draw()
    state.shape = nil
    pendingIcons.Clear()
    ReleaseRows()
    gridSlots.ReleaseAll()
    goldText:Hide()
    noMatchDivider:Hide()
    empty:Hide()
    local char, pick = frame.GetSelectedCharacter()
    money:SetText(char and SD.GetMoneyString(DS:GetMoney(char) or 0) or "")
    if not char then
        headerRow:Hide()
        empty:SetText("No characters recorded yet.")
        empty:Show()
        status:SetText("")
        child:SetHeight(1)
        viewport.UpdateRange()
        return
    end
    local messages = IL.MailMessages(char, time())
    for _, msg in ipairs(messages) do
        msg.senderLabel = frame.ColorCharacterName(msg.sender, pick and pick.realm)
    end
    local name = pick and pick.coloredName or "this character"
    if #messages == 0 then
        headerRow:Hide()
        local seen = LastChecked(char)
        empty:SetText(seen ~= "" and string.format("No mail for %s.", name)
            or string.format("No mail recorded yet.\n\nOpen the mailbox on %s once.", name))
        empty:Show()
        status:SetText(seen)
        child:SetHeight(1)
        viewport.UpdateRange()
        return
    end
    local width = ListWidth()
    state.shape = WidthShape(width)
    local query = frame.GetSearchQuery and frame.GetSearchQuery() or ""
    local height, attachments
    if IO.GetLayout(IO.EnsureOptions(), "mail") == "grid" then
        height, attachments = LayoutGrid(messages, width, query)
    else
        height, attachments = LayoutRows(messages, width, query)
    end
    child:SetHeight(math.max(height, 1))
    viewport.UpdateRange()
    ApplySearch(query)
    local summary = string.format("%d message%s, %d item%s", #messages, #messages == 1 and "" or "s",
        attachments, attachments == 1 and "" or "s")
    local seen = LastChecked(char)
    status:SetText(seen ~= "" and (summary .. "  |cff9d9d9d" .. seen .. "|r") or summary)
end

--- Redraw the view. A redraw asked for during one (a resize the client fires mid-redraw) runs next frame
--- instead: nested, the two would each lay out their own rows and slots.
Refresh = function()
    if state.drawing then
        if frame.ScheduleRefresh then frame.ScheduleRefresh() end
        return
    end
    state.drawing = true
    local ok, err = pcall(Draw)
    state.drawing = false
    if not ok then error(err, 0) end
end
frame.RefreshMail = Refresh

-- The search text changed: both layouts re-sort (matches first), so redraw from the top, where they are.
frame.ApplySearchMail = function()
    Refresh()
    viewport.SetOffset(0)
end

-- Both layouts follow the window's width (the resize grip). Dragging it fires this every frame: while the
-- icons per line (rows) or the grid's columns stay the same, only the cells move to the new column widths.
viewport.scroll:HookScript("OnSizeChanged", function()
    if not panel:IsVisible() then return end
    local width = ListWidth()
    if not state.shape or WidthShape(width) ~= state.shape then
        Refresh()
        return
    end
    if state.shape:sub(1, 5) == "rows:" then -- WidthShape fitted the columns
        PlaceCells(headerRow, headerRow.cells)
        for _, row in ipairs(state.rows) do PlaceCells(row, row.cells) end
        noMatchDivider:SetWidth(TotalColWidth())
    else
        noMatchDivider:SetWidth(width)
    end
end)
