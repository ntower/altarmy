--[[
  Unit tests for Text.lua (TruncateFontString).
  Run from project root: npm test
]]

describe("Text", function()
  local Text

  local function mockFontString()
    local text = ""
    return {
      SetText = function(_, value)
        text = value or ""
      end,
      GetText = function()
        return text
      end,
      GetStringWidth = function()
        return #text * 8
      end,
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("Text")
    Text = AltArmy.Text
  end)

  it("counts and cuts shown characters past colour codes", function()
    local s = "|cff40c7ebMage|r, |cfffff468Rogue|r"
    assert.are.equal(11, Text.VisibleLength(s))
    assert.are.equal("|cff40c7ebMa|r", Text.CutVisible(s, 2))
    assert.are.equal("|cff40c7ebMage|r, ", Text.CutVisible(s, 6))
    assert.are.equal("|cff40c7ebMage|r, |cfffff468R|r", Text.CutVisible(s, 7))
    assert.are.equal(s, Text.CutVisible(s, 20))
  end)

  it("never truncates inside a colour code of several", function()
    local fs = mockFontString()
    local s = "|cff40c7ebMage|r, |cfffff468Rogue|r, |cfffff468Rogue|r"
    assert.is_true(Text.TruncateFontString(fs, s, 250, { returnBoolean = true }))
    local text = fs:GetText()
    assert.is_truthy(text:find("...", 1, true))
    local bare, opens = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    assert.is_nil(bare:find("|c", 1, true), text) -- every |c starts a whole code
    assert.are.equal(opens, select(2, text:gsub("|r", "")))
  end)

  it("returns full text when it fits", function()
    local fs = mockFontString()
    local out = Text.TruncateFontString(fs, "Bob", 100)
    assert.are.equal("Bob", out)
    assert.are.equal("Bob", fs:GetText())
  end)

  it("truncates with ellipsis when too wide", function()
    local fs = mockFontString()
    local out = Text.TruncateFontString(fs, "LongNameHere", 10)
    assert.are.equal("...", out)
  end)

  it("returnBoolean reports truncation", function()
    local fs = mockFontString()
    assert.is_false(Text.TruncateFontString(fs, "Short", 100, { returnBoolean = true }))
    assert.is_true(Text.TruncateFontString(fs, "LongNameHere", 10, { returnBoolean = true }))
  end)

  it("preserves color codes and optional suffix", function()
    local fs = mockFontString()
    local colored = "|cff00ff00LongCharacterName|r"
    Text.TruncateFontString(fs, colored, 80, {
      preserveColorCodes = true,
      suffix = "|cffffffff (Bags)|r",
    })
    local text = fs:GetText()
    assert.is_true(text:find("|cff00ff00", 1, true) ~= nil)
    assert.is_true(text:find("|r", 1, true) ~= nil)
    assert.is_true(text:find("(Bags)", 1, true) ~= nil)
  end)

  it("truncates item name but keeps icon prefix and count suffix", function()
    local fs = mockFontString()
    local iconPrefix = "|TInterface\\Icons\\INV_Misc_QuestionMark:0|t "
    local countSuffix = " x1"
    local name = "Archer's Shoulderpads of Agility"
    Text.TruncateFontString(fs, name, 120, {
      prefix = iconPrefix,
      suffix = countSuffix,
    })
    local text = fs:GetText()
    assert.is_true(text:sub(1, #iconPrefix) == iconPrefix)
    assert.is_true(text:sub(-#countSuffix) == countSuffix)
    assert.is_true(text:find("...", 1, true) ~= nil)
    assert.is_false(text:find(name, 1, true) ~= nil)
  end)
end)
