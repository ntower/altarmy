-- AltArmy TBC — "Link with your other account?": shown when another of your WoW accounts (the same
-- Battle.net login) asks to link (LinkSession's LREQ). Both clients show the same 4-digit code. Accept keeps
-- the link and starts the sync; Not now (or closing) turns it down. Waits for the end of combat to open.

if not AltArmy then return end

local Theme = AltArmy.Theme

local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_LinkAccountDialog")
dialog:SetSize(420, 250)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

if UISpecialFrames then
    tinsert(UISpecialFrames, "AltArmyTBC_LinkAccountDialog") -- never assign the global: that taints it
end

local headerPanel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
headerPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetHeight(HEADER_PANEL_HEIGHT)
headerPanel:EnableMouse(true)
headerPanel:RegisterForDrag("LeftButton")
headerPanel:SetScript("OnDragStart", function() dialog:StartMoving() end)
headerPanel:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
Theme.ApplyBackdrop(headerPanel, "section")

local headerTitle = headerPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
headerTitle:SetPoint("LEFT", headerPanel, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
headerTitle:SetText("Alt Army")
Theme.SetTitleColor(headerTitle)

local closeBtn = CreateFrame("Button", nil, headerPanel, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", headerPanel, "RIGHT", 2, 0)

local bodyPanel = Theme.CreateTabContentPanel(dialog)
bodyPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET,
    -(CONTENT_INSET + HEADER_PANEL_HEIGHT + HEADER_SECTION_GAP))
bodyPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
local bodyInner = Theme.CreatePanelInnerContent(bodyPanel)

local headline = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.headline)
headline:SetPoint("TOPLEFT", bodyInner, "TOPLEFT", 0, 0)
headline:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
headline:SetJustifyH("LEFT")
headline:SetWordWrap(true)
headline:SetTextColor(1, 1, 1, 1)

local bodyText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
bodyText:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -10)
bodyText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(true)
bodyText:SetTextColor(0.75, 0.75, 0.75, 1)
bodyText:SetText("Each account will send full data about its characters to the other. You will be able to view "
    .. "the full list of characters from either account. You can unlink later in Options > Sharing")

local codeText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.headline)
codeText:SetPoint("TOP", bodyText, "BOTTOM", 0, -12)
codeText:SetTextColor(1, 0.82, 0, 1)

local btnYes = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
btnYes:SetSize(120, 24)
btnYes:SetPoint("BOTTOMRIGHT", bodyInner, "BOTTOM", -6, 4)
btnYes:SetText("Link")
Theme.SkinButton(btnYes)

local btnNo = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
btnNo:SetSize(120, 24)
btnNo:SetPoint("BOTTOMLEFT", bodyInner, "BOTTOM", 6, 4)
btnNo:SetText("Not now")
Theme.SkinButton(btnNo)

local current -- the peer asking
local waitFrame = CreateFrame("Frame")

local function answer(accept)
    local peer = current
    current = nil
    dialog:Hide()
    local T = AltArmy.LinkTransport
    if peer and T then
        if accept then
            T.AcceptLink(peer.g)
        else
            T.DeclineLink(peer.g)
        end
    end
end

btnYes:SetScript("OnClick", function() answer(true) end)
btnNo:SetScript("OnClick", function() answer(false) end)
closeBtn:SetScript("OnClick", function() answer(false) end)

local function present()
    if not current then return end
    local where = current.realm and (" (" .. current.realm .. ")") or ""
    headline:SetText("Link with your other account, " .. (current.name or "?") .. where .. "?")
    codeText:SetText("Code: " .. (current.code or "") .. "  (the other window shows the same)")
    dialog:Show()
end

AltArmy.LinkAccountDialog = AltArmy.LinkAccountDialog or {}

--- Ask whether to link with `peer` (LinkSession's peer: g, name, realm), showing `code`.
function AltArmy.LinkAccountDialog.Show(peer, code)
    if not peer then return end
    current = { g = peer.g, name = peer.name, realm = peer.realm, code = code }
    if InCombatLockdown and InCombatLockdown() then
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            present()
        end)
        return
    end
    present()
end
