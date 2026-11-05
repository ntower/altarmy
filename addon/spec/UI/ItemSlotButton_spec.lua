--[[
  Unit tests for ItemSlotButton.lua (the Inventory tab's item slot widget).
  Run from project root: npm test
]]

describe("ItemSlotButton", function()
  local ISB
  local saved
  local GLOBALS = { "CreateFrame", "GetItemInfo", "GetItemIcon", "C_Item", "ITEM_QUALITY_COLORS", "GameTooltip",
    "IsShiftKeyDown", "IsControlKeyDown" }
  local tooltip, actions

  local function stubRegion()
    local t = { shown = true, points = {} }
    function t:SetAllPoints() self.allPoints = true end
    function t:SetPoint(...) table.insert(self.points, { ... }) end
    function t:ClearAllPoints() self.points = {} end
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetTexture(path) self.texture = path end
    function t:SetAtlas(name) self.atlas = name end
    function t:SetVertexColor(r, g, b) self.color = { r, g, b } end
    function t:SetBlendMode(mode) self.blend = mode end
    function t:SetDesaturated(on) self.desaturated = on end
    function t:SetAlpha(a) self.alpha = a end
    function t:SetJustifyH(j) self.justify = j end
    function t:SetText(s) self.text = s end
    function t:GetText() return self.text end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:IsShown() return self.shown end
    return t
  end

  local function stubFrame()
    local f = stubRegion()
    f.scripts, f.textures, f.fontStrings = {}, {}, {}
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:CreateTexture(_, layer)
      local t = stubRegion()
      t.layer = layer
      table.insert(self.textures, t)
      return t
    end
    function f:CreateFontString(_, _, font)
      local s = stubRegion()
      s.font = font
      table.insert(self.fontStrings, s)
      return s
    end
    function f:SetNormalTexture(path) self.normal = stubRegion(); self.normal.texture = path end
    function f:GetNormalTexture() return self.normal end
    function f:SetPushedTexture(path) self.pushed = path end
    function f:SetHighlightTexture(path, mode) self.highlight, self.highlightMode = path, mode end
    return f
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    package.loaded["ItemSlotButton"] = nil
    require("ItemSlotButton")
    ISB = AltArmy.ItemSlotButton
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    _G.CreateFrame = function() return stubFrame() end
    _G.GetItemInfo = function(item)
      if item == 100 or item == "|Hitem:100|h[Sword]|h" then
        return "Sword", "|Hitem:100|h[Sword]|h", 3, 1, 1, "Weapon", "Sword", 1, "INVTYPE_WEAPON", "icon-sword"
      end
      if item == 200 then
        return "Cloth", "link", 1, 1, 1, "Trade", "Cloth", 20, "", "icon-cloth"
      end
      return nil
    end
    _G.GetItemIcon = nil
    _G.C_Item = nil
    _G.ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.44, b = 0.87 } }
    tooltip = { lines = {} }
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function tooltip:SetHyperlink(link) self.link = link end
    function tooltip:SetItemByID(id) self.itemID = id end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    _G.GameTooltip = tooltip
    actions = { previewed = nil, linked = nil }
    AltArmy.ItemActions = {
      GetClickAction = function(button, shift, ctrl)
        if button ~= "LeftButton" then return nil end
        if ctrl then return "preview" end
        if shift then return "chatlink" end
        return nil
      end,
      PreviewInDressingRoom = function(t) actions.previewed = t end,
      InsertLinkIntoChat = function(t) actions.linked = t end,
    }
    _G.IsShiftKeyDown = function() return false end
    _G.IsControlKeyDown = function() return false end
    AltArmy.DataStore = nil
    AltArmy.Theme = { FONTS = { count = "NumberFontNormal" } }
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  describe("Create", function()
    it("draws the stock slot art, well, border and count", function()
      local btn = ISB.Create({}, { caps = {} })
      assert.are.same({ 37, 37 }, { btn.w, btn.h })
      assert.are.equal("Interface\\Buttons\\UI-Quickslot2", btn.normal.texture)
      assert.are.same({ 64, 64 }, { btn.normal.w, btn.normal.h })
      assert.are.equal("Interface\\Buttons\\UI-Quickslot-Depress", btn.pushed)
      assert.are.equal("Interface\\Buttons\\ButtonHilight-Square", btn.highlight)
      assert.are.equal("ADD", btn.highlightMode)
      assert.are.equal("Interface\\PaperDoll\\UI-Backpack-EmptySlot", btn.emptyBg.texture)
      assert.is_nil(btn.emptyBg.atlas)
      assert.are.equal("Interface\\Common\\WhiteIconFrame", btn.border.texture)
      assert.is_false(btn.border.shown)
      assert.are.equal("NumberFontNormal", btn.count.font)
      assert.are.equal("RIGHT", btn.count.justify)
      assert.is_false(btn.icon.shown)
    end)

    it("uses the retail empty-slot atlas where the client has it", function()
      local btn = ISB.Create({}, { caps = { bagSlotAtlas = true } })
      assert.are.equal("bags-item-slot64", btn.emptyBg.atlas)
      assert.is_true(btn.emptyIsAtlas)
    end)

    it("scales the slot art with a smaller size", function()
      local btn = ISB.Create({}, { caps = {}, size = 24 })
      assert.are.same({ 24, 24 }, { btn.w, btn.h })
      assert.are.equal(64 * 24 / 37, btn.normal.w)
    end)
  end)

  describe("SetItem", function()
    it("shows the icon, a border for uncommon and better, and the count above one", function()
      local btn = ISB.Create({}, { caps = {} })
      local pending = ISB.SetItem(btn, { itemID = 100, count = 3, link = "|Hitem:100|h[Sword]|h" })
      assert.is_nil(pending)
      assert.are.equal("icon-sword", btn.icon.texture)
      assert.is_true(btn.icon.shown)
      assert.is_true(btn.border.shown)
      assert.are.same({ 0, 0.44, 0.87 }, btn.border.color)
      assert.are.equal("3", btn.count.text)
      assert.is_true(btn.count.shown)
      assert.are.equal(100, btn.entry.itemID)
    end)

    it("hides the border for common items and the count for a single one", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 200, count = 1 })
      assert.are.equal("icon-cloth", btn.icon.texture)
      assert.is_false(btn.border.shown)
      assert.is_false(btn.count.shown)
    end)

    it("prefers an icon the caller already has (mail rows)", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 1, icon = "mail-icon" })
      assert.are.equal("mail-icon", btn.icon.texture)
    end)

    it("shows a question mark and reports the id while the item is not cached", function()
      local btn = ISB.Create({}, { caps = {} })
      assert.are.equal(999, ISB.SetItem(btn, { itemID = 999, count = 2 }))
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", btn.icon.texture)
      assert.is_false(btn.border.shown)
      assert.are.equal("2", btn.count.text)
    end)

    it("falls back to C_Item for the icon and quality", function()
      _G.C_Item = {
        GetItemIconByID = function(id) return "c-icon-" .. id end,
        GetItemQualityByID = function() return 4 end,
      }
      local btn = ISB.Create({}, { caps = {} })
      assert.is_nil(ISB.SetItem(btn, { itemID = 999, count = 1 }))
      assert.are.equal("c-icon-999", btn.icon.texture)
      assert.is_true(btn.border.shown)
      assert.are.same({ 0.64, 0.21, 0.93 }, btn.border.color) -- no ITEM_QUALITY_COLORS[4]: the fallback
    end)

    it("draws an icon-only entry with a plain-text tooltip (the bag bar's backpack)", function()
      local btn = ISB.Create({}, { caps = {} })
      assert.is_nil(ISB.SetItem(btn, { icon = "backpack-art", name = "Backpack" }))
      assert.are.equal("backpack-art", btn.icon.texture)
      assert.is_true(btn.icon.shown)
      assert.is_false(btn.border.shown)
      assert.is_false(btn.count.shown)
      tooltip.text = nil
      function tooltip:SetText(s) self.text = s end
      btn.scripts.OnEnter(btn)
      assert.are.equal("Backpack", tooltip.text)
      btn.scripts.OnClick(btn, "LeftButton")
      assert.is_nil(actions.linked)
    end)

    it("SetEmpty clears everything but the well", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 5 })
      ISB.SetEmpty(btn)
      assert.is_nil(btn.entry)
      assert.is_false(btn.icon.shown)
      assert.is_false(btn.border.shown)
      assert.is_false(btn.count.shown)
      assert.is_true(btn.emptyBg.shown)
      assert.is_nil(ISB.SetItem(btn, nil))
      assert.is_nil(btn.entry)
    end)
  end)

  describe("QualityColor", function()
    it("colours uncommon and better only", function()
      assert.is_nil(ISB.QualityColor(1))
      assert.is_nil(ISB.QualityColor(nil))
      assert.are.same({ 0, 0.44, 0.87 }, { ISB.QualityColor(3) })
      assert.are.same({ 0, 1, 0 }, { ISB.QualityColor(2) })
    end)
  end)

  describe("interaction", function()
    it("shows the item tooltip by link, else by id, with any extra lines", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 1, link = "|Hitem:100|h[Sword]|h" })
      local extra = 0
      btn.tooltipExtra = function() extra = extra + 1 end
      btn.scripts.OnEnter(btn)
      assert.are.equal(btn, tooltip.owner)
      assert.are.equal("ANCHOR_RIGHT", tooltip.anchor)
      assert.are.equal("|Hitem:100|h[Sword]|h", tooltip.link)
      assert.are.equal(1, extra)
      assert.is_true(tooltip.shown)
      btn.scripts.OnLeave(btn)
      assert.is_false(tooltip.shown)

      ISB.SetItem(btn, { itemID = 200, count = 1 })
      btn.scripts.OnEnter(btn)
      assert.are.equal(200, tooltip.itemID)

      ISB.SetEmpty(btn)
      tooltip.owner = nil
      btn.scripts.OnEnter(btn)
      assert.is_nil(tooltip.owner)
    end)

    it("routes Shift-click to chat and Ctrl-click to the dressing room", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 1, link = "L" })
      btn.scripts.OnClick(btn, "LeftButton")
      assert.is_nil(actions.linked)
      _G.IsShiftKeyDown = function() return true end
      btn.scripts.OnClick(btn, "LeftButton")
      assert.are.equal("L", actions.linked)
      _G.IsShiftKeyDown = function() return false end
      _G.IsControlKeyDown = function() return true end
      btn.scripts.OnClick(btn, "LeftButton")
      assert.are.equal("L", actions.previewed)
      ISB.SetEmpty(btn)
      actions.previewed = nil
      btn.scripts.OnClick(btn, "LeftButton")
      assert.is_nil(actions.previewed)
    end)
  end)

  describe("NameMatches", function()
    it("matches a case-insensitive substring, everything on an empty query", function()
      assert.is_true(ISB.NameMatches("Bolt of Linen Cloth", "linen"))
      assert.is_true(ISB.NameMatches("Bolt of Linen Cloth", ""))
      assert.is_true(ISB.NameMatches(nil, ""))
      assert.is_false(ISB.NameMatches("Bolt of Linen Cloth", "wool"))
      assert.is_false(ISB.NameMatches(nil, "linen"))
    end)

    it("reads pattern characters literally", function()
      assert.is_true(ISB.NameMatches("100% [Rare]", "% [r"))
      assert.is_false(ISB.NameMatches("Linen", "l.n"))
    end)
  end)

  describe("ApplySearch", function()
    it("rings a matching item, dims the rest, and resets on an empty query", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 1 })
      assert.are.equal("Sword", btn.itemName)
      assert.is_false(btn.searchGlow.shown)

      ISB.ApplySearch(btn, "swo")
      assert.is_true(btn.searchGlow.shown)
      assert.are.equal(1, btn.alpha)
      assert.is_false(btn.icon.desaturated)

      ISB.ApplySearch(btn, "cloth")
      assert.is_false(btn.searchGlow.shown)
      assert.are.equal(ISB.DIMMED_ALPHA, btn.alpha)
      assert.is_true(btn.icon.desaturated)

      ISB.ApplySearch(btn, "")
      assert.is_false(btn.searchGlow.shown)
      assert.are.equal(1, btn.alpha)
      assert.is_false(btn.icon.desaturated)
    end)

    it("dims empty slots and items whose name is not cached under a query", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.ApplySearch(btn, "sword")
      assert.are.equal(ISB.DIMMED_ALPHA, btn.alpha)
      ISB.SetItem(btn, { itemID = 999, count = 1 })
      ISB.ApplySearch(btn, "sword")
      assert.are.equal(ISB.DIMMED_ALPHA, btn.alpha)
      assert.is_false(btn.searchGlow.shown)
    end)

    it("SetEmpty clears the search look", function()
      local btn = ISB.Create({}, { caps = {} })
      ISB.SetItem(btn, { itemID = 100, count = 1 })
      ISB.ApplySearch(btn, "sword")
      ISB.SetEmpty(btn)
      assert.is_nil(btn.itemName)
      assert.is_false(btn.searchGlow.shown)
      assert.are.equal(1, btn.alpha)
    end)
  end)

  describe("bag highlight", function()
    it("shows retail's blue bag indicator over the slot, which SetEmpty clears", function()
      local btn = ISB.Create({}, { caps = {} })
      assert.are.equal("Interface\\Store\\store-item-highlight", btn.bagHighlight.texture)
      assert.are.equal("OVERLAY", btn.bagHighlight.layer)
      assert.are.same({ 64, 64 }, { btn.bagHighlight.w, btn.bagHighlight.h })
      assert.is_false(btn.bagHighlight.shown)
      ISB.SetBagHighlight(btn, true)
      assert.is_true(btn.bagHighlight.shown)
      ISB.SetBagHighlight(btn, false)
      assert.is_false(btn.bagHighlight.shown)
      ISB.SetBagHighlight(btn, true)
      ISB.SetEmpty(btn)
      assert.is_false(btn.bagHighlight.shown)
    end)

    it("draws a bag's icon faintly behind the slot, kept by SetItem and cleared by SetEmpty", function()
      local btn = ISB.Create({}, { caps = {} })
      assert.are.equal("BACKGROUND", btn.bagBg.layer)
      assert.are.equal(ISB.BAG_BACKGROUND_ALPHA, btn.bagBg.alpha)
      assert.is_true(btn.bagBg.desaturated)
      assert.is_false(btn.bagBg.shown)
      ISB.SetBagBackground(btn, "icon-bag")
      assert.is_true(btn.bagBg.shown)
      assert.is_false(btn.emptyBg.shown) -- the bag's icon replaces the well
      assert.are.equal("icon-bag", btn.bagBg.texture)
      ISB.SetItem(btn, { itemID = 100, count = 1 })
      assert.is_true(btn.bagBg.shown)
      ISB.SetBagBackground(btn, nil)
      assert.is_false(btn.bagBg.shown)
      assert.is_true(btn.emptyBg.shown)
      ISB.SetBagBackground(btn, "icon-bag")
      ISB.SetEmpty(btn)
      assert.is_false(btn.bagBg.shown)
      assert.is_true(btn.emptyBg.shown)
    end)

    it("tells onHover when the mouse enters and leaves, item or not", function()
      local btn = ISB.Create({}, { caps = {} })
      local calls = {}
      btn.onHover = function(b, inside) calls[#calls + 1] = { b, inside } end
      btn.scripts.OnEnter(btn)
      btn.scripts.OnLeave(btn)
      assert.are.same({ { btn, true }, { btn, false } }, calls)
    end)
  end)

  describe("CreatePool", function()
    it("pools any frame kind with a create and reset of the caller's", function()
      local made, resets = 0, 0
      local pool = ISB.CreatePool({}, {
        create = function() made = made + 1; return stubFrame() end,
        reset = function() resets = resets + 1 end,
      })
      local a = pool.Acquire()
      pool.ReleaseAll()
      assert.are.equal(a, pool.Acquire())
      assert.are.same({ 1, 1 }, { made, resets })
    end)

    it("reuses released buttons and empties them", function()
      local pool = ISB.CreatePool({}, { caps = {} })
      local a = pool.Acquire()
      local b = pool.Acquire()
      ISB.SetItem(a, { itemID = 100, count = 2 })
      assert.are.equal(2, #pool.active)
      pool.ReleaseAll()
      assert.are.equal(0, #pool.active)
      assert.is_false(a.shown)
      assert.is_nil(a.entry)
      local c = pool.Acquire()
      assert.is_true(c == a or c == b)
      assert.is_true(c.shown)
    end)
  end)
end)
