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
---@field itemId number|nil An item's use cooldown (saved under its use spell, spellId): a row for whoever holds one.
---@field unannounced boolean|nil In the game data but not announced: hidden unless Debug's Show unannounced cooldowns.

--- Longest plausible tracked profession cooldown (TBC's Shadowcloth 3d 20h, WoW Forever's Mooncloth 95h).
--- Saved values above this are shown as unscanned in the UI (see IsExpiryPlausible).
CD.MAX_PROF_COOLDOWN_SECONDS = 4 * 86400

--- The categories each client tracks (BuildRows' order): TBC's, and WoW Forever's from its game data.
CD.TBC_CATEGORY_ORDER = {
    "transmute",
    "spellcloth",
    "shadowcloth",
    "primal_mooncloth",
    "brilliant_glass",
    "void_sphere",
    "research",
    "dedicated_study",
}
CD.FOREVER_CATEGORY_ORDER = {
    "transmute",
    "mooncloth",
    "salt_shaker",
    "research",
    "dedicated_study",
    "essence_of_innovation",
}

--- Every category key on either client (saved options, the tracked spell ids).
CD.CATEGORY_ORDER = {}
do
    local seen = {}
    for _, list in ipairs({ CD.TBC_CATEGORY_ORDER, CD.FOREVER_CATEGORY_ORDER }) do
        for _, key in ipairs(list) do
            if not seen[key] then
                seen[key] = true
                CD.CATEGORY_ORDER[#CD.CATEGORY_ORDER + 1] = key
            end
        end
    end
end

local function IsForever()
    local DS = AltArmy and AltArmy.DataStore
    return DS ~= nil and DS.IsWowForever == true
end

local function ShowsUnannounced()
    local D = AltArmy and AltArmy.Debug
    return D ~= nil and D.IsShowUnannouncedCooldowns ~= nil and D.IsShowUnannouncedCooldowns() == true
end

--- The list without unannounced categories, unless Debug shows them.
local function WithoutUnannounced(keys)
    if ShowsUnannounced() then
        return keys
    end
    local out = {}
    for _, key in ipairs(keys) do
        local cat = CD.CATEGORIES[key]
        if not (cat and cat.unannounced) then
            out[#out + 1] = key
        end
    end
    return out
end

--- The categories this client lists rows and alerts for.
---@param isForever boolean
---@return string[]
function CD.GetCategoryOrder(isForever)
    if isForever then
        return WithoutUnannounced(CD.FOREVER_CATEGORY_ORDER)
    end
    return CD.TBC_CATEGORY_ORDER
end

--- The cooldowns the Cooldowns tab's settings panel lists on each client, by title A to Z: WoW Forever's
--- (the rest are TBC-specific crafts), and TBC's crafts without Forever's Study and Dedicated Study.
CD.FOREVER_OPTIONS_CATEGORY_ORDER = {
    "dedicated_study",
    "essence_of_innovation",
    "mooncloth",
    "salt_shaker",
    "research", -- Study
    "transmute",
}
CD.TBC_OPTIONS_CATEGORY_ORDER = {
    "brilliant_glass",
    "primal_mooncloth",
    "shadowcloth",
    "spellcloth",
    "transmute",
    "void_sphere",
}

--- Category keys the settings panel's Show in UI and Alert when ready dropdowns list.
---@param isForever boolean
---@return string[]
function CD.GetOptionsCategoryOrder(isForever)
    if isForever then
        return WithoutUnannounced(CD.FOREVER_OPTIONS_CATEGORY_ORDER)
    end
    return CD.TBC_OPTIONS_CATEGORY_ORDER
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

-- WoW Forever: the spells of the game data's shared "Transmute - Alchemy" cooldown (SpellCategory 310). The
-- lockout is as long as the spell cast says: 47h Arcanite and Legionite, 23h the elementals, 2h the Onyxia
-- scale, 10 min Elemental Fire. Iron to Gold and Mithril to Truesilver have their own 1h cooldown there, so
-- they are not in the group (and not tracked).
CD.FOREVER_TRANSMUTE_SPELL_IDS = {
    17187, -- Transmute: Arcanite
    1317279, -- Transmute: Legionite
    17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, -- the elemental transmutes
    22430, -- Refined Scale of Onyxia
    25146, -- Transmute: Elemental Fire
}

--- WoW Forever's Auto after the last cast: Arcanite, then Legionite.
CD.FOREVER_TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS = {
    17187, -- Transmute: Arcanite
    1317279, -- Transmute: Legionite
}

--- The transmutes that share one cooldown on this client.
function CD.GetTransmuteSpellIds()
    if IsForever() then
        return CD.FOREVER_TRANSMUTE_SPELL_IDS
    end
    return CD.TRANSMUTE_SPELL_IDS
end

function CD.GetTransmuteFallbackSpellIds()
    if IsForever() then
        return CD.FOREVER_TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS
    end
    return CD.TRANSMUTE_AUTOMATIC_FALLBACK_SPELL_IDS
end

local function KeySet(list)
    local s = {}
    for _, id in ipairs(list) do
        s[id] = true
    end
    return s
end

CD.TRANSMUTE_SPELL_SET = KeySet(CD.TRANSMUTE_SPELL_IDS)
CD.FOREVER_TRANSMUTE_SPELL_SET = KeySet(CD.FOREVER_TRANSMUTE_SPELL_IDS)
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
        spellIds = CD.TRANSMUTE_SPELL_IDS, -- TBC's; WoW Forever's are GetTransmuteSpellIds()
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
    -- WoW Forever: Comprehension (mage-only profession), shown as "Research" in the spellbook; 1h. Listed by its
    -- spell's name, Study (the key stays "research": saved settings use it).
    -- Study is the only Research recipe known so far. Revisit if more appear: if they share one
    -- cooldown this should become a "group" category like transmute.
    research = {
        key = "research",
        title = "Study",
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
    -- WoW Forever: Mooncloth keeps vanilla's long cooldown (95h in the game data; none on TBC).
    mooncloth = {
        key = "mooncloth",
        title = "Mooncloth",
        mode = "single",
        spellId = 18560,
        spellIds = { 18560 },
    },
    -- WoW Forever: the Salt Shaker item's use (71h) refines Deeprock Salt; a row for whoever holds one.
    salt_shaker = {
        key = "salt_shaker",
        title = "Salt Shaker",
        mode = "single",
        spellId = 19566, -- the item's use spell, which its cooldown is saved under
        spellIds = { 19566 },
        itemId = 15846,
    },
    -- WoW Forever: Legacy talent (Profession tree), 23h: crafts an Essence of Innovation and researches a new
    -- recipe at 300 skill. In the game data but not announced yet, so hidden unless Debug shows it.
    essence_of_innovation = {
        key = "essence_of_innovation",
        title = "Essence of Innovation",
        mode = "single",
        spellId = 1225470,
        spellIds = { 1225470 },
        legacyTalent = true,
        unannounced = true,
    },
}

-- Reagent lists for mats + tooltips come from AltArmyTBC_Data.RecipeReagents, filled when you
-- open a tradeskill or craft window (ScanRecipes / ScanCraftRecipes read the client APIs).

--- Built-in reagents for tracked recipes whose reagents the client scan can't capture. WoW Forever's
--- C_TradeSkillUI recipe scan doesn't read reagents yet, so without this its cooldowns have no mats (from
--- its game data's SpellReagents). A scanned RecipeReagents entry still wins.
CD.KNOWN_RECIPE_REAGENTS = {
    [1302508] = { { 17056, 1 } }, -- Study: 1x Light Feather
    [17187] = { { 12359, 1 }, { 12363, 1 } }, -- Transmute: Arcanite: Thorium Bar, Arcane Crystal
    [1317279] = { { 251291, 1 }, { 248819, 1 } }, -- Transmute: Legionite: Heavy Thorium Bar, Fel Crystal
    [17559] = { { 7082, 1 } }, -- Air to Fire: Essence of Air
    [17560] = { { 7078, 1 } }, -- Fire to Earth: Essence of Fire
    [17561] = { { 7076, 1 } }, -- Earth to Water: Essence of Earth
    [17562] = { { 7080, 1 } }, -- Water to Air: Essence of Water
    [17563] = { { 12808, 1 } }, -- Undeath to Water: Essence of Undeath
    [17564] = { { 7080, 1 } }, -- Water to Undeath: Essence of Water
    [17565] = { { 12803, 1 } }, -- Life to Earth: Living Essence
    [17566] = { { 7076, 1 } }, -- Earth to Life: Essence of Earth
    [22430] = { { 15410, 1 } }, -- Refined Scale of Onyxia: Scale of Onyxia
    [25146] = { { 7077, 1 } }, -- Transmute: Elemental Fire: Heart of Fire
    [18560] = { { 14256, 2 } }, -- Mooncloth: 2x Felcloth
    [19566] = { { 8150, 1 } }, -- Salt Shaker: Deeprock Salt
    -- Essence of Innovation: an essence of each element, Pristine Scale, Viridian Dye, Azerothium Bar
    [1225470] = {
        { 7076, 1 }, { 7078, 1 }, { 7080, 1 }, { 7082, 1 }, { 249429, 1 }, { 249431, 1 }, { 249726, 1 },
    },
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

--- The spell ids one client's categories persist cooldown expiry for (its transmutes, then each category's).
local function TrackedSpellIdsFor(transmuteIds, categoryOrder, out, seen)
    out = out or {}
    seen = seen or {}
    local function add(id)
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, id in ipairs(transmuteIds) do
        add(id)
    end
    for _, key in ipairs(categoryOrder) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.spellIds and key ~= "transmute" then
            for _, sid in ipairs(cat.spellIds) do
                add(sid)
            end
        end
    end
    return out, seen
end

--- Flat set of every spell id we persist cooldown expiry for, on either client.
function CD.GetAllTrackedSpellIds()
    local out, seen = TrackedSpellIdsFor(CD.TRANSMUTE_SPELL_IDS, CD.TBC_CATEGORY_ORDER)
    return TrackedSpellIdsFor(CD.FOREVER_TRANSMUTE_SPELL_IDS, CD.FOREVER_CATEGORY_ORDER, out, seen)
end

local _, TBC_TRACKED_SET = TrackedSpellIdsFor(CD.TRANSMUTE_SPELL_IDS, CD.TBC_CATEGORY_ORDER)
local _, FOREVER_TRACKED_SET = TrackedSpellIdsFor(CD.FOREVER_TRANSMUTE_SPELL_IDS, CD.FOREVER_CATEGORY_ORDER)
CD._TRACKED_SPELL_SET = TBC_TRACKED_SET
CD._FOREVER_TRACKED_SPELL_SET = FOREVER_TRACKED_SET

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
    -- The Cooldowns settings panel: its realm filter (CharacterFilter), Group characters and the folded
    -- realm/faction sections of the crafting list.
    if cd.groupByRealmFaction == nil then
        cd.groupByRealmFaction = true
    end
    if type(cd.collapsedGroups) ~= "table" then
        cd.collapsedGroups = {}
    end
    local CF = AltArmy.CharacterFilter
    if CF and CF.Ensure then
        if cd.filter == nil then
            -- The first filter starts from the Summary's, which the tab followed until it had its own.
            local summary = rawget(_G, "AltArmyTBC_SummarySettings")
            local scope = type(summary) == "table" and type(summary.filter) == "table" and summary.filter.scope
            if type(scope) == "table" then
                cd.filter = {
                    version = CF.VERSION,
                    scope = {
                        otherFaction = scope.otherFaction == true,
                        otherRealms = scope.otherRealms == true,
                        linked = scope.linked ~= false,
                    },
                    classes = {},
                }
            end
        end
        CF.Ensure(cd)
    end
    return cd
end

--- The settings panel's Show in UI and Alert when ready dropdowns: one entry per category of
--- GetOptionsCategoryOrder, and after each category with a specialization on this client a second,
--- "<title> (<specialization> only)", entry keyed "<key>:spec" (ticking one of the pair unticks the other).
CD.SPEC_NAMES = {
    transmute = "Master of Transmutation",
    spellcloth = "Spellfire Tailor",
    shadowcloth = "Shadoweave Tailor",
    primal_mooncloth = "Mooncloth Tailor",
}
CD.SPEC_SUFFIX = ":spec"
--- Said after a cooldown's name in the dropdowns' rows (not in their summaries): who has it.
CD.SETTINGS_NOTES = {
    research = "mage",
    dedicated_study = "legacy talent",
    essence_of_innovation = "legacy talent",
}

local SETTINGS_FIELDS = {
    show = { on = "showInUI", spec = "showOnlyIfSpecialization" },
    alert = { on = "alertWhenAvailable", spec = "alertOnlyIfSpecialization" },
}

--- @param isForever boolean
--- @return string[] keys, table<string, string> labels
function CD.SettingsEntries(isForever)
    local keys, labels = {}, {}
    for _, key in ipairs(CD.GetOptionsCategoryOrder(isForever)) do
        local title = CD.CATEGORIES[key] and CD.CATEGORIES[key].title or key
        local specName = CD.SPEC_NAMES[key]
        if specName and CD.CategoryHasSpecialization(key) then
            keys[#keys + 1] = key
            labels[key] = title .. " (all specs)"
            local specKey = key .. CD.SPEC_SUFFIX
            keys[#keys + 1] = specKey
            labels[specKey] = title .. " (" .. specName .. " only)"
        else
            keys[#keys + 1] = key
            local note = CD.SETTINGS_NOTES[key]
            labels[key] = note and (title .. " (" .. note .. ")") or title
        end
    end
    return keys, labels
end

--- Which entries are ticked: every key explicit (the dropdown reads a missing key as ticked).
--- @param options table AltArmyTBC_Options.cooldowns
--- @param which "show"|"alert"
function CD.SettingsMap(options, which)
    local fields = SETTINGS_FIELDS[which]
    local map = {}
    for key, cat in pairs(options and options.categories or {}) do
        local on = cat[fields.on] ~= false
        -- a saved gate counts only where the client has the specialization (never on WoW Forever)
        local spec = cat[fields.spec] == true and CD.CategoryHasSpecialization(key)
        map[key] = on and not spec
        map[key .. CD.SPEC_SUFFIX] = on and spec
    end
    return map
end

--- A dropdown entry ticked or unticked: ticking turns the category on with the entry's specialization
--- gate (so its sibling reads unticked); unticking turns the category off.
function CD.SetSettingsEntry(options, which, entryKey, checked)
    local fields = SETTINGS_FIELDS[which]
    if not fields or type(entryKey) ~= "string" then return end
    local key, isSpec = entryKey, false
    local suffixAt = #entryKey - #CD.SPEC_SUFFIX
    if suffixAt > 0 and entryKey:sub(suffixAt + 1) == CD.SPEC_SUFFIX then
        key, isSpec = entryKey:sub(1, suffixAt), true
    end
    local cat = options and options.categories and options.categories[key]
    if not cat then return end
    if checked then
        cat[fields.on] = true
        cat[fields.spec] = isSpec
    else
        cat[fields.on] = false
    end
end

--- The dropdown button's text, by the cooldowns' plain names (no "(all specs)", "(<spec> only)" or note):
--- "All", "None", "All but <name>" when one is off, else the ticked ones.
function CD.FormatSettingsSummary(keys, labels, map)
    local on, off = {}, {}
    for _, key in ipairs(keys or {}) do
        if key:sub(-#CD.SPEC_SUFFIX) ~= CD.SPEC_SUFFIX then -- one category: its entry or its spec entry
            local title = CD.CATEGORIES[key] and CD.CATEGORIES[key].title or (labels and labels[key]) or key
            if map[key] ~= false or map[key .. CD.SPEC_SUFFIX] == true then
                on[#on + 1] = title
            else
                off[#off + 1] = title
            end
        end
    end
    if #on == 0 then
        return "None"
    end
    if #off == 0 then
        return "All"
    end
    if #off == 1 then
        return "All but " .. off[1]
    end
    return table.concat(on, ", ")
end

--- Whether this client persists the spell's cooldown (its own categories' spells only).
function CD.IsTrackedSpellId(spellId)
    if not spellId then return false end
    if IsForever() then
        return FOREVER_TRACKED_SET[spellId] == true
    end
    return TBC_TRACKED_SET[spellId] == true
end

--- The item whose use cooldown a tracked spell is (an itemId category's spellId), else nil.
function CD.ItemForTrackedSpell(spellId)
    if not spellId then return nil end
    for _, key in ipairs(CD.GetCategoryOrder(IsForever())) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.itemId and cat.spellId == spellId then
            return cat.itemId
        end
    end
    return nil
end

--- {itemId, spellId} of this client's item cooldowns, for the login read.
function CD.TrackedItemCooldowns()
    local out = {}
    for _, key in ipairs(CD.GetCategoryOrder(IsForever())) do
        local cat = CD.CATEGORIES[key]
        if cat and cat.itemId and cat.spellId then
            out[#out + 1] = { itemId = cat.itemId, spellId = cat.spellId }
        end
    end
    return out
end

--- Whether the character's last bags or bank scan holds the item.
function CD.CharacterHoldsItem(char, itemId)
    if not char or type(char.Containers) ~= "table" or not itemId then return false end
    for _, bag in pairs(char.Containers) do
        if type(bag) == "table" and type(bag.items) == "table" then
            for _, slot in pairs(bag.items) do
                if type(slot) == "table" and slot.itemID == itemId then
                    return true
                end
            end
        end
    end
    return false
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

--- Known transmute if recipe id is in transmute set OR name contains "Transmute" (fallback; TBC only: WoW
--- Forever's group is its game data's, without Iron to Gold and Mithril to Truesilver).
function CD.CharacterKnowsTransmute(char, getSpellInfoFn)
    if not char or not char.Professions then return false end
    local set = IsForever() and CD.FOREVER_TRANSMUTE_SPELL_SET or CD.TRANSMUTE_SPELL_SET
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes then
            for rid in pairs(prof.Recipes) do
                if set[rid] then
                    return true
                end
            end
        end
    end
    if IsForever() then return false end
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

--- True for any alchemy transmute recipe, whether or not it shares the transmute cooldown (TBC's ID set, WoW
--- Forever's there too, or a localized name containing "transmute"): the Search tab's yield bonus label.
function CD.IsTransmuteRecipe(spellId, getSpellInfoFn)
    if not spellId then return false end
    if CD.TRANSMUTE_SPELL_SET[spellId] then return true end
    if IsForever() and CD.FOREVER_TRANSMUTE_SPELL_SET[spellId] then return true end
    local gsi = getSpellInfoFn or GetSpellInfo
    if gsi then
        local name = gsi(spellId)
        if type(name) == "string" and name:lower():find("transmute", 1, true) then
            return true
        end
    end
    return false
end

--- True if spellId is in this client's shared transmute cooldown: TBC's ID set or a localized name containing
--- "transmute"; on WoW Forever its ID set alone (its Iron to Gold and Truesilver have their own cooldowns).
function CD.IsTransmuteSpellId(spellId, getSpellInfoFn)
    if not spellId then return false end
    if IsForever() then
        return CD.FOREVER_TRANSMUTE_SPELL_SET[spellId] == true
    end
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
    if categoryKey == "transmute" then
        return CD.GetTransmuteSpellIds()
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
    -- WoW Forever: a last cast saved before its group lost Iron to Gold and Truesilver doesn't count
    if lastId and IsForever() and not CD.FOREVER_TRANSMUTE_SPELL_SET[lastId] then
        lastId = nil
    end
    if lastId and select(1, CD.FindRecipeProfession(char, lastId)) then
        return lastId
    end
    for _, sid in ipairs(CD.GetTransmuteFallbackSpellIds()) do
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
--- 2) Primal Might then Arcanite when known (WoW Forever: Arcanite then Legionite).
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

--- Alchemy transmutes share one cooldown; expiry may be stored under any of this client's transmute spell ids.
function CD.GetTransmuteExpiryUnix(char)
    if not char then return nil end
    local best = nil
    for _, sid in ipairs(CD.GetTransmuteSpellIds()) do
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
--- @param opts table|nil { all = true }: every category and character, whatever Show in UI says (the alerts)
--- @return table[] rows { categoryKey, categoryTitle, name, realm, spellId, expiresUnix }
function CD.BuildRows(DS, options, now, opts)
    now = now or (time and time() or 0)
    local all = opts and opts.all == true
    local rows = {}
    if not DS or not DS.ForEachCharacter then return rows end

    for _, catKey in ipairs(CD.GetCategoryOrder(IsForever())) do
        if all or CategoryListVisible(catKey, options) then
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
                        elseif cat.itemId then
                            include = CD.CharacterHoldsItem(char, cat.itemId)
                        elseif cat.legacyTalent then
                            include = CD.CharacterHasLegacyTalentSpell(char, cat.spellId)
                        elseif cat.mode == "single" and cat.spellId then
                            include = select(1, CD.FindRecipeProfession(char, cat.spellId))
                        end
                        if include
                            and CD.RowMeetsSpecializationGate(catKey, char,
                                not all and catOpts.showOnlyIfSpecialization == true)
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
                                faction = char and char.faction or nil, -- the realm filter and grouping
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

    -- every category, whatever Show in UI says: Alert when ready is its own setting
    local rows = CD.BuildRows(DS, options, now, { all = true })
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
