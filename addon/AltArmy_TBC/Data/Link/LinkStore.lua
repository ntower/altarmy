-- AltArmy TBC — Linked accounts' characters, as received (linked accounts).
-- Owns the SavedVariable AltArmyTBC_LinkedData, apart from AltArmyTBC_Data so nothing that reads our own
-- characters (guild sharing, mail alerts, the profit export, the website's upload) ever sees a linked one:
--   version = 1
--   links[accountId]    = { kind = "own", label, confirmed, linkedAt, lastSyncAt, wowProjectID, interface,
--                           addonVersion, suspended (why, or nil) }
--   declined[accountId] = when we said no
--   pendingUnlinks[accountId] = when we unlinked, until that account hears of it
--   accounts[accountId] = { Characters = { [realm] = { [guid] = char } }, meta = { CurrencyMeta, ... },
--                           hashes = { [guid] = { [domain] = hash } }, receivedAt }
-- A character is kept in the DataStore's own shape (LinkDomains), so DS getters read it as they read ours.
-- Only units LinkValidate passed are applied. Characters of a link that is not confirmed, or suspended
-- (another game, an addon too old), are kept but not listed.

AltArmy = AltArmy or {}
AltArmy.LinkStore = AltArmy.LinkStore or {}
local S = AltArmy.LinkStore

S.VERSION = 1

local linkOf = setmetatable({}, { __mode = "k" }) -- character table -> accountId

local function root()
    return rawget(_G, "AltArmyTBC_LinkedData")
end

function S.Ensure()
    local data = root()
    if type(data) ~= "table" or data.version ~= S.VERSION then
        data = { version = S.VERSION }
        _G.AltArmyTBC_LinkedData = data
    end
    data.links = type(data.links) == "table" and data.links or {}
    data.declined = type(data.declined) == "table" and data.declined or {}
    data.pendingUnlinks = type(data.pendingUnlinks) == "table" and data.pendingUnlinks or {}
    data.accounts = type(data.accounts) == "table" and data.accounts or {}
    return data
end

local function account(id)
    local data = S.Ensure()
    local acct = data.accounts[id]
    if not acct then
        acct = { Characters = {}, meta = {}, hashes = {} }
        data.accounts[id] = acct
    end
    return acct
end

local function changed()
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    local DS = AltArmy.DataStore
    if DS and DS.FireLinkedDataChanged then
        DS:FireLinkedDataChanged()
    end
end

--- Record (or update) a link. `fields` as in links[accountId] (see the file's head).
function S.SetLink(id, fields)
    local data = S.Ensure()
    local link = data.links[id] or { kind = "own" }
    for k, v in pairs(fields or {}) do
        link[k] = v
    end
    data.links[id] = link
    data.declined[id] = nil
    if link.confirmed then
        data.pendingUnlinks[id] = nil -- linked again: nothing to tell it
    end
    changed()
    return link
end

function S.GetLink(id)
    return S.Ensure().links[id]
end

--- accountId -> link, every link we have.
function S.Links()
    return S.Ensure().links
end

function S.HasLinks()
    return next(S.Ensure().links) ~= nil
end

--- Whether a link's characters are listed: confirmed and not suspended.
function S.IsActive(id)
    local link = S.Ensure().links[id]
    return link ~= nil and link.confirmed == true and not link.suspended
end

--- Keep one validated unit of `domain` for the character `guid` on `realm` (LinkValidate.Unit's result).
function S.ApplyUnit(id, realm, guid, domain, unit, hash, now)
    local def = AltArmy.LinkDomains.DOMAINS[domain]
    if not def or type(unit) ~= "table" then
        return false
    end
    local acct = account(id)
    acct.Characters[realm] = acct.Characters[realm] or {}
    local char = acct.Characters[realm][guid]
    if not char then
        if domain ~= "identity" then
            return false -- a character starts with who it is
        end
        char = { dataVersions = {} }
        acct.Characters[realm][guid] = char
    end
    for _, f in ipairs(def.fields) do
        char[f] = unit[f]
    end
    char.dataVersions = char.dataVersions or {}
    for _, k in ipairs(def.versions) do
        char.dataVersions[k] = unit.dataVersions and unit.dataVersions[k] or nil
    end
    acct.hashes[guid] = acct.hashes[guid] or {}
    acct.hashes[guid][domain] = hash
    acct.receivedAt = now
    linkOf[char] = id
    changed()
    return true
end

--- Take one unit as it arrived from `id`: checked (LinkValidate), then kept. Returns true, or false and why.
--- What every way in (a sync, the debug harness) goes through. `hash` is the sender's for the unit (what its
--- manifests will say), else ours is taken.
function S.Receive(id, realm, guid, domain, unit, now, hash)
    local V, DS = AltArmy.LinkValidate, AltArmy.DataStore
    local versions = DS and DS._DATA_VERSIONS or {}
    local acct = S.Ensure().accounts[id]
    local known = acct and acct.Characters[realm] and acct.Characters[realm][guid]
    if not known then
        local count = 0
        for _, chars in pairs(acct and acct.Characters or {}) do
            for _ in pairs(chars) do count = count + 1 end
        end
        if count >= V.MAX_CHARACTERS then
            return false, "tooManyCharacters"
        end
    end
    local kept, why = V.Unit(domain, unit, guid, realm, versions)
    if not kept then
        return false, why
    end
    if type(hash) ~= "number" then
        hash = AltArmy.LinkDomains.Hash(kept)
    end
    if not S.ApplyUnit(id, realm, guid, domain, kept, hash, now) then
        return false, "noIdentity"
    end
    if DS and DS._MigrateDataVersions then
        DS._MigrateDataVersions({ Characters = S.Ensure().accounts[id].Characters })
    end
    return true
end

--- Take a "meta" unit as it arrived from `id` (checked first); fills in names our account lacks.
function S.ReceiveMeta(id, unit, ownRoot, hash)
    local meta, why = AltArmy.LinkValidate.Meta(unit)
    if not meta then
        return false, why
    end
    S.ApplyMeta(id, meta, ownRoot)
    account(id).metaHash = hash
    return true
end

--- The hash of the meta unit we hold from `id`.
function S.MetaHash(id)
    local acct = S.Ensure().accounts[id]
    return acct and acct.metaHash or nil
end

--- The characters we hold from `id`: { [guid] = realm }.
function S.CharacterRealms(id)
    local out = {}
    local acct = S.Ensure().accounts[id]
    for realm, chars in pairs(acct and acct.Characters or {}) do
        for guid in pairs(chars) do
            out[guid] = realm
        end
    end
    return out
end

--- Unlinked here, to be told to `id` when it is next online (UnlinkSent once it heard).
function S.MarkUnlinkPending(id, now)
    S.Ensure().pendingUnlinks[id] = now or true
end

function S.IsUnlinkPending(id)
    return S.Ensure().pendingUnlinks[id] ~= nil
end

function S.UnlinkSent(id)
    S.Ensure().pendingUnlinks[id] = nil
end

--- Keep a validated "meta" unit, and fill in the names our own account lacks (never overwriting ours).
function S.ApplyMeta(id, meta, ownRoot)
    local acct = account(id)
    acct.meta = meta or {}
    for f, names in pairs(acct.meta) do
        if type(ownRoot) == "table" and type(names) == "table" then
            ownRoot[f] = ownRoot[f] or {}
            for k, v in pairs(names) do
                if ownRoot[f][k] == nil then
                    ownRoot[f][k] = v
                end
            end
        end
    end
end

--- Forget a character the linked account no longer has.
function S.RemoveCharacter(id, realm, guid)
    local acct = S.Ensure().accounts[id]
    if not acct or not acct.Characters[realm] then
        return
    end
    acct.Characters[realm][guid] = nil
    if next(acct.Characters[realm]) == nil then
        acct.Characters[realm] = nil
    end
    if acct.hashes then
        acct.hashes[guid] = nil
    end
    changed()
end

--- Unlink: forget the link and everything received from it.
function S.Unlink(id)
    local data = S.Ensure()
    data.links[id] = nil
    data.accounts[id] = nil
    changed()
end

--- Remember that we said no to a link with `id` (no prompt again until asked).
function S.Decline(id, now)
    S.Ensure().declined[id] = now or true
end

function S.IsDeclined(id)
    return S.Ensure().declined[id] ~= nil
end

--- The hashes we hold of what `id` sent: { [guid] = { [domain] = hash } }.
function S.Hashes(id)
    local acct = S.Ensure().accounts[id]
    return acct and acct.hashes or {}
end

--- Every character of every active link: fn(realm, guid, char, accountId); return true to stop.
function S.ForEachCharacter(fn)
    local data = S.Ensure()
    for id, acct in pairs(data.accounts) do
        if S.IsActive(id) then
            for realm, chars in pairs(acct.Characters or {}) do
                for guid, char in pairs(chars) do
                    linkOf[char] = id
                    if fn(realm, guid, char, id) == true then
                        return
                    end
                end
            end
        end
    end
end

--- A character `id` sent, by GUID (its key) or name, on `realm`; nil if we hold none (or the link isn't
--- active).
function S.FindCharacter(id, name, realm)
    if not (id and name and realm) or not S.IsActive(id) then
        return nil
    end
    local acct = S.Ensure().accounts[id]
    local chars = acct and acct.Characters and acct.Characters[realm]
    if not chars then
        return nil
    end
    local char = chars[name]
    if not char then
        for _, c in pairs(chars) do
            if type(c) == "table" and c.name == name then
                char = c
                break
            end
        end
    end
    if char then
        linkOf[char] = id
    end
    return char
end

--- The link a character table came from (nil for our own characters).
function S.LinkOf(char)
    return char and linkOf[char] or nil
end

--- A link's name for the UI: its label, else "Linked account".
function S.Label(id)
    local link = S.Ensure().links[id]
    return link and link.label or "Linked account"
end

--- When we last received anything from `id`.
function S.ReceivedAt(id)
    local acct = S.Ensure().accounts[id]
    return acct and acct.receivedAt or nil
end

-- Specs.
function S._Reset()
    _G.AltArmyTBC_LinkedData = nil
    for k in pairs(linkOf) do
        linkOf[k] = nil
    end
end

return S
