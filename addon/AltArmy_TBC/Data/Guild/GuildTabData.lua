-- AltArmy TBC — Guild tab: pure grouping / sorting / filtering / formatting helpers.
-- No frames or comm; consumes the flat member list from GuildShareData.GetGuildMembersForDisplay
-- and produces the main-grouped, sorted, filtered view the Guild tab UI renders.
-- Also provides guild-roster last-online helpers
-- (BuildRosterLastOnlineMap / FormatRosterLastOnline / GetDefaultListSort).

if not AltArmy then return end

AltArmy.GuildTabData = AltArmy.GuildTabData or {}
local GTD = AltArmy.GuildTabData

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

--- Legacy GetSpellInfo tuple (name, rank, icon). Forever has only C_Spell.GetSpellInfo;
--- without this fallback a recipe spell id got misread as an unrelated item id.
local function compatGetSpellInfo(spellID)
    if GetSpellInfo then return GetSpellInfo(spellID) end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, nil, info.iconID end
    end
end

--- Patch 12.0+ clients (Forever included) can hand GetGuildRosterInfo() names/notes
--- to addons as Secret Values that error on any operation beyond store/pass.
--- `canaccessvalue()` (existence-checked) is the guard, matching
--- DataStoreProfessions.lua's fix. Self-contained for the same reason as
--- hasItemInfoApi()/compatGetItemInfo() above.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

local GRAY = "|cff808080"
local GUILD_TAG_COLOR = "|cff8ab4f8"
local WHITE = "|cffffffff"
local SEARCH_MATCH_COLOR = "|cff00ff00"

--- Trim and lowercase a guild-tab search query; empty string when absent.
function GTD.NormalizeSearchQuery(query)
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return "" end
    return trimmed:lower()
end

--- Placeholder for the per-character recipe search field in the Guild tab (plain name, not class-colored).
function GTD.FormatRecipeSearchPlaceholder(characterName)
    local name = characterName
    if not name or name == "" then
        name = "this character"
    end
    return "Search for recipes on " .. name
end

--- Filter recipe rows by case-insensitive substring on resolved recipe name.
function GTD.FilterRecipesBySearch(recipes, query, getRecipeName)
    local q = GTD.NormalizeSearchQuery(query)
    if q == "" then
        return recipes or {}
    end
    local out = {}
    for _, recipe in ipairs(recipes or {}) do
        local name = getRecipeName and getRecipeName(recipe) or ""
        if (name or ""):lower():find(q, 1, true) then
            out[#out + 1] = recipe
        end
    end
    return out
end

--- True when both lists have the same ordered recipeIDs (content equality, not table identity).
--- Used to preserve guild recipe-list scroll across refreshes that rebuild row tables.
function GTD.AreRecipeListsEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        local ai, bi = a[i], b[i]
        if type(ai) ~= "table" or type(bi) ~= "table" then return false end
        local idA, idB = ai.recipeID, bi.recipeID
        if idA ~= idB and tonumber(idA) ~= tonumber(idB) then
            return false
        end
    end
    return true
end

--- Highlight every case-insensitive substring match in bright green; other segments use
--- `formatSegment(text, classFile)` when supplied (typically class-colored name text).
function GTD.FormatTextWithSearchHighlight(text, classFile, query, formatSegment)
    text = text or "?"
    query = GTD.NormalizeSearchQuery(query)
    if query == "" then
        if formatSegment then return formatSegment(text, classFile) end
        return text
    end

    local lowerText = text:lower()
    local parts = {}
    local pos = 1
    while pos <= #text do
        local matchStart, matchEnd = lowerText:find(query, pos, true)
        if not matchStart then
            local rest = text:sub(pos)
            if rest ~= "" then
                parts[#parts + 1] = formatSegment and formatSegment(rest, classFile) or rest
            end
            break
        end
        if matchStart > pos then
            local before = text:sub(pos, matchStart - 1)
            parts[#parts + 1] = formatSegment and formatSegment(before, classFile) or before
        end
        parts[#parts + 1] = SEARCH_MATCH_COLOR .. text:sub(matchStart, matchEnd) .. "|r"
        pos = matchEnd + 1
    end
    return table.concat(parts)
end

--- Like FormatTextWithSearchHighlight, but for text truncated with a trailing "...": matches are
--- found in `fullText` so a match cut off by the ellipsis still highlights its visible part
--- (e.g. "Durotar Supply and..." highlights "and" for query "and logistics").
function GTD.FormatTruncatedTextWithSearchHighlight(fullText, shownText, query)
    fullText = fullText or "?"
    shownText = shownText or fullText
    query = GTD.NormalizeSearchQuery(query)
    if query == "" then return shownText end

    local visibleLen = #shownText
    local ellipsis = ""
    if shownText ~= fullText and shownText:sub(-3) == "..." then
        visibleLen = visibleLen - 3
        ellipsis = "..."
    end
    if fullText:sub(1, visibleLen) ~= shownText:sub(1, visibleLen) then
        return GTD.FormatTextWithSearchHighlight(shownText, nil, query)
    end

    local lowerFull = fullText:lower()
    local parts = {}
    local pos = 1
    while pos <= visibleLen do
        local matchStart, matchEnd = lowerFull:find(query, pos, true)
        if not matchStart or matchStart > visibleLen then
            parts[#parts + 1] = fullText:sub(pos, visibleLen)
            break
        end
        if matchStart > pos then
            parts[#parts + 1] = fullText:sub(pos, matchStart - 1)
        end
        parts[#parts + 1] = SEARCH_MATCH_COLOR .. fullText:sub(matchStart, math.min(matchEnd, visibleLen)) .. "|r"
        pos = matchEnd + 1
    end
    return table.concat(parts) .. ellipsis
end

local function nameMatchesQuery(name, query)
    return query ~= "" and (name or ""):lower():find(query, 1, true) ~= nil
end

local function professionMatchesQuery(prof, query)
    if nameMatchesQuery(prof.name, query) then return true end
    if prof.spec and nameMatchesQuery(prof.spec, query) then return true end
    return false
end

local function entryMatchesQuery(entry, query)
    if nameMatchesQuery(entry.name, query) then return true end
    for _, prof in ipairs(GTD.GetPrimaryProfessions(entry)) do
        if professionMatchesQuery(prof, query) then return true end
    end
    return false
end

-- Crafting professions (recipe tabs + left side of character-row profession list).
GTD.PRIMARY_PROFESSION_KEYS = {
    alchemy = true,
    blacksmithing = true,
    enchanting = true,
    engineering = true,
    jewelcrafting = true,
    leatherworking = true,
    tailoring = true,
}

-- Gathering-slot professions recognized on character rows (right of crafting when they have no
-- recipe window). Secondary skills (cooking, first aid, fishing, riding), poisons, and lockpicking
-- are omitted entirely. Membership here is structural (these always occupy a primary-profession
-- slot); whether a key actually lands in the gathering bucket vs. gets promoted to a recipe tab is
-- decided dynamically by hasNoRecipeWindow() below, not by this table alone.
GTD.GATHERING_PROFESSION_KEYS = {
    herbalism = true,
    mining = true,
    skinning = true,
}

--- True when key has no recipe window on the currently active client, per the shared
--- AltArmy.DataStore.ProfessionHasNoRecipeWindow (DataStoreProfessions.lua) — the single source of
--- truth this module's crafting/gathering split and SummaryData.lua's missing-data nag both read,
--- so a future correction (another profession gaining/losing recipes, e.g. WoW Forever's Skinning —
--- see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Ninth") only has to happen in one place.
--- Resolved fresh on every call, not captured at file scope: this module is intentionally
--- self-contained (no AltArmy.DataStore dependency), same reason as hasItemInfoApi above. Defaults
--- to true (TBC's actual behavior for every key in GATHERING_PROFESSION_KEYS) when
--- AltArmy.DataStore isn't loaded, which is exactly this module's unit-test environment.
local function hasNoRecipeWindow(key)
    local DS = AltArmy.DataStore
    if DS and DS.ProfessionHasNoRecipeWindow then
        return DS.ProfessionHasNoRecipeWindow(key)
    end
    return true
end

local function sortProfessionsByRankThenName(list)
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name:lower() < b.name:lower()
    end)
end

--- Map a stored profession table key (or display name) to a stable crafting/gathering key.
--- Returns nil for secondary skills, poisons, lockpicking, and unknown professions.
local function resolveDisplayProfessionKey(key, prof)
    if type(key) ~= "string" or key == "" then return nil end
    if GTD.PRIMARY_PROFESSION_KEYS[key] or GTD.GATHERING_PROFESSION_KEYS[key] then
        return key
    end
    local lower = key:lower()
    if GTD.PRIMARY_PROFESSION_KEYS[lower] or GTD.GATHERING_PROFESSION_KEYS[lower] then
        return lower
    end
    local name = prof and prof.name
    if type(name) == "string" and name ~= "" then
        local nameLower = name:lower()
        if GTD.PRIMARY_PROFESSION_KEYS[nameLower] or GTD.GATHERING_PROFESSION_KEYS[nameLower] then
            return nameLower
        end
    end
    return nil
end

local function collectProfessions(entry, includeGathering)
    local crafting = {}
    local gathering = {}
    local profs = entry and entry.Professions
    if type(profs) ~= "table" then
        return crafting, gathering
    end
    for key, prof in pairs(profs) do
        if (prof.rank or 0) > 0 then
            local resolved = resolveDisplayProfessionKey(key, prof)
            if resolved then
                local row = {
                    key = resolved,
                    name = prof.name or key,
                    rank = prof.rank or 0,
                    spec = prof.spec,
                }
                if GTD.GATHERING_PROFESSION_KEYS[resolved] and hasNoRecipeWindow(resolved) then
                    if includeGathering then
                        gathering[#gathering + 1] = row
                    end
                else
                    crafting[#crafting + 1] = row
                end
            end
        end
    end
    sortProfessionsByRankThenName(crafting)
    if includeGathering then
        sortProfessionsByRankThenName(gathering)
    end
    return crafting, gathering
end

--- Character-row professions (rank > 0): crafting first, then gathering on the right.
--- Each entry is { key, name, rank, spec }. Within each group: highest rank first, then name.
function GTD.GetPrimaryProfessions(entry)
    local crafting, gathering = collectProfessions(entry, true)
    local out = {}
    for i = 1, #crafting do
        out[#out + 1] = crafting[i]
    end
    for i = 1, #gathering do
        out[#out + 1] = gathering[i]
    end
    return out
end

-- Profession spell per display key; its icon is the one the native profession window shows.
-- Static textures cover clients where the spell lookup comes back empty.
local PROFESSION_ICONS = {
    alchemy = { spellID = 2259, texture = "Interface\\Icons\\Trade_Alchemy" },
    blacksmithing = { spellID = 2018, texture = "Interface\\Icons\\Trade_BlackSmithing" },
    enchanting = { spellID = 7411, texture = "Interface\\Icons\\Trade_Engraving" },
    engineering = { spellID = 4036, texture = "Interface\\Icons\\Trade_Engineering" },
    jewelcrafting = { spellID = 25229, texture = "Interface\\Icons\\INV_Misc_Gem_02" },
    leatherworking = { spellID = 2108, texture = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
    tailoring = { spellID = 3908, texture = "Interface\\Icons\\Trade_Tailoring" },
    herbalism = { spellID = 2366, texture = "Interface\\Icons\\Trade_Herbalism" },
    mining = { spellID = 2575, texture = "Interface\\Icons\\Trade_Mining" },
    skinning = { spellID = 8613, texture = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
}

--- Icon (file id or texture path) for a crafting/gathering profession key.
function GTD.GetProfessionIcon(profKey)
    local def = profKey and PROFESSION_ICONS[profKey]
    if not def then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, icon = compatGetSpellInfo(def.spellID)
    return icon or def.texture
end

--- Crafting-only professions for recipe tabs (excludes gathering).
function GTD.GetCraftingProfessions(entry)
    local crafting = collectProfessions(entry, false)
    return crafting
end

local function findProfessionByKey(char, profKey)
    if not char or type(char.Professions) ~= "table" or not profKey then return nil end
    local prof = char.Professions[profKey]
    if prof then return prof end
    local SS = AltArmy.SearchSettings
    local label = SS and SS.PROFESSION_LABELS and SS.PROFESSION_LABELS[profKey]
    if label and char.Professions[label] then
        return char.Professions[label]
    end
    for name, p in pairs(char.Professions) do
        local key = (SS and SS.ResolveProfessionKey and SS.ResolveProfessionKey(name)) or name
        if key == profKey then return p end
    end
    -- Search's key tables omit gathering skills, but WoW Forever's Skinning has recipes; match on
    -- this module's own tab keys too (e.g. stored "Skinning" -> "skinning").
    for name, p in pairs(char.Professions) do
        if resolveDisplayProfessionKey(name, p) == profKey then return p end
    end
    return nil
end

local function buildRecipeList(prof)
    local P = AltArmy.GuildShareProtocol
    local ids = (P and P.GetPrimaryRecipeIDs and P.GetPrimaryRecipeIDs(prof)) or {}
    local out = {}
    local recipes = prof and prof.Recipes or {}
    for _, id in ipairs(ids) do
        local data = recipes[id]
        local resultItemID, name
        if type(data) == "table" then
            resultItemID = data.resultItemID
            if type(data.name) == "string" and data.name ~= "" then
                name = data.name
            end
        end
        out[#out + 1] = { recipeID = id, resultItemID = resultItemID, name = name }
    end
    return out
end

--- Resolve full character data for recipe lookup (DataStore for local, GuildShareData otherwise).
function GTD.GetStoredCharacter(entry)
    if not entry or not entry.name then return nil end
    if entry.source == "local" then
        local DS = AltArmy.DataStore
        -- By name: DataStore keys characters by GUID.
        if DS and DS.GetCharacter then
            return DS:GetCharacter(entry.name, entry.realm)
        end
        if DS and DS.GetCharacters then
            local chars = DS:GetCharacters(entry.realm)
            return chars and chars[entry.name] or nil
        end
        return nil
    end
    local GSD = AltArmy.GuildShareData
    return GSD and GSD.GetCharacter and GSD.GetCharacter(entry.guid or entry.name, entry.realm) or nil
end

--- Enrich a guild-tab recipe row with recipe data skill metadata (mutates entry).
function GTD.EnrichRecipeEntry(recipe, professionName, skillRank)
    local entry = {
        recipeID = recipe and recipe.recipeID,
        resultItemID = recipe and recipe.resultItemID,
        professionName = professionName,
        skillRank = skillRank or 0,
    }
    local RI = AltArmy and AltArmy.RecipeInfo
    if RI and RI.EnrichEntry then
        RI.EnrichEntry(entry)
    end
    return entry
end

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Prefer icons that do not require the item cache (GetItemIcon / GetItemInfoInstant).
local function resolveItemIcon(itemID)
    if not itemID then return nil end
    if GetItemIcon then
        local icon = GetItemIcon(itemID)
        if icon then return icon end
    end
    if GetItemInfoInstant then
        local _, _, _, _, icon = GetItemInfoInstant(itemID)
        if icon then return icon end
    end
    if hasItemInfoApi() then
        local _, _, _, _, _, _, _, _, _, icon = compatGetItemInfo(itemID)
        if icon then return icon end
    end
    return nil
end

--- Resolve recipe display name and icon for guild-tab rows.
--- knownName (optional) is the name captured at scan time and wins over id-based lookups.
--- Returns recipeName, iconPath, pendingItemID (item id to watch via GET_ITEM_INFO_RECEIVED, or nil).
function GTD.ResolveRecipeDisplay(recipeID, resultItemID, knownName)
    local recipeName = (type(knownName) == "string" and knownName ~= "") and knownName or nil
    local iconPath = QUESTION_MARK_ICON
    local pendingItemID = nil

    if not recipeName and recipeID then
        recipeName = compatGetSpellInfo(recipeID)
    end
    -- The crafted item is a reliable stand-in; recipeID-as-item is a last-resort guess.
    if not recipeName and resultItemID and hasItemInfoApi() then
        recipeName = compatGetItemInfo(resultItemID)
    end
    if not recipeName and recipeID and hasItemInfoApi() then
        recipeName = compatGetItemInfo(recipeID)
    end
    recipeName = recipeName or ("Recipe " .. tostring(recipeID or "?"))

    if resultItemID then
        local icon = resolveItemIcon(resultItemID)
        if icon then
            iconPath = icon
        else
            pendingItemID = resultItemID
        end
    elseif recipeID then
        -- Spell first: recipe ids are normally spell ids; reading one as an item id shows an unrelated icon.
        local _, _, spellIcon = compatGetSpellInfo(recipeID)
        local icon = spellIcon or resolveItemIcon(recipeID)
        if icon then
            iconPath = icon
        else
            pendingItemID = recipeID
        end
    end

    return recipeName, iconPath, pendingItemID
end

--- Skill column text for a recipe row (same formatting as Search recipe results).
function GTD.FormatRecipeSkillCell(recipe, professionName, skillRank)
    local entry = GTD.EnrichRecipeEntry(recipe, professionName, skillRank)
    local RI = AltArmy and AltArmy.RecipeInfo
    if RI and RI.FormatSkillCell then
        return RI.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
    end
    return tostring(entry.skillRank or 0)
end

local DIFFICULTY_SORT_ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }

local function cmpValues(a, b)
    if a < b then return -1 end
    if a > b then return 1 end
    return 0
end

local function recipeNameLower(recipe, getRecipeName)
    if getRecipeName then
        return (getRecipeName(recipe) or ""):lower()
    end
    return ""
end

--- Default recipe list sort when opening a character's recipes.
--- With recipe data: required skill descending (highest first). Otherwise: name ascending.
function GTD.GetDefaultRecipeSort(recipeDataAvailable)
    if recipeDataAvailable then
        return "skill", false
    end
    return "recipe", true
end

--- Default guild list sort.
--- When roster last-online can be looked up (player is in that guild): online ascending
--- (most recently online first). Otherwise: name ascending.
function GTD.GetDefaultListSort(canLookupOnline)
    if canLookupOnline then
        return "online", true
    end
    return "name", true
end

--- Sort recipe rows for the guild recipe list (`sortKey`: "recipe" or "skill").
function GTD.SortRecipes(recipes, sortKey, ascending, opts)
    local out = {}
    for i = 1, #(recipes or {}) do
        out[i] = recipes[i]
    end
    if #out < 2 then
        return out
    end
    opts = opts or {}
    local profName = opts.professionName
    local skillRank = opts.skillRank or 0
    local getRecipeName = opts.getRecipeName
    local key = sortKey == "skill" and "skill" or "recipe"

    table.sort(out, function(a, b)
        local cmp = 0
        if key == "skill" then
            local entryA = GTD.EnrichRecipeEntry(a, profName, skillRank)
            local entryB = GTD.EnrichRecipeEntry(b, profName, skillRank)
            -- Unknown required skill sorts as 0 (not as "very high").
            local reqA = entryA.recipeSkillRequired or 0
            local reqB = entryB.recipeSkillRequired or 0
            cmp = cmpValues(reqA, reqB)
            if cmp == 0 then
                local ordA = DIFFICULTY_SORT_ORDER[entryA.difficulty] or 99
                local ordB = DIFFICULTY_SORT_ORDER[entryB.difficulty] or 99
                cmp = cmpValues(ordA, ordB)
            end
        end
        if cmp == 0 then
            cmp = cmpValues(recipeNameLower(a, getRecipeName), recipeNameLower(b, getRecipeName))
        end
        if cmp == 0 then
            cmp = cmpValues(a.recipeID or 0, b.recipeID or 0)
        end
        if not ascending then
            cmp = -cmp
        end
        return cmp < 0
    end)
    return out
end

--- Primary (non-alias) recipes for one profession, sorted by recipe id.
function GTD.GetProfessionRecipes(entry, profKey)
    if not entry or not profKey or profKey == "" then return {} end
    local char = GTD.GetStoredCharacter(entry)
    local prof
    if char then
        prof = findProfessionByKey(char, profKey)
    end
    if not prof and entry.Professions then
        prof = entry.Professions[profKey]
    end
    if not prof then return {} end
    return buildRecipeList(prof)
end

local function formatNamePart(entry, formatName)
    local name = entry.name or "?"
    if formatName then
        return formatName(name, entry.classFile)
    end
    local CC = AltArmy.ClassColor
    return (CC and CC.formatName and CC.formatName(name, entry.classFile)) or name
end

--- Class-colored character name for detail headers (no level suffix).
function GTD.FormatCharacterTitle(entry, formatName)
    return formatNamePart(entry, formatName)
end

--- Empty-state copy when recipe tabs are unavailable.
--- No primary/gathering professions (secondary-only counts as none) → "No known professions for {name}".
--- Has gathering (or other non-crafting primary) but no crafting → "{name} has no professions with recipes".
function GTD.FormatNoProfessionsMessage(entry, formatName)
    local name = formatNamePart(entry, formatName)
    if #GTD.GetPrimaryProfessions(entry) > 0 then
        return name .. " has no professions with recipes"
    end
    return "No known professions for " .. name
end

--- Empty-state copy when a profession is known but its recipe list is empty.
--- Second line (gray) explains recipes arrive when they open that profession screen.
function GTD.FormatNoProfessionRecipesMessage(entry, formatName, professionName)
    local name = formatNamePart(entry, formatName)
    local profession = (professionName and professionName ~= "") and professionName or "profession"
    return "No known " .. profession .. " recipes for " .. name
        .. "\n\n" .. GRAY .. "Data will be shared when they open their " .. profession .. " screen|r"
end

--- Sorted unique guild names from characters on `realm` that have a guild set.
function GTD.CollectGuildsOnRealm(realm)
    local seen = {}
    local out = {}
    if not realm or realm == "" then return out end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacters then return out end
    for _, charData in pairs(DS:GetCharacters(realm) or {}) do
        local guild = charData and charData.guildName
        if guild and guild ~= "" and not seen[guild] then
            seen[guild] = true
            out[#out + 1] = guild
        end
    end
    table.sort(out, function(a, b)
        return a:lower() < b:lower()
    end)
    return out
end

--- Sorted unique guild names from all account characters that have a guild set.
function GTD.CollectAccountGuilds()
    local seen = {}
    local out = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter then return out end
    DS:ForEachCharacter(function(_, _, charData)
        local guild = charData and charData.guildName
        if guild and guild ~= "" and not seen[guild] then
            seen[guild] = true
            out[#out + 1] = guild
        end
    end)
    table.sort(out, function(a, b)
        return a:lower() < b:lower()
    end)
    return out
end

--- True when any stored character on `realm` has a guild membership.
function GTD.HasGuildedCharactersOnRealm(realm)
    return #(GTD.CollectGuildsOnRealm(realm)) > 0
end

--- Guild tab button visibility: feature flag on and at least one guilded character
--- on the current realm.
function GTD.ShouldShowGuildTab(guildShareFlagOn, hasGuildedCharacters)
    if not guildShareFlagOn then return false end
    if not hasGuildedCharacters then return false end
    return true
end

--- Live evaluation using current addon state (current realm only).
function GTD.CanShowGuildTab()
    local D = AltArmy and AltArmy.Debug
    local flagOn = D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() or false
    local realm
    local DS = AltArmy and AltArmy.DataStore
    if DS and DS.GetCurrentPlayerRealm then
        realm = DS:GetCurrentPlayerRealm()
    end
    if not realm or realm == "" then
        realm = (GetRealmName and GetRealmName()) or ""
    end
    return GTD.ShouldShowGuildTab(flagOn, GTD.HasGuildedCharactersOnRealm(realm))
end

--- When the account has exactly one guild, return it for automatic browse selection.
function GTD.GetAutoBrowseGuild(guilds)
    if type(guilds) ~= "table" or #guilds ~= 1 then return nil end
    return guilds[1]
end

--- Group a flat member list by main character, producing sorted groups.
--- Each group: { main, preferredName, characterCount, classFile, members = { sorted } }.
function GTD.GroupMembersByMain(members)
    local groups = {}
    local order = {}
    for _, m in ipairs(members or {}) do
        local mainKey = m.main or m.name
        local g = groups[mainKey]
        if not g then
            g = { main = mainKey, members = {} }
            groups[mainKey] = g
            order[#order + 1] = g
        end
        g.members[#g.members + 1] = m
    end

    for _, g in ipairs(order) do
        table.sort(g.members, function(a, b)
            local la, lb = a.level or 0, b.level or 0
            if la ~= lb then return la > lb end
            return (a.name or "") < (b.name or "")
        end)
        for _, m in ipairs(g.members) do
            if m.isMain or m.name == g.main then
                g.preferredName = m.displayName or m.main
                g.classFile = m.classFile
                break
            end
        end
        g.preferredName = g.preferredName or g.main
        g.characterCount = #g.members
    end

    table.sort(order, function(a, b)
        return (a.preferredName or ""):lower() < (b.preferredName or ""):lower()
    end)
    return order
end

-- Age at which received guildmate data is flagged as outdated in the Guild tab (not purged).
GTD.OLD_DATA_AGE_SEC = 60 * 60 * 24 * 30

--- True when a received (non-local) member's data is at least OLD_DATA_AGE_SEC old.
function GTD.IsMemberDataOld(member, nowTs, maxAgeSec)
    if not member or member.source == "local" then return false end
    local receivedAt = member.receivedAt
    if type(receivedAt) ~= "number" then return false end
    nowTs = nowTs or ((time and time()) or 0)
    maxAgeSec = maxAgeSec or GTD.OLD_DATA_AGE_SEC
    return (nowTs - receivedAt) >= maxAgeSec
end

--- True when any member in the group has outdated received data.
function GTD.GroupHasOldData(group, nowTs, maxAgeSec)
    if not group then return false end
    for _, m in ipairs(group.members or {}) do
        if GTD.IsMemberDataOld(m, nowTs, maxAgeSec) then
            return true
        end
    end
    return false
end

--- Oldest receivedAt among non-local members, or nil.
function GTD.GetGroupOldestReceivedAt(group)
    if not group then return nil end
    local oldest
    for _, m in ipairs(group.members or {}) do
        if m and m.source ~= "local" and type(m.receivedAt) == "number" then
            if not oldest or m.receivedAt < oldest then
                oldest = m.receivedAt
            end
        end
    end
    return oldest
end

--- Whole days since receivedAt (floored). Nil when receivedAt is missing.
function GTD.GetDataAgeDays(receivedAt, nowTs)
    if type(receivedAt) ~= "number" then return nil end
    nowTs = nowTs or ((time and time()) or 0)
    return math.max(0, math.floor((nowTs - receivedAt) / (60 * 60 * 24)))
end

--- Whole days remaining until auto-delete (ceiled). 0 when already due.
function GTD.GetDaysUntilAutoDelete(receivedAt, nowTs, maxAgeSec)
    if type(receivedAt) ~= "number" then return nil end
    nowTs = nowTs or ((time and time()) or 0)
    if not maxAgeSec then
        local GSS = AltArmy.GuildShareSettings
        maxAgeSec = (GSS and GSS.AUTO_DELETE_MAX_AGE_SEC) or (60 * 60 * 24 * 180)
    end
    local remaining = (receivedAt + maxAgeSec) - nowTs
    if remaining <= 0 then return 0 end
    return math.ceil(remaining / (60 * 60 * 24))
end

--- Tooltip body for the Guild tab old-data warning icon.
function GTD.GetOldDataTooltipText(ageDays)
    return string.format(
        "This data is %d days old. The guildmate has not shared an update with you recently.",
        tonumber(ageDays) or 0)
end

--- Gray follow-up line when auto-delete is enabled.
function GTD.GetOldDataAutoDeleteTooltipText(daysUntilDelete)
    return string.format(
        "This data will be deleted in %d days, unless new data is received by then.",
        tonumber(daysUntilDelete) or 0)
end

--- True when this member comes from a local manual grouping (not addon-shared).
function GTD.IsManualMember(member)
    return member ~= nil and member.source == "manual"
end

--- True when any member in the group is a manual stub.
function GTD.GroupHasManualData(group)
    if not group then return false end
    for _, m in ipairs(group.members or {}) do
        if GTD.IsManualMember(m) then
            return true
        end
    end
    return false
end

--- True when the group has members and every member is a manual stub (no shared data).
function GTD.GroupIsEntirelyManual(group)
    if not group then return false end
    local members = group.members or {}
    if #members == 0 then return false end
    for _, m in ipairs(members) do
        if not GTD.IsManualMember(m) then
            return false
        end
    end
    return true
end

--- Tooltip body for the Guild tab manual-grouping warning icon on a group row.
function GTD.GetManualDataTooltipText(_member)
    return "This player does not use Alt Army. This group was entered manually and may be inaccurate."
end

--- Tooltip body for the Guild tab manual-grouping warning icon on a character row.
function GTD.GetManualCharacterTooltipText(_member)
    return "This character was entered manually and may be inaccurate"
end

--- Brief explanation shown at the top of the "New manual group" wizard.
function GTD.GetManualGroupCreateDescription()
    return "Manual groups let you link guildmates who don't use Alt Army as main and alts."
end

--- Lowercase short-name set of every character already present in a flat member list.
function GTD.CollectOccupiedNames(members)
    local set = {}
    for _, m in ipairs(members or {}) do
        local key = GTD.NormalizeRosterName(m and m.name)
        if key and key ~= "" then
            set[key] = true
        end
    end
    return set
end

--- Sorted roster display names from a BuildRosterInfoMap result.
function GTD.RosterDisplayNames(rosterInfoMap)
    local out = {}
    for _, info in pairs(rosterInfoMap or {}) do
        if info and type(info.name) == "string" and info.name ~= "" then
            out[#out + 1] = info.name
        end
    end
    table.sort(out, function(a, b)
        return a:lower() < b:lower()
    end)
    return out
end

--- Case-insensitive match of typed text to a roster display name.
--- `rosterInfoMap` is a BuildRosterInfoMap result (normalized key → { name, ... }).
--- Returns the proper-cased roster name, or nil when unknown.
function GTD.ResolveRosterName(text, rosterInfoMap)
    if type(text) ~= "string" or text == "" then return nil end
    if type(rosterInfoMap) ~= "table" then return nil end
    local key = GTD.NormalizeRosterName(text)
    if not key then return nil end
    local info = rosterInfoMap[key]
    if info and type(info.name) == "string" and info.name ~= "" then
        return info.name
    end
    return nil
end

--- Filter roster display names for an "add character" autocomplete.
--- Matches against name (and `note` when `opts.rosterInfo` is provided).
--- Names present in `occupiedNames` (lowercase set of truthy values / reason strings)
--- are included after selectable matches, sorted A-Z within each group.
--- Optional `opts.maxResults` trims the combined list.
function GTD.FilterRosterNamesForAdd(rosterNames, query, occupiedNames, opts)
    opts = opts or {}
    local q = GTD.NormalizeSearchQuery(query)
    local occupied = occupiedNames or {}
    local rosterInfo = opts.rosterInfo
    local maxResults = opts.maxResults
    local available = {}
    local blocked = {}
    for _, name in ipairs(rosterNames or {}) do
        if type(name) == "string" and name ~= "" then
            local key = GTD.NormalizeRosterName(name)
            if key then
                local matched = q == "" or name:lower():find(q, 1, true)
                if not matched and rosterInfo then
                    local info = rosterInfo[key]
                    local note = info and info.note
                    if type(note) == "string" and note ~= "" and note:lower():find(q, 1, true) then
                        matched = true
                    end
                end
                if matched then
                    if occupied[key] then
                        blocked[#blocked + 1] = name
                    else
                        available[#available + 1] = name
                    end
                end
            end
        end
    end
    table.sort(available, function(a, b)
        return a:lower() < b:lower()
    end)
    table.sort(blocked, function(a, b)
        return a:lower() < b:lower()
    end)
    local out = {}
    for _, name in ipairs(available) do
        out[#out + 1] = name
    end
    for _, name in ipairs(blocked) do
        out[#out + 1] = name
    end
    if maxResults and #out > maxResults then
        local trimmed = {}
        for i = 1, maxResults do
            trimmed[i] = out[i]
        end
        return trimmed
    end
    return out
end

--- User-facing occupied entry for a roster name, or nil when selectable.
--- Values may be reason strings, `{ groupName, classFile }` tables, or other truthy markers.
function GTD.RosterAddDisabledReason(occupiedNames, name)
    if type(name) ~= "string" or name == "" then return nil end
    local key = GTD.NormalizeRosterName(name)
    if not key then return nil end
    local value = occupiedNames and occupiedNames[key]
    if not value then return nil end
    return value
end

--- Format an occupied-entry value for the add-character suggest list.
--- Group entries render as "Already in group {class-colored name}" with the prefix in
--- gray; plain strings / other truthy values are fully gray.
function GTD.FormatRosterAddDisabledReason(value, formatNameFn)
    if value == nil or value == false then return "" end
    if type(value) == "table" then
        local groupName = value.groupName
        if type(groupName) ~= "string" or groupName == "" then
            groupName = "?"
        end
        local coloredName
        if formatNameFn then
            coloredName = formatNameFn(groupName, value.classFile) or groupName
        else
            local CC = AltArmy.ClassColor
            coloredName = (CC and CC.formatName and CC.formatName(groupName, value.classFile))
                or groupName
        end
        return GRAY .. "Already in group |r" .. coloredName
    end
    local text
    if type(value) == "string" and value ~= "" then
        if value == "your character" then
            text = "Your character"
        else
            text = value
        end
    else
        text = "Already in a group"
    end
    return GRAY .. text .. "|r"
end

--- Occupied map for add-character autocomplete: normalized name → `{ groupName, classFile }`.
--- `groupName` is ResolveGroupDisplayName (override → preferred → main). Optional `getOverride`.
function GTD.BuildOccupiedGroupReasons(members, getOverride)
    local occupied = {}
    for _, g in ipairs(GTD.GroupMembersByMain(members) or {}) do
        local payload = {
            groupName = GTD.ResolveGroupDisplayName(g, getOverride),
            classFile = g.classFile,
        }
        for _, m in ipairs(g.members or {}) do
            local key = GTD.NormalizeRosterName(m and m.name)
            -- A character read by link that nothing grouped sits in an automatic group of its own: free
            -- to add to another group, which then replaces the automatic one.
            if key and not m.autoGroup then
                occupied[key] = payload
            end
        end
    end
    return occupied
end

--- Manual-only alt members of a group (excludes the main stub and addon/local members).
function GTD.GetManualAlts(group)
    local out = {}
    if not group then return out end
    local mainKey = GTD.NormalizeRosterName(group.main)
    for _, m in ipairs(group.members or {}) do
        if GTD.IsManualMember(m) then
            local key = GTD.NormalizeRosterName(m.name)
            if key and key ~= mainKey then
                out[#out + 1] = m
            end
        end
    end
    return out
end

--- Members of a group that still have a local manual mapping disagreeing with addon data.
--- `gmg` defaults to AltArmy.GuildManualGroups (injectable for tests).
--- Returns `{ name, realm, manualMain, addonMain, origin }`.
function GTD.FindManualAddonDisagreements(group, gmg)
    local out = {}
    gmg = gmg or AltArmy.GuildManualGroups
    if not group or not gmg or not gmg.GetMapping then return out end
    for _, m in ipairs(group.members or {}) do
        if m and m.name and m.source and m.source ~= "manual" and m.source ~= "local" and not m.linkOnly then
            local mapping = gmg.GetMapping(m.name, m.realm)
            if mapping and mapping.main and mapping.main ~= (m.main or m.name) then
                out[#out + 1] = {
                    name = m.name,
                    realm = m.realm,
                    manualMain = mapping.main,
                    addonMain = m.main or m.name,
                    origin = mapping.origin,
                }
            end
        end
    end
    return out
end

--- User-facing explanation of a manual vs addon main conflict.
function GTD.FormatManualDisagreementText(conflict)
    if not conflict then return "" end
    return string.format(
        "You grouped %s under %s, but %s's addon reports %s as their main. Addon data is being used.",
        conflict.name or "?",
        conflict.manualMain or "?",
        conflict.name or "?",
        conflict.addonMain or "?")
end

--- Build a staged edit proposal from an existing guild group for the full-screen editor.
--- `gmg` defaults to AltArmy.GuildManualGroups (injectable for tests).
--- Returns `{ main, members, order, pinned, overrideName, edit = true,
--- mainReasonKind, mainDeclared }` or nil.
--- `mainReasonKind` is the inclusion reason for the grouping main
--- ("shared"|"manual"|"main"); `mainDeclared` is true only when that character
--- explicitly set themselves as main and shared via Alt Army.
--- Each non-main member has: name, removable, reasonKind ("shared"|"manual"|"note"|"conflict"),
--- and optionally conflictManualMain when reasonKind is "conflict".
function GTD.BuildGroupEditProposal(group, gmg)
    if not group then return nil end
    gmg = gmg or AltArmy.GuildManualGroups
    local mainKey = GTD.NormalizeRosterName(group.main)
    local conflictByKey = {}
    for _, c in ipairs(GTD.FindManualAddonDisagreements(group, gmg)) do
        local key = GTD.NormalizeRosterName(c.name)
        if key then
            conflictByKey[key] = c
        end
    end

    local order = {}
    local members = {}
    local mainMember
    -- Main first in display order.
    if type(group.main) == "string" and group.main ~= "" then
        order[#order + 1] = group.main
    end
    for _, m in ipairs(group.members or {}) do
        if m and m.name then
            local key = GTD.NormalizeRosterName(m.name)
            if key and key == mainKey then
                mainMember = m
            elseif key then
                order[#order + 1] = m.name
                local conflict = conflictByKey[key]
                local reasonKind
                local conflictManualMain
                local removable
                if conflict then
                    reasonKind = "conflict"
                    removable = true
                    conflictManualMain = conflict.manualMain
                elseif m.autoGroup then
                    reasonKind = "auto"
                    removable = false
                elseif GTD.IsManualMember(m) or m.linkOnly then
                    -- A character read by link sits in this group only by a mapping (note or manual).
                    removable = true
                    local origin = m.origin
                    if (not origin or origin == "") and gmg and gmg.GetMapping then
                        local mapping = gmg.GetMapping(m.name, m.realm)
                        origin = mapping and mapping.origin
                    end
                    if origin == "note" then
                        reasonKind = "note"
                    else
                        reasonKind = "manual"
                    end
                else
                    reasonKind = "shared"
                    removable = false
                end
                local entry = {
                    name = m.name,
                    removable = removable,
                    reasonKind = reasonKind,
                    addedManually = removable and true or false,
                    origin = (reasonKind == "note" and "note")
                        or (reasonKind == "manual" and "user")
                        or nil,
                }
                if conflictManualMain then
                    entry.conflictManualMain = conflictManualMain
                end
                members[#members + 1] = entry
            end
        end
    end

    local originalRemovable = {}
    for _, entry in ipairs(members) do
        if entry.removable then
            originalRemovable[#originalRemovable + 1] = entry.name
        end
    end

    local mainOrigin = mainMember and mainMember.origin
    if (not mainOrigin or mainOrigin == "") and gmg and gmg.GetMapping
        and type(group.main) == "string" and group.main ~= "" then
        local mapping = gmg.GetMapping(group.main, mainMember and mainMember.realm)
        mainOrigin = mapping and mapping.origin
    end
    local mainFromShared = mainMember ~= nil and not GTD.IsManualMember(mainMember)
        and not mainMember.linkOnly
    local mainReasonKind = GTD.ClassifyNotesWizardInclusionReason({
        isMain = true,
        mainFromShared = mainFromShared,
        origin = mainOrigin,
        isManualMember = GTD.IsManualMember(mainMember) or (mainMember ~= nil and mainMember.linkOnly == true),
        autoGroup = mainMember ~= nil and mainMember.autoGroup == true,
    })

    return {
        main = group.main,
        members = members,
        order = order,
        pinned = group.pinned and true or false,
        overrideName = group.overrideName,
        edit = true,
        mainReasonKind = mainReasonKind,
        mainDeclared = GTD.IsExplicitMain(mainMember) and true or false,
        mainFromShared = mainFromShared and true or false,
        -- Snapshot of removable names at open-time so Diff does not need live GMG.
        originalRemovable = originalRemovable,
    }
end

--- Diff a staged edit proposal against the original group.
--- Returns `{ adds = {names}, removes = {names}, pinned?, overrideName? }`.
--- `pinned` / `overrideName` are set only when they differ from the original
--- (overrideName is "" when clearing a previous override).
--- `adds`/`removes` cover removable members only (manual alts + conflict mappings).
function GTD.DiffGroupEditProposal(proposal, group)
    local diff = { adds = {}, removes = {} }
    if type(proposal) ~= "table" or type(group) ~= "table" then
        return diff
    end

    local mainKey = GTD.NormalizeRosterName(group.main)

    -- Prefer the snapshot taken at Build time (covers conflicts without live GMG).
    local originalRemovable = {}
    if type(proposal.originalRemovable) == "table" then
        for _, name in ipairs(proposal.originalRemovable) do
            local key = GTD.NormalizeRosterName(name)
            if key then
                originalRemovable[key] = name
            end
        end
    else
        for _, m in ipairs(GTD.GetManualAlts(group)) do
            local key = GTD.NormalizeRosterName(m.name)
            if key then
                originalRemovable[key] = m.name
            end
        end
    end

    local originalMemberKeys = {}
    for _, m in ipairs(group.members or {}) do
        local key = GTD.NormalizeRosterName(m and m.name)
        if key then
            originalMemberKeys[key] = true
        end
    end

    local stagedRemovable = {}
    for _, m in ipairs(proposal.members or {}) do
        if m and m.name then
            local key = GTD.NormalizeRosterName(m.name)
            if key and key ~= mainKey then
                local isRemovable = m.removable or m.addedManually
                    or m.reasonKind == "manual" or m.reasonKind == "note"
                    or m.reasonKind == "conflict"
                if isRemovable then
                    stagedRemovable[key] = m.name
                end
            end
        end
    end
    for _, name in ipairs(proposal.order or {}) do
        local key = GTD.NormalizeRosterName(name)
        if key and key ~= mainKey and not originalMemberKeys[key] then
            stagedRemovable[key] = name
        end
    end

    for key, name in pairs(stagedRemovable) do
        if not originalRemovable[key] then
            diff.adds[#diff.adds + 1] = name
        end
    end
    for key, name in pairs(originalRemovable) do
        if not stagedRemovable[key] then
            diff.removes[#diff.removes + 1] = name
        end
    end

    local origPinned = group.pinned and true or false
    local stagedPinned = proposal.pinned and true or false
    if stagedPinned ~= origPinned then
        diff.pinned = stagedPinned
    end

    local origOverride = group.overrideName
    if origOverride == "" then origOverride = nil end
    local stagedOverride = proposal.overrideName
    if stagedOverride == "" then stagedOverride = nil end
    if origOverride ~= stagedOverride then
        if stagedOverride == nil then
            diff.overrideName = ""
        else
            diff.overrideName = stagedOverride
        end
    end

    return diff
end

--- True when a staged edit proposal differs from the original group.
function GTD.GroupEditProposalHasChanges(proposal, group)
    local diff = GTD.DiffGroupEditProposal(proposal, group)
    if not diff then return false end
    if #(diff.adds or {}) > 0 then return true end
    if #(diff.removes or {}) > 0 then return true end
    if diff.pinned ~= nil then return true end
    if diff.overrideName ~= nil then return true end
    return false
end

--- True when this character is the player's explicitly marked main (not a deduced grouping main).
function GTD.IsExplicitMain(member)
    return member ~= nil and member.isMain == true and member.mainDeclared == true
end

--- Tooltip for the main-character star.
--- `isOwn == false` → "their"; otherwise "your".
--- @param name string|nil
--- @param classFile string|nil
--- @param isOwn boolean|nil
--- @return string
function GTD.FormatMainStarTooltip(name, classFile, isOwn)
    local CC = AltArmy.ClassColor
    local coloredName = CC and CC.formatName and CC.formatName(name, classFile)
        or ("|cffffffff" .. (name or "?") .. "|r")
    if isOwn == false then
        return coloredName .. " is their main character"
    end
    return coloredName .. " is your main character"
end

--- Present main-star tooltip. opts: name, classFile, isOwn, showConfigureHint
--- @return boolean true if tooltip was shown
function GTD.PresentMainStarTooltip(owner, anchor, opts)
    if not owner or not GameTooltip then return false end
    opts = opts or {}
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(
        GTD.FormatMainStarTooltip(opts.name, opts.classFile, opts.isOwn),
        1, 1, 1, true
    )
    if opts.showConfigureHint then
        GameTooltip:AddLine("Click to configure", 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
    return true
end

--- Display label for a main group: override → preferredName → main.
--- Optional `getOverride(group)` supplies an override when `group.overrideName` is unset.
function GTD.ResolveGroupDisplayName(group, getOverride)
    if not group then return "?" end
    local override = group.overrideName
    if (not override or override == "") and getOverride then
        override = getOverride(group)
    end
    if type(override) == "string" and override ~= "" then
        return override
    end
    return group.preferredName or group.main or "?"
end

--- True when `group.main` is the player's configured main.
function GTD.IsOwnGroup(group, ownMain)
    return group ~= nil and type(ownMain) == "string" and ownMain ~= "" and group.main == ownMain
end

--- The groups the Guild tab lists: without those made only of characters read by profession link that
--- nothing groups (`autoGroup`). Their recipes still reach search; only shared Alt Army groups and those
--- from manual or note mappings are listed.
function GTD.ListedGroups(groups)
    local out = {}
    for _, g in ipairs(groups or {}) do
        local listed = false
        for _, m in ipairs(g.members or {}) do
            if not m.autoGroup then
                listed = true
                break
            end
        end
        if listed then out[#out + 1] = g end
    end
    return out
end

--- Filter groups by a search query (empty/nil returns all groups unchanged).
--- Omits groups with no match on override/preferred/main name, any character name, or profession.
--- When preferred, override, or main name matches, all characters in the group are shown; otherwise only
--- characters matching on name or profession are included.
function GTD.FilterGroups(groups, query)
    local q = GTD.NormalizeSearchQuery(query)
    if q == "" then return groups end
    local out = {}
    for _, g in ipairs(groups or {}) do
        local preferredMatch = nameMatchesQuery(g.preferredName, q)
        local overrideMatch = nameMatchesQuery(g.overrideName, q)
        local mainMatch = nameMatchesQuery(g.main, q)
        local groupNameMatch = preferredMatch or overrideMatch or mainMatch
        local matchedMembers = {}
        if groupNameMatch then
            for _, m in ipairs(g.members or {}) do
                matchedMembers[#matchedMembers + 1] = m
            end
        else
            for _, m in ipairs(g.members or {}) do
                if entryMatchesQuery(m, q) then
                    matchedMembers[#matchedMembers + 1] = m
                end
            end
        end
        if groupNameMatch or #matchedMembers > 0 then
            out[#out + 1] = {
                main = g.main,
                preferredName = g.preferredName,
                overrideName = g.overrideName,
                pinned = g.pinned,
                prefsRealm = g.prefsRealm,
                classFile = g.classFile,
                members = matchedMembers,
                characterCount = #matchedMembers,
            }
        end
    end
    return out
end

--- Preferred/override name for a main group row (class-colored when formatName is supplied).
--- Optional `query` highlights matching substrings in the display name.
--- Main-row display name (class-colored). When `isOwn`, appends gray " (you)".
function GTD.FormatMainRowName(group, formatName, query, isOwn)
    local name = GTD.ResolveGroupDisplayName(group)
    local text
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        text = GTD.FormatTextWithSearchHighlight(name, group.classFile, query, formatName)
    elseif formatName then
        text = formatName(name, group.classFile)
    else
        text = name
    end
    if isOwn then
        text = text .. " " .. GRAY .. "(you)|r"
    end
    return text
end

--- Character-count suffix for a main group row (plain text).
function GTD.FormatMainRowCount(group)
    local count = group.characterCount or #(group.members or {})
    local noun = count == 1 and "character" or "characters"
    return count .. " " .. noun
end

--- Main-row label: "{preferred name} -- {N} character(s)". When `formatName` is supplied
--- the preferred name is colored (by the main's class); the count suffix stays plain.
--- Optional `query` highlights matching substrings in the preferred name.
function GTD.FormatMainRowLabel(group, formatName, query)
    return GTD.FormatMainRowName(group, formatName, query) .. " " .. GTD.FormatMainRowCount(group)
end

--- Class-colored character name only (no level / manual mark). Optional `query` highlights
--- matching substrings. Used when the list row places "M" and level as separate widgets.
function GTD.FormatCharacterNamePart(entry, formatName, query)
    local name = entry.name or "?"
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        return GTD.FormatTextWithSearchHighlight(name, entry.classFile, query, formatName)
    end
    if formatName then
        return formatName(name, entry.classFile)
    end
    local CC = AltArmy.ClassColor
    return (CC and CC.formatName and CC.formatName(name, entry.classFile)) or name
end

--- Character name column: class-colored name + gray "(level N)".
--- Optional `query` highlights matching substrings in the character name.
function GTD.FormatCharacterName(entry, formatName, query)
    local namePart = GTD.FormatCharacterNamePart(entry, formatName, query)
    local level = math.floor(tonumber(entry.level) or 0)
    return namePart .. " " .. GRAY .. "(level " .. level .. ")|r"
end

--- Comparable online-sort value for a roster status.
--- Online is always 0 (least time). Offline uses years→months→days→hours so order matches
--- the displayed unit buckets. Unknown/missing is a large sentinel (most time).
GTD.ROSTER_ONLINE_SORT_UNKNOWN = 2000000000
GTD.ROSTER_ONLINE_SORT_OFFLINE_BASE = 1000000000

function GTD.RosterStatusSortValue(status)
    if not status then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    if status.online then
        return 0
    end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    return GTD.ROSTER_ONLINE_SORT_OFFLINE_BASE
        + years * 1000000
        + months * 10000
        + days * 100
        + hours
end

--- Comparable online-sort value for a main group (most recent member status).
function GTD.GroupOnlineSortValue(group, rosterByName)
    return GTD.RosterStatusSortValue(GTD.GetGroupLastOnlineStatus(group, rosterByName or {}))
end

--- Comparable online-sort value for one character entry.
--- Accepts guild-tab members (`name`) or search guild rows (`characterName`).
function GTD.MemberOnlineSortValue(member, rosterByName)
    if not member or type(rosterByName) ~= "table" then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    local key = GTD.NormalizeRosterName(member.name or member.characterName)
    if not key then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    return GTD.RosterStatusSortValue(rosterByName[key])
end

--- Sort search guild-char rows (`{ characterName = ... }`) by last-online
--- (most recently online first), then character name A–Z. Mutates `chars` in place.
--- Optional `opts.getStatus(entry)` supplies a roster status (e.g. main-group presence);
--- when omitted, falls back to looking up the entry's own name in `rosterByName`.
function GTD.SortGuildSearchCharsByLastOnline(chars, rosterByName, opts)
    if type(chars) ~= "table" or #chars < 2 then
        return chars
    end
    rosterByName = rosterByName or {}
    opts = opts or {}
    local getStatus = opts.getStatus
    table.sort(chars, function(a, b)
        local va
        local vb
        if getStatus then
            va = GTD.RosterStatusSortValue(getStatus(a))
            vb = GTD.RosterStatusSortValue(getStatus(b))
        else
            va = GTD.MemberOnlineSortValue(a, rosterByName)
            vb = GTD.MemberOnlineSortValue(b, rosterByName)
        end
        if va ~= vb then
            return va < vb
        end
        local na = (a.characterName or a.name or ""):lower()
        local nb = (b.characterName or b.name or ""):lower()
        if na ~= nb then
            return na < nb
        end
        return (a.characterName or a.name or "") < (b.characterName or b.name or "")
    end)
    return chars
end

local function copyGroupWithMembers(group, members)
    return {
        main = group.main,
        preferredName = group.preferredName,
        overrideName = group.overrideName,
        pinned = group.pinned,
        prefsRealm = group.prefsRealm,
        classFile = group.classFile,
        characterCount = group.characterCount or #(members or {}),
        members = members,
    }
end

local function sortMembersForList(members, sortKey, ascending, rosterByName)
    local out = {}
    for i = 1, #(members or {}) do
        out[i] = members[i]
    end
    if #out < 2 then
        return out
    end
    local asc = ascending ~= false
    if sortKey == "online" then
        table.sort(out, function(a, b)
            local va = GTD.MemberOnlineSortValue(a, rosterByName)
            local vb = GTD.MemberOnlineSortValue(b, rosterByName)
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
            if na ~= nb then return na < nb end
            return (a.name or "") < (b.name or "")
        end)
        return out
    end
    -- Default character order: highest level first, then name.
    table.sort(out, function(a, b)
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la > lb end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

--- Sort main groups for the guild list (`sortKey`: "name", "characterCount", or "online").
--- Optional `rosterByName` is required for meaningful "online" sorting.
--- Returns a new list; does not mutate `groups`. Name is the stable tie-breaker (always A→Z).
--- Pinned groups (`group.pinned`) always sort above unpinned; column sort applies within each bucket.
--- When sorting by online, members within each group are also ordered by last online.
function GTD.SortGroups(groups, sortKey, ascending, rosterByName)
    local out = {}
    for i = 1, #(groups or {}) do
        out[i] = groups[i]
    end
    if #out == 0 then
        return out
    end
    local key = sortKey
    if key ~= "characterCount" and key ~= "online" then
        key = "name"
    end
    local asc = ascending ~= false
    rosterByName = rosterByName or {}

    if #out >= 2 then
        table.sort(out, function(a, b)
            local aPinned = a.pinned and true or false
            local bPinned = b.pinned and true or false
            if aPinned ~= bPinned then
                return aPinned
            end
            local va, vb
            if key == "characterCount" then
                va = a.characterCount or #(a.members or {})
                vb = b.characterCount or #(b.members or {})
            elseif key == "online" then
                va = GTD.GroupOnlineSortValue(a, rosterByName)
                vb = GTD.GroupOnlineSortValue(b, rosterByName)
            else
                va = (GTD.ResolveGroupDisplayName(a)):lower()
                vb = (GTD.ResolveGroupDisplayName(b)):lower()
            end
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            local na = (GTD.ResolveGroupDisplayName(a)):lower()
            local nb = (GTD.ResolveGroupDisplayName(b)):lower()
            if na ~= nb then
                return na < nb
            end
            return (a.main or "") < (b.main or "")
        end)
    end

    for i = 1, #out do
        local g = out[i]
        out[i] = copyGroupWithMembers(g, sortMembersForList(g.members, key, asc, rosterByName))
    end
    return out
end

--- Strip a realm suffix and lowercase a guild-roster or character name.
function GTD.NormalizeRosterName(name)
    if type(name) ~= "string" then return nil end
    local short = name:match("^[^%-]+") or name
    return short:lower()
end

--- Comparable offline duration in hours (approximate months as 30.5 days).
--- Online / missing status returns 0.
function GTD.RosterOfflineHours(status)
    if not status or status.online then return 0 end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    return (((years * 12) + months) * 30.5 + days) * 24 + hours
end

--- Display string for a roster last-online status. Empty when status is missing.
--- When `opts.showUnknownWhenMissing` is set, missing status returns gray "Unknown".
function GTD.FormatRosterLastOnline(status, opts)
    if not status then
        if opts and opts.showUnknownWhenMissing then
            return GRAY .. "Unknown|r"
        end
        return ""
    end
    if status.online then return "Online" end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    if years > 0 then return years .. "y ago" end
    if months > 0 then return months .. "mo ago" end
    if days > 0 then return days .. "d ago" end
    if hours > 0 then return hours .. "h ago" end
    return "< 1h ago"
end

--- Most recent status among a list: any online wins; otherwise shortest offline duration.
function GTD.PickMostRecentRosterStatus(statuses)
    if type(statuses) ~= "table" then return nil end
    local best
    local bestHours
    for _, status in ipairs(statuses) do
        if status then
            if status.online then
                return { online = true }
            end
            local hours = GTD.RosterOfflineHours(status)
            if not bestHours or hours < bestHours then
                bestHours = hours
                best = status
            end
        end
    end
    return best
end

--- Most recent last-online status for a main group, looking up each member in `rosterByName`.
function GTD.GetGroupLastOnlineStatus(group, rosterByName)
    if not group or type(rosterByName) ~= "table" then return nil end
    local statuses = {}
    for _, member in ipairs(group.members or {}) do
        local key = GTD.NormalizeRosterName(member.name)
        if key and key ~= "" then
            statuses[#statuses + 1] = rosterByName[key]
        end
    end
    return GTD.PickMostRecentRosterStatus(statuses)
end

--- Like GetGroupLastOnlineStatus, but also reports which member produced the status.
--- Returns `{ status, memberName, classFile }` or nil.
function GTD.GetGroupMostRecentOnlineDetail(group, rosterByName)
    if not group or type(rosterByName) ~= "table" then return nil end
    local best
    local bestMember
    local bestHours
    for _, member in ipairs(group.members or {}) do
        local key = GTD.NormalizeRosterName(member.name)
        if key and key ~= "" then
            local status = rosterByName[key]
            if status then
                if status.online then
                    return {
                        status = { online = true },
                        memberName = member.name,
                        classFile = member.classFile,
                    }
                end
                local hours = GTD.RosterOfflineHours(status)
                if not bestHours or hours < bestHours then
                    bestHours = hours
                    best = status
                    bestMember = member
                end
            end
        end
    end
    if best and bestMember then
        return {
            status = best,
            memberName = bestMember.name,
            classFile = bestMember.classFile,
        }
    end
    return nil
end

--- Tooltip presence line for a hovered guild character, or nil when roster info is missing.
--- Online is white; last-seen uses the same gray as search Offline. When the most recent
--- presence belongs to a different alt, appends " (as Name)" with Name class-colored via
--- formatName / ClassColor (surrounding text keeps white/gray, including parentheses).
function GTD.FormatGroupPresenceTooltipLine(hoveredName, detail, formatName)
    if not detail or not detail.status then
        return nil
    end
    local prefixColor = detail.status.online and WHITE or GRAY
    local body
    if detail.status.online then
        body = "Online"
    else
        local ago = GTD.FormatRosterLastOnline(detail.status)
        if not ago or ago == "" then
            return nil
        end
        body = "Last seen " .. ago
    end
    local hoverKey = GTD.NormalizeRosterName(hoveredName)
    local memberKey = GTD.NormalizeRosterName(detail.memberName)
    if memberKey and hoverKey and memberKey ~= hoverKey and detail.memberName and detail.memberName ~= "" then
        local asName = detail.memberName
        if formatName then
            asName = formatName(detail.memberName, detail.classFile)
        else
            local CC = AltArmy.ClassColor
            if CC and CC.formatName then
                asName = CC.formatName(detail.memberName, detail.classFile)
            end
        end
        return prefixColor .. body .. " (as |r" .. asName .. prefixColor .. ")|r"
    end
    return prefixColor .. body .. "|r"
end

--- Localized / display class name for tooltip copy.
function GTD.FormatClassDisplayName(classFile)
    if not classFile or classFile == "" then
        return "Unknown"
    end
    local male = _G.LOCALIZED_CLASS_NAMES_MALE
    if male and male[classFile] then
        return male[classFile]
    end
    local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
    if female and female[classFile] then
        return female[classFile]
    end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- Search-result character suffix for guildmate recipes: "(Online/Offline)".
--- Parens use the guild tag color; Online is white, Offline is gray.
function GTD.FormatGuildSearchCharacterSuffix(isOnline)
    if isOnline then
        return GUILD_TAG_COLOR .. " (|r" .. WHITE .. "Online|r" .. GUILD_TAG_COLOR .. ")|r"
    end
    return GUILD_TAG_COLOR .. " (|r" .. GRAY .. "Offline|r" .. GUILD_TAG_COLOR .. ")|r"
end

local function colorTooltipName(name, classFile, formatName)
    if formatName then
        return formatName(name, classFile)
    end
    local CC = AltArmy.ClassColor
    if CC and CC.formatName then
        return CC.formatName(name, classFile)
    end
    return name
end

--- Tooltip lines for a collapsed "Multiple guildmates" recipe search row.
--- `chars` entries: `{ name, classFile, mainName?, mainClassFile?, status?, namePrefix? }`.
--- Presence/sort use `c.status` when provided (caller supplies main-group / player presence);
--- otherwise fall back to individual `rosterByName` lookup by character name.
--- Sorted by last online via RosterStatusSortValue: online first (A–Z among online),
--- then shortest offline duration, unknown last (A–Z tie-break within equal status).
--- Character rows are `{ left = namePart, right = presence }` for GameTooltip:AddDoubleLine
--- (names left, times right-aligned). Footer lines are plain strings for AddLine:
--- optional white "...and N others", then gray "Click to expand/collapse".
--- opts.formatName?(name, classFile) optional class-color formatter.
function GTD.BuildCollapsedGuildRecipeTooltipLines(chars, rosterByName, opts)
    if type(chars) ~= "table" or #chars == 0 then
        return {}
    end
    opts = opts or {}
    rosterByName = rosterByName or {}
    local formatName = opts.formatName

    local rows = {}
    for i = 1, #chars do
        local c = chars[i]
        if c and c.name and c.name ~= "" then
            local status = c.status
            if status == nil then
                local key = GTD.NormalizeRosterName(c.name)
                status = key and rosterByName[key] or nil
            end
            local online = status and status.online and true or false
            rows[#rows + 1] = {
                name = c.name,
                classFile = c.classFile,
                mainName = c.mainName,
                mainClassFile = c.mainClassFile,
                namePrefix = c.namePrefix,
                online = online,
                status = status,
                -- Finite sort key (avoid math.huge; WoW table.sort mishandles inf).
                sortValue = GTD.RosterStatusSortValue(status),
                sortKey = (c.name or ""):lower(),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.sortValue ~= b.sortValue then
            return a.sortValue < b.sortValue
        end
        return a.sortKey < b.sortKey
    end)

    local total = #rows
    local showCount = total
    local others = 0
    if total >= 10 then
        showCount = 8
        others = total - 8
    end

    local lines = {}
    for i = 1, showCount do
        local row = rows[i]
        local colored = colorTooltipName(row.name, row.classFile, formatName)
        local left = colored
        local main = row.mainName
        if main and main ~= "" and main:lower() ~= row.name:lower() then
            local mainColored = colorTooltipName(main, row.mainClassFile or row.classFile, formatName)
            left = colored .. " " .. WHITE .. "(|r" .. mainColored .. WHITE .. ")|r"
        end
        local prefix = row.namePrefix
        if type(prefix) == "string" and prefix ~= "" then
            left = prefix .. left
        end
        local presence
        if row.online then
            presence = WHITE .. "Online|r"
        else
            local ago = GTD.FormatRosterLastOnline(row.status, { showUnknownWhenMissing = true })
            -- FormatRosterLastOnline already wraps Unknown in gray; wrap ago-text ourselves.
            if ago:sub(1, #GRAY) == GRAY then
                presence = ago
            else
                presence = GRAY .. ago .. "|r"
            end
        end
        lines[i] = { left = left, right = presence }
    end
    if others > 0 then
        lines[#lines + 1] = WHITE .. "...and " .. others .. " others|r"
    end
    local hint = (opts.isExpanded and "Click to collapse") or "Click to expand"
    lines[#lines + 1] = GRAY .. hint .. "|r"
    return lines
end

--- Tooltip for an own-account character in search results.
--- opts: name, classFile, level, formatName?, classDisplayName?, specializationLabel?
--- Returns class-colored name, optional green specialization, then "Level N Class".
function GTD.BuildOwnCharacterHoverTooltipLines(opts)
    opts = opts or {}
    local name = opts.name or "?"
    local className = opts.classDisplayName or GTD.FormatClassDisplayName(opts.classFile)
    local level = math.floor(tonumber(opts.level) or 0)
    local lines = {
        colorTooltipName(name, opts.classFile, opts.formatName),
    }
    local specLabel = opts.specializationLabel
    if type(specLabel) == "string" and specLabel ~= "" then
        lines[#lines + 1] = "|cff00ff00" .. specLabel .. " specialization|r"
    end
    lines[#lines + 1] = "Level " .. level .. " " .. className
    return lines
end

--- Lines for a search-result guildmate name tooltip.
--- opts: name, preferredName, preferredClassFile?, classFile, level, presenceDetail?,
---       formatName?, classDisplayName?, specializationLabel?
--- Returns lines: name, optional green specialization, level/class, optional presence.
--- Preferred/main name is omitted from line1 when it matches the character name.
--- When shown, preferred name is class-colored (preferredClassFile) with white parentheses.
function GTD.BuildGuildCharacterHoverTooltipLines(opts)
    opts = opts or {}
    local name = opts.name or "?"
    local preferred = opts.preferredName or name
    local formatName = opts.formatName
    local colored = colorTooltipName(name, opts.classFile, formatName)
    local line1 = colored
    if preferred ~= "" and preferred:lower() ~= name:lower() then
        local preferredColored = colorTooltipName(
            preferred, opts.preferredClassFile or opts.classFile, formatName)
        line1 = colored .. " " .. WHITE .. "(|r" .. preferredColored .. WHITE .. ")|r"
    end
    local lines = { line1 }
    local specLabel = opts.specializationLabel
    if type(specLabel) == "string" and specLabel ~= "" then
        lines[#lines + 1] = "|cff00ff00" .. specLabel .. " specialization|r"
    end
    local className = opts.classDisplayName or GTD.FormatClassDisplayName(opts.classFile)
    local level = math.floor(tonumber(opts.level) or 0)
    lines[#lines + 1] = "Level " .. level .. " " .. className
    local presence = GTD.FormatGroupPresenceTooltipLine(name, opts.presenceDetail, formatName)
    if presence then
        lines[#lines + 1] = presence
        lines.presenceOnline = opts.presenceDetail
            and opts.presenceDetail.status
            and opts.presenceDetail.status.online
            and true
            or false
    end
    return lines
end

--- Notes-wizard member title: class-colored name + gray "(level N)".
function GTD.FormatNotesWizardMemberName(name, classFile, level, formatNameFn)
    local colored
    if formatNameFn then
        colored = formatNameFn(name or "?", classFile) or (name or "?")
    else
        local CC = AltArmy.ClassColor
        colored = (CC and CC.formatName and CC.formatName(name or "?", classFile)) or (name or "?")
    end
    local n = math.floor(tonumber(level) or 0)
    return colored .. " " .. GRAY .. "(level " .. n .. ")|r"
end

--- Notes-wizard note line (white): the note wrapped in double quotes.
--- Empty string when there is no note.
--- Pipe characters in the note are doubled so player-controlled text cannot
--- inject WoW UI escape sequences (|c, |T, etc.).
--- Optional `query` highlights matching substrings in green inside the quotes.
function GTD.FormatNotesWizardMemberNote(note, query)
    if type(note) ~= "string" then return "" end
    note = note:match("^%s*(.-)%s*$") or note
    if note == "" then return "" end
    note = note:gsub("|", "||")
    local q = query and GTD.NormalizeSearchQuery(query) or ""
    if q == "" then
        return WHITE .. '"' .. note .. '"|r'
    end
    local body = GTD.FormatTextWithSearchHighlight(note, nil, q, function(seg)
        return WHITE .. seg .. "|r"
    end)
    return WHITE .. '"' .. "|r" .. body .. WHITE .. '"' .. "|r"
end

--- Count characters in a notes/manual wizard proposal for Accept-button enabling.
--- Counts main (if set), members (excluding case-variants of the main), and knownMembers.
--- Accept is meaningful when the result is greater than 1.
function GTD.CountNotesProposalCharacters(proposal)
    if type(proposal) ~= "table" then return 0 end
    local count = 0
    local mainKey
    if type(proposal.main) == "string" and proposal.main ~= "" then
        count = count + 1
        mainKey = GTD.NormalizeRosterName and GTD.NormalizeRosterName(proposal.main)
    end
    for _, member in ipairs(proposal.members or {}) do
        if member and type(member.name) == "string" and member.name ~= "" then
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(member.name)
            if not mainKey or key ~= mainKey then
                count = count + 1
            end
        end
    end
    for _, known in ipairs(proposal.knownMembers or {}) do
        if known and type(known.name) == "string" and known.name ~= "" then
            count = count + 1
        end
    end
    return count
end

--- Notes-wizard attribution line (gray), prefixed with "Reason: ".
--- The reason body starts with a lowercase letter.
--- `kind`: "note" | "manual" | "shared" | "referred" (or any other string used as custom reason).
--- For "note", always returns "text match in guild note" (does not repeat the note text).
--- For "manual", returns "added manually".
--- Otherwise uses `reason` when provided (first character lowercased).
function GTD.FormatNotesWizardMemberAttribution(kind, reason)
    local text
    if kind == "note" then
        text = "text match in guild note"
    elseif kind == "manual" then
        text = "added manually"
    else
        text = (type(reason) == "string" and reason ~= "" and reason) or nil
        if not text and kind == "shared" then
            text = "from Alt Army shared data"
        elseif not text and kind == "referred" then
            text = "referred to by other notes"
        end
    end
    if not text or text == "" then return "" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then
        text = text:sub(1, 1):lower() .. text:sub(2)
    end
    return GRAY .. "Reason: " .. text .. "|r"
end

--- Short inclusion-reason label for the notes wizard "Reason for Inclusion" column.
--- `kind`: "main" | "note" | "manual" | "shared" | "referred" | "conflict"
function GTD.NotesWizardInclusionReasonLabel(kind)
    if kind == "note" then
        return "Name in note"
    elseif kind == "manual" then
        return "Manually added"
    elseif kind == "shared" then
        return "Shared via Alt Army"
    elseif kind == "auto" then
        return "Group created automatically"
    elseif kind == "conflict" then
        return "Conflicts with addon"
    elseif kind == "main" or kind == "referred" then
        return "Referred to by note"
    end
    return ""
end

--- Classify a notes-wizard display row into an inclusion-reason kind.
--- opts: isMain?, mainFromShared?, isKnownShared?, noteText?, alreadyMapped?,
--- origin? ("note"|"user"), isManualMember?, autoGroup? (a character read by link that nothing grouped)
function GTD.ClassifyNotesWizardInclusionReason(opts)
    opts = opts or {}
    if opts.isMain and opts.autoGroup then
        return "auto"
    end
    if opts.isMain then
        if opts.mainFromShared then
            return "shared"
        end
        -- Note-created grouping main: other notes referred to this character.
        if opts.origin == "note" then
            return "main"
        end
        -- Manual-create grouping main (or a manual stub with no note origin).
        if opts.origin == "user" or opts.isManualMember then
            return "manual"
        end
        return "main"
    end
    if opts.isKnownShared then
        return "shared"
    end
    if type(opts.noteText) == "string" and opts.noteText:match("%S") then
        return "note"
    end
    if opts.alreadyMapped then
        if opts.origin == "note" then
            return "note"
        end
        return "manual"
    end
    return "manual"
end

--- Ensure `proposal.order` exists (add order for stable manual-wizard display).
--- Synthesizes from main + members when missing. Returns the order table.
function GTD.EnsureManualProposalOrder(proposal)
    if type(proposal) ~= "table" then return {} end
    if type(proposal.order) == "table" then
        return proposal.order
    end
    local order = {}
    if type(proposal.main) == "string" and proposal.main ~= "" then
        order[#order + 1] = proposal.main
    end
    for _, member in ipairs(proposal.members or {}) do
        if member and type(member.name) == "string" and member.name ~= "" then
            order[#order + 1] = member.name
        end
    end
    proposal.order = order
    return order
end

--- Stable display order for a manual-create proposal (add order; independent of main).
function GTD.ManualProposalDisplayOrder(proposal)
    if type(proposal) ~= "table" then return {} end
    local order = GTD.EnsureManualProposalOrder(proposal)
    local out = {}
    for i, name in ipairs(order) do
        out[i] = name
    end
    return out
end

local function rebuildManualMembersFromOrder(proposal)
    local mainKey = type(proposal.main) == "string" and proposal.main ~= ""
        and GTD.NormalizeRosterName and GTD.NormalizeRosterName(proposal.main)
    proposal.members = {}
    for _, name in ipairs(proposal.order or {}) do
        if type(name) == "string" and name ~= "" then
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
            if key and key ~= mainKey then
                proposal.members[#proposal.members + 1] = { name = name, addedManually = true }
            end
        end
    end
end

--- Add a character to an in-memory manual-create proposal.
--- First name becomes `proposal.main`; subsequent names append as `{ name, addedManually = true }`.
--- Appends to `proposal.order` (stable display order). Returns true on success.
function GTD.AddManualProposalMember(proposal, name)
    if type(proposal) ~= "table" then return false end
    if type(name) ~= "string" or name == "" then return false end
    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
    if not key or key == "" then return false end
    local order = GTD.EnsureManualProposalOrder(proposal)
    for _, existing in ipairs(order) do
        local existingKey = GTD.NormalizeRosterName and GTD.NormalizeRosterName(existing)
        if existingKey == key then return false end
    end
    order[#order + 1] = name
    if type(proposal.main) ~= "string" or proposal.main == "" then
        proposal.main = name
    end
    rebuildManualMembersFromOrder(proposal)
    return true
end

--- Remove a character from an in-memory manual-create proposal.
--- When the main is removed, promotes the next name in display order.
--- Returns true when something was removed.
function GTD.RemoveManualProposalMember(proposal, name)
    if type(proposal) ~= "table" then return false end
    if type(name) ~= "string" or name == "" then return false end
    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
    if not key or key == "" then return false end
    local order = GTD.EnsureManualProposalOrder(proposal)
    local removeIndex
    for i, existing in ipairs(order) do
        local existingKey = GTD.NormalizeRosterName and GTD.NormalizeRosterName(existing)
        if existingKey == key then
            removeIndex = i
            break
        end
    end
    if not removeIndex then return false end
    local mainKey = type(proposal.main) == "string" and proposal.main ~= ""
        and GTD.NormalizeRosterName and GTD.NormalizeRosterName(proposal.main)
    table.remove(order, removeIndex)
    if mainKey and mainKey == key then
        local nextName = order[1]
        if type(nextName) == "string" and nextName ~= "" then
            proposal.main = nextName
        else
            proposal.main = nil
        end
    end
    rebuildManualMembersFromOrder(proposal)
    return true
end

--- Make `name` the main of an in-memory manual-create proposal.
--- Does not change `proposal.order` (display order stays stable).
--- Returns true on success (including when name is already the main).
function GTD.SetManualProposalMain(proposal, name)
    if type(proposal) ~= "table" then return false end
    if type(name) ~= "string" or name == "" then return false end
    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
    if not key or key == "" then return false end
    local order = GTD.EnsureManualProposalOrder(proposal)
    local found = false
    for _, existing in ipairs(order) do
        local existingKey = GTD.NormalizeRosterName and GTD.NormalizeRosterName(existing)
        if existingKey == key then
            found = true
            break
        end
    end
    if not found then return false end
    proposal.main = name
    rebuildManualMembersFromOrder(proposal)
    return true
end

--- Gray level suffix for the guild character recipe title: "(level N)" or "(N)".
function GTD.FormatCharacterLevelSuffix(level, mode, grayPrefix)
    local n = math.floor(tonumber(level) or 0)
    local inner = (mode == "short") and tostring(n) or ("level " .. n)
    local body = "(" .. inner .. ")"
    if grayPrefix and grayPrefix ~= "" then
        return " " .. grayPrefix .. body .. "|r"
    end
    return " " .. body
end

--- Which title form fits: "full" ((level N)), "short" ((N)), or "ellipsis" (truncate name + short).
--- fitsFull / fitsShort are booleans from the caller's width measurements.
function GTD.ChooseCharacterTitleLevelMode(fitsFull, fitsShort)
    if fitsFull then return "full" end
    if fitsShort then return "short" end
    return "ellipsis"
end

--- Name to whisper when someone in the viewed character's group is online.
--- Prefer the character currently playing (online roster member); nil when none are online
--- or when viewing one of the player's own (local) characters.
function GTD.ResolveOnlineWhisperTarget(entry, rosterByName, members)
    if not entry or not entry.name then
        return nil
    end
    if entry.source == "local" then
        return nil
    end
    local group
    if type(members) == "table" and GTD.GroupMembersByMain then
        local groups = GTD.GroupMembersByMain(members)
        for _, g in ipairs(groups or {}) do
            for _, m in ipairs(g.members or {}) do
                if m.name == entry.name then
                    group = g
                    break
                end
            end
            if group then break end
        end
    end
    if not group then
        group = { members = { entry }, main = entry.main or entry.name }
    end
    local detail = GTD.GetGroupMostRecentOnlineDetail(group, rosterByName or {})
    if detail and detail.status and detail.status.online and detail.memberName then
        return detail.memberName
    end
    return nil
end

--- Build short-name -> last-online status from guild roster APIs.
--- `api` may override: isInGuild, getNumGuildMembers, getGuildRosterInfo,
--- getGuildRosterLastOnline, normalizeName (defaults to live WoW globals / NormalizeRosterName).
function GTD.BuildRosterLastOnlineMap(api)
    api = api or {}
    local isInGuild = api.isInGuild or IsInGuild
    local getNum = api.getNumGuildMembers or GetNumGuildMembers
    local getInfo = api.getGuildRosterInfo or GetGuildRosterInfo
    local getLast = api.getGuildRosterLastOnline or GetGuildRosterLastOnline
    local normalize = api.normalizeName or GTD.NormalizeRosterName

    local out = {}
    if not isInGuild or not isInGuild() then return out end
    if not getNum or not getInfo then return out end
    local n = getNum()
    if type(n) ~= "number" or n < 1 then return out end
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online = getInfo(i)
        local key = normalize(name)
        if key and key ~= "" then
            if online then
                out[key] = { online = true }
            elseif getLast then
                local years, months, days, hours = getLast(i)
                out[key] = {
                    online = false,
                    years = years or 0,
                    months = months or 0,
                    days = days or 0,
                    hours = hours or 0,
                }
            else
                out[key] = { online = false, years = 0, months = 0, days = 0, hours = 0 }
            end
        end
    end
    return out
end

--- Build short-name -> { classFile, level, name, note } from guild roster APIs.
--- Used to enrich manual grouping stubs and to refresh stored class/level on mappings.
--- `note` is the trimmed public note, or officer note when public is empty.
--- `api` may override: isInGuild, getNumGuildMembers, getGuildRosterInfo, normalizeName.
function GTD.BuildRosterInfoMap(api)
    api = api or {}
    local isInGuild = api.isInGuild or IsInGuild
    local getNum = api.getNumGuildMembers or GetNumGuildMembers
    local getInfo = api.getGuildRosterInfo or GetGuildRosterInfo
    local normalize = api.normalizeName or GTD.NormalizeRosterName

    local out = {}
    if not isInGuild or not isInGuild() then return out end
    if not getNum or not getInfo then return out end
    local n = getNum()
    if type(n) ~= "number" or n < 1 then return out end
    for i = 1, n do
        -- name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName
        local name, _, _, level, _, _, publicNote, officerNote, _, _, classFile = getInfo(i)
        if not canAccessSecretValue(name) then name = nil end
        local key = normalize(name)
        if key and key ~= "" then
            local short = type(name) == "string" and (name:match("^[^%-]+") or name) or name
            local note = ""
            if type(publicNote) == "string" and canAccessSecretValue(publicNote) then
                note = publicNote:match("^%s*(.-)%s*$") or ""
            end
            if note == "" and type(officerNote) == "string" and canAccessSecretValue(officerNote) then
                note = officerNote:match("^%s*(.-)%s*$") or ""
            end
            out[key] = {
                classFile = classFile or "",
                level = level or 0,
                name = short,
                note = note,
            }
        end
    end
    return out
end

--- Autocomplete label: class-colored name + white "(level)".
--- `formatNameFn(name, classFile)` supplies the colored name (defaults to plain name).
--- Optional `query` highlights matching name substrings in green.
function GTD.FormatRosterSuggestName(info, formatNameFn, query)
    local name = (info and info.name) or ""
    local classFile = info and info.classFile or nil
    local colored
    local q = query and GTD.NormalizeSearchQuery(query) or ""
    if q ~= "" then
        colored = GTD.FormatTextWithSearchHighlight(name, classFile, q, formatNameFn)
    elseif formatNameFn then
        colored = formatNameFn(name, classFile) or name
    else
        colored = name
    end
    local level = math.floor(tonumber(info and info.level) or 0)
    return colored .. " |cffffffff(" .. level .. ")|r"
end

--- Professions column: "Name — Spec (rank), ..." with the specialization (when present) after
--- an em dash in the default (white) color and the gray skill level in parentheses.
--- Gathering professions are listed after crafting. Optional `query` highlights matching
--- substrings in profession names and specializations.
--- Empty string when the character has no displayable professions (including manual members).
function GTD.FormatProfessions(entry, query)
    if GTD.IsManualMember(entry) then
        return ""
    end
    local activeQuery = query and GTD.NormalizeSearchQuery(query) or ""
    local parts = {}
    for _, prof in ipairs(GTD.GetPrimaryProfessions(entry)) do
        local profName = prof.name
        if activeQuery ~= "" then
            profName = GTD.FormatTextWithSearchHighlight(prof.name, nil, activeQuery)
        end
        local spec = ""
        if prof.spec and prof.spec ~= "" then
            local specText = prof.spec
            if activeQuery ~= "" then
                specText = GTD.FormatTextWithSearchHighlight(prof.spec, nil, activeQuery)
            end
            spec = " \226\128\148 " .. specText
        end
        parts[#parts + 1] = profName .. spec .. " " .. GRAY .. "(" .. prof.rank .. ")|r"
    end
    return table.concat(parts, ", ")
end
