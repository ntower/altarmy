--[[
  Unit tests for DataStoreProfessions.lua (getters).
  Run from project root: npm test
]]

describe("DataStoreProfessions", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreItemSpellCompat")
    require("CooldownData")
    require("DataStoreProfessions")
    require("RecipeInfo")
    DS = AltArmy.DataStore
  end)

  describe("GetProfessions", function()
    it("returns empty when char nil", function()
      assert.are.same({}, DS:GetProfessions(nil))
    end)
    it("returns char.Professions or empty", function()
      local profs = { Mining = { rank = 300, maxRank = 375 } }
      local char = { Professions = profs }
      assert.are.same(profs, DS:GetProfessions(char))
      assert.are.same({}, DS:GetProfessions({}))
    end)
  end)

  describe("GetProfession", function()
    it("returns nil when char or name nil", function()
      assert.is_nil(DS:GetProfession(nil, "Mining"))
      assert.is_nil(DS:GetProfession({ Professions = {} }, nil))
    end)
    it("returns profession table when present", function()
      local prof = { rank = 300, maxRank = 375 }
      local char = { Professions = { Mining = prof } }
      assert.are.same(prof, DS:GetProfession(char, "Mining"))
    end)
  end)

  describe("ResolveSpecializationLabel", function()
    it("returns the label of the first known specialization spell", function()
      local knows = function(id) return id == 28677 end -- Master of Elixirs
      assert.are.equal("Elixir", DS.ResolveSpecializationLabel("alchemy", knows))
    end)

    it("prefers the more specific specialization listed first", function()
      -- Knows both Weaponsmith (general) and Master Swordsmith (specific) -> Swordsmith wins.
      local knows = function(id) return id == 17041 or id == 9787 end
      assert.are.equal("Swordsmith", DS.ResolveSpecializationLabel("blacksmithing", knows))
    end)

    it("returns nil when no specialization spell is known", function()
      assert.is_nil(DS.ResolveSpecializationLabel("alchemy", function() return false end))
    end)

    it("returns nil for professions without specializations or bad args", function()
      assert.is_nil(DS.ResolveSpecializationLabel("mining", function() return true end))
      assert.is_nil(DS.ResolveSpecializationLabel(nil, function() return true end))
      assert.is_nil(DS.ResolveSpecializationLabel("alchemy", nil))
    end)
  end)

  describe("GetProfession1 / GetProfession2", function()
    it("returns 0, 0, nil when char nil", function()
      local r, m, n = DS:GetProfession1(nil)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.is_nil(n)
    end)
    it("returns rank, maxRank, name for Prof1", function()
      local char = { Prof1 = "Mining", Professions = { Mining = { rank = 300, maxRank = 375 } } }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(300, r)
      assert.are.equal(375, m)
      assert.are.equal("Mining", n)
    end)
    it("returns 0, 0, name when prof missing", function()
      local char = { Prof1 = "Mining", Professions = {} }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.are.equal("Mining", n)
    end)
    it("GetProfession2 returns rank, maxRank, name", function()
      local char = { Prof2 = "Herbalism", Professions = { Herbalism = { rank = 350, maxRank = 375 } } }
      local r, m, n = DS:GetProfession2(char)
      assert.are.equal(350, r)
      assert.are.equal(375, m)
      assert.are.equal("Herbalism", n)
    end)
  end)

  describe("GetNumRecipes", function()
    it("returns 0 when char or profName nil", function()
      assert.are.equal(0, DS:GetNumRecipes(nil, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, nil))
    end)
    it("returns count of Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [1] = 1, [2] = 1, [3] = 1 } } } }
      assert.are.equal(3, DS:GetNumRecipes(char, "Mining"))
    end)
    it("returns 0 when prof or Recipes missing", function()
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = { Mining = {} } }, "Mining"))
    end)
  end)

  describe("SaveRecipeReagentsMulti", function()
    it("stores one list under every spell id key", function()
      assert.is_not_nil(DS.accountData)
      DS.accountData.RecipeReagents = {}
      DS.SaveRecipeReagentsMulti(DS, { 26751, 31373 }, { { 21840, 1 }, { 14341, 1 } })
      assert.are.same({ { 21840, 1 }, { 14341, 1 } }, DS.accountData.RecipeReagents[26751])
      assert.are.equal(DS.accountData.RecipeReagents[26751], DS.accountData.RecipeReagents[31373])
    end)
  end)

  describe("ScanTradeSkillCooldownExpiry", function()
    it("persists cooldown under cast spell id when recipe link is an item id", function()
      local oldTime = _G.time
      local oldGt = _G.GetTime
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      _G.time = function()
        return 1000
      end
      _G.GetTime = function()
        return 50
      end
      _G.GetTradeSkillLine = function()
        return "Alchemy"
      end
      _G.GetTradeSkillSelectionIndex = function()
        return 1
      end
      _G.SelectTradeSkill = function() end
      _G.ExpandAllTradeSkillHeaders = nil
      _G.GetNumTradeSkills = function()
        return 1
      end
      _G.GetTradeSkillInfo = function()
        return "Transmute: Earthstorm Diamond", "optimal"
      end
      _G.GetTradeSkillRecipeLink = function()
        return "|cff0070dd|Hitem:25868|h[Recipe: Transmute: Earthstorm Diamond]|h|r"
      end
      _G.GetTradeSkillItemLink = function()
        return "|cffa335ee|Hitem:25867|h[Earthstorm Diamond]|h|r"
      end
      _G.GetItemSpell = function(itemRef)
        if itemRef == 25868 or itemRef == 25867 then
          return "Transmute: Earthstorm Diamond", 28566
        end
        return nil
      end
      _G.GetTradeSkillCooldown = function()
        return 3600, 0
      end
      _G.GetSpellCooldown = function() end

      DS:ScanTradeSkillCooldownExpiry()

      _G.time = oldTime
      _G.GetTime = oldGt

      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.is_not_nil(char.ProfCooldownExpiry[28566])
      assert.is_true(char.ProfCooldownExpiry[28566].expiresAtUnix > 1000)
    end)
  end)

  describe("Cooldown expiry persistence guard", function()
    it("does not overwrite a known future expiry when scan returns (0,0)", function()
      local char = { ProfCooldownExpiry = { [123] = { expiresAtUnix = 1000 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 123, 0, 0, 0, 900, "Test")
      assert.is_false(changed)
      assert.are.equal(1000, char.ProfCooldownExpiry[123].expiresAtUnix)
    end)

    it("does overwrite when prior expiry is not meaningfully in the future", function()
      local char = { ProfCooldownExpiry = { [123] = { expiresAtUnix = 905 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 123, 0, 0, 0, 900, "Test")
      assert.is_true(changed)
      assert.are.equal(900, char.ProfCooldownExpiry[123].expiresAtUnix)
    end)
  end)

  describe("TryScanTrackedCooldownFromSpellApi", function()
    local saved

    before_each(function()
      saved = {
        GetSpellCooldown = _G.GetSpellCooldown, C_Spell = _G.C_Spell,
        time = _G.time, GetTime = _G.GetTime,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      DS.accountData = _G.AltArmyTBC_Data
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.time = function() return 1000 end
      _G.GetTime = function() return 50 end
    end)

    after_each(function()
      _G.GetSpellCooldown, _G.C_Spell = saved.GetSpellCooldown, saved.C_Spell
      _G.time, _G.GetTime = saved.time, saved.GetTime
    end)

    it("falls back to C_Spell.GetSpellCooldown when the global is missing (WoW Forever)", function()
      _G.GetSpellCooldown = nil
      _G.C_Spell = {
        GetSpellCooldown = function(spellId)
          if spellId == 1302508 then
            return { startTime = 50, duration = 3600, isEnabled = true, modRate = 1 }
          end
        end,
      }
      DS:TryScanTrackedCooldownFromSpellApi(1302508)
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1000 + 3600, char.ProfCooldownExpiry[1302508].expiresAtUnix)
    end)
  end)

  describe("WoW Forever's item and transmute cooldown scans", function()
    local SALT_SHAKER_ITEM, SALT_SHAKER_SPELL = 15846, 19566
    local saved

    before_each(function()
      saved = {
        GetSpellCooldown = _G.GetSpellCooldown, C_Spell = _G.C_Spell, C_Container = _G.C_Container,
        GetItemCooldown = _G.GetItemCooldown, time = _G.time, GetTime = _G.GetTime,
        IsWowForever = DS.IsWowForever,
      }
      DS.IsWowForever = true
      _G.AltArmyTBC_Data = { Characters = { TestRealm = { TestPlayer = {} } } }
      DS.accountData = _G.AltArmyTBC_Data
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.time = function() return 1000 end
      _G.GetTime = function() return 50 end
      _G.C_Container = nil
      _G.GetItemCooldown = nil
    end)

    after_each(function()
      _G.GetSpellCooldown, _G.C_Spell = saved.GetSpellCooldown, saved.C_Spell
      _G.C_Container, _G.GetItemCooldown = saved.C_Container, saved.GetItemCooldown
      _G.time, _G.GetTime = saved.time, saved.GetTime
      DS.IsWowForever = saved.IsWowForever
    end)

    local function player()
      return _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
    end

    local function holdSaltShaker()
      player().Containers = { [0] = { items = { [2] = { itemID = SALT_SHAKER_ITEM, count = 1 } } } }
    end

    it("saves the Salt Shaker's use cooldown from C_Container.GetItemCooldown under its use spell", function()
      holdSaltShaker()
      _G.C_Container = {
        GetItemCooldown = function(itemId)
          if itemId == SALT_SHAKER_ITEM then return 50, 71 * 3600, 1 end
          return 0, 0, 1
        end,
      }
      DS:TryScanTrackedItemCooldown(SALT_SHAKER_ITEM, SALT_SHAKER_SPELL)
      assert.are.equal(1000 + 71 * 3600, player().ProfCooldownExpiry[SALT_SHAKER_SPELL].expiresAtUnix)
    end)

    it("falls back to the global GetItemCooldown", function()
      holdSaltShaker()
      _G.GetItemCooldown = function() return 50, 3600, 1 end
      DS:TryScanTrackedItemCooldowns()
      assert.are.equal(1000 + 3600, player().ProfCooldownExpiry[SALT_SHAKER_SPELL].expiresAtUnix)
    end)

    it("saves nothing for a character not holding the item", function()
      _G.GetItemCooldown = function() return 50, 3600, 1 end
      DS:TryScanTrackedItemCooldowns()
      assert.is_nil(player().ProfCooldownExpiry and player().ProfCooldownExpiry[SALT_SHAKER_SPELL])
    end)

    it("doesn't copy the transmute cooldown onto Mithril to Truesilver, which has its own", function()
      player().Professions = { Alchemy = { Recipes = { [17187] = {}, [17559] = {}, [11480] = {} } } }
      _G.GetSpellCooldown = function(spellId)
        if spellId == 17187 then return 50, 47 * 3600 end
        return 0, 0
      end
      DS:TryScanTransmuteCooldownsFromSpellApi(17187)
      local exp = player().ProfCooldownExpiry
      assert.are.equal(1000 + 47 * 3600, exp[17187].expiresAtUnix)
      assert.are.equal(1000 + 47 * 3600, exp[17559].expiresAtUnix)
      assert.is_nil(exp[11480])
    end)
  end)

  describe("CooldownRemainingSecondsFromSpellApi", function()
    it("computes start+duration remaining for normal GetSpellCooldown values", function()
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(50, 3600, 100, 1000)
      assert.are.equal(3550, rem)
    end)

    it("uses duration when start exceeds GetTime (corrupted multi-day CD)", function()
      -- Repro: Mindfrell Shadowcloth — start >> gt inflated remaining by ~46 days.
      local gt = 114269856
      local duration = 331200
      local start = gt + 3935573
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(start, duration, gt, 1781451396)
      assert.are.equal(duration, rem)
    end)

    it("does not cap absurd remaining from spell cooldown math", function()
      local rem = DS._CooldownRemainingSecondsFromSpellApiForTest(50, 5000000, 100, 1000)
      assert.are.equal(4999950, rem)
    end)
  end)

  describe("CooldownRemainingSecondsFromTradeSkillApi", function()
    it("treats first return as seconds remaining", function()
      assert.are.equal(331200, DS._CooldownRemainingSecondsFromTradeSkillApiForTest(331200, 0))
    end)

    it("ignores isDayCooldown flag in second return", function()
      assert.are.equal(331200, DS._CooldownRemainingSecondsFromTradeSkillApiForTest(331200, 1))
    end)
  end)

  describe("PersistCooldownExpiry tradeskill API", function()
    it("does not overwrite future expiry when tradeskill scan returns (0,0)", function()
      local char = { ProfCooldownExpiry = { [36686] = { expiresAtUnix = 5000 } } }
      local changed = DS._PersistCooldownExpiryForTest(char, 36686, 0, 0, 50, 1000, "TradeSkill", "tradeskill")
      assert.is_false(changed)
      assert.are.equal(5000, char.ProfCooldownExpiry[36686].expiresAtUnix)
    end)

    it("persists shadowcloth duration from corrupted spell scan via duration fallback", function()
      local wall = 1781451396
      local gt = 114269856
      local duration = 331200
      local start = gt + 3935573
      local char = {}
      DS._PersistCooldownExpiryForTest(char, 36686, start, duration, gt, wall, "SpellApi", "spell")
      assert.are.equal(wall + duration, char.ProfCooldownExpiry[36686].expiresAtUnix)
    end)
  end)

  describe("ScanCraftRecipes", function()
    local scheduleCount

    before_each(function()
      scheduleCount = 0
      AltArmy.GuildShareComm = {
        ScheduleBroadcast = function()
          scheduleCount = scheduleCount + 1
        end,
      }
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
    end)

    it("calls GetCraftSkillLine with index 1 (client requires a positive index)", function()
      local oldTime = _G.time
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      local receivedIndex
      _G.GetCraftSkillLine = function(index)
        if index == nil then
          error("Usage: GetCraftSkillLine(index)")
        end
        receivedIndex = index
        return "Poisons"
      end
      _G.GetNumCrafts = function()
        return 1
      end
      _G.GetCraftInfo = function()
        return nil, nil, "optimal"
      end
      _G.GetCraftRecipeLink = function()
        return "enchant:12345"
      end
      _G.GetCraftDisplaySkillLine = function()
        return "Poisons", 340, 375
      end
      _G.time = function()
        return 0
      end
      DS:ScanCraftRecipes()
      _G.time = oldTime
      assert.are.equal(1, receivedIndex)
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.are.equal(340, char.Professions.Poisons.rank)
      assert.are.equal(375, char.Professions.Poisons.maxRank)
    end)

    it("schedules a guild-share presence broadcast after scanning craft recipes", function()
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetCraftSkillLine = function() return "Enchanting" end
      _G.GetNumCrafts = function() return 1 end
      _G.GetCraftInfo = function() return nil, nil, "optimal" end
      _G.GetCraftRecipeLink = function() return "enchant:7411" end
      _G.GetCraftDisplaySkillLine = function() return "Enchanting", 1, 75 end
      _G.time = function() return 0 end
      DS:ScanCraftRecipes()
      assert.are.equal(1, scheduleCount)
    end)

    it("updates trade skill rank from GetTradeSkillLine during ScanRecipes", function()
      _G.UnitName = function()
        return "TestPlayer"
      end
      _G.GetRealmName = function()
        return "TestRealm"
      end
      _G.GetTradeSkillLine = function()
        return "Alchemy", 360, 375
      end
      _G.GetNumTradeSkills = function()
        return 0
      end
      _G.time = function()
        return 0
      end
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char)
      assert.are.equal(360, char.Professions.Alchemy.rank)
      assert.are.equal(375, char.Professions.Alchemy.maxRank)
    end)

    it("schedules a guild-share presence broadcast after scanning trade-skill recipes", function()
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetTradeSkillLine = function() return "Alchemy", 1, 75 end
      _G.GetNumTradeSkills = function() return 1 end
      _G.GetTradeSkillInfo = function() return "Minor Healing Potion", "optimal" end
      _G.GetTradeSkillRecipeLink = function()
        return "|Hitem:118:0:0:0:0:0:0:0|h[Minor Healing Potion]|h"
      end
      _G.GetTradeSkillItemLink = function() return nil end
      _G.GetTradeSkillNumReagents = function() return 0 end
      _G.time = function() return 0 end
      DS:ScanRecipes()
      assert.are.equal(1, scheduleCount)
    end)

    it("tells linked accounts after scanning trade-skill recipes", function()
      local noted = 0
      AltArmy.LinkTransport = { NoteLocalChange = function() noted = noted + 1 end }
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetTradeSkillLine = function() return "Alchemy", 1, 75 end
      _G.GetNumTradeSkills = function() return 1 end
      _G.GetTradeSkillInfo = function() return "Minor Healing Potion", "optimal" end
      _G.GetTradeSkillRecipeLink = function()
        return "|Hitem:118:0:0:0:0:0:0:0|h[Minor Healing Potion]|h"
      end
      _G.GetTradeSkillItemLink = function() return nil end
      _G.GetTradeSkillNumReagents = function() return 0 end
      _G.time = function() return 0 end
      DS:ScanRecipes()
      AltArmy.LinkTransport = nil
      assert.are.equal(1, noted)
    end)
  end)

  describe("HasTradeSkillRecipesApi", function()
    local oldGetNumTradeSkills, oldGetTradeSkillLine, oldCTradeSkillUI

    before_each(function()
      oldGetNumTradeSkills, oldGetTradeSkillLine = _G.GetNumTradeSkills, _G.GetTradeSkillLine
      oldCTradeSkillUI = _G.C_TradeSkillUI
      _G.C_TradeSkillUI = nil
    end)

    after_each(function()
      _G.GetNumTradeSkills, _G.GetTradeSkillLine = oldGetNumTradeSkills, oldGetTradeSkillLine
      _G.C_TradeSkillUI = oldCTradeSkillUI
    end)

    it("returns true when both GetNumTradeSkills and GetTradeSkillLine exist", function()
      _G.GetNumTradeSkills = function() return 0 end
      _G.GetTradeSkillLine = function() end
      assert.is_true(DS.HasTradeSkillRecipesApi())
    end)

    it("returns false when neither the legacy nor C_TradeSkillUI API is available", function()
      _G.GetNumTradeSkills = nil
      _G.GetTradeSkillLine = nil
      assert.is_false(DS.HasTradeSkillRecipesApi())
    end)

    it("returns true via the C_TradeSkillUI fallback when the legacy pair is missing", function()
      _G.GetNumTradeSkills = nil
      _G.GetTradeSkillLine = nil
      _G.C_TradeSkillUI = {
        GetAllRecipeIDs = function() return {} end,
        GetBaseProfessionInfo = function() end,
        GetRecipeInfo = function() end,
      }
      assert.is_true(DS.HasTradeSkillRecipesApi())
    end)
  end)

  describe("ProfessionHasNoRecipeWindow", function()
    local oldGetNumTradeSkills, oldGetTradeSkillLine, oldCTradeSkillUI

    local function useLegacyApi()
      _G.GetNumTradeSkills = function() return 0 end
      _G.GetTradeSkillLine = function() end
      _G.C_TradeSkillUI = nil
    end

    local function useTradeSkillUiFallback()
      _G.GetNumTradeSkills, _G.GetTradeSkillLine = nil, nil
      _G.C_TradeSkillUI = { GetAllRecipeIDs = function() return {} end }
    end

    before_each(function()
      oldGetNumTradeSkills, oldGetTradeSkillLine = _G.GetNumTradeSkills, _G.GetTradeSkillLine
      oldCTradeSkillUI = _G.C_TradeSkillUI
    end)

    after_each(function()
      _G.GetNumTradeSkills, _G.GetTradeSkillLine = oldGetNumTradeSkills, oldGetTradeSkillLine
      _G.C_TradeSkillUI = oldCTradeSkillUI
    end)

    it("treats gathering skills and fishing as recipe-less on the legacy TBC API", function()
      useLegacyApi()
      for _, name in ipairs({ "Fishing", "Riding", "Herbalism", "Mining", "Skinning" }) do
        assert.is_true(DS.ProfessionHasNoRecipeWindow(name), name)
      end
    end)

    -- WoW Forever: Smelt Copper (Mining), Incense Candle (Herbalism), Fish Bowl (Fishing), Camp Chair (Skinning).
    it("treats only Riding as recipe-less on the C_TradeSkillUI fallback (WoW Forever)", function()
      useTradeSkillUiFallback()
      for _, name in ipairs({ "Fishing", "Herbalism", "Mining", "Skinning" }) do
        assert.is_false(DS.ProfessionHasNoRecipeWindow(name), name)
      end
      assert.is_true(DS.ProfessionHasNoRecipeWindow("Riding"))
    end)

    it("drives MarkProfessionRecipesStale: Skinning skipped on legacy, marked on the fallback", function()
      local char = {
        Professions = {
          Skinning = { rank = 150, Recipes = {} },
          Riding = { rank = 75, Recipes = {} },
        },
      }
      useLegacyApi()
      DS:MarkProfessionRecipesStale(char, "Skinning")
      assert.is_nil(char.professionsNeedingRecipeScan.Skinning)

      useTradeSkillUiFallback()
      DS:MarkProfessionRecipesStale(char, "Skinning")
      assert.is_true(char.professionsNeedingRecipeScan.Skinning)
      assert.is_nil(char.professionsNeedingRecipeScan.Riding)
    end)
  end)

  describe("ScanRecipes (C_TradeSkillUI fallback)", function()
    local scheduleCount
    local oldGetNumTradeSkills, oldGetTradeSkillLine

    before_each(function()
      scheduleCount = 0
      AltArmy.GuildShareComm = {
        ScheduleBroadcast = function()
          scheduleCount = scheduleCount + 1
        end,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      DS.accountData = _G.AltArmyTBC_Data
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.time = function() return 0 end
      oldGetNumTradeSkills, oldGetTradeSkillLine = _G.GetNumTradeSkills, _G.GetTradeSkillLine
      _G.GetNumTradeSkills, _G.GetTradeSkillLine = nil, nil
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
      _G.GetNumTradeSkills, _G.GetTradeSkillLine = oldGetNumTradeSkills, oldGetTradeSkillLine
      _G.C_TradeSkillUI = nil
    end)

    local function mockTradeSkillUI(opts)
      opts = opts or {}
      _G.C_TradeSkillUI = {
        GetBaseProfessionInfo = function()
          return {
            professionName = opts.professionName or "Leatherworking",
            skillLevel = opts.skillLevel or 300,
            maxSkillLevel = opts.maxSkillLevel or 375,
          }
        end,
        GetAllRecipeIDs = function()
          return opts.recipeIDs or {}
        end,
        GetRecipeInfo = function(recipeID)
          return opts.recipes and opts.recipes[recipeID]
        end,
        GetRecipeOutputItemData = opts.noOutputApi and nil or function(recipeID)
          local outputs = opts.outputs or {}
          return outputs[recipeID]
        end,
        GetRecipeCooldown = opts.cooldowns and function(recipeID)
          local cd = opts.cooldowns[recipeID]
          if cd == false then return nil end
          return cd, false, 0, 0
        end or nil,
        IsTradeSkillLinked = function()
          return opts.linked == true, opts.linkedName
        end,
        IsTradeSkillGuild = function() return opts.guild == true end,
        IsNPCCrafting = function() return opts.npc == true end,
      }
    end

    -- Comprehension's Study (WoW Forever): the legacy tradeskill cooldown scan can't run there.
    local STUDY = 1302508
    local studyRecipes = {
      [STUDY] = { recipeID = STUDY, categoryID = 1, name = "Study", learned = true, relativeDifficulty = 3 },
      [100] = { recipeID = 100, categoryID = 1, name = "Untracked", learned = true, relativeDifficulty = 3 },
    }

    it("doesn't store a window still listing another profession's recipes (WoW Forever)", function()
      local savedSS = AltArmy.SearchSettings
      AltArmy.SearchSettings = {
        ResolveProfessionKey = function(name)
          return ({ Cooking = "cooking", ["First Aid"] = "firstAid" })[name]
        end,
      }
      AltArmy.RecipeData = {
        recipes = {
          [3275] = { "firstAid", 1251, 1, 30, 45, "starter", false },
          [3276] = { "firstAid", 2581, 40, 50, 100, "trainer", false },
        },
      }
      AltArmy.RecipeInfo.ClearCaches()
      local firstAid = {
        [3275] = { recipeID = 3275, name = "Linen Bandage", learned = true, relativeDifficulty = 3 },
        [3276] = { recipeID = 3276, name = "Heavy Linen Bandage", learned = true, relativeDifficulty = 2 },
      }
      -- The Cooking window opened right after a First Aid read: it describes Cooking, lists First Aid.
      mockTradeSkillUI({ professionName = "Cooking", skillLevel = 37, maxSkillLevel = 75,
        recipeIDs = { 3275, 3276 }, recipes = firstAid })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(next(char.Professions.Cooking.Recipes))
      assert.is_nil(char.lastUpdate)
      -- Its own list arrives: stored. The First Aid window stores the same ids under First Aid.
      mockTradeSkillUI({ professionName = "Cooking", skillLevel = 37, maxSkillLevel = 75,
        recipeIDs = { 2538 }, recipes = { [2538] = { recipeID = 2538, name = "Charred Wolf Meat", learned = true } } })
      DS:ScanRecipes()
      assert.is_not_nil(char.Professions.Cooking.Recipes[2538])
      mockTradeSkillUI({ professionName = "First Aid", skillLevel = 84, maxSkillLevel = 150,
        recipeIDs = { 3275, 3276 }, recipes = firstAid })
      DS:ScanRecipes()
      assert.is_not_nil(char.Professions["First Aid"].Recipes[3276])
      AltArmy.SearchSettings = savedSS
      AltArmy.RecipeData = nil
      AltArmy.RecipeInfo.ClearCaches()
    end)

    it("persists tracked recipe cooldowns from GetRecipeCooldown", function()
      _G.time = function() return 1000 end
      mockTradeSkillUI({
        professionName = "Comprehension",
        recipeIDs = { STUDY, 100 },
        recipes = studyRecipes,
        cooldowns = { [STUDY] = 3600, [100] = 60 },
      })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1000 + 3600, char.ProfCooldownExpiry[STUDY].expiresAtUnix)
      assert.is_nil(char.ProfCooldownExpiry[100])
    end)

    it("persists a ready tracked recipe as expiring now when GetRecipeCooldown returns nil", function()
      _G.time = function() return 1000 end
      mockTradeSkillUI({
        professionName = "Comprehension",
        recipeIDs = { STUDY },
        recipes = studyRecipes,
        cooldowns = { [STUDY] = false },
      })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1000, char.ProfCooldownExpiry[STUDY].expiresAtUnix)
    end)

    it("populates only learned recipes, mapping relativeDifficulty to our color scale", function()
      mockTradeSkillUI({
        recipeIDs = { 100, 200 },
        recipes = {
          [100] = { recipeID = 100, categoryID = 1, name = "Learned Recipe", learned = true, relativeDifficulty = 0 },
          [200] = { recipeID = 200, categoryID = 1, name = "Unlearned Recipe", learned = false, relativeDifficulty = 3 },
        },
        outputs = {
          [100] = { icon = 1, itemID = 5555, hyperlink = "item:5555" },
        },
      })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Leatherworking.Recipes[100])
      assert.are.equal(1, char.Professions.Leatherworking.Recipes[100].color)
      assert.are.equal(5555, char.Professions.Leatherworking.Recipes[100].resultItemID)
      assert.is_nil(char.Professions.Leatherworking.Recipes[200])
    end)

    it("updates profession rank from GetBaseProfessionInfo", function()
      mockTradeSkillUI({ professionName = "Cooking", skillLevel = 150, maxSkillLevel = 375, recipeIDs = {} })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(150, char.Professions.Cooking.rank)
      assert.are.equal(375, char.Professions.Cooking.maxRank)
    end)

    it("leaves resultItemID nil when GetRecipeOutputItemData is unavailable", function()
      mockTradeSkillUI({
        noOutputApi = true,
        recipeIDs = { 100 },
        recipes = {
          [100] = { recipeID = 100, categoryID = 1, name = "Learned Recipe", learned = true, relativeDifficulty = 1 },
        },
      })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(2, char.Professions.Leatherworking.Recipes[100].color)
      assert.is_nil(char.Professions.Leatherworking.Recipes[100].resultItemID)
    end)

    it("marks dataVersions.professions as gathered and schedules a guild-share broadcast", function()
      mockTradeSkillUI({
        recipeIDs = { 100 },
        recipes = {
          [100] = { recipeID = 100, categoryID = 1, name = "Learned Recipe", learned = true, relativeDifficulty = 2 },
        },
      })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_true((char.dataVersions.professions or 0) > 0)
      assert.are.equal(1, scheduleCount)
    end)

    it("does not mark professions as scanned when no recipe IDs are returned yet", function()
      mockTradeSkillUI({ recipeIDs = {} })
      DS:ScanRecipes()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_true(not char.dataVersions or not char.dataVersions.professions)
      assert.are.equal(0, scheduleCount)
    end)

    describe("whose window is open", function()
      local learned = {
        [100] = { recipeID = 100, categoryID = 1, name = "Learned Recipe", learned = true, relativeDifficulty = 0 },
      }

      local function scanned(opts)
        opts.recipeIDs, opts.recipes = { 100 }, learned
        mockTradeSkillUI(opts)
        DS:ScanRecipes()
        local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
        local prof = char.Professions and char.Professions.Leatherworking
        return prof ~= nil and prof.Recipes ~= nil and prof.Recipes[100] ~= nil
      end

      before_each(function()
        _G.AltArmyTBC_Data.Characters = {}
      end)

      it("stores the player's own window", function()
        assert.is_true(scanned({}))
      end)

      it("stores a linked window bearing the player's own name", function()
        assert.is_true(scanned({ linked = true, linkedName = "TestPlayer" }))
        _G.AltArmyTBC_Data.Characters = {}
        assert.is_true(scanned({ linked = true, linkedName = "TestPlayer-TestRealm" }))
      end)

      it("stores a linked window bearing the player's first name and surname (WoW Forever)", function()
        -- Forever's UnitName gives the first name and the surname apart; the link carries both.
        _G.UnitName = function() return "TestPlayer", "Surname" end
        mockTradeSkillUI({ linked = true, linkedName = "TestPlayer Surname", recipeIDs = { 100 }, recipes = learned })
        DS:ScanRecipes()
        local char = _G.AltArmyTBC_Data.Characters.TestRealm["TestPlayer Surname"]
        assert.truthy(char and char.Professions.Leatherworking.Recipes[100])
      end)

      it("ignores another player's linked window", function()
        assert.is_false(scanned({ linked = true, linkedName = "Someoneelse" }))
        assert.are.equal(0, scheduleCount)
      end)

      it("ignores guild and NPC crafting windows", function()
        assert.is_false(scanned({ guild = true }))
        assert.is_false(scanned({ npc = true }))
      end)

      describe("while OwnRecipeRead reads a guildmate", function()
        local savedReader

        before_each(function()
          savedReader = AltArmy.OwnRecipeRead
          AltArmy.OwnRecipeRead = {
            IsReading = function() return false end,
            IsReadingGuild = function() return true end,
          }
        end)

        after_each(function()
          AltArmy.OwnRecipeRead = savedReader
        end)

        it("trusts no window as the player's own, linked or not", function()
          assert.is_false(scanned({}))
          assert.is_false(scanned({ linked = true }))
          assert.is_false(scanned({ linked = true, linkedName = "TestPlayer" }))
        end)
      end)

      it("neither clears the search caches nor schedules a broadcast for a window it passed over", function()
        local SD = AltArmy.SearchData
        local savedNotify = SD and SD.NotifyRecipesChanged
        local savedWipe = _G.wipe
        _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
        local notified = 0
        if SD then SD.NotifyRecipesChanged = function() notified = notified + 1 end end
        mockTradeSkillUI({ linked = true, linkedName = "Someoneelse", recipeIDs = { 100 }, recipes = learned })
        DS:RunDeferredRecipeScan()
        if SD then SD.NotifyRecipesChanged = savedNotify end
        _G.wipe = savedWipe
        assert.are.equal(0, notified)
        assert.are.equal(0, scheduleCount)
      end)
    end)
  end)

  describe("IsRecipeKnownAnyProfession", function()
    it("returns false when spell missing", function()
      local char = { Professions = { Mining = { Recipes = { [1] = {} } } } }
      assert.is_false(DS:IsRecipeKnownAnyProfession(char, 99))
    end)
    it("returns true when any profession has recipe", function()
      local char = {
        Professions = {
          Mining = { Recipes = {} },
          Alchemy = { Recipes = { [29688] = { color = 1 } } },
        },
      }
      assert.is_true(DS:IsRecipeKnownAnyProfession(char, 29688))
    end)
  end)

  describe("IsRecipeKnown", function()
    it("returns false when char or profName or spellID nil", function()
      assert.is_false(DS:IsRecipeKnown(nil, "Mining", 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, nil, 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, "Mining", nil))
    end)
    it("returns true when recipe in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_true(DS:IsRecipeKnown(char, "Mining", 123))
    end)
    it("returns false when recipe not in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_false(DS:IsRecipeKnown(char, "Mining", 999))
    end)
  end)

  describe("MigrateRecipePrimaryIds", function()
    before_each(function()
      _G.AltArmyTBC_Data = {
        Characters = {},
        recipePrimaryIdsMigrated = nil,
      }
      DS.accountData = _G.AltArmyTBC_Data
    end)

    it("backfills primaryRecipeID and skips effect spell aliases", function()
      local row = { color = 1, resultItemID = 9187 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = row,
                  [11334] = row,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11334 then return "Agility" end
        return nil
      end
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, row.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("repairs split rows sharing resultItemID", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, rowCraft.primaryRecipeID)
      assert.are.equal(11449, rowEffect.primaryRecipeID)
    end)

    it("converts numeric legacy recipe rows to tables", function()
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Mining = { Recipes = { [12345] = 2 } },
            },
          },
        },
      }
      DS:MigrateRecipePrimaryIds()
      local row = _G.AltArmyTBC_Data.Characters.Realm1.Char1.Professions.Mining.Recipes[12345]
      assert.are.same({ color = 2, primaryRecipeID = 12345 }, row)
    end)

    it("runs only once per account", function()
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [1] = { color = 1 } } },
            },
          },
        },
      }
      DS:MigrateRecipePrimaryIds()
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      local row = _G.AltArmyTBC_Data.Characters.Realm1.Char1.Professions.Alchemy.Recipes[1]
      row.primaryRecipeID = nil
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.is_nil(row.primaryRecipeID)
    end)

    it("runs when recipePrimaryIdsMigrated is unset", function()
      local row = { color = 1 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [11449] = row } },
            },
          },
        },
      }
      assert.is_nil(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      local updated = DS:MigrateRecipePrimaryIds()
      assert.is_true(updated > 0)
      assert.are.equal(11449, row.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("skips immediately when recipePrimaryIdsMigrated is already true", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.are.equal(11328, rowEffect.primaryRecipeID)
    end)

    it("RemigrateRecipePrimaryIdsDebug clears flag and re-runs migration", function()
      local rowCraft = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 }
      local rowEffect = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 }
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = {
                Recipes = {
                  [11449] = rowCraft,
                  [11328] = rowEffect,
                },
              },
            },
          },
        },
      }
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      local updated = DS:RemigrateRecipePrimaryIdsDebug()
      assert.is_true(updated > 0)
      assert.are.equal(11449, rowEffect.primaryRecipeID)
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
    end)

    it("marks account migrated even when no recipe rows need changes", function()
      local row = { color = 1, primaryRecipeID = 11449 }
      _G.AltArmyTBC_Data.Characters = {
        Realm1 = {
          Char1 = {
            Professions = {
              Alchemy = { Recipes = { [11449] = row } },
            },
          },
        },
      }
      assert.are.equal(0, DS:MigrateRecipePrimaryIds())
      assert.is_true(_G.AltArmyTBC_Data.recipePrimaryIdsMigrated)
      assert.are.equal(11449, row.primaryRecipeID)
    end)
  end)

  describe("HasProfessionsListApi", function()
    local oldGetNumSkillLines, oldGetSkillLineInfo, oldGetProfessions, oldGetProfessionInfo

    before_each(function()
      oldGetNumSkillLines, oldGetSkillLineInfo = _G.GetNumSkillLines, _G.GetSkillLineInfo
      oldGetProfessions, oldGetProfessionInfo = _G.GetProfessions, _G.GetProfessionInfo
      _G.GetProfessions, _G.GetProfessionInfo = nil, nil
    end)

    after_each(function()
      _G.GetNumSkillLines, _G.GetSkillLineInfo = oldGetNumSkillLines, oldGetSkillLineInfo
      _G.GetProfessions, _G.GetProfessionInfo = oldGetProfessions, oldGetProfessionInfo
    end)

    it("returns true when both GetNumSkillLines and GetSkillLineInfo exist", function()
      _G.GetNumSkillLines = function() return 0 end
      _G.GetSkillLineInfo = function() return nil end
      assert.is_true(DS.HasProfessionsListApi())
    end)

    it("returns false when neither the legacy nor fallback API is available (e.g. WoW Forever, unconfirmed)", function()
      _G.GetNumSkillLines = nil
      _G.GetSkillLineInfo = nil
      assert.is_false(DS.HasProfessionsListApi())
    end)

    it("returns true via the GetProfessions/GetProfessionInfo fallback when the legacy pair is missing", function()
      _G.GetNumSkillLines = nil
      _G.GetSkillLineInfo = nil
      _G.GetProfessions = function() return nil end
      _G.GetProfessionInfo = function() return nil end
      assert.is_true(DS.HasProfessionsListApi())
    end)
  end)

  describe("ScanProfessionLinks", function()
    local scheduleCount

    local function mockPlayer(name, realm)
      _G.UnitName = function()
        return name
      end
      _G.GetRealmName = function()
        return realm
      end
      _G.GetSpellInfo = function(id)
        if id == 3273 then return "First Aid" end
        return nil
      end
      _G.time = function()
        return 0
      end
      _G.ExpandSkillHeader = function() end
    end

    local function mockSkillLines(lines)
      _G.GetNumSkillLines = function()
        return #lines
      end
      _G.GetSkillLineInfo = function(i)
        local row = lines[i]
        if not row then return nil end
        return row.name, row.isHeader, nil, row.rank, nil, nil, row.maxRank
      end
    end

    local lastScheduleDelay

    before_each(function()
      scheduleCount = 0
      lastScheduleDelay = nil
      AltArmy.GuildShareComm = {
        PROFESSION_BROADCAST_DEBOUNCE_SEC = 30,
        ScheduleBroadcast = function(delay)
          scheduleCount = scheduleCount + 1
          lastScheduleDelay = delay
        end,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      DS.accountData = _G.AltArmyTBC_Data
      mockPlayer("TestPlayer", "TestRealm")
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
    end)

    it("schedules a longer quiet-period guild-share broadcast after profession link scans", function()
      mockSkillLines({
        { name = "Professions", isHeader = true },
        { name = "Alchemy", isHeader = false, rank = 1, maxRank = 75 },
      })
      DS:ScanProfessionLinks()
      assert.are.equal(1, scheduleCount)
      assert.are.equal(30, lastScheduleDelay)
    end)

    it("removes professions no longer present in skill lines", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Alchemy",
          Prof2 = "Herbalism",
          Professions = {
            Alchemy = { rank = 350, maxRank = 375, Recipes = { [1] = { color = 1 } } },
            Herbalism = { rank = 300, maxRank = 375, Recipes = {} },
            Tailoring = { rank = 375, maxRank = 375, Recipes = { [2] = { color = 1 } } },
          },
        },
      }
      mockSkillLines({
        { name = "Professions", isHeader = true },
        { name = "Alchemy", isHeader = false, rank = 350, maxRank = 375 },
        { name = "Herbalism", isHeader = false, rank = 300, maxRank = 375 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Alchemy)
      assert.is_not_nil(char.Professions.Herbalism)
      assert.is_nil(char.Professions.Tailoring)
      assert.are.equal("Alchemy", char.Prof1)
      assert.are.equal("Herbalism", char.Prof2)
    end)

    it("clears stale primary professions when the character has none trained", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Tailoring",
          Professions = {
            Tailoring = { rank = 375, maxRank = 375, Recipes = { [1] = { color = 1 } } },
          },
        },
      }
      mockSkillLines({
        { name = "Professions", isHeader = true },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(char.Prof1)
      assert.is_nil(char.Prof2)
      assert.is_nil(char.Professions.Tailoring)
    end)

    it("does not prune when profession skill categories are not loaded yet", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Professions = {
            Alchemy = { rank = 350, maxRank = 375, Recipes = {} },
          },
        },
      }
      mockSkillLines({
        { name = "Weapon Skills", isHeader = true },
        { name = "Axes", isHeader = false, rank = 300, maxRank = 300 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Alchemy)
    end)
  end)

  describe("ScanProfessionLinks (GetProfessions/GetProfessionInfo fallback)", function()
    local scheduleCount
    local oldGetNumSkillLines, oldGetSkillLineInfo

    local function mockPlayer(name, realm)
      _G.UnitName = function()
        return name
      end
      _G.GetRealmName = function()
        return realm
      end
      _G.time = function()
        return 0
      end
    end

    -- slots keyed by 1=prof1, 2=prof2, 3=fishing, 4=cooking, 5=firstAid; index maps to slots key.
    local function mockGetProfessions(slots)
      local nextIndex = 1
      local indexToInfo = {}
      local function assignIndex(slot)
        if not slots[slot] then return nil end
        local idx = nextIndex
        nextIndex = nextIndex + 1
        indexToInfo[idx] = slots[slot]
        return idx
      end
      local prof1Index = assignIndex(1)
      local prof2Index = assignIndex(2)
      local archIndex = assignIndex("arch")
      local fishIndex = assignIndex(3)
      local cookIndex = assignIndex(4)
      local firstAidIndex = assignIndex(5)
      _G.GetProfessions = function()
        return prof1Index, prof2Index, archIndex, fishIndex, cookIndex, firstAidIndex
      end
      _G.GetProfessionInfo = function(index)
        local info = indexToInfo[index]
        if not info then return nil end
        return info.name, nil, info.rank, info.maxRank
      end
    end

    before_each(function()
      scheduleCount = 0
      AltArmy.GuildShareComm = {
        PROFESSION_BROADCAST_DEBOUNCE_SEC = 30,
        ScheduleBroadcast = function()
          scheduleCount = scheduleCount + 1
        end,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      DS.accountData = _G.AltArmyTBC_Data
      mockPlayer("TestPlayer", "TestRealm")
      oldGetNumSkillLines, oldGetSkillLineInfo = _G.GetNumSkillLines, _G.GetSkillLineInfo
      _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
      _G.GetNumSkillLines, _G.GetSkillLineInfo = oldGetNumSkillLines, oldGetSkillLineInfo
      _G.GetProfessions, _G.GetProfessionInfo = nil, nil
    end)

    it("populates primary professions (including gathering) via GetProfessions/GetProfessionInfo", function()
      mockGetProfessions({
        [1] = { name = "Mining", rank = 300, maxRank = 375 },
        [2] = { name = "Tailoring", rank = 350, maxRank = 375 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal("Mining", char.Prof1)
      assert.are.equal("Tailoring", char.Prof2)
      assert.are.equal(300, char.Professions.Mining.rank)
      assert.are.equal(375, char.Professions.Mining.maxRank)
      assert.is_true(char.Professions.Mining.isPrimary)
      assert.are.equal(350, char.Professions.Tailoring.rank)
      assert.is_true(char.Professions.Tailoring.isPrimary)
    end)

    it("populates secondary professions (cooking/fishing) as isSecondary", function()
      mockGetProfessions({
        [3] = { name = "Fishing", rank = 100, maxRank = 375 },
        [4] = { name = "Cooking", rank = 150, maxRank = 375 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_true(char.Professions.Fishing.isSecondary)
      assert.is_nil(char.Professions.Fishing.isPrimary)
      assert.are.equal(100, char.Professions.Fishing.rank)
      assert.is_true(char.Professions.Cooking.isSecondary)
      assert.are.equal(150, char.Professions.Cooking.rank)
    end)

    it("marks dataVersions.professions as gathered even though no window was ever opened", function()
      mockGetProfessions({ [1] = { name = "Alchemy", rank = 1, maxRank = 75 } })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_true((char.dataVersions.professions or 0) > 0)
    end)

    it("removes professions whose slot no longer reports an index (dropped profession)", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Tailoring",
          Professions = {
            Tailoring = { rank = 375, maxRank = 375, Recipes = { [1] = { color = 1 } } },
          },
        },
      }
      mockGetProfessions({ [1] = { name = "Alchemy", rank = 1, maxRank = 75 } })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(char.Professions.Tailoring)
      assert.is_not_nil(char.Professions.Alchemy)
      assert.are.equal("Alchemy", char.Prof1)
    end)

    it("keeps Comprehension, which no GetProfessions slot reports (WoW Forever)", function()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Prof1 = "Tailoring",
          Professions = {
            Tailoring = { rank = 112, maxRank = 150, Recipes = {} },
            Comprehension = { rank = 24, maxRank = 100, Recipes = { [1302508] = { name = "Study" } } },
          },
        },
      }
      mockGetProfessions({ [1] = { name = "Tailoring", rank = 112, maxRank = 150 } })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_not_nil(char.Professions.Comprehension)
      assert.is_not_nil(char.Professions.Comprehension.Recipes[1302508])
      assert.are.equal(24, char.Professions.Comprehension.rank)
    end)

    it("reads First Aid from the slot other clients give Archaeology (WoW Forever)", function()
      mockGetProfessions({
        [1] = { name = "Tailoring", rank = 112, maxRank = 150 },
        arch = { name = "First Aid", rank = 84, maxRank = 150 },
        [4] = { name = "Cooking", rank = 37, maxRank = 75 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      local firstAid = char.Professions["First Aid"]
      assert.is_not_nil(firstAid)
      assert.are.equal(84, firstAid.rank)
      assert.are.equal(150, firstAid.maxRank)
      assert.is_true(firstAid.isSecondary)
      assert.is_nil(firstAid.isPrimary)
      assert.are.equal("Tailoring", char.Prof1)
      assert.is_nil(char.Prof2)
      assert.are.equal(37, char.Professions.Cooking.rank)
    end)

    it("still skips Archaeology, by name", function()
      mockGetProfessions({
        [1] = { name = "Tailoring", rank = 112, maxRank = 150 },
        arch = { name = "Archaeology", rank = 50, maxRank = 75 },
      })
      DS:ScanProfessionLinks()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(char.Professions.Archaeology)
      assert.is_not_nil(char.Professions.Tailoring)
    end)

    it("clears a recipe list stored under the wrong profession and marks it stale", function()
      local savedSS = AltArmy.SearchSettings
      AltArmy.SearchSettings = {
        ResolveProfessionKey = function(name)
          return ({ Cooking = "cooking", ["First Aid"] = "firstAid" })[name]
        end,
      }
      AltArmy.RecipeData = {
        recipes = {
          [3275] = { "firstAid", 1251, 1, 30, 45, "starter", false },
          [3276] = { "firstAid", 2581, 40, 50, 100, "trainer", false },
          [2538] = { "cooking", 2679, 1, 45, 85, "starter", false },
        },
      }
      AltArmy.RecipeInfo.ClearCaches()
      _G.AltArmyTBC_Data.Characters.TestRealm = {
        TestPlayer = {
          Professions = {
            Cooking = { rank = 37, maxRank = 75, Recipes = { [3275] = { color = 1 }, [3276] = { color = 1 } } },
            ["First Aid"] = { rank = 84, maxRank = 150, Recipes = { [3275] = { color = 1 }, [3276] = { color = 1 } } },
          },
        },
      }
      mockGetProfessions({
        arch = { name = "First Aid", rank = 84, maxRank = 150 },
        [4] = { name = "Cooking", rank = 37, maxRank = 75 },
      })
      DS:ScanProfessionLinks()
      AltArmy.SearchSettings = savedSS
      AltArmy.RecipeData = nil
      AltArmy.RecipeInfo.ClearCaches()
      local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.is_nil(next(char.Professions.Cooking.Recipes))
      assert.is_true(char.professionsNeedingRecipeScan.Cooking)
      assert.is_not_nil(char.Professions["First Aid"].Recipes[3276])
      assert.is_nil(char.professionsNeedingRecipeScan["First Aid"])
    end)

    it("schedules a guild-share broadcast when profession presence changes", function()
      mockGetProfessions({ [1] = { name = "Alchemy", rank = 1, maxRank = 75 } })
      DS:ScanProfessionLinks()
      assert.are.equal(1, scheduleCount)
    end)
  end)

  describe("OnNewRecipeLearned", function()
    local deferredScanCalls
    local craftScanCalls

    local function mockPlayer(name, realm)
      _G.UnitName = function()
        return name
      end
      _G.GetRealmName = function()
        return realm
      end
      _G.time = function()
        return 1000
      end
    end

    before_each(function()
      deferredScanCalls = 0
      craftScanCalls = 0
      AltArmy.GuildShareComm = {
        PROFESSION_BROADCAST_DEBOUNCE_SEC = 30,
        ScheduleBroadcast = function() end,
      }
      _G.AltArmyTBC_Data = { Characters = {} }
      mockPlayer("TestPlayer", "TestRealm")
      _G.GetTradeSkillLine = function()
        return "UNKNOWN"
      end
      _G.GetCraftSkillLine = nil
      DS.RunDeferredRecipeScan = function()
        deferredScanCalls = deferredScanCalls + 1
      end
      DS.ScanCraftRecipes = function()
        craftScanCalls = craftScanCalls + 1
      end
    end)

    it("marks professions stale even when recipe id is nil", function()
      local char = DS:_GetCurrentCharTable()
      char.Professions = {
        Enchanting = { rank = 300, maxRank = 375, Recipes = { [1] = true } },
      }
      DS:OnNewRecipeLearned(nil)
      assert.is_true(char.professionsNeedingRecipeScan.Enchanting)
      assert.are.equal(0, deferredScanCalls)
    end)

    it("runs deferred trade-skill scan when TradeSkill UI is open", function()
      _G.GetTradeSkillLine = function()
        return "Alchemy", 300, 375
      end
      local char = DS:_GetCurrentCharTable()
      char.Professions = { Alchemy = { rank = 300, maxRank = 375, Recipes = {} } }
      DS:OnNewRecipeLearned(11449)
      assert.are.equal(1, deferredScanCalls)
      assert.are.equal(0, craftScanCalls)
      assert.is_nil(char.professionsNeedingRecipeScan)
    end)

    it("runs craft scan when Craft UI is open and TradeSkill is not", function()
      _G.GetTradeSkillLine = function()
        return "UNKNOWN"
      end
      _G.GetCraftSkillLine = function()
        return "Enchanting"
      end
      local char = DS:_GetCurrentCharTable()
      char.Professions = { Enchanting = { rank = 300, maxRank = 375, Recipes = {} } }
      DS:OnNewRecipeLearned(7418)
      assert.are.equal(0, deferredScanCalls)
      assert.are.equal(1, craftScanCalls)
      assert.is_nil(char.professionsNeedingRecipeScan)
    end)

    it("marks craftable professions stale when UI is closed", function()
      local char = DS:_GetCurrentCharTable()
      char.Professions = {
        Alchemy = { rank = 300, maxRank = 375, Recipes = { [11449] = { color = 1 } } },
        Tailoring = { rank = 375, maxRank = 375, Recipes = { [1] = true } },
        Mining = { rank = 300, maxRank = 375, Recipes = {} },
        Fishing = { rank = 300, maxRank = 375, Recipes = {} },
      }
      DS:OnNewRecipeLearned(18560)
      assert.is_true(char.professionsNeedingRecipeScan.Alchemy)
      assert.is_true(char.professionsNeedingRecipeScan.Tailoring)
      assert.is_nil(char.professionsNeedingRecipeScan.Mining)
      assert.is_nil(char.professionsNeedingRecipeScan.Fishing)
      assert.are.equal(0, deferredScanCalls)
    end)

    describe("with bundled recipe data", function()
      local savedSpellInfo
      local broadcastCalls

      before_each(function()
        savedSpellInfo = _G.GetSpellInfo
        _G.GetSpellInfo = function(id)
          local names = { [3908] = "Tailoring", [2259] = "Alchemy", [18560] = "Mooncloth" }
          return names[id]
        end
        broadcastCalls = 0
        AltArmy.GuildShareComm.ScheduleBroadcast = function()
          broadcastCalls = broadcastCalls + 1
        end
        AltArmy.RecipeData = {
          recipes = { [18560] = { "tailoring", 14342, 250, 270, 290, "drop", 14526 } },
        }
        AltArmy.RecipeInfo.ClearCaches()
      end)

      after_each(function()
        _G.GetSpellInfo = savedSpellInfo
        AltArmy.RecipeData = nil
        AltArmy.RecipeInfo.ClearCaches()
      end)

      it("stores the learned recipe with its difficulty color and keeps the profession fresh", function()
        local char = DS:_GetCurrentCharTable()
        char.Professions = {
          Alchemy = { rank = 300, maxRank = 375, Recipes = { [11449] = { color = 1 } } },
          Tailoring = { rank = 275, maxRank = 300, Recipes = { [1] = true } },
        }
        DS:OnNewRecipeLearned(18560)
        assert.are.same({
          color = 2, -- yellow at 275 (yellow 270, green 280)
          resultItemID = 14342,
          primaryRecipeID = 18560,
        }, char.Professions.Tailoring.Recipes[18560])
        assert.is_nil(char.professionsNeedingRecipeScan)
        assert.is_true(broadcastCalls >= 1)
      end)

      it("leaves an already known recipe alone without marking anything stale", function()
        local char = DS:_GetCurrentCharTable()
        char.Professions = {
          Tailoring = {
            rank = 300,
            maxRank = 375,
            Recipes = { [18560] = { color = 2, resultItemID = 14342, primaryRecipeID = 18560 } },
          },
        }
        DS:OnNewRecipeLearned(18560)
        assert.are.equal(2, char.Professions.Tailoring.Recipes[18560].color)
        assert.is_nil(char.professionsNeedingRecipeScan)
        assert.are.equal(0, broadcastCalls)
      end)

      it("falls back to all craftable professions when the recipe is unknown", function()
        local char = DS:_GetCurrentCharTable()
        char.Professions = {
          Alchemy = { rank = 300, maxRank = 375, Recipes = {} },
          Tailoring = { rank = 375, maxRank = 375, Recipes = {} },
        }
        DS:OnNewRecipeLearned(999999)
        assert.is_true(char.professionsNeedingRecipeScan.Alchemy)
        assert.is_true(char.professionsNeedingRecipeScan.Tailoring)
      end)

      it("marks the whole set stale when the character has no row for the recipe's profession", function()
        local char = DS:_GetCurrentCharTable()
        char.Professions = { Alchemy = { rank = 300, maxRank = 375, Recipes = {} } }
        DS:OnNewRecipeLearned(18560)
        assert.is_true(char.professionsNeedingRecipeScan.Alchemy)
      end)
    end)

    it("ClearProfessionRecipesStale removes one profession and drops empty table", function()
      local char = DS:_GetCurrentCharTable()
      char.professionsNeedingRecipeScan = { Alchemy = true, Tailoring = true }
      DS:ClearProfessionRecipesStale("Alchemy", char)
      assert.is_nil(char.professionsNeedingRecipeScan.Alchemy)
      assert.is_true(char.professionsNeedingRecipeScan.Tailoring)
      DS:ClearProfessionRecipesStale("Tailoring", char)
      assert.is_nil(char.professionsNeedingRecipeScan)
    end)
  end)

  describe("IsProfessionRecipeLearnSystemMessage", function()
    it("matches ERR_LEARN_RECIPE_S and English recipe fallback", function()
      _G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
      _G.ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
      assert.is_true(DS:IsProfessionRecipeLearnSystemMessage(
        "You have learned how to create a new item: Major Healing Potion."))
      assert.is_true(DS:IsProfessionRecipeLearnSystemMessage(
        "You have learned how to create a new item: Mooncloth."))
    end)

    it("matches enchant formula learn lines but not arbitrary new spells", function()
      _G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
      _G.ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
      assert.is_true(DS:IsProfessionRecipeLearnSystemMessage(
        "You have learned a new spell: Enchant Cloak - Greater Shadow Resistance."))
      assert.is_false(DS:IsProfessionRecipeLearnSystemMessage(
        "You have learned a new spell: Fireball."))
      assert.is_false(DS:IsProfessionRecipeLearnSystemMessage("Some other system message."))
    end)

    it("returns nil instead of erroring when inspecting msg throws (e.g. a tainted/secret chat string)", function()
      _G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
      _G.ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
      local originalMatch = string.match
      string.match = function(...)
        error("attempt to compare local 'msg' (a secret string value, while execution tainted by 'AltArmy_TBC'")
      end
      local ok, result = pcall(function()
        return DS:GetProfessionRecipeLearnName("You have learned how to create a new item: Mooncloth.")
      end)
      string.match = originalMatch
      assert.is_true(ok)
      assert.is_nil(result)
    end)

    it("returns nil via canaccessvalue without ever touching the value's content", function()
      _G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
      _G.ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
      local checked
      _G.canaccessvalue = function(v)
        checked = v
        return false
      end
      local result = DS:GetProfessionRecipeLearnName(
        "You have learned how to create a new item: Mooncloth.")
      _G.canaccessvalue = nil
      assert.is_nil(result)
      assert.are.equal("You have learned how to create a new item: Mooncloth.", checked)
    end)
  end)

  describe("OnProfessionLearnSystemMessage", function()
    local function mockPlayer(name, realm)
      _G.UnitName = function()
        return name
      end
      _G.GetRealmName = function()
        return realm
      end
    end

    before_each(function()
      _G.AltArmyTBC_Data = { Characters = {} }
      mockPlayer("TestPlayer", "TestRealm")
      _G.GetTradeSkillLine = function()
        return "UNKNOWN"
      end
      _G.GetCraftSkillLine = nil
      _G.ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
      _G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
    end)

    it("marks professions stale for enchant learn system chat when Craft UI is closed", function()
      local char = DS:_GetCurrentCharTable()
      char.Professions = {
        Enchanting = { rank = 350, maxRank = 375, Recipes = { [7418] = true } },
      }
      local ok = DS:OnProfessionLearnSystemMessage(
        "You have learned a new spell: Enchant Cloak - Greater Shadow Resistance.")
      assert.is_true(ok)
      assert.is_true(char.professionsNeedingRecipeScan.Enchanting)
    end)

    it("stores the recipe named in learn chat and keeps the profession fresh", function()
      local broadcastCalls = 0
      AltArmy.GuildShareComm = {
        PROFESSION_BROADCAST_DEBOUNCE_SEC = 30,
        ScheduleBroadcast = function()
          broadcastCalls = broadcastCalls + 1
        end,
      }
      local savedSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        local names = { [2259] = "Alchemy", [3908] = "Tailoring", [17556] = "Major Healing Potion" }
        return names[id]
      end
      AltArmy.RecipeData = {
        recipes = { [17556] = { "alchemy", 13446, 275, 290, 310, "trainer", false } },
      }
      AltArmy.RecipeInfo.ClearCaches()
      local char = DS:_GetCurrentCharTable()
      char.Professions = {
        Alchemy = { rank = 300, maxRank = 375, Recipes = {} },
        Tailoring = { rank = 375, maxRank = 375, Recipes = {} },
      }
      local ok = DS:OnProfessionLearnSystemMessage(
        "You have learned how to create a new item: Major Healing Potion.")
      _G.GetSpellInfo = savedSpellInfo
      AltArmy.RecipeData = nil
      AltArmy.RecipeInfo.ClearCaches()
      assert.is_true(ok)
      assert.are.same({
        color = 3, -- green at 300 (green 300, gray 310)
        resultItemID = 13446,
        primaryRecipeID = 17556,
      }, char.Professions.Alchemy.Recipes[17556])
      assert.is_nil(char.professionsNeedingRecipeScan)
      assert.is_true(broadcastCalls >= 1)
    end)

    it("ignores unrelated system chat", function()
      local char = DS:_GetCurrentCharTable()
      char.Professions = {
        Enchanting = { rank = 350, maxRank = 375, Recipes = { [7418] = true } },
      }
      assert.is_false(DS:OnProfessionLearnSystemMessage("You have learned a new spell: Fireball."))
      assert.is_nil(char.professionsNeedingRecipeScan)
    end)
  end)
end)
