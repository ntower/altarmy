-- AltArmy TBC — "Link your accounts": the onboarding dialog shown once (ever, per WoW account) when another
-- of this player's WoW accounts on the same Battle.net login is found online running Alt Army and isn't
-- linked. Queued with the other onboarding dialogs (one a session). Link Accounts sends the link request
-- (LinkSession's LREQ: the other account then asks its player, LinkAccountDialog) and opens Options' Sharing
-- page, where the code both windows show is; Do Not Link (or closing) only closes it.

if not AltArmy then return end

AltArmy.LinkAccountsOnboarding = AltArmy.LinkAccountsOnboarding or {}
local LAO = AltArmy.LinkAccountsOnboarding

LAO.HEADLINE = "Link your accounts"
LAO.BODY = "We notice you have another account that's part of your Battle.net account. Would you like to"
    .. " share data between them?\n\n"
    .. "Both accounts will be able to see full data about the other. This includes all characters, their"
    .. " gold, play time, professions, items, cooldowns, etc. You can use filters to hide or show linked"
    .. " characters.\n\n"
    .. "If you choose to link, the other account must click a button to accept"
LAO.LINK_BUTTON = "Link Accounts"
LAO.SKIP_BUTTON = "Do Not Link"

local function options()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    return _G.AltArmyTBC_Options
end

function LAO.IsDismissed()
    return options().linkAccountsOnboardingShown == true
end

function LAO.Dismiss()
    options().linkAccountsOnboardingShown = true
end

--- The first account in `view` (LinkTransport.View()) to offer linking with: online, answering as Alt Army,
--- not linked, and with no link request either way under way or turned down this session.
function LAO.Candidate(view)
    for _, e in ipairs(view or {}) do
        if not e.linked and e.online and e.g and not e.incoming and not e.waitingCode and not e.declined then
            return e
        end
    end
    return nil
end

local function transport()
    local T = AltArmy.LinkTransport
    if T and T.IsEnabled and T.IsEnabled() then
        return T
    end
    return nil
end

function LAO.ShouldPrompt()
    if LAO.IsDismissed() then
        return false
    end
    local T = transport()
    return T ~= nil and LAO.Candidate(T.View()) ~= nil
end

--- Discovery changed who is online (LinkTransport): ask the queue to show this dialog if it now should.
function LAO.Check()
    local ODQ = AltArmy.OnboardingDialogQueue
    if ODQ and ODQ.RequestProcess and LAO.ShouldPrompt() then
        ODQ.RequestProcess()
    end
end

--- Link Accounts: ask `acct` to link, unless that account asked us meanwhile (its dialog is up then).
function LAO.RequestLink(acct)
    local T = transport()
    if not T then
        return false
    end
    for _, e in ipairs(T.View()) do
        if e.acct == acct then
            if e.linked or e.incoming or e.waitingCode or not e.g then
                return false
            end
            return T.RequestLink(e.g)
        end
    end
    return false
end

-- *** Dialog ***

local Theme = AltArmy.Theme
if not (Theme and CreateFrame and UIParent) then return end

local ADDON_NAME = "Alt Army"
local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28

local dialog
local footnote
local currentAcct
local onDoneCallback

local function finish()
    dialog:Hide()
    currentAcct = nil
    local cb = onDoneCallback
    onDoneCallback = nil
    if cb then cb() end
end

local function buildDialog()
    if dialog then return end

    dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_LinkAccountsOnboarding")
    dialog:SetSize(460, 240)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    dialog:Hide()
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    if UISpecialFrames then
        tinsert(UISpecialFrames, "AltArmyTBC_LinkAccountsOnboarding") -- never assign the global: that taints it
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
    headerTitle:SetText(ADDON_NAME)
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
    headline:SetText(LAO.HEADLINE)
    headline:SetTextColor(1, 1, 1, 1)

    local bodyText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    bodyText:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -12)
    bodyText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)
    bodyText:SetTextColor(0.75, 0.75, 0.75, 1)
    bodyText:SetText(LAO.BODY)

    local btnLink = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
    btnLink:SetSize(168, 24)
    btnLink:SetPoint("TOP", bodyText, "BOTTOM", 0, -14)
    btnLink:SetPoint("RIGHT", bodyInner, "CENTER", -6, 0)
    btnLink:SetText(LAO.LINK_BUTTON)
    Theme.SkinButton(btnLink)

    local btnSkip = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
    btnSkip:SetSize(168, 24)
    btnSkip:SetPoint("TOP", bodyText, "BOTTOM", 0, -14)
    btnSkip:SetPoint("LEFT", bodyInner, "CENTER", 6, 0)
    btnSkip:SetText(LAO.SKIP_BUTTON)
    Theme.SkinButton(btnSkip)

    footnote = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    footnote:SetPoint("TOP", btnLink, "BOTTOM", 0, -10)
    footnote:SetPoint("LEFT", bodyInner, "LEFT", 0, 0)
    footnote:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    footnote:SetJustifyH("CENTER")
    footnote:SetWordWrap(true)
    footnote:SetTextColor(0.55, 0.55, 0.55, 1)
    footnote:SetText(AltArmy.Text and AltArmy.Text.ONBOARDING_DISMISS_FOOTNOTE
        or "This message will only show once but you can make changes later in Options")

    btnLink:SetScript("OnClick", function()
        local acct = currentAcct
        finish()
        if acct then
            LAO.RequestLink(acct)
        end
        -- the code to compare with the other window's is on the Sharing page's Linked accounts section
        if AltArmy.OpenInterfaceOptions and not (InCombatLockdown and InCombatLockdown()) then
            AltArmy.OpenInterfaceOptions("sharing")
        end
    end)
    btnSkip:SetScript("OnClick", finish)
    closeBtn:SetScript("OnClick", finish)
end

--- Grow/shrink the dialog so the footnote (last element) sits inside the body panel.
local function fitDialogHeight()
    if not (dialog and footnote) then return end
    local top, bottom = dialog:GetTop(), footnote:GetBottom()
    if not (top and bottom) then return end
    local needed = (top - bottom) + Theme.TAB_CONTENT_PADDING + CONTENT_INSET
    dialog:SetHeight(math.ceil(needed))
end

local waitFrame = CreateFrame("Frame")

local function present()
    dialog:Show()
    fitDialogHeight()
    -- Wrapped text heights can settle a frame after Show.
    if C_Timer and C_Timer.After then C_Timer.After(0, fitDialogHeight) end
end

--- Show the dialog for `entry` (a LinkTransport.View() entry); `done` when it closes. Waits out combat.
local function show(entry, done)
    buildDialog()
    currentAcct = entry and entry.acct
    onDoneCallback = done
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

--- Debug: show the dialog whether or not it was shown before or an account is online.
--- @return boolean
function LAO.ShowDebug()
    local T = transport()
    show(T and LAO.Candidate(T.View()) or nil)
    return true
end

if AltArmy.OnboardingDialogQueue and AltArmy.OnboardingDialogQueue.Register then
    AltArmy.OnboardingDialogQueue.Register({
        id = "linkAccountsOnboarding",
        priority = 20,
        shouldPrompt = LAO.ShouldPrompt,
        show = function(done)
            local T = transport()
            local entry = T and LAO.Candidate(T.View())
            if not entry then
                done()
                return
            end
            LAO.Dismiss() -- shown once, however it is closed (or the game is)
            show(entry, done)
        end,
    })
end
