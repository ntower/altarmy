-- AltArmy TBC — Pawn stat-key translation for gear scoring scales.
-- Maps Pawn-style scale keys to internal normalized stat keys (ItemStats short keys).
-- Used by built-in weebly/EJ scales and future scale-string import.

AltArmy = AltArmy or {}
AltArmy.GearUpgrade = AltArmy.GearUpgrade or {}

local GU = AltArmy.GearUpgrade

--- Pawn scale stat name -> internal short key (ItemStats normalized keys).
GU.PAWN_KEY_MAP = {
    Strength = "str",
    Agility = "agi",
    Stamina = "sta",
    Intellect = "int",
    Spirit = "spi",
    Armor = "armor",
    HitRating = "hit",
    CritRating = "crit",
    HasteRating = "haste",
    ExpertiseRating = "expertise",
    ArmorPenetration = "armor_pen",
    SpellHitRating = "spell_hit",
    SpellCritRating = "spell_crit",
    SpellHasteRating = "spell_haste",
    SpellPenetration = "spell_pen",
    Ap = "ap",
    Rap = "rap",
    FeralAp = "feral_ap",
    MeleeDps = "melee_dps",
    RangedDps = "ranged_dps",
    Mp5 = "mp5",
    Hp5 = "health_regen",
    Mana = "mana",
    Health = "health",
    Healing = "heal",
    SpellPower = "sp",
    FireSpellDamage = "fire_sp",
    FrostSpellDamage = "frost_sp",
    ArcaneSpellDamage = "arcane_sp",
    ShadowSpellDamage = "shadow_sp",
    NatureSpellDamage = "nature_sp",
    HolySpellDamage = "holy_sp",
    DefenseRating = "def",
    DodgeRating = "dodge",
    ParryRating = "parry",
    BlockRating = "block",
    BlockValue = "blockval",
    ResilienceRating = "resilience",
    FireResist = "fire_res",
    FrostResist = "frost_res",
    ArcaneResist = "arcane_res",
    ShadowResist = "shadow_res",
    NatureResist = "nature_res",
    HolyResist = "holy_res",
    -- +1 to all resistances, scored once (ItemStats folds the shared amount into all_res);
    -- the scales set it to the five schools' weights summed, so it isn't added to each school.
    AllResist = "all_res",
}

local IGNORED_PAWN_KEYS = {
    RedSocket = true,
    YellowSocket = true,
    BlueSocket = true,
    ColorlessSocket = true,
    MetaSocket = true,
    MetaSocketEffect = true,
    MeleeMinDamage = true,
    MeleeMaxDamage = true,
    MeleeSpeed = true,
    SpeedBaseline = true,
    IsMainHand = true,
    IsOffHand = true,
    IsOneHand = true,
    IsTwoHand = true,
    IsShield = true,
    IsPlate = true,
    IsMail = true,
    IsLeather = true,
    IsCloth = true,
    IsWand = true,
}

local function addWeight(out, key, value)
    if not key or not value or value <= 0 then return end
    out[key] = (out[key] or 0) + value
end

--- Convert a Pawn-style { StatName = weight } table to internal short keys.
function GU.PawnScaleToWeights(pawnValues)
    local out = {}
    if not pawnValues then return out end
    for pawnKey, raw in pairs(pawnValues) do
        local value = tonumber(raw)
        if value and value > 0 and not IGNORED_PAWN_KEYS[pawnKey] then
            if pawnKey == "Dps" then
                addWeight(out, "melee_dps", value)
            elseif pawnKey == "SpellDamage" then
                addWeight(out, "sp", value)
            else
                local mapped = GU.PAWN_KEY_MAP[pawnKey]
                if mapped then
                    addWeight(out, mapped, value)
                end
            end
        end
    end
    return out
end
