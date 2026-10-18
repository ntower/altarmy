-- AltArmy TBC — Guild data sharing: guildmates' professions read through profession links (WoW Forever).
--
-- The server answers a profession link ("trade:<GUID>:<Apprentice spell>:<skill line>") for any player
-- online on this server, addon or not. DataStore/OwnRecipeRead.lua opens such a window out of sight and
-- reads it; this module decides whose professions to ask for, when, and stores what comes back through
-- GuildShareData.SaveLinkRead, in the shape search and the Guild tab already read. The sharing opt-in
-- (GuildShareSettings) plays no part: it governs what the player sends about their own characters.
--
-- Who is read: guildmates who share nothing through Alt Army (no addon, or the addon with sharing off).
-- Those who share get their recipes by the guild share messages (GuildShareComm), never by link.
--   - Each such member online in the guild roster (GUILD_ROSTER_UPDATE, polled every ROSTER_POLL), probed one
--     linkable skill line at a time: Cooking and First Aid first, since nearly everyone has them. When
--     both go unanswered the member is unreachable for now (offline since the roster was read) and their
--     other lines wait. Members on another server are left out (TRY_OTHER_SERVERS). Lines that never
--     answer back off for days (GuildShareData.linkProbes); known lines are read again after a few days or
--     when the member levelled.
-- Pacing: reads run one at a time in OwnRecipeRead's queue after the player's own, SESSION_BUDGET per
-- session, pausing PAUSE_SEC after PAUSE_AFTER_TIMEOUTS unanswered links in a row. With the Guild tab open
-- on a character, their reads go first (RequestNow).
-- Every read is logged through Debug.LogGuildShare (the "Guild sharing traffic (verbose)" debug flag).

if not AltArmy then return end

AltArmy.GuildLinkRead = AltArmy.GuildLinkRead or {}
local GLR = AltArmy.GuildLinkRead

GLR.LOGIN_DELAY = 45          -- seconds after login before the first roster pass (own reads, presence first)
GLR.ROSTER_SETTLE = 5         -- seconds a roster update settles before a pass
GLR.ROSTER_POLL = 300         -- seconds between asking the server for the roster (who came online)
GLR.PRESENCE_GRACE = 60       -- seconds a member just seen online gets to announce the addon before a probe
GLR.SESSION_BUDGET = 150      -- guild reads per session
GLR.PAUSE_AFTER_TIMEOUTS = 3  -- unanswered links in a row before a pause...
GLR.PAUSE_SEC = 120           -- ...this long
GLR.REACHABILITY_MISSES = 2   -- unanswered reachability probes that make a member unreachable for now
GLR.UNREACHABLE_RETRY_SEC = 1800
GLR.EMPTY_ROSTER_RETRY_SEC = 10 -- seconds before a pass that found the roster not loaded yet tries again...
GLR.EMPTY_ROSTER_RETRIES = 6    -- ...at most this many times in a row
-- The server answers links only for players on your own backend server (the number after "Player-" in the
-- GUID): a link for a member on another server always times out, so they are never read. Blizzard may fix
-- this in the future; turning this on then reads them last, tagged "other server" in the log, and their
-- unanswered links never pause the reads of everyone else.
GLR.TRY_OTHER_SERVERS = false
GLR.PRIORITY_ON_DEMAND = 2
GLR.PRIORITY_BACKGROUND = 3

--- The linkable skill lines in probe order: the two nearly everyone has first (reachability), then the six.
GLR.LINES = {
    { skillLine = 185, key = "cooking" },
    { skillLine = 129, key = "firstAid" },
    { skillLine = 171, key = "alchemy" },
    { skillLine = 164, key = "blacksmithing" },
    { skillLine = 165, key = "leatherworking" },
    { skillLine = 197, key = "tailoring" },
    { skillLine = 202, key = "engineering" },
    { skillLine = 333, key = "enchanting" },
}
GLR.REACHABILITY_LINES = { [185] = true, [129] = true }

local state

local function reset()
    state = {
        enqueued = 0,          -- reads queued this session (the budget)
        timeouts = 0,          -- unanswered links in a row
        pausedUntil = nil,
        unreachable = {},      -- guid -> when both reachability probes had gone unanswered
        seen = {},             -- guid -> when first seen online this session
        probes = {},           -- guid -> { misses, answered }: the reachability probes' fate
        members = {},          -- guid -> the roster row from the last pass
        settleScheduled = false,
        pollArmed = false,
        loginArmed = false,
        budgetLogged = false,
        noGuidLogged = false,
        rosterDumped = false,
        emptyRetries = 0,
    }
end
reset()

local function log(msg)
    local D = AltArmy.Debug
    if D and D.LogGuildShare then D.LogGuildShare(msg) end
end

local function nowTs()
    return (time and time()) or 0
end

local function reader()
    return AltArmy.OwnRecipeRead
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

local function shortName(name)
    if type(name) ~= "string" then return name end
    return name:match("^[^%-]+") or name
end

local function duration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds >= 86400 then return string.format("%dd", math.floor(seconds / 86400)) end
    if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600)) end
    if seconds >= 60 then return string.format("%dm", math.floor(seconds / 60)) end
    return string.format("%ds", seconds)
end

--- A read's member as the log names them: "(other server)" after a member on another backend server.
local function who(desc)
    if desc.otherServer then return tostring(desc.name) .. " (other server)" end
    return tostring(desc.name)
end

local function notifyChanged()
    local Comm = AltArmy.GuildShareComm
    if Comm and Comm.NotifyDataChanged then pcall(Comm.NotifyDataChanged) end
end

--- Whether guild reads can run on this client: OwnRecipeRead's engine and its one switch.
function GLR.IsAvailable()
    local R = reader()
    return R ~= nil and R.CanRunGuildReads ~= nil and R.CanRunGuildReads() == true
end

local function serverOf(guid)
    if type(guid) ~= "string" then return nil end
    return guid:match("^Player%-(%d+)%-")
end

--- Whether two player GUIDs name the same server (the number after "Player-"). Links are answered only
--- for players on the player's own server. GUIDs of another shape can't be told apart and pass.
function GLR.SameServer(guidA, guidB)
    local a, b = serverOf(guidA), serverOf(guidB)
    if not a or not b then return true end
    return a == b
end

--- The guild's online members with a usable GUID on this server: { { guid, name (short), fullName,
--- level, classFile }, ... }, and what the roster held: { inGuild, source ("roster" or "club"), total
--- (rows), online (others online), noGuid, otherServer }. Rows come from GuildShareComm.GuildRosterRows:
--- the classic roster, else the Club API's. `api` may override isInGuild, getNumGuildMembers,
--- getGuildRosterInfo, club and playerGuid (tests).
function GLR.CollectOnlineMembers(api)
    api = api or {}
    local isInGuild = api.isInGuild or IsInGuild
    local myGuid = api.playerGuid or (UnitGUID and UnitGUID("player"))
    local out = {}
    local skipped = { inGuild = false, source = "roster", total = 0, online = 0, noGuid = 0, otherServer = 0 }
    local Comm = AltArmy.GuildShareComm
    if not (isInGuild and isInGuild()) or not (Comm and Comm.GuildRosterRows) then return out, skipped end
    skipped.inGuild = true
    local rows, source = Comm.GuildRosterRows(api)
    skipped.total, skipped.source = #rows, source
    for _, row in ipairs(rows) do
        local name, level, online, classFile, guid = row.name, row.level, row.online, row.classFile, row.guid
        if online and guid ~= myGuid then skipped.online = skipped.online + 1 end
        if online then
            if type(guid) ~= "string" or guid == "" or type(name) ~= "string" or name == "" then
                skipped.noGuid = skipped.noGuid + 1
            elseif guid ~= myGuid and not GLR.SameServer(guid, myGuid) then
                skipped.otherServer = skipped.otherServer + 1
                if GLR.TRY_OTHER_SERVERS then
                    out[#out + 1] = {
                        guid = guid,
                        name = shortName(name),
                        fullName = name,
                        level = tonumber(level) or 0,
                        classFile = classFile,
                        otherServer = true,
                    }
                end
            elseif guid ~= myGuid then
                out[#out + 1] = {
                    guid = guid,
                    name = shortName(name),
                    fullName = name,
                    level = tonumber(level) or 0,
                    classFile = classFile,
                }
            end
        end
    end
    return out, skipped
end

local function hasLinkRead(entry)
    for _, prof in pairs(entry and entry.Professions or {}) do
        if type(prof) == "table" and prof.linkReadAt then return true end
    end
    return false
end

--- The reads worth queueing for online members, pure: { { guid, name, level, classFile, skillLine, key,
--- reason, reachability }, ... } in the order to run them: the reachability probes of members never
--- read, then re-reads, then the other probes; members in the order given, lines in GLR.LINES' order.
--- Also a summary { members, shared, graced }. A member who shares through Alt Army (their recipes come by
--- message), one unreachable for now, or one seen online under PRESENCE_GRACE ago with nothing stored
--- (they may be about to announce the addon) is left out.
function GLR.PlanJobs(members, realm, nowTs_, st)
    st = st or state
    local GSD = AltArmy.GuildShareData
    local jobs = {}
    local summary = { members = #members, shared = 0, graced = 0 }
    if not (GSD and GSD.GetSkillLinesNeedingLinkRead) then return jobs, summary end
    for index, member in ipairs(members) do
        local entry = GSD.GetCharacter and GSD.GetCharacter(member.guid, realm) or nil
        local shared = entry ~= nil and not entry.linkOnly
        if shared then summary.shared = summary.shared + 1 end
        local unreachableAt = st.unreachable[member.guid]
        local skip = shared or (unreachableAt ~= nil and (nowTs_ - unreachableAt) < GLR.UNREACHABLE_RETRY_SEC)
        if not skip and not entry then
            local seenAt = st.seen[member.guid]
            if seenAt and (nowTs_ - seenAt) < GLR.PRESENCE_GRACE then
                skip = true
                summary.graced = summary.graced + 1
            end
        end
        if not skip then
            local known = hasLinkRead(entry)
            for lineOrder, need in ipairs(GSD.GetSkillLinesNeedingLinkRead(realm, member, nowTs_, GLR.LINES)) do
                local probe = need.reason == "probe"
                local reachability = probe and not known and GLR.REACHABILITY_LINES[need.skillLine] == true
                local rank
                if reachability then
                    rank = 1
                elseif not probe then
                    rank = 2
                else
                    rank = 3
                end
                jobs[#jobs + 1] = {
                    guid = member.guid,
                    name = member.name,
                    level = member.level,
                    classFile = member.classFile,
                    skillLine = need.skillLine,
                    key = need.key,
                    reason = need.reason,
                    reachability = reachability,
                    otherServer = member.otherServer == true,
                    rank = rank + (member.otherServer and 10 or 0),
                    order = index,
                    lineOrder = lineOrder,
                }
            end
        end
    end
    table.sort(jobs, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.order ~= b.order then return a.order < b.order end
        return a.lineOrder < b.lineOrder
    end)
    return jobs, summary
end

local enqueueJob

local function pause()
    local R = reader()
    local dropped = R and R.CancelWhere and R.CancelWhere(function() return true end) or 0
    state.pausedUntil = nowTs() + GLR.PAUSE_SEC
    state.timeouts = 0
    log(string.format("LINK pause %ds after %d timeouts (%d read(s) dropped)",
        GLR.PAUSE_SEC, GLR.PAUSE_AFTER_TIMEOUTS, dropped))
    if C_Timer and C_Timer.After then
        C_Timer.After(GLR.PAUSE_SEC, function()
            state.pausedUntil = nil
            GLR.Schedule("pause over")
        end)
    end
end

--- A read ended (OwnRecipeRead's onResult): store it, remember a miss, judge reachability, pause.
function GLR._OnResult(desc, realm, outcome, result, elapsed)
    local GSD = AltArmy.GuildShareData
    local R = reader()
    local took = elapsed and string.format("%.1fs", elapsed) or "?"
    if outcome == "ok" and result then
        state.timeouts = 0
        state.unreachable[desc.guid] = nil
        state.probes[desc.guid] = { answered = true }
        local member = state.members[desc.guid] or {}
        if GSD and GSD.SaveLinkRead then
            GSD.SaveLinkRead(realm, {
                guid = desc.guid,
                name = desc.name,
                guildName = currentGuild(),
                classFile = member.classFile or desc.classFile,
                level = member.level or desc.level,
                profKey = result.key or desc.key,
                profName = result.professionName,
                skillLine = desc.skillLine,
                rank = result.rank,
                maxRank = result.maxRank,
                ids = result.ids,
                readAt = nowTs(),
            })
        end
        log(string.format("LINK ok %s %s %d/%d, %d recipes, %s", who(desc), desc.key,
            tonumber(result.rank) or 0, tonumber(result.maxRank) or 0, #(result.ids or {}), took))
        notifyChanged()
        return
    end
    if outcome == "absent" then
        -- The server answered, so the member is reachable; they just haven't got this profession.
        state.timeouts = 0
        state.unreachable[desc.guid] = nil
        state.probes[desc.guid] = { answered = true }
        local member = state.members[desc.guid] or {}
        local removed = GSD and GSD.MarkLinkAbsent and GSD.MarkLinkAbsent(realm, desc.guid, desc.skillLine,
            (result and result.key) or desc.key, nowTs(), member.level or desc.level)
        log(string.format("LINK absent %s %s: not one of their professions, %s", who(desc), desc.key, took))
        if removed then notifyChanged() end
        return
    end
    if outcome == "wrong name" then
        local again = not desc.retried
        log(string.format("LINK wrong-name %s %s: window named %s%s", desc.name, desc.key,
            tostring(result and result.linkedName), again and ", trying again" or ""))
        if again then
            desc.retried = true
            enqueueJob(desc, realm, desc.priority)
        end
        return
    end
    -- timeout, unnamed, error, wrong profession: the link went unanswered as far as we're concerned.
    -- An other-server link going unanswered is expected, not a sign the reads should pause.
    if not desc.otherServer then state.timeouts = state.timeouts + 1 end
    local probe
    if GSD and GSD.MarkLinkTried then
        GSD.MarkLinkTried(realm, desc.guid, desc.skillLine, nowTs())
        probe = GSD.GetLinkProbe and GSD.GetLinkProbe(realm, desc.guid, desc.skillLine) or nil
    end
    local misses = probe and probe.misses or 1
    local backoff = GSD and GSD.LinkProbeBackoffSec and GSD.LinkProbeBackoffSec(misses) or 0
    log(string.format("LINK %s %s %s %s (miss %d, next in %s)", outcome, who(desc), desc.key, took,
        misses, duration(backoff)))
    if desc.reachability then
        local p = state.probes[desc.guid] or { misses = 0 }
        if not p.answered then
            p.misses = (p.misses or 0) + 1
            state.probes[desc.guid] = p
            if p.misses >= GLR.REACHABILITY_MISSES then
                state.unreachable[desc.guid] = nowTs()
                state.probes[desc.guid] = nil
                local dropped = R and R.CancelWhere
                    and R.CancelWhere(function(job) return job.guid == desc.guid end) or 0
                log(string.format(
                    "LINK unreachable %s: Cooking and First Aid unanswered, %d read(s) dropped; retry in %s",
                    desc.name, dropped, duration(GLR.UNREACHABLE_RETRY_SEC)))
            end
        end
    end
    if state.timeouts >= GLR.PAUSE_AFTER_TIMEOUTS then pause() end
end

enqueueJob = function(desc, realm, priority)
    local R = reader()
    if not (R and R.Enqueue) then return false end
    priority = priority or GLR.PRIORITY_BACKGROUND
    if state.enqueued >= GLR.SESSION_BUDGET then
        if not state.budgetLogged then
            state.budgetLogged = true
            log(string.format("LINK budget: %d reads this session, stopping", GLR.SESSION_BUDGET))
        end
        return false
    end
    desc.priority = priority
    local job = {
        guid = desc.guid,
        name = desc.name,
        skillLine = desc.skillLine,
        priority = priority,
        onStart = function(spell)
            log(string.format("LINK start %s [%s] %s (%d) spell %d prio %d reason=%s", who(desc), desc.guid,
                desc.key, desc.skillLine, tonumber(spell) or 0, priority, desc.reason or "?"))
        end,
        onResult = function(outcome, result, elapsed)
            GLR._OnResult(desc, realm, outcome, result, elapsed)
        end,
    }
    if not R.Enqueue(job) then
        if R.Promote then R.Promote(job.tag or R.JobTag(desc.guid, desc.skillLine), priority) end
        return false
    end
    state.enqueued = state.enqueued + 1
    return true
end

--- Debug only: where the roster came from ("roster": GetGuildRosterInfo, "club": the Club API) and its
--- first rows, until a pass finds it loaded.
local function dumpRoster(api)
    if state.rosterDumped then return end
    local D = AltArmy.Debug
    local Comm = AltArmy.GuildShareComm
    if not (D and D.Dump and Comm and Comm.GuildRosterRows) then return end
    local all, source = Comm.GuildRosterRows(api)
    if #all > 0 then state.rosterDumped = true end
    local rows = {}
    for i = 1, math.min(#all, 5) do
        local row = all[i]
        rows[#rows + 1] = {
            name = row.name or "<secret or nil>",
            online = row.online and true or false,
            guid = row.guid or "<secret or nil>",
        }
    end
    D.Dump("guildRosterGuid", {
        source = source, total = #all, rows = rows, myGuid = UnitGUID and UnitGUID("player") or nil,
    })
end

--- One pass over the roster: forget members gone offline, plan and queue reads for those online.
function GLR.RunPass(reason, api)
    if not GLR.IsAvailable() then return end
    local now = nowTs()
    if state.pausedUntil and now < state.pausedUntil then return end
    local realm = currentRealm()
    local members, skipped = GLR.CollectOnlineMembers(api)
    dumpRoster(api)
    if skipped.inGuild and skipped.total == 0 then
        -- The client hasn't got the roster yet (it fills only once asked for): ask, and look again.
        if state.emptyRetries < GLR.EMPTY_ROSTER_RETRIES then
            state.emptyRetries = state.emptyRetries + 1
            local Comm = AltArmy.GuildShareComm
            local asked = Comm and Comm.RequestGuildRoster and Comm.RequestGuildRoster()
            log(string.format("LINK roster not loaded yet (%s), %s; looking again in %ds (%d/%d)",
                tostring(reason), asked and "asked the server for it" or "no way to ask for it",
                GLR.EMPTY_ROSTER_RETRY_SEC, state.emptyRetries, GLR.EMPTY_ROSTER_RETRIES))
            GLR.Schedule("roster retry", GLR.EMPTY_ROSTER_RETRY_SEC)
        else
            log(string.format("LINK roster still empty after %d tries; waiting for the next roster update",
                GLR.EMPTY_ROSTER_RETRIES))
        end
        return
    end
    state.emptyRetries = 0
    local online = {}
    for _, m in ipairs(members) do
        online[m.guid] = true
        state.members[m.guid] = m
        if not state.seen[m.guid] then state.seen[m.guid] = now end
    end
    for guid in pairs(state.seen) do
        if not online[guid] then
            state.seen[guid] = nil
            state.members[guid] = nil
        end
    end
    local R = reader()
    if R and R.CancelWhere then
        R.CancelWhere(function(job) return not online[job.guid] end)
    end
    local jobs, summary = GLR.PlanJobs(members, realm, now, state)
    local queued = 0
    for _, desc in ipairs(jobs) do
        if enqueueJob(desc, realm, GLR.PRIORITY_BACKGROUND) then queued = queued + 1 end
    end
    log(string.format(
        "LINK plan (%s): %s %d, %d online (%d without a GUID, %d on another server); "
            .. "%d read(s) for %d member(s), %d shared, %d waiting to announce; %d queued, %d budget left",
        tostring(reason), skipped.source, skipped.total, skipped.online, skipped.noGuid, skipped.otherServer,
        #jobs, summary.members, summary.shared, summary.graced, queued,
        math.max(GLR.SESSION_BUDGET - state.enqueued, 0)))
    if skipped.noGuid > 0 and not state.noGuidLogged then
        state.noGuidLogged = true
        log(string.format("LINK roster: %d online member(s) without a usable GUID", skipped.noGuid))
    end
    if summary.graced > 0 then GLR.Schedule("grace over", GLR.PRESENCE_GRACE) end
end

--- A pass once things settle (at most one waiting at a time).
function GLR.Schedule(reason, delay)
    if state.settleScheduled then return end
    if not (C_Timer and C_Timer.After) then
        GLR.RunPass(reason)
        return
    end
    state.settleScheduled = true
    C_Timer.After(delay or GLR.ROSTER_SETTLE, function()
        state.settleScheduled = false
        GLR.RunPass(reason)
    end)
end

--- The Guild tab opened a character's recipes: their reads go next. Returns how many were queued or moved up.
function GLR.RequestNow(entry, api)
    if not GLR.IsAvailable() or type(entry) ~= "table" or type(entry.guid) ~= "string" then return 0 end
    local member = state.members[entry.guid]
    if not member then
        for _, m in ipairs((GLR.CollectOnlineMembers(api))) do
            if m.guid == entry.guid then
                member = m
                state.members[m.guid] = m
                break
            end
        end
    end
    if not member then return 0 end
    local realm = entry.realm or currentRealm()
    local now = nowTs()
    state.seen[entry.guid] = state.seen[entry.guid] or (now - GLR.PRESENCE_GRACE)
    local jobs = GLR.PlanJobs({ member }, realm, now, state)
    local moved = 0
    local R = reader()
    for _, desc in ipairs(jobs) do
        if enqueueJob(desc, realm, GLR.PRIORITY_ON_DEMAND) then
            moved = moved + 1
        elseif R and R.Promote and R.JobTag
            and R.Promote(R.JobTag(desc.guid, desc.skillLine), GLR.PRIORITY_ON_DEMAND) then
            moved = moved + 1
        end
    end
    return moved
end

--- Ask the server for the roster now and every ROSTER_POLL, so members coming online are noticed.
function GLR.PollRoster()
    if GLR.IsAvailable() and IsInGuild and IsInGuild() then
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.RequestGuildRoster then
            Comm.RequestGuildRoster()
        elseif C_GuildInfo and C_GuildInfo.GuildRoster then
            pcall(C_GuildInfo.GuildRoster)
        elseif GuildRoster then
            pcall(GuildRoster)
        end
        GLR.Schedule("poll")
    end
    if not state.pollArmed and C_Timer and C_Timer.After then
        state.pollArmed = true
        C_Timer.After(GLR.ROSTER_POLL, function()
            state.pollArmed = false
            GLR.PollRoster()
        end)
    end
end

function GLR.OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if (isInitialLogin or isReloadingUi) and not state.loginArmed and C_Timer and C_Timer.After then
            local GSD = AltArmy.GuildShareData
            local dropped = GSD and GSD.DropForeignLinkReads and GSD.DropForeignLinkReads() or 0
            if dropped > 0 then
                log(string.format("LINK dropped %d read(s) holding another profession's recipes", dropped))
                notifyChanged()
            end
            state.loginArmed = true
            C_Timer.After(GLR.LOGIN_DELAY, function()
                state.loginArmed = false
                GLR.PollRoster()
            end)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if GLR.IsAvailable() then GLR.Schedule("roster") end
    elseif event == "PLAYER_GUILD_UPDATE" then
        local R = reader()
        if R and R.CancelWhere then R.CancelWhere(function() return true end) end
        state.unreachable, state.seen, state.members, state.probes = {}, {}, {}, {}
    end
end

function GLR._ResetForTests()
    reset()
end

function GLR._State()
    return state
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...) GLR.OnEvent(event, ...) end)
end
