-- AltArmy TBC — DataStore module: level-up milestones, death log, one-time backfill.
-- Requires DataStore.lua (core) loaded first.
-- luacheck: globals GetRealZoneText GetMoney GetXPExhaustion RequestTimePlayed C_Timer C_AddOns IsAddOnLoaded
-- luacheck: globals UnitGUID UnitLevel UnitName GetRealmName RXPCTrackingData NITdatabase CHAT_FRAMES NUM_CHAT_WINDOWS

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local ZERO_GUID = "0000000000000000"
local ENVIRONMENT_KILLER = "Environment"

--- Patch 12.0+ clients (Forever included) can hand combat-log fields (source
--- name/subevent) to addons as Secret Values that error on any operation beyond
--- store/pass. `canaccessvalue()` (existence-checked) is the guard for that,
--- matching both our own DataStoreProfessions.lua fix and the convention Thaoky's
--- DataStore addons use for this exact case.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

local lastAttacker = { name = nil, guid = nil }
local testCharOverride = nil
local testDebugMessages = nil
local testRxpAddonEnabled = nil
local rxpBackfillRetryCount = 0
local rxpBackfillRetryScheduled = false

local RXP_ADDON_NAMES = { "RXPGuides", "RXPGuides_TBC" }
local RXP_BACKFILL_RETRY_DELAY = 3
local RXP_BACKFILL_MAX_RETRIES = 5

local LEVEL_HISTORY_DEBUG_PREFIX = "|cff00ccff[Alt Army:LevelHistory]|r "

-- Our own /played requests are kept out of chat by unregistering TIME_PLAYED_MSG on the chat frames
-- until the answer has come (our DataStore frame still gets it). Nothing of Blizzard's is replaced:
-- Forever's chat calls ChatFrameUtil.DisplayTimePlayed from ChatFrameMixin, not the old global, and
-- replacing Blizzard functions on 12.0 clients taints.
local PLAYED_EVENT = "TIME_PLAYED_MSG"
local PLAYED_CHAT_MUTE_TIMEOUT = 10
local mutedChatFrames = {}
local pendingPlayedRequests = 0
local playedMuteGeneration = 0

local function ChatFrames()
    local list = {}
    if type(CHAT_FRAMES) == "table" then
        for _, name in ipairs(CHAT_FRAMES) do
            local f = _G[name]
            if f then list[#list + 1] = f end
        end
    else
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local f = _G["ChatFrame" .. i]
            if f then list[#list + 1] = f end
        end
    end
    return list
end

local function UnmutePlayedChat()
    for _, f in ipairs(mutedChatFrames) do
        if f.IsEventRegistered and not f:IsEventRegistered(PLAYED_EVENT) then
            pcall(f.RegisterEvent, f, PLAYED_EVENT)
        end
    end
    mutedChatFrames = {}
    pendingPlayedRequests = 0
    playedMuteGeneration = playedMuteGeneration + 1
end

local function MutePlayedChat()
    if #mutedChatFrames > 0 then return end
    for _, f in ipairs(ChatFrames()) do
        if f.IsEventRegistered and f.UnregisterEvent and f:IsEventRegistered(PLAYED_EVENT) then
            f:UnregisterEvent(PLAYED_EVENT)
            mutedChatFrames[#mutedChatFrames + 1] = f
        end
    end
    if #mutedChatFrames > 0 and C_Timer and C_Timer.After then
        local generation = playedMuteGeneration
        C_Timer.After(PLAYED_CHAT_MUTE_TIMEOUT, function()
            if generation == playedMuteGeneration then UnmutePlayedChat() end
        end)
    end
end

--- Called with every TIME_PLAYED_MSG: once each request has its answer, the chat frames get the event back
--- (next frame, so they don't receive the one being delivered now).
local function OnPlayedAnswered()
    if pendingPlayedRequests <= 0 then return end
    pendingPlayedRequests = pendingPlayedRequests - 1
    if pendingPlayedRequests > 0 then return end
    if C_Timer and C_Timer.After then
        local generation = playedMuteGeneration
        C_Timer.After(0, function()
            if generation == playedMuteGeneration then UnmutePlayedChat() end
        end)
    else
        UnmutePlayedChat()
    end
end

function DS:RequestTimePlayedSilently()
    if not RequestTimePlayed then return end
    MutePlayedChat()
    pendingPlayedRequests = pendingPlayedRequests + 1
    RequestTimePlayed()
end

function DS._GetPlayedChatMuted()
    return #mutedChatFrames
end

function DS._GetPendingPlayedRequests()
    return pendingPlayedRequests
end

local function GetAccountData()
    return DS.accountData or AltArmyTBC_Data
end

local function EnsureLevelHistoryOptions()
    AltArmyTBC_Options = AltArmyTBC_Options or {}
    if not AltArmyTBC_Options.levelHistory then
        AltArmyTBC_Options.levelHistory = { enabled = true }
    end
    if AltArmyTBC_Options.levelHistory.enabled == nil then
        AltArmyTBC_Options.levelHistory.enabled = true
    end
end

local function IsLevelHistoryEnabled()
    EnsureLevelHistoryOptions()
    return AltArmyTBC_Options.levelHistory.enabled == true
end

local function EnsureLevelHistory(char)
    if not char then return nil end
    char.levelHistory = char.levelHistory or {}
    char.levelHistory.meta = char.levelHistory.meta or {}
    char.levelHistory.milestones = char.levelHistory.milestones or {}
    char.levelHistory.deaths = char.levelHistory.deaths or {}
    if char.levelHistory.meta.bracketDeathCount == nil then
        char.levelHistory.meta.bracketDeathCount = 0
    end
    return char.levelHistory
end

local function GetActiveChar()
    if testCharOverride then return testCharOverride end
    return GetCurrentCharTable()
end

function DS._ResetLevelHistoryTestState()
    lastAttacker = { name = nil, guid = nil }
    testCharOverride = nil
    testDebugMessages = nil
    testRxpAddonEnabled = nil
    rxpBackfillRetryCount = 0
    rxpBackfillRetryScheduled = false
    DS._pendingLevelUp = nil
    DS._playedBaseline = nil
    mutedChatFrames = {}
    pendingPlayedRequests = 0
    playedMuteGeneration = playedMuteGeneration + 1
end

function DS._SetLevelHistoryTestRxpAddonEnabled(enabled)
    testRxpAddonEnabled = enabled
end

function DS._BeginLevelHistoryDebugCapture()
    testDebugMessages = {}
end

function DS._GetLevelHistoryDebugMessages()
    return testDebugMessages or {}
end

local function LevelHistoryDebugEnabled()
    local Dbg = AltArmy and AltArmy.Debug
    return Dbg and Dbg.IsLevelHistoryEnabled and Dbg.IsLevelHistoryEnabled()
end

local function LogLevelHistoryDebug(msg)
    if not LevelHistoryDebugEnabled() then return end
    local line = LEVEL_HISTORY_DEBUG_PREFIX .. tostring(msg)
    if testDebugMessages then
        testDebugMessages[#testDebugMessages + 1] = line
        return
    end
    local Dbg = AltArmy and AltArmy.Debug
    if Dbg and Dbg.NotifyChat then
        Dbg.NotifyChat(line)
    end
end

local function EnsureOrphanImports(account)
    account.OrphanImports = account.OrphanImports or {}
    account.OrphanImports.levelHistory = account.OrphanImports.levelHistory or {}
    return account.OrphanImports
end

function DS:GetOrphanLevelHistoryRecord(realm, name)
    if not realm or not name then return nil end
    local orphans = EnsureOrphanImports(GetAccountData())
    orphans.levelHistory[realm] = orphans.levelHistory[realm] or {}
    local record = orphans.levelHistory[realm][name]
    if not record then
        record = { name = name, realm = realm }
        orphans.levelHistory[realm][name] = record
    end
    return record
end

function DS:MergeLevelHistory(targetChar, sourceChar)
    if not targetChar or not sourceChar or not sourceChar.levelHistory then return end
    local target = EnsureLevelHistory(targetChar)
    local source = sourceChar.levelHistory
    for level, milestone in pairs(source.milestones or {}) do
        target.milestones[level] = DS._MergeMilestone(target.milestones[level], milestone)
    end
    for _, death in ipairs(source.deaths or {}) do
        target.deaths[#target.deaths + 1] = death
    end
    if source.meta and source.meta.importedRxpAt and not target.meta.importedRxpAt then
        target.meta.importedRxpAt = source.meta.importedRxpAt
    end
    targetChar.dataVersions = targetChar.dataVersions or {}
    targetChar.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
end

function DS:ClaimOrphanLevelHistory(name, realm, char)
    if not name or not realm or not char then return false end
    if not self:HasModuleData(char, "character") then return false end
    local account = GetAccountData()
    local orphans = account.OrphanImports and account.OrphanImports.levelHistory
    if not orphans then return false end
    local realmTable = orphans[realm]
    if not realmTable then return false end
    local orphan = realmTable[name]
    if not orphan or not orphan.levelHistory then return false end

    self:MergeLevelHistory(char, orphan)
    realmTable[name] = nil
    if not next(realmTable) then
        orphans[realm] = nil
    end
    LogLevelHistoryDebug(string.format(
        "Claimed orphan level history for %s on %s",
        name,
        realm
    ))
    return true
end

function DS:MigratePhantomLevelHistoryImports()
    local account = GetAccountData()
    local moved = 0
    for realm, chars in pairs(account.Characters or {}) do
        for name, char in pairs(chars) do
            -- GUID-bearing entries are live characters (keyed by GUID), never phantom imports.
            if char and char.levelHistory and not char.guid and not self:HasModuleData(char, "character") then
                local orphan = self:GetOrphanLevelHistoryRecord(realm, name)
                self:MergeLevelHistory(orphan, char)
                chars[name] = nil
                moved = moved + 1
            end
        end
    end
    if moved > 0 then
        LogLevelHistoryDebug(string.format(
            "Moved level history for %d phantom character(s) into OrphanImports",
            moved
        ))
    end
    return moved
end

function DS._SetLevelHistoryTestChar(char)
    testCharOverride = char
end

function DS._ParseDeathKiller(sourceGUID, sourceName)
    if sourceName and not canAccessSecretValue(sourceName) then
        sourceName = nil
    end
    if not sourceName or sourceName == "" then
        if not sourceGUID or sourceGUID == "" or sourceGUID == ZERO_GUID then
            return { killerName = ENVIRONMENT_KILLER, killerGuid = nil }
        end
    end
    if sourceGUID == ZERO_GUID then
        return { killerName = ENVIRONMENT_KILLER, killerGuid = nil }
    end
    if sourceName and sourceName ~= "" then
        return { killerName = sourceName, killerGuid = sourceGUID }
    end
    return { killerName = ENVIRONMENT_KILLER, killerGuid = nil }
end

function DS._ComputePlayedLevel(playedTotal, previousPlayedTotal)
    if type(playedTotal) ~= "number" then return nil end
    if type(previousPlayedTotal) ~= "number" then return playedTotal end
    local delta = playedTotal - previousPlayedTotal
    if delta < 0 then return playedTotal end
    return delta
end

function DS._MergeMilestone(existing, incoming)
    existing = existing or {}
    incoming = incoming or {}
    local out = {}
    for k, v in pairs(existing) do
        out[k] = v
    end
    for k, v in pairs(incoming) do
        if out[k] == nil then
            out[k] = v
        end
    end
    return out
end

function DS._CalendarToUnix(calendar)
    if not calendar or type(calendar) ~= "table" or not calendar.year then
        return nil
    end
    if not os or not os.time then return nil end
    return os.time({
        year = calendar.year,
        month = calendar.month or 1,
        day = calendar.monthDay or calendar.day or 1,
        hour = calendar.hour or 0,
        min = calendar.minute or calendar.min or 0,
        sec = calendar.second or calendar.sec or 0,
    })
end

local function CopyGearSnapshot(gear)
    if not gear or type(gear) ~= "table" then return nil end
    local out = {}
    for slot, value in pairs(gear) do
        out[slot] = value
    end
    return out
end

local function GetPreviousMilestonePlayedTotal(char, level)
    local history = char and char.levelHistory
    if not history or not history.milestones then return nil end
    local prev = history.milestones[level - 1]
    return prev and prev.playedTotal or nil
end

function DS:GetLevelHistory(char)
    if not char then
        return { milestones = {}, deaths = {}, meta = {} }
    end
    local history = EnsureLevelHistory(char)
    return history
end

function DS:RecordLevelMilestone(char, payload)
    if not char or not payload or not payload.level then return false end
    if not IsLevelHistoryEnabled() then return false end
    local level = payload.level
    local history = EnsureLevelHistory(char)
    if history.milestones[level] then return false end

    local playedTotal = payload.playedTotal
    local playedLevel = payload.playedLevel
    if playedLevel == nil and playedTotal ~= nil then
        playedLevel = DS._ComputePlayedLevel(playedTotal, GetPreviousMilestonePlayedTotal(char, level))
    end

    local deaths = payload.deaths
    if deaths == nil then
        deaths = history.meta.bracketDeathCount or 0
    end
    history.meta.bracketDeathCount = 0

    history.milestones[level] = {
        reachedAt = payload.reachedAt,
        playedTotal = playedTotal,
        playedLevel = playedLevel,
        playedSource = payload.playedSource,
        zone = payload.zone,
        money = payload.money,
        restXP = payload.restXP,
        gear = CopyGearSnapshot(payload.gear),
        deaths = deaths,
    }
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
    char.lastUpdate = time and time() or nil
    return true
end

function DS:RecordDeath(char, payload)
    if not char or not payload then return false end
    if not IsLevelHistoryEnabled() then return false end
    local history = EnsureLevelHistory(char)
    history.deaths[#history.deaths + 1] = {
        at = payload.at,
        level = payload.level,
        zone = payload.zone,
        playedTotal = payload.playedTotal,
        killerName = payload.killerName,
        killerGuid = payload.killerGuid,
    }
    history.meta.bracketDeathCount = (history.meta.bracketDeathCount or 0) + 1
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
    char.lastUpdate = time and time() or nil
    return true
end

local function IsDamageSubevent(subevent)
    if type(subevent) ~= "string" then return false end
    if not canAccessSecretValue(subevent) then return false end
    if subevent == "ENVIRONMENTAL_DAMAGE" then return true end
    return subevent:match("_DAMAGE$") ~= nil
end

local function IsPlayerGuid(guid, playerGUID)
    return guid and playerGUID and guid == playerGUID
end

function DS:HandleCombatLogForLevelHistory(payload)
    if not IsLevelHistoryEnabled() then return end
    if type(payload) ~= "table" then return end
    if not UnitGUID then return end

    local subevent = payload[2]
    local sourceGUID = payload[4]
    local sourceName = payload[5]
    local destGUID = payload[8]
    local playerGUID = UnitGUID("player")
    if not playerGUID then return end

    if IsDamageSubevent(subevent) and IsPlayerGuid(destGUID, playerGUID) then
        lastAttacker.name = sourceName
        lastAttacker.guid = sourceGUID
        return
    end

    if subevent ~= "UNIT_DIED" and subevent ~= "UNIT_DESTROYED" then return end
    if not IsPlayerGuid(destGUID, playerGUID) then return end

    local char = GetActiveChar()
    if not char then return end

    local killer = DS._ParseDeathKiller(lastAttacker.guid, lastAttacker.name)
    lastAttacker.name = nil
    lastAttacker.guid = nil

    local level = char.level
    if UnitLevel then
        level = UnitLevel("player") or level
    end

    local zone = nil
    if GetRealZoneText then
        zone = GetRealZoneText()
    end

    DS:RecordDeath(char, {
        at = time and time() or 0,
        level = level or 0,
        zone = zone,
        playedTotal = DS:GetDerivedPlayedTotal(),
        killerName = killer.killerName,
        killerGuid = killer.killerGuid,
    })
end

function DS:UpdatePlayedBaseline(totalPlayed)
    if type(totalPlayed) ~= "number" then return end
    DS._playedBaseline = {
        totalPlayed = totalPlayed,
        wallClock = time and time() or 0,
    }
end

function DS:GetDerivedPlayedTotal()
    local baseline = DS._playedBaseline
    if baseline
        and type(baseline.totalPlayed) == "number"
        and type(baseline.wallClock) == "number"
    then
        local now = time and time() or baseline.wallClock
        return baseline.totalPlayed + (now - baseline.wallClock)
    end
    local char = GetActiveChar()
    return (char and char.played) or 0
end

function DS:RefinePlayedForLevel(char, level, authoritativePlayedTotal)
    if not char or not level or type(authoritativePlayedTotal) ~= "number" then return false end
    if not DS._pendingLevelUp or DS._pendingLevelUp.level ~= level then return false end

    local history = EnsureLevelHistory(char)
    local milestone = history.milestones[level]
    if not milestone then return false end

    milestone.playedTotal = authoritativePlayedTotal
    milestone.playedLevel = DS._ComputePlayedLevel(
        authoritativePlayedTotal,
        GetPreviousMilestonePlayedTotal(char, level)
    )
    milestone.playedSource = "server"
    char.lastUpdate = time and time() or nil
    return true
end

--- Played time is asked once a session (and on each level-up): at the first login. A /reload keeps
--- the session, so the answer saved with its time (`char.playedAt`, cleared at login so it is always
--- this session's) gives the baseline again without asking; other loading screens ask only when no
--- answer came yet.
function DS:OnEnteringWorldPlayed(isInitialLogin, isReloadingUi)
    local char = GetActiveChar()
    if isInitialLogin then
        if char then char.playedAt = nil end
        DS:RequestTimePlayedSilently()
        return
    end
    if isReloadingUi and char and type(char.played) == "number" and type(char.playedAt) == "number" then
        DS._playedBaseline = { totalPlayed = char.played, wallClock = char.playedAt }
        return
    end
    if not DS._playedBaseline then
        DS:RequestTimePlayedSilently()
    end
end

function DS:OnTimePlayedMessage(totalTimePlayed, _timePlayedThisLevel)
    OnPlayedAnswered()
    if type(totalTimePlayed) ~= "number" then return end

    DS:UpdatePlayedBaseline(totalTimePlayed)

    local pending = DS._pendingLevelUp
    if not pending or not pending.level then return end

    local char = GetActiveChar()
    if not char then return end

    if DS:RefinePlayedForLevel(char, pending.level, totalTimePlayed) then
        DS._pendingLevelUp = nil
    end
end

function DS:BeginPendingLevelUp(newLevel)
    if not IsLevelHistoryEnabled() then return end
    local char = GetActiveChar()
    if not char or not newLevel then return end

    if DS.ScanEquipment then
        DS:ScanEquipment()
    end

    local zone = nil
    if GetRealZoneText then
        zone = GetRealZoneText()
    end
    local money = char.money
    if GetMoney then
        money = GetMoney()
    end
    local restXP = char.restXP or 0
    if GetXPExhaustion then
        restXP = GetXPExhaustion() or 0
    end

    local gear = nil
    if char.Inventory then
        gear = CopyGearSnapshot(char.Inventory)
    end

    local history = EnsureLevelHistory(char)
    local deaths = history.meta.bracketDeathCount or 0

    DS:RecordLevelMilestone(char, {
        level = newLevel,
        reachedAt = time and time() or 0,
        playedTotal = DS:GetDerivedPlayedTotal(),
        playedSource = "backupTimer",
        zone = zone,
        money = money,
        restXP = restXP,
        gear = gear,
        deaths = deaths,
    })

    DS._pendingLevelUp = { level = newLevel }

    if RequestTimePlayed then
        DS:RequestTimePlayedSilently()
    end
end

function DS:ImportLevelHistoryFromQuestie(char, questieCharData)
    if not char or not questieCharData or not questieCharData.journey then return 0 end
    local history = EnsureLevelHistory(char)
    local imported = 0
    for _, entry in ipairs(questieCharData.journey) do
        if entry and entry.Event == "Level" and entry.NewLevel and entry.Timestamp then
            local level = entry.NewLevel
            if not history.milestones[level] then
                history.milestones[level] = { reachedAt = entry.Timestamp }
                char.dataVersions = char.dataVersions or {}
                char.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
                imported = imported + 1
            end
        end
    end
    return imported
end

local function BuildMilestoneFromRxpLevel(bracket)
    if not bracket or type(bracket) ~= "table" then return nil end
    local ts = bracket.timestamp or {}
    local playedTotal = ts.finished
    local playedLevel = nil
    if type(ts.started) == "number" and type(ts.finished) == "number" then
        playedLevel = ts.finished - ts.started
        if playedLevel < 0 then playedLevel = nil end
    end
    local reachedAt = DS._CalendarToUnix(ts.dateFinished)
    return {
        reachedAt = reachedAt,
        playedTotal = playedTotal,
        playedLevel = playedLevel,
        deaths = bracket.deaths,
    }
end

local function CountIncomingMilestoneFields(existing, incoming)
    if not incoming then return 0 end
    local added = 0
    for key, value in pairs(incoming) do
        if value ~= nil and (not existing or existing[key] == nil) then
            added = added + 1
        end
    end
    return added
end

function DS:ImportLevelHistoryFromRXP(char, rxpProfile)
    if not char or not rxpProfile then return 0 end
    local levels = rxpProfile.levels
    if (not levels or not next(levels)) and rxpProfile.levelsArchive then
        for _, archived in pairs(rxpProfile.levelsArchive) do
            if archived and next(archived) then
                levels = archived
                break
            end
        end
    end
    if not levels then return 0 end

    local history = EnsureLevelHistory(char)
    local imported = 0
    for bracketLevel, bracket in pairs(levels) do
        local bracketNum = tonumber(bracketLevel)
        if bracketNum and bracket then
            local levelReached = bracketNum + 1
            local incoming = BuildMilestoneFromRxpLevel(bracket)
            if incoming and CountIncomingMilestoneFields(history.milestones[levelReached], incoming) > 0 then
                history.milestones[levelReached] = DS._MergeMilestone(
                    history.milestones[levelReached],
                    incoming
                )
                char.dataVersions = char.dataVersions or {}
                char.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
                imported = imported + 1
            end
        end
    end
    return imported
end

local function BuildMilestoneFromNITLevel(entry, nextEntry)
    if not entry or type(entry) ~= "table" then return nil end
    local milestone = {}
    if entry.timestamp then
        milestone.reachedAt = entry.timestamp
    end
    local zone = entry.zoneName
    if not zone or zone == "" then
        zone = entry.subzoneName
    end
    if zone and zone ~= "" then
        milestone.zone = zone
    end
    if entry.gold then
        milestone.money = entry.gold
    end
    if entry.played and entry.playedSource ~= "backupTimer" then
        milestone.playedTotal = entry.played
        if nextEntry and nextEntry.played and nextEntry.playedSource ~= "backupTimer" then
            local delta = nextEntry.played - entry.played
            if delta > 0 then
                milestone.playedLevel = delta
            end
        end
    end
    return milestone
end

function DS:ImportLevelHistoryFromNIT(char, nitCharData)
    if not char or not nitCharData or not nitCharData.levelLog then return 0 end
    local levelLog = nitCharData.levelLog
    local history = EnsureLevelHistory(char)
    local imported = 0
    for levelKey, entry in pairs(levelLog) do
        local level = tonumber(levelKey)
        if level and entry then
            local nextEntry = levelLog[level + 1]
            local incoming = BuildMilestoneFromNITLevel(entry, nextEntry)
            if incoming and CountIncomingMilestoneFields(history.milestones[level], incoming) > 0 then
                history.milestones[level] = DS._MergeMilestone(
                    history.milestones[level],
                    incoming
                )
                char.dataVersions = char.dataVersions or {}
                char.dataVersions.levelHistory = DATA_VERSIONS.levelHistory
                imported = imported + 1
            end
        end
    end
    return imported
end

function DS._ResolveNITGlobal()
    local nit = rawget(_G, "NITdatabase")
    return nit and nit.global or nil
end

local function ParseQuestieCharacterKey(key)
    if type(key) ~= "string" then return nil, nil end
    local name, realm = key:match("^(.+) %- (.+)$")
    if not name or not realm then return nil, nil end
    return name, realm
end

function DS._SummarizeLevelHistory(char)
    local history = char and char.levelHistory
    if not history then
        return { milestones = 0, deaths = 0 }
    end
    local milestoneCount = 0
    for _ in pairs(history.milestones or {}) do
        milestoneCount = milestoneCount + 1
    end
    return {
        milestones = milestoneCount,
        deaths = #(history.deaths or {}),
    }
end

function DS._FormatLevelHistorySummary(char)
    local summary = DS._SummarizeLevelHistory(char)
    local name = (char and char.name) or "?"
    return string.format(
        "%s: %d level milestone(s), %d death event(s)",
        name,
        summary.milestones,
        summary.deaths
    )
end

local function IsRxpAddonEnabled()
    if testRxpAddonEnabled ~= nil then
        return testRxpAddonEnabled
    end
    for _, addonName in ipairs(RXP_ADDON_NAMES) do
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then
            return true
        end
        if IsAddOnLoaded and IsAddOnLoaded(addonName) then
            return true
        end
    end
    return rawget(_G, "RXPGuides") ~= nil
end

function DS._BuildRxpProfileKey(name, realm)
    if not name or not realm then return nil end
    return name .. " - " .. realm
end

local function GetRxpProfileKey()
    if not UnitName or not GetRealmName then return nil end
    local name = UnitName("player")
    local realm = GetRealmName()
    return DS._BuildRxpProfileKey(name, realm)
end

local function ResolveRxpProfileFromSavedVar(rxp)
    if not rxp or type(rxp) ~= "table" then return nil, nil end

    if rxp.profiles and type(rxp.profiles) == "table" then
        local profileKey = GetRxpProfileKey()
        if profileKey and rxp.profiles[profileKey] then
            return rxp.profiles[profileKey], "RXPCTrackingData.profiles[" .. profileKey .. "]"
        end
        if profileKey and rxp.profileKeys and rxp.profileKeys[profileKey] then
            local alias = rxp.profileKeys[profileKey]
            if rxp.profiles[alias] then
                return rxp.profiles[alias], "RXPCTrackingData.profiles[" .. alias .. "]"
            end
        end
        for key, profile in pairs(rxp.profiles) do
            if profile and profile.levels and next(profile.levels) then
                return profile, "RXPCTrackingData.profiles[" .. tostring(key) .. "]"
            end
        end
    end

    if rxp.profile and type(rxp.profile) == "table" then
        return rxp.profile, "RXPCTrackingData.profile"
    end

    if rxp.levels then
        return rxp, "RXPCTrackingData"
    end

    return nil, nil
end

function DS._ResolveRxpTrackingProfile()
    local rxp = rawget(_G, "RXPCTrackingData")
    return ResolveRxpProfileFromSavedVar(rxp)
end

local function ScheduleRxpBackfillRetry()
    if rxpBackfillRetryScheduled then return end
    if rxpBackfillRetryCount >= RXP_BACKFILL_MAX_RETRIES then return end
    if not C_Timer or not C_Timer.After then return end

    rxpBackfillRetryScheduled = true
    rxpBackfillRetryCount = rxpBackfillRetryCount + 1
    C_Timer.After(RXP_BACKFILL_RETRY_DELAY, function()
        rxpBackfillRetryScheduled = false
        if DS.TryRxpLevelHistoryImport then
            DS:TryRxpLevelHistoryImport()
        end
    end)
end

function DS:TryRxpLevelHistoryImport()
    local char = GetActiveChar()
    local charLabel = (char and char.name) or "unknown"

    if not char then
        LogLevelHistoryDebug("RXP: skip import (no active character)")
        return false
    end

    local rxpHistory = char.levelHistory
    if rxpHistory and rxpHistory.meta and rxpHistory.meta.importedRxpAt then
        LogLevelHistoryDebug(string.format(
            "RXP: skip import for %s (already completed at %s)",
            charLabel,
            tostring(rxpHistory.meta.importedRxpAt)
        ))
        return true
    end

    local rxpProfile, rxpSource = DS._ResolveRxpTrackingProfile()
    if rxpProfile then
        LogLevelHistoryDebug(string.format(
            "RXP: one-time import needed for %s; %s found, running import",
            charLabel,
            rxpSource
        ))
        local rxpImported = DS:ImportLevelHistoryFromRXP(char, rxpProfile) or 0
        if rxpImported > 0 then
            LogLevelHistoryDebug(string.format(
                "RXP: import complete for %s, added %d milestone(s)",
                charLabel,
                rxpImported
            ))
        else
            LogLevelHistoryDebug(string.format(
                "RXP: import complete for %s, no new milestones added",
                charLabel
            ))
        end
        local history = EnsureLevelHistory(char)
        history.meta.importedRxpAt = time and time() or 0
        return true
    end

    if IsRxpAddonEnabled() then
        local rxp = rawget(_G, "RXPCTrackingData")
        local profileCount = 0
        if rxp and rxp.profiles then
            for _ in pairs(rxp.profiles) do
                profileCount = profileCount + 1
            end
        end
        LogLevelHistoryDebug(string.format(
            "RXP: tracking data not ready yet for %s (profile key %s, %d saved profile(s)), will retry shortly",
            charLabel,
            tostring(GetRxpProfileKey()),
            profileCount
        ))
        ScheduleRxpBackfillRetry()
    else
        LogLevelHistoryDebug(string.format(
            "RXP: RestedXP not loaded for %s, will retry on a future login",
            charLabel
        ))
    end
    return false
end

function DS:RunLevelHistoryBackfill()
    LogLevelHistoryDebug("Checking level history import status")
    rxpBackfillRetryCount = 0
    rxpBackfillRetryScheduled = false
    local account = GetAccountData()
    local char = GetActiveChar()

    if not account.levelHistoryImport or not account.levelHistoryImport.questieAt then
        local questie = rawget(_G, "QuestieConfig")
        if questie and questie.char then
            LogLevelHistoryDebug("Questie: one-time import needed; QuestieConfig found, running import")
            account.Characters = account.Characters or {}
            local questieMilestones = 0
            local questieCharacters = 0
            for key, questieCharData in pairs(questie.char) do
                local name, realm = ParseQuestieCharacterKey(key)
                if name and realm then
                    local storedChar = DS:GetCharacter(name, realm)
                    local importTarget
                    if storedChar and DS:HasModuleData(storedChar, "character") then
                        importTarget = storedChar
                    else
                        importTarget = DS:GetOrphanLevelHistoryRecord(realm, name)
                    end
                    local imported = DS:ImportLevelHistoryFromQuestie(importTarget, questieCharData)
                    if imported > 0 then
                        questieCharacters = questieCharacters + 1
                        questieMilestones = questieMilestones + imported
                    end
                end
            end
            if questieMilestones > 0 then
                LogLevelHistoryDebug(string.format(
                    "Questie: import complete, added %d milestone(s) across %d character(s)",
                    questieMilestones,
                    questieCharacters
                ))
            else
                LogLevelHistoryDebug("Questie: import complete, no new milestones added")
            end
            account.levelHistoryImport = account.levelHistoryImport or {}
            account.levelHistoryImport.questieAt = time and time() or 0
        else
            LogLevelHistoryDebug("Questie: QuestieConfig not found, will retry on a future login")
        end
    else
        LogLevelHistoryDebug(string.format(
            "Questie: skip import (already completed at %s)",
            tostring(account.levelHistoryImport.questieAt)
        ))
    end

    if not char then
        LogLevelHistoryDebug("RXP: skip import (no active character)")
    else
        DS:TryRxpLevelHistoryImport()
    end

    if not account.levelHistoryImport or not account.levelHistoryImport.nitAt then
        local nitGlobal = DS._ResolveNITGlobal()
        if nitGlobal then
            LogLevelHistoryDebug("NIT: one-time import needed; NITdatabase found, running import")
            account.Characters = account.Characters or {}
            local nitMilestones = 0
            local nitCharacters = 0
            for realm, realmData in pairs(nitGlobal) do
                if type(realmData) == "table" and realmData.myChars then
                    for charName, nitCharData in pairs(realmData.myChars) do
                        local storedChar = DS:GetCharacter(charName, realm)
                        local importTarget
                        if storedChar and DS:HasModuleData(storedChar, "character") then
                            importTarget = storedChar
                        else
                            importTarget = DS:GetOrphanLevelHistoryRecord(realm, charName)
                        end
                        local imported = DS:ImportLevelHistoryFromNIT(importTarget, nitCharData)
                        if imported > 0 then
                            nitCharacters = nitCharacters + 1
                            nitMilestones = nitMilestones + imported
                        end
                    end
                end
            end
            if nitMilestones > 0 then
                LogLevelHistoryDebug(string.format(
                    "NIT: import complete, added %d milestone(s) across %d character(s)",
                    nitMilestones,
                    nitCharacters
                ))
            else
                LogLevelHistoryDebug("NIT: import complete, no new milestones added")
            end
            account.levelHistoryImport = account.levelHistoryImport or {}
            account.levelHistoryImport.nitAt = time and time() or 0
        else
            LogLevelHistoryDebug("NIT: NITdatabase not found, will retry on a future login")
        end
    else
        LogLevelHistoryDebug(string.format(
            "NIT: skip import (already completed at %s)",
            tostring(account.levelHistoryImport.nitAt)
        ))
    end

    LogLevelHistoryDebug("Stored: " .. DS._FormatLevelHistorySummary(char))
end

local rxpAddonFrame = CreateFrame and CreateFrame("Frame")
if rxpAddonFrame then
    rxpAddonFrame:RegisterEvent("ADDON_LOADED")
    rxpAddonFrame:SetScript("OnEvent", function(_, _, loadedName)
        if loadedName == "RXPGuides" or loadedName == "RXPGuides_TBC" then
            if DS.TryRxpLevelHistoryImport then
                DS:TryRxpLevelHistoryImport()
            end
        elseif loadedName == "NovaInstanceTracker" then
            if DS.RunLevelHistoryBackfill then
                DS:RunLevelHistoryBackfill()
            end
        end
    end)
end

function DS:DeleteAllLevelHistory()
    local account = GetAccountData()
    account.levelHistoryImport = nil
    if account.OrphanImports then
        account.OrphanImports.levelHistory = nil
    end
    local charactersCleared = 0
    for _, chars in pairs(account.Characters or {}) do
        for _, char in pairs(chars) do
            if char and char.levelHistory then
                char.levelHistory = nil
                charactersCleared = charactersCleared + 1
            end
            if char and char.dataVersions then
                char.dataVersions.levelHistory = nil
            end
        end
    end
    DS._pendingLevelUp = nil
    DS._playedBaseline = nil
    lastAttacker.name = nil
    lastAttacker.guid = nil
    LogLevelHistoryDebug(string.format(
        "Deleted all level history data (%d character(s) cleared, import gates reset)",
        charactersCleared
    ))
    return charactersCleared
end

DS.IsLevelHistoryEnabled = IsLevelHistoryEnabled
