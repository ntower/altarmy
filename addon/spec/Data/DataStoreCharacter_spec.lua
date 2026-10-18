--[[
  Unit tests for DataStoreCharacter.lua (rest XP, getters).
  Run from project root: npm test
]]

describe("DataStoreCharacter", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("CharKey")
    require("DataStore")
    require("DataStoreCharacter")
    DS = AltArmy.DataStore
  end)

  describe("GetStoredRestXp", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetStoredRestXp(nil), 0)
    end)
    it("returns 0 at max level", function()
      assert.are.equal(DS:GetStoredRestXp({ level = 70, xpMax = 1000, restXP = 500 }), 0)
    end)
    it("returns 0 when xpMax <= 0", function()
      assert.are.equal(DS:GetStoredRestXp({ level = 1, xpMax = 0, restXP = 100 }), 0)
    end)
    it("returns min(100, (restXP/maxRest)*100)", function()
      local char = { level = 1, xpMax = 1000, restXP = 750 }
      local maxRest = 1000 * 1.5
      local expected = math.min(100, (750 / maxRest) * 100)
      assert.are.equal(expected, DS:GetStoredRestXp(char))
    end)
    it("caps at 100", function()
      local char = { level = 1, xpMax = 1000, restXP = 2000 }
      assert.are.equal(100, DS:GetStoredRestXp(char))
    end)
  end)

  describe("GetRestXp", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetRestXp(nil), 0)
    end)
    it("returns 0 at max level", function()
      assert.are.equal(DS:GetRestXp({ level = 70, xpMax = 1000, restXP = 500 }), 0)
    end)
    it("uses stored rate when lastLogout >= sentinel", function()
      local char = { level = 1, xpMax = 1000, restXP = 750, lastLogout = 5000000000 }
      local maxRest = 1000 * 1.5
      local expected = math.min(100, (750 / maxRest) * 100)
      assert.are.equal(expected, DS:GetRestXp(char))
    end)

    describe("accumulation since logout", function()
      local savedTime
      before_each(function()
        savedTime = _G.time
        _G.time = function() return 1000 + 28800 * 4 end
      end)
      after_each(function() _G.time = savedTime end)

      -- 32 hours offline: four bubbles (50 of a 1000 xpMax each) in an inn, one outside.
      it("earns a bubble every 8 hours when it logged out resting", function()
        local char = { level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000, isResting = true }
        assert.are.equal(200 / 1500 * 100, DS:GetRestXp(char))
      end)
      it("earns a quarter of that when it logged out outside a resting area", function()
        local char = { level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000, isResting = false }
        assert.are.equal(50 / 1500 * 100, DS:GetRestXp(char))
      end)
      it("counts as resting when it was saved before the addon kept it", function()
        local char = { level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000 }
        assert.are.equal(200 / 1500 * 100, DS:GetRestXp(char))
      end)
      it("gives the amounts and the time until full at the rate it rests", function()
        local inn = DS:GetRestXpInfo({ level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000, isResting = true })
        assert.are.same({ max = 1500, current = 200, secondsToFull = 26 * 28800 }, inn)
        local out = DS:GetRestXpInfo({ level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000, isResting = false })
        assert.are.same({ max = 1500, current = 50, secondsToFull = 29 * 28800 * 4 }, out)
      end)
      it("reads a logged-in character live: rest grows only while it rests", function()
        local char = { level = 1, xpMax = 1, restXP = 0 }
        local resting = DS:GetRestXpInfo(char, { restXP = 300, xpMax = 1000, resting = true })
        assert.are.same({ max = 1500, current = 300, secondsToFull = 24 * 28800 }, resting)
        local outside = DS:GetRestXpInfo(char, { restXP = 300, xpMax = 1000, resting = false })
        assert.is_nil(outside.secondsToFull)
      end)
      it("is full when capped", function()
        local char = { level = 1, xpMax = 1000, restXP = 1500, lastLogout = 1000 }
        assert.are.equal(0, DS:GetRestXpInfo(char).secondsToFull)
      end)
    end)
  end)

  describe("Legacy Talent rest-XP multiplier (WoW Forever)", function()
    setup(function()
      _G.AltArmy.DataStoreLegacy = { GetRestXpMultiplier = function(char)
        local rank = char and char.legacyTalents and char.legacyTalents.restRank or 0
        return 1 + (rank * 0.04)
      end }
    end)

    teardown(function()
      _G.AltArmy.DataStoreLegacy = nil
    end)

    it("GetStoredRestXp widens the cap by the Legacy Talent multiplier", function()
      local char = { level = 1, xpMax = 1000, restXP = 750, legacyTalents = { restRank = 5 } }
      local maxRest = 1000 * 1.5 * 1.2
      local expected = math.min(100, (750 / maxRest) * 100)
      assert.are.equal(expected, DS:GetStoredRestXp(char))
    end)

    it("GetRestXp widens both the cap and the accumulation rate", function()
      local char = {
        level = 1, xpMax = 1000, restXP = 0, lastLogout = 1000,
        legacyTalents = { restRank = 5 },
      }
      _G.time = function() return 1000 + 28800 end
      local maxRest = 1000 * 1.5 * 1.2
      local oneXPBubble = (1000 / 20) * 1.2
      local expected = math.min(100, (oneXPBubble / maxRest) * 100)
      assert.are.equal(expected, DS:GetRestXp(char))
    end)
  end)

  describe("getters", function()
    it("GetCharacterName returns name or empty", function()
      assert.are.equal("Alice", DS:GetCharacterName({ name = "Alice" }))
      assert.are.equal("", DS:GetCharacterName(nil))
      assert.are.equal("", DS:GetCharacterName({}))
    end)
    it("GetCharacterLevel returns level or 0", function()
      assert.are.equal(60, DS:GetCharacterLevel({ level = 60 }))
      assert.are.equal(0, DS:GetCharacterLevel(nil))
    end)
    it("GetMoney returns money or 0", function()
      assert.are.equal(1000, DS:GetMoney({ money = 1000 }))
      assert.are.equal(0, DS:GetMoney(nil))
    end)
    it("GetPlayTime returns played or 0", function()
      assert.are.equal(3600, DS:GetPlayTime({ played = 3600 }))
      assert.are.equal(0, DS:GetPlayTime(nil))
    end)
    it("GetPlayTime returns derived total for the logged-in character", function()
      require("DataStoreLevelHistory")
      DS._ResetLevelHistoryTestState()
      _G.time = function() return 1700000000 end
      _G.UnitName = function() return "Bob" end
      _G.GetRealmName = function() return "Faerlina" end
      AltArmyTBC_Data.Characters = {
        Faerlina = {
          Bob = { name = "Bob", realm = "Faerlina", played = 3600 },
        },
      }
      local char = AltArmyTBC_Data.Characters.Faerlina.Bob
      DS:UpdatePlayedBaseline(5000)
      _G.time = function() return 1700000600 end

      assert.are.equal(5600, DS:GetPlayTime(char))
    end)
    it("GetPlayTime returns stored played for other characters", function()
      require("DataStoreLevelHistory")
      DS._ResetLevelHistoryTestState()
      _G.UnitName = function() return "Bob" end
      _G.GetRealmName = function() return "Faerlina" end
      AltArmyTBC_Data.Characters = {
        Faerlina = {
          Bob = { name = "Bob", realm = "Faerlina", played = 5000 },
        },
      }
      DS:UpdatePlayedBaseline(5000)
      local alt = { name = "Alice", realm = "Faerlina", played = 3600 }

      assert.are.equal(3600, DS:GetPlayTime(alt))
    end)
    it("GetLastLogout returns lastLogout or sentinel", function()
      assert.are.equal(123, DS:GetLastLogout({ lastLogout = 123 }))
      assert.are.equal(5000000000, DS:GetLastLogout(nil))
    end)
    it("GetCharacterClass returns class and classFile", function()
      local a, b = DS:GetCharacterClass({ class = "Warrior", classFile = "WARRIOR" })
      assert.are.equal("Warrior", a)
      assert.are.equal("WARRIOR", b)
      local c, d = DS:GetCharacterClass(nil)
      assert.are.equal("", c)
      assert.are.equal("", d)
    end)
    it("GetCharacterFaction returns faction or empty", function()
      assert.are.equal("Alliance", DS:GetCharacterFaction({ faction = "Alliance" }))
      assert.are.equal("", DS:GetCharacterFaction(nil))
    end)
    it("GetCharacterGuild returns guildName or nil", function()
      assert.are.equal("The Guild", DS:GetCharacterGuild({ guildName = "The Guild" }))
      assert.is_nil(DS:GetCharacterGuild({}))
      assert.is_nil(DS:GetCharacterGuild(nil))
    end)
  end)

  describe("ScanCharacter guild capture", function()
    local function stubUnitGlobals()
      _G.UnitName = function() return "Scanner" end
      _G.GetRealmName = function() return "Faerlina" end
      _G.UnitLevel = function() return 42 end
      _G.GetMoney = function() return 0 end
      _G.UnitClass = function() return "Mage", "MAGE" end
      _G.UnitRace = function() return "Gnome", "GNOME" end
      _G.UnitSex = function() return 2 end
      _G.UnitFactionGroup = function() return "Alliance" end
      _G.UnitXP = function() return 0 end
      _G.UnitXPMax = function() return 100 end
      _G.GetXPExhaustion = function() return 0 end
      _G.time = function() return 1700000000 end
    end

    before_each(function()
      AltArmyTBC_Data.Characters = {}
      stubUnitGlobals()
    end)

    it("stores the current guild name from GetGuildInfo", function()
      _G.GetGuildInfo = function(unit)
        if unit == "player" then return "Knights of Faerlina" end
      end
      DS:ScanCharacter()
      local char = AltArmyTBC_Data.Characters.Faerlina.Scanner
      assert.are.equal("Knights of Faerlina", char.guildName)
      assert.are.equal(1, char.dataVersions.guildMembership)
    end)

    it("clears the guild name when not in a guild", function()
      AltArmyTBC_Data.Characters.Faerlina = {
        Scanner = { name = "Scanner", realm = "Faerlina", guildName = "Old Guild" },
      }
      _G.GetGuildInfo = function() return nil end
      DS:ScanCharacter()
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.Scanner.guildName)
      assert.are.equal(1, AltArmyTBC_Data.Characters.Faerlina.Scanner.dataVersions.guildMembership)
    end)
  end)

  describe("ScanCharacter on WoW Forever", function()
    -- Forever's UnitName returns the first name and surname separately ("Frell", "Ofelements"), and
    -- several characters can share a first name. Entries are keyed by GUID and named in full.
    local REALM = "Classic Beta PvE"
    local guid, surname, classFile
    before_each(function()
      AltArmyTBC_Data.Characters = {}
      guid, surname, classFile = "Player-1-A", "Ofelements", "SHAMAN"
      _G.UnitName = function() return "Frell", surname end
      _G.GetRealmName = function() return REALM end
      _G.UnitLevel = function() return 21 end
      _G.GetMoney = function() return 500 end
      _G.UnitClass = function() return classFile, classFile end
      _G.UnitRace = function() return "Tauren", "TAUREN" end
      _G.UnitSex = function() return 2 end
      _G.UnitFactionGroup = function() return "Horde" end
      _G.UnitXP = function() return 0 end
      _G.UnitXPMax = function() return 100 end
      _G.GetXPExhaustion = function() return 0 end
      _G.GetGuildInfo = function() return nil end
      _G.UnitGUID = function(unit) if unit == "player" then return guid end end
      _G.time = function() return 1700000000 end
      _G.AltArmyTBC_GraphSettings = nil
    end)
    after_each(function()
      _G.UnitGUID = nil
      _G.AltArmyTBC_GraphSettings = nil
    end)

    local function realmChars()
      AltArmyTBC_Data.Characters[REALM] = AltArmyTBC_Data.Characters[REALM] or {}
      return AltArmyTBC_Data.Characters[REALM]
    end

    local function oldEntry(key, fields)
      local e = {
        name = key, realm = REALM, level = 20, money = 100,
        class = "Shaman", classFile = "SHAMAN", raceFile = "TAUREN", faction = "Horde",
        Professions = { Leatherworking = { rank = 102 } },
      }
      for k, v in pairs(fields or {}) do e[k] = v end
      realmChars()[key] = e
      return e
    end

    local function keys()
      local out = {}
      for k in pairs(realmChars()) do out[#out + 1] = k end
      table.sort(out)
      return out
    end

    it("stores the full name under the GUID", function()
      DS:ScanCharacter()
      assert.are.same({ "Player-1-A" }, keys())
      local char = realmChars()["Player-1-A"]
      assert.are.equal("Frell Ofelements", char.name)
      assert.are.equal("Player-1-A", char.guid)
      assert.are.equal(3, char.dataVersions.character)
    end)

    it("keeps two characters that share a first name apart", function()
      DS:ScanCharacter()
      guid, surname, classFile = "Player-1-B", "Blast", "MAGE"
      _G.UnitLevel = function() return 20 end
      DS:ScanCharacter()
      assert.are.same({ "Player-1-A", "Player-1-B" }, keys())
      assert.are.equal("Frell Ofelements", realmChars()["Player-1-A"].name)
      assert.are.equal(21, realmChars()["Player-1-A"].level)
      assert.are.equal("SHAMAN", realmChars()["Player-1-A"].classFile)
      assert.are.equal("Frell Blast", realmChars()["Player-1-B"].name)
      assert.are.equal(20, realmChars()["Player-1-B"].level)
      assert.are.equal("MAGE", realmChars()["Player-1-B"].classFile)
    end)

    it("adopts the old entry saved under the full name", function()
      oldEntry("Frell Ofelements")
      DS:ScanCharacter()
      assert.are.same({ "Player-1-A" }, keys())
      local char = realmChars()["Player-1-A"]
      -- Fresh scan values win; what this scan does not write is kept from the old entry.
      assert.are.equal("Frell Ofelements", char.name)
      assert.are.equal(21, char.level)
      assert.are.equal(500, char.money)
      assert.are.equal(102, char.Professions.Leatherworking.rank)
    end)

    it("adopts an entry with the same GUID under any key", function()
      oldEntry("Frell", { guid = "Player-1-A" })
      DS:ScanCharacter()
      assert.are.same({ "Player-1-A" }, keys())
      assert.are.equal("Frell Ofelements", realmChars()["Player-1-A"].name)
    end)

    it("leaves other characters that share the first name alone", function()
      oldEntry("Frell", { guid = "Player-1-B", classFile = "MAGE" })
      oldEntry("Frell Blast", { class = "Mage", classFile = "MAGE" })
      oldEntry("Frell Hound", { guid = "Player-1-C" })
      oldEntry("Frells Angel")
      DS:ScanCharacter()
      assert.are.same({ "Frell", "Frell Blast", "Frell Hound", "Frells Angel", "Player-1-A" }, keys())
      assert.are.equal("MAGE", realmChars().Frell.classFile)
    end)

    it("leaves other realms alone", function()
      AltArmyTBC_Data.Characters["Other Realm"] = {
        ["Frell Ofelements"] = { name = "Frell Ofelements", classFile = "SHAMAN", raceFile = "TAUREN", faction = "Horde" },
      }
      DS:ScanCharacter()
      assert.is_not_nil(AltArmyTBC_Data.Characters["Other Realm"]["Frell Ofelements"])
    end)

    it("carries per-character settings over when the name changes", function()
      _G.AltArmyTBC_GraphSettings = { selected = { [REALM .. "\\Frell"] = true } }
      oldEntry("Player-1-A", { name = "Frell", guid = "Player-1-A" })
      DS:ScanCharacter()
      assert.are.equal("Frell Ofelements", realmChars()["Player-1-A"].name)
      assert.are.same({ [REALM .. "\\Frell Ofelements"] = true }, AltArmyTBC_GraphSettings.selected)
    end)

    it("carries settings over from an adopted entry's old name", function()
      _G.AltArmyTBC_GraphSettings = { selected = { [REALM .. "\\Frell"] = true } }
      oldEntry("Frell", { guid = "Player-1-A" })
      DS:ScanCharacter()
      assert.are.same({ [REALM .. "\\Frell Ofelements"] = true }, AltArmyTBC_GraphSettings.selected)
    end)
  end)

  describe("ScanGuildMembership", function()
    before_each(function()
      AltArmyTBC_Data.Characters = {}
      _G.UnitName = function() return "Scanner" end
      _G.GetRealmName = function() return "Faerlina" end
    end)

    it("updates guildName and guildMembership without a full character scan", function()
      AltArmyTBC_Data.Characters.Faerlina = {
        Scanner = { name = "Scanner", realm = "Faerlina", level = 10, money = 999 },
      }
      _G.GetGuildInfo = function() return "Knights of Faerlina" end
      DS:ScanGuildMembership()
      local char = AltArmyTBC_Data.Characters.Faerlina.Scanner
      assert.are.equal("Knights of Faerlina", char.guildName)
      assert.are.equal(1, char.dataVersions.guildMembership)
      assert.are.equal(10, char.level)
      assert.are.equal(999, char.money)
    end)
  end)

  describe("IsSameFactionAsCurrent", function()
    local savedUFG
    before_each(function() savedUFG = _G.UnitFactionGroup end)
    after_each(function() _G.UnitFactionGroup = savedUFG end)

    it("matches same faction and rejects the other", function()
      _G.UnitFactionGroup = function() return "Alliance" end
      assert.are.equal("Alliance", DS:GetCurrentPlayerFaction())
      assert.is_true(DS:IsSameFactionAsCurrent({ faction = "Alliance" }))
      assert.is_false(DS:IsSameFactionAsCurrent({ faction = "Horde" }))
    end)

    it("keeps characters when either faction is unknown", function()
      _G.UnitFactionGroup = function() return "Horde" end
      assert.is_true(DS:IsSameFactionAsCurrent({ faction = "" }))
      assert.is_true(DS:IsSameFactionAsCurrent({}))
      _G.UnitFactionGroup = function() return nil end
      assert.is_true(DS:IsSameFactionAsCurrent({ faction = "Alliance" }))
    end)
  end)
end)
