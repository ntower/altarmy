-- AltArmy TBC — Guild data sharing: comm layer (AceComm/AceSerializer wiring).
-- luacheck: globals C_Timer
-- Broadcasts a privacy-limited presence over the GUILD channel and pulls recipe lists
-- on demand (guildmates who share nothing are read through profession links instead: GuildLinkRead).
-- Sending is ALWAYS active (subject to the send-set below); receiving + UI
-- are gated behind the guildShare feature flag, except that inbound RQ/CQ (recipe / char-card
-- requests) are always processed: flag-off clients always reply with RC/CC; flag-on clients
-- reply only when guild sharing is enabled in Options.
-- ScheduleBroadcast is a trailing-edge debounce (timer resets on each call). Options/
-- onboarding use 5s; profession/recipe scans use PROFESSION_BROADCAST_DEBOUNCE_SEC so
-- long craft casts (e.g. 8s bandages) do not each complete the quiet window mid-session.
-- Login/reload and guild join/leave Broadcast immediately. Login/reload presence carries
-- login=true so peers whisper a PR reply even when data is already stored.
--
-- Send-set inversion (see GuildShareSettings):
--   flag OFF -> GetAllGuildedCharacters() (ignore the user's settings; lets the developer
--               collect data from flag-off guildmates). Empty set => no send.
--   flag ON  -> GetShareableCharacters() (opt-in, defaults to none). Empty set => still
--               send an empty presence so peers clear previously received characters.
--
-- Libs are acquired lazily inside Init() (called on login) so this file's position in the
-- .toc relative to the Ace3 libs does not matter.

if not AltArmy then return end

AltArmy.GuildShareComm = AltArmy.GuildShareComm or {}
local Comm = AltArmy.GuildShareComm

local PREFIX = "AltArmyGS"
local MSG_PRESENCE = "P"       -- initial presence broadcast
local MSG_PRESENCE_REPLY = "PR" -- whispered reply to a broadcast (no further reply)
local MSG_REQ_RECIPES = "RQ"   -- request recipe list for a character
local MSG_RECIPES = "RC"       -- recipe list reply
local MSG_REQ_CHAR_CARD = "CQ" -- request profession card for one character
local MSG_CHAR_CARD = "CC"     -- profession card reply

local MSG_LABELS = {
    [MSG_PRESENCE] = "presence",
    [MSG_PRESENCE_REPLY] = "presence reply",
    [MSG_REQ_RECIPES] = "recipe request",
    [MSG_RECIPES] = "recipes",
    [MSG_REQ_CHAR_CARD] = "char card request",
    [MSG_CHAR_CARD] = "char card",
}

--- Human-readable log label for a wire message type, e.g. "P (presence)".
local function formatMsgType(msgType)
    local label = MSG_LABELS[msgType]
    if label then
        return string.format("%s (%s)", msgType, label)
    end
    return tostring(msgType)
end
Comm._FormatMsgType = formatMsgType

local UNDECODABLE_HEAD_LEN = 48

--- Safe short preview of a raw AceComm payload for chat debug logs.
local function messageHead(message)
    if type(message) ~= "string" then
        return string.format("<%s>", type(message))
    end
    local head = message:sub(1, UNDECODABLE_HEAD_LEN)
    head = head:gsub("[%c]", ".")
    if #message > UNDECODABLE_HEAD_LEN then
        head = head .. "..."
    end
    return head
end

local function undecodableReason(deserializeOk, firstValue)
    if not deserializeOk then
        return tostring(firstValue)
    end
    return "msgType=" .. type(firstValue)
end

--- Verbose log line when AceSerializer cannot decode an inbound guild-share message.
function Comm._FormatUndecodableRecvLog(prefix, message, distribution, rawSender, deserializeOk, firstValue)
    local bytes = (type(message) == "string") and #message or 0
    return string.format(
        "recv (undecodable) from %s prefix=%s dist=%s bytes=%d reason=%s head=%s",
        tostring(rawSender),
        tostring(prefix),
        tostring(distribution),
        bytes,
        undecodableReason(deserializeOk, firstValue),
        messageHead(message)
    )
end

--- SavedVariables payload for the latest undecodable inbound message (full wire body).
function Comm._BuildUndecodableDump(prefix, message, distribution, rawSender, deserializeOk, firstValue)
    local msg = (type(message) == "string") and message or ""
    return {
        version = 1,
        timestamp = (time and time()) or 0,
        prefix = tostring(prefix),
        distribution = tostring(distribution),
        sender = tostring(rawSender),
        bytes = #msg,
        deserializeOk = deserializeOk and true or false,
        reason = undecodableReason(deserializeOk, firstValue),
        head = messageHead(message),
        message = msg,
    }
end

local function saveUndecodableDump(prefix, message, distribution, rawSender, deserializeOk, firstValue)
    local D = AltArmy.Debug
    if not D or not D.AppendGuildShareUndecodableDump then return end
    local payload = Comm._BuildUndecodableDump(
        prefix, message, distribution, rawSender, deserializeOk, firstValue
    )
    -- The sender's recent raw parts (GuildShareProbe): which part of a multipart message went missing.
    local Probe = AltArmy.GuildShareProbe
    if Probe and Probe.PartsFrom then
        local ok, recent = pcall(Probe.PartsFrom, rawSender)
        if ok then payload.parts = recent end
        -- Again a few seconds on: the part that completed this message (the probe sees it after AceComm does),
        -- and a missing part that only arrives late.
        local ctimer = _G.C_Timer
        if ctimer and ctimer.After then
            ctimer.After(Probe.LATE_PARTS_SEC or 8, function()
                local okLate, later = pcall(Probe.PartsFrom, rawSender)
                if okLate then payload.partsLater = later end
            end)
        end
    end
    local index = D.AppendGuildShareUndecodableDump(payload)
    -- Chat tip only when verbose logging is on (dump itself always saved, last one kept).
    if index and D.IsGuildShareVerbose and D.IsGuildShareVerbose()
        and D.NotifyGuildShareUndecodableDumpSaved then
        D.NotifyGuildShareUndecodableDumpSaved(index, index)
    end
end

local BROADCAST_THROTTLE = 10          -- seconds between guild broadcasts
-- Debounce window for Options/onboarding settings changes (coalesce rapid toggles).
Comm.SETTINGS_BROADCAST_DEBOUNCE_SEC = 5
-- Longer than typical craft cast times so skill-ups during a crafting session coalesce.
Comm.PROFESSION_BROADCAST_DEBOUNCE_SEC = 30
-- Prune received data older than 180 days (30+ day data stays but is flagged in the Guild tab).
Comm.STALE_MAX_AGE = 60 * 60 * 24 * 180
local STALE_MAX_AGE = Comm.STALE_MAX_AGE

local commObj            -- table embedded with AceComm-3.0 + AceSerializer-3.0
local initialized = false
local lastBroadcast = 0
local settingsBroadcastGeneration = 0
local knownGuild        -- last observed guild name, to detect gkick/gquit/gjoin

-- *** Small helpers (some exposed for unit tests) ***

local function isReceiveEnabled()
    local D = AltArmy.Debug
    return D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() == true
end

--- True when an inbound message type may be processed (RQ/CQ always allowed).
local function isInboundAllowed(msgType)
    if msgType == MSG_REQ_RECIPES or msgType == MSG_REQ_CHAR_CARD then return true end
    return isReceiveEnabled()
end
Comm._IsInboundAllowed = isInboundAllowed

--- True when this client should send RC in response to an inbound RQ.
function Comm._ShouldRespondToRecipeRequest()
    if not isReceiveEnabled() then
        return true
    end
    local GSS = AltArmy.GuildShareSettings
    return GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled() == true
end

--- True when this client should send CC in response to an inbound CQ.
function Comm._ShouldRespondToCharCardRequest()
    return Comm._ShouldRespondToRecipeRequest()
end

--- Verbose traffic logging (gated by the standalone guildShareVerbose debug flag).
local function log(msg)
    local D = AltArmy.Debug
    if D and D.LogGuildShare then
        D.LogGuildShare(msg)
    end
end

local function playerName()
    return (UnitName and UnitName("player")) or ""
end

--- The logged-in character's ID (GUID), or nil when unknown.
local function playerGuid()
    local DS = AltArmy.DataStore
    if DS and DS.GetCurrentPlayerGUID then
        return DS:GetCurrentPlayerGUID()
    end
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

local function currentRealm()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm then return GSS._CurrentRealm() end
    return (GetRealmName and GetRealmName()) or ""
end

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end

--- Strip any realm suffix an addon-message sender may carry ("Name-Realm" -> "Name").
local function normalizeSender(sender)
    if type(sender) ~= "string" then return sender end
    return sender:match("^[^%-]+") or sender
end
Comm._NormalizeSender = normalizeSender

--- True when the addon-message sender is this client (guild broadcasts echo back to self).
local function isLocalSender(sender)
    local mine = normalizeSender(playerName())
    if mine == "" then return false end
    return normalizeSender(sender) == mine
end
Comm._IsLocalSender = isLocalSender

--- True when a received message came from this client. Messages that carry the sender's ID are
--- judged by ID alone: on WoW Forever another guildmate's short name can equal ours. Messages from
--- older versions carry no ID and fall back to the name.
local function isLocalMessage(payload, sender)
    local from = type(payload) == "table" and payload.from or nil
    if type(from) == "string" and from ~= "" then
        return from == playerGuid()
    end
    return isLocalSender(sender)
end
Comm._IsLocalMessage = isLocalMessage

--- Select the set of characters to broadcast, branching on the feature flag.
--- Exposed for unit testing the flag inversion.
function Comm._SelectShareChars(flagOn, guild, realm)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return {} end
    if flagOn then
        return GSS.GetShareableCharacters(guild, realm)
    end
    return GSS.GetAllGuildedCharacters(guild, realm)
end

local function sameRealm(a, b)
    local RF = AltArmy.RealmFilter
    if RF and RF.sameRealm then return RF.sameRealm(a, b) end
    return (a or "") == (b or "")
end

--- The share set across every realm one with `realm` (WoW Forever's coalesced realms: the player's characters
--- report "CAMWOW US1 Realm 5 PvE" or "CAMWOW US2 Realm 3 PvE" yet play together), `realm` itself first. Each
--- entry carries its own realm. Elsewhere realms are one only with themselves, so this is the realm's set.
function Comm._SelectShareCharsInGroup(flagOn, guild, realm)
    local realms = { realm }
    local DS = AltArmy.DataStore
    if DS and DS.GetRealms then
        local others = {}
        for r in pairs(DS:GetRealms() or {}) do
            if r ~= realm and sameRealm(r, realm) then others[#others + 1] = r end
        end
        table.sort(others)
        for _, r in ipairs(others) do realms[#realms + 1] = r end
    end
    local out = {}
    for _, r in ipairs(realms) do
        for _, entry in ipairs(Comm._SelectShareChars(flagOn, guild, r)) do
            out[#out + 1] = entry
        end
    end
    return out
end

--- Legacy helper: sharing-disabled no longer skips the wire send (an empty presence is
--- broadcast instead so peers can clear). Kept for tests / call sites; always returns nil.
function Comm._BroadcastSkippedLogMessage(_flagOn, _sharingEnabled)
    return nil
end

--- Build a presence payload for the selected share set.
--- Flag ON + empty set => empty presence (opt-out clear). Flag OFF + empty => nil (no send).
function Comm._PresenceForShareChars(flagOn, chars, mainName, displayName)
    local P = AltArmy.GuildShareProtocol
    if not P or type(P.BuildPresence) ~= "function" then return nil end
    chars = chars or {}
    if #chars == 0 then
        if flagOn then
            return P.BuildPresence({}, nil, nil)
        end
        return nil
    end
    return P.BuildPresence(chars, mainName, displayName)
end

--- True when the player's guild membership changed (nil and name are distinct states).
function Comm._GuildMembershipChanged(prevGuild, newGuild)
    return prevGuild ~= newGuild
end

--- Whether PLAYER_ENTERING_WORLD should broadcast (login/reload only; not zone transitions).
function Comm._ShouldBroadcastOnEnteringWorld(isInitialLogin, isReloadingUi)
    return isInitialLogin == true or isReloadingUi == true
end

--- True when it is safe to send on the GUILD channel.
--- IsInGuild can be true briefly at login before GetGuildInfo returns a name; sending then
--- builds an empty opt-in presence and clears peers. Require a real guild name.
function Comm._ShouldSendGuildBroadcast(isInGuild, guildName)
    return isInGuild == true and type(guildName) == "string" and guildName ~= ""
end

--- Stamp or clear the login announce flag on a presence payload.
function Comm._WithLoginAnnounce(presence, isLoginAnnounce)
    if not presence then return nil end
    if isLoginAnnounce then
        presence.login = true
    else
        presence.login = nil
    end
    return presence
end

--- Patch 12.0+ clients (Forever included) can hand GetGuildRosterInfo() names to
--- addons as Secret Values that error on any operation beyond store/pass.
--- `canaccessvalue()` (existence-checked) is the guard, matching
--- DataStoreProfessions.lua's fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

-- Enum.ClubMemberPresence: Online 1, OnlineMobile 2 (the app, not in game), Offline 3, Away 4, Busy 5.
local IN_GAME_PRESENCE = { [1] = true, [4] = true, [5] = true }

local function accessible(value)
    return value ~= nil and canAccessSecretValue(value)
end

local function classFileOf(classID)
    if type(classID) ~= "number" then return nil end
    local creature = _G.C_CreatureInfo
    if creature and creature.GetClassInfo then
        local ok, info = pcall(creature.GetClassInfo, classID)
        if ok and type(info) == "table" and type(info.classFile) == "string" then return info.classFile end
    end
    if _G.GetClassInfo then
        local ok, _, file = pcall(_G.GetClassInfo, classID)
        if ok and type(file) == "string" then return file end
    end
    return nil
end

--- The guild's members from the Club API (C_Club, what the retail guild UI reads), for clients whose
--- classic roster stays empty: { { name, guid, level, classFile, online }, ... }, or nil when the client
--- has no guild club. `club` may override C_Club (tests).
function Comm.ClubRosterRows(club)
    club = club or _G.C_Club
    if type(club) ~= "table" or not club.GetGuildClubId or not club.GetClubMembers or not club.GetMemberInfo then
        return nil
    end
    local okId, clubId = pcall(club.GetGuildClubId)
    if not okId or not accessible(clubId) then return nil end
    local okM, memberIds = pcall(club.GetClubMembers, clubId)
    if not okM or type(memberIds) ~= "table" then return nil end
    local rows = {}
    for _, memberId in ipairs(memberIds) do
        local ok, info = pcall(club.GetMemberInfo, clubId, memberId)
        if ok and type(info) == "table" and info.isSelf ~= true then
            local presence = accessible(info.presence) and info.presence or 0
            rows[#rows + 1] = {
                name = accessible(info.name) and info.name or nil,
                guid = accessible(info.guid) and info.guid or nil,
                level = accessible(info.level) and tonumber(info.level) or nil,
                classFile = classFileOf(accessible(info.classID) and info.classID or nil),
                online = IN_GAME_PRESENCE[presence] == true,
            }
        end
    end
    return rows
end

--- The guild roster as rows { name, guid, level, classFile, online }: the classic roster
--- (GetGuildRosterInfo), else the Club API's when the classic one reads empty (WoW Forever). Also says
--- which: "roster" or "club". `api` may override getNumGuildMembers, getGuildRosterInfo and club (tests).
function Comm.GuildRosterRows(api)
    api = api or {}
    local getNum = api.getNumGuildMembers or GetNumGuildMembers
    local getInfo = api.getGuildRosterInfo or GetGuildRosterInfo
    local rows = {}
    local n = 0
    if getNum then
        local ok, count = pcall(getNum)
        if ok and accessible(count) then n = tonumber(count) or 0 end
    end
    if getInfo and n > 0 then
        for i = 1, n do
            local name, _, _, level, _, _, _, _, online, _, classFile, _, _, _, _, _, guid = getInfo(i)
            rows[#rows + 1] = {
                name = accessible(name) and name or nil,
                guid = accessible(guid) and guid or nil,
                level = accessible(level) and tonumber(level) or nil,
                classFile = (type(classFile) == "string" and accessible(classFile)) and classFile or nil,
                online = online and true or false,
            }
        end
        return rows, "roster"
    end
    local clubRows = Comm.ClubRosterRows(api.club)
    if clubRows and #clubRows > 0 then return clubRows, "club" end
    return rows, "roster"
end

local function collectOnlineGuildMembers()
    local out = {}
    if not (IsInGuild and IsInGuild()) then return out end
    local mine = normalizeSender(playerName())
    for _, row in ipairs((Comm.GuildRosterRows())) do
        if row.online and type(row.name) == "string" then
            local short = normalizeSender(row.name)
            if short ~= "" and short ~= mine then
                out[short] = true
            end
        end
    end
    return out
end
Comm._CollectOnlineGuildMembers = collectOnlineGuildMembers

--- Ask the server for the guild roster. The roster stays empty (GetNumGuildMembers() = 0) until it is
--- asked for; WoW Forever has only C_GuildInfo.GuildRoster, older clients only the GuildRoster global.
--- Returns true when a request went out.
function Comm.RequestGuildRoster()
    local info = _G.C_GuildInfo
    if info and info.GuildRoster then
        return (pcall(info.GuildRoster))
    end
    if _G.GuildRoster then
        return (pcall(_G.GuildRoster))
    end
    return false
end

--- True when a guildmate (normalized short name) is online in the roster.
function Comm.IsGuildMemberOnline(name)
    name = normalizeSender(name)
    if name == "" then return false end
    return collectOnlineGuildMembers()[name] == true
end

local function handlePlayerGuildUpdate()
    local newGuild = currentGuild()
    if not Comm._GuildMembershipChanged(knownGuild, newGuild) then
        return
    end
    if knownGuild then
        local GSD = AltArmy.GuildShareData
        if GSD and GSD.PurgeGuild then
            pcall(function() GSD.PurgeGuild(knownGuild) end)
        end
        Comm.NotifyDataChanged()
    end
    knownGuild = newGuild
    -- Join / guild info becoming available (common login race): login-announce so peers
    -- whisper PR. Leave (newGuild nil): do not send — Broadcast also refuses nil guild.
    if newGuild then
        Comm.Broadcast(true, true)
    end
end
Comm._HandlePlayerGuildUpdate = handlePlayerGuildUpdate

-- *** Sending ***

local function serialize(msgType, payload)
    if not commObj then return nil end
    return commObj:Serialize(msgType, payload)
end

-- *** Numbered parts (GuildShareReassembly.SplitSequenced) ***
-- Every message says this client reads numbered parts (`mp`, MULTIPART_VERSION); a whisper over 255 bytes to a
-- peer whose last message said so goes in numbered parts, reassembled exactly whatever order they arrive in.
-- Anyone else (and the guild channel, where not every reader has it) gets AceComm's parts as before.
Comm.MULTIPART_VERSION = 1

local peerNumbered = {}   -- [short sender] = true when their last message carried `mp`

--- Remember whether a peer reads numbered parts, from a message they sent.
function Comm._NotePeerCapabilities(payload, sender)
    if type(payload) ~= "table" or type(sender) ~= "string" then return end
    local short = normalizeSender(sender)
    if short == "" then return end
    peerNumbered[short] = (tonumber(payload.mp) or 0) >= 1 or nil
end

function Comm._PeerReadsNumbered(target)
    return type(target) == "string" and peerNumbered[normalizeSender(target)] == true
end

local nextMessageId = math.random and math.random(0, 1295) or 0
local ID_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

--- A short id for a numbered message (two base-36 digits; it only has to differ from the sender's other
--- messages still in flight).
local function newMessageId()
    nextMessageId = (nextMessageId + 1) % 1296
    local hi, lo = math.floor(nextMessageId / 36), nextMessageId % 36
    return ID_DIGITS:sub(hi + 1, hi + 1) .. ID_DIGITS:sub(lo + 1, lo + 1)
end
Comm._NewMessageId = newMessageId

--- Send `data` to `target` in numbered parts through ChatThrottleLib's queue for our prefix (AceComm's own
--- messages use the same queue, so everything goes out in order). Returns false when it can't.
local function sendNumbered(data, target, onResult)
    local R = AltArmy.GuildShareReassembly
    local CTL = _G.ChatThrottleLib
    if not (R and R.SplitSequenced and CTL and CTL.SendAddonMessage) then return false end
    local parts = R.SplitSequenced(data, newMessageId())
    for i, part in ipairs(parts) do
        local callback = (onResult and i == #parts) and function(_, sent, sendResult)
            pcall(onResult, sent, sendResult)
        end or nil
        CTL:SendAddonMessage("NORMAL", PREFIX, part, "WHISPER", target, PREFIX, callback)
    end
    return true
end

--- `onResult(sent, sendResult)` (optional) is called per wire part once ChatThrottleLib sends it
--- (GuildShareProbe reads the client's send result).
local function send(msgType, payload, distribution, target, onResult)
    -- Stamp the sending character's ID so peers can tell senders apart and ignore our echo.
    -- Older clients ignore the field.
    if type(payload) == "table" and payload.from == nil then
        payload.from = playerGuid()
    end
    if type(payload) == "table" and payload.mp == nil then
        payload.mp = Comm.MULTIPART_VERSION
    end
    -- Unit-test hook: capture outbound messages without AceComm.
    if Comm._TestHookSend then
        Comm._TestHookSend(msgType, payload, distribution, target)
        return
    end
    local data = serialize(msgType, payload)
    if not data then return end
    log(string.format("SEND %s -> %s%s (%d bytes)",
        formatMsgType(msgType), distribution, target and (":" .. target) or "", #data))
    pcall(function()
        if distribution == "WHISPER" and #data > 255 and Comm._PeerReadsNumbered(target)
            and sendNumbered(data, target, onResult) then
            return
        end
        local callback = onResult and function(_, sent, _, sendResult) pcall(onResult, sent, sendResult) end
        commObj:SendCommMessage(PREFIX, data, distribution, target, "NORMAL", callback)
    end)
end
Comm._Send = send

--- On-demand recipe pull for one character; whispers `sender` when they are online and recipes are missing.
--- `guid` (optional) is the character's ID; the name is always sent for responders on older versions. `realm` is
--- the realm table the character is stored in; the request names the realm the character reports.
--- Returns true when a request was sent.
function Comm.RequestRecipesForCharacter(name, realm, sender, guid)
    if not name or not sender or sender == "" then return false end
    sender = normalizeSender(sender)
    if not Comm.IsGuildMemberOnline(sender) then return false end
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetProfessionsNeedingRecipes then return false end
    local storedKey = guid or name
    local needed = GSD.GetProfessionsNeedingRecipes(storedKey, realm)
    if #needed == 0 then return false end
    -- Name the character's own realm: responders look their characters up by it (older versions by it alone).
    local stored = GSD.GetCharacter and GSD.GetCharacter(storedKey, realm)
    local charRealm = stored and stored.charRealm or realm
    send(MSG_REQ_RECIPES, { name = name, realm = charRealm, guid = guid }, "WHISPER", sender)
    if GSD.MarkRecipesRequested then
        GSD.MarkRecipesRequested(storedKey, realm, needed)
    end
    return true
end

--- On-demand profession-card pull for one character (slim v2 presence follow-up).
--- Returns true when a request was sent.
function Comm.RequestCharCard(name, realm, sender, guid)
    if not name or not sender or sender == "" then return false end
    sender = normalizeSender(sender)
    if not Comm.IsGuildMemberOnline(sender) then return false end
    local P = AltArmy.GuildShareProtocol
    if not P or not P.BuildCharCardRequest then return false end
    send(MSG_REQ_CHAR_CARD, P.BuildCharCardRequest(name, realm, guid), "WHISPER", sender)
    local GSD = AltArmy.GuildShareData
    if GSD and GSD.MarkCardRequested and GSD.StorageRealm then
        GSD.MarkCardRequested(guid or name, GSD.StorageRealm(currentRealm(), guid))
    end
    return true
end

Comm.SWEEP_SEC = 60            -- how often cards and recipes still missing are asked for again
Comm.SWEEP_MAX_REQUESTS = 8    -- requests one sweep sends at most
Comm.RETRY_AFTER_LOSS_SEC = 5  -- after a sender's message is lost, ask them again this soon

--- Ask again for what guildmates online still owe: a card (GSD.CardRetryDue; `force` ignores the back-off,
--- for right after one of their messages was lost) or recipe lists (RequestRecipesForCharacter's own back-off).
--- `onlySender` (optional) limits it to one sender's characters. Returns how many requests went out.
function Comm.SweepPending(onlySender, force, nowTs)
    local GSD = AltArmy.GuildShareData
    if not (GSD and GSD.SharedCharactersInGroup and GSD.CardRetryDue) then return 0 end
    if not (IsInGuild and IsInGuild()) then return 0 end
    nowTs = nowTs or ((time and time()) or 0)
    local sent = 0
    local online = {}
    for _, item in ipairs(GSD.SharedCharactersInGroup(currentRealm())) do
        if sent >= Comm.SWEEP_MAX_REQUESTS then break end
        local entry, storedRealm = item.entry, item.realm
        local source = normalizeSender(entry.source)
        if (not onlySender or source == normalizeSender(onlySender)) then
            if online[source] == nil then online[source] = Comm.IsGuildMemberOnline(source) end
            if online[source] then
                if entry.needsProfessionCard then
                    if force or GSD.CardRetryDue(entry, nowTs) then
                        if Comm.RequestCharCard(entry.name, entry.charRealm or storedRealm, source, entry.guid) then
                            sent = sent + 1
                        end
                    end
                elseif Comm.RequestRecipesForCharacter(entry.name, storedRealm, source, entry.guid) then
                    sent = sent + 1
                end
            end
        end
    end
    if sent > 0 then log(string.format("sweep: asked again %d time(s)%s", sent,
        onlySender and (" of " .. tostring(onlySender)) or "")) end
    return sent
end

local sweepScheduled = false

--- Sweep every SWEEP_SEC from login on.
local function scheduleSweeps()
    local ctimer = _G.C_Timer
    if sweepScheduled or not (ctimer and ctimer.After) then return end
    sweepScheduled = true
    local function tick()
        pcall(Comm.SweepPending)
        ctimer.After(Comm.SWEEP_SEC, tick)
    end
    ctimer.After(Comm.SWEEP_SEC, tick)
end

--- A sender's message was lost or mangled: ask them again shortly, without waiting for the back-off.
function Comm.RetryAfterLoss(sender)
    local ctimer = _G.C_Timer
    if not (ctimer and ctimer.After) or type(sender) ~= "string" then return end
    ctimer.After(Comm.RETRY_AFTER_LOSS_SEC, function()
        pcall(Comm.SweepPending, sender, true)
    end)
end

--- Build my presence payload for the given guild/realm (respecting the flag-branched set).
local function buildMyPresence(guild, realm)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return nil end
    local flagOn = isReceiveEnabled()
    local chars = Comm._SelectShareCharsInGroup(flagOn, guild, realm)
    local mainName, displayName
    if #chars > 0 and GSS.ResolvePresenceMainAndDisplay then
        mainName, displayName = GSS.ResolvePresenceMainAndDisplay(chars, realm)
    end
    return Comm._PresenceForShareChars(flagOn, chars, mainName, displayName)
end

--- Broadcast presence to the guild. When isLoginAnnounce is true, peers whisper a PR
--- reply even if they already have our data (covers newcomers who missed prior sends).
function Comm.Broadcast(force, isLoginAnnounce)
    if not Comm._TestHookSend and not commObj then return end
    local inGuild = IsInGuild and IsInGuild() == true
    local guild = currentGuild()
    if not Comm._ShouldSendGuildBroadcast(inGuild, guild) then
        return
    end
    local nowTs = (GetTime and GetTime()) or 0
    if not force and (nowTs - lastBroadcast) < BROADCAST_THROTTLE then return end
    local realm = currentRealm()
    local presence = Comm._WithLoginAnnounce(buildMyPresence(guild, realm), isLoginAnnounce)
    if not presence then
        return
    end
    lastBroadcast = nowTs
    log(string.format("broadcasting presence: %d character(s) to guild '%s' (flag %s%s)",
        #presence.chars, tostring(guild), isReceiveEnabled() and "on/opt-in" or "off/all-guilded",
        isLoginAnnounce and ", login announce" or ""))
    send(MSG_PRESENCE, presence, "GUILD")
end

--- Cancel a pending settings-driven presence broadcast.
function Comm.CancelScheduledBroadcast()
    settingsBroadcastGeneration = settingsBroadcastGeneration + 1
end

--- Schedule a forced presence broadcast after a quiet period (trailing-edge debounce).
--- Repeated calls reset the timer. delaySec defaults to SETTINGS_BROADCAST_DEBOUNCE_SEC;
--- pass PROFESSION_BROADCAST_DEBOUNCE_SEC for skill/recipe scans.
function Comm.ScheduleBroadcast(delaySec)
    Comm.CancelScheduledBroadcast()
    local generation = settingsBroadcastGeneration
    local delay = delaySec or Comm.SETTINGS_BROADCAST_DEBOUNCE_SEC
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(delay, function()
            if generation ~= settingsBroadcastGeneration then return end
            Comm.Broadcast(true)
        end)
    else
        Comm.Broadcast(true)
    end
end

-- *** Receiving (gated by the feature flag) ***

--- Notify dependents that guild data changed (search cache, guild tab).
function Comm.NotifyDataChanged()
    local SD = AltArmy.SearchData
    if SD and SD.NotifyRecipesChanged then
        pcall(SD.NotifyRecipesChanged)
    end
    if AltArmy.RefreshGuildTab then
        pcall(AltArmy.RefreshGuildTab)
    end
end

-- *** Debug: single-account test injection ***

--- Pick one of the player's own scanned characters that has professions, so the test
--- injection can seed realistic recipe data that resolves to real names in search.
--- Returns a char table (with .Professions) or nil.
function Comm._PickSampleProfChar(realm)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacters then return nil end
    local chars = DS:GetCharacters(realm) or {}
    local best, bestCount
    for _, char in pairs(chars) do
        if type(char) == "table" and type(char.Professions) == "table" then
            local count = 0
            for _ in pairs(char.Professions) do count = count + 1 end
            if count > 0 and (not bestCount or count > bestCount) then
                best, bestCount = char, count
            end
        end
    end
    return best
end

--- DEBUG-ONLY (/altarmy debug guildshare test): inject a synthetic guildmate (a main + an
--- alt) straight into the receive/store path, so a single account can exercise the store +
--- Guild tab + search-merge without a second player online. Requires the feature flag ON
--- (that is the receive gate). Recipes are seeded from one of the player's own characters so
--- they resolve to real names in search; if none exist the guildmate simply has no recipes.
--- Returns true on success, or false + reason ("flag-off" / "unavailable" / "parse").
function Comm.InjectTestPresence()
    if not isReceiveEnabled() then
        log("test inject skipped: guildShare feature flag is OFF")
        return false, "flag-off"
    end
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then
        log("test inject skipped: guild share modules unavailable")
        return false, "unavailable"
    end

    local realm = currentRealm()
    if realm == "" then realm = "TestRealm" end
    local guild = currentGuild() or "AltArmy Test Guild"

    local sample = Comm._PickSampleProfChar(realm)
    local summaries = sample and P.BuildProfessionSummaries(sample) or {}

    local presence = {
        v = P.VERSION,
        main = "AAtestmain",
        displayName = "AA Test Main",
        chars = {
            {
                name = "AAtestmain", realm = realm, classFile = "MAGE",
                faction = "Alliance", level = (AltArmy.DataStore and AltArmy.DataStore.MAX_LEVEL) or 70,
                profs = summaries,
            },
            {
                name = "AAtestalt", realm = realm, classFile = "WARRIOR",
                faction = "Alliance", level = 42, profs = {},
            },
        },
    }

    local parsed = P.ParsePresence(presence)
    if not parsed then
        log("test inject failed: presence did not parse")
        return false, "parse"
    end
    GSD.SaveReceived("AAtestmain", parsed, guild, realm)

    if sample then
        GSD.SaveRecipes(realm, P.BuildRecipes("AAtestmain", realm, sample))
    end

    Comm.NotifyDataChanged()
    log(string.format(
        "test inject: 2 synthetic guildmate(s) stored under guild '%s' (realm %s)%s",
        guild, realm, sample and " with sampled recipes" or " (no local recipes to sample)"))
    return true
end

--- After storing a peer's presence, request recipe lists for any professions we lack.
local function requestMissingRecipes(presence, sender, realm)
    for _, c in ipairs(presence.chars or {}) do
        Comm.RequestRecipesForCharacter(c.name, realm, sender, c.guid)
    end
end

--- After storing slim presence, whisper CQ for characters still missing profession cards.
local function requestMissingCharCards(presence, sender, realm)
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.CharsNeedingProfessionCard then return end
    local needing = GSD.CharsNeedingProfessionCard(presence, realm)
    for _, entry in ipairs(needing) do
        Comm.RequestCharCard(entry.name, entry.realm or realm, sender, entry.guid)
    end
end

--- The shared character a request asks for: by ID when the request has one (the requester may
--- know it by an older name), else by name. Only characters we own and share can match.
local function findRequestedShareChar(chars, name, guid)
    for _, entry in ipairs(chars) do
        local char = entry.char
        if guid and char and char.guid then
            if char.guid == guid then return char end
        elseif entry.name == name then
            return char
        end
    end
    return nil
end
Comm._FindRequestedShareChar = findRequestedShareChar

--- Reply to a recipe request: only for characters we actually own and are sharing.
local function handleRecipeRequest(payload, sender)
    local P = AltArmy.GuildShareProtocol
    local DS = AltArmy.DataStore
    if not P or not DS or type(payload) ~= "table" then return end
    if not Comm._ShouldRespondToRecipeRequest() then return end
    local guild = currentGuild()
    local realm = payload.realm or currentRealm()
    local flagOn = isReceiveEnabled()
    local chars = Comm._SelectShareCharsInGroup(flagOn, guild, realm)
    local guid = type(payload.guid) == "string" and payload.guid ~= "" and payload.guid or nil
    local ownedAndShared = findRequestedShareChar(chars, payload.name, guid)
    if Comm.OnRequestHandled then
        pcall(Comm.OnRequestHandled, MSG_REQ_RECIPES, payload.name, guid, realm, #chars, ownedAndShared ~= nil, sender)
    end
    if not ownedAndShared then return end
    -- Echo the requested name: an older requester stores the reply under the name it asked for.
    send(MSG_RECIPES, P.BuildRecipes(payload.name, realm, ownedAndShared), "WHISPER", sender)
end

--- Reply to a char-card request: only for characters we actually own and are sharing.
local function handleCharCardRequest(payload, sender)
    local P = AltArmy.GuildShareProtocol
    if not P or not P.ParseCharCardRequest or not P.BuildCharCard then return end
    if not Comm._ShouldRespondToCharCardRequest() then return end
    local parsed = P.ParseCharCardRequest(payload)
    if not parsed then return end
    local guild = currentGuild()
    local realm = parsed.realm or currentRealm()
    local flagOn = isReceiveEnabled()
    local chars = Comm._SelectShareCharsInGroup(flagOn, guild, realm)
    local ownedAndShared = findRequestedShareChar(chars, parsed.name, parsed.guid)
    if Comm.OnRequestHandled then
        pcall(Comm.OnRequestHandled, MSG_REQ_CHAR_CARD, parsed.name, parsed.guid, realm, #chars,
            ownedAndShared ~= nil, sender)
    end
    if not ownedAndShared then return end
    send(MSG_CHAR_CARD, P.BuildCharCard(parsed.name, realm, ownedAndShared), "WHISPER", sender)
end

local function whisperPresenceReply(sender, guild, realm)
    local mine = buildMyPresence(guild, realm)
    if mine then
        send(MSG_PRESENCE_REPLY, mine, "WHISPER", sender)
    end
end

local function handlePresence(payload, sender, isReply)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then return end
    local parsed = P.ParsePresence(payload)
    if not parsed then return end
    local guild = currentGuild()
    local realm = currentRealm()
    local isLoginAnnounce = parsed.login == true
    local unchanged = GSD.PresenceMatchesStored
        and GSD.PresenceMatchesStored(sender, parsed, realm)
    if unchanged then
        -- Still refresh freshness so the Guild tab old-data warning clears, but do not
        -- re-request profession cards / recipes for content we already have.
        local touched = GSD.TouchReceivedAt and GSD.TouchReceivedAt(sender, parsed, realm)
        if touched then
            Comm.NotifyDataChanged()
        end
        -- Login announces still get a whispered PR so the newcomer receives our presence
        -- even though their data is already stored (they missed our last guild broadcast).
        if not isReply and isLoginAnnounce then
            whisperPresenceReply(sender, guild, realm)
        end
        return
    end
    GSD.SaveReceived(sender, parsed, guild, realm)
    Comm.NotifyDataChanged()
    requestMissingCharCards(parsed, sender, realm)
    requestMissingRecipes(parsed, sender, realm)
    -- Announce/reply handshake: reply to an initial broadcast (not to a reply) so we don't loop.
    if not isReply and sender ~= playerName() then
        whisperPresenceReply(sender, guild, realm)
    end
end

local function handleCharCard(payload, sender)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD or not P.ParseCharCard or not GSD.SaveCharCard then return end
    local parsed = P.ParseCharCard(payload)
    if not parsed then return end
    -- Diagnostics (GuildShareProbe): a reply to a probe is recorded and stored under its real name.
    if Comm.InterceptCharCard then
        local ok, card = pcall(Comm.InterceptCharCard, parsed, sender)
        if ok and type(card) == "table" then parsed = card end
    end
    local guild = currentGuild()
    -- Stored where the guildmate already is (the card names the character's own realm, maybe another
    -- coalesced realm's string than ours).
    local realm = GSD.StorageRealm and GSD.StorageRealm(currentRealm(), parsed.guid)
        or parsed.realm or currentRealm()
    GSD.SaveCharCard(sender, parsed, guild, realm)
    Comm.NotifyDataChanged()
    Comm.RequestRecipesForCharacter(parsed.name, realm, sender, parsed.guid)
end

local function handleRecipes(payload)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then return end
    local parsed = P.ParseRecipes(payload)
    if not parsed then return end
    local realm = GSD.StorageRealm and GSD.StorageRealm(currentRealm(), parsed.guid)
        or parsed.realm or currentRealm()
    GSD.SaveRecipes(realm, parsed)
    Comm.NotifyDataChanged()
end

--- Raw AceComm receive callback. All work is wrapped in pcall so a malformed message
--- can never surface an error. Inbound is ignored when the flag is off, except RQ/CQ
--- which send-only clients still answer with RC/CC.
function Comm._DispatchReceivedMessage(msgType, payload, rawSender)
    local sender = normalizeSender(rawSender)
    if isLocalMessage(payload, sender) then return end
    Comm._NotePeerCapabilities(payload, sender)
    log(string.format("RECV %s from %s", formatMsgType(msgType),
        tostring(rawSender ~= sender and rawSender or sender)))
    if msgType == MSG_PRESENCE then
        handlePresence(payload, sender, false)
    elseif msgType == MSG_PRESENCE_REPLY then
        handlePresence(payload, sender, true)
    elseif msgType == MSG_REQ_RECIPES then
        handleRecipeRequest(payload, sender)
    elseif msgType == MSG_RECIPES then
        handleRecipes(payload)
    elseif msgType == MSG_REQ_CHAR_CARD then
        handleCharCardRequest(payload, sender)
    elseif msgType == MSG_CHAR_CARD then
        handleCharCard(payload, sender)
    end
end

local function onCommReceived(prefix, message, distribution, rawSender)
    if not commObj then return end
    pcall(function()
        local ok, msgType, payload = commObj:Deserialize(message)
        if not ok or type(msgType) ~= "string" then
            log(Comm._FormatUndecodableRecvLog(prefix, message, distribution, rawSender, ok, msgType))
            saveUndecodableDump(prefix, message, distribution, rawSender, ok, msgType)
            Comm.RetryAfterLoss(rawSender)
            return
        end
        -- Diagnostics (GuildShareProbe): who sent what, with the sender's realm suffix intact.
        if Comm.OnRawReceive then
            pcall(Comm.OnRawReceive, msgType, payload, rawSender, distribution)
        end
        if not isInboundAllowed(msgType) then return end
        Comm._DispatchReceivedMessage(msgType, payload, rawSender)
    end)
end

-- *** Receiving multipart messages in any order (GuildShareReassembly) ***

local receiver

--- Whether an AceSerializer text decodes to one of our messages (the reassembler's check of an arrangement).
local function decodes(text)
    if not commObj then return false end
    local ok, msgType = commObj:Deserialize(text)
    return ok == true and type(msgType) == "string"
end

--- Parts that solved nothing in time: logged, and saved like an undecodable message (in arrival order).
local function dropUnsolvedParts(parts, distribution, sender)
    local kinds, texts = {}, {}
    for i, p in ipairs(parts) do
        kinds[i] = p.kind
        texts[i] = p.text
    end
    local reason = "unsolved multipart parts: " .. table.concat(kinds, ",")
    log(string.format("dropped %d unsolved part(s) from %s (%s)", #parts, tostring(sender), reason))
    saveUndecodableDump(PREFIX, table.concat(texts), distribution, sender, false, reason)
    Comm.RetryAfterLoss(sender)
end

--- Receive the prefix ourselves instead of through AceComm's in-order reassembly. Returns false when the
--- client lacks what it needs (the caller then registers with AceComm as before).
function Comm._StartReceiver()
    local R = AltArmy.GuildShareReassembly
    if receiver or not (R and R.New and CreateFrame) then return receiver ~= nil end
    local chatInfo = _G.C_ChatInfo
    if chatInfo and chatInfo.RegisterAddonMessagePrefix then
        chatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif _G.RegisterAddonMessagePrefix then
        _G.RegisterAddonMessagePrefix(PREFIX)
    else
        return false
    end
    local ctimer = _G.C_Timer
    receiver = R.New({
        validate = decodes,
        deliver = function(text, distribution, sender)
            onCommReceived(PREFIX, text, distribution, sender)
        end,
        drop = function(parts, distribution, sender)
            pcall(dropUnsolvedParts, parts, distribution, sender)
        end,
        after = ctimer and ctimer.After and function(sec, fn) ctimer.After(sec, fn) end or nil,
    })
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, message, distribution, sender)
        -- Values the client hides (encounter chat lockdown) can't be read; drop them, as AceComm's patch does.
        if not (canAccessSecretValue(prefix) and canAccessSecretValue(message)
            and canAccessSecretValue(distribution) and canAccessSecretValue(sender)) then
            return
        end
        if prefix ~= PREFIX then return end
        if _G.Ambiguate and type(sender) == "string" then sender = _G.Ambiguate(sender, "none") end
        pcall(receiver.OnPart, receiver, message, distribution, sender)
    end)
    return true
end

-- *** Initialization ***

function Comm.Init()
    if initialized then return end
    if not LibStub then return end
    local AceComm = LibStub:GetLibrary("AceComm-3.0", true)
    local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0", true)
    if not AceComm or not AceSerializer then return end
    commObj = {}
    AceComm:Embed(commObj)
    AceSerializer:Embed(commObj)
    if not Comm._StartReceiver() then
        commObj:RegisterComm(PREFIX, onCommReceived)
    end
    initialized = true
    scheduleSweeps()
    -- Prune very old received data (harmless when the flag is off / no data present).
    Comm.PurgeStaleReceived()
    -- Drop the player's own characters that older clients stored as guildmates.
    local GSD = AltArmy.GuildShareData
    if GSD and GSD.PurgeOwnCharacters then
        pcall(GSD.PurgeOwnCharacters)
    end
    -- Merge guildmates older versions split across coalesced realms' tables (card under theirs, presence ours).
    if GSD and GSD.MergeCoalescedRealms then
        pcall(GSD.MergeCoalescedRealms, currentRealm())
    end
    -- Drop professions stored from the server's empty answer for a profession the player hasn't got.
    if GSD and GSD.PurgeEmptyLinkReads then
        pcall(GSD.PurgeEmptyLinkReads)
    end
end

--- Remove received guild share entries older than STALE_MAX_AGE when auto-delete is on.
function Comm.PurgeStaleReceived()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.IsAutoDeleteOldDataEnabled and not GSS.IsAutoDeleteOldDataEnabled() then
        return
    end
    local GSD = AltArmy.GuildShareData
    if not (GSD and GSD.PurgeStale) then return end
    local maxAge = (GSS and GSS.AUTO_DELETE_MAX_AGE_SEC) or STALE_MAX_AGE
    pcall(function() GSD.PurgeStale(maxAge) end)
end

-- *** Events ***

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            Comm.Init()
            knownGuild = currentGuild()
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isInitialLogin, isReloadingUi = ...
            Comm.Init()
            knownGuild = currentGuild()
            if Comm._ShouldBroadcastOnEnteringWorld(isInitialLogin, isReloadingUi) then
                Comm.RequestGuildRoster()
                -- Broadcast no-ops until GetGuildInfo is ready; PLAYER_GUILD_UPDATE
                -- then login-announces when the name becomes available.
                Comm.Broadcast(true, true)
            end
        elseif event == "PLAYER_GUILD_UPDATE" then
            handlePlayerGuildUpdate()
        end
    end)
end
