-- AltArmy TBC — TEMPORARY skill-up logger for testing Working Overtime (remove once measured).
-- /altarmy skilltest start <profession> | stop | status | clear
-- While running, every craft the player finishes and every rank change of that profession is appended
-- to AltArmyTBC_Options.debug.devDumps.skillTest (read with /reload, then `npm run dump:sync`).
-- Each session records the Legacy talents at its start; each cast its spell, the rank read when it
-- finished and, when the trade skill window shows it, the recipe's difficulty colour. A /reload ends a
-- session (start another after it).

if not AltArmy then return end

AltArmy.SkillTest = AltArmy.SkillTest or {}
local ST = AltArmy.SkillTest

local SPELL_WORKING_OVERTIME = 1225451

local function say(text)
    if AltArmy.Debug and AltArmy.Debug.NotifyChat then
        AltArmy.Debug.NotifyChat("|cff00ccff[Alt Army skill test]|r " .. text)
    end
end

local function log()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local o = AltArmyTBC_Options
    o.debug = type(o.debug) == "table" and o.debug or {}
    o.debug.devDumps = type(o.debug.devDumps) == "table" and o.debug.devDumps or {}
    local t = o.debug.devDumps.skillTest
    if type(t) ~= "table" then
        t = { sessions = {} }
        o.debug.devDumps.skillTest = t
    end
    return t
end

local function now()
    return GetTime and GetTime() or 0
end

--- The profession's rank, max rank and exact name: from the skill list (expanding collapsed headers
--- first), else from GetProfessions' slots (WoW Forever has no skill list).
local function readSkill(name)
    local want = name:lower()
    if GetNumSkillLines and GetSkillLineInfo then
        for i = GetNumSkillLines(), 1, -1 do
            local _, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded and ExpandSkillHeader then
                ExpandSkillHeader(i)
            end
        end
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and skillName and skillName:lower() == want then
                return rank, maxRank, skillName
            end
        end
    end
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local skillName, _, rank, maxRank = GetProfessionInfo(index)
            if skillName and skillName:lower() == want then
                return rank, maxRank, skillName
            end
        end
    end
    return nil
end

local RELATIVE_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

--- The recipe's difficulty colour ("optimal", "medium", "easy", "trivial") from the open trade skill
--- window, or nil when it can't be read.
local function difficultyOf(spellID, spellName)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spellID)
        if ok and type(info) == "table" and info.relativeDifficulty ~= nil then
            return RELATIVE_DIFFICULTY[info.relativeDifficulty] or tostring(info.relativeDifficulty)
        end
    end
    if not spellName or not GetNumTradeSkills or not GetTradeSkillInfo then return nil end
    local ok, count = pcall(GetNumTradeSkills)
    if not ok or not count then return nil end
    for i = 1, count do
        local okInfo, name, kind = pcall(GetTradeSkillInfo, i)
        if okInfo and name == spellName then return kind end
    end
    return nil
end

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return name end
    end
    return nil
end

local function talentRanks()
    local DL = AltArmy.DataStoreLegacy
    local scan = DL and DL.ScanActiveConfig and DL.ScanActiveConfig()
    return scan and scan.spells or nil
end

local session -- the running session's table inside the log, or nil

local frame = CreateFrame("Frame")

--- Logs a skill event when the profession's rank moved since the last one.
local function checkRank()
    if not session then return end
    local rank = readSkill(session.profession)
    if rank and rank ~= session.rank then
        session.rank = rank
        session.events[#session.events + 1] = { k = "skill", n = session.crafts, t = now(), rank = rank }
        say(string.format("%s %d (%d crafts so far)", session.profession, rank, session.crafts))
    end
end

local function onEvent(_, event, ...)
    if not session then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        local name = spellName(spellID)
        -- Every cast is logged (the analysis keeps the profession's recipes); the colour when readable.
        local colour = difficultyOf(spellID, name)
        local rank = readSkill(session.profession)
        session.crafts = session.crafts + 1
        session.events[#session.events + 1] = {
            k = "craft", n = session.crafts, t = now(), spell = spellID, name = name, rank = rank,
            colour = colour,
        }
        -- The rank may move after the cast's event: look again shortly (not every client fires a skill event).
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, checkRank)
        end
    else
        checkRank()
    end
end
frame:SetScript("OnEvent", onEvent)

local function start(profession)
    if profession == "" then
        say("Name the profession: /altarmy skilltest start Cooking")
        return
    end
    local rank, maxRank, exact = readSkill(profession)
    if not rank then
        say("You don't have a skill called " .. profession .. ".")
        return
    end
    local talents = talentRanks()
    session = {
        profession = exact, character = UnitName and UnitName("player") or "?",
        realm = GetRealmName and GetRealmName() or "?", startRank = rank, maxRank = maxRank, rank = rank,
        startedAt = time and time() or 0, talents = talents,
        workingOvertime = talents and talents[SPELL_WORKING_OVERTIME] or nil,
        crafts = 0, events = {},
    }
    local sessions = log().sessions
    sessions[#sessions + 1] = session
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("CHAT_MSG_SKILL")
    if frame.RegisterEvent and C_TradeSkillUI then
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_LIST_UPDATE")
    end
    say(string.format("Logging %s from %d (Working Overtime %s).",
        exact, rank, tostring(session.workingOvertime or "unknown")))
end

local function stop()
    if not session then
        say("Not running.")
        return
    end
    frame:UnregisterAllEvents()
    say(string.format("Stopped: %d crafts, %s %d to %d. /reload to save.", session.crafts, session.profession,
        session.startRank, session.rank))
    session = nil
end

function ST.Command(rest)
    local verb, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    verb = (verb or ""):lower()
    if verb == "start" then
        if session then stop() end
        start(arg or "")
    elseif verb == "stop" then
        stop()
    elseif verb == "clear" then
        if session then stop() end
        log().sessions = {}
        say("Cleared.")
    else
        if session then
            say(string.format("Running: %s %d, %d crafts.", session.profession, session.rank, session.crafts))
        else
            say(string.format("Not running; %d session(s) logged.", #log().sessions))
        end
        say("/altarmy skilltest start <profession> | stop | status | clear")
    end
end
