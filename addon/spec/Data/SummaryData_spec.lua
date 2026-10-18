--[[
  Unit tests for SummaryData.lua (formatting helpers).
  Run from project root: npm test
]]

describe("SummaryData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("SummaryData")
    SD = AltArmy.SummaryData
  end)

  describe("GetCharacterList (money includes mail)", function()
    it("adds mail money to on-character money when available", function()
      _G.AltArmy = _G.AltArmy or {}
      _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
      _G.CreateFrame = _G.CreateFrame or function()
        return { SetScript = function() end, RegisterEvent = function() end }
      end
      _G.UIParent = _G.UIParent or {}
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"

      require("DataStore")
      require("DataStoreCharacter")
      require("DataStoreMail")

      local DS = _G.AltArmy.DataStore
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return {
          Alice = { name = "Alice", money = 1000, Mails = { { money = 2500 } } },
        }
      end

      local list = SD.GetCharacterList()
      assert.are.equal(1, #list)
      assert.are.equal(3500, list[1].money)
    end)
  end)

  describe("GetCharacterList (Well Rested)", function()
    local DS, savedGetRealms, savedGetCharacters

    setup(function()
      _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
      _G.CreateFrame = _G.CreateFrame or function()
        return { SetScript = function() end, RegisterEvent = function() end }
      end
      _G.UIParent = _G.UIParent or {}
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("DataStore")
      require("DataStoreCharacter")
      require("DataStoreLegacy")
      DS = _G.AltArmy.DataStore
      savedGetRealms, savedGetCharacters = DS.GetRealms, DS.GetCharacters
    end)

    teardown(function()
      DS.GetRealms, DS.GetCharacters = savedGetRealms, savedGetCharacters
    end)

    local function listFor(chars)
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function() return chars end
      local byName = {}
      for _, e in ipairs(SD.GetCharacterList()) do byName[e.name] = e end
      return byName
    end

    it("carries the Well Rested rank, none at max level", function()
      local legacy = { spells = {}, restRank = 2 }
      local byName = listFor({
        Rested = { name = "Rested", level = 20, xp = 0, xpMax = 1000, legacyTalents = legacy },
        Capped = { name = "Capped", level = DS.MAX_LEVEL, legacyTalents = legacy },
        Plain = { name = "Plain", level = 20, xp = 0, xpMax = 1000 },
      })
      assert.are.equal(2, byName.Rested.wellRestedRank)
      assert.are.equal(0, byName.Capped.wellRestedRank)
      assert.are.equal(0, byName.Plain.wellRestedRank)
    end)

    it("marks a character that logged out outside a resting area, not at max level or unknown", function()
      local byName = listFor({
        Outside = { name = "Outside", level = 20, xp = 0, xpMax = 1000, isResting = false },
        Inn = { name = "Inn", level = 20, xp = 0, xpMax = 1000, isResting = true },
        Old = { name = "Old", level = 20, xp = 0, xpMax = 1000 },
        Capped = { name = "Capped", level = DS.MAX_LEVEL, isResting = false },
      })
      assert.is_true(byName.Outside.notResting)
      assert.is_nil(byName.Inn.notResting)
      assert.is_nil(byName.Old.notResting)
      assert.is_nil(byName.Capped.notResting)
    end)
  end)

  describe("PresentRestXpTooltip", function()
    local savedTooltip, savedColors, savedSecondsToTime, tip

    before_each(function()
      savedTooltip, savedColors, savedSecondsToTime = _G.GameTooltip, _G.RAID_CLASS_COLORS, _G.SecondsToTime
      tip = { lines = {} }
      function tip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
      function tip:ClearLines() self.lines = {} end
      function tip:AddLine(text) self.lines[#self.lines + 1] = text end
      function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
      function tip:Show() self.shown = true end
      _G.GameTooltip = tip
      _G.SecondsToTime = nil
      _G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("ClassColor")
    end)
    after_each(function()
      _G.GameTooltip, _G.RAID_CLASS_COLORS, _G.SecondsToTime = savedTooltip, savedColors, savedSecondsToTime
    end)

    local function entry(fields)
      local e = { name = "Frell", classFile = "MAGE", restMax = 12345, restCurrent = 4567.4,
        restSecondsToFull = 2 * 86400 + 3 * 3600 }
      for k, v in pairs(fields or {}) do e[k] = v end
      return e
    end

    it("shows the name, the rest XP amounts and the time until full", function()
      assert.is_true(SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", entry()))
      assert.are.same({ "Frell", "Max Rest XP: 12,345", "Current Rest XP: 4,567",
        "Time until fully rested: 2d 3h" }, tip.lines)
      assert.are.equal("ANCHOR_BOTTOMLEFT", tip.anchor)
      assert.is_true(tip.shown)
    end)

    it("follows with Well Rested and its rank on one line", function()
      SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", entry({ wellRestedRank = 2 }))
      assert.are.same({ " ", "Well Rested | Rank 2/5", "Rested XP cap and accumulation +8%" },
        { tip.lines[5], tip.lines[6], tip.lines[7] })
    end)

    it("ends with the warning, name in class colour, when it logged out outside a resting area", function()
      SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", entry({ notResting = true }))
      assert.are.equal("|cFF3fc6eaFrell|r|cFFff664c is not in a resting area|r", tip.lines[#tip.lines])
    end)

    it("shows both Well Rested and the warning when it has the talent and logged out outside", function()
      SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", entry({ notResting = true, wellRestedRank = 5 }))
      assert.are.same({
        "Frell", "Max Rest XP: 12,345", "Current Rest XP: 4,567", "Time until fully rested: 2d 3h",
        " ", "Well Rested | Rank 5/5", "Rested XP cap and accumulation +20%",
        " ", "|cFF3fc6eaFrell|r|cFFff664c is not in a resting area|r",
      }, tip.lines)
    end)

    it("says Now when full and -- online outside a resting area", function()
      SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", entry({ restSecondsToFull = 0 }))
      assert.are.equal("Time until fully rested: Now", tip.lines[4])
      local online = entry({ isOnline = true })
      online.restSecondsToFull = nil
      SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT", online)
      assert.are.equal("Time until fully rested: --", tip.lines[4])
    end)

    it("still shows at max level", function()
      assert.is_true(SD.PresentRestXpTooltip("owner", "ANCHOR_BOTTOMLEFT",
        { name = "Frell", isMaxLevel = true, wellRestedRank = 0 }))
      assert.are.same({ "Frell", "No rest XP at max level" }, tip.lines)
    end)
  end)

  describe("FormatRestXp", function()
    it("returns empty string for nil", function()
      assert.are.equal(SD.FormatRestXp(nil), "")
    end)
    it("formats zero rate", function()
      assert.are.equal(SD.FormatRestXp(0), "0.0%")
    end)
    it("rounds to one decimal", function()
      assert.are.equal(SD.FormatRestXp(50.34), "50.3%")
      assert.are.equal(SD.FormatRestXp(50.36), "50.4%")
    end)
    it("formats integer rate", function()
      assert.are.equal(SD.FormatRestXp(100), "100.0%")
    end)
  end)

  describe("FormatPlayedSingleUnit", function()
    it("formats zero as seconds", function()
      assert.are.equal(SD.FormatPlayedSingleUnit(0), "0.0 s")
    end)
    it("uses days with one decimal rounded to nearest 0.1", function()
      -- 4 days 8 minutes -> 4.0 d (single unit, not compound)
      assert.are.equal(SD.FormatPlayedSingleUnit(346080), "4.0 d")
    end)
    it("uses hours when under one day", function()
      assert.are.equal(SD.FormatPlayedSingleUnit(5400), "1.5 h")
    end)
    it("uses minutes when under one hour", function()
      assert.are.equal(SD.FormatPlayedSingleUnit(90), "1.5 m")
    end)
    it("rounds to nearest 0.1", function()
      assert.are.equal(SD.FormatPlayedSingleUnit(86400 + 4320), "1.1 d")
    end)
    it("uses full words when unitStyle is full", function()
      assert.are.equal(SD.FormatPlayedSingleUnit(346080, "full"), "4.0 days")
      assert.are.equal(SD.FormatPlayedSingleUnit(5400, "full"), "1.5 hours")
      assert.are.equal(SD.FormatPlayedSingleUnit(90, "full"), "1.5 mins")
      assert.are.equal(SD.FormatPlayedSingleUnit(0, "full"), "0.0 secs")
    end)
  end)

  describe("GetTimeString", function()
    it("uses fallback when SecondsToTime missing", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(0)
      assert.truthy(s:find("0"))
      assert.truthy(s:find("m"))
      _G.SecondsToTime = old
    end)
    it("fallback formats days and hours", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(90061)
      assert.truthy(s:find("1d") or s:find("1"))
      _G.SecondsToTime = old
    end)
    it("treats nil as 0", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(nil)
      assert.truthy(#s > 0)
      _G.SecondsToTime = old
    end)
  end)

  describe("FormatLastOnline", function()
    it("returns Online when isCurrent", function()
      assert.are.equal(SD.FormatLastOnline(nil, true), "Online")
      assert.are.equal(SD.FormatLastOnline(0, true), "Online")
    end)
    it("returns Unknown when lastLogout is nil", function()
      assert.are.equal(SD.FormatLastOnline(nil, false), "Unknown")
    end)
    it("returns Unknown when lastLogout >= sentinel", function()
      assert.are.equal(SD.FormatLastOnline(5000000000, false), "Unknown")
      assert.are.equal(SD.FormatLastOnline(6000000000, false), "Unknown")
    end)
    it("returns Just now when ago < 60 seconds", function()
      local old = _G.time
      _G.time = function() return 100 end
      assert.are.equal(SD.FormatLastOnline(50, false), "Just now")
      _G.time = old
    end)
    it("returns Xm ago when ago in minutes", function()
      local old = _G.time
      _G.time = function() return 1000 end
      local s = SD.FormatLastOnline(100)
      assert.truthy(s:find("ago"))
      assert.truthy(s:find("m") or s:find("h") or s:find("d"))
      _G.time = old
    end)
  end)

  describe("GetMissingDataInfo", function()
    local DS
    local DT

    before_each(function()
      DS = _G.AltArmy.DataStore
      if not DS then
        _G.AltArmy.DataStore = {}
        DS = _G.AltArmy.DataStore
      end
      DT = _G.AltArmy.DataStoreTalents
      if not DT then
        _G.AltArmy.DataStoreTalents = {}
        DT = _G.AltArmy.DataStoreTalents
      end
      DT.HasTalentData = function(char)
        return char and char.talents and char.talents.tabs ~= nil
      end
      DT.IsTalentEligible = function(char)
        return (char and tonumber(char.level) or 0) >= 10
      end
      -- Default: reputation storage is current (no stale-format warning)
      DS.NeedsRescan = function()
        return false
      end
      -- Default: TBC's legacy no-recipe-window set (matches DataStoreProfessions.lua's
      -- NO_RECIPE_PROFESSION_KEYS_LEGACY); tests targeting the Forever/fallback behavior override this.
      DS.ProfessionHasNoRecipeWindow = function(profName)
        local set = { Fishing = true, Riding = true, Herbalism = true, Mining = true, Skinning = true }
        return set[profName] == true
      end
    end)

    it("returns no missing when char is nil", function()
      local oldGetCharacter = DS and DS.GetCharacter
      DS.GetCharacter = function(_, _name, _realm) return nil end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
      if oldGetCharacter then DS.GetCharacter = oldGetCharacter end
    end)

    it("returns no missing when all modules have data", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
    end)

    it("does not nag to open the Skills window when the client has no skill-line API (e.g. WoW Forever)", function()
      local char = {
        level = 20,
        talents = { tabs = { 0, 0, 5 } },
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1,
          reputations = 1, currencies = 1,
          -- professions intentionally absent: never gatherable on this client
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.HasProfessionsListApi = function() return false end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
    end)

    it("still nags to open the Skills window when the skill-line API exists but professions have not been gathered", function()
      local char = {
        level = 20,
        talents = { tabs = { 0, 0, 5 } },
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1,
          reputations = 1, currencies = 1,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.HasProfessionsListApi = function() return true end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      assert.are.same(out.instructions, { "* Open your Skills window (P)" })
    end)

    it("flags outdated reputation storage for current character (needs relog/reload)", function()
      local char = {
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 1, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        Reputations = { [47] = 50000 },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, c, mod)
        return mod == "reputations" and (c.dataVersions.reputations or 0) < 2
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("reputation") and (line:find("reload") or line:find("log")) then
          found = true
          break
        end
      end
      assert.is_true(found, "expected reputation refresh instruction for current character")
    end)

    it("does not warn for stale containers version (equipped bag identity is optional)", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, c, mod)
        return mod == "containers" and (c.dataVersions.containers or 0) < 2
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
    end)

    it("flags outdated reputation storage for alt with log in instruction", function()
      local char = {
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 1, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        Reputations = { [47] = 50000 },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, c, mod)
        return mod == "reputations" and (c.dataVersions.reputations or 0) < 2
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character") then found = true break end
      end
      assert.is_true(found, "expected log-in instruction for alt with stale reputation")
    end)

    it("adds Skills instruction when professions module missing (current character)", function()
      local char = { dataVersions = { character = 1, containers = 1, equipment = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Skills") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Skills'")
    end)

    it("adds Log in with this character when alt has missing data", function()
      local char = { dataVersions = { character = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character") then found = true break end
      end
      assert.is_true(found, "expected 'Log in with this character' for alt")
    end)

    it("adds Open your Alchemy window when profession has no recipes", function()
      local char = {
        dataVersions = { character = 1, professions = 1 },
        Professions = { Alchemy = { rank = 50, maxRank = 300, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Alchemy") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Alchemy'")
    end)

    it("does not warn about Skinning on TBC's legacy trade-skill API (no recipe window there)", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Skinning = { rank = 50, maxRank = 300, Recipes = {} } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function() return 0 end
      -- (uses before_each's default TBC/legacy DS.ProfessionHasNoRecipeWindow, which excludes Skinning)
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same({}, out.instructions)
    end)

    it("warns about Skinning when scanning via the C_TradeSkillUI fallback (WoW Forever has recipes there)", function()
      local char = {
        dataVersions = { character = 1, professions = 1 },
        Professions = { Skinning = { rank = 50, maxRank = 300, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function() return 0 end
      -- Forever/fallback: Skinning has real recipes, so it's no longer in the no-warning set.
      DS.ProfessionHasNoRecipeWindow = function(profName)
        local set = { Fishing = true, Riding = true, Herbalism = true, Mining = true }
        return set[profName] == true
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Skinning") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Skinning'")
    end)

    it("adds Open your profession window when recipes are marked stale after learn", function()
      local char = {
        dataVersions = { character = 1, professions = 1 },
        Professions = {
          Alchemy = { rank = 300, maxRank = 375, Recipes = { [11449] = { color = 1 } } },
          Mining = { rank = 300, maxRank = 375, Recipes = {} },
        },
        professionsNeedingRecipeScan = { Alchemy = true, Mining = true },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      assert.is_true(out.hasMissing)
      local foundAlchemy, foundMining = false, false
      for _, line in ipairs(out.instructions) do
        if line:find("Alchemy", 1, true) then foundAlchemy = true end
        if line:find("Mining", 1, true) then foundMining = true end
      end
      assert.is_true(foundAlchemy, "expected Alchemy rescan instruction")
      assert.is_false(foundMining, "gathering professions should not warn for stale recipes")
    end)

    it("dedupes empty-recipes and stale-recipe instructions for the same profession", function()
      local char = {
        dataVersions = { character = 1, professions = 1 },
        Professions = { Alchemy = { rank = 50, maxRank = 300, Recipes = {} } },
        professionsNeedingRecipeScan = { Alchemy = true },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function() return 0 end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      local count = 0
      for _, line in ipairs(out.instructions) do
        if line:find("Alchemy", 1, true) then count = count + 1 end
      end
      assert.are.equal(1, count)
    end)

    describe("where recipes are read at login (WoW Forever)", function()
      local savedReader, oldUnitName, oldGetRealmName

      before_each(function()
        savedReader = _G.AltArmy.OwnRecipeRead
        _G.AltArmy.OwnRecipeRead = {
          HasApi = function() return true end,
          IsEnabled = function() return true end,
          CanRead = function(name) return name ~= "Skinning" end,
        }
        oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
        _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
        _G.GetRealmName = function() return "Realm1" end
        local char = {
          dataVersions = { character = 1, professions = 1 },
          Professions = {
            Alchemy = { rank = 50, maxRank = 300, Recipes = {} },
            Tailoring = { rank = 75, maxRank = 150, Recipes = {} },
          },
        }
        DS.GetCharacter = function() return char end
        DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
        DS.GetProfessions = function(_, c) return c.Professions or {} end
        DS.GetNumRecipes = function() return 0 end
      end)

      after_each(function()
        _G.AltArmy.OwnRecipeRead = savedReader
        _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      end)

      it("asks only to log in with an alt whose recipes are missing", function()
        local out = SD.GetMissingDataInfo("Bob", "Realm1")
        assert.is_true(out.hasMissing)
        assert.are.same({ "* Log in with this character" }, out.instructions)
      end)

      it("still names the window for the character logged in", function()
        local out = SD.GetMissingDataInfo("Alice", "Realm1")
        local found = false
        for _, line in ipairs(out.instructions) do
          if line == "* Open your Alchemy window" then found = true end
        end
        assert.is_true(found, "expected 'Open your Alchemy window' for the current character")
      end)

      it("names the window of a profession that can't be read in the background", function()
        DS.ProfessionHasNoRecipeWindow = function() return false end
        local char = DS.GetCharacter()
        char.Professions = { Skinning = { rank = 75, maxRank = 150, Recipes = {} } }
        local out = SD.GetMissingDataInfo("Bob", "Realm1")
        local found = false
        for _, line in ipairs(out.instructions) do
          if line == "* Open your Skinning window" then found = true end
        end
        assert.is_true(found, "expected 'Open your Skinning window' for an alt")
      end)

      it("never asks for Comprehension, which has no window to open", function()
        DS.ProfessionHasNoRecipeWindow = function() return false end
        _G.AltArmy.OwnRecipeRead.CanRead = function(name) return name ~= "Comprehension" end
        local char = DS.GetCharacter()
        char.Professions = { Comprehension = { rank = 24, maxRank = 100, Recipes = {} } }
        char.professionsNeedingRecipeScan = { Comprehension = true }
        for _, who in ipairs({ "Alice", "Bob" }) do
          local out = SD.GetMissingDataInfo(who, "Realm1")
          for _, line in ipairs(out.instructions) do
            assert.is_nil(line:find("Comprehension", 1, true), who .. ": " .. line)
          end
        end
      end)

      it("names the window when reading is turned off", function()
        _G.AltArmy.OwnRecipeRead.IsEnabled = function() return false end
        local out = SD.GetMissingDataInfo("Bob", "Realm1")
        local found = false
        for _, line in ipairs(out.instructions) do
          if line == "* Open your Tailoring window" then found = true end
        end
        assert.is_true(found, "expected 'Open your Tailoring window' when reading is off")
      end)
    end)

    it("adds Open your Poisons window when poison skill rank was not captured", function()
      local char = {
        classFile = "ROGUE",
        level = 70,
        dataVersions = { character = 1, professions = 1 },
        Professions = { Poisons = { rank = 0, maxRank = 375, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.GetCharacterClass = function(_, c) return "", (c and c.classFile) or "" end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldGi = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 2842 then return "Poisons" end
        return oldGi and oldGi(id)
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.GetSpellInfo = oldGi
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Poisons") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Poisons'")
    end)

    it("does not duplicate poisons warning when rank is known but recipes are missing", function()
      local char = {
        classFile = "ROGUE",
        level = 70,
        dataVersions = { character = 1, professions = 1 },
        Professions = { Poisons = { rank = 340, maxRank = 375, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.GetCharacterClass = function(_, c) return "", (c and c.classFile) or "" end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldGi = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 2842 then return "Poisons" end
        return oldGi and oldGi(id)
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.GetSpellInfo = oldGi
      assert.is_true(out.hasMissing)
      local count = 0
      for _, line in ipairs(out.instructions) do
        if line:find("Poisons") then count = count + 1 end
      end
      assert.are.equal(1, count)
    end)

    it("does not flag poisons for non-rogue characters", function()
      local char = {
        classFile = "WARRIOR",
        level = 70,
        dataVersions = { character = 1, professions = 1 },
        Professions = { Poisons = { rank = 0, maxRank = 375, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.GetCharacterClass = function(_, c) return "", (c and c.classFile) or "" end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function() return 0 end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Poisons") then found = true break end
      end
      assert.is_false(found)
    end)

    it("flags reputation when data version is current but storage still has legacy scalars", function()
      local char = {
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        Reputations = { [47] = 5000 },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function()
        return false
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("reputation") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected reputation refresh for legacy scalar storage")
    end)

    it("flags missing cooldown specialization data for current character (level 60+, tailoring 350+)", function()
      local char = {
        level = 60,
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Tailoring = { rank = 350, maxRank = 375, Recipes = { [1] = true } } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      DS.NeedsRescan = function()
        return false
      end
      local oldGi = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 3908 then return "Tailoring" end
        if id == 2259 then return "Alchemy" end
        return oldGi and oldGi(id)
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Tailor" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Tailor", "Realm1")
      _G.GetSpellInfo = oldGi
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if type(line) == "string" and line:find("Log in with this character", 1, true) then
          found = true
          break
        end
      end
      assert.is_true(found, "expected login instruction for cooldown specialization scan")
    end)

    it("does not flag cooldown specialization when snapshot already exists", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 375, maxRank = 375, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      DS.NeedsRescan = function()
        return false
      end
      local oldGi = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 3908 then return "Tailoring" end
        if id == 2259 then return "Alchemy" end
        return oldGi and oldGi(id)
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.GetSpellInfo = oldGi
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_false(out.hasMissing)
    end)

    it("does not flag cooldown specialization below level 60", function()
      local char = {
        level = 59,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 375, maxRank = 375, Recipes = { [1] = true } } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      DS.NeedsRescan = function()
        return false
      end
      local oldGi = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 3908 then return "Tailoring" end
        if id == 2259 then return "Alchemy" end
        return oldGi and oldGi(id)
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.GetSpellInfo = oldGi
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_false(out.hasMissing)
    end)

    it("flags missing gearScores when GearScoreTBCClassic addon is enabled", function()
      local char = {
        level = 70,
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldGS = _G.AltArmy.GearScore
      _G.AltArmy.GearScore = {
        IsGearScoreTBCClassicAvailable = function() return true end,
      }
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.AltArmy.GearScore = oldGS
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character") then found = true break end
      end
      assert.is_true(found, "expected log-in instruction for alt missing gearScores")
    end)

    it("does not flag missing gearScores when GearScoreTBCClassic addon is disabled", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldGS = _G.AltArmy.GearScore
      _G.AltArmy.GearScore = {
        IsGearScoreTBCClassicAvailable = function() return false end,
      }
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.AltArmy.GearScore = oldGS
      assert.is_false(out.hasMissing)
    end)

    it("returns no talent instruction when talent data exists", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      assert.is_false(out.hasMissing)
      for _, line in ipairs(out.instructions) do
        assert.is_false(line:find("Talents", 1, true) ~= nil)
      end
    end)

    it("does not add talents instruction for current character too low level for talents", function()
      local char = {
        level = 9,
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_false(out.hasMissing)
      for _, line in ipairs(out.instructions) do
        assert.is_false(line:find("Talents", 1, true) ~= nil)
      end
    end)

    it("adds Open your Talents window for current character without talent data", function()
      local char = {
        level = 70,
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Talents", 1, true) then found = true break end
      end
      assert.is_true(found, "expected Talents window instruction for current character")
    end)

    it("adds Log in with this character for alt without talent data", function()
      local char = {
        level = 70,
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local loginCount = 0
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character", 1, true) then
          loginCount = loginCount + 1
        end
      end
      assert.are.equal(1, loginCount, "expected exactly one log-in instruction for alt")
    end)

    it("dedupes Log in with this character when alt is missing modules and talents", function()
      local char = { dataVersions = { character = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local loginCount = 0
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character", 1, true) then
          loginCount = loginCount + 1
        end
      end
      assert.are.equal(1, loginCount, "expected single deduped log-in instruction")
    end)

    it("flags missing guild membership for current character (needs relog/reload)", function()
      local char = {
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        talents = { tabs = { 0, 0, 21 } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, c, mod)
        return mod == "guildMembership"
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("guild", 1, true) then found = true break end
      end
      assert.is_true(found, "expected guild refresh instruction for current character")
    end)

    it("flags missing guild membership for alts", function()
      local char = {
        dataVersions = { character = 1, guildMembership = 0 },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        talents = { tabs = { 0, 0, 21 } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        if mod == "guildMembership" then return false end
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, _c, mod)
        return mod == "guildMembership"
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character", 1, true) then found = true break end
      end
      assert.is_true(found, "expected log-in instruction for alt missing guild data")
    end)

    it("does not flag guildless characters after guild membership has been scanned", function()
      local char = {
        guildName = nil,
        dataVersions = {
          character = 1, guildMembership = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        talents = { tabs = { 0, 0, 21 } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function() return false end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
    end)
  end)

  describe("GetMissingDataTooltip", function()
    local DS

    before_each(function()
      DS = _G.AltArmy.DataStore
      if not DS then
        _G.AltArmy.DataStore = {}
        DS = _G.AltArmy.DataStore
      end
      DS.NeedsRescan = function()
        return false
      end
    end)

    it("returns nil when nothing missing", function()
      local char = {
        level = 70,
        talents = { tabs = { 0, 0, 21 } },
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 2, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
        Reputations = { [47] = { s = 5, e = 1, b = 0, t = 1 } },
        cooldownSpecs = {
          masterTransmutation = false,
          spellfireTailor = false,
          shadoweaveTailor = false,
          moonclothTailor = false,
        },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.GetCharacterLevel = function(_, c) return (c and c.level) or 0 end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local title, lines = SD.GetMissingDataTooltip("Zed", "R1", nil)
      assert.is_nil(title)
      assert.is_nil(lines)
    end)

    it("returns title and lines when data missing", function()
      local char = { dataVersions = { character = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local title, lines = SD.GetMissingDataTooltip("Bob", "Realm1", nil)
      assert.is_string(title)
      assert.truthy(title:find("Some data for"))
      assert.truthy(title:find("has not been gathered yet"))
      assert.truthy(title:find("Bob"))
      assert.is_table(lines)
      assert.truthy(#lines > 0)
    end)
  end)

  describe("GetExportMissingDataInfo", function()
    local DS, DL, saved, savedTraits, current

    before_each(function()
      _G.AltArmy.DataStore = _G.AltArmy.DataStore or {}
      DS = _G.AltArmy.DataStore
      _G.AltArmy.DataStoreLegacy = _G.AltArmy.DataStoreLegacy or {}
      DL = _G.AltArmy.DataStoreLegacy
      saved = {}
      for _, k in ipairs({
        "IsCurrentCharacter", "HasModuleData", "NeedsRescan", "GetProfessions", "GetNumRecipes",
        "ProfessionHasNoRecipeWindow", "HasProfessionsListApi", "GetCharacterClass", "GetCharacterLevel",
      }) do
        saved[k] = DS[k]
      end
      savedTraits = DL.HasTraitsApi
      current = nil
      DS.IsCurrentCharacter = function(_, name) return name == current end
      DS.HasModuleData = function(_, c, mod)
        local v = c.dataVersions and c.dataVersions[mod]
        return v ~= nil and v > 0
      end
      DS.NeedsRescan = function(_, c, mod)
        local want = ({ reputations = 2, legacyTalents = 2 })[mod]
        return want ~= nil and ((c.dataVersions and c.dataVersions[mod]) or 0) < want
      end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local n = 0
        for _ in pairs(c.Professions[profName].Recipes or {}) do n = n + 1 end
        return n
      end
      DS.ProfessionHasNoRecipeWindow = function(profName) return profName == "Mining" end
      DS.HasProfessionsListApi = function() return true end
      DS.GetCharacterClass = function(_, c) return c.classFile, c.classFile end
      DS.GetCharacterLevel = function(_, c) return c.level or 0 end
      DL.HasTraitsApi = function() return true end
    end)

    after_each(function()
      for k, v in pairs(saved) do DS[k] = v end
      DL.HasTraitsApi = savedTraits
    end)

    local function complete()
      return {
        name = "Alice", guid = "Player-1-0001", classFile = "MAGE", level = 70,
        -- containers, equipment and the rest aren't exported: their absence is no warning here
        dataVersions = { character = 3, professions = 1, reputations = 2, legacyTalents = 2 },
        Professions = {
          Tailoring = { rank = 300, Recipes = { [1] = true } },
          Mining = { rank = 300 },
        },
        Reputations = { [76] = { s = 6 } },
        legacyTalents = { spells = {} },
      }
    end

    it("finds nothing missing when everything the export writes is there", function()
      local out = SD.GetExportMissingDataInfo(complete(), "R1")
      assert.is_false(out.hasMissing)
      assert.are.same({}, out.instructions)
    end)

    it("asks to open a profession's window when its recipes are missing", function()
      local char = complete()
      char.Professions.Tailoring.Recipes = nil
      current = "Alice"
      assert.are.same({ "* Open your Tailoring window" }, SD.GetExportMissingDataInfo(char, "R1").instructions)
    end)

    it("asks the current character to open the panels whose modules were never gathered", function()
      local char = complete()
      char.dataVersions.professions, char.dataVersions.reputations = nil, nil
      current = "Alice"
      assert.are.same(
        { "* Open your Skills window (P)", "* Open your Reputation panel" },
        SD.GetExportMissingDataInfo(char, "R1").instructions
      )
    end)

    it("asks for a reload when reputations are stored in the old format", function()
      local char = complete()
      char.Reputations = { [76] = 4500 }
      current = "Alice"
      assert.are.same(
        { "* /reload or log in again to refresh reputation data" },
        SD.GetExportMissingDataInfo(char, "R1").instructions
      )
    end)

    it("asks to log in, once, an alt with no GUID, no Legacy talents and no reputations", function()
      local char = complete()
      char.guid, char.legacyTalents = nil, nil
      char.dataVersions.legacyTalents, char.dataVersions.reputations = nil, nil
      assert.are.same({ "* Log in with this character" }, SD.GetExportMissingDataInfo(char, "R1").instructions)
    end)

    it("doesn't ask for Legacy talents on a client without them, nor of the current character", function()
      local char = complete()
      char.dataVersions.legacyTalents = nil
      current = "Alice"
      assert.is_false(SD.GetExportMissingDataInfo(char, "R1").hasMissing)
      current = nil
      DL.HasTraitsApi = function() return false end
      assert.is_false(SD.GetExportMissingDataInfo(char, "R1").hasMissing)
    end)
  end)

  describe("GetTalentSpecMissingInfo", function()
    local DS
    local DT

    before_each(function()
      DS = _G.AltArmy.DataStore
      DT = _G.AltArmy.DataStoreTalents
      if not DS then
        _G.AltArmy.DataStore = {}
        DS = _G.AltArmy.DataStore
      end
      if not DT then
        _G.AltArmy.DataStoreTalents = {}
        DT = _G.AltArmy.DataStoreTalents
      end
      DT.IsTalentEligible = function(char)
        return (char and tonumber(char.level) or 0) >= 10
      end
      _G.UnitName = function() return "Me" end
      _G.GetRealmName = function() return "Realm1" end
    end)

    it("returns no missing when talent data exists", function()
      DS.GetCharacter = function() return { level = 70, talents = { tabs = { 0, 0, 21 } } } end
      DT.HasTalentData = function(char) return char and char.talents ~= nil end
      local out = SD.GetTalentSpecMissingInfo("Bob", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same({}, out.instructions)
    end)

    it("returns log-in instruction for another character", function()
      DS.GetCharacter = function() return { level = 70, classFile = "MAGE" } end
      DT.HasTalentData = function() return false end
      local out = SD.GetTalentSpecMissingInfo("Bob", "Realm1")
      assert.is_true(out.hasMissing)
      assert.are.same({ "* Log in with this character" }, out.instructions)
    end)

    it("returns talents window instruction for current character", function()
      DS.GetCharacter = function() return { level = 70, classFile = "MAGE" } end
      DT.HasTalentData = function() return false end
      local out = SD.GetTalentSpecMissingInfo("Me", "Realm1")
      assert.is_true(out.hasMissing)
      assert.are.same({ "* Open your Talents window" }, out.instructions)
    end)

    it("returns no missing for a character too low level to have talents", function()
      DS.GetCharacter = function() return { level = 9, classFile = "MAGE" } end
      DT.HasTalentData = function() return false end
      local out = SD.GetTalentSpecMissingInfo("Me", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same({}, out.instructions)
    end)

    it("uses same title format as other missing-data tooltips", function()
      DS.GetCharacter = function() return { level = 70, classFile = "MAGE" } end
      DT.HasTalentData = function() return false end
      local title, lines = SD.GetTalentSpecMissingTooltip("Bob", "Realm1", "MAGE")
      assert.truthy(title:find("Some data for"))
      assert.truthy(title:find("has not been gathered yet"))
      assert.are.same({ "* Log in with this character" }, lines)
    end)
  end)
  describe("GetNameStatusIconLayout", function()
    it("puts the main star first after the class icon, then the bank icon", function()
      assert.are.same({ mainX = 18, bankX = 36, nameTextLeft = 54 }, SD.GetNameStatusIconLayout(16, 16, 2, true, true))
    end)

    it("leaves no gap for icons not shown", function()
      assert.are.same({ nameTextLeft = 18 }, SD.GetNameStatusIconLayout(16, 16, 2))
      assert.are.same({ bankX = 18, nameTextLeft = 36 }, SD.GetNameStatusIconLayout(16, 16, 2, false, true))
    end)
  end)
end)
