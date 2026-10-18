--[[
  Font role conventions (Theme.FONTS) — see docs/UI_DESIGN.md "Typography".
  Run from project root: npm test
]]

describe("Theme.FONTS", function()
  local Theme

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["Theme"] = nil
    require("Theme")
    Theme = AltArmy.Theme
  end)

  it("maps native 12pt roles like Blizzard's Character / Reputation panels", function()
    assert.are.equal("GameFontNormal", Theme.BASE_FONTS.heading)
    assert.are.equal("GameFontHighlight", Theme.BASE_FONTS.body)
    assert.are.equal("GameFontDisable", Theme.BASE_FONTS.muted)
    assert.are.equal("GameFontNormalMed3", Theme.BASE_FONTS.title)
  end)

  it("uses a larger gray font for centered empty-state messages", function()
    assert.are.equal("GameFontDisableLarge", Theme.BASE_FONTS.emptyState)
  end)

  it("draws item slot stack counts with the stock outlined number font", function()
    assert.are.equal("NumberFontNormal", Theme.BASE_FONTS.count)
  end)

  it("has no 10pt text roles; only icon badges stay Small", function()
    for _, role in ipairs({ "gridCell", "gridHeader", "gridMuted", "fineprint", "smallButton" }) do
      assert.is_nil(Theme.BASE_FONTS[role], role)
      assert.is_nil(Theme.FONTS[role], role)
    end
    assert.are.equal("GameFontNormalSmall", Theme.BASE_FONTS.badge)
  end)

  it("uses the Blizzard fonts themselves where no font object can be made", function()
    assert.are.same(Theme.BASE_FONTS, Theme.FONTS)
    assert.are.equal(12, Theme.DEFAULT_FONT_SIZE)
    Theme.ApplyFontSize() -- nothing to size: no error
  end)

  it("scales each role's size by the body's ratio, in whole points", function()
    assert.are.equal(12, Theme.FontSizeFor(12, 12, 12))
    assert.are.equal(18, Theme.FontSizeFor(12, 18, 12))
    assert.are.equal(30, Theme.FontSizeFor(20, 18, 12))
    assert.are.equal(8, Theme.FontSizeFor(10, 9, 12))
    assert.are.equal(1, Theme.FontSizeFor(1, 9, 12))
  end)

  describe("with the game's fonts", function()
    local fonts, OwnTheme

    local function stubFont(size, flags)
      return {
        GetFont = function() return "Fonts\\FRIZQT__.TTF", size, flags end,
      }
    end

    setup(function()
      fonts = {}
      for role, base in pairs(Theme.BASE_FONTS) do
        local size = ({ pageTitle = 20, headline = 16, title = 14, emptyState = 16, badge = 10, count = 14 })[role]
        _G[base] = stubFont(size or 12, role == "count" and "OUTLINE" or "")
      end
      _G.CreateFont = function(name)
        local font = { name = name }
        function font:SetFontObject(base) self.base = base end
        function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
        fonts[name] = font
        return font
      end
      _G.AltArmyTBC_Options = {}
      package.loaded["Theme"] = nil
      require("Theme")
      OwnTheme = AltArmy.Theme
    end)

    teardown(function()
      for _, base in pairs(Theme.BASE_FONTS) do
        _G[base] = nil
      end
      _G.CreateFont = nil
      _G.AltArmyTBC_Options = nil
      package.loaded["Theme"] = nil
      require("Theme")
    end)

    it("makes a font object per role from its Blizzard font", function()
      assert.are.equal("AltArmyFont_body", OwnTheme.FONTS.body)
      assert.are.equal("AltArmyFont_count", OwnTheme.FONTS.count)
      assert.are.equal(_G.GameFontHighlight, fonts.AltArmyFont_body.base)
      assert.are.equal(12, fonts.AltArmyFont_body.size)
      assert.are.equal("OUTLINE", fonts.AltArmyFont_count.flags)
      assert.are.equal(12, OwnTheme.DEFAULT_FONT_SIZE)
    end)

    it("SetFontSize resizes every role by the body's ratio and saves all but the default", function()
      OwnTheme.SetFontSize(18)
      assert.are.equal(18, _G.AltArmyTBC_Options.fontSize)
      assert.are.equal(18, fonts.AltArmyFont_body.size)
      assert.are.equal(18, fonts.AltArmyFont_heading.size)
      assert.are.equal(30, fonts.AltArmyFont_pageTitle.size)
      assert.are.equal(15, fonts.AltArmyFont_badge.size)
      assert.are.equal(21, fonts.AltArmyFont_count.size)
      assert.are.equal(18, OwnTheme.GetFontSize())

      OwnTheme.SetFontSize(12)
      assert.is_nil(_G.AltArmyTBC_Options.fontSize)
      assert.are.equal(12, fonts.AltArmyFont_body.size)
      assert.are.equal(10, fonts.AltArmyFont_badge.size)
    end)

    it("clamps what is saved and applied to the slider's range", function()
      _G.AltArmyTBC_Options.fontSize = 40
      assert.are.equal(18, OwnTheme.GetFontSize())
      OwnTheme.SetFontSize(2)
      assert.are.equal(9, _G.AltArmyTBC_Options.fontSize)
      assert.are.equal(9, fonts.AltArmyFont_body.size)
      _G.AltArmyTBC_Options.fontSize = "big"
      assert.are.equal(12, OwnTheme.GetFontSize())
      OwnTheme.ApplyFontSize()
      assert.are.equal(12, fonts.AltArmyFont_body.size)
    end)
  end)

  -- Modules loaded by their own specs with a stub Theme keep literals equal to their role.
  local ALLOWED = {
    ["AltArmy_TBC/UI/Theme.lua"] = true,
    ["AltArmy_TBC/UI/ScoreSortRow.lua"] = true,         -- body
    ["AltArmy_TBC/UI/GraphCore.lua"] = true,            -- muted
    ["AltArmy_TBC/UI/QuestRewardIndicators.lua"] = true, -- badge
  }

  local function luaFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd = isWindows and 'dir /s /b "AltArmy_TBC\\*.lua"' or 'find AltArmy_TBC -name "*.lua"'
    local pipe = io.popen(cmd)
    for line in pipe:lines() do
      local rel = line:gsub("\\", "/"):match("(AltArmy_TBC/.+)$")
      if rel and not rel:match("^AltArmy_TBC/Libs/") and not rel:match("^AltArmy_TBC/ForeverSVFixData/") then
        files[#files + 1] = rel
      end
    end
    pipe:close()
    return files
  end

  it("is used instead of GameFont literals in UI code", function()
    local offenders = {}
    local files = luaFiles()
    assert.is_true(#files > 20)
    for _, rel in ipairs(files) do
      if not ALLOWED[rel] then
        local f = assert(io.open(rel, "r"))
        local n = 0
        for line in f:lines() do
          n = n + 1
          if line:find('"GameFont%a*"') then
            offenders[#offenders + 1] = rel .. ":" .. n
          end
        end
        f:close()
      end
    end
    assert.are.same({}, offenders)
  end)
end)
