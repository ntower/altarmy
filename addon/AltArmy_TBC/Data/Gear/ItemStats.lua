-- AltArmy TBC — Item stat extraction for gear compare/scoring.
-- Priority: GetItemStats / C_Item.GetItemStats → tooltip regex parsing.
-- luacheck: globals GetItemInfo GetItemStats UIParent CreateFrame

AltArmy = AltArmy or {}
AltArmy.ItemStats = AltArmy.ItemStats or {}

local IS = AltArmy.ItemStats

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

-- Same self-contained pattern; Forever has only C_Item.GetItemStats.
local function hasItemStatsApi()
    return GetItemStats ~= nil or (C_Item ~= nil and C_Item.GetItemStats ~= nil)
end

local function compatGetItemStats(link)
    if GetItemStats then return GetItemStats(link) end
    if C_Item and C_Item.GetItemStats then return C_Item.GetItemStats(link) end
end

IS.STAT_ALIASES = {
    -- Primary attributes
    ["ITEM_MOD_STRENGTH_SHORT"] = "str",
    ["ITEM_MOD_STRENGTH"] = "str",
    ["ITEM_MOD_AGILITY_SHORT"] = "agi",
    ["ITEM_MOD_AGILITY"] = "agi",
    ["ITEM_MOD_STAMINA_SHORT"] = "sta",
    ["ITEM_MOD_STAMINA"] = "sta",
    ["ITEM_MOD_INTELLECT_SHORT"] = "int",
    ["ITEM_MOD_INTELLECT"] = "int",
    ["ITEM_MOD_SPIRIT_SHORT"] = "spi",
    ["ITEM_MOD_SPIRIT"] = "spi",
    -- Armor and resistances (GetItemStats uses RESISTANCE*_NAME keys)
    ["RESISTANCE0_NAME"] = "armor",
    ["RESISTANCE1_NAME"] = "holy_res",
    ["RESISTANCE2_NAME"] = "fire_res",
    ["RESISTANCE3_NAME"] = "nature_res",
    ["RESISTANCE4_NAME"] = "frost_res",
    ["RESISTANCE5_NAME"] = "shadow_res",
    ["RESISTANCE6_NAME"] = "arcane_res",
    ["ITEM_MOD_EXTRA_ARMOR_SHORT"] = "bonus_armor",
    ["ITEM_MOD_EXTRA_ARMOR"] = "bonus_armor",
    -- Spell power / damage / healing
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = "sp",
    ["ITEM_MOD_SPELL_DAMAGE_DONE"] = "sp",
    ["ITEM_MOD_SPELL_DAMAGE"] = "sp",
    ["ITEM_MOD_SPELL_POWER_SHORT"] = "sp",
    ["ITEM_MOD_SPELL_POWER"] = "sp",
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = "heal",
    ["ITEM_MOD_SPELL_HEALING_DONE"] = "heal",
    -- Hit / crit (physical vs spell)
    ["ITEM_MOD_HIT_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RATING"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING"] = "hit",
    ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = "spell_hit",
    ["ITEM_MOD_HIT_SPELL_RATING"] = "spell_hit",
    ["ITEM_MOD_CRIT_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RATING"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING"] = "crit",
    ["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] = "spell_crit",
    ["ITEM_MOD_CRIT_SPELL_RATING"] = "spell_crit",
    -- Attack power / weapon
    ["ITEM_MOD_ATTACK_POWER_SHORT"] = "ap",
    ["ITEM_MOD_ATTACK_POWER"] = "ap",
    -- TBC Classic GetItemStats often exposes form-only AP as MELEE_ATTACK_POWER.
    ["ITEM_MOD_MELEE_ATTACK_POWER_SHORT"] = "feral_ap",
    ["ITEM_MOD_MELEE_ATTACK_POWER"] = "feral_ap",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = "rap",
    ["ITEM_MOD_RANGED_ATTACK_POWER"] = "rap",
    ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = "feral_ap",
    ["ITEM_MOD_FERAL_ATTACK_POWER"] = "feral_ap",
    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = "dps",
    -- Tank / avoidance
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = "def",
    ["ITEM_MOD_DEFENSE_SKILL_RATING"] = "def",
    ["ITEM_MOD_DODGE_RATING_SHORT"] = "dodge",
    ["ITEM_MOD_DODGE_RATING"] = "dodge",
    ["ITEM_MOD_PARRY_RATING_SHORT"] = "parry",
    ["ITEM_MOD_PARRY_RATING"] = "parry",
    ["ITEM_MOD_BLOCK_RATING_SHORT"] = "block",
    ["ITEM_MOD_BLOCK_RATING"] = "block",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"] = "blockval",
    ["ITEM_MOD_BLOCK_VALUE"] = "blockval",
    -- Regeneration
    ["ITEM_MOD_MANA_REGENERATION_SHORT"] = "mp5",
    ["ITEM_MOD_MANA_REGENERATION"] = "mp5",
    ["ITEM_MOD_POWER_REGEN0_SHORT"] = "mp5",
    ["ITEM_MOD_HEALTH_REGEN_SHORT"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGENERATION_SHORT"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGEN"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGENERATION"] = "health_regen",
    -- Health / mana (uncommon on gear but returned by GetItemStats)
    ["ITEM_MOD_HEALTH_SHORT"] = "health",
    ["ITEM_MOD_HEALTH"] = "health",
    ["ITEM_MOD_MANA_SHORT"] = "mana",
    ["ITEM_MOD_MANA"] = "mana",
    -- TBC-adjacent ratings that may appear on later patches / edge items
    ["ITEM_MOD_RESILIENCE_RATING_SHORT"] = "resilience",
    ["ITEM_MOD_RESILIENCE_RATING"] = "resilience",
    ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = "expertise",
    ["ITEM_MOD_EXPERTISE_RATING"] = "expertise",
    ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = "armor_pen",
    ["ITEM_MOD_ARMOR_PENETRATION_RATING"] = "armor_pen",
    ["ITEM_MOD_SPELL_PENETRATION_SHORT"] = "spell_pen",
    ["ITEM_MOD_SPELL_PENETRATION"] = "spell_pen",
    ["ITEM_MOD_HASTE_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_RATING"] = "haste",
    ["ITEM_MOD_HASTE_MELEE_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_MELEE_RATING"] = "haste",
    ["ITEM_MOD_HASTE_RANGED_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_RANGED_RATING"] = "haste",
    ["ITEM_MOD_HASTE_SPELL_RATING_SHORT"] = "spell_haste",
    ["ITEM_MOD_HASTE_SPELL_RATING"] = "spell_haste",
    -- Per-school spell damage (tooltip-only keys)
    ["ALTARMY_FIRE_SPELL"] = "fire_sp",
    ["ALTARMY_FROST_SPELL"] = "frost_sp",
    ["ALTARMY_ARCANE_SPELL"] = "arcane_sp",
    ["ALTARMY_SHADOW_SPELL"] = "shadow_sp",
    ["ALTARMY_NATURE_SPELL"] = "nature_sp",
    ["ALTARMY_HOLY_SPELL"] = "holy_sp",
    -- Movement speed (tooltip-only; currently only seen on conditional/situational effects).
    ["ALTARMY_MOVE_SPEED"] = "move_speed",
}

-- Resistance API keys fanned out together by "all Resistances"-style equip lines.
local ALL_RESISTANCE_KEYS = {
    "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
    "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME",
}

-- English display labels for normalized stat keys (compare panel, debug).
IS.STAT_LABELS = {
    str = "Strength",
    agi = "Agility",
    sta = "Stamina",
    int = "Intellect",
    spi = "Spirit",
    armor = "Armor",
    bonus_armor = "Bonus Armor",
    holy_res = "Holy Resistance",
    fire_res = "Fire Resistance",
    nature_res = "Nature Resistance",
    frost_res = "Frost Resistance",
    shadow_res = "Shadow Resistance",
    arcane_res = "Arcane Resistance",
    sp = "Spell Damage",
    heal = "Healing",
    hit = "Hit Rating",
    crit = "Crit Rating",
    spell_hit = "Spell Hit Rating",
    spell_crit = "Spell Crit Rating",
    spell_haste = "Spell Haste Rating",
    fire_sp = "Fire Spell Damage",
    frost_sp = "Frost Spell Damage",
    arcane_sp = "Arcane Spell Damage",
    shadow_sp = "Shadow Spell Damage",
    nature_sp = "Nature Spell Damage",
    holy_sp = "Holy Spell Damage",
    ap = "Attack Power",
    rap = "Ranged AP",
    feral_ap = "Attack Power In Forms",
    melee_dps = "Melee DPS",
    ranged_dps = "Ranged DPS",
    def = "Defense",
    dodge = "Dodge",
    parry = "Parry",
    block = "Block",
    blockval = "Block Value",
    mp5 = "Mana Regen",
    health_regen = "Health Regen",
    health = "Health",
    mana = "Mana",
    resilience = "Resilience",
    expertise = "Expertise",
    armor_pen = "Armor Penetration",
    spell_pen = "Spell Penetration",
    haste = "Haste",
    move_speed = "Movement Speed",
}

local PRIMARY_STAT_DEFS = {
    { apiKey = "ITEM_MOD_STRENGTH_SHORT", label = "Strength" },
    { apiKey = "ITEM_MOD_AGILITY_SHORT", label = "Agility" },
    { apiKey = "ITEM_MOD_STAMINA_SHORT", label = "Stamina" },
    { apiKey = "ITEM_MOD_INTELLECT_SHORT", label = "Intellect" },
    { apiKey = "ITEM_MOD_SPIRIT_SHORT", label = "Spirit" },
}

-- Healing tooltip labels vary by client/patch and by addon overrides of
-- ITEM_MOD_SPELL_HEALING_DONE_SHORT (e.g. "Bonus Healing" vs "Healing").
local HEALING_TOOLTIP_LABELS = {
    "Healing",
    "Bonus Healing",
    "Healing Spells",
}

-- Combined spell damage + healing on random suffix greens (e.g. "of the Sorcerer").
local COMBINED_SPELL_DAMAGE_HEAL_KEYS = {
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
}

local COMBINED_SPELL_TOOLTIP_LABELS = {
    "Spell Damage and Healing",
}

-- Per-school spell damage labels vary by client and addon tooltip reformatting
-- (e.g. "+59 Shadow Damage" vs equip-effect wording).
local SCHOOL_SPELL_TOOLTIP_DEFS = {
    { apiKey = "ALTARMY_FIRE_SPELL", labels = { "Fire Damage", "Fire Spell Damage" } },
    { apiKey = "ALTARMY_FROST_SPELL", labels = { "Frost Damage", "Frost Spell Damage" } },
    { apiKey = "ALTARMY_ARCANE_SPELL", labels = { "Arcane Damage", "Arcane Spell Damage" } },
    { apiKey = "ALTARMY_SHADOW_SPELL", labels = { "Shadow Damage", "Shadow Spell Damage" } },
    { apiKey = "ALTARMY_NATURE_SPELL", labels = { "Nature Damage", "Nature Spell Damage" } },
    { apiKey = "ALTARMY_HOLY_SPELL", labels = { "Holy Damage", "Holy Spell Damage" } },
}

local EQUIP_STAT_PATTERNS = {
    -- Form-only AP must be matched before the generic AP patterns below.
    { "^Equip: Increases attack power by (%d+) in Cat, Bear, Dire Bear, and Moonkin forms only%.$",
        "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
    { "^Equip: %+(%d+) Attack Power in Cat, Bear, Dire Bear, and Moonkin forms only%.$",
        "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
    { "^Equip: %+(%d+) Attack Power%.$", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "^Equip: Increases attack power by (%d+)%.$", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "^Equip: %+(%d+) Ranged Attack Power%.$", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    { "^Equip: Increases ranged attack power by (%d+)%.$", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    { "^%+(%d+) Hit Rating$", "ITEM_MOD_HIT_RATING_SHORT" },
    { "^%+(%d+) Critical Strike Rating$", "ITEM_MOD_CRIT_RATING_SHORT" },
    { "^%+(%d+) Spell Hit Rating$", "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    { "^%+(%d+) Spell Critical Strike Rating$", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    { "^%+(%d+) Spell Haste Rating$", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" },
    { "^Equip: Increases damage done by Fire spells and effects by up to (%d+)%.$",
        "ALTARMY_FIRE_SPELL" },
    { "^Equip: Increases damage done by Frost spells and effects by up to (%d+)%.$",
        "ALTARMY_FROST_SPELL" },
    { "^Equip: Increases damage done by Arcane spells and effects by up to (%d+)%.$",
        "ALTARMY_ARCANE_SPELL" },
    { "^Equip: Increases damage done by Shadow spells and effects by up to (%d+)%.$",
        "ALTARMY_SHADOW_SPELL" },
    { "^Equip: Increases damage done by Nature spells and effects by up to (%d+)%.$",
        "ALTARMY_NATURE_SPELL" },
    { "^Equip: Increases damage done by Holy spells and effects by up to (%d+)%.$",
        "ALTARMY_HOLY_SPELL" },
    { "^%+(%d+) Defense Rating$", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    { "^%+(%d+) Dodge Rating$", "ITEM_MOD_DODGE_RATING_SHORT" },
    { "^%+(%d+) Parry Rating$", "ITEM_MOD_PARRY_RATING_SHORT" },
    { "^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.$",
        COMBINED_SPELL_DAMAGE_HEAL_KEYS },
    { "^%+(%d+) Damage and Healing Spells$", COMBINED_SPELL_DAMAGE_HEAL_KEYS },
    { "^%+(%d+) Spell Damage and Healing$", COMBINED_SPELL_DAMAGE_HEAL_KEYS },
    { "^Equip: Restores (%d+) [Mm]ana per 5 sec%.$", "ITEM_MOD_MANA_REGENERATION_SHORT" },
    -- Tooltip wraps this line in parens, e.g. "(52.5 damage per second)".
    { "^%(?(%d+%.?%d*) damage per second%)?$", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
    { "^(%d+) Armor$", "RESISTANCE0_NAME" },
    { "^Equip: Increases all Resistances by (%d+)%.?$", ALL_RESISTANCE_KEYS },
}

-- Conditional/situational equip clauses (e.g. "...in Forest and Grassland areas."). Each row has
-- two captures: the bonus amount, and the condition text (kept verbatim, starting with "in ").
-- A row may be a continuation sentence with no "Equip:" prefix (boosting a base clause further
-- under a condition) or a full, entirely-conditional "Equip:" line — both are tried the same way
-- by parseLineToConditionalRaw. See Data/DESIGN.md for the resulting stats.conditional shape.
local CONDITIONAL_STAT_PATTERNS = {
    { "^Gain an additional (%d+) to all Resistances (in .-)%.?$", ALL_RESISTANCE_KEYS },
    { "^Restores an additional (%d+) [Mm]ana per 5 sec (in .-)%.?$",
        "ITEM_MOD_MANA_REGENERATION_SHORT" },
    { "^Equip: Movement speed increased by (%d+)%% (in .-)%.?$", "ALTARMY_MOVE_SPEED" },
}

local TOOLTIP_ONLY_STAT_KEYS = {
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = true,
    ITEM_MOD_DAMAGE_PER_SECOND = true,
    ALTARMY_FIRE_SPELL = true,
    ALTARMY_FROST_SPELL = true,
    ALTARMY_ARCANE_SPELL = true,
    ALTARMY_SHADOW_SPELL = true,
    ALTARMY_NATURE_SPELL = true,
    ALTARMY_HOLY_SPELL = true,
}

local RANGED_WEAPON_SUBCLASSES = {
    Bow = true,
    Gun = true,
    Crossbow = true,
    Wand = true,
    Thrown = true,
}

local function isTooltipOnlyStatKey(apiKey)
    return TOOLTIP_ONLY_STAT_KEYS[apiKey] == true
end

local function resolveWeaponDpsKey(link)
    if not link or not hasItemInfoApi() then return "melee_dps" end
    local _, _, _, _, _, _, subclass, _, equipSlot = compatGetItemInfo(link)
    if subclass and RANGED_WEAPON_SUBCLASSES[subclass] then
        return "ranged_dps"
    end
    if equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
        return "ranged_dps"
    end
    return "melee_dps"
end

local function isInvalidApiStatValue(value)
    local n = tonumber(value)
    return n ~= nil and n < 0
end

local function canonicalizeRawStatKey(key)
    if type(key) ~= "string" or key:match("_SHORT$") then
        return key
    end
    local shortKey = key .. "_SHORT"
    if IS.STAT_ALIASES[shortKey] then
        return shortKey
    end
    return key
end

local function canonicalizeRawStats(raw)
    local out = {}
    if not raw then return out end
    for k, v in pairs(raw) do
        local canon = canonicalizeRawStatKey(k)
        if out[canon] == nil then
            out[canon] = v
        elseif isInvalidApiStatValue(out[canon]) and not isInvalidApiStatValue(v) then
            out[canon] = v
        elseif not isInvalidApiStatValue(v) then
            out[canon] = (tonumber(out[canon]) or 0) + (tonumber(v) or 0)
        end
    end
    return out
end

local function mergeTooltipSupplement(apiRaw, tooltipRaw)
    apiRaw = canonicalizeRawStats(apiRaw)
    tooltipRaw = canonicalizeRawStats(tooltipRaw)
    local merged = {}
    if apiRaw then
        for k, v in pairs(apiRaw) do
            merged[k] = v
        end
    end
    local hasApi = apiRaw and next(apiRaw) ~= nil
    if not tooltipRaw then return merged end
    for k, v in pairs(tooltipRaw) do
        -- API often omits random suffix stats on green items; merge those from tooltip.
        -- Random suffix stats can also appear as -1 sentinels from GetItemStats.
        local useTooltip = isTooltipOnlyStatKey(k) or not hasApi or merged[k] == nil
            or isInvalidApiStatValue(merged[k])
        if useTooltip then
            if isInvalidApiStatValue(merged[k]) then
                merged[k] = tonumber(v) or 0
            else
                merged[k] = (merged[k] or 0) + (tonumber(v) or 0)
            end
        end
    end
    return merged
end

-- TBC unified spell power: API may expose SPELL_POWER while tooltip uses SPELL_DAMAGE_DONE.
local UNIFIED_SPELL_STAT_KEYS = {
    "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_SPELL_POWER",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE",
}

local function finalizeMergedSpellStats(merged)
    if not merged then return end
    local best = nil
    for i = 1, #UNIFIED_SPELL_STAT_KEYS do
        local key = UNIFIED_SPELL_STAT_KEYS[i]
        local value = merged[key]
        if value ~= nil and not isInvalidApiStatValue(value) then
            local n = tonumber(value) or 0
            if best == nil or n > best then
                best = n
            end
        end
    end
    if best == nil then
        for i = 1, #UNIFIED_SPELL_STAT_KEYS do
            local key = UNIFIED_SPELL_STAT_KEYS[i]
            if isInvalidApiStatValue(merged[key]) then
                merged[key] = nil
            end
        end
        return
    end
    merged["ITEM_MOD_SPELL_POWER_SHORT"] = best
    merged["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = nil
    merged["ITEM_MOD_SPELL_DAMAGE_DONE"] = nil
    merged["ITEM_MOD_SPELL_POWER"] = nil
end

-- Some clients' GetItemStats expose per-school damage (e.g. ITEM_MOD_FIRE_DAMAGE_DONE_SHORT) while the
-- tooltip parse yields ALTARMY_*_SPELL for the same line. Keep the larger value under the tooltip key.
local SCHOOL_SPELL_API_KEYS = {
    ALTARMY_FIRE_SPELL = { "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", "ITEM_MOD_FIRE_DAMAGE_DONE" },
    ALTARMY_FROST_SPELL = { "ITEM_MOD_FROST_DAMAGE_DONE_SHORT", "ITEM_MOD_FROST_DAMAGE_DONE" },
    ALTARMY_ARCANE_SPELL = { "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT", "ITEM_MOD_ARCANE_DAMAGE_DONE" },
    ALTARMY_SHADOW_SPELL = { "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT", "ITEM_MOD_SHADOW_DAMAGE_DONE" },
    ALTARMY_NATURE_SPELL = { "ITEM_MOD_NATURE_DAMAGE_DONE_SHORT", "ITEM_MOD_NATURE_DAMAGE_DONE" },
    ALTARMY_HOLY_SPELL = { "ITEM_MOD_HOLY_DAMAGE_DONE_SHORT", "ITEM_MOD_HOLY_DAMAGE_DONE" },
}

local function finalizeMergedSchoolSpellStats(merged)
    if not merged then return end
    for schoolKey, apiKeys in pairs(SCHOOL_SPELL_API_KEYS) do
        local best = nil
        local candidates = { schoolKey, apiKeys[1], apiKeys[2] }
        for i = 1, #candidates do
            local value = merged[candidates[i]]
            if value ~= nil and not isInvalidApiStatValue(value) then
                local n = tonumber(value) or 0
                if best == nil or n > best then
                    best = n
                end
            end
            if i > 1 then
                merged[candidates[i]] = nil
            end
        end
        merged[schoolKey] = best
    end
end

-- API uses POWER_REGEN0; tooltip parse uses MANA_REGENERATION. Both map to mp5.
local UNIFIED_MP5_STAT_KEYS = {
    "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ITEM_MOD_MANA_REGENERATION",
    "ITEM_MOD_POWER_REGEN0_SHORT",
    "ITEM_MOD_POWER_REGEN0",
}

local function finalizeMergedManaRegen(merged)
    if not merged then return end
    local best = nil
    for i = 1, #UNIFIED_MP5_STAT_KEYS do
        local key = UNIFIED_MP5_STAT_KEYS[i]
        local value = merged[key]
        if value ~= nil and not isInvalidApiStatValue(value) then
            local n = tonumber(value) or 0
            if best == nil or n > best then
                best = n
            end
        end
    end
    if best == nil then
        for i = 1, #UNIFIED_MP5_STAT_KEYS do
            local key = UNIFIED_MP5_STAT_KEYS[i]
            if isInvalidApiStatValue(merged[key]) then
                merged[key] = nil
            end
        end
        return
    end
    merged["ITEM_MOD_MANA_REGENERATION_SHORT"] = best
    merged["ITEM_MOD_MANA_REGENERATION"] = nil
    merged["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    merged["ITEM_MOD_POWER_REGEN0"] = nil
end

local FERAL_AP_KEYS = {
    "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
    "ITEM_MOD_FERAL_ATTACK_POWER",
    "ITEM_MOD_MELEE_ATTACK_POWER_SHORT",
    "ITEM_MOD_MELEE_ATTACK_POWER",
}

local GENERIC_AP_KEYS = {
    "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_ATTACK_POWER",
}

local function rawStatValue(raw, keys)
    if not raw then return nil end
    local best = nil
    for i = 1, #keys do
        local n = tonumber(raw[keys[i]])
        if n ~= nil and not isInvalidApiStatValue(n) then
            if best == nil or n > best then
                best = n
            end
        end
    end
    return best
end

local function clearRawStatKeys(raw, keys)
    for i = 1, #keys do
        raw[keys[i]] = nil
    end
end

-- Form-only AP ("in Cat, Bear, Dire Bear, and Moonkin forms only") must score as
-- feral_ap. GetItemStats may label it MELEE_ATTACK_POWER or even ATTACK_POWER.
local function finalizeMergedFeralAttackPower(merged, tooltipRaw)
    if not merged then return end
    tooltipRaw = canonicalizeRawStats(tooltipRaw)
    local tooltipFeral = rawStatValue(tooltipRaw, {
        "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
        "ITEM_MOD_FERAL_ATTACK_POWER",
    })
    local feral = rawStatValue(merged, FERAL_AP_KEYS) or 0
    if tooltipFeral and tooltipFeral > feral then
        feral = tooltipFeral
    end

    clearRawStatKeys(merged, {
        "ITEM_MOD_MELEE_ATTACK_POWER_SHORT",
        "ITEM_MOD_MELEE_ATTACK_POWER",
        "ITEM_MOD_FERAL_ATTACK_POWER",
    })

    if tooltipFeral then
        local tooltipGenericAp = rawStatValue(tooltipRaw, GENERIC_AP_KEYS)
        local mergedAp = rawStatValue(merged, GENERIC_AP_KEYS)
        -- When tooltip only reports form AP, drop API generic AP that duplicates it
        -- (GetItemStats is often off by one from the tooltip value).
        if not tooltipGenericAp and mergedAp and math.abs(mergedAp - tooltipFeral) <= 1 then
            clearRawStatKeys(merged, GENERIC_AP_KEYS)
        end
    end

    if feral > 0 then
        merged["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = feral
    else
        merged["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = nil
    end
end

local cache = {}
local pendingIds = {}
local onUpdatedCallback
local pendingFrame
local statScanTooltip
local tooltipPatterns

local function copyTable(t)
    local out = {}
    if not t then return out end
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

local function escapePattern(s)
    return (s:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"))
end

local function addTooltipLabelPattern(patterns, seen, label, apiKey)
    if not label or label == "" or seen[label] then return end
    if label:find("%%", 1, true) then return end
    seen[label] = true
    patterns[#patterns + 1] = {
        -- Signed: most items add a stat, a few take one away ("-3 Spirit": Ring of Scorn).
        pattern = "^([%+%-]?%d+) " .. escapePattern(label) .. "$",
        apiKey = apiKey,
    }
end

local function buildTooltipPatterns()
    if tooltipPatterns then return tooltipPatterns end
    local patterns = {}
    local seenLabels = {}
    for i = 1, #PRIMARY_STAT_DEFS do
        local def = PRIMARY_STAT_DEFS[i]
        local label = _G[def.apiKey] or def.label
        addTooltipLabelPattern(patterns, seenLabels, label, def.apiKey)
    end
    local healingApiKey = "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
    for i = 1, #HEALING_TOOLTIP_LABELS do
        addTooltipLabelPattern(patterns, seenLabels, HEALING_TOOLTIP_LABELS[i], healingApiKey)
    end
    local healingGlobal = _G[healingApiKey]
    if type(healingGlobal) == "string" then
        addTooltipLabelPattern(patterns, seenLabels, healingGlobal, healingApiKey)
    end
    for i = 1, #COMBINED_SPELL_TOOLTIP_LABELS do
        addTooltipLabelPattern(
            patterns, seenLabels, COMBINED_SPELL_TOOLTIP_LABELS[i], COMBINED_SPELL_DAMAGE_HEAL_KEYS)
    end
    local spellPowerGlobal = _G.ITEM_MOD_SPELL_POWER_SHORT
    if type(spellPowerGlobal) == "string" then
        addTooltipLabelPattern(
            patterns, seenLabels, spellPowerGlobal, COMBINED_SPELL_DAMAGE_HEAL_KEYS)
    end
    for i = 1, #SCHOOL_SPELL_TOOLTIP_DEFS do
        local def = SCHOOL_SPELL_TOOLTIP_DEFS[i]
        for j = 1, #def.labels do
            addTooltipLabelPattern(patterns, seenLabels, def.labels[j], def.apiKey)
        end
    end
    for i = 1, #EQUIP_STAT_PATTERNS do
        local row = EQUIP_STAT_PATTERNS[i]
        patterns[#patterns + 1] = { pattern = row[1], apiKey = row[2] }
    end
    tooltipPatterns = patterns
    return patterns
end

local function parseItemId(link)
    if not link then return nil end
    return tonumber(tostring(link):match("item:(%d+)"))
end

local function resolveGlobalStringLabel(name)
    local g = _G[name]
    if type(g) ~= "string" or g == "" or g == name then return nil end
    if g:find("%%") then
        if not name:match("_SHORT$") then
            return resolveGlobalStringLabel(name .. "_SHORT")
        end
        return nil
    end
    return g
end

function IS.GetDisplayLabel(key)
    if not key then return "?" end
    local shortKey = IS.STAT_ALIASES[key] or key
    if IS.STAT_LABELS[shortKey] then
        return IS.STAT_LABELS[shortKey]
    end
    local globalLabel = resolveGlobalStringLabel(key)
    if globalLabel then return globalLabel end
    if shortKey ~= key then
        for apiKey, mappedShort in pairs(IS.STAT_ALIASES) do
            if mappedShort == shortKey then
                globalLabel = resolveGlobalStringLabel(apiKey)
                if globalLabel then return globalLabel end
            end
        end
    end
    return key
end

--- Raw keys whose negative value the tooltip itself shows ("-3 Spirit"): real negative stats,
--- unlike the -1 sentinels GetItemStats reports for stats it can't resolve.
local function confirmedNegativeKeys(tooltipRaw)
    local out = {}
    for k, v in pairs(canonicalizeRawStats(tooltipRaw)) do
        if isInvalidApiStatValue(v) then
            out[k] = true
        end
    end
    return out
end

local function normalizeRawStats(raw, link, negativeKeys)
    local out = {}
    if not raw then return out end
    local dpsKey = resolveWeaponDpsKey(link)
    for statKey, value in pairs(raw) do
        local short = IS.STAT_ALIASES[statKey] or statKey
        if statKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
            or statKey == "ITEM_MOD_DAMAGE_PER_SECOND" then
            short = dpsKey
        end
        if not isInvalidApiStatValue(value) or (negativeKeys and negativeKeys[statKey]) then
            out[short] = (out[short] or 0) + (tonumber(value) or 0)
        end
    end
    return out
end

--- Normalizes each condition's raw stat group and, if any are non-empty, sets `normalized.conditional`.
--- Leaves `normalized.conditional` unset when there are no conditional clauses on this item.
local function applyConditionalStats(normalized, conditionalRaw, link)
    if not conditionalRaw or not next(conditionalRaw) then return end
    local out
    for condition, raw in pairs(conditionalRaw) do
        local normalizedGroup = normalizeRawStats(raw, link)
        if next(normalizedGroup) then
            out = out or {}
            out[condition] = normalizedGroup
        end
    end
    if out then
        normalized.conditional = out
    end
end

local function stripColorCodes(text)
    text = text:gsub("|c[%x]+", "")
    text = text:gsub("|r", "")
    return text
end

local function normalizeTooltipLine(text)
    text = stripColorCodes(text or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local name, val = text:match("^([%w%s]+) %+(%d+)$")
    if name and val then
        text = "+" .. val .. " " .. name
    end
    return text
end

local function isSetBonusKillLine(text)
    return text:match(" %(%d+/%d+%)$") ~= nil
end

local function lineHasArmor(text)
    return text:find("Armor", 1, true) ~= nil and text:match("(%d+)") ~= nil
end

local function getStatScanTooltip()
    if statScanTooltip then
        if statScanTooltip.SetHyperlink and statScanTooltip.GetRegions then
            return statScanTooltip
        end
        statScanTooltip = nil
    end
    if not CreateFrame then return nil end
    statScanTooltip = CreateFrame(
        "GameTooltip",
        "AltArmyTBC_ItemStatsScanTooltip",
        UIParent,
        "GameTooltipTemplate")
    if not statScanTooltip or not statScanTooltip.SetHyperlink then
        statScanTooltip = nil
        return nil
    end
    if statScanTooltip.SetOwner then
        statScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return statScanTooltip
end

local function collectTooltipLines(tooltip)
    local lines = {}
    if not tooltip then return lines end
    if tooltip.GetRegions then
        for _, region in ipairs({ tooltip:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("FontString") then
                local text = region.GetText and region:GetText()
                if text and text ~= "" then
                    lines[#lines + 1] = text
                end
            end
        end
    end
    if #lines == 0 and tooltip.NumLines and tooltip.GetName then
        local tipName = tooltip:GetName()
        if tipName then
            for i = 1, tooltip:NumLines() do
                local line = _G[tipName .. "TextLeft" .. i]
                if line and line.GetText then
                    local text = line:GetText()
                    if text and text ~= "" then
                        lines[#lines + 1] = text
                    end
                end
            end
        end
    end
    return lines
end

local function applyRawStat(rawOut, apiKey, value)
    rawOut[apiKey] = (rawOut[apiKey] or 0) + value
end

local function applyRawStatKeys(rawOut, apiKeys, value)
    if type(apiKeys) == "string" then
        applyRawStat(rawOut, apiKeys, value)
        return
    end
    for i = 1, #apiKeys do
        applyRawStat(rawOut, apiKeys[i], value)
    end
end

local function parseLineToRaw(text, rawOut)
    local patterns = buildTooltipPatterns()
    for i = 1, #patterns do
        local row = patterns[i]
        local amount = text:match(row.pattern)
        if amount then
            local n = tonumber(amount) or tonumber((amount:gsub(",", ".", 1)))
            if n then
                applyRawStatKeys(rawOut, row.apiKey, n)
                return true
            end
        end
    end
    return false
end

local function parseLineToConditionalRaw(text, conditionalRawOut)
    for i = 1, #CONDITIONAL_STAT_PATTERNS do
        local row = CONDITIONAL_STAT_PATTERNS[i]
        local amount, condition = text:match(row[1])
        if amount and condition then
            local n = tonumber(amount)
            if n then
                conditionalRawOut[condition] = conditionalRawOut[condition] or {}
                applyRawStatKeys(conditionalRawOut[condition], row[2], n)
                return true
            end
        end
    end
    return false
end

--- Split a tooltip line on ". " (period+space) into sentence fragments, re-attaching the
--- period to the front piece. Safe as a no-op for every existing single-sentence wording (none
--- contain ". " — decimals like "52.5" have no space after the period); it's what lets a single
--- "Equip:" line carry a base clause and a conditional addendum, e.g. "Increases X by 3. Gain
--- an additional 5 ... in <condition>."
local function splitTooltipSentences(text)
    local parts = {}
    local start = 1
    while true do
        local s = text:find(". ", start, true)
        if not s then
            parts[#parts + 1] = text:sub(start)
            break
        end
        parts[#parts + 1] = text:sub(start, s)
        start = s + 2
    end
    return parts
end

local function parseTooltipToRaw(link)
    local tip = getStatScanTooltip()
    if not tip then return {}, {}, false, {} end
    tip:ClearLines()
    tip:SetHyperlink(link)
    local rawLines = collectTooltipLines(tip)
    local strippedLines = {}
    local raw = {}
    local conditionalRaw = {}
    local sawArmor = false
    for i = 1, #rawLines do
        local normalized = normalizeTooltipLine(rawLines[i])
        strippedLines[#strippedLines + 1] = normalized
        if isSetBonusKillLine(normalized) then
            break
        end
        if lineHasArmor(normalized) then
            sawArmor = true
        end
        local sentences = splitTooltipSentences(normalized)
        for j = 1, #sentences do
            local sentence = sentences[j]
            parseLineToRaw(sentence, raw)
            parseLineToConditionalRaw(sentence, conditionalRaw)
        end
    end
    local incomplete = false
    if sawArmor and not next(raw) and #strippedLines > 0 then
        incomplete = true
    end
    return raw, strippedLines, incomplete, conditionalRaw
end

local function fetchFromApi(link)
    if not hasItemStatsApi() then return nil end
    local stats = compatGetItemStats(link)
    if type(stats) == "table" and next(stats) then
        return stats, "api"
    end
    -- Legacy out-table form; C_Item.GetItemStats takes no second argument.
    if not GetItemStats then return nil end
    local tableStats = {}
    local ok = GetItemStats(link, tableStats)
    if ok ~= false and next(tableStats) then
        return tableStats, "api"
    end
    return nil
end

local function ensurePendingFrame()
    if pendingFrame or not CreateFrame then return end
    pendingFrame = CreateFrame("Frame")
    if not pendingFrame.RegisterEvent then return end
    pendingFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pendingFrame:SetScript("OnEvent", function(_, _, itemId)
        itemId = tonumber(itemId)
        if not itemId or not pendingIds[itemId] then return end
        pendingIds[itemId] = nil
        local cleared = false
        for link, entry in pairs(cache) do
            if entry.itemId == itemId then
                cache[link] = nil
                cleared = true
            end
        end
        if cleared then
            local GU = AltArmy.GearUpgrade
            if GU and GU.InvalidateScoreDependentMemos then
                GU.InvalidateScoreDependentMemos()
            end
        end
        if onUpdatedCallback then
            onUpdatedCallback(itemId)
        end
    end)
end

local function queuePending(itemId)
    if not itemId then return end
    pendingIds[itemId] = true
    ensurePendingFrame()
end

local function formatRawTable(raw)
    if not raw or next(raw) == nil then return "(empty)" end
    local keys = {}
    for k in pairs(raw) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = string.format("%s=%s", k, tostring(raw[k]))
    end
    return table.concat(parts, ", ")
end

local function describeHealingGlobals()
    local short = _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT
    local full = _G.ITEM_MOD_SPELL_HEALING_DONE
    return {
        short = type(short) == "string" and short or "(nil)",
        full = type(full) == "string" and full or "(nil)",
    }
end

local function describeHealingPatternMatches(text)
    local patterns = buildTooltipPatterns()
    local matches = {}
    for i = 1, #patterns do
        local row = patterns[i]
        if row.apiKey:find("HEALING", 1, true) then
            local amount = text:match(row.pattern)
            matches[#matches + 1] = string.format(
                "%s => %s",
                row.pattern,
                amount and ("matched " .. amount .. " as " .. row.apiKey) or "no match")
        end
    end
    return matches
end

local function collectFreshParseSnapshot(link)
    local itemName
    if hasItemInfoApi() then
        itemName = compatGetItemInfo(link)
    end
    local apiRaw = fetchFromApi(link) or {}
    local tooltipRaw, tooltipLines, incomplete, conditionalRaw = parseTooltipToRaw(link)
    local mergedRaw = mergeTooltipSupplement(apiRaw, tooltipRaw)
    finalizeMergedSpellStats(mergedRaw)
    finalizeMergedSchoolSpellStats(mergedRaw)
    finalizeMergedManaRegen(mergedRaw)
    finalizeMergedFeralAttackPower(mergedRaw, tooltipRaw)
    local normalized = normalizeRawStats(mergedRaw, link, confirmedNegativeKeys(tooltipRaw))
    applyConditionalStats(normalized, conditionalRaw, link)
    return {
        itemName = itemName,
        itemId = parseItemId(link),
        apiRaw = copyTable(apiRaw),
        tooltipRaw = copyTable(tooltipRaw),
        mergedRaw = copyTable(mergedRaw),
        normalized = copyTable(normalized),
        tooltipLines = copyTable(tooltipLines),
        incomplete = incomplete,
    }
end

local function resolveStatsSource(apiRaw, tooltipRaw, mergedRaw)
    local source = apiRaw and next(apiRaw) and "api" or "tooltip"
    if apiRaw and next(apiRaw) and tooltipRaw and next(tooltipRaw) then
        for k in pairs(tooltipRaw) do
            if isTooltipOnlyStatKey(k) and mergedRaw[k] then
                source = "api"
                break
            end
        end
    end
    return source
end

local function storeCache(link, normalized, source, meta)
    meta = meta or {}
    cache[link] = {
        normalized = copyTable(normalized),
        source = source,
        tooltipLines = meta.tooltipLines,
        itemId = parseItemId(link),
        complete = source ~= "pending",
        parseSnapshot = meta.parseSnapshot,
    }
end

function IS.ClearCache()
    cache = {}
    pendingIds = {}
    local GU = AltArmy.GearUpgrade
    if GU and GU.InvalidateScoreDependentMemos then
        GU.InvalidateScoreDependentMemos()
    end
end

function IS.SetOnUpdated(fn)
    onUpdatedCallback = fn
end

function IS.GetSource(link)
    if not link then return "none" end
    local entry = cache[link]
    if entry then return entry.source or "none" end
    IS.GetNormalized(link)
    entry = cache[link]
    return entry and entry.source or "none"
end

function IS.GetTooltipLines(link)
    if not link then return {} end
    local entry = cache[link]
    if entry and entry.tooltipLines then
        return copyTable(entry.tooltipLines)
    end
    IS.GetNormalized(link)
    entry = cache[link]
    return entry and copyTable(entry.tooltipLines or {}) or {}
end

local function fetchStats(link)
    if hasItemInfoApi() then
        local name = compatGetItemInfo(link)
        if not name then
            queuePending(parseItemId(link))
            return {}, "pending", {}
        end
    end

    local apiRaw = fetchFromApi(link)
    local tooltipRaw, tooltipLines, incomplete, conditionalRaw = parseTooltipToRaw(link)
    local mergedRaw = mergeTooltipSupplement(apiRaw, tooltipRaw)
    finalizeMergedSpellStats(mergedRaw)
    finalizeMergedSchoolSpellStats(mergedRaw)
    finalizeMergedManaRegen(mergedRaw)
    finalizeMergedFeralAttackPower(mergedRaw, tooltipRaw)

    local parseSnapshot = {
        itemName = hasItemInfoApi() and compatGetItemInfo(link) or nil,
        itemId = parseItemId(link),
        apiRaw = copyTable(apiRaw or {}),
        tooltipRaw = copyTable(tooltipRaw or {}),
        mergedRaw = copyTable(mergedRaw),
        incomplete = incomplete,
        tooltipLines = copyTable(tooltipLines),
    }

    -- An item can be entirely conditional (e.g. a movement-speed line with no always-on clause),
    -- so treat a non-empty conditionalRaw the same as a non-empty mergedRaw here.
    if next(mergedRaw) or (conditionalRaw and next(conditionalRaw)) then
        local source = resolveStatsSource(apiRaw, tooltipRaw, mergedRaw)
        local normalized = normalizeRawStats(mergedRaw, link, confirmedNegativeKeys(tooltipRaw))
        applyConditionalStats(normalized, conditionalRaw, link)
        parseSnapshot.normalized = copyTable(normalized)
        return normalized, source, {
            tooltipLines = tooltipLines,
            parseSnapshot = parseSnapshot,
        }
    end
    if incomplete then
        queuePending(parseItemId(link))
        parseSnapshot.normalized = {}
        return {}, "pending", {
            tooltipLines = tooltipLines,
            parseSnapshot = parseSnapshot,
        }
    end

    parseSnapshot.normalized = {}
    return {}, "none", {
        tooltipLines = tooltipLines,
        parseSnapshot = parseSnapshot,
    }
end

function IS.GetNormalized(link)
    if not link then return {} end
    local entry = cache[link]
    if entry and entry.complete ~= false then
        return copyTable(entry.normalized)
    end
    local normalized, source, meta = fetchStats(link)
    storeCache(link, normalized, source, meta)
    return copyTable(normalized)
end

--- Read-only cached normalized stats; do not mutate the returned table.
function IS.GetNormalizedRef(link)
    if not link then return nil end
    local entry = cache[link]
    if entry and entry.complete ~= false then
        return entry.normalized
    end
    IS.GetNormalized(link)
    entry = cache[link]
    return entry and entry.normalized or nil
end

--- Structured parse snapshot for debug dumps (API, tooltip, merge, normalized).
function IS.CollectParseSnapshot(link, opts)
    if not link then return nil end
    opts = opts or {}
    if opts.forceRefresh then
        local snap = collectFreshParseSnapshot(link)
        if snap.normalized and next(snap.normalized) then
            storeCache(link, snap.normalized, resolveStatsSource(
                snap.apiRaw, snap.tooltipRaw, snap.mergedRaw), {
                tooltipLines = snap.tooltipLines,
                parseSnapshot = snap,
            })
            local GU = AltArmy.GearUpgrade
            if GU and GU.InvalidateScoreDependentMemos then
                GU.InvalidateScoreDependentMemos()
            end
        end
        return snap
    end
    local entry = cache[link]
    if entry and entry.parseSnapshot then
        local snap = copyTable(entry.parseSnapshot)
        if entry.tooltipLines and not snap.tooltipLines then
            snap.tooltipLines = copyTable(entry.tooltipLines)
        end
        return snap
    end
    IS.GetNormalized(link)
    entry = cache[link]
    if entry and entry.parseSnapshot then
        local snap = copyTable(entry.parseSnapshot)
        if entry.tooltipLines and not snap.tooltipLines then
            snap.tooltipLines = copyTable(entry.tooltipLines)
        end
        return snap
    end
    return collectFreshParseSnapshot(link)
end

function IS.FormatNormalizedForDebug(stats)
    if not stats or not next(stats) then return "(none)" end
    local keys = {}
    for k in pairs(stats) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = string.format("%s=%s", k, tostring(stats[k]))
    end
    return table.concat(parts, " ")
end

--- Chat lines for diagnosing tooltip/API stat parsing (enable Debug > Item stat parsing).
function IS.BuildStatParseDebugLines(link, opts)
    opts = opts or {}
    local lines = {}
    if not link then
        lines[#lines + 1] = "No item link."
        return lines
    end

    local cached = cache[link]
    local snapshot = (not opts.forceRefresh and cached and cached.parseSnapshot) or nil
    if not snapshot then
        snapshot = collectFreshParseSnapshot(link)
    elseif snapshot.tooltipLines == nil and cached and cached.tooltipLines then
        snapshot.tooltipLines = copyTable(cached.tooltipLines)
    end

    local itemLabel = snapshot.itemName or "?"
    lines[#lines + 1] = string.format(
        "Item: %s (id=%s)",
        itemLabel,
        tostring(snapshot.itemId or "?"))
    lines[#lines + 1] = string.format("  link: %s", tostring(link))
    if cached then
        lines[#lines + 1] = string.format(
            "  cache: source=%s complete=%s normalized=%s",
            tostring(cached.source or "?"),
            tostring(cached.complete),
            IS.FormatNormalizedForDebug(cached.normalized))
    else
        lines[#lines + 1] = "  cache: (miss)"
    end

    local globals = describeHealingGlobals()
    lines[#lines + 1] = string.format(
        "  healing globals: SHORT=%q FULL=%q",
        globals.short,
        globals.full)

    lines[#lines + 1] = "  GetItemStats: " .. formatRawTable(snapshot.apiRaw)
    lines[#lines + 1] = "  tooltip parsed: " .. formatRawTable(snapshot.tooltipRaw)
    lines[#lines + 1] = "  merged raw: " .. formatRawTable(snapshot.mergedRaw)
    lines[#lines + 1] = string.format(
        "  normalized: %s",
        IS.FormatNormalizedForDebug(snapshot.normalized))
    lines[#lines + 1] = string.format(
        "  tooltip incomplete=%s lineCount=%s",
        tostring(snapshot.incomplete),
        tostring(snapshot.tooltipLines and #snapshot.tooltipLines or 0))

    local tipLines = snapshot.tooltipLines or {}
    for i = 1, #tipLines do
        local line = tostring(tipLines[i])
        local parsed = parseLineToRaw(normalizeTooltipLine(line), {})
        local suffix = parsed and " [parsed]" or " [unparsed]"
        lines[#lines + 1] = string.format("  tooltip[%d]: %s%s", i, line, suffix)
        if not parsed and line:find("Heal", 1, true) then
            local healingMatches = describeHealingPatternMatches(normalizeTooltipLine(line))
            for m = 1, #healingMatches do
                lines[#lines + 1] = "    healing pattern: " .. healingMatches[m]
            end
        end
    end

    local apiHeal = snapshot.apiRaw.ITEM_MOD_SPELL_HEALING_DONE
        or snapshot.apiRaw.ITEM_MOD_SPELL_HEALING_DONE_SHORT
    local tipHeal = snapshot.tooltipRaw.ITEM_MOD_SPELL_HEALING_DONE
        or snapshot.tooltipRaw.ITEM_MOD_SPELL_HEALING_DONE_SHORT
    if apiHeal ~= nil or tipHeal ~= nil then
        lines[#lines + 1] = string.format(
            "  healing keys: api DONE=%s api SHORT=%s tooltip DONE=%s tooltip SHORT=%s normalized heal=%s",
            tostring(snapshot.apiRaw.ITEM_MOD_SPELL_HEALING_DONE),
            tostring(snapshot.apiRaw.ITEM_MOD_SPELL_HEALING_DONE_SHORT),
            tostring(snapshot.tooltipRaw.ITEM_MOD_SPELL_HEALING_DONE),
            tostring(snapshot.tooltipRaw.ITEM_MOD_SPELL_HEALING_DONE_SHORT),
            tostring(snapshot.normalized and snapshot.normalized.heal))
    end

    return lines
end

function IS.LogStatParseDebug(link, opts)
    local D = AltArmy.Debug
    if not D or not D.IsItemStatsEnabled or not D.IsItemStatsEnabled() then
        return
    end
    local lines = IS.BuildStatParseDebugLines(link, opts)
    if #lines == 0 then return end
    if D.LogItemStats then
        D.LogItemStats(lines)
    end
end
