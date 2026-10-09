-- AltArmy TBC — Export dialog: shows ProfitExport's string, selected, to copy with Ctrl+C and paste on the
-- the Alt Army website's Upload tab. Opened only by `/altarmy export` (no button in the UI). Above the string,
-- a note lists characters still lacking data the export carries (SummaryData.GetExportMissingDataInfo).
-- luacheck: globals UISpecialFrames UIParent

if not AltArmy then return end

local Theme = AltArmy.Theme

local UI = {
    INSET = 8,
    HEADER_GAP = 4,
    HEADER_HEIGHT = 28,
    GAP = 12,
    BUTTON_HEIGHT = 24,
    BUTTON_WIDTH = 120,
    WIDTH = 520,
    HEIGHT = 170,
    MISSING_SHOWN = 8, -- characters listed in the missing-data warning before "...and N more"
}

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_ProfitExportDialog")
dialog:SetSize(UI.WIDTH, UI.HEIGHT)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

if UISpecialFrames then
    tinsert(UISpecialFrames, "AltArmyTBC_ProfitExportDialog") -- never assign the global: that taints it
end

local header = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
header:SetPoint("TOPLEFT", dialog, "TOPLEFT", UI.INSET, -UI.INSET)
header:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -UI.INSET, -UI.INSET)
header:SetHeight(UI.HEADER_HEIGHT)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function()
    dialog:StartMoving()
end)
header:SetScript("OnDragStop", function()
    dialog:StopMovingOrSizing()
end)
Theme.ApplyBackdrop(header, "section")

local title = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
title:SetPoint("LEFT", header, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
title:SetText("Export")
Theme.SetTitleColor(title)

local body = Theme.CreateTabContentPanel(dialog)
body:SetPoint("TOPLEFT", dialog, "TOPLEFT", UI.INSET, -(UI.INSET + UI.HEADER_HEIGHT + UI.HEADER_GAP))
body:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -UI.INSET, UI.INSET)
local inner = Theme.CreatePanelInnerContent(body)

local intro = inner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
intro:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
intro:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
intro:SetJustifyH("LEFT")
intro:SetWordWrap(true)
intro:SetTextColor(0.85, 0.85, 0.85, 1)
intro:SetText("Copy this string into the alt army website to upload your data")

-- What the export is known to lack (SummaryData's missing-data checks, export-scoped); hidden when nothing.
local missing = inner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
missing:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -UI.GAP)
missing:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
missing:SetJustifyH("LEFT")
missing:SetWordWrap(true)
missing:SetTextColor(1, 0.82, 0, 1)
missing:Hide()

-- One line holds the whole string; it is selected on show, so Ctrl+C copies all of it.
local box = CreateFrame("EditBox", nil, inner, "InputBoxTemplate")
box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -UI.GAP)
box:SetPoint("RIGHT", inner, "RIGHT", -6, 0)
box:SetHeight(24)
box:SetAutoFocus(false)
box:SetMaxLetters(0)
box:SetScript("OnEscapePressed", function()
    dialog:Hide()
end)
-- Read-only: typing puts the export back; clicking selects it all again.
box:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self.export then
        self:SetText(self.export)
        self:HighlightText()
    end
end)
box:SetScript("OnMouseUp", function(self)
    self:HighlightText()
end)

local status = inner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -UI.GAP)
status:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
status:SetJustifyH("LEFT")
status:SetWordWrap(true)
status:SetTextColor(0.6, 0.6, 0.6, 1)

local close = CreateFrame("Button", nil, inner, "UIPanelButtonTemplate")
close:SetSize(UI.BUTTON_WIDTH, UI.BUTTON_HEIGHT)
close:SetPoint("BOTTOM", inner, "BOTTOM", 0, 0)
close:SetText("Close")
Theme.SkinButton(close)
close:SetScript("OnClick", function()
    dialog:Hide()
end)

AltArmy.ProfitExportDialog = AltArmy.ProfitExportDialog or {}

--- Show the missing-data warning above the box (or hide it), growing the dialog to fit.
local function showMissing()
    local PE, SD = AltArmy.ProfitExport, AltArmy.SummaryData
    local data = AltArmyTBC_Data --luacheck: ignore 113
    local rows = PE and PE.MissingData and SD and SD.GetExportMissingDataInfo
        and PE.MissingData(data and data.Characters, SD.GetExportMissingDataInfo) or {}
    local text = PE and PE.MissingDataText and PE.MissingDataText(rows, UI.MISSING_SHOWN) or ""
    box:ClearAllPoints()
    box:SetPoint("RIGHT", inner, "RIGHT", -6, 0)
    if text == "" then
        missing:SetText("")
        missing:Hide()
        box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -UI.GAP)
        dialog:SetHeight(UI.HEIGHT)
    else
        missing:SetText(text)
        missing:Show()
        box:SetPoint("TOPLEFT", missing, "BOTTOMLEFT", 6, -UI.GAP)
        dialog:SetHeight(UI.HEIGHT + missing:GetStringHeight() + UI.GAP)
    end
end

--- Build a fresh export and show it, selected.
function AltArmy.ProfitExportDialog.Show()
    local PE = AltArmy.ProfitExport
    local export = PE and PE.Build and PE.Build()
    title:SetText("Export")
    intro:SetText("Copy this string into the alt army website to upload your data")
    box.export = export
    if export then
        box:SetText(export)
        status:SetText("")
    else
        box:SetText("")
        status:SetText("The export needs the LibDeflate library, which failed to load.")
    end
    dialog:Show()
    showMissing()
    box:SetFocus()
    box:HighlightText()
end

--- Show any one-line text in the same copy box (a dev report, say), selected for Ctrl+C.
function AltArmy.ProfitExportDialog.ShowText(titleText, introText, text)
    title:SetText(titleText or "Export")
    intro:SetText(introText or "")
    box.export = text
    box:SetText(text or "")
    status:SetText("")
    missing:SetText("")
    missing:Hide()
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -UI.GAP)
    box:SetPoint("RIGHT", inner, "RIGHT", -6, 0)
    dialog:SetHeight(UI.HEIGHT)
    dialog:Show()
    box:SetFocus()
    box:HighlightText()
end

function AltArmy.ProfitExportDialog.Hide()
    dialog:Hide()
end
