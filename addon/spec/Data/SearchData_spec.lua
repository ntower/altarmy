--[[
  Unit tests for SearchData.lua (location, match score, search/aggregation).
  Run from project root: npm test
]]

describe("SearchData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      local f = { scripts = {} }
      function f:SetScript(event, fn) self.scripts[event] = fn end
      function f:GetScript(event) return self.scripts[event] end
      function f:RegisterEvent() end
      function f:UnregisterEvent() end
      function f:Hide() end
      function f:Show() end
      return f
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreProfessions")
    require("RecipeInfo")
    require("SearchSettings")
    require("SearchIndex")
    require("SearchQuery")
    require("SearchPresent")
    require("SearchTasks")
    require("SearchData")
    SD = AltArmy.SearchData
  end)

  before_each(function()
    _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = nil
    if AltArmy.DataStore then
      AltArmy.DataStore.accountData = _G.AltArmyTBC_Data
    end
    if SD and SD.ClearSearchCaches then
      SD.ClearSearchCaches()
    elseif SD and SD.ClearSearchableTextCache then
      SD.ClearSearchableTextCache()
    end
  end)

  describe("GetAllContainerSlots (mail)", function()
    it("includes mail attachment items as location=mail", function()
      local DS = AltArmy.DataStore
      assert.truthy(DS)
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ScanCurrentCharacterBags = DS.ScanCurrentCharacterBags,
      }

      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return {
          Alice = {
            name = "Alice",
            Mails = { { itemID = 111, count = 2, link = "item:111" } },
            MailCache = { { itemID = 222, count = 3, link = "item:222" } },
          },
        }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        -- One bag item so we can verify mail + bag both exist
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end
      DS.ScanCurrentCharacterBags = function() end

      local list = SD.GetAllContainerSlots()

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.ScanCurrentCharacterBags = old.ScanCurrentCharacterBags

      local seenBag, seenMail111, seenMail222 = false, false, false
      for _, e in ipairs(list) do
        if e.itemID == 999 and e.location == "bag" then seenBag = true end
        if e.itemID == 111 and e.location == "mail" and e.count == 2 then seenMail111 = true end
        if e.itemID == 222 and e.location == "mail" and e.count == 3 then seenMail222 = true end
      end
      assert.is_true(seenBag)
      assert.is_true(seenMail111)
      assert.is_true(seenMail222)
    end)

    it("includes equipped items as location=equipped", function()
      local DS = AltArmy.DataStore
      assert.truthy(DS)
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }

      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, _cb) end
      DS.IterateInventory = function(_self, _char, cb)
        cb(1, 333)
        cb(2, "item:444:0:0:0:0:0:0:0:0:0:0:0:0")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end

      local list = SD.GetAllContainerSlots()

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.IterateInventory = old.IterateInventory
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass

      local seenNumeric, seenEnchanted = false, false
      for _, e in ipairs(list) do
        if e.itemID == 333 and e.location == "equipped" and e.count == 1 and e.slot == 1 then
          seenNumeric = true
        end
        if e.itemID == 444 and e.location == "equipped" and e.count == 1 and e.slot == 2
            and e.itemLink == "item:444:0:0:0:0:0:0:0:0:0:0:0:0" then
          seenEnchanted = true
        end
      end
      assert.is_true(seenNumeric)
      assert.is_true(seenEnchanted)
    end)

    it("includes inventory bags as equipped and bank bags as equipped-bank", function()
      local DS = AltArmy.DataStore
      assert.truthy(DS)
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateEquippedBags = DS.IterateEquippedBags,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }

      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, _cb) end
      DS.IterateInventory = function(_self, _char, _cb) end
      DS.IterateEquippedBags = function(_self, _char, cb)
        cb(1, 21841, "|Hitem:21841:0|h[Netherweave Bag]|h")
        cb(5, 14156, "|Hitem:14156:0|h[Bottomless Bag]|h")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end

      local list = SD.GetAllContainerSlots()

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.IterateEquippedBags = old.IterateEquippedBags
      DS.IterateInventory = old.IterateInventory
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass

      local seenInv, seenBank = false, false
      for _, e in ipairs(list) do
        if e.itemID == 21841 and e.location == "equipped" and e.count == 1 and e.bagID == 1 then
          seenInv = true
        end
        if e.itemID == 14156 and e.location == "equipped-bank" and e.count == 1 and e.bagID == 5 then
          seenBank = true
        end
      end
      assert.is_true(seenInv)
      assert.is_true(seenBank)
    end)
  end)

  describe("search caches", function()
    it("caches container slot list until invalidated", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }

      local iterateCalls = 0
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        iterateCalls = iterateCalls + 1
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end

      local first = SD.GetAllContainerSlots()
      local second = SD.GetAllContainerSlots()
      assert.are.equal(1, iterateCalls)
      assert.are.equal(#first, #second)

      SD.InvalidateContainerSlotsCache()
      local third = SD.GetAllContainerSlots()
      assert.are.equal(2, iterateCalls)
      assert.are.equal(#first, #third)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
    end)

    it("does not scan current character bags while building container cache", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ScanCurrentCharacterBags = DS.ScanCurrentCharacterBags,
      }

      local scanned = false
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end
      DS.ScanCurrentCharacterBags = function()
        scanned = true
      end

      SD.InvalidateContainerSlotsCache()
      SD.GetAllContainerSlots()
      assert.is_false(scanned)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.ScanCurrentCharacterBags = old.ScanCurrentCharacterBags
    end)

    it("caches recipe list until invalidated", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        GetProfessions = DS.GetProfessions,
      }

      local getProfessionsCalls = 0
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, Recipes = { [12345] = 1 } },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARLOCK" end
      DS.GetProfessions = function(_, char)
        getProfessionsCalls = getProfessionsCalls + 1
        return char and char.Professions or {}
      end

      local first = SD.GetAllRecipes()
      local second = SD.GetAllRecipes()
      assert.are.equal(1, getProfessionsCalls)
      assert.are.equal(#first, #second)

      SD.InvalidateRecipesCache()
      local third = SD.GetAllRecipes()
      assert.are.equal(2, getProfessionsCalls)
      assert.are.equal(#first, #third)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.GetProfessions = old.GetProfessions
    end)

    it("does not re-fetch recipe names during sort comparator", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemInfo = _G.GetItemInfo

      SD.GetAllRecipes = function()
        return {
          { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 280, recipeID = 111 },
          { characterName = "C", realm = "R", professionName = "Alchemy", skillRank = 260, recipeID = 222 },
        }
      end

      local spellCalls = 0
      _G.GetSpellInfo = function(id)
        spellCalls = spellCalls + 1
        if id == 111 then return "Minor Potion" end
        if id == 222 then return "Major Potion" end
        return nil
      end
      _G.GetItemInfo = function() return nil end

      local results = SD.SearchRecipes("potion")
      assert.are.equal(3, #results)
      assert.are.equal(2, spellCalls)

      local resultsAgain = SD.SearchRecipes("potion")
      assert.are.equal(3, #resultsAgain)
      assert.are.equal(2, spellCalls)

      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemInfo = oldGetItemInfo
    end)
  end)

  describe("_LocationSortKey", function()
    it("orders bag before keyring before bank before equipped before equipped-bank before mail", function()
      assert.is_true(SD._LocationSortKey("bag") < SD._LocationSortKey("keyring"))
      assert.is_true(SD._LocationSortKey("keyring") < SD._LocationSortKey("bank"))
      assert.is_true(SD._LocationSortKey("bank") < SD._LocationSortKey("equipped"))
      assert.is_true(SD._LocationSortKey("equipped") < SD._LocationSortKey("equipped-bank"))
      assert.is_true(SD._LocationSortKey("equipped-bank") < SD._LocationSortKey("mail"))
    end)
  end)

  describe("_LocationFromBagID", function()
    it("returns bag for 0-4", function()
      assert.are.equal(SD._LocationFromBagID(0), "bag")
      assert.are.equal(SD._LocationFromBagID(1), "bag")
      assert.are.equal(SD._LocationFromBagID(4), "bag")
    end)
    it("returns bank for -1", function()
      assert.are.equal(SD._LocationFromBagID(-1), "bank")
    end)
    it("returns bank for 5-11", function()
      assert.are.equal(SD._LocationFromBagID(5), "bank")
      assert.are.equal(SD._LocationFromBagID(11), "bank")
    end)
    it("returns keyring for -2", function()
      assert.are.equal(SD._LocationFromBagID(-2), "keyring")
    end)
    it("follows DataStore's bag roles when it has them (WoW Forever: keyring -1, reagent bag 5, tabs 6+)", function()
      local DS = AltArmy.DataStore
      local saved = DS.GetBagRole
      DS.GetBagRole = function(_, bagID)
        local roles = { [0] = "backpack", [1] = "bag", [5] = "reagentbag", [-1] = "keyring", [6] = "bankbag" }
        return roles[bagID]
      end
      assert.are.equal("keyring", SD._LocationFromBagID(-1))
      assert.are.equal("bag", SD._LocationFromBagID(5))
      assert.are.equal("bank", SD._LocationFromBagID(6))
      assert.are.equal("bag", SD._LocationFromBagID(-2))
      DS.GetBagRole = saved
    end)
  end)

  describe("_GetNameMatchScore", function()
    it("returns 0 for nil or empty", function()
      assert.are.equal(SD._GetNameMatchScore(nil, "x"), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", ""), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", nil), 0)
    end)
    it("returns 3 for exact match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo bar"), 3)
    end)
    it("returns 2 for prefix match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo"), 2)
    end)
    it("returns 1 for contains", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "bar"), 1)
    end)
    it("returns 0 when no match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "baz"), 0)
    end)
  end)

  describe("_AggregateAndSort", function()
    it("sums counts for the same item/character/location", function()
      local out = SD._AggregateAndSort({
        { itemID = 1, itemName = "Cloth", characterName = "A", realm = "R", location = "bag", count = 2 },
        { itemID = 1, itemName = "Cloth", characterName = "A", realm = "R", location = "bag", count = 3 },
      }, "cloth")
      assert.are.equal(1, #out)
      assert.are.equal(5, out[1].count)
      assert.are.equal("bag", out[1].location)
    end)

    it("orders by match score then name, keeping item rows contiguous", function()
      local out = SD._AggregateAndSort({
        { itemID = 2, itemName = "Super Potion", characterName = "Z", realm = "R", location = "bag", count = 1 },
        { itemID = 1, itemName = "Potion", characterName = "B", realm = "R", location = "bank", count = 1 },
        { itemID = 1, itemName = "Potion", characterName = "A", realm = "R", location = "bag", count = 5 },
        { itemID = 3, itemName = "Alpha Bolt", characterName = "C", realm = "R", location = "bag", count = 1 },
      }, "potion")
      -- Exact "potion" (score 3) before contains "super potion" (1); alpha bolt also contains? "potion" in alpha bolt? no.
      -- Alpha Bolt score 0, Potion exact 3, Super Potion contains 1.
      assert.are.equal(1, out[1].itemID)
      assert.are.equal("A", out[1].characterName)
      assert.are.equal("bag", out[1].location)
      assert.are.equal(1, out[2].itemID)
      assert.are.equal("B", out[2].characterName)
      assert.are.equal(2, out[3].itemID)
      assert.are.equal(3, out[4].itemID)
    end)

    it("within an item, higher charTotal then bag before bank", function()
      local out = SD._AggregateAndSort({
        { itemID = 1, itemName = "Runecloth", characterName = "A", realm = "R", location = "bank", count = 10 },
        { itemID = 1, itemName = "Runecloth", characterName = "A", realm = "R", location = "bag", count = 1 },
        { itemID = 1, itemName = "Runecloth", characterName = "B", realm = "R", location = "bag", count = 2 },
      }, "rune")
      -- A charTotal=11, B charTotal=2; A's bag before A's bank
      assert.are.equal("A", out[1].characterName)
      assert.are.equal("bag", out[1].location)
      assert.are.equal("A", out[2].characterName)
      assert.are.equal("bank", out[2].location)
      assert.are.equal("B", out[3].characterName)
    end)

    it("does not leave temporary sort fields on rows", function()
      local out = SD._AggregateAndSort({
        { itemID = 1, itemName = "Foo", characterName = "A", realm = "R", location = "bag", count = 1 },
      }, "foo")
      assert.is_nil(out[1].charTotal)
      assert.is_nil(out[1].matchScore)
      assert.is_nil(out[1].nameLower)
    end)
  end)


  describe("Search", function()
    it("returns empty for nil query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search(nil), {})
      SD.GetAllContainerSlots = old
    end)
    it("returns empty for whitespace-only query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search("   "), {})
      SD.GetAllContainerSlots = old
    end)
    it("matches by itemID when query is number", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
        { characterName = "B", realm = "R", itemID = 99999, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search(12345)
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
    it("matches by itemID when query is string digits", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search("12345")
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
    it("returns non-nil second value (tooltipOnly list)", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      local _, tooltipOnly = SD.Search("anything")
      SD.GetAllContainerSlots = old
      assert.is_not_nil(tooltipOnly)
    end)
    it("puts tooltip-only matches into second result, not first", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 11111, itemLink = nil, count = 1, location = "bag" },
      }
      local oldSlots = SD.GetAllContainerSlots
      local oldGetSearchable = SD._GetSearchableTextForItem
      SD.GetAllContainerSlots = function() return list end
      SD._GetSearchableTextForItem = function(itemID, _)
        if itemID == 11111 then return "mote of fire primal fire" end
        return nil
      end
      local main, tooltipOnly = SD.Search("primal")
      SD.GetAllContainerSlots = oldSlots
      SD._GetSearchableTextForItem = oldGetSearchable
      assert.are.equal(#main, 0)
      assert.are.equal(#tooltipOnly, 1)
      assert.are.equal(tooltipOnly[1].itemID, 11111)
    end)
    it("keeps name-matched entries in main result only", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 22222, itemLink = nil, count = 1, location = "bag" },
      }
      local oldSlots = SD.GetAllContainerSlots
      local oldGetItemInfo = _G.GetItemInfo
      SD.GetAllContainerSlots = function() return list end
      _G.GetItemInfo = function(id)
        if id == 22222 then return "Primal Fire" end
        return nil
      end
      local main, tooltipOnly = SD.Search("primal")
      SD.GetAllContainerSlots = oldSlots
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(#main, 1)
      assert.are.equal(#tooltipOnly, 0)
      assert.are.equal(main[1].itemID, 22222)
    end)
  end)

  describe("ClearSearchableTextCache", function()
    it("exists and does not error", function()
      assert.is_function(SD.ClearSearchableTextCache)
      assert.has_no.errors(function()
        SD.ClearSearchableTextCache()
      end)
    end)
  end)

  describe("SearchGroupedByCharacter", function()
    it("aggregates count by character", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { characterName = "A", realm = "R", itemID = 100, count = 2 },
          { characterName = "A", realm = "R", itemID = 100, count = 3 },
        }, {}
      end
      local results = SD.SearchGroupedByCharacter("x")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
  end)

  describe("SearchWithLocationGroups", function()
    it("returns empty tables for nil query", function()
      local main, tooltipOnly = SD.SearchWithLocationGroups(nil)
      assert.are.same(main, {})
      assert.are.same(tooltipOnly, {})
    end)
    it("returns two non-nil values", function()
      local old = SD.Search
      SD.Search = function() return {}, {} end
      local main, tooltipOnly = SD.SearchWithLocationGroups("foo")
      SD.Search = old
      assert.is_not_nil(main)
      assert.is_not_nil(tooltipOnly)
    end)
    it("aggregates by itemID, character, realm, location", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 2, classFile = "" },
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 3, classFile = "" },
        }, {}
      end
      local results, _ = SD.SearchWithLocationGroups("foo")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
    it("routes tooltip-only entries into second return", function()
      local old = SD.Search
      SD.Search = function()
        return {}, {
          { itemID = 300, itemLink = "link", itemName = "Mote of Fire", characterName = "A", realm = "R",
            location = "bag", count = 1, classFile = "" },
        }
      end
      local _, tooltipOnly = SD.SearchWithLocationGroups("primal")
      SD.Search = old
      assert.are.equal(#tooltipOnly, 1)
      assert.are.equal(tooltipOnly[1].itemID, 300)
    end)
  end)

  describe("GetAllRecipes", function()
    it("returns empty when DS or GetProfessions missing", function()
      local DS = AltArmy.DataStore
      local oldGetProfessions = DS and DS.GetProfessions
      if DS then DS.GetProfessions = nil end
      local oldGetRealms = DS and DS.GetRealms
      if DS then DS.GetRealms = function() return {} end end
      assert.are.same(SD.GetAllRecipes(), {})
      if DS and oldGetProfessions then DS.GetProfessions = oldGetProfessions end
      if DS and oldGetRealms then DS.GetRealms = oldGetRealms end
    end)
    it("returns flat list of recipe entries per character profession", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, maxRank = 375, Recipes = { [12345] = 1, [67890] = 2 } },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "WARLOCK"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      local results = SD.GetAllRecipes()
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      assert.are.equal(#results, 2)
      table.sort(results, function(a, b) return (a.recipeID or 0) < (b.recipeID or 0) end)
      assert.are.equal(results[1].characterName, "Char1")
      assert.are.equal(results[1].realm, "Realm1")
      assert.are.equal(results[1].professionName, "Alchemy")
      assert.are.equal(results[1].skillRank, 300)
      assert.are.equal(results[1].recipeID, 12345)
      assert.are.equal(results[2].recipeID, 67890)
    end)
    it("excludes alias recipe ids (e.g. crafted item use spell)", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemSpell = _G.GetItemSpell
      local row = { color = 1, resultItemID = 9187, primaryRecipeID = 11449 }
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = {
                rank = 300,
                Recipes = {
                  [11449] = row,
                  [11334] = row, -- Agility buff spell alias
                },
              },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      AltArmy.DataStore:MigrateRecipePrimaryIds()
      local results = SD.GetAllRecipes()
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 11449)
    end)
  end)

  describe("GetAllGuildRecipes", function()
    local DS, restore

    before_each(function()
      DS = AltArmy.DataStore
      require("Debug")
      require("GuildShareProtocol")
      require("GuildShareData")
      restore = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        GetProfessions = DS.GetProfessions,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ForEachCharacter = DS.ForEachCharacter,
        GetCurrentPlayerRealm = DS.GetCurrentPlayerRealm,
      }
      -- No local profession data; guild-toggle eligibility still needs a guilded char on realm.
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function(_, realm)
        if realm == "R" then
          return { Local = { guildName = "G" } }
        end
        return {}
      end
      DS.GetProfessions = function() return {} end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.GetCurrentPlayerRealm = function() return "R" end
      _G.AltArmyTBC_GuildData = {
        chars = {
          R = {
            Bob = {
              name = "Bob", realm = "R", classFile = "MAGE", guildName = "G", displayName = "Bobby",
              Professions = {
                tailoring = {
                  key = "tailoring", name = "Tailoring", rank = 375,
                  Recipes = { [100] = { primaryRecipeID = 100 }, [200] = { primaryRecipeID = 200 } },
                },
              },
            },
          },
        },
      }
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(true)
      package.loaded["GuildShareSettings"] = nil
      package.loaded["GuildTabData"] = nil
      require("GuildShareSettings")
      require("GuildTabData")
      AltArmy.GuildShareSettings.SetSharingEnabled(true)
      AltArmy.DataStore.ForEachCharacter = function(_, fn)
        fn("R", "Local", { guildName = "G" })
      end
      SD.NotifyRecipesChanged()
    end)

    after_each(function()
      for k, v in pairs(restore) do
        if v ~= nil then DS[k] = v end
      end
      if AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.SetSharingEnabled then
        AltArmy.GuildShareSettings.SetSharingEnabled(false)
      end
      _G.AltArmyTBC_GuildData = nil
      SD.NotifyRecipesChanged()
    end)

    it("keeps GetAllRecipes local-only (no guild rows)", function()
      assert.are.equal(0, #SD.GetAllRecipes())
      local guild = SD.GetAllGuildRecipes()
      assert.are.equal(2, #guild)
      for _, r in ipairs(guild) do
        assert.is_true(r.isGuild)
        assert.are.equal("Bob", r.characterName)
        assert.are.equal("tailoring", r.professionKey)
      end
    end)

    it("excludes guild recipes when the feature flag is off", function()
      local saved = AltArmy.Debug.IsGuildShareEnabled
      AltArmy.Debug.IsGuildShareEnabled = function() return false end
      SD.NotifyRecipesChanged()
      assert.are.equal(0, #SD.GetAllGuildRecipes())
      AltArmy.Debug.IsGuildShareEnabled = saved
    end)

    it("excludes guild recipes when the include-guildmates toggle is off", function()
      assert.are.equal(2, #SD.GetAllGuildRecipes())
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(false)
      assert.are.equal(0, #SD.GetAllGuildRecipes())
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(true)
      assert.are.equal(2, #SD.GetAllGuildRecipes())
    end)

    it("leaves out the player's own characters stored as guildmates", function()
      _G.AltArmyTBC_GuildData.chars.R.Local = {
        name = "Local", realm = "R", classFile = "MAGE", guildName = "G",
        Professions = { tailoring = { key = "tailoring", name = "Tailoring", rank = 57,
          Recipes = { [300] = { primaryRecipeID = 300 } } } },
      }
      DS.GetCharacters = function(_, realm)
        if realm == "R" then return { ["Player-1-L"] = { name = "Local", guildName = "G" } } end
        return {}
      end
      SD.NotifyRecipesChanged()
      local guild = SD.GetAllGuildRecipes()
      assert.are.equal(2, #guild)
      for _, r in ipairs(guild) do assert.are.equal("Bob", r.characterName) end
    end)

    it("includes guild recipes whether or not the player shares their own", function()
      AltArmy.GuildShareSettings.SetSharingEnabled(false)
      SD.NotifyRecipesChanged()
      assert.are.equal(2, #SD.GetAllGuildRecipes())
    end)
  end)

  describe("SearchRecipes", function()
    it("returns empty for nil or whitespace query", function()
      local old = SD.GetAllRecipes
      SD.GetAllRecipes = function() return {} end
      assert.are.same(SD.SearchRecipes(nil), {})
      assert.are.same(SD.SearchRecipes("   "), {})
      SD.GetAllRecipes = old
    end)
    it("filters by recipe name (item or spell)", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
          { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 250, recipeID = 222 },
        }
      end
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon1" end
        if id == 222 then return "Super Mana Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon2" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local results = SD.SearchRecipes("mana")
      SD.GetAllRecipes = oldGetAll
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 222)
      assert.are.equal(results[1].characterName, "B")
    end)

    it("uses a recipe row's own name instead of GetSpellInfo/GetItemInfo when present", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          {
            characterName = "A", realm = "R", professionName = "Blacksmithing",
            skillRank = 150, recipeID = 2664, resultItemID = 2954, name = "Runed Copper Bracers",
          },
        }
      end
      -- Item/spell info not yet cached client-side (common right after login): both nil.
      _G.GetItemInfo = function() return nil end
      _G.GetSpellInfo = function() return nil end
      local results = SD.SearchRecipes("runed copper bracers")
      SD.GetAllRecipes = oldGetAll
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(1, #results)
      assert.are.equal(2664, results[1].recipeID)
    end)

    it("does not permanently cache a recipe as unresolved when info wasn't available yet", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          { characterName = "A", realm = "R", professionName = "Blacksmithing", skillRank = 150, recipeID = 9001 },
        }
      end
      -- First lookup: item/spell not cached yet server-side, both return nil.
      _G.GetItemInfo = function() return nil end
      _G.GetSpellInfo = function() return nil end
      local firstResults = SD.SearchRecipes("bracers")
      assert.are.equal(0, #firstResults)

      -- Later the client has the info cached. A rescan (NotifyRecipesChanged) should
      -- let it resolve instead of permanently reusing the earlier nil result.
      SD.InvalidateRecipesCache()
      _G.GetItemInfo = function(id)
        if id == 9001 then return "Runed Copper Bracers" end
        return nil
      end
      local secondResults = SD.SearchRecipes("bracers")
      SD.GetAllRecipes = oldGetAll
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(1, #secondResults)
      assert.are.equal(9001, secondResults[1].recipeID)
    end)

    it("lists own characters before guildmates when FilterAndSortRecipes merges both", function()
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon1" end
        if id == 222 then return "Super Mana Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon2" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local results = SD._FilterAndSortRecipes({
        {
          characterName = "Zebra",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 300,
          recipeID = 111,
          isGuild = true,
        },
        {
          characterName = "Alice",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 250,
          recipeID = 111,
          isGuild = true,
        },
        {
          characterName = "MageAlt",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 375,
          recipeID = 111,
        },
        {
          characterName = "PriestAlt",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 200,
          recipeID = 111,
        },
        {
          characterName = "OtherRecipeOwner",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 100,
          recipeID = 222,
          isGuild = true,
        },
      }, "potion")
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(5, #results)
      -- Same recipe: own chars (alpha by name), then guildmates (alpha by name).
      assert.are.equal("MageAlt", results[1].characterName)
      assert.is_nil(results[1].isGuild)
      assert.are.equal("PriestAlt", results[2].characterName)
      assert.is_nil(results[2].isGuild)
      assert.are.equal("Alice", results[3].characterName)
      assert.is_true(results[3].isGuild)
      assert.are.equal("Zebra", results[4].characterName)
      assert.is_true(results[4].isGuild)
      -- Different recipe name still sorts after (mana after healing).
      assert.are.equal(222, results[5].recipeID)
      assert.are.equal("OtherRecipeOwner", results[5].characterName)
    end)

    it("SearchRecipes returns only local rows; SearchGuildRecipes returns guild rows", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetGuild = SD.GetAllGuildRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          { characterName = "Local", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
        }
      end
      SD.GetAllGuildRecipes = function()
        return {
          {
            characterName = "Bob",
            realm = "R",
            professionName = "Alchemy",
            skillRank = 200,
            recipeID = 111,
            isGuild = true,
          },
        }
      end
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local localResults = SD.SearchRecipes("potion")
      local guildResults = SD.SearchGuildRecipes("potion")
      SD.GetAllRecipes = oldGetAll
      SD.GetAllGuildRecipes = oldGetGuild
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(1, #localResults)
      assert.is_nil(localResults[1].isGuild)
      assert.are.equal(1, #guildResults)
      assert.is_true(guildResults[1].isGuild)
    end)

    it("does not return alias effect spells when both match query", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemSpell = _G.GetItemSpell
      local row = { color = 1, resultItemID = 9187, primaryRecipeID = 11449 }
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = {
                rank = 300,
                Recipes = {
                  [11449] = row,
                  [11334] = row,
                },
              },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11334 then return "Agility" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      AltArmy.DataStore:MigrateRecipePrimaryIds()
      local results = SD.SearchRecipes("agility")
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 11449)
    end)
    it("excludes split alias rows after remigrate debug", function()
      local DS = AltArmy.DataStore
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemSpell = _G.GetItemSpell
      DS.accountData = _G.AltArmyTBC_Data
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Dreamscythe = {
          felfrell = {
            name = "felfrell",
            Professions = {
              Alchemy = {
                rank = 373,
                Recipes = {
                  [11449] = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 },
                  [11328] = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 },
                },
              },
            },
          },
        },
      }
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      SD.ClearSearchCaches()
      local updated = DS:RemigrateRecipePrimaryIdsDebug()
      assert.is_true(updated > 0)
      local all = SD.GetAllRecipes()
      assert.are.equal(1, #all)
      local results = SD.SearchRecipes("agility")
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(1, #results)
      assert.are.equal(11449, results[1].recipeID)
    end)
  end)

  describe("_FilterRecipesByLevel", function()
    it("keeps rows in range and rows with nil recipeSkillRequired", function()
      AltArmy.RecipeData = { recipes = {} }
      local rows = {
        { recipeID = 1, recipeSkillRequired = 200 },
        { recipeID = 2, recipeSkillRequired = 260 },
        { recipeID = 3, recipeSkillRequired = nil },
      }
      local filtered = SD._FilterRecipesByLevel(rows, { min = 200, max = 250 })
      AltArmy.RecipeData = nil
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)

    it("returns all rows when filter is full range 0-375", function()
      local rows = { { recipeID = 1, recipeSkillRequired = 999 } }
      local filtered = SD._FilterRecipesByLevel(rows, { min = 0, max = 375 })
      assert.are.equal(1, #filtered)
    end)
  end)

  describe("_EnrichRecipeEntry", function()
    before_each(function()
      AltArmy.RecipeData = nil
      if AltArmy.RecipeInfo and AltArmy.RecipeInfo.ClearCaches then
        AltArmy.RecipeInfo.ClearCaches()
      end
    end)

    it("adds recipeSkillRequired and difficulty from the bundled recipe data", function()
      _G.GetSpellInfo = function(id)
        if id == 2259 then return "Alchemy" end
        return nil
      end
      AltArmy.RecipeData = { recipes = { [111] = { "alchemy", 5, 180, 195, 225, "trainer", false } } }
      local entry = {
        professionName = "Alchemy",
        recipeID = 111,
        skillRank = 300,
      }
      SD._EnrichRecipeEntry(entry)
      assert.are.equal(180, entry.recipeSkillRequired)
      assert.are.equal("gray", entry.difficulty)
    end)

    it("is idempotent and skips the recipe lookup on second call", function()
      local calls = 0
      local saved = AltArmy.RecipeInfo
      AltArmy.RecipeInfo = {
        IsAvailable = function() return true end,
        EnrichEntry = function(entry)
          calls = calls + 1
          entry.recipeSkillRequired = 100
          entry.difficulty = "orange"
          return entry
        end,
      }
      local entry = { recipeID = 1, professionName = "Alchemy", skillRank = 50 }
      SD._EnrichRecipeEntry(entry)
      SD._EnrichRecipeEntry(entry)
      AltArmy.RecipeInfo = saved
      assert.are.equal(1, calls)
      assert.are.equal(100, entry.recipeSkillRequired)
    end)
  end)

  describe("EnsureRecipeDisplayCache", function()
    it("resolves name icon and skill text once then reuses cache", function()
      local spellCalls = 0
      _G.GetSpellInfo = function(id)
        if id == 11449 then
          spellCalls = spellCalls + 1
          return "Greater Mana Potion", nil, "Interface\\Icons\\INV_Potion_73"
        end
        return "Alchemy"
      end
      _G.GetItemInfo = function() return nil end
      local entry = {
        professionName = "Alchemy",
        recipeID = 11449,
        resultItemID = nil,
        recipeSkillRequired = 180,
        skillRank = 300,
        difficulty = "gray",
      }
      SD.EnsureRecipeDisplayCache(entry)
      SD.EnsureRecipeDisplayCache(entry)
      assert.are.equal(1, spellCalls)
      assert.are.equal("Alchemy: Greater Mana Potion", entry._aaRecipeBaseName)
      assert.are.equal("Alchemy: ", entry._aaRecipeNamePrefix)
      assert.are.equal("Greater Mana Potion", entry._aaRecipeMatchName)
      assert.are.equal("Interface\\Icons\\INV_Potion_73", entry._aaIconPath)
      assert.is_truthy(entry._aaSkillCellText)
      assert.is_truthy(entry._aaSkillCellText:find("180", 1, true))
      assert.is_truthy(entry._aaDisplayCached)
    end)

    it("takes the crafted item's icon without the item cache (GetItemInfoInstant)", function()
      _G.GetSpellInfo = function() return nil end
      _G.GetItemInfo = function() return nil end -- item not cached yet
      _G.GetItemInfoInstant = function(id)
        if id == 32068 then
          return 32068, "Consumable", "Elixir", "", "Interface\\Icons\\INV_Potion_158"
        end
        return nil
      end
      local entry = { professionName = "Alchemy", recipeID = 39639, resultItemID = 32068, name = "Elixir of Ironskin" }
      SD.EnsureRecipeDisplayCache(entry)
      _G.GetItemInfoInstant = nil
      assert.are.equal("Interface\\Icons\\INV_Potion_158", entry._aaIconPath)
    end)

    it("falls back to the recipe spell's icon when the crafted item has none yet", function()
      _G.GetSpellInfo = function(id)
        if id == 39640 then return "Elixir of Ironskin", nil, "Interface\\Icons\\Trade_Alchemy" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      local entry = { professionName = "Alchemy", recipeID = 39640, resultItemID = 32069, name = "Elixir of Ironskin" }
      SD.EnsureRecipeDisplayCache(entry)
      assert.are.equal("Interface\\Icons\\Trade_Alchemy", entry._aaIconPath)
    end)

    it("retries the icon on a later paint instead of caching the question mark", function()
      _G.GetSpellInfo = function() return nil end
      local cached = false
      _G.GetItemInfo = function(id)
        if id == 32070 and cached then
          return "Elixir", nil, nil, nil, nil, nil, nil, nil, nil, "Interface\\Icons\\INV_Potion_159"
        end
        return nil
      end
      local first = { professionName = "Alchemy", recipeID = 39641, resultItemID = 32070, name = "Elixir" }
      SD.EnsureRecipeDisplayCache(first)
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", first._aaIconPath)
      cached = true
      SD.EnsureRecipeDisplayCache(first) -- same row repainted
      assert.are.equal("Interface\\Icons\\INV_Potion_159", first._aaIconPath)
      local second = { professionName = "Alchemy", recipeID = 39641, resultItemID = 32070, name = "Elixir" }
      SD.EnsureRecipeDisplayCache(second)
      assert.are.equal("Interface\\Icons\\INV_Potion_159", second._aaIconPath)
    end)

    it("uses entry.name instead of GetSpellInfo/GetItemInfo(recipeID) when present", function()
      -- recipeID isn't reliably a spell or item ID (e.g. some non-enchant profession recipes
      -- use an unrelated numeric id), so a GetSpellInfo/GetItemInfo(recipeID) guess can
      -- misresolve to a completely unrelated real item/spell that happens to share that id.
      _G.GetSpellInfo = function(id)
        if id == 2664 then
          return "Some Unrelated Spell"
        end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      local entry = {
        professionName = "Blacksmithing",
        recipeID = 2664,
        resultItemID = 2854,
        name = "Runed Copper Bracers",
        skillRank = 150,
      }
      SD.EnsureRecipeDisplayCache(entry)
      assert.are.equal("Runed Copper Bracers", entry._aaRecipeMatchName)
      assert.are.equal("Blacksmithing: Runed Copper Bracers", entry._aaRecipeBaseName)
    end)

    it("uses result item icon when available", function()
      _G.GetSpellInfo = function(id)
        if id == 11449 then
          return "Greater Mana Potion"
        end
        return "Alchemy"
      end
      _G.GetItemInfo = function(id)
        if id == 1710 then
          return "Greater Mana Potion", nil, nil, nil, nil, nil, nil, nil, nil,
            "Interface\\Icons\\INV_Potion_72"
        end
        return nil
      end
      local entry = {
        professionName = "Alchemy",
        recipeID = 11449,
        resultItemID = 1710,
        skillRank = 200,
      }
      SD.EnsureRecipeDisplayCache(entry)
      assert.are.equal("Interface\\Icons\\INV_Potion_72", entry._aaIconPath)
    end)

    it("reuses name and icon by recipe identity across characters", function()
      local spellCalls = 0
      _G.GetSpellInfo = function(id)
        if id == 11449 then
          spellCalls = spellCalls + 1
          return "Greater Mana Potion", nil, "Interface\\Icons\\INV_Potion_73"
        end
        return "Alchemy"
      end
      _G.GetItemInfo = function() return nil end
      local a = {
        professionName = "Alchemy",
        recipeID = 11449,
        skillRank = 300,
        recipeSkillRequired = 180,
        difficulty = "gray",
        characterName = "Alice",
      }
      local b = {
        professionName = "Alchemy",
        recipeID = 11449,
        skillRank = 200,
        recipeSkillRequired = 180,
        difficulty = "yellow",
        characterName = "Bob",
      }
      SD.EnsureRecipeDisplayCache(a)
      SD.EnsureRecipeDisplayCache(b)
      assert.are.equal(1, spellCalls)
      assert.are.equal(a._aaRecipeBaseName, b._aaRecipeBaseName)
      assert.are.equal(a._aaIconPath, b._aaIconPath)
      assert.is_truthy(a._aaSkillCellText:find("/300", 1, true))
      assert.is_truthy(b._aaSkillCellText:find("/200", 1, true))
    end)

    it("formats collapsed guild rows as required/*** using hardest difficulty", function()
      _G.GetSpellInfo = function(id)
        if id == 11449 then
          return "Greater Mana Potion", nil, "Interface\\Icons\\INV_Potion_73"
        end
        return "Alchemy"
      end
      _G.GetItemInfo = function() return nil end
      local RI = AltArmy.RecipeInfo
      local oldAvailable = RI.IsAvailable
      local oldEnrich = RI.EnrichEntry
      RI.IsAvailable = function() return true end
      RI.EnrichEntry = function(entry)
        if not entry then return entry end
        entry.recipeSkillRequired = 180
        if entry.skillRank == 100 then
          entry.difficulty = "orange"
        elseif entry.skillRank == 200 then
          entry.difficulty = "yellow"
        else
          entry.difficulty = "gray"
        end
        return entry
      end
      local entry = {
        isGuildCollapsed = true,
        professionName = "Alchemy",
        recipeID = 11449,
        guildChars = {
          { characterName = "Alice", professionName = "Alchemy", recipeID = 11449, skillRank = 300 },
          { characterName = "Bob", professionName = "Alchemy", recipeID = 11449, skillRank = 100 },
          { characterName = "Carol", professionName = "Alchemy", recipeID = 11449, skillRank = 200 },
        },
      }
      SD.EnsureRecipeDisplayCache(entry)
      RI.IsAvailable = oldAvailable
      RI.EnrichEntry = oldEnrich
      assert.are.equal("|cffff8040180|r/***", entry._aaSkillCellText)
    end)

    it("uses * for collapsed rows without recipe data", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.GetItemInfo = function() return nil end
      local RI = AltArmy.RecipeInfo
      local oldAvailable = RI.IsAvailable
      RI.IsAvailable = function() return false end
      local entry = {
        isGuildCollapsed = true,
        professionName = "Alchemy",
        recipeID = 11449,
        guildChars = {
          { characterName = "Alice", professionName = "Alchemy", recipeID = 11449, skillRank = 300 },
          { characterName = "Bob", professionName = "Alchemy", recipeID = 11449, skillRank = 100 },
        },
      }
      SD.EnsureRecipeDisplayCache(entry)
      RI.IsAvailable = oldAvailable
      assert.are.equal("*", entry._aaSkillCellText)
    end)
  end)

  describe("StartRecipeResultPrewarm", function()
    before_each(function()
      if SD.StopRecipeResultPrewarm then
        SD.StopRecipeResultPrewarm()
      end
      AltArmy.RecipeData = nil
      if AltArmy.RecipeInfo and AltArmy.RecipeInfo.ClearCaches then
        AltArmy.RecipeInfo.ClearCaches()
      end
    end)

    it("enriches and display-caches entries across OnUpdate chunks", function()
      local spellCalls = 0
      _G.GetSpellInfo = function(id)
        if id == 1 or id == 2 or id == 3 then
          spellCalls = spellCalls + 1
          return "Spell" .. tostring(id), nil, "Interface\\Icons\\Spell" .. tostring(id)
        end
        return "Alchemy"
      end
      _G.GetItemInfo = function() return nil end
      local list = {
        { professionName = "Alchemy", recipeID = 1, skillRank = 100 },
        { professionName = "Alchemy", recipeID = 2, skillRank = 100 },
        { professionName = "Alchemy", recipeID = 3, skillRank = 100 },
      }
      SD.StartRecipeResultPrewarm(list)
      assert.is_true(SD.IsRecipeResultPrewarmRunning())
      -- Force tiny chunks via test helper if available; otherwise tick until done.
      local guard = 0
      while SD.IsRecipeResultPrewarmRunning() and guard < 20 do
        SD._TickRecipeResultPrewarmForTests()
        guard = guard + 1
      end
      assert.is_false(SD.IsRecipeResultPrewarmRunning())
      assert.is_true(list[1]._aaRecipeEnriched)
      assert.is_true(list[3]._aaDisplayCached)
      assert.is_truthy(list[2]._aaRecipeBaseName)
    end)
  end)

  describe("deferred recipe enrich", function()
    local function stubCraftEnrichCounter()
      local calls = { n = 0 }
      local saved = AltArmy.RecipeInfo
      AltArmy.RecipeInfo = {
        IsAvailable = function() return true end,
        EnrichEntry = function(entry)
          calls.n = calls.n + 1
          entry.recipeSkillRequired = 150
          entry.difficulty = "yellow"
          entry.recipeSource = "trainer"
          return entry
        end,
      }
      return calls, saved
    end

    it("NeedsRecipeEnrichForFilters is false when filters are defaults", function()
      local SS = AltArmy.SearchSettings
      SS.ResetAllRecipeFilters()
      assert.is_false(SD._NeedsRecipeEnrichForFilters(SS.GetSearchSettings()))
    end)

    it("NeedsRecipeEnrichForFilters is true when difficulty filter is narrowed", function()
      local SS = AltArmy.SearchSettings
      SS.ResetAllRecipeFilters()
      SS.SetDifficultyBandEnabled("gray", false)
      assert.is_true(SD._NeedsRecipeEnrichForFilters(SS.GetSearchSettings()))
      SS.ResetAllRecipeFilters()
    end)

    it("SearchRecipes skips bulk enrich when recipe data filters are inactive", function()
      local SS = AltArmy.SearchSettings
      SS.ResetAllRecipeFilters()
      local calls, savedRI = stubCraftEnrichCounter()
      local oldGetAll = SD.GetAllRecipes
      SD.GetAllRecipes = function()
        return {
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 1 },
          { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 200, recipeID = 1 },
        }
      end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function() return "Test Potion" end

      local results = SD.SearchRecipes("potion")
      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      AltArmy.RecipeInfo = savedRI

      assert.are.equal(2, #results)
      assert.are.equal(0, calls.n)
      assert.is_nil(results[1].recipeSkillRequired)
    end)

    it("SearchRecipes bulk-enriches when a recipe data filter is active", function()
      local SS = AltArmy.SearchSettings
      SS.ResetAllRecipeFilters()
      SS.SetDifficultyBandEnabled("gray", false)
      local calls, savedRI = stubCraftEnrichCounter()
      local oldGetAll = SD.GetAllRecipes
      SD.GetAllRecipes = function()
        return {
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 1 },
        }
      end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function() return "Test Potion" end

      local results = SD.SearchRecipes("potion")
      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      AltArmy.RecipeInfo = savedRI
      SS.ResetAllRecipeFilters()

      assert.are.equal(1, #results)
      assert.are.equal(1, calls.n)
      assert.are.equal(150, results[1].recipeSkillRequired)
    end)

    it("SortRecipeResults enriches before Skill sort with recipe data", function()
      local calls, savedRI = stubCraftEnrichCounter()
      local rows = {
        { characterName = "A", professionName = "Alchemy", recipeID = 1, skillRank = 300, recipeNameLower = "a" },
        { characterName = "B", professionName = "Alchemy", recipeID = 2, skillRank = 100, recipeNameLower = "b" },
      }
      local out = SD.SortRecipeResults(rows, "Skill", true, true)
      AltArmy.RecipeInfo = savedRI
      assert.are.equal(2, calls.n)
      assert.are.equal(150, out[1].recipeSkillRequired)
    end)
  end)

  describe("_FilterRecipesByDifficulty", function()
    before_each(function()
      AltArmy.RecipeData = { recipes = {} }
    end)
    after_each(function()
      AltArmy.RecipeData = nil
    end)

    it("keeps rows with enabled difficulty and unknown difficulty", function()
      local rows = {
        { recipeID = 1, difficulty = "orange" },
        { recipeID = 2, difficulty = "gray" },
        { recipeID = 3, difficulty = nil },
      }
      local filtered = SD._FilterRecipesByDifficulty(rows, {
        orange = true, yellow = true, green = true, gray = false,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_FilterRecipesBySource", function()
    before_each(function()
      AltArmy.RecipeData = { recipes = {} }
    end)
    after_each(function()
      AltArmy.RecipeData = nil
    end)

    it("keeps rows with enabled source and unknown source", function()
      local rows = {
        { recipeID = 1, recipeSource = "trainer" },
        { recipeID = 2, recipeSource = "drop" },
        { recipeID = 3, recipeSource = nil },
      }
      local filtered = SD._FilterRecipesBySource(rows, {
        trainer = true, vendor = true, quest = true,
        drop = false, reputation = true, starter = true,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_FilterRecipesByProfession", function()
    before_each(function()
      _G.AltArmy = _G.AltArmy or {}
      package.loaded["SearchSettings"] = nil
      require("SearchSettings")
      AltArmy.SearchSettings._ClearProfessionKeyCache()
      _G.GetSpellInfo = function(spellId)
        if spellId == 2259 then return "Alchemy" end
        if spellId == 3908 then return "Tailoring" end
        return nil
      end
    end)
    after_each(function()
      _G.GetSpellInfo = nil
    end)

    it("keeps rows with enabled professions and unknown professions", function()
      local rows = {
        { recipeID = 1, professionName = "Alchemy" },
        { recipeID = 2, professionName = "Tailoring" },
        { recipeID = 3, professionName = "Unknown" },
      }
      local filtered = SD._FilterRecipesByProfession(rows, {
        alchemy = true,
        blacksmithing = true,
        cooking = true,
        enchanting = true,
        engineering = true,
        firstAid = true,
        jewelcrafting = true,
        leatherworking = true,
        mining = true,
        poisons = true,
        tailoring = false,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_ApplyRecipeSearchFilters", function()
    before_each(function()
      AltArmy.RecipeData = { recipes = {} }
    end)
    after_each(function()
      AltArmy.RecipeData = nil
    end)

    it("applies difficulty and source filters together", function()
      local rows = {
        { recipeID = 1, difficulty = "orange", recipeSource = "trainer" },
        { recipeID = 2, difficulty = "gray", recipeSource = "trainer" },
        { recipeID = 3, difficulty = "orange", recipeSource = "drop" },
      }
      local filtered = SD._ApplyRecipeSearchFilters(rows, {
        recipeLevelFilter = { min = 0, max = 375 },
        professionFilter = {
          alchemy = true, blacksmithing = true, cooking = true, enchanting = true,
          engineering = true, firstAid = true, jewelcrafting = true, leatherworking = true,
          mining = true, poisons = true, tailoring = true,
        },
        difficultyFilter = { orange = true, yellow = true, green = true, gray = false },
        sourceFilter = {
          trainer = true, vendor = true, quest = true,
          drop = false, reputation = true, starter = true,
        },
      })
      assert.are.equal(1, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
    end)

    it("applies profession filter without recipe data", function()
      AltArmy.RecipeData = nil
      local rows = {
        { recipeID = 1, professionName = "Alchemy" },
        { recipeID = 2, professionName = "Tailoring" },
      }
      local filtered = SD._ApplyRecipeSearchFilters(rows, {
        professionFilter = {
          alchemy = true,
          blacksmithing = true,
          cooking = true,
          enchanting = true,
          engineering = true,
          firstAid = true,
          jewelcrafting = true,
          leatherworking = true,
          mining = true,
          tailoring = false,
        },
      })
      assert.are.equal(1, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
    end)
  end)

  describe("SortItemResults", function()
    local rows = {
      { itemID = 1, itemName = "Zebra Cloth", characterName = "Bob", realm = "R", location = "bag", count = 2 },
      { itemID = 2, itemName = "Alpha Bolt", characterName = "Alice", realm = "R", location = "bank", count = 5 },
      { itemID = 1, itemName = "Zebra Cloth", characterName = "Alice", realm = "R", location = "bank", count = 3 },
    }

    it("returns the list unchanged when sortKey is nil", function()
      assert.are.same(rows, SD.SortItemResults(rows, nil, true))
    end)

    it("sorts by item name ascending", function()
      local out = SD.SortItemResults(rows, "Item", true)
      assert.are.equal(2, out[1].itemID)
      assert.are.equal(1, out[2].itemID)
      assert.are.equal("bank", out[2].location)
      assert.are.equal(1, out[3].itemID)
      assert.are.equal("bag", out[3].location)
    end)

    it("sorts by character name ascending", function()
      local out = SD.SortItemResults(rows, "Character", true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Alice", out[2].characterName)
      assert.are.equal("Bob", out[3].characterName)
    end)

    it("sorts by grouped item total descending", function()
      local out = SD.SortItemResults(rows, "Total", false)
      assert.are.equal(1, out[1].itemID)
      assert.are.equal(1, out[2].itemID)
      assert.are.equal(2, out[3].itemID)
    end)
  end)

  describe("SortRecipeResults", function()
    local rows = {
      {
        characterName = "Zebra",
        recipeID = 1,
        recipeNameLower = "zebra cloth",
        professionName = "Tailoring",
        skillRank = 300,
        isGuild = true,
      },
      {
        characterName = "Alice",
        recipeID = 2,
        recipeNameLower = "alpha bolt",
        professionName = "Tailoring",
        skillRank = 375,
        recipeSkillRequired = 250,
        difficulty = "yellow",
      },
      {
        characterName = "Bob",
        recipeID = 3,
        recipeNameLower = "mooncloth",
        professionName = "Tailoring",
        skillRank = 200,
        recipeSkillRequired = 300,
        difficulty = "orange",
      },
    }

    it("sorts by recipe name ascending", function()
      local out = SD.SortRecipeResults(rows, "Recipe", true, true)
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("stamps _aaRecipeSortKey on all index rows for a recipe id", function()
      local oldGetAll = SD.GetAllRecipes
      SD.GetAllRecipes = function()
        return {
          {
            characterName = "Alice",
            realm = "R",
            professionName = "Alchemy",
            skillRank = 300,
            recipeID = 1,
          },
          {
            characterName = "Bob",
            realm = "R",
            professionName = "Alchemy",
            skillRank = 1,
            recipeID = 1,
          },
        }
      end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 1 then return "Minor Healing Potion" end
        return nil
      end

      SD.ClearSearchCaches()
      local hits = SD.SearchRecipes("healing")
      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo

      assert.are.equal(2, #hits)
      local expected = "alchemy\0minor healing potion"
      assert.are.equal(expected, hits[1]._aaRecipeSortKey)
      assert.are.equal(expected, hits[2]._aaRecipeSortKey)
      assert.are.equal("minor healing potion", hits[1].recipeNameLower)
    end)

    it("sorts by character name ascending", function()
      local out = SD.SortRecipeResults(rows, "Character", true, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)

    it("sorts by required skill descending with recipe data", function()
      local out = SD.SortRecipeResults(rows, "Skill", false, true)
      assert.are.equal(3, out[1].recipeID)
      assert.are.equal(2, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("sorts by character skill rank without recipe data", function()
      local out = SD.SortRecipeResults(rows, "Skill", false, false)
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(3, out[3].recipeID)
    end)

    it("lists own characters before guildmates when recipe names tie", function()
      local tied = {
        {
          characterName = "Zebra",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
          isGuild = true,
        },
        {
          characterName = "Alice",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
        },
        {
          characterName = "Bob",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
        },
      }
      local out = SD.SortRecipeResults(tied, "Recipe", true, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)

    it("keeps same recipeID rows contiguous when sorting by Recipe", function()
      local rows = {
        { characterName = "Z", recipeID = 2, recipeNameLower = "beta", professionName = "Alchemy", isGuild = true },
        { characterName = "A", recipeID = 1, recipeNameLower = "alpha", professionName = "Alchemy" },
        { characterName = "B", recipeID = 2, recipeNameLower = "beta", professionName = "Alchemy" },
        { characterName = "C", recipeID = 1, recipeNameLower = "alpha", professionName = "Alchemy", isGuild = true },
      }
      local out = SD.SortRecipeResults(rows, "Recipe", true, true)
      assert.are.equal(1, out[1].recipeID)
      assert.are.equal("A", out[1].characterName)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal("C", out[2].characterName)
      assert.are.equal(2, out[3].recipeID)
      assert.are.equal("B", out[3].characterName)
      assert.are.equal(2, out[4].recipeID)
      assert.are.equal("Z", out[4].characterName)
    end)

    it("lists own characters before guildmates when required skill ties", function()
      local tied = {
        {
          characterName = "Zebra",
          recipeID = 1,
          recipeNameLower = "alpha",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
          isGuild = true,
        },
        {
          characterName = "Alice",
          recipeID = 2,
          recipeNameLower = "beta",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
        },
        {
          characterName = "Bob",
          recipeID = 3,
          recipeNameLower = "gamma",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
        },
      }
      local out = SD.SortRecipeResults(tied, "Skill", false, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)
  end)

  describe("CollapseGuildRecipeRows", function()
    local function guildRow(name, recipeID, skillRank)
      return {
        characterName = name,
        recipeID = recipeID,
        professionName = "Tailoring",
        skillRank = skillRank or 300,
        isGuild = true,
        classFile = "MAGE",
        realm = "R",
      }
    end

    local function localRow(name, recipeID, skillRank)
      return {
        characterName = name,
        recipeID = recipeID,
        professionName = "Tailoring",
        skillRank = skillRank or 375,
        classFile = "WARRIOR",
        realm = "R",
      }
    end

    it("collapses 3+ guild rows for the same recipe into one synthetic entry", function()
      local sorted = {
        localRow("Alice", 1),
        guildRow("Bob", 1, 250),
        guildRow("Carol", 1, 300),
        guildRow("Dave", 1, 200),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(2, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.is_true(out[2].isGuildCollapsed)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal("Tailoring", out[2].professionName)
      assert.are.equal("*", out[2]._aaSkillCellText)
      assert.are.equal(3, #out[2].guildChars)
      assert.are.equal("Bob", out[2].guildChars[1].characterName)
      assert.are.equal("Carol", out[2].guildChars[2].characterName)
      assert.are.equal("Dave", out[2].guildChars[3].characterName)
    end)

    it("leaves a single guild row uncollapsed", function()
      local sorted = {
        localRow("Alice", 1),
        guildRow("Bob", 1),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(2, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.is_nil(out[2].isGuildCollapsed)
    end)

    it("leaves exactly two guild rows uncollapsed", function()
      local sorted = {
        localRow("Alice", 1),
        guildRow("Bob", 1),
        guildRow("Carol", 1),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(3, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Carol", out[3].characterName)
      assert.is_nil(out[2].isGuildCollapsed)
      assert.is_nil(out[3].isGuildCollapsed)
    end)

    it("leaves local-only rows unchanged", function()
      local sorted = {
        localRow("Alice", 1),
        localRow("Bob", 1),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(2, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
    end)

    it("places the collapsed row at the first guild row position", function()
      -- Sorted by Character: Alice (local), Bob/Carol/Dave (guild), Zebra (local other recipe)
      local sorted = {
        localRow("Alice", 1),
        guildRow("Bob", 1),
        guildRow("Carol", 1),
        guildRow("Dave", 1),
        localRow("Zebra", 2),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(3, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.is_true(out[2].isGuildCollapsed)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal("Zebra", out[3].characterName)
    end)

    it("collapses each recipe independently", function()
      local sorted = {
        guildRow("A", 1),
        guildRow("B", 1),
        guildRow("B2", 1),
        guildRow("C", 2),
        guildRow("D", 2),
        guildRow("D2", 2),
        guildRow("E", 3),
        guildRow("F", 3),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(4, #out)
      assert.is_true(out[1].isGuildCollapsed)
      assert.are.equal(1, out[1].recipeID)
      assert.is_true(out[2].isGuildCollapsed)
      assert.are.equal(2, out[2].recipeID)
      assert.are.equal("E", out[3].characterName)
      assert.is_nil(out[3].isGuildCollapsed)
      assert.are.equal("F", out[4].characterName)
      assert.is_nil(out[4].isGuildCollapsed)
    end)

    it("keeps the summary row and appends child rows when expanded", function()
      local sorted = {
        localRow("Alice", 1),
        guildRow("Bob", 1),
        guildRow("Carol", 1),
        guildRow("Dave", 1),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, { [1] = true })
      assert.are.equal(5, #out)
      assert.are.equal("Alice", out[1].characterName)
      assert.is_true(out[2].isGuildCollapsed)
      assert.is_true(out[2].isGuildExpanded)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(3, #out[2].guildChars)
      assert.are.equal("Bob", out[3].characterName)
      assert.is_true(out[3]._aaFromCollapse)
      assert.are.equal("Carol", out[4].characterName)
      assert.is_true(out[4]._aaFromCollapse)
      assert.are.equal("Dave", out[5].characterName)
      assert.is_true(out[5]._aaFromCollapse)
      assert.is_nil(out[1]._aaFromCollapse)
    end)

    it("does not mutate the input list", function()
      local sorted = {
        guildRow("Bob", 1),
        guildRow("Carol", 1),
        guildRow("Dave", 1),
      }
      local out = SD.CollapseGuildRecipeRows(sorted, {})
      assert.are.equal(1, #out)
      assert.are.equal(3, #sorted)
      assert.are.equal("Bob", sorted[1].characterName)
    end)

    it("returns the list unchanged when nil or empty", function()
      assert.is_nil(SD.CollapseGuildRecipeRows(nil, {}))
      local empty = {}
      local out = SD.CollapseGuildRecipeRows(empty, {})
      assert.are.equal(0, #out)
    end)
  end)

  describe("_IsRecipeAliasId", function()
    it("returns true when recipeID differs from primaryRecipeID", function()
      assert.is_true(SD._IsRecipeAliasId(11334, { primaryRecipeID = 11449 }))
      assert.is_false(SD._IsRecipeAliasId(11449, { primaryRecipeID = 11449 }))
    end)
    it("returns false when primaryRecipeID is missing", function()
      assert.is_false(SD._IsRecipeAliasId(11334, { resultItemID = 9187 }))
    end)
  end)

  describe("GetSearchTailDebounceSecs", function()
    it("returns 0 for empty query", function()
      assert.are.equal(0, SD.GetSearchTailDebounceSecs(nil))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs(""))
    end)
    it("uses 0.4s debounce for 1-character queries", function()
      assert.are.equal(0.4, SD.GetSearchTailDebounceSecs("a"))
    end)
    it("uses 0.1s debounce for 2-character queries", function()
      assert.are.equal(0.1, SD.GetSearchTailDebounceSecs("ab"))
    end)
    it("runs synchronously (0 delay) for 3+ character queries", function()
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("abc"))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("abcd"))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("healing potion"))
    end)
  end)

  describe("search phase debug logging", function()
    local function withSearchDebug(fn)
      local logs = {}
      local prevDebug = AltArmy.Debug
      AltArmy.Debug = {
        IsSearchEnabled = function() return true end,
        LogSearch = function(msg) logs[#logs + 1] = msg end,
      }
      local oldStart, oldStop = _G.debugprofilestart, _G.debugprofilestop
      local tick = 0
      _G.debugprofilestart = function() end
      _G.debugprofilestop = function()
        tick = tick + 1
        return tick * 0.5
      end
      local ok, err = pcall(fn, logs)
      _G.debugprofilestart = oldStart
      _G.debugprofilestop = oldStop
      AltArmy.Debug = prevDebug
      if not ok then error(err) end
      return logs
    end

    it("logs lookup/expand/sort/enrich/filter phases for SearchRecipes", function()
      local oldGetAll = SD.GetAllRecipes
      SD.GetAllRecipes = function()
        return {
          { characterName = "Alice", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 1 },
          { characterName = "Bob", realm = "R", professionName = "Alchemy", skillRank = 1, recipeID = 2 },
        }
      end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 1 then return "Minor Healing Potion" end
        if id == 2 then return "Elixir of Giants" end
        return nil
      end

      local logs = withSearchDebug(function()
        SD.ClearSearchCaches()
        SD.SearchRecipes("elixir")
      end)

      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo

      local recipeLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("recipes q=", 1, true) then
          recipeLog = msg
          break
        end
      end
      assert.is_truthy(recipeLog, "expected recipes timing log")
      assert.is_truthy(recipeLog:find("lookup=", 1, true), recipeLog)
      assert.is_truthy(recipeLog:find("expand=", 1, true), recipeLog)
      assert.is_truthy(recipeLog:find("sort=", 1, true), recipeLog)
      assert.is_truthy(recipeLog:find("enrich=", 1, true), recipeLog)
      assert.is_truthy(recipeLog:find("filter=", 1, true), recipeLog)
    end)

    it("logs lookup/expand/sort/enrich/filter phases for SearchGuildRecipes", function()
      local oldGetAll = SD.GetAllGuildRecipes
      SD.GetAllGuildRecipes = function()
        return {
          {
            characterName = "G1",
            realm = "R",
            professionName = "Alchemy",
            skillRank = 300,
            recipeID = 1,
            isGuild = true,
          },
        }
      end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 1 then return "Minor Healing Potion" end
        return nil
      end
      local SS = AltArmy.SearchSettings
      local oldCan = SS and SS.CanShowIncludeGuildmatesToggle
      local oldInc = SS and SS.IsIncludeGuildmatesEnabled
      if SS then
        SS.CanShowIncludeGuildmatesToggle = function() return true end
        SS.IsIncludeGuildmatesEnabled = function() return true end
      end

      local logs = withSearchDebug(function()
        SD.ClearSearchCaches()
        SD.SearchGuildRecipes("healing")
      end)

      SD.GetAllGuildRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      if SS then
        SS.CanShowIncludeGuildmatesToggle = oldCan
        SS.IsIncludeGuildmatesEnabled = oldInc
      end

      local guildLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("guildRecipes q=", 1, true) then
          guildLog = msg
          break
        end
      end
      assert.is_truthy(guildLog, "expected guildRecipes timing log")
      assert.is_truthy(guildLog:find("lookup=", 1, true), guildLog)
      assert.is_truthy(guildLog:find("expand=", 1, true), guildLog)
      assert.is_truthy(guildLog:find("sort=", 1, true), guildLog)
      assert.is_truthy(guildLog:find("enrich=", 1, true), guildLog)
      assert.is_truthy(guildLog:find("filter=", 1, true), guildLog)
    end)

    it("logs lookup/expand/aggregate phases for SearchItems", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_, _char, cb)
        cb(0, 1, 111, 1, "item:111")
      end
      DS.IterateInventory = function() end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        return nil
      end

      local logs = withSearchDebug(function()
        SD.ClearSearchCaches()
        SD.SearchItems("potion", true)
      end)

      for k, v in pairs(old) do DS[k] = v end
      _G.GetItemInfo = oldGetItemInfo
      SD.ClearSearchCaches()

      local itemLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("items q=", 1, true) then
          itemLog = msg
          break
        end
      end
      assert.is_truthy(itemLog, "expected items timing log")
      assert.is_truthy(itemLog:find("lookup=", 1, true), itemLog)
      assert.is_truthy(itemLog:find("expand=", 1, true), itemLog)
      assert.is_truthy(itemLog:find("aggregate=", 1, true), itemLog)
    end)

    it("logs index build timing when building a cold item index", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_, _char, cb)
        cb(0, 1, 111, 1, "item:111")
      end
      DS.IterateInventory = function() end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        return nil
      end

      local logs = withSearchDebug(function()
        SD.ClearSearchCaches()
        SD.GetAllContainerSlots()
        SD.SearchItems("potion", true)
      end)

      for k, v in pairs(old) do DS[k] = v end
      _G.GetItemInfo = oldGetItemInfo
      SD.ClearSearchCaches()

      local indexLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("index items", 1, true) then
          indexLog = msg
          break
        end
      end
      assert.is_truthy(indexLog, "expected index items timing log")
    end)

    it("logs recipeUi sort/collapse sub-timings", function()
      local logs = withSearchDebug(function()
        local timings = SD.BeginUiTiming()
        assert.is_truthy(timings)
        SD.MarkUiTiming(timings, "sort")
        SD.MarkUiTiming(timings, "collapse")
        SD.LogRecipeUiTimings(timings, { nIn = 120, nOut = 40 })
      end)

      local uiLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("recipeUi ", 1, true) then
          uiLog = msg
          break
        end
      end
      assert.is_truthy(uiLog, "expected recipeUi timing log")
      assert.is_truthy(uiLog:find("sort=", 1, true), uiLog)
      assert.is_truthy(uiLog:find("collapse=", 1, true), uiLog)
      assert.is_truthy(uiLog:find("nIn=120", 1, true), uiLog)
      assert.is_truthy(uiLog:find("nOut=40", 1, true), uiLog)
    end)

    it("logs scrollPaint row counts when ending paint debug", function()
      local logs = withSearchDebug(function()
        local stats = SD.BeginScrollPaintDebug()
        assert.is_truthy(stats)
        SD.NoteScrollItemPaint(stats)
        SD.NoteScrollRecipePaint(stats)
        SD.NoteScrollTooltipPaint(stats)
        assert.is_true(SD.EndScrollPaintDebug(stats))
      end)

      local paintLog = nil
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("scrollPaint ", 1, true) then
          paintLog = msg
          break
        end
      end
      assert.is_truthy(paintLog, "expected scrollPaint timing log")
      assert.is_truthy(paintLog:find("itemRows=1", 1, true), paintLog)
      assert.is_truthy(paintLog:find("recipeRows=1", 1, true), paintLog)
      assert.is_truthy(paintLog:find("tooltipRows=1", 1, true), paintLog)
    end)
  end)

  describe("_PlainTooltipText", function()
    it("drops atlas icons, so a gold coin doesn't read as the word gold", function()
      -- WoW: Forever's Sell Price line, as the scan tooltip gives it.
      local line = "Sell Price: 1|A:coin-gold:14:14:2:0|a 77|A:coin-silver:14:14:2:0|a"
        .. " 84|A:coin-copper:14:14:2:0|a"
      local plain = SD._PlainTooltipText(line)
      assert.are.equal("Sell Price: 1 77 84", plain)
      assert.is_nil(plain:lower():find("gold", 1, true))
    end)

    it("drops texture icons, so an icon's file id doesn't match a number", function()
      assert.are.equal(" Small Radiant Shard", SD._PlainTooltipText("|T132884:16|t Small Radiant Shard"))
    end)

    it("drops classic and WoW: Forever colour codes but keeps the words", function()
      assert.are.equal("Binds when picked up", SD._PlainTooltipText("|cffffffffBinds when picked up|r"))
      assert.are.equal("- 10 Gold Ore", SD._PlainTooltipText("|cnIQ1:- 10 Gold Ore|r"))
    end)

    it("keeps a hyperlink's visible text and drops its link data", function()
      local line = "Teaches |cnIQ3:|Hitem:274606::::::::45:1482|h[Bloodspine Staff]|h|r."
      assert.are.equal("Teaches [Bloodspine Staff].", SD._PlainTooltipText(line))
    end)

    it("leaves plain text alone", function()
      assert.are.equal("Requires Level 36", SD._PlainTooltipText("Requires Level 36"))
    end)
  end)
end)
