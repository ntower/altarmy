--[[ Unit tests for Link/LinkDiscovery.lua — run: npm test

  The fakes follow what /altarmy debug bnprobe measured on WoW: Forever (interface 16001): the game account
  struct has no bnetAccountID, there is no legacy BNGetGameAccountInfo, BNGetInfo's third return is not our
  game account id, and an account is placed on a Battle.net account through GetAccountInfoByGUID.
]]

describe("LinkDiscovery", function()
  local LD

  -- A game account as C_BattleNet.GetGameAccountInfoByID returns it on Forever.
  local function account(id, over)
    local a = {
      gameAccountID = id,
      clientProgram = "WoW",
      isOnline = true,
      wowProjectID = 18,
      regionID = 110,
      characterName = "Char" .. id,
      realmName = "ClassicBetaPvE",
      playerGuid = "Player-4618-" .. id,
    }
    for k, v in pairs(over or {}) do
      a[k] = v
    end
    return a
  end

  -- `owners`: playerGuid -> { bnetAccountID, battleTag } (GetAccountInfoByGUID); ours is Player-4618-3.
  local function api(accounts, owners, opts)
    opts = opts or {}
    local byId = {}
    for _, a in ipairs(accounts) do
      byId[a.gameAccountID] = a
    end
    return {
      wowProjectID = 18,
      BNGetInfo = function()
        return 1, "Cyphern#1832", 1 -- the third is not our game account id
      end,
      GetGameAccountInfoByID = function(id)
        return byId[id]
      end,
      GetAccountInfoByGUID = function(guid)
        if guid == "Player-4618-3" then
          return opts.myPresence -- blank (nil) right after login
        end
        return owners[guid]
      end,
      UnitGUID = function()
        return "Player-4618-3"
      end,
    }
  end

  local MINE = { bnetAccountID = 1, battleTag = "Cyphern#1832" }

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    require("LinkDiscovery")
    LD = AltArmy.LinkDiscovery
  end)

  it("knows this client by its GUID, not BNGetInfo's third return", function()
    local me = LD.Me(api({}, {}))
    assert.are.same({ guid = "Player-4618-3", bnetAccountID = 1, battleTag = "Cyphern#1832", wowProjectID = 18 },
      me)
  end)

  it("reads our game account from our presence when it is there", function()
    local presence = { bnetAccountID = 1, battleTag = "Cyphern#1832",
      gameAccountInfo = { gameAccountID = 3, wowProjectID = 18, regionID = 110 } }
    local me = LD.Me(api({}, {}, { myPresence = presence }))
    assert.are.same({ 3, 18, 110 }, { me.gameAccountID, me.wowProjectID, me.regionID })
  end)

  it("finds your other account as measured on Forever", function()
    local a = api({ account(3, { hasFocus = true }), account(4) }, { ["Player-4618-4"] = MINE })
    local me = LD.Me(a)
    local scan = LD.Scan(a, me)
    assert.are.same({ "self", true }, { scan[1].reason, scan[2].candidate })
    assert.are.equal("guid", scan[2].bnetAccountFrom)
    assert.are.same({ 3, 110 }, { me.gameAccountID, me.regionID }) -- filled in from our own entry
  end)

  it("keeps only your accounts online in the same game and region", function()
    local owners = {}
    for id = 4, 10 do
      owners["Player-4618-" .. id] = MINE
    end
    owners["Player-4618-8"] = { bnetAccountID = 99, battleTag = "Friend#1" }
    local a = api({
      account(3),
      account(4), -- your other account
      account(5, { isOnline = false }),
      account(6, { clientProgram = "App" }),
      account(7, { wowProjectID = 2 }), -- another game on the same login
      account(8), -- a friend's
      account(9, { isWowMobile = true }),
      account(10, { regionID = 1 }),
    }, owners)
    local reasons = {}
    for _, info in ipairs(LD.Scan(a, LD.Me(a))) do
      reasons[#reasons + 1] = info.candidate and "yes" or info.reason
    end
    assert.are.same({ "self", "yes", "offline", "client", "project", "bnetAccount", "mobile", "region" },
      reasons)
  end)

  it("takes the BattleTag when the account ids don't say", function()
    local a = api({ account(3), account(4) }, { ["Player-4618-4"] = { battleTag = "Cyphern#1832" } })
    local scan = LD.Scan(a, LD.Me(a))
    assert.is_true(scan[2].candidate)
  end)

  it("never takes an account it can't place on a Battle.net account", function()
    local a = api({ account(3), account(4) }, {})
    local scan = LD.Scan(a, LD.Me(a))
    assert.are.equal("bnetUnknown", scan[2].reason)
  end)

  it("survives a client without the API", function()
    local me = LD.Me({ wowProjectID = 18 })
    assert.are.same({ wowProjectID = 18 }, me)
    assert.are.same({}, LD.Scan({}, me))
  end)
end)
