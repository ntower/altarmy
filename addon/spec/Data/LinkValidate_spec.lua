--[[ Unit tests for Link/LinkValidate.lua — run: npm test ]]

describe("LinkValidate", function()
  local V
  local GUID = "Player-4618-017C546E"
  local REALM = "Classic Beta PvE"
  local VERSIONS = { character = 3, containers = 4, mail = 2, equipment = 1, gearScores = 1 }

  local function identity(over)
    local u = { name = "Medusa Frell", realm = REALM, guid = GUID, level = 23, dataVersions = { character = 3 } }
    for k, v in pairs(over or {}) do u[k] = v end
    return u
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    require("LinkDomains")
    require("LinkValidate")
    V = AltArmy.LinkValidate
  end)

  it("keeps a good unit's fields and drops the rest", function()
    local kept = V.Unit("identity", identity({ levelHistory = {}, evil = "x" }), GUID, REALM, VERSIONS)
    assert.are.equal("Medusa Frell", kept.name)
    assert.is_nil(kept.levelHistory)
    assert.is_nil(kept.evil)
  end)

  it("refuses an identity that isn't the character it came as", function()
    assert.are.same({ nil, "badGuid" }, { V.Unit("identity", identity(), "Player-4618-OTHER", REALM, VERSIONS) })
    assert.are.same({ nil, "badGuid" }, { V.Unit("identity", identity({ guid = "nonsense" }), "nonsense", REALM,
      VERSIONS) })
    assert.are.same({ nil, "noName" }, { V.Unit("identity", identity({ name = "" }), GUID, REALM, VERSIONS) })
    assert.are.same({ nil, "wrongRealm" }, { V.Unit("identity", identity(), GUID, "Elsewhere", VERSIONS) })
  end)

  it("refuses data newer than this addon reads, and keeps older", function()
    local newer = identity({ dataVersions = { character = 4 } })
    assert.are.same({ nil, "newer" }, { V.Unit("identity", newer, GUID, REALM, VERSIONS) })
    local older = V.Unit("identity", identity({ dataVersions = { character = 2 } }), GUID, REALM, VERSIONS)
    assert.are.equal(2, older.dataVersions.character)
  end)

  it("refuses odd values: functions, NaN, huge strings, deep or huge tables, odd keys", function()
    local function deep(n)
      local t = {}
      local cur = t
      for _ = 1, n do cur.x = {}; cur = cur.x end
      return t
    end
    local big = {}
    for i = 1, V.MAX_NODES + 1 do big[i] = i end
    local cases = {
      { identity({ money = function() end }), "badType" },
      { identity({ money = 0 / 0 }), "badNumber" },
      { identity({ money = math.huge }), "badNumber" },
      { identity({ name = string.rep("a", V.MAX_STRING + 1) }), "longString" },
      { identity({ bagInfo = deep(V.MAX_DEPTH + 1) }), "tooDeep" },
      { identity({ bagInfo = big }), "tooBig" },
      { identity({ bagInfo = { [true] = 1 } }), "badKey" },
    }
    for _, c in ipairs(cases) do
      assert.are.same({ nil, c[2] }, { V.Unit("identity", c[1], GUID, REALM, VERSIONS) })
    end
  end)

  it("refuses a bag slot or equipped item whose link names no item", function()
    local bags = { Containers = { { items = { { itemID = 1, link = "|cff|Hspell:1|h[x]|h|r" } } } } }
    assert.are.same({ nil, "badLink" }, { V.Unit("containers", bags, GUID, REALM, VERSIONS) })
    local forever = { Containers = { { items = { { link = "|cnIQ1:|Hitem:2589::::|h[Linen]|h|r" } } } } }
    assert.truthy(V.Unit("containers", forever, GUID, REALM, VERSIONS))
    assert.are.same({ nil, "badLink" }, { V.Unit("equipment", { Inventory = { [1] = "plain text" } }, GUID, REALM,
      VERSIONS) })
  end)

  it("strips mail text again on the way in", function()
    local kept = V.Unit("mail", { MailCache = { { money = 5, subject = "s", sender = "x", text = "t" } } }, GUID,
      REALM, VERSIONS)
    assert.are.same({ money = 5 }, kept.MailCache[1])
  end)

  it("keeps of a level history only milestones' played times, whatever was sent", function()
    local sent = { levelHistory = { deaths = { { at = 1 } }, milestones = {
      [20] = { playedTotal = 7200, playedLevel = 900, gear = { "link" }, zone = "Duskwood" },
    } }, dataVersions = { levelHistory = 1 } }
    local kept = V.Unit("levels", sent, GUID, REALM, { levelHistory = 1 })
    assert.are.same({ milestones = { [20] = { playedTotal = 7200, playedLevel = 900 } } }, kept.levelHistory)
  end)

  it("refuses an unknown domain", function()
    assert.are.same({ nil, "unknownDomain" }, { V.Unit("levelHistory", {}, GUID, REALM, VERSIONS) })
  end)

  it("keeps only the names a meta unit should carry", function()
    assert.are.same({ CurrencyMeta = { [1] = { name = "Honor" } } },
      V.Meta({ CurrencyMeta = { [1] = { name = "Honor" } }, WritOrders = { 1 } }))
    assert.are.same({ nil, "badType" }, { V.Meta({ CurrencyMeta = { [1] = function() end } }) })
  end)
end)
