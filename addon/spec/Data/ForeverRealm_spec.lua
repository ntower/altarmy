--[[
  Unit tests for ForeverRealm.lua: on WoW Forever 1.60.1+ (which hides realm names) a character's realm is its
  region and ruleset ("US PvE"), read from the game rules; saved data moves to that key.
  Run from project root: npm test
]]

describe("ForeverRealm", function()
  local FR, DS
  local saved = {}
  local GLOBALS = { "GetRealmName", "GetCurrentRegionName", "C_GameRules", "Enum" }
  local rules

  local function setRules(pvp, rp, hc)
    rules = { [1] = pvp, [2] = rp, [3] = hc }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/DataStore/?.lua"
    require("DataStore")
    dofile("AltArmy_TBC/Data/DataStore/ForeverRealm.lua")
    FR = AltArmy.ForeverRealm
    DS = AltArmy.DataStore
  end)

  local wasForever
  before_each(function()
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    wasForever = DS.IsWowForever
    DS.IsWowForever = true
    setRules(false, false, false)
    _G.Enum = { GameRule = { PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3 } }
    _G.C_GameRules = { IsGameRuleActive = function(rule) return rules[rule] == true end }
    _G.GetCurrentRegionName = function() return "US" end
    _G.GetRealmName = function() return "" end
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    DS.IsWowForever = wasForever
  end)

  describe("Ruleset", function()
    it("reads each ruleset the game rules name", function()
      setRules(false, false, false)
      assert.are.equal("PvE", FR.Ruleset())
      setRules(true, false, false)
      assert.are.equal("PvP", FR.Ruleset())
      setRules(false, true, false)
      assert.are.equal("RP", FR.Ruleset())
      setRules(true, true, false)
      assert.are.equal("RPPvP", FR.Ruleset())
    end)

    it("is Hardcore whenever the Hardcore rule is on, whatever PvP and RP say", function()
      setRules(false, false, true)
      assert.are.equal("Hardcore", FR.Ruleset())
      setRules(true, false, true)
      assert.are.equal("Hardcore", FR.Ruleset())
    end)

    it("is nil when the client has no game rules", function()
      _G.C_GameRules = nil
      assert.is_nil(FR.Ruleset())
      _G.C_GameRules = { IsGameRuleActive = function() return false end }
      _G.Enum = nil
      assert.is_nil(FR.Ruleset())
    end)

    it("is PvE when the client lacks a rule it asks about", function()
      _G.Enum = { GameRule = {} }
      assert.are.equal("PvE", FR.Ruleset())
    end)
  end)

  describe("Current", function()
    it("is the region and the ruleset", function()
      setRules(true, true, false)
      _G.GetCurrentRegionName = function() return "EU" end
      assert.are.equal("EU RPPvP", FR.Current())
    end)

    it("falls back to the realm name the game gives, as its group", function()
      _G.C_GameRules = nil
      _G.GetRealmName = function() return "CAMWOW US2 Realm 5 PvE" end
      assert.are.equal("US PvE", FR.Current())
    end)

    it("is nil when neither the game rules nor a realm name say anything", function()
      _G.C_GameRules = nil
      assert.is_nil(FR.Current())
      _G.C_GameRules = { IsGameRuleActive = function() return false end }
      _G.GetCurrentRegionName = function() return nil end
      assert.is_nil(FR.Current())
    end)
  end)

  describe("Normalize", function()
    it("makes an old realm name its region and ruleset", function()
      assert.are.equal("US PvE", FR.Normalize("CAMWOW US2 Realm 5 PvE"))
      assert.are.equal("US PvE", FR.Normalize("CAMWOW US1 Realm 3 PvE"))
      assert.are.equal("EU PvP", FR.Normalize("CAMWOW EU4 Realm 4 PvP"))
      assert.are.equal("US RP", FR.Normalize("CAMWOW US2 Realm 1 RP"))
      assert.are.equal("US RPPvP", FR.Normalize("CAMWOW US2 Realm 1 RPPvP"))
      assert.are.equal("US Hardcore", FR.Normalize("CAMWOW US2 Realm 1 Hardcore"))
    end)

    it("reads the other words a ruleset may go by", function()
      assert.are.equal("US RP", FR.Normalize("CAMWOW US2 Realm 1 RPPvE"))
      assert.are.equal("US RP", FR.Normalize("CAMWOW US2 Realm 1 Roleplay"))
      assert.are.equal("US RPPvP", FR.Normalize("CAMWOW US2 Realm 1 RP-PvP"))
      assert.are.equal("US Hardcore", FR.Normalize("CAMWOW US2 Realm 1 HC"))
      assert.are.equal("US PvE", FR.Normalize("CAMWOW US2 Realm 1 Normal"))
    end)

    it("makes an older group name (with its cluster) the group", function()
      assert.are.equal("US PvE", FR.Normalize("CAMWOW US PvE"))
      assert.are.equal("US PvE", FR.Normalize("CAMWOW US Realm 0 PvE"))
    end)

    it("keeps a group name as it is", function()
      assert.are.equal("US PvE", FR.Normalize("US PvE"))
      assert.are.equal("EU RPPvP", FR.Normalize("EU RPPvP"))
    end)

    it("makes \"\" (an older Alt Army on 1.60.1) the current group, unless asked to keep it", function()
      setRules(true, false, false)
      assert.are.equal("US PvP", FR.Normalize(""))
      assert.are.equal("", FR.Normalize("", true))
      assert.are.equal("US PvP", FR.Normalize(nil))
    end)

    it("keeps a name it can't read, and one of an unknown ruleset", function()
      assert.are.equal("Dreamscythe", FR.Normalize("Dreamscythe"))
      assert.are.equal("CAMWOW US2 Realm 5 Bogus", FR.Normalize("CAMWOW US2 Realm 5 Bogus"))
      assert.are.equal("Living Flame", FR.Normalize("Living Flame"))
    end)

    it("changes nothing on TBC", function()
      DS.IsWowForever = false
      assert.are.equal("CAMWOW US2 Realm 5 PvE", FR.Normalize("CAMWOW US2 Realm 5 PvE"))
      assert.are.equal("Dreamscythe", FR.Normalize("Dreamscythe"))
      assert.are.equal("", FR.Normalize(""))
    end)
  end)

  describe("DataStore", function()
    local keepData
    before_each(function()
      keepData = _G.AltArmyTBC_Data
      _G.UnitGUID = function() return "Player-1-A" end
      _G.UnitName = function() return "Frell", "Blast" end
    end)
    after_each(function()
      _G.AltArmyTBC_Data = keepData
      _G.UnitGUID, _G.UnitName = nil, nil
    end)

    it("files the current character under its group on Forever", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      setRules(true, false, false)
      assert.are.equal("US PvP", AltArmy.CurrentRealm())
      assert.are.equal("US PvP", DS._GetCurrentCharTable().realm)
      assert.is_table(AltArmyTBC_Data.Characters["US PvP"]["Player-1-A"])
    end)

    it("makes no entry while the group isn't known", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      _G.C_GameRules = nil
      assert.are.equal("", AltArmy.CurrentRealm())
      assert.is_nil(DS._GetCurrentCharTable())
      assert.is_nil(AltArmyTBC_Data.Characters[""])
    end)

    it("adopts the character's copy saved under \"\" at its login", function()
      _G.AltArmyTBC_Data = { Characters = { [""] = { ["Player-1-A"] = { realm = "", level = 12, lastUpdate = 5 } } } }
      local char = DS._GetCurrentCharTable()
      assert.are.equal(12, char.level)
      assert.are.equal("US PvE", char.realm)
      assert.is_nil(AltArmyTBC_Data.Characters[""])
    end)

    it("keeps TBC on the server GetRealmName names, and never makes a \"\" entry there", function()
      DS.IsWowForever = false
      _G.AltArmyTBC_Data = { Characters = {} }
      _G.GetRealmName = function() return "Dreamscythe" end
      assert.are.equal("Dreamscythe", AltArmy.CurrentRealm())
      assert.are.equal("Dreamscythe", DS._GetCurrentCharTable().realm)
      _G.GetRealmName = function() return "" end
      _G.AltArmyTBC_Data = { Characters = {} }
      assert.is_nil(DS._GetCurrentCharTable())
    end)
  end)

  describe("RealmFilter on Forever", function()
    local RF
    setup(function()
      dofile("AltArmy_TBC/Data/Characters/RealmFilter.lua")
      RF = AltArmy.RealmFilter
    end)

    it("groups old names and group names alike", function()
      assert.are.equal("US PvE", RF.realmGroup("CAMWOW US2 Realm 5 PvE"))
      assert.are.equal("US PvE", RF.realmGroup("US PvE"))
      assert.is_true(RF.sameRealm("CAMWOW US1 Realm 3 PvE", "US PvE"))
      assert.is_false(RF.sameRealm("US PvP", "US PvE"))
    end)

    it("never files a character saved under \"\" with the logged-in group", function()
      -- An older Alt Army on 1.60.1 saved every ruleset's characters under "": which one is unknown until that
      -- character logs in, so none is shown with the group the player happens to be on now.
      assert.are.equal("", RF.realmGroup(""))
      assert.are.equal("", RF.realmGroup(nil))
      assert.is_false(RF.sameRealm("", "US PvE"))
      assert.is_true(RF.sameRealm("", ""))
    end)

    it("shows the group as the realm, and \"\" as a ruleset not known yet", function()
      assert.are.equal("US PvE", RF.realmLabel("US PvE"))
      assert.are.equal("US PvE", RF.realmLabel("CAMWOW US2 Realm 5 PvE"))
      assert.are.equal("Unknown ruleset", RF.realmLabel(""))
    end)

    it("leaves TBC servers alone", function()
      DS.IsWowForever = false
      assert.are.equal("Dreamscythe", RF.realmGroup("Dreamscythe"))
      assert.are.equal("Dreamscythe", RF.realmLabel("Dreamscythe"))
    end)
  end)
end)
