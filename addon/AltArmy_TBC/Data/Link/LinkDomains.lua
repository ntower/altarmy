-- AltArmy TBC — What a linked account is sent of each character, by domain (linked accounts).
-- Pure. A character travels as units, one per domain: each a copy of the character's fields of that domain
-- (the DataStore's own shape, so every DS getter reads a linked character as it reads ours) plus the
-- `dataVersions` those fields are at. Sender and receiver share this whitelist: a field not listed here is
-- never sent and never kept.
--
-- Of levelHistory only what the Graphs tab draws travels (the "levels" unit: each milestone's playedTotal and
-- playedLevel, Dom.TrimLevels); never its per-milestone gear, zone, money or deaths log. Never sent:
-- Auctions/Bids/lastAuctionScan (auction house data), cooldownGroupChoice and professionsNeedingRecipeScan
-- (this client's UI state), and of mail the subject, body and sender (only what is held: items, money,
-- expiry). Account-wide data travels as the
-- "meta" unit: the currency and faction names a linked character's numbers need (filled in where we lack
-- them, never overwriting ours). Options, guild data, auction scans and every other SavedVariable are never
-- sent.

AltArmy = AltArmy or {}
AltArmy.LinkDomains = AltArmy.LinkDomains or {}
local Dom = AltArmy.LinkDomains

--- Domain -> { fields = character fields, versions = the dataVersions keys that go with them }, in the order
--- a sync sends them (what the Summary shows first).
Dom.ORDER = { "identity", "equipment", "professions", "containers", "reputations", "currencies", "talents",
    "lockouts", "mail", "levels" }
Dom.DOMAINS = {
    identity = {
        fields = { "name", "realm", "guid", "faction", "race", "raceFile", "class", "classFile", "sex", "level",
            "xp", "xpMax", "restXP", "money", "played", "playedThisLevel", "lastLogout", "lastUpdate",
            "guildName", "bagInfo", "bankInfo", "Prof1", "Prof2" },
        versions = { "character", "guildMembership" },
    },
    containers = {
        fields = { "Containers", "bagsScannedAt", "bankScannedAt" },
        versions = { "containers" },
    },
    equipment = {
        fields = { "Inventory", "gearScores" },
        versions = { "equipment", "gearScores" },
    },
    professions = {
        fields = { "Professions", "ProfCooldownExpiry", "lastTransmute", "lastSphere", "cooldownSpecs" },
        versions = { "professions" },
    },
    reputations = {
        fields = { "Reputations" },
        versions = { "reputations" },
    },
    currencies = {
        fields = { "Currencies", "CurrencyList" },
        versions = { "currencies", "currencyList" },
    },
    talents = {
        fields = { "talents", "legacyTalents" },
        versions = { "talents", "legacyTalents" },
    },
    lockouts = {
        fields = { "RaidLockouts", "lastLockoutScan" },
        versions = {},
    },
    mail = {
        fields = { "Mails", "MailCache", "lastMailCheck" },
        versions = { "mail" },
    },
    -- the Graphs tab's: levelHistory trimmed to milestones' played times (Dom.TrimLevels)
    levels = {
        fields = { "levelHistory" },
        versions = { "levelHistory" },
    },
}
Dom.MAX_LEVEL = 200 -- a milestone's level above this is not a level
-- Account-wide names the characters' numbers refer to.
Dom.META_FIELDS = { "CurrencyMeta", "ReputationFactionNames" }
-- Of a mail entry (Mails, MailCache), what is never sent.
Dom.MAIL_PRIVATE = { subject = true, sender = true, text = true, body = true }

local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = copy(x)
    end
    return out
end
Dom.Copy = copy

local function stripMail(list)
    if type(list) ~= "table" then
        return list
    end
    for _, entry in pairs(list) do
        if type(entry) == "table" then
            for k in pairs(Dom.MAIL_PRIVATE) do
                entry[k] = nil
            end
        end
    end
    return list
end

local function playedSeconds(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v or nil
end

--- What the Graphs tab needs of a level history: { milestones = { [level] = { playedTotal, playedLevel } } };
--- nil when it has no milestone with either.
function Dom.TrimLevels(levelHistory)
    local milestones = type(levelHistory) == "table" and levelHistory.milestones
    if type(milestones) ~= "table" then
        return nil
    end
    local out, any = {}, false
    for level, m in pairs(milestones) do
        if type(level) == "number" and level >= 1 and level <= Dom.MAX_LEVEL and level == math.floor(level)
            and type(m) == "table" then
            local total, inLevel = playedSeconds(m.playedTotal), playedSeconds(m.playedLevel)
            if total or inLevel then
                out[level] = { playedTotal = total, playedLevel = inLevel }
                any = true
            end
        end
    end
    return any and { milestones = out } or nil
end

--- The unit of `domain` for `char`: a copy of its fields and their dataVersions; nil for an unknown domain.
function Dom.Extract(char, domain)
    local def = Dom.DOMAINS[domain]
    if not def or type(char) ~= "table" then
        return nil
    end
    local unit = {}
    if domain == "levels" then
        unit.levelHistory = Dom.TrimLevels(char.levelHistory) -- never a copy of the whole history
    else
        for _, f in ipairs(def.fields) do
            if char[f] ~= nil then
                unit[f] = copy(char[f])
            end
        end
    end
    if domain == "mail" then
        stripMail(unit.Mails)
        stripMail(unit.MailCache)
    end
    local versions = {}
    local have = type(char.dataVersions) == "table" and char.dataVersions or {}
    for _, k in ipairs(def.versions) do
        if have[k] ~= nil then
            versions[k] = have[k]
        end
    end
    unit.dataVersions = versions
    return unit
end

--- The "meta" unit of an account's data root (AltArmyTBC_Data): the names its characters' numbers need.
function Dom.ExtractMeta(root)
    local unit = {}
    for _, f in ipairs(Dom.META_FIELDS) do
        if type(root) == "table" and type(root[f]) == "table" then
            unit[f] = copy(root[f])
        end
    end
    return unit
end

-- A stable hash of a value: tables walked in sorted key order (numbers before strings), so the same data
-- hashes the same on both sides whatever order pairs() gives. Only tells changes apart: the link itself
-- vouches for who sent it.
local PRIME = 2147483647

local function mix(h, s)
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % PRIME
    end
    return (h * 33 + 1) % PRIME
end

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta < tb
    end
    if ta == "number" or ta == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

local function hashValue(h, v)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, keyLess)
        h = mix(h, "{")
        for _, k in ipairs(keys) do
            h = hashValue(h, k)
            h = hashValue(h, v[k])
        end
        return mix(h, "}")
    end
    if t == "number" then
        return mix(h, "n" .. string.format("%.17g", v))
    end
    return mix(h, t:sub(1, 1) .. tostring(v))
end

--- A number that changes when `v` does.
function Dom.Hash(v)
    return hashValue(5381, v)
end

return Dom
