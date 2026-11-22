--[[
  Unit tests for ForeverRealm.Migrate: moving saved data from WoW Forever's old realm names ("CAMWOW US2 Realm 5
  PvE") and from "" (an Alt Army before this, on Forever 1.60.1) to the group key ("US PvE").
  Run from project root: npm test
]]

describe("ForeverRealm.Migrate", function()
  local FR, DS, wasForever

  local US2, US1, US1R3 = "CAMWOW US2 Realm 5 PvE", "CAMWOW US1 Realm 5 PvE", "CAMWOW US1 Realm 3 PvE"
  local PVP = "CAMWOW US2 Realm 7 PvP"

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

  before_each(function()
    wasForever = DS.IsWowForever
    DS.IsWowForever = true
  end)

  after_each(function()
    DS.IsWowForever = wasForever
  end)

  --- Run Migrate on `sv` (missing roots are fine) with `current` as the logged-in group (nil: not known yet).
  local function migrate(sv, current)
    FR.Migrate(sv, current)
    return sv
  end

  --- A deep copy, to check a second run changes nothing.
  local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
  end

  local function idempotent(sv, current)
    local once = copy(migrate(sv, current))
    assert.are.same(once, migrate(sv, current))
  end

  describe("Characters", function()
    it("moves every shard's characters to the group, the realm field too", function()
      local sv = { data = { Characters = {
        [US2] = { A = { realm = US2, name = "A", lastUpdate = 1 } },
        [US1] = { B = { realm = US1, name = "B", lastUpdate = 2 } },
        [PVP] = { C = { realm = PVP, name = "C", lastUpdate = 3 } },
      } } }
      migrate(sv)
      local chars = sv.data.Characters
      assert.are.same({ "US PvE", "US PvP" }, (function()
        local ks = {} for k in pairs(chars) do ks[#ks + 1] = k end table.sort(ks) return ks
      end)())
      assert.are.equal("US PvE", chars["US PvE"].A.realm)
      assert.are.equal("US PvE", chars["US PvE"].B.realm)
      assert.are.equal("US PvP", chars["US PvP"].C.realm)
    end)

    it("keeps the copy updated last when a character was saved under two shards, the other filling gaps", function()
      local sv = { data = { Characters = {
        [US1] = { G = { realm = US1, lastUpdate = 10, money = 100, bankScannedAt = 3 } },
        [US2] = { G = { realm = US2, lastUpdate = 20, money = 500 } },
      } } }
      migrate(sv)
      local g = sv.data.Characters["US PvE"].G
      assert.are.equal(500, g.money)
      assert.are.equal(20, g.lastUpdate)
      assert.are.equal(3, g.bankScannedAt)
      assert.is_nil(sv.data.Characters[US1])
      assert.is_nil(sv.data.Characters[US2])
    end)

    it("joins a character's AU copy (Oceania, saved before AU was folded into US) to its US PvE copy", function()
      local sv = { data = { Characters = {
        ["AU PvE"] = { G = { realm = "AU PvE", lastUpdate = 10, money = 100, bankScannedAt = 3 } },
        ["US PvE"] = { G = { realm = "US PvE", lastUpdate = 20, money = 500 } },
      } } }
      migrate(sv, "US PvE")
      local g = sv.data.Characters["US PvE"].G
      assert.are.equal(500, g.money)
      assert.are.equal(3, g.bankScannedAt)
      assert.are.equal("US PvE", g.realm)
      assert.is_nil(sv.data.Characters["AU PvE"])
    end)

    it("moves an Oceanic realm's characters to US PvE", function()
      local sv = { data = { Characters = {
        ["CAMWOW AU1 Realm 1 PvE"] = { A = { realm = "CAMWOW AU1 Realm 1 PvE", lastUpdate = 1 } },
      } } }
      migrate(sv)
      assert.are.equal("US PvE", sv.data.Characters["US PvE"].A.realm)
      assert.is_nil(sv.data.Characters["CAMWOW AU1 Realm 1 PvE"])
    end)

    it("changes nothing a second time", function()
      idempotent({ data = { Characters = { [US2] = { A = { realm = US2, lastUpdate = 1 } },
        [US1] = { A = { realm = US1, lastUpdate = 2 } } } } })
    end)

    it("changes nothing on TBC", function()
      DS.IsWowForever = false
      local sv = { data = { Characters = { Dreamscythe = { A = { realm = "Dreamscythe" } },
        [""] = { B = { realm = "" } } } } }
      local before = copy(sv)
      assert.are.same(before, migrate(sv, "US PvE"))
    end)
  end)

  describe("characters saved under \"\"", function()
    it("go to the group of their copy saved elsewhere, the newer copy winning", function()
      local sv = { data = { Characters = {
        [""] = { G = { realm = "", lastUpdate = 20, level = 60 } },
        [US2] = { G = { realm = US2, lastUpdate = 10, level = 59, played = 7 } },
      } } }
      migrate(sv)
      assert.is_nil(sv.data.Characters[""])
      local g = sv.data.Characters["US PvE"].G
      assert.are.equal(60, g.level)
      assert.are.equal(7, g.played)
      assert.are.equal("US PvE", g.realm)
    end)

    it("stay for their own login when saved nowhere else, even with the current group known", function()
      local sv = { data = { Characters = { [""] = { NEW = { realm = "", name = "New" } } } } }
      migrate(sv, "US PvE")
      assert.are.equal("New", sv.data.Characters[""].NEW.name)
    end)
  end)

  describe("OrphanImports", function()
    it("moves level history imports to the group", function()
      local sv = { data = { Characters = {}, OrphanImports = { levelHistory = {
        [US2] = { Frell = { name = "Frell", realm = US2, milestones = { [10] = {} } } },
        [US1] = { Frell = { name = "Frell", realm = US1, deaths = 2 } },
      } } } }
      migrate(sv)
      local lh = sv.data.OrphanImports.levelHistory
      assert.is_nil(lh[US2])
      assert.are.equal("US PvE", lh["US PvE"].Frell.realm)
      assert.is_table(lh["US PvE"].Frell.milestones)
      idempotent(sv)
    end)
  end)

  describe("per-character settings (realm\\name keys)", function()
    it("re-keys pins, hides, bank alts, currency picks and graph selections", function()
      local sv = {
        summary = { characters = { [US2 .. "\\Frell Blast"] = { pin = true } } },
        gear = { characters = { [US1 .. "\\Frell Fire"] = { hide = true } } },
        reputation = { characters = { [PVP .. "\\Pvp Guy"] = { pin = true } } },
        options = {
          economy = { currency = { characters = { [US2 .. "\\Frell Blast"] = true } } },
          bankAlts = { [US2 .. "\\Banky Bank"] = true },
          bankAltPromptDismissed = { [US1 .. "\\Other Alt"] = true },
        },
        graph = { selected = { [US2 .. "\\Player-1-A"] = true, [US2 .. "\\Player-2-B\1link1"] = true } },
      }
      migrate(sv)
      assert.is_true(sv.summary.characters["US PvE\\Frell Blast"].pin)
      assert.is_true(sv.gear.characters["US PvE\\Frell Fire"].hide)
      assert.is_true(sv.reputation.characters["US PvP\\Pvp Guy"].pin)
      assert.is_true(sv.options.economy.currency.characters["US PvE\\Frell Blast"])
      assert.is_true(sv.options.bankAlts["US PvE\\Banky Bank"])
      assert.is_true(sv.options.bankAltPromptDismissed["US PvE\\Other Alt"])
      assert.is_true(sv.graph.selected["US PvE\\Player-1-A"])
      assert.is_true(sv.graph.selected["US PvE\\Player-2-B\1link1"])
      assert.is_nil(sv.summary.characters[US2 .. "\\Frell Blast"])
      idempotent(sv)
    end)

    it("keeps a setting already under the group when an old key says otherwise", function()
      local sv = { summary = { characters = {
        ["US PvE\\Frell Blast"] = { pin = true },
        [US2 .. "\\Frell Blast"] = { pin = false, hide = true },
      } } }
      migrate(sv)
      assert.are.same({ pin = true, hide = true }, sv.summary.characters["US PvE\\Frell Blast"])
    end)

    it("moves \"\" settings to the group of the character they belong to, else the current group", function()
      local sv = {
        data = { Characters = {
          [""] = { G = { realm = "", name = "Frell Blast", lastUpdate = 2 } },
          [PVP] = { G = { realm = PVP, name = "Frell Blast", lastUpdate = 1 } },
        } },
        summary = { characters = { ["\\Frell Blast"] = { pin = true }, ["\\Someone Else"] = { hide = true } } },
      }
      migrate(sv, "US PvE")
      assert.is_true(sv.summary.characters["US PvP\\Frell Blast"].pin)
      assert.is_true(sv.summary.characters["US PvE\\Someone Else"].hide)
      assert.is_nil(sv.summary.characters["\\Frell Blast"])
    end)

    it("leaves \"\" settings while the current group isn't known", function()
      local sv = { summary = { characters = { ["\\Someone Else"] = { hide = true } } } }
      migrate(sv)
      assert.is_true(sv.summary.characters["\\Someone Else"].hide)
    end)
  end)

  describe("collapsed sections (group|faction keys)", function()
    it("re-keys Summary's and Cooldowns' folded sections", function()
      local sv = {
        summary = { collapsedGroups = { ["CAMWOW US PvE|Horde"] = true, ["|Horde"] = true } },
        options = { cooldowns = { collapsedGroups = { ["CAMWOW US PvP|Alliance"] = true } } },
      }
      migrate(sv, "US PvE")
      assert.are.same({ ["US PvE|Horde"] = true }, sv.summary.collapsedGroups)
      assert.are.same({ ["US PvP|Alliance"] = true }, sv.options.cooldowns.collapsedGroups)
      idempotent(sv, "US PvE")
    end)
  end)

  describe("guild sharing settings", function()
    it("merges each realm-keyed table into the group, a value already there kept", function()
      local sv = { sharing = {
        enabled = true,
        mains = { [US2] = "Frell Blast", [US1] = "Other Main" },
        displayNames = { [US2] = "Frell" },
        onboardingCompleted = { [US1] = true },
        optOut = { [US2] = { ["Alt One"] = true }, [US1] = { ["Alt Two"] = true } },
        nonGuildedOptIn = { [US2] = { ["Alt Three"] = "Guild" } },
        groupUiPrefs = { [US2] = { ["Frell Blast"] = { collapsed = true } } },
      } }
      migrate(sv)
      local s = sv.sharing
      assert.is_true(s.enabled)
      assert.is_string(s.mains["US PvE"])
      assert.is_nil(s.mains[US2])
      assert.are.equal("Frell", s.displayNames["US PvE"])
      assert.is_true(s.onboardingCompleted["US PvE"])
      assert.are.same({ ["Alt One"] = true, ["Alt Two"] = true }, s.optOut["US PvE"])
      assert.are.equal("Guild", s.nonGuildedOptIn["US PvE"]["Alt Three"])
      assert.is_true(s.groupUiPrefs["US PvE"]["Frell Blast"].collapsed)
      idempotent(sv)
    end)

    it("moves \"\" entries to the current group once it is known", function()
      local sv = { sharing = { mains = { [""] = "Frell Blast" }, optOut = { [""] = { Alt = true } } } }
      migrate(sv)
      assert.are.equal("Frell Blast", sv.sharing.mains[""])
      migrate(sv, "US PvE")
      assert.are.equal("Frell Blast", sv.sharing.mains["US PvE"])
      assert.is_true(sv.sharing.optOut["US PvE"].Alt)
      assert.is_nil(sv.sharing.mains[""])
    end)
  end)

  describe("guild data", function()
    it("moves guildmates to the group, the one received last winning, keeping the charRealm they report", function()
      local sv = { guild = { chars = {
        [US2] = { G = { guid = "G", realm = US2, charRealm = "CAMWOW US2 Realm 7 PvE", receivedAt = 5,
          Professions = { alchemy = { rank = 19 } } } },
        [US1] = { G = { guid = "G", realm = US1, receivedAt = 9, level = 40 } },
      }, linkProbes = {}, manual = {} } }
      migrate(sv)
      local g = sv.guild.chars["US PvE"].G
      assert.are.equal(40, g.level)
      assert.are.equal(9, g.receivedAt)
      assert.are.equal(19, g.Professions.alchemy.rank)
      assert.are.equal("US PvE", g.realm)
      -- An older Alt Army answers card requests only for the exact realm string it reported.
      assert.are.equal("CAMWOW US2 Realm 7 PvE", g.charRealm)
      assert.is_nil(sv.guild.chars[US2])
      idempotent(sv)
    end)

    it("moves link probes and manual groups to the group", function()
      local sv = { guild = { chars = {},
        linkProbes = { [US2] = { G = { [165] = { misses = 0 } } }, [US1] = { G = { [171] = { misses = 1 } } } },
        manual = { [US2] = { ["Alt One"] = { main = "Frell" } } },
      } }
      migrate(sv)
      assert.are.same({ [165] = { misses = 0 }, [171] = { misses = 1 } }, sv.guild.linkProbes["US PvE"].G)
      assert.are.equal("Frell", sv.guild.manual["US PvE"]["Alt One"].main)
      idempotent(sv)
    end)

    it("moves guildmates received under \"\" to the current group once it is known", function()
      local sv = { guild = { chars = {
        [""] = { H = { guid = "H", realm = "", charRealm = "CAMWOW US2 Realm 7 PvE", receivedAt = 9 } },
        [US2] = { H = { guid = "H", realm = US2, receivedAt = 2, Professions = { x = {} } } },
      } } }
      migrate(sv)
      assert.is_table(sv.guild.chars[""])
      migrate(sv, "US PvE")
      assert.is_nil(sv.guild.chars[""])
      local h = sv.guild.chars["US PvE"].H
      assert.are.equal(9, h.receivedAt)
      assert.is_table(h.Professions)
      assert.are.equal("US PvE", h.realm)
    end)

    it("keeps a guildmate's \"\" charRealm (an older Alt Army on 1.60.1 answers for \"\")", function()
      local sv = { guild = { chars = { [""] = { H = { guid = "H", realm = "", charRealm = "" } } } } }
      migrate(sv, "US PvE")
      assert.are.equal("", sv.guild.chars["US PvE"].H.charRealm)
    end)
  end)

  describe("auction data", function()
    it("gives the book's scans and summaries the group", function()
      local sv = { book = { version = 1, scans = { { realm = US2, faction = "Horde", t = 1 } },
        summaries = { { realm = US1, faction = "Horde", t = 2 } } } }
      migrate(sv)
      assert.are.equal("US PvE", sv.book.scans[1].realm)
      assert.are.equal("US PvE", sv.book.summaries[1].realm)
      idempotent(sv)
    end)

    it("gives the Auctionator scan log the group, \"\" rows the current group once known", function()
      local sv = { scans = { version = 1, scans = {
        { realm = US1, key = "PvE Horde", faction = "Horde" },
        { realm = "", key = "PvE Horde", faction = "Horde" },
      } } }
      migrate(sv)
      assert.are.equal("US PvE", sv.scans.scans[1].realm)
      assert.are.equal("", sv.scans.scans[2].realm)
      migrate(sv, "US PvE")
      assert.are.equal("US PvE", sv.scans.scans[2].realm)
      assert.are.equal("PvE Horde", sv.scans.scans[2].key)
    end)
  end)

  describe("linked accounts", function()
    it("moves a linked account's characters and mail notes to the group", function()
      local sv = { linked = { version = 1, accounts = { acct1 = { Characters = {
        [US2] = { G = { realm = US2, lastUpdate = 1, money = 5 } },
        [US1R3] = { G = { realm = US1R3, lastUpdate = 2 } },
      } } }, outMail = { acct1 = { m1 = { g = "G", r = US2, rows = {} } } } } }
      migrate(sv)
      local g = sv.linked.accounts.acct1.Characters["US PvE"].G
      assert.are.equal(2, g.lastUpdate)
      assert.are.equal(5, g.money)
      assert.are.equal("US PvE", g.realm)
      assert.are.equal("US PvE", sv.linked.outMail.acct1.m1.r)
      idempotent(sv)
    end)

    it("joins a linked character saved under \"\" to its copy elsewhere", function()
      local sv = { linked = { accounts = { acct1 = { Characters = {
        [""] = { G = { realm = "", lastUpdate = 9 } },
        [US2] = { G = { realm = US2, lastUpdate = 1, money = 5 } },
      } } } } }
      migrate(sv)
      assert.is_nil(sv.linked.accounts.acct1.Characters[""])
      assert.are.equal(9, sv.linked.accounts.acct1.Characters["US PvE"].G.lastUpdate)
    end)
  end)

  describe("the user's real data shapes", function()
    it("brings a 1.60.1 session's copy home and keeps every character", function()
      local sv = {
        data = { Characters = {
          [""] = { ["Player-6931-006AA60C"] = { realm = "", name = "Frell Blast", lastUpdate = 1795202099,
            lastLogout = 1795202099, level = 60, faction = "Horde" } },
          [US2] = {
            ["Player-6931-006AA60C"] = { realm = US2, name = "Frell Blast", lastUpdate = 1795188951, level = 60,
              faction = "Horde", Professions = { Tailoring = {} } },
            ["Player-6931-00159CB0"] = { realm = US2, name = "Frell Fire", lastUpdate = 1794252629 },
          },
          [US1] = { ["Player-6923-00CB2BBF"] = { realm = US1, name = "Gasille Readywrench", lastUpdate = 1 } },
        } },
        guild = { chars = { [""] = { ["Player-6933-0069C8A1"] = { guid = "Player-6933-0069C8A1", realm = "",
          charRealm = "CAMWOW US2 Realm 7 PvE", receivedAt = 1795202007, name = "Solantha Skymane" } } } },
        scans = { version = 1, scans = { { realm = "", key = "PvE Horde", faction = "Horde", t = 1795201743 } } },
      }
      migrate(sv, "US PvE")
      local chars = sv.data.Characters
      assert.is_nil(chars[""])
      local n = 0
      for _ in pairs(chars["US PvE"]) do n = n + 1 end
      assert.are.equal(3, n)
      assert.are.equal(1795202099, chars["US PvE"]["Player-6931-006AA60C"].lastLogout)
      assert.is_table(chars["US PvE"]["Player-6931-006AA60C"].Professions)
      assert.are.equal("Solantha Skymane", sv.guild.chars["US PvE"]["Player-6933-0069C8A1"].name)
      assert.are.equal("CAMWOW US2 Realm 7 PvE", sv.guild.chars["US PvE"]["Player-6933-0069C8A1"].charRealm)
      assert.are.equal("US PvE", sv.scans.scans[1].realm)
      idempotent(sv, "US PvE")
    end)
  end)

  describe("MigrateGlobals", function()
    it("reads and writes the addon's SavedVariables", function()
      local names = { "AltArmyTBC_Data", "AltArmyTBC_SummarySettings", "AltArmyTBC_GuildData" }
      local keep = {}
      for _, k in ipairs(names) do keep[k] = _G[k] end
      _G.AltArmyTBC_Data = { Characters = { [US2] = { A = { realm = US2 } } } }
      _G.AltArmyTBC_SummarySettings = { characters = { [US2 .. "\\A"] = { pin = true } } }
      _G.AltArmyTBC_GuildData = nil
      FR.MigrateGlobals("US PvE")
      assert.is_table(AltArmyTBC_Data.Characters["US PvE"].A)
      assert.is_true(AltArmyTBC_SummarySettings.characters["US PvE\\A"].pin)
      assert.is_nil(_G.AltArmyTBC_GuildData)
      for _, k in ipairs(names) do _G[k] = keep[k] end
    end)
  end)
end)
