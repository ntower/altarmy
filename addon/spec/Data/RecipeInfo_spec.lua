--[[
  Unit tests for RecipeInfo.lua (bundled recipe data: Data/Recipes/RecipeData_*.lua).
  Run from project root: npm test
]]

describe("RecipeInfo", function()
  local RI
  -- [spellID] = { profession, resultItemID, reqSkill, yellow, gray, source, recipeItemID }
  local FIXTURE = {
    [2963] = { "tailoring", 2996, 1, 25, 50, "starter", false },
    [26745] = { "tailoring", 21840, 300, 305, 325, "trainer", false },
    [27984] = { "enchanting", 0, 375, 385, 415, "drop", 22559 },
    [2543] = { "cooking", 733, 75, 115, 155, "quest|vendor", 728 },
    [13240] = { "engineering", 10577, 205, false, false, "trainer", false },
    [22813] = { "tailoring", 18258, 285, 285, 295, "trainer", false },
    [22815] = { "leatherworking", 18258, 285, 285, 295, "trainer", false },
    [7934] = { "firstAid", 6452, false, 80, 115, false, false },
  }
  local SPELL_NAMES = {
    [2963] = "Bolt of Linen Cloth",
    [26745] = "Bolt of Netherweave",
    [27984] = "Enchant Weapon - Mongoose",
    [2543] = "Westfall Stew",
    [13240] = "The Mortar: Reloaded",
    [22813] = "Gordok Ogre Suit",
    [22815] = "Gordok Ogre Suit",
    [7934] = "Anti-Venom",
    -- profession spells (localized names come from these)
    [3908] = "Tailoring",
    [7411] = "Enchanting",
    [2550] = "Cooking",
    [4036] = "Engineering",
    [2108] = "Leatherworking",
    [3273] = "First Aid",
  }

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Recipes/?.lua"
    require("RecipeInfo")
    RI = AltArmy.RecipeInfo
  end)

  before_each(function()
    AltArmy.RecipeData = { build = "test", client = "tbc", recipes = FIXTURE }
    _G.GetSpellInfo = function(id) return SPELL_NAMES[id] end
    RI.ClearCaches()
  end)

  describe("IsAvailable", function()
    it("is true when this client's recipe data loaded", function()
      assert.is_true(RI.IsAvailable())
    end)

    it("is false without recipe data", function()
      AltArmy.RecipeData = nil
      assert.is_false(RI.IsAvailable())
    end)
  end)

  describe("GetRecipe", function()
    it("returns named fields with unknown values as nil", function()
      assert.are.same({
        recipeID = 26745,
        professionKey = "tailoring",
        resultItemID = 21840,
        reqSkill = 300,
        yellow = 305,
        gray = 325,
        source = "trainer",
      }, RI.GetRecipe(26745))
      local antiVenom = RI.GetRecipe(7934)
      assert.is_nil(antiVenom.reqSkill)
      assert.is_nil(antiVenom.source)
      assert.are.equal(27984, RI.GetRecipe(27984).recipeID)
      assert.are.equal(22559, RI.GetRecipe(27984).recipeItemID)
    end)

    it("returns nil for an unknown spell", function()
      assert.is_nil(RI.GetRecipe(1))
      assert.is_nil(RI.GetRecipe(nil))
    end)
  end)

  describe("GetDifficulty", function()
    it("uses yellow, floored green midpoint and gray bands", function()
      local linen = RI.GetRecipe(2963)
      assert.are.equal("orange", RI.GetDifficulty(linen, 10))
      assert.are.equal("yellow", RI.GetDifficulty(linen, 25))
      assert.are.equal("yellow", RI.GetDifficulty(linen, 36))
      assert.are.equal("green", RI.GetDifficulty(linen, 37))
      assert.are.equal("gray", RI.GetDifficulty(linen, 50))
      local netherweave = RI.GetRecipe(26745)
      assert.are.equal("orange", RI.GetDifficulty(netherweave, 300))
      assert.are.equal("yellow", RI.GetDifficulty(netherweave, 305))
      assert.are.equal("green", RI.GetDifficulty(netherweave, 315))
      assert.are.equal("gray", RI.GetDifficulty(netherweave, 325))
    end)

    it("returns nil without bands", function()
      assert.is_nil(RI.GetDifficulty(RI.GetRecipe(13240), 300))
      assert.is_nil(RI.GetDifficulty(nil, 300))
    end)
  end)

  describe("EnrichEntry", function()
    it("sets skill, difficulty and source from the recipe", function()
      local entry = { professionName = "Tailoring", recipeID = 26745, skillRank = 310 }
      RI.EnrichEntry(entry)
      assert.are.equal(300, entry.recipeSkillRequired)
      assert.are.equal("yellow", entry.difficulty)
      assert.are.equal("trainer", entry.recipeSource)
      assert.are.equal(21840, entry.resultItemID)
    end)

    it("keeps an existing resultItemID", function()
      local entry = { professionName = "Tailoring", recipeID = 26745, resultItemID = 5, skillRank = 1 }
      RI.EnrichEntry(entry)
      assert.are.equal(5, entry.resultItemID)
    end)

    it("leaves unknown fields nil and still sets difficulty from bands", function()
      local entry = { professionName = "First Aid", recipeID = 7934, skillRank = 100 }
      RI.EnrichEntry(entry)
      assert.is_nil(entry.recipeSkillRequired)
      assert.is_nil(entry.recipeSource)
      assert.are.equal("green", entry.difficulty)
    end)

    it("clears fields for a recipe it does not know", function()
      local entry = {
        professionName = "Tailoring",
        recipeID = 1,
        skillRank = 300,
        recipeSkillRequired = 9,
        difficulty = "orange",
        recipeSource = "vendor",
      }
      RI.EnrichEntry(entry)
      assert.is_nil(entry.recipeSkillRequired)
      assert.is_nil(entry.difficulty)
      assert.is_nil(entry.recipeSource)
    end)

    it("falls back to the crafted item when the stored id is not the recipe spell", function()
      local entry = { professionName = "Cooking", recipeID = 999999, resultItemID = 733, skillRank = 120 }
      RI.EnrichEntry(entry)
      assert.are.equal(75, entry.recipeSkillRequired)
      assert.are.equal("yellow", entry.difficulty)
      assert.are.equal("quest|vendor", entry.recipeSource)
    end)

    it("ignores a spell id belonging to another profession", function()
      -- 26745 is Tailoring; a Cooking row whose id collides must not borrow its data
      local entry = { professionName = "Cooking", recipeID = 26745, skillRank = 300 }
      RI.EnrichEntry(entry)
      assert.is_nil(entry.recipeSkillRequired)
    end)

    it("picks the profession's copy when two professions craft the same item", function()
      local lw = { professionName = "Leatherworking", recipeID = 1, resultItemID = 18258, skillRank = 287 }
      RI.EnrichEntry(lw)
      assert.are.equal(285, lw.recipeSkillRequired)
      assert.are.equal("yellow", lw.difficulty)
    end)

    it("recomputes difficulty per skill rank from the cached recipe", function()
      local a = { professionName = "Tailoring", recipeID = 26745, skillRank = 320 }
      local b = { professionName = "Tailoring", recipeID = 26745, skillRank = 290 }
      RI.EnrichEntry(a)
      RI.EnrichEntry(b)
      assert.are.equal("green", a.difficulty)
      assert.are.equal("orange", b.difficulty)
    end)
  end)

  describe("RecipesFitProfession", function()
    it("trusts a list whose known recipes are the profession's", function()
      local fits, known, foreign = RI.RecipesFitProfession({ 2963, 26745 }, "tailoring")
      assert.is_true(fits)
      assert.are.equal(2, known)
      assert.are.equal(0, foreign)
    end)

    it("refuses a list that is mostly another profession's (a window not yet refreshed)", function()
      local fits, known, foreign = RI.RecipesFitProfession({ 7934, 2543 }, "tailoring")
      assert.is_false(fits)
      assert.are.equal(2, known)
      assert.are.equal(2, foreign)
      assert.is_false(RI.RecipesFitProfession({ 7934 }, "cooking"))
    end)

    it("lets a stray id through while the profession's own make up at least half", function()
      assert.is_true(RI.RecipesFitProfession({ 2963, 26745, 7934 }, "tailoring"))
      assert.is_true(RI.RecipesFitProfession({ 2963, 7934 }, "tailoring"))
    end)

    it("has nothing to say without data, a key, or any known id", function()
      assert.is_true(RI.RecipesFitProfession({}, "tailoring"))
      assert.is_true(RI.RecipesFitProfession({ 1, 2 }, "tailoring"))
      assert.is_true(RI.RecipesFitProfession({ 7934 }, nil))
      assert.is_true(RI.RecipesFitProfession(nil, "tailoring"))
      AltArmy.RecipeData = nil
      RI.ClearCaches()
      assert.is_true(RI.RecipesFitProfession({ 7934 }, "tailoring"))
    end)
  end)

  describe("SourceIncludes", function()
    it("matches any of a recipe's sources", function()
      assert.is_true(RI.SourceIncludes("quest|vendor", { vendor = true }))
      assert.is_true(RI.SourceIncludes("quest|vendor", { quest = true, vendor = false }))
      assert.is_false(RI.SourceIncludes("quest|vendor", { quest = false, vendor = false, drop = true }))
      assert.is_true(RI.SourceIncludes("trainer", { trainer = true }))
    end)
  end)

  describe("FindRecipeLearnInfo", function()
    it("resolves by recipe spell id with the localized profession name", function()
      _G.GetSpellInfo = function(id)
        if id == 3908 then return "Schneiderei" end
        return SPELL_NAMES[id]
      end
      assert.are.same(
        { professionName = "Schneiderei", professionKey = "tailoring", recipeID = 26745, resultItemID = 21840 },
        RI.FindRecipeLearnInfo(26745, nil)
      )
    end)

    it("resolves by crafted item id", function()
      local info = RI.FindRecipeLearnInfo(733, nil)
      assert.are.equal("Cooking", info.professionName)
      assert.are.equal(2543, info.recipeID)
    end)

    it("leaves resultItemID nil for an enchant", function()
      local info = RI.FindRecipeLearnInfo(nil, "Enchant Weapon - Mongoose")
      assert.are.same(
        { professionName = "Enchanting", professionKey = "enchanting", recipeID = 27984, resultItemID = nil },
        info
      )
    end)

    it("resolves by the client's (localized) recipe name", function()
      _G.GetSpellInfo = function(id)
        if id == 26745 then return "Netherstoffballen" end
        return SPELL_NAMES[id]
      end
      local info = RI.FindRecipeLearnInfo(nil, "Netherstoffballen")
      assert.are.equal(26745, info.recipeID)
      assert.are.equal("Tailoring", info.professionName)
    end)

    it("prefers a profession the character has when a name is shared", function()
      local info = RI.FindRecipeLearnInfo(nil, "Gordok Ogre Suit", { Leatherworking = true })
      assert.are.equal(22815, info.recipeID)
      info = RI.FindRecipeLearnInfo(nil, "Gordok Ogre Suit", { Tailoring = true })
      assert.are.equal(22813, info.recipeID)
    end)

    it("names recipes through C_Spell when legacy GetSpellInfo is absent (Forever)", function()
      _G.GetSpellInfo = nil
      _G.C_Spell = {
        GetSpellInfo = function(id)
          return SPELL_NAMES[id] and { name = SPELL_NAMES[id] } or nil
        end,
      }
      local info = RI.FindRecipeLearnInfo(nil, "Bolt of Netherweave")
      _G.C_Spell = nil
      assert.are.equal(26745, info.recipeID)
      assert.are.equal("Tailoring", info.professionName)
    end)

    it("returns nil for an unknown recipe or without data", function()
      assert.is_nil(RI.FindRecipeLearnInfo(1, "Not A Real Recipe"))
      AltArmy.RecipeData = nil
      RI.ClearCaches()
      assert.is_nil(RI.FindRecipeLearnInfo(26745, "Bolt of Netherweave"))
    end)
  end)

  describe("FormatSkillCell", function()
    it("returns player skill only when recipe level unknown", function()
      assert.are.equal("375", RI.FormatSkillCell(nil, 375, nil))
      assert.are.equal("375", RI.FormatSkillCell(80240, 375, "orange"))
      assert.are.equal("—", RI.FormatSkillCell(nil, 0, nil))
    end)

    it("returns colored recipe/player when recipe level known", function()
      local text = RI.FormatSkillCell(180, 375, "yellow")
      assert.is_truthy(text:find("180", 1, true))
      assert.is_truthy(text:find("|cffffff00", 1, true))
      assert.is_truthy(text:find("|r/375", 1, true))
    end)
  end)

  describe("PickHardestDifficulty", function()
    it("returns nil for empty or unknown values", function()
      assert.is_nil(RI.PickHardestDifficulty(nil))
      assert.is_nil(RI.PickHardestDifficulty({}))
      assert.is_nil(RI.PickHardestDifficulty({ nil, "unknown" }))
    end)

    it("picks orange over yellow/green/gray", function()
      assert.are.equal("orange", RI.PickHardestDifficulty({ "gray", "orange", "yellow" }))
      assert.are.equal("yellow", RI.PickHardestDifficulty({ "green", "yellow", "gray" }))
      assert.are.equal("green", RI.PickHardestDifficulty({ "gray", "green" }))
      assert.are.equal("gray", RI.PickHardestDifficulty({ "gray" }))
    end)
  end)

  describe("FormatCollapsedSkillCell", function()
    it("returns * when recipe level unknown", function()
      assert.are.equal("*", RI.FormatCollapsedSkillCell(nil, "orange"))
      assert.are.equal("*", RI.FormatCollapsedSkillCell(80240, "orange"))
    end)

    it("returns colored required skill over ***", function()
      assert.are.equal("|cffff8040180|r/***", RI.FormatCollapsedSkillCell(180, "orange"))
      assert.are.equal("|cffffff00180|r/***", RI.FormatCollapsedSkillCell(180, "yellow"))
      assert.are.equal("|cff40ff40180|r/***", RI.FormatCollapsedSkillCell(180, "green"))
      assert.are.equal("|cff808080180|r/***", RI.FormatCollapsedSkillCell(180, "gray"))
    end)

    it("uses white when difficulty is missing", function()
      assert.are.equal("|cffffffff180|r/***", RI.FormatCollapsedSkillCell(180, nil))
    end)
  end)
end)
