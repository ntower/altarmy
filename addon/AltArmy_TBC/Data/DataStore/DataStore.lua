-- AltArmy TBC — Internal character data store (core).
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- Domain modules (DataStoreCharacter, DataStoreContainers, etc.) attach scans and getters to AltArmy.DataStore.
-- TBC-compatible; no external DataStore dependency.
-- luacheck: globals C_EventUtils

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore

-- Existence-check, not version-check: GetMaxPlayerLevel() reflects whatever
-- cap the running client actually has (70 on TBC Classic, 60 on WoW Forever),
-- so this stays correct across clients without needing to detect which one
-- we're on. Falls back to TBC's 70 if the API isn't present.
DS.MAX_LEVEL = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 70

-- Version check, not existence check: unlike most of this file, there's no API
-- to defensively probe here — selecting which stat-weight data table to use
-- (see Data/Gear/PawnScalesForever.lua) genuinely requires knowing which client
-- is running. 16001 is WoW Forever's confirmed Interface number (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md). Falls back to false (today's
-- TBC behavior) if GetBuildInfo isn't present.
DS.IsWowForever = (GetBuildInfo and select(4, GetBuildInfo()) == 16001) or false

local DATA_VERSIONS = {
    character = 3,
    guildMembership = 1,
    containers = 4, -- v4: a soulbound copy's slot says `bound`; bagsScannedAt / bankScannedAt
    equipment = 1,
    gearScores = 1,
    professions = 1,
    reputations = 2,
    mail = 2,
    auctions = 1,
    currencies = 1,
    currencyList = 1,
    levelHistory = 1,
    talents = 2,
    legacyTalents = 2,
}

AltArmyTBC_Data = AltArmyTBC_Data or {}
AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
AltArmyTBC_Data.OrphanImports = AltArmyTBC_Data.OrphanImports or {}

-- SavedVariables are applied after this file can run; the global table may be replaced, so
-- re-point these in SyncAccountDataRoot (ADDON_LOADED + VARIABLES_LOADED) or writes (e.g.
-- RecipeReagents) can go to a stale table and not persist across /reload.
AltArmy.DB = AltArmyTBC_Data
DS.accountData = AltArmyTBC_Data

local function SyncAccountDataRoot()
    DS.accountData = AltArmyTBC_Data
    AltArmy.DB = AltArmyTBC_Data
end

-- UnitName("player") reads UNKNOWNOBJECT ("Unknown") early in loading; that is no character's name.
local UNKNOWN_NAME = "Unknown"

local function IsUnknownName(name)
    return name == UNKNOWN_NAME or (UNKNOWNOBJECT ~= nil and name == UNKNOWNOBJECT) --luacheck: ignore 113
end

--- Separator the client puts between first name and surname (WoW Forever), else a space.
local function SurnameSeparator()
    local c = Constants --luacheck: ignore 113
    local sep = type(c) == "table" and c.CharacterNameSeparatorConsts
        and c.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(sep) == "string" and sep ~= "" then return sep end
    return " "
end

local function GetCurrentRealm()
    return (GetRealmName and GetRealmName()) or ""
end

--- Full character name. WoW Forever's UnitName returns the first name and the surname as two
--- values ("Frell", "Ofelements"); older clients return one name (the second value is a realm,
--- and only for cross-realm units, never for "player").
local function GetCurrentName()
    local name, surname
    if UnitName then
        name, surname = UnitName("player")
    end
    if not name or name == "" then
        name, surname = (GetUnitName and GetUnitName("player", true)) or "", nil
    end
    if IsUnknownName(name) then return "" end
    if type(surname) == "string" and surname ~= "" and surname ~= GetCurrentRealm() then
        name = name .. SurnameSeparator() .. surname
    end
    return name
end

local function GetCurrentGUID()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

--- The current character's storage key and name. The key is the GUID (stable across renames and
--- however the client formats names); only a client without UnitGUID falls back to the name.
--- The key is nil while it is not known yet.
local function GetCurrentKey()
    local name = GetCurrentName()
    if UnitGUID then
        return GetCurrentGUID(), name
    end
    if name == "" then return nil, name end
    return name, name
end

local function GetCurrentCharTable()
    local realm = GetCurrentRealm()
    local key, name = GetCurrentKey()
    if not realm or not key then return nil end
    if not AltArmyTBC_Data.Characters[realm] then
        AltArmyTBC_Data.Characters[realm] = {}
    end
    local char = AltArmyTBC_Data.Characters[realm][key]
    if not char then
        char = { realm = realm, guid = GetCurrentGUID() }
        if name ~= "" then char.name = name end
        AltArmyTBC_Data.Characters[realm][key] = char
    end
    return char
end

local function MigrateDataVersions(data)
    data = data or AltArmyTBC_Data
    for _, chars in pairs(data.Characters or {}) do
        for _, char in pairs(chars) do
            char.dataVersions = char.dataVersions or {}
            if char.name and not char.dataVersions.character then
                char.dataVersions.character = 1
            end
            if char.Containers and next(char.Containers) and not char.dataVersions.containers then
                char.dataVersions.containers = 1
            end
            if char.Inventory and next(char.Inventory) and not char.dataVersions.equipment then
                char.dataVersions.equipment = 1
            end
        end
    end
end

--- Drop entries keyed "Unknown" that were never scanned (no name, class or faction): older versions made one
--- when UnitName("player") still read "Unknown" during loading.
local function RemoveUnknownStubs(data)
    data = data or AltArmyTBC_Data
    for _, chars in pairs(data.Characters or {}) do
        for key, char in pairs(chars) do
            if IsUnknownName(key) and type(char) == "table"
                and not char.name and not char.classFile and not char.faction
            then
                chars[key] = nil
            end
        end
    end
end

--- Copy `old`'s fields that `char` lacks into `char` (char's values win).
local function MergeInto(char, old)
    for field, value in pairs(old) do
        if char[field] == nil then char[field] = value end
    end
end

--- Move every character entry that carries a GUID under that GUID (character v3). Entries without
--- one (saved before v2) stay under their name until that character logs in (FoldLegacyEntries).
--- When two entries share a GUID, the one scanned last wins and the other fills its gaps.
local function MigrateCharacterKeys(data)
    data = data or AltArmyTBC_Data
    for _, chars in pairs(data.Characters or {}) do
        local moves = {}
        for key, char in pairs(chars) do
            if type(char) == "table" and type(char.guid) == "string" and char.guid ~= ""
                and key ~= char.guid
            then
                moves[#moves + 1] = key
            end
        end
        for _, key in ipairs(moves) do
            local char = chars[key]
            local existing = chars[char.guid]
            chars[key] = nil
            if type(existing) ~= "table" then
                chars[char.guid] = char
            elseif (char.lastUpdate or 0) > (existing.lastUpdate or 0) then
                MergeInto(char, existing)
                chars[char.guid] = char
            else
                MergeInto(existing, char)
            end
        end
    end
end

--- Fold older entries of the current character on `realm` into `char` and delete them: any entry
--- with the same GUID, and a GUID-less entry saved under exactly the character's full name.
--- Settings saved under an adopted entry's old name move to `fullName`.
local function FoldLegacyEntries(data, realm, guid, fullName, char)
    local chars = (data or AltArmyTBC_Data).Characters
    local realmTable = chars and chars[realm]
    if not realmTable or not char then return end
    local adopted = {}
    for key, old in pairs(realmTable) do
        if old ~= char and type(old) == "table" then
            local sameGuid = guid ~= nil and old.guid == guid
            local sameLegacyName = old.guid == nil and fullName ~= "" and key == fullName
            if sameGuid or sameLegacyName then
                adopted[#adopted + 1] = key
            end
        end
    end
    for _, key in ipairs(adopted) do
        local old = realmTable[key]
        MergeInto(char, old)
        realmTable[key] = nil
        local oldName = old.name or key
        if AltArmy.RekeyCharSettings and fullName ~= "" and oldName ~= fullName then
            AltArmy.RekeyCharSettings(realm, oldName, fullName)
        end
    end
end

-- This WoW account's id: 16 random hex digits made on first load and kept in AltArmyTBC_Data. Nothing in the
-- game names the account, and every character of it shares this file. The website replaces only the
-- characters of the account an upload comes from (site/src/altarmy_site/altarmy.py), and linked accounts
-- tell each other apart by it. `force` makes a new one (a copied WTF folder shares the old one).
local ACCOUNT_ID_PATTERN = "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"

local function EnsureAccountId(data, rng, force)
    data = data or AltArmyTBC_Data
    if not force and type(data.accountId) == "string" and data.accountId:match(ACCOUNT_ID_PATTERN) then
        return data.accountId
    end
    rng = rng or math.random
    local digits = {}
    for i = 1, 16 do
        digits[i] = string.format("%x", rng(0, 15))
    end
    data.accountId = table.concat(digits)
    return data.accountId
end

DS.EnsureAccountId = EnsureAccountId
DS._EnsureAccountId = EnsureAccountId

DS._GetCurrentCharTable = GetCurrentCharTable
DS._RemoveUnknownStubs = RemoveUnknownStubs
DS._MigrateCharacterKeys = MigrateCharacterKeys
DS._FoldLegacyEntries = FoldLegacyEntries
DS._MigrateDataVersions = MigrateDataVersions
DS._DATA_VERSIONS = DATA_VERSIONS

function DS:GetRealms()
    local out = {}
    for realm in pairs(AltArmyTBC_Data.Characters) do
        out[realm] = true
    end
    return out
end

function DS:GetCharacters(realm)
    if not realm then return {} end
    return AltArmyTBC_Data.Characters[realm] or {}
end

--- Storage key and entry of a character on `realm`, by storage key (GUID or legacy name) or by name.
local function FindCharacterEntry(nameOrKey, realm)
    if not nameOrKey or not realm then return nil end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    if not realmTable then return nil end
    if realmTable[nameOrKey] then return nameOrKey, realmTable[nameOrKey] end
    for key, char in pairs(realmTable) do
        if type(char) == "table" and char.name == nameOrKey then
            return key, char
        end
    end
    return nil
end

--- A stored character, looked up by name or by storage key.
function DS:GetCharacter(name, realm)
    local _, char = FindCharacterEntry(name, realm)
    return char
end

--- Storage key of a stored character: its GUID, or the name for entries saved before GUIDs.
function DS:GetCharacterKey(char)
    if type(char) ~= "table" then return nil end
    return char.guid or char.name
end

function DS:GetCurrentCharacter()
    return GetCurrentCharTable()
end

function DS:GetCurrentPlayerName()
    return GetCurrentName()
end

function DS:GetCurrentPlayerRealm()
    return GetCurrentRealm()
end

function DS:GetCurrentPlayerGUID()
    return GetCurrentGUID()
end

function DS:GetCurrentPlayerIdentity()
    return GetCurrentName(), GetCurrentRealm()
end

function DS:IsCurrentCharacter(name, realm)
    if not name or not realm then return false end
    return name == GetCurrentName() and realm == GetCurrentRealm()
end

--- Iterate all stored characters. fn(realm, key, charData) — return true to stop early. `key` is the
--- storage key (GUID, or the name for entries saved before GUIDs); charData.name is the name.
function DS:ForEachCharacter(fn)
    if not fn then return end
    for realm in pairs(self:GetRealms()) do
        for charName, charData in pairs(self:GetCharacters(realm)) do
            if fn(realm, charName, charData) == true then
                return
            end
        end
    end
end

--- Linked accounts' characters (Data/Link/LinkStore.lua; only links confirmed and not suspended):
--- fn(realm, key, charData, accountId) — return true to stop early. Read-only: never write to them.
function DS:ForEachLinkedCharacter(fn)
    local LS = AltArmy.LinkStore
    if not fn or not (LS and LS.ForEachCharacter) then return end
    LS.ForEachCharacter(fn)
end

--- Our characters, then linked accounts' when the character scope shows them (GlobalRealmFilter) or
--- `opts.linked` says so: fn(realm, key, charData, linkId) — linkId nil for ours; return true to stop.
--- For lists the player browses (Summary, Search, Cooldowns); everything that acts on characters keeps
--- ForEachCharacter, ours alone.
function DS:ForEachCharacterInScope(fn, opts)
    if not fn then return end
    local stopped = false
    self:ForEachCharacter(function(realm, key, char)
        if fn(realm, key, char, nil) == true then
            stopped = true
            return true
        end
    end)
    if stopped then return end
    local linked = opts and opts.linked
    if linked == nil then
        local G = AltArmy.GlobalRealmFilter
        local scope = G and G.GetScope and G.GetScope()
        linked = scope == nil or scope.linked ~= false
    end
    if linked then
        self:ForEachLinkedCharacter(fn)
    end
end

--- The linked account a character table came from; nil for our own.
function DS:GetLinkId(char)
    local LS = AltArmy.LinkStore
    return LS and LS.LinkOf and LS.LinkOf(char) or nil
end

function DS:IsLinkedCharacter(char)
    return self:GetLinkId(char) ~= nil
end

--- A character by name (or storage key) on `realm`: ours, else a linked account's. Second return: its link.
function DS:GetCharacterAny(name, realm)
    local char = self:GetCharacter(name, realm)
    if char then return char, nil end
    local found, foundLink
    self:ForEachLinkedCharacter(function(r, key, c, linkId)
        if r == realm and (key == name or c.name == name) then
            found, foundLink = c, linkId
            return true
        end
    end)
    return found, foundLink
end

--- The character a list row stands for: a linked account's when the row came from one (its `linkId`),
--- else ours. For tabs that draw rows of ForEachCharacterInScope's characters; read-only for a linked one.
function DS:GetCharacterFor(name, realm, linkId)
    if linkId == nil then
        return self:GetCharacter(name, realm)
    end
    local LS = AltArmy.LinkStore
    return LS and LS.FindCharacter and LS.FindCharacter(linkId, name, realm) or nil
end

--- Linked data arrived or was removed: views that list characters redraw, and the Inventory (a container
--- listener) too. A sync applies a character's units one after another: coalesced into one redraw.
local linkedRedrawPending = false
function DS:FireLinkedDataChanged()
    local function redraw()
        linkedRedrawPending = false
        if AltArmy.RefreshCharacterViews then
            AltArmy.RefreshCharacterViews()
        end
        self:FireContainerDataChanged()
    end
    if not (C_Timer and C_Timer.After) then
        redraw()
        return
    end
    if linkedRedrawPending then
        return
    end
    linkedRedrawPending = true
    C_Timer.After(0.5, redraw)
end

function DS:HasModuleData(char, moduleName)
    if not char or not moduleName then return false end
    local v = (char.dataVersions and char.dataVersions[moduleName]) or 0
    return v > 0
end

function DS:GetDataVersion(char, moduleName)
    if not char or not moduleName then return 0 end
    return (char.dataVersions and char.dataVersions[moduleName]) or 0
end

function DS:NeedsRescan(char, moduleName)
    if not char or not moduleName then return true end
    local current = DATA_VERSIONS[moduleName]
    if not current then return false end
    return (DS:GetDataVersion(char, moduleName) or 0) < current
end

function DS:GetAllDataVersions(char)
    if not char then return {} end
    local out = {}
    for k, v in pairs(char.dataVersions or {}) do
        out[k] = v
    end
    return out
end

-- Listeners (the Inventory tab) run after each bag, bank, mailbox or equipment scan, and after a mail
-- prediction is cached; the scan modules call FireContainerDataChanged from their notify helpers.
local containerListeners = {}
function DS:OnContainerDataChanged(fn)
    if type(fn) == "function" then
        containerListeners[#containerListeners + 1] = fn
    end
end
function DS:FireContainerDataChanged()
    for _, fn in ipairs(containerListeners) do pcall(fn) end
end

function DS:DeleteCharacter(name, realm)
    local key = FindCharacterEntry(name, realm)
    if not key then return end
    AltArmyTBC_Data.Characters[realm][key] = nil
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    -- linked accounts drop their copy once they hear (a full manifest, debounced)
    local T = AltArmy.LinkTransport
    if T and T.NoteDeletion then
        T.NoteDeletion()
    end
end

-- Event frame and dispatch
local frame = CreateFrame("Frame", nil, UIParent)
-- OwnRecipeRead's silenced reads take TRADE_SKILL_SHOW from every frame but its own and this one.
DS.eventFrame = frame

--- Registers an event only if the running client recognizes it (checked via
--- C_EventUtils.IsEventValid when available, per Thaoky/AddonFactory's
--- cross-flavor pattern), falling back to a pcall so an unrecognized event
--- can never hard-error RegisterEvent on any client, old or new.
local function SafeRegisterEvent(eventName)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
        return
    end
    pcall(frame.RegisterEvent, frame, eventName)
end

--- Patch 12.0+ clients (Forever included) can hand combat-log fields to addons as
--- Secret Values that error on any operation beyond store/pass. `canaccessvalue()`
--- (existence-checked) is the guard, matching DataStoreLevelHistory.lua's copy and
--- our DataStoreProfessions.lua fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("VARIABLES_LOADED")
SafeRegisterEvent("PLAYER_ALIVE")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("PLAYER_GUILD_UPDATE")
SafeRegisterEvent("PLAYER_LOGOUT")
SafeRegisterEvent("PLAYER_MONEY")
SafeRegisterEvent("PLAYER_XP_UPDATE")
SafeRegisterEvent("PLAYER_LEVEL_UP")
SafeRegisterEvent("TIME_PLAYED_MSG")
SafeRegisterEvent("BAG_UPDATE")
SafeRegisterEvent("BANKFRAME_OPENED")
SafeRegisterEvent("BANKFRAME_CLOSED")
SafeRegisterEvent("PLAYERBANKSLOTS_CHANGED")
SafeRegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SafeRegisterEvent("SKILL_LINES_CHANGED")
SafeRegisterEvent("TRADE_SKILL_SHOW")
SafeRegisterEvent("TRADE_SKILL_CLOSE")
-- Retail/Forever-shaped trigger for the C_TradeSkillUI recipe scan (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth"): on those clients TRADE_SKILL_SHOW alone
-- doesn't signal that recipe data is actually loaded, this event does. SafeRegisterEvent no-ops on
-- clients without it (TBC Classic included, where TRADE_SKILL_SHOW's own timer already covers it).
SafeRegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
SafeRegisterEvent("CRAFT_SHOW")
SafeRegisterEvent("CHAT_MSG_SKILL")
SafeRegisterEvent("CHAT_MSG_SYSTEM")
SafeRegisterEvent("NEW_RECIPE_LEARNED")
SafeRegisterEvent("UPDATE_FACTION")
SafeRegisterEvent("CURRENCY_DISPLAY_UPDATE")
SafeRegisterEvent("MAIL_SHOW")
SafeRegisterEvent("MAIL_INBOX_UPDATE")
SafeRegisterEvent("MAIL_CLOSED")
-- TBC Anniversary often does not fire MAIL_CLOSED; interaction-manager covers that client.
SafeRegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
SafeRegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
SafeRegisterEvent("AUCTION_HOUSE_SHOW")
SafeRegisterEvent("AUCTION_HOUSE_CLOSED")
SafeRegisterEvent("AUCTION_OWNED_LIST_UPDATE")
SafeRegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
-- Retail/Forever-shaped C_AuctionHouse equivalents of the two legacy events above (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md); SafeRegisterEvent no-ops on clients without them.
SafeRegisterEvent("OWNED_AUCTIONS_UPDATED")
SafeRegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
SafeRegisterEvent("BIDS_UPDATED")
-- Forever's client is missing CombatLogGetCurrentEventInfo (confirmed via
-- /altarmy debug apicheck; see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md), and the
-- OnEvent handler below is a no-op without it — registering anyway triggers a spurious
-- ADDON_ACTION_FORBIDDEN, so skip registration entirely when the API isn't there.
if CombatLogGetCurrentEventInfo then
    SafeRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
SafeRegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SafeRegisterEvent("UPDATE_INSTANCE_INFO")
SafeRegisterEvent("RAID_INSTANCE_WELCOME")

local isMailOpen = false
local isAuctionHouseOpen = false
local lastReputationScan = 0
local isBankOpen = false
local MAIL_INTERACTION_TYPE = (
    _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.MailInfo
) or 17

local function HookMailFrameVisibility()
    local mf = _G.MailFrame
    if not mf or mf.altArmyDataStoreMailHooked then
        return
    end
    mf.altArmyDataStoreMailHooked = true
    if mf.HookScript then
        mf:HookScript("OnShow", function()
            isMailOpen = true
        end)
        mf:HookScript("OnHide", function()
            isMailOpen = false
        end)
    end
end

HookMailFrameVisibility()

function DS:IsBankOpen()
    return isBankOpen
end

--- Called on PLAYER_GUILD_UPDATE to keep guild membership current without a relog.
--- WoW can fire this event twice for a single join/leave; skip when nothing changed.
function DS:HandlePlayerGuildUpdate()
    local char = GetCurrentCharTable()
    if not char then return end
    local prevGuild = char.guildName
    local liveGuild
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        liveGuild = (g ~= "" and g) or nil
    end
    if liveGuild == prevGuild and DS.HasModuleData and DS:HasModuleData(char, "guildMembership") then
        return
    end
    if DS.ScanGuildMembership then
        DS:ScanGuildMembership()
    end
end

local REPUTATION_SCAN_THROTTLE = 3
local BAG_SCAN_DELAY = 3
--- Equipment links can be nil on PEW/ALIVE before item cache is ready (same class of bug as bags).
local EQUIPMENT_SCAN_DELAY = 3
local TRADE_SKILL_SCAN_DELAY = 0.5
--- Deferred reagent-only retry (Cooldowns RecipeReagents); avoids TRADE_SKILL_UPDATE loops.
local TRADE_SKILL_REAGENT_RETRY_DELAY = 1.25
local CRAFT_REAGENT_RETRY_DELAY = 1.25

local bagScanFrame = CreateFrame("Frame", nil, UIParent)
bagScanFrame:SetScript("OnUpdate", nil)
bagScanFrame.elapsed = 0

local equipmentScanFrame = CreateFrame("Frame", nil, UIParent)
equipmentScanFrame:SetScript("OnUpdate", nil)
equipmentScanFrame.elapsed = 0

-- Run professions + reputations again after delay (skill/faction data can load late)
local LATE_SCAN_DELAY = 2
local lateScanFrame = CreateFrame("Frame", nil, UIParent)
lateScanFrame:SetScript("OnUpdate", nil)
lateScanFrame.elapsed = 0

local tradeSkillScanFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillScanFrame:SetScript("OnUpdate", nil)
tradeSkillScanFrame.elapsed = 0

local craftScanFrame = CreateFrame("Frame", nil, UIParent)
craftScanFrame:SetScript("OnUpdate", nil)
craftScanFrame.elapsed = 0

local tradeSkillReagentRetryFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillReagentRetryFrame:SetScript("OnUpdate", nil)
tradeSkillReagentRetryFrame.elapsed = 0

local craftReagentRetryFrame = CreateFrame("Frame", nil, UIParent)
craftReagentRetryFrame:SetScript("OnUpdate", nil)
craftReagentRetryFrame.elapsed = 0

-- After a successful cast, the cooldown isn't always queryable on the same frame.
local cooldownAfterCastFrame = CreateFrame("Frame", nil, UIParent)
cooldownAfterCastFrame:SetScript("OnUpdate", nil)
cooldownAfterCastFrame.elapsed = 0
cooldownAfterCastFrame.pendingSpellId = nil

-- Player GUID is fixed for the session; cached so the combat-log hot path skips UnitGUID.
local cleuPlayerGUID

function DS:IsMailOpen()
    return isMailOpen == true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local addonName, a1, a3 = ...
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Hot path: fires for every nearby unit (busy in cities). Everything below only
        -- cares about events from or to the player, so bail before allocating anything.
        if not CombatLogGetCurrentEventInfo or not UnitGUID then return end
        local playerGUID = cleuPlayerGUID
        if not playerGUID then
            playerGUID = UnitGUID("player")
            if not playerGUID then return end
            cleuPlayerGUID = playerGUID
        end
        local timestamp, subevent, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
            destGUID, destName, destFlags, destRaidFlags, spellId = CombatLogGetCurrentEventInfo()
        if not canAccessSecretValue(srcGUID) or not canAccessSecretValue(destGUID) then return end
        local fromPlayer = srcGUID == playerGUID
        if not fromPlayer and destGUID ~= playerGUID then return end
        if DS.HandleCombatLogForLevelHistory then
            DS:HandleCombatLogForLevelHistory({
                timestamp, subevent, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
                destGUID, destName, destFlags, destRaidFlags,
            })
        end
        if not fromPlayer then return end
        local CD = AltArmy and AltArmy.CooldownData
        if not CD or not CD.RecordSuccessfulTransmuteCast then return end
        if not canAccessSecretValue(subevent) or subevent ~= "SPELL_CAST_SUCCESS" then return end
        if type(spellId) ~= "number" then return end
        local char = GetCurrentCharTable()
        if char then
            CD.RecordSuccessfulTransmuteCast(char, spellId)
            if CD.RecordSuccessfulSphereCast then
                CD.RecordSuccessfulSphereCast(char, spellId)
            end
            cooldownAfterCastFrame.pendingSpellId = spellId
            cooldownAfterCastFrame.elapsed = 0
            cooldownAfterCastFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= 0.10 then
                    f:SetScript("OnUpdate", nil)
                    local sid = f.pendingSpellId
                    f.pendingSpellId = nil
                    if sid and CD.IsTransmuteSpellId and CD.IsTransmuteSpellId(sid)
                        and DS.TryScanTransmuteCooldownsFromSpellApi
                    then
                        DS:TryScanTransmuteCooldownsFromSpellApi(sid)
                    elseif sid and CD.IsSphereSpellId and CD.IsSphereSpellId(sid)
                        and DS.TryScanSphereCooldownsFromSpellApi
                    then
                        DS:TryScanSphereCooldownsFromSpellApi(sid)
                    elseif sid and DS.TryScanTrackedCooldownFromSpellApi then
                        DS:TryScanTrackedCooldownFromSpellApi(sid)
                    end
                end
            end)
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = addonName
        local spellId = a3
        -- Spell-cast payloads can be secret during encounters on 12.0+ clients (Forever).
        if not canAccessSecretValue(unit) or not canAccessSecretValue(spellId) then return end
        if unit ~= "player" then return end
        if type(spellId) ~= "number" then return end
        local CD = AltArmy and AltArmy.CooldownData
        if not CD or not CD.IsTrackedSpellId then return end
        if not CD.IsTrackedSpellId(spellId) then return end

        cooldownAfterCastFrame.pendingSpellId = spellId
        cooldownAfterCastFrame.elapsed = 0
        cooldownAfterCastFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= 0.10 then
                f:SetScript("OnUpdate", nil)
                local sid = f.pendingSpellId
                f.pendingSpellId = nil
                if sid and CD.IsTransmuteSpellId and CD.IsTransmuteSpellId(sid)
                    and DS.TryScanTransmuteCooldownsFromSpellApi
                then
                    DS:TryScanTransmuteCooldownsFromSpellApi(sid)
                elseif sid and CD.IsSphereSpellId and CD.IsSphereSpellId(sid)
                    and DS.TryScanSphereCooldownsFromSpellApi
                then
                    DS:TryScanSphereCooldownsFromSpellApi(sid)
                elseif sid and DS.TryScanTrackedCooldownFromSpellApi then
                    DS:TryScanTrackedCooldownFromSpellApi(sid)
                end
            end
        end)
        return
    end
    if event == "VARIABLES_LOADED" then
        SyncAccountDataRoot()
        return
    end
    if event == "ADDON_LOADED" then
        if addonName == "AltArmy_TBC" then
            SyncAccountDataRoot()
            AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
            AltArmyTBC_Data.OrphanImports = AltArmyTBC_Data.OrphanImports or {}
            AltArmyTBC_Data.RecipeReagents = AltArmyTBC_Data.RecipeReagents or {}
            EnsureAccountId()
            RemoveUnknownStubs()
            MigrateCharacterKeys()
            GetCurrentCharTable()
            MigrateDataVersions()
            if DS.MigratePhantomLevelHistoryImports then
                DS:MigratePhantomLevelHistoryImports()
            end
        end
        return
    end
    if event == "PLAYER_ALIVE" or event == "PLAYER_ENTERING_WORLD" then
        if DS.MigrateRecipePrimaryIds then
            DS:MigrateRecipePrimaryIds()
        end
        if DS.ScanCharacter then DS:ScanCharacter() end
        if DS.RequestTimePlayedSilently then
            DS:RequestTimePlayedSilently()
        elseif RequestTimePlayed then
            RequestTimePlayed()
        end
        local char = GetCurrentCharTable()
        if char then
            if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
                DS:ScanProfessionLinks()
            end
            if DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                DS:ScanReputations()
            end
            if DS.RequestCurrencyListScan then DS:RequestCurrencyListScan() end
            -- Delayed run: skill/faction data can load after login; rescan so we get it without opening panels
            lateScanFrame.elapsed = 0
            lateScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= LATE_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    local c = GetCurrentCharTable()
                    if c then
                        if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
                            DS:ScanProfessionLinks()
                        end
                        if DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                            DS:ScanReputations()
                        end
                    end
                end
            end)
            -- Equipment: delay only — early PEW links are often all nil and would wipe Inventory
            equipmentScanFrame.elapsed = 0
            equipmentScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= EQUIPMENT_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if DS.ScanEquipment then DS:ScanEquipment() end
                end
            end)
            -- Bags: run once now (if ready) and again after delay to catch late-loaded data
            if DS.ScanBags then DS:ScanBags() end
            if DS.TryScanTrackedCooldownsFromActionBars then
                DS:TryScanTrackedCooldownsFromActionBars()
            end
            bagScanFrame.elapsed = 0
            bagScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= BAG_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if DS.ScanBags then DS:ScanBags() end
                    if DS.TryScanTrackedCooldownsFromActionBars then
                        DS:TryScanTrackedCooldownsFromActionBars()
                    end
                end
            end)
            if DS.RunLevelHistoryBackfill then
                DS:RunLevelHistoryBackfill()
            end
            if DS.RequestLockoutInfoDelayed then
                DS:RequestLockoutInfoDelayed()
            end
        end
        return
    end
    if event == "UPDATE_INSTANCE_INFO" then
        if DS.ScanSavedInstances then
            DS:ScanSavedInstances()
        end
        return
    end
    if event == "RAID_INSTANCE_WELCOME" then
        if DS.RequestLockoutInfo then
            DS:RequestLockoutInfo()
        end
        return
    end
    if event == "SKILL_LINES_CHANGED" then
        local char = GetCurrentCharTable()
        if char and DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" then
        if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        tradeSkillScanFrame.elapsed = 0
        tradeSkillScanFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= TRADE_SKILL_SCAN_DELAY then
                f:SetScript("OnUpdate", nil)
                if DS.HasTradeSkillRecipesApi and DS.HasTradeSkillRecipesApi() and DS.RunDeferredRecipeScan then
                    DS:RunDeferredRecipeScan()
                end
            end
        end)
        tradeSkillReagentRetryFrame.elapsed = 0
        tradeSkillReagentRetryFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= TRADE_SKILL_REAGENT_RETRY_DELAY then
                f:SetScript("OnUpdate", nil)
                -- Legacy-only: reagent capture still has no C_TradeSkillUI fallback (deferred, see
                -- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth").
                if GetNumTradeSkills and DS.CaptureAllTradeSkillReagentsOnly then
                    DS:CaptureAllTradeSkillReagentsOnly()
                end
            end
        end)
        return
    end
    if event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- Retail/Forever-shaped: fires once recipe data for the currently-viewed profession is
        -- actually loaded, unlike TRADE_SKILL_SHOW which fires on window-open regardless. No-op on
        -- TBC Classic (this event won't fire there; TRADE_SKILL_SHOW's own timer already covers it).
        if DS.HasTradeSkillRecipesApi and DS.HasTradeSkillRecipesApi() and DS.RunDeferredRecipeScan then
            DS:RunDeferredRecipeScan()
        end
        return
    end
    if event == "TRADE_SKILL_CLOSE" then
        return
    end
    if event == "CRAFT_SHOW" then
        if GetCraftSkillLine and DS.ScanCraftRecipes then
            craftScanFrame.elapsed = 0
            craftScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= TRADE_SKILL_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if GetCraftSkillLine and DS.ScanCraftRecipes then
                        DS:ScanCraftRecipes()
                    end
                end
            end)
            craftReagentRetryFrame.elapsed = 0
            craftReagentRetryFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= CRAFT_REAGENT_RETRY_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if GetNumCrafts and DS.CaptureAllCraftReagentsOnly then
                        DS:CaptureAllCraftReagentsOnly()
                    end
                end
            end)
        end
        return
    end
    if event == "NEW_RECIPE_LEARNED" then
        if DS.OnNewRecipeLearned then
            DS:OnNewRecipeLearned(tonumber((...)))
        end
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if DS.OnProfessionLearnSystemMessage then
            DS:OnProfessionLearnSystemMessage(msg)
        end
        return
    end
    if event == "CHAT_MSG_SKILL" then
        local char = GetCurrentCharTable()
        if char and DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "CURRENCY_DISPLAY_UPDATE" then
        if DS.RequestCurrencyListScan then DS:RequestCurrencyListScan() end
        return
    end
    if event == "UPDATE_FACTION" then
        local now = time()
        if now - lastReputationScan >= REPUTATION_SCAN_THROTTLE then
            lastReputationScan = now
            local char = GetCurrentCharTable()
            if char and DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                DS:ScanReputations()
            end
        end
        return
    end
    if event == "MAIL_SHOW" then
        isMailOpen = true
        HookMailFrameVisibility()
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == MAIL_INTERACTION_TYPE then
            isMailOpen = true
            HookMailFrameVisibility()
        end
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "MAIL_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local interactionType = ...
            if interactionType ~= MAIL_INTERACTION_TYPE then
                return
            end
        end
        isMailOpen = false
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        isAuctionHouseOpen = true
        local char = GetCurrentCharTable()
        if char and DS.HasOwnedAuctionsApi and DS.HasOwnedAuctionsApi() and DS.ScanAuctions then
            DS:ScanAuctions()
        end
        if char and DS.HasBidAuctionsApi and DS.HasBidAuctionsApi() and DS.ScanBids then
            DS:ScanBids()
        end
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        isAuctionHouseOpen = false
        return
    end
    if event == "AUCTION_OWNED_LIST_UPDATE" or event == "OWNED_AUCTIONS_UPDATED"
        or event == "AUCTION_HOUSE_AUCTION_CREATED" then
        if isAuctionHouseOpen and DS.HasOwnedAuctionsApi and DS.HasOwnedAuctionsApi() and DS.ScanAuctions then
            local char = GetCurrentCharTable()
            if char then DS:ScanAuctions() end
        end
        return
    end
    if event == "AUCTION_BIDDER_LIST_UPDATE" or event == "BIDS_UPDATED" then
        if isAuctionHouseOpen and DS.HasBidAuctionsApi and DS.HasBidAuctionsApi() and DS.ScanBids then
            local char = GetCurrentCharTable()
            if char then DS:ScanBids() end
        end
        return
    end
    if event == "BAG_UPDATE" then
        local char = GetCurrentCharTable()
        if not char then return end
        if isMailOpen and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        local bagID = a1
        local role = DS.GetBagRole and DS:GetBagRole(bagID)
        if type(bagID) == "number" then
            if role == "backpack" or role == "bag" or role == "reagentbag" or role == "keyring" then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBags then DS:ScanBags() end
            elseif isBankOpen and (role == "bank" or role == "bankbag") then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBank then DS:ScanBank() end
            end
        else
            if DS.ScanBags then DS:ScanBags() end
            if isBankOpen and DS.ScanBank then DS:ScanBank() end
        end
        return
    end
    if event == "BANKFRAME_OPENED" then
        isBankOpen = true
        local char = GetCurrentCharTable()
        if char and DS.ScanBank then DS:ScanBank() end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        isBankOpen = false
        return
    end
    if event == "PLAYERBANKSLOTS_CHANGED" then
        if isBankOpen and DS.ScanBank then
            local char = GetCurrentCharTable()
            if char then DS:ScanBank() end
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local char = GetCurrentCharTable()
        if char and DS.ScanEquipment then DS:ScanEquipment() end
        return
    end
    if event == "PLAYER_LOGOUT" then
        local char = GetCurrentCharTable()
        if char then
            char.lastLogout = time()
            char.lastUpdate = time()
        end
        return
    end
    if event == "PLAYER_GUILD_UPDATE" then
        if DS.HandlePlayerGuildUpdate then DS:HandlePlayerGuildUpdate() end
        return
    end
    if event == "PLAYER_MONEY" then
        local char = GetCurrentCharTable()
        if char and GetMoney then
            char.money = GetMoney()
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local char = GetCurrentCharTable()
        if char then
            if UnitLevel then
                char.level = UnitLevel("player") or char.level
            end
            if UnitXP and UnitXPMax then
                char.xp = UnitXP("player") or 0
                char.xpMax = UnitXPMax("player") or 0
            end
            if GetXPExhaustion then
                char.restXP = GetXPExhaustion() or 0
            end
            if char.level == DS.MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = addonName
        local char = GetCurrentCharTable()
        if char and UnitLevel then
            char.level = UnitLevel("player") or newLevel
            if char.level == DS.MAX_LEVEL then
                char.restXP = 0
            end
        end
        if DS.BeginPendingLevelUp then
            DS:BeginPendingLevelUp(newLevel or (char and char.level))
        end
        local Comm = AltArmy and AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then
            Comm.ScheduleBroadcast()
        end
        return
    end
    if event == "TIME_PLAYED_MSG" then
        local totalTimePlayed, timePlayedThisLevel = addonName, a1
        local char = GetCurrentCharTable()
        if char and totalTimePlayed and type(totalTimePlayed) == "number" then
            char.played = totalTimePlayed
            if type(timePlayedThisLevel) == "number" then
                char.playedThisLevel = timePlayedThisLevel
            end
            if DS.OnTimePlayedMessage then
                DS:OnTimePlayedMessage(totalTimePlayed, timePlayedThisLevel)
            end
            if AltArmy.BankAltDetect and AltArmy.BankAltDetect.TryPromptForCurrentCharacter then
                AltArmy.BankAltDetect.TryPromptForCurrentCharacter()
            end
        end
        return
    end
end)
