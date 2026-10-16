-- AltArmy TBC — Item usability: class armor/weapon rules, equip slots, effective level.
-- luacheck: globals GetItemInfo

AltArmy = AltArmy or {}
AltArmy.ItemUsability = AltArmy.ItemUsability or {}

local IU = AltArmy.ItemUsability
local DS = AltArmy.DataStore

-- Self-contained (no AltArmy.DataStore dependency) so this module's unit tests,
-- which stub GetItemInfo directly without loading the DataStore layer, keep working.
-- See docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md for why the C_Item fallback exists.
local function hasItemInfoApi()
    return GetItemInfo ~= nil or (C_Item ~= nil and C_Item.GetItemInfo ~= nil)
end

local function compatGetItemInfo(item)
    if GetItemInfo then return GetItemInfo(item) end
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
end

local ARMOR_SPEC_LEVEL = 40
local POLEARM_TRAIN_LEVEL = 20
-- Passive spells taught by the trainer at ARMOR_SPEC_LEVEL.
local ARMOR_PROFICIENCY_SPELLS = { mail = 8737, plate = 750 }

-- TBC class weapon proficiencies (subclass strings normalized to lowercase).
local WEAPON_PROFICIENCIES = {
    WARRIOR = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["polearms"] = true, ["staves"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
        ["shields"] = true,
    },
    PALADIN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["polearms"] = true,
        ["shields"] = true,
    },
    HUNTER = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["polearms"] = true, ["staves"] = true, ["daggers"] = true,
        ["fist weapons"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
    },
    ROGUE = {
        ["daggers"] = true, ["fist weapons"] = true,
        ["one-handed swords"] = true, ["one-handed maces"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
    },
    DRUID = {
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
    },
    SHAMAN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true,
        ["shields"] = true,
    },
    MAGE = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
    PRIEST = {
        ["daggers"] = true, ["one-handed maces"] = true, ["staves"] = true, ["wands"] = true,
    },
    WARLOCK = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
}

-- WoW equip location -> inventory slot IDs (1-19).
local INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}

-- Weapon types that show both main-hand and off-hand grid rows in focus mode.
local WEAPON_PAIR_DISPLAY_TYPES = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

local MAIN_AND_OFF_HAND_SLOTS = { 16, 17 }

local EQUIPLOC_TO_WEAPON_ROLE = {
    INVTYPE_2HWEAPON = "twohand",
    INVTYPE_RANGED = "ranged",
    INVTYPE_RANGEDRIGHT = "ranged",
    INVTYPE_WEAPON = "onehand",
    INVTYPE_WEAPONMAINHAND = "onehand",
    INVTYPE_WEAPONOFFHAND = "offhand",
    INVTYPE_SHIELD = "offhand",
    INVTYPE_HOLDABLE = "offhand",
}

local DUAL_WIELD_CLASS = {
    WARRIOR = true,
    ROGUE = true,
    HUNTER = true,
}

local function normalizeClassFile(classFile)
    return (classFile or ""):upper()
end

local weaponRoleCache = {}
local inventorySlotsCache = {}
local effectiveLevelCache = {}
local canNeverUseCache = {}
local pendingFrame

local function classLinkKey(classFile, link)
    return normalizeClassFile(classFile) .. "\0" .. tostring(link)
end

local function invalidateCachesForItemId(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end
    local needle = "item:" .. tostring(itemId)
    for link in pairs(weaponRoleCache) do
        if link:find(needle, 1, true) then
            weaponRoleCache[link] = nil
        end
    end
    for link in pairs(inventorySlotsCache) do
        if link:find(needle, 1, true) then
            inventorySlotsCache[link] = nil
        end
    end
    for key in pairs(effectiveLevelCache) do
        if key:find(needle, 1, true) then
            effectiveLevelCache[key] = nil
        end
    end
    for key in pairs(canNeverUseCache) do
        if key:find(needle, 1, true) then
            canNeverUseCache[key] = nil
        end
    end
end

local function ensurePendingFrame()
    if pendingFrame or not CreateFrame then return end
    pendingFrame = CreateFrame("Frame")
    if not pendingFrame.RegisterEvent then return end
    pendingFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pendingFrame:SetScript("OnEvent", function(_, _, itemId)
        invalidateCachesForItemId(itemId)
    end)
end

function IU.ClearCache()
    weaponRoleCache = {}
    inventorySlotsCache = {}
    effectiveLevelCache = {}
    canNeverUseCache = {}
end

--- True for WoW weapon subclass strings for fishing poles (singular or plural).
function IU.IsFishingPoleSubclass(weaponSubclass)
    if not weaponSubclass or weaponSubclass == "" then return false end
    local key = weaponSubclass:lower()
    return key == "fishing pole" or key == "fishing poles"
end

--- Parse GetItemInfo: returns itemLevel (iLvl), minLevel (required to equip).
local function getItemInfoLevels(link)
    if not link or not hasItemInfoApi() then return nil, nil end
    local name, _, _, itemLevel, minLevel = compatGetItemInfo(link)
    if not name then return nil, nil end
    return tonumber(itemLevel) or 0, tonumber(minLevel) or 0
end

--- Required character level to equip (item min level, not iLvl).
function IU.GetItemMinLevel(link)
    local _, minLevel = getItemInfoLevels(link)
    return minLevel
end

--- True if this class can ever wear this armor subclass.
function IU.CanClassEverUseArmor(classFile, subclass)
    if not subclass or subclass == "" then return true end
    classFile = normalizeClassFile(classFile)
    subclass = subclass:lower()
    if subclass == "cloth" then return true end
    if subclass == "leather" then
        return classFile ~= "MAGE" and classFile ~= "PRIEST" and classFile ~= "WARLOCK"
    end
    if subclass == "mail" then
        return classFile == "HUNTER" or classFile == "SHAMAN"
            or classFile == "WARRIOR" or classFile == "PALADIN"
    end
    if subclass == "plate" then
        return classFile == "WARRIOR" or classFile == "PALADIN"
    end
    return true
end

--- Extra weapon proficiencies granted only on WoW Forever, beyond TBC's WEAPON_PROFICIENCIES
--- (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md): Rogue gains one-handed axes there.
local FOREVER_EXTRA_WEAPON_PROFICIENCIES = {
    ROGUE = { ["one-handed axes"] = true },
    DRUID = { ["polearms"] = true },
}

--- True if this class can ever use this weapon subclass.
function IU.CanClassEverUseWeapon(classFile, weaponSubclass)
    if not weaponSubclass or weaponSubclass == "" then return true end
    if IU.IsFishingPoleSubclass(weaponSubclass) then return true end
    local key = weaponSubclass:lower()
    classFile = normalizeClassFile(classFile)
    local prof = WEAPON_PROFICIENCIES[classFile]
    if not prof then return true end
    if prof[key] == true then return true end
    local liveDS = AltArmy.DataStore
    if liveDS and liveDS.IsWowForever then
        local extra = FOREVER_EXTRA_WEAPON_PROFICIENCIES[classFile]
        if extra and extra[key] then return true end
    end
    return false
end

--- Parse item link for reqLevel, armor subclass, weapon subclass.
function IU.GetItemUseInfo(link)
    if not link or not hasItemInfoApi() then return nil, nil, nil end
    local name, _, _, _, minLevel, itemClass, subclass = compatGetItemInfo(link)
    if not name then return nil, nil, nil end
    local reqLevel = tonumber(minLevel) or 0
    local ic = itemClass and itemClass:lower() or ""
    if ic == "armor" or ic == "armour" then
        if subclass == "Shields" then
            return reqLevel, nil, subclass
        end
        return reqLevel, subclass, nil
    end
    if ic == "weapon" then
        return reqLevel, nil, subclass
    end
    return reqLevel, subclass, nil
end

--- Inventory slot IDs for an item link, or empty table.
function IU.GetInventorySlotsForItem(link)
    if not link or not hasItemInfoApi() then return {} end
    local cached = inventorySlotsCache[link]
    if cached then
        local out = {}
        for i = 1, #cached do
            out[i] = cached[i]
        end
        return out
    end
    local name = compatGetItemInfo(link)
    if not name then return {} end
    local equipLoc = select(9, compatGetItemInfo(link))
    if not equipLoc then return {} end
    local slots = INVTYPE_TO_SLOTS[equipLoc]
    if not slots then return {} end
    local stored = {}
    for i = 1, #slots do
        stored[i] = slots[i]
    end
    inventorySlotsCache[link] = stored
    ensurePendingFrame()
    local out = {}
    for i = 1, #stored do
        out[i] = stored[i]
    end
    return out
end

--- Weapon role for loadout comparison: twohand, onehand, offhand, ranged, or nil.
function IU.GetWeaponRole(link)
    if not link or not hasItemInfoApi() then return nil end
    local cached = weaponRoleCache[link]
    if cached ~= nil then return cached end
    local name = compatGetItemInfo(link)
    if not name then return nil end
    local equipLoc = select(9, compatGetItemInfo(link))
    if not equipLoc then return nil end
    local role = EQUIPLOC_TO_WEAPON_ROLE[equipLoc]
    weaponRoleCache[link] = role
    ensurePendingFrame()
    return role
end

--- True when class/spec can dual-wield one-handed weapons.
--- Enhancement Shaman's Dual Wield talent is TBC-only: WoW Forever's client
--- doesn't grant it (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md), so that
--- exception is skipped when AltArmy.DataStore.IsWowForever is set.
function IU.CanClassDualWield(classFile, specKey)
    classFile = normalizeClassFile(classFile)
    if DUAL_WIELD_CLASS[classFile] then return true end
    local liveDS = AltArmy.DataStore
    if classFile == "SHAMAN" and specKey == "enhancement" and not (liveDS and liveDS.IsWowForever) then
        return true
    end
    return false
end

--- Inventory slots to show in the gear grid when an item is focused (may be wider than equip slots).
function IU.GetFocusDisplaySlotsForItem(link)
    local slots = IU.GetInventorySlotsForItem(link)
    if not slots or #slots == 0 then return {} end
    if not link or not hasItemInfoApi() then return slots end
    local equipLoc = select(9, compatGetItemInfo(link))
    if WEAPON_PAIR_DISPLAY_TYPES[equipLoc] then
        return { MAIN_AND_OFF_HAND_SLOTS[1], MAIN_AND_OFF_HAND_SLOTS[2] }
    end
    return slots
end

--- Level at which the class can train this armor/weapon proficiency.
function IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
    if not subclass or subclass == "" then return 1 end
    classFile = normalizeClassFile(classFile)
    local ic = (itemClass or ""):lower()
    if ic == "armor" or ic == "armour" then
        local sub = subclass:lower()
        if sub == "plate" then
            if classFile == "WARRIOR" or classFile == "PALADIN" then
                return ARMOR_SPEC_LEVEL
            end
            return 999
        end
        if sub == "mail" then
            if classFile == "HUNTER" or classFile == "SHAMAN" then
                return ARMOR_SPEC_LEVEL
            end
            if classFile == "WARRIOR" or classFile == "PALADIN" then
                return 1
            end
            return 999
        end
        return 1
    end
    if ic == "weapon" then
        local sub = subclass:lower()
        if sub == "polearms" and IU.CanClassEverUseWeapon(classFile, subclass) then
            return POLEARM_TRAIN_LEVEL
        end
        if IU.CanClassEverUseWeapon(classFile, subclass) then
            return 1
        end
        return 999
    end
    return 1
end

--- max(item reqLevel, proficiency train level).
function IU.EffectiveRequiredLevel(classFile, link)
    if not link or not hasItemInfoApi() then return 999 end
    local cacheKey = classLinkKey(classFile, link)
    local cached = effectiveLevelCache[cacheKey]
    if cached ~= nil then return cached end
    local name, _, _, _, minLevel, itemClass, subclass = compatGetItemInfo(link)
    if not name then return 999 end
    local reqLevel = tonumber(minLevel) or 0
    classFile = normalizeClassFile(classFile)
    local ic = itemClass and itemClass:lower() or ""
    local effective
    if ic == "armor" or ic == "armour" then
        if subclass == "Shields" then
            if not IU.CanClassEverUseWeapon(classFile, "Shields") then
                effective = 999
            else
                effective = reqLevel
            end
        elseif not IU.CanClassEverUseArmor(classFile, subclass) then
            effective = 999
        else
            local train = IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
            effective = math.max(reqLevel, train)
        end
    elseif ic == "weapon" then
        if not IU.CanClassEverUseWeapon(classFile, subclass) then
            effective = 999
        else
            local train = IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
            effective = math.max(reqLevel, train)
        end
    else
        effective = reqLevel
    end
    effectiveLevelCache[cacheKey] = effective
    ensurePendingFrame()
    return effective
end

--- Whether character can equip within levelsAhead levels.
--- Returns equippable (bool), levelsUntil (number or 0), reason (string or nil).
function IU.IsEquippableWithin(classFile, level, link, levelsAhead)
    levelsAhead = tonumber(levelsAhead) or 0
    level = math.floor(tonumber(level) or 0)
    if not link then return false, 0, "no_item" end

    local reqLevel, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    if reqLevel == nil then return false, 0, "unknown_item" end

    classFile = normalizeClassFile(classFile)
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            return false, 0, "armor"
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return false, 0, "weapon"
        end
    end

    local effective = IU.EffectiveRequiredLevel(classFile, link)
    if effective >= 999 then
        return false, 0, "never"
    end

    if level + levelsAhead < effective then
        return false, effective - level, "level"
    end

    local equippableNow = level >= effective
    local levelsUntil = equippableNow and 0 or (effective - level)
    return true, levelsUntil, nil
end

--- Human-readable skill name for trainer message.
function IU.GetProficiencySkillName(itemClass, subclass)
    if not subclass or subclass == "" then return "the required skill" end
    local ic = (itemClass or ""):lower()
    if ic == "armor" or ic == "armour" then
        local sub = subclass:lower()
        if sub == "plate" then return "Plate Armor" end
        if sub == "mail" then return "Mail Armor" end
        if sub == "leather" then return "Leather Armor" end
        if sub == "cloth" then return "Cloth Armor" end
        if sub == "shields" then return "Shields" end
    end
    if IU.IsFishingPoleSubclass(subclass) then
        return "Fishing"
    end
    return subclass
end

--- True when this armor type must be learned from a trainer (plate/mail at 40).
function IU.RequiresTrainerProficiency(classFile, subclass, itemClass)
    if not subclass or subclass == "" then return false end
    return IU.MinLevelToTrainProficiency(classFile, subclass, itemClass) == ARMOR_SPEC_LEVEL
end

--- True if character has any equipped item of this armor subclass.
function IU.CharHasEquippedArmorSubclass(charData, subclass)
    if not charData or not charData.Inventory or not subclass or not hasItemInfoApi() then
        return false
    end
    local target = subclass:lower()
    for _, item in pairs(charData.Inventory) do
        if type(item) == "string" then
            local name, _, _, _, _, itemClass, itemSubclass = compatGetItemInfo(item)
            if name then
                local ic = itemClass and itemClass:lower() or ""
                if (ic == "armor" or ic == "armour")
                    and itemSubclass
                    and itemSubclass:lower() == target then
                    return true
                end
            end
        end
    end
    return false
end

local function isCurrentCharacter(classFile, charData)
    if not charData or not UnitClass or not UnitName then return false end
    -- Full name (WoW Forever's UnitName returns the surname separately); stored names are full.
    local liveDS = AltArmy.DataStore
    local playerName = (liveDS and liveDS.GetCurrentPlayerName and liveDS:GetCurrentPlayerName())
        or UnitName("player")
    if not playerName or playerName ~= charData.name then return false end
    local _, currentClass = UnitClass("player")
    return normalizeClassFile(classFile) == normalizeClassFile(currentClass)
end

--- True when character already knows an armor proficiency that requires training.
function IU.HasLearnedArmorProficiency(classFile, subclass, itemClass, charData, link)
    if not IU.RequiresTrainerProficiency(classFile, subclass, itemClass) then
        return true
    end
    if IU.CharHasEquippedArmorSubclass(charData, subclass) then
        return true
    end
    if isCurrentCharacter(classFile, charData) then
        local spellId = ARMOR_PROFICIENCY_SPELLS[subclass:lower()]
        if spellId and _G.IsSpellKnown then
            local ok, known = pcall(_G.IsSpellKnown, spellId)
            if ok and known ~= nil then return known == true end
        end
        if link and _G.IsUsableItem then
            return _G.IsUsableItem(link) == true
        end
    end
    return false
end

--- True when the item is armor the class learns from a trainer (mail/plate at 40) and the
--- character hasn't learned it, whatever their level: they can't wear it until they train.
function IU.LacksTrainedProficiency(classFile, link, charData)
    if not link or not hasItemInfoApi() then return false end
    local name, _, _, _, _, itemClass, subclass = compatGetItemInfo(link)
    if not name then return false end
    local ic = itemClass and itemClass:lower() or ""
    if ic ~= "armor" and ic ~= "armour" then return false end
    if not subclass or subclass == "" or subclass == "Shields" then return false end
    classFile = normalizeClassFile(classFile)
    if not IU.CanClassEverUseArmor(classFile, subclass) then return false end
    if not IU.RequiresTrainerProficiency(classFile, subclass, itemClass) then return false end
    return not IU.HasLearnedArmorProficiency(classFile, subclass, itemClass, charData, link)
end

--- True when character is high enough to train but has not learned armor proficiency.
function IU.NeedsProficiencyTraining(classFile, charLevel, link, charData)
    if not link or not hasItemInfoApi() then return false end
    local name, _, _, _, minLevel, itemClass, subclass = compatGetItemInfo(link)
    if not name then return false end
    local reqLevel = tonumber(minLevel) or 0
    classFile = normalizeClassFile(classFile)
    charLevel = math.floor(tonumber(charLevel) or 0)
    local ic = itemClass and itemClass:lower() or ""
    if ic ~= "armor" and ic ~= "armour" then return false end
    if not subclass or subclass == "" or subclass == "Shields" then return false end
    if not IU.CanClassEverUseArmor(classFile, subclass) then return false end
    if not IU.RequiresTrainerProficiency(classFile, subclass, itemClass) then return false end

    local trainLevel = IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
    if charLevel < trainLevel or charLevel < reqLevel then return false end

    return not IU.HasLearnedArmorProficiency(classFile, subclass, itemClass, charData, link)
end

local function charHasFishingSkill(charData, classFile, link)
    if charData and charData.Professions then
        for profName, prof in pairs(charData.Professions) do
            if profName:lower() == "fishing" and (tonumber(prof.rank) or 0) > 0 then
                return true
            end
        end
    end
    if isCurrentCharacter(classFile, charData) and link and _G.IsUsableItem then
        return _G.IsUsableItem(link) == true
    end
    return false
end

--- True when character meets item level but has not learned Fishing.
function IU.NeedsFishingTraining(classFile, charLevel, link, charData)
    if not link or not hasItemInfoApi() then return false end
    local name, _, _, _, minLevel, itemClass, subclass = compatGetItemInfo(link)
    if not name then return false end
    local ic = itemClass and itemClass:lower() or ""
    if ic ~= "weapon" then return false end
    if not IU.IsFishingPoleSubclass(subclass) then return false end
    charLevel = math.floor(tonumber(charLevel) or 0)
    local reqLevel = tonumber(minLevel) or 0
    if charLevel < reqLevel then return false end
    classFile = normalizeClassFile(classFile)
    if charHasFishingSkill(charData, classFile, link) then return false end
    return true
end

--- Class-colored first name for compare-panel warnings (full name goes in the hover tooltip).
local function formatWarningCharName(name, classFile)
    local CC = AltArmy.ClassColor
    if CC and CC.firstName then
        name = CC.firstName(name)
    end
    if CC and CC.wrapName then
        return CC.wrapName(name, classFile)
    end
    return name or "?"
end

local function getSoulboundOwnerNameAndClass(fallbackName, fallbackClass)
    if DS and DS.GetCurrentCharacter then
        local char = DS:GetCurrentCharacter()
        if char and char.name then
            return char.name, char.classFile or fallbackClass
        end
    end
    return fallbackName, fallbackClass
end

local SOULBOUND_ITEM_NAME_MAX = 30

local function soulboundWarningItemLabel(link)
    if not link or not hasItemInfoApi() then return "This item" end
    local name = compatGetItemInfo(link)
    if not name or name == "" or #name > SOULBOUND_ITEM_NAME_MAX then
        return "This item"
    end
    return name
end

local function formatSoulboundWarning(link, coloredOwnerName)
    return soulboundWarningItemLabel(link) .. " is soulbound to " .. coloredOwnerName
end

local function formatLevelsToGainPhrase(count)
    count = math.floor(tonumber(count) or 0)
    if count == 1 then return "1 level" end
    return tostring(count) .. " levels"
end

local function formatLevelRequirementWarning(coloredName, charLevel, effective)
    local levelsToGain = effective - charLevel
    return coloredName .. " must gain " .. formatLevelsToGainPhrase(levelsToGain)
        .. " to equip this"
end

--- Skill name for items the class can never equip (armor/weapon proficiency).
function IU.GetNeverEquipSkillName(classFile, link)
    if not link or not hasItemInfoApi() then return "the required skill" end
    local _, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    local _, _, _, _, _, itemClass, subclass = compatGetItemInfo(link)
    classFile = normalizeClassFile(classFile)
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            return IU.GetProficiencySkillName(itemClass or "Armor", armorSubclass)
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return IU.GetProficiencySkillName(itemClass or "Weapon", weaponSubclass)
        end
    end
    return IU.GetProficiencySkillName(itemClass, subclass)
end

IU.EQUIP_WARNING_KIND = {
    SOULBOUND = "soulbound",
    NEVER = "never",
    LEVEL = "level",
    TRAINING = "training",
}

--- nameText is the colored name as embedded in text; charName is the full name for the tooltip.
local function addEquipWarning(warnings, text, kind, charName, classFile, nameText)
    warnings[#warnings + 1] = {
        text = text,
        kind = kind,
        charName = charName,
        classFile = classFile,
        nameText = nameText,
    }
end

function IU.GetEquipWarningText(warning)
    if type(warning) == "table" then return warning.text end
    return warning
end

function IU.GetEquipWarningKind(warning)
    if type(warning) == "table" then return warning.kind end
    return nil
end

--- Warning lines for compare panel (soulbound, level, proficiency).
function IU.GetEquipWarnings(classFile, charLevel, charName, link, charData)
    local warnings = {}
    if not link then return warnings end
    charName = charName or "?"
    charLevel = math.floor(tonumber(charLevel) or 0)
    classFile = normalizeClassFile(classFile)

    if IU.IsBindOnPickup(link) then
        local ownerName, ownerClass = getSoulboundOwnerNameAndClass(charName, classFile)
        local coloredName = formatWarningCharName(ownerName, ownerClass)
        addEquipWarning(
            warnings,
            formatSoulboundWarning(link, coloredName),
            IU.EQUIP_WARNING_KIND.SOULBOUND,
            ownerName, ownerClass, coloredName)
    end

    if IU.CanNeverUseItem(classFile, link) then
        local skill = IU.GetNeverEquipSkillName(classFile, link)
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            coloredName .. " can never equip this (" .. skill .. ")",
            IU.EQUIP_WARNING_KIND.NEVER,
            charName, classFile, coloredName)
        return warnings
    end

    local effective = IU.EffectiveRequiredLevel(classFile, link)
    if effective < 999 and charLevel < effective then
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            formatLevelRequirementWarning(coloredName, charLevel, effective),
            IU.EQUIP_WARNING_KIND.LEVEL,
            charName, classFile, coloredName)
    end

    if IU.NeedsProficiencyTraining(classFile, charLevel, link, charData) then
        local _, _, _, _, _, itemClass, subclass = compatGetItemInfo(link)
        local skill = IU.GetProficiencySkillName(itemClass, subclass)
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            coloredName .. " must train " .. skill .. " to equip this",
            IU.EQUIP_WARNING_KIND.TRAINING,
            charName, classFile, coloredName)
    end

    if IU.NeedsFishingTraining(classFile, charLevel, link, charData) then
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            coloredName .. " must train Fishing to equip this",
            IU.EQUIP_WARNING_KIND.TRAINING,
            charName, classFile, coloredName)
    end

    return warnings
end

--- Whether class can never equip the item (for graying columns).
function IU.CanNeverUseItem(classFile, link)
    if not link then return false end
    local cacheKey = classLinkKey(classFile, link)
    local cached = canNeverUseCache[cacheKey]
    if cached ~= nil then return cached end
    local _, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    classFile = normalizeClassFile(classFile)
    local never = false
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            never = true
        end
    end
    if not never and weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            never = true
        end
    end
    if not never then
        local eff = IU.EffectiveRequiredLevel(classFile, link)
        if eff >= 999 then
            never = true
        end
    end
    canNeverUseCache[cacheKey] = never
    ensurePendingFrame()
    return never
end

local scanTooltip

local function getScanTooltip()
    if scanTooltip then return scanTooltip end
    if not CreateFrame then return nil end
    scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_ItemUsabilityScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

--- True when tooltip shows bind-on-pickup or quest item (not valid for item check / loot alerts).
function IU.IsBindOnPickup(link)
    if not link then return false end
    local tip = getScanTooltip()
    if not tip or not tip.SetHyperlink then return false end
    tip:ClearLines()
    tip:SetHyperlink(link)
    for i = 1, tip:NumLines() do
        local line = _G["AltArmyTBC_ItemUsabilityScanTooltipTextLeft" .. i]
        if line and line.GetText then
            local text = line:GetText() or ""
            if text:find("Binds when picked up") or text:find("Quest Item") or text:find("Soulbound") then
                return true
            end
        end
    end
    return false
end

--- Whether an item may be dropped on Item Check; returns ok, errorMessage.
function IU.ValidateItemCheckDrop(link)
    if not link or link == "" then
        return false, "Drop an item to check."
    end
    if not hasItemInfoApi() then
        return false, "Unknown item."
    end
    local name = compatGetItemInfo(link)
    if not name then
        return false, "Unknown item."
    end
    local slots = IU.GetInventorySlotsForItem(link)
    if not slots or #slots == 0 then
        return false, "This item cannot be equipped."
    end
    return true, nil
end
