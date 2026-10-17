-- AltArmy TBC — v2 presentation: aggregate, sort, guild collapse.
-- Builds display rows from match hits without relying on SearchData caches.

AltArmy = AltArmy or {}
AltArmy.SearchPresent = AltArmy.SearchPresent or {}

local SP = AltArmy.SearchPresent

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

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Item icon without needing the item cache (GetItemInfo returns nothing until the client has seen the
--- item); GetItemInfo is the last resort.
local function resolveItemIcon(itemID)
    if not itemID then return nil end
    if GetItemIcon then
        local icon = GetItemIcon(itemID)
        if icon then return icon end
    end
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then return icon end
    end
    local instant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if instant then
        local _, _, _, _, icon = instant(itemID)
        if icon then return icon end
    end
    if hasItemInfoApi() then
        local _, _, _, _, _, _, _, _, _, icon = compatGetItemInfo(itemID)
        if icon then return icon end
    end
    return nil
end

--- Legacy GetSpellInfo tuple (name, rank, icon); Forever has only C_Spell.GetSpellInfo.
local function compatGetSpellInfo(spellID)
    if GetSpellInfo then return GetSpellInfo(spellID) end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, nil, info.iconID end
    end
end

local function LocationSortKey(location)
    if location == "bag" then return 1 end
    if location == "keyring" then return 2 end
    if location == "bank" then return 3 end
    if location == "equipped" then return 4 end
    if location == "equipped-bank" then return 5 end
    if location == "mail" then return 6 end
    return 99
end

local function GetNameMatchScoreFromLower(nameLower, queryLower)
    if not nameLower or not queryLower or queryLower == "" then
        return 0
    end
    if nameLower == queryLower then
        return 3
    end
    if nameLower:sub(1, #queryLower) == queryLower then
        return 2
    end
    if nameLower:find(queryLower, 1, true) then
        return 1
    end
    return 0
end

local function EnsureNestedMap(parent, key)
    local child = parent[key]
    if not child then
        child = {}
        parent[key] = child
    end
    return child
end

local function BuildItemAggregateGroupFromList(list)
    local byItem = {}
    for i = 1, #(list or {}) do
        local entry = list[i]
        local itemID = entry.itemID or 0
        local item = byItem[itemID]
        if not item then
            local itemName = entry.itemName
            local nameLower = entry.itemNameLower
                or (itemName and itemName:lower())
                or ""
            item = {
                itemID = itemID,
                itemName = itemName,
                itemLink = entry.itemLink,
                nameLower = nameLower,
                chars = {},
            }
            byItem[itemID] = item
        elseif not item.itemLink and entry.itemLink then
            item.itemLink = entry.itemLink
        end

        local realm = entry.realm or ""
        local charName = entry.characterName or ""
        local realmMap = EnsureNestedMap(item.chars, realm)
        -- a linked account's copy of a character is its own row, never summed into ours
        local charKey = entry.linkId and (charName .. "" .. entry.linkId) or charName
        local ch = realmMap[charKey]
        if not ch then
            ch = {
                classFile = entry.classFile,
                total = 0,
                locs = {},
            }
            realmMap[charKey] = ch
        end

        local loc = entry.location or "bag"
        local locRow = ch.locs[loc]
        local count = entry.count or 1
        if not locRow then
            locRow = {
                itemID = itemID,
                itemLink = entry.itemLink or item.itemLink,
                itemName = item.itemName,
                characterName = charName,
                realm = realm,
                location = loc,
                locKey = LocationSortKey(loc),
                count = 0,
                classFile = entry.classFile or ch.classFile,
                linkId = entry.linkId,
            }
            ch.locs[loc] = locRow
        end
        locRow.count = locRow.count + count
        ch.total = ch.total + count
    end
    return byItem
end

--- Aggregate raw slot hits into display rows (same shape as SearchData AggregateAndSort).
function SP.AggregateItemRows(raw, queryLower)
    local byItem = BuildItemAggregateGroupFromList(raw)
    local items = {}
    for _, item in pairs(byItem) do
        items[#items + 1] = item
    end
    for i = 1, #items do
        items[i].matchScore = GetNameMatchScoreFromLower(items[i].nameLower, queryLower)
    end
    table.sort(items, function(a, b)
        if a.matchScore ~= b.matchScore then
            return a.matchScore > b.matchScore
        end
        if a.nameLower ~= b.nameLower then
            return a.nameLower < b.nameLower
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    local list = {}
    for i = 1, #items do
        local item = items[i]
        local rows = {}
        for _, realmMap in pairs(item.chars) do
            for _, ch in pairs(realmMap) do
                for _, locRow in pairs(ch.locs) do
                    locRow.charTotal = ch.total
                    rows[#rows + 1] = locRow
                end
            end
        end
        if #rows > 1 then
            table.sort(rows, function(a, b)
                if a.charTotal ~= b.charTotal then
                    return a.charTotal > b.charTotal
                end
                if a.locKey ~= b.locKey then
                    return a.locKey < b.locKey
                end
                return (a.location or "") < (b.location or "")
            end)
        end
        for j = 1, #rows do
            list[#list + 1] = rows[j]
        end
    end
    for i = 1, #list do
        list[i].charTotal = nil
    end
    return list
end

local recipeVisualCache = {}

function SP.ClearVisualCache()
    recipeVisualCache = {}
end

local DIFFICULTY_SORT_ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }

local function cmpValues(a, b)
    if a < b then return -1 end
    if a > b then return 1 end
    return 0
end

local function characterSortKey(entry)
    return ((entry.characterName or "") .. "\0" .. (entry.realm or "")):lower()
end

local function buildItemGroupTotals(list)
    local totals = {}
    for _, row in ipairs(list) do
        local key = (row.itemID or 0) .. "\t" .. (row.itemName or "")
        totals[key] = (totals[key] or 0) + (row.count or 1)
    end
    return totals
end

--- Sort item search rows by column (`sortKey`: "Item", "Character", or "Total").
function SP.SortItemResults(list, sortKey, ascending)
    if not list or #list < 2 or not sortKey then
        return list
    end
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    local itemTotals = sortKey == "Total" and buildItemGroupTotals(out) or nil
    local nameKeys = {}
    local charKeys = {}
    for i = 1, #out do
        local row = out[i]
        nameKeys[row] = (row.itemName or ""):lower()
        charKeys[row] = characterSortKey(row)
    end

    table.sort(out, function(a, b)
        local cmp = 0
        if sortKey == "Item" then
            cmp = cmpValues(nameKeys[a], nameKeys[b])
            if cmp == 0 then
                cmp = cmpValues(a.itemID or 0, b.itemID or 0)
            end
        elseif sortKey == "Character" then
            cmp = cmpValues(charKeys[a], charKeys[b])
        elseif sortKey == "Total" then
            local keyA = (a.itemID or 0) .. "\t" .. (a.itemName or "")
            local keyB = (b.itemID or 0) .. "\t" .. (b.itemName or "")
            cmp = cmpValues(itemTotals[keyA] or 0, itemTotals[keyB] or 0)
        end
        if cmp == 0 then
            cmp = cmpValues(nameKeys[a], nameKeys[b])
        end
        if cmp == 0 then
            cmp = cmpValues(charKeys[a], charKeys[b])
        end
        if cmp == 0 then
            cmp = cmpValues(LocationSortKey(a.location or "bag"), LocationSortKey(b.location or "bag"))
        end
        if not ascending then
            cmp = -cmp
        end
        return cmp < 0
    end)
    return out
end

local function recipeSortName(entry)
    if entry._aaRecipeSortKey then
        return entry._aaRecipeSortKey
    end
    local nameLower = entry.recipeNameLower or ""
    return ((entry.professionName or ""):lower() .. "\0" .. nameLower)
end

local function applySortDirection(cmp, ascending)
    if not ascending then
        return -cmp
    end
    return cmp
end

local function compareRequiredSkill(a, b, ascending)
    local reqA = a.recipeSkillRequired
    local reqB = b.recipeSkillRequired
    if reqA == nil and reqB == nil then
        return 0
    end
    if reqA == nil then
        return 1
    end
    if reqB == nil then
        return -1
    end
    local cmp = applySortDirection(cmpValues(reqA, reqB), ascending)
    if cmp ~= 0 then
        return cmp
    end
    local ordA = DIFFICULTY_SORT_ORDER[a.difficulty] or 99
    local ordB = DIFFICULTY_SORT_ORDER[b.difficulty] or 99
    return applySortDirection(cmpValues(ordA, ordB), ascending)
end

-- Whose a row is, in the order rows sort: ours, then a linked account's, then a guildmate's.
local function affiliationTier(row)
    if row.isGuild then
        return 2
    end
    if row.linkId then
        return 1
    end
    return 0
end
SP.AffiliationTier = affiliationTier

local function compareGuildAffiliation(a, b)
    local ta, tb = affiliationTier(a), affiliationTier(b)
    if ta == tb then
        return 0
    end
    return ta < tb and -1 or 1
end

local function compareRecipeRowsWithinId(a, b)
    local ta, tb = affiliationTier(a), affiliationTier(b)
    if ta ~= tb then
        return ta < tb
    end
    local ca = (a.characterName or ""):lower()
    local cb = (b.characterName or ""):lower()
    if ca ~= cb then
        return ca < cb
    end
    return (a.recipeID or 0) < (b.recipeID or 0)
end

--- True when rows are already own-before-guild then character A-Z (hot path after search merge).
local function withinIdOrdered(rows)
    for i = 2, #rows do
        local prev = rows[i - 1]
        local cur = rows[i]
        if not compareRecipeRowsWithinId(prev, cur) then
            -- Equal keys are fine (stable); only fail when cur should sort before prev.
            if compareRecipeRowsWithinId(cur, prev) then
                return false
            end
        end
    end
    return true
end

--- Sort by recipe (profession+name): sort unique recipe IDs, then expand rows
--- (own before guild, then character). O(U log U + R) instead of O(R log R).
--- Within-id table.sort is skipped when rows are already ordered (TabSearch merge).
local function SortRecipeResultsByRecipe(list, ascending)
    local groupsById = {}
    local groups = {}
    for i = 1, #list do
        local row = list[i]
        local id = row.recipeID or 0
        local g = groupsById[id]
        if not g then
            g = {
                id = id,
                key = recipeSortName(row),
                rows = {},
            }
            groupsById[id] = g
            groups[#groups + 1] = g
        end
        g.rows[#g.rows + 1] = row
    end
    table.sort(groups, function(a, b)
        if a.key ~= b.key then
            if ascending then
                return a.key < b.key
            end
            return a.key > b.key
        end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, #groups do
        local rows = groups[i].rows
        if #rows > 1 and not withinIdOrdered(rows) then
            table.sort(rows, compareRecipeRowsWithinId)
        end
        for j = 1, #rows do
            out[#out + 1] = rows[j]
        end
    end
    return out
end

local function enrich(entry)
    local eng = AltArmy.SearchEngine or AltArmy.SearchData
    if eng and eng.EnrichRecipeEntry then
        return eng.EnrichRecipeEntry(entry)
    end
    if eng and eng._EnrichRecipeEntry then
        return eng._EnrichRecipeEntry(entry)
    end
end

--- Sort recipe search rows by column (`sortKey`: "Recipe", "Character", or "Skill").
--- Skill uses required recipe level when recipe data is loaded, otherwise character skill rank.
--- Recipe/Skill tie-breakers: own characters, then guildmates, then character name A-Z.
function SP.SortRecipeResults(list, sortKey, ascending, recipeDataAvailable)
    if not list or #list < 2 or not sortKey then
        return list
    end
    if sortKey == "Recipe" then
        return SortRecipeResultsByRecipe(list, ascending ~= false)
    end
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    local useRequiredSkill = sortKey == "Skill" and recipeDataAvailable
    if useRequiredSkill then
        for i = 1, #out do
            enrich(out[i])
        end
    end
    local useGuildTiebreak = sortKey == "Skill"
    local recipeNameKeys = {}
    local characterNameKeys = {}
    for i = 1, #out do
        local row = out[i]
        recipeNameKeys[row] = recipeSortName(row)
        characterNameKeys[row] = (row.characterName or ""):lower()
    end

    table.sort(out, function(a, b)
        local cmp = 0
        if sortKey == "Character" then
            cmp = applySortDirection(cmpValues(characterNameKeys[a], characterNameKeys[b]), ascending)
            if cmp == 0 then
                cmp = compareGuildAffiliation(a, b)
            end
        elseif sortKey == "Skill" then
            if useRequiredSkill then
                cmp = compareRequiredSkill(a, b, ascending)
            else
                cmp = applySortDirection(cmpValues(a.skillRank or 0, b.skillRank or 0), ascending)
            end
        end
        if cmp ~= 0 then
            return cmp < 0
        end
        if useGuildTiebreak then
            cmp = compareGuildAffiliation(a, b)
            if cmp ~= 0 then
                return cmp < 0
            end
            cmp = cmpValues(characterNameKeys[a], characterNameKeys[b])
            if cmp ~= 0 then
                return cmp < 0
            end
            return (a.recipeID or 0) < (b.recipeID or 0)
        end
        cmp = cmpValues(recipeNameKeys[a], recipeNameKeys[b])
        if cmp ~= 0 then
            return applySortDirection(cmp, ascending) < 0
        end
        return (a.recipeID or 0) < (b.recipeID or 0)
    end)
    return out
end

--- Collapse guild rows for the same recipeID (parity with SearchData.CollapseGuildRecipeRows).
--- Clears prior _aaFromCollapse flags on the input before building the display list.
--- Collects guild chars per recipeID in one O(n) pass (no per-id j=i..n rescans).
--- Last-online sort (main-group, then A–Z) runs only for expanded groups so collapsed
--- search refreshes stay cheap. Optional `rosterByName` feeds that expand-time sort.
function SP.CollapseGuildRecipeRows(sortedList, expandedSet, rosterByName)
    if sortedList == nil then
        return nil
    end
    local n = #sortedList
    if n == 0 then
        return {}
    end
    expandedSet = expandedSet or {}

    local guildCountById = {}
    local guildCharsById = {}

    for i = 1, n do
        local entry = sortedList[i]
        if entry then
            entry._aaFromCollapse = nil
            if entry.isGuild and entry.recipeID ~= nil then
                local id = entry.recipeID
                local chars = guildCharsById[id]
                if not chars then
                    chars = {}
                    guildCharsById[id] = chars
                end
                chars[#chars + 1] = entry
                guildCountById[id] = #chars
            end
        end
    end

    local Nav = AltArmy and AltArmy.SearchGuildNav
    local GTD = AltArmy and AltArmy.GuildTabData
    local sortOpts = { rosterByName = rosterByName }
    local function sortGuildCharsForExpand(chars)
        if Nav and Nav.SortGuildRecipeCharsByLastOnline then
            Nav.SortGuildRecipeCharsByLastOnline(chars, sortOpts)
        elseif GTD and GTD.SortGuildSearchCharsByLastOnline then
            GTD.SortGuildSearchCharsByLastOnline(chars, rosterByName)
        end
    end

    local out = {}
    local outN = 0
    local collapsedEmitted = {}

    for i = 1, n do
        local entry = sortedList[i]
        if entry and not entry.isGuild then
            outN = outN + 1
            out[outN] = entry
        elseif entry and entry.isGuild then
            local id = entry.recipeID
            local count = id ~= nil and guildCountById[id] or 0
            if count < 3 then
                outN = outN + 1
                out[outN] = entry
            elseif not collapsedEmitted[id] then
                collapsedEmitted[id] = true
                local guildChars = guildCharsById[id]
                local charN = #guildChars
                local isExpanded = expandedSet[id] and true or false
                if isExpanded then
                    sortGuildCharsForExpand(guildChars)
                end
                outN = outN + 1
                out[outN] = {
                    isGuildCollapsed = true,
                    isGuildExpanded = isExpanded or nil,
                    recipeID = id,
                    professionName = entry.professionName,
                    guildChars = guildChars,
                    _aaSkillCellText = "*",
                }
                if isExpanded then
                    for k = 1, charN do
                        local child = guildChars[k]
                        child._aaFromCollapse = true
                        outN = outN + 1
                        out[outN] = child
                    end
                end
            end
        end
    end
    return out
end

--- Resolve and cache recipe row display fields (name, icon, skill text) after first paint.
--- Name/icon are shared by recipe identity; skill text is per entry (skillRank/difficulty).
--- `_aaRecipeBaseName` is the full display string (profession prefix + recipe name).
--- Highlighting uses `_aaRecipeMatchName` only so profession prefixes are not tinted.
function SP.EnsureRecipeDisplayCache(entry)
    if not entry or entry._aaDisplayCached then
        return entry
    end
    local cacheKey = tostring(entry.professionName or "") .. ":"
        .. tostring(entry.recipeID or "") .. ":" .. tostring(entry.resultItemID or "")
    local visual = recipeVisualCache[cacheKey]
    local recipeName
    local matchName
    local namePrefix
    local iconPath
    if visual then
        recipeName = visual.name
        matchName = visual.matchName
        namePrefix = visual.namePrefix
        iconPath = visual.iconPath
    else
        matchName = "Recipe " .. tostring(entry.recipeID or "?")
        -- entry.name is captured directly off the recipe at scan time (see
        -- DataStoreProfessions.lua) and is preferred: recipeID isn't reliably a spell ID
        -- (it can be an item ID depending on profession/client), so the GetSpellInfo/
        -- GetItemInfo(recipeID) guesses below can miss or misresolve it.
        if entry.name and entry.name ~= "" then
            matchName = entry.name
        end
        local spellIcon
        if entry.recipeID then
            local name, _, icon = compatGetSpellInfo(entry.recipeID)
            spellIcon = icon
            if name and matchName == ("Recipe " .. tostring(entry.recipeID or "?")) then
                matchName = name
            end
        end
        if matchName == ("Recipe " .. tostring(entry.recipeID or "?")) and hasItemInfoApi() and entry.recipeID then
            local name = compatGetItemInfo(entry.recipeID)
            if name then
                matchName = name
            end
        end
        -- Crafted item's icon, else the recipe spell's, else (no spell) recipeID as an item.
        iconPath = resolveItemIcon(entry.resultItemID)
            or spellIcon
            or (not entry.resultItemID and resolveItemIcon(entry.recipeID))
            or QUESTION_MARK_ICON
        local profName = entry.professionName or ""
        namePrefix = ""
        if profName ~= "" then
            namePrefix = profName .. ": "
        end
        recipeName = namePrefix .. matchName
        -- No icon yet (item and spell data not loaded): leave it uncached so a later paint retries.
        if iconPath ~= QUESTION_MARK_ICON then
            recipeVisualCache[cacheKey] = {
                name = recipeName,
                matchName = matchName,
                namePrefix = namePrefix,
                iconPath = iconPath,
            }
        end
    end
    local skillText
    local RI = AltArmy and AltArmy.RecipeInfo
    if entry.isGuildCollapsed then
        skillText = "*"
        if RI and RI.IsAvailable and RI.IsAvailable()
            and RI.FormatCollapsedSkillCell and RI.PickHardestDifficulty then
            -- Required skill is recipe-level; difficulty varies by each guildmate's skillRank.
            enrich(entry)
            local difficulties = {}
            local req = entry.recipeSkillRequired
            local chars = entry.guildChars
            if type(chars) == "table" then
                for i = 1, #chars do
                    local c = chars[i]
                    if c then
                        enrich(c)
                        if not req and c.recipeSkillRequired then
                            req = c.recipeSkillRequired
                        end
                        if c.difficulty then
                            difficulties[#difficulties + 1] = c.difficulty
                        end
                    end
                end
            end
            skillText = RI.FormatCollapsedSkillCell(req, RI.PickHardestDifficulty(difficulties))
        end
    elseif RI and RI.FormatSkillCell then
        skillText = RI.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
    else
        skillText = tostring(entry.skillRank or 0)
    end
    entry._aaRecipeBaseName = recipeName
    entry._aaRecipeMatchName = matchName
    entry._aaRecipeNamePrefix = namePrefix or ""
    entry._aaIconPath = iconPath
    entry._aaSkillCellText = skillText
    entry._aaDisplayCached = iconPath ~= QUESTION_MARK_ICON
    return entry
end

--- Build the recipe display name with search highlighting applied only to the searchable
--- recipe name (not the profession prefix like "Enchanting: ").
--- `highlightFn(text, query)` should return `text` unchanged when highlighting is off.
function SP.FormatHighlightedRecipeName(entry, query, highlightFn)
    if not entry then
        return ""
    end
    local matchName = entry._aaRecipeMatchName
    local prefix = entry._aaRecipeNamePrefix
    local fallback = entry._aaRecipeBaseName
        or ("Recipe " .. tostring(entry.recipeID or "?"))
    if not matchName then
        if highlightFn then
            return highlightFn(fallback, query)
        end
        return fallback
    end
    local highlighted = matchName
    if highlightFn then
        highlighted = highlightFn(matchName, query) or matchName
    end
    return (prefix or "") .. highlighted
end

--- True when search settings require recipe data fields on every hit (level/difficulty/source).
--- Profession filter does not need enrichment.
function SP.NeedsRecipeEnrichForFilters(settings)
    if not settings then
        return false
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if not SS then
        return false
    end
    if SS.IsRecipeLevelFilterActive and SS.IsRecipeLevelFilterActive(settings.recipeLevelFilter) then
        return true
    end
    if SS.IsDifficultyFilterActive and SS.IsDifficultyFilterActive(settings.difficultyFilter) then
        return true
    end
    if SS.IsSourceFilterActive and SS.IsSourceFilterActive(settings.sourceFilter) then
        return true
    end
    return false
end

local function RecipeFiltersAvailable()
    local RI = AltArmy and AltArmy.RecipeInfo
    return RI and RI.IsAvailable and RI.IsAvailable()
end

local function FilterRecipesByLevel(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsRecipeLevelFilterActive and not SS.IsRecipeLevelFilterActive(filter) then
        return results
    end
    if not RecipeFiltersAvailable() then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        local req = entry.recipeSkillRequired
        if req == nil then
            out[#out + 1] = entry
        elseif req >= filter.min and req <= filter.max then
            out[#out + 1] = entry
        end
    end
    return out
end
SP._FilterRecipesByLevel = FilterRecipesByLevel

local function FilterRecipesByDifficulty(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsDifficultyFilterActive and not SS.IsDifficultyFilterActive(filter) then
        return results
    end
    if not RecipeFiltersAvailable() then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        local difficulty = entry.difficulty
        if difficulty == nil or filter[difficulty] then
            out[#out + 1] = entry
        end
    end
    return out
end
SP._FilterRecipesByDifficulty = FilterRecipesByDifficulty

local function FilterRecipesBySource(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsSourceFilterActive and not SS.IsSourceFilterActive(filter) then
        return results
    end
    if not RecipeFiltersAvailable() then
        return results
    end
    local RI = AltArmy.RecipeInfo
    local out = {}
    for _, entry in ipairs(results) do
        -- "|"-joined: a recipe stays when any of its sources is enabled
        local source = entry.recipeSource
        if source == nil or RI.SourceIncludes(source, filter) then
            out[#out + 1] = entry
        end
    end
    return out
end
SP._FilterRecipesBySource = FilterRecipesBySource

local function FilterRecipesByProfession(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsProfessionFilterActive and not SS.IsProfessionFilterActive(filter) then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        -- Guild entries already carry a locale-safe profession key; fall back to resolving
        -- from the (localized) profession name for locally scanned recipes.
        local professionKey = entry.professionKey
        if professionKey == nil and SS and SS.ResolveProfessionKey then
            professionKey = SS.ResolveProfessionKey(entry.professionName)
        end
        if professionKey == nil or filter[professionKey] then
            out[#out + 1] = entry
        end
    end
    return out
end
SP._FilterRecipesByProfession = FilterRecipesByProfession

function SP.ApplyRecipeSearchFilters(results, settings)
    if not results or not settings then
        return results
    end
    results = FilterRecipesByProfession(results, settings.professionFilter)
    if not RecipeFiltersAvailable() then
        return results
    end
    results = FilterRecipesByLevel(results, settings.recipeLevelFilter)
    results = FilterRecipesByDifficulty(results, settings.difficultyFilter)
    results = FilterRecipesBySource(results, settings.sourceFilter)
    return results
end
