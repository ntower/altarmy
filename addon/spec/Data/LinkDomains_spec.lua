--[[ Unit tests for Link/LinkDomains.lua — run: npm test ]]

describe("LinkDomains", function()
  local Dom

  local function char()
    return {
      name = "Medusa Frell", realm = "Classic Beta PvE", guid = "Player-4618-017C546E", faction = "Horde",
      classFile = "WARLOCK", level = 23, money = 1234,
      Containers = { { items = { { itemID = 2589, count = 5, link = "|cnIQ1:|Hitem:2589::::|h[Linen Cloth]|h|r" } } } },
      Mails = { { itemID = 1, count = 1, money = 0, subject = "Hi", sender = "Bob", daysLeft = 20 } },
      MailCache = { { money = 50, text = "secret", subject = "Re", sender = "Al", daysLeft = 3 } },
      levelHistory = { [10] = { gear = {} } },
      Auctions = { { itemID = 3 } },
      cooldownGroupChoice = { x = 1 },
      professionsNeedingRecipeScan = { Tailoring = true },
      dataVersions = { character = 3, containers = 4, mail = 2, levelHistory = 1, auctions = 1 },
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    require("LinkDomains")
    Dom = AltArmy.LinkDomains
  end)

  it("copies a domain's fields and their data versions, nothing else", function()
    local c = char()
    local unit = Dom.Extract(c, "identity")
    assert.are.equal("Medusa Frell", unit.name)
    assert.are.same({ character = 3 }, unit.dataVersions)
    assert.is_nil(unit.Containers)
    local bags = Dom.Extract(c, "containers")
    assert.are.same({ containers = 4 }, bags.dataVersions)
    bags.Containers[1].items[1].count = 99
    assert.are.equal(5, c.Containers[1].items[1].count) -- a copy
  end)

  it("never sends mail subjects, bodies or senders", function()
    local unit = Dom.Extract(char(), "mail")
    assert.are.same({ itemID = 1, count = 1, money = 0, daysLeft = 20 }, unit.Mails[1])
    assert.are.same({ money = 50, daysLeft = 3 }, unit.MailCache[1])
    assert.are.equal("Hi", char().Mails[1].subject) -- the source keeps them
  end)

  it("has no domain for level history, auctions or this client's UI state", function()
    for _, domain in ipairs(Dom.ORDER) do
      local unit = Dom.Extract(char(), domain)
      assert.is_nil(unit.levelHistory)
      assert.is_nil(unit.Auctions)
      assert.is_nil(unit.cooldownGroupChoice)
      assert.is_nil(unit.professionsNeedingRecipeScan)
      assert.is_nil(unit.dataVersions.levelHistory)
      assert.is_nil(unit.dataVersions.auctions)
    end
    assert.is_nil(Dom.Extract(char(), "levelHistory"))
  end)

  it("lists every domain in its send order", function()
    local seen = {}
    for _, d in ipairs(Dom.ORDER) do seen[d] = true end
    for d in pairs(Dom.DOMAINS) do assert.is_true(seen[d], d) end
  end)

  it("sends the account's currency and faction names", function()
    local meta = Dom.ExtractMeta({ CurrencyMeta = { [1] = { name = "Honor" } }, WritOrders = {},
      ReputationFactionNames = { [76] = "Orgrimmar" } })
    assert.are.same({ CurrencyMeta = { [1] = { name = "Honor" } }, ReputationFactionNames = { [76] = "Orgrimmar" } },
      meta)
  end)

  it("hashes the same data the same whatever the order, and different data differently", function()
    local a, b = {}, {}
    for i = 1, 20 do a[i] = i; a["k" .. i] = i * 2 end
    for i = 20, 1, -1 do b["k" .. i] = i * 2; b[i] = i end
    assert.are.equal(Dom.Hash(a), Dom.Hash(b))
    b.k3 = 7
    assert.are_not.equal(Dom.Hash(a), Dom.Hash(b))
    assert.are_not.equal(Dom.Hash({ x = "1" }), Dom.Hash({ x = 1 }))
    assert.are_not.equal(Dom.Hash({ a = { b = 1 } }), Dom.Hash({ a = {}, b = 1 }))
  end)
end)
