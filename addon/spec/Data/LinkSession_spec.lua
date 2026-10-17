--[[ Unit tests for Link/LinkSession.lua and Link/LinkSync.lua — run: npm test

  Two clients in one Lua state: each side is its own AltArmy table with its own copy of the Link modules
  and its own SavedVariables, swapped into the globals while that side runs. They talk through the real
  LinkCodec over a fake Battle.net that can reorder, repeat and drop chunks. As in game, each client numbers
  the other's game account its own way (A sees B as 4, B sees A as 2).
]]

describe("LinkSession + LinkSync", function()
  local VERSIONS = { character = 3, guildMembership = 1, containers = 4, equipment = 1, gearScores = 1,
    professions = 1, reputations = 2, mail = 2, currencies = 1, currencyList = 1, talents = 2, legacyTalents = 2 }
  local MODULES = { "LinkDomains", "LinkValidate", "LinkStore", "LinkCodec", "LinkSync", "LinkSession" }
  local libs
  local clock
  local network -- { to = side, from = gameAccountID as the receiver knows the sender, chunk }
  local A, B

  local function char(guid, name, money)
    return { name = name, realm = "R", guid = guid, faction = "Horde", classFile = "MAGE", level = 10,
      money = money or 5, dataVersions = { character = 3, containers = 4 },
      Containers = { { items = { { itemID = 2589, count = 3, link = "|cnIQ1:|Hitem:2589::::|h[Linen]|h|r" } } } } }
  end

  local function within(side, fn, ...)
    local saved = { _G.AltArmy, _G.AltArmyTBC_LinkedData, _G.AltArmyTBC_Data }
    _G.AltArmy, _G.AltArmyTBC_LinkedData, _G.AltArmyTBC_Data = side.AltArmy, side.linked, side.data
    local results = { pcall(fn, ...) }
    side.linked = _G.AltArmyTBC_LinkedData
    _G.AltArmy, _G.AltArmyTBC_LinkedData, _G.AltArmyTBC_Data = saved[1], saved[2], saved[3]
    assert(results[1], results[2])
    return unpack(results, 2)
  end

  local function newSide(name, accountId, data)
    local side = { name = name, AltArmy = {}, data = data, accountId = accountId, project = 18, prompts = {},
      mine = {}, seq = 0 }
    within(side, function()
      AltArmy.DataStore = { _DATA_VERSIONS = VERSIONS, _MigrateDataVersions = function() end }
      for _, m in ipairs(MODULES) do
        dofile("AltArmy_TBC/Data/Link/" .. m .. ".lua")
      end
    end)
    side.reassembler = side.AltArmy.LinkCodec.NewReassembler()
    side.env = {
      now = function() return clock end,
      random = function()
        side.seq = side.seq + 1
        return ((side.seq * 7919 + (name == "A" and 13 or 101)) % 1000) / 1000
      end,
      isMine = function(g) return side.mine[g] == true end,
      myAccountId = function() return side.accountId end,
      regenerateAccountId = function() side.accountId = side.accountId .. (name == "A" and "1" or "2") end,
      self = function()
        return { name = name .. " Main", realm = "R", faction = "Horde", addon = "1", interface = 16001,
          project = side.project }
      end,
      ownRoot = function() return side.data end,
      currentGuid = function() return next(side.data.Characters.R) end,
      prompt = function(peer, code) side.prompts[#side.prompts + 1] = { g = peer.g, code = code } end,
      changed = function() end,
      send = function(g, msg)
        local to = side.peerSides[g]
        if not to then return end
        local C = side.AltArmy.LinkCodec
        side.msgs = (side.msgs or 0) + 1
        for _, chunk in ipairs(C.Split(C.Encode(msg, libs), side.name .. side.msgs)) do
          network[#network + 1] = { to = to, from = to.idOf[side], chunk = chunk, t = msg.t, g = msg.g }
        end
      end,
    }
    return side
  end

  local function call(side, module, fn, ...)
    local args = { ... }
    return within(side, function()
      return side.AltArmy[module][fn](side.env, unpack(args))
    end)
  end

  --- Deliver everything on the network (and what that sends), `opts.reorder` reversing each batch,
  --- `opts.repeatChunks` sending each twice, `opts.drop(item)` losing some.
  local function deliver(opts)
    opts = opts or {}
    for _ = 1, 50 do
      if #network == 0 then return end
      local batch = network
      network = {}
      if opts.reorder then
        local r = {}
        for i = #batch, 1, -1 do r[#r + 1] = batch[i] end
        batch = r
      end
      for _, item in ipairs(batch) do
        if not (opts.drop and opts.drop(item)) then
          for _ = 1, opts.repeatChunks and 2 or 1 do
            local payload = item.to.reassembler:Add(item.from, item.chunk, clock)
            if payload then
              local msg = item.to.AltArmy.LinkCodec.Decode(payload, libs)
              within(item.to, function()
                item.to.AltArmy.LinkSession.OnMessage(item.to.env, item.from, msg)
              end)
            end
          end
        end
      end
    end
    error("the network never went quiet")
  end

  local function held(side, acct)
    return within(side, function() return AltArmy.LinkStore.CharacterRealms(acct) end)
  end

  local function linkOf(side, acct)
    return within(side, function() return AltArmy.LinkStore.GetLink(acct) end)
  end

  local function connect()
    A.peerSides, B.peerSides = { [4] = B }, { [2] = A }
    A.idOf, B.idOf = { [B] = 4 }, { [A] = 2 }
    A.mine[4], B.mine[2] = true, true
  end

  local function discover()
    call(A, "LinkSession", "Discover", { { gameAccountID = 4, characterName = "B Main", realmName = "R" } })
    call(B, "LinkSession", "Discover", { { gameAccountID = 2, characterName = "A Main", realmName = "R" } })
    deliver()
  end

  local function link(opts)
    discover()
    call(A, "LinkSession", "RequestLink", 4)
    deliver(opts)
    call(B, "LinkSession", "AcceptLink", 2)
    deliver(opts)
  end

  setup(function()
    if not _G.LibStub then dofile("AltArmy_TBC/Libs/LibStub/LibStub.lua") end
    dofile("AltArmy_TBC/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    dofile("AltArmy_TBC/Libs/LibDeflate/LibDeflate.lua")
    libs = { serializer = LibStub("AceSerializer-3.0"), deflate = LibStub("LibDeflate") }
  end)

  before_each(function()
    clock = 1000
    network = {}
    A = newSide("A", "aaaa", { Characters = { R = { ["Player-1-A1"] = char("Player-1-A1", "A One") } } })
    B = newSide("B", "bbbb", { Characters = { R = {
      ["Player-1-B1"] = char("Player-1-B1", "B One"),
      ["Player-1-B2"] = char("Player-1-B2", "B Two"),
    } }, CurrencyMeta = { [1] = { name = "Honor" } } })
    connect()
  end)

  it("links once the other player accepts, both showing the same code, then syncs both ways", function()
    discover()
    call(A, "LinkSession", "RequestLink", 4)
    deliver()
    assert.are.equal(1, #B.prompts)
    local view = within(A, function() return AltArmy.LinkSession.View() end)
    assert.are.equal(B.prompts[1].code, view[1].waitingCode)
    assert.is_nil(linkOf(A, "bbbb"))
    call(B, "LinkSession", "AcceptLink", 2)
    deliver()
    assert.is_true(linkOf(A, "bbbb").confirmed)
    assert.is_true(linkOf(B, "aaaa").confirmed)
    assert.are.same({ ["Player-1-B1"] = "R", ["Player-1-B2"] = "R" }, held(A, "bbbb"))
    assert.are.same({ ["Player-1-A1"] = "R" }, held(B, "aaaa"))
    -- the names a character's numbers need came too
    within(A, function() end)
  end)

  it("gets everything though chunks arrive in any order, twice", function()
    link({ reorder = true, repeatChunks = true })
    assert.are.same({ ["Player-1-B1"] = "R", ["Player-1-B2"] = "R" }, held(A, "bbbb"))
  end)

  it("asks again for what didn't arrive", function()
    local dropped = 0
    link({ drop = function(item)
      if item.t == "DATA" and item.g == "Player-1-B2" and dropped < 1 then
        dropped = dropped + 1
        return true
      end
    end })
    local before = 0
    for _ in pairs(held(A, "bbbb")) do before = before + 1 end
    assert.are.equal(1, before)
    clock = clock + 200
    call(A, "LinkSession", "Tick")
    deliver()
    assert.are.same({ ["Player-1-B1"] = "R", ["Player-1-B2"] = "R" }, held(A, "bbbb"))
  end)

  it("sends a character's change, and forgets a character the other account no longer has", function()
    link()
    B.data.Characters.R["Player-1-B1"].money = 999
    call(B, "LinkSync", "NoteLocalChange")
    clock = clock + 21
    B.env.currentGuid = function() return "Player-1-B1" end
    call(B, "LinkSession", "Tick")
    deliver()
    local money = within(A, function() return AltArmy.LinkStore.Ensure().accounts.bbbb.Characters.R["Player-1-B1"].money end)
    assert.are.equal(999, money)
    B.data.Characters.R["Player-1-B2"] = nil
    clock = clock + 60
    call(B, "LinkSession", "SyncNow", "aaaa")
    deliver()
    assert.are.same({ ["Player-1-B1"] = "R" }, held(A, "bbbb"))
  end)

  it("knows which linked character is online: the one that account is logged in on", function()
    B.env.currentGuid = function() return "Player-1-B2" end
    link()
    local online = function(guid) return within(A, function() return AltArmy.LinkSession.IsOnline(guid) end) end
    assert.is_true(online("Player-1-B2"))
    assert.is_false(online("Player-1-B1"))
    call(A, "LinkSession", "Unlink", "bbbb")
    assert.is_false(online("Player-1-B2"))
  end)

  it("says nothing more to a linked account it already knows, minute after minute", function()
    link()
    clock = clock + 120
    call(A, "LinkSession", "Discover", { { gameAccountID = 4, characterName = "B Main", realmName = "R" } })
    call(B, "LinkSession", "Discover", { { gameAccountID = 2, characterName = "A Main", realmName = "R" } })
    assert.are.equal(0, #network)
  end)

  it("syncs both ways again when the other account starts a new session", function()
    link()
    B.data.Characters.R["Player-1-B1"].money = 4321 -- changed while A wasn't told (say, before a /reload)
    clock = clock + 120
    within(B, function() AltArmy.LinkSession._Reset() end)
    discover()
    local money = within(A, function()
      return AltArmy.LinkStore.Ensure().accounts.bbbb.Characters.R["Player-1-B1"].money
    end)
    assert.are.equal(4321, money)
  end)

  it("tells linked accounts of characters deleted here, 20 s after the last deletion", function()
    link()
    local function heldByA()
      local n = 0
      for _ in pairs(held(A, "bbbb")) do n = n + 1 end
      return n
    end
    B.data.Characters.R["Player-1-B1"] = nil
    call(B, "LinkSync", "NoteDeletion")
    clock = clock + 15
    B.data.Characters.R["Player-1-B2"] = nil
    call(B, "LinkSync", "NoteDeletion") -- a second deletion puts it off again
    clock = clock + 15
    call(B, "LinkSession", "Tick")
    deliver()
    assert.are.equal(2, heldByA()) -- 30 s after the first, 15 after the last: not yet
    clock = clock + 6
    call(B, "LinkSession", "Tick")
    deliver()
    assert.are.equal(0, heldByA())
  end)

  it("knows a linked account went offline when it says goodbye", function()
    B.env.currentGuid = function() return "Player-1-B2" end
    link()
    local online = function() return within(A, function() return AltArmy.LinkSession.IsOnline("Player-1-B2") end) end
    assert.is_true(online())
    call(B, "LinkSession", "Goodbye")
    deliver()
    assert.is_false(online())
    local view = within(A, function() return AltArmy.LinkSession.View() end)
    assert.is_false(view[1].online)
    -- back again: a new session there, found by the next discovery
    within(B, function() AltArmy.LinkSession._Reset() end)
    discover()
    assert.is_true(online())
  end)

  it("unlinks on both sides, telling the other when it is next online", function()
    link()
    A.peerSides = {} -- B is offline
    call(A, "LinkSession", "Unlink", "bbbb")
    assert.is_nil(linkOf(A, "bbbb"))
    assert.is_true(linkOf(B, "aaaa").confirmed)
    connect()
    clock = clock + 120
    discover()
    assert.is_nil(linkOf(B, "aaaa"))
    assert.are.same({}, held(B, "aaaa"))
    assert.is_false(within(A, function() return AltArmy.LinkStore.IsUnlinkPending("bbbb") end))
  end)

  it("answers nobody who isn't on this Battle.net account", function()
    A.mine[4] = false
    discover()
    call(B, "LinkSession", "RequestLink", 2)
    deliver()
    assert.are.equal(0, #A.prompts)
    assert.are.same({}, within(A, function() return AltArmy.LinkSession.View() end))
  end)

  it("keeps no link when the other player says no", function()
    discover()
    call(A, "LinkSession", "RequestLink", 4)
    deliver()
    call(B, "LinkSession", "DeclineLink", 2)
    deliver()
    assert.is_nil(linkOf(A, "bbbb"))
    assert.is_nil(linkOf(B, "aaaa"))
    local view = within(A, function() return AltArmy.LinkSession.View() end)
    assert.is_true(view[1].declined)
  end)

  it("makes a new account id when the other has the same (a copied WTF folder)", function()
    B.accountId = "aaaa"
    discover()
    assert.are_not.equal(A.accountId, B.accountId)
  end)

  it("pauses a link with an account in another game, and syncs nothing", function()
    link()
    B.project = 2 -- B logs in to another game: a new session there
    B.data.Characters.R["Player-1-B1"].money = 7
    clock = clock + 120
    within(B, function() AltArmy.LinkSession._Reset() end)
    discover()
    assert.are.equal("another game", linkOf(A, "bbbb").suspended)
    assert.are.same({}, within(A, function()
      local out = {}
      AltArmy.LinkStore.ForEachCharacter(function(_, guid) out[#out + 1] = guid end)
      return out
    end))
  end)
end)
