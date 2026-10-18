-- AltArmy TBC — DataStore module: character (name, level, class, money, XP, rest).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local MAX_LEVEL = DS.MAX_LEVEL
local MAX_LOGOUT_SENTINEL = 5000000000

function DS:ScanCharacter(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    local realm = DS:GetCurrentPlayerRealm()
    local fullName = DS:GetCurrentPlayerName()
    local guid = DS:GetCurrentPlayerGUID()
    -- Adopt this character's older entries (same GUID, or saved under its full name before GUIDs).
    DS._FoldLegacyEntries(nil, realm, guid, fullName, char)
    if fullName ~= "" then
        -- Renamed (paid rename, or WoW Forever now reporting the surname): carry settings over.
        if char.name and char.name ~= fullName and AltArmy.RekeyCharSettings then
            AltArmy.RekeyCharSettings(realm, char.name, fullName)
        end
        char.name = fullName
    end
    char.realm = realm
    char.guid = guid or char.guid
    char.level = (UnitLevel and UnitLevel("player")) or 0
    char.money = (GetMoney and GetMoney()) or 0
    char.lastUpdate = time()
    if UnitClass then
        local loc, eng = UnitClass("player")
        char.class = loc
        char.classFile = eng and eng:upper() or ""
    else
        char.class = ""
        char.classFile = ""
    end
    if UnitRace then
        local raceLoc, raceEng = UnitRace("player")
        char.race = raceLoc or ""
        char.raceFile = raceEng and raceEng:upper() or ""
    else
        char.race = ""
        char.raceFile = ""
    end
    if UnitSex then
        char.sex = UnitSex("player") or 2
    else
        char.sex = 2
    end
    if UnitFactionGroup then
        char.faction = UnitFactionGroup("player") or ""
    else
        char.faction = ""
    end
    -- Guild membership (needed by guild data sharing; nil = not in a guild).
    DS:ScanGuildMembership()
    if GetMoney then
        char.money = GetMoney()
    end
    if UnitXP and UnitXPMax then
        char.xp = UnitXP("player") or 0
        char.xpMax = UnitXPMax("player") or 0
    else
        char.xp = 0
        char.xpMax = 0
    end
    if GetXPExhaustion then
        char.restXP = GetXPExhaustion() or 0
    else
        char.restXP = 0
    end
    if char.level == MAX_LEVEL then
        char.restXP = 0
    end
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.character = DATA_VERSIONS.character
    if DS.ClaimOrphanLevelHistory then
        DS:ClaimOrphanLevelHistory(char.name, char.realm, char)
    end
end

--- Refresh stored guild membership for the current character (join/leave/promote).
function DS:ScanGuildMembership(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    char.dataVersions = char.dataVersions or {}
    if GetGuildInfo then
        local guildName = GetGuildInfo("player")
        char.guildName = (guildName ~= "" and guildName) or nil
        char.dataVersions.guildMembership = DATA_VERSIONS.guildMembership
    end
    if AltArmy.UpdateGuildTabVisibility then
        AltArmy.UpdateGuildTabVisibility()
    end
end

function DS:GetCharacterName(char)
    return char and char.name or ""
end

function DS:GetCharacterLevel(char)
    return (char and char.level) or 0
end

function DS:GetMoney(char)
    return (char and char.money) or 0
end

function DS:GetPlayTime(char)
    if not char then return 0 end
    if DS.GetDerivedPlayedTotal then
        local current = GetCurrentCharTable()
        if current and char == current then
            return DS:GetDerivedPlayedTotal()
        end
    end
    return char.played or 0
end

function DS:GetLastLogout(char)
    return (char and char.lastLogout) or MAX_LOGOUT_SENTINEL
end

function DS:GetCharacterClass(char)
    if not char then return "", "" end
    return char.class or "", char.classFile or ""
end

function DS:GetCharacterFaction(char)
    return (char and char.faction) or ""
end

--- Faction of the logged-in character ("Alliance", "Horde", or "" when unknown).
function DS:GetCurrentPlayerFaction()
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    if faction == "" then
        faction = DS:GetCharacterFaction(GetCurrentCharTable())
    end
    return faction
end

--- False only when both factions are known and differ (gear compare / upgrade alerts).
function DS:IsSameFactionAsCurrent(char)
    local faction = DS:GetCharacterFaction(char)
    local current = DS:GetCurrentPlayerFaction()
    return faction == "" or current == "" or faction == current
end

--- Guild name for a character, or nil when the character is not in a guild.
function DS:GetCharacterGuild(char)
    return char and char.guildName or nil
end

--- Rest-cap/accumulation multiplier from the "Well Rested" Legacy Talent (WoW Forever), 1 when
--- unavailable/not spent — see DataStoreLegacy.lua.
local function getRestXpMultiplier(char)
    local DL = AltArmy.DataStoreLegacy
    if DL and DL.GetRestXpMultiplier then
        return DL.GetRestXpMultiplier(char)
    end
    return 1
end

function DS:GetStoredRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5 * getRestXpMultiplier(char)
    return math.min(100, (restXP / maxRest) * 100)
end

--- Seconds a logged-out character takes to earn one rest bubble (5% of a level): 8 hours in an inn or
--- city, four times that elsewhere. A character saved before the addon kept `isResting` counts as resting.
DS.REST_BUBBLE_SECONDS = 28800
DS.REST_BUBBLE_SECONDS_NOT_RESTING = 28800 * 4

--- Rest XP in amounts: { max, current, secondsToFull }, nil at max level or without an XP bar.
--- An offline character's rest is predicted since its logout (a bubble, 5% of a level, every
--- REST_BUBBLE_SECONDS, four times as long when it logged out outside a resting area). `live`, for a
--- character logged in now, gives { restXP, xpMax, resting } read from the game. secondsToFull is 0 when
--- full, nil when the rest isn't growing (online outside a resting area) or can't be told.
function DS:GetRestXpInfo(char, live)
    if not char or char.level == MAX_LEVEL then return nil end
    local xpMax = (live and live.xpMax) or char.xpMax or 0
    if xpMax <= 0 then return nil end
    local restMultiplier = getRestXpMultiplier(char)
    local maxRest = xpMax * 1.5 * restMultiplier
    local oneXPBubble = (xpMax / 20) * restMultiplier
    local restXP = (live and live.restXP) or char.restXP or 0
    local bubbleSeconds
    if live then
        bubbleSeconds = live.resting and DS.REST_BUBBLE_SECONDS or nil
    else
        local lastLogout = char.lastLogout or MAX_LOGOUT_SENTINEL
        if lastLogout < MAX_LOGOUT_SENTINEL then
            bubbleSeconds = char.isResting == false and DS.REST_BUBBLE_SECONDS_NOT_RESTING
                or DS.REST_BUBBLE_SECONDS
            restXP = restXP + math.max(0, (time() - lastLogout) / bubbleSeconds * oneXPBubble)
        end
    end
    restXP = math.min(restXP, maxRest)
    local secondsToFull
    if restXP >= maxRest then
        secondsToFull = 0
    elseif bubbleSeconds then
        secondsToFull = (maxRest - restXP) / oneXPBubble * bubbleSeconds
    end
    return { max = maxRest, current = restXP, secondsToFull = secondsToFull }
end

--- Rest XP as a percent (0-100) of the most a character can hold, predicted since its logout.
function DS:GetRestXp(char)
    local info = DS:GetRestXpInfo(char)
    if not info then return 0 end
    return math.min(100, (info.current / info.max) * 100)
end
