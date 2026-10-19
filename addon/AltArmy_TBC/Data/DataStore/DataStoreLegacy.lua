-- AltArmy TBC — Legacy Talent tracking (WoW Forever's account-wide Legacy Points system).
-- Requires DataStore.lua loaded first.
--
-- Speculative API surface: as of 2026-09-21, Blizzard has published no addon-facing documentation
-- for the Legacy system (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Legacy Talents"). The
-- best community evidence (Thunderz96/forever-addon-kit, a beta addon-dev findings repo) confirms
-- only that "both [class talents and Legacy trees] run on Retail's trait system (C_Traits)" and
-- that the panel opens via ToggleLegacySystemUI at level 25 — no confirmed config/tree/node IDs or
-- exact function signatures exist yet. The system/tree ids come from Forever's DB2 (see
-- LEGACY_SYSTEM_ID below); the config is resolved by them (C_Traits.GetConfigIDBySystemID, else
-- GetConfigIDByTreeID). This module calls the same C_Traits chain Retail's own class
-- talent trees use (GetNodeInfo/GetEntryInfo/GetDefinitionInfo), behind existence checks and pcall
-- throughout, so a wrong guess makes it silently capture nothing rather than error — same
-- "existence check over version check" house style as DataStoreTalents.lua's C_SpecializationInfo
-- fallback. Every candidate is also tracked in ApiCheck.lua so a real Forever login can confirm or
-- correct these guesses via /altarmy debug apicheck.
-- luacheck: globals C_Traits C_Spell GetSpellInfo C_EventUtils

if not AltArmy or not AltArmy.DataStore then return end

AltArmy.DataStoreLegacy = AltArmy.DataStoreLegacy or {}

local DS = AltArmy.DataStore
local DL = AltArmy.DataStoreLegacy
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

-- Rest-XP legacy talent: no confirmed node ID, so matched by resolved spell/entry name instead (see
-- module header). "Well Rested" (WoW Forever's Legacy Adventure tree, per Wowhead/Icy Veins Legacy
-- System guides): +4% rested-XP cap and +4% rested-XP accumulation rate per rank, up to 5 ranks
-- (20% at max rank). English name only — no locale handling, since none of the sources this doc
-- cites confirm localized strings yet.
DL.REST_TALENT_NAMES = { "Well Rested" }
DL.REST_TALENT_PERCENT_PER_RANK = 0.04
DL.REST_TALENT_MAX_RANK = 5

-- The Legacy system's trait system and trees, from Forever's DB2 (wago.tools, build 1.60.1.70009):
-- TraitSystem 45 owns TraitTree 1187/1188/1189 (TraitCurrency 4225, 16 points). The first version of
-- this module read C_ClassTalents.GetActiveConfigID(), which is the *class* talent config: saved
-- characters below the Legacy unlock level (25) came back with their class talents' ranks.
DL.LEGACY_SYSTEM_ID = 45
DL.LEGACY_TREE_IDS = { 1187, 1188, 1189 }

-- Legacy talent spell ids (TraitDefinition.SpellID), as other tools read them from `legacyTalents.spells`.
DL.SPELL_MASTER_CHEF = 1225457 -- Cooking: 10% per rank chance of an extra result, 5 ranks
DL.SPELL_BARTERING = 1225459 -- vendor prices -5% per rank, 2 ranks
DL.SPELL_WELL_RESTED = 1225478

local function isLegacyTree(treeID)
    for i = 1, #DL.LEGACY_TREE_IDS do
        if DL.LEGACY_TREE_IDS[i] == treeID then return true end
    end
    return false
end

--- The Legacy trait config: by its system, else by one of its trees. Never the class-talent config.
local function API_GetLegacyConfigID()
    if not C_Traits then return nil end
    if C_Traits.GetConfigIDBySystemID then
        local ok, configID = pcall(C_Traits.GetConfigIDBySystemID, DL.LEGACY_SYSTEM_ID)
        if ok and configID and configID ~= 0 then return configID end
    end
    if C_Traits.GetConfigIDByTreeID then
        for _, treeID in ipairs(DL.LEGACY_TREE_IDS) do
            local ok, configID = pcall(C_Traits.GetConfigIDByTreeID, treeID)
            if ok and configID and configID ~= 0 then return configID end
        end
    end
    return nil
end

local function getSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then return info.name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return name end
    end
    return nil
end

local function isRestTalentName(name)
    if not name then return false end
    for i = 1, #DL.REST_TALENT_NAMES do
        if name == DL.REST_TALENT_NAMES[i] then return true end
    end
    return false
end

--- A node's definition info via its first entry, existence-checked and pcall-guarded throughout the
--- C_Traits call chain (GetNodeInfo -> entryIDs -> GetEntryInfo -> definitionID -> GetDefinitionInfo).
--- Returns nil if any link is missing.
local function resolveDefinition(configID, nodeID)
    if not C_Traits or not C_Traits.GetNodeInfo then return nil end
    local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or not nodeInfo or not nodeInfo.entryIDs or not nodeInfo.entryIDs[1] then return nil end
    if not C_Traits.GetEntryInfo then return nil end
    local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, nodeInfo.entryIDs[1])
    if not okEntry or not entryInfo or not entryInfo.definitionID then return nil end
    if not C_Traits.GetDefinitionInfo then return nil end
    local okDef, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
    if not okDef or not defInfo then return nil end
    return defInfo
end

--- A definition's display name: its override, else its spell's name.
local function definitionName(defInfo)
    if not defInfo then return nil end
    if defInfo.overriddenName and defInfo.overriddenName ~= "" then return defInfo.overriddenName end
    return getSpellName(defInfo.spellID)
end

local function getNodeRank(configID, nodeID)
    if not C_Traits or not C_Traits.GetNodeInfo then return 0 end
    local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or not nodeInfo then return 0 end
    return tonumber(nodeInfo.activeRank or nodeInfo.currentRank) or 0
end

--- True when the C_Traits call chain this module relies on is present at all (regardless of
--- whether a config/tree actually resolves) — lets callers distinguish "API missing entirely"
--- (e.g. TBC Classic) from "API present, nothing spent yet".
function DL.HasTraitsApi()
    return C_Traits ~= nil and C_Traits.GetTreeNodes ~= nil and C_Traits.GetNodeInfo ~= nil
end

--- Scans the Legacy trees of the Legacy trait config, returning nodeID->rank and definition
--- spellID->rank for every node with at least one point spent, the total ranks spent, and the rank of
--- the rest-XP legacy talent. Returns nil (not an empty result) when the API chain or the Legacy
--- config can't be resolved at all, so callers can tell "nothing captured because unavailable" apart
--- from "captured, zero spent".
function DL.ScanActiveConfig()
    if not DL.HasTraitsApi() then return nil end
    local configID = API_GetLegacyConfigID()
    if not configID then return nil end

    local treeIDs = {}
    if C_Traits.GetConfigInfo then
        local ok, configInfo = pcall(C_Traits.GetConfigInfo, configID)
        if ok and configInfo and configInfo.treeIDs then
            for _, treeID in ipairs(configInfo.treeIDs) do
                if isLegacyTree(treeID) then treeIDs[#treeIDs + 1] = treeID end
            end
        end
    end
    if #treeIDs == 0 then treeIDs = DL.LEGACY_TREE_IDS end

    local nodes, spells, totalRanks, restRank = {}, {}, 0, 0
    for _, treeID in ipairs(treeIDs) do
        local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local rank = getNodeRank(configID, nodeID)
                if rank > 0 then
                    nodes[nodeID] = rank
                    totalRanks = totalRanks + rank
                    local defInfo = resolveDefinition(configID, nodeID)
                    local spellID = defInfo and tonumber(defInfo.spellID)
                    if spellID then spells[spellID] = rank end
                    if spellID == DL.SPELL_WELL_RESTED or isRestTalentName(definitionName(defInfo)) then
                        restRank = rank
                    end
                end
            end
        end
    end
    return { nodes = nodes, spells = spells, totalRanksSpent = totalRanks, restRank = restRank }
end

function DS:ScanLegacyTalents(_self)
    local char = GetCurrentCharTable and GetCurrentCharTable() or nil
    if not char then return end
    local result = DL.ScanActiveConfig()
    if not result then
        -- Leave any previously-captured data alone; nil just means the API wasn't
        -- resolvable this scan (e.g. TBC Classic, or the guess above needs correcting). v1 data
        -- (no `spells`) was read from the class-talent config, so that goes.
        if type(char.legacyTalents) == "table" and char.legacyTalents.spells == nil then
            char.legacyTalents = nil
        end
        return
    end
    char.legacyTalents = result
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.legacyTalents = (DATA_VERSIONS and DATA_VERSIONS.legacyTalents) or 1
    char.lastUpdate = time and time() or char.lastUpdate
end

--- The captured "Well Rested" legacy talent rank, clamped to its max rank; 0 when unavailable,
--- unscanned, or zero ranks spent.
function DL.GetWellRestedRank(char)
    local legacy = char and char.legacyTalents
    -- v1 data (no `spells`) came from the class-talent config: not a Legacy rank.
    if type(legacy) ~= "table" or legacy.spells == nil then return 0 end
    local rank = tonumber(legacy.restRank) or 0
    if rank <= 0 then return 0 end
    return math.min(rank, DL.REST_TALENT_MAX_RANK)
end

--- Rest-XP multiplier (cap and accumulation rate) from the captured "Well Rested" legacy talent
--- rank; 1 (no change) when unavailable, unscanned, or zero ranks spent. See DataStoreCharacter.lua
--- GetRestXp/GetStoredRestXp.
function DL.GetRestXpMultiplier(char)
    return 1 + (DL.GetWellRestedRank(char) * DL.REST_TALENT_PERCENT_PER_RANK)
end

if CreateFrame then
    local legacyFrame = CreateFrame("Frame")

    --- Same SafeRegisterEvent pattern as DataStoreTalents.lua / DataStore.lua: TRAIT_CONFIG_UPDATED
    --- doesn't exist on TBC Classic, so this must never hard-error RegisterEvent there.
    local function SafeRegisterLegacyEvent(eventName)
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
            return
        end
        pcall(legacyFrame.RegisterEvent, legacyFrame, eventName)
    end

    SafeRegisterLegacyEvent("PLAYER_ENTERING_WORLD")
    SafeRegisterLegacyEvent("TRAIT_CONFIG_UPDATED")
    legacyFrame:SetScript("OnEvent", function()
        if DS.ScanLegacyTalents then
            DS:ScanLegacyTalents()
        end
        -- The Legacy talents' cooldowns (Cooldowns tab: Dedicated Study, Essence of Innovation): read them at
        -- login too, not only after a cast.
        local CD = AltArmy.CooldownData
        local char = GetCurrentCharTable and GetCurrentCharTable() or nil
        if CD and CD.CATEGORIES and CD.CATEGORY_ORDER and DS.TryScanTrackedCooldownFromSpellApi then
            for _, key in ipairs(CD.CATEGORY_ORDER) do
                local cat = CD.CATEGORIES[key]
                if cat and cat.legacyTalent and CD.CharacterHasLegacyTalentSpell(char, cat.spellId) then
                    DS:TryScanTrackedCooldownFromSpellApi(cat.spellId)
                end
            end
        end
        -- A Well Rested rank changes the Summary's Rest XP; RefreshSummary does nothing while hidden.
        if AltArmy.RefreshSummary then
            AltArmy.RefreshSummary()
        end
    end)
end
