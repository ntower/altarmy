--[[ Unit tests for Link/LinkProbe.lua — run: npm test ]]

describe("LinkProbe", function()
  local P
  local sent

  local function account(id)
    return { gameAccountID = id, clientProgram = "WoW", isOnline = true, wowProjectID = 18, regionID = 110,
      playerGuid = "Player-1-" .. id, characterName = "Char" .. id, realmName = "Realm" }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.C_BattleNet = {}
    require("LinkDiscovery")
    require("LinkProbe")
    P = AltArmy.LinkProbe
  end)

  teardown(function()
    _G.C_BattleNet = nil
  end)

  before_each(function()
    P._Reset()
    sent = {}
    P._send = function(to, text)
      sent[#sent + 1] = { to = to, text = text }
      return true
    end
    local accounts = { [1] = account(1), [2] = account(2), [3] = account(3) }
    -- whose Battle.net account each character is on: 2 is yours, 3 a friend's
    local owners = { ["Player-1-2"] = { bnetAccountID = 7 }, ["Player-1-3"] = { bnetAccountID = 99 } }
    P._SetApi({
      wowProjectID = 18,
      BNGetInfo = function() return 7, "Frell#1234", 1 end,
      UnitGUID = function() return "Player-1-1" end,
      GetGameAccountInfoByID = function(id) return accounts[id] end,
      GetAccountInfoByGUID = function(guid) return owners[guid] end,
    })
  end)

  it("pings your other accounts and only those", function()
    local res = P.Start(false)
    assert.are.equal(1, #sent)
    assert.are.equal(2, sent[1].to)
    assert.truthy(sent[1].text:match("^PING|"))
    assert.are.equal(3, #res.accounts)
  end)

  it("answers a PING from your own account, and nobody else's", function()
    P.OnMessage("AltArmyLk", "PING|r1|5", "WHISPER", 2)
    assert.are.same({ { to = 2, text = "PONG|r1|5" } }, sent)
    P.OnMessage("AltArmyLk", "PING|r2|5", "WHISPER", 3)
    assert.are.equal(1, #sent)
    local log = P._Result().log
    assert.are.equal("notMine", log[2].dropped)
    assert.are.same({ "string", "string", "string", "number" }, log[1].types)
  end)

  it("ignores other prefixes and unreadable senders", function()
    P.OnMessage("Other", "PING|r1|5", "WHISPER", 2)
    assert.is_nil(P._Result())
    P.OnMessage("AltArmyLk", "PING|r1|5", "WHISPER", nil)
    assert.are.equal("unreadable", P._Result().log[1].dropped)
    assert.are.equal(0, #sent)
  end)

  it("sends 40 burst messages of 250 bytes", function()
    P.Start(true)
    local burst = 0
    for _, s in ipairs(sent) do
      if s.text:match("^B|") then
        burst = burst + 1
        assert.are.equal(250, #s.text)
      end
    end
    assert.are.equal(40, burst)
  end)

  it("reports a burst: what arrived, duplicated and out of order", function()
    local function b(seq)
      local head = "B|run|" .. seq .. "|4|"
      P.OnMessage("AltArmyLk", head .. string.rep("x", 250 - #head), "WHISPER", 2)
    end
    b(1)
    b(3)
    b(3)
    b(2)
    assert.are.equal(0, #sent) -- still waiting for the 4th
    P._FlushBurst("run", 2)
    assert.are.equal(1, #sent)
    local f = {}
    for part in (sent[1].text .. "|"):gmatch("([^|]*)|") do
      f[#f + 1] = part
    end
    assert.are.same({ "BR", "run", "3", "4", "1", "1" }, { f[1], f[2], f[3], f[4], f[5], f[6] })
    local r = P._Result().bursts.run
    assert.are.equal(3, r.got)
  end)
end)
