--[[
  Unit tests for RealmFilter.lua (realm filter and display name helpers).
  Run from project root: npm test
]]

describe("RealmFilter", function()
  local RF

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("RealmFilter")
    RF = AltArmy.RealmFilter
  end)

  describe("filterListByRealm", function()
    it("returns full list when realmFilter is 'all'", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
      }
      local out = RF.filterListByRealm(list, "all", "R1")
      assert.are.equal(#out, 2)
      assert.are.equal(out[1].name, "A")
      assert.are.equal(out[2].name, "B")
    end)

    it("returns only current-realm entries when realmFilter is 'currentRealm'", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
        { name = "C", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R1")
      assert.are.equal(#out, 2)
      assert.are.equal(out[1].name, "A")
      assert.are.equal(out[2].name, "C")
    end)

    it("returns empty list when currentRealm has no matches", function()
      local list = {
        { name = "A", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R2")
      assert.are.equal(#out, 0)
    end)

    it("returns new table (does not mutate input)", function()
      local list = {
        { name = "A", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R2")
      assert.are.equal(#list, 1)
      assert.are.equal(#out, 0)
    end)
  end)

  describe("hasMultipleRealms", function()
    it("returns false for empty list", function()
      assert.is_false(RF.hasMultipleRealms({}))
    end)

    it("returns false for single entry", function()
      assert.is_false(RF.hasMultipleRealms({ { name = "A", realm = "R1" } }))
    end)

    it("returns false when all entries same realm", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R1" },
      }
      assert.is_false(RF.hasMultipleRealms(list))
    end)

    it("returns true when entries have different realms", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
      }
      assert.is_true(RF.hasMultipleRealms(list))
    end)

    it("returns true when more than two realms", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
        { name = "C", realm = "R3" },
      }
      assert.is_true(RF.hasMultipleRealms(list))
    end)
  end)

  describe("formatCharacterDisplayName", function()
    it("returns name only when showRealmSuffix is false", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", "Dreamscythe", false), "Frell")
    end)

    it("returns name-realm when showRealmSuffix is true", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", "Dreamscythe", true), "Frell-Dreamscythe")
    end)

    it("handles nil realm as empty string when showRealmSuffix true", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", nil, true), "Frell-")
    end)
  end)

  describe("formatCharacterDisplayNameColored", function()
    it("returns name with color code when showRealmSuffix false", function()
      local s = RF.formatCharacterDisplayNameColored("Frell", "Dreamscythe", false, 1, 0.5, 0)
      assert.truthy(s:find("|cFF"))
      assert.truthy(s:find("Frell"))
      assert.truthy(s:find("|r"))
      assert.is_nil(s:find("Dreamscythe"))
    end)

    it("returns name (colored) and -realm (after |r) when showRealmSuffix true", function()
      local s = RF.formatCharacterDisplayNameColored("Frell", "Dreamscythe", true, 1, 0.5, 0)
      assert.truthy(s:find("|cFF"))
      assert.truthy(s:find("Frell"))
      assert.truthy(s:find("|r"))
      assert.truthy(s:find("-Dreamscythe"))
    end)
  end)

  describe("formatColoredCharacterNameRealm", function()
    it("uses raid class color and gray realm with em dash when suffix on", function()
      local s = RF.formatColoredCharacterNameRealm("Ada", "Alpha", true, "MAGE")
      assert.truthy(s:find("|cff"))
      assert.truthy(s:find("Ada"))
      assert.truthy(s:find("|cffaaaaaa"))
      assert.truthy(s:find(" — Alpha"))
    end)

    it("omits realm when showRealmSuffix false", function()
      local s = RF.formatColoredCharacterNameRealm("Ada", "Alpha", false, "MAGE")
      assert.is_nil(s:find("Alpha"))
      assert.truthy(s:find("Ada"))
    end)

    it("uses white name when classFile nil", function()
      local s = RF.formatColoredCharacterNameRealm("Bob", "Beta", true, nil)
      assert.truthy(s:find("|cffffffffBob|r"))
      assert.truthy(s:find(" — Beta"))
    end)

    it("prepends bank icon for bank alts by default", function()
      package.loaded["BankAlt"] = nil
      require("CharKey")
      require("BankAlt")
      _G.AltArmyTBC_Options = {}
      AltArmy.BankAlt.Set("Ada", "Alpha", true)
      local s = RF.formatColoredCharacterNameRealm("Ada", "Alpha", false, "MAGE")
      assert.truthy(s:find("|T.-|t"))
      assert.truthy(s:find("Ada"))
    end)

    it("omits bank icon when includeBankIcon is false", function()
      package.loaded["BankAlt"] = nil
      require("CharKey")
      require("BankAlt")
      _G.AltArmyTBC_Options = {}
      AltArmy.BankAlt.Set("Ada", "Alpha", true)
      local s = RF.formatColoredCharacterNameRealm("Ada", "Alpha", false, "MAGE", false)
      assert.is_nil(s:find("|T"))
      assert.truthy(s:find("Ada"))
    end)
  end)

  describe("inScope / filterListByScope", function()
    local ALL_OFF = { otherFaction = false, otherRealms = false, linked = false }
    local ALL_ON = { otherFaction = true, otherRealms = true, linked = true }

    it("always shows this realm's characters of my faction, and those whose faction is unknown", function()
      assert.is_true(RF.inScope({ realm = "R" }, "Horde", ALL_OFF, "R", "Horde"))
      assert.is_true(RF.inScope({ realm = "R" }, nil, ALL_OFF, "R", "Horde"))
    end)

    it("shows the other faction here only with otherFaction", function()
      assert.is_false(RF.inScope({ realm = "R" }, "Alliance", ALL_OFF, "R", "Horde"))
      assert.is_true(RF.inScope({ realm = "R" }, "Alliance", { otherFaction = true }, "R", "Horde"))
    end)

    it("shows other realms, either faction, only with otherRealms", function()
      assert.is_false(RF.inScope({ realm = "X" }, "Horde", { otherFaction = true }, "R", "Horde"))
      assert.is_true(RF.inScope({ realm = "X" }, "Alliance", { otherRealms = true }, "R", "Horde"))
    end)

    it("shows a linked account's characters only with linked, then by the same rules", function()
      local linked = { realm = "R", linkId = "acct" }
      assert.is_false(RF.inScope(linked, "Horde", { otherFaction = true, otherRealms = true }, "R", "Horde"))
      assert.is_true(RF.inScope(linked, "Horde", { linked = true }, "R", "Horde"))
      assert.is_false(RF.inScope(linked, "Alliance", { linked = true }, "R", "Horde"))
      assert.is_true(RF.inScope(linked, "Alliance", ALL_ON, "R", "Horde"))
    end)

    it("filters a list, looking a faction up when an entry has none", function()
      local list = { { realm = "R", name = "A", faction = "Horde" }, { realm = "R", name = "B" },
        { realm = "X", name = "C", faction = "Horde" } }
      local lookups = {}
      local out = RF.filterListByScope(list, ALL_OFF, "R", "Horde", function(e)
        lookups[#lookups + 1] = e.name
        return "Alliance"
      end)
      assert.are.same({ "B" }, lookups)
      assert.are.equal(1, #out)
      assert.are.equal("A", out[1].name)
    end)
  end)
end)
