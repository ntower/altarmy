-- AltArmy TBC — Standalone dialog suggesting the current character may be a bank alt.

if not AltArmy then return end

local Theme = AltArmy.Theme
local BD = AltArmy.BankAltDetect
local BA = AltArmy.BankAlt

local ADDON_NAME = "Alt Army"
local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28

local function refreshBankAltDependents()
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    local gearFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Gear
    if gearFrame and gearFrame.RefreshGrid then
        gearFrame:RefreshGrid()
    end
    local repFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Reputation
    if repFrame and repFrame.RefreshGrid then
        repFrame:RefreshGrid()
    end
end

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_BankAltSuggestDialog")
dialog:SetSize(460, 300)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

if UISpecialFrames then
    tinsert(UISpecialFrames, "AltArmyTBC_BankAltSuggestDialog") -- never assign the global: that taints it
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
headline:SetText("It looks like this character may be a bank alt")
headline:SetTextColor(1, 1, 1, 1)

local bodyText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
bodyText:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -14)
bodyText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(true)
bodyText:SetTextColor(0.75, 0.75, 0.75, 1)
bodyText:SetText(
    "You can mark it as a bank alt, which will:\n\n"
        .. "• Hide it from Gear and Reputation tabs\n\n"
        .. "• Skip it when deciding if an item is an upgrade\n\n"
        .. "Your bank alt will still appear in other parts of the addon, "
        .. "such as Summary, Graphs, and Search")

local footnote = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
footnote:SetPoint("BOTTOMLEFT", bodyInner, "BOTTOMLEFT", 0, 0)
footnote:SetPoint("BOTTOMRIGHT", bodyInner, "BOTTOMRIGHT", 0, 0)
footnote:SetJustifyH("CENTER")
footnote:SetWordWrap(true)
footnote:SetTextColor(0.55, 0.55, 0.55, 1)
footnote:SetText(AltArmy.Text and AltArmy.Text.ONBOARDING_DISMISS_FOOTNOTE
    or "This message will only show once but you can make changes later in Options")

local btnYes = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
btnYes:SetSize(168, 24)
btnYes:SetPoint("BOTTOMRIGHT", bodyInner, "BOTTOM", -6, 28)
btnYes:SetText("Yes, this is a bank alt")
Theme.SkinButton(btnYes)

local btnNo = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
btnNo:SetSize(176, 24)
btnNo:SetPoint("BOTTOMLEFT", bodyInner, "BOTTOM", 6, 28)
btnNo:SetText("No, this is not a bank alt")
Theme.SkinButton(btnNo)

local currentResult
local onDismissCallback

local function dismissWithoutMarking()
    if currentResult and BD and BD.Dismiss then
        BD.Dismiss(currentResult.name, currentResult.realm, "declined")
    end
end

local function hideDialog()
    dialog:Hide()
    currentResult = nil
    local callback = onDismissCallback
    onDismissCallback = nil
    if callback then
        callback()
    end
end

local function onYes()
    if currentResult and BA and BA.Set then
        BA.Set(currentResult.name, currentResult.realm, true)
        if BD and BD.Dismiss then
            BD.Dismiss(currentResult.name, currentResult.realm, "accepted")
        end
        refreshBankAltDependents()
    end
    hideDialog()
end

local function onNo()
    dismissWithoutMarking()
    hideDialog()
end

btnYes:SetScript("OnClick", onYes)
btnNo:SetScript("OnClick", onNo)
closeBtn:SetScript("OnClick", onNo)

AltArmy.BankAltSuggestDialog = AltArmy.BankAltSuggestDialog or {}

function AltArmy.BankAltSuggestDialog.Show(result, onDismiss)
    if not result then return end
    currentResult = result
    onDismissCallback = onDismiss
    dialog:Show()
end

function AltArmy.BankAltSuggestDialog.ShowDebug()
    if not BD or not BD.EvaluateCurrentCharacter then return false end
    local result = BD.EvaluateCurrentCharacter()
    if not result then return false end
    AltArmy.BankAltSuggestDialog.Show(result)
    return true
end

function AltArmy.BankAltSuggestDialog.Hide()
    hideDialog()
end
