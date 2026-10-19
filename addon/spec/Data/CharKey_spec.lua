--[[
  Unit tests for CharKey.lua.
  Run from project root: npm test
]]

describe("CharKey", function()
  local CharKey

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("CharKey")
    CharKey = AltArmy.CharKey
  end)

  it("builds realm\\name key", function()
    assert.are.equal("RealmA\\Alice", CharKey("Alice", "RealmA"))
  end)

  it("handles nil name and realm", function()
    assert.are.equal("\\", CharKey(nil, nil))
    assert.are.equal("RealmA\\", CharKey(nil, "RealmA"))
    assert.are.equal("\\Bob", CharKey("Bob", nil))
  end)

  it("matches saved-var format used in gear settings", function()
    assert.are.equal("RealmA\\Me", CharKey("Me", "RealmA"))
  end)

  describe("RekeyCharSettings", function()
    local Rekey
    setup(function() Rekey = AltArmy.RekeyCharSettings end)
    before_each(function()
      _G.AltArmyTBC_SummarySettings = { characters = { ["R\\Frell"] = { pin = true } } }
      _G.AltArmyTBC_GearSettings = { characters = { ["R\\Frell"] = { hide = true } } }
      _G.AltArmyTBC_ReputationSettings = { characters = { ["R\\Frell"] = { pin = true } } }
      _G.AltArmyTBC_GraphSettings = { selected = { ["R\\Frell"] = true, ["R\\Other"] = true } }
      _G.AltArmyTBC_Options = {
        bankAlts = { ["R\\Frell"] = true },
        bankAltPromptDismissed = { ["R\\Frell"] = true },
        economy = { currency = { characters = { ["R\\Frell"] = { hide = true } } } },
      }
    end)

    it("moves every per-character setting to the new name", function()
      Rekey("R", "Frell", "Frell Blast")
      assert.are.same({ ["R\\Frell Blast"] = { pin = true } }, AltArmyTBC_SummarySettings.characters)
      assert.are.same({ ["R\\Frell Blast"] = { hide = true } }, AltArmyTBC_GearSettings.characters)
      assert.are.same({ ["R\\Frell Blast"] = { pin = true } }, AltArmyTBC_ReputationSettings.characters)
      assert.are.same({ ["R\\Frell Blast"] = true, ["R\\Other"] = true }, AltArmyTBC_GraphSettings.selected)
      assert.are.same({ ["R\\Frell Blast"] = true }, AltArmyTBC_Options.bankAlts)
      assert.are.same({ ["R\\Frell Blast"] = true }, AltArmyTBC_Options.bankAltPromptDismissed)
      assert.are.same({ ["R\\Frell Blast"] = { hide = true } }, AltArmyTBC_Options.economy.currency.characters)
    end)

    it("keeps a setting already saved under the new name", function()
      AltArmyTBC_GearSettings.characters["R\\Frell Blast"] = { pin = true }
      Rekey("R", "Frell", "Frell Blast")
      assert.are.same({ ["R\\Frell Blast"] = { pin = true } }, AltArmyTBC_GearSettings.characters)
    end)

    it("does nothing when the name is unchanged or missing", function()
      Rekey("R", "Frell", "Frell")
      Rekey("R", nil, "Frell Blast")
      Rekey("R", "Frell", "")
      assert.is_true(AltArmyTBC_Options.bankAlts["R\\Frell"])
    end)

    it("tolerates settings tables that do not exist yet", function()
      _G.AltArmyTBC_SummarySettings = nil
      _G.AltArmyTBC_GraphSettings = {}
      AltArmyTBC_Options.economy = nil
      assert.has_no.errors(function() Rekey("R", "Frell", "Frell Blast") end)
    end)

    it("renames guild-share settings when that module is loaded", function()
      local calls = {}
      AltArmy.GuildShareSettings = {
        RenameCharacter = function(realm, old, new) calls[#calls + 1] = { realm, old, new } end,
      }
      Rekey("R", "Frell", "Frell Blast")
      AltArmy.GuildShareSettings = nil
      assert.are.same({ { "R", "Frell", "Frell Blast" } }, calls)
    end)
  end)
end)
