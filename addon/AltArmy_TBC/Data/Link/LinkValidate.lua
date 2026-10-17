-- AltArmy TBC — Checking what a linked account sent before it is kept (linked accounts).
-- Pure. Everything a unit holds is untrusted until checked here: only the domain's fields (LinkDomains)
-- are kept, and a unit is refused whole, never patched, when any value breaks a rule:
--   - values are strings, finite numbers, booleans or tables; keys strings or numbers
--   - strings at most MAX_STRING bytes; tables at most MAX_DEPTH deep; at most MAX_NODES values a unit
--   - a field that holds an item link names an item (|Hitem:)
--   - the identity unit names a character: a GUID (Player-<server>-<hex>) that is the key it came under, a
--     name and the realm it came under
--   - its data versions are ones this addon reads: newer than ours means the sender's addon is newer, and
--     the unit waits for this one to update (reason "newer")
-- Returns the unit to keep, or nil and why.

AltArmy = AltArmy or {}
AltArmy.LinkValidate = AltArmy.LinkValidate or {}
local V = AltArmy.LinkValidate

V.MAX_STRING = 1024
V.MAX_DEPTH = 7
V.MAX_NODES = 40000
V.MAX_CHARACTERS = 64 -- per linked account
V.GUID_PATTERN = "^Player%-%d+%-%x+$"

local function Domains()
    return AltArmy.LinkDomains
end

local function isFinite(n)
    return n == n and n ~= math.huge and n ~= -math.huge
end

-- Walk `v`; false and why on the first value that breaks a rule. `count` is a one-slot box.
local function check(v, depth, count)
    count[1] = count[1] + 1
    if count[1] > V.MAX_NODES then
        return false, "tooBig"
    end
    local t = type(v)
    if t == "string" then
        if #v > V.MAX_STRING then
            return false, "longString"
        end
        return true
    end
    if t == "number" then
        if not isFinite(v) then
            return false, "badNumber"
        end
        return true
    end
    if t == "boolean" then
        return true
    end
    if t ~= "table" then
        return false, "badType"
    end
    if depth >= V.MAX_DEPTH then
        return false, "tooDeep"
    end
    for k, x in pairs(v) do
        local kt = type(k)
        if kt == "number" then
            if not isFinite(k) then
                return false, "badKey"
            end
        elseif kt ~= "string" or #k > V.MAX_STRING then
            return false, "badKey"
        end
        local ok, why = check(x, depth + 1, count)
        if not ok then
            return false, why
        end
    end
    return true
end

--- Whether `v` (any value) keeps to the generic rules; false and why if not.
function V.CheckValue(v)
    return check(v, 0, { 0 })
end

local LINK_FIELDS = { bagLink = true, link = true }

-- Item links where the DataStore keeps them: a slot's or bag's `link`/`bagLink`, an equipped slot.
local function linksOk(v, inInventory)
    if type(v) ~= "table" then
        return true
    end
    for k, x in pairs(v) do
        if type(x) == "string" and (LINK_FIELDS[k] or inInventory) and not x:find("|Hitem:", 1, true) then
            return false
        end
        if type(x) == "table" and not linksOk(x, false) then
            return false
        end
    end
    return true
end

--- The unit to keep of `domain` for the character `charKey` on `realm`, as `localVersions` (DATA_VERSIONS)
--- reads it; nil and why if it is refused.
function V.Unit(domain, unit, charKey, realm, localVersions)
    local def = Domains().DOMAINS[domain]
    if not def then
        return nil, "unknownDomain"
    end
    if type(unit) ~= "table" then
        return nil, "badType"
    end
    local ok, why = V.CheckValue(unit)
    if not ok then
        return nil, why
    end
    local out = {}
    for _, f in ipairs(def.fields) do
        out[f] = unit[f]
    end
    local versions = type(unit.dataVersions) == "table" and unit.dataVersions or {}
    out.dataVersions = {}
    for _, k in ipairs(def.versions) do
        local v = versions[k]
        if v ~= nil then
            if type(v) ~= "number" then
                return nil, "badVersion"
            end
            if v > ((localVersions or {})[k] or 0) then
                return nil, "newer"
            end
            out.dataVersions[k] = v
        end
    end
    if domain == "identity" then
        if type(out.guid) ~= "string" or not out.guid:match(V.GUID_PATTERN) or out.guid ~= charKey then
            return nil, "badGuid"
        end
        if type(out.name) ~= "string" or out.name == "" then
            return nil, "noName"
        end
        if out.realm ~= realm then
            return nil, "wrongRealm"
        end
    end
    if domain == "mail" then
        for _, field in ipairs({ "Mails", "MailCache" }) do
            local list = out[field]
            for _, entry in pairs(type(list) == "table" and list or {}) do
                if type(entry) == "table" then
                    for k in pairs(Domains().MAIL_PRIVATE) do
                        entry[k] = nil
                    end
                end
            end
        end
    end
    if not linksOk(out.Containers, false) or not linksOk(out.Inventory, true) then
        return nil, "badLink"
    end
    return out
end

--- The account-wide names to keep from a "meta" unit; nil and why if it is refused.
function V.Meta(unit)
    if type(unit) ~= "table" then
        return nil, "badType"
    end
    local ok, why = V.CheckValue(unit)
    if not ok then
        return nil, why
    end
    local out = {}
    for _, f in ipairs(Domains().META_FIELDS) do
        if type(unit[f]) == "table" then
            out[f] = unit[f]
        end
    end
    return out
end

return V
