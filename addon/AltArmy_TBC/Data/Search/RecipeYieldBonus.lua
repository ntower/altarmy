-- AltArmy TBC — recipe yield-bonus specialization classification (alchemy / cloth).
-- Needs recipe data: IsFeatureEnabled requires RecipeInfo.IsAvailable().

AltArmy = AltArmy or {}
AltArmy.RecipeYieldBonus = AltArmy.RecipeYieldBonus or {}

local RYB = AltArmy.RecipeYieldBonus
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

local SPECIALIST_PREFIX = "|cff33ff33+|r "

-- Consumable classID / subclassIDs (TBC Classic GetItemInfo returns).
local ITEM_CLASS_CONSUMABLE = 0
local SUBCLASS_POTION = 1
local SUBCLASS_ELIXIR = 2
local SUBCLASS_FLASK = 3

local CLOTH_BONUS_BY_SPELL = {
    [31373] = "Spellfire", -- Spellcloth
    [36686] = "Shadoweave", -- Shadowcloth
    [26751] = "Mooncloth", -- Primal Mooncloth
}

function RYB.IsFeatureEnabled()
    local RI = AltArmy and AltArmy.RecipeInfo
    return RI and RI.IsAvailable and RI.IsAvailable() and true or false
end

function RYB.FormatSpecialistPrefixMarkup()
    return SPECIALIST_PREFIX
end

--- Spec label for the specialist + / hover tooltip, or nil.
--- Same condition as the + prefix: feature on and recipe bonus matches char spec.
function RYB.GetMatchingSpecLabel(entry)
    if not entry or not RYB.IsFeatureEnabled() then
        return nil
    end
    if not entry._aaYieldBonusMatch then
        return nil
    end
    local spec = entry._aaCharSpecLabel
    if type(spec) == "string" and spec ~= "" then
        return spec
    end
    return nil
end

--- Bonus label for a recipe, or nil when none.
--- @param recipeID number|nil craft spell id
--- @param resultItemID number|nil crafted item id
function RYB.ResolveRecipeBonusLabel(recipeID, resultItemID)
    recipeID = tonumber(recipeID)
    resultItemID = tonumber(resultItemID)

    if recipeID and CLOTH_BONUS_BY_SPELL[recipeID] then
        return CLOTH_BONUS_BY_SPELL[recipeID]
    end

    local CD = AltArmy and AltArmy.CooldownData
    if recipeID and CD and CD.IsTransmuteSpellId then
        if CD.IsTransmuteSpellId(recipeID, GetSpellInfo) then
            return "Transmute"
        end
    elseif recipeID and CD and CD.TRANSMUTE_SPELL_SET and CD.TRANSMUTE_SPELL_SET[recipeID] then
        return "Transmute"
    end

    if not resultItemID or not hasItemInfoApi() then
        return nil
    end

    local name, _, _, _, _, itemType, itemSubType, _, _, _, _, classID, subclassID =
        compatGetItemInfo(resultItemID)
    if not name and not itemType then
        return nil
    end

    if classID == ITEM_CLASS_CONSUMABLE then
        if subclassID == SUBCLASS_POTION then
            return "Potion"
        end
        if subclassID == SUBCLASS_ELIXIR or subclassID == SUBCLASS_FLASK then
            return "Elixir"
        end
    end

    -- Fallback: localized subtype strings (tests / older clients).
    local sub = type(itemSubType) == "string" and itemSubType:lower() or ""
    if sub == "potion" or sub == "potions" then
        return "Potion"
    end
    if sub == "elixir" or sub == "elixirs" or sub == "flask" or sub == "flasks"
        or sub:find("flask", 1, true) then
        return "Elixir"
    end

    return nil
end

local function resolveProfessionKey(entry)
    if not entry then
        return nil
    end
    if entry.professionKey and entry.professionKey ~= "" then
        return entry.professionKey
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.ResolveProfessionKey and entry.professionName then
        return SS.ResolveProfessionKey(entry.professionName)
    end
    return nil
end

--- Profession specialization label for the crafter on this entry, or nil.
function RYB.LookupCharSpecLabel(entry)
    if not entry or not entry.characterName then
        return nil
    end

    if entry.isGuild then
        local data = _G.AltArmyTBC_GuildData
        local realm = entry.realm
        local chars = data and data.chars and realm and data.chars[realm]
        if type(chars) ~= "table" then
            return nil
        end
        local char = chars[entry.characterName]
        if not char and type(chars) == "table" then
            local want = entry.characterName:lower()
            for _, c in pairs(chars) do
                if type(c) == "table" and type(c.name) == "string" and c.name:lower() == want then
                    char = c
                    break
                end
            end
        end
        local profs = char and char.Professions
        if type(profs) ~= "table" then
            return nil
        end
        local key = resolveProfessionKey(entry)
        if key and profs[key] and profs[key].spec then
            return profs[key].spec
        end
        -- Fall back: match by profession display name.
        local wantName = entry.professionName
        if wantName then
            for _, prof in pairs(profs) do
                if type(prof) == "table" and (prof.name == wantName or prof.key == wantName) then
                    return prof.spec
                end
            end
        end
        return nil
    end

    -- Local account character.
    if not DS or not DS.GetCharacter then
        return nil
    end
    local char = DS:GetCharacterFor(entry.characterName, entry.realm, entry.linkId)
    if not char then
        return nil
    end
    local profs = char.Professions
    if type(profs) ~= "table" then
        return nil
    end
    local profName = entry.professionName
    if profName and profs[profName] and profs[profName].specialization then
        return profs[profName].specialization
    end
    local key = resolveProfessionKey(entry)
    if key then
        for name, prof in pairs(profs) do
            local SS = AltArmy and AltArmy.SearchSettings
            local pkey = SS and SS.ResolveProfessionKey and SS.ResolveProfessionKey(name)
            if pkey == key and type(prof) == "table" and prof.specialization then
                return prof.specialization
            end
        end
    end
    return nil
end

local function ensureResultItemId(entry)
    if not entry or entry.resultItemID then
        return
    end
    local RI = AltArmy and AltArmy.RecipeInfo
    if RI and RI.EnrichEntry then
        RI.EnrichEntry(entry)
    end
end

--- Stamp `_aaRecipeBonusLabel`, `_aaCharSpecLabel`, `_aaYieldBonusMatch` when feature on.
function RYB.StampEntry(entry)
    if not entry then
        return entry
    end
    if not RYB.IsFeatureEnabled() then
        return entry
    end
    if entry._aaYieldStamped then
        return entry
    end

    ensureResultItemId(entry)
    local bonus = RYB.ResolveRecipeBonusLabel(entry.recipeID, entry.resultItemID)
    local spec = RYB.LookupCharSpecLabel(entry)
    entry._aaRecipeBonusLabel = bonus
    entry._aaCharSpecLabel = spec
    entry._aaYieldBonusMatch = (bonus ~= nil and spec ~= nil and bonus == spec) and true or false
    entry._aaYieldStamped = true
    return entry
end

return RYB
