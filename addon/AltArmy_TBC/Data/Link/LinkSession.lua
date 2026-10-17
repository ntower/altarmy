-- AltArmy TBC — Linked accounts' conversation: who is online, linking, unlinking (linked accounts).
-- Pure: it talks through `env` (LinkTransport in game, a fake in specs):
--   env.send(gameAccountID, msg, prio), env.now(), env.random(), env.isMine(gameAccountID) (that game account
--   is on this Battle.net account, asked of the client afresh: LinkDiscovery), env.myAccountId(),
--   env.regenerateAccountId(), env.self() ({ name, realm, faction, addon, interface, project }),
--   env.ownRoot(), env.currentGuid(), env.prompt(peer, code), env.changed()
-- Nothing from a game account that is not ours is ever answered or kept. A game account id holds for this
-- session only (each client numbers them its own way), so a peer is known by the account id its HELLO
-- carries (AltArmyTBC_Data.accountId). Linking: one client asks (LREQ), the other answers with its own
-- nonce (LACK) and asks its player, both show the same 4-digit code, and the link is kept once the other
-- player accepts (LOK). Unlinking tells the other account (UNL), again at its next HELLO until it answers.
--
-- Messages: HELLO { proto, acct, addon, iface, proj, name, realm, faction, guid, reply, linked }
-- (`guid`: the character that account is logged in on, so the Summary can say it is online)
--           LREQ { n } / LACK { n, n2 } / LOK { n } / LNO { n } / UNL / UNLA
--           BYE (at logout or /reload: that account is offline now; sent with env.sendNow, as nothing queued
--           goes out once the client is closing)

AltArmy = AltArmy or {}
AltArmy.LinkSession = AltArmy.LinkSession or {}
local L = AltArmy.LinkSession

L.PROTO = 1
L.HELLO_AGAIN = 60 -- seconds before saying HELLO again to a game account that hasn't answered
L.REQUEST_EXPIRES = 120 -- a link request not answered in this long is dropped
L.MANIFEST_AGAIN = 30 -- seconds a full manifest to a peer stands for (crossing HELLOs send one once)

local peers = {} -- gameAccountID -> { g, acct, name, realm, faction, addon, iface, proj, helloAt, ... }
local regenerated = false

local function Store()
    return AltArmy.LinkStore
end

local function Sync()
    return AltArmy.LinkSync
end

--- The 4-digit code both screens show for a link request.
function L.Code(n1, n2)
    return string.format("%04d", AltArmy.LinkDomains.Hash(tostring(n1) .. ":" .. tostring(n2)) % 10000)
end

local function hello(env, g, reply, acct)
    local me = env.self()
    local link = acct and Store().GetLink(acct)
    env.send(g, {
        t = "HELLO", proto = L.PROTO, acct = env.myAccountId(), addon = me.addon, iface = me.interface,
        proj = me.project, name = me.name, realm = me.realm, faction = me.faction, guid = env.currentGuid(),
        reply = reply or nil,
        linked = reply and (link ~= nil and link.confirmed == true) or nil,
    }, "NORMAL")
end

local function nonce(env)
    return math.floor(env.random() * 2147483646) + 1
end

--- The game accounts of ours online now (LinkDiscovery candidates): say HELLO to the new ones (and again,
--- now and then, to one that hasn't answered), forget the ones gone, and tell any we unlinked meanwhile.
--- A known peer gets nothing: its changes come as partial manifests (LinkSync), and a full one is sent
--- when a session starts on either side (its HELLO), on linking, and on Sync now.
function L.Discover(env, candidates)
    local now = env.now()
    local seen = {}
    for _, c in ipairs(candidates or {}) do
        local g = c.gameAccountID
        seen[g] = true
        local peer = peers[g]
        if not peer then
            peer = { g = g, name = c.characterName, realm = c.realmName, faction = c.factionName }
            peers[g] = peer
        end
        -- the character it is on now (it may have switched since its HELLO)
        if type(c.playerGuid) == "string" and c.playerGuid ~= "" then
            peer.guid = c.playerGuid
        end
        if not peer.helloAt or (not peer.acct and now - peer.helloAt >= L.HELLO_AGAIN) then
            peer.helloAt = now
            hello(env, g, false)
        elseif peer.acct and Store().IsUnlinkPending(peer.acct) then
            env.send(g, { t = "UNL" }, "NORMAL")
        end
    end
    for g in pairs(peers) do
        if not seen[g] then
            peers[g] = nil
        end
    end
    env.changed()
end

local function startSync(env, peer)
    local now = env.now()
    if Store().IsActive(peer.acct) and (not peer.manAt or now - peer.manAt >= L.MANIFEST_AGAIN) then
        peer.manAt = now
        Sync().Start(env, peer, not peer.gotMan)
    end
end

local function onHello(env, peer, msg)
    if type(msg.acct) ~= "string" or not msg.acct:match("^%x+$") or #msg.acct > 32 then
        return
    end
    if msg.acct == env.myAccountId() then
        -- a copied WTF folder: both accounts have the same id. Make ours anew (once a session) and go on.
        if not regenerated then
            regenerated = true
            env.regenerateAccountId()
            hello(env, peer.g, false)
        end
        return
    end
    peer.acct = msg.acct
    peer.name = type(msg.name) == "string" and msg.name or peer.name
    peer.realm = type(msg.realm) == "string" and msg.realm or peer.realm
    peer.faction = type(msg.faction) == "string" and msg.faction or peer.faction
    peer.addon, peer.iface, peer.proj, peer.proto = msg.addon, msg.iface, msg.proj, msg.proto
    if type(msg.guid) == "string" and msg.guid:match("^Player%-%d+%-%x+$") then
        peer.guid = msg.guid
    end
    local S = Store()
    local link = S.GetLink(msg.acct)
    if link and link.confirmed then
        local me = env.self()
        local why = false
        if msg.proj ~= me.project then
            why = "another game"
        elseif msg.proto ~= L.PROTO then
            why = "Alt Army versions differ: update both"
        end
        if (link.suspended or false) ~= why then
            S.SetLink(msg.acct, { suspended = why })
        end
    end
    if not msg.reply then
        -- a session starts there (a login, a /reload, or it found us): it holds nothing of ours this
        -- session, so both sides send a full manifest
        peer.gotMan, peer.manAt = nil, nil
        hello(env, peer.g, true, msg.acct)
    end
    if S.IsUnlinkPending(msg.acct) then
        env.send(peer.g, { t = "UNL" }, "NORMAL")
    elseif msg.reply and msg.linked == false and link and link.confirmed then
        -- it unlinked us while we were away
        S.Unlink(msg.acct)
        Sync().Forget(msg.acct)
    else
        startSync(env, peer)
    end
    env.changed()
end

--- Ask the game account `g` to link (the player clicked Link).
function L.RequestLink(env, g)
    local peer = peers[g]
    if not peer or not peer.acct then
        return false
    end
    peer.outgoing = { n = nonce(env), at = env.now() }
    peer.declined = nil
    env.send(g, { t = "LREQ", n = peer.outgoing.n }, "NORMAL")
    env.changed()
    return true
end

local function linkFields(env, peer)
    return {
        kind = "own", label = peer.name, confirmed = true, linkedAt = env.now(), suspended = false,
        wowProjectID = peer.proj, interface = peer.iface, addonVersion = peer.addon,
    }
end

local function onLinkRequest(env, peer, msg)
    if type(msg.n) ~= "number" then return end
    local link = Store().GetLink(peer.acct)
    if link and link.confirmed then
        env.send(peer.g, { t = "LOK", n = msg.n }, "NORMAL")
        startSync(env, peer)
        return
    end
    peer.incoming = { n = msg.n, n2 = nonce(env), at = env.now() }
    env.send(peer.g, { t = "LACK", n = msg.n, n2 = peer.incoming.n2 }, "NORMAL")
    env.prompt(peer, L.Code(msg.n, peer.incoming.n2))
    env.changed()
end

--- The player accepted the link request from `g`.
function L.AcceptLink(env, g)
    local peer = peers[g]
    if not (peer and peer.incoming and peer.acct) then
        return false
    end
    Store().SetLink(peer.acct, linkFields(env, peer))
    env.send(g, { t = "LOK", n = peer.incoming.n }, "NORMAL")
    peer.incoming = nil
    startSync(env, peer)
    env.changed()
    return true
end

--- The player turned the link request from `g` down.
function L.DeclineLink(env, g)
    local peer = peers[g]
    if not (peer and peer.incoming) then
        return false
    end
    if peer.acct then
        Store().Decline(peer.acct, env.now())
    end
    env.send(g, { t = "LNO", n = peer.incoming.n }, "NORMAL")
    peer.incoming = nil
    env.changed()
    return true
end

--- Unlink `acct`: forget it here and tell it (now if online, else at its next HELLO).
function L.Unlink(env, acct)
    local S = Store()
    S.Unlink(acct)
    S.MarkUnlinkPending(acct, env.now())
    Sync().Forget(acct)
    for g, peer in pairs(peers) do
        if peer.acct == acct then
            env.send(g, { t = "UNL" }, "NORMAL")
        end
    end
    env.changed()
end

--- Sync now with the online peer of `acct`.
function L.SyncNow(env, acct)
    for _, peer in pairs(peers) do
        if peer.acct == acct then
            peer.manAt = nil
            startSync(env, peer)
            return true
        end
    end
    return false
end

--- This client is logging out (or reloading): tell the linked accounts online that we are gone.
function L.Goodbye(env)
    local sendNow = env.sendNow or env.send
    for g, peer in pairs(peers) do
        if peer.acct and Store().GetLink(peer.acct) then
            sendNow(g, { t = "BYE" }, "ALERT")
        end
    end
end

local HANDLERS = {
    HELLO = onHello,
    BYE = function(env, peer)
        -- offline now; its next login says HELLO and is a new peer
        peers[peer.g] = nil
        env.changed()
    end,
    LREQ = onLinkRequest,
    LACK = function(env, peer, msg)
        if peer.outgoing and msg.n == peer.outgoing.n and type(msg.n2) == "number" then
            peer.outgoing.code = L.Code(msg.n, msg.n2)
            env.changed()
        end
    end,
    LOK = function(env, peer, msg)
        if peer.outgoing and msg.n == peer.outgoing.n then
            Store().SetLink(peer.acct, linkFields(env, peer))
            peer.outgoing = nil
            startSync(env, peer)
            env.changed()
        end
    end,
    LNO = function(env, peer, msg)
        if peer.outgoing and msg.n == peer.outgoing.n then
            peer.outgoing = nil
            peer.declined = true
            env.changed()
        end
    end,
    UNL = function(env, peer)
        Store().Unlink(peer.acct)
        Sync().Forget(peer.acct)
        env.send(peer.g, { t = "UNLA" }, "NORMAL")
        env.changed()
    end,
    UNLA = function(_, peer)
        Store().UnlinkSent(peer.acct)
    end,
}

local SYNC_HANDLERS = { MAN = "OnManifest", REQ = "OnRequest", DATA = "OnData" }

--- A message from game account `g`. Dropped unless `g` is ours; anything but HELLO also waits for its
--- HELLO; sync messages need an active link.
function L.OnMessage(env, g, msg)
    if type(msg) ~= "table" or not env.isMine(g) then
        return
    end
    local peer = peers[g]
    if not peer then
        peer = { g = g }
        peers[g] = peer
    end
    if msg.t ~= "HELLO" and not peer.acct then
        return
    end
    local handler = HANDLERS[msg.t]
    if handler then
        handler(env, peer, msg)
        return
    end
    local syncFn = SYNC_HANDLERS[msg.t]
    if syncFn and Store().IsActive(peer.acct) then
        if msg.t == "MAN" and not msg.partial then
            peer.gotMan = true
            if msg.ask then
                peer.manAt = env.now()
                Sync().Start(env, peer, false)
            end
        end
        Sync()[syncFn](env, peer, msg)
    end
end

--- Every few seconds: requests expire, the sync asks again for what didn't come.
function L.Tick(env)
    local now = env.now()
    local active = {}
    for _, peer in pairs(peers) do
        if peer.outgoing and now - peer.outgoing.at > L.REQUEST_EXPIRES then
            peer.outgoing = nil
            env.changed()
        end
        if peer.incoming and now - peer.incoming.at > L.REQUEST_EXPIRES then
            peer.incoming = nil
            env.changed()
        end
        if peer.acct and Store().IsActive(peer.acct) then
            active[peer.acct] = peer
        end
    end
    Sync().Tick(env, active)
end

--- What the Sharing page lists: the links (online or not), then the accounts of ours online not linked.
function L.View()
    local S = Store()
    local out = {}
    local online = {}
    for _, peer in pairs(peers) do
        if peer.acct then online[peer.acct] = peer end
    end
    for acct, link in pairs(S.Links()) do
        local peer = online[acct]
        local chars = 0
        for _ in pairs(S.CharacterRealms(acct)) do chars = chars + 1 end
        out[#out + 1] = {
            acct = acct, linked = link.confirmed == true, label = S.Label(acct), online = peer ~= nil,
            g = peer and peer.g, suspended = link.suspended or nil, characters = chars,
            lastSyncAt = link.lastSyncAt, syncing = Sync().IsSyncing(acct), refused = peer and peer.lastRefused,
        }
    end
    for g, peer in pairs(peers) do
        if peer.acct and not S.GetLink(peer.acct) then
            out[#out + 1] = {
                acct = peer.acct, g = g, linked = false, online = true, label = peer.name,
                realm = peer.realm, faction = peer.faction,
                waitingCode = peer.outgoing and (peer.outgoing.code or "...") or nil,
                incoming = peer.incoming ~= nil, declined = peer.declined,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.linked ~= b.linked then return a.linked end
        return (a.label or "") < (b.label or "")
    end)
    return out
end

--- Whether the character `guid` is the one a linked account of ours is logged in on right now.
function L.IsOnline(guid)
    if type(guid) ~= "string" then
        return false
    end
    for _, peer in pairs(peers) do
        if peer.acct and peer.guid == guid and Store().IsActive(peer.acct) then
            return true
        end
    end
    return false
end

--- The online peer with game account `g`.
function L.Peer(g)
    return peers[g]
end

-- Specs.
function L._Reset()
    peers = {}
    regenerated = false
end

return L
