-- AltArmy TBC — Dialog resolving RestedXP vs Alt Army quest reward upgrade indicators.
-- luacheck: globals UISpecialFrames UIParent

if not AltArmy then return end

local Theme = AltArmy.Theme
local Text = AltArmy.Text
local RC = AltArmy.RestedXpQuestRewardConflict

local ADDON_NAME = "Alt Army"
local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28
local COLUMN_GAP = 16
local PREVIEW_PANEL_PADDING = 6
local PREVIEW_MAX_WIDTH = 208
local PREVIEW_MAX_HEIGHT = 86
local PREVIEW_SIDEGRADE_MAX_HEIGHT = 36
local PREVIEW_STACK_GAP = 6
local BUTTON_TOP_GAP = 10
local FOOTNOTE_TOP_GAP = 8
local COLUMN_TOP_INSET = 4
local BUTTON_HEIGHT = 24
local SIDEGRADE_LABEL_HEIGHT = 14
local BUTTON_WIDTH = 180
local FOOTNOTE_LINE_HEIGHT = 14
local HEADLINE_BODY_GAP = 10
local BODY_COLUMNS_GAP = 18
local HEADLINE_HEIGHT = 16
local BODY_TEXT_HEIGHT = 28
local TAB_PAD = Theme.TAB_CONTENT_PADDING
local DIALOG_WIDTH = 560
local TEXTURE_ROOT = "Interface\\AddOns\\AltArmy_TBC\\Textures\\"
local PREVIEW_ALT_ARMY_TEXTURE = TEXTURE_ROOT .. "QuestRewardPreview_AltArmy"
local PREVIEW_ALT_ARMY_SIDEGRADE_TEXTURE = TEXTURE_ROOT .. "QuestRewardPreview_AltArmySidegrade"
local PREVIEW_RESTED_XP_TEXTURE = TEXTURE_ROOT .. "QuestRewardPreview_RestedXP"

local function computeDialogHeight(columnsHeight, headlineHeight, bodyTextHeight, footnoteHeight)
    return CONTENT_INSET
        + HEADER_PANEL_HEIGHT
        + HEADER_SECTION_GAP
        + TAB_PAD
        + headlineHeight
        + HEADLINE_BODY_GAP
        + bodyTextHeight
        + BODY_COLUMNS_GAP
        + columnsHeight
        + FOOTNOTE_TOP_GAP
        + footnoteHeight
        + TAB_PAD
        + CONTENT_INSET
end

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_RestedXpQuestRewardConflictDialog")
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

if UISpecialFrames then
    tinsert(UISpecialFrames, "AltArmyTBC_RestedXpQuestRewardConflictDialog") -- never assign the global: that taints it
end

local headerPanel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
headerPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetHeight(HEADER_PANEL_HEIGHT)
headerPanel:EnableMouse(true)
headerPanel:RegisterForDrag("LeftButton")
headerPanel:SetScript("OnDragStart", function()
    dialog:StartMoving()
end)
headerPanel:SetScript("OnDragStop", function()
    dialog:StopMovingOrSizing()
end)
Theme.ApplyBackdrop(headerPanel, "section")

local headerTitle = headerPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
headerTitle:SetPoint("LEFT", headerPanel, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
headerTitle:SetText(ADDON_NAME)
Theme.SetTitleColor(headerTitle)

local closeBtn = CreateFrame("Button", nil, headerPanel, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", headerPanel, "RIGHT", 2, 0)

local bodyPanel = Theme.CreateTabContentPanel(dialog)
bodyPanel:SetPoint(
    "TOPLEFT",
    dialog,
    "TOPLEFT",
    CONTENT_INSET,
    -(CONTENT_INSET + HEADER_PANEL_HEIGHT + HEADER_SECTION_GAP))
bodyPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

local bodyInner = Theme.CreatePanelInnerContent(bodyPanel)

local headline = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.headline)
headline:SetPoint("TOPLEFT", bodyInner, "TOPLEFT", 0, 0)
headline:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
headline:SetJustifyH("LEFT")
headline:SetWordWrap(true)
headline:SetText("Conflicting Settings")
headline:SetTextColor(1, 1, 1, 1)

local bodyText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
bodyText:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -HEADLINE_BODY_GAP)
bodyText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(true)
bodyText:SetTextColor(0.75, 0.75, 0.75, 1)
bodyText:SetText(
    "Both Alt Army and RestedXP show upgrade markers on quest rewards. Which do you prefer?")

local columns = CreateFrame("Frame", nil, bodyInner)
columns:SetPoint("TOPLEFT", bodyText, "BOTTOMLEFT", 0, -BODY_COLUMNS_GAP)
columns:SetPoint("TOPRIGHT", bodyText, "BOTTOMRIGHT", 0, -BODY_COLUMNS_GAP)

local function fitPreviewSize(maxWidth, maxHeight, textureWidth, textureHeight)
    local aspect = textureWidth / textureHeight
    local width = maxHeight * aspect
    local height = maxHeight
    if width > maxWidth then
        width = maxWidth
        height = width / aspect
    end
    return width, height
end

local function previewPanelHeight(textureWidth, textureHeight, maxWidth, maxHeight)
    local _, texHeight = fitPreviewSize(maxWidth, maxHeight, textureWidth, textureHeight)
    return texHeight + PREVIEW_PANEL_PADDING * 2
end

local columnsHeight = COLUMN_TOP_INSET
    + previewPanelHeight(253, 105, PREVIEW_MAX_WIDTH, PREVIEW_MAX_HEIGHT)
    + PREVIEW_STACK_GAP + SIDEGRADE_LABEL_HEIGHT + PREVIEW_STACK_GAP
    + previewPanelHeight(255, 42, PREVIEW_MAX_WIDTH, PREVIEW_SIDEGRADE_MAX_HEIGHT)
    + BUTTON_TOP_GAP + BUTTON_HEIGHT
columns:SetHeight(columnsHeight)
dialog:SetSize(
    DIALOG_WIDTH,
    computeDialogHeight(columnsHeight, HEADLINE_HEIGHT, BODY_TEXT_HEIGHT, FOOTNOTE_LINE_HEIGHT))

local leftColumn = CreateFrame("Frame", nil, columns)
leftColumn:SetPoint("TOPLEFT", columns, "TOPLEFT", 0, 0)
leftColumn:SetPoint("BOTTOMLEFT", columns, "BOTTOMLEFT", 0, 0)
leftColumn:SetWidth((DIALOG_WIDTH - CONTENT_INSET * 2 - 32 - COLUMN_GAP) / 2)

local rightColumn = CreateFrame("Frame", nil, columns)
rightColumn:SetPoint("TOPRIGHT", columns, "TOPRIGHT", 0, 0)
rightColumn:SetPoint("BOTTOMRIGHT", columns, "BOTTOMRIGHT", 0, 0)
rightColumn:SetWidth(leftColumn:GetWidth())

local function createPreviewPanel(parent, texturePath, textureWidth, textureHeight, maxWidth, maxHeight)
    local texWidth, texHeight = fitPreviewSize(maxWidth, maxHeight, textureWidth, textureHeight)
    local panelWidth = texWidth + PREVIEW_PANEL_PADDING * 2
    local panelHeight = texHeight + PREVIEW_PANEL_PADDING * 2

    local previewPanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    previewPanel:SetSize(panelWidth, panelHeight)
    Theme.ApplyBackdrop(previewPanel, "section")

    local preview = previewPanel:CreateTexture(nil, "ARTWORK")
    preview:SetPoint("CENTER", previewPanel, "CENTER", 0, 0)
    preview:SetSize(texWidth, texHeight)
    preview:SetTexture(texturePath)

    return previewPanel
end

local mainAltArmyPanel = createPreviewPanel(
    leftColumn,
    PREVIEW_ALT_ARMY_TEXTURE,
    253,
    105,
    PREVIEW_MAX_WIDTH,
    PREVIEW_MAX_HEIGHT)
mainAltArmyPanel:SetPoint("TOP", leftColumn, "TOP", 0, -COLUMN_TOP_INSET)

local orLabel = leftColumn:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
orLabel:SetPoint("TOP", mainAltArmyPanel, "BOTTOM", 0, -PREVIEW_STACK_GAP)
orLabel:SetText("If the item is a sidegrade:")
orLabel:SetTextColor(0.75, 0.75, 0.75, 1)

local sidegradePanel = createPreviewPanel(
    leftColumn,
    PREVIEW_ALT_ARMY_SIDEGRADE_TEXTURE,
    255,
    42,
    PREVIEW_MAX_WIDTH,
    PREVIEW_SIDEGRADE_MAX_HEIGHT)
sidegradePanel:SetPoint("TOP", orLabel, "BOTTOM", 0, -PREVIEW_STACK_GAP)

local restedXpPanel = createPreviewPanel(
    rightColumn,
    PREVIEW_RESTED_XP_TEXTURE,
    257,
    106,
    PREVIEW_MAX_WIDTH,
    PREVIEW_MAX_HEIGHT)
restedXpPanel:SetPoint("TOP", rightColumn, "TOP", 0, -COLUMN_TOP_INSET)

local function anchorColumnButton(btn, column, yRef)
    btn:SetPoint("TOP", yRef, "BOTTOM", 0, -BUTTON_TOP_GAP)
    btn:SetPoint("LEFT", column, "LEFT", (column:GetWidth() - BUTTON_WIDTH) / 2, 0)
end

local footnote = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
footnote:SetJustifyH("CENTER")
footnote:SetWordWrap(true)
footnote:SetTextColor(0.55, 0.55, 0.55, 1)
footnote:SetText(Text.ONBOARDING_DISMISS_FOOTNOTE)

local btnAltArmy = CreateFrame("Button", nil, leftColumn, "UIPanelButtonTemplate")
btnAltArmy:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
anchorColumnButton(btnAltArmy, leftColumn, sidegradePanel)
btnAltArmy:SetText("Use Alt Army")
Theme.SkinButton(btnAltArmy)

local btnRestedXp = CreateFrame("Button", nil, rightColumn, "UIPanelButtonTemplate")
btnRestedXp:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
anchorColumnButton(btnRestedXp, rightColumn, sidegradePanel)
btnRestedXp:SetText("Use RestedXP")
Theme.SkinButton(btnRestedXp)

footnote:SetPoint("TOP", btnAltArmy, "BOTTOM", 0, -FOOTNOTE_TOP_GAP)
footnote:SetPoint("LEFT", bodyInner, "LEFT", 0, 0)
footnote:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)

local function syncDialogHeight()
    dialog:SetHeight(computeDialogHeight(
        columnsHeight,
        headline:GetStringHeight() or HEADLINE_HEIGHT,
        bodyText:GetStringHeight() or BODY_TEXT_HEIGHT,
        footnote:GetStringHeight() or FOOTNOTE_LINE_HEIGHT))
end

local onDismissCallback

local function hideDialog()
    dialog:Hide()
    local callback = onDismissCallback
    onDismissCallback = nil
    if callback then
        callback()
    end
end

local function onChooseAltArmy()
    if RC and RC.ChooseAltArmy then
        RC.ChooseAltArmy()
    end
    hideDialog()
end

local function onChooseRestedXp()
    if RC and RC.ChooseRestedXp then
        RC.ChooseRestedXp()
    end
    hideDialog()
end

local function onClose()
    if RC and RC.DismissWithoutChoice then
        RC.DismissWithoutChoice()
    end
    hideDialog()
end

btnAltArmy:SetScript("OnClick", onChooseAltArmy)
btnRestedXp:SetScript("OnClick", onChooseRestedXp)
closeBtn:SetScript("OnClick", onClose)

AltArmy.RestedXpQuestRewardConflictDialog = AltArmy.RestedXpQuestRewardConflictDialog or {}

function AltArmy.RestedXpQuestRewardConflictDialog.Show(onDismiss)
    onDismissCallback = onDismiss
    dialog:Show()
    syncDialogHeight()
end

function AltArmy.RestedXpQuestRewardConflictDialog.ShowDebug()
    AltArmy.RestedXpQuestRewardConflictDialog.Show()
    return true
end

function AltArmy.RestedXpQuestRewardConflictDialog.Hide()
    hideDialog()
end

if RC and RC.RegisterOnboardingProviders then
    RC.RegisterOnboardingProviders()
end
