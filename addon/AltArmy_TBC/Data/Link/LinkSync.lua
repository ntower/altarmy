-- AltArmy TBC — Keeping a linked account's characters up to date (linked accounts).
-- Pure: what it sends goes through env.send (LinkTransport in game, a fake in specs). Once two accounts are
-- linked and both online, each sends a manifest: per character, the hash of each domain's unit
-- (LinkDomains), and the hash of its account-wide names (meta). The other asks (REQ) for what differs from
-- what it holds, and gets one DATA message per character with the units asked for (a character's units
-- travel together: Battle.net delivers messages in any order, and a character starts with its identity).
-- A character missing from a full manifest is gone there and is removed here. What isn't answered within
-- REQUEST_WAIT (plus a little per character) is asked for again, up to TRIES times. When this character
-- changes (bags, money, ...), a partial manifest of it alone follows CHANGE_DEBOUNCE seconds later.
--
-- Messages: MAN { c = { [guid] = { r = realm, h = { [domain] = hash } } }, mh = meta hash, partial, ask }
--           (`ask`: the sender has no manifest of ours yet this session; Battle.net may have delivered ours
--           before the link was kept there, so it is sent again)
--           REQ { c = { [guid] = { domain, ... } }, meta = true }
--           DATA { g = guid, r = realm, u = { [domain] = unit }, h = { [domain] = hash } } or
--           DATA { meta = unit, mh = hash }

AltArmy = AltArmy or {}
AltArmy.LinkSync = AltArmy.LinkSync or {}
local Y = AltArmy.LinkSync

Y.REQUEST_WAIT = 30 -- seconds, plus PER_CHARACTER_WAIT for each character asked for
Y.PER_CHARACTER_WAIT = 5
Y.TRIES = 3
Y.CHARS_PER_REQUEST = 8
Y.CHANGE_DEBOUNCE = 20
Y.DELETE_DEBOUNCE = 20 -- after the last character deleted here, a full manifest tells linked accounts
Y.GUID_PATTERN = "^Player%-%d+%-%x+$"

local outstanding = {} -- accountId -> { g, chars = { [guid] = { domain = true } }, meta, deadline, tries }
local changeDueAt -- when the pending partial manifest of this character goes out
local fullDueAt -- when the pending full manifest (characters deleted here) goes out

local function Dom()
    return AltArmy.LinkDomains
end

local function Store()
    return AltArmy.LinkStore
end

-- Our characters that can be sent: those with a GUID (one saved before GUIDs can't be told apart).
local function ownCharacters(root, onlyGuid)
    local out = {}
    for realm, chars in pairs(type(root) == "table" and root.Characters or {}) do
        for key, char in pairs(chars) do
            local guid = type(char) == "table" and char.guid
            if type(guid) == "string" and guid:match(Y.GUID_PATTERN) and guid == key and char.name
                and (not onlyGuid or guid == onlyGuid) then
                out[#out + 1] = { realm = realm, guid = guid, char = char }
            end
        end
    end
    return out
end

--- The manifest of `root` (AltArmyTBC_Data): every character's (or `onlyGuid`'s) domain hashes.
function Y.Manifest(root, onlyGuid)
    local man = { t = "MAN", c = {}, partial = onlyGuid ~= nil or nil }
    for _, e in ipairs(ownCharacters(root, onlyGuid)) do
        local h = {}
        for _, domain in ipairs(Dom().ORDER) do
            h[domain] = Dom().Hash(Dom().Extract(e.char, domain))
        end
        man.c[e.guid] = { r = e.realm, h = h }
    end
    if not onlyGuid then
        man.mh = Dom().Hash(Dom().ExtractMeta(root))
    end
    return man
end

local function sendRequests(env, peer, want)
    local batch, n = { t = "REQ", c = {} }, 0
    if want.meta then
        batch.meta = true
    end
    for guid, domains in pairs(want.chars) do
        local list = {}
        for _, d in ipairs(Dom().ORDER) do
            if domains[d] then list[#list + 1] = d end
        end
        batch.c[guid] = list
        n = n + 1
        if n >= Y.CHARS_PER_REQUEST then
            env.send(peer.g, batch, "NORMAL")
            batch, n = { t = "REQ", c = {} }, 0
        end
    end
    if n > 0 or batch.meta then
        env.send(peer.g, batch, "NORMAL")
    end
end

local function countChars(want)
    local n = 0
    for _ in pairs(want.chars) do n = n + 1 end
    return n
end

--- Send our full manifest to `peer` (a LinkSession peer: { g, acct }); `ask` for theirs back.
function Y.Start(env, peer, ask)
    local man = Y.Manifest(env.ownRoot())
    man.ask = ask or nil
    env.send(peer.g, man, "NORMAL")
end

--- A manifest from `peer`: ask for what we don't hold as it is, forget characters it no longer has.
function Y.OnManifest(env, peer, msg)
    local S = Store()
    if type(msg.c) ~= "table" then
        return
    end
    local held = S.Hashes(peer.acct)
    local want = { chars = {} }
    local listed, count = {}, 0
    for guid, info in pairs(msg.c) do
        count = count + 1
        if count > AltArmy.LinkValidate.MAX_CHARACTERS then
            break
        end
        if type(guid) == "string" and guid:match(Y.GUID_PATTERN) and type(info) == "table"
            and type(info.r) == "string" and type(info.h) == "table" then
            listed[guid] = true
            local have = held[guid] or {}
            for _, d in ipairs(Dom().ORDER) do
                if info.h[d] ~= nil and info.h[d] ~= have[d] then
                    want.chars[guid] = want.chars[guid] or {}
                    want.chars[guid][d] = true
                end
            end
            -- a character we don't hold starts with who it is
            if want.chars[guid] and not held[guid] then
                want.chars[guid].identity = true
            end
        end
    end
    if not msg.partial then
        for guid, realm in pairs(S.CharacterRealms(peer.acct)) do
            if not listed[guid] then
                S.RemoveCharacter(peer.acct, realm, guid)
            end
        end
        if msg.mh ~= nil and msg.mh ~= S.MetaHash(peer.acct) then
            want.meta = true
        end
    end
    -- what is already asked for (manifests cross: each side may send two) is not asked for again
    local pending = outstanding[peer.acct]
    if pending then
        for guid, domains in pairs(want.chars) do
            local asked = pending.chars[guid]
            for d in pairs(asked or {}) do
                domains[d] = nil
            end
            if next(domains) == nil then
                want.chars[guid] = nil
            end
        end
        if pending.meta then
            want.meta = nil
        end
    end
    if next(want.chars) == nil and not want.meta then
        if not pending then
            S.SetLink(peer.acct, { lastSyncAt = env.now() })
        end
        return
    end
    if pending then
        for guid, domains in pairs(want.chars) do
            pending.chars[guid] = pending.chars[guid] or {}
            for d in pairs(domains) do
                pending.chars[guid][d] = true
            end
        end
        pending.meta = pending.meta or want.meta
    else
        outstanding[peer.acct] = {
            g = peer.g,
            chars = want.chars,
            meta = want.meta,
            tries = 1,
            deadline = env.now() + Y.REQUEST_WAIT + Y.PER_CHARACTER_WAIT * countChars(want),
        }
    end
    sendRequests(env, peer, want)
    env.changed()
end

local function findOwn(root, guid)
    return ownCharacters(root, guid)[1]
end

--- A request from `peer`: one DATA per character asked for, and the meta unit if asked.
function Y.OnRequest(env, peer, msg)
    local root = env.ownRoot()
    if msg.meta then
        local meta = Dom().ExtractMeta(root)
        env.send(peer.g, { t = "DATA", meta = meta, mh = Dom().Hash(meta) }, "BULK")
    end
    for guid, domains in pairs(type(msg.c) == "table" and msg.c or {}) do
        local e = type(guid) == "string" and findOwn(root, guid)
        if e and type(domains) == "table" then
            local units, hashes = {}, {}
            for _, d in ipairs(domains) do
                local unit = Dom().Extract(e.char, d)
                if unit then
                    units[d] = unit
                    hashes[d] = Dom().Hash(unit)
                end
            end
            env.send(peer.g, { t = "DATA", g = guid, r = e.realm, u = units, h = hashes }, "BULK")
        end
    end
end

--- Units from `peer`: kept (each checked by LinkStore.Receive), identity first.
function Y.OnData(env, peer, msg)
    local S = Store()
    local now = env.now()
    local pending = outstanding[peer.acct]
    local got = false
    if msg.meta ~= nil then
        got = S.ReceiveMeta(peer.acct, msg.meta, env.ownRoot(), msg.mh) or got
        if pending then pending.meta = nil end
    end
    if type(msg.g) == "string" and type(msg.r) == "string" and type(msg.u) == "table" then
        local hashes = type(msg.h) == "table" and msg.h or {}
        for _, d in ipairs(Dom().ORDER) do
            if msg.u[d] ~= nil then
                local ok, why = S.Receive(peer.acct, msg.r, msg.g, d, msg.u[d], now, hashes[d])
                got = ok or got
                if not ok then
                    peer.lastRefused = d .. ": " .. tostring(why)
                end
                if pending and pending.chars[msg.g] then
                    pending.chars[msg.g][d] = nil
                end
            end
        end
        if pending and pending.chars[msg.g] and next(pending.chars[msg.g]) == nil then
            pending.chars[msg.g] = nil
        end
    end
    if pending and next(pending.chars) == nil and not pending.meta then
        outstanding[peer.acct] = nil
    end
    if got then
        S.SetLink(peer.acct, { lastSyncAt = now })
    end
    env.changed()
end

--- Whether we are still waiting for units from `acct`.
function Y.IsSyncing(acct)
    return outstanding[acct] ~= nil
end

--- This character changed: send its partial manifest CHANGE_DEBOUNCE seconds after the first change (later
--- ones ride along: bags change often, and pushing the time back each time could put it off forever).
function Y.NoteLocalChange(env)
    changeDueAt = changeDueAt or (env.now() + Y.CHANGE_DEBOUNCE)
end

--- Characters were deleted here: a full manifest (which tells the other side what is gone) goes to the
--- online linked accounts DELETE_DEBOUNCE seconds after the last deletion, so deleting several sends one.
function Y.NoteDeletion(env)
    fullDueAt = env.now() + Y.DELETE_DEBOUNCE
end

--- Every few seconds: ask again for what didn't come, and send this character's changes.
--- `peers`: accountId -> online peer, for the links that are active.
function Y.Tick(env, peers)
    local now = env.now()
    for acct, pending in pairs(outstanding) do
        if now >= pending.deadline then
            local peer = peers[acct]
            if peer and pending.tries < Y.TRIES then
                pending.tries = pending.tries + 1
                pending.g = peer.g
                pending.deadline = now + Y.REQUEST_WAIT + Y.PER_CHARACTER_WAIT * countChars(pending)
                sendRequests(env, peer, pending)
            else
                outstanding[acct] = nil
                if peer then
                    peer.lastRefused = "some data did not arrive; it is asked for again next time"
                end
                env.changed()
            end
        end
    end
    if fullDueAt and now >= fullDueAt then
        fullDueAt = nil
        if next(peers) then
            local man = Y.Manifest(env.ownRoot())
            for _, peer in pairs(peers) do
                env.send(peer.g, man, "NORMAL")
            end
        end
    end
    if changeDueAt and now >= changeDueAt then
        changeDueAt = nil
        local guid = env.currentGuid()
        if guid then
            local man = Y.Manifest(env.ownRoot(), guid)
            for _, peer in pairs(peers) do
                env.send(peer.g, man, "NORMAL")
            end
        end
    end
end

--- Forget what we were waiting for from `acct` (unlinked).
function Y.Forget(acct)
    outstanding[acct] = nil
end

-- Specs.
function Y._Reset()
    outstanding = {}
    changeDueAt = nil
    fullDueAt = nil
end

return Y
