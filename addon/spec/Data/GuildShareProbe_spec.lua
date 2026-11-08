--[[
  Unit tests for GuildShareProbe's pure helpers and its receive hooks.
  Run from project root: npm test
]]

describe("GuildShareProbe", function()
  local Probe

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { RegisterEvent = function() end, SetScript = function() end }
    end
    package.path = package.path .. ";AltArmy_TBC/Data/Guild/?.lua"
    require("GuildShareProbe")
    Probe = AltArmy.GuildShareProbe
    assert.truthy(Probe)
  end)

  before_each(function() Probe._Reset() end)

  it("turns a whisper suffix into a Forever realm and back", function()
    assert.are.equal("CAMWOW US1 Realm 5 PvE", Probe.RealmFromSuffix("CAMWOWUS1Realm5PvE"))
    assert.are.equal("CAMWOWUS1Realm5PvE", Probe.SuffixFromRealm("CAMWOW US1 Realm 5 PvE"))
    assert.is_nil(Probe.RealmFromSuffix("Dreamscythe"))
  end)

  it("reads the suffix of a full sender name only", function()
    assert.are.equal("CAMWOWUS1Realm5PvE", Probe.SuffixOf("Drubbles Thunderpaw-CAMWOWUS1Realm5PvE"))
    assert.is_nil(Probe.SuffixOf("Drubbles Thunderpaw"))
  end)

  it("tags and untags a name", function()
    local tagged = Probe.TagName("Drubbles Thunderpaw", "full/theirRealm")
    assert.are.same({ "Drubbles Thunderpaw", "full/theirRealm" }, { Probe.UntagName(tagged) })
    assert.are.same({ "Drubbles Thunderpaw" }, { Probe.UntagName("Drubbles Thunderpaw") })
  end)

  it("makes variants per target and realm, dropping repeats and unknowns", function()
    local four = Probe.Variants("A", "A-R2", "R1", { "R2" })
    assert.are.equal(4, #four)
    assert.are.equal("short/myRealm", four[1].label)
    assert.are.equal("short/realm=R2", four[2].label)
    assert.are.equal(2, #Probe.Variants("A", "A-R1", "R1", { "R1" }))
    assert.are.equal(1, #Probe.Variants("A", nil, "R1", {}))
  end)

  it("tries the known realm alone, else the seen realms then a grid of the player's region", function()
    assert.are.same({ "X" }, Probe.RealmCandidates("CAMWOW US1 Realm 5 PvE", "X", {}))
    local guesses = Probe.RealmCandidates("CAMWOW US1 Realm 5 PvE", nil,
      { g1 = "CAMWOW US1 Realm 7 PvE", g2 = "CAMWOW US1 Realm 5 PvE" })
    assert.are.equal("CAMWOW US1 Realm 7 PvE", guesses[1])
    assert.are.equal("CAMWOW US1 Realm 1 PvE", guesses[2])
    assert.are.equal(3 * Probe.MAX_GUESS_REALM - 1, #guesses)
    for _, r in ipairs(guesses) do assert.are_not.equal("CAMWOW US1 Realm 5 PvE", r) end
  end)

  it("records raw senders and the realms presence characters report", function()
    Probe.OnRawReceive("P", { chars = { { guid = "Player-6929-1", realm = "CAMWOW US1 Realm 5 PvE" } } },
      "Drubbles Thunderpaw-CAMWOWUS1Realm5PvE", "GUILD")
    assert.are.equal("Drubbles Thunderpaw-CAMWOWUS1Realm5PvE", Probe._Senders()["Drubbles Thunderpaw"].raw)
    assert.are.equal("CAMWOW US1 Realm 5 PvE", Probe._GuidRealms()["Player-6929-1"])
  end)

  describe("multipart parts", function()
    local FIRST, NEXT, LAST = string.char(1), string.char(2), string.char(3)
    local function recv(msg, sender) Probe.OnAddonMessage("AltArmyGS", msg, "WHISPER", sender or "Sylantz") end

    it("records parts by kind and finds no anomaly in a whole message", function()
      recv(FIRST .. "aaa")
      recv(NEXT .. "bbb")
      recv(LAST .. "ccc")
      recv("single")
      local got = Probe.PartsFrom("Sylantz")
      assert.are.same({ "first", "next", "last", "single" },
        { got[1].kind, got[2].kind, got[3].kind, got[4].kind })
      assert.are.equal(0, #Probe.Anomalies())
    end)

    it("flags a part arriving after its message's last as an orphan", function()
      recv(FIRST .. "aaa")
      recv(LAST .. "ccc")
      recv(NEXT .. "bbb")
      assert.are.equal(1, #Probe.Anomalies())
      assert.are.equal("orphan", Probe.Anomalies()[1].anomaly)
    end)

    it("flags a first while another message is open as a restart", function()
      recv(FIRST .. "aaa")
      recv(FIRST .. "ddd")
      assert.are.equal("restart", Probe.Anomalies()[1].anomaly)
    end)

    it("keeps streams of different senders apart and ignores other prefixes", function()
      recv(FIRST .. "aaa", "A")
      recv(FIRST .. "bbb", "B")
      recv(LAST .. "ccc", "A")
      recv(LAST .. "ddd", "B")
      Probe.OnAddonMessage("Other", NEXT .. "x", "WHISPER", "A")
      assert.are.equal(0, #Probe.Anomalies())
      assert.are.equal(2, #Probe.PartsFrom("A"))
    end)
  end)

  it("hands an untagged card on unchanged and strips a tag", function()
    local card = { name = "Kairu Stormhoof", profs = {} }
    assert.are.equal(card, Probe.InterceptCharCard(card, "Kairu Stormhoof"))
    local tagged = { name = Probe.TagName("Kairu Stormhoof", "short/theirRealm"), profs = {} }
    assert.are.equal("Kairu Stormhoof", Probe.InterceptCharCard(tagged, "Kairu Stormhoof").name)
  end)
end)
