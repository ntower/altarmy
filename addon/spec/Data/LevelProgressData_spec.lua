--[[
  Unit tests for LevelProgressData.lua.
  Run from project root: npm test
]]

describe("LevelProgressData", function()
  local LPD
  local DS

  local function makeChar(overrides)
    overrides = overrides or {}
    return {
      name = overrides.name or "Bob",
      realm = overrides.realm or "Faerlina",
      level = overrides.level or 10,
      classFile = overrides.classFile or "WARRIOR",
      levelHistory = overrides.levelHistory,
    }
  end

  local function seedChar(name, realm, char)
    AltArmyTBC_Data.Characters[realm] = AltArmyTBC_Data.Characters[realm] or {}
    AltArmyTBC_Data.Characters[realm][name] = char
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.AltArmyTBC_Options = {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreLevelHistory")
    require("ClassColor")
    require("LevelProgressData")
    DS = AltArmy.DataStore
    LPD = AltArmy.LevelProgressData
  end)

  describe("_DeriveSeconds", function()
    it("uses playedLevel when present", function()
      local seconds = LPD._DeriveSeconds({ playedLevel = 3600 }, nil)
      assert.are.equal(3600, seconds)
    end)

    it("derives from playedTotal delta when playedLevel absent", function()
      local seconds = LPD._DeriveSeconds({ playedTotal = 7200 }, 3600)
      assert.are.equal(3600, seconds)
    end)

    it("uses playedTotal alone when no previous milestone", function()
      local seconds = LPD._DeriveSeconds({ playedTotal = 1800 }, nil)
      assert.are.equal(1800, seconds)
    end)

    it("returns nil when no usable duration", function()
      assert.is_nil(LPD._DeriveSeconds({}, nil))
      assert.is_nil(LPD._DeriveSeconds({ reachedAt = 123 }, 100))
    end)

    it("returns nil for negative delta", function()
      assert.is_nil(LPD._DeriveSeconds({ playedTotal = 1000 }, 2000))
    end)
  end)

  describe("metric constants", function()
    it("exposes time-per-level and cumulative-played metric ids", function()
      assert.are.equal("timePerLevel", LPD.METRIC_TIME_PER_LEVEL)
      assert.are.equal("cumulativePlayed", LPD.METRIC_CUMULATIVE_PLAYED)
    end)

    it("normalizes unknown metrics to time per level", function()
      assert.are.equal(LPD.METRIC_TIME_PER_LEVEL, LPD.NormalizeMetric(nil))
      assert.are.equal(LPD.METRIC_TIME_PER_LEVEL, LPD.NormalizeMetric("nope"))
      assert.are.equal(LPD.METRIC_CUMULATIVE_PLAYED, LPD.NormalizeMetric(LPD.METRIC_CUMULATIVE_PLAYED))
    end)

    it("lists dropdown entries for both metrics", function()
      local entries = LPD.GetMetricEntries()
      assert.are.equal(2, #entries)
      assert.are.equal(LPD.METRIC_TIME_PER_LEVEL, entries[1].id)
      assert.are.equal("Time per level", entries[1].label)
      assert.are.equal(LPD.METRIC_CUMULATIVE_PLAYED, entries[2].id)
      assert.are.equal("Cumulative play time", entries[2].label)
    end)
  end)

  describe("GetSeriesForCharacter", function()
    it("builds sorted level->seconds series from playedLevel", function()
      seedChar("Bob", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [3] = { playedLevel = 1000 },
            [5] = { playedLevel = 2000 },
            [4] = { playedLevel = 1500 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("Bob", "Faerlina")
      assert.are.equal(3, #series)
      assert.are.equal(3, series[1].level)
      assert.are.equal(1000, series[1].seconds)
      assert.are.equal(2, series[1].fromLevel)
      assert.are.equal(3, series[1].toLevel)
      assert.are.equal(4, series[2].level)
      assert.are.equal(1500, series[2].seconds)
      assert.are.equal(5, series[3].level)
      assert.are.equal(2000, series[3].seconds)
    end)

    it("derives seconds from playedTotal deltas when playedLevel absent", function()
      seedChar("Alice", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [2] = { playedTotal = 1000 },
            [3] = { playedTotal = 2500 },
            [4] = { playedTotal = 4000 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("Alice", "Faerlina")
      assert.are.equal(3, #series)
      assert.are.equal(2, series[1].level)
      assert.are.equal(1000, series[1].seconds)
      assert.are.equal(1, series[1].fromLevel)
      assert.are.equal(2, series[1].toLevel)
      assert.are.equal(1000, series[1].totalSeconds)
      assert.are.equal(3, series[2].level)
      assert.are.equal(1500, series[2].seconds)
      assert.are.equal(2, series[2].fromLevel)
      assert.are.equal(3, series[2].toLevel)
      assert.are.equal(4, series[3].level)
      assert.are.equal(1500, series[3].seconds)
    end)

    it("builds cumulative playedTotal vs level when metric is cumulativePlayed", function()
      seedChar("CumAlice", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [2] = { playedTotal = 1000 },
            [3] = { playedTotal = 2500 },
            [4] = { playedTotal = 4000 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter(
        "CumAlice", "Faerlina", LPD.METRIC_CUMULATIVE_PLAYED
      )
      assert.are.equal(3, #series)
      assert.are.equal(2, series[1].level)
      assert.are.equal(1000, series[1].seconds)
      assert.are.equal(1000, series[1].totalSeconds)
      assert.are.equal(3, series[2].level)
      assert.are.equal(2500, series[2].seconds)
      assert.are.equal(1500, series[2].totalSeconds)
      assert.are.equal(4, series[3].level)
      assert.are.equal(4000, series[3].seconds)
      assert.are.equal(1500, series[3].totalSeconds)
    end)

    it("accumulates playedLevel into cumulative series when playedTotal absent", function()
      seedChar("CumBob", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [3] = { playedLevel = 1000 },
            [4] = { playedLevel = 1500 },
            [5] = { playedLevel = 2000 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter(
        "CumBob", "Faerlina", LPD.METRIC_CUMULATIVE_PLAYED
      )
      assert.are.equal(3, #series)
      assert.are.equal(1000, series[1].seconds)
      assert.are.equal(2500, series[2].seconds)
      assert.are.equal(4500, series[3].seconds)
      assert.are.equal(1000, series[1].totalSeconds)
      assert.are.equal(1500, series[2].totalSeconds)
      assert.are.equal(2000, series[3].totalSeconds)
    end)

    it("uses absolute playedTotal for leading cumulative gap points", function()
      seedChar("CumLate", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [61] = { playedTotal = 60000 },
            [62] = { playedTotal = 63600 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter(
        "CumLate", "Faerlina", LPD.METRIC_CUMULATIVE_PLAYED
      )
      assert.are.equal(2, #series)
      assert.are.equal(61, series[1].level)
      assert.are.equal(60000, series[1].seconds)
      assert.are.equal(1, series[1].fromLevel)
      assert.is_true(series[1].spansGap)
      assert.are.equal(62, series[2].level)
      assert.are.equal(63600, series[2].seconds)
      assert.are.equal(3600, series[2].totalSeconds)
      assert.is_false(series[2].spansGap)
    end)

    it("defaults to time-per-level when metric omitted", function()
      seedChar("DefaultMetric", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [2] = { playedTotal = 1000 },
            [3] = { playedTotal = 2500 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("DefaultMetric", "Faerlina")
      assert.are.equal(1000, series[1].seconds)
      assert.are.equal(1500, series[2].seconds)
    end)

    it("spans missing intermediate levels using last available playedTotal", function()
      seedChar("Gap", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [60] = { playedTotal = 100000 },
            [62] = { playedTotal = 107200 },
            [63] = { playedLevel = 3200 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("Gap", "Faerlina")
      assert.are.equal(3, #series)
      assert.are.equal(60, series[1].level)
      assert.are.equal(62, series[2].level)
      assert.are.equal(60, series[2].fromLevel)
      assert.are.equal(62, series[2].toLevel)
      assert.are.equal(7200, series[2].totalSeconds)
      assert.are.equal(3600, series[2].seconds)
      assert.is_true(series[2].spansGap)
      assert.are.equal(63, series[3].level)
      assert.are.equal(3200, series[3].seconds)
      assert.is_false(series[3].spansGap)
    end)

    it("treats leading history as spanning from level 1 with zero baseline", function()
      seedChar("Late", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [61] = { playedTotal = 60000 },
            [62] = { playedTotal = 63600 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("Late", "Faerlina")
      assert.are.equal(2, #series)
      assert.are.equal(61, series[1].level)
      assert.are.equal(1, series[1].fromLevel)
      assert.are.equal(61, series[1].toLevel)
      assert.are.equal(60000, series[1].totalSeconds)
      assert.are.equal(1000, series[1].seconds)
      assert.is_true(series[1].spansGap)
      assert.are.equal(62, series[2].level)
      assert.are.equal(3600, series[2].totalSeconds)
      assert.are.equal(3600, series[2].seconds)
      assert.is_false(series[2].spansGap)
    end)

    it("skips levels with no usable duration", function()
      seedChar("Skip", "Faerlina", makeChar({
        levelHistory = {
          milestones = {
            [2] = { reachedAt = 1 },
            [3] = { playedLevel = 500 },
          },
        },
      }))

      local series = LPD.GetSeriesForCharacter("Skip", "Faerlina")
      assert.are.equal(1, #series)
      assert.are.equal(3, series[1].level)
    end)

    it("returns empty for missing character or nil levelHistory", function()
      assert.are.same({}, LPD.GetSeriesForCharacter("Nobody", "Faerlina"))
      seedChar("Empty", "Faerlina", makeChar({}))
      assert.are.same({}, LPD.GetSeriesForCharacter("Empty", "Faerlina"))
    end)
  end)

  describe("GetCharactersWithHistory", function()
    it("returns characters with at least two usable milestones", function()
      seedChar("One", "R1", makeChar({
        name = "One", classFile = "MAGE",
        levelHistory = { milestones = { [2] = { playedLevel = 100 } } },
      }))
      seedChar("Two", "R1", makeChar({
        name = "Two", classFile = "WARRIOR",
        levelHistory = {
          milestones = {
            [2] = { playedLevel = 100 },
            [3] = { playedLevel = 200 },
          },
        },
      }))
      seedChar("Three", "R2", makeChar({
        name = "Three", classFile = "MAGE",
        levelHistory = {
          milestones = {
            [5] = { playedTotal = 1000 },
            [6] = { playedTotal = 2000 },
            [7] = { playedTotal = 3000 },
          },
        },
      }))

      AltArmy.SummaryData = AltArmy.SummaryData or {}
      AltArmy.SummaryData.GetCharacterList = function()
        return {
          { name = "One", realm = "R1", level = 2, classFile = "MAGE" },
          { name = "Two", realm = "R1", level = 3, classFile = "WARRIOR" },
          { name = "Three", realm = "R2", level = 7, classFile = "MAGE" },
        }
      end

      local list = LPD.GetCharactersWithHistory()
      assert.are.equal(2, #list)

      local names = {}
      for _, entry in ipairs(list) do
        names[entry.name] = entry
      end
      assert.is_not_nil(names.Two)
      assert.are.equal("WARRIOR", names.Two.classFile)
      assert.is_not_nil(names.Three)
      assert.is_nil(names.One)
    end)

    it("reads each character's own history when two share a name", function()
      seedChar("Player-1-A", "R3", makeChar({
        name = "Frell Aa", classFile = "ROGUE",
        levelHistory = { milestones = { [2] = { playedLevel = 100 } } },
      }))
      seedChar("Player-1-B", "R3", makeChar({
        name = "Frell Aa", classFile = "SHAMAN",
        levelHistory = { milestones = { [2] = { playedLevel = 100 }, [3] = { playedLevel = 200 } } },
      }))

      AltArmy.SummaryData = AltArmy.SummaryData or {}
      AltArmy.SummaryData.GetCharacterList = function()
        return {
          { name = "Frell Aa", realm = "R3", key = "Player-1-A", level = 2, classFile = "ROGUE" },
          { name = "Frell Aa", realm = "R3", key = "Player-1-B", level = 3, classFile = "SHAMAN" },
        }
      end

      local list = LPD.GetCharactersWithHistory()
      assert.are.equal(1, #list)
      assert.are.equal("SHAMAN", list[1].classFile)
      assert.are.equal("Player-1-B", list[1].key)
      local insufficient = LPD.GetCharactersWithInsufficientHistory()
      assert.are.equal(1, #insufficient)
      assert.are.equal("Player-1-A", insufficient[1].key)
    end)
  end)

  describe("GetAxisRange", function()
    it("returns fixed level 0 to 70 domain", function()
      local minLevel, maxLevel, range = LPD.GetAxisRange()
      assert.are.equal(0, minLevel)
      assert.are.equal(70, maxLevel)
      assert.are.equal(70, range)
    end)
  end)

  describe("PrepareDrawableSeries", function()
    it("returns all points when history starts at level 1", function()
      local series = {
        { level = 2, seconds = 100, fromLevel = 1, toLevel = 2, totalSeconds = 100, spansGap = false },
        { level = 3, seconds = 200, fromLevel = 2, toLevel = 3, totalSeconds = 200, spansGap = false },
      }
      local drawable = LPD.PrepareDrawableSeries(series)
      assert.is_nil(drawable.leadingGap)
      assert.are.equal(2, #drawable.usable)
      assert.are.equal(2, drawable.usable[1].level)
    end)

    it("marks leading gap when first point spans from level 1", function()
      local series = {
        {
          level = 61, seconds = 1000, fromLevel = 1, toLevel = 61,
          totalSeconds = 60000, spansGap = true,
        },
        {
          level = 62, seconds = 3600, fromLevel = 61, toLevel = 62,
          totalSeconds = 3600, spansGap = false,
        },
      }
      local drawable = LPD.PrepareDrawableSeries(series)
      assert.is_not_nil(drawable.leadingGap)
      assert.are.equal(1, drawable.leadingGap.fromLevel)
      assert.are.equal(61, drawable.leadingGap.toLevel)
      assert.are.equal(1000, drawable.leadingGap.toY)
      assert.are.equal(60000, drawable.leadingGap.totalSeconds)
      assert.are.equal(2, #drawable.usable)
    end)

    it("returns empty usable when series is empty", function()
      local drawable = LPD.PrepareDrawableSeries({})
      assert.is_nil(drawable.leadingGap)
      assert.are.equal(0, #drawable.usable)
    end)
  end)

  describe("GetCharactersWithInsufficientHistory", function()
    it("returns characters with milestones but fewer than two usable points", function()
      seedChar("Ready", "R1", makeChar({
        name = "Ready", classFile = "MAGE",
        levelHistory = {
          milestones = {
            [2] = { playedLevel = 100 },
            [3] = { playedLevel = 200 },
          },
        },
      }))
      seedChar("Almost", "R1", makeChar({
        name = "Almost", classFile = "WARRIOR",
        levelHistory = { milestones = { [5] = { playedLevel = 300 } } },
      }))
      seedChar("Empty", "R1", makeChar({
        name = "Empty", classFile = "MAGE",
        levelHistory = { milestones = {} },
      }))
      seedChar("None", "R1", makeChar({ name = "None", classFile = "MAGE" }))

      AltArmy.SummaryData = AltArmy.SummaryData or {}
      AltArmy.SummaryData.GetCharacterList = function()
        return {
          { name = "Ready", realm = "R1", level = 3, classFile = "MAGE" },
          { name = "Almost", realm = "R1", level = 5, classFile = "WARRIOR" },
          { name = "Empty", realm = "R1", level = 1, classFile = "MAGE" },
          { name = "None", realm = "R1", level = 1, classFile = "MAGE" },
        }
      end

      local list = LPD.GetCharactersWithInsufficientHistory()
      assert.are.equal(3, #list)
      assert.are.equal("Almost", list[1].name)
      assert.are.equal("Empty", list[2].name)
      assert.are.equal("None", list[3].name)
    end)

    it("includes tracked characters with no levelHistory at all", function()
      seedChar("Frellbank", "Dreamscythe", makeChar({
        name = "Frellbank", classFile = "WARRIOR", level = 1,
      }))

      AltArmy.SummaryData = AltArmy.SummaryData or {}
      AltArmy.SummaryData.GetCharacterList = function()
        return {
          { name = "Frellbank", realm = "Dreamscythe", level = 1, classFile = "WARRIOR" },
        }
      end

      local list = LPD.GetCharactersWithInsufficientHistory()
      assert.are.equal(1, #list)
      assert.are.equal("Frellbank", list[1].name)
      assert.are.equal("Dreamscythe", list[1].realm)
    end)
  end)

  describe("GetClassColor", function()
    it("returns RAID_CLASS_COLORS for known class", function()
      local r, g, b = LPD.GetClassColor("WARRIOR")
      assert.are.equal(0.78, r)
      assert.are.equal(0.61, g)
      assert.are.equal(0.43, b)
    end)

    it("returns neutral gray for unknown class", function()
      local r, g, b = LPD.GetClassColor(nil)
      assert.are.equal(0.7, r)
      assert.are.equal(0.7, g)
      assert.are.equal(0.7, b)
    end)
  end)
end)
