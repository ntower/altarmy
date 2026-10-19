--[[
  Unit tests for MainTabs.lua (main window tab registry).
  Run from project root: npm test
]]

describe("MainTabs", function()
  local MainTabs

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("MainTabs")
    MainTabs = AltArmy.MainTabs
  end)

  it("lists the side tabs in display order with Guild last", function()
    assert.are.same(
      { "Summary", "Economy", "Gear", "Inventory", "Reputation", "Cooldowns", "Graph", "Guild" },
      MainTabs.ORDER
    )
  end)

  it("gives every tab (and Search) a label and an icon path", function()
    for _, name in ipairs(MainTabs.ORDER) do
      local def = MainTabs.Get(name)
      assert.is_table(def)
      assert.are.equal(name, def.name)
      assert.is_string(def.label)
      assert.truthy(def.icon:match("^Interface\\Icons\\")
        or def.icon:match("^Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\"))
    end
    assert.is_string(MainTabs.Get("Search").icon)
  end)

  it("shows the toolbar item/recipe search only on Summary", function()
    for _, name in ipairs(MainTabs.ORDER) do
      assert.are.equal(name == "Summary", MainTabs.Get(name).headerSearch == true, name)
    end
  end)

  describe("native side-tab icons", function()
    local savedProject, savedMainline

    local function reload(project)
      _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = project, 1
      package.loaded["MainTabs"] = nil
      AltArmy.MainTabs = nil
      require("MainTabs")
      return AltArmy.MainTabs
    end

    before_each(function()
      savedProject, savedMainline = _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE
    end)

    after_each(function()
      _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = savedProject, savedMainline
      MainTabs = reload(savedProject)
    end)

    it("uses the CharacterFrame Reputation / Statistics tab icons on Forever", function()
      local tabs = reload(1)
      assert.are.equal("Interface\\Icons\\INV_SideTab_Reputation2_c60", tabs.Get("Reputation").icon)
      assert.are.equal("Interface\\Icons\\INV_SideTab_Stats_c60", tabs.Get("Graph").icon)
    end)

    it("uses the bundled copies of those icons on TBC Anniversary, which lacks the files", function()
      local tabs = reload(5)
      assert.are.equal(
        "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\INV_SideTab_Reputation2_c60",
        tabs.Get("Reputation").icon)
      assert.are.equal(
        "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\INV_SideTab_Stats_c60",
        tabs.Get("Graph").icon)
    end)

    it("ships the bundled icon files", function()
      for _, name in ipairs({ "INV_SideTab_Reputation2_c60", "INV_SideTab_Stats_c60" }) do
        local f = io.open("AltArmy_TBC/Textures/Icons/" .. name .. ".blp", "rb")
        assert.is_not_nil(f, name)
        assert.are.equal("BLP2", f:read(4))
        f:close()
      end
    end)

    it("keeps stock game icons for tabs without a native side-tab icon", function()
      assert.are.equal("Interface\\Icons\\INV_Misc_PocketWatch_01", reload(5).Get("Cooldowns").icon)
    end)

    it("marks the Guild tab to show the guild crest", function()
      assert.is_true(reload(1).Get("Guild").guildCrest)
      assert.are.equal("Interface\\Icons\\INV_Shirt_GuildTabard_01", MainTabs.Get("Guild").icon)
    end)
  end)

  it("labels Graph as Graphs", function()
    assert.are.equal("Graphs", MainTabs.Get("Graph").label)
  end)

  it("returns nil for unknown tabs", function()
    assert.is_nil(MainTabs.Get("Characters"))
    assert.is_nil(MainTabs.Get(nil))
  end)

  describe("Title", function()
    it("prefixes the addon name", function()
      assert.are.equal("Alt Army - Reputation", MainTabs.Title("Reputation"))
      assert.are.equal("Alt Army - Graphs", MainTabs.Title("Graph"))
      assert.are.equal("Alt Army - Search", MainTabs.Title("Search"))
    end)

    it("falls back to the bare addon name", function()
      assert.are.equal("Alt Army", MainTabs.Title("Nope"))
    end)
  end)

  describe("slash commands", function()
    it("names every side tab's command, spelled /alta, and fills it in on the def", function()
      assert.are.equal("/alta summary", MainTabs.SlashCommand("Summary"))
      assert.are.equal("/alta graphs", MainTabs.SlashCommand("Graph"))
      assert.are.equal("/alta guild", MainTabs.Get("Guild").command)
      for _, name in ipairs(MainTabs.ORDER) do
        assert.is_string(MainTabs.Get(name).command, name)
      end
    end)

    it("names sub-view commands by their words, not their view names", function()
      assert.are.equal("/alta economy crates", MainTabs.SlashCommand("Economy", "waylaid"))
      assert.are.equal("/alta cooldowns dungeons", MainTabs.SlashCommand("Cooldowns", "raids"))
      assert.are.equal("/alta inventory mail", MainTabs.SlashCommand("Inventory", "mail"))
      assert.are.equal("/alta gear upgrade", MainTabs.SlashCommand("Gear", "upgrade"))
    end)

    it("has no command for Search, unknown tabs or views, or the Guild tab's professions", function()
      assert.is_nil(MainTabs.SlashCommand("Search"))
      assert.is_nil(MainTabs.SlashCommand("Nope"))
      assert.is_nil(MainTabs.SlashCommand("Economy", "nope"))
      assert.is_nil(MainTabs.SlashCommand("Guild", "alchemy"))
    end)

    it("names a frame setter for every tab with views", function()
      for _, name in ipairs(MainTabs.ORDER) do
        local def = MainTabs.Get(name)
        assert.are.equal(def.views ~= nil, def.setView ~= nil, name)
      end
    end)

    describe("ParseSlash", function()
      local function parse(msg) return { MainTabs.ParseSlash(msg) } end

      it("reads a tab alone", function()
        assert.are.same({ "Economy", nil, true }, parse("economy"))
        assert.are.same({ "Graph", nil, true }, parse("graphs"))
      end)

      it("reads a tab and view in any case and spacing", function()
        assert.are.same({ "Economy", "waylaid", true }, parse("ECONOMY  Crates"))
        assert.are.same({ "Cooldowns", "raids", true }, parse("cooldowns dungeons"))
      end)

      it("takes a plural word without its s", function()
        assert.are.same({ "Graph", nil, true }, parse("graph"))
        assert.are.same({ "Cooldowns", "raids", true }, parse("cooldown dungeon"))
        assert.are.same({ "Economy", "waylaid", true }, parse("economy crate"))
        assert.are.same({ "Economy", "writs", true }, parse("economy writ"))
        assert.are.same({ "Inventory", "bags", true }, parse("inventory bag"))
      end)

      it("marks an unknown view or extra words invalid", function()
        assert.are.same({ "Economy", nil, false }, parse("economy foo"))
        assert.are.same({ "Economy", nil, false }, parse("economy crates now"))
        assert.are.same({ "Summary", nil, false }, parse("summary grid"))
        assert.are.same({ "Guild", nil, false }, parse("guild alchemy"))
      end)

      it("leaves other commands alone", function()
        assert.is_nil(MainTabs.ParseSlash(""))
        assert.is_nil(MainTabs.ParseSlash(nil))
        assert.is_nil(MainTabs.ParseSlash("scan"))
        assert.is_nil(MainTabs.ParseSlash("debug on"))
        assert.is_nil(MainTabs.ParseSlash("search"))
      end)
    end)
  end)

  describe("settings", function()
    it("describes toggle-panel settings by frame method names", function()
      local s = MainTabs.Get("Gear").settings
      assert.are.equal("ToggleGearSettings", s.toggle)
      assert.are.equal("IsGearSettingsShown", s.isShown)
      assert.are.equal("ToggleSearchSettings", MainTabs.Get("Search").settings.toggle)
    end)

    it("routes Cooldowns settings to Interface Options", function()
      assert.are.equal("cooldowns", MainTabs.Get("Cooldowns").settings.optionsKey)
    end)

    it("routes Economy settings to its Currency view, only while that view is available", function()
      local s = MainTabs.Get("Economy").settings
      assert.are.equal("ToggleEconomySettings", s.toggle)
      assert.are.equal("IsEconomySettingsShown", s.isShown)
      assert.are.equal("IsEconomySettingsAvailable", s.isAvailable)
    end)

    it("routes Graph settings to its right column", function()
      local s = MainTabs.Get("Graph").settings
      assert.are.equal("ToggleGraphSettings", s.toggle)
      assert.are.equal("IsGraphSettingsShown", s.isShown)
    end)

    it("has no settings for Inventory or Guild", function()
      assert.is_nil(MainTabs.Get("Inventory").settings)
      assert.is_nil(MainTabs.Get("Guild").settings)
    end)
  end)
end)
