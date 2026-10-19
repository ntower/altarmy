--[[
  Unit tests for GuildShareData.lua (received guildmate data store).
  Run from project root: npm test
]]

describe("GuildShareData", function()
  local GSD, P, GMG
  local NOW = 1700000000

  local function presence(main, chars)
    return { v = 1, main = main, displayName = main and (main .. "!"), chars = chars }
  end

  local function charEntry(name, profs)
    return { name = name, realm = "R", classFile = "MAGE", faction = "Alliance", level = 70, profs = profs or {} }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.time = function() return NOW end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("CharKey")
    require("GuildShareProtocol")
    require("GuildShareData")
    require("GuildManualGroups")
    GSD = AltArmy.GuildShareData
    P = AltArmy.GuildShareProtocol
    GMG = AltArmy.GuildManualGroups
    assert.truthy(GSD)
  end)

  before_each(function()
    _G.AltArmyTBC_GuildData = nil
    GSD._Ensure()
    if GMG and GMG._Ensure then GMG._Ensure() end
  end)

  describe("SaveReceived / getters", function()
    it("stores each character under realm keyed by name with guild + main + source", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 42 } }),
        charEntry("Alt", {}),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")

      local members = GSD.GetGuildMembers("G")
      assert.are.equal(2, #members)

      local main = GSD.GetCharacter("Main", "R")
      assert.are.equal("G", main.guildName)
      assert.are.equal("Main", main.main)
      assert.is_true(main.isMain)
      assert.are.equal("Main", main.source)
      assert.are.equal(NOW, main.receivedAt)

      local alt = GSD.GetCharacter("Alt", "R")
      assert.are.equal("Main", alt.main)
      assert.is_false(alt.isMain)
    end)

    it("guesses a main for received data when the sender declares none (level, then item level)", function()
      -- Sender hasn't picked a main (presence.main nil). Same level, differing item level:
      -- the higher-item-level character becomes the implicit main for the whole group.
      local msg = {
        v = 1, main = nil, chars = {
          { name = "Lowgear", classFile = "MAGE", level = 70, itemLevel = 100, profs = {} },
          { name = "Topgear", classFile = "MAGE", level = 70, itemLevel = 145, profs = {} },
          { name = "Leveler", classFile = "WARRIOR", level = 40, itemLevel = 200, profs = {} },
        },
      }
      GSD.SaveReceived("Peer", P.ParsePresence(msg), "G", "R")
      local top = GSD.GetCharacter("Topgear", "R")
      local low = GSD.GetCharacter("Lowgear", "R")
      assert.are.equal("Topgear", top.main)
      assert.is_true(top.isMain)
      assert.is_false(top.mainDeclared)
      assert.are.equal("Topgear", low.main)
      assert.is_false(low.isMain)
      assert.is_false(low.mainDeclared)
      assert.are.equal("Topgear", GSD.GetCharacter("Leveler", "R").main)
    end)

    it("stores received item level and keeps a sender-declared main untouched", function()
      local msg = {
        v = 1, main = "Declared", chars = {
          { name = "Declared", classFile = "MAGE", level = 70, itemLevel = 90, profs = {} },
          { name = "Beefy", classFile = "WARRIOR", level = 70, itemLevel = 150, profs = {} },
        },
      }
      GSD.SaveReceived("Peer", P.ParsePresence(msg), "G", "R")
      local declared = GSD.GetCharacter("Declared", "R")
      assert.are.equal("Declared", declared.main)
      assert.is_true(declared.isMain)
      assert.is_true(declared.mainDeclared)
      assert.are.equal(150, GSD.GetCharacter("Beefy", "R").itemLevel)
      assert.is_false(GSD.GetCharacter("Beefy", "R").isMain)
      assert.is_true(GSD.GetCharacter("Beefy", "R").mainDeclared)
    end)

    it("stores a received profession specialization", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.equal("Spellfire", GSD.GetCharacter("Main", "R").Professions.tailoring.spec)
    end)

    it("does not clear guildName when SaveReceived is called with a nil guild", function()
      local msg = presence("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Peer", P.ParsePresence(msg), "G", "R")
      GSD.SaveReceived("Peer", P.ParsePresence(msg), nil, "R")
      assert.are.equal("G", GSD.GetCharacter("Main", "R").guildName)
      assert.are.equal("G", GSD.GetCharacter("Alt", "R").guildName)
      assert.are.equal(2, #GSD.GetGuildMembers("G"))
    end)

    it("GetMainOf resolves an alt to its main, and a main to itself", function()
      local msg = presence("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.equal("Main", GSD.GetMainOf("Alt", "R"))
      assert.are.equal("Main", GSD.GetMainOf("Main", "R"))
      assert.is_nil(GSD.GetMainOf("Stranger", "R"))
    end)

    it("GetMainOf falls through to manual mappings when no stored character", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GSD.GetMainOf("Bobsalt", "R"))
      assert.are.equal("Bob", GSD.GetMainOf("Bob", "R"))
      assert.is_nil(GSD.GetMainOf("Stranger", "R"))
    end)

    it("GetMainOf prefers stored character over manual mapping", function()
      GMG.SetMapping("Alt", "R", "ManualMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("AddonMain", {
        charEntry("AddonMain"), charEntry("Alt"),
      })), "G", "R")
      assert.are.equal("AddonMain", GSD.GetMainOf("Alt", "R"))
    end)
  end)

  describe("PresenceMatchesStored", function()
    local function parsed(main, chars)
      return P.ParsePresence(presence(main, chars))
    end

    it("returns false when no prior data exists", function()
      assert.is_false(GSD.PresenceMatchesStored("Peer", parsed("Main", { charEntry("Main") }), "R"))
    end)

    it("returns true when presence matches stored data", function()
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 42 } }),
        charEntry("Alt", {}),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      assert.is_true(GSD.PresenceMatchesStored("Peer", msg, "R"))
    end)

    it("returns false when level changes", function()
      local msg = parsed("Main", { charEntry("Main") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence(presence("Main", {
        { name = "Main", realm = "R", classFile = "MAGE", faction = "Alliance", level = 71, profs = {} },
      }))
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when rv changes", function()
      local rv1 = P.HashRecipeIDs({ 100, 200 })
      local rv2 = P.HashRecipeIDs({ 100, 200, 300 })
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv1 } }),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3, rv = rv2 } }),
      }))
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when main changes", function()
      local msg = parsed("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Alt", { charEntry("Main"), charEntry("Alt") })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when displayName changes", function()
      local msg = P.ParsePresence({ v = 1, main = "Main", displayName = "OldName", chars = { charEntry("Main") } })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence({ v = 1, main = "Main", displayName = "NewName", chars = { charEntry("Main") } })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when mainDeclared changes even if the effective main name matches", function()
      local declared = P.ParsePresence({
        v = 1, main = "Topgear", chars = {
          { name = "Topgear", classFile = "MAGE", level = 70, itemLevel = 145, profs = {} },
          { name = "Lowgear", classFile = "MAGE", level = 70, itemLevel = 100, profs = {} },
        },
      })
      GSD.SaveReceived("Peer", declared, "G", "R")
      assert.is_true(GSD.GetCharacter("Topgear", "R").mainDeclared)
      local deduced = P.ParsePresence({
        v = 1, main = nil, chars = {
          { name = "Topgear", classFile = "MAGE", level = 70, itemLevel = 145, profs = {} },
          { name = "Lowgear", classFile = "MAGE", level = 70, itemLevel = 100, profs = {} },
        },
      })
      assert.is_false(GSD.PresenceMatchesStored("Peer", deduced, "R"))
    end)

    it("returns false when spec changes", function()
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, spec = "Spellfire" } }),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, spec = "Shadoweave" } }),
      })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when a new char appears in presence", function()
      local msg = parsed("Main", { charEntry("Main") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Main", { charEntry("Main"), charEntry("NewAlt") })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when a previously stored char from this sender is missing", function()
      local msg = parsed("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local reduced = parsed("Main", { charEntry("Main") })
      assert.is_false(GSD.PresenceMatchesStored("Peer", reduced, "R"))
    end)

    it("returns true for empty presence when nothing is stored from that sender", function()
      assert.is_true(GSD.PresenceMatchesStored("Peer", parsed("Main", {}), "R"))
      GSD.SaveReceived("Other", parsed("Other", { charEntry("Other") }), "G", "R")
      assert.is_true(GSD.PresenceMatchesStored("Peer", parsed("Main", {}), "R"))
    end)

    it("returns false for empty presence when that sender still has stored chars", function()
      GSD.SaveReceived("Peer", parsed("Main", { charEntry("Main") }), "G", "R")
      assert.is_false(GSD.PresenceMatchesStored("Peer", parsed("Main", {}), "R"))
    end)
  end)

  describe("TouchReceivedAt", function()
    local function parsed(main, chars)
      return P.ParsePresence(presence(main, chars))
    end

    it("bumps receivedAt for presence chars from that sender without changing content", function()
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 42 } }),
        charEntry("Alt", {}),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local main = GSD.GetCharacter("Main", "R")
      local alt = GSD.GetCharacter("Alt", "R")
      assert.are.equal(NOW, main.receivedAt)
      main.receivedAt = NOW - 20 * 24 * 60 * 60
      alt.receivedAt = NOW - 20 * 24 * 60 * 60

      local touched = GSD.TouchReceivedAt("Peer", msg, "R")
      assert.is_true(touched)
      assert.are.equal(NOW, GSD.GetCharacter("Main", "R").receivedAt)
      assert.are.equal(NOW, GSD.GetCharacter("Alt", "R").receivedAt)
      assert.are.equal(375, GSD.GetCharacter("Main", "R").Professions.tailoring.rank)
    end)

    it("does not bump chars from a different sender", function()
      GSD.SaveReceived("Alice", parsed("Alice", { charEntry("Alice") }), "G", "R")
      GSD.SaveReceived("Bob", parsed("Bob", { charEntry("Bob") }), "G", "R")
      GSD.GetCharacter("Alice", "R").receivedAt = NOW - 1000
      GSD.GetCharacter("Bob", "R").receivedAt = NOW - 1000

      local touched = GSD.TouchReceivedAt("Bob", parsed("Bob", { charEntry("Bob") }), "R")
      assert.is_true(touched)
      assert.are.equal(NOW - 1000, GSD.GetCharacter("Alice", "R").receivedAt)
      assert.are.equal(NOW, GSD.GetCharacter("Bob", "R").receivedAt)
    end)

    it("returns false when presence has no matching stored chars", function()
      assert.is_false(GSD.TouchReceivedAt("Peer", parsed("Main", { charEntry("Main") }), "R"))
      assert.is_false(GSD.TouchReceivedAt("Peer", parsed("Main", {}), "R"))
    end)
  end)

  describe("SaveReceived clear-by-source", function()
    it("removes all chars from a sender when they advertise an empty presence", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Main", {
        charEntry("Main"), charEntry("Alt"),
      })), "G", "R")
      assert.truthy(GSD.GetCharacter("Main", "R"))
      assert.truthy(GSD.GetCharacter("Alt", "R"))

      GSD.SaveReceived("Peer", P.ParsePresence({ v = 1, chars = {} }), "G", "R")
      assert.is_nil(GSD.GetCharacter("Main", "R"))
      assert.is_nil(GSD.GetCharacter("Alt", "R"))
    end)

    it("does not remove chars stored from a different sender", function()
      GSD.SaveReceived("Alice", P.ParsePresence(presence("Alice", { charEntry("Alice") })), "G", "R")
      GSD.SaveReceived("Bob", P.ParsePresence(presence("Bob", { charEntry("Bob") })), "G", "R")

      GSD.SaveReceived("Alice", P.ParsePresence({ v = 1, chars = {} }), "G", "R")
      assert.is_nil(GSD.GetCharacter("Alice", "R"))
      assert.truthy(GSD.GetCharacter("Bob", "R"))
      assert.are.equal("Bob", GSD.GetCharacter("Bob", "R").source)
    end)

    it("removes only chars dropped from a non-empty presence for that sender", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Main", {
        charEntry("Main"), charEntry("Alt"),
      })), "G", "R")
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Main", { charEntry("Main") })), "G", "R")
      assert.truthy(GSD.GetCharacter("Main", "R"))
      assert.is_nil(GSD.GetCharacter("Alt", "R"))
    end)
  end)

  describe("slim v2 presence + char cards", function()
    local function slimPresence(main, chars)
      return { v = 2, main = main, displayName = main and (main .. "!"), chars = chars }
    end

    local function slimChar(name, ch, overrides)
      local c = {
        name = name, realm = "R", classFile = "MAGE", faction = "Alliance",
        level = 70, itemLevel = 100, ch = ch,
      }
      for k, v in pairs(overrides or {}) do c[k] = v end
      return c
    end

    it("marks chars as needing a profession card on first slim save", function()
      local msg = P.ParsePresence(slimPresence("Main", { slimChar("Main", 42) }))
      GSD.SaveReceived("Peer", msg, "G", "R")
      local stored = GSD.GetCharacter("Main", "R")
      assert.are.equal(42, stored.ch)
      assert.is_true(stored.needsProfessionCard)
      assert.are.same({}, stored.Professions)
      local needing = GSD.CharsNeedingProfessionCard(msg, "R")
      assert.are.equal(1, #needing)
      assert.are.equal("Main", needing[1].name)
    end)

    it("preserves professions when slim checksum is unchanged", function()
      local msg = P.ParsePresence(slimPresence("Main", { slimChar("Main", 42) }))
      GSD.SaveReceived("Peer", msg, "G", "R")
      GSD.SaveCharCard("Peer", {
        v = 2, name = "Main", realm = "R", classFile = "MAGE", faction = "Alliance",
        level = 70, itemLevel = 100, ch = 42,
        profs = { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 9 } },
      }, "G", "R")
      assert.is_false(GSD.GetCharacter("Main", "R").needsProfessionCard)
      assert.are.equal(375, GSD.GetCharacter("Main", "R").Professions.tailoring.rank)

      GSD.SaveReceived("Peer", msg, "G", "R")
      assert.is_false(GSD.GetCharacter("Main", "R").needsProfessionCard)
      assert.are.equal(375, GSD.GetCharacter("Main", "R").Professions.tailoring.rank)
      assert.are.equal(0, #GSD.CharsNeedingProfessionCard(msg, "R"))
      assert.is_true(GSD.PresenceMatchesStored("Peer", msg, "R"))
    end)

    it("clears professions and re-requests card when checksum changes", function()
      local first = P.ParsePresence(slimPresence("Main", { slimChar("Main", 42) }))
      GSD.SaveReceived("Peer", first, "G", "R")
      GSD.SaveCharCard("Peer", {
        v = 2, name = "Main", realm = "R", ch = 42,
        profs = { { key = "tailoring", name = "Tailoring", rank = 375, count = 1, rv = 1 } },
      }, "G", "R")

      local second = P.ParsePresence(slimPresence("Main", { slimChar("Main", 99) }))
      GSD.SaveReceived("Peer", second, "G", "R")
      local stored = GSD.GetCharacter("Main", "R")
      assert.are.equal(99, stored.ch)
      assert.is_true(stored.needsProfessionCard)
      assert.is_nil(stored.Professions.tailoring)
      assert.is_false(GSD.PresenceMatchesStored("Peer", second, "R"))
    end)

    it("SaveCharCard merges recipes when rv is unchanged", function()
      local rv = P.HashRecipeIDs({ 100, 200 })
      local msg = P.ParsePresence(slimPresence("Main", { slimChar("Main", 42) }))
      GSD.SaveReceived("Peer", msg, "G", "R")
      GSD.SaveCharCard("Peer", {
        v = 2, name = "Main", realm = "R", ch = 42,
        profs = { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = rv } },
      }, "G", "R")
      GSD.SaveRecipes("R", { v = 1, name = "Main", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      GSD.SaveCharCard("Peer", {
        v = 2, name = "Main", realm = "R", ch = 42,
        profs = { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = rv } },
      }, "G", "R")
      assert.truthy(GSD.GetCharacter("Main", "R").Professions.tailoring.Recipes[100])
    end)
  end)

  describe("recipe pull tracking", function()
    it("flags professions as needing recipes until SaveRecipes fills them", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      GSD.SaveRecipes("R", { v = 1, name = "Main", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      local profs = GSD.GetRecipesFor("Main", "R")
      assert.truthy(profs.tailoring.Recipes[100])
      assert.are.equal(100, profs.tailoring.Recipes[100].primaryRecipeID)
    end)

    it("re-flags a profession for pull when the advertised version changes", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })), "G", "R")
      GSD.SaveRecipes("R", { v = 1, name = "Main", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      -- New presence advertises a different recipe set version -> needs re-pull, old recipes dropped.
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3, rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R"))
    end)

    it("returns empty within backoff after MarkRecipesRequested", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 100))
    end)

    it("returns prof again after backoff expires", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 3601))
    end)

    it("ignores backoff when rv changes", function()
      local rv1 = P.HashRecipeIDs({ 100, 200 })
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv1 } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3,
          rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 100))
    end)

    it("preserves recipesRequestedAt when rv is unchanged on SaveReceived", function()
      local rv = P.HashRecipeIDs({ 100, 200 })
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
      })), "G", "R")
      assert.are.equal(NOW, GSD.GetCharacter("Main", "R").Professions.tailoring.recipesRequestedAt)
    end)

    it("clears recipesRequestedAt when rv changes on SaveReceived", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3,
          rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.is_nil(GSD.GetCharacter("Main", "R").Professions.tailoring.recipesRequestedAt)
    end)
  end)

  describe("local guild members for display", function()
    before_each(function()
      AltArmy.GuildShareSettings = {
        _CurrentRealm = function() return "R" end,
        GetMain = function() return "Main" end,
        GetDisplayName = function() return "MainDisplay" end,
        GetAllGuildedCharacters = function(guild, realm)
          if guild ~= "G" or realm ~= "R" then return {} end
          return {
            { name = "Main", realm = "R", char = {
              name = "Main", classFile = "MAGE", level = 70,
              Professions = { Tailoring = { rank = 375, Recipes = { [1] = { primaryRecipeID = 1 } } } },
            } },
            { name = "Alt", realm = "R", char = { name = "Alt", classFile = "WARRIOR", level = 42 } },
          }
        end,
      }
    end)

    it("GetLocalGuildMembers builds entries from account data", function()
      local members = GSD.GetLocalGuildMembers("G", "R")
      assert.are.equal(2, #members)
      local main, alt
      for _, m in ipairs(members) do
        if m.name == "Main" then main = m elseif m.name == "Alt" then alt = m end
      end
      assert.are.equal("local", main.source)
      assert.is_true(main.isMain)
      assert.is_true(main.mainDeclared)
      assert.are.equal("MainDisplay", main.displayName)
      assert.truthy(main.Professions.Tailoring)
      assert.are.equal(375, main.Professions.Tailoring.rank)
      assert.is_false(alt.isMain)
      assert.is_true(alt.mainDeclared)
    end)

    it("GetGuildMembersForDisplay merges received data with local account characters", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Peer", { charEntry("Peer") })), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      assert.are.equal(3, #members)
      local names = {}
      for _, m in ipairs(members) do names[m.name] = m.source end
      assert.are.equal("Peer", names.Peer)
      assert.is_true(names.Main ~= nil)
      assert.are.equal("local", names.Main)
      assert.are.equal("local", names.Alt)
    end)

    it("groups all local characters under a default main when none is configured", function()
      -- Sharing enabled but no main picked yet: every character must still collapse under
      -- one group instead of each becoming its own top-level row.
      AltArmy.GuildShareSettings.GetMain = function() return nil end
      local members = GSD.GetLocalGuildMembers("G", "R")
      assert.are.equal(2, #members)
      local mains, isMainCount = {}, 0
      for _, m in ipairs(members) do
        local key = m.main or "<nil>"
        mains[key] = (mains[key] or 0) + 1
        if m.isMain then isMainCount = isMainCount + 1 end
        assert.is_false(m.mainDeclared)
      end
      -- Highest-level character (Main, 70) becomes the implicit main for the whole group.
      assert.are.equal(2, mains["Main"])
      assert.is_nil(mains["<nil>"])
      assert.are.equal(1, isMainCount)
    end)

    it("local account data overrides received entries for the same character", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 1, count = 0, rv = 0 } }),
      })), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local main
      for _, m in ipairs(members) do
        if m.name == "Main" then main = m break end
      end
      assert.are.equal("local", main.source)
      assert.are.equal(375, main.Professions.Tailoring.rank)
    end)

    it("GetGuildMembersForDisplay appends unshadowed manual mappings", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", {
        guild = "G", origin = "note", noteText = "bob alt",
      })
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("manual", byName.Bobsalt.source)
      assert.are.equal("Bob", byName.Bobsalt.main)
      assert.is_false(byName.Bobsalt.mainDeclared)
      assert.are.equal("note", byName.Bobsalt.origin)
      assert.are.equal("bob alt", byName.Bobsalt.noteText)
      assert.are.equal("G", byName.Bobsalt.guildName)
      -- Stub main when not already present
      assert.truthy(byName.Bob)
      assert.are.equal("manual", byName.Bob.source)
      assert.is_true(byName.Bob.isMain)
      assert.is_false(byName.Bob.mainDeclared)
      -- Local chars still present
      assert.are.equal("local", byName.Main.source)
    end)

    it("GetGuildMembersForDisplay skips manual mappings shadowed by received or local data", function()
      GMG.SetMapping("Alt", "R", "ManualMain", { guild = "G" })
      GMG.SetMapping("PeerAlt", "R", "Peer", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Peer", {
        charEntry("Peer"), charEntry("PeerAlt"),
      })), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      -- Local Alt wins over manual
      assert.are.equal("local", byName.Alt.source)
      assert.are.equal("Main", byName.Alt.main)
      -- Received PeerAlt wins over manual
      assert.are.equal("Peer", byName.PeerAlt.source)
      assert.are.equal("Peer", byName.PeerAlt.main)
      assert.is_nil(byName.ManualMain)
    end)

    it("enriches manual entries from an optional roster info map", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      local rosterInfo = {
        bobsalt = { classFile = "WARRIOR", level = 60, name = "Bobsalt" },
        bob = { classFile = "MAGE", level = 70, name = "Bob" },
      }
      local members = GSD.GetGuildMembersForDisplay("G", "R", false, rosterInfo)
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("WARRIOR", byName.Bobsalt.classFile)
      assert.are.equal(60, byName.Bobsalt.level)
      assert.are.equal("MAGE", byName.Bob.classFile)
      assert.are.equal(70, byName.Bob.level)
    end)

    it("falls back to stored classFile and level when roster info is absent", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", {
        guild = "G", classFile = "WARRIOR", level = 60,
      })
      GMG.SetMapping("Bob", "R", "Bob", {
        guild = "G", classFile = "MAGE", level = 70,
      })
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("WARRIOR", byName.Bobsalt.classFile)
      assert.are.equal(60, byName.Bobsalt.level)
      assert.are.equal("MAGE", byName.Bob.classFile)
      assert.are.equal(70, byName.Bob.level)
    end)
  end)

  describe("purging", function()
    it("PurgeGuild removes all characters in a guild", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      GSD.SaveReceived("B", P.ParsePresence(presence("B", { charEntry("B") })), "OtherGuild", "R")
      GSD.PurgeGuild("G")
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
      assert.are.equal(1, #GSD.GetGuildMembers("OtherGuild"))
    end)

    it("PurgeStale removes entries older than maxAge", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      local removed = GSD.PurgeStale(100, NOW + 1000)
      assert.are.equal(1, removed)
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
    end)

    it("PurgeStale keeps fresh entries", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      local removed = GSD.PurgeStale(100, NOW + 50)
      assert.are.equal(0, removed)
      assert.are.equal(1, #GSD.GetGuildMembers("G"))
    end)

    it("RemoveGroup removes all characters under that main", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main"), charEntry("Alt"),
      })), "G", "R")
      GSD.SaveReceived("Other", P.ParsePresence(presence("Other", {
        charEntry("Other"),
      })), "G", "R")
      local removed = GSD.RemoveGroup("Main", "R")
      assert.are.equal(2, removed)
      local remaining = GSD.GetGuildMembers("G")
      assert.are.equal(1, #remaining)
      assert.are.equal("Other", remaining[1].name)
    end)

    it("RemoveGroup with no realm searches all realms", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main"),
      })), "G", "R")
      local removed = GSD.RemoveGroup("Main")
      assert.are.equal(1, removed)
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
    end)

    it("SaveReceived retires manual mappings that agree with the addon main", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Main", {
        charEntry("Main"), charEntry("Alt"),
      })), "G", "R")
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)

    it("SaveReceived keeps disagreeing manual mappings (shadowed, not deleted)", function()
      GMG.SetMapping("Alt", "R", "ManualMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("AddonMain", {
        charEntry("AddonMain"), charEntry("Alt"),
      })), "G", "R")
      local m = GMG.GetMapping("Alt", "R")
      assert.truthy(m)
      assert.are.equal("ManualMain", m.main)
    end)

    it("SaveReceived retires only the presence's names, leaving other mappings alone", function()
      GMG.SetMapping("PeerAlt", "R", "PeerMain", { guild = "G" })
      GMG.SetMapping("OtherAlt", "R", "PeerMain", { guild = "G" })
      GMG.SetMapping("Elsewhere", "OtherRealm", "PeerMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("PeerMain", {
        charEntry("PeerMain"), charEntry("PeerAlt"),
      })), "G", "R")
      assert.is_nil(GMG.GetMapping("PeerAlt", "R"))
      assert.truthy(GMG.GetMapping("OtherAlt", "R"))
      assert.truthy(GMG.GetMapping("Elsewhere", "OtherRealm"))
    end)

    it("disagreeing presence shadows the mapping in display and IsShadowed", function()
      AltArmy.GuildShareSettings = nil
      GMG.SetMapping("PeerAlt", "R", "ManualMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("AddonMain", {
        charEntry("AddonMain"), charEntry("PeerAlt"),
      })), "G", "R")
      assert.is_true(GMG.IsShadowed("PeerAlt", "R"))
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("AddonMain", byName.PeerAlt.main)
      assert.are.equal("Peer", byName.PeerAlt.source)
      assert.are.not_equal("manual", byName.PeerAlt.source)
    end)

    it("main-only presence retires the anchor; manual alts still group via display stubs", function()
      AltArmy.GuildShareSettings = nil
      GMG.SetMapping("PeerMain", "R", "PeerMain", { guild = "G" })
      GMG.SetMapping("PeerAlt", "R", "PeerMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("PeerMain", {
        charEntry("PeerMain"),
      })), "G", "R")
      assert.is_nil(GMG.GetMapping("PeerMain", "R"))
      assert.truthy(GMG.GetMapping("PeerAlt", "R"))
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("Peer", byName.PeerMain.source)
      assert.are.equal("manual", byName.PeerAlt.source)
      assert.are.equal("PeerMain", byName.PeerAlt.main)
    end)

    it("opt-out empty presence unshadows surviving manual mappings", function()
      AltArmy.GuildShareSettings = nil
      GMG.SetMapping("PeerAlt", "R", "ManualMain", { guild = "G" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("AddonMain", {
        charEntry("AddonMain"), charEntry("PeerAlt"),
      })), "G", "R")
      assert.is_true(GMG.IsShadowed("PeerAlt", "R"))
      -- Peer opts out: empty presence clears their received chars.
      GSD.SaveReceived("Peer", P.ParsePresence({ v = 1, chars = {} }), "G", "R")
      assert.is_false(GMG.IsShadowed("PeerAlt", "R"))
      assert.truthy(GMG.GetMapping("PeerAlt", "R"))
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("manual", byName.PeerAlt.source)
      assert.are.equal("ManualMain", byName.PeerAlt.main)
    end)

    it("SetMapping after coverage is shadowed then retired by the next agreeing presence", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("PeerMain", {
        charEntry("PeerMain"), charEntry("PeerAlt"),
      })), "G", "R")
      GMG.SetMapping("PeerAlt", "R", "PeerMain", { guild = "G", origin = "user" })
      assert.is_true(GMG.IsShadowed("PeerAlt", "R"))
      assert.truthy(GMG.GetMapping("PeerAlt", "R"))
      GSD.SaveReceived("Peer", P.ParsePresence(presence("PeerMain", {
        charEntry("PeerMain"), charEntry("PeerAlt"),
      })), "G", "R")
      assert.is_nil(GMG.GetMapping("PeerAlt", "R"))
    end)

    it("PurgeGuild also clears manual mappings for that guild", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GMG.SetMapping("OtherAlt", "R", "Other", { guild = "OtherGuild" })
      GSD.PurgeGuild("G")
      assert.is_nil(GMG.GetMapping("Alt", "R"))
      assert.truthy(GMG.GetMapping("OtherAlt", "R"))
    end)

    it("PurgeAll also clears all manual mappings", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GSD.PurgeAll()
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)

    it("PurgeStale does not remove manual mappings", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      GSD.PurgeStale(100, NOW + 1000)
      assert.truthy(GMG.GetMapping("Alt", "R"))
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
    end)

    it("PurgeStale converts stale received characters into a manual group", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Main", {
        charEntry("Main"), charEntry("Alt"),
      })), "G", "R")
      local removed = GSD.PurgeStale(100, NOW + 1000)
      assert.are.equal(2, removed)
      assert.are.equal(0, #GSD.GetGuildMembers("G"))

      local mainMap = GMG.GetMapping("Main", "R")
      local altMap = GMG.GetMapping("Alt", "R")
      assert.truthy(mainMap)
      assert.truthy(altMap)
      assert.are.equal("Main", mainMap.main)
      assert.are.equal("Main", altMap.main)
      assert.are.equal("G", altMap.guild)
      assert.are.equal("MAGE", altMap.classFile)
      assert.are.equal(70, altMap.level)

      AltArmy.GuildShareSettings = nil
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local byName = {}
      for _, m in ipairs(members) do byName[m.name] = m end
      assert.are.equal("manual", byName.Main.source)
      assert.are.equal("manual", byName.Alt.source)
      assert.are.equal("Main", byName.Alt.main)
      assert.are.same({}, byName.Main.Professions)
      assert.are.same({}, byName.Alt.Professions)
    end)

    it("PurgeStale does not overwrite an existing manual mapping", function()
      GMG.SetMapping("Alt", "R", "ManualMain", { guild = "G", origin = "user" })
      GSD.SaveReceived("Peer", P.ParsePresence(presence("AddonMain", {
        charEntry("AddonMain"), charEntry("Alt"),
      })), "G", "R")
      GSD.PurgeStale(100, NOW + 1000)
      local altMap = GMG.GetMapping("Alt", "R")
      assert.truthy(altMap)
      assert.are.equal("ManualMain", altMap.main)
    end)
  end)

  describe("character IDs", function()
    local function idChar(name, guid, fields)
      local c = charEntry(name)
      c.guid = guid
      for k, v in pairs(fields or {}) do c[k] = v end
      return c
    end

    local function idPresence(from, main, mainGuid, chars)
      return P.ParsePresence({ v = 1, from = from, main = main, mainGuid = mainGuid, chars = chars })
    end

    local function keys(realm)
      local out = {}
      for k in pairs(AltArmyTBC_GuildData.chars[realm or "R"] or {}) do out[#out + 1] = k end
      table.sort(out)
      return out
    end

    it("stores characters that carry an ID under that ID and finds them by name", function()
      GSD.SaveReceived("Frell", idPresence("Player-1-B", "Frell Blast", "Player-1-B", {
        idChar("Frell Blast", "Player-1-B"),
        idChar("Frell Ofelements", "Player-1-A"),
      }), "G", "R")
      assert.are.same({ "Player-1-A", "Player-1-B" }, keys())
      local blast = GSD.GetCharacter("Frell Blast", "R")
      assert.are.equal("Frell Blast", blast.name)
      assert.are.equal("Player-1-B", blast.guid)
      assert.are.equal(blast, GSD.GetCharacter("Player-1-B", "R"))
      assert.are.equal(blast, GSD.FindCharacter("Frell Blast"))
      assert.are.equal("Frell Blast", GSD.GetMainOf("Frell Ofelements"))
      assert.are.equal("Frell Blast", GSD.GetMainOf("Frell Ofelements", "R"))
    end)

    it("keeps two senders whose names shorten to the same first name apart", function()
      GSD.SaveReceived("Frell", idPresence("Player-1-B", nil, nil, { idChar("Frell Blast", "Player-1-B") }), "G", "R")
      GSD.SaveReceived("Frell", idPresence("Player-9-X", nil, nil, { idChar("Frell Hound", "Player-9-X") }), "G", "R")
      assert.are.same({ "Player-1-B", "Player-9-X" }, keys())
    end)

    it("adopts an older name-keyed entry when that character now sends its ID", function()
      GSD.SaveReceived("Frell", P.ParsePresence(presence(nil, { charEntry("Frell Blast") })), "G", "R")
      assert.are.same({ "Frell Blast" }, keys())
      GSD.SaveReceived("Frell", idPresence("Player-1-B", nil, nil, { idChar("Frell Blast", "Player-1-B") }), "G", "R")
      assert.are.same({ "Player-1-B" }, keys())
    end)

    it("drops a first-name entry from an older version when that sender upgrades", function()
      GSD.SaveReceived("Frell", P.ParsePresence(presence(nil, { charEntry("Frell") })), "G", "R")
      GSD.SaveReceived("Frell", idPresence("Player-1-B", nil, nil, { idChar("Frell Blast", "Player-1-B") }), "G", "R")
      assert.are.same({ "Player-1-B" }, keys())
    end)

    it("does not let an older client with the same short name remove ID-keyed characters", function()
      GSD.SaveReceived("Frell", idPresence("Player-1-B", nil, nil, { idChar("Frell Blast", "Player-1-B") }), "G", "R")
      GSD.SaveReceived("Frell", P.ParsePresence(presence(nil, { charEntry("Frell") })), "G", "R")
      assert.are.same({ "Frell", "Player-1-B" }, keys())
    end)

    it("names the group after the main's ID", function()
      GSD.SaveReceived("Frell", idPresence("Player-1-B", "Frell", "Player-1-B", {
        idChar("Frell Blast", "Player-1-B"),
        idChar("Frell Ofelements", "Player-1-A"),
      }), "G", "R")
      assert.are.equal("Frell Blast", GSD.GetCharacter("Player-1-A", "R").main)
      assert.is_true(GSD.GetCharacter("Player-1-B", "R").isMain)
    end)

    it("matches and touches an unchanged ID presence", function()
      local msg = idPresence("Player-1-B", "Frell Blast", "Player-1-B", { idChar("Frell Blast", "Player-1-B") })
      GSD.SaveReceived("Frell", msg, "G", "R")
      assert.is_true(GSD.PresenceMatchesStored("Frell", msg, "R"))
      assert.is_true(GSD.TouchReceivedAt("Frell", msg, "R"))
      local renamed = idPresence("Player-1-B", "Frell Blasty", "Player-1-B", { idChar("Frell Blasty", "Player-1-B") })
      assert.is_false(GSD.PresenceMatchesStored("Frell", renamed, "R"))
      GSD.SaveReceived("Frell", renamed, "G", "R")
      assert.are.same({ "Player-1-B" }, keys())
      assert.are.equal("Frell Blasty", GSD.GetCharacter("Player-1-B", "R").name)
    end)

    it("treats a presence that still needs its legacy entry re-keyed as changed", function()
      GSD.SaveReceived("Frell", P.ParsePresence(presence(nil, { charEntry("Frell Blast") })), "G", "R")
      local msg = idPresence("Player-1-B", nil, nil, { idChar("Frell Blast", "Player-1-B") })
      assert.is_false(GSD.PresenceMatchesStored("Frell", msg, "R"))
    end)

    it("saves cards and recipe lists sent with an ID under that ID", function()
      GSD.SaveReceived("Frell", P.ParsePresence({
        v = 2, from = "Player-1-B", chars = { { name = "Frell Blast", guid = "Player-1-B", ch = 5 } },
      }), "G", "R")
      assert.are.same({ { name = "Frell Blast", realm = "R", guid = "Player-1-B" } },
        GSD.CharsNeedingProfessionCard(P.ParsePresence({
          v = 2, chars = { { name = "Frell Blast", guid = "Player-1-B", ch = 5 } },
        }), "R"))
      GSD.SaveCharCard("Frell", P.ParseCharCard({
        v = 2, from = "Player-1-B", name = "Frell Blast", guid = "Player-1-B", ch = 5,
        profs = { { key = "tailoring", rank = 300, count = 1, rv = 9 } },
      }), "G", "R")
      -- The requester may still know the character by an older name; the ID wins.
      GSD.SaveRecipes("R", P.ParseRecipes({
        v = 1, name = "Frell", guid = "Player-1-B", profs = { { key = "tailoring", ids = { 42 } } },
      }))
      assert.are.same({ "Player-1-B" }, keys())
      local entry = GSD.GetCharacter("Player-1-B", "R")
      assert.is_false(entry.needsProfessionCard)
      assert.is_truthy(entry.Professions.tailoring.Recipes[42])
    end)

    it("keeps a manual mapping by name when an ID-keyed character goes stale", function()
      GSD.SaveReceived("Frell", idPresence("Player-1-B", "Frell Blast", "Player-1-B", {
        idChar("Frell Blast", "Player-1-B"),
      }), "G", "R")
      GSD.PurgeStale(10, NOW + 100)
      assert.are.same({}, keys())
      assert.is_truthy(GMG.GetMapping("Frell Blast", "R"))
      assert.is_nil(GMG.GetMapping("Player-1-B", "R"))
    end)
  end)

  describe("the player's own characters", function()
    local savedDS

    before_each(function()
      savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm ~= "R" then return {} end
          return {
            ["Player-1-OWN"] = { name = "Frell Blast", guid = "Player-1-OWN" },
            ["Frell Old"] = { name = "Frell Old" },
          }
        end,
      }
    end)

    after_each(function()
      AltArmy.DataStore = savedDS
    end)

    it("are recognised by GUID or by full name", function()
      assert.is_true(GSD.IsOwnCharacter({ name = "Someone", guid = "Player-1-OWN" }, "R"))
      assert.is_true(GSD.IsOwnCharacter({ name = "Frell Blast" }, "R"))
      assert.is_true(GSD.IsOwnCharacter({ name = "Frell Old", guid = "Player-1-NEW" }, "R"))
      assert.is_false(GSD.IsOwnCharacter({ name = "Frell" }, "R"))
      assert.is_false(GSD.IsOwnCharacter({ name = "Frell Blast" }, "Elsewhere"))
    end)

    it("include the player's linked accounts' characters (each shares itself with the guild)", function()
      AltArmy.DataStore.ForEachLinkedCharacter = function(_, fn)
        fn("R", "Player-1-BOX", { name = "Stheno Frell", guid = "Player-1-BOX" }, "acct")
        fn("Elsewhere", "Player-1-FAR", { name = "Far Frell", guid = "Player-1-FAR" }, "acct")
      end
      assert.is_true(GSD.IsOwnCharacter({ name = "Anyone", guid = "Player-1-BOX" }, "R"))
      assert.is_true(GSD.IsOwnCharacter({ name = "Stheno Frell" }, "R"))
      assert.is_false(GSD.IsOwnCharacter({ name = "Far Frell" }, "R"))
    end)

    it("are never stored from a presence, a card or a link read", function()
      GSD.SaveReceived("Frell Ofelements", P.ParsePresence(presence("Frell Blast", {
        charEntry("Frell Blast"), charEntry("Guildie"),
      })), "G", "R")
      assert.is_nil(GSD.GetCharacter("Frell Blast", "R"))
      assert.is_truthy(GSD.GetCharacter("Guildie", "R"))
      GSD.SaveCharCard("Frell", P.ParseCharCard({
        v = 2, name = "Frell Blast", guid = "Player-1-OWN", ch = 1, profs = {},
      }), "G", "R")
      assert.is_nil(GSD.GetCharacter("Player-1-OWN", "R"))
      assert.is_nil(GSD.SaveLinkRead("R", {
        guid = "Player-1-OWN", name = "Frell Blast", profKey = "tailoring", skillLine = 197, ids = { 1 },
      }))
      assert.is_nil(GSD.GetCharacter("Player-1-OWN", "R"))
    end)

    it("stored by older clients are purged", function()
      local rt = AltArmyTBC_GuildData.chars
      rt.R = {
        ["Frell Blast"] = { name = "Frell Blast", source = "Frell Ofelements", Professions = {} },
        ["Player-1-G"] = { name = "Guildie", guid = "Player-1-G", Professions = {} },
      }
      assert.are.equal(1, GSD.PurgeOwnCharacters())
      assert.is_nil(rt.R["Frell Blast"])
      assert.is_truthy(rt.R["Player-1-G"])
    end)
  end)

  describe("link reads", function()
    local LINES = {
      { skillLine = 185, key = "cooking" },
      { skillLine = 129, key = "firstAid" },
      { skillLine = 171, key = "alchemy" },
      { skillLine = 197, key = "tailoring" },
    }
    local NIA = { guid = "Player-1-N", name = "Nia", level = 40 }

    local function read(overrides)
      local info = {
        guid = "Player-1-N", name = "Nia", guildName = "G", classFile = "MAGE", level = 40,
        profKey = "tailoring", profName = "Tailoring", skillLine = 197, rank = 142, maxRank = 225,
        ids = { 300, 100 },
      }
      for k, v in pairs(overrides or {}) do info[k] = v end
      return GSD.SaveLinkRead("R", info)
    end

    local function card(rv, extraProfs)
      local profs = { { key = "tailoring", rank = 140, count = 2, rv = rv } }
      for _, pr in ipairs(extraProfs or {}) do profs[#profs + 1] = pr end
      GSD.SaveCharCard("Nia", P.ParseCharCard({
        v = 2, from = "Player-1-N", name = "Nia", guid = "Player-1-N", ch = 1, profs = profs,
      }), "G", "R")
    end

    local function needs(member, nowTs)
      local out = {}
      for _, n in ipairs(GSD.GetSkillLinesNeedingLinkRead("R", member or NIA, nowTs or NOW, LINES)) do
        out[#out + 1] = n.key .. ":" .. n.reason
      end
      return out
    end

    it("drops reads whose recipe list was another profession's, and reads them again", function()
      package.path = package.path .. ";AltArmy_TBC/Data/Recipes/?.lua"
      require("RecipeInfo")
      local RI = AltArmy.RecipeInfo
      AltArmy.RecipeData = { recipes = {
        [3275] = { "firstAid", 1251, 1, 30, 45, "starter", false },
        [3276] = { "firstAid", 2581, 40, 50, 100, "trainer", false },
        [2538] = { "cooking", 2679, 1, 45, 85, "starter", false },
      } }
      RI.ClearCaches()
      -- A Cooking read taken before the window's list refreshed from the First Aid read before it.
      read({ profKey = "cooking", profName = "Cooking", skillLine = 185, rank = 37, maxRank = 75,
        ids = { 3275, 3276 } })
      read({ profKey = "firstAid", profName = "First Aid", skillLine = 129, rank = 84, maxRank = 150,
        ids = { 3275, 3276 } })
      read({ ids = { 100, 300 } }) -- Tailoring, nothing the data knows
      assert.are.equal(1, GSD.DropForeignLinkReads())
      local entry = GSD.GetCharacter("Nia", "R")
      assert.is_nil(entry.Professions.cooking)
      assert.is_not_nil(entry.Professions.firstAid.Recipes[3276])
      assert.is_not_nil(entry.Professions.tailoring.Recipes[300])
      assert.are.equal(0, GSD.DropForeignLinkReads())
      local again = false
      for _, n in ipairs(needs()) do if n == "cooking:probe" then again = true end end
      assert.is_true(again)
      AltArmy.RecipeData = nil
      RI.ClearCaches()
      assert.are.equal(0, GSD.DropForeignLinkReads())
    end)

    it("makes an entry for a character nobody shares, in the shape the Guild tab and search read", function()
      local entry = read()
      assert.are.equal(entry, GSD.GetCharacter("Player-1-N", "R"))
      assert.is_true(entry.linkOnly)
      assert.are.equal("Nia", entry.name)
      assert.are.equal("G", entry.guildName)
      assert.are.equal("MAGE", entry.classFile)
      assert.are.equal(40, entry.level)
      assert.are.equal("Nia", entry.source)
      assert.are.equal("Player-1-N", entry.sourceGuid)
      assert.are.equal(NOW, entry.receivedAt)
      assert.are.equal("Nia", entry.main)
      assert.is_true(entry.isMain)
      assert.is_false(entry.mainDeclared)
      assert.is_false(entry.needsProfessionCard)
      local prof = entry.Professions.tailoring
      assert.are.equal("Tailoring", prof.name)
      assert.are.same({ primaryRecipeID = 100 }, prof.Recipes[100])
      assert.are.same({ primaryRecipeID = 300 }, prof.Recipes[300])
      assert.are.equal(2, prof.count)
      assert.are.equal(142, prof.rank)
      assert.are.equal(225, prof.maxRank)
      assert.are.equal(197, prof.skillLine)
      assert.are.equal(NOW, prof.linkReadAt)
      assert.are.equal(P.HashRecipeIDs({ 100, 300 }), prof.linkRv)
      assert.are.equal(prof.linkRv, prof.rv)
      assert.are.equal(prof.rv, prof.recipesRv)
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Player-1-N", "R"))
      assert.are.equal(1, #GSD.GetGuildMembers("G"))
    end)

    it("fills a shared character's profession and asks for nothing more until their card changes", function()
      card(77)
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Player-1-N", "R"))
      local entry = read()
      assert.is_nil(entry.linkOnly)
      local prof = entry.Professions.tailoring
      assert.are.equal(77, prof.rv)
      assert.are.equal(77, prof.recipesRv)
      assert.are.equal(142, prof.rank)
      assert.is_truthy(prof.Recipes[100])
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Player-1-N", "R"))
      assert.are.same({}, needs())

      card(77)
      prof = GSD.GetCharacter("Player-1-N", "R").Professions.tailoring
      assert.is_truthy(prof.Recipes[100])
      assert.are.equal(77, prof.recipesRv)

      card(P.HashRecipeIDs({ 100, 300 }))
      prof = GSD.GetCharacter("Player-1-N", "R").Professions.tailoring
      assert.are.equal(prof.rv, prof.recipesRv)
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Player-1-N", "R"))

      card(78)
      prof = GSD.GetCharacter("Player-1-N", "R").Professions.tailoring
      assert.is_truthy(prof.Recipes[100])
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Player-1-N", "R"))
      assert.are.same({}, needs())
    end)

    it("leaves a profession alone for a pulled list that follows a read too closely, and stores the rest", function()
      read()
      local payload = {
        name = "Nia", guid = "Player-1-N",
        profs = { { key = "tailoring", ids = { 1 } }, { key = "cooking", ids = { 2 } } },
      }
      GSD.SaveRecipes("R", payload)
      local profs = GSD.GetCharacter("Player-1-N", "R").Professions
      assert.is_truthy(profs.tailoring.Recipes[100])
      assert.is_nil(profs.tailoring.Recipes[1])
      assert.is_truthy(profs.cooking.Recipes[2])

      profs.tailoring.linkReadAt = NOW - GSD.LINK_READ_WINS_SEC
      GSD.SaveRecipes("R", payload)
      profs = GSD.GetCharacter("Player-1-N", "R").Professions
      assert.is_truthy(profs.tailoring.Recipes[1])
      assert.is_nil(profs.tailoring.Recipes[100])
      assert.is_nil(profs.tailoring.linkReadAt)
    end)

    it("keeps link-read recipes through a presence that asks for a card, and adopts the entry", function()
      read()
      GSD.SaveReceived("Nia", P.ParsePresence({
        v = 2, from = "Player-1-N",
        chars = { { name = "Nia", guid = "Player-1-N", ch = 5, classFile = "MAGE", level = 40 } },
      }), "G", "R")
      local entry = GSD.GetCharacter("Player-1-N", "R")
      assert.is_nil(entry.linkOnly)
      assert.is_true(entry.needsProfessionCard)
      assert.is_truthy(entry.Professions.tailoring.Recipes[100])
      assert.are.same({}, needs())
    end)

    it("shows in the Guild tab for someone who never shares a presence, as their own group", function()
      require("GuildTabData")
      local GTD = AltArmy.GuildTabData
      read()
      -- A client with sharing off announces itself with an empty presence: it groups nothing.
      GSD.SaveReceived("Nia", P.ParsePresence({ v = 2, from = "Player-1-N", chars = {} }), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      assert.are.equal(1, #members)
      local groups = GTD.GroupMembersByMain(members)
      assert.are.equal(1, #groups)
      assert.are.equal("Nia", groups[1].main)
      assert.are.equal("Nia", groups[1].preferredName)
      assert.are.equal("MAGE", groups[1].classFile)
      local m = groups[1].members[1]
      assert.is_false(GTD.IsManualMember(m))
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
      local recipes = GTD.GetProfessionRecipes(m, "tailoring")
      assert.are.equal(2, #recipes)
      assert.are.equal(100, recipes[1].recipeID)
    end)

    describe("as an automatic group", function()
      local GTD

      local function groupsByMain()
        local out = {}
        for _, g in ipairs(GTD.GroupMembersByMain(GSD.GetGuildMembersForDisplay("G", "R"))) do
          local names = {}
          for _, m in ipairs(g.members) do names[#names + 1] = m.name end
          table.sort(names)
          out[g.main] = names
        end
        return out
      end

      local function groupOf(main)
        for _, g in ipairs(GTD.GroupMembersByMain(GSD.GetGuildMembersForDisplay("G", "R"))) do
          if g.main == main then return g end
        end
      end

      before_each(function()
        require("GuildTabData")
        GTD = AltArmy.GuildTabData
        read()
      end)

      it("says why the character is there, and doesn't stop adding them to another group", function()
        local members = GSD.GetGuildMembersForDisplay("G", "R")
        assert.is_true(members[1].autoGroup)
        assert.is_nil(GSD.GetCharacter("Player-1-N", "R").autoGroup)
        assert.is_nil(GTD.BuildOccupiedGroupReasons(members).nia)
        local proposal = GTD.BuildGroupEditProposal(groupOf("Nia"), GMG)
        assert.are.equal("auto", proposal.mainReasonKind)
        assert.are.equal("Group created automatically", GTD.NotesWizardInclusionReasonLabel("auto"))
      end)

      it("gives way to the group the character is added to", function()
        GMG.SetMapping("Mainchar", "R", "Mainchar", { guild = "G", origin = "user" })
        GMG.AssignToGroup("Nia", "R", "Mainchar", { guild = "G", origin = "user" })
        local groups = groupsByMain()
        assert.is_nil(groups.Nia)
        assert.are.same({ "Mainchar", "Nia" }, groups.Mainchar)
        local nia
        for _, m in ipairs(groupOf("Mainchar").members) do
          if m.name == "Nia" then nia = m end
        end
        assert.is_nil(nia.autoGroup)
        assert.are.equal("Mainchar", GTD.BuildOccupiedGroupReasons(GSD.GetGuildMembersForDisplay("G", "R")).nia.groupName)
        local proposal = GTD.BuildGroupEditProposal(groupOf("Mainchar"), GMG)
        local entry
        for _, m in ipairs(proposal.members) do
          if m.name == "Nia" then entry = m end
        end
        assert.are.equal("manual", entry.reasonKind)
        assert.is_true(entry.removable)
      end)

      it("becomes a real group when made the main of one", function()
        GMG.AssignToGroup("Other", "R", "Nia", { guild = "G", origin = "user" })
        local members = GSD.GetGuildMembersForDisplay("G", "R")
        for _, m in ipairs(members) do assert.is_nil(m.autoGroup, m.name) end
        assert.are.same({ "Nia", "Other" }, groupsByMain().Nia)
        assert.are_not.equal("auto", GTD.BuildGroupEditProposal(groupOf("Nia"), GMG).mainReasonKind)
      end)
    end)

    it("isn't withdrawn by an empty presence from that character", function()
      read()
      GSD.SaveReceived("Nia", P.ParsePresence({ v = 2, from = "Player-1-N", chars = {} }), "G", "R")
      assert.is_truthy(GSD.GetCharacter("Player-1-N", "R"))
    end)

    it("survives PurgeStale while fresh and becomes a manual mapping when old", function()
      read()
      GSD.PurgeStale(10, NOW + 5)
      assert.is_truthy(GSD.GetCharacter("Player-1-N", "R"))
      GSD.PurgeStale(10, NOW + 100)
      assert.is_nil(GSD.GetCharacter("Player-1-N", "R"))
      assert.is_truthy(GMG.GetMapping("Nia", "R"))
    end)

    it("remembers unanswered links with a growing backoff, and forgets one that answered", function()
      GSD.MarkLinkTried("R", "Player-1-N", 171, NOW)
      assert.are.same({ triedAt = NOW, misses = 1 }, GSD.GetLinkProbe("R", "Player-1-N", 171))
      GSD.MarkLinkTried("R", "Player-1-N", 171, NOW + 1)
      assert.are.equal(2, GSD.GetLinkProbe("R", "Player-1-N", 171).misses)
      assert.are.equal(1 * 86400, GSD.LinkProbeBackoffSec(1))
      assert.are.equal(3 * 86400, GSD.LinkProbeBackoffSec(2))
      assert.are.equal(30 * 86400, GSD.LinkProbeBackoffSec(9))
      read({ profKey = "alchemy", profName = "Alchemy", skillLine = 171 })
      assert.is_nil(GSD.GetLinkProbe("R", "Player-1-N", 171))

      GSD.MarkLinkTried("R", "Player-1-N", 185, NOW - 100)
      GSD.PurgeStale(10, NOW)
      assert.is_nil(GSD.GetLinkProbe("R", "Player-1-N", 185))
    end)

    it("remembers a profession a member hasn't got, drops a stale copy, and asks again later", function()
      read()
      assert.is_true(GSD.MarkLinkAbsent("R", "Player-1-N", 197, "tailoring", NOW, 40))
      assert.is_nil(GSD.GetCharacter("Player-1-N", "R").Professions.tailoring)
      assert.is_true(GSD.GetLinkProbe("R", "Player-1-N", 197).absent)
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe" }, needs())
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe", "tailoring:probe" },
        needs(NIA, NOW + GSD.LINK_REREAD_SEC))
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe", "tailoring:probe" },
        needs({ guid = "Player-1-N", name = "Nia", level = 41 }))
      assert.is_false(GSD.MarkLinkAbsent("R", "Player-1-N", 185, "cooking", NOW, 40))
    end)

    it("purges professions stored from an empty answer by older builds", function()
      read()
      read({ profKey = "alchemy", profName = "Alchemy", skillLine = 171, rank = 0, maxRank = 0, ids = {} })
      assert.are.equal(1, GSD.PurgeEmptyLinkReads())
      local profs = GSD.GetCharacter("Player-1-N", "R").Professions
      assert.is_nil(profs.alchemy)
      assert.is_truthy(profs.tailoring)
      assert.is_true(GSD.GetLinkProbe("R", "Player-1-N", 171).absent)
    end)

    it("probes every line of an unknown member, in the order given", function()
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe", "tailoring:probe" }, needs())
    end)

    it("skips lines inside their backoff, and reads a known line again when stale or the member levelled", function()
      read()
      GSD.MarkLinkTried("R", "Player-1-N", 171, NOW)
      assert.are.same({ "cooking:probe", "firstAid:probe" }, needs())
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe" }, needs(NIA, NOW + 86400))
      assert.are.same({ "cooking:probe", "firstAid:probe", "tailoring:level-changed" },
        needs({ guid = "Player-1-N", name = "Nia", level = 45 }))
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe", "tailoring:stale" },
        needs(NIA, NOW + GSD.LINK_REREAD_SEC))
    end)

    it("reads nothing by link for a member who shares through Alt Army, whatever their card says", function()
      card(77, { { key = "cooking", rank = 50, count = 1, rv = 5 } })
      assert.are.same({}, needs())
      GSD.SaveReceived("Nia", P.ParsePresence({ v = 2, from = "Player-1-N", chars = {} }), "G", "R")
      assert.are.same({ "cooking:probe", "firstAid:probe", "alchemy:probe", "tailoring:probe" }, needs())
    end)

    it("groups a link-read character under a manual mapping", function()
      read()
      assert.are.equal("Nia", GSD.GetMainOf("Nia", "R"))
      GMG.SetMapping("Nia", "R", "Mainchar", { guild = "G", origin = "note" })
      assert.are.equal("Mainchar", GSD.GetMainOf("Nia", "R"))
      local byName = {}
      for _, m in ipairs(GSD.GetGuildMembersForDisplay("G", "R")) do byName[m.name] = m end
      assert.are.equal("Mainchar", byName.Nia.main)
      assert.is_false(byName.Nia.isMain)
      assert.is_truthy(byName.Nia.Professions.tailoring.Recipes[100])
      assert.are.equal("manual", byName.Mainchar.source)
      -- The stored entry itself is left alone.
      assert.are.equal("Nia", GSD.GetCharacter("Player-1-N", "R").main)

      GSD.GetCharacter("Player-1-N", "R").linkOnly = nil
      read({ guid = "Player-1-M", name = "Mia" })
      assert.are.equal("Mia", GSD.GetCharacter("Player-1-M", "R").main)
      GMG.SetMapping("Mia", "R", "Mainchar", { guild = "G", origin = "note" })
      assert.are.equal("Mainchar", GSD.SaveLinkRead("R", {
        guid = "Player-1-M", name = "Mia", guildName = "G", profKey = "cooking", skillLine = 185, ids = {},
      }).main)
    end)
  end)

  describe("first-name copies and live levels", function()
    -- WoW Forever: a pre-v3 addon saved "Not Kaiborn" as "Not" (no GUID); the sender's addon still shares it.
    local function char(name, guid, classFile, level)
      return { name = name, guid = guid, classFile = classFile, faction = "Horde", level = level, profs = {} }
    end
    local function notKai(chars)
      return { v = 1, from = "Player-1-K", main = "Not Kai", chars = chars }
    end
    local function shownByName(rosterInfo)
      local byName = {}
      for _, m in ipairs(GSD.GetGuildMembersForDisplay("G", "R", false, rosterInfo)) do byName[m.name] = m end
      return byName
    end

    it("never stores a GUID-less first name of a same-class character of the same player", function()
      GSD.SaveReceived("Not Kai", notKai({
        char("Not Kai", "Player-1-K", "PALADIN", 22),
        char("Not Kaiborn", "Player-1-B", "SHAMAN", 14),
        char("Not", nil, "SHAMAN", 9),
      }), "G", "R")
      assert.is_nil(GSD.GetCharacter("Not", "R"))
      assert.truthy(GSD.GetCharacter("Not Kaiborn", "R"))
    end)

    it("keeps a GUID-less one-word character nothing else explains", function()
      GSD.SaveReceived("Saxa Lamoose", { v = 1, from = "Player-1-S", main = "Saxa Lamoose", chars = {
        char("Saxa Lamoose", "Player-1-S", "HUNTER", 20),
        char("Nason", nil, "MAGE", 6),
        -- Another class, or higher than every sibling: not a copy of them.
        char("Saxa", nil, "HUNTER", 21),
      } }, "G", "R")
      assert.truthy(GSD.GetCharacter("Nason", "R"))
      assert.truthy(GSD.GetCharacter("Saxa", "R"))
    end)

    it("drops a copy stored before with the sender's next presence", function()
      local presence = notKai({
        char("Not Kaiborn", "Player-1-B", "SHAMAN", 14),
        char("Not", nil, "SHAMAN", 9),
      })
      local rt = GSD._Ensure().chars
      rt.R = { Not = { name = "Not", realm = "R", classFile = "SHAMAN", level = 9, guildName = "G",
        source = "Not Kai", sourceGuid = "Player-1-K", main = "Not Kai", Professions = {} } }
      GSD.SaveReceived("Not Kai", presence, "G", "R")
      assert.is_nil(GSD.GetCharacter("Not", "R"))
      assert.is_true(GSD.PresenceMatchesStored("Not Kai", presence, "R"))
    end)

    it("does not show a copy stored before", function()
      local rt = GSD._Ensure().chars
      rt.R = {
        ["Player-1-B"] = { name = "Not Kaiborn", guid = "Player-1-B", realm = "R", classFile = "SHAMAN",
          level = 14, guildName = "G", source = "Not Kai", sourceGuid = "Player-1-K", main = "Not Kai",
          Professions = {} },
        Not = { name = "Not", realm = "R", classFile = "SHAMAN", level = 9, guildName = "G",
          source = "Not Kai", sourceGuid = "Player-1-K", main = "Not Kai", Professions = {} },
      }
      local byName = shownByName()
      assert.truthy(byName["Not Kaiborn"])
      assert.is_nil(byName.Not)
    end)

    it("shows a received character at its live roster level, without changing what is stored", function()
      GSD.SaveReceived("Deadicated Suryal", { v = 1, from = "Player-1-D", main = "Deadicated Suryal", chars = {
        char("Cropdust Deathwind", "Player-1-C", "ROGUE", 20),
      } }, "G", "R")
      local byName = shownByName({ ["cropdust deathwind"] = { classFile = "ROGUE", level = 23 } })
      assert.are.equal(23, byName["Cropdust Deathwind"].level)
      assert.are.equal(20, GSD.GetCharacter("Cropdust Deathwind", "R").level)
      -- Not in the roster (left the guild, or roster not loaded): the shared level.
      assert.are.equal(20, shownByName({})["Cropdust Deathwind"].level)
    end)
  end)
end)
