-- AltArmy TBC — Cooldown availability alerts (chat + sound).
-- Uses CooldownData.EvaluateAlerts. Chat lines are prefixed with gold "Alt Army".

if not AltArmy then return end

AltArmy.CooldownAlerts = AltArmy.CooldownAlerts or {}
local CA = AltArmy.CooldownAlerts

local alertState = {
    lastAvailAlertAt = {},
}

local TICK_INTERVAL = 30
local LOGIN_DELAY = 5
local elapsed = TICK_INTERVAL

local alertFrame = CreateFrame("Frame", "AltArmyTBC_CooldownAlertFrame", UIParent)

local ALTARMY_GOLD = "|cfffecc00"

local function categoryTitleFallback(key)
    local CD = AltArmy.CooldownData
    local c = CD and CD.CATEGORIES and CD.CATEGORIES[key]
    return (c and c.title) or key or "?"
end

local CC = AltArmy.ClassColor

local function classColorWrap(text, classFile)
    if CC and CC.wrapName then
        return CC.wrapName(text, classFile)
    end
    return text or "?"
end

--- Recipe / cooldown ready / name (and optional realm).
--- @param r table alert row from CooldownData.EvaluateAlerts
--- @param showAllRealms boolean append (realm) when true
local function formatAlertBody(r, showAllRealms)
    local recipe = r.categoryTitle
    if not recipe or recipe == "" then
        recipe = categoryTitleFallback(r.categoryKey)
    end
    local namePart = classColorWrap(r.name, r.classFile)
    local msg = string.format("%s cooldown ready — %s", recipe, namePart)
    if showAllRealms and r.realm and r.realm ~= "" then
        msg = msg .. " (" .. r.realm .. ")"
    end
    return msg
end

local function sendCooldownAlert(chatLine)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chatLine and chatLine ~= "" and chat and chat.AddMessage then
        chat:AddMessage(chatLine)
    end
end

local function announceBatch(alerts, showAllRealms)
    if not alerts or #alerts == 0 then return end
    for _, r in ipairs(alerts) do
        local body = formatAlertBody(r, showAllRealms == true)
        sendCooldownAlert(ALTARMY_GOLD .. "Alt Army|r " .. body)
    end
    pcall(function()
        if PlaySound then
            PlaySound("TellMessage", "Master")
        end
    end)
end

function CA.RunEvaluateOnce()
    local DS = AltArmy.DataStore
    local CD = AltArmy.CooldownData
    if not DS or not CD or not CD.EvaluateAlerts or not CD.EnsureCooldownOptions then return end
    CD.EnsureCooldownOptions()
    local opts = AltArmyTBC_Options and AltArmyTBC_Options.cooldowns
    if not opts then return end
    local now = time and time() or 0
    local alerts = CD.EvaluateAlerts(DS, opts, now, alertState)
    local GRF = AltArmy.GlobalRealmFilter
    local showAllRealms = GRF and GRF.Get and GRF.Get() == "all"
    if GRF and GRF.FilterList then
        alerts = GRF.FilterList(alerts)
    end
    announceBatch(alerts, showAllRealms)
end

function CA.ResetAnnouncementState()
    alertState.lastAvailAlertAt = {}
end

alertFrame:RegisterEvent("PLAYER_LOGIN")
alertFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CA.ResetAnnouncementState()
        elapsed = TICK_INTERVAL
        alertFrame.loginSweepPending = true
        alertFrame.loginElapsed = 0
    end
end)

alertFrame:SetScript("OnUpdate", function(f, dt)
    if f.loginSweepPending then
        f.loginElapsed = (f.loginElapsed or 0) + dt
        if f.loginElapsed >= LOGIN_DELAY then
            f.loginSweepPending = false
            CA.RunEvaluateOnce()
            elapsed = 0
        end
        return
    end
    elapsed = elapsed + dt
    if elapsed >= TICK_INTERVAL then
        elapsed = 0
        CA.RunEvaluateOnce()
    end
end)
