--[[
  Unit tests for TopTabs.lua (spellbook-style tabs hanging above a panel).
  Run from project root: npm test
]]

describe("TopTabs", function()
  local TopTabs
  local saved
  local GLOBALS = { "CreateFrame", "CreateFramePool", "GameTooltip" }
  local created

  local function stubFrame(kind, template)
    local f = { kind = kind, template = template, points = {}, scripts = {}, shown = true }
    function f:SetPoint(...) table.insert(self.points, { ... }) end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript(k, fn)
      local prev = self.scripts[k]
      self.scripts[k] = function(...)
        if prev then prev(...) end
        fn(...)
      end
    end
    function f:SetText(t) self.text = t end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    table.insert(created, f)
    return f
  end

  local function tabSystemStub(f)
    f.tabs = {}
    function f:SetTabSelectedCallback(cb) self.cb = cb end
    function f:AddTab(text, icon)
      local btn = stubFrame("Button", self.tabTemplate)
      btn.tabText, btn.tabIcon, btn.initIcon = text, icon, icon
      function btn:SetTooltipText(t) self.tooltipText = t end
      -- What Blizzard's Init(tabID, text, icon) would do with an icon: SetSquareMode, which writes a
      -- variable shared by every tab system (tainting it when an addon calls it).
      function btn:SetSquareMode()
        error("SetSquareMode taints Blizzard's shared tab spacing; TopTabs must draw the square look itself")
      end
      if icon then btn:SetSquareMode(true) end
      local function texture()
        local t = { shown = true }
        function t:Hide() self.shown = false end
        function t:Show() self.shown = true end
        function t:SetTexture(x) self.texture = x end
        function t:SetAtlas(a, useSize) self.atlas, self.useAtlasSize = a, useSize end
        function t:GetWidth() return 30 end
        return t
      end
      btn.Icon, btn.IconMask = texture(), texture()
      btn.Icon.shown, btn.IconMask.shown = false, false
      btn.SquareBackground, btn.SquareBackgroundActive, btn.SquareBackgroundActiveGlow = texture(), texture(), texture()
      for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
        "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
        btn[key] = texture()
      end
      function btn:SetTabSelected(on) self.isSelected = on end
      function btn:SetTabWidth(w) self.tabWidth = w end
      btn.scripts.OnEnter = function(self) -- TabSystemTopButtonTemplate's own tooltip
        GameTooltip:SetOwner(self)
        GameTooltip:SetText(self.tooltipText)
      end
      table.insert(self.tabs, btn)
      return #self.tabs
    end
    function f:GetTabButton(id) return self.tabs[id] end
    function f:SetTabVisuallySelected(id) self.selectedID = id end
    function f:SetTab(id, isUser)
      if not self.cb(id, isUser) then self:SetTabVisuallySelected(id) end
    end
  end

  local defs = {
    { name = "crafting", label = "Crafting", icon = "Interface\\Icons\\Trade_Alchemy" },
    { name = "raids", label = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_13" },
  }

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("MainTabs")
    require("TabTooltip")
    require("TopTabs")
    TopTabs = AltArmy.TopTabs
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    created = {}
    _G.CreateFrame = function(kind, _, _, template)
      local f = stubFrame(kind, template)
      if template == "TabSystemTemplate" then tabSystemStub(f) end
      return f
    end
    _G.CreateFramePool = function(_, _, template) return { template = template } end
    _G.GameTooltip = {
      lines = {},
      SetOwner = function(self, owner) self.owner, self.lines = owner, {} end,
      IsOwned = function(self, owner) return self.owner == owner end,
      SetText = function(self, t) self.text = t end,
      AddLine = function(self, t, r, g, b) table.insert(self.lines, { t, r, g, b }) end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.owner, self.shown = nil, false end,
    }
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  it("builds square icon tabs on the Forever TabSystem, with names as tooltips", function()
    local tabs = TopTabs.Create({}, defs, { caps = { topTabs = true, iconTabs = true } })
    local sys = tabs.frame
    assert.are.equal("TabSystemTemplate", sys.template)
    assert.are.equal("TabSystemTopButtonTemplate", sys.tabPool.template)
    assert.is_nil(sys.tabs[1].tabText)
    assert.are.equal("Interface\\Icons\\Trade_Alchemy", sys.tabs[1].tabIcon)
    assert.are.equal("Dungeons", sys.tabs[2].tooltipText)
  end)

  it("draws the square icon look itself, never through Blizzard's SetSquareMode (shared state, taint)", function()
    local tabs = TopTabs.Create({}, defs, { caps = { topTabs = true, iconTabs = true } })
    local btn = tabs.frame.tabs[1]
    assert.is_nil(btn.initIcon) -- Blizzard's Init saw no icon, so it never called SetSquareMode
    assert.are.equal("Interface\\Icons\\Trade_Alchemy", btn.Icon.texture)
    assert.is_true(btn.Icon.shown)
    assert.is_true(btn.IconMask.shown)
    assert.is_true(btn.squareMode)
    assert.are.equal(TopTabs.SQUARE.atlas, btn.SquareBackground.atlas)
    assert.are.equal(TopTabs.SQUARE.activeAtlas, btn.SquareBackgroundActive.atlas)
    assert.are.equal(TopTabs.SQUARE.glowAtlas, btn.SquareBackgroundActiveGlow.atlas)
    assert.is_false(btn.Left.shown)
    assert.is_false(btn.RightHighlight.shown)
    assert.is_false(btn.isSelected)
    assert.are.equal(30 + TopTabs.SQUARE.sideSpacing, btn.tabWidth)
  end)

  it("uses text top tabs when the client has no icon tab art (TBC)", function()
    local tabs = TopTabs.Create({}, defs, { caps = { topTabs = true, iconTabs = false } })
    assert.are.equal("Crafting", tabs.frame.tabs[1].tabText)
    assert.is_nil(tabs.frame.tabs[1].tabIcon)
  end)

  it("reports user clicks by name and selects visually by name", function()
    local picked
    local tabs = TopTabs.Create({}, defs, {
      caps = { topTabs = true, iconTabs = true },
      onSelect = function(name) picked = name end,
    })
    tabs.frame:SetTab(2, true)
    assert.are.equal("raids", picked)
    tabs:SetSelected("crafting")
    assert.are.equal(1, tabs.frame.selectedID)
  end)

  it("does not report programmatic selection as a user click", function()
    local picked
    local tabs = TopTabs.Create({}, defs, {
      caps = { topTabs = true, iconTabs = true },
      onSelect = function(name) picked = name end,
    })
    tabs.frame:SetTab(1, false)
    assert.is_nil(picked)
  end)

  describe("classic panel top tabs (TBC Anniversary: no TabSystem)", function()
    local savedSelect, savedDeselect, savedResize, calls

    before_each(function()
      savedSelect, savedDeselect, savedResize =
        _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab, _G.PanelTemplates_TabResize
      calls = {}
      _G.PanelTemplates_SelectTab = function(tab) calls[#calls + 1] = { "select", tab } end
      _G.PanelTemplates_DeselectTab = function(tab) calls[#calls + 1] = { "deselect", tab } end
      _G.PanelTemplates_TabResize = function(tab, pad) tab.resized = pad end
    end)

    after_each(function()
      _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab, _G.PanelTemplates_TabResize =
        savedSelect, savedDeselect, savedResize
    end)

    it("uses named PanelTopTabButtonTemplate text tabs sized to their labels", function()
      local tabs = TopTabs.Create({}, defs, { caps = { panelTopTabs = true } })
      local crafting = tabs.buttons.crafting
      assert.are.equal("PanelTopTabButtonTemplate", crafting.template)
      assert.are.equal("Crafting", crafting.text)
      assert.is_not_nil(crafting.resized)
      assert.are.equal("BOTTOMLEFT", crafting.points[1][1])
    end)

    it("selects one tab and deselects the rest via PanelTemplates", function()
      local tabs = TopTabs.Create({}, defs, { caps = { panelTopTabs = true } })
      tabs:SetSelected("raids")
      local selected, deselected = {}, {}
      for _, c in ipairs(calls) do
        if c[1] == "select" then selected[#selected + 1] = c[2] else deselected[#deselected + 1] = c[2] end
      end
      assert.are.same({ tabs.buttons.raids }, selected)
      assert.are.same({ tabs.buttons.crafting }, deselected)
    end)

    it("reports clicks by name", function()
      local picked
      local tabs = TopTabs.Create({}, defs, {
        caps = { panelTopTabs = true },
        onSelect = function(name) picked = name end,
      })
      tabs.buttons.raids.scripts.OnClick()
      assert.are.equal("raids", picked)
    end)
  end)

  describe("slash commands in tooltips", function()
    local opts = { mainTab = "Cooldowns" }

    local function hover(btn)
      btn.scripts.OnEnter(btn)
      return GameTooltip
    end

    it("adds the view's command in gray under the TabSystem tab's own tooltip", function()
      opts.caps = { topTabs = true, iconTabs = true }
      local tabs = TopTabs.Create({}, defs, opts)
      local tip = hover(tabs.frame.tabs[2])
      assert.are.equal("Dungeons", tip.text)
      assert.are.same({ { "/alta cooldowns dungeons", 0.5, 0.5, 0.5 } }, tip.lines)
      assert.is_true(tip.shown)
    end)

    it("gives the classic text top tabs a tooltip with the label and command", function()
      opts.caps = { panelTopTabs = true }
      local tabs = TopTabs.Create({}, defs, opts)
      local tip = hover(tabs.buttons.raids)
      assert.are.equal(tabs.buttons.raids, tip.owner)
      assert.are.equal("Dungeons", tip.text)
      assert.are.equal("/alta cooldowns dungeons", tip.lines[1][1])
      tabs.buttons.raids.scripts.OnLeave(tabs.buttons.raids)
      assert.is_false(tip.shown)
    end)

    it("gives the fallback buttons the same tooltip", function()
      opts.caps = {}
      local tabs = TopTabs.Create({}, defs, opts)
      assert.are.equal("/alta cooldowns crafting", hover(tabs.buttons.crafting).lines[1][1])
    end)

    it("adds no tooltip without a main tab", function()
      local tabs = TopTabs.Create({}, defs, { caps = { panelTopTabs = true } })
      assert.is_nil(tabs.buttons.raids.scripts.OnEnter)
    end)
  end)

  it("falls back to toggle buttons without TabSystem", function()
    local skinned = {}
    AltArmy.Theme = AltArmy.Theme or {}
    local savedSkin = AltArmy.Theme.SkinButton
    AltArmy.Theme.SkinButton = function(btn, toggle)
      skinned[#skinned + 1] = toggle
      function btn:SetSelected(on) self.selected = on end
    end
    local picked
    local tabs = TopTabs.Create({}, defs, { caps = {}, onSelect = function(n) picked = n end })
    AltArmy.Theme.SkinButton = savedSkin
    assert.are.same({ true, true }, skinned)
    tabs.buttons.raids.scripts.OnClick()
    assert.are.equal("raids", picked)
    tabs:SetSelected("raids")
    assert.is_true(tabs.buttons.raids.selected)
    assert.is_false(tabs.buttons.crafting.selected)
  end)
end)
