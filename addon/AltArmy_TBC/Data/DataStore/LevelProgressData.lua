-- AltArmy TBC — Read-only accessors for level graph chart data.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

AltArmy.LevelProgressData = AltArmy.LevelProgressData or {}

local LPD = AltArmy.LevelProgressData
local DS = AltArmy.DataStore

local NEUTRAL_COLOR = { r = 0.7, g = 0.7, b = 0.7 }

LPD.AXIS_MIN_LEVEL = 0
LPD.AXIS_MAX_LEVEL = (DS.MAX_LEVEL) or 70
LPD.METRIC_TIME_PER_LEVEL = "timePerLevel"
LPD.METRIC_CUMULATIVE_PLAYED = "cumulativePlayed"
local FIRST_RECORDED_LEVEL = 1

--- @param metric string|nil
--- @return string
function LPD.NormalizeMetric(metric)
    if metric == LPD.METRIC_CUMULATIVE_PLAYED then
        return LPD.METRIC_CUMULATIVE_PLAYED
    end
    return LPD.METRIC_TIME_PER_LEVEL
end

--- Dropdown entries for Graphs metric selector.
--- @return table[] { id, label }
function LPD.GetMetricEntries()
    return {
        { id = LPD.METRIC_TIME_PER_LEVEL, label = "Time per level" },
        { id = LPD.METRIC_CUMULATIVE_PLAYED, label = "Cumulative play time" },
    }
end

local GRAPH_DEBUG_PREFIX = "|cff00ccff[Alt Army:Graph]|r "
local WATCH_NAMES_LOWER = {
    -- frellbank = true,
    -- frellbanq = true,
    -- frellcloth = true,
}

--- Derive seconds spent on a level from milestone fields.
--- @param milestone table Milestone at level reached.
--- @param previousPlayedTotal number|nil playedTotal from previous level milestone.
--- @return number|nil
function LPD._DeriveSeconds(milestone, previousPlayedTotal)
    if not milestone or type(milestone) ~= "table" then return nil end

    if type(milestone.playedLevel) == "number" and milestone.playedLevel > 0 then
        return milestone.playedLevel
    end

    local playedTotal = milestone.playedTotal
    if type(playedTotal) ~= "number" then return nil end

    if type(previousPlayedTotal) ~= "number" then
        return playedTotal > 0 and playedTotal or nil
    end

    local delta = playedTotal - previousPlayedTotal
    if delta <= 0 then return nil end
    return delta
end

local function SortedMilestoneLevels(milestones)
    local levels = {}
    if not milestones then return levels end
    for level in pairs(milestones) do
        if type(level) == "number" then
            levels[#levels + 1] = level
        end
    end
    table.sort(levels)
    return levels
end

local function AppendSeriesPoint(series, toLevel, fromLevel, totalSeconds)
    local levelSpan = toLevel - fromLevel
    if levelSpan <= 0 or totalSeconds <= 0 then return false end

    series[#series + 1] = {
        level = toLevel,
        seconds = totalSeconds / levelSpan,
        fromLevel = fromLevel,
        toLevel = toLevel,
        totalSeconds = totalSeconds,
        spansGap = levelSpan > 1,
    }
    return true
end

--- Build chart points from milestones, spanning missing levels from the last
--- available milestone (or level 1 with zero baseline for the first point).
--- @param milestones table
--- @return table[]
function LPD._BuildSeriesFromMilestones(milestones)
    local levels = SortedMilestoneLevels(milestones)
    local series = {}
    local lastLevel = nil
    local lastPlayedTotal = nil

    for _, level in ipairs(levels) do
        local milestone = milestones[level]
        if milestone and type(milestone.playedTotal) == "number" then
            local fromLevel = lastLevel or FIRST_RECORDED_LEVEL
            local baseTotal = lastPlayedTotal or 0
            local totalSeconds = milestone.playedTotal - baseTotal
            if AppendSeriesPoint(series, level, fromLevel, totalSeconds) then
                lastLevel = level
            end
            lastPlayedTotal = milestone.playedTotal
        elseif milestone and type(milestone.playedLevel) == "number" and milestone.playedLevel > 0 then
            if not lastLevel or level - lastLevel == 1 then
                local fromLevel = lastLevel or (level - 1)
                if AppendSeriesPoint(series, level, fromLevel, milestone.playedLevel) then
                    lastLevel = level
                end
            end
        end
    end

    return series
end

local function AppendCumulativePoint(series, toLevel, fromLevel, cumulative, segmentSeconds)
    local levelSpan = toLevel - fromLevel
    if levelSpan <= 0 or not cumulative or cumulative <= 0 then return false end
    if not segmentSeconds or segmentSeconds <= 0 then return false end

    series[#series + 1] = {
        level = toLevel,
        seconds = cumulative,
        fromLevel = fromLevel,
        toLevel = toLevel,
        totalSeconds = segmentSeconds,
        spansGap = levelSpan > 1,
    }
    return true
end

--- Build cumulative /played series from milestones (Y = playedTotal at level).
--- @param milestones table
--- @return table[]
function LPD._BuildCumulativeSeriesFromMilestones(milestones)
    local levels = SortedMilestoneLevels(milestones)
    local series = {}
    local lastLevel = nil
    local lastCumulative = 0

    for _, level in ipairs(levels) do
        local milestone = milestones[level]
        if milestone and type(milestone.playedTotal) == "number" and milestone.playedTotal > 0 then
            local fromLevel = lastLevel or FIRST_RECORDED_LEVEL
            local cumulative = milestone.playedTotal
            local segmentSeconds = cumulative - lastCumulative
            if AppendCumulativePoint(series, level, fromLevel, cumulative, segmentSeconds) then
                lastLevel = level
                lastCumulative = cumulative
            end
        elseif milestone and type(milestone.playedLevel) == "number" and milestone.playedLevel > 0 then
            if not lastLevel or level - lastLevel == 1 then
                local fromLevel = lastLevel or (level - 1)
                local cumulative = lastCumulative + milestone.playedLevel
                if AppendCumulativePoint(series, level, fromLevel, cumulative, milestone.playedLevel) then
                    lastLevel = level
                    lastCumulative = cumulative
                end
            end
        end
    end

    return series
end

local function CountUsableMilestones(milestones)
    return #LPD._BuildSeriesFromMilestones(milestones)
end

--- Build sorted chart series for one character.
--- @param name string
--- @param realm string
--- @param metric string|nil LPD.METRIC_TIME_PER_LEVEL or LPD.METRIC_CUMULATIVE_PLAYED
--- @param linkId string|nil the linked account a row's character came from (nil: ours)
--- @return table[] { level, seconds, fromLevel, toLevel, totalSeconds, spansGap }
function LPD.GetSeriesForCharacter(name, realm, metric, linkId)
    local char = DS:GetCharacterFor(name, realm, linkId)
    if not char or not char.levelHistory or not char.levelHistory.milestones then
        return {}
    end

    metric = LPD.NormalizeMetric(metric)
    if metric == LPD.METRIC_CUMULATIVE_PLAYED then
        return LPD._BuildCumulativeSeriesFromMilestones(char.levelHistory.milestones)
    end
    return LPD._BuildSeriesFromMilestones(char.levelHistory.milestones)
end

local function HasAnyMilestone(milestones)
    return milestones and next(milestones) ~= nil
end

local function IsGraphDebugEnabled()
    local Dbg = AltArmy and AltArmy.Debug
    return Dbg and Dbg.IsLevelHistoryEnabled and Dbg.IsLevelHistoryEnabled()
end

local function LogGraphDebug(msg)
    if not IsGraphDebugEnabled() then return end
    local Dbg = AltArmy and AltArmy.Debug
    if Dbg and Dbg.NotifyChat then
        Dbg.NotifyChat(GRAPH_DEBUG_PREFIX .. tostring(msg))
    end
end

local function IsWatchedName(name)
    return name and WATCH_NAMES_LOWER[name:lower()] == true
end

local function FormatMilestoneLevels(milestones)
    if not milestones then return "none" end
    local levels = {}
    for level in pairs(milestones) do
        if type(level) == "number" then
            levels[#levels + 1] = level
        end
    end
    table.sort(levels)
    if #levels == 0 then return "none" end
    local parts = {}
    for _, level in ipairs(levels) do
        parts[#parts + 1] = tostring(level)
    end
    return table.concat(parts, ",")
end

local function GetUsableMilestoneCountForChar(char)
    if not char then return 0 end
    local milestones = char.levelHistory and char.levelHistory.milestones
    if not HasAnyMilestone(milestones) then return 0 end
    return CountUsableMilestones(milestones)
end

local function GetInsufficientDetail(char, usableCount, rawCount)
    if not char.levelHistory then
        return "no_level_history"
    end
    if rawCount == 0 then
        return "no_milestones"
    end
    if usableCount == 0 then
        return "no_usable_milestones"
    end
    return "partial"
end

--- Explain why a character lands in compare, insufficient, or neither sidebar bucket.
--- @return string bucket, number usableCount, number rawMilestoneCount, string|nil detail
function LPD._ClassifySelectorBucket(name, realm)
    local char = DS:GetCharacter(name, realm)
    if not char then
        return "not_in_datastore", 0, 0, nil
    end
    local milestones = char.levelHistory and char.levelHistory.milestones
    local rawCount = 0
    if milestones then
        for _ in pairs(milestones) do
            rawCount = rawCount + 1
        end
    end
    local usableCount = GetUsableMilestoneCountForChar(char)
    if usableCount >= 2 then
        return "compare", usableCount, rawCount, nil
    end
    return "insufficient", usableCount, rawCount, GetInsufficientDetail(char, usableCount, rawCount)
end

function LPD.DebugLogSelectorEligibility()
    if not IsGraphDebugEnabled() then return end

    LogGraphDebug("Selector debug: scanning character list for compare / insufficient buckets")

    local SD = AltArmy.SummaryData
    if not SD or not SD.GetCharacterList then
        LogGraphDebug("SummaryData.GetCharacterList unavailable")
        return
    end

    local summaryList = SD.GetCharacterList()
    local seenWatchNames = {}

    for _, entry in ipairs(summaryList) do
        local bucket, usableCount, rawCount, detail = LPD._ClassifySelectorBucket(entry.name, entry.realm)
        if IsWatchedName(entry.name) then
            seenWatchNames[entry.name:lower()] = true
            local char = DS:GetCharacter(entry.name, entry.realm)
            local milestoneLevels = FormatMilestoneLevels(
                char and char.levelHistory and char.levelHistory.milestones
            )
            local detailText = detail and (" detail=" .. detail) or ""
            LogGraphDebug(string.format(
                "WATCH %s-%s: in SummaryData=yes bucket=%s%s usable=%d rawMilestones=%d levels=[%s]",
                entry.name,
                entry.realm or "?",
                bucket,
                detailText,
                usableCount,
                rawCount,
                milestoneLevels
            ))
        end
    end

    for watchName in pairs(WATCH_NAMES_LOWER) do
        if not seenWatchNames[watchName] then
            LogGraphDebug(string.format(
                "WATCH %s: not present in SummaryData.GetCharacterList()",
                watchName
            ))
            if DS.ForEachCharacter then
                DS:ForEachCharacter(function(realm, charName, charData)
                        local storedName = DS:GetCharacterName(charData) or charName
                        if storedName:lower() == watchName then
                            local bucket, usableCount, rawCount, detail = LPD._ClassifySelectorBucket(storedName, realm)
                            local detailText = detail and (" detail=" .. detail) or ""
                            LogGraphDebug(string.format(
                                "WATCH %s: DataStore %s@%s bucket=%s%s usable=%d raw=%d levels=[%s]",
                                watchName,
                                charName,
                                realm,
                                bucket,
                                detailText,
                                usableCount,
                                rawCount,
                                FormatMilestoneLevels(charData.levelHistory and charData.levelHistory.milestones)
                            ))
                        end
                end)
            end
        end
    end

    local compareList = LPD.GetCharactersWithHistory()
    local insufficientList = LPD.GetCharactersWithInsufficientHistory()
    LogGraphDebug(string.format(
        "Selector totals: compare=%d insufficient=%d summaryEntries=%d",
        #compareList,
        #insufficientList,
        #summaryList
    ))
end

local function BuildCharacterEntry(entry, char)
    return {
        name = entry.name,
        realm = entry.realm,
        linkId = entry.linkId,
        classFile = entry.classFile or (char and char.classFile) or "",
        level = entry.level or (char and char.level) or 0,
    }
end

local function SortCharacterEntries(list)
    table.sort(list, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
end

local function CollectCharactersByMilestoneCount(minCount, maxExclusive)
    local out = {}
    local SD = AltArmy.SummaryData
    if not SD or not SD.GetCharacterList then
        return out
    end

    for _, entry in ipairs(SD.GetCharacterList()) do
        local char = DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
        local milestones = char and char.levelHistory and char.levelHistory.milestones
        if HasAnyMilestone(milestones) then
            local count = CountUsableMilestones(milestones)
            if count >= minCount and (not maxExclusive or count < maxExclusive) then
                out[#out + 1] = BuildCharacterEntry(entry, char)
            end
        end
    end

    SortCharacterEntries(out)
    return out
end

--- Characters with enough milestone data to draw a line (>= 2 points).
--- @return table[] { name, realm, classFile, level }
function LPD.GetCharactersWithHistory()
    return CollectCharactersByMilestoneCount(2, nil)
end

--- Tracked characters with fewer than 2 usable milestones (including none at all).
--- @return table[] { name, realm, classFile, level }
function LPD.GetCharactersWithInsufficientHistory()
    local out = {}
    local SD = AltArmy.SummaryData
    if not SD or not SD.GetCharacterList then
        return out
    end

    for _, entry in ipairs(SD.GetCharacterList()) do
        local char = DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
        if char and GetUsableMilestoneCountForChar(char) < 2 then
            out[#out + 1] = BuildCharacterEntry(entry, char)
        end
    end

    SortCharacterEntries(out)
    return out
end

--- Fixed horizontal axis domain for the level graph.
--- @return number minLevel, number maxLevel, number range
function LPD.GetAxisRange()
    local minLevel = LPD.AXIS_MIN_LEVEL
    local maxLevel = LPD.AXIS_MAX_LEVEL
    return minLevel, maxLevel, maxLevel - minLevel
end

--- Prepare a series for rendering, including an optional leading dashed segment
--- when the first point spans multiple levels from the level-1 baseline.
--- @param series table[] { level, seconds, fromLevel, toLevel, totalSeconds, spansGap }
--- @return table { usable, leadingGap|nil }
function LPD.PrepareDrawableSeries(series)
    if not series or #series == 0 then
        return { usable = {}, leadingGap = nil }
    end

    local first = series[1]
    local leadingGap = nil
    if first.spansGap and first.fromLevel == FIRST_RECORDED_LEVEL then
        leadingGap = {
            fromLevel = first.fromLevel,
            toLevel = first.toLevel,
            toY = first.seconds,
            totalSeconds = first.totalSeconds,
        }
    end

    return {
        usable = series,
        leadingGap = leadingGap,
    }
end

--- @param classFile string|nil
--- @return number r, number g, number b
function LPD.GetClassColor(classFile)
    local CC = AltArmy.ClassColor
    if CC and CC.getRGB then
        return CC.getRGB(classFile)
    end
    return NEUTRAL_COLOR.r, NEUTRAL_COLOR.g, NEUTRAL_COLOR.b
end
