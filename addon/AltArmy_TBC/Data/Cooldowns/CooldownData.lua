-- AltArmy TBC — Cooldown categories, row building, mats, and alert evaluation (data only).
-- Consumed by TabCooldowns.lua and CooldownAlerts.lua.

if not AltArmy then return end

AltArmy.CooldownData = AltArmy.CooldownData or {}
local CD = AltArmy.CooldownData

---@class CooldownCategoryDef
---@field key string Stable id (e.g. "transmute").
---@field title string UI label.
---@field mode "group"|"single" group = one row if any spell in spellIds matches; single = per spell row.
---@field spellIds number[]|nil For single-mode or group membership.
---@field spellId number|nil Primary spell for single mode (same as spellIds[1]).
---@field legacyTalent boolean|nil Known via a Legacy talent (char.legacyTalents.spells), not a profession recipe.
---@field noReagents boolean|nil Needs no materials: no mats count, tooltip reagents or stockpile send.

--- Longest plausible tracked profession cooldown in TBC (~Shadowcloth 3d 20h).
--- Saved values above this are shown as unscanned in the UI (see IsExpiryPlausible).
CD.MAX_PROF_COOLDOWN_SECONDS = 4 * 86400

CD.CATEGORY_ORDER = {
    "transmute",
    "spellcloth",
    "shadowcloth",
    "primal_mooncloth",
    "brilliant_glass",
    "void_sphere",
    "research",
    "dedicated_study",
}

--- Categories WoW Forever's Options → Cooldowns tab shows (the rest are TBC-specific crafts).
CD.FOREVER_OPTIONS_CATEGORY_ORDER = { "dedicated_study", "transmute", "research" }

--- Category keys the Options → Cooldowns tab builds rows for.
---@param isForever boolean
---@return string[]
function CD.GetOptionsCategoryOrder(isForever)
    if isForever then
        return CD.FOREVER_OPTIONS_CATEGORY_ORDER
    end
    return CD.CATEGORY_ORDER
end

-- TBC enchanting sphere crafts share one cooldown (2 days).
CD.SPHERE_SPELL_IDS = {
    28028, -- Void Sphere
    28027, -- Prismatic Sphere
}

--- Prefer Void Sphere when both are known (unless last cast says otherwise).
CD.SPHERE_AUTOMATIC_FALLBACK_SPELL_IDS = {
    28028, -- Void Sphere
    28027, -- Prismatic Sphere
}

-- TBC: transmute spells (alchemy). Used for category membership + effective recipe resolution.
CD.TRANSMUTE_SPELL_IDS = {
    11480, -- Transmute: Mithril to Truesilver
    17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566,
    28566, 28567, 28568, 28569, 28580, 28581, 28582, 28583, 28584, 28585,
    29688, -- Transmute: Primal Might
    32765, -- Transmute: Earthstorm Diamond
    32766, -- Transmute: Skyfire Diamond
    -- Transmute: Arcanite (automatic fallback after Primal Might).
    17187,
}

--- After last successful transmute (if still known): Primal Might, then Arcanite.
CD.TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS = {
    29688, -- Transmute: Primal Might
    17187, -- Transmute: Arcanite
}

local function KeySet(list)
    local s = {}
    for _, id in ipairs(list) do
        s[id] = true
    end
    return s
end

CD.TRANSMUTE_SPELL_SET = KeySet(CD.TRANSMUTE_SPELL_IDS)
CD.SPHERE_SPELL_SET = KeySet(CD.SPHERE_SPELL_IDS)

-- TBC profession specialization passive spell IDs (for cooldown UI / alerts).
CD.COOLDOWN_SPEC_SPELL_IDS = {
    masterTransmutation = 28672,
    spellfireTailor = 26797,
    shadoweaveTailor = 26801,
    moonclothTailor = 26798,
}

--- Maps cooldown category key -> char.cooldownSpecs field name (see DataStoreProfessions).
CD.CATEGORY_SPEC_FIELD = {
    transmute = "masterTransmutation",
    spellcloth = "spellfireTailor",
    shadowcloth = "shadoweaveTailor",
    primal_mooncloth = "moonclothTailor",
}

CD.CATEGORIES = {
    transmute = {
        key = "transmute",
        title = "Transmute",
        mode = "group",
        spellIds = CD.TRANSMUTE_SPELL_IDS,
    },
    spellcloth = {
        key = "spellcloth",
        title = "Spellcloth",
        mode = "single",
        spellId = 31373,
        spellIds = { 31373 },
    },
    shadowcloth = {
        key = "shadowcloth",
        title = "Shadowcloth",
        mode = "single",
        spellId = 36686,
        spellIds = { 36686 },
    },
    primal_mooncloth = {
        key = "primal_mooncloth",
        title = "Primal Mooncloth",
        mode = "single",
        spellId = 26751,
        spellIds = { 26751 },
    },
    brilliant_glass = {
        key = "brilliant_glass",
        title = "Brilliant Glass",
        mode = "single",
        spellId = 47280,
        spellIds = { 47280 },
    },
    void_sphere = {
        key = "void_sphere",
        title = "Void Sphere / Prismatic Sphere",
        mode = "group",
        spellIds = CD.SPHERE_SPELL_IDS,
    },
    -- WoW Forever: Comprehension (mage-only profession), shown as "Research" in the spellbook; 1h.
    -- Study is the only Research recipe known so far. Revisit if more appear: if they share one
    -- cooldown this should become a "group" category like transmute.
    research = {
        key = "research",
        title = "Research",
        mode = "single",
        spellId = 1302508, -- Study
        spellIds = { 1302508 },
    },
    -- WoW Forever: Legacy talent (Profession tree); 23h. +1 skill in the lowest tradeskill, no reagents.
    dedicated_study = {
        key = "dedicated_study",
        title = "Dedicated Study",
        mode = "single",
        spellId = 1225469,
        spellIds = { 1225469 },
        legacyTalent = true,
        noReagents = true,
    },
}

-- Reagent lists for mats + tooltips come from AltArmyTBC_Data.RecipeReagents, filled when you
-- open a tradeskill or craft window (ScanRecipes / ScanCraftRecipes read the client APIs).

--- Built-in reagents for tracked recipes whose reagents the client scan can't capture. WoW Forever's
--- C_TradeSkillUI recipe scan doesn't read reagents yet, so without this Research has no mats.
--- A scanned RecipeReagents entry still wins.
CD.KNOWN_RECIPE_REAGENTS = {
    [1302508] = { { 17056, 1 } }, -- Study: 1x Light Feather
}

--- Lookup order matches DataStoreProfession captures (accountData then SavedVariables root).
local function RecipeReagentsTableForSpell(spellId)
    if not spellId then return nil end
    local tries = {}
    local seenDb = {}
    local function append(db)
        if db and type(db) == "table" and not seenDb[db] then
            seenDb[db] = true
            tries[#tries + 1] = db
        end
    end
    local DS = AltArmy and AltArmy.DataStore
    append(DS and DS.accountData)
    append(rawget(_G, "AltArmyTBC_Data"))
    append(AltArmy and AltArmy.DB)
    for _, db in ipairs(tries) do
        local rr = db.RecipeReagents
        if type(rr) == "table" then
            local list = rr[spellId]
            if type(list) == "table" and #list > 0 then
                return list
            end
        end
    end
    return CD.KNOWN_RECIPE_REAGENTS[spellId]
end

--- Flat set of every spell id we persist cooldown expiry for.
function CD.GetAllTrackedSpellIds()
    local out = {}
    local seen = {}
    for _, id in ipairs(CD.TRANSMUTE_SPELL_IDS) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, key in ipairs(CD.CATEGORY_ORDER) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.spellIds then
            for _, sid in ipairs(cat.spellIds) do
                if not seen[sid] then
                    seen[sid] = true
                    out[#out + 1] = sid
                end
            end
        end
    end
    return out, seen
end

local _, TRACKED_SET = CD.GetAllTrackedSpellIds()
CD._TRACKED_SPELL_SET = TRACKED_SET

--- Defaults for AltArmyTBC_Options.cooldowns (SavedVariables).
function CD.ResetCooldownOptionsToDefaults()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    _G.AltArmyTBC_Options.cooldowns = nil
    CD.EnsureCooldownOptions()
end

function CD.EnsureCooldownOptions()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local root = _G.AltArmyTBC_Options
    root.cooldowns = root.cooldowns or {}
    local cd = root.cooldowns
    cd.categories = cd.categories or {}
    for _, key in ipairs(CD.CATEGORY_ORDER) do
        local cat = cd.categories[key]
        if not cat then
            cat = {}
            cd.categories[key] = cat
        end
        if cat.showInUI == nil then
            cat.showInUI = true
        end
        cat.alertMinutesBefore = nil
        cat.alertMinutesBeforeMinutes = nil
        if cat.alertWhenAvailable == nil then cat.alertWhenAvailable = true end
        if cat.showOnlyIfSpecialization == nil then cat.showOnlyIfSpecialization = false end
        if cat.alertOnlyIfSpecialization == nil then cat.alertOnlyIfSpecialization = false end
        cat.alertType = nil
        cat.remindMe = nil
        cat.remindEveryMinutes = nil
    end
    local sk = cd.listSortKey
    if sk ~= "recipe" and sk ~= "character" and sk ~= "mats" and sk ~= "time" then
        cd.listSortKey = "recipe"
    end
    if cd.listSortAscending == nil then
        cd.listSortAscending = true
    end
    return cd
end

function CD.IsTrackedSpellId(spellId)
    return spellId and TRACKED_SET[spellId] == true
end

--- True when the character's captured Legacy talents include spellId (see DataStoreLegacy).
function CD.CharacterHasLegacyTalentSpell(char, spellId)
    local legacy = char and char.legacyTalents
    local spells = type(legacy) == "table" and legacy.spells
    return type(spells) == "table" and (tonumber(spells[spellId]) or 0) > 0
end

--- True for spells whose category needs no materials (no mats, reagent tooltip or stockpile send).
function CD.SpellNeedsNoReagents(spellId)
    if not spellId then return false end
    for _, key in ipairs(CD.CATEGORY_ORDER) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.noReagents and cat.spellId == spellId then
            return true
        end
    end
    return false
end

--- @param char table
--- @param spellId number
--- @return boolean, string|nil professionName
function CD.FindRecipeProfession(char, spellId)
    if not char or not spellId or not char.Professions then
        return false, nil
    end
    for profName, prof in pairs(char.Professions) do
        if prof and prof.Recipes and prof.Recipes[spellId] then
            return true, profName
        end
    end
    return false, nil
end

--- Known transmute if recipe id is in transmute set OR name contains "Transmute" (fallback).
function CD.CharacterKnowsTransmute(char, getSpellInfoFn)
    if not char or not char.Professions then return false end
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes then
            for rid in pairs(prof.Recipes) do
                if CD.TRANSMUTE_SPELL_SET[rid] then
                    return true
                end
            end
        end
    end
    local gsi = getSpellInfoFn or GetSpellInfo
    if gsi then
        for _, prof in pairs(char.Professions) do
            if prof and prof.Recipes then
                for rid in pairs(prof.Recipes) do
                    local name = gsi(rid)
                    if type(name) == "string" and name:lower():find("transmute", 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Collect transmute spell ids known anywhere on the account.
function CD.CollectAccountKnownTransmuteSpellIds(data, getSpellInfoFn)
    local out = {}
    local seen = {}
    local gsi = getSpellInfoFn or GetSpellInfo
    if not data or not data.Characters then return out end
    for _, realmTable in pairs(data.Characters) do
        for _, char in pairs(realmTable or {}) do
            if char and char.Professions then
                for _, prof in pairs(char.Professions) do
                    if prof and prof.Recipes then
                        for rid in pairs(prof.Recipes) do
                            if not seen[rid] and CD.IsTransmuteSpellId(rid, gsi) then
                                seen[rid] = true
                                out[#out + 1] = rid
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

--- True if spellId is an alchemy transmute (ID set or localized name contains "transmute").
function CD.IsTransmuteSpellId(spellId, getSpellInfoFn)
    if not spellId then return false end
    if CD.TRANSMUTE_SPELL_SET[spellId] then return true end
    local gsi = getSpellInfoFn or GetSpellInfo
    if gsi then
        local name = gsi(spellId)
        if type(name) == "string" and name:lower():find("transmute", 1, true) then
            return true
        end
    end
    return false
end

--- Called when the player completes a spell cast that is a transmute (combat log).
--- Persists char.lastTransmute = { spellId = number, ... } for future fields.
function CD.RecordSuccessfulTransmuteCast(char, spellId)
    if not char or type(spellId) ~= "number" then return end
    if not CD.IsTransmuteSpellId(spellId, GetSpellInfo) then return end
    char.lastTransmute = { spellId = spellId }
end

function CD.IsSphereSpellId(spellId)
    return spellId and CD.SPHERE_SPELL_SET[spellId] == true
end

--- Called when the player completes a sphere craft (combat log / cast success).
function CD.RecordSuccessfulSphereCast(char, spellId)
    if not char or type(spellId) ~= "number" then return end
    if not CD.IsSphereSpellId(spellId) then return end
    char.lastSphere = { spellId = spellId }
end

--- True for categories that share one cooldown across several recipes (transmute, spheres).
function CD.IsGroupCategory(categoryKey)
    local cat = CD.CATEGORIES[categoryKey]
    return cat and cat.mode == "group" and type(cat.spellIds) == "table"
end

local function GroupSpellIds(categoryKey)
    if not CD.IsGroupCategory(categoryKey) then
        return nil
    end
    return CD.CATEGORIES[categoryKey].spellIds
end

--- Group spell ids this character knows, in category definition order.
function CD.GetKnownGroupSpellIds(char, categoryKey)
    local ids = GroupSpellIds(categoryKey)
    if not ids or not char then
        return {}
    end
    local out = {}
    for _, sid in ipairs(ids) do
        if select(1, CD.FindRecipeProfession(char, sid)) then
            out[#out + 1] = sid
        end
    end
    return out
end

--- "auto" or a known group spellId. Unknown / unlearned overrides are Auto.
function CD.GetGroupRecipeChoice(char, categoryKey)
    if not char or not GroupSpellIds(categoryKey) then
        return "auto"
    end
    local t = char.cooldownGroupChoice
    local chosen = t and t[categoryKey]
    if type(chosen) == "number" and select(1, CD.FindRecipeProfession(char, chosen)) then
        local ids = GroupSpellIds(categoryKey)
        for _, sid in ipairs(ids) do
            if sid == chosen then
                return chosen
            end
        end
    end
    return "auto"
end

--- Persist Auto (clears override) or a known group spellId. Ignores invalid picks.
function CD.SetGroupRecipeChoice(char, categoryKey, choice)
    if not char or not GroupSpellIds(categoryKey) then
        return
    end
    if choice == "auto" or choice == nil then
        if type(char.cooldownGroupChoice) == "table" then
            char.cooldownGroupChoice[categoryKey] = nil
        end
        return
    end
    if type(choice) ~= "number" or not select(1, CD.FindRecipeProfession(char, choice)) then
        return
    end
    local inGroup = false
    for _, sid in ipairs(GroupSpellIds(categoryKey)) do
        if sid == choice then
            inGroup = true
            break
        end
    end
    if not inGroup then
        return
    end
    char.cooldownGroupChoice = char.cooldownGroupChoice or {}
    char.cooldownGroupChoice[categoryKey] = choice
end

local function GroupRecipeDisplayTitle(categoryKey, spellId, getSpellInfoFn)
    if categoryKey == "transmute" then
        return CD.TransmuteCategoryDisplayTitle(spellId, getSpellInfoFn)
    end
    if categoryKey == "void_sphere" then
        return CD.SphereCategoryDisplayTitle(spellId, getSpellInfoFn)
    end
    local name = getSpellInfoFn and getSpellInfoFn(spellId)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return tostring(spellId)
end

--- Last-cast then fallback (no manual cooldownGroupChoice).
local function ResolveSphereSpellAuto(char)
    if not char then return nil end
    local last = char.lastSphere
    local lastId = type(last) == "table" and type(last.spellId) == "number" and last.spellId or nil
    if lastId and select(1, CD.FindRecipeProfession(char, lastId)) then
        return lastId
    end
    for _, sid in ipairs(CD.SPHERE_AUTOMATIC_FALLBACK_SPELL_IDS) do
        if select(1, CD.FindRecipeProfession(char, sid)) then
            return sid
        end
    end
    return nil
end

--- Last-cast then fallback (no manual cooldownGroupChoice).
local function ResolveTransmuteSpellAuto(char)
    if not char then return nil end
    local last = char.lastTransmute
    local lastId = type(last) == "table" and type(last.spellId) == "number" and last.spellId or nil
    if lastId and select(1, CD.FindRecipeProfession(char, lastId)) then
        return lastId
    end
    for _, sid in ipairs(CD.TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS) do
        if select(1, CD.FindRecipeProfession(char, sid)) then
            return sid
        end
    end
    return nil
end

local function ResolveGroupSpellAuto(char, categoryKey)
    if categoryKey == "transmute" then
        return ResolveTransmuteSpellAuto(char)
    end
    if categoryKey == "void_sphere" then
        return ResolveSphereSpellAuto(char)
    end
    return nil
end

local function GroupRecipeEntryMatchesQuery(entry, query)
    if not query or query == "" then
        return true
    end
    if entry.id == "auto" then
        if string.find("auto", query, 1, true) then
            return true
        end
        local autoLabel = entry.autoLabel
        return type(autoLabel) == "string" and string.find(autoLabel:lower(), query, 1, true) ~= nil
    end
    local label = entry.label
    return type(label) == "string" and string.find(label:lower(), query, 1, true) ~= nil
end

--- Dropdown entries: Auto first, then known recipes A–Z by display label.
--- Auto includes spellId/autoLabel for the last-cast/fallback recipe (ignores manual pick).
--- Optional query (case-insensitive) filters Auto by "auto"/autoLabel and recipes by label.
function CD.ListGroupRecipeChoiceEntries(char, categoryKey, getSpellInfoFn, query)
    local gsi = getSpellInfoFn or GetSpellInfo
    local autoSpellId = ResolveGroupSpellAuto(char, categoryKey)
    local autoLabel = autoSpellId and GroupRecipeDisplayTitle(categoryKey, autoSpellId, gsi) or nil
    local entries = {
        { id = "auto", label = "Auto", spellId = autoSpellId, autoLabel = autoLabel },
    }
    if not GroupSpellIds(categoryKey) then
        return entries
    end
    local recipes = {}
    for _, sid in ipairs(CD.GetKnownGroupSpellIds(char, categoryKey)) do
        local label = GroupRecipeDisplayTitle(categoryKey, sid, gsi)
        recipes[#recipes + 1] = { id = sid, label = label, spellId = sid }
    end
    table.sort(recipes, function(a, b)
        return (a.label or ""):lower() < (b.label or ""):lower()
    end)
    for i = 1, #recipes do
        entries[#entries + 1] = recipes[i]
    end
    if type(query) == "string" then
        query = (query:match("^%s*(.-)%s*$") or query):lower()
    else
        query = ""
    end
    if query == "" then
        return entries
    end
    local filtered = {}
    for i = 1, #entries do
        if GroupRecipeEntryMatchesQuery(entries[i], query) then
            filtered[#filtered + 1] = entries[i]
        end
    end
    return filtered
end

local GROUP_RECIPE_AUTO_GRAY = "|cffaaaaaa"

--- Dropdown text for Auto / recipe entries. Optional highlightFn(text, query, formatSegment)
--- wraps matching substrings (same contract as GuildTabData.FormatTextWithSearchHighlight).
function CD.FormatGroupRecipeChoiceDisplayLabel(entry, query, highlightFn)
    local function hl(text, formatSegment)
        if highlightFn then
            return highlightFn(text, query, formatSegment)
        end
        if formatSegment then
            return formatSegment(text)
        end
        return text or ""
    end
    local function gray(seg)
        return GROUP_RECIPE_AUTO_GRAY .. (seg or "") .. "|r"
    end
    if not entry or entry.id == "auto" then
        local autoWord = hl("Auto")
        local autoLabel = entry and entry.autoLabel
        if type(autoLabel) == "string" and autoLabel ~= "" then
            if highlightFn then
                local inner = hl(autoLabel, gray)
                return autoWord .. " " .. GROUP_RECIPE_AUTO_GRAY .. "(|r" .. inner
                    .. GROUP_RECIPE_AUTO_GRAY .. ")|r"
            end
            return autoWord .. " " .. GROUP_RECIPE_AUTO_GRAY .. "(" .. autoLabel .. ")|r"
        end
        return autoWord
    end
    return hl(entry.label or "")
end

local function ResolveGroupOverride(char, categoryKey)
    local choice = CD.GetGroupRecipeChoice(char, categoryKey)
    if type(choice) == "number" then
        return choice
    end
    return nil
end

--- Effective sphere spell for cooldown rows:
--- 0) manual cooldownGroupChoice when still known,
--- 1) last successful sphere craft when still known,
--- 2) Void Sphere then Prismatic Sphere when known.
--- nil = do not show sphere row.
function CD.ResolveSphereSpellForCharacter(char)
    if not char then return nil end
    local override = ResolveGroupOverride(char, "void_sphere")
    if override then
        return override
    end
    return ResolveSphereSpellAuto(char)
end

--- Effective transmute spell for cooldown rows:
--- 0) manual cooldownGroupChoice when still known,
--- 1) last successful transmute when still known,
--- 2) Primal Might then Arcanite when known.
--- nil = do not show transmute row.
function CD.ResolveTransmuteSpellForCharacter(char)
    if not char then return nil end
    local override = ResolveGroupOverride(char, "transmute")
    if override then
        return override
    end
    return ResolveTransmuteSpellAuto(char)
end

--- Short label for the Recipe column when category is transmute (from effective spell name).
--- e.g. "Transmute: Primal Might" / "Alchemy: Transmute: Primal Might" -> "Primal Might".
function CD.TransmuteCategoryDisplayTitle(spellId, getSpellInfoFn)
    local fallback = (CD.CATEGORIES.transmute and CD.CATEGORIES.transmute.title) or "Transmute"
    if not spellId or type(getSpellInfoFn) ~= "function" then
        return fallback
    end
    local name = getSpellInfoFn(spellId)
    if type(name) ~= "string" or name == "" then
        return fallback
    end
    local after = name:match("Transmute:%s*(.+)$") or name:match("transmute:%s*(.+)$")
    if after and after ~= "" then
        return after:gsub("^%s+", "")
    end
    return name
end

--- Short label for the Recipe column when category is void_sphere (from effective spell name).
function CD.SphereCategoryDisplayTitle(spellId, getSpellInfoFn)
    local fallback = (CD.CATEGORIES.void_sphere and CD.CATEGORIES.void_sphere.title)
        or "Void Sphere / Prismatic Sphere"
    if not spellId or type(getSpellInfoFn) ~= "function" then
        return fallback
    end
    local name = getSpellInfoFn(spellId)
    if type(name) ~= "string" or name == "" then
        return fallback
    end
    return name
end

--- Per-category spell used for mats / tooltip.
function CD.ResolveEffectiveSpellId(categoryKey, char, _options)
    local cat = CD.CATEGORIES[categoryKey]
    if not cat then return nil end
    if categoryKey == "transmute" then
        return CD.ResolveTransmuteSpellForCharacter(char)
    end
    if categoryKey == "void_sphere" then
        return CD.ResolveSphereSpellForCharacter(char)
    end
    if cat.mode == "single" and cat.spellId then
        return cat.spellId
    end
    return cat.spellIds and cat.spellIds[1] or nil
end

--- {{ itemID, quantity }, ...} from account cache (see DataStoreProfessions capture), else nil.
function CD.GetReagentList(spellId)
    if not spellId then return nil end
    return RecipeReagentsTableForSpell(spellId)
end

--- @param char table
--- @param spellId number
--- @param getContainerItemCount fun(char, itemID): number
--- Maximum crafts from inventory, or nil if RecipeReagents not loaded yet (open tradeskill once).
function CD.GetMaxCraftableQuantity(char, spellId, getContainerItemCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not char or not getContainerItemCount then
        return nil
    end
    local minCrafts = math.huge
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local have = getContainerItemCount(char, itemId) or 0
        local n = math.floor(have / need)
        if n < minCrafts then
            minCrafts = n
        end
    end
    if minCrafts == math.huge then
        return 0
    end
    return minCrafts
end

--- Maximum crafts possible after transferring all reagents from source to target.
--- Returns nil when reagent list is unknown (open tradeskill once).
--- @param target table
--- @param source table
--- @param spellId number
--- @param getTargetCount fun(char, itemID): number
--- @param getSourceCount fun(char, itemID): number
function CD.GetMaxCraftableQuantityAfterTransfer(target, source, spellId, getTargetCount, getSourceCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not target or not source or not getTargetCount or not getSourceCount then
        return nil
    end
    local minCrafts = math.huge
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local haveTarget = getTargetCount(target, itemId) or 0
        local haveSource = getSourceCount(source, itemId) or 0
        local n = math.floor((haveTarget + haveSource) / need)
        if n < minCrafts then
            minCrafts = n
        end
    end
    if minCrafts == math.huge then
        return 0
    end
    return minCrafts
end

--- For a requested craft count, compute per-reagent quantities needed from source to reach it.
--- Assumes requestedCrafts is within feasible range; callers should validate vs max-after-transfer.
--- Returns nil when reagent list is unknown.
--- @return table[]|nil rows { itemID, need, targetHave, sourceHave, requiredToSend }
function CD.GetReagentSendPlan(target, source, spellId, requestedCrafts, getTargetCount, getSourceCount)
    local list = CD.GetReagentList(spellId)
    if not list then
        return nil
    end
    if not target or not source or not getTargetCount or not getSourceCount then
        return nil
    end
    local crafts = tonumber(requestedCrafts) or 0
    if crafts < 0 then crafts = 0 end
    local rows = {}
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        if need <= 0 then
            need = 1
        end
        local targetHave = getTargetCount(target, itemId) or 0
        local sourceHave = getSourceCount(source, itemId) or 0
        local required = crafts * need - targetHave
        if required < 0 then required = 0 end
        rows[#rows + 1] = {
            itemID = itemId,
            need = need,
            targetHave = targetHave,
            sourceHave = sourceHave,
            requiredToSend = required,
        }
    end
    return rows
end

--- Classify a crafting-cooldown list row for /alta sendall N.
--- minCrafts / maxAfterTransfer may be nil when RecipeReagents are unknown.
--- @return table { action, reason?, requestedCrafts? }
---   action = "send"|"skip"
---   reason = "self"|"realm"|"enough"|"unknown"|"insufficient"|nil
function CD.EvaluateSendAllRow(curName, curRealm, rowName, rowRealm, n, minCrafts, maxAfterTransfer)
    local targetN = tonumber(n) or 0
    if (rowName or "") == (curName or "") and (rowRealm or "") == (curRealm or "") then
        return { action = "skip", reason = "self" }
    end
    if (rowRealm or "") ~= (curRealm or "") then
        return { action = "skip", reason = "realm" }
    end
    if minCrafts == nil or maxAfterTransfer == nil then
        return { action = "skip", reason = "unknown" }
    end
    local minV = tonumber(minCrafts) or 0
    local maxV = tonumber(maxAfterTransfer) or 0
    if minV >= targetN then
        return { action = "skip", reason = "enough" }
    end
    if maxV < targetN then
        return { action = "skip", reason = "insufficient" }
    end
    return { action = "send", requestedCrafts = targetN }
end

--- Allocate a shared source reagent pool across selected cooldown rows in list order.
--- desiredN is the absolute craft count each selected row should reach (same as sendall N).
--- sourceCounts: map itemID -> count available on the sending character.
--- rowInputs: array of {
---   selected = bool,
---   skip = "self"|"realm"|nil,
---   minCrafts = number|nil,  -- nil = unknown reagents
---   reagents = { { itemID, need, targetHave }, ... }|nil
--- }
--- @return table { rows = { { willHave, delta, shortfall }, ... }, anyShortfall = bool }
function CD.AllocateSendAllCrafts(desiredN, sourceCounts, rowInputs)
    local targetN = tonumber(desiredN) or 0
    if targetN < 0 then targetN = 0 end
    local remaining = {}
    if sourceCounts then
        for itemId, count in pairs(sourceCounts) do
            remaining[itemId] = tonumber(count) or 0
        end
    end
    local out = {}
    local anyShortfall = false
    local inputs = rowInputs or {}
    for i = 1, #inputs do
        local inp = inputs[i] or {}
        local minCrafts = inp.minCrafts
        local baseline = tonumber(minCrafts) or 0
        local entry = { willHave = baseline, delta = 0, shortfall = false }

        if not inp.selected or inp.skip == "self" or inp.skip == "realm" then
            out[#out + 1] = entry
        elseif minCrafts == nil or not inp.reagents then
            entry.willHave = 0
            entry.shortfall = true
            anyShortfall = true
            out[#out + 1] = entry
        elseif baseline >= targetN then
            entry.willHave = baseline
            entry.delta = 0
            entry.shortfall = false
            out[#out + 1] = entry
        else
            local maxFromRemaining = math.huge
            for _, r in ipairs(inp.reagents) do
                local need = tonumber(r.need) or 1
                if need <= 0 then need = 1 end
                local targetHave = tonumber(r.targetHave) or 0
                local srcHave = remaining[r.itemID] or 0
                local n = math.floor((targetHave + srcHave) / need)
                if n < maxFromRemaining then
                    maxFromRemaining = n
                end
            end
            if maxFromRemaining == math.huge then
                maxFromRemaining = baseline
            end
            local willHave = maxFromRemaining
            if willHave > targetN then willHave = targetN end
            if willHave < baseline then willHave = baseline end
            -- Consume reagents for the increase above what the target already has.
            for _, r in ipairs(inp.reagents) do
                local need = tonumber(r.need) or 1
                if need <= 0 then need = 1 end
                local targetHave = tonumber(r.targetHave) or 0
                local required = willHave * need - targetHave
                if required < 0 then required = 0 end
                local have = remaining[r.itemID] or 0
                remaining[r.itemID] = have - required
                if remaining[r.itemID] < 0 then
                    remaining[r.itemID] = 0
                end
            end
            entry.willHave = willHave
            entry.delta = willHave - baseline
            if willHave < targetN then
                entry.shortfall = true
                anyShortfall = true
            end
            out[#out + 1] = entry
        end
    end
    return { rows = out, anyShortfall = anyShortfall }
end

--- true / false when reagents known; nil when RecipeReagents missing for this spell.
function CD.CharacterHasReagents(char, spellId, getContainerItemCount)
    local qty = CD.GetMaxCraftableQuantity(char, spellId, getContainerItemCount)
    if qty == nil then
        return nil
    end
    return qty >= 1
end

--- @param char table
--- @param spellId number
--- @param getContainerItemCount fun(char, itemID): number
function CD.GetReagentHaveCounts(char, spellId, getContainerItemCount)
    local list = CD.GetReagentList(spellId)
    if not list or not char or not getContainerItemCount then return {} end
    local rows = {}
    for _, pair in ipairs(list) do
        local itemId, need = pair[1], pair[2] or 1
        rows[#rows + 1] = {
            itemID = itemId,
            need = need,
            have = getContainerItemCount(char, itemId) or 0,
        }
    end
    return rows
end

--- Nil on WoW Forever: specializations (Master of Transmutation, tailoring specs) are TBC-only there, so
--- any saved "only if specialization" setting is ignored.
--- @return string|nil field key on char.cooldownSpecs
function CD.CategorySpecField(categoryKey)
    local DS = AltArmy and AltArmy.DataStore
    if DS and DS.IsWowForever then
        return nil
    end
    return CD.CATEGORY_SPEC_FIELD[categoryKey]
end

--- Whether the category offers "only if specialization" options on this client.
function CD.CategoryHasSpecialization(categoryKey)
    return CD.CategorySpecField(categoryKey) ~= nil
end

--- @param char table
--- @param field string e.g. "masterTransmutation"
function CD.CharacterHasCooldownSpec(char, field)
    if not char or not field then return false end
    local cs = char.cooldownSpecs
    return type(cs) == "table" and cs[field] == true
end

--- When requireFlag is false, always true. When true, character must have matching persisted spec.
function CD.RowMeetsSpecializationGate(categoryKey, char, requireFlag)
    if not requireFlag then return true end
    local field = CD.CategorySpecField(categoryKey)
    if not field then return true end
    return CD.CharacterHasCooldownSpec(char, field)
end

local function CategoryListVisible(categoryKey, options)
    local o = options and options.categories and options.categories[categoryKey]
    if o and o.showInUI == false then
        return false
    end
    return true
end

--- True when expiry is nil, ready, or within the longest tracked profession CD.
function CD.IsExpiryPlausible(expiresUnix, now)
    if expiresUnix == nil then
        return false
    end
    now = now or (time and time() or 0)
    if expiresUnix <= now then
        return true
    end
    return (expiresUnix - now) <= CD.MAX_PROF_COOLDOWN_SECONDS
end

--- Expiry for UI rows/alerts; nil when missing or implausibly far in the future.
function CD.ExpiryForDisplay(expiresUnix, now)
    if CD.IsExpiryPlausible(expiresUnix, now) then
        return expiresUnix
    end
    return nil
end

--- @param expiresUnix number|nil When spell cooldown ends (unix); nil = unknown / never scanned.
--- @param now number unix time
function CD.FormatTimeRemaining(expiresUnix, now)
    now = now or (time and time() or 0)
    if not CD.IsExpiryPlausible(expiresUnix, now) then
        return "Unscanned"
    end
    if expiresUnix <= now then
        return "Ready"
    end
    local sec = math.floor(expiresUnix - now)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h >= 24 then
        local d = math.floor(h / 24)
        local rh = h % 24
        return string.format("%dd %dh %dm", d, rh, m)
    end
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    if m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

--- Read unix expiry for a spell from char.ProfCooldownExpiry
function CD.GetExpiryUnix(char, spellId)
    if not char or not spellId then return nil end
    local t = char.ProfCooldownExpiry and char.ProfCooldownExpiry[spellId]
    if t == nil then return nil end
    if type(t) == "table" then
        return t.expiresAtUnix
    end
    if type(t) == "number" then
        return t
    end
    return nil
end

--- Alchemy transmutes share one cooldown; expiry may be stored under any transmute spell id.
function CD.GetTransmuteExpiryUnix(char)
    if not char then return nil end
    local best = nil
    for _, sid in ipairs(CD.TRANSMUTE_SPELL_IDS) do
        local exp = CD.GetExpiryUnix(char, sid)
        if exp ~= nil and (best == nil or exp > best) then
            best = exp
        end
    end
    return best
end

--- Void / Prismatic spheres share one cooldown; expiry may be stored under either spell id.
function CD.GetSphereExpiryUnix(char)
    if not char then return nil end
    local best = nil
    for _, sid in ipairs(CD.SPHERE_SPELL_IDS) do
        local exp = CD.GetExpiryUnix(char, sid)
        if exp ~= nil and (best == nil or exp > best) then
            best = exp
        end
    end
    return best
end

--- @param DS table AltArmy.DataStore
--- @param options table AltArmyTBC_Options.cooldowns shape
--- @param now number|nil unix
--- @return table[] rows { categoryKey, categoryTitle, name, realm, spellId, expiresUnix }
function CD.BuildRows(DS, options, now)
    now = now or (time and time() or 0)
    local rows = {}
    if not DS or not DS.ForEachCharacter then return rows end

    for _, catKey in ipairs(CD.CATEGORY_ORDER) do
        if CategoryListVisible(catKey, options) then
            local cat = CD.CATEGORIES[catKey]
            if cat then
                local catOpts = options.categories and options.categories[catKey] or {}
                (DS.ForEachCharacterInScope or DS.ForEachCharacter)(DS, function(realm, charName, char, linkId)
                        local displayName = (char and char.name) or charName
                        local include = false
                        if catKey == "transmute" then
                            include = CD.ResolveTransmuteSpellForCharacter(char) ~= nil
                        elseif catKey == "void_sphere" then
                            include = CD.ResolveSphereSpellForCharacter(char) ~= nil
                        elseif cat.legacyTalent then
                            include = CD.CharacterHasLegacyTalentSpell(char, cat.spellId)
                        elseif cat.mode == "single" and cat.spellId then
                            include = select(1, CD.FindRecipeProfession(char, cat.spellId))
                        end
                        if include
                            and CD.RowMeetsSpecializationGate(catKey, char, catOpts.showOnlyIfSpecialization == true)
                        then
                            local spellId = CD.ResolveEffectiveSpellId(catKey, char, options)
                            local rawExpires
                            if catKey == "transmute" then
                                rawExpires = CD.GetTransmuteExpiryUnix(char)
                            elseif catKey == "void_sphere" then
                                rawExpires = CD.GetSphereExpiryUnix(char)
                            else
                                rawExpires = CD.GetExpiryUnix(char, spellId)
                            end
                            local expires = CD.ExpiryForDisplay(rawExpires, now)
                            local gsi = type(_G.GetSpellInfo) == "function" and _G.GetSpellInfo or nil
                            local title = cat.title
                            if catKey == "transmute" then
                                title = CD.TransmuteCategoryDisplayTitle(spellId, gsi)
                            elseif catKey == "void_sphere" then
                                title = CD.SphereCategoryDisplayTitle(spellId, gsi)
                            end
                            rows[#rows + 1] = {
                                categoryKey = catKey,
                                categoryTitle = title,
                                -- The name, not the storage key (a GUID): also the stockpile mail recipient.
                                charKeyName = displayName,
                                name = displayName,
                                realm = realm,
                                linkId = linkId,
                                classFile = char and char.classFile or nil,
                                spellId = spellId,
                                expiresUnix = expires,
                                timeText = CD.FormatTimeRemaining(expires, now),
                                noReagents = cat.noReagents == true,
                            }
                        end
                end)
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.categoryTitle ~= b.categoryTitle then
            return a.categoryTitle < b.categoryTitle
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return (a.realm or "") < (b.realm or "")
    end)
    return rows
end

--- Alert evaluation: returns list of fired alerts
--- { categoryKey, categoryTitle, name, realm, classFile, spellId, kind }
--- kind = "available" only; each ready transition fires at most once until the cooldown is used again.
--- stateMutate: lastAvailAlertAt unix per row key — cleared when cooldown no longer ready
function CD.EvaluateAlerts(DS, options, now, stateMutate)
    local results = {}
    if not DS or not options then return results end
    now = now or (time and time() or 0)
    stateMutate = stateMutate or {}
    stateMutate.lastAvailAlertAt = stateMutate.lastAvailAlertAt or {}

    local rows = CD.BuildRows(DS, options, now)
    for _, row in ipairs(rows) do
        local catKey = row.categoryKey
        local catOpts = options.categories and options.categories[catKey] or {}
        local char = DS.GetCharacter and DS:GetCharacter(row.charKeyName, row.realm) or nil
        -- a linked account's character is listed, but its cooldowns never alert here
        if not row.linkId and catOpts.alertWhenAvailable ~= false
            and CD.RowMeetsSpecializationGate(catKey, char, catOpts.alertOnlyIfSpecialization == true)
        then
            local exp = row.expiresUnix
            local key = (row.realm or "") .. "\0" .. (row.name or "") .. "\0" .. catKey

            if exp ~= nil and exp <= now then
                if not stateMutate.lastAvailAlertAt[key] then
                    stateMutate.lastAvailAlertAt[key] = now
                    results[#results + 1] = {
                        categoryKey = catKey,
                        categoryTitle = row.categoryTitle,
                        name = row.name,
                        realm = row.realm,
                        classFile = row.classFile,
                        spellId = row.spellId,
                        kind = "available",
                    }
                end
            else
                stateMutate.lastAvailAlertAt[key] = nil
            end
        else
            local key = (row.realm or "") .. "\0" .. (row.name or "") .. "\0" .. catKey
            stateMutate.lastAvailAlertAt[key] = nil
        end
    end
    return results
end
