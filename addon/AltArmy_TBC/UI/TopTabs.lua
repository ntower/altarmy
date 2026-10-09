-- AltArmy TBC — Spellbook-style sub-view tabs that hang above a panel (Cooldowns: Crafting /
-- Dungeons). Uses Blizzard's TabSystemTemplate with TabSystemTopButtonTemplate:
--   Forever: square icon tabs (spellbook-Tab-Frame-C60 art), name in the tooltip.
--   TBC Anniversary: its client does not load TabSystem at all, so classic text top tabs
--   (PanelTopTabButtonTemplate + PanelTemplates_SelectTab / DeselectTab).
--   Neither: plain toggle buttons.
-- Callers anchor `obj.frame` by its BOTTOMLEFT so the tabs grow upward from the panel top.

AltArmy = AltArmy or {}
AltArmy.TopTabs = AltArmy.TopTabs or {}

local TopTabs = AltArmy.TopTabs

TopTabs.FALLBACK_BUTTON = { width = 90, height = 22, gap = 4 }

local function resolveCaps(opts)
    if opts.caps then return opts.caps end
    local NativeUI = AltArmy.NativeUI
    return NativeUI and NativeUI.GetCaps() or {}
end

local function hookTooltip(btn, def)
    AltArmy.TabTooltip.Hook(btn, def.label, def.command, "ANCHOR_TOP")
end

-- The square icon look (what Blizzard's TabSystemButtonMixin:SetSquareMode draws), applied here by hand.
-- SetSquareMode also writes TabSideExtraSpacing, a variable in TabSystemTemplates.lua shared by every tab
-- system in the client. Written from an addon, that value is tainted, and the next Blizzard frame to build its
-- tabs (the talents frame, the first time it opens) reads it, runs tainted from there on, and its cast bar
-- hand-off ends in ADDON_ACTION_BLOCKED on PlayerCastingBarFrame:Show() for every cast afterwards. So a tab
-- is added without an icon (Init then never calls SetSquareMode) and dressed up here, touching only itself.
TopTabs.SQUARE = {
    atlas = "spellbook-Tab-Frame-C60",
    activeAtlas = "spellbook-Tab-Frame-Glow-C60",
    glowAtlas = "spellbook-Tab-Frame-glow-gradient-C60",
    sideSpacing = 8, -- TabSideExtraSpacingSquare: the icon plus this is the tab's width
}
local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight" }

local function makeSquareIconTab(btn, icon)
    local S = TopTabs.SQUARE
    btn.tabIcon = icon
    btn.squareMode = true
    if btn.Icon then
        btn.Icon:SetTexture(icon)
        btn.Icon:Show()
    end
    if btn.IconMask then btn.IconMask:Show() end
    for _, key in ipairs(TAB_ART) do
        local tex = btn[key]
        if tex then tex:Hide() end
    end
    if btn.SquareBackground then btn.SquareBackground:SetAtlas(S.atlas, true) end
    if btn.SquareBackgroundActive then btn.SquareBackgroundActive:SetAtlas(S.activeAtlas, true) end
    if btn.SquareBackgroundActiveGlow then btn.SquareBackgroundActiveGlow:SetAtlas(S.glowAtlas, true) end
    if btn.SetTabSelected then btn:SetTabSelected(false) end -- shows the square art for the unselected state
    local iconWidth = btn.Icon and btn.Icon.GetWidth and btn.Icon:GetWidth() or 0
    if btn.SetTabWidth then btn:SetTabWidth(iconWidth + S.sideSpacing) end
end

local function createTabSystem(parent, defs, obj, onSelect, useIcons)
    local sys = CreateFrame("Frame", nil, parent, "TabSystemTemplate")
    -- TabSystemMixin:OnLoad pooled the default (bottom) template; rebuild for top tabs.
    sys.tabTemplate = "TabSystemTopButtonTemplate"
    sys.tabPool = _G.CreateFramePool("BUTTON", sys, "TabSystemTopButtonTemplate")
    sys:SetTabSelectedCallback(function(tabID, isUserAction)
        local name = obj.nameById[tabID]
        if isUserAction and name then
            onSelect(name)
        end
        return false
    end)
    for _, def in ipairs(defs) do
        local id
        if useIcons then
            id = sys:AddTab(nil) -- no icon here: see makeSquareIconTab
        else
            id = sys:AddTab(def.label)
        end
        local btn = sys:GetTabButton(id)
        if btn and useIcons then
            makeSquareIconTab(btn, def.icon)
        end
        if btn and btn.SetTooltipText then
            btn:SetTooltipText(def.label)
        end
        if btn then hookTooltip(btn, def) end
        obj.idByName[def.name] = id
        obj.nameById[id] = def.name
        obj.buttons[def.name] = btn
    end
    obj.frame = sys
    function obj:SetSelected(name)
        local id = self.idByName[name]
        if id then
            sys:SetTabVisuallySelected(id)
        end
    end
end

-- Classic TabButtonTemplate top tabs (HelpFrameTab art) driven by PanelTemplates_*; these helpers
-- look up textures by global name, so tabs need unique names.
local classicTabCount = 0
TopTabs.CLASSIC_TAB = { padding = 20, gap = -8 }

local function createClassicTopTabs(parent, defs, obj, onSelect)
    local C = TopTabs.CLASSIC_TAB
    local container = CreateFrame("Frame", nil, parent)
    local prev
    for _, def in ipairs(defs) do
        classicTabCount = classicTabCount + 1
        local btn = CreateFrame("Button", "AltArmyTBC_TopTab" .. classicTabCount, container,
            "PanelTopTabButtonTemplate")
        btn:SetText(def.label)
        if _G.PanelTemplates_TabResize then
            _G.PanelTemplates_TabResize(btn, C.padding)
        end
        if prev then
            btn:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", C.gap, 0)
        else
            btn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        end
        btn:SetScript("OnClick", function()
            onSelect(def.name)
        end)
        hookTooltip(btn, def)
        obj.buttons[def.name] = btn
        prev = btn
    end
    local first = obj.buttons[defs[1] and defs[1].name]
    container:SetSize(200, first and first.GetHeight and first:GetHeight() or 24)
    obj.frame = container
    function obj:SetSelected(name)
        for tabName, btn in pairs(self.buttons) do
            if tabName == name then
                _G.PanelTemplates_SelectTab(btn)
            else
                _G.PanelTemplates_DeselectTab(btn)
            end
        end
    end
end

local function createFallbackButtons(parent, defs, obj, onSelect)
    local B = TopTabs.FALLBACK_BUTTON
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(#defs * (B.width + B.gap), B.height)
    local Theme = AltArmy.Theme
    for i, def in ipairs(defs) do
        local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        btn:SetSize(B.width, B.height)
        btn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", (i - 1) * (B.width + B.gap), 0)
        btn:SetText(def.label)
        if Theme and Theme.SkinButton then
            Theme.SkinButton(btn, true)
        end
        btn:SetScript("OnClick", function()
            onSelect(def.name)
        end)
        hookTooltip(btn, def)
        obj.buttons[def.name] = btn
    end
    obj.frame = container
    function obj:SetSelected(name)
        for tabName, btn in pairs(self.buttons) do
            if btn.SetSelected then
                btn:SetSelected(tabName == name)
            end
        end
    end
end

--- defs: array of { name, label, icon }. opts.onSelect(name) fires on user clicks only.
--- opts.mainTab: the main window tab these views belong to; each tab's tooltip then shows the slash command
--- opening its view (MainTabs.SlashCommand). opts.caps overrides NativeUI caps (tests).
function TopTabs.Create(parent, defs, opts)
    opts = opts or {}
    local MainTabs = AltArmy.MainTabs
    if opts.mainTab and MainTabs then
        local withCommands = {}
        for i, def in ipairs(defs) do
            withCommands[i] = {
                name = def.name, label = def.label, icon = def.icon,
                command = MainTabs.SlashCommand(opts.mainTab, def.name),
            }
        end
        defs = withCommands
    end
    local caps = resolveCaps(opts)
    local onSelect = opts.onSelect or function() end
    local obj = { buttons = {}, idByName = {}, nameById = {} }
    if caps.topTabs then
        createTabSystem(parent, defs, obj, onSelect, caps.iconTabs)
    elseif caps.panelTopTabs then
        createClassicTopTabs(parent, defs, obj, onSelect)
    else
        createFallbackButtons(parent, defs, obj, onSelect)
    end
    return obj
end
