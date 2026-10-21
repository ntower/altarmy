-- AltArmy TBC — Realm filter and display name helpers (multi-realm support).

AltArmy.RealmFilter = AltArmy.RealmFilter or {}

local RF = AltArmy.RealmFilter

-- WoW Forever's mega-server: GetRealmName() says "<cluster> <region> Realm <n> <ruleset>" ("CAMWOW US2 Realm 3
-- PvE"), and the realms of one cluster, region and ruleset are coalesced (UnitRealmRelationship 2: party, mail,
-- trade and the auction house reach across them), so the addon treats them as one realm. Elsewhere, and for a
-- name of another shape, a realm is its name.
local FOREVER_REALM = "^(.-)%s+Realm%s+%d+%s+(%S+)$"

local function isForever()
    local DS = AltArmy.DataStore
    return DS ~= nil and DS.IsWowForever == true
end

--- The realm `realm` is one with: on Forever its cluster, region and ruleset ("CAMWOW US2 PvE"), else itself.
--- Compare realms with this (or sameRealm), never a character's storage realm: that stays the name it reports.
function RF.realmGroup(realm)
    realm = realm or ""
    if isForever() then
        local shard, ruleset = realm:match(FOREVER_REALM)
        if shard then
            return shard .. " " .. ruleset
        end
    end
    return realm
end

--- Whether characters on realms `a` and `b` can play together (the same realm, or coalesced ones on Forever).
function RF.sameRealm(a, b)
    return RF.realmGroup(a) == RF.realmGroup(b)
end

--- The realm as shown: on Forever its group without the cluster ("US2 PvE"), else the name.
function RF.realmLabel(realm)
    local group = RF.realmGroup(realm)
    if group ~= (realm or "") then
        return (group:gsub("^%S+%s+", ""))
    end
    return group
end

--- Filter a list of entries (with .realm) by realm.
--- @param list table[] Array of entries with at least .realm
--- @param realmFilter "all"|"currentRealm"
--- @param currentRealm string Current realm name (e.g. from GetRealmName())
--- @return table[] New array; when realmFilter == "currentRealm" only entries where
--- entry.realm == currentRealm; when "all" a copy of list.
function RF.filterListByRealm(list, realmFilter, currentRealm)
    if not list then return {} end
    if realmFilter ~= "currentRealm" then
        local out = {}
        for i = 1, #list do out[i] = list[i] end
        return out
    end
    local out = {}
    for i = 1, #list do
        local e = list[i]
        if RF.sameRealm(e.realm, currentRealm) then
            out[#out + 1] = e
        end
    end
    return out
end

--- Whether one entry is shown under `scope` (GlobalRealmFilter's: otherFaction, otherRealms, linked). This
--- realm's characters of the current faction always are; the other faction here and every faction on other
--- realms each by their toggle; a linked account's (entry.linkId) only with `linked` too. An entry whose
--- faction isn't known counts as the current faction's.
--- @param faction string|nil the entry's faction ("Horde" | "Alliance"), when known
function RF.inScope(entry, faction, scope, currentRealm, currentFaction)
    scope = scope or {}
    if entry.linkId ~= nil and not scope.linked then
        return false
    end
    if not RF.sameRealm(entry.realm, currentRealm) then
        return scope.otherRealms and true or false
    end
    if faction and faction ~= "" and currentFaction and currentFaction ~= "" and faction ~= currentFaction then
        return scope.otherFaction and true or false
    end
    return true
end

--- Filter a list of entries (with .realm, and .faction or a `factionOf(entry)` lookup) by `scope`.
--- @return table[] a new array
function RF.filterListByScope(list, scope, currentRealm, currentFaction, factionOf)
    local out = {}
    for i = 1, #(list or {}) do
        local e = list[i]
        local faction = e.faction
        if faction == nil and factionOf then
            faction = factionOf(e)
        end
        if RF.inScope(e, faction, scope, currentRealm, currentFaction) then
            out[#out + 1] = e
        end
    end
    return out
end

--- Return true if list has entries from more than one distinct realm (coalesced ones count as one).
--- @param list table[] Array of entries with at least .realm
--- @return boolean
function RF.hasMultipleRealms(list)
    if not list or #list == 0 then return false end
    local seen = {}
    for i = 1, #list do
        seen[RF.realmGroup(list[i].realm)] = true
    end
    local count = 0
    for _ in pairs(seen) do
        count = count + 1
        if count > 1 then return true end
    end
    return false
end

--- Plain display name: name only or "name-realm".
--- @param name string
--- @param realm string|nil
--- @param showRealmSuffix boolean
--- @return string
function RF.formatCharacterDisplayName(name, realm, showRealmSuffix)
    name = name or ""
    if not showRealmSuffix then return name end
    return name .. "-" .. RF.realmLabel(realm)
end

--- Colored display string for UI: |cFFrrggbbname|r or |cFFrrggbbname|r-realm.
--- @param name string
--- @param realm string|nil
--- @param showRealmSuffix boolean
--- @param r number 0-1 red
--- @param g number 0-1 green
--- @param b number 0-1 blue
--- @return string
function RF.formatCharacterDisplayNameColored(name, realm, showRealmSuffix, r, g, b)
    name = name or ""
    r = (r == nil) and 1 or r
    g = (g == nil) and 0.82 or g
    b = (b == nil) and 0 or b
    local rr = math.floor(math.max(0, math.min(1, r)) * 255)
    local gg = math.floor(math.max(0, math.min(1, g)) * 255)
    local bb = math.floor(math.max(0, math.min(1, b)) * 255)
    local hex = string.format("|cFF%02x%02x%02x%s|r", rr, gg, bb, name)
    if showRealmSuffix then
        hex = hex .. "-" .. RF.realmLabel(realm)
    end
    return hex
end

--- UI string with RAID class color on the name and gray " — realm" when showRealmSuffix (matches Cooldowns tab).
--- @param name string
--- @param realm string|nil
--- @param showRealmSuffix boolean
--- @param classFile string|nil e.g. "MAGE"
--- @param includeBankIcon boolean|nil default true; when false, omit inline bank icon markup
--- @return string WoW escape sequences for FontString / GameTooltip
function RF.formatColoredCharacterNameRealm(name, realm, showRealmSuffix, classFile, includeBankIcon)
    name = name or ""
    local CC = AltArmy.ClassColor
    local namePart = CC and CC.formatName and CC.formatName(name, classFile)
        or ("|cffffffff" .. name .. "|r")
    local result
    if showRealmSuffix and realm and realm ~= "" then
        result = namePart .. "|cffaaaaaa — " .. RF.realmLabel(realm) .. "|r"
    else
        result = namePart
    end
    local BA = AltArmy.BankAlt
    if includeBankIcon ~= false and BA and BA.Is and BA.Is(name, realm) and BA.IconMarkup then
        return BA.IconMarkup() .. " " .. result
    end
    return result
end
