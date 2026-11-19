-- AltArmy TBC — Built-in TBC stat scales (weebly EJ/MaxDPS-derived, Pawn naming).
-- Values authored from community scale strings; not copied from Pawn addon code.

AltArmy = AltArmy or {}
AltArmy.PawnScales = AltArmy.PawnScales or {}

local PS = AltArmy.PawnScales

local function s(values)
    return values
end

-- Shared trailing stats omitted from each table; merged at load via copy helper.
local COMMON = {
    Strength = 0,
    Agility = 0.05,
    MeleeDps = 0,
    RangedDps = 0,
    Ap = 0,
    Rap = 0,
    FeralAp = 0,
    HitRating = 0,
    ExpertiseRating = 0,
    CritRating = 0,
    HasteRating = 0,
    ArmorPenetration = 0,
    Intellect = 0,
    Mana = 0,
    Spirit = 0.05,
    Mp5 = 0,
    Healing = 0,
    SpellDamage = 0,
    FireSpellDamage = 0,
    FrostSpellDamage = 0,
    ArcaneSpellDamage = 0,
    ShadowSpellDamage = 0,
    NatureSpellDamage = 0,
    HolySpellDamage = 0,
    SpellPower = 0,
    SpellHitRating = 0,
    SpellCritRating = 0,
    SpellHasteRating = 0,
    SpellPenetration = 0,
    Stamina = 0.5,
    Health = 0.05,
    Hp5 = 1,
    Armor = 0.005,
    DefenseRating = 0.05,
    DodgeRating = 0.05,
    ParryRating = 0.05,
    BlockRating = 0,
    BlockValue = 0,
    ResilienceRating = 0.2,
    AllResist = 0.2,
    FireResist = 0.04,
    FrostResist = 0.04,
    ArcaneResist = 0.04,
    ShadowResist = 0.04,
    NatureResist = 0.04,
}

local function merge(base, overrides)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    if overrides then
        for k, v in pairs(overrides) do out[k] = v end
    end
    return out
end

PS.RAW = {
    HUNTER = {
        beast = merge(COMMON, s({
            Strength = 0.05, Agility = 1, MeleeDps = 0.75, RangedDps = 2.4,
            Ap = 0.43, Rap = 0.43, HitRating = 1, ExpertiseRating = 0.05,
            CritRating = 0.8, HasteRating = 0.5, ArmorPenetration = 0.17,
            Intellect = 0.8, Mana = 0.075, Mp5 = 2.4,
        })),
        survival = merge(COMMON, s({
            Strength = 0.05, Agility = 1, MeleeDps = 1, RangedDps = 2.4,
            Ap = 0.55, Rap = 0.55, HitRating = 1, ExpertiseRating = 0.05,
            CritRating = 0.65, HasteRating = 0.4, ArmorPenetration = 0.28,
            Intellect = 0.8, Mana = 0.075, Mp5 = 2.4,
        })),
        marksmanship = merge(COMMON, s({
            Strength = 0.05, Agility = 1, MeleeDps = 0.75, RangedDps = 2.6,
            Ap = 0.55, Rap = 0.55, HitRating = 1, ExpertiseRating = 0.05,
            CritRating = 0.6, HasteRating = 0.4, ArmorPenetration = 0.37,
            Intellect = 0.9, Mana = 0.085, Mp5 = 2.4,
        })),
    },
    SHAMAN = {
        restoration = merge(COMMON, s({
            Agility = 0.05, Intellect = 1, Mana = 0.009, Spirit = 0.61,
            Mp5 = 1.33, Healing = 0.9, SpellCritRating = 0.48, SpellHasteRating = 0.74,
            BlockRating = 0.01,
        })),
        elemental = merge(COMMON, s({
            Agility = 0.05, Intellect = 0.31, Mana = 0.024, Spirit = 0.09,
            Mp5 = 1.14, SpellDamage = 1, NatureSpellDamage = 1,
            SpellHitRating = 0.9, SpellCritRating = 1.05, SpellHasteRating = 0.9,
            SpellPenetration = 0.38, ParryRating = 0.12, BlockRating = 0.01,
        })),
        enhancement = merge(COMMON, s({
            Strength = 1, Agility = 0.87, MeleeDps = 3, Ap = 0.5,
            HitRating = 0.67, ExpertiseRating = 1.5, CritRating = 0.98,
            HasteRating = 0.64, ArmorPenetration = 0.12, Intellect = 0.34,
            Mana = 0.032, Mp5 = 1, SpellDamage = 0.3, NatureSpellDamage = 0.3,
            SpellHitRating = 0.223, SpellCritRating = 0.326, SpellHasteRating = 0.08,
            SpellPenetration = 0.11,
        })),
    },
    WARRIOR = {
        protection = merge(COMMON, s({
            Strength = 0.33, Agility = 0.59, MeleeDps = 3.13, Ap = 0.06,
            HitRating = 0.67, ExpertiseRating = 0.67, CritRating = 0.28,
            HasteRating = 0.21, ArmorPenetration = 0.19, Stamina = 1,
            Health = 0.09, Hp5 = 2, Armor = 0.02, DefenseRating = 0.81,
            DodgeRating = 0.7, ParryRating = 0.58, BlockRating = 0.59,
            BlockValue = 0.35, AllResist = 1, FireResist = 0.2, FrostResist = 0.2,
            ArcaneResist = 0.2, ShadowResist = 0.2, NatureResist = 0.2,
        })),
        fury = merge(COMMON, s({
            Strength = 1, Agility = 0.57, MeleeDps = 5.22, Ap = 0.54,
            HitRating = 0.57, ExpertiseRating = 0.57, CritRating = 0.7,
            HasteRating = 0.41, ArmorPenetration = 0.47, ParryRating = 0.12,
        })),
        arms = merge(COMMON, s({
            Strength = 1, Agility = 0.69, MeleeDps = 5.31, Ap = 0.45,
            HitRating = 1, ExpertiseRating = 1, CritRating = 0.85,
            HasteRating = 0.57, ArmorPenetration = 1.1,
        })),
    },
    WARLOCK = {
        affliction = merge(COMMON, s({
            Intellect = 0.4, Mana = 0.03, Spirit = 0.1, Mp5 = 1,
            SpellDamage = 1, FireSpellDamage = 0.35, ShadowSpellDamage = 0.91,
            SpellHitRating = 1.2, SpellCritRating = 0.39, SpellHasteRating = 0.78,
            SpellPenetration = 0.08,
        })),
        demonology = merge(COMMON, s({
            Intellect = 0.4, Mana = 0.03, Spirit = 0.5, Mp5 = 1,
            SpellDamage = 1, FireSpellDamage = 0.80, ShadowSpellDamage = 0.8,
            SpellHitRating = 1.2, SpellCritRating = 0.66, SpellHasteRating = 0.7,
            SpellPenetration = 0.08,
        })),
        destruction = merge(COMMON, s({
            Intellect = 0.34, Mana = 0.028, Spirit = 0.25, Mp5 = 0.65,
            SpellDamage = 1, FireSpellDamage = 0.23, ShadowSpellDamage = 0.95,
            SpellHitRating = 1.6, SpellCritRating = 0.87, SpellHasteRating = 1.15,
            SpellPenetration = 0.08,
        })),
    },
    ROGUE = {
        -- Combat main-hand scale; assassination uses same stat balance per weebly notes.
        combat = merge(COMMON, s({
            Strength = 0.5, Agility = 1, MeleeDps = 3, Ap = 0.45,
            HitRating = 1, ExpertiseRating = 1.1, CritRating = 0.81,
            HasteRating = 0.9, ArmorPenetration = 0.24, ParryRating = 0.12,
        })),
        assassination = merge(COMMON, s({
            Strength = 0.5, Agility = 1, MeleeDps = 3, Ap = 0.45,
            HitRating = 1, ExpertiseRating = 1.1, CritRating = 0.81,
            HasteRating = 0.9, ArmorPenetration = 0.24, ParryRating = 0.12,
        })),
        subtlety = merge(COMMON, s({
            Strength = 0.5, Agility = 1, MeleeDps = 3, Ap = 0.45,
            HitRating = 1, ExpertiseRating = 1.1, CritRating = 0.81,
            HasteRating = 0.9, ArmorPenetration = 0.24, ParryRating = 0.12,
        })),
    },
    PALADIN = {
        protection = merge(COMMON, s({
            Strength = 0.2, Agility = 0.6, MeleeDps = 1.77, Ap = 0.06,
            HitRating = 0.16, ExpertiseRating = 0.27, CritRating = 0.15,
            HasteRating = 0.5, ArmorPenetration = 0.09, Intellect = 0.5,
            Mana = 0.045, SpellDamage = 0.44, HolySpellDamage = 0.44,
            SpellHitRating = 0.78, SpellCritRating = 0.6, SpellHasteRating = 0.12,
            SpellPenetration = 0.03, Stamina = 1, Health = 0.09, Hp5 = 2,
            Armor = 0.02, DefenseRating = 0.7, DodgeRating = 0.7,
            ParryRating = 0.6, BlockRating = 0.6, BlockValue = 0.15,
            AllResist = 1, FireResist = 0.2, FrostResist = 0.2,
            ArcaneResist = 0.2, ShadowResist = 0.2, NatureResist = 0.2,
        })),
        retribution = merge(COMMON, s({
            Strength = 1, Agility = 0.64, MeleeDps = 5.4, Ap = 0.41,
            HitRating = 0.84, ExpertiseRating = 0.87, CritRating = 0.66,
            HasteRating = 0.25, ArmorPenetration = 0.09, Intellect = 0.34,
            Mana = 0.032, Mp5 = 1, SpellDamage = 0.33, HolySpellDamage = 0.33,
            SpellHitRating = 0.21, SpellCritRating = 0.12, SpellHasteRating = 0.04,
            SpellPenetration = 0.015,
        })),
        holy = merge(COMMON, s({
            Intellect = 1, Mana = 0.009, Spirit = 0.28, Mp5 = 1.24,
            Healing = 0.54, SpellCritRating = 0.46, SpellHasteRating = 0.39,
            BlockRating = 0.01,
        })),
    },
    PRIEST = {
        holy = merge(COMMON, s({
            Intellect = 1, Mana = 0.09, Spirit = 0.73, Mp5 = 1.35,
            Healing = 0.81, SpellCritRating = 0.24, SpellHasteRating = 0.60,
        })),
        discipline = merge(COMMON, s({
            Intellect = 1, Mana = 0.09, Spirit = 0.48, Mp5 = 1.19,
            Healing = 0.72, SpellCritRating = 0.32, SpellHasteRating = 0.57,
        })),
        shadow = merge(COMMON, s({
            Intellect = 0.19, Mana = 0.017, Spirit = 0.21, Mp5 = 1,
            SpellDamage = 1, ShadowSpellDamage = 1,
            SpellHitRating = 1.12, SpellCritRating = 0.76, SpellHasteRating = 0.65,
            SpellPenetration = 0.08,
        })),
    },
    MAGE = {
        fire = merge(COMMON, s({
            Intellect = 0.44, Mana = 0.036, Spirit = 0.066, Mp5 = 0.9,
            SpellDamage = 1, FireSpellDamage = 0.94, FrostSpellDamage = 0.32,
            ArcaneSpellDamage = 0.168,
            SpellHitRating = 0.93, SpellCritRating = 0.77, SpellHasteRating = 0.82,
            SpellPenetration = 0.09,
        })),
        frost = merge(COMMON, s({
            Intellect = 0.37, Mana = 0.032, Spirit = 0.06, Mp5 = 0.8,
            SpellDamage = 1, FireSpellDamage = 0.05, FrostSpellDamage = 0.95,
            ArcaneSpellDamage = 0.13,
            SpellHitRating = 1.22, SpellCritRating = 0.58, SpellHasteRating = 0.63,
            SpellPenetration = 0.07,
        })),
        arcane = merge(COMMON, s({
            Intellect = 0.46, Mana = 0.038, Spirit = 0.59, Mp5 = 1.13,
            SpellDamage = 1, FireSpellDamage = 0.064, FrostSpellDamage = 0.52,
            ArcaneSpellDamage = 0.88,
            SpellHitRating = 0.87, SpellCritRating = 0.6, SpellHasteRating = 0.59,
            SpellPenetration = 0.09,
        })),
    },
    DRUID = {
        -- Feral leveling/DPS uses cat scale; bear tanking uses protection-style weights when detected later.
        feral = merge(COMMON, s({
            Strength = 1.48, Agility = 1, Ap = 0.59, FeralAp = 0.59,
            HitRating = 0.61, ExpertiseRating = 0.61, CritRating = 0.59,
            HasteRating = 0.43, ArmorPenetration = 0.4, Intellect = 0.1,
            Mana = 0.009, Mp5 = 0.3, Healing = 0.025, Armor = 0.02,
        })),
        balance = merge(COMMON, s({
            Intellect = 0.38, Mana = 0.032, Spirit = 0.34, Mp5 = 0.58,
            SpellDamage = 1, ArcaneSpellDamage = 0.64, NatureSpellDamage = 0.43,
            SpellHitRating = 1.21, SpellCritRating = 0.62, SpellHasteRating = 0.8,
            SpellPenetration = 0.21,
        })),
        restoration = merge(COMMON, s({
            Intellect = 1, Mana = 0.09, Spirit = 0.87, Mp5 = 1.7,
            Healing = 1.21, SpellCritRating = 0.35, SpellHasteRating = 0.49,
        })),
    },
}

-- Sparse level-range overrides on top of PS.RAW. Entries only list keys they change.
-- Wand-class leveling: priests wand the most (Spirit Tap / Wand Spec), then warlocks,
-- then mages. MeleeDps fills staff/mace gaps while leveling; endgame stays at 0.
-- Cutoff is "one below max level" so it clears on the last level regardless of
-- the running client's cap (70 on TBC Classic, 60 on WoW Forever).
local MAX_LEVEL = (AltArmy.DataStore and AltArmy.DataStore.MAX_LEVEL) or 70
local WAND_LEVELING_CUTOFF = MAX_LEVEL - 1
local WAND_LEVELING_MAGE = { minLevel = 1, maxLevel = WAND_LEVELING_CUTOFF, RangedDps = 3.5, MeleeDps = 0.25 }
local WAND_LEVELING_WARLOCK = { minLevel = 1, maxLevel = WAND_LEVELING_CUTOFF, RangedDps = 5, MeleeDps = 0.25 }
local WAND_LEVELING_PRIEST = { minLevel = 1, maxLevel = WAND_LEVELING_CUTOFF, RangedDps = 6, MeleeDps = 0.25 }
-- Tanks: resistance only matters in max-level resistance sets, so leveling tanks weigh it like
-- every other spec does: small rather than zero, so it still breaks ties between otherwise equal items.
local TANK_LEVELING_RESIST = {
    minLevel = 1, maxLevel = WAND_LEVELING_CUTOFF,
    AllResist = COMMON.AllResist, FireResist = COMMON.FireResist, FrostResist = COMMON.FrostResist,
    ArcaneResist = COMMON.ArcaneResist, ShadowResist = COMMON.ShadowResist,
    NatureResist = COMMON.NatureResist,
}

PS.LEVEL_OVERRIDES = {
    MAGE = {
        fire = { WAND_LEVELING_MAGE },
        frost = { WAND_LEVELING_MAGE },
        arcane = { WAND_LEVELING_MAGE },
    },
    WARLOCK = {
        affliction = { WAND_LEVELING_WARLOCK },
        demonology = { WAND_LEVELING_WARLOCK },
        destruction = { WAND_LEVELING_WARLOCK },
    },
    PRIEST = {
        holy = { WAND_LEVELING_PRIEST },
        discipline = { WAND_LEVELING_PRIEST },
        shadow = { WAND_LEVELING_PRIEST },
    },
    WARRIOR = {
        protection = { TANK_LEVELING_RESIST },
    },
    PALADIN = {
        protection = { TANK_LEVELING_RESIST },
    },
}

local function sparseOverrideValues(entry)
    local sparse = {}
    for k, v in pairs(entry) do
        if k ~= "minLevel" and k ~= "maxLevel" then
            sparse[k] = v
        end
    end
    return sparse
end

--- Band id for weight caching: which override entries matched at this level.
function PS.GetOverrideBandId(classFile, specKey, level)
    if level == nil then return "default" end
    local byClass = PS.LEVEL_OVERRIDES[(classFile or ""):upper()]
    local ranges = byClass and byClass[specKey]
    if not ranges then return "default" end
    local parts = {}
    for i, entry in ipairs(ranges) do
        local minL = entry.minLevel or 1
        local maxL = entry.maxLevel or MAX_LEVEL
        if level >= minL and level <= maxL then
            parts[#parts + 1] = tostring(i)
        end
    end
    if #parts == 0 then return "default" end
    return table.concat(parts, ",")
end

function PS.GetRawScale(classFile, specKey, level)
    local byClass = PS.RAW[(classFile or ""):upper()]
    if not byClass then return nil end
    local base = byClass[specKey]
    if not base then return nil end
    if level == nil then return base end

    local overrideClass = PS.LEVEL_OVERRIDES[(classFile or ""):upper()]
    local ranges = overrideClass and overrideClass[specKey]
    if not ranges then return base end

    local merged = nil
    for _, entry in ipairs(ranges) do
        local minL = entry.minLevel or 1
        local maxL = entry.maxLevel or MAX_LEVEL
        if level >= minL and level <= maxL then
            merged = merge(merged or base, sparseOverrideValues(entry))
        end
    end
    return merged or base
end
