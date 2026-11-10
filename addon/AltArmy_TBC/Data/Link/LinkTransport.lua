-- AltArmy TBC — Linked accounts in the running client: Battle.net game data in and out (linked accounts).
-- The glue LinkSession and LinkSync run on (their `env`): messages go out as LinkCodec chunks through
-- ChatThrottleLib's Battle.net game data (prefix PREFIX, its own queue so it never holds up guild sharing),
-- and come in on BN_CHAT_MSG_ADDON. A chunk is dropped before anything is kept unless its sender is one of
-- this Battle.net account's game accounts (LinkDiscovery, asked of the client, cached CACHE_MINE seconds),
-- or if any of its arguments is a secret value. Nothing is sent during combat or chat lockdown (it waits,
-- in order), and a whole message that arrives in combat is read once combat ends. Off unless
-- Debug.IsLinkedAccountsEnabled().
-- The group route: a client can lose Battle.net's friends service while staying in game (BattleNetUp false:
-- no game account can be told to be ours), so linked accounts' characters in this party or raid are also
-- reached by addon messages to the group (PARTY/RAID, each chunk wrapped with the account it is for and the
-- sender's GUID: LinkCodec.Wrap), but only while everyone else in the group is a linked account's character
-- (LinkDiscovery.GroupCandidates): the whole group hears what is sent. Peers keyed "u:<guid>" (LinkSession).
-- luacheck: read globals C_ChatInfo ChatThrottleLib C_BattleNet WOW_PROJECT_ID C_EventUtils
-- luacheck: read globals IsInGroup IsInRaid GetNumGroupMembers LE_PARTY_CATEGORY_HOME

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
local bnUp -- LinkDiscovery.BattleNetUp at the last discovery (nil before the first)
local groupOwners = {} -- group route key ("u:<guid>") -> the linked account that character belongs to
local groupWhy = "noGroup" -- why the group route is not used, or nil when it is

local function now()
    return time and time() or 0
end

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
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

local function groupChannel()
    return IsInRaid and IsInRaid() and "RAID" or "PARTY"
end

local function sendChunks(item)
    local CTL = ChatThrottleLib
    if type(item.g) == "string" then
        if not groupOwners[item.g] then
            return -- the group changed since: its sync asks again
        end
        local channel = groupChannel()
        for _, text in ipairs(item.chunks) do
            if CTL and CTL.SendAddonMessage then
                CTL:SendAddonMessage(item.prio, T.PREFIX, text, channel, nil, T.PREFIX .. "group")
            elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
                C_ChatInfo.SendAddonMessage(T.PREFIX, text, channel)
            end
        end
        return
    end
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
    if type(g) == "string" then
        return groupOwners[g] ~= nil
    end
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
        if AltArmy.LinkAccountsOnboarding and AltArmy.LinkAccountsOnboarding.Check then
            AltArmy.LinkAccountsOnboarding.Check() -- an account of ours not linked yet: offer it once
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, run)
    else
        run()
    end
end

--- A message to `g` as what goes on the wire: chunks, wrapped for the group route; nil if `g` can't be reached.
local function chunksFor(g, msg, l)
    local payload = C.Encode(msg, l)
    if type(g) ~= "string" then
        return C.Split(payload, nextMsgId())
    end
    local to, from = groupOwners[g], UnitGUID and UnitGUID("player")
    if not to or type(from) ~= "string" then
        return nil
    end
    local out = {}
    for i, chunk in ipairs(C.Split(payload, nextMsgId(), C.WrapRoom(to, from))) do
        out[i] = C.Wrap(to, from, chunk)
    end
    return out
end

local env = {}
T.env = env

function env.send(g, msg, prio)
    local l = getLibs()
    if not l then
        return
    end
    local chunks = chunksFor(g, msg, l)
    if not chunks then
        return
    end
    local item = { g = g, prio = prio or "NORMAL", chunks = chunks }
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
    local chunks = l and chunksFor(g, msg, l)
    if not chunks then
        return
    end
    if type(g) == "string" then
        local chat = C_ChatInfo
        if chat and chat.SendAddonMessage then
            local channel = groupChannel()
            for _, text in ipairs(chunks) do
                pcall(chat.SendAddonMessage, T.PREFIX, text, channel)
            end
        end
        return
    end
    local bn = C_BattleNet
    if not (bn and bn.SendGameData) then
        return
    end
    for _, chunk in ipairs(chunks) do
        pcall(bn.SendGameData, g, T.PREFIX, chunk)
    end
end

env.now = now
env.random = math.random
env.isMine = isMine

--- The linked account a group route key must be (nil for a Battle.net game account).
function env.ownerOf(g)
    return type(g) == "string" and groupOwners[g] or nil
end

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

--- LinkMail wrote mail a linked account sent into our character `guid`: Search and the Inventory redraw.
function env.ownMailChanged()
    local SD = AltArmy.SearchData
    if SD and SD.NotifyContainerDataChanged then
        SD.NotifyContainerDataChanged()
    end
    local DS = AltArmy.DataStore
    if DS and DS.FireContainerDataChanged then
        DS:FireContainerDataChanged()
    end
end

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

local function receiveChunk(g, chunk)
    local payload = reassembler:Add(g, chunk, now())
    if not payload then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if #inbox < T.MAX_INBOX then
            inbox[#inbox + 1] = { g = g, payload = payload }
        end
        return
    end
    handlePayload(g, payload)
end

local function onAddonMessage(prefix, text, _, sender)
    if isSecret(prefix) or prefix ~= T.PREFIX or not T.IsEnabled() then
        return
    end
    if isSecret(text) or isSecret(sender) or type(text) ~= "string" or not isMine(sender) then
        return
    end
    receiveChunk(sender, text)
end

--- A chunk on the group route (CHAT_MSG_ADDON): taken only when it is for this account and from a linked
--- account's character in the group.
local function onGroupMessage(prefix, text, channel)
    if isSecret(prefix) or prefix ~= T.PREFIX or not T.IsEnabled() then
        return
    end
    if isSecret(text) or isSecret(channel) or (channel ~= "PARTY" and channel ~= "RAID") then
        return
    end
    local to, from, chunk = C.Unwrap(text)
    if not to or to ~= env.myAccountId() or not groupOwners["u:" .. from] then
        return
    end
    receiveChunk("u:" .. from, chunk)
end

--- The others in this (home) party or raid: { guid, name } each.
local function groupMembers()
    local out = {}
    local home = LE_PARTY_CATEGORY_HOME
    if not (IsInGroup and IsInGroup(home)) or not UnitGUID then
        return out
    end
    local raid = IsInRaid and IsInRaid(home)
    local n = GetNumGroupMembers and GetNumGroupMembers(home) or 0
    local mine = UnitGUID("player")
    for i = 1, raid and n or n - 1 do
        local unit = (raid and "raid" or "party") .. i
        local guid = UnitGUID(unit)
        if guid and not isSecret(guid) and guid ~= mine then
            local name = UnitName and UnitName(unit)
            out[#out + 1] = { guid = guid, name = not isSecret(name) and name or nil }
        end
    end
    return out
end

--- Which linked accounts' characters this group reaches (none unless the group is nobody else's), and HELLO.
function T.DiscoverGroup()
    if not T.IsEnabled() then
        return
    end
    local candidates, why = LD.GroupCandidates(groupMembers(), AltArmy.LinkStore.AccountOf)
    groupOwners = {}
    for _, c in ipairs(candidates) do
        groupOwners[c.key] = c.acct
    end
    groupWhy = why
    Session.Discover(env, candidates, "group")
end

--- Whether this client is on Battle.net, as the last discovery found (true before the first).
function T.BattleNetAvailable()
    return bnUp ~= false
end

--- Why the group route is not used ("noGroup", "stranger"), or nil when it is.
function T.GroupRouteWhy()
    return groupWhy
end

--- Look for our other accounts online now (over Battle.net, then in the group) and say HELLO.
function T.Discover()
    if not T.IsEnabled() then
        return
    end
    lastDiscover = now()
    local api = LD.LiveApi()
    me = LD.Me(api)
    mineCache = {}
    local wasUp = bnUp
    bnUp = LD.BattleNetUp(me)
    Session.Discover(env, LD.Candidates(LD.Scan(api, me)))
    T.DiscoverGroup()
    if wasUp ~= bnUp then
        refreshUi()
    end
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

--- One of our characters mailed (or returned mail to) `name` on `realm`, none of ours (DataStoreMail's
--- SendMail hook): if a linked account has that character, it shows the mail now and that account is told.
function T.MailSent(realm, name, rows, sender, returned)
    if not T.IsEnabled() then
        return false
    end
    return Session.SendMail(env, realm, name, rows, sender, returned)
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
local BNET_EVENTS = { "BN_INFO_CHANGED", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED",
    "BN_DISCONNECTED" }
-- Battle.net coming back or going: look again at once (the Sharing page says whether it is up).
local BNET_STATE_EVENTS = { BN_CONNECTED = true, BN_DISCONNECTED = true }

local frame = CreateFrame("Frame")
local function register(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return
    end
    pcall(frame.RegisterEvent, frame, event)
end
register("PLAYER_LOGIN")
register("BN_CHAT_MSG_ADDON")
register("CHAT_MSG_ADDON")
register("GROUP_ROSTER_UPDATE")
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
    elseif event == "CHAT_MSG_ADDON" then
        onGroupMessage(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        T.DiscoverGroup()
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
        if T.IsEnabled() and (BNET_STATE_EVENTS[event] or now() - lastDiscover >= 10) then
            T.Discover()
        end
    elseif isChangeEvent[event] then
        if T.IsEnabled() then
            Sync.NoteLocalChange(env)
        end
    end
end)

return T
