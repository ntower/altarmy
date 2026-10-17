-- AltArmy TBC — Options > Sharing > Linked accounts: your other WoW accounts (the same Battle.net login).
-- Lists each link (online or not: its characters, when it last synced, Sync now and Unlink) and each other
-- account of yours online with Alt Army that isn't linked (Link). Shown while linked accounts are on
-- (Debug.IsLinkedAccountsEnabled: WoW: Forever only, for now). Rows come from LinkTransport.View (LinkSession.View).

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
    row.second = button(row, "Unlink", 80)
    row.first = button(row, "Sync now", 90)
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

-- The buttons shown sit at the row's right edge; the state text fills what is left (a hidden button keeps
-- no room).
local function layoutRow(row)
    row.second:ClearAllPoints()
    row.first:ClearAllPoints()
    row.state:ClearAllPoints()
    row.state:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    local right, rightPoint, gap = row, "RIGHT", 0
    if row.second:IsShown() then
        row.second:SetPoint("RIGHT", right, rightPoint, -gap, 0)
        right, rightPoint, gap = row.second, "LEFT", 6
    end
    if row.first:IsShown() then
        row.first:SetPoint("RIGHT", right, rightPoint, -gap, 0)
        right, rightPoint, gap = row.first, "LEFT", 6
    end
    row.state:SetPoint("RIGHT", right, rightPoint, -(gap > 0 and 8 or 0), 0)
end

local function fill(row, e)
    local T = AltArmy.LinkTransport
    row.name:SetText(e.linked and ("|cff7fd8c8" .. (e.label or "?") .. "|r")
        or ((e.label or "?") .. (e.realm and ("|cff808080 - " .. e.realm .. "|r") or "")))
    row.first:SetScript("OnClick", nil)
    row.second:SetScript("OnClick", nil)
    if e.linked then
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

local LO = {}
AltArmy.LinkedAccountsOptions = LO

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
        LO.Refresh()
    end)
end
