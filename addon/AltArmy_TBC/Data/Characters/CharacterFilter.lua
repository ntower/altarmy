-- AltArmy TBC — Which characters a tab lists: its realm filter, level filter and class filter.
-- Summary, Gear, Reputation and Currency each keep one as `settings.filter` (their settings panels edit it,
-- UI/CharacterFilterControls.lua); the Summary's realm filter is also every other tab's
-- (GlobalRealmFilter.lua). Pure apart from the WoW globals Context() reads.
--
-- filter = {
--   version = 1,
--   scope   = { otherFaction, otherRealms, linked },  -- RealmFilter.inScope's: this realm and faction always
--   levelMin = 1, levelMax = 60,                       -- shown levels, both ends included (1..max level)
--   classes = { WARRIOR = true, ... },                  -- false hides
-- }
-- Every known key holds an explicit boolean. A filter from before the level range kept `levels`, a map of
-- level buckets ("1-9", ..., "50-59", "60"; false hid one): Ensure turns it into the range from the lowest
-- shown bucket to the highest. A tab's first filter is seeded from the old global scope
-- (AltArmyTBC_Options.characterScope, else realmFilter == "all"), which nothing writes any more.

AltArmy = AltArmy or {}
AltArmy.CharacterFilter = AltArmy.CharacterFilter or {}
local CF = AltArmy.CharacterFilter

CF.VERSION = 1

CF.SCOPE_KEYS = { "own", "otherFaction", "otherRealms", "linked" }
CF.SCOPE_LABELS = {
    own = "This realm, this faction",
    otherFaction = "This realm, opposite faction",
    otherRealms = "Other realms",
    linked = "Include linked accounts",
}
CF.LOCKED_SCOPE_KEYS = { own = true }

-- The classes both clients have, in the game's order.
CF.CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

--- The running client's level cap (60 on WoW Forever, 70 on TBC).
function CF.MaxLevel()
    local DS = AltArmy.DataStore
    return (DS and DS.MAX_LEVEL) or 70
end

--- A level bucket key of the old level filter ("10-19", "60") as its lowest and highest level.
local function bucketBounds(key)
    local lo, hi = tostring(key):match("^(%d+)%-(%d+)$")
    if lo then
        return tonumber(lo), tonumber(hi)
    end
    local n = tonumber(key)
    return n, n
end

--- The level range an old `levels` bucket map showed: its lowest shown bucket to its highest (nil when none).
local function rangeFromBuckets(levels)
    local lo, hi
    for key, on in pairs(levels) do
        local a, b = bucketBounds(key)
        if on ~= false and a then
            lo = lo and math.min(lo, a) or a
            hi = hi and math.max(hi, b) or b
        end
    end
    return lo, hi
end

--- Whole levels, inside 1..maxLevel, min no higher than max.
local function clampRange(lo, hi, maxLevel)
    lo = math.max(1, math.min(maxLevel, math.floor(tonumber(lo) or 1)))
    hi = math.max(lo, math.min(maxLevel, math.floor(tonumber(hi) or maxLevel)))
    return lo, hi
end

--- The level range as its settings row words it: "All", "42" or "10–59".
function CF.FormatLevelRange(lo, hi, maxLevel)
    maxLevel = maxLevel or CF.MaxLevel()
    if lo <= 1 and hi >= maxLevel then
        return "All"
    end
    if lo == hi then
        return tostring(lo)
    end
    return lo .. "–" .. hi
end

--- A class's name as the client says it ("Mage"), else the class token in title case.
function CF.ClassLabel(classFile)
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local name = type(names) == "table" and names[classFile]
    if name and name ~= "" then
        return name
    end
    classFile = classFile or ""
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- The class's name in its class colour, for the class filter's rows.
function CF.ClassRowLabel(classFile)
    local CC = AltArmy.ClassColor
    local name = CF.ClassLabel(classFile)
    if CC and CC.wrapName then
        return CC.wrapName(name, classFile)
    end
    return name
end

--- The scope a tab starts from: the old global scope's choice, else this realm and faction only.
local function seedScope()
    local root = rawget(_G, "AltArmyTBC_Options")
    local old = type(root) == "table" and root.characterScope
    if type(old) == "table" then
        return { otherFaction = old.otherFaction == true, otherRealms = old.otherRealms == true,
            linked = old.linked ~= false }
    end
    local all = type(root) == "table" and root.realmFilter == "all"
    return { otherFaction = all, otherRealms = all, linked = true }
end

local function fillKeys(map, keys)
    for _, key in ipairs(keys) do
        map[key] = map[key] ~= false
    end
end

--- `settings.filter`, made or completed: a level range inside 1..maxLevel and every class present.
--- @param opts table|nil { maxLevel }
--- @return table the filter (the saved table)
function CF.Ensure(settings, opts)
    local maxLevel = opts and opts.maxLevel or CF.MaxLevel()
    local f = settings.filter
    if type(f) ~= "table" or f.version ~= CF.VERSION then
        f = { version = CF.VERSION, scope = seedScope(), classes = {} }
        settings.filter = f
    end
    local scope = type(f.scope) == "table" and f.scope or {}
    f.scope = scope
    scope.otherFaction = scope.otherFaction == true
    scope.otherRealms = scope.otherRealms == true
    scope.linked = scope.linked ~= false
    if type(f.levelMin) ~= "number" or type(f.levelMax) ~= "number" then
        local lo, hi
        if type(f.levels) == "table" then
            lo, hi = rangeFromBuckets(f.levels)
        end
        f.levelMin, f.levelMax = lo or 1, hi or maxLevel
    end
    f.levels = nil
    f.levelMin, f.levelMax = clampRange(f.levelMin, f.levelMax, maxLevel)
    f.classes = type(f.classes) == "table" and f.classes or {}
    fillKeys(f.classes, CF.CLASS_ORDER)
    return f
end

--- A saved character's faction, for a list entry that doesn't carry one (by realm and name).
function CF.FactionLookup()
    local DS = AltArmy.DataStore
    local cache = {}
    return function(e)
        local name = e.name or e.characterName or e.charName
        if not (DS and DS.GetCharacter and name and e.realm) then
            return nil
        end
        local key = e.realm .. "|" .. name
        if cache[key] == nil then
            local char = DS.GetCharacterAny and DS:GetCharacterAny(name, e.realm) or DS:GetCharacter(name, e.realm)
            cache[key] = char and char.faction or false
        end
        return cache[key] or nil
    end
end

--- Where the player is: { currentRealm, currentFaction, maxLevel, factionOf }.
function CF.Context(currentRealm)
    local getRealm = rawget(_G, "GetRealmName")
    local factionGroup = rawget(_G, "UnitFactionGroup")
    return {
        currentRealm = currentRealm or (getRealm and getRealm()) or "",
        currentFaction = factionGroup and factionGroup("player") or nil,
        maxLevel = CF.MaxLevel(),
        factionOf = CF.FactionLookup(),
    }
end

--- Whether the realm filter shows `entry`.
function CF.InScope(entry, filter, ctx)
    local faction = entry.faction
    if faction == nil and ctx.factionOf then
        faction = ctx.factionOf(entry)
    end
    return AltArmy.RealmFilter.inScope(entry, faction, filter.scope, ctx.currentRealm, ctx.currentFaction)
end

--- Whether every filter shows `entry`. An unknown level or class passes.
function CF.Matches(entry, filter, ctx)
    if not CF.InScope(entry, filter, ctx) then
        return false
    end
    if entry.level ~= nil then
        local level = math.max(1, math.floor(tonumber(entry.level) or 1))
        local maxLevel = ctx.maxLevel or CF.MaxLevel()
        -- the top of the range at the cap shows anyone over it too (a level the client never reports)
        if level < filter.levelMin or (level > filter.levelMax and filter.levelMax < maxLevel) then
            return false
        end
    end
    local classFile = entry.classFile
    if classFile and classFile ~= "" and filter.classes[classFile] == false then
        return false
    end
    return true
end

--- `list` narrowed to the filter (a new array, order kept).
--- @param opts table|nil { keep = fn(entry) -> true to list it whatever the filter; scopeOnly = realm filter alone }
function CF.FilterList(list, filter, ctx, opts)
    local keep = opts and opts.keep
    local test = (opts and opts.scopeOnly) and CF.InScope or CF.Matches
    local out = {}
    for i = 1, #(list or {}) do
        local e = list[i]
        if (keep and keep(e)) or test(e, filter, ctx) then
            out[#out + 1] = e
        end
    end
    return out
end

--- Whether other realms' characters show (names then carry their realm).
function CF.ShowsOtherRealms(filter)
    return filter and filter.scope and filter.scope.otherRealms == true or false
end

--- The realm filter as the dropdown reads it.
function CF.ScopeFilterMap(filter)
    local s = filter.scope
    return { own = true, otherFaction = s.otherFaction, otherRealms = s.otherRealms, linked = s.linked }
end

function CF.SetScope(filter, key, on)
    if key == "otherFaction" or key == "otherRealms" or key == "linked" then
        filter.scope[key] = on and true or false
    end
end

--- Sets the level range (whole levels, kept inside 1..maxLevel, min no higher than max).
function CF.SetLevelRange(filter, lo, hi, maxLevel)
    filter.levelMin, filter.levelMax = clampRange(lo, hi, maxLevel or CF.MaxLevel())
end

function CF.SetClass(filter, key, on)
    filter.classes[key] = on and true or false
end

--- "All" when every key is on, "None" when none is, else the chosen ones' labels.
function CF.FormatMultiSelectSummary(keys, labels, map)
    local chosen = {}
    for _, key in ipairs(keys) do
        if map[key] ~= false then
            chosen[#chosen + 1] = labels[key] or key
        end
    end
    if #chosen == #keys then
        return "All"
    end
    if #chosen == 0 then
        return "None"
    end
    return table.concat(chosen, ", ")
end

--- "None" when nothing is chosen, else the chosen ones' labels (the pin and hide dropdowns).
function CF.FormatChosenSummary(keys, labels, map)
    local chosen = {}
    for _, key in ipairs(keys) do
        if map[key] then
            chosen[#chosen + 1] = labels[key] or key
        end
    end
    if #chosen == 0 then
        return "None"
    end
    return table.concat(chosen, ", ")
end

CF.DIVIDER_PREFIX = "divider:"

--- The realm filter's keys: linked accounts only when there are any.
function CF.ScopeKeys(hasLinks)
    if hasLinks then
        return CF.SCOPE_KEYS
    end
    return { "own", "otherFaction", "otherRealms" }
end

--- The realm filter's dropdown summary: "All" when every option it offers is on, "All realms" when all
--- but linked accounts are, else "This faction", or "This realm" with the opposite faction, then
--- ", Other realms" and ", Linked accounts" (the latter only when there are links).
function CF.FormatScopeSummary(filter, hasLinks)
    local s = filter.scope
    if s.otherFaction and s.otherRealms then
        if not hasLinks or s.linked then
            return "All"
        end
        return "All realms"
    end
    local parts = { s.otherFaction and "This realm" or "This faction" }
    if s.otherRealms then
        parts[#parts + 1] = "Other realms"
    end
    if hasLinks and s.linked then
        parts[#parts + 1] = "Linked accounts"
    end
    return table.concat(parts, ", ")
end

--- `list` in groups by realm and faction, in the Summary's section order (ctx.currentRealm,
--- ctx.currentFaction: this realm and faction first), each group by name A to Z: { { entry, ... }, ... }.
function CF.GroupByRealmFaction(list, ctx)
    local sorted = {}
    for i = 1, #(list or {}) do sorted[i] = list[i] end
    table.sort(sorted, function(a, b)
        local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return (a.realm or ""):lower() < (b.realm or ""):lower()
    end)
    local groups = {}
    for g, section in ipairs(AltArmy.CharacterSections.Group(sorted, ctx and ctx.currentRealm,
        ctx and ctx.currentFaction)) do
        groups[g] = section.entries
    end
    return groups
end

--- Whether a CharacterChoices key is the divider between two groups.
function CF.IsDividerKey(key)
    return type(key) == "string" and key:sub(1, #CF.DIVIDER_PREFIX) == CF.DIVIDER_PREFIX
end

--- The name of a GroupByRealmFaction group ("Realm — Faction"), for its divider.
function CF.GroupLabel(group)
    local e = group and group[1] or {}
    return AltArmy.CharacterSections.GroupLabel(e.realm, e.faction)
end

--- The characters a pin or hide dropdown lists: keys (CharKey), grouped by realm and faction in the
--- Summary's section order (opts.currentRealm, opts.currentFaction: this realm and faction first), by name
--- A to Z within each, a divider key ("divider:n", labelled with the group's name) before each group; plain
--- labels ("Name", or "Name — Realm"
--- when there are several realms) and the entry for each key. A character is listed once (a linked
--- account's copy shares its settings); opts.skip(entry) leaves one out.
function CF.CharacterChoices(list, opts)
    local skip = opts and opts.skip
    local entries, byKey = {}, {}
    for i = 1, #(list or {}) do
        local e = list[i]
        local key = AltArmy.CharKey(e.name, e.realm)
        if not byKey[key] and not (skip and skip(e)) then
            byKey[key] = e
            entries[#entries + 1] = e
        end
    end
    local RF = AltArmy.RealmFilter
    local several = RF and RF.hasMultipleRealms and RF.hasMultipleRealms(entries) or false
    local keys, labels = {}, {}
    local groups = CF.GroupByRealmFaction(entries, opts)
    for g, group in ipairs(groups) do
        local divider = CF.DIVIDER_PREFIX .. g
        keys[#keys + 1] = divider
        labels[divider] = CF.GroupLabel(group)
        for _, e in ipairs(group) do
            local key = AltArmy.CharKey(e.name, e.realm)
            keys[#keys + 1] = key
            labels[key] = several and ((e.name or "") .. " — " .. (e.realm or "")) or (e.name or "")
        end
    end
    return keys, labels, byKey
end
