-- AltArmy TBC — Linked accounts in the running client: Battle.net game data in and out (linked accounts).
-- The glue LinkSession and LinkSync run on (their `env`): messages go out as LinkCodec chunks through
-- ChatThrottleLib's Battle.net game data (prefix PREFIX, its own queue so it never holds up guild sharing),
-- and come in on BN_CHAT_MSG_ADDON. A chunk is dropped before anything is kept unless its sender is one of
-- this Battle.net account's game accounts (LinkDiscovery, asked of the client, cached CACHE_MINE seconds),
-- or if any of its arguments is a secret value. Nothing is sent during combat or chat lockdown (it waits,
-- in order), and a whole message that arrives in combat is read once combat ends. Off unless
-- Debug.IsLinkedAccountsEnabled() (WoW: Forever only, for now).
-- luacheck: read globals C_ChatInfo ChatThrottleLib C_BattleNet WOW_PROJECT_ID C_EventUtils

if not AltArmy then return end

AltArmy.LinkTransport = AltArmy.LinkTransport or {}
local T = AltArmy.LinkTransport

T.PREFIX = "AltArmyLink"
T.TICK = 5
T.CACHE_MINE = 30
T.DISCOVER_EVERY = 60
T.MAX_WAITING = 200 -- messages held while sending is paused
T.MAX_INBOX = 20 -- whole messages held until combat ends

local C, LD, Session, Sync = AltArmy.LinkCodec, AltArmy.LinkDiscovery, AltArmy.LinkSession, AltArmy.LinkSync

local libs
local reassembler = C.NewReassembler()
local outbox, inbox = {}, {}
local mineCache = {}
local me -- LinkDiscovery.Me, refreshed at each discovery
local msgCounter = 0
local lastDiscover = 0
local changedPending = false

local function now()
    return time and time() or 0
end

function T.IsEnabled()
    local D = AltArmy.Debug
    return D and D.IsLinkedAccountsEnabled and D.IsLinkedAccountsEnabled() or false
end

local function getLibs()
    libs = libs or C.LiveLibs()
    return libs
end

local function paused()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    local chat = C_ChatInfo
    return chat and chat.InChatMessagingLockdown and chat.InChatMessagingLockdown() or false
end

local function nextMsgId()
    msgCounter = msgCounter + 1
    return string.format("%x%x", now() % 4096, msgCounter % 65536)
end

local function sendChunks(item)
    local CTL = ChatThrottleLib
    for _, chunk in ipairs(item.chunks) do
        if CTL and CTL.BNSendGameData then
            CTL:BNSendGameData(item.prio, T.PREFIX, chunk, "WHISPER", item.g, T.PREFIX .. item.g)
        elseif C_BattleNet and C_BattleNet.SendGameData then
            C_BattleNet.SendGameData(item.g, T.PREFIX, chunk)
        end
    end
end

local function flushOutbox()
    while #outbox > 0 and not paused() do
        sendChunks(table.remove(outbox, 1))
    end
end

local function isMine(g)
    if type(g) ~= "number" then
        return false
    end
    local cached = mineCache[g]
    local t = now()
    if cached and t - cached.at < T.CACHE_MINE then
        return cached.ok
    end
    local api = LD.LiveApi()
    me = me or LD.Me(api)
    local ok = LD.IsCandidate(LD.Info(api, g), me) and true or false
    mineCache[g] = { ok = ok, at = t }
    return ok
end

local function refreshUi()
    -- the character list caches who is online on a linked account: drop it whether or not a tab is open
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if changedPending then
        return
    end
    changedPending = true
    local function run()
        changedPending = false
        if AltArmy.LinkedAccountsOptions and AltArmy.LinkedAccountsOptions.Refresh then
            AltArmy.LinkedAccountsOptions.Refresh()
        end
        if AltArmy.RefreshSummary then
            AltArmy.RefreshSummary() -- who is online on a linked account
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, run)
    else
        run()
    end
end

local env = {}
T.env = env

function env.send(g, msg, prio)
    local l = getLibs()
    if not l then
        return
    end
    local item = { g = g, prio = prio or "NORMAL", chunks = C.Split(C.Encode(msg, l), nextMsgId()) }
    if paused() or #outbox > 0 then
        if #outbox < T.MAX_WAITING then
            outbox[#outbox + 1] = item
        end
        return
    end
    sendChunks(item)
end

--- Send at once, past ChatThrottleLib's queue (which no longer drains once the client is closing): for a
--- short message (BYE) at logout.
function env.sendNow(g, msg)
    local l = getLibs()
    local bn = C_BattleNet
    if not l or not (bn and bn.SendGameData) then
        return
    end
    for _, chunk in ipairs(C.Split(C.Encode(msg, l), nextMsgId())) do
        pcall(bn.SendGameData, g, T.PREFIX, chunk)
    end
end

env.now = now
env.random = math.random
env.isMine = isMine

function env.myAccountId()
    return AltArmy.DataStore.EnsureAccountId()
end

function env.regenerateAccountId()
    AltArmy.DataStore.EnsureAccountId(nil, nil, true)
end

function env.self()
    local DS = AltArmy.DataStore
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return {
        name = DS.GetCurrentPlayerName and DS:GetCurrentPlayerName() or (UnitName and UnitName("player")),
        realm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or (GetRealmName and GetRealmName()),
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
        addon = getMeta and getMeta("AltArmy_TBC", "Version") or nil,
        interface = GetBuildInfo and select(4, GetBuildInfo()) or nil,
        project = WOW_PROJECT_ID,
    }
end

function env.ownRoot()
    return AltArmyTBC_Data
end

function env.currentGuid()
    return UnitGUID and UnitGUID("player") or nil
end

function env.prompt(peer, code)
    local dialog = AltArmy.LinkAccountDialog
    if dialog and dialog.Show then
        dialog.Show(peer, code)
    end
end

env.changed = refreshUi

local function handlePayload(g, payload)
    local l = getLibs()
    if not l then
        return
    end
    local msg = C.Decode(payload, l)
    if msg then
        Session.OnMessage(env, g, msg)
    end
end

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function onAddonMessage(prefix, text, _, sender)
    if isSecret(prefix) or prefix ~= T.PREFIX or not T.IsEnabled() then
        return
    end
    if isSecret(text) or isSecret(sender) or type(text) ~= "string" or not isMine(sender) then
        return
    end
    local payload = reassembler:Add(sender, text, now())
    if not payload then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if #inbox < T.MAX_INBOX then
            inbox[#inbox + 1] = { g = sender, payload = payload }
        end
        return
    end
    handlePayload(sender, payload)
end

--- Look for our other accounts online now and say HELLO.
function T.Discover()
    if not T.IsEnabled() then
        return
    end
    lastDiscover = now()
    local api = LD.LiveApi()
    me = LD.Me(api)
    mineCache = {}
    local scan = LD.Scan(api, me)
    Session.Discover(env, LD.Candidates(scan))
end

local function tick()
    if not T.IsEnabled() then
        return
    end
    flushOutbox()
    if not (InCombatLockdown and InCombatLockdown()) then
        while #inbox > 0 do
            local item = table.remove(inbox, 1)
            handlePayload(item.g, item.payload)
        end
    end
    if now() - lastDiscover >= T.DISCOVER_EVERY then
        T.Discover()
    end
    Session.Tick(env)
end

-- What the Sharing page and the dialog call.
function T.RequestLink(g) return Session.RequestLink(env, g) end
function T.AcceptLink(g) return Session.AcceptLink(env, g) end
function T.DeclineLink(g) return Session.DeclineLink(env, g) end
function T.Unlink(acct) Session.Unlink(env, acct) end
function T.SyncNow(acct) return Session.SyncNow(env, acct) end
function T.View() return Session.View() end

--- This character changed in a way no event below tells (its recipes were read or learned: the DataStore's
--- profession scans call this): its partial manifest follows, as for a bag or money change.
function T.NoteLocalChange()
    if T.IsEnabled() then
        Sync.NoteLocalChange(env)
    end
end

--- A character was deleted here (DataStore:DeleteCharacter): linked accounts hear of it 20 s after the last.
function T.NoteDeletion()
    if T.IsEnabled() then
        Sync.NoteDeletion(env)
    end
end

local CHANGE_EVENTS = {
    "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "MAIL_INBOX_UPDATE",
    "SKILL_LINES_CHANGED", "UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE",
}
local BNET_EVENTS = { "BN_INFO_CHANGED", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED" }

local frame = CreateFrame("Frame")
local function register(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return
    end
    pcall(frame.RegisterEvent, frame, event)
end
register("PLAYER_LOGIN")
register("BN_CHAT_MSG_ADDON")
register("PLAYER_REGEN_ENABLED")
register("PLAYER_LOGOUT")
for _, e in ipairs(BNET_EVENTS) do register(e) end
for _, e in ipairs(CHANGE_EVENTS) do register(e) end
local isBnetEvent, isChangeEvent = {}, {}
for _, e in ipairs(BNET_EVENTS) do isBnetEvent[e] = true end
for _, e in ipairs(CHANGE_EVENTS) do isChangeEvent[e] = true end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "BN_CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, T.PREFIX)
        end
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(T.TICK, tick)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(5, T.Discover)
        end
    elseif event == "PLAYER_LOGOUT" then
        if T.IsEnabled() then
            Session.Goodbye(env)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if T.IsEnabled() then tick() end
    elseif isBnetEvent[event] then
        if T.IsEnabled() and now() - lastDiscover >= 10 then
            T.Discover()
        end
    elseif isChangeEvent[event] then
        if T.IsEnabled() then
            Sync.NoteLocalChange(env)
        end
    end
end)

return T
