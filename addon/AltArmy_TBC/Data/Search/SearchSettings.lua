-- AltArmy TBC — Search tab settings (AltArmyTBC_SearchSettings).

AltArmy = AltArmy or {}
AltArmy.SearchSettings = AltArmy.SearchSettings or {}

local SS = AltArmy.SearchSettings

local MIN_RECIPE_LEVEL = 0
local MAX_RECIPE_LEVEL = 375

SS.DIFFICULTY_BANDS = { "orange", "yellow", "green", "gray" }
SS.SOURCE_TYPES = { "trainer", "vendor", "quest", "drop", "reputation", "starter" }
SS.PROFESSION_KEYS = {
    "alchemy",
    "blacksmithing",
    "cooking",
    "enchanting",
    "engineering",
    "firstAid",
    "jewelcrafting",
    "leatherworking",
    "mining",
    "poisons",
    "tailoring",
}
SS.PROFESSION_LABELS = {
    alchemy = "Alchemy",
    blacksmithing = "Blacksmithing",
    cooking = "Cooking",
    enchanting = "Enchanting",
    engineering = "Engineering",
    firstAid = "First Aid",
    jewelcrafting = "Jewelcrafting",
    leatherworking = "Leatherworking",
    mining = "Mining",
    poisons = "Poisons (rogue)",
    tailoring = "Tailoring",
}

local PROFESSION_SPELL_IDS = {
    alchemy = 2259,
    blacksmithing = 2018,
    cooking = 2550,
    enchanting = 7411,
    engineering = 4036,
    firstAid = 3273,
    jewelcrafting = 25229,
    leatherworking = 2108,
    mining = 2575,
    poisons = 2842,
    tailoring = 3908,
}

local professionKeyCache = {}

local function clampLevel(value, default)
    local n = math.floor(tonumber(value) or default or MIN_RECIPE_LEVEL)
    if n < MIN_RECIPE_LEVEL then
        return MIN_RECIPE_LEVEL
    end
    if n > MAX_RECIPE_LEVEL then
        return MAX_RECIPE_LEVEL
    end
    return n
end

local function normalizeBooleanMap(filter, keys, defaultValue)
    filter = filter or {}
    for _, key in ipairs(keys) do
        if filter[key] == nil then
            filter[key] = defaultValue
        else
            filter[key] = filter[key] and true or false
        end
    end
    return filter
end

local function isBooleanMapActive(filter, keys, defaultEnabled)
    for _, key in ipairs(keys) do
        local enabled = filter[key]
        if enabled == nil then
            enabled = defaultEnabled
        end
        if not enabled then
            return true
        end
    end
    return false
end

function SS.GetSearchSettings()
    _G.AltArmyTBC_SearchSettings = _G.AltArmyTBC_SearchSettings or {}
    local s = _G.AltArmyTBC_SearchSettings
    s.recipeLevelFilter = s.recipeLevelFilter or {}
    local f = s.recipeLevelFilter
    f.min = clampLevel(f.min, MIN_RECIPE_LEVEL)
    f.max = clampLevel(f.max, MAX_RECIPE_LEVEL)
    if f.min > f.max then
        f.min, f.max = f.max, f.min
    end
    s.difficultyFilter = normalizeBooleanMap(s.difficultyFilter, SS.DIFFICULTY_BANDS, true)
    s.sourceFilter = normalizeBooleanMap(s.sourceFilter, SS.SOURCE_TYPES, true)
    s.professionFilter = normalizeBooleanMap(s.professionFilter, SS.PROFESSION_KEYS, true)
    if s.includeGuildmates == nil then
        s.includeGuildmates = true
    end
    return s
end

--- Whether guildmate-shared recipes are merged into recipe search results (default true).
--- Only takes effect when the guildShare feature flag is on.
function SS.IsIncludeGuildmatesEnabled()
    return SS.GetSearchSettings().includeGuildmates == true
end

local function isCheckboxChecked(on)
    return on == true or on == 1
end

function SS.SetIncludeGuildmatesEnabled(on)
    SS.GetSearchSettings().includeGuildmates = isCheckboxChecked(on)
    local SD = AltArmy and AltArmy.SearchData
    if SD and SD.NotifyRecipesChanged then
        SD.NotifyRecipesChanged()
    end
end

--- Whether the search-mode "Guildmate recipes" checkbox should be shown. Guildmates' recipes don't
--- depend on the player sharing their own (Guild/GuildLinkRead.lua reads them from the server), so the
--- sharing opt-in, which covers grouping and the rest of what the player sends, plays no part.
function SS.ShouldShowIncludeGuildmatesToggle(guildShareFlagOn, hasGuildedCharacters)
    if not guildShareFlagOn then return false end
    if not hasGuildedCharacters then return false end
    return true
end

--- Live evaluation using current addon state (UI visibility + guild recipe eligibility).
function SS.CanShowIncludeGuildmatesToggle()
    local D = AltArmy and AltArmy.Debug
    local flagOn = D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() or false
    local hasGuild = false
    local GTD = AltArmy and AltArmy.GuildTabData
    if GTD and GTD.HasGuildedCharactersOnRealm then
        local realm
        local DS = AltArmy and AltArmy.DataStore
        if DS and DS.GetCurrentPlayerRealm then
            realm = DS:GetCurrentPlayerRealm()
        end
        if not realm or realm == "" then
            realm = (AltArmy.CurrentRealm and AltArmy.CurrentRealm() or GetRealmName and GetRealmName()) or ""
        end
        hasGuild = GTD.HasGuildedCharactersOnRealm(realm)
    end
    return SS.ShouldShowIncludeGuildmatesToggle(flagOn, hasGuild)
end

function SS.GetProfessionDropdownOrder()
    local keys = {}
    for _, key in ipairs(SS.PROFESSION_KEYS) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local la = SS.PROFESSION_LABELS[a] or a
        local lb = SS.PROFESSION_LABELS[b] or b
        return la:lower() < lb:lower()
    end)
    return keys
end

--- Map a scanned profession name to a stable filter key (locale-aware via spell IDs).
function SS.ResolveProfessionKey(professionName)
    if not professionName or professionName == "" then
        return nil
    end
    local cached = professionKeyCache[professionName]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    local RI = AltArmy and AltArmy.RecipeInfo
    if RI and RI.ResolveProfessionKey then
        local key = RI.ResolveProfessionKey(professionName)
        if key then
            professionKeyCache[professionName] = key
            return key
        end
    end
    if GetSpellInfo then
        for key, spellId in pairs(PROFESSION_SPELL_IDS) do
            local name = GetSpellInfo(spellId)
            if name and name == professionName then
                professionKeyCache[professionName] = key
                return key
            end
        end
    end
    professionKeyCache[professionName] = false
    return nil
end

SS._ClearProfessionKeyCache = function()
    for k in pairs(professionKeyCache) do
        professionKeyCache[k] = nil
    end
end

--- Comma-separated enabled labels, or "All" when every key is enabled.
function SS.FormatMultiSelectFilterSummary(keys, labelMap, filter)
    filter = filter or {}
    local allEnabled = true
    local selected = {}
    for _, key in ipairs(keys) do
        if filter[key] then
            selected[#selected + 1] = labelMap[key] or key
        else
            allEnabled = false
        end
    end
    if allEnabled then
        return "All"
    end
    if #selected == 0 then
        return "None"
    end
    return table.concat(selected, ", ")
end

function SS.GetRecipeLevelFilter()
    return SS.GetSearchSettings().recipeLevelFilter
end

--- True when min/max differ from the full-range defaults (0–375 includes all recipes).
function SS.IsRecipeLevelFilterActive(filter)
    filter = filter or SS.GetRecipeLevelFilter()
    return filter.min ~= MIN_RECIPE_LEVEL or filter.max ~= MAX_RECIPE_LEVEL
end

function SS.SetRecipeLevelFilterMin(minLevel)
    SS.GetRecipeLevelFilter().min = clampLevel(minLevel, MIN_RECIPE_LEVEL)
    SS.GetSearchSettings()
end

function SS.SetRecipeLevelFilterMax(maxLevel)
    SS.GetRecipeLevelFilter().max = clampLevel(maxLevel, MAX_RECIPE_LEVEL)
    SS.GetSearchSettings()
end

function SS.ResetRecipeLevelFilter()
    local f = SS.GetRecipeLevelFilter()
    f.min = MIN_RECIPE_LEVEL
    f.max = MAX_RECIPE_LEVEL
    SS.GetSearchSettings()
end

function SS.GetDifficultyFilter()
    return SS.GetSearchSettings().difficultyFilter
end

function SS.IsDifficultyFilterActive(filter)
    filter = filter or SS.GetDifficultyFilter()
    return isBooleanMapActive(filter, SS.DIFFICULTY_BANDS, true)
end

function SS.SetDifficultyBandEnabled(band, enabled)
    SS.GetDifficultyFilter()[band] = enabled and true or false
    SS.GetSearchSettings()
end

function SS.ResetDifficultyFilter()
    local f = SS.GetDifficultyFilter()
    for _, band in ipairs(SS.DIFFICULTY_BANDS) do
        f[band] = true
    end
    SS.GetSearchSettings()
end

function SS.GetSourceFilter()
    return SS.GetSearchSettings().sourceFilter
end

function SS.IsSourceFilterActive(filter)
    filter = filter or SS.GetSourceFilter()
    return isBooleanMapActive(filter, SS.SOURCE_TYPES, true)
end

function SS.SetSourceTypeEnabled(sourceType, enabled)
    SS.GetSourceFilter()[sourceType] = enabled and true or false
    SS.GetSearchSettings()
end

function SS.ResetSourceFilter()
    local f = SS.GetSourceFilter()
    for _, sourceType in ipairs(SS.SOURCE_TYPES) do
        f[sourceType] = true
    end
    SS.GetSearchSettings()
end

function SS.GetProfessionFilter()
    return SS.GetSearchSettings().professionFilter
end

function SS.IsProfessionFilterActive(filter)
    filter = filter or SS.GetProfessionFilter()
    return isBooleanMapActive(filter, SS.PROFESSION_KEYS, true)
end

function SS.SetProfessionEnabled(professionKey, enabled)
    SS.GetProfessionFilter()[professionKey] = enabled and true or false
    SS.GetSearchSettings()
end

function SS.ResetProfessionFilter()
    local f = SS.GetProfessionFilter()
    for _, professionKey in ipairs(SS.PROFESSION_KEYS) do
        f[professionKey] = true
    end
    SS.GetSearchSettings()
end

function SS.IsAnyRecipeFilterActive()
    return SS.IsRecipeLevelFilterActive()
        or SS.IsDifficultyFilterActive()
        or SS.IsSourceFilterActive()
        or SS.IsProfessionFilterActive()
end

function SS.ResetAllRecipeFilters()
    SS.ResetRecipeLevelFilter()
    SS.ResetDifficultyFilter()
    SS.ResetSourceFilter()
    SS.ResetProfessionFilter()
end

SS.MIN_RECIPE_LEVEL = MIN_RECIPE_LEVEL
SS.MAX_RECIPE_LEVEL = MAX_RECIPE_LEVEL
