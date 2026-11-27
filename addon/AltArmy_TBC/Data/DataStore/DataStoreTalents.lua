-- AltArmy TBC — Talent / spec tracking for gear upgrade comparisons.
-- Requires DataStore.lua loaded first.
-- luacheck: globals GetNumTalentTabs GetTalentTabInfo PlayerTalentFrame GetSpecialization
-- luacheck: globals GetSpecializationInfo C_SpecializationInfo C_EventUtils C_ClassTalents C_Traits C_Timer

if not AltArmy or not AltArmy.DataStore then return end

AltArmy.DataStoreTalents = AltArmy.DataStoreTalents or {}

local DS = AltArmy.DataStore
local DT = AltArmy.DataStoreTalents
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local SPEC_KEYS_BY_CLASS = {
    WARRIOR = { "arms", "fury", "protection" },
    PALADIN = { "holy", "protection", "retribution" },
    HUNTER = { "beast", "marksmanship", "survival" },
    ROGUE = { "assassination", "combat", "subtlety" },
    PRIEST = { "discipline", "holy", "shadow" },
    SHAMAN = { "elemental", "enhancement", "restoration" },
    MAGE = { "arcane", "fire", "frost" },
    WARLOCK = { "affliction", "demonology", "destruction" },
    DRUID = { "balance", "feral", "restoration" },
}

-- Legacy GetNumTalentTabs/GetTalentTabInfo are absent on some clients (e.g. WoW Forever, interface
-- 16001 — confirmed via /altarmy debug apicheck, see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md).
-- C_SpecializationInfo.GetSpecialization/GetSpecializationInfo (the retail-shaped replacement,
-- per Thaoky's DataStore_Talents ScanTalents_Retail) is the fallback. Spec IDs below are Blizzard's
-- canonical, expansion-stable specialization IDs (unchanged since Mists of Pandaria), used instead
-- of matching on the (localized) spec name string or assuming index order lines up with TBC's tabs.
-- Druid's classic "Feral Combat" tree covers both the cat (DPS) and bear (tank) builds under a
-- single PawnScales key; retail's later Feral(103)/Guardian(104) split doesn't exist as a TBC
-- distinction, so both IDs map to the one "feral" key already used by SPEC_KEYS_BY_CLASS below.
local SPEC_ID_TO_KEY_BY_CLASS = {
    WARRIOR = { [71] = "arms", [72] = "fury", [73] = "protection" },
    PALADIN = { [65] = "holy", [66] = "protection", [70] = "retribution" },
    HUNTER = { [253] = "beast", [254] = "marksmanship", [255] = "survival" },
    ROGUE = { [259] = "assassination", [260] = "combat", [261] = "subtlety" },
    PRIEST = { [256] = "discipline", [257] = "holy", [258] = "shadow" },
    SHAMAN = { [262] = "elemental", [263] = "enhancement", [264] = "restoration" },
    MAGE = { [62] = "arcane", [63] = "fire", [64] = "frost" },
    WARLOCK = { [265] = "affliction", [266] = "demonology", [267] = "destruction" },
    DRUID = { [102] = "balance", [103] = "feral", [104] = "feral", [105] = "restoration" },
}

local LEVELING_SPEC_BY_CLASS = {
    WARRIOR = "fury",
    PALADIN = "retribution",
    HUNTER = "beast",
    ROGUE = "combat",
    PRIEST = "shadow",
    SHAMAN = "enhancement",
    MAGE = "frost",
    WARLOCK = "affliction",
    DRUID = "feral",
}

local function normalizeClassFile(classFile)
    return (classFile or ""):upper()
end

--- Tab index (1-based) with the most points spent, or nil if none spent.
function DT.DerivePrimaryTabIndex(tabs)
    if not tabs or #tabs == 0 then return nil end
    local bestIdx, bestPts = nil, 0
    for i = 1, #tabs do
        local pts = tonumber(tabs[i]) or 0
        if pts > bestPts then
            bestPts = pts
            bestIdx = i
        end
    end
    if bestPts <= 0 then return nil end
    return bestIdx
end

function DT.GetSpecKeyForTab(classFile, tabIndex)
    classFile = normalizeClassFile(classFile)
    local list = SPEC_KEYS_BY_CLASS[classFile]
    if not list or not tabIndex then return nil end
    return list[tabIndex]
end

function DT.GetSpecKeyForSpecId(classFile, specId)
    classFile = normalizeClassFile(classFile)
    local map = SPEC_ID_TO_KEY_BY_CLASS[classFile]
    if not map or not specId then return nil end
    return map[specId]
end

function DT.GetLevelingSpecKey(classFile)
    return LEVELING_SPEC_BY_CLASS[normalizeClassFile(classFile)] or "unknown"
end

--- Level at which TBC Classic characters gain their first talent point / the Talents tab unlocks.
DT.TALENT_UNLOCK_LEVEL = 10

--- Whether a character is high enough level to have any talents to speak of.
function DT.IsTalentEligible(char)
    local level = tonumber(char and char.level) or 0
    return level >= DT.TALENT_UNLOCK_LEVEL
end

function DT.HasTalentData(char)
    if not char or not char.talents or char.talents.tabs == nil then
        return false
    end
    return true
end

--- Returns specKey, isKnown (true when talent data was scanned and primary tab is decisive).
function DT.ResolveSpecKey(char)
    if not char then
        return "unknown", false
    end
    local classFile = normalizeClassFile(char.classFile)
    if DT.HasTalentData(char) and char.talents.specKey then
        local primary = char.talents.primary
        if primary and primary > 0 then
            return char.talents.specKey, true
        end
    end
    return DT.GetLevelingSpecKey(classFile), false
end

function DS:GetCharacterSpec(char)
    return DT.ResolveSpecKey(char)
end

function DS:HasTalentData(char)
    return DT.HasTalentData(char)
end

local function readTalentTabs()
    if not GetNumTalentTabs or not GetTalentTabInfo then return nil end
    local numTabs = GetNumTalentTabs()
    if not numTabs or numTabs <= 0 then return nil end
    local tabs = {}
    for i = 1, numTabs do
        local _, _, _, _, pointsSpent = GetTalentTabInfo(i)
        tabs[i] = tonumber(pointsSpent) or 0
    end
    return tabs
end

-- Resolved dynamically on every call (not captured as load-time upvalues) so this keeps working if
-- a client ever defines these later than addon load, and so tests can stub the globals per-case —
-- same convention as DataStoreReputations.lua's API_* wrappers. C_SpecializationInfo is the current
-- (2026) namespaced form; the bare globals are kept as the fallback since they still resolve today.
local function API_GetSpecialization()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    if GetSpecialization then return GetSpecialization() end
    return nil
end

local function API_GetSpecializationInfo(specIndex)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    if GetSpecializationInfo then return GetSpecializationInfo(specIndex) end
    return nil
end

--- True when the modern specialization API (legacy global or C_SpecializationInfo) is available.
--- Used both by ScanTalents' fallback and exposed for /altarmy debug apicheck-style diagnostics.
function DT.HasSpecializationApi()
    local hasGetSpec = GetSpecialization ~= nil
        or (C_SpecializationInfo ~= nil and C_SpecializationInfo.GetSpecialization ~= nil)
    local hasGetSpecInfo = GetSpecializationInfo ~= nil
        or (C_SpecializationInfo ~= nil and C_SpecializationInfo.GetSpecializationInfo ~= nil)
    return hasGetSpec and hasGetSpecInfo
end

--- Modern-API fallback for clients (e.g. WoW Forever) where GetNumTalentTabs/GetTalentTabInfo don't
--- exist. Returns specKey, specIndex, apiPresent — specKey/specIndex are nil until a spec has
--- actually been chosen (or the specID isn't one of ours, e.g. an unexpected 4th spec); apiPresent
--- tells the caller whether this path could run at all, so "API missing" and "API present but no
--- spec picked yet" stay distinguishable the same way the legacy tabs path already distinguishes them.
local function readSpecializationSpec(classFile)
    if not DT.HasSpecializationApi() then return nil, nil, false end
    local specIndex = API_GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil, nil, true end
    local specId = API_GetSpecializationInfo(specIndex)
    return DT.GetSpecKeyForSpecId(classFile, specId), specIndex, true
end

-- WoW Forever has no talent-tab API and a single placeholder specialization per class (Warrior:
-- 1491, unnamed, "DAMAGER"), so the spec comes from where the points went. Its class talents are a
-- trait tree (C_ClassTalents' active config) laid out as the three classic tabs side by side: in
-- Forever's DB2 (build 1.60.1.70450) every class's nodes sit in columns at x 1020-2820, 5020-6820 and
-- 9080-10880 (one hidden Hunter node at x 102800, a Survival talent), left to right in tab order,
-- the order SPEC_KEYS_BY_CLASS lists. A node right of an edge belongs to the next tab.
local TRAIT_TAB_EDGES = { 4000, 8000 }

--- Tab index (1-3) of a class trait node by its x position.
function DT.TraitTabForPosX(posX)
    posX = tonumber(posX) or 0
    local tab = 1
    for i = 1, #TRAIT_TAB_EDGES do
        if posX >= TRAIT_TAB_EDGES[i] then tab = i + 1 end
    end
    return tab
end

local function callApi(fn, ...)
    if not fn then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

--- Points spent per tab in the class talent trait tree, or nil when the client has none.
local function readTraitTabs()
    local CT, TR = C_ClassTalents, C_Traits
    if type(CT) ~= "table" or type(TR) ~= "table" then return nil end
    if not (TR.GetConfigInfo and TR.GetTreeNodes and TR.GetNodeInfo) then return nil end
    local configID = callApi(CT.GetActiveConfigID)
    if not configID or configID == 0 then return nil end
    local info = callApi(TR.GetConfigInfo, configID)
    local treeID = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1] or nil
    if not treeID then return nil end
    local nodeIDs = callApi(TR.GetTreeNodes, treeID)
    if type(nodeIDs) ~= "table" or #nodeIDs == 0 then return nil end
    local tabs = { 0, 0, 0 }
    for i = 1, #nodeIDs do
        local node = callApi(TR.GetNodeInfo, configID, nodeIDs[i])
        if type(node) == "table" then
            local spent = tonumber(node.ranksPurchased) or tonumber(node.activeRank) or 0
            if spent > 0 then
                local tab = DT.TraitTabForPosX(node.posX)
                tabs[tab] = tabs[tab] + spent
            end
        end
    end
    return tabs
end

function DS:ScanTalents(_self)
    local char = GetCurrentCharTable and GetCurrentCharTable() or nil
    if not char then return end
    local classFile = normalizeClassFile(char.classFile)
    local tabs = readTalentTabs() or readTraitTabs()
    local primary, specKey
    if tabs then
        primary = DT.DerivePrimaryTabIndex(tabs)
        specKey = primary and DT.GetSpecKeyForTab(classFile, primary) or nil
    else
        local modernSpecKey, specIndex, apiPresent = readSpecializationSpec(classFile)
        if apiPresent then
            tabs = {}
            primary = specIndex
            specKey = modernSpecKey
        end
    end
    if not tabs then return end
    char.talents = {
        tabs = tabs,
        primary = primary,
        specKey = specKey,
    }
    char.dataVersions = char.dataVersions or {}
    if DATA_VERSIONS and DATA_VERSIONS.talents then
        char.dataVersions.talents = DATA_VERSIONS.talents
    else
        char.dataVersions.talents = 1
    end
    char.lastUpdate = time and time() or char.lastUpdate
end

if CreateFrame then
    local talentFrame = CreateFrame("Frame")

    --- Registers an event only if the running client recognizes it, so a retail-only event name
    --- (e.g. PLAYER_SPECIALIZATION_CHANGED, which TBC Classic doesn't know) can never hard-error
    --- RegisterEvent on a client that lacks it — same pattern/rationale as DataStore.lua's
    --- SafeRegisterEvent (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "C_EventUtils.IsEventValid").
    local function SafeRegisterTalentEvent(eventName)
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
            return
        end
        pcall(talentFrame.RegisterEvent, talentFrame, eventName)
    end

    SafeRegisterTalentEvent("PLAYER_ENTERING_WORLD")
    SafeRegisterTalentEvent("CHARACTER_POINTS_CHANGED")
    SafeRegisterTalentEvent("PLAYER_TALENT_UPDATE")
    -- GetNumTalentTabs/GetTalentTabInfo return no data (numTabs == 0) until the lazy-loaded classic
    -- talent UI has actually been opened once this session — CHARACTER_POINTS_CHANGED/
    -- PLAYER_TALENT_UPDATE alone don't fire from merely opening the window with no points spent, so
    -- without this the "Open your Talents window" instruction never actually clears itself.
    SafeRegisterTalentEvent("ADDON_LOADED")
    -- Retail/Forever-shaped equivalent of CHARACTER_POINTS_CHANGED/PLAYER_TALENT_UPDATE for the
    -- C_SpecializationInfo fallback path — fires on spec change/respec. Doesn't exist on TBC
    -- Classic; SafeRegisterTalentEvent no-ops there instead of erroring.
    SafeRegisterTalentEvent("PLAYER_SPECIALIZATION_CHANGED")
    -- A dual-spec swap (Forever: resto <-> enhancement) fires these, not CHARACTER_POINTS_CHANGED,
    -- so without them the old spec was kept until a reload and gear compared for it.
    SafeRegisterTalentEvent("ACTIVE_TALENT_GROUP_CHANGED")
    SafeRegisterTalentEvent("TRAIT_CONFIG_UPDATED")
    SafeRegisterTalentEvent("ACTIVE_COMBAT_CONFIG_CHANGED")

    --- Seconds after a swap to read the talents again: the tree may still hold the old group's ranks
    --- when the event fires.
    local SWAP_SETTLE_SECONDS = 1

    local SPEC_SWAP_EVENTS = {
        ACTIVE_TALENT_GROUP_CHANGED = true,
        TRAIT_CONFIG_UPDATED = true,
        ACTIVE_COMBAT_CONFIG_CHANGED = true,
    }

    local function scanNow()
        if DS.ScanTalents then
            DS:ScanTalents()
        end
    end

    talentFrame:SetScript("OnEvent", function(_, event, addonName)
        if SPEC_SWAP_EVENTS[event] then
            scanNow()
            if C_Timer and C_Timer.After then
                C_Timer.After(SWAP_SETTLE_SECONDS, scanNow)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
        elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
        elseif event == "ADDON_LOADED" and addonName == "Blizzard_TalentUI" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
            if PlayerTalentFrame and PlayerTalentFrame.HookScript then
                PlayerTalentFrame:HookScript("OnShow", function()
                    if DS.ScanTalents then
                        DS:ScanTalents()
                    end
                end)
            end
        end
    end)
end
