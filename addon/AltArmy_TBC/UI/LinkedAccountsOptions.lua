-- AltArmy TBC — Options > Sharing > Linked accounts: your other WoW accounts (the same Battle.net login).
-- Lists each link (online or not: its characters, when it last synced, Rename, Sync now and Unlink; the client
-- doesn't tell an addon a game account's name, so a link is named after its character until renamed) and each other
-- account of yours online with Alt Army that isn't linked (Link). Shown while linked accounts are on
-- (Debug.IsLinkedAccountsEnabled). Rows come from LinkTransport.View (LinkSession.View).

if not AltArmy then return end

local Theme = AltArmy.Theme
local panel = AltArmy.OptionsPanel
local section = panel and panel.linkedSection
if not section then return end

local MAX_ROWS = 8
local ROW_HEIGHT = 24
local INTRO_HEIGHT = 44
local UNLINK_CONFIRM_SECONDS = 5

local content = section.content

local intro = content:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
intro:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
intro:SetPoint("RIGHT", content, "RIGHT", 0, 0)
intro:SetJustifyH("LEFT")
intro:SetWordWrap(true)
intro:SetTextColor(0.75, 0.75, 0.75, 1)
intro:SetText("If you have multiple accounts on the same battle.net login, you can link them together. "
    .. "Log in with your other account and alt army running and it will appear below.")

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    if Theme.SkinButton then Theme.SkinButton(b) end
    return b
end

local rows = {}
for i = 1, MAX_ROWS do
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(INTRO_HEIGHT + (i - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.state = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    row.state:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.state:SetJustifyH("LEFT")
    row.state:SetTextColor(0.75, 0.75, 0.75, 1)
    row.state:SetWordWrap(false)
    row.edit = CreateFrame("EditBox", nil, row)
    row.edit:SetSize(160, 20)
    row.edit:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.edit:SetFontObject(Theme.FONTS.body)
    row.edit:SetAutoFocus(false)
    row.edit:SetTextInsets(6, 6, 0, 0)
    row.edit:SetMaxLetters(AltArmy.LinkStore and AltArmy.LinkStore.NAME_MAX or 32)
    if Theme.ApplyInputTextures then Theme.ApplyInputTextures(row.edit) end
    row.edit:Hide()
    row.second = button(row, "Unlink", 80)
    row.first = button(row, "Sync now", 90)
    row.rename = button(row, "Rename", 80)
    row:Hide()
    rows[i] = row
end

local empty = content:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -INTRO_HEIGHT)
empty:SetTextColor(0.55, 0.55, 0.55, 1)
empty:SetText("None of your other accounts is online with Alt Army right now.")

local function ago(t)
    local SD = AltArmy.SummaryData
    if not t then return "never" end
    return SD and SD.FormatLastOnline and SD.FormatLastOnline(t, false) or tostring(t)
end

local unlinkArmedAt = {}
local renaming -- the account whose name is being edited, if any

-- The buttons shown sit at the row's right edge; the state text fills what is left (a hidden button keeps
-- no room).
local function layoutRow(row)
    row.state:ClearAllPoints()
    row.state:SetPoint("LEFT", row.edit:IsShown() and row.edit or row.name, "RIGHT", 8, 0)
    local right, rightPoint, gap = row, "RIGHT", 0
    for _, b in ipairs({ row.second, row.first, row.rename }) do
        b:ClearAllPoints()
        if b:IsShown() then
            b:SetPoint("RIGHT", right, rightPoint, -gap, 0)
            right, rightPoint, gap = b, "LEFT", 6
        end
    end
    row.state:SetPoint("RIGHT", right, rightPoint, -(gap > 0 and 8 or 0), 0)
end

local LO = {}
AltArmy.LinkedAccountsOptions = LO

local function stopRenaming(save, row)
    local acct = renaming
    renaming = nil
    if save and acct and AltArmy.LinkStore then
        AltArmy.LinkStore.SetName(acct, row.edit:GetText())
    end
    row.edit:ClearFocus()
    LO.Refresh()
end

local function fill(row, e)
    local T = AltArmy.LinkTransport
    row.name:SetText(e.linked and ("|cff7fd8c8" .. (e.label or "?") .. "|r")
        or ((e.label or "?") .. (e.realm and ("|cff808080 - " .. e.realm .. "|r") or "")))
    row.first:SetScript("OnClick", nil)
    row.second:SetScript("OnClick", nil)
    row.rename:SetScript("OnClick", nil)
    local editing = e.linked and renaming == e.acct
    if editing and not row.edit:IsShown() then
        row.edit:SetText(e.label or "")
        row.edit:Show()
        row.edit:SetFocus()
        row.edit:HighlightText()
    elseif not editing then
        row.edit:Hide()
    end
    row.name:SetShown(not editing)
    row.edit:SetScript("OnEnterPressed", function() stopRenaming(true, row) end)
    row.edit:SetScript("OnEscapePressed", function() stopRenaming(false, row) end)
    row.rename:SetShown(e.linked)
    if e.linked then
        row.rename:SetText(editing and "Save" or "Rename")
        row.rename:SetScript("OnClick", function()
            if editing then
                stopRenaming(true, row)
            else
                renaming = e.acct
                LO.Refresh()
            end
        end)
        local state
        if e.suspended then
            state = "Paused: " .. tostring(e.suspended)
        elseif e.syncing then
            state = "Syncing..."
        elseif e.online then
            state = "Online"
        else
            state = "Offline"
        end
        state = state .. " - " .. e.characters .. " character" .. (e.characters == 1 and "" or "s")
            .. ", synced " .. ago(e.lastSyncAt)
        if e.refused then
            state = state .. " |cffff8080(" .. e.refused .. ")|r"
        end
        row.state:SetText(state)
        row.first:SetText("Sync now")
        row.first:SetShown(e.online and not e.suspended)
        row.first:SetScript("OnClick", function() T.SyncNow(e.acct) end)
        local armed = unlinkArmedAt[e.acct] and (time() - unlinkArmedAt[e.acct] < UNLINK_CONFIRM_SECONDS)
        row.second:SetText(armed and "Sure?" or "Unlink")
        row.second:Show()
        row.second:SetScript("OnClick", function()
            local at = unlinkArmedAt[e.acct]
            if at and time() - at < UNLINK_CONFIRM_SECONDS then
                unlinkArmedAt[e.acct] = nil
                T.Unlink(e.acct)
            else
                unlinkArmedAt[e.acct] = time()
                row.second:SetText("Sure?")
            end
        end)
    else
        local state
        if e.waitingCode then
            state = "Accept on that account (code " .. e.waitingCode .. ")"
        elseif e.incoming then
            state = "Asks to link"
        elseif e.declined then
            state = "Not linked: declined there"
        else
            state = "Online, not linked"
        end
        row.state:SetText(state)
        row.first:SetText("Link")
        row.first:SetShown(not e.waitingCode)
        row.first:SetScript("OnClick", function() T.RequestLink(e.g) end)
        row.second:Hide()
    end
end

function LO.Refresh()
    local T = AltArmy.LinkTransport
    local on = T and T.IsEnabled() or false
    if section.IsShown() ~= on then
        section.SetShown(on)
    end
    local entries = on and T.View() or {}
    local shown = math.min(#entries, MAX_ROWS)
    for i = 1, MAX_ROWS do
        if i <= shown then
            fill(rows[i], entries[i])
            layoutRow(rows[i])
            rows[i]:Show()
        else
            rows[i]:Hide()
        end
    end
    empty:SetShown(shown == 0)
    section.SetContentHeight(INTRO_HEIGHT + math.max(1, shown) * ROW_HEIGHT)
    if panel.LayoutSectionPages then
        panel.LayoutSectionPages()
    end
end

if panel.pageSharing then
    panel.pageSharing:HookScript("OnShow", function()
        local T = AltArmy.LinkTransport
        if T and T.IsEnabled() then
            T.Discover()
        end
        renaming = nil
        LO.Refresh()
    end)
end
