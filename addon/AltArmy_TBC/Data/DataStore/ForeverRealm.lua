-- AltArmy TBC — realms on WoW Forever, which no longer names them.
-- Forever 1.60.1 (2026-11-20) returns "" or 0 from every realm API (GetRealmName, GetNormalizedRealmName,
-- GetRealmID, GetPlayerInfoByGUID's realm, C_BattleNet's game accounts) so addons can't target layers. Players
-- of one region and ruleset share auction houses, mail and guilds anyway, so on Forever a character's realm is
-- "<region> <ruleset>" ("US PvE"): GetCurrentRegionName and the game rules (C_GameRules: PvP, RP and Hardcore
-- rulesets, as Auctionator reads them). Saved data keyed by the old names ("CAMWOW US2 Realm 5 PvE") or by ""
-- (what an Alt Army before this saved under 1.60.1) moves to that key (Migrate). TBC is untouched: its realms
-- are servers, which GetRealmName still names.
-- luacheck: globals GetRealmName GetCurrentRegionName C_GameRules Enum

if not AltArmy then return end

local FR = {}
AltArmy.ForeverRealm = FR

--- The ruleset each word a realm name has ended in means (the site's versions.RULESETS read the values).
FR.RULESET_WORDS = {
    PvE = "PvE", Normal = "PvE",
    PvP = "PvP",
    RP = "RP", RPPvE = "RP", Roleplay = "RP",
    RPPvP = "RPPvP", ["RP-PvP"] = "RPPvP",
    Hardcore = "Hardcore", HC = "Hardcore",
}

local function isForever()
    local DS = AltArmy.DataStore
    return DS ~= nil and DS.IsWowForever == true
end
FR.IsForever = isForever

local function ruleActive(name)
    local rule = Enum.GameRule[name]
    return rule ~= nil and C_GameRules.IsGameRuleActive(rule) == true
end

--- The ruleset the game rules name: Hardcore whenever its rule is on, else RPPvP, PvP, RP or PvE; nil when the
--- client has no game rules.
function FR.Ruleset()
    if type(C_GameRules) ~= "table" or type(C_GameRules.IsGameRuleActive) ~= "function"
        or type(Enum) ~= "table" or type(Enum.GameRule) ~= "table"
    then
        return nil
    end
    if ruleActive("HardcoreRuleset") then return "Hardcore" end
    local pvp, rp = ruleActive("PvPRuleset"), ruleActive("RPRuleset")
    if pvp and rp then return "RPPvP" end
    if pvp then return "PvP" end
    if rp then return "RP" end
    return "PvE"
end

local function region()
    local r = GetCurrentRegionName and GetCurrentRegionName()
    if type(r) == "string" and r:match("^%a+$") then return r end
    return nil
end

local normalize

--- The current character's group ("US PvE"): the region and the game rules' ruleset, else the realm name the
--- game gives as its group; nil when nothing says.
function FR.Current()
    local r, ruleset = region(), FR.Ruleset()
    if r and ruleset then return r .. " " .. ruleset end
    local name = GetRealmName and GetRealmName()
    if type(name) == "string" and name ~= "" then
        local group = normalize(name, true)
        if group ~= name then return group end
    end
    return nil
end

-- "CAMWOW US2 Realm 5 PvE" (a realm name), "CAMWOW US PvE" (Alt Army's group before 1.60.1), "US PvE".
local REALM_NAME = "^%S+%s+(%a+)%d*%s+Realm%s+%d+%s+(%S+)$"
local CLUSTER_GROUP = "^%u+%s+(%a+)%s+(%S+)$"
local GROUP = "^(%a+)%s+(%S+)$"

--- On Forever, the group a realm name is one with ("CAMWOW US2 Realm 5 PvE" -> "US PvE"); "" (an older Alt Army
--- on 1.60.1) is the current group unless `keepEmpty`; a name of no known ruleset stays as it is. Elsewhere the
--- name itself.
normalize = function(realm, keepEmpty)
    if not isForever() then return realm end
    realm = realm or ""
    if realm == "" then
        if keepEmpty then return "" end
        return FR.Current() or ""
    end
    for _, pattern in ipairs({ REALM_NAME, CLUSTER_GROUP, GROUP }) do
        local r, word = realm:match(pattern)
        local ruleset = r and FR.RULESET_WORDS[word]
        if ruleset then return r .. " " .. ruleset end
    end
    return realm
end
FR.Normalize = normalize

-- ---------------------------------------------------------------------------------------------------------------
-- Migrate: saved data to the group keys. Idempotent, run at every load (older linked accounts and guildmates
-- can still send old names). Keys of "" (an Alt Army before this, on 1.60.1) go where they belong: a character
-- to its copy saved elsewhere (else it waits for its own login, DataStore's GetCurrentCharTable), account-wide
-- entries to `current`, the logged-in group, once it is known.

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

--- Fill what `into` lacks from `from`, tables within tables too; a value `into` has is kept.
local function fill(into, from)
    for k, v in pairs(from) do
        if into[k] == nil then
            into[k] = v
        elseif type(into[k]) == "table" and type(v) == "table" then
            fill(into[k], v)
        end
    end
    return into
end

--- Two copies of one entry: the one with the newer `stamp` is kept, the other fills its gaps.
local function mergeCopies(a, b, stamp)
    if type(a) ~= "table" or type(b) ~= "table" then return a or b end
    if (tonumber(b[stamp]) or 0) > (tonumber(a[stamp]) or 0) then a, b = b, a end
    return fill(a, b)
end
FR._MergeCopies = mergeCopies

local function fillMerge(have, moving)
    if type(have) == "table" and type(moving) == "table" then return fill(have, moving) end
    return have
end

--- Merge for realm tables of entries keyed by GUID: each entry by mergeCopies on `stamp`.
local function entriesMerge(stamp)
    return function(have, moving)
        if type(have) ~= "table" or type(moving) ~= "table" then return have end
        for key, entry in pairs(moving) do
            have[key] = have[key] == nil and entry or mergeCopies(have[key], entry, stamp)
        end
        return have
    end
end

--- Re-key a map with `target(key)` (nil or the key itself: leave it); a key already there is merged by
--- `merge(have, moving)`, which returns the value kept.
local function rekey(map, target, merge)
    if type(map) ~= "table" then return end
    for _, key in ipairs(sortedKeys(map)) do
        local to = target(key)
        if to and to ~= key then
            local v = map[key]
            map[key] = nil
            map[to] = map[to] == nil and v or merge(map[to], v)
        end
    end
end

--- The key a realm-keyed entry moves to: its group; "" goes to `current` (nil while it isn't known).
local function groupOf(current)
    return function(realm)
        local to = normalize(realm, true)
        if to == "" then return current end
        return to
    end
end

local function keepEmpty(realm)
    return normalize(realm, true)
end

--- Set each entry's `field` to the realm table it is in.
local function stampRealms(byRealm, field)
    for realm, list in pairs(type(byRealm) == "table" and byRealm or {}) do
        if realm ~= "" and type(list) == "table" then
            for _, entry in pairs(list) do
                if type(entry) == "table" then entry[field] = realm end
            end
        end
    end
end

--- Characters[realm][guid] (the account's or a linked account's): shards merged into the group, each "" copy
--- joined to the same GUID's copy elsewhere (one saved nowhere else waits for its login). Returns, for the ""
--- copies joined, name -> group, where their per-character settings go.
local function migrateCharacters(chars)
    local homes = {}
    if type(chars) ~= "table" then return homes end
    rekey(chars, keepEmpty, entriesMerge("lastUpdate"))
    local empty = chars[""]
    if type(empty) == "table" then
        for _, guid in ipairs(sortedKeys(empty)) do
            for _, realm in ipairs(sortedKeys(chars)) do
                local others = chars[realm]
                if realm ~= "" and type(others) == "table" and type(others[guid]) == "table" then
                    local char = empty[guid]
                    if type(char) == "table" and type(char.name) == "string" then homes[char.name] = realm end
                    others[guid] = mergeCopies(others[guid], char, "lastUpdate")
                    empty[guid] = nil
                    break
                end
            end
        end
        if next(empty) == nil then chars[""] = nil end
    end
    stampRealms(chars, "realm")
    return homes
end

--- Keys "<realm><sep><rest>": AltArmy.CharKey and GraphLogic.SelectionKey ("\"), CharacterSections' "|". A key
--- of "" goes to the group `homes` gives its name (rest), else `current`.
local function rekeyPrefixed(map, sep, current, homes)
    rekey(map, function(key)
        local cut = key:find(sep, 1, true)
        if not cut then return nil end
        local realm, rest = key:sub(1, cut - 1), key:sub(cut)
        local to
        if realm == "" then
            to = homes and homes[rest:sub(#sep + 1)] or current
        else
            to = normalize(realm, true)
        end
        if not to or to == "" then return nil end
        return to .. rest
    end, fillMerge)
end

local function path(root, ...)
    local t = root
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return type(t) == "table" and t or nil
end

local function migrateGuild(guild, current)
    if type(guild) ~= "table" then return end
    local target = groupOf(current)
    rekey(guild.chars, target, entriesMerge("receivedAt"))
    -- `charRealm` stays as the guildmate reported it: an older Alt Army answers card requests only for that
    -- exact string (its old realm name, or "" on 1.60.1).
    stampRealms(guild.chars, "realm")
    rekey(guild.linkProbes, target, fillMerge)
    rekey(guild.manual, target, fillMerge)
end

--- Rows (an array) whose `field` names a realm.
local function migrateRealmFields(rows, field, current)
    if type(rows) ~= "table" then return end
    local target = groupOf(current)
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row[field]) == "string" then
            row[field] = target(row[field]) or row[field]
        end
    end
end

--- Move `sv`'s Forever data to the group keys. `sv` holds the SavedVariables roots (any may be missing): data,
--- summary, gear, reputation, options, graph, sharing, guild, book, scans, linked. `current` is the logged-in
--- group, or nil while it isn't known (account-wide "" entries wait for it). Nothing happens off Forever.
function FR.Migrate(sv, current)
    if not isForever() or type(sv) ~= "table" then return end
    if current == "" then current = nil end
    local target = groupOf(current)
    local homes = {}
    if type(sv.data) == "table" then
        homes = migrateCharacters(sv.data.Characters)
        local lh = path(sv.data, "OrphanImports", "levelHistory")
        rekey(lh, keepEmpty, fillMerge)
        for realm, byName in pairs(lh or {}) do
            if realm ~= "" then stampRealms({ [realm] = byName }, "realm") end
        end
    end
    for _, map in ipairs({
        path(sv.summary, "characters"), path(sv.gear, "characters"), path(sv.reputation, "characters"),
        path(sv.options, "economy", "currency", "characters"), path(sv.options, "bankAlts"),
        path(sv.options, "bankAltPromptDismissed"), path(sv.graph, "selected"),
    }) do
        rekeyPrefixed(map, "\\", current, homes)
    end
    rekeyPrefixed(path(sv.summary, "collapsedGroups"), "|", current)
    rekeyPrefixed(path(sv.options, "cooldowns", "collapsedGroups"), "|", current)
    if type(sv.sharing) == "table" then
        for _, field in ipairs({ "mains", "displayNames", "onboardingCompleted", "optOut", "nonGuildedOptIn",
            "groupUiPrefs" }) do
            rekey(sv.sharing[field], target, fillMerge)
        end
    end
    migrateGuild(sv.guild, current)
    migrateRealmFields(path(sv.book, "scans"), "realm", current)
    migrateRealmFields(path(sv.book, "summaries"), "realm", current)
    migrateRealmFields(path(sv.scans, "scans"), "realm", current)
    if type(sv.linked) == "table" then
        for _, acct in pairs(path(sv.linked, "accounts") or {}) do
            if type(acct) == "table" then migrateCharacters(acct.Characters) end
        end
        for _, notes in pairs(path(sv.linked, "outMail") or {}) do
            for _, note in pairs(type(notes) == "table" and notes or {}) do
                if type(note) == "table" and type(note.r) == "string" then note.r = target(note.r) or note.r end
            end
        end
    end
end

--- Migrate the addon's own SavedVariables (the globals; ones not loaded stay nil).
function FR.MigrateGlobals(current)
    FR.Migrate({
        data = rawget(_G, "AltArmyTBC_Data"),
        summary = rawget(_G, "AltArmyTBC_SummarySettings"),
        gear = rawget(_G, "AltArmyTBC_GearSettings"),
        reputation = rawget(_G, "AltArmyTBC_ReputationSettings"),
        options = rawget(_G, "AltArmyTBC_Options"),
        graph = rawget(_G, "AltArmyTBC_GraphSettings"),
        sharing = rawget(_G, "AltArmyTBC_SharingSettings"),
        guild = rawget(_G, "AltArmyTBC_GuildData"),
        book = rawget(_G, "AltArmyTBC_AuctionBook"),
        scans = rawget(_G, "AltArmyTBC_AuctionScans"),
        linked = rawget(_G, "AltArmyTBC_LinkedData"),
    }, current)
end
