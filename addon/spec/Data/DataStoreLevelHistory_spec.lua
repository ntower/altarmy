--[[
  Unit tests for DataStoreLevelHistory.lua.
  Run from project root: npm test
]]

describe("DataStoreLevelHistory", function()
  local DS

  local function makeChar(overrides)
    overrides = overrides or {}
    return {
      name = overrides.name or "Bob",
      realm = overrides.realm or "Faerlina",
      level = overrides.level or 10,
      played = overrides.played or 3600,
      levelHistory = overrides.levelHistory,
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.AltArmyTBC_Options = {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.time = function() return 1700000000 end
    _G.UnitGUID = _G.UnitGUID or function() return "Player-1-2" end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreLevelHistory")
    DS = AltArmy.DataStore
    DS._ResetLevelHistoryTestState()
  end)

  describe("_ParseDeathKiller", function()
    it("returns Environment for nil source", function()
      local killer = DS._ParseDeathKiller(nil, nil)
      assert.are.equal("Environment", killer.killerName)
      assert.is_nil(killer.killerGuid)
    end)

    it("returns Environment for zero GUID", function()
      local killer = DS._ParseDeathKiller("0000000000000000", nil)
      assert.are.equal("Environment", killer.killerName)
    end)

    it("returns source name and guid when present", function()
      local killer = DS._ParseDeathKiller(
        "Creature-0-1234-0-5678-000012345678",
        "Defias Bandit"
      )
      assert.are.equal("Defias Bandit", killer.killerName)
      assert.are.equal("Creature-0-1234-0-5678-000012345678", killer.killerGuid)
    end)

    it("falls back to Environment instead of using an inaccessible (secret) source name", function()
      _G.canaccessvalue = function() return false end
      local killer = DS._ParseDeathKiller(
        "Creature-0-1234-0-5678-000012345678",
        "Defias Bandit"
      )
      _G.canaccessvalue = nil
      assert.are.equal("Environment", killer.killerName)
    end)
  end)

  describe("_ComputePlayedLevel", function()
    it("returns playedTotal when no previous milestone", function()
      assert.are.equal(7200, DS._ComputePlayedLevel(7200, nil))
    end)

    it("returns delta from previous playedTotal", function()
      assert.are.equal(1800, DS._ComputePlayedLevel(9000, 7200))
    end)
  end)

  describe("_MergeMilestone", function()
    it("fills empty fields only", function()
      local merged = DS._MergeMilestone(
        { reachedAt = 100 },
        { reachedAt = 200, playedTotal = 5000, zone = "Elwynn" }
      )
      assert.are.equal(100, merged.reachedAt)
      assert.are.equal(5000, merged.playedTotal)
      assert.are.equal("Elwynn", merged.zone)
    end)

    it("does not overwrite existing fields", function()
      local merged = DS._MergeMilestone(
        { playedTotal = 1000, deaths = 2 },
        { playedTotal = 2000, deaths = 5, playedLevel = 500 }
      )
      assert.are.equal(1000, merged.playedTotal)
      assert.are.equal(2, merged.deaths)
      assert.are.equal(500, merged.playedLevel)
    end)
  end)

  describe("RecordLevelMilestone", function()
    it("is idempotent for the same level", function()
      local char = makeChar()
      DS:RecordLevelMilestone(char, {
        level = 11,
        reachedAt = 100,
        playedTotal = 4000,
        playedLevel = 400,
        zone = "Westfall",
      })
      DS:RecordLevelMilestone(char, {
        level = 11,
        reachedAt = 999,
        playedTotal = 9999,
        playedLevel = 999,
        zone = "Duskwood",
      })
      local milestone = char.levelHistory.milestones[11]
      assert.are.equal(100, milestone.reachedAt)
      assert.are.equal(4000, milestone.playedTotal)
      assert.are.equal("Westfall", milestone.zone)
    end)

    it("computes playedLevel from previous milestone when omitted", function()
      local char = makeChar({
        levelHistory = {
          milestones = { [10] = { playedTotal = 3000 } },
        },
      })
      DS:RecordLevelMilestone(char, {
        level = 11,
        reachedAt = 200,
        playedTotal = 4500,
      })
      assert.are.equal(1500, char.levelHistory.milestones[11].playedLevel)
    end)

    it("copies gear snapshot into milestone", function()
      local char = makeChar()
      char.Inventory = { [1] = 12345, [16] = "item:12345:0:0:0:0:0:0:0" }
      DS:RecordLevelMilestone(char, {
        level = 11,
        reachedAt = 200,
        playedTotal = 4500,
        gear = { [1] = 12345, [16] = "item:12345:0:0:0:0:0:0:0" },
      })
      assert.are.equal(12345, char.levelHistory.milestones[11].gear[1])
    end)

    it("flushes bracket death count into milestone", function()
      local char = makeChar()
      char.levelHistory = { meta = { bracketDeathCount = 2 }, milestones = {}, deaths = {} }
      DS:RecordLevelMilestone(char, {
        level = 11,
        reachedAt = 200,
        playedTotal = 4500,
        deaths = 2,
      })
      assert.are.equal(2, char.levelHistory.milestones[11].deaths)
      assert.are.equal(0, char.levelHistory.meta.bracketDeathCount)
    end)
  end)

  describe("RecordDeath", function()
    it("appends death with killer info", function()
      local char = makeChar()
      DS:RecordDeath(char, {
        at = 100,
        level = 10,
        zone = "Westfall",
        playedTotal = 3500,
        killerName = "Harvest Watcher",
        killerGuid = "Creature-0-1",
      })
      assert.are.equal(1, #char.levelHistory.deaths)
      assert.are.equal("Harvest Watcher", char.levelHistory.deaths[1].killerName)
      assert.are.equal(1, char.levelHistory.meta.bracketDeathCount)
    end)
  end)

  describe("HandleCombatLogForLevelHistory", function()
    it("tracks killer from damage then records on UNIT_DIED", function()
      local char = makeChar()
      DS._SetLevelHistoryTestChar(char)
      DS:HandleCombatLogForLevelHistory({
        1,
        "SWING_DAMAGE",
        nil,
        "Creature-0-1",
        "Murloc",
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      DS:HandleCombatLogForLevelHistory({
        2,
        "UNIT_DIED",
        nil,
        nil,
        nil,
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      assert.are.equal(1, #char.levelHistory.deaths)
      assert.are.equal("Murloc", char.levelHistory.deaths[1].killerName)
      assert.are.equal("Creature-0-1", char.levelHistory.deaths[1].killerGuid)
    end)

    it("records derived played total at death time", function()
      local now = 1700000000
      _G.time = function() return now end
      local char = makeChar({ played = 3600 })
      DS._SetLevelHistoryTestChar(char)
      DS:UpdatePlayedBaseline(5000)
      now = now + 600
      DS:HandleCombatLogForLevelHistory({
        1,
        "SWING_DAMAGE",
        nil,
        "Creature-0-1",
        "Murloc",
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      DS:HandleCombatLogForLevelHistory({
        2,
        "UNIT_DIED",
        nil,
        nil,
        nil,
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      assert.are.equal(5600, char.levelHistory.deaths[1].playedTotal)
    end)

    it("ignores a damage event whose subevent is inaccessible (secret) instead of tracking a killer from it", function()
      local char = makeChar()
      DS._SetLevelHistoryTestChar(char)
      _G.canaccessvalue = function(v) return v ~= "SWING_DAMAGE" end
      DS:HandleCombatLogForLevelHistory({
        1,
        "SWING_DAMAGE",
        nil,
        "Creature-0-1",
        "Murloc",
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      _G.canaccessvalue = nil
      DS:HandleCombatLogForLevelHistory({
        2,
        "UNIT_DIED",
        nil,
        nil,
        nil,
        nil,
        nil,
        "Player-1-2",
        "Bob",
      })
      assert.are.equal("Environment", char.levelHistory.deaths[1].killerName)
    end)
  end)

  describe("RequestTimePlayedSilently", function()
    before_each(function()
      DS._ResetLevelHistoryTestState()
    end)

    local function makeChatFrame(registered)
      local events = {}
      if registered then events.TIME_PLAYED_MSG = true end
      return {
        events = events,
        IsEventRegistered = function(self, e) return self.events[e] == true end,
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
      }
    end

    local requests, timers, savedTimer

    before_each(function()
      requests = 0
      timers = {}
      savedTimer = _G.C_Timer
      _G.C_Timer = nil
      _G.CHAT_FRAMES = nil
      _G.NUM_CHAT_WINDOWS = 2
      _G.ChatFrame1 = makeChatFrame(true)
      _G.ChatFrame2 = makeChatFrame(false)
      _G.RequestTimePlayed = function() requests = requests + 1 end
    end)

    after_each(function()
      _G.C_Timer = savedTimer
      _G.ChatFrame1, _G.ChatFrame2, _G.NUM_CHAT_WINDOWS = nil, nil, nil
      DS._ResetLevelHistoryTestState()
    end)

    local function collectTimers()
      _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    end

    it("requests played time with the chat frames' event unregistered", function()
      DS:RequestTimePlayedSilently()

      assert.are.equal(1, requests)
      assert.is_false(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.is_false(_G.ChatFrame2:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.are.equal(1, DS._GetPlayedChatMuted())
      assert.are.equal(1, DS._GetPendingPlayedRequests())
    end)

    it("gives the chat frames the event back once answered, not ones that never had it", function()
      DS:RequestTimePlayedSilently()
      DS:OnTimePlayedMessage(5000, 120)

      assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.is_false(_G.ChatFrame2:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.are.equal(0, DS._GetPlayedChatMuted())
    end)

    it("reads CHAT_FRAMES when the client has it", function()
      _G.CHAT_FRAMES = { "ChatFrame2", "ChatFrame1" }
      DS:RequestTimePlayedSilently()
      assert.is_false(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      _G.CHAT_FRAMES = nil
    end)

    it("registers again on the next frame, not while the answer is delivered", function()
      collectTimers()
      DS:RequestTimePlayedSilently()
      DS:OnTimePlayedMessage(5000, 120)

      assert.is_false(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      local nextFrame = timers[#timers]
      assert.are.equal(0, nextFrame.delay)
      nextFrame.fn()
      assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
    end)

    it("stays muted until every request is answered", function()
      DS:RequestTimePlayedSilently()
      DS:RequestTimePlayedSilently()
      assert.are.equal(2, requests)

      DS:OnTimePlayedMessage(5000, 120)
      assert.is_false(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))

      DS:OnTimePlayedMessage(5000, 120)
      assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
    end)

    it("unmutes after the timeout when no answer comes", function()
      collectTimers()
      DS:RequestTimePlayedSilently()

      local timeout = timers[1]
      assert.is_true(timeout.delay > 0)
      timeout.fn()

      assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.are.equal(0, DS._GetPendingPlayedRequests())
    end)

    it("leaves a /played typed later alone", function()
      DS:RequestTimePlayedSilently()
      DS:OnTimePlayedMessage(5000, 120)
      DS:OnTimePlayedMessage(5100, 220)

      assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"))
      assert.are.equal(0, DS._GetPendingPlayedRequests())
    end)
  end)

  describe("OnEnteringWorldPlayed", function()
    local requests

    before_each(function()
      DS._ResetLevelHistoryTestState()
      requests = 0
      _G.RequestTimePlayed = function() requests = requests + 1 end
    end)

    after_each(function()
      DS._ResetLevelHistoryTestState()
    end)

    it("asks at the first login and forgets the last session's answer time", function()
      local char = makeChar({ played = 5000 })
      char.playedAt = 100
      DS._SetLevelHistoryTestChar(char)

      DS:OnEnteringWorldPlayed(true, false)

      assert.are.equal(1, requests)
      assert.is_nil(char.playedAt)
    end)

    it("restores the baseline on a reload without asking", function()
      local now = 1700000000
      _G.time = function() return now end
      local char = makeChar({ played = 5000 })
      char.playedAt = now - 600
      DS._SetLevelHistoryTestChar(char)

      DS:OnEnteringWorldPlayed(false, true)

      assert.are.equal(0, requests)
      assert.are.equal(5600, DS:GetDerivedPlayedTotal())
    end)

    it("asks on a reload when this session has no answer saved", function()
      DS._SetLevelHistoryTestChar(makeChar({ played = 5000 }))
      DS:OnEnteringWorldPlayed(false, true)
      assert.are.equal(1, requests)
    end)

    it("asks on another loading screen only without a baseline", function()
      DS._SetLevelHistoryTestChar(makeChar({ played = 5000 }))
      DS:OnEnteringWorldPlayed(false, false)
      assert.are.equal(1, requests)

      DS:UpdatePlayedBaseline(5000)
      DS:OnEnteringWorldPlayed(false, false)
      assert.are.equal(1, requests)
    end)
  end)

  describe("played baseline", function()
    before_each(function()
      DS._playedBaseline = nil
    end)

    it("GetDerivedPlayedTotal returns baseline total plus elapsed wall-clock", function()
      local now = 1700000000
      _G.time = function() return now end
      DS:UpdatePlayedBaseline(5000)
      now = now + 3600
      assert.are.equal(8600, DS:GetDerivedPlayedTotal())
    end)

    it("GetDerivedPlayedTotal falls back to char.played when no baseline", function()
      local char = makeChar({ played = 7200 })
      DS._SetLevelHistoryTestChar(char)
      assert.are.equal(7200, DS:GetDerivedPlayedTotal())
    end)
  end)

  describe("BeginPendingLevelUp", function()
    it("records milestone immediately with backupTimer when TIME_PLAYED_MSG never arrives", function()
      local now = 1700000000
      _G.time = function() return now end
      local char = makeChar({
        level = 10,
        played = 5000,
        levelHistory = {
          milestones = { [10] = { playedTotal = 5000 } },
          meta = { bracketDeathCount = 0 },
          deaths = {},
        },
      })
      DS._SetLevelHistoryTestChar(char)
      DS:UpdatePlayedBaseline(5000)
      now = now + 1800

      DS:BeginPendingLevelUp(11)

      assert.are.equal(11, DS._pendingLevelUp.level)
      assert.are.equal(6800, char.levelHistory.milestones[11].playedTotal)
      assert.are.equal(1800, char.levelHistory.milestones[11].playedLevel)
      assert.are.equal("backupTimer", char.levelHistory.milestones[11].playedSource)
    end)
  end)

  describe("OnTimePlayedMessage", function()
    it("refines pending level played totals from authoritative server value", function()
      local char = makeChar({
        level = 10,
        played = 5000,
        levelHistory = {
          milestones = {
            [10] = { playedTotal = 5000 },
            [11] = {
              playedTotal = 6800,
              playedLevel = 1800,
              playedSource = "backupTimer",
              zone = "Redridge",
            },
          },
          meta = { bracketDeathCount = 0 },
          deaths = {},
        },
      })
      DS._SetLevelHistoryTestChar(char)
      DS._pendingLevelUp = { level = 11 }

      DS:OnTimePlayedMessage(5200)

      assert.is_nil(DS._pendingLevelUp)
      assert.are.equal(5200, char.levelHistory.milestones[11].playedTotal)
      assert.are.equal(200, char.levelHistory.milestones[11].playedLevel)
      assert.are.equal("server", char.levelHistory.milestones[11].playedSource)
      assert.are.equal("Redridge", char.levelHistory.milestones[11].zone)
      assert.are.equal(5200, DS._playedBaseline.totalPlayed)
    end)
  end)

  describe("GetLevelHistory", function()
    it("returns empty structure for nil char", function()
      local history = DS:GetLevelHistory(nil)
      assert.are.same({}, history.milestones)
      assert.are.same({}, history.deaths)
    end)
  end)

  describe("DeleteAllLevelHistory", function()
    it("clears level history on all characters and import gates", function()
      AltArmyTBC_Data.Characters = {
        Faerlina = {
          Bob = {
            levelHistory = {
              milestones = { [5] = { reachedAt = 1 } },
              deaths = { { at = 1 } },
              meta = { importedRxpAt = 99 },
            },
            dataVersions = { levelHistory = 1 },
          },
          Alice = {
            levelHistory = {
              milestones = { [10] = { reachedAt = 2 } },
              deaths = {},
              meta = {},
            },
          },
        },
      }
      AltArmyTBC_Data.levelHistoryImport = { questieAt = 123 }
      DS._pendingLevelUp = { level = 11 }
      DS._playedBaseline = { totalPlayed = 1000, wallClock = 500 }
      assert.are.equal(2, DS:DeleteAllLevelHistory())
      assert.is_nil(AltArmyTBC_Data.levelHistoryImport)
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.Bob.levelHistory)
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.Alice.levelHistory)
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.Bob.dataVersions.levelHistory)
      assert.is_nil(DS._pendingLevelUp)
      assert.is_nil(DS._playedBaseline)
    end)
  end)

  describe("OrphanImports", function()
    it("claims orphan level history when a tracked character logs in", function()
      AltArmyTBC_Data.OrphanImports = {
        levelHistory = {
          Faerlina = {
            Bob = {
              name = "Bob",
              realm = "Faerlina",
              levelHistory = {
                milestones = { [5] = { reachedAt = 500 } },
                deaths = {},
                meta = {},
              },
            },
          },
        },
      }
      local char = { name = "Bob", realm = "Faerlina", dataVersions = { character = 1 } }
      assert.is_true(DS:ClaimOrphanLevelHistory("Bob", "Faerlina", char))
      assert.are.equal(500, char.levelHistory.milestones[5].reachedAt)
      assert.is_nil(AltArmyTBC_Data.OrphanImports.levelHistory.Faerlina)
    end)

    it("migrates phantom character shells into OrphanImports", function()
      AltArmyTBC_Data.Characters = {
        Faerlina = {
          OldName = {
            name = "OldName",
            realm = "Faerlina",
            levelHistory = {
              milestones = { [5] = { reachedAt = 500 } },
              deaths = {},
              meta = {},
            },
          },
        },
      }
      AltArmyTBC_Data.OrphanImports = nil
      assert.are.equal(1, DS:MigratePhantomLevelHistoryImports())
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.OldName)
      assert.are.equal(
        500,
        AltArmyTBC_Data.OrphanImports.levelHistory.Faerlina.OldName.levelHistory.milestones[5].reachedAt
      )
    end)

    it("clears orphan imports when deleting all level history", function()
      AltArmyTBC_Data.OrphanImports = {
        levelHistory = {
          Faerlina = {
            Bob = {
              levelHistory = { milestones = { [5] = { reachedAt = 1 } }, deaths = {}, meta = {} },
            },
          },
        },
      }
      DS:DeleteAllLevelHistory()
      assert.is_nil(AltArmyTBC_Data.OrphanImports.levelHistory)
    end)
  end)
end)
