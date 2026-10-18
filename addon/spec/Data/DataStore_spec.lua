--[[
  Unit tests for DataStore.lua (MigrateDataVersions).
  Run from project root: npm test
]]

describe("DataStore", function()
  local DS

  setup(function()
    -- Stub WoW globals so DataStore.lua can load outside the game.
    if not _G.AltArmy then
      _G.AltArmy = {}
    end
    if not _G.AltArmyTBC_Data then
      _G.AltArmyTBC_Data = {}
    end
    if not _G.CreateFrame then
      _G.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
      end
    end
    if not _G.UIParent then
      _G.UIParent = {}
    end
    -- Allow require("DataStore") to find AltArmy_TBC/Data/DataStore.lua (cwd = project root).
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    DS = AltArmy.DataStore
  end)

  describe("EnsureAccountId", function()
    local function counter()
      local n = 0
      return function()
        n = (n + 1) % 16
        return n
      end
    end

    it("makes 16 hex digits once and keeps them", function()
      local data = {}
      local id = DS._EnsureAccountId(data, counter())
      assert.are.equal("123456789abcdef0", id)
      assert.are.equal(id, data.accountId)
      assert.are.equal(id, DS._EnsureAccountId(data, function() return 0 end))
    end)

    it("replaces a malformed id", function()
      local data = { accountId = "not an id" }
      assert.are.equal("0000000000000000", DS._EnsureAccountId(data, function() return 0 end))
    end)

    it("makes a new one when forced (a copied WTF folder)", function()
      local data = { accountId = "0000000000000000" }
      assert.are.equal("123456789abcdef0", DS._EnsureAccountId(data, counter(), true))
    end)

    it("uses math.random by default", function()
      assert.truthy(DS._EnsureAccountId({}):match("^%x+$"))
    end)
  end)

  describe("_MigrateDataVersions", function()
    it("does nothing when Characters is empty", function()
      local data = { Characters = {} }
      assert.has_no.errors(function()
        DS._MigrateDataVersions(data)
      end)
    end)

    it("initializes dataVersions on each character", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = {} },
        },
      }
      DS._MigrateDataVersions(data)
      assert.truthy(data.Characters.Realm1.Char1.dataVersions)
      assert.are.same(data.Characters.Realm1.Char1.dataVersions, {})
    end)

    it("sets character = 1 when char has name", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { name = "Alice" } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 1)
    end)

    it("does not set character when char has no name", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = {} },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.character)
    end)

    it("does not overwrite existing dataVersions.character", function()
      local data = {
        Characters = {
          Realm1 = {
            Char1 = {
              name = "Alice",
              dataVersions = { character = 2 },
            },
          },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 2)
    end)

    it("sets containers = 1 when char has non-empty Containers", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Containers = { [0] = { slots = 16 } } } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.containers, 1)
    end)

    it("does not set containers when Containers is empty", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Containers = {} } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.containers)
    end)

    it("sets equipment = 1 when char has non-empty Inventory", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Inventory = { [16] = 12345 } } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.equipment, 1)
    end)

    it("does not set equipment when Inventory is empty", function()
      local data = {
        Characters = {
          Realm1 = { Char1 = { Inventory = {} } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.is_nil(data.Characters.Realm1.Char1.dataVersions.equipment)
    end)

    it("migrates all realms and characters", function()
      local data = {
        Characters = {
          Realm1 = {
            Char1 = { name = "A" },
            Char2 = { name = "B" },
          },
          Realm2 = { Char3 = { name = "C" } },
        },
      }
      DS._MigrateDataVersions(data)
      assert.are.equal(data.Characters.Realm1.Char1.dataVersions.character, 1)
      assert.are.equal(data.Characters.Realm1.Char2.dataVersions.character, 1)
      assert.are.equal(data.Characters.Realm2.Char3.dataVersions.character, 1)
    end)

    it("uses passed-in data instead of global AltArmyTBC_Data", function()
      local globalData = { Characters = { R = { C = { name = "Global" } } } }
      local mockData = { Characters = { R = { C = { name = "Mock" } } } }
      _G.AltArmyTBC_Data = globalData
      DS._MigrateDataVersions(mockData)
      assert.are.equal(mockData.Characters.R.C.dataVersions.character, 1)
      assert.is_nil(globalData.Characters.R.C.dataVersions)
    end)
  end)

  describe("GetRealms", function()
    it("returns realm keys as table with true values", function()
      _G.AltArmyTBC_Data = { Characters = { RealmA = {}, RealmB = {} } }
      local out = DS:GetRealms()
      assert.truthy(out.RealmA)
      assert.truthy(out.RealmB)
      local n = 0
      for _ in pairs(out) do n = n + 1 end
      assert.are.equal(n, 2)
    end)
    it("returns empty when Characters is empty", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      local out = DS:GetRealms()
      local n = 0
      for _ in pairs(out) do n = n + 1 end
      assert.are.equal(n, 0)
    end)
  end)

  describe("GetCharacters", function()
    it("returns realm table when realm exists", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {}, Bob = {} } } }
      local chars = DS:GetCharacters("R1")
      assert.truthy(chars.Alice)
      assert.truthy(chars.Bob)
    end)
    it("returns empty table when realm is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.are.same(DS:GetCharacters(nil), {})
    end)
    it("returns empty table when realm missing", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.are.same(DS:GetCharacters("Missing"), {})
    end)
  end)

  describe("GetCharacter", function()
    it("returns char when name and realm exist", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = { name = "Alice" } } } }
      local char = DS:GetCharacter("Alice", "R1")
      assert.truthy(char)
      assert.are.equal(char.name, "Alice")
    end)
    it("returns nil when name is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      assert.is_nil(DS:GetCharacter(nil, "R1"))
    end)
    it("returns nil when realm is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      assert.is_nil(DS:GetCharacter("Alice", nil))
    end)
    it("returns nil when character missing", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.is_nil(DS:GetCharacter("Alice", "R1"))
    end)
  end)

  describe("GetCurrentPlayerIdentity", function()
    it("returns name and realm from WoW APIs", function()
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "RealmA" end
      local name, realm = DS:GetCurrentPlayerIdentity()
      assert.are.equal("Alice", name)
      assert.are.equal("RealmA", realm)
    end)
  end)

  describe("the name while loading", function()
    -- UnitName("player") reads "Unknown" (UNKNOWNOBJECT) early in loading: never key a character by it.
    it("is empty while UnitName says Unknown", function()
      _G.UnitName = function() return "Unknown" end
      _G.GetRealmName = function() return "RealmA" end
      _G.AltArmyTBC_Data = { Characters = {} }
      assert.are.equal("", DS:GetCurrentPlayerName())
      assert.is_nil(DS:GetCurrentCharacter())
      assert.is_nil(AltArmyTBC_Data.Characters.RealmA)
    end)

    it("drops stubs saved under Unknown that were never scanned", function()
      local data = { Characters = {
        RealmA = {
          Unknown = { lastUpdate = 5, Reputations = {} },
          Alice = { name = "Alice", faction = "Horde" },
        },
      } }
      DS._RemoveUnknownStubs(data)
      assert.is_nil(data.Characters.RealmA.Unknown)
      assert.is_not_nil(data.Characters.RealmA.Alice)
    end)

    it("keeps a real character named Unknown", function()
      local data = { Characters = { RealmA = { Unknown = { name = "Unknown", faction = "Horde" } } } }
      DS._RemoveUnknownStubs(data)
      assert.is_not_nil(data.Characters.RealmA.Unknown)
    end)
  end)

  describe("IsCurrentCharacter", function()
    before_each(function()
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "RealmA" end
    end)

    it("returns true for matching name and realm", function()
      assert.is_true(DS:IsCurrentCharacter("Alice", "RealmA"))
    end)

    it("returns false for different name or realm", function()
      assert.is_false(DS:IsCurrentCharacter("Bob", "RealmA"))
      assert.is_false(DS:IsCurrentCharacter("Alice", "RealmB"))
    end)

    it("returns false when name or realm is nil", function()
      assert.is_false(DS:IsCurrentCharacter(nil, "RealmA"))
      assert.is_false(DS:IsCurrentCharacter("Alice", nil))
    end)
  end)

  describe("full character names", function()
    -- WoW Forever's UnitName returns the first name and the surname as two values.
    before_each(function()
      _G.GetRealmName = function() return "RealmA" end
    end)
    after_each(function()
      _G.Constants = nil
    end)

    it("joins the first name and surname", function()
      _G.UnitName = function() return "Frell", "Ofelements" end
      assert.are.equal("Frell Ofelements", DS:GetCurrentPlayerName())
    end)

    it("uses the client's surname separator when it has one", function()
      _G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "_" } }
      _G.UnitName = function() return "Frell", "Ofelements" end
      assert.are.equal("Frell_Ofelements", DS:GetCurrentPlayerName())
    end)

    it("is the first name alone when there is no surname", function()
      _G.UnitName = function() return "Alice", nil end
      assert.are.equal("Alice", DS:GetCurrentPlayerName())
      _G.UnitName = function() return "Alice", "" end
      assert.are.equal("Alice", DS:GetCurrentPlayerName())
    end)

    it("never appends the realm name", function()
      _G.UnitName = function() return "Alice", "RealmA" end
      assert.are.equal("Alice", DS:GetCurrentPlayerName())
    end)

    it("matches the current character by full name", function()
      _G.UnitName = function() return "Frell", "Blast" end
      assert.is_true(DS:IsCurrentCharacter("Frell Blast", "RealmA"))
      assert.is_false(DS:IsCurrentCharacter("Frell", "RealmA"))
      assert.is_false(DS:IsCurrentCharacter("Frell Ofelements", "RealmA"))
    end)
  end)

  describe("GUID keys", function()
    local guid
    before_each(function()
      guid = "Player-1-A"
      _G.UnitName = function() return "Frell", "Blast" end
      _G.GetRealmName = function() return "RealmA" end
      _G.UnitGUID = function(unit) if unit == "player" then return guid end end
      _G.AltArmyTBC_Data = { Characters = {} }
    end)
    after_each(function()
      _G.UnitGUID = nil
    end)

    it("keys the current character by its GUID", function()
      local char = DS:GetCurrentCharacter()
      assert.are.equal(char, AltArmyTBC_Data.Characters.RealmA["Player-1-A"])
      assert.are.equal("Frell Blast", char.name)
      assert.are.equal("Player-1-A", char.guid)
      assert.are.equal("RealmA", char.realm)
      assert.are.equal("Player-1-A", DS:GetCurrentPlayerGUID())
    end)

    it("gives characters that share a first name separate entries", function()
      local blast = DS:GetCurrentCharacter()
      guid = "Player-1-B"
      _G.UnitName = function() return "Frell", "Ofelements" end
      local ofelements = DS:GetCurrentCharacter()
      assert.are_not.equal(blast, ofelements)
      assert.are.equal("Frell Blast", AltArmyTBC_Data.Characters.RealmA["Player-1-A"].name)
      assert.are.equal("Frell Ofelements", AltArmyTBC_Data.Characters.RealmA["Player-1-B"].name)
    end)

    it("has no current character while the GUID is unknown", function()
      guid = nil
      assert.is_nil(DS:GetCurrentCharacter())
      assert.is_nil(AltArmyTBC_Data.Characters.RealmA)
    end)

    it("keys by name on a client without UnitGUID", function()
      _G.UnitGUID = nil
      local char = DS:GetCurrentCharacter()
      assert.are.equal(char, AltArmyTBC_Data.Characters.RealmA["Frell Blast"])
    end)

    it("finds and deletes a GUID-keyed character by name", function()
      AltArmyTBC_Data.Characters.RealmA = {
        ["Player-1-A"] = { name = "Frell Blast", guid = "Player-1-A" },
        Legacy = { name = "Legacy" },
      }
      assert.are.equal(AltArmyTBC_Data.Characters.RealmA["Player-1-A"], DS:GetCharacter("Frell Blast", "RealmA"))
      assert.are.equal(AltArmyTBC_Data.Characters.RealmA["Player-1-A"], DS:GetCharacter("Player-1-A", "RealmA"))
      assert.are.equal(AltArmyTBC_Data.Characters.RealmA.Legacy, DS:GetCharacter("Legacy", "RealmA"))
      assert.is_nil(DS:GetCharacter("Frell", "RealmA"))
      DS:DeleteCharacter("Frell Blast", "RealmA")
      assert.is_nil(AltArmyTBC_Data.Characters.RealmA["Player-1-A"])
      assert.is_not_nil(AltArmyTBC_Data.Characters.RealmA.Legacy)
    end)

    it("returns the storage key for a character", function()
      assert.are.equal("Player-1-A", DS:GetCharacterKey({ name = "Frell Blast", guid = "Player-1-A" }))
      assert.are.equal("Legacy", DS:GetCharacterKey({ name = "Legacy" }))
    end)
  end)

  describe("_MigrateCharacterKeys", function()
    it("moves entries that carry a GUID under that GUID", function()
      local data = { Characters = { R = {
        Frell = { name = "Frell", guid = "Player-1-A", level = 20 },
        ["Frell Hound"] = { name = "Frell Hound", level = 1 },
      } } }
      DS._MigrateCharacterKeys(data)
      assert.is_nil(data.Characters.R.Frell)
      assert.are.equal(20, data.Characters.R["Player-1-A"].level)
      assert.are.equal(1, data.Characters.R["Frell Hound"].level)
    end)

    it("keeps the newer entry's values when two share a GUID", function()
      local data = { Characters = { R = {
        Frell = { name = "Frell", guid = "Player-1-A", lastUpdate = 20, level = 20, Professions = { A = 1 } },
        ["Player-1-A"] = { name = "Frell Blast", guid = "Player-1-A", lastUpdate = 10, level = 18, Mails = {} },
      } } }
      DS._MigrateCharacterKeys(data)
      local char = data.Characters.R["Player-1-A"]
      assert.is_nil(data.Characters.R.Frell)
      assert.are.equal(20, char.level)
      assert.are.equal("Frell", char.name)
      assert.are.same({ A = 1 }, char.Professions)
      assert.are.same({}, char.Mails)
    end)
  end)

  describe("ForEachCharacter", function()
    it("visits every character", function()
      _G.AltArmyTBC_Data = {
        Characters = {
          R1 = { Alice = { name = "Alice" }, Bob = { name = "Bob" } },
          R2 = { Carol = { name = "Carol" } },
        },
      }
      local seen = {}
      DS:ForEachCharacter(function(realm, charName, charData)
        seen[realm .. "/" .. charName] = charData
      end)
      assert.truthy(seen["R1/Alice"])
      assert.truthy(seen["R1/Bob"])
      assert.truthy(seen["R2/Carol"])
    end)

    it("stops early when callback returns true", function()
      _G.AltArmyTBC_Data = {
        Characters = {
          R1 = { Alice = {}, Bob = {} },
        },
      }
      local count = 0
      DS:ForEachCharacter(function()
        count = count + 1
        return true
      end)
      assert.are.equal(1, count)
    end)

    it("does nothing when Characters is empty", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      local count = 0
      DS:ForEachCharacter(function()
        count = count + 1
      end)
      assert.are.equal(0, count)
    end)
  end)

  describe("HasModuleData", function()
    it("returns false when char is nil", function()
      assert.is_false(DS:HasModuleData(nil, "character"))
    end)
    it("returns false when moduleName is nil", function()
      assert.is_false(DS:HasModuleData({ dataVersions = {} }, nil))
    end)
    it("returns false when dataVersions missing or zero", function()
      assert.is_false(DS:HasModuleData({}, "character"))
      assert.is_false(DS:HasModuleData({ dataVersions = { character = 0 } }, "character"))
    end)
    it("returns true when dataVersions.character is 1", function()
      assert.is_true(DS:HasModuleData({ dataVersions = { character = 1 } }, "character"))
    end)
  end)

  describe("GetDataVersion", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetDataVersion(nil, "character"), 0)
    end)
    it("returns 0 when moduleName is nil", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = { character = 1 } }, nil), 0)
    end)
    it("returns 0 when key missing", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = {} }, "character"), 0)
    end)
    it("returns version when present", function()
      assert.are.equal(DS:GetDataVersion({ dataVersions = { character = 2 } }, "character"), 2)
    end)
  end)

  describe("NeedsRescan", function()
    it("returns true when char is nil", function()
      assert.is_true(DS:NeedsRescan(nil, "character"))
    end)
    it("returns true when moduleName is nil", function()
      assert.is_true(DS:NeedsRescan({}, nil))
    end)
    it("returns false when moduleName unknown", function()
      assert.is_false(DS:NeedsRescan({ dataVersions = {} }, "unknown_module"))
    end)
    it("returns true when stored version < current", function()
      assert.is_true(DS:NeedsRescan({ dataVersions = {} }, "character"))
      assert.is_true(DS:NeedsRescan({ dataVersions = { character = 0 } }, "character"))
    end)
    it("returns false when stored version == current", function()
      assert.is_false(DS:NeedsRescan({ dataVersions = { character = DS._DATA_VERSIONS.character } }, "character"))
    end)
  end)

  describe("GetAllDataVersions", function()
    it("returns empty when char is nil", function()
      assert.are.same(DS:GetAllDataVersions(nil), {})
    end)
    it("returns copy of dataVersions", function()
      local dv = { character = 1, equipment = 1 }
      local char = { dataVersions = dv }
      local out = DS:GetAllDataVersions(char)
      assert.are.same(dv, out)
      assert.is_true(out ~= dv)
    end)
    it("returns empty when dataVersions nil", function()
      assert.are.same(DS:GetAllDataVersions({}), {})
    end)
  end)

  describe("DeleteCharacter", function()
    local invalidateCalled

    before_each(function()
      invalidateCalled = false
      _G.AltArmy.Characters = {
        InvalidateView = function() invalidateCalled = true end,
      }
    end)

    it("removes the character entry from saved data", function()
      _G.AltArmyTBC_Data = {
        Characters = { R1 = { Alice = { name = "Alice" }, Bob = { name = "Bob" } } },
      }
      DS:DeleteCharacter("Alice", "R1")
      assert.is_nil(_G.AltArmyTBC_Data.Characters.R1.Alice)
      assert.truthy(_G.AltArmyTBC_Data.Characters.R1.Bob)
    end)

    it("invalidates the character view after deletion", function()
      _G.AltArmyTBC_Data = {
        Characters = { R1 = { Alice = { name = "Alice" } } },
      }
      DS:DeleteCharacter("Alice", "R1")
      assert.is_true(invalidateCalled)
    end)

    it("is a no-op when character does not exist", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = {} } }
      assert.has_no.errors(function()
        DS:DeleteCharacter("NonExistent", "R1")
      end)
    end)

    it("is a no-op when realm does not exist", function()
      _G.AltArmyTBC_Data = { Characters = {} }
      assert.has_no.errors(function()
        DS:DeleteCharacter("Alice", "NoSuchRealm")
      end)
    end)

    it("is a no-op when name is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = { name = "Alice" } } } }
      assert.has_no.errors(function()
        DS:DeleteCharacter(nil, "R1")
      end)
      assert.truthy(_G.AltArmyTBC_Data.Characters.R1.Alice)
    end)

    it("is a no-op when realm is nil", function()
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = { name = "Alice" } } } }
      assert.has_no.errors(function()
        DS:DeleteCharacter("Alice", nil)
      end)
      assert.truthy(_G.AltArmyTBC_Data.Characters.R1.Alice)
    end)
  end)

  describe("HandlePlayerGuildUpdate", function()
    local scanned

    before_each(function()
      scanned = false
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      AltArmyTBC_Data.Characters = { R1 = { Alice = {} } }
      DS.ScanGuildMembership = function()
        scanned = true
        AltArmyTBC_Data.Characters.R1.Alice.guildName = "My Guild"
        AltArmyTBC_Data.Characters.R1.Alice.dataVersions = { guildMembership = 1 }
      end
    end)

    it("refreshes guild membership when it changed", function()
      _G.GetGuildInfo = function() return "My Guild" end
      DS:HandlePlayerGuildUpdate()
      assert.is_true(scanned)
    end)

    it("skips duplicate events when guild membership is already current", function()
      AltArmyTBC_Data.Characters.R1.Alice = {
        guildName = "My Guild",
        dataVersions = { guildMembership = 1 },
      }
      _G.GetGuildInfo = function() return "My Guild" end
      DS:HandlePlayerGuildUpdate()
      assert.is_false(scanned)
    end)
  end)

  describe("PLAYER_LEVEL_UP guild share broadcast", function()
    local eventHandler
    local scheduleCount

    local function reloadDataStoreWithFrames()
      eventHandler = nil
      _G.CreateFrame = function()
        return {
          RegisterEvent = function() end,
          SetScript = function(_, script, handler)
            if script == "OnEvent" then
              eventHandler = handler
            end
          end,
        }
      end
      package.loaded["DataStore"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("DataStore")
      DS = AltArmy.DataStore
    end

    before_each(function()
      scheduleCount = 0
      AltArmy.GuildShareComm = {
        ScheduleBroadcast = function()
          scheduleCount = scheduleCount + 1
        end,
      }
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      _G.UnitLevel = function() return 41 end
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = { level = 40 } } } }
      reloadDataStoreWithFrames()
      DS.BeginPendingLevelUp = function() end
    end)

    after_each(function()
      AltArmy.GuildShareComm = nil
    end)

    it("schedules a debounced presence broadcast on level up", function()
      assert.is_function(eventHandler)
      eventHandler(nil, "PLAYER_LEVEL_UP", 41)
      assert.are.equal(1, scheduleCount)
      assert.are.equal(41, _G.AltArmyTBC_Data.Characters.R1.Alice.level)
    end)
  end)

  describe("equipment scan delay on login", function()
    local frames
    local eventHandler
    local equipmentScanCount

    local function reloadDataStoreWithFrames()
      frames = {}
      eventHandler = nil
      _G.CreateFrame = function()
        local f = {
          RegisterEvent = function() end,
          SetScript = function(self, script, handler)
            if script == "OnEvent" then
              eventHandler = handler
            elseif script == "OnUpdate" then
              self._onUpdate = handler
            end
          end,
        }
        frames[#frames + 1] = f
        return f
      end
      package.loaded["DataStore"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("DataStore")
      DS = AltArmy.DataStore
    end

    before_each(function()
      equipmentScanCount = 0
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      reloadDataStoreWithFrames()
      DS.ScanEquipment = function()
        equipmentScanCount = equipmentScanCount + 1
      end
      DS.ScanCharacter = function() end
      DS.RequestTimePlayedSilently = function() end
      DS.ScanProfessionLinks = function() end
      DS.ScanReputations = function() end
      DS.ScanBags = function() end
      DS.TryScanTrackedCooldownsFromActionBars = function() end
      DS.RunLevelHistoryBackfill = function() end
    end)

    it("does not scan equipment immediately on PLAYER_ENTERING_WORLD", function()
      assert.is_function(eventHandler)
      eventHandler(nil, "PLAYER_ENTERING_WORLD")
      assert.are.equal(0, equipmentScanCount)
    end)

    it("scans equipment after EQUIPMENT_SCAN_DELAY on PLAYER_ENTERING_WORLD", function()
      eventHandler(nil, "PLAYER_ENTERING_WORLD")
      assert.are.equal(0, equipmentScanCount)

      local active = {}
      for _, f in ipairs(frames) do
        if f._onUpdate then
          active[#active + 1] = f
        end
      end
      assert.is_true(#active > 0, "expected delayed OnUpdate frame(s)")

      for _, f in ipairs(active) do
        f:_onUpdate(2.9)
      end
      assert.are.equal(0, equipmentScanCount)

      for _, f in ipairs(active) do
        if f._onUpdate then
          f:_onUpdate(0.2)
        end
      end
      assert.are.equal(1, equipmentScanCount)
    end)
  end)

  describe("MAX_LEVEL", function()
    local function reloadDataStore()
      package.loaded["DataStore"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("DataStore")
      return AltArmy.DataStore
    end

    after_each(function()
      -- Restore the default (no GetMaxPlayerLevel) so AltArmy.DataStore.MAX_LEVEL
      -- is back to 70 for any later spec file sharing this Lua process/globals.
      _G.GetMaxPlayerLevel = nil
      reloadDataStore()
    end)

    it("falls back to 70 when GetMaxPlayerLevel is unavailable", function()
      _G.GetMaxPlayerLevel = nil
      local reloaded = reloadDataStore()
      assert.are.equal(70, reloaded.MAX_LEVEL)
    end)

    it("uses GetMaxPlayerLevel() when the client exposes it", function()
      _G.GetMaxPlayerLevel = function() return 60 end
      local reloaded = reloadDataStore()
      assert.are.equal(60, reloaded.MAX_LEVEL)
    end)
  end)

  describe("IsWowForever", function()
    local function reloadDataStore()
      package.loaded["DataStore"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("DataStore")
      return AltArmy.DataStore
    end

    after_each(function()
      -- Restore the default (no GetBuildInfo) so AltArmy.DataStore.IsWowForever
      -- is back to false for any later spec file sharing this Lua process/globals.
      _G.GetBuildInfo = nil
      reloadDataStore()
    end)

    it("falls back to false when GetBuildInfo is unavailable", function()
      _G.GetBuildInfo = nil
      local reloaded = reloadDataStore()
      assert.is_false(reloaded.IsWowForever)
    end)

    it("is false when the client's interface number isn't Forever's", function()
      _G.GetBuildInfo = function() return "2.5.6", 20506, "enUS", 20506 end
      local reloaded = reloadDataStore()
      assert.is_false(reloaded.IsWowForever)
    end)

    it("is true when the client's interface number is Forever's confirmed 16001", function()
      _G.GetBuildInfo = function() return "1.60.1", 16001, "enUS", 16001 end
      local reloaded = reloadDataStore()
      assert.is_true(reloaded.IsWowForever)
    end)
  end)

  describe("COMBAT_LOG_EVENT_UNFILTERED", function()
    local eventHandler
    local levelHistoryPayloads
    local transmuteCasts
    local cleuInfo

    local function cleu(subevent, srcGUID, srcName, destGUID, spellId)
      cleuInfo = { 1, subevent, false, srcGUID, srcName, 0, 0, destGUID, "Dest", 0, 0, spellId }
      eventHandler(nil, "COMBAT_LOG_EVENT_UNFILTERED")
    end

    before_each(function()
      eventHandler = nil
      levelHistoryPayloads = {}
      transmuteCasts = {}
      _G.CreateFrame = function()
        return {
          RegisterEvent = function() end,
          SetScript = function(_, script, handler)
            if script == "OnEvent" then eventHandler = handler end
          end,
        }
      end
      _G.CombatLogGetCurrentEventInfo = function() return unpack(cleuInfo) end
      _G.UnitGUID = function(unit)
        if unit == "player" then return "Player-1-2" end
      end
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      package.loaded["DataStore"] = nil
      require("DataStore")
      DS = AltArmy.DataStore
      DS.HandleCombatLogForLevelHistory = function(_, payload)
        levelHistoryPayloads[#levelHistoryPayloads + 1] = payload
      end
      AltArmy.CooldownData = {
        RecordSuccessfulTransmuteCast = function(_, spellId)
          transmuteCasts[#transmuteCasts + 1] = spellId
        end,
      }
    end)

    after_each(function()
      _G.CombatLogGetCurrentEventInfo = nil
      AltArmy.CooldownData = nil
    end)

    it("ignores events that neither come from nor target the player", function()
      cleu("SPELL_AURA_APPLIED", "Player-9-9", "Stranger", "Creature-0-1", 1234)
      cleu("SPELL_CAST_SUCCESS", "Player-9-9", "Stranger", "Player-9-9", 28566)
      assert.are.equal(0, #levelHistoryPayloads)
      assert.are.equal(0, #transmuteCasts)
    end)

    it("passes damage taken by the player to level history", function()
      cleu("SWING_DAMAGE", "Creature-0-1", "Murloc", "Player-1-2")
      assert.are.equal(1, #levelHistoryPayloads)
      local p = levelHistoryPayloads[1]
      assert.are.equal("SWING_DAMAGE", p[2])
      assert.are.equal("Creature-0-1", p[4])
      assert.are.equal("Murloc", p[5])
      assert.are.equal("Player-1-2", p[8])
      assert.are.equal(0, #transmuteCasts)
    end)

    it("records the player's own successful casts", function()
      cleu("SPELL_CAST_SUCCESS", "Player-1-2", "Alice", nil, 28566)
      assert.are.same({ 28566 }, transmuteCasts)
    end)
  end)

  describe("UNIT_SPELLCAST_SUCCEEDED", function()
    local eventHandler
    local trackedLookups

    before_each(function()
      eventHandler = nil
      trackedLookups = {}
      _G.CreateFrame = function()
        return {
          RegisterEvent = function() end,
          SetScript = function(_, script, handler)
            if script == "OnEvent" then eventHandler = handler end
          end,
        }
      end
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      _G.AltArmyTBC_Data = { Characters = { R1 = { Alice = {} } } }
      package.loaded["DataStore"] = nil
      require("DataStore")
      DS = AltArmy.DataStore
      AltArmy.CooldownData = {
        IsTrackedSpellId = function(spellId)
          trackedLookups[#trackedLookups + 1] = spellId
          return false
        end,
      }
    end)

    after_each(function()
      _G.canaccessvalue = nil
      AltArmy.CooldownData = nil
    end)

    it("looks up the player's own casts", function()
      eventHandler(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 28566)
      assert.are.same({ 28566 }, trackedLookups)
    end)

    it("ignores a secret unit token or spell id", function()
      _G.canaccessvalue = function(v) return v ~= 28566 end
      eventHandler(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 28566)
      _G.canaccessvalue = function(v) return v ~= "player" end
      eventHandler(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 28566)
      assert.are.equal(0, #trackedLookups)
    end)
  end)
  describe("resting state", function()
    local eventHandler, resting, savedIsResting, savedTime

    before_each(function()
      eventHandler = nil
      resting = false
      savedIsResting, savedTime = _G.IsResting, _G.time
      _G.IsResting = function() return resting end
      _G.time = function() return 1000 end
      _G.CreateFrame = function()
        return {
          RegisterEvent = function() end,
          SetScript = function(_, script, handler)
            if script == "OnEvent" then eventHandler = handler end
          end,
        }
      end
      _G.UnitGUID = function(unit)
        if unit == "player" then return "Player-1-2" end
      end
      _G.UnitName = function() return "Alice" end
      _G.GetRealmName = function() return "R1" end
      _G.AltArmyTBC_Data = { Characters = {} }
      package.loaded["DataStore"] = nil
      require("DataStore")
    end)
    after_each(function() _G.IsResting, _G.time = savedIsResting, savedTime end)

    local function char() return AltArmy.DataStore._GetCurrentCharTable() end

    it("is saved whenever it changes", function()
      resting = true
      eventHandler(nil, "PLAYER_UPDATE_RESTING")
      assert.is_true(char().isResting)
      resting = false
      eventHandler(nil, "PLAYER_UPDATE_RESTING")
      assert.is_false(char().isResting)
    end)

    it("keeps what it tracked when the logout says not resting", function()
      resting = true
      eventHandler(nil, "ZONE_CHANGED")
      resting = false
      eventHandler(nil, "PLAYER_LOGOUT")
      assert.is_true(char().isResting)
    end)

    it("believes a logout that says resting", function()
      eventHandler(nil, "ZONE_CHANGED_NEW_AREA")
      resting = true
      eventHandler(nil, "PLAYER_LOGOUT")
      assert.is_true(char().isResting)
    end)
  end)
end)
