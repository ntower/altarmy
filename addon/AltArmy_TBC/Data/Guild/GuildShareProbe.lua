-- AltArmy TBC — Guild data sharing: diagnostics for guildmates whose profession card never arrives.
-- luacheck: globals C_Timer
--
-- `/altarmy debug guildshare probe <name>` whispers the stored guildmate's sender four profession-card
-- requests (CQ), one per combination of
--   target: the short name the addon whispers today ("First Surname"), or the full "First Surname-Realm"
--   realm:  ours (what the addon sends today), or the sender's own realm
-- Each request's name carries a tag (TAG .. variant) that the responder echoes back in its card, so a reply
-- says which combination got through. Responders on any version that shares GUIDs match the request by GUID,
-- so the tag never stops them answering, and they look their characters up by the realm the request names.
-- Reading the results:
--   only "their realm" variants answer -> whispers arrive; the realm the request names is the gap
--   nothing answers, "player not found" -> the whisper target is the gap
--   nothing answers, no system message  -> whispers to other servers are dropped silently (or they're offline)
--   every variant answers               -> no gap here; look elsewhere
-- Multipart messages: AceComm splits a message over 255 bytes into parts (first, next..., last) and glues
-- whatever arrives between a first and a last, so a part lost or arriving late yields an undecodable message.
-- Every raw guild-share part is recorded (Probe.PartsFrom), with the stream anomalies that tell which:
--   "orphan" a next or last with no first open (it came after its last: out of order, or its first was lost)
--   "restart" a first while another was open (the open message's last was lost)
-- and an undecodable message's dump carries its sender's recent parts.
-- Also recorded from the moment the addon loads: every guild-share message's raw sender (realm suffix intact)
-- and the realm each presence character reports. Results go to chat and to the dev dump "guildShareProbe"
-- (needs /altarmy debug on). Diagnostics only: nothing here changes what is stored, beyond storing a probe's
-- reply under the character's real name.

if not AltArmy then return end

AltArmy.GuildShareProbe = AltArmy.GuildShareProbe or {}
local Probe = AltArmy.GuildShareProbe

Probe.WINDOW_SEC = 30
Probe.TAG = "#aaprobe:"
Probe.MAX_SYSTEM = 20
Probe.MAX_SENDERS = 60

local senders = {}      -- [short sender] = { raw, distribution, msgType, at, count }
local guidRealms = {}   -- [character GUID] = realm the sender's presence reports for it
local parts = {}        -- raw guild-share addon messages received (newest last)
local openStreams = {}  -- [distribution .. "\t" .. sender] = true while a multipart message is open
local anomalies = {}
Probe.MAX_PARTS = 300
Probe.LATE_PARTS_SEC = 8     -- an undecodable message's parts are read again this long after
Probe.CARD_SPACING_SEC = 4   -- between the cards test's requests
Probe.MAX_CARD_REPEATS = 10
Probe.MAX_ANOMALIES = 50
Probe.PREFIX = "AltArmyGS"
local PART_KINDS = { ["\001"] = "first", ["\002"] = "next", ["\003"] = "last", ["\004"] = "escaped",
    ["\005"] = "numbered" }
local handled = {}      -- requests this client got and whether it answered (newest last)
Probe.MAX_HANDLED = 40
local pending           -- the probe running: { variants = { [label] = variant }, system = {}, ... }

local function now() return (time and time()) or 0 end

local function chat(msg)
    local D = AltArmy.Debug
    if D and D.NotifyChat then D.NotifyChat("|cff00ccff[Alt Army:Probe]|r " .. tostring(msg)) end
end

local function accessible(v)
    if v == nil then return false end
    if _G.canaccessvalue then return _G.canaccessvalue(v) end
    return true
end

local function shortName(name)
    if type(name) ~= "string" then return nil end
    return name:match("^[^%-]+") or name
end

--- The realm suffix of a "Name-Realm" sender, or nil.
function Probe.SuffixOf(name)
    if type(name) ~= "string" then return nil end
    return name:match("^[^%-]+%-(.+)$")
end

--- A Forever realm from its whisper suffix ("CAMWOWUS1Realm5PvE" -> "CAMWOW US1 Realm 5 PvE"), or nil.
function Probe.RealmFromSuffix(suffix)
    if type(suffix) ~= "string" then return nil end
    local cluster, shard, n, ruleset = suffix:match("^(%u+)(%u%u%d+)Realm(%d+)(.+)$")
    if not cluster then return nil end
    return string.format("%s %s Realm %s %s", cluster, shard, n, ruleset)
end

--- A whisper suffix from a realm ("CAMWOW US1 Realm 5 PvE" -> "CAMWOWUS1Realm5PvE").
function Probe.SuffixFromRealm(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    return (realm:gsub("[%s%-]", ""))
end

function Probe.TagName(name, label) return name .. Probe.TAG .. label end

--- The real name and variant label of a tagged name, or the name alone.
function Probe.UntagName(name)
    if type(name) ~= "string" then return name, nil end
    local i = name:find(Probe.TAG, 1, true)
    if not i then return name, nil end
    return name:sub(1, i - 1), name:sub(i + #Probe.TAG)
end

--- The realms to try for a sender whose own realm is unknown: those presences reported this session and the
--- player's own, then every shard 1-3 and realm 1-MAX_GUESS_REALM of the player's region and ruleset.
Probe.MAX_GUESS_REALM = 8
function Probe.RealmCandidates(myRealm, theirRealm, seenRealms)
    if theirRealm then return { theirRealm } end
    local out, seen = {}, { [myRealm or ""] = true }
    local function add(r)
        if type(r) == "string" and r ~= "" and not seen[r] then
            seen[r] = true
            out[#out + 1] = r
        end
    end
    local sorted = {}
    for _, r in pairs(seenRealms or {}) do sorted[#sorted + 1] = r end
    table.sort(sorted)
    for _, r in ipairs(sorted) do add(r) end
    local cluster, region, ruleset = (myRealm or ""):match("^(%S+) (%a+)%d+ Realm %d+ (.+)$")
    if cluster then
        for shard = 1, 3 do
            for n = 1, Probe.MAX_GUESS_REALM do
                add(string.format("%s %s%d Realm %d %s", cluster, region, shard, n, ruleset))
            end
        end
    end
    return out
end

--- The requests to send: { label, target, realm }, skipping a combination that repeats another one.
--- `theirRealms` is a list (one entry when the sender's realm is known).
function Probe.Variants(shortTarget, fullTarget, myRealm, theirRealms)
    local out, seen = {}, {}
    local targets = { { "short", shortTarget }, { "full", fullTarget } }
    local realms = { { "myRealm", myRealm } }
    for _, r in ipairs(theirRealms or {}) do realms[#realms + 1] = { "realm=" .. r, r } end
    for _, t in ipairs(targets) do
        for _, r in ipairs(realms) do
            if t[2] and r[2] then
                local key = t[2] .. "\0" .. r[2]
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { label = t[1] .. "/" .. r[1], target = t[2], realm = r[2] }
                end
            end
        end
    end
    return out
end

-- *** Recording ***

local function clock()
    return (GetTime and GetTime()) or now()
end

--- The kind of a raw AceComm part: "first", "next", "last", "escaped" or "single".
function Probe.PartKind(message)
    if type(message) ~= "string" then return "single" end
    return PART_KINDS[message:sub(1, 1)] or "single"
end

--- Record one raw addon message of ours, and any stream anomaly it shows.
function Probe.OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= Probe.PREFIX then return end
    if not (accessible(message) and accessible(sender) and accessible(distribution)) then return end
    if type(message) ~= "string" or type(sender) ~= "string" then return end
    local kind = Probe.PartKind(message)
    local stream = tostring(distribution) .. "\t" .. sender
    local anomaly
    if kind == "first" then
        if openStreams[stream] then anomaly = "restart" end
        openStreams[stream] = true
    elseif kind == "next" or kind == "last" then
        if not openStreams[stream] then anomaly = "orphan" end
        if kind == "last" then openStreams[stream] = nil end
    end
    local body = kind == "single" and message or message:sub(2)
    local rec = { at = clock(), sender = sender, distribution = distribution, kind = kind, bytes = #message,
        head = (body:sub(1, 24):gsub("[%c]", ".")), tail = (body:sub(-16):gsub("[%c]", ".")), anomaly = anomaly }
    parts[#parts + 1] = rec
    while #parts > Probe.MAX_PARTS do table.remove(parts, 1) end
    if anomaly then
        anomalies[#anomalies + 1] = rec
        while #anomalies > Probe.MAX_ANOMALIES do table.remove(anomalies, 1) end
        local D = AltArmy.Debug
        if D and D.LogGuildShare then
            D.LogGuildShare(string.format("multipart %s from %s (%s, %d bytes)", anomaly, sender, kind, #message))
        end
        -- Kept for /reload while debug is on (the table itself, so later anomalies land too).
        if D and D.IsEnabled and D.IsEnabled() and D.Ensure and _G.AltArmyTBC_Options then
            D.Ensure()
            _G.AltArmyTBC_Options.debug.guildShareMultipartAnomalies = anomalies
        end
    end
end

--- The last `n` (default 30) parts received from `sender` (as AceComm names it), oldest first.
function Probe.PartsFrom(sender, n)
    n = n or 30
    local out = {}
    for i = #parts, 1, -1 do
        if parts[i].sender == sender then
            table.insert(out, 1, parts[i])
            if #out >= n then break end
        end
    end
    return out
end

function Probe.Anomalies() return anomalies end

-- *** Recording (hooked into GuildShareComm's receive path) ***

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Probe.OnRawReceive(msgType, payload, rawSender, distribution)
    if type(rawSender) ~= "string" or not accessible(rawSender) then return end
    local short = shortName(rawSender)
    local rec = senders[short]
    if not rec and countKeys(senders) >= Probe.MAX_SENDERS then return end
    rec = rec or { count = 0 }
    rec.raw, rec.distribution, rec.msgType, rec.at = rawSender, distribution, msgType, now()
    rec.count = rec.count + 1
    senders[short] = rec
    if (msgType == "P" or msgType == "PR") and type(payload) == "table" and type(payload.chars) == "table" then
        for _, c in ipairs(payload.chars) do
            if type(c) == "table" and type(c.guid) == "string" and type(c.realm) == "string" then
                guidRealms[c.guid] = c.realm
            end
        end
    end
end

--- A recipe or card request this client got: whether one of its shared characters matched.
function Probe.OnRequestHandled(msgType, name, guid, realm, sharedOnRealm, answered, sender)
    if #handled >= Probe.MAX_HANDLED then table.remove(handled, 1) end
    handled[#handled + 1] = { at = now(), msgType = msgType, from = sender, name = name, guid = guid,
        realm = realm, sharedOnRealm = sharedOnRealm, answered = answered }
end

--- A card answering a probe: record which variant it answered, and hand it on under its real name.
function Probe.InterceptCharCard(card, sender)
    local name, label = Probe.UntagName(card.name)
    if not label then return card end
    card.name = name
    if pending and pending.variants[label] then
        local v = pending.variants[label]
        v.answered = true
        v.answeredAfter = now() - pending.startedAt
        v.replyFrom = sender
        v.replyRealm = card.realm
        v.replyProfs = #(card.profs or {})
        chat(string.format("reply to %s (%s): %d profession(s)", label, tostring(sender), v.replyProfs))
    end
    return card
end

-- *** Probe ***

local function findStored(query)
    local GSD = AltArmy.GuildShareData
    local d = GSD and GSD._Ensure and GSD._Ensure()
    if not d then return nil end
    query = query:lower()
    local exact, partial
    for realm, rt in pairs(d.chars) do
        for key, entry in pairs(rt) do
            local name = type(entry) == "table" and entry.name
            if type(name) == "string" then
                local lower = name:lower()
                if lower == query or lower:match("^(%S+)") == query then
                    exact = exact or { realm = realm, key = key, entry = entry }
                elseif lower:find(query, 1, true) then
                    partial = partial or { realm = realm, key = key, entry = entry }
                end
            end
        end
    end
    return exact or partial
end

local function rosterRowFor(short)
    local Comm = AltArmy.GuildShareComm
    if not (Comm and Comm.GuildRosterRows) then return nil, nil end
    local rows, source = Comm.GuildRosterRows()
    for _, row in ipairs(rows or {}) do
        if type(row.name) == "string" and shortName(row.name) == short then return row, source end
    end
    return nil, source
end

local function onSystemMessage(text)
    if not pending or type(text) ~= "string" or not accessible(text) then return end
    if #pending.system < Probe.MAX_SYSTEM then
        pending.system[#pending.system + 1] = { after = now() - pending.startedAt, text = text }
    end
end

local function finish()
    local p = pending
    pending = nil
    if not p then return end
    local list = {}
    local answered = 0
    for _, v in ipairs(p.order) do
        list[#list + 1] = v
        if v.answered then
            answered = answered + 1
            chat(string.format("ANSWERED: %s -> %s [realm %s] after %ss", v.label, v.target, v.realm,
                tostring(v.answeredAfter)))
        end
    end
    chat(string.format("%d of %d request(s) answered.", answered, #p.order))
    local partsSeen
    if p.partsSince then
        partsSeen = {}
        local counts = { first = 0, next = 0, last = 0, single = 0, escaped = 0, anomalies = 0 }
        for _, rec in ipairs(parts) do
            if rec.sender == p.sender and rec.at >= p.partsSince then
                partsSeen[#partsSeen + 1] = rec
                counts[rec.kind] = (counts[rec.kind] or 0) + 1
                if rec.anomaly then counts.anomalies = counts.anomalies + 1 end
            end
        end
        chat(string.format("parts from %s: %d first, %d next, %d last, %d single; %d anomalies", p.sender,
            counts.first, counts.next, counts.last, counts.single, counts.anomalies))
    end
    local refused = 0
    for _, h in ipairs(handled) do
        if not h.answered then refused = refused + 1 end
    end
    chat(string.format("This client got %d request(s) this session and left %d unanswered.", #handled, refused))
    for _, s in ipairs(p.system) do
        chat("system message: " .. s.text)
    end
    local dump = {
        when = _G.date and _G.date() or nil,
        query = p.query,
        character = p.character,
        sender = p.sender,
        senderOnline = p.senderOnline,
        rosterSource = p.rosterSource,
        rosterName = p.rosterName,
        rawSenderSeen = p.rawSenderSeen,
        myRealm = p.myRealm,
        theirRealm = p.theirRealm,
        theirRealmFrom = p.theirRealmFrom,
        realmsTried = p.realmsTried,
        myGuid = p.myGuid,
        variants = list,
        systemMessages = p.system,
        sendersThisSession = senders,
        presenceRealmsThisSession = guidRealms,
        requestsThisClientGot = handled,
        multipartAnomalies = anomalies,
        mode = p.mode,
        partsFromSender = partsSeen,
    }
    local D = AltArmy.Debug
    if D and D.Dump then D.Dump("guildShareProbe", dump) end
    if not (D and D.IsEnabled and D.IsEnabled()) then
        chat("Turn on /altarmy debug on and probe again to save these results for /reload.")
    end
end

--- Probe a stored guildmate by name (full, first name or a part of it). Returns true when requests went out.
function Probe.Run(query)
    local Comm = AltArmy.GuildShareComm
    local P = AltArmy.GuildShareProtocol
    if not (Comm and Comm._Send and P and P.BuildCharCardRequest) then
        chat("Guild sharing is unavailable.")
        return false
    end
    if pending then
        chat("A probe is still running; wait for its results.")
        return false
    end
    if type(query) ~= "string" or query == "" then
        chat("Usage: /altarmy debug guildshare probe <guildmate name>")
        return false
    end
    local hit = findStored(query)
    if not hit then
        chat("No stored guildmate matches '" .. query .. "'. The probe needs their presence (they log in while"
            .. " you're online).")
        return false
    end
    local entry = hit.entry
    local sender = entry.source
    if type(sender) ~= "string" or sender == "" then
        chat(tostring(entry.name) .. " has no sender to whisper (read by link only?).")
        return false
    end
    local GSS = AltArmy.GuildShareSettings
    local myRealm = (GSS and GSS._CurrentRealm and GSS._CurrentRealm()) or (GetRealmName and GetRealmName()) or ""
    local row, rosterSource = rosterRowFor(sender)
    local seen = senders[sender]
    local suffix = Probe.SuffixOf(seen and seen.raw) or Probe.SuffixOf(row and row.name)

    local theirRealm, theirRealmFrom = guidRealms[entry.guid] or guidRealms[entry.sourceGuid], "presence"
    if not theirRealm then
        theirRealm, theirRealmFrom = Probe.RealmFromSuffix(suffix), "suffix"
    end
    if not theirRealm then theirRealmFrom = nil end

    local fullTarget = (seen and Probe.SuffixOf(seen.raw) and seen.raw)
        or (row and Probe.SuffixOf(row.name) and row.name)
        or (theirRealm and (sender .. "-" .. Probe.SuffixFromRealm(theirRealm)))

    pending = {
        query = query,
        character = { name = entry.name, guid = entry.guid, storedRealm = hit.realm,
            needsProfessionCard = entry.needsProfessionCard },
        sender = sender,
        senderOnline = Comm.IsGuildMemberOnline and Comm.IsGuildMemberOnline(sender) or nil,
        rosterSource = rosterSource,
        rosterName = row and row.name or nil,
        rawSenderSeen = seen and seen.raw or nil,
        myRealm = myRealm,
        theirRealm = theirRealm,
        theirRealmFrom = theirRealmFrom,
        myGuid = UnitGUID and UnitGUID("player") or nil,
        startedAt = now(),
        variants = {},
        order = {},
        system = {},
    }
    chat(string.format("probing %s via %s (online %s); their realm %s (from %s), full target %s",
        tostring(entry.name), sender, tostring(pending.senderOnline), tostring(theirRealm),
        tostring(theirRealmFrom), tostring(fullTarget)))

    local candidates = Probe.RealmCandidates(myRealm, theirRealm, guidRealms)
    pending.realmsTried = candidates
    for _, v in ipairs(Probe.Variants(sender, fullTarget, myRealm, candidates)) do
        pending.variants[v.label] = v
        pending.order[#pending.order + 1] = v
        local request = P.BuildCharCardRequest(Probe.TagName(entry.name, v.label), v.realm, entry.guid)
        Comm._Send("CQ", request, "WHISPER", v.target, function(sent, sendResult)
            v.sent = sent
            v.sendResult = sendResult
        end)
    end

    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(Probe.WINDOW_SEC, finish)
        chat(string.format("results in %ds.", Probe.WINDOW_SEC))
    else
        finish()
    end
    return true
end

--- The cards test: ask a guildmate's sender for one character's profession card `n` times, CARD_SPACING_SEC
--- apart, naming the character's own realm, and record every part that comes back: whether a reply's middle
--- part goes missing, arrives late, or the reply is whole. Returns true when the requests were scheduled.
function Probe.RunCards(query, n)
    local Comm = AltArmy.GuildShareComm
    local P = AltArmy.GuildShareProtocol
    if not (Comm and Comm._Send and P and P.BuildCharCardRequest) then
        chat("Guild sharing is unavailable.")
        return false
    end
    if pending then
        chat("A probe is still running; wait for its results.")
        return false
    end
    n = math.max(1, math.min(tonumber(n) or 5, Probe.MAX_CARD_REPEATS))
    local hit = type(query) == "string" and query ~= "" and findStored(query) or nil
    if not hit then
        chat("Usage: /altarmy debug guildshare cards <stored guildmate name> [times]")
        return false
    end
    local entry = hit.entry
    local sender = entry.source
    if type(sender) ~= "string" or sender == "" then
        chat(tostring(entry.name) .. " has no sender to whisper (read by link only?).")
        return false
    end
    local GSS = AltArmy.GuildShareSettings
    local myRealm = (GSS and GSS._CurrentRealm and GSS._CurrentRealm()) or (GetRealmName and GetRealmName()) or ""
    local realm = entry.charRealm or guidRealms[entry.guid] or myRealm
    pending = {
        mode = "cards",
        query = query,
        character = { name = entry.name, guid = entry.guid, storedRealm = hit.realm,
            needsProfessionCard = entry.needsProfessionCard },
        sender = sender,
        senderOnline = Comm.IsGuildMemberOnline and Comm.IsGuildMemberOnline(sender) or nil,
        myRealm = myRealm,
        theirRealm = realm,
        theirRealmFrom = entry.charRealm and "stored" or (guidRealms[entry.guid] and "presence") or "mine",
        myGuid = UnitGUID and UnitGUID("player") or nil,
        startedAt = now(),
        partsSince = clock(),
        variants = {},
        order = {},
        system = {},
    }
    local p = pending
    chat(string.format("asking %s for %s's card %d times (realm %s, online %s)", sender, tostring(entry.name), n,
        realm, tostring(p.senderOnline)))
    local ctimer = _G.C_Timer
    for i = 1, n do
        local v = { label = "rep" .. i, target = sender, realm = realm }
        p.variants[v.label] = v
        p.order[#p.order + 1] = v
        local function sendOne()
            if pending ~= p then return end
            v.sentAt = clock()
            Comm._Send("CQ", P.BuildCharCardRequest(Probe.TagName(entry.name, v.label), realm, entry.guid),
                "WHISPER", sender, function(sent, sendResult)
                    v.sent = sent
                    v.sendResult = sendResult
                end)
        end
        if ctimer and ctimer.After and i > 1 then
            ctimer.After((i - 1) * Probe.CARD_SPACING_SEC, sendOne)
        else
            sendOne()
        end
    end
    local total = (n - 1) * Probe.CARD_SPACING_SEC + Probe.WINDOW_SEC
    if ctimer and ctimer.After then
        ctimer.After(total, finish)
        chat(string.format("results in %ds.", total))
    else
        finish()
    end
    return true
end

-- Test helpers.
function Probe._Reset()
    senders, guidRealms, handled, pending, parts, openStreams, anomalies = {}, {}, {}, nil, {}, {}, {}
end
function Probe._Senders() return senders end
function Probe._GuidRealms() return guidRealms end
Probe._OnSystemMessage = onSystemMessage
Probe._Finish = finish

do
    local Comm = AltArmy.GuildShareComm
    if Comm then
        Comm.OnRawReceive = Probe.OnRawReceive
        Comm.InterceptCharCard = Probe.InterceptCharCard
        Comm.OnRequestHandled = Probe.OnRequestHandled
    end
    local frame = CreateFrame and CreateFrame("Frame")
    if frame then
        frame:RegisterEvent("CHAT_MSG_SYSTEM")
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_ADDON" then
                local prefix, message, distribution, sender = ...
                -- AceComm passes the sender through Ambiguate(sender, "none"); match it.
                if type(sender) == "string" and accessible(sender) and _G.Ambiguate then
                    local ok, short = pcall(_G.Ambiguate, sender, "none")
                    if ok then sender = short end
                end
                pcall(Probe.OnAddonMessage, prefix, message, distribution, sender)
            else
                pcall(onSystemMessage, ...)
            end
        end)
    end
end
