--[[ Unit tests for Link/LinkStore.lua, the DataStore's linked accessors and the debug harness — npm test ]]

describe("LinkStore", function()
  local S, DS, H
  local REALM = "Classic Beta PvE"
  local GUID = "Player-4618-0A"

  local function identity(name, guid)
    return { name = name, realm = REALM, guid = guid or GUID, faction = "Horde", classFile = "MAGE", level = 10,
      dataVersions = { character = 3 } }
  end

  local function names(fnScope)
    local out = {}
    fnScope(function(_, _, char, linkId)
      out[#out + 1] = (linkId and "L:" or "") .. char.name
    end)
    table.sort(out)
    return out
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    require("DataStore")
    require("LinkDomains")
    require("LinkValidate")
    require("LinkStore")
    require("LinkHarness")
    S, DS, H = AltArmy.LinkStore, AltArmy.DataStore, AltArmy.LinkHarness
  end)

  before_each(function()
    S._Reset()
    AltArmyTBC_Data.Characters = { [REALM] = { ["Player-4618-01"] = { name = "Mine", faction = "Horde",
      guid = "Player-4618-01", classFile = "MAGE", level = 60 } } }
    AltArmy.GlobalRealmFilter = nil
  end)

  it("keeps a linked character only once its identity arrived, and lists it only once confirmed", function()
    assert.are.same({ false, "noIdentity" }, { S.Receive("acct", REALM, GUID, "containers", { Containers = {} }) })
    assert.is_true(S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100))
    assert.are.same({}, names(function(fn) S.ForEachCharacter(fn) end)) -- no link yet
    S.SetLink("acct", { label = "Box 2", confirmed = true })
    assert.are.same({ "L:Theirs" }, names(function(fn) S.ForEachCharacter(fn) end))
    S.SetLink("acct", { suspended = "project" })
    assert.are.same({}, names(function(fn) S.ForEachCharacter(fn) end))
  end)

  it("lists ours, then linked accounts', and only ours to ForEachCharacter", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    assert.are.same({ "Mine" }, names(function(fn) DS:ForEachCharacter(fn) end))
    assert.are.same({ "L:Theirs", "Mine" }, names(function(fn) DS:ForEachCharacterInScope(fn) end))
    assert.are.same({ "Mine" }, names(function(fn) DS:ForEachCharacterInScope(fn, { linked = false }) end))
    -- every list drops them by its own realm filter, so the source always gives them
    AltArmy.GlobalRealmFilter = { GetScope = function() return { linked = false } end }
    assert.are.same({ "L:Theirs", "Mine" }, names(function(fn) DS:ForEachCharacterInScope(fn) end))
    AltArmy.GlobalRealmFilter = nil
  end)

  it("knows which link a character came from, and finds it by name", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    local char, link = DS:GetCharacterAny("Theirs", REALM)
    assert.are.same({ "Theirs", "acct" }, { char.name, link })
    assert.are.equal("acct", DS:GetLinkId(char))
    assert.is_false(DS:IsLinkedCharacter(DS:GetCharacter("Mine", REALM)))
  end)

  it("gives a list row its character: the linked account's by the row's link, else ours", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Mine"), 100) -- the same name as one of ours
    assert.are.equal(60, DS:GetCharacterFor("Mine", REALM).level)
    assert.are.equal(10, DS:GetCharacterFor("Mine", REALM, "acct").level)
    assert.are.equal(10, DS:GetCharacterFor(GUID, REALM, "acct").level) -- or by its key
    assert.is_nil(DS:GetCharacterFor("Mine", REALM, "other"))
    S.SetLink("acct", { suspended = "another game" })
    assert.is_nil(DS:GetCharacterFor("Mine", REALM, "acct"))
  end)

  it("updates a domain in place and remembers its hash", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    S.Receive("acct", REALM, GUID, "containers", { Containers = { { items = {} } }, dataVersions = { containers = 4 } },
      200)
    local char = DS:GetCharacterAny("Theirs", REALM)
    assert.are.same({ { items = {} } }, char.Containers)
    assert.are.equal(4, char.dataVersions.containers)
    assert.are.equal(3, char.dataVersions.character)
    assert.truthy(S.Hashes("acct")[GUID].containers)
    assert.are.equal(200, S.ReceivedAt("acct"))
  end)

  it("refuses a unit that fails the checks, keeping what it had", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    local bad = identity("Theirs")
    bad.level = 0 / 0
    assert.are.same({ false, "badNumber" }, { S.Receive("acct", REALM, GUID, "identity", bad, 200) })
    assert.are.equal(10, DS:GetCharacterAny("Theirs", REALM).level)
  end)

  it("unlinks: the link and everything from it are gone", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    S.Unlink("acct")
    assert.is_false(S.HasLinks())
    assert.is_nil(DS:GetCharacterAny("Theirs", REALM))
    assert.is_nil(AltArmyTBC_LinkedData.accounts.acct)
  end)

  it("removes a character the linked account no longer has", function()
    S.SetLink("acct", { confirmed = true })
    S.Receive("acct", REALM, GUID, "identity", identity("Theirs"), 100)
    S.RemoveCharacter("acct", REALM, GUID)
    assert.is_nil(DS:GetCharacterAny("Theirs", REALM))
  end)

  it("fills in currency and faction names we lack, never overwriting ours", function()
    local own = { CurrencyMeta = { [1] = { name = "Ours" } } }
    S.ReceiveMeta("acct", { CurrencyMeta = { [1] = { name = "Theirs" }, [2] = { name = "New" } } }, own)
    assert.are.same({ [1] = { name = "Ours" }, [2] = { name = "New" } }, own.CurrencyMeta)
  end)

  it("caps how many characters one account may send", function()
    S.SetLink("acct", { confirmed = true })
    local V = AltArmy.LinkValidate
    local cap = V.MAX_CHARACTERS
    V.MAX_CHARACTERS = 2
    S.Receive("acct", REALM, "Player-4618-0A", "identity", identity("A", "Player-4618-0A"))
    S.Receive("acct", REALM, "Player-4618-0B", "identity", identity("B", "Player-4618-0B"))
    assert.are.same({ false, "tooManyCharacters" },
      { S.Receive("acct", REALM, "Player-4618-0C", "identity", identity("C", "Player-4618-0C")) })
    V.MAX_CHARACTERS = cap
  end)

  it("the harness links copies of our characters through the real checks", function()
    local made, refused = H.Fake(3, AltArmyTBC_Data, 100)
    assert.are.equal(1, made)
    assert.are.same({}, refused)
    local copy = DS:GetCharacterAny("Mine Copy", REALM)
    assert.truthy(copy)
    assert.are_not.equal("Player-4618-01", copy.guid)
    assert.are.equal("Test account", S.Label(H.ACCOUNT_ID))
    H.Clear()
    assert.is_nil(DS:GetCharacterAny("Mine Copy", REALM))
  end)
end)
