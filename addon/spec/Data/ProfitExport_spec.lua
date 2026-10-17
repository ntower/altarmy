--[[
  Unit tests for ProfitExport.lua: the string the Alt Army website's Upload tab takes.
  Run from project root: npm test

  spec/fixtures/profit_export_v2.txt is the golden export of CHARACTERS below. The site's tests (site/tests,
  test_paste.py and others) read that same file, so its parser must read back any change made here.
]]

local CHARACTERS = {
  Dreamscythe = {
    -- keyed by GUID (character data v3); the name is the entry's `name`
    ["Player-5826-0A1B2C3D"] = {
      name = "Frell Ofelements",
      guid = "Player-5826-0A1B2C3D",
      faction = "Horde",
      classFile = "MAGE",
      level = 70,
      Professions = {
        Tailoring = {
          rank = 375,
          maxRank = 375,
          Recipes = {
            [26745] = { color = 1, primaryRecipeID = 26745 },
            [26746] = { color = 2, primaryRecipeID = 26746, resultItemID = 21845 },
            [31460] = { color = 2, primaryRecipeID = 26746 }, -- an alias of 26746
          },
        },
        Enchanting = {
          rank = 300,
          maxRank = 375,
          Recipes = {
            [7418] = { color = 3 }, -- Enchanting rows carry only a color
            [7420] = 2, -- a pre-migration row
          },
        },
        Cooking = { rank = 1, maxRank = 75 },
      },
      legacyTalents = { spells = { [1225459] = 2, [1225457] = 3, [1225478] = 0 }, nodes = {}, restRank = 0 },
      -- only the city factions are exported: not the Darkmoon Faire (909), nor a pre-v2 scalar row (68) or a
      -- standing the game doesn't have (81)
      Reputations = {
        [530] = { s = 5, e = 100, b = 3000, t = 9000 },
        [76] = { s = 6, e = 1200, b = 9000, t = 21000 },
        [909] = { s = 8, e = 0, b = 42000, t = 43000 },
        [68] = 4500,
        [81] = { s = 12 },
      },
    },
    -- saved before GUIDs: keyed by name, which the entry also carries
    Alchemist = { name = "Alchemist", faction = "Horde", classFile = "ROGUE", level = 12 },
  },
  ["Classic Beta PvE"] = {
    -- never scanned: no faction, no professions; v1 legacy talents (class talents really) aren't exported
    ["Tailor Guy"] = { classFile = "PRIEST", level = 20, legacyTalents = { nodes = { [105955] = 2 } } },
  },
}

local ACCOUNT = "0a1b2c3d4e5f6789"

local LINES = table.concat({
  "V|2|20506|2.5.6.69795|" .. ACCOUNT,
  "C|Classic Beta PvE|Tailor Guy||PRIEST|20|",
  "C|Dreamscythe|Alchemist|Horde|ROGUE|12|",
  "C|Dreamscythe|Frell Ofelements|Horde|MAGE|70|Player-5826-0A1B2C3D",
  "P|Cooking|1|75|",
  "P|Enchanting|300|375|7418,7420",
  "P|Tailoring|375|375|26745,26746",
  "T|1225457|3",
  "T|1225459|2",
  "R|76|6",
  "R|530|5",
}, "\n")

describe("ProfitExport", function()
  local ProfitExport, LibDeflate

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Libs/LibDeflate/?.lua"
    LibDeflate = require("LibDeflate")
    require("ProfitExport")
    ProfitExport = AltArmy.ProfitExport
  end)

  it("names characters by their name and identifies them by GUID, sorted by name", function()
    assert.are.equal(LINES, ProfitExport.Lines(CHARACTERS, 20506, "2.5.6.69795", ACCOUNT))
  end)

  it("resolves recipe aliases to their primary recipe id", function()
    local text = ProfitExport.Lines(CHARACTERS, 20506, "2.5.6.69795", ACCOUNT)
    assert.is_nil(text:find("31460", 1, true))
  end)

  it("drops separators from names so a line always splits the same way", function()
    local odd = { ["Realm|X"] = { ["A\nB"] = { faction = "Horde", classFile = "MAGE", level = 1 } } }
    assert.are.equal("V|2|16001|1.60.1\nC|RealmX|AB|Horde|MAGE|1|", ProfitExport.Lines(odd, 16001, "1.60.1"))
  end)

  it("exports nothing but the version line without characters", function()
    assert.are.equal("V|2|16001|1.60.1", ProfitExport.Lines(nil, 16001, "1.60.1"))
  end)

  it("names the WoW account on the version line when it has an id", function()
    assert.are.equal("V|2|16001|1.60.1|abc", ProfitExport.Lines(nil, 16001, "1.60.1", "abc"))
    assert.are.equal("V|2|16001|1.60.1", ProfitExport.Lines(nil, 16001, "1.60.1", ""))
  end)

  it("encodes as AAX1: plus LibDeflate's printable raw DEFLATE, matching the golden fixture", function()
    local encoded = ProfitExport.Encode(LINES, LibDeflate)
    assert.are.equal("AAX1:", encoded:sub(1, 5))
    assert.are.equal(LINES, LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(encoded:sub(6))))
    local f = assert(io.open("spec/fixtures/profit_export_v2.txt", "rb"))
    local golden = f:read("*a"):gsub("%s+$", "")
    f:close()
    assert.are.equal(golden, encoded)
  end)
  describe("MissingData", function()
    local function missingFn(names)
      return function(char)
        return { instructions = names[char.name] or {} }
      end
    end

    it("lists characters with missing data in the export's order, without the bullet, realm when several", function()
      local rows = ProfitExport.MissingData(CHARACTERS, missingFn({
        ["Frell Ofelements"] = { "* Open your Tailoring window", "* Log in with this character" },
        Alchemist = { "* Log in with this character" },
      }))
      assert.are.same({
        { label = "Alchemist (Dreamscythe)", instructions = { "Log in with this character" } },
        {
          label = "Frell Ofelements (Dreamscythe)",
          instructions = { "Open your Tailoring window", "Log in with this character" },
        },
      }, rows)
    end)

    it("names characters without the realm when there is only one, and leaves out never-scanned stubs", function()
      local chars = {
        R1 = {
          A = { name = "A", faction = "Horde", classFile = "MAGE" },
          Stub = { name = "Stub" },
        },
      }
      local all = function() return { instructions = { "* Log in with this character" } } end
      assert.are.same(
        { { label = "A", instructions = { "Log in with this character" } } },
        ProfitExport.MissingData(chars, all)
      )
    end)

    it("is empty when nothing is missing or there is no check", function()
      assert.are.same({}, ProfitExport.MissingData(CHARACTERS, missingFn({})))
      assert.are.same({}, ProfitExport.MissingData(CHARACTERS, nil))
    end)

    it("words the warning one line per character, capped with how many more", function()
      local rows = {
        { label = "A", instructions = { "Log in with this character" } },
        { label = "B", instructions = { "Open your Tailoring window", "Open your Reputation panel" } },
        { label = "C", instructions = { "Log in with this character" } },
        { label = "D", instructions = { "Log in with this character" } },
      }
      assert.are.equal("", ProfitExport.MissingDataText({}, 2))
      assert.are.equal(table.concat({
        "Some data has not been gathered yet, so this export lacks it:",
        "A: Log in with this character",
        "B: Open your Tailoring window; Open your Reputation panel",
        "...and 2 more characters",
      }, "\n"), ProfitExport.MissingDataText(rows, 2))
      assert.is_truthy(ProfitExport.MissingDataText(rows, 3):find("and 1 more character$"))
    end)
  end)
end)
