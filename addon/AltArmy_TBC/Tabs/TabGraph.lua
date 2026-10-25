-- AltArmy TBC — Graphs tab: multi-character level progress line graphs.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Graph
if not frame then return end

local LPD = AltArmy.LevelProgressData
local Core = AltArmy.GraphCore
local Logic = AltArmy.GraphLogic
local Theme = AltArmy.Theme

-- The right column's (options and Compare) fitted width: a wider window gives it a little of what the tab
-- gains, up to its cap, so long names and realm dividers stop truncating; the plot takes the rest
-- (ApplyRightColumnLayout, Data/ColumnFit.lua). stockTab: the tab frame's width at the stock window.
local SELECTOR_WIDTH = 195
local SELECTOR_FIT = { stock = 195, flex = 0.15, cap = 260, stockTab = 654 }
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local SECTION_GAP = Theme.SECTION_GAP
local ROW_HEIGHT = 20
local OPTION_ROW_HEIGHT = ROW_HEIGHT
local OPTION_ROW_GAP = 0
local METRIC_DROPDOWN_HEIGHT = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or (OPTION_ROW_HEIGHT + 4)
local METRIC_TO_OPTIONS_GAP = 4
local OPTIONS_PANEL_PAD = 6
local OPTIONS_PANEL_HEIGHT_FULL = OPTIONS_PANEL_PAD
    + METRIC_DROPDOWN_HEIGHT
    + METRIC_TO_OPTIONS_GAP
    + 3 * OPTION_ROW_HEIGHT
    + 2 * OPTION_ROW_GAP
    + OPTIONS_PANEL_PAD
local OPTIONS_PANEL_HEIGHT_CUMULATIVE = OPTIONS_PANEL_PAD
    + METRIC_DROPDOWN_HEIGHT
    + METRIC_TO_OPTIONS_GAP
    + OPTION_ROW_HEIGHT
    + OPTIONS_PANEL_PAD
local OUTLIER_INFO_ICON_SIZE = 14
local SECTION_HEADER_HEIGHT = 20
local INSUFFICIENT_SECTION_GAP = 10
local LINE_THICKNESS = 2
local DASH_THICKNESS = 1
local MARKER_HIT_SIZE = 18
local MARKER_DOT_SIZE = 4
local FULL_LINE_ALPHA = Logic.FULL_LINE_ALPHA
local FULL_DASH_ALPHA = Logic.FULL_DASH_ALPHA
local DIM_LINE_ALPHA = Logic.DIM_LINE_ALPHA
local DIM_DASH_ALPHA = Logic.DIM_DASH_ALPHA

AltArmyTBC_GraphSettings = AltArmyTBC_GraphSettings or AltArmyTBC_ProgressionSettings or {}

local RF = AltArmy.RealmFilter
local hoveredCompareEntry = nil
local hoveredCompareSelectAll = false

local currentX, currentY = nil, nil
local currentRawYMax = 0
local currentRawYMin = 0
local currentLogAxisYMin = nil
local drawnKeys = {}
local seriesGroups = {}
local selectedColorByKey = {}

local markerDotPool = { free = {} }
local markerHitPool = { free = {} }
local hoveredLogarithmicPreview = false
local hoveredOutliersPreview = false
local hoveredRollingAveragePreview = false
local suppressLogarithmicHoverPreview = false
local suppressOutliersHoverPreview = false
local suppressRollingAverageHoverPreview = false

local ZOOM_MIN_SPAN = 2
local zoomMinLevel = nil
local zoomMaxLevel = nil
local dragStartLevel = nil
local isDragSelecting = false

local RebuildGraph
local ApplyHighlight
local HandleCompareRowEnter
local HandleCompareRowLeave
local HandleCompareSelectAllEnter
local HandleCompareSelectAllLeave
local UpdateSelectAllCheckbox
local HideOutlierOptionTooltip
local UpdateMetricDependentOptions

local function EnsureSettings()
    AltArmyTBC_GraphSettings.selected = AltArmyTBC_GraphSettings.selected or {}
    if AltArmyTBC_GraphSettings.logarithmic == nil then
        AltArmyTBC_GraphSettings.logarithmic = false
    end
    if AltArmyTBC_GraphSettings.ignoreOutliers == nil then
        AltArmyTBC_GraphSettings.ignoreOutliers = false
    end
    if AltArmyTBC_GraphSettings.rollingAverage == nil then
        AltArmyTBC_GraphSettings.rollingAverage = false
    end
    local defaultMetric = (LPD and LPD.METRIC_TIME_PER_LEVEL) or "timePerLevel"
    if LPD and LPD.NormalizeMetric then
        AltArmyTBC_GraphSettings.metric = LPD.NormalizeMetric(AltArmyTBC_GraphSettings.metric)
    elseif AltArmyTBC_GraphSettings.metric == nil then
        AltArmyTBC_GraphSettings.metric = defaultMetric
    end
    return AltArmyTBC_GraphSettings
end

local function GetSelectedMetric()
    local metric = EnsureSettings().metric
    if LPD and LPD.NormalizeMetric then
        return LPD.NormalizeMetric(metric)
    end
    return metric or "timePerLevel"
end

local function IsCumulativePlayedMetric()
    return LPD
        and LPD.METRIC_CUMULATIVE_PLAYED
        and GetSelectedMetric() == LPD.METRIC_CUMULATIVE_PLAYED
end

local function GetSeriesForEntry(entry)
    if not LPD or not entry then return {} end
    return LPD.GetSeriesForCharacter(entry.key or entry.name, entry.realm, GetSelectedMetric(), entry.linkId)
end

local function IsLogarithmic()
    if hoveredLogarithmicPreview and not suppressLogarithmicHoverPreview then
        return true
    end
    return EnsureSettings().logarithmic == true
end

local function IsIgnoreOutliers()
    if IsCumulativePlayedMetric() then
        return false
    end
    if hoveredOutliersPreview and not suppressOutliersHoverPreview then
        return true
    end
    return EnsureSettings().ignoreOutliers == true
end

local function IsRollingAverage()
    if IsCumulativePlayedMetric() then
        return false
    end
    if hoveredRollingAveragePreview and not suppressRollingAverageHoverPreview then
        return true
    end
    return EnsureSettings().rollingAverage == true
end

local function WireOptionRowCheck(getSaved, setSaved, clearHoverPreview, setHoverSuppress)
    return function(self)
        local wasChecked = getSaved() == true
        local nowChecked = self:GetChecked() and true or false
        setSaved(nowChecked)
        if wasChecked and not nowChecked then
            clearHoverPreview()
            setHoverSuppress(true)
        end
        RebuildGraph()
    end
end

local function IsSelected(entry)
    return EnsureSettings().selected[Logic.SelectionKey(entry)] == true
end

local function SetSelected(entry, on)
    EnsureSettings().selected[Logic.SelectionKey(entry)] = on and true or nil
end

-- Selections saved by name, before they were keyed by GUID, move to the GUID keys as the list is read.
local function GetCompareList()
    if not LPD or not LPD.GetCharactersWithHistory then return {} end
    local list = LPD.GetCharactersWithHistory()
    Logic.MigrateNameSelections(EnsureSettings().selected, list)
    return list
end

local function GetSelectedCharacters()
    local out = {}
    if not LPD or not LPD.GetCharactersWithHistory then return out end
    for _, entry in ipairs(GetCompareList()) do
        if IsSelected(entry) then
            out[#out + 1] = entry
        end
    end
    return out
end

local function EntryKey(entry)
    if not entry then return "" end
    return Logic.SelectionKey(entry)
end

-- Maps each selected character key to its line color: the class color, or for a
-- second, third, ... character of a class the fallback color farthest from
-- everything else on the chart (Logic.AssignLineColors).
local function BuildSelectedColorByKey()
    local selected = GetSelectedCharacters()
    local entries = {}
    for i, entry in ipairs(selected) do
        local r, g, b = LPD.GetClassColor(entry.classFile)
        entries[i] = { classFile = entry.classFile, r = r, g = g, b = b }
    end

    local colors = Logic.AssignLineColors(entries)
    local map = {}
    for i, entry in ipairs(selected) do
        map[EntryKey(entry)] = colors[i]
    end
    return map
end

local function GetCharactersToDraw()
    if hoveredCompareSelectAll then
        return GetCompareList()
    end

    local out = {}
    local seen = {}

    for _, entry in ipairs(GetSelectedCharacters()) do
        local key = EntryKey(entry)
        if not seen[key] then
            out[#out + 1] = entry
            seen[key] = true
        end
    end

    if hoveredCompareEntry then
        local key = EntryKey(hoveredCompareEntry)
        if not seen[key] then
            out[#out + 1] = hoveredCompareEntry
            seen[key] = true
        end
    end

    return out
end

local function ClearHoverPreviewState()
    hoveredCompareEntry = nil
    hoveredCompareSelectAll = false
    hoveredLogarithmicPreview = false
    hoveredOutliersPreview = false
    hoveredRollingAveragePreview = false
end

local function SetRowHoverHighlight(row, on)
    Theme.SetHoverTint(row, on)
end

local function BindCompareRowHover(row, entry)
    local function onEnter()
        HandleCompareRowEnter(row, entry)
    end

    local function onLeave()
        HandleCompareRowLeave(row, entry)
    end

    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row.check:SetScript("OnEnter", onEnter)
    row.check:SetScript("OnLeave", onLeave)
    if row.nameButton then
        row.nameButton:SetScript("OnEnter", onEnter)
        row.nameButton:SetScript("OnLeave", onLeave)
    end
end

local function BindSelectAllRowHover(row)
    local function onEnter()
        HandleCompareSelectAllEnter(row)
    end

    local function onLeave()
        HandleCompareSelectAllLeave(row)
    end

    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row.check:SetScript("OnEnter", onEnter)
    row.check:SetScript("OnLeave", onLeave)
    if row.labelButton then
        row.labelButton:SetScript("OnEnter", onEnter)
        row.labelButton:SetScript("OnLeave", onLeave)
    end
end

local function OnCompareRowUnchecked(row, entry)
    if hoveredCompareEntry and EntryKey(hoveredCompareEntry) == EntryKey(entry) then
        hoveredCompareEntry = nil
    end
    row.suppressHoverPreview = true
end

local function ToggleCompareSelection(row, entry)
    local wasChecked = IsSelected(entry)
    local checked = not wasChecked
    row.check:SetChecked(checked)
    SetSelected(entry, checked)
    if wasChecked and not checked then
        OnCompareRowUnchecked(row, entry)
    end
    if UpdateSelectAllCheckbox then
        UpdateSelectAllCheckbox()
    end
    RebuildGraph()
end

-- Layout: graph (left) + selector (right)
local graphFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
graphFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
graphFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
Theme.ApplyBackdrop(graphFrame, "content")
graphFrame:EnableMouse(true)

local selectionOverlay = graphFrame:CreateTexture(nil, "OVERLAY")
selectionOverlay:SetColorTexture(0.35, 0.65, 1, 0.22)
selectionOverlay:Hide()

local CURSOR_LINE_COLOR = { r = 0.45, g = 0.65, b = 0.85, a = 0.28 }
local CURSOR_LINE_DASH = 3
local CURSOR_LINE_GAP = 8
local CURSOR_LINE_THICKNESS = 1
local cursorLinePool = { free = {}, active = {} }
local graphMouseOver = false

local function ReleaseCursorLine()
    while #cursorLinePool.active > 0 do
        local tex = table.remove(cursorLinePool.active)
        tex:Hide()
        table.insert(cursorLinePool.free, tex)
    end
end

local function AcquireCursorLineSegment()
    local tex = table.remove(cursorLinePool.free)
    if not tex then
        tex = graphFrame:CreateTexture(nil, "OVERLAY")
    end
    tex:Show()
    cursorLinePool.active[#cursorLinePool.active + 1] = tex
    return tex
end

local function CursorToPlotX()
    local scale = graphFrame:GetEffectiveScale()
    local left = graphFrame:GetLeft()
    return select(1, GetCursorPosition()) / scale - left
end

local function UpdateCursorLine()
    ReleaseCursorLine()
    if not graphMouseOver or not currentX or isDragSelecting then
        return
    end

    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    local pad = Core.PADDING
    local x = CursorToPlotX()
    if x < pad.left or x > pad.left + plotW then
        return
    end

    local yBottom = pad.bottom
    local yTop = pad.bottom + plotH
    local pos = yBottom
    local c = CURSOR_LINE_COLOR
    while pos < yTop do
        local dashEnd = math.min(pos + CURSOR_LINE_DASH, yTop)
        local height = dashEnd - pos
        if height > 0 then
            local tex = AcquireCursorLineSegment()
            tex:SetColorTexture(c.r, c.g, c.b, c.a)
            tex:ClearAllPoints()
            tex:SetSize(CURSOR_LINE_THICKNESS, height)
            tex:SetPoint(
                "BOTTOMLEFT", graphFrame, "BOTTOMLEFT",
                x - CURSOR_LINE_THICKNESS / 2, pos
            )
        end
        pos = dashEnd + CURSOR_LINE_GAP
    end
end

local function RefreshCursorLineAfterRebuild()
    if graphMouseOver then
        UpdateCursorLine()
    else
        ReleaseCursorLine()
    end
end

local zoomResetBtn = CreateFrame("Button", nil, graphFrame, "BackdropTemplate")
zoomResetBtn:SetSize(92, 22)
zoomResetBtn:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", Core.PADDING.left + 6, -8)
zoomResetBtn:SetFrameLevel(graphFrame:GetFrameLevel() + 60)
Theme.SkinButton(zoomResetBtn)
local zoomResetBtnText = zoomResetBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
zoomResetBtnText:SetPoint("CENTER", zoomResetBtn, "CENTER", 0, 0)
zoomResetBtnText:SetText("Reset Zoom")
zoomResetBtn:Hide()

local function IsZoomed()
    return zoomMinLevel ~= nil and zoomMaxLevel ~= nil
end

local function GetEffectiveXRange()
    if IsZoomed() then
        return zoomMinLevel, zoomMaxLevel, zoomMaxLevel - zoomMinLevel
    end
    return LPD.GetAxisRange()
end

local function GetLevelBoundsForScale()
    if IsZoomed() then
        return zoomMinLevel, zoomMaxLevel
    end
    return nil, nil
end

local function ClearZoom()
    zoomMinLevel = nil
    zoomMaxLevel = nil
    zoomResetBtn:Hide()
end

local function CursorToLevel()
    local plotW = Core.CalculatePlotDimensions(graphFrame)
    local xMin, _, xRange = GetEffectiveXRange()
    local pad = Core.PADDING
    local scale = graphFrame:GetEffectiveScale()
    local left = graphFrame:GetLeft()
    local cx = select(1, GetCursorPosition()) / scale - left
    local level = xMin + ((cx - pad.left) / plotW) * xRange
    return math.max(xMin, math.min(xMin + xRange, level))
end

local function UpdateSelectionOverlay(startLevel, endLevel)
    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    local xMin, _, xRange = GetEffectiveXRange()
    local pad = Core.PADDING
    local lo = math.max(xMin, math.min(startLevel, endLevel))
    local hi = math.min(xMin + xRange, math.max(startLevel, endLevel))
    local x1 = pad.left + plotW * ((lo - xMin) / xRange)
    local x2 = pad.left + plotW * ((hi - xMin) / xRange)
    selectionOverlay:ClearAllPoints()
    selectionOverlay:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", x1, pad.bottom)
    selectionOverlay:SetPoint("TOPRIGHT", graphFrame, "BOTTOMLEFT", x2, pad.bottom + plotH)
    selectionOverlay:Show()
end

local function FinalizeDragSelection()
    if not isDragSelecting then
        return
    end
    isDragSelecting = false
    selectionOverlay:Hide()
    local endLevel = CursorToLevel()
    local fullMin, fullMax = LPD.AXIS_MIN_LEVEL, LPD.AXIS_MAX_LEVEL
    local newMin, newMax = Logic.NormalizeZoomRange(
        dragStartLevel, endLevel, fullMin, fullMax, ZOOM_MIN_SPAN
    )
    dragStartLevel = nil
    if not newMin then
        return
    end
    zoomMinLevel = newMin
    zoomMaxLevel = newMax
    zoomResetBtn:Show()
    RebuildGraph()
end

graphFrame:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not currentX then
        return
    end
    local hadHoverPreview = hoveredCompareEntry ~= nil
        or hoveredCompareSelectAll
        or hoveredLogarithmicPreview
        or hoveredOutliersPreview
        or hoveredRollingAveragePreview
    ClearHoverPreviewState()
    dragStartLevel = CursorToLevel()
    isDragSelecting = true
    ReleaseCursorLine()
    UpdateSelectionOverlay(dragStartLevel, dragStartLevel)
    if hadHoverPreview then
        RebuildGraph()
    end
end)

graphFrame:SetScript("OnEnter", function()
    graphMouseOver = true
    UpdateCursorLine()
end)

graphFrame:SetScript("OnLeave", function()
    graphMouseOver = false
    ReleaseCursorLine()
end)

graphFrame:SetScript("OnUpdate", function()
    if isDragSelecting then
        if not IsMouseButtonDown("LeftButton") then
            FinalizeDragSelection()
        else
            UpdateSelectionOverlay(dragStartLevel, CursorToLevel())
        end
        return
    end
    if graphMouseOver then
        UpdateCursorLine()
    end
end)

zoomResetBtn:SetScript("OnClick", function()
    ClearZoom()
    RebuildGraph()
end)

local HINT_SELECT_CHARACTERS = "Select one or more characters on the right"
local HINT_LEVEL_UP_PROGRESSION =
    "As you level up your characters\nthis page will display graphs of their progression"
local HINT_NO_HISTORY = "No level history yet.\nLevel up characters while\nlevel history is enabled."

local graphHint = graphFrame:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
graphHint:SetPoint("CENTER", graphFrame, "CENTER", 0, 0)
graphHint:SetWidth(graphFrame:GetWidth() - 40)
graphHint:SetText(HINT_SELECT_CHARACTERS)
graphHint:SetJustifyH("CENTER")

local function UpdateEmptyGraphHint()
    if not LPD or not LPD.GetCharactersWithHistory then return end

    local list = LPD.GetCharactersWithHistory()
    local insufficientList = {}
    if LPD.GetCharactersWithInsufficientHistory then
        insufficientList = LPD.GetCharactersWithInsufficientHistory()
    end

    if #list == 0 and #insufficientList == 0 then
        graphHint:SetText(HINT_NO_HISTORY)
    elseif #list == 0 then
        graphHint:SetText(HINT_LEVEL_UP_PROGRESSION)
    else
        graphHint:SetText(HINT_SELECT_CHARACTERS)
    end
end

-- Options panel (top right)
local optionsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
optionsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
optionsPanel:SetSize(SELECTOR_WIDTH, OPTIONS_PANEL_HEIGHT_FULL)
Theme.ApplyBackdrop(optionsPanel, "content")

local metricDropdown = Theme.CreateSingleSelectDropdown({
    parent = optionsPanel,
    dropdownParent = frame,
    popupAlign = "right",
    width = SELECTOR_WIDTH - 12,
    rowHeight = METRIC_DROPDOWN_HEIGHT,
    point = "TOPLEFT",
    relativeTo = optionsPanel,
    relativePoint = "TOPLEFT",
    x = 6,
    y = -6,
    entries = (LPD and LPD.GetMetricEntries and LPD.GetMetricEntries()) or {
        { id = "timePerLevel", label = "Time per level" },
        { id = "cumulativePlayed", label = "Cumulative play time" },
    },
    getSelectedId = function()
        return GetSelectedMetric()
    end,
    onSelect = function(id)
        EnsureSettings().metric = (LPD and LPD.NormalizeMetric and LPD.NormalizeMetric(id)) or id
        UpdateMetricDependentOptions()
        RebuildGraph()
    end,
})

local function CreateOptionRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(OPTION_ROW_HEIGHT)
    row:EnableMouse(true)

    Theme.InstallHoverTint(row)

    row.check = Theme.CreateThemeCheckbox(row)
    row.check:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    return row
end

local logRow = CreateOptionRow(optionsPanel)
logRow:SetPoint("TOPLEFT", metricDropdown.button, "BOTTOMLEFT", 0, -METRIC_TO_OPTIONS_GAP)
logRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
logRow.label:SetText("Logarithmic")
logRow.check:SetChecked(EnsureSettings().logarithmic == true)
logRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().logarithmic end,
    function(v) EnsureSettings().logarithmic = v end,
    function() hoveredLogarithmicPreview = false end,
    function() suppressLogarithmicHoverPreview = true end
))

local outlierRow = CreateOptionRow(optionsPanel)
outlierRow:SetPoint("TOPLEFT", logRow, "BOTTOMLEFT", 0, -OPTION_ROW_GAP)
outlierRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
outlierRow.label:SetText("Shrink Outliers")
outlierRow.infoIcon = outlierRow:CreateTexture(nil, "ARTWORK")
outlierRow.infoIcon:SetTexture("Interface\\Common\\help-i")
outlierRow.infoIcon:SetSize(OUTLIER_INFO_ICON_SIZE, OUTLIER_INFO_ICON_SIZE)
outlierRow.infoIcon:SetPoint("RIGHT", outlierRow, "RIGHT", 0, 0)
outlierRow.label:ClearAllPoints()
outlierRow.label:SetPoint("LEFT", outlierRow.check, "RIGHT", 2, 0)
outlierRow.label:SetPoint("RIGHT", outlierRow.infoIcon, "LEFT", -4, 0)
outlierRow.check:SetChecked(EnsureSettings().ignoreOutliers == true)
outlierRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().ignoreOutliers end,
    function(v) EnsureSettings().ignoreOutliers = v end,
    function() hoveredOutliersPreview = false end,
    function() suppressOutliersHoverPreview = true end
))

local rollingAverageRow = CreateOptionRow(optionsPanel)
rollingAverageRow:SetPoint("TOPLEFT", outlierRow, "BOTTOMLEFT", 0, -OPTION_ROW_GAP)
rollingAverageRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
rollingAverageRow.label:SetText("Rolling Average")
rollingAverageRow.check:SetChecked(EnsureSettings().rollingAverage == true)
rollingAverageRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().rollingAverage end,
    function(v) EnsureSettings().rollingAverage = v end,
    function() hoveredRollingAveragePreview = false end,
    function() suppressRollingAverageHoverPreview = true end
))

UpdateMetricDependentOptions = function()
    local cumulative = IsCumulativePlayedMetric()
    outlierRow:SetShown(not cumulative)
    rollingAverageRow:SetShown(not cumulative)
    optionsPanel:SetHeight(cumulative and OPTIONS_PANEL_HEIGHT_CUMULATIVE or OPTIONS_PANEL_HEIGHT_FULL)
    if cumulative then
        hoveredOutliersPreview = false
        hoveredRollingAveragePreview = false
        suppressOutliersHoverPreview = false
        suppressRollingAverageHoverPreview = false
        SetRowHoverHighlight(outlierRow, false)
        SetRowHoverHighlight(rollingAverageRow, false)
        if HideOutlierOptionTooltip then
            HideOutlierOptionTooltip()
        end
    end
end

-- Selector panel
local selectorPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
selectorPanel:SetPoint("TOPRIGHT", optionsPanel, "BOTTOMRIGHT", 0, -SECTION_GAP)
selectorPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
selectorPanel:SetWidth(SELECTOR_WIDTH)
Theme.ApplyBackdrop(selectorPanel, "content")

local selectorTitle = selectorPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
selectorTitle:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 8, -8)
selectorTitle:SetText("Compare")
Theme.SetTitleColor(selectorTitle)

local selectorScroll = CreateFrame("ScrollFrame", nil, selectorPanel)
selectorScroll:SetPoint("TOPLEFT", selectorTitle, "BOTTOMLEFT", 0, -6)
selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, 4)
selectorScroll:EnableMouse(true)
selectorScroll:EnableMouseWheel(true)

local selectorChild = CreateFrame("Frame", nil, selectorScroll)
selectorChild:SetPoint("TOPLEFT", selectorScroll, "TOPLEFT", 0, 0)
selectorChild:SetWidth(1)
selectorScroll:SetScrollChild(selectorChild)

local selectorScrollBinding = Theme.CreateVerticalScrollBinding(selectorScroll, {
    parent = selectorPanel,
    step = ROW_HEIGHT * 2,
})
local selectorScrollBar = selectorScrollBinding.bar
Theme.AnchorVerticalScrollBar(selectorScrollBar, selectorPanel, selectorScroll,
        { bottomInset = AltArmy.WINDOW_GRIP_INSET }) -- clear of the window's grip

local function UpdateSelectorScrollbar()
    selectorScrollBinding.UpdateRange()
end

selectorChild:SetScript("OnMouseWheel", function(_, delta)
    selectorScrollBinding.Wheel(delta)
end)

local selectorRows = {}
local insufficientRows = {}
local selectAllRow = nil

-- Recolors compare-row swatches from selectedColorByKey so selected same-class
-- rows show their variation; unselected rows fall back to the exact class color.
local function UpdateCompareSwatchColors()
    for _, row in ipairs(selectorRows) do
        if row:IsShown() and row.entry then
            local r, g, b = LPD.GetClassColor(row.entry.classFile)
            local varied = selectedColorByKey[EntryKey(row.entry)]
            if varied then
                r, g, b = varied.r, varied.g, varied.b
            end
            row.swatch:SetVertexColor(r, g, b, 1)
        end
    end
end

-- Divider rows naming each realm and faction group of the compare list (CharacterFilter.GroupByRealmFaction).
local groupDividers = {}
local function GetGroupDivider(i)
    if not groupDividers[i] then
        groupDividers[i] = Theme.CreateLabeledDividerRow(selectorChild)
    end
    return groupDividers[i]
end

local insufficientHeader = selectorChild:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
insufficientHeader:SetText("Not enough data:")
insufficientHeader:Hide()

local function UpdateSelectorLayout(hasCompareSection)
    if hasCompareSection then
        selectorTitle:Show()
        selectorScroll:ClearAllPoints()
        selectorScroll:SetPoint("TOPLEFT", selectorTitle, "BOTTOMLEFT", 0, -6)
        selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, 4)
    else
        selectorTitle:Hide()
        selectorScroll:ClearAllPoints()
        selectorScroll:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 4, -8)
        selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, 4)
    end
    Theme.AnchorVerticalScrollBar(selectorScrollBar, selectorPanel, selectorScroll,
        { bottomInset = AltArmy.WINDOW_GRIP_INSET }) -- clear of the window's grip
end

local function PositionListRow(row, yOffset)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 0, -yOffset)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("RIGHT", selectorChild, "RIGHT", 0, 0)
end

local function GetSelectorRow(i)
    if not selectorRows[i] then
        local row = CreateFrame("Frame", nil, selectorChild)
        row:EnableMouse(true)

        Theme.InstallHoverTint(row)

        row.check = Theme.CreateThemeCheckbox(row)
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)

        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")

        row.label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row.nameButton = CreateFrame("Button", nil, row)
        row.nameButton:SetPoint("TOPLEFT", row.swatch, "TOPLEFT", -2, 0)
        row.nameButton:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
        row.nameButton:SetFrameLevel(row:GetFrameLevel() + 2)
        row.nameButton:RegisterForClicks("LeftButtonUp")

        selectorRows[i] = row
    end
    return selectorRows[i]
end

local function GetInsufficientRow(i)
    if not insufficientRows[i] then
        local row = CreateFrame("Frame", nil, selectorChild)

        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")

        row.label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        insufficientRows[i] = row
    end
    return insufficientRows[i]
end

local function CountCompareSelected(list)
    local count = 0
    for _, entry in ipairs(list) do
        if IsSelected(entry) then
            count = count + 1
        end
    end
    return count
end

local function AreAllCompareSelected()
    local list = GetCompareList()
    return Logic.IsCompareSelectAllChecked(#list, CountCompareSelected(list))
end

local function SetAllCompareSelected(selectAll)
    for _, entry in ipairs(GetCompareList()) do
        SetSelected(entry, selectAll)
    end
end

local function EnsureSelectAllRow()
    if selectAllRow then
        return selectAllRow
    end

    selectAllRow = CreateFrame("Frame", nil, selectorChild)
    selectAllRow:EnableMouse(true)

    Theme.InstallHoverTint(selectAllRow)

    selectAllRow.check = Theme.CreateThemeCheckbox(selectAllRow)
    selectAllRow.check:SetPoint("LEFT", selectAllRow, "LEFT", 2, 0)

    selectAllRow.label = selectAllRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    selectAllRow.label:SetPoint("LEFT", selectAllRow.check, "RIGHT", 2, 0)
    selectAllRow.label:SetPoint("RIGHT", selectAllRow, "RIGHT", -2, 0)
    selectAllRow.label:SetJustifyH("LEFT")
    selectAllRow.label:SetWordWrap(false)
    selectAllRow.label:SetText("All")

    selectAllRow.labelButton = CreateFrame("Button", nil, selectAllRow)
    selectAllRow.labelButton:SetPoint("TOPLEFT", selectAllRow.label, "TOPLEFT", -2, 0)
    selectAllRow.labelButton:SetPoint("BOTTOMRIGHT", selectAllRow, "BOTTOMRIGHT", -2, 0)
    selectAllRow.labelButton:SetFrameLevel(selectAllRow:GetFrameLevel() + 2)
    selectAllRow.labelButton:RegisterForClicks("LeftButtonUp")
    selectAllRow.labelButton:SetScript("OnClick", function()
        selectAllRow.check:Click()
    end)

    selectAllRow.check:SetScript("OnClick", function(self)
        local wasSelectAll = AreAllCompareSelected()
        local selectAll = Logic.GetCompareSelectAllAction(wasSelectAll)
        SetAllCompareSelected(selectAll)
        self:SetChecked(selectAll)
        for _, row in ipairs(selectorRows) do
            if row:IsShown() and row.entry then
                row.check:SetChecked(selectAll)
            end
        end
        if wasSelectAll and not selectAll then
            if hoveredCompareSelectAll then
                hoveredCompareSelectAll = false
                selectAllRow.suppressHoverPreview = true
            end
            if hoveredCompareEntry then
                local hoverKey = EntryKey(hoveredCompareEntry)
                hoveredCompareEntry = nil
                for _, row in ipairs(selectorRows) do
                    if row:IsShown() and row.entry and EntryKey(row.entry) == hoverKey then
                        row.suppressHoverPreview = true
                        break
                    end
                end
            end
        end
        RebuildGraph()
    end)

    BindSelectAllRowHover(selectAllRow)

    return selectAllRow
end

UpdateSelectAllCheckbox = function()
    if selectAllRow and selectAllRow:IsShown() then
        selectAllRow.check:SetChecked(AreAllCompareSelected())
    end
end

local function FormatDurationUnit(value, singular, plural)
    if value == 1 then
        return "1 " .. singular
    end
    return string.format("%d %s", value, plural)
end

local function FormatDurationPrecise(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds <= 0 then
        return "0 seconds"
    end

    local days = math.floor(seconds / 86400)
    local rem = seconds % 86400
    local hours = math.floor(rem / 3600)
    rem = rem % 3600
    local minutes = math.floor(rem / 60)
    local secs = rem % 60

    local parts = {}
    if days > 0 then
        parts[#parts + 1] = FormatDurationUnit(days, "day", "days")
    end
    if hours > 0 then
        parts[#parts + 1] = FormatDurationUnit(hours, "hour", "hours")
    end
    if minutes > 0 then
        parts[#parts + 1] = FormatDurationUnit(minutes, "minute", "minutes")
    end
    if secs > 0 and days == 0 and hours == 0 then
        parts[#parts + 1] = FormatDurationUnit(secs, "second", "seconds")
    end

    if #parts == 0 then
        return "0 seconds"
    end
    return table.concat(parts, " ")
end

local function FormatTooltipTitle(entry)
    local name = (entry and entry.name) or "?"
    local realm = entry and entry.realm
    local classFile = entry and entry.classFile
    if RF and RF.formatColoredCharacterNameRealm then
        return RF.formatColoredCharacterNameRealm(name, realm, true, classFile)
    end
    if realm and realm ~= "" then
        return name .. " — " .. realm
    end
    return name
end

local function ShowSegmentTooltip(owner, entry, fromLevel, toLevel, totalSeconds, ySeconds)
    if not GameTooltip or not owner then return end

    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(FormatTooltipTitle(entry), 1, 1, 1, true)

    if IsCumulativePlayedMetric() then
        GameTooltip:AddLine(string.format("Level %d", toLevel), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(
            "Total played: " .. FormatDurationPrecise(ySeconds),
            0.9, 0.9, 0.9, true
        )
        if totalSeconds and totalSeconds > 0 and fromLevel and toLevel and toLevel > fromLevel then
            GameTooltip:AddLine(
                string.format(
                    "(+%s from %d-%d)",
                    FormatDurationPrecise(totalSeconds),
                    fromLevel,
                    toLevel
                ),
                0.9, 0.9, 0.9, true
            )
        end
    else
        GameTooltip:AddLine(string.format("Level %d-%d", fromLevel, toLevel), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(FormatDurationPrecise(totalSeconds), 0.9, 0.9, 0.9, true)
        local levelSpan = toLevel - fromLevel
        if levelSpan > 1 then
            local perLevel = ySeconds or (totalSeconds / levelSpan)
            GameTooltip:AddLine(
                string.format("(%s per level)", FormatDurationPrecise(perLevel)),
                0.9, 0.9, 0.9, true
            )
        end
    end
    GameTooltip:Show()
end

local function ShowOutlierOptionTooltip(owner)
    if not GameTooltip or not owner then return end

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Shrink Outliers", 1, 1, 1, true)
    GameTooltip:AddLine(
        "Extremely long times are artificially shifted down so you can see more details on the other levels.",
        0.9, 0.9, 0.9, true
    )
    GameTooltip:AddLine(
        "For example, if your character spent several days at level 29 to do that bracket of pvp, "
            .. "the graph can be hard to read unless you turn this feature on.",
        0.9, 0.9, 0.9, true
    )
    GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
    GameTooltip:Show()
end

HideOutlierOptionTooltip = function()
    if GameTooltip then GameTooltip:Hide() end
end

UpdateMetricDependentOptions()

local function ReleaseMarkerDot(dot)
    if not dot then return end
    dot:Hide()
    table.insert(markerDotPool.free, dot)
end

local function ReleaseMarkerHit(hf)
    if not hf then return end
    hf:Hide()
    hf:SetScript("OnEnter", nil)
    hf:SetScript("OnLeave", nil)
    table.insert(markerHitPool.free, hf)
end

local function AcquireMarkerDot(r, g, b, alpha, px, py)
    local dot = table.remove(markerDotPool.free)
    if not dot then
        dot = graphFrame:CreateTexture(nil, "OVERLAY")
    end
    dot:ClearAllPoints()
    dot:SetColorTexture(r, g, b, alpha or 1)
    dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
    dot:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    dot:Show()
    return dot
end

local function AcquireMarkerHit(px, py)
    local hf = table.remove(markerHitPool.free)
    if not hf then
        hf = CreateFrame("Frame", nil, graphFrame)
        hf:EnableMouse(true)
        hf:SetFrameLevel(graphFrame:GetFrameLevel() + 50)
    end
    hf:ClearAllPoints()
    hf:SetSize(MARKER_HIT_SIZE, MARKER_HIT_SIZE)
    hf:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    hf:Show()
    return hf
end

local function AddStyledObject(group, obj, r, g, b, fullAlpha, dimAlpha, useColorTexture)
    if not obj then
        return
    end
    group.objects[#group.objects + 1] = {
        obj = obj,
        r = r,
        g = g,
        b = b,
        fullAlpha = fullAlpha,
        dimAlpha = dimAlpha,
        useColorTexture = useColorTexture,
    }
end

local function ApplyObjectAlpha(styled, dimOthers, isHovered)
    if not styled.obj then
        return
    end
    local alpha = dimOthers and (isHovered and styled.fullAlpha or styled.dimAlpha) or styled.fullAlpha
    if styled.useColorTexture then
        styled.obj:SetColorTexture(styled.r, styled.g, styled.b, alpha)
    else
        styled.obj:SetVertexColor(styled.r, styled.g, styled.b, alpha)
    end
end

local function TrackNewCoreObjects(group, r, g, b, fullAlpha, dimAlpha, lineCountBefore, texCountBefore)
    for i = lineCountBefore + 1, #Core.graphLines do
        AddStyledObject(group, Core.graphLines[i], r, g, b, fullAlpha, dimAlpha)
    end
    for i = texCountBefore + 1, #Core.graphTextures do
        AddStyledObject(group, Core.graphTextures[i], r, g, b, fullAlpha, dimAlpha)
    end
end

local function AddSegmentMarker(group, px, py, r, g, b, alpha, entry, pt)
    local dot = AcquireMarkerDot(r, g, b, alpha, px, py)
    group.markerDots[#group.markerDots + 1] = dot
    AddStyledObject(group, dot, r, g, b, FULL_LINE_ALPHA, DIM_LINE_ALPHA, true)

    local hf = AcquireMarkerHit(px, py)
    group.markerHits[#group.markerHits + 1] = hf

    hf:SetScript("OnEnter", function(self)
        dot:SetSize(MARKER_DOT_SIZE + 3, MARKER_DOT_SIZE + 3)
        ShowSegmentTooltip(self, entry, pt.fromLevel, pt.toLevel, pt.totalSeconds, pt.seconds)
    end)
    hf:SetScript("OnLeave", function()
        dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function ReleaseSeriesGroupResources(group)
    if not group then return end
    for _, styled in ipairs(group.objects) do
        if styled.obj then
            Core.ReleaseDrawnObject(styled.obj)
        end
    end
    wipe(group.objects)
    for _, dot in ipairs(group.markerDots) do
        ReleaseMarkerDot(dot)
    end
    wipe(group.markerDots)
    for _, hf in ipairs(group.markerHits) do
        ReleaseMarkerHit(hf)
    end
    wipe(group.markerHits)
end

local function ReleaseAllSeriesGroups()
    for i = #seriesGroups, 1, -1 do
        ReleaseSeriesGroupResources(seriesGroups[i])
    end
    wipe(seriesGroups)
    wipe(drawnKeys)
end

local function GetSeriesSecondsBounds(entry)
    if not LPD or not entry or not Logic then return 0, 0 end
    local series = GetSeriesForEntry(entry)
    local drawable = LPD.PrepareDrawableSeries(series)
    local marked = Logic.ApplyOutlierFlags(drawable.usable, IsIgnoreOutliers())
    if IsRollingAverage() then
        marked = Logic.ApplyRollingAverage(
            marked,
            Logic.ROLLING_AVERAGE_WINDOW,
            IsIgnoreOutliers()
        )
    end
    return Logic.GetSeriesScaleBounds(marked, true, GetLevelBoundsForScale())
end

local function PrepareCharGraphData(entry, drawable)
    local ignoreOutliers = IsIgnoreOutliers()
    local markedPoints = Logic.ApplyOutlierFlags(drawable.usable, ignoreOutliers)
    if IsRollingAverage() then
        markedPoints = Logic.ApplyRollingAverage(
            markedPoints,
            Logic.ROLLING_AVERAGE_WINDOW,
            ignoreOutliers
        )
    end
    local drawPlan = Logic.BuildSeriesDrawPlan(markedPoints)
    local cr, cg, cb = LPD.GetClassColor(entry.classFile)
    local varied = selectedColorByKey[EntryKey(entry)]
    if varied then
        cr, cg, cb = varied.r, varied.g, varied.b
    end
    return {
        entry = entry,
        drawable = drawable,
        markedPoints = markedPoints,
        drawPlan = drawPlan,
        r = cr,
        g = cg,
        b = cb,
    }
end

local function DrawLineSegment(group, x1, y1, x2, y2, style, r, g, b)
    if style == "dashed" then
        local lineCountBefore = #Core.graphLines
        local texCountBefore = #Core.graphTextures
        Core.CreateDashedLine(graphFrame, x1, y1, x2, y2, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
        TrackNewCoreObjects(group, r, g, b, FULL_DASH_ALPHA, DIM_DASH_ALPHA, lineCountBefore, texCountBefore)
    else
        local line = Core.CreateLine(graphFrame, x1, y1, x2, y2, LINE_THICKNESS, r, g, b, FULL_LINE_ALPHA)
        AddStyledObject(group, line, r, g, b, FULL_LINE_ALPHA, DIM_LINE_ALPHA)
    end
end

local function DrawLeadingGap(group, gap, endPt, X, Y, logarithmic, r, g, b)
    local lineCountBefore = #Core.graphLines
    local texCountBefore = #Core.graphTextures
    local cumulative = IsCumulativePlayedMetric()
    -- Time-per-level gaps are linear in data space (straight on a linear axis).
    -- Cumulative play time is the integral of that ramp, so use a quadratic curve.
    if logarithmic or cumulative then
        local curveMode = cumulative
            and Logic.LEADING_GAP_CURVE_QUADRATIC
            or Logic.LEADING_GAP_CURVE_LINEAR
        local axisFloor = logarithmic and currentLogAxisYMin or nil
        local samples = Logic.SampleLeadingGapCurve(gap, endPt, nil, axisFloor, curveMode)
        local screenPoints = {}
        for _, sample in ipairs(samples) do
            screenPoints[#screenPoints + 1] = {
                x = X(sample.level),
                y = Y(sample.seconds),
            }
        end
        Core.CreateDashedPolyline(graphFrame, screenPoints, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
    else
        local x, y = X(endPt.level), Y(endPt.seconds)
        local gx1, gy1 = X(gap.fromLevel), Y(0)
        Core.CreateDashedLine(graphFrame, gx1, gy1, x, y, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
    end
    TrackNewCoreObjects(group, r, g, b, FULL_DASH_ALPHA, DIM_DASH_ALPHA, lineCountBefore, texCountBefore)
end

local function PlotSeriesPoint(pt, X, Y, plotTopY)
    return Logic.PlotSeriesPoint(pt, X(pt.level), Y(pt.seconds), plotTopY)
end

local function DrawSeriesGroup(charData, X, Y, logarithmic, plotH)
    local group = {
        key = EntryKey(charData.entry),
        entry = charData.entry,
        objects = {},
        markerDots = {},
        markerHits = {},
    }
    local drawable = charData.drawable
    local drawPlan = charData.drawPlan
    if IsZoomed() then
        drawPlan = Logic.ClipDrawPlanToRange(drawPlan, zoomMinLevel, zoomMaxLevel)
    end
    local r, g, b = charData.r, charData.g, charData.b
    local entry = charData.entry
    local firstMarker = drawPlan.markers[1]
    local plotTopY = Logic.ComputePlotTopY(plotH, Core.PADDING)

    if drawable.leadingGap and firstMarker and (not IsZoomed() or zoomMinLevel <= LPD.AXIS_MIN_LEVEL) then
        DrawLeadingGap(group, drawable.leadingGap, firstMarker.pt, X, Y, logarithmic, r, g, b)
    end

    for _, seg in ipairs(drawPlan.segments) do
        local x1, y1 = PlotSeriesPoint(seg.from, X, Y, plotTopY)
        local x2, y2 = PlotSeriesPoint(seg.to, X, Y, plotTopY)
        DrawLineSegment(group, x1, y1, x2, y2, seg.style, r, g, b)
    end

    if not IsRollingAverage() then
        for _, marker in ipairs(drawPlan.markers) do
            local pt = marker.pt
            local x, y = PlotSeriesPoint(pt, X, Y, plotTopY)
            AddSegmentMarker(group, x, y, r, g, b, FULL_LINE_ALPHA, entry, pt)
        end
    end

    return group
end

local function AddHoveredSeries(entry)
    if not currentX or not currentY or not entry then return end

    local key = EntryKey(entry)
    if drawnKeys[key] then return end

    local series = GetSeriesForEntry(entry)
    local drawable = LPD.PrepareDrawableSeries(series)
    if #drawable.usable < 1 then return end

    local charData = PrepareCharGraphData(entry, drawable)
    local _, plotH = Core.CalculatePlotDimensions(graphFrame)
    local group = DrawSeriesGroup(charData, currentX, currentY, IsLogarithmic(), plotH)
    drawnKeys[key] = true
    seriesGroups[#seriesGroups + 1] = group
end

ApplyHighlight = function()
    if #seriesGroups == 0 then return end

    local hoverKey = hoveredCompareEntry and EntryKey(hoveredCompareEntry) or nil
    local dimOthers = hoverKey ~= nil

    for _, group in ipairs(seriesGroups) do
        local isHovered = hoverKey and group.key == hoverKey
        for _, styled in ipairs(group.objects) do
            ApplyObjectAlpha(styled, dimOthers, isHovered)
        end
    end
end

RebuildGraph = function()
    if not Core or not LPD or not Logic then return end

    ReleaseAllSeriesGroups()
    Core.ClearObjects()

    selectedColorByKey = BuildSelectedColorByKey()
    UpdateCompareSwatchColors()

    currentX, currentY = nil, nil
    currentRawYMax = 0
    currentRawYMin = 0
    currentLogAxisYMin = nil

    local toDraw = GetCharactersToDraw()
    if #toDraw == 0 then
        graphHint:Show()
        UpdateEmptyGraphHint()
        RefreshCursorLineAfterRebuild()
        return
    end

    local seriesByChar = {}
    local yMax = 0
    local yMin = math.huge
    local scaleMinLevel, scaleMaxLevel = GetLevelBoundsForScale()

    for _, entry in ipairs(toDraw) do
        local series = GetSeriesForEntry(entry)
        local drawable = LPD.PrepareDrawableSeries(series)
        if #drawable.usable >= 1 then
            local charData = PrepareCharGraphData(entry, drawable)
            seriesByChar[#seriesByChar + 1] = charData
            local scaleMin, scaleMax = Logic.GetSeriesScaleBounds(
                charData.markedPoints, true, scaleMinLevel, scaleMaxLevel
            )
            if scaleMin > 0 and scaleMin < yMin then yMin = scaleMin end
            if scaleMax > yMax then yMax = scaleMax end
        end
    end

    if yMin == math.huge then
        yMin = 0
    end

    if #seriesByChar == 0 then
        graphHint:SetText("Selected characters have no\nusable level history.")
        graphHint:Show()
        RefreshCursorLineAfterRebuild()
        return
    end

    graphHint:Hide()

    local xMin, _, xRange = GetEffectiveXRange()
    local xLabelInterval = Logic.ChooseXLabelInterval(xRange)

    currentRawYMax = yMax
    currentRawYMin = yMin
    local logarithmic = IsLogarithmic()
    local linearAxis = Logic.ComputeLinearYAxis(yMax)
    local logAxis = logarithmic and Logic.ComputeLogYAxis(yMax, yMin, IsZoomed()) or nil
    currentLogAxisYMin = logAxis and logAxis.yMin or nil

    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    if logarithmic and logAxis then
        currentX, currentY = Core.CreateTransformers(plotW, plotH, xMin, xRange, logAxis.yMin, 0, {
            yAxisMode = "log",
            logMin = logAxis.logMin,
            logMax = logAxis.logMax,
        })
    else
        currentX, currentY = Core.CreateTransformers(plotW, plotH, xMin, xRange, linearAxis.yMin, linearAxis.yRange)
    end

    local gridOpts = {
        xInterval = xLabelInterval,
        xMin = xMin,
        xRange = xRange,
        yMin = linearAxis.yMin,
        yRange = linearAxis.yRange,
    }
    if logarithmic and logAxis then
        gridOpts.logYTicks = Logic.FilterLogYGridTicks(
            logAxis.gridTicks,
            logAxis.logMin,
            logAxis.logMax,
            Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
        )
        gridOpts.logMin = logAxis.logMin
        gridOpts.logMax = logAxis.logMax
    else
        gridOpts.linearYTicks = linearAxis.gridTicks
    end

    Core.RenderGridLines(graphFrame, plotW, plotH, gridOpts)
    Core.RenderAxes(graphFrame, plotW, plotH, logarithmic and { yAxisBreak = true } or nil)
    Core.RenderYLabels(graphFrame, plotH, linearAxis.yMin, linearAxis.yRange, function(v)
        return Core.FormatDurationAxis(v)
    end, gridOpts)
    Core.RenderXLabelsAtInterval(graphFrame, plotW, xMin, xRange, xLabelInterval, function(v)
        return tostring(math.floor(v + 0.5))
    end)

    if IsZoomed() then
        zoomResetBtn:Show()
    end

    for _, charData in ipairs(seriesByChar) do
        local group = DrawSeriesGroup(charData, currentX, currentY, logarithmic, plotH)
        drawnKeys[group.key] = true
        seriesGroups[#seriesGroups + 1] = group
    end

    ApplyHighlight()
    RefreshCursorLineAfterRebuild()
end

HandleCompareSelectAllEnter = function(row)
    if isDragSelecting then
        return
    end
    SetRowHoverHighlight(row, true)

    if row.suppressHoverPreview then
        return
    end

    hoveredCompareEntry = nil
    hoveredCompareSelectAll = true
    RebuildGraph()
end

HandleCompareSelectAllLeave = function(row)
    if isDragSelecting then
        return
    end
    row.suppressHoverPreview = false
    hoveredCompareSelectAll = false
    SetRowHoverHighlight(row, false)
    RebuildGraph()
end

HandleCompareRowEnter = function(row, entry)
    if isDragSelecting then
        return
    end
    SetRowHoverHighlight(row, true)

    if row.suppressHoverPreview then
        return
    end

    hoveredCompareSelectAll = false
    hoveredCompareEntry = entry

    local key = EntryKey(entry)
    if drawnKeys[key] then
        ApplyHighlight()
        return
    end

    if #seriesGroups == 0 then
        RebuildGraph()
        return
    end

    local minSec, maxSec = GetSeriesSecondsBounds(entry)
    if Logic.HoverNeedsRebuild(key, drawnKeys, maxSec, currentRawYMax, minSec, currentRawYMin, IsLogarithmic()) then
        RebuildGraph()
        return
    end

    AddHoveredSeries(entry)
    ApplyHighlight()
end

HandleCompareRowLeave = function(row, entry)
    if isDragSelecting then
        return
    end
    row.suppressHoverPreview = false
    hoveredCompareEntry = nil
    SetRowHoverHighlight(row, false)

    if IsSelected(entry) then
        ApplyHighlight()
        return
    end

    RebuildGraph()
end

local function FormatCharacterLabel(entry, showRealmSuffix)
    local name = (entry and entry.name) or "?"
    local realm = entry and entry.realm
    local classFile = entry and entry.classFile
    if RF and RF.formatColoredCharacterNameRealm then
        -- omit inline bank icon; Graphs selector has no separate bank column
        return RF.formatColoredCharacterNameRealm(name, realm, showRealmSuffix, classFile, false)
    end
    if showRealmSuffix and realm and realm ~= "" then
        return name .. " — " .. realm
    end
    return name
end

local function RefreshSelector()
    if not LPD or not LPD.GetCharactersWithHistory then return end
    local list = GetCompareList()
    local insufficientList = {}
    if LPD.GetCharactersWithInsufficientHistory then
        insufficientList = LPD.GetCharactersWithInsufficientHistory()
    end

    for _, row in ipairs(selectorRows) do
        row:Hide()
    end
    for _, row in ipairs(insufficientRows) do
        row:Hide()
    end
    for _, line in ipairs(groupDividers) do
        line:Hide()
    end
    insufficientHeader:Hide()
    UpdateSelectorLayout(#list > 0)

    local scrollW = selectorScroll:GetWidth() or SELECTOR_WIDTH - 12
    selectorChild:SetWidth(scrollW)

    local yOffset = 0
    if Logic.ShouldShowCompareSelectAll(#list) then
        local allRow = EnsureSelectAllRow()
        PositionListRow(allRow, yOffset)
        allRow:Show()
        allRow.check:SetChecked(AreAllCompareSelected())
        SetRowHoverHighlight(allRow, hoveredCompareSelectAll)
        yOffset = yOffset + ROW_HEIGHT
    elseif selectAllRow then
        selectAllRow:Hide()
    end

    -- Every character, whatever the Summary's filters, grouped by realm and faction as the Summary's
    -- sections are, each group under a divider naming it (so the rows don't name the realm).
    local CF = AltArmy.CharacterFilter
    local ctx = CF.Context()
    local dividers = 0
    local function Grouped(entries)
        local ordered, groupStarts = {}, {}
        for _, group in ipairs(CF.GroupByRealmFaction(entries, ctx)) do
            groupStarts[#ordered + 1] = CF.GroupLabel(group)
            for _, e in ipairs(group) do ordered[#ordered + 1] = e end
        end
        return ordered, groupStarts
    end
    local function PlaceDivider(label)
        dividers = dividers + 1
        local divider = GetGroupDivider(dividers)
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 0, -yOffset)
        divider:SetPoint("RIGHT", selectorChild, "RIGHT", 0, 0)
        divider:SetHeight(ROW_HEIGHT)
        divider:SetText(label)
        divider:Show()
        yOffset = yOffset + ROW_HEIGHT
    end
    local ordered, groupStarts = Grouped(list)
    for i, entry in ipairs(ordered) do
        if groupStarts[i] then
            PlaceDivider(groupStarts[i])
        end
        local row = GetSelectorRow(i)
        PositionListRow(row, yOffset)
        row:Show()
        row.entry = entry

        local r, g, b = LPD.GetClassColor(entry.classFile)
        row.swatch:SetVertexColor(r, g, b, 1)
        row.label:SetText(FormatCharacterLabel(entry, false))
        -- White so class/gray realm escape codes from FormatCharacterLabel render correctly
        row.label:SetTextColor(1, 1, 1, 1)

        row.check:SetChecked(IsSelected(entry))
        row.check:SetScript("OnClick", function(self)
            local wasChecked = IsSelected(entry)
            local nowChecked = self:GetChecked() and true or false
            SetSelected(entry, nowChecked)
            if wasChecked and not nowChecked then
                OnCompareRowUnchecked(row, entry)
            end
            UpdateSelectAllCheckbox()
            RebuildGraph()
        end)
        row.nameButton:SetScript("OnClick", function()
            ToggleCompareSelection(row, entry)
        end)
        BindCompareRowHover(row, entry)
        SetRowHoverHighlight(row, hoveredCompareEntry and EntryKey(hoveredCompareEntry) == EntryKey(entry))

        yOffset = yOffset + ROW_HEIGHT
    end

    if #insufficientList > 0 then
        if #list > 0 then
            yOffset = yOffset + INSUFFICIENT_SECTION_GAP
        end
        insufficientHeader:ClearAllPoints()
        insufficientHeader:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 4, -yOffset)
        insufficientHeader:Show()
        yOffset = yOffset + SECTION_HEADER_HEIGHT

        for i, entry in ipairs(insufficientList) do
            local row = GetInsufficientRow(i)
            PositionListRow(row, yOffset)
            row:Show()

            local r, g, b = LPD.GetClassColor(entry.classFile)
            row.swatch:SetVertexColor(r, g, b, 0.45)
            row.label:SetText(FormatCharacterLabel(entry, false))
            row.label:SetTextColor(1, 1, 1, 0.55)

            yOffset = yOffset + ROW_HEIGHT
        end
    end

    selectedColorByKey = BuildSelectedColorByKey()
    UpdateCompareSwatchColors()

    selectorChild:SetHeight(math.max(1, yOffset))
    UpdateSelectorScrollbar()

    if LPD.DebugLogSelectorEligibility then
        LPD.DebugLogSelectorEligibility()
    end
end

function frame:Redraw()
    RebuildGraph()
end

-- The toolbar's settings button shows and hides the right column (options and Compare); unlike other
-- tabs it starts shown. Hidden, the graph takes the whole tab.
local function ApplyRightColumnLayout()
    local shown = optionsPanel:IsShown()
    selectorPanel:SetShown(shown)
    local CF = AltArmy.ColumnFit
    if CF then
        local fitted = CF.Fit({ column = SELECTOR_FIT.stock, plot = SELECTOR_FIT.stockTab - SELECTOR_FIT.stock },
            { column = SELECTOR_FIT.flex }, frame:GetWidth(), { column = SELECTOR_FIT.cap })
        if fitted.column ~= SELECTOR_WIDTH then
            SELECTOR_WIDTH = fitted.column
            optionsPanel:SetWidth(SELECTOR_WIDTH)
            selectorPanel:SetWidth(SELECTOR_WIDTH)
            local scrollW = selectorScroll:GetWidth()
            if scrollW and scrollW > 0 then selectorChild:SetWidth(scrollW) end
        end
    end
    graphFrame:SetPoint("RIGHT", frame, "RIGHT", shown and (-SELECTOR_WIDTH - SECTION_GAP) or 0, 0)
end
ApplyRightColumnLayout()
-- The right column follows the tab's width (the window's resize grip); the plot's own size change redraws it.
frame:HookScript("OnSizeChanged", ApplyRightColumnLayout)

function frame:IsGraphSettingsShown()
    return optionsPanel:IsShown()
end

function frame:ToggleGraphSettings(_self)
    optionsPanel:SetShown(not optionsPanel:IsShown())
    ApplyRightColumnLayout()
end

-- The plot is drawn at the graph frame's size, so it is drawn again at every size change: live while
-- the window's grip is dragged (a trial of whether a rebuild per frame is quick enough; if not,
-- AltArmy.OnWindowResized tells when the drag has ended). A hidden tab redraws on show anyway.
graphFrame:HookScript("OnSizeChanged", function()
    if not frame:IsVisible() then return end
    graphHint:SetWidth(math.max(1, (graphFrame:GetWidth() or 0) - 40))
    RebuildGraph()
end)

local function WireOptionLabelClick(row, onEnter, onLeave)
    local check = row.check
    local label = row.label
    local hit = CreateFrame("Button", nil, check)
    hit:SetFrameLevel((check:GetFrameLevel() or 0) + 5)
    hit:EnableMouse(true)
    hit:RegisterForClicks("LeftButtonUp")
    hit:SetScript("OnClick", function()
        if check:IsEnabled() then
            check:Click()
        end
    end)
    hit:SetScript("OnEnter", onEnter)
    hit:SetScript("OnLeave", onLeave)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", -6, 6)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 6, -6)
end

local function BindOptionRowHover(row, setPreview, getSuppress, clearSuppress, onHoverExtra)
    local function onEnter()
        if isDragSelecting then
            return
        end
        SetRowHoverHighlight(row, true)
        if onHoverExtra then onHoverExtra(true) end
        if not getSuppress() then
            setPreview(true)
            RebuildGraph()
        end
    end

    local function onLeave()
        if isDragSelecting then
            return
        end
        setPreview(false)
        clearSuppress()
        SetRowHoverHighlight(row, false)
        if onHoverExtra then onHoverExtra(false) end
        RebuildGraph()
    end

    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row.check:SetScript("OnEnter", onEnter)
    row.check:SetScript("OnLeave", onLeave)
    WireOptionLabelClick(row, onEnter, onLeave)
end

BindOptionRowHover(logRow, function(on)
    hoveredLogarithmicPreview = on
end, function()
    return suppressLogarithmicHoverPreview
end, function()
    suppressLogarithmicHoverPreview = false
end)
BindOptionRowHover(outlierRow, function(on)
    hoveredOutliersPreview = on
end, function()
    return suppressOutliersHoverPreview
end, function()
    suppressOutliersHoverPreview = false
end, function(show)
    if show then
        ShowOutlierOptionTooltip(outlierRow)
    else
        HideOutlierOptionTooltip()
    end
end)
BindOptionRowHover(rollingAverageRow, function(on)
    hoveredRollingAveragePreview = on
end, function()
    return suppressRollingAverageHoverPreview
end, function()
    suppressRollingAverageHoverPreview = false
end)

frame:SetScript("OnHide", function()
    ClearHoverPreviewState()
    suppressLogarithmicHoverPreview = false
    suppressOutliersHoverPreview = false
    suppressRollingAverageHoverPreview = false
    if metricDropdown and metricDropdown.Close then
        metricDropdown:Close()
    end
    for _, row in ipairs(selectorRows) do
        row.suppressHoverPreview = false
    end
    if selectAllRow then
        selectAllRow.suppressHoverPreview = false
        SetRowHoverHighlight(selectAllRow, false)
    end
    SetRowHoverHighlight(logRow, false)
    SetRowHoverHighlight(outlierRow, false)
    SetRowHoverHighlight(rollingAverageRow, false)
    HideOutlierOptionTooltip()
end)

frame:SetScript("OnShow", function()
    if metricDropdown and metricDropdown.Update then
        metricDropdown:Update()
    end
    UpdateMetricDependentOptions()
    logRow.check:SetChecked(EnsureSettings().logarithmic == true)
    outlierRow.check:SetChecked(EnsureSettings().ignoreOutliers == true)
    rollingAverageRow.check:SetChecked(EnsureSettings().rollingAverage == true)
    RefreshSelector()
    frame:Redraw()
end)
