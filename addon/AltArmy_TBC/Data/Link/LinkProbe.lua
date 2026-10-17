-- AltArmy TBC — Battle.net probe for linked accounts.
-- Manual diagnostic only: /altarmy debug bnprobe [burst], with Alt Army running on two of your WoW
-- accounts at once (same Battle.net login). Answers whether Battle.net game data reaches your other
-- accounts on this client before the linked-accounts protocol is built on it:
--   - which of your game accounts the client lists, and why each is or isn't another of yours (LinkDiscovery)
--   - whether a PING reaches each and a PONG comes back (and how long that takes)
--   - with `burst`, how 40 messages of 250 bytes arrive: lost, out of order, bytes per second
--   - what BN_CHAT_MSG_ADDON hands an addon: argument types, and whether any is a secret value
-- Every client running Alt Army listens (answering only its own Battle.net account's game accounts), so
-- run the command on one; both record. The result goes to AltArmyTBC_Options.debug.bnProbe (read it from
-- the SavedVariables .lua file after /reload, or `npm run dump:sync`); chat gets one-line statuses.

AltArmy = AltArmy or {}
AltArmy.LinkProbe = AltArmy.LinkProbe or {}
local P = AltArmy.LinkProbe

P.VERSION = 1
P.PREFIX = "AltArmyLk"
P.BURST_COUNT = 40
P.BURST_BYTES = 250 -- under the 255 a game data message may carry
P.BURST_IDLE = 5 -- seconds without a burst message before the receiver reports
P.RESCAN_WAIT = 60 -- seconds to wait for Battle.net to fill in when nothing was found
P.MAX_LOG = 120 -- received messages kept

local result -- this session's record, saved as it grows
local bursts = {} -- runId -> what the receiver has seen
local pings = {} -- runId .. ":" .. gameAccountID -> sent at (ms)
local runCounter = 0
local api -- LinkDiscovery's view of the client (P._SetApi in specs)

local function LD()
    return AltArmy.LinkDiscovery
end

local function clientApi()
    if api then
        return api
    end
    return LD().LiveApi()
end

local function nowMs()
    if GetTimePreciseSec then --luacheck: ignore 113
        return math.floor(GetTimePreciseSec() * 1000) --luacheck: ignore 113
    end
    if debugprofilestop then --luacheck: ignore 113
        return math.floor(debugprofilestop()) --luacheck: ignore 113
    end
    return math.floor((os and os.clock and os.clock() or 0) * 1000)
end

local function notify(msg)
    local D = AltArmy.Debug
    if D and D.NotifyChat then
        D.NotifyChat("|cff00ccff[Alt Army:BNProbe]|r " .. msg)
    end
end

local function after(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    end
end

local function record()
    if not result then
        result = { version = P.VERSION, log = {}, sends = {}, pongs = {}, bursts = {}, reports = {} }
        result.interface = GetBuildInfo and select(4, GetBuildInfo()) or nil --luacheck: ignore 113
        result.wowProjectID = WOW_PROJECT_ID --luacheck: ignore 113
        result.realm = GetRealmName and GetRealmName() or nil --luacheck: ignore 113
        result.faction = UnitFactionGroup and UnitFactionGroup("player") or nil --luacheck: ignore 113
        result.player = UnitName and UnitName("player") or nil --luacheck: ignore 113
    end
    local D = AltArmy.Debug
    if D and D.Ensure and AltArmyTBC_Options then --luacheck: ignore 113
        D.Ensure()
        AltArmyTBC_Options.debug.bnProbe = result --luacheck: ignore 113
    end
    return result
end

--- A table the client can save: functions and other odd values become their type's name.
local function plain(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" or t == "nil" then
        return v
    end
    if t ~= "table" or (depth or 0) >= 3 then
        return "<" .. t .. ">"
    end
    local out = {}
    for k, val in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            out[k] = plain(val, (depth or 0) + 1)
        end
    end
    return out
end

local function isSecret(v)
    if issecretvalue then --luacheck: ignore 113
        local ok, secret = pcall(issecretvalue, v) --luacheck: ignore 113
        return ok and secret or false
    end
    return nil -- the client has no secret values
end

--- Send one game data message; returns what the send said. `send` is P._send in specs.
function P.Send(gameAccountID, text, prio)
    if P._send then
        return P._send(gameAccountID, text)
    end
    local CTL = ChatThrottleLib --luacheck: ignore 113
    if CTL and CTL.BNSendGameData then
        return pcall(CTL.BNSendGameData, CTL, prio or "NORMAL", P.PREFIX, text, "WHISPER", gameAccountID)
    end
    local bn = C_BattleNet --luacheck: ignore 113
    if bn and bn.SendGameData then
        return pcall(bn.SendGameData, gameAccountID, P.PREFIX, text)
    end
    return false, "no SendGameData"
end

local function nextRun()
    runCounter = runCounter + 1
    return tostring(nowMs() % 100000) .. "-" .. runCounter
end

--- Whether `senderID` is another of this player's game accounts (only those are answered).
local function fromMine(senderID)
    local a = clientApi()
    local me = LD().Me(a)
    local info = LD().Info(a, senderID)
    return LD().IsCandidate(info, me)
end

local function burstReport(runId)
    local b = bursts[runId]
    if not b or b.reported then
        return nil
    end
    b.reported = true
    local elapsed = math.max(1, b.lastAt - b.firstAt)
    local report = {
        run = runId,
        got = b.count,
        of = b.total,
        dupes = b.dupes,
        outOfOrder = b.outOfOrder,
        ms = elapsed,
        bytesPerSec = math.floor(b.bytes * 1000 / elapsed),
    }
    record().bursts[runId] = report
    return report
end

local function sendReport(runId, senderID)
    local r = burstReport(runId)
    if not r then
        return
    end
    P.Send(senderID, table.concat({ "BR", runId, r.got, r.of, r.dupes, r.outOfOrder, r.ms }, "|"))
    notify(string.format("Burst %s: %d/%d arrived, %d out of order, %d B/s.", runId, r.got, r.of, r.outOfOrder,
        r.bytesPerSec))
end

local function onBurst(runId, seq, total, text, senderID)
    local b = bursts[runId]
    if not b then
        b = { count = 0, total = total, dupes = 0, outOfOrder = 0, maxSeq = 0, seen = {}, bytes = 0,
            firstAt = nowMs(), sender = senderID }
        bursts[runId] = b
    end
    b.lastAt = nowMs()
    if b.seen[seq] then
        b.dupes = b.dupes + 1
        return
    end
    b.seen[seq] = true
    b.count = b.count + 1
    b.bytes = b.bytes + #text
    if seq < b.maxSeq then
        b.outOfOrder = b.outOfOrder + 1
    else
        b.maxSeq = seq
    end
    if b.count >= total then
        sendReport(runId, senderID)
        return
    end
    local at = b.lastAt
    after(P.BURST_IDLE, function()
        if bursts[runId] and bursts[runId].lastAt == at then
            sendReport(runId, senderID)
        end
    end)
end

local function split(text)
    local out = {}
    for part in (text .. "|"):gmatch("([^|]*)|") do
        out[#out + 1] = part
    end
    return out
end

--- BN_CHAT_MSG_ADDON for our prefix: records what arrived, answers PING and bursts from your accounts.
function P.OnMessage(prefix, text, channel, senderID)
    if prefix ~= P.PREFIX then
        return
    end
    local res = record()
    local entry = {
        at = nowMs(),
        types = { type(prefix), type(text), type(channel), type(senderID) },
        secret = { isSecret(prefix), isSecret(text), isSecret(channel), isSecret(senderID) },
        channel = type(channel) == "string" and channel or nil,
        sender = type(senderID) == "number" and senderID or nil,
        head = type(text) == "string" and text:sub(1, 40) or nil,
        bytes = type(text) == "string" and #text or nil,
    }
    if #res.log < P.MAX_LOG then
        res.log[#res.log + 1] = entry
    end
    if type(text) ~= "string" or type(senderID) ~= "number" then
        entry.dropped = "unreadable"
        return
    end
    local mine, why = fromMine(senderID)
    entry.mine, entry.why = mine, why
    if not mine then
        entry.dropped = "notMine"
        return
    end
    local f = split(text)
    if f[1] == "PING" then
        P.Send(senderID, "PONG|" .. (f[2] or "") .. "|" .. (f[3] or ""))
    elseif f[1] == "PONG" then
        local key = (f[2] or "") .. ":" .. senderID
        local sentAt = pings[key]
        res.pongs[#res.pongs + 1] = { sender = senderID, run = f[2], ms = sentAt and (nowMs() - sentAt) or nil }
        notify(string.format("PONG from game account %d%s.", senderID,
            sentAt and string.format(" in %d ms", nowMs() - sentAt) or ""))
    elseif f[1] == "B" then
        onBurst(f[2] or "", tonumber(f[3]) or 0, tonumber(f[4]) or 0, text, senderID)
    elseif f[1] == "BR" then
        res.reports[#res.reports + 1] = {
            sender = senderID, run = f[2], got = tonumber(f[3]), of = tonumber(f[4]), dupes = tonumber(f[5]),
            outOfOrder = tonumber(f[6]), ms = tonumber(f[7]),
        }
        notify(string.format("Game account %d got %s/%s of burst %s in %s ms (%s out of order).", senderID,
            tostring(f[3]), tostring(f[4]), tostring(f[2]), tostring(f[7]), tostring(f[6])))
    end
end

local function burstMessage(runId, seq, total)
    local head = table.concat({ "B", runId, seq, total, "" }, "|")
    return head .. string.rep("x", P.BURST_BYTES - #head)
end

local function probe(burst, rescanned)
    local a = clientApi()
    local res = record()
    local me = LD().Me(a)
    local scan = LD().Scan(a, me)
    res.me = plain(me)
    res.accounts = plain(scan)
    res.burst = burst or nil
    local candidates = LD().Candidates(scan)
    if #candidates == 0 then
        if not rescanned then
            notify("No other account of yours found yet; looking again as Battle.net fills in.")
            P._waitForBattleNet(burst)
        else
            notify(string.format("No other account of yours found (%d game accounts listed). Saved to "
                .. "AltArmyTBC_Options.debug.bnProbe.", #scan))
        end
        return res
    end
    for _, c in ipairs(candidates) do
        local runId = nextRun()
        pings[runId .. ":" .. c.gameAccountID] = nowMs()
        local ok, err = P.Send(c.gameAccountID, "PING|" .. runId .. "|" .. nowMs())
        res.sends[#res.sends + 1] = { to = c.gameAccountID, kind = "PING", ok = ok and true or false,
            err = err ~= nil and tostring(err) or nil }
        if burst then
            local burstId = nextRun()
            for seq = 1, P.BURST_COUNT do
                P.Send(c.gameAccountID, burstMessage(burstId, seq, P.BURST_COUNT), "BULK")
            end
            res.sends[#res.sends + 1] = { to = c.gameAccountID, kind = "BURST", run = burstId }
        end
        notify(string.format("Sent PING%s to game account %d (%s, %s).", burst and " and a burst" or "",
            c.gameAccountID, tostring(c.characterName), tostring(c.realmName)))
    end
    return res
end

local waitFrame
function P._waitForBattleNet(burst)
    if not CreateFrame then --luacheck: ignore 113
        return
    end
    waitFrame = waitFrame or CreateFrame("Frame") --luacheck: ignore 113
    local done = false
    local function again()
        if done then
            return
        end
        done = true
        waitFrame:UnregisterAllEvents()
        probe(burst, true)
    end
    waitFrame:RegisterEvent("BN_INFO_CHANGED")
    waitFrame:RegisterEvent("FRIENDLIST_UPDATE")
    waitFrame:SetScript("OnEvent", again)
    after(P.RESCAN_WAIT, again)
end

--- /altarmy debug bnprobe [burst]
function P.Start(burst)
    if not (C_BattleNet or BNGetInfo or P._send) then --luacheck: ignore 113
        notify("This client has no Battle.net API for addons.")
        return nil
    end
    return probe(burst)
end

-- Listen from login on every client, so the other account answers without running anything.
local function register()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then --luacheck: ignore 113
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, P.PREFIX) --luacheck: ignore 113
    end
end

if CreateFrame then --luacheck: ignore 113
    local frame = CreateFrame("Frame") --luacheck: ignore 113
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("BN_CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            register()
        elseif event == "BN_CHAT_MSG_ADDON" then
            P.OnMessage(...)
        end
    end)
end

-- Specs.
function P._SetApi(a)
    api = a
end

function P._Reset()
    result, bursts, pings, runCounter = nil, {}, {}, 0
end

function P._Result()
    return result
end

function P._FlushBurst(runId, senderID)
    sendReport(runId, senderID)
end

return P
