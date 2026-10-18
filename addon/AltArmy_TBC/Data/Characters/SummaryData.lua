-- AltArmy TBC — Summary data layer: character list for the Summary tab.
-- Summary list entries (SavedVariables / DataStore): name, realm, level, restXp, wellRestedRank,
-- isMaxLevel, money, played, lastOnline.
-- luacheck: globals GetSpellInfo

AltArmy.SummaryData = AltArmy.SummaryData or {}

local MAX_LOGOUT_SENTINEL = 5000000000
local MAX_LEVEL = (AltArmy.DataStore and AltArmy.DataStore.MAX_LEVEL) or 70

-- Formatting helpers (raw values in entry; format in UI or here for display)

-- Coin icon texture escape sequences (game's gold/silver/copper icons); size 12 to match small font
local COIN_ICON_SIZE = 12
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"

--- Layout for Summary name-column status icons (main star / bank alt) after the class icon.
--- Returns mainX/bankX (nil when hidden) and nameTextLeft for the name font string.
function AltArmy.SummaryData.GetNameStatusIconLayout(classIconSize, statusIconSize, gap, isMain, isBankAlt)
    classIconSize = classIconSize or 16
    statusIconSize = statusIconSize or 16
    gap = gap or 2
    local x = classIconSize + gap
    local mainX, bankX
    if isMain then
        mainX = x
        x = x + statusIconSize + gap
    end
    if isBankAlt then
        bankX = x
        x = x + statusIconSize + gap
    end
    return {
        mainX = mainX,
        bankX = bankX,
        nameTextLeft = x,
    }
end

--- Copper to amount + gold/silver/copper icons. Skips leading zeros; shows zeros once a significant digit appears.
function AltArmy.SummaryData.GetMoneyString(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRem = copper % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. GOLD_ICON)
        table.insert(parts, silver .. SILVER_ICON)
        table.insert(parts, copperRem .. COPPER_ICON)
    elseif silver > 0 then
        table.insert(parts, silver .. SILVER_ICON)
        table.insert(parts, copperRem .. COPPER_ICON)
    else
        table.insert(parts, copperRem .. COPPER_ICON)
    end
    return table.concat(parts, " ")
end

--- Seconds to readable string (e.g. "2d 3h"). Uses SecondsToTime if available.
function AltArmy.SummaryData.GetTimeString(seconds)
    seconds = seconds or 0
    if SecondsToTime then
        return SecondsToTime(seconds)
    end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local parts = {}
    if d > 0 then table.insert(parts, d .. "d") end
    if h > 0 then table.insert(parts, h .. "h") end
    if m > 0 or #parts == 0 then table.insert(parts, m .. "m") end
    return table.concat(parts, " ")
end

--- Seconds to a single-unit played-time string (e.g. "4.0 d", "1.5 h"). Rounded to nearest 0.1.
--- @param unitStyle string|nil "full" for words (days, hours, …); default abbreviated (d, h, …).
function AltArmy.SummaryData.FormatPlayedSingleUnit(seconds, unitStyle)
    seconds = tonumber(seconds) or 0
    local unitKey
    local value
    if seconds >= 86400 then
        value = seconds / 86400
        unitKey = "d"
    elseif seconds >= 3600 then
        value = seconds / 3600
        unitKey = "h"
    elseif seconds >= 60 then
        value = seconds / 60
        unitKey = "m"
    else
        value = seconds
        unitKey = "s"
    end
    local units = (unitStyle == "full")
        and { d = "days", h = "hours", m = "mins", s = "secs" }
        or { d = "d", h = "h", m = "m", s = "s" }
    local rounded = math.floor(value * 10 + 0.5) / 10
    return string.format("%.1f %s", rounded, units[unitKey])
end

--- Last online: timestamp (number), nil = current/Online, MAX_LOGOUT_SENTINEL = unknown.
--- isCurrent: true if this is the logged-in character. Never shows seconds (days/hours/minutes only).
function AltArmy.SummaryData.FormatLastOnline(lastLogout, isCurrent)
    if isCurrent then
        return "Online"
    end
    if not lastLogout or lastLogout >= MAX_LOGOUT_SENTINEL then
        return "Unknown"
    end
    local ago = time() - lastLogout
    if ago < 60 then
        return "Just now"
    end
    local d = math.floor(ago / 86400)
    local h = math.floor((ago % 86400) / 3600)
    local m = math.floor((ago % 3600) / 60)
    if d > 0 then return d .. "d ago" end
    if h > 0 then return h .. "h ago" end
    return m .. "m ago"
end

--- Build rest XP display: rate is 0-100 (or 0-150). Round to nearest 0.1, show one decimal (e.g. "50.3%").
function AltArmy.SummaryData.FormatRestXp(rate)
    if rate == nil then return "" end
    local rounded = math.floor(rate * 10 + 0.5) / 10
    return string.format("%.1f%%", rounded)
end

-- Returns a list of character entries: { name, realm, level, restXp, isMaxLevel, money, played, lastOnline }
-- Raw values (copper, seconds, timestamp); formatting in UI.
function AltArmy.SummaryData.GetCharacterList()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter then
        return list
    end

    (DS.ForEachCharacterInScope or DS.ForEachCharacter)(DS, function(realm, charName, charData, linkId)
            local name = DS:GetCharacterName(charData) or charName
            -- a linked account's copy of this character is not the one logged in here
            local isCurrent = not linkId and DS:IsCurrentCharacter(name, realm)
            -- a linked account's character it is logged in on right now
            local LS = linkId and AltArmy.LinkSession
            local linkedOnline = LS and LS.IsOnline and LS.IsOnline(charData.guid) or false
            local level = DS:GetCharacterLevel(charData) or 0
            -- Fractional level (level + xp progress) for display with one decimal, rounded down
            local xp = isCurrent and (UnitXP and UnitXP("player")) or charData.xp
            local xpMax = isCurrent and (UnitXPMax and UnitXPMax("player")) or charData.xpMax
            if xp and xpMax and xpMax > 0 then
                level = level + xp / xpMax
            end
            local money = DS:GetMoney(charData) or 0
            if DS.GetMailMoneyTotal then
                money = money + (DS:GetMailMoneyTotal(charData) or 0)
            end
            local played = DS:GetPlayTime(charData) or 0
            local lastLogout = DS:GetLastLogout(charData) or MAX_LOGOUT_SENTINEL
            local classLoc, classFile = DS:GetCharacterClass(charData)
            local isMaxLevel = math.floor(level) == MAX_LEVEL
            local DL = AltArmy.DataStoreLegacy
            local wellRestedRank = 0
            if not isMaxLevel and DL and DL.GetWellRestedRank then
                wellRestedRank = DL.GetWellRestedRank(charData)
            end
            local restInfo
            if not isMaxLevel and DS.GetRestXpInfo then
                local live
                if isCurrent and UnitXPMax and GetXPExhaustion then
                    live = {
                        restXP = GetXPExhaustion() or 0,
                        xpMax = UnitXPMax("player") or 0,
                        resting = IsResting and IsResting() or false,
                    }
                end
                restInfo = DS:GetRestXpInfo(charData, live)
                -- a linked account's character online now: its rest as last synced, growing or not
                if restInfo and linkedOnline then restInfo.secondsToFull = nil end
            end
            local restRate = restInfo and math.min(100, (restInfo.current / restInfo.max) * 100) or 0
            local bagSlots = (DS.GetNumBagSlots and DS:GetNumBagSlots(charData)) or 0
            local bagFree = (DS.GetNumFreeBagSlots and DS:GetNumFreeBagSlots(charData)) or 0
            local equipmentCount = 0
            if charData.Inventory then
                for _ in pairs(charData.Inventory) do
                    equipmentCount = equipmentCount + 1
                end
            end
            local avgItemLevel = (DS.GetAverageItemLevel and DS:GetAverageItemLevel(charData)) or 0
            table.insert(list, {
                name = name,
                realm = realm or "",
                faction = charData.faction,
                linkId = linkId,
                level = level,
                restXp = restRate,
                restMax = restInfo and restInfo.max or nil,
                restCurrent = restInfo and restInfo.current or nil,
                restSecondsToFull = restInfo and restInfo.secondsToFull or nil,
                wellRestedRank = wellRestedRank,
                isMaxLevel = isMaxLevel,
                -- logged out outside an inn or city (false, not nil: unknown from before it was saved)
                notResting = not (isCurrent or linkedOnline) and not isMaxLevel
                    and charData.isResting == false or nil,
                money = money,
                played = played,
                lastOnline = (isCurrent or linkedOnline) and nil or lastLogout,
                isOnline = (isCurrent or linkedOnline) and true or nil,
                class = classLoc or "",
                classFile = classFile or "",
                bagSlots = bagSlots,
                bagFree = bagFree,
                equipmentCount = equipmentCount,
                avgItemLevel = avgItemLevel,
            })
    end)
    return list
end

-- Module name -> instruction when that module's data has not been gathered
-- (mail, auctions excluded: do not warn for mailbox or auction house)
local MODULE_INSTRUCTIONS = {
    containers = "* Open your bags or visit a bank",
    equipment = "* Log in with this character",
    professions = "* Open your Skills window (P)",
    reputations = "* Open your Reputation panel",
    currencies = "* Open your bags or visit a bank",
}


local function charHasLegacyReputationScalars(char)
    if not char or not char.Reputations then return false end
    for _, v in pairs(char.Reputations) do
        if type(v) == "number" then return true end
    end
    return false
end

-- Profession spell IDs (TBC) — localized skill names from GetSpellInfo match DataStore Professions keys.
local SPELL_ID_ALCHEMY = 2259
local SPELL_ID_TAILORING = 3908
local SPELL_ID_POISONS = 2842
local COOLDOWN_SPEC_SCAN_MIN_LEVEL = 60
local COOLDOWN_SPEC_SCAN_MIN_PROF_RANK = 350
local POISONS_UNLOCK_LEVEL = 20

local function getPoisonsProfessionName()
    if GetSpellInfo then
        return GetSpellInfo(SPELL_ID_POISONS) or "Poisons"
    end
    return "Poisons"
end

local function characterHasPoisonsSkill(char, DS)
    local poisonsName = getPoisonsProfessionName()
    if char.Professions and char.Professions[poisonsName] then
        return true
    end
    if DS and DS.GetNumRecipes and (DS:GetNumRecipes(char, poisonsName) or 0) > 0 then
        return true
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, SPELL_ID_POISONS)
        if ok and known then
            return true
        end
    end
    return false
end

local function needsPoisonsWindowScan(char, DS)
    if not char or not DS or not DS.GetCharacterClass or not DS.GetCharacterLevel then
        return false
    end
    local _, classFile = DS:GetCharacterClass(char)
    if classFile ~= "ROGUE" then
        return false
    end
    if not DS.HasModuleData or not DS:HasModuleData(char, "professions") then
        return false
    end
    local level = tonumber(DS:GetCharacterLevel(char)) or 0
    if math.floor(level) < POISONS_UNLOCK_LEVEL then
        return false
    end
    if not characterHasPoisonsSkill(char, DS) then
        return false
    end
    local poisonsName = getPoisonsProfessionName()
    local prof = char.Professions and char.Professions[poisonsName]
    local rank = prof and prof.rank or 0
    local numRecipes = DS.GetNumRecipes and DS:GetNumRecipes(char, poisonsName) or 0
    if rank > 0 and numRecipes > 0 then
        return false
    end
    -- rank > 0 with no recipes is handled by the generic per-profession loop below.
    if rank > 0 and numRecipes == 0 then
        return false
    end
    return true
end

--- True after DataStoreProfessions:ScanCooldownSpecializations has written boolean flags (even if all false).
local function hasPersistedCooldownSpecializations(char)
    local cs = char and char.cooldownSpecs
    if type(cs) ~= "table" then
        return false
    end
    return rawget(cs, "masterTransmutation") ~= nil
end

local function tailoringOrAlchemyAtLeastRank(char, minRank)
    local gsi = _G.GetSpellInfo
    if type(gsi) ~= "function" or not char or not char.Professions then
        return false
    end
    local profs = char.Professions
    local alchName = gsi(SPELL_ID_ALCHEMY)
    local tailorName = gsi(SPELL_ID_TAILORING)
    local alchR = (alchName and profs[alchName] and profs[alchName].rank) or 0
    local tailR = (tailorName and profs[tailorName] and profs[tailorName].rank) or 0
    return alchR >= minRank or tailR >= minRank
end

--- High-level toons with tailoring or alchemy may be missing cooldown specialization flags until login scan runs.
local function needsCooldownSpecializationScan(char, DS)
    if hasPersistedCooldownSpecializations(char) then
        return false
    end
    local level = 0
    if DS and DS.GetCharacterLevel then
        level = tonumber(DS:GetCharacterLevel(char)) or 0
    elseif char and char.level then
        level = tonumber(char.level) or 0
    end
    if math.floor(level) < COOLDOWN_SPEC_SCAN_MIN_LEVEL then
        return false
    end
    return tailoringOrAlchemyAtLeastRank(char, COOLDOWN_SPEC_SCAN_MIN_PROF_RANK)
end

local function resolveIsCurrentChar(name, realm)
    local DS = AltArmy.DataStore
    if DS and DS.IsCurrentCharacter then
        return DS:IsCurrentCharacter(name, realm)
    end
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = GetRealmName and GetRealmName() or ""
    return (name == currentName and realm == currentRealm)
end

local function addUniqueInstruction(out, line)
    if not out or not line or line == "" then return end
    for _, existing in ipairs(out.instructions) do
        if existing == line then
            return
        end
    end
    table.insert(out.instructions, line)
end

local function needsGuildMembershipScan(char, DS)
    if not char or not DS then return false end
    if not DS.HasModuleData or not DS:HasModuleData(char, "character") then
        return false
    end
    return DS.NeedsRescan and DS:NeedsRescan(char, "guildMembership")
end

local function appendGuildMembershipMissingInstructions(out, char, DS, isCurrent)
    if not needsGuildMembershipScan(char, DS) then return end
    if isCurrent then
        addUniqueInstruction(out, "* /reload or log in again to refresh guild data")
    else
        addUniqueInstruction(out, "* Log in with this character")
    end
end

local function appendTalentMissingInstructions(out, char, isCurrent)
    local DT = AltArmy.DataStoreTalents
    if not DT or not DT.IsTalentEligible or not DT.IsTalentEligible(char) then
        return
    end
    if DT.HasTalentData and DT.HasTalentData(char) then
        return
    end
    if isCurrent then
        addUniqueInstruction(out, "* Open your Talents window")
    else
        addUniqueInstruction(out, "* Log in with this character")
    end
end

local function appendModuleMissingInstruction(out, char, DS, isCurrent, moduleName)
    -- Professions: skip the nag entirely on clients missing GetNumSkillLines/GetSkillLineInfo
    -- (e.g. WoW Forever) — there is no window the player can open that would gather this data.
    local skipUnreachable = moduleName == "professions"
        and DS.HasProfessionsListApi and not DS.HasProfessionsListApi()
    if not skipUnreachable and not (DS.HasModuleData and DS:HasModuleData(char, moduleName)) then
        if isCurrent then
            addUniqueInstruction(out, MODULE_INSTRUCTIONS[moduleName])
        else
            addUniqueInstruction(out, "* Log in with this character")
        end
    end
end

local function appendReputationMissingInstructions(out, char, DS, isCurrent)
    -- Reputation: stale data version and/or legacy scalar storage (pre-v2 snapshot rows)
    -- Containers v2 (equipped bag identity), v3 (slot counts) and mail v2 (message index) are
    -- additive and not worth a Summary warning.
    if DS.HasModuleData and DS:HasModuleData(char, "reputations") then
        local staleVersion = DS.NeedsRescan and DS:NeedsRescan(char, "reputations")
        local legacyScalars = charHasLegacyReputationScalars(char)
        if staleVersion or legacyScalars then
            if isCurrent then
                addUniqueInstruction(out, "* /reload or log in again to refresh reputation data")
            else
                addUniqueInstruction(out, "* Log in with this character")
            end
        end
    end
end

-- Lowercase names of professions with recipes but no window the player can open (WoW Forever's mage-only
-- Comprehension), so nothing the player does would gather them: never asked for. Not in
-- DS.NO_RECIPE_PROFESSION_KEYS_*, which would also stop their recipes being stored when learned.
local NO_WINDOW_TO_OPEN = {
    comprehension = true,
}

local function appendRecipeMissingInstructions(out, char, DS, isCurrent)
    -- Per-profession: no recipes yet, or recipes marked stale after NEW_RECIPE_LEARNED without UI.
    -- Skips professions with no recipe window at all (Fishing/Riding/Herbalism/Mining, plus
    -- Skinning on TBC's legacy API only — Forever's Skinning has real recipes); see
    -- DS.ProfessionHasNoRecipeWindow in DataStoreProfessions.lua, the shared source of truth this
    -- and GuildTabData.lua's crafting/gathering split both read from.
    -- Where recipes are read in the background at login (OwnRecipeRead, WoW Forever), an alt only needs
    -- logging in, for professions that can be read that way (not Fishing or gathering); the current
    -- character is still told to open the window should a read have failed. Comprehension is never asked
    -- for (NO_WINDOW_TO_OPEN).
    if DS.HasModuleData and DS:HasModuleData(char, "professions") and DS.GetProfessions and DS.GetNumRecipes then
        local professions = DS:GetProfessions(char)
        local needingRescan = char.professionsNeedingRecipeScan
        local R = AltArmy.OwnRecipeRead
        local readAtLogin = not isCurrent and R and R.HasApi and R.HasApi() and R.IsEnabled and R.IsEnabled()
        for profName, prof in pairs(professions or {}) do
            if not (DS.ProfessionHasNoRecipeWindow and DS.ProfessionHasNoRecipeWindow(profName))
                and not (type(profName) == "string" and NO_WINDOW_TO_OPEN[profName:lower()]) then
                local rank = (prof and prof.rank) or 0
                local needsOpen = (rank > 0 and DS:GetNumRecipes(char, profName) == 0)
                    or (type(needingRescan) == "table" and needingRescan[profName])
                if needsOpen and readAtLogin and R.CanRead and R.CanRead(profName) then
                    addUniqueInstruction(out, "* Log in with this character")
                elseif needsOpen then
                    addUniqueInstruction(out, "* Open your " .. profName .. " window")
                end
            end
        end
    end
end

--- Returns whether a character is missing any gathered data and a list of instructions for the tooltip.
--- @param name string Character name
--- @param realm string Realm name
--- @return table { hasMissing = boolean, instructions = string[] }
function AltArmy.SummaryData.GetMissingDataInfo(name, realm)
    local out = { hasMissing = false, instructions = {} }
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacter then return out end
    local char = DS:GetCharacter(name, realm)
    if not char then return out end

    local isCurrent = resolveIsCurrentChar(name, realm)

    for moduleName in pairs(MODULE_INSTRUCTIONS) do
        appendModuleMissingInstruction(out, char, DS, isCurrent, moduleName)
    end

    local GS = AltArmy and AltArmy.GearScore
    if GS and GS.IsGearScoreTBCClassicAvailable and GS.IsGearScoreTBCClassicAvailable()
        and DS.HasModuleData and not DS:HasModuleData(char, "gearScores") then
        if not isCurrent then
            addUniqueInstruction(out, "* Log in with this character")
        end
    end

    appendReputationMissingInstructions(out, char, DS, isCurrent)
    appendRecipeMissingInstructions(out, char, DS, isCurrent)

    if needsPoisonsWindowScan(char, DS) then
        local poisonsName = getPoisonsProfessionName()
        addUniqueInstruction(out, "* Open your " .. poisonsName .. " window")
    end

    -- Cooldown specialization passives (Master of Transmutation, Spellfire, etc.): filled on login scan.
    if needsCooldownSpecializationScan(char, DS) then
        addUniqueInstruction(out, "* Log in with this character")
    end

    appendGuildMembershipMissingInstructions(out, char, DS, isCurrent)
    appendTalentMissingInstructions(out, char, isCurrent)

    out.hasMissing = #out.instructions > 0
    return out
end

--- What `/altarmy export` would lack for a character: only what the export writes (ProfitExport.lua: the
--- character's GUID, professions and their recipes, Legacy talents, city reputations), with the same
--- instructions as GetMissingDataInfo. Takes the stored entry itself, so duplicate names can't mix up.
--- @param char table A stored character (AltArmyTBC_Data.Characters[realm][key])
--- @param realm string Realm name
--- @return table { hasMissing = boolean, instructions = string[] }
function AltArmy.SummaryData.GetExportMissingDataInfo(char, realm)
    local out = { hasMissing = false, instructions = {} }
    local DS = AltArmy.DataStore
    if not DS or type(char) ~= "table" then return out end
    local isCurrent = resolveIsCurrentChar(char.name, realm)

    -- Entries saved before character data v3 have no GUID; logging in stores it.
    if not isCurrent and (type(char.guid) ~= "string" or char.guid == "") then
        addUniqueInstruction(out, "* Log in with this character")
    end
    appendModuleMissingInstruction(out, char, DS, isCurrent, "professions")
    appendRecipeMissingInstructions(out, char, DS, isCurrent)
    if needsPoisonsWindowScan(char, DS) then
        addUniqueInstruction(out, "* Open your " .. getPoisonsProfessionName() .. " window")
    end
    appendModuleMissingInstruction(out, char, DS, isCurrent, "reputations")
    appendReputationMissingInstructions(out, char, DS, isCurrent)

    -- Legacy talents (WoW Forever's C_Traits) are read at login: an alt needs logging in. The current
    -- character's read already ran, so nothing the player does would fill it.
    local DL = AltArmy.DataStoreLegacy
    if not isCurrent and DL and DL.HasTraitsApi and DL.HasTraitsApi()
        and DS.NeedsRescan and DS:NeedsRescan(char, "legacyTalents") then
        addUniqueInstruction(out, "* Log in with this character")
    end

    out.hasMissing = #out.instructions > 0
    return out
end

--- Title (with |c-colored name) for missing-data tooltips.
local function buildMissingDataTitle(name, classFile)
    local CC = AltArmy.ClassColor
    local r, g, b = 1, 0.82, 0
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(classFile, r, g, b)
    end
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local n = name or ""
    return "Some data for " .. hex .. n .. "|r has not been gathered yet."
end

local function showInstructionsTooltip(owner, anchor, title, lines)
    if not owner or not GameTooltip or not title or not lines then return false end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, 1, 1, true)
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
    return true
end

--- @param name string
--- @param realm string
--- @param classFile string|nil
--- @return string|nil title, table|nil instructions
function AltArmy.SummaryData.GetMissingDataTooltip(name, realm, classFile)
    local info = AltArmy.SummaryData.GetMissingDataInfo(name, realm)
    if not info or not info.hasMissing then return nil, nil end
    return buildMissingDataTitle(name, classFile), info.instructions
end

--- Same GameTooltip presentation as the Summary warning column (white title, gold instructions).
--- @return boolean true if a tooltip was shown
function AltArmy.SummaryData.PresentMissingDataTooltip(owner, anchor, name, realm, classFile)
    local title, lines = AltArmy.SummaryData.GetMissingDataTooltip(name, realm, classFile)
    return showInstructionsTooltip(owner, anchor, title, lines)
end

local function colorCode(r, g, b)
    return string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

--- Whole XP amount with thousands separators ("12,345").
local function formatXp(amount)
    local digits = tostring(math.floor((tonumber(amount) or 0) + 0.5))
    local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

--- Tooltip over a Summary row's Rest XP cell: the name in class colour; the most rest XP it can hold, what
--- it has and how long until full; then the "Well Rested" talent when it has a rank, and a warning when it
--- logged out outside a resting area (entry.notResting).
--- @return boolean true if a tooltip was shown
function AltArmy.SummaryData.PresentRestXpTooltip(owner, anchor, entry)
    if not GameTooltip or not owner or not entry then return false end
    local CC = AltArmy.ClassColor
    local r, g, b = 1, 1, 1
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
    end
    local name = entry.name or ""
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(name, r, g, b)
    if entry.isMaxLevel then
        GameTooltip:AddLine("No rest XP at max level", 1, 0.82, 0)
    elseif entry.restMax then
        local seconds = entry.restSecondsToFull
        local timeText
        if seconds == nil then
            timeText = entry.isOnline and "--" or "Unknown"
        elseif seconds <= 0 then
            timeText = "Now"
        else
            timeText = AltArmy.SummaryData.GetTimeString(math.ceil(seconds))
        end
        GameTooltip:AddLine("Max Rest XP: " .. formatXp(entry.restMax), 1, 1, 1)
        GameTooltip:AddLine("Current Rest XP: " .. formatXp(entry.restCurrent), 1, 1, 1)
        GameTooltip:AddLine("Time until fully rested: " .. timeText, 1, 1, 1)
    else
        GameTooltip:AddLine("Rest XP unknown: log in with this character", 1, 0.82, 0)
    end
    local rank = tonumber(entry.wellRestedRank) or 0
    if rank > 0 and not entry.isMaxLevel then
        local DL = AltArmy.DataStoreLegacy or {}
        local percent = math.floor(rank * (DL.REST_TALENT_PERCENT_PER_RANK or 0.04) * 100 + 0.5)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Well Rested", string.format("Rank %d/%d", rank, DL.REST_TALENT_MAX_RANK or 5),
            1, 1, 1, 1, 0.82, 0)
        GameTooltip:AddLine(string.format("Rested XP cap and accumulation +%d%%", percent), 0.2, 1, 0.2, true)
    end
    if entry.notResting then
        local theme = AltArmy.Theme and AltArmy.Theme.COLORS
        local err = theme and theme.warningBlocking or { 1.00, 0.40, 0.30, 1.00 }
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(colorCode(r, g, b) .. name .. "|r" .. colorCode(err[1], err[2], err[3])
            .. " is not in a resting area|r", 1, 1, 1, true)
    end
    GameTooltip:Show()
    return true
end

--- Whether talent/spec data is missing for this character.
function AltArmy.SummaryData.GetTalentSpecMissingInfo(name, realm)
    local out = { hasMissing = false, instructions = {} }
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacter then return out end
    local char = DS:GetCharacter(name, realm)
    if not char then return out end

    local isCurrent = resolveIsCurrentChar(name, realm)
    appendTalentMissingInstructions(out, char, isCurrent)
    out.hasMissing = #out.instructions > 0
    return out
end

function AltArmy.SummaryData.GetTalentSpecMissingTooltip(name, realm, classFile)
    local info = AltArmy.SummaryData.GetTalentSpecMissingInfo(name, realm)
    if not info or not info.hasMissing then return nil, nil end
    return buildMissingDataTitle(name, classFile), info.instructions
end

function AltArmy.SummaryData.PresentTalentSpecMissingTooltip(owner, anchor, name, realm, classFile)
    local title, lines = AltArmy.SummaryData.GetTalentSpecMissingTooltip(name, realm, classFile)
    return showInstructionsTooltip(owner, anchor, title, lines)
end
