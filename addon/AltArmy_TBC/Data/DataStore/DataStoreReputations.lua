-- AltArmy TBC — DataStore module: reputations.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local FACTION_STANDING_THRESHOLDS = { 0, 36000, 78000, 108000, 129000, 150000, 171000, 192000 }
-- Labels by threshold index (legacy number-only storage; not WoW standingID order)
local FACTION_STANDING_LABELS = {
    "Hated", "Friendly", "Unfriendly", "Neutral", "Hostile", "Honored", "Revered", "Exalted",
}

-- WoW GetFactionInfo standingID 1..8 → display name (v2 table storage)
local STANDING_ID_TO_LABEL = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

-- Legacy globals are absent on some clients (e.g. WoW Forever beta, interface 16001 — see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md); C_Reputation is the retail/Forever-shaped
-- replacement. Existence-checked, not version-checked, per Data/DESIGN.md "TBC Compatibility".
-- Checked dynamically on every call (not captured as load-time upvalues) so this keeps working
-- if a client ever defines these later than addon load, and so tests can stub the globals per-case.
local function API_GetNumFactions()
    if GetNumFactions then return GetNumFactions() end
    if C_Reputation and C_Reputation.GetNumFactions then return C_Reputation.GetNumFactions() end
    return nil
end

local function API_ExpandFactionHeader(index)
    if ExpandFactionHeader then return ExpandFactionHeader(index) end
    if C_Reputation and C_Reputation.ExpandFactionHeader then return C_Reputation.ExpandFactionHeader(index) end
end

local function API_CollapseFactionHeader(index)
    if CollapseFactionHeader then return CollapseFactionHeader(index) end
    if C_Reputation and C_Reputation.CollapseFactionHeader then return C_Reputation.CollapseFactionHeader(index) end
end

-- Returns the same tuple shape as the legacy GetFactionInfo(index):
-- name, description, standingID, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar,
-- isHeader, isCollapsed, hasRep, isWatched, isChild, factionID
-- The C_Reputation.GetFactionDataByIndex field names below are the public retail API's; Forever
-- characters' standings have been read through them since 2026-09 (Reputation tab, R| export).
local function API_GetFactionInfo(index)
    if GetFactionInfo then return GetFactionInfo(index) end
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
        local data = C_Reputation.GetFactionDataByIndex(index)
        if not data then return nil end
        return data.name, data.description, data.reaction, data.currentReactionThreshold,
            data.nextReactionThreshold, data.currentStanding, data.atWarWith, data.canToggleAtWar,
            data.isHeader, data.isCollapsed, data.hasRep, data.isWatched, data.isChild, data.factionID
    end
end

--- True when a faction-scan API (legacy or C_Reputation) is actually available. Used by DataStore.lua's
--- event dispatch so it doesn't call ScanReputations on clients (e.g. WoW Forever) where neither exists.
function DS.HasReputationApi()
    return (GetNumFactions ~= nil or (C_Reputation ~= nil and C_Reputation.GetNumFactions ~= nil))
        and (GetFactionInfo ~= nil or (C_Reputation ~= nil and C_Reputation.GetFactionDataByIndex ~= nil))
end

local factionHeadersState = {}
local function SaveFactionHeaders()
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
    local headerCount = 0
    if not DS.HasReputationApi() then return end
    for i = API_GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader, isCollapsed = API_GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if isCollapsed then
                API_ExpandFactionHeader(i)
                factionHeadersState[headerCount] = true
            end
        end
    end
end

local function RestoreFactionHeaders()
    local headerCount = 0
    if not DS.HasReputationApi() then return end
    for i = API_GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader = API_GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if factionHeadersState[headerCount] then
                API_CollapseFactionHeader(i)
            end
        end
    end
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
end

local function GetReputationLimits(earned)
    local bottom, top = 0, 42000
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if earned >= FACTION_STANDING_THRESHOLDS[i] then
            bottom = FACTION_STANDING_THRESHOLDS[i]
        end
    end
    for i = 1, #FACTION_STANDING_THRESHOLDS - 1 do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            top = FACTION_STANDING_THRESHOLDS[i + 1]
            break
        end
    end
    if top == 0 then top = 42000 end
    return bottom, top
end
DS._GetReputationLimits = GetReputationLimits

--- Progress line for reputation cell: "repEarned/nextSpan" or "Max" when span invalid (non-Exalted).
--- Exalted uses the same cur/span as other tiers; when span is missing (capped API), TBC uses 0–1000 in Exalted.
--- @param standing string|nil
--- @param repEarned number
--- @param nextLevel number
--- @return string
--- Abbreviate a reputation amount as "<n>k", rounded to the nearest 1k.
local function FormatRepK(value)
    local v = math.floor(tonumber(value) or 0)
    local k = math.floor(v / 1000 + 0.5)
    return tostring(k) .. "k"
end

function DS.FormatReputationProgressText(standing, repEarned, nextLevel)
    local span = tonumber(nextLevel) or 0
    local cur = math.floor(tonumber(repEarned) or 0)
    if span > 0 then
        return FormatRepK(cur) .. "/" .. FormatRepK(span)
    end
    if standing == "Exalted" then
        return FormatRepK(cur) .. "/" .. FormatRepK(1000)
    end
    return "Max"
end

--- Percent-to-next-level text (e.g. "81%"), rate clamped to 0..100 and rounded to nearest 1%.
--- A maxed Exalted faction (rounds to 100%) shows "Max" instead.
function DS.FormatReputationPercentText(rate, standing)
    local pct = tonumber(rate) or 0
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    local rounded = math.floor(pct + 0.5)
    if standing == "Exalted" and rounded >= 100 then
        return "Max"
    end
    return tostring(rounded) .. "%"
end

--- Exact (non-abbreviated) progress text for tooltips.
function DS.FormatReputationProgressTextExact(standing, repEarned, nextLevel)
    local span = tonumber(nextLevel) or 0
    local cur = math.floor(tonumber(repEarned) or 0)
    if span > 0 then
        return tostring(cur) .. "/" .. tostring(span)
    end
    if standing == "Exalted" then
        return tostring(cur) .. "/1000"
    end
    return "Max"
end

-- Bar RGB per standing label (WoW-like friendly / neutral / hostile palette); used when FACTION_BAR_COLORS unavailable.
local STANDING_BAR_COLORS = {
    Hated = { 0.8, 0.09, 0.09 },
    Hostile = { 1, 0.25, 0 },
    Unfriendly = { 0.9, 0.45, 0 },
    Neutral = { 0.9, 0.85, 0.2 },
    Friendly = { 0.2, 0.75, 0.1 },
    Honored = { 0.1, 0.6, 0.85 },
    Revered = { 0.35, 0.2, 0.95 },
    Exalted = { 0.5, 0.2, 0.75 },
}

-- Standing name -> WoW standing index (for FACTION_BAR_COLORS[1..8] when present).
local STANDING_NAME_TO_ID = {
    Hated = 1,
    Hostile = 2,
    Unfriendly = 3,
    Neutral = 4,
    Friendly = 5,
    Honored = 6,
    Revered = 7,
    Exalted = 8,
}

--- RGB 0..1 for reputation bar fill from standing name.
--- @param standing string|nil
--- @return number r, number g, number b
function DS.GetReputationBarColorsForStanding(standing)
    local key = standing
    if type(key) == "string" then
        key = key:gsub("^%s+", ""):gsub("%s+$", "")
    end
    local sid = type(key) == "string" and STANDING_NAME_TO_ID[key]
    if sid and FACTION_BAR_COLORS and FACTION_BAR_COLORS[sid] then
        local c = FACTION_BAR_COLORS[sid]
        return c.r or 0.5, c.g or 0.5, c.b or 0.5
    end
    if type(key) == "string" and STANDING_BAR_COLORS[key] then
        local t = STANDING_BAR_COLORS[key]
        return t[1], t[2], t[3]
    end
    return 0.5, 0.5, 0.5
end

--- SavedVariables may use string keys; scans use numeric keys — check both.
local function GetStoredFactionDisplayName(nameMap, factionID)
    if not nameMap then
        return nil
    end
    local n = tonumber(factionID)
    if not n or n < 1 then
        return nil
    end
    local s = nameMap[n]
    if type(s) == "string" and s ~= "" then
        return s
    end
    s = nameMap[tostring(n)]
    if type(s) == "string" and s ~= "" then
        return s
    end
    return nil
end

--- Client APIs that resolve a faction ID to a display name even if this character has not discovered it.
local function TryFactionNameFromGameAPI(factionID)
    if not factionID or factionID <= 0 then
        return nil
    end
    if type(GetFactionInfoByID) == "function" then
        local ok, name = pcall(function()
            return GetFactionInfoByID(factionID)
        end)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    local CR = C_Reputation
    if CR and type(CR.GetFactionDataByID) == "function" then
        local ok, data = pcall(function()
            return CR.GetFactionDataByID(factionID)
        end)
        if ok and type(data) == "table" then
            local nm = data.name or data.factionName
            if type(nm) == "string" and nm ~= "" then
                return nm
            end
        end
    end
    return nil
end

--- True if saved rep data is worth showing: v2 snapshot only (legacy v1 scalars ignored for the grid).
--- Among v2 rows, omit "Neutral at bottom of tier" with no progress (default capitals in the client list).
local function reputationRawQualifiesForUnion(raw)
    if raw == nil then
        return false
    end
    if type(raw) == "number" then
        return false
    end
    if type(raw) == "table" then
        if tonumber(raw.s) == nil then
            return false
        end
        local s = tonumber(raw.s) or 4
        local e = tonumber(raw.e) or 0
        local b = tonumber(raw.b) or 0
        if s ~= 4 then
            return true
        end
        return e > b
    end
    return false
end

--- Collect faction IDs from v2 rep snapshots only (at least one alt); legacy v1 scalars are skipped.
local function CollectFactionIdsFromSavedCharacters()
    local ids = {}
    local data = AltArmyTBC_Data
    if not data or not data.Characters then
        return ids
    end
    for _, realmTbl in pairs(data.Characters) do
        for _, char in pairs(realmTbl) do
            local reps = char and char.Reputations
            if reps then
                for fid, raw in pairs(reps) do
                    local n = tonumber(fid)
                    if n and n > 0 and reputationRawQualifiesForUnion(raw) then
                        ids[n] = true
                    end
                end
            end
        end
    end
    return ids
end

--- Faction rows: union of faction IDs where at least one alt has v2 rep data (non-legacy), excluding
--- v2 Neutral with zero progress within that tier (still stored by scans but omitted from the grid).
--- The live GetFactionInfo loop only fills ReputationFactionNames for labels. Sorted A–Z by name.
--- @return table[] { { factionID = number, name = string }, ... }
function DS:GetCurrentReputationFactionRows()
    AltArmyTBC_Data.ReputationFactionNames = AltArmyTBC_Data.ReputationFactionNames or {}
    local nameMap = AltArmyTBC_Data.ReputationFactionNames

    local ids = CollectFactionIdsFromSavedCharacters()

    -- Refresh display names from the current client's rep list (does not add factions to the grid).
    if DS.HasReputationApi() then
        local n = API_GetNumFactions()
        if n and n >= 1 then
            for i = 1, n do
                local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID =
                    API_GetFactionInfo(i)
                if not isHeader and factionID and factionID > 0 then
                    if name and name ~= "" then
                        nameMap[factionID] = name
                    end
                end
            end
        end
    end

    local rows = {}
    for fid in pairs(ids) do
        local label = GetStoredFactionDisplayName(nameMap, fid)
        if not label then
            label = TryFactionNameFromGameAPI(fid)
            if label then
                nameMap[fid] = label
            end
        end
        if not label or label == "" then
            label = "#" .. tostring(fid)
        end
        rows[#rows + 1] = {
            factionID = fid,
            name = label,
        }
    end

    table.sort(rows, function(a, b)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        if na ~= nb then
            return na < nb
        end
        return (a.factionID or 0) < (b.factionID or 0)
    end)

    return rows
end

function DS:ScanReputations()
    local char = GetCurrentCharTable()
    if not char then return end
    if not DS.HasReputationApi() then return end
    AltArmyTBC_Data.ReputationFactionNames = AltArmyTBC_Data.ReputationFactionNames or {}
    local factionNames = AltArmyTBC_Data.ReputationFactionNames
    char.Reputations = char.Reputations or {}
    for k in pairs(char.Reputations) do char.Reputations[k] = nil end
    SaveFactionHeaders()
    for i = 1, API_GetNumFactions() do
        local name, _, standingID, bottomValue, topValue, earnedValue, _, _, isHeader, _, _, _, _, factionID =
            API_GetFactionInfo(i)
        if not isHeader and factionID and factionID > 0 then
            if name and name ~= "" then
                factionNames[factionID] = name
            end
            local snapshot = {
                s = tonumber(standingID) or 4,
                e = tonumber(earnedValue) or 0,
                b = tonumber(bottomValue) or 0,
                t = tonumber(topValue) or 0,
            }
            -- Skip storing default Neutral/no-progress rows (still listed by the client for everyone).
            if reputationRawQualifiesForUnion(snapshot) then
                char.Reputations[factionID] = snapshot
            end
        end
    end
    RestoreFactionHeaders()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.reputations = DATA_VERSIONS.reputations
end

function DS:GetReputations(char)
    return (char and char.Reputations) or {}
end

function DS:GetReputationInfo(char, factionID)
    if not char or not char.Reputations or not factionID then return nil, 0, 0, 0 end
    local raw = char.Reputations[factionID]
    if raw == nil then return nil, 0, 0, 0 end

    if type(raw) == "table" then
        local sid = raw.s
        local e = tonumber(raw.e) or 0
        local b = tonumber(raw.b) or 0
        local t = tonumber(raw.t) or 0
        local standing = (type(sid) == "number" and STANDING_ID_TO_LABEL[sid]) or nil
        if not standing then return nil, 0, 0, 0 end
        local repEarned = e - b
        local nextLevel = t - b
        if nextLevel < 0 then nextLevel = 0 end
        local rate = (nextLevel > 0) and (repEarned / nextLevel * 100) or 100
        return standing, repEarned, nextLevel, rate
    end

    local earned = tonumber(raw) or 0
    local bottom, top = GetReputationLimits(earned)
    local standing = FACTION_STANDING_LABELS[1]
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            standing = FACTION_STANDING_LABELS[i] or standing
            break
        end
    end
    local repEarned = earned - bottom
    local nextLevel = top - bottom
    local rate = (nextLevel > 0) and (repEarned / nextLevel * 100) or 100
    return standing, repEarned, nextLevel, rate
end

function DS:IterateReputations(char, callback)
    if not char or not char.Reputations or not callback then return end
    for factionID, raw in pairs(char.Reputations) do
        local standing, repEarned, nextLevel, rate = self:GetReputationInfo(char, factionID)
        local earned
        if type(raw) == "table" then
            earned = tonumber(raw.e) or 0
        else
            earned = tonumber(raw) or 0
        end
        if callback(factionID, earned, standing, repEarned, nextLevel, rate) then
            return
        end
    end
end
