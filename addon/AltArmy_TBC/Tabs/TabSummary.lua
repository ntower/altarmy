-- AltArmy TBC — Summary tab: character list (Altoholic-style fixed row pool + Update())

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Summary
if not frame then return end

local ROW_HEIGHT = 20
local ROW_POOL_SIZE = 30 -- row widget pool (covers the 484px-tall window); visible count follows scrollFrame height

local function GetVisibleRowCount(viewportH)
    if not viewportH or viewportH <= 0 then
        return 1
    end
    local rows = math.min(ROW_POOL_SIZE, math.max(1, math.ceil(viewportH / ROW_HEIGHT)))
    return math.max(1, rows - 1)
end

local function GetSummaryListViewportBottomInset(needsHorizontalScroll, horizontalScrollBarHeight, summaryRowLift)
    if needsHorizontalScroll then
        return horizontalScrollBarHeight
    end
    return summaryRowLift or 0
end
local HEADER_HEIGHT = 20
local TOTALS_ROW_HEIGHT = 20
local PAD = 4
local WARNING_COL_WIDTH = 20
local NAME_COL_BASE_WIDTH = 204 -- +55 vs original 149 to fill 670px frame content width

local SD = AltArmy.SummaryData
local Theme = AltArmy.Theme
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP

local CLASS_ICON_SHEET = "Interface\\WorldStateFrame\\Icons-Classes"
local ICON_SIZE = 16
local REST_ICON_WIDTH = 12 -- the Rest XP column's icon right of the percent: "!" or the Well Rested arrow
-- The Rest XP percent ends this far left of its column's edge, room for the icon, on every row when any
-- character shown has an icon; flush right when none has.
local REST_TEXT_INSET = 10
local STATUS_ICON_SIZE = 16
local STATUS_ICON_GAP = 2
local MAIN_STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local CC = AltArmy.ClassColor
local BA = AltArmy.BankAlt
local GTD = AltArmy.GuildTabData
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString

local function openOptionsForMainCharacter()
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions("general", { flash = "main" })
    end
end

local function openOptionsForBankAlt(name, realm)
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions("characters", {
            name = name,
            realm = realm,
            flash = "bankAlt",
        })
    end
end

local function hideStatusIcon(icon, hit)
    if icon then icon:Hide() end
    if hit then
        hit.tooltipEntry = nil
        hit:Hide()
    end
end

local function showStatusIcon(row, icon, hit, x, tooltipEntry)
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row, "LEFT", x, 0)
        icon:Show()
    end
    if hit then
        hit.tooltipEntry = tooltipEntry
        hit:Show()
    end
end

--- Green up arrow after a Rest XP that includes the "Well Rested" legacy talent: the bags' upgrade
--- arrow where the client has that atlas, else the green stream arrow flipped to point up.
local function SetWellRestedArrowArt(tex)
    local NUI = AltArmy.NativeUI
    if tex.SetAtlas and NUI and NUI.HasAtlas and NUI.HasAtlas("bags-greenarrow") then
        tex:SetAtlas("bags-greenarrow")
    else
        tex:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
        tex:SetTexCoord(0, 1, 1, 0)
    end
end

local function SetNameIcon(icon, iconFallback, classFile)
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

local VALID_SORT_KEYS = {
    name = true, level = true, restXp = true,
    money = true, played = true, lastOnline = true,
}

local function GetSummarySettings()
    AltArmyTBC_SummarySettings = AltArmyTBC_SummarySettings or {}
    local s = AltArmyTBC_SummarySettings
    if not VALID_SORT_KEYS[s.sortKey] then
        s.sortKey = "name"
    end
    if s.sortAscending == nil then
        s.sortAscending = true
    end
    if s.showSelfFirst == nil then
        s.showSelfFirst = false
    end
    s.characters = s.characters or {}
    return s
end

local CharKey = AltArmy.CharKey

local function GetSummaryCharSetting(name, realm, key)
    local s = GetSummarySettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

local function SetSummaryCharSetting(name, realm, pin, hide)
    local s = GetSummarySettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

local summaryCharListRefresh = function() end  -- set below if CreateCharacterPinHideList is available

local function isCurrentCharacter(entry)
    local DS = AltArmy.DataStore
    return entry and DS and DS.IsCurrentCharacter
        and DS:IsCurrentCharacter(entry.name, entry.realm)
end

-- Column definitions: Name, Level, RestXP, Money, Played, LastOnline, Warning
local columns = {
    Name = {
        Width = NAME_COL_BASE_WIDTH - WARNING_COL_WIDTH,
        GetText = function(entry) return entry.name or "" end,
        JustifyH = "LEFT",
    },
    Level = {
        Width = 44,
        sortedHeaderLabel = "Lvl", -- "Level" plus the sort arrow truncates at this width
        GetText = function(entry)
            local l = entry.level
            if l == nil then return "" end
            return string.format("%.1f", math.floor((tonumber(l) or 0) * 10) / 10)
        end,
        JustifyH = "RIGHT",
    },
    RestXP = {
        Width = 71,
        headerLabel = "Rest XP",
        GetText = function(entry)
            if entry.isMaxLevel then
                return "--"
            end
            return SD and SD.FormatRestXp and SD.FormatRestXp(entry.restXp) or ""
        end,
        JustifyH = "RIGHT",
    },
    Money = {
        Width = 125,
        GetText = function(entry) return SD and SD.GetMoneyString and SD.GetMoneyString(entry.money) or "" end,
        GetMoney = function(entry) return tonumber(entry.money) or 0 end, -- shown in a MoneyCell
        JustifyH = "RIGHT",
    },
    Played = {
        Width = 109,
        GetText = function(entry) return SD and SD.GetTimeString and SD.GetTimeString(entry.played) or "" end,
        JustifyH = "RIGHT",
    },
    LastOnline = {
        Width = 72,
        headerLabel = "Online",
        GetText = function(entry)
            local online = entry.isOnline or isCurrentCharacter(entry)
            return SD and SD.FormatLastOnline and SD.FormatLastOnline(entry.lastOnline, online) or ""
        end,
        JustifyH = "RIGHT",
    },
    Warning = {
        Width = WARNING_COL_WIDTH,
        headerLabel = "",
    },
}
local columnOrder = { "Name", "Level", "RestXP", "Money", "Played", "LastOnline", "Warning" }

-- Column display name -> sort key for Characters:Sort()
local columnToSortKey = {
    Name = "name",
    Level = "level",
    RestXP = "restXp",
    Money = "money",
    Played = "played",
    LastOnline = "lastOnline",
}

local currentSortKey = "name"
local sortAscending = true

local Update -- forward-declare so header OnClick closure can call it

-- Scroll frame (viewport; no template — we use a custom scroll bar like Gear tab)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + TOTALS_ROW_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD + TOTALS_ROW_HEIGHT)
scrollFrame:EnableMouse(true)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
scrollChild:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
scrollFrame:SetScrollChild(scrollChild)

-- Vertical scroll bar (native MinimalScrollBar). Rows are a fixed pool on scrollFrame (faux
-- scrolling): the scroll offset only picks the first list index, so every scroll re-runs Update().
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local summaryNeedsHorizontalScroll = false
local scrollBinding = Theme.CreateVerticalScrollBinding(scrollFrame, {
    parent = frame,
    name = "AltArmyTBC_SummaryScrollBar",
    step = ROW_HEIGHT * 2,
    onScroll = function()
        Update()
    end,
})
local scrollBar = scrollBinding.bar
scrollChild:SetScript("OnMouseWheel", function(_, delta)
    scrollBinding.Wheel(delta)
end)

-- Header row (fixed above scroll area; each column is a clickable button)
local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetFrameLevel(frame:GetFrameLevel() + 10)

local headerButtons = {}
local function UpdateHeaderSortIndicators()
    for _, cn in ipairs(columnOrder) do
        local b = headerButtons[cn]
        if b and b.label then
            local col = columns[cn]
            local sorted = columnToSortKey[cn] == currentSortKey
            local label = (sorted and col and col.sortedHeaderLabel) or (col and col.headerLabel) or cn
            Theme.SetSortHeaderLabel(b.label, label, sorted, sortAscending)
        end
    end
end

local x = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    local w = col and col.Width or 100
    local cn = colName
    if cn == "Warning" then
        local headerFrame = CreateFrame("Frame", nil, headerRow)
        headerFrame:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        headerFrame:SetSize(w, HEADER_HEIGHT)
        headerButtons[colName] = headerFrame
    else
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        btn:SetSize(w, HEADER_HEIGHT)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetScript("OnClick", function()
            local sortKey = columnToSortKey[cn]
            if sortKey == currentSortKey then
                sortAscending = not sortAscending
            else
                currentSortKey = sortKey
                sortAscending = true
            end
            local s = GetSummarySettings()
            s.sortKey = currentSortKey
            s.sortAscending = sortAscending
            if AltArmy.Characters and AltArmy.Characters.Sort then
                AltArmy.Characters:Sort(sortAscending, currentSortKey)
            end
            Update()
            UpdateHeaderSortIndicators()
        end)
        local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        label:SetHeight(HEADER_HEIGHT)
        label:SetJustifyH(col and col.JustifyH or "LEFT")
        label:SetText(col and col.headerLabel or colName)
        btn.label = label
        headerButtons[colName] = btn
        Theme.BindInteractableHover(btn)
    end
    x = x + w
end

local totalColWidth = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    totalColWidth = totalColWidth + (col and col.Width or 100)
end

-- Totals row (fixed at bottom of list area; reparented to horizontalScrollChild below)
local totalsRow = CreateFrame("Frame", nil, frame)
totalsRow:SetHeight(TOTALS_ROW_HEIGHT)
totalsRow:SetWidth(totalColWidth)
totalsRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
totalsRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)
totalsRow.cells = {}
local cellX = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    local w = col and col.Width or 100
    local cell
    if col and col.GetMoney then
        cell = AltArmy.MoneyCell.Create(totalsRow, Theme.FONTS.body, w, TOTALS_ROW_HEIGHT)
    else
        cell = totalsRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cell:SetWidth(w)
        cell:SetJustifyH(col and col.JustifyH or "LEFT")
    end
    cell:SetPoint("LEFT", totalsRow, "LEFT", cellX, 0)
    totalsRow.cells[colName] = cell
    cellX = cellX + w
end

-- Main tab content: bordered panel (same styling as settings panel).
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20
local tabContentPanel = Theme.CreateMainContentPanel(frame)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)
scrollBar:SetParent(tabContentInner) -- reparented; layout in ApplySummaryListLayout

-- List viewport: clips list content to left 60% when settings panel is open (so list doesn't show through).
-- Horizontal scroll sits inside so the grid can scroll when viewport is narrower than totalColWidth.
local listViewport = CreateFrame("Frame", nil, tabContentInner)
listViewport:SetClipsChildren(true)
-- Points set in ApplySummaryListLayout

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryHorizontalScroll", listViewport)
horizontalScroll:SetAllPoints(listViewport)
horizontalScroll:EnableMouse(true)

local horizontalScrollChild = CreateFrame("Frame", nil, horizontalScroll)
horizontalScrollChild:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
horizontalScrollChild:SetHeight(1) -- Updated in layout; width = totalColWidth set in Update
horizontalScrollChild:SetWidth(totalColWidth)
horizontalScroll:SetScrollChild(horizontalScrollChild)

-- Reparent header into horizontal scroll child so it scrolls with the grid
headerRow:ClearAllPoints()
headerRow:SetParent(horizontalScrollChild)
headerRow:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, 0)
headerRow:SetPoint("TOPRIGHT", horizontalScrollChild, "TOPRIGHT", 0, 0)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetFrameLevel((horizontalScrollChild:GetFrameLevel() or 0) + 10)

-- Reparent vertical scroll frame into horizontal scroll child
scrollFrame:ClearAllPoints()
scrollFrame:SetParent(horizontalScrollChild)
scrollFrame:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, -HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, TOTALS_ROW_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, TOTALS_ROW_HEIGHT)

-- Gradient under the pinned header when the list is scrolled (Gear / Search pattern).
local summaryHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = headerRow,
    scrollFrame = scrollFrame,
    scrollBar = scrollBar,
    headerBottomInset = 0,
})

-- Reparent totals row into horizontal scroll child
totalsRow:ClearAllPoints()
totalsRow:SetParent(horizontalScrollChild)
totalsRow:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, 0)
totalsRow:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, 0)

-- Horizontal scroll bar at bottom of list area (like Gear tab)
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_SummaryHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar

-- Summary settings panel (right 40% when visible; same layout as Gear tab)
local SUMMARY_SETTINGS_SPLIT = 0.6
local summarySettingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(summarySettingsPanel, "section")
local function ApplySummarySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    summarySettingsPanel:ClearAllPoints()
    summarySettingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * SUMMARY_SETTINGS_SPLIT + SECTION_GAP, -SECTION_INSET)
    summarySettingsPanel:SetPoint(
        "BOTTOMLEFT", frame, "BOTTOMLEFT", w * SUMMARY_SETTINGS_SPLIT + SECTION_GAP, SECTION_INSET)
    summarySettingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    summarySettingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
end
ApplySummarySettingsPanelLayout()
summarySettingsPanel:Hide()
local summarySettingsContent = Theme.CreateSettingsPanelContent(summarySettingsPanel)
local summarySettingsTitle = summarySettingsContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
summarySettingsTitle:SetPoint("TOPLEFT", summarySettingsContent, "TOPLEFT", 0, 0)
summarySettingsTitle:SetPoint("TOPRIGHT", summarySettingsContent, "TOPRIGHT", 0, 0)
summarySettingsTitle:SetJustifyH("LEFT")
summarySettingsTitle:SetText("Summary Settings")
Theme.SetTitleColor(summarySettingsTitle)

local sortingContent = CreateFrame("Frame", nil, summarySettingsContent)
sortingContent:SetPoint("TOPLEFT", summarySettingsTitle, "BOTTOMLEFT", 0, -8)
sortingContent:SetPoint("BOTTOMRIGHT", summarySettingsContent, "BOTTOMRIGHT", 0, 0)

local showSelfFirstRow = Theme.CreateLabeledCheckbox(sortingContent, {
    point = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Pin current character",
    fullWidthHover = true,
    onClick = function(checked)
        GetSummarySettings().showSelfFirst = checked
        Update()
    end,
})
Theme.AttachSettingsHelpIcon(showSelfFirstRow, {
    title = "Pin current character",
    lines = {
        "When enabled, your current character is automatically pinned, "
            .. "causing it to show ahead of non-pinned characters.",
        'This will override the "Hide" setting.',
    },
})
local showSelfFirstCheck = showSelfFirstRow.check
showSelfFirstCheck:SetChecked(GetSummarySettings().showSelfFirst)

-- Character list: Pin/Hide (reusable component, same as Gear tab)
if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent,
        showSelfFirstRow, {
            gutterEdge = summarySettingsPanel,
            splitBankAlts = false,
            getSettings = GetSummarySettings,
            getCharSetting = GetSummaryCharSetting,
            setCharSetting = SetSummaryCharSetting,
            onChange = function()
                Update()
            end,
        })
    if refresh then summaryCharListRefresh = refresh end
    -- luacheck: pop
end

function frame:IsSummarySettingsShown()
    return summarySettingsPanel and summarySettingsPanel:IsShown()
end

local function ApplySummaryListLayout()
    local showSettings = summarySettingsPanel and summarySettingsPanel:IsShown()
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if showSettings then
        tabContentPanel:SetPoint("BOTTOMRIGHT", summarySettingsPanel, "BOTTOMLEFT", -SECTION_GAP, 0)
    else
        tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
    -- List viewport: reserve bottom space for horizontal scroll bar only when columns overflow.
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -PAD)
    local listBottomInset = GetSummaryListViewportBottomInset(
        summaryNeedsHorizontalScroll, HORIZONTAL_SCROLL_BAR_HEIGHT, PAD)
    listViewport:SetPoint(
        "BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, listBottomInset)
    -- Horizontal scroll bar: same span as list viewport at bottom of inner content.
    horizontalScrollBar:ClearAllPoints()
    horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", PAD, -4)
    horizontalScrollBar:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, -4)
    Theme.AnchorVerticalScrollBar(scrollBar, tabContentPanel, listViewport, { gap = 0 })
end

local summaryDeferredUpdatePending = false

local function ScheduleSummaryUpdateAfterLayout()
    if summaryDeferredUpdatePending then return end
    summaryDeferredUpdatePending = true
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(0, function()
            summaryDeferredUpdatePending = false
            if frame and frame.IsVisible and frame:IsVisible() then
                Update()
            end
        end)
    else
        summaryDeferredUpdatePending = false
    end
end

local function GetSummaryScrollViewportHeight()
    if listViewport then
        local listH = listViewport:GetHeight()
        if listH and listH > 0 then
            return math.max(1, listH - HEADER_HEIGHT - TOTALS_ROW_HEIGHT)
        end
    end
    local scrollH = scrollFrame and scrollFrame:GetHeight() or 0
    return math.max(1, scrollH > 0 and scrollH or 1)
end

--- Sync list viewport bottom inset when column overflow changes; returns true if layout changed.
local function SyncSummaryHorizontalScrollLayout()
    local needsHorzScroll = false
    if listViewport then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            needsHorzScroll = totalColWidth > vw
        end
    end
    if needsHorzScroll == summaryNeedsHorizontalScroll then
        return false
    end
    summaryNeedsHorizontalScroll = needsHorzScroll
    ApplySummaryListLayout()
    return true
end

function frame:ToggleSummarySettings(_self)
    local showSettings = not summarySettingsPanel:IsShown()
    summarySettingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySummarySettingsPanelLayout()
        showSelfFirstCheck:SetChecked(GetSummarySettings().showSelfFirst)
        if summaryCharListRefresh then summaryCharListRefresh() end
    end
    ApplySummaryListLayout()
    UpdateHeaderSortIndicators()
    Update()
    ScheduleSummaryUpdateAfterLayout()
end
ApplySummaryListLayout()

frame:SetScript("OnSizeChanged", function()
    if summarySettingsPanel and summarySettingsPanel:IsShown() then
        ApplySummarySettingsPanelLayout()
    end
    ApplySummaryListLayout()
    Update()
    ScheduleSummaryUpdateAfterLayout()
end)

-- Row pool: parented to scrollFrame so they're clipped and don't show under settings panel
local rowPool = {}
local prevRow = nil
for i = 1, ROW_POOL_SIZE do
    local row = CreateFrame("Frame", nil, scrollFrame)
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(totalColWidth)
    if i == 1 then
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
    end
    row.cells = {}
    local rowCellX = 0
    for _, colName in ipairs(columnOrder) do
        local col = columns[colName]
        local w = col and col.Width or 100
        if colName == "Warning" then
            local iconFrame = CreateFrame("Frame", nil, row)
            iconFrame:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            iconFrame:SetSize(w, ROW_HEIGHT)
            iconFrame:EnableMouse(true)
            local mark = iconFrame:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            mark:SetText("!")
            mark:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
            mark:SetTextColor(1, 0.82, 0, 1)
            iconFrame.mark = mark
            mark:Hide()
            iconFrame:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                local e = self.missingDataTooltipEntry
                if e and SD and SD.PresentMissingDataTooltip then
                    SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile)
                end
            end)
            iconFrame:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            row.cells[colName] = iconFrame
        elseif colName == "Name" then
            local nameIcon = row:CreateTexture(nil, "ARTWORK")
            nameIcon:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            nameIcon:SetSize(ICON_SIZE, ICON_SIZE)
            row.nameIcon = nameIcon
            local nameIconFallback = row:CreateTexture(nil, "ARTWORK")
            nameIconFallback:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            nameIconFallback:SetSize(ICON_SIZE, ICON_SIZE)
            nameIconFallback:Hide()
            row.nameIconFallback = nameIconFallback
            local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            cell:SetPoint("LEFT", row, "LEFT", rowCellX + ICON_SIZE + 2, 0)
            cell:SetWidth(w - ICON_SIZE - 2)
            cell:SetJustifyH(col and col.JustifyH or "LEFT")
            cell:SetWordWrap(false)
            row.cells[colName] = cell
        elseif col and col.GetMoney then
            local cell = AltArmy.MoneyCell.Create(row, Theme.FONTS.body, w, ROW_HEIGHT)
            cell:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            row.cells[colName] = cell
        else
            local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            cell:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            cell:SetWidth(w)
            cell:SetJustifyH(col and col.JustifyH or "LEFT")
            row.cells[colName] = cell
            if colName == "RestXP" then
                -- Every row's percent ends the same distance in, icon or not, so they stay aligned:
                -- the inset is set per update (UpdateRestXpCell), for the whole list at once.
                row.restCellWidth = w
                -- One icon just right of the percent, which stays put: a yellow "!" when the character
                -- logged out outside a resting area, else the Well Rested arrow when it has the talent.
                local restArrow = row:CreateTexture(nil, "ARTWORK")
                restArrow:SetSize(REST_ICON_WIDTH, REST_ICON_WIDTH)
                restArrow:SetPoint("LEFT", cell, "RIGHT", 0, 0)
                SetWellRestedArrowArt(restArrow)
                restArrow:Hide()
                row.restArrow = restArrow
                local notRestingMark = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
                notRestingMark:SetPoint("LEFT", cell, "RIGHT", 3, 0)
                notRestingMark:SetText("!")
                local caution = Theme.COLORS.warningCaution
                notRestingMark:SetTextColor(caution[1], caution[2], caution[3], 1)
                notRestingMark:Hide()
                row.notRestingMark = notRestingMark
                -- One tooltip over the whole cell and its icon: rest XP, Well Rested, the resting warning.
                local restHit = CreateFrame("Frame", nil, row)
                restHit:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
                restHit:SetSize(w + 3 + REST_ICON_WIDTH, ROW_HEIGHT)
                restHit:EnableMouse(true)
                restHit:SetFrameLevel(row:GetFrameLevel() + 3)
                restHit:Hide()
                restHit:SetScript("OnEnter", function(self)
                    if self.tooltipEntry and SD and SD.PresentRestXpTooltip then
                        SD.PresentRestXpTooltip(self, "ANCHOR_BOTTOMLEFT", self.tooltipEntry)
                    end
                end)
                restHit:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)
                row.restHit = restHit
            end
        end
        rowCellX = rowCellX + w
    end
    -- Overlay for Name column so we can show tooltip with full name when truncated
    local nameOverlay = CreateFrame("Frame", nil, row)
    nameOverlay:SetPoint("LEFT", row, "LEFT", 0, 0)
    nameOverlay:SetSize(columns.Name.Width, ROW_HEIGHT)
    nameOverlay:EnableMouse(true)
    nameOverlay:SetScript("OnEnter", function(self)
        if self.fullNameDisplay and self.wasTruncated and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    nameOverlay:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.nameOverlay = nameOverlay

    local bankAltIcon = row:CreateTexture(nil, "ARTWORK")
    bankAltIcon:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
    bankAltIcon:SetTexture(BA and BA.ICON_TEXTURE or "Interface\\MINIMAP\\TRACKING\\Banker")
    bankAltIcon:Hide()
    row.bankAltIcon = bankAltIcon

    local bankAltHit = CreateFrame("Frame", nil, row)
    bankAltHit:SetAllPoints(bankAltIcon)
    bankAltHit:EnableMouse(true)
    bankAltHit:Hide()
    bankAltHit:SetFrameLevel(row:GetFrameLevel() + 3)
    bankAltHit:SetScript("OnEnter", function(self)
        local e = self.tooltipEntry
        if e and BA and BA.PresentTooltip then
            BA.PresentTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile)
        end
    end)
    bankAltHit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    bankAltHit:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local e = self.tooltipEntry
        if e then
            openOptionsForBankAlt(e.name, e.realm)
        end
    end)
    row.bankAltHit = bankAltHit

    local mainStarIcon = row:CreateTexture(nil, "ARTWORK")
    mainStarIcon:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
    mainStarIcon:SetTexture(MAIN_STAR_TEXTURE)
    mainStarIcon:Hide()
    row.mainStarIcon = mainStarIcon

    local mainStarHit = CreateFrame("Frame", nil, row)
    mainStarHit:SetAllPoints(mainStarIcon)
    mainStarHit:EnableMouse(true)
    mainStarHit:Hide()
    mainStarHit:SetFrameLevel(row:GetFrameLevel() + 3)
    mainStarHit:SetScript("OnEnter", function(self)
        if not self.showTooltip then return end
        local e = self.tooltipEntry
        if GTD and GTD.PresentMainStarTooltip then
            GTD.PresentMainStarTooltip(self, "ANCHOR_BOTTOMLEFT", {
                name = e and e.name,
                classFile = e and e.classFile,
                isOwn = true,
                showConfigureHint = true,
            })
        end
    end)
    mainStarHit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    mainStarHit:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            openOptionsForMainCharacter()
        end
    end)
    row.mainStarHit = mainStarHit

    rowPool[i] = row
    prevRow = row
end

local function GetRow(index)
    return rowPool[index]
end

--- Arms the Rest XP cell's tooltip and shows its one icon: the "!" when the character logged out outside
--- a resting area (with Well Rested or not), else the Well Rested arrow when it has a rank, else none
--- (entry nil: an empty row, all hidden).
--- Which icon a Rest XP cell shows: "warn", "wellRested" or nil.
local function RestXpIcon(entry)
    if not entry then return nil end
    if entry.notResting == true then return "warn" end
    if not entry.isMaxLevel and (tonumber(entry.wellRestedRank) or 0) > 0 then return "wellRested" end
    return nil
end

--- Whether any character in the list shows a Rest XP icon (then every row's percent is inset).
local function AnyRestXpIcon(list)
    for i = 1, #list do
        if RestXpIcon(list[i]) then return true end
    end
    return false
end

--- inset: how far left of the column's edge the percent ends (REST_TEXT_INSET or 0, the same for all rows).
local function UpdateRestXpCell(rowFrame, entry, inset)
    local hit, mark, arrow = rowFrame.restHit, rowFrame.notRestingMark, rowFrame.restArrow
    local width = rowFrame.restCellWidth
    if width and rowFrame.cells.RestXP then
        rowFrame.cells.RestXP:SetWidth(width - (inset or 0))
    end
    if hit then
        hit.tooltipEntry = entry
        hit:SetShown(entry ~= nil)
        if width then hit:SetWidth(width - (inset or 0) + 3 + REST_ICON_WIDTH) end
    end
    local icon = RestXpIcon(entry)
    if mark then mark:SetShown(icon == "warn") end
    if arrow then arrow:SetShown(icon == "wellRested") end
end

--- Update visible rows from the character list using current vertical scrollbar position.
Update = function()
    local rawList = AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList() or {}
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    local RF = AltArmy.RealmFilter
    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then
        realmFilter = GRF.Get()
    end
    local filtered
    if RF and RF.filterListByRealm then
        filtered = AltArmy.GlobalRealmFilter.FilterList(rawList, currentRealm)
    else
        filtered = rawList
    end
    -- Filter hidden; order: pinned first (keep sort), then non-pinned
    local showSelfFirst = GetSummarySettings().showSelfFirst == true
    local list = {}
    local pinned, rest = {}, {}
    for i = 1, #filtered do
        local e = filtered[i]
        local isHidden = GetSummaryCharSetting(e.name, e.realm, "hide")
        if not isHidden or (showSelfFirst and isCurrentCharacter(e)) then
            if GetSummaryCharSetting(e.name, e.realm, "pin")
                or (showSelfFirst and isCurrentCharacter(e)) then
                pinned[#pinned + 1] = e
            else
                rest[#rest + 1] = e
            end
        end
    end
    for i = 1, #pinned do list[#list + 1] = pinned[i] end
    for i = 1, #rest do list[#list + 1] = rest[i] end
    local numItems = #list
    local restInset = AnyRestXpIcon(list) and REST_TEXT_INSET or 0

    -- Horizontal scroll need drives list viewport height (totals row sits lower when bar hidden).
    local horzLayoutChanged = SyncSummaryHorizontalScrollLayout()

    -- Virtual list: ROW_POOL_SIZE row widgets; visibleRows derived from viewport height. Maximum scroll
    -- is how far we must move to bring item numItems into the last slot — (numItems - visibleRows)
    -- row heights — not (numItems * ROW_HEIGHT - viewportHeight).
    local viewportH = GetSummaryScrollViewportHeight()
    local visibleRows = GetVisibleRowCount(viewportH)
    if horzLayoutChanged then
        ScheduleSummaryUpdateAfterLayout()
    end
    local maxScroll = math.max(0, (numItems - visibleRows) * ROW_HEIGHT)
    scrollChild:SetHeight(viewportH + maxScroll)
    scrollChild:Show()

    scrollBinding.UpdateRange()

    local maxOffset = math.max(0, numItems - visibleRows)
    local offset = math.min(math.floor(scrollBinding.GetOffset() / ROW_HEIGHT), maxOffset)

    -- Horizontal scroll: list viewport may be narrower than totalColWidth (e.g. when settings panel is open)
    if listViewport and horizontalScroll and horizontalScrollChild and horizontalScrollBar then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            horizontalScrollChild:SetWidth(totalColWidth)
            local vh = listViewport:GetHeight()
            if not vh or vh <= 0 then
                vh = HEADER_HEIGHT + scrollFrame:GetHeight() + TOTALS_ROW_HEIGHT
            end
            horizontalScrollChild:SetHeight(vh)
            local maxHorzScroll = math.max(0, totalColWidth - vw)
            horizontalScrollApi:SetRange(0, maxHorzScroll, vw)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            local hVal = horizontalScrollBar:GetValue()
            if hVal > maxHorzScroll then
                horizontalScrollBar:SetValue(maxHorzScroll)
                horizontalScrollApi:Apply(maxHorzScroll)
            else
                horizontalScrollApi:Sync()
            end
        end
    end

    for i = 1, ROW_POOL_SIZE do
        local rowFrame = GetRow(i)
        if i > visibleRows then
            rowFrame:Hide()
        else
            local j = offset + i
            if j <= numItems then
                local entry = list[j]
                for _, colName in ipairs(columnOrder) do
                local col = columns[colName]
                local cell = rowFrame.cells[colName]
                if colName == "Warning" then
                    local info = { hasMissing = false, instructions = {} }
                    -- what to open to fill in missing data is for our own characters only
                    if SD and SD.GetMissingDataInfo and not entry.linkId then
                        local result = SD.GetMissingDataInfo(entry.name, entry.realm)
                        if result then info = result end
                    end
                    if info.hasMissing and cell and cell.mark then
                        cell.mark:Show()
                        cell.missingDataTooltipEntry = {
                            name = entry.name or "",
                            realm = entry.realm or "",
                            classFile = entry.classFile,
                        }
                    else
                        if cell then
                            if cell.mark then cell.mark:Hide() end
                            cell.missingDataTooltipEntry = nil
                        end
                    end
                elseif cell and col and col.GetText then
                    if colName == "Name" then
                        local showRealmSuffix = (realmFilter == "all")
                            and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
                        local isBankAlt = not entry.linkId and BA and BA.Is and BA.Is(entry.name, entry.realm)
                        local nameDisplayStr
                        if RF and RF.formatColoredCharacterNameRealm then
                            nameDisplayStr = RF.formatColoredCharacterNameRealm(
                                entry.name or "",
                                entry.realm,
                                showRealmSuffix,
                                entry.classFile,
                                not isBankAlt
                            )
                            cell:SetText(nameDisplayStr)
                            cell:SetTextColor(1, 1, 1, 1)
                        else
                            nameDisplayStr = col.GetText(entry)
                            cell:SetText(nameDisplayStr)
                            local classFile = entry.classFile
                            if CC and CC.getRGBOr then
                                local r, g, b = CC.getRGBOr(classFile, 1, 0.82, 0)
                                cell:SetTextColor(r, g, b, 1)
                            else
                                cell:SetTextColor(1, 0.82, 0, 1)
                            end
                        end
                        SetNameIcon(rowFrame.nameIcon, rowFrame.nameIconFallback, entry.classFile)
                        local nameColW = columns.Name and columns.Name.Width
                            or (NAME_COL_BASE_WIDTH - WARNING_COL_WIDTH)
                        local GSS = AltArmy.GuildShareSettings
                        -- a linked account's character is never our main
                        local isMain = not entry.linkId and GSS and GSS.IsConfiguredMain
                            and GSS.IsConfiguredMain(entry.name, entry.realm)
                        local layout = SD.GetNameStatusIconLayout(
                            ICON_SIZE, STATUS_ICON_SIZE, STATUS_ICON_GAP, isMain, isBankAlt
                        )
                        if isMain then
                            showStatusIcon(rowFrame, rowFrame.mainStarIcon, rowFrame.mainStarHit, layout.mainX, {
                                name = entry.name or "",
                                classFile = entry.classFile,
                            })
                            if rowFrame.mainStarHit then
                                rowFrame.mainStarHit.showTooltip = true
                            end
                        else
                            hideStatusIcon(rowFrame.mainStarIcon, rowFrame.mainStarHit)
                            if rowFrame.mainStarHit then
                                rowFrame.mainStarHit.showTooltip = false
                            end
                        end
                        if isBankAlt then
                            showStatusIcon(rowFrame, rowFrame.bankAltIcon, rowFrame.bankAltHit, layout.bankX, {
                                name = entry.name or "",
                                realm = entry.realm or "",
                                classFile = entry.classFile,
                            })
                        else
                            hideStatusIcon(rowFrame.bankAltIcon, rowFrame.bankAltHit)
                        end
                        local nameTextLeft = layout.nameTextLeft
                        cell:ClearAllPoints()
                        cell:SetPoint("LEFT", rowFrame, "LEFT", nameTextLeft, 0)
                        cell:SetWidth(nameColW - nameTextLeft)
                        local nameW = nameColW
                        local wasTruncated = TruncateFontString
                            and TruncateFontString(
                                cell, nameDisplayStr, nameW - nameTextLeft - 2, { returnBoolean = true }
                            )
                            or false
                        local overlay = rowFrame.nameOverlay
                        if overlay then
                            overlay.fullNameDisplay = nameDisplayStr
                            overlay.wasTruncated = wasTruncated
                        end
                    elseif col.GetMoney then
                        cell:SetMoney(col.GetMoney(entry))
                    else
                        cell:SetText(col.GetText(entry))
                        if colName == "RestXP" then
                            UpdateRestXpCell(rowFrame, entry, restInset)
                        end
                    end
                end
            end
                rowFrame:Show()
            else
                local warningCell = rowFrame.cells and rowFrame.cells["Warning"]
                if warningCell then
                    if warningCell.mark then warningCell.mark:Hide() end
                    warningCell.missingDataTooltipEntry = nil
                end
                if rowFrame.nameOverlay then
                    rowFrame.nameOverlay.fullNameDisplay = nil
                    rowFrame.nameOverlay.wasTruncated = nil
                end
                hideStatusIcon(rowFrame.mainStarIcon, rowFrame.mainStarHit)
                if rowFrame.mainStarHit then
                    rowFrame.mainStarHit.showTooltip = false
                end
                hideStatusIcon(rowFrame.bankAltIcon, rowFrame.bankAltHit)
                UpdateRestXpCell(rowFrame, nil, restInset)
                rowFrame:Hide()
            end
        end
    end

    -- Totals row: Level, Money, Played only; ours alone (a linked account's gold isn't ours)
    local totalLevel, totalMoney, totalPlayed = 0, 0, 0
    for _, entry in ipairs(list) do
        if not entry.linkId then
            totalLevel = totalLevel + (tonumber(entry.level) or 0)
            totalMoney = totalMoney + (tonumber(entry.money) or 0)
            totalPlayed = totalPlayed + (tonumber(entry.played) or 0)
        end
    end
    for _, colName in ipairs(columnOrder) do
        local cell = totalsRow.cells[colName]
        if cell then
            if colName == "Level" then
                cell:SetText(string.format("%.1f", math.floor(totalLevel * 10) / 10))
            elseif colName == "Money" then
                cell:SetMoney(totalMoney)
            elseif colName == "Played" then
                cell:SetText(SD and SD.GetTimeString and SD.GetTimeString(totalPlayed) or "")
            else
                cell:SetText("")
            end
        end
    end

    if summaryHeaderFade then
        summaryHeaderFade:Update()
    end
end

-- Run Update when Summary tab is shown (invalidate so list is fresh)
frame:SetScript("OnShow", function()
    local s = GetSummarySettings()
    currentSortKey = s.sortKey
    sortAscending = s.sortAscending
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters and AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(sortAscending, currentSortKey)
    end
    UpdateHeaderSortIndicators()
    Update()
end)

-- Thin wrapper for external refresh (e.g. minimap, main frame OnShow)
function AltArmy.RefreshSummary()
    if not frame or not frame:IsShown() then return end
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters and AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(sortAscending, currentSortKey)
    end
    UpdateHeaderSortIndicators()
    Update()
end

if AltArmy.MainFrame then
    local oldOnShow = AltArmy.MainFrame:GetScript("OnShow")
    AltArmy.MainFrame:SetScript("OnShow", function()
        if oldOnShow then oldOnShow() end
        if AltArmy.RefreshSummary then AltArmy.RefreshSummary() end
    end)
end

-- Optional: run once when player is known so list is non-empty on first open
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if frame:IsShown() then
            scrollBinding.SetOffset(0)
            Update()
        end
    end
end)
