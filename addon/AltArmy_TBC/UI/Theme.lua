-- AltArmy TBC — Shared UI theme: native Blizzard chrome (templates, NineSlice layouts, atlases)
-- chosen per client via NativeUI caps. Theme.COLORS is the legacy flat palette, used only as the
-- fallback where a native piece is missing, and for accent / meaning colors. See docs/UI_DESIGN.md.
-- Loaded before Core.lua in the .toc; must bootstrap the namespace here.

AltArmy = AltArmy or {}
AltArmy.Theme = AltArmy.Theme or {}

local Theme = AltArmy.Theme

-- Font roles -> Blizzard font objects (same sizes on Forever and TBC Anniversary: Small 10,
-- Normal/Highlight 12, Med3 14, Large 16). Like native panels (Character / Reputation / Skills),
-- all text is 12pt: labels and column headers gold Normal, rows / values white Highlight. Only
-- icon badge glyphs use a Small base. Use Theme.FONTS.<role>, never a GameFont literal, in UI code.
-- The Blizzard font each text role is drawn like.
Theme.BASE_FONTS = {
    pageTitle = "GameFontNormalHuge",       -- Interface Options page header
    headline = "GameFontHighlightLarge",    -- dialog headline
    title = "GameFontNormalMed3",           -- panel / settings / dialog titles
    heading = "GameFontNormal",             -- section and column headers, labels, button labels
    body = "GameFontHighlight",             -- grid cells, list rows, values, hints, inputs
    muted = "GameFontDisable",              -- unavailable rows, graph axes, inline empty notes
    emptyState = "GameFontDisableLarge",    -- centered empty-state messages that replace a table/graph
    badge = "GameFontNormalSmall",          -- Gear upgrade glyphs on item icons (scaled x2)
    count = "NumberFontNormal",             -- stack counts on item slots (ItemButtonTemplate's Count)
}

-- Theme.FONTS names the font object each role uses. In game it is AltArmyFont_<role>, our own font
-- made from the Blizzard one (CreateFont), so Theme.SetFontSize can resize every font string of the
-- role at once (the General options' Look and Feel "Font size"); where no font can be made (unit
-- tests, a client without the Blizzard font) it is the Blizzard font itself.
Theme.FONTS = {}
local ownFonts = {} -- role -> { font, path, size (the Blizzard font's), flags }
for role, base in pairs(Theme.BASE_FONTS) do
    local baseFont = _G[base]
    local name = "AltArmyFont_" .. role
    local own
    if _G.CreateFont and type(baseFont) == "table" and baseFont.GetFont then
        local path, size, flags = baseFont:GetFont()
        if path and size then
            own = _G.CreateFont(name)
            if own.SetFontObject then
                own:SetFontObject(baseFont) -- colour, shadow and justification come along
            end
            own:SetFont(path, size, flags or "")
            ownFonts[role] = { font = own, path = path, size = size, flags = flags or "" }
        end
    end
    Theme.FONTS[role] = own and name or base
end

-- The font size (the body role's; the other roles keep their ratio to it): AltArmyTBC_Options.fontSize,
-- unset at the client's own (DEFAULT_FONT_SIZE: the body font's, 12 on Forever and TBC Anniversary).
Theme.FONT_SIZE_MIN = 9
Theme.FONT_SIZE_MAX = 18
local bodyBaseSize = ownFonts.body and ownFonts.body.size or 12

local function clampFontSize(size)
    return math.max(Theme.FONT_SIZE_MIN, math.min(Theme.FONT_SIZE_MAX, size))
end
Theme.DEFAULT_FONT_SIZE = clampFontSize(math.floor(bodyBaseSize + 0.5))

--- A role's size when the body is `fontSize`: its Blizzard size scaled by the same ratio, whole points.
function Theme.FontSizeFor(baseSize, fontSize, bodyDefault)
    bodyDefault = bodyDefault or bodyBaseSize
    if not bodyDefault or bodyDefault <= 0 then bodyDefault = 12 end
    return math.max(1, math.floor(baseSize * fontSize / bodyDefault + 0.5))
end

--- The saved font size, clamped; the default when nothing valid is saved.
function Theme.GetFontSize()
    local o = _G.AltArmyTBC_Options
    local s = type(o) == "table" and o.fontSize or nil
    if type(s) ~= "number" or s ~= s then return Theme.DEFAULT_FONT_SIZE end
    return clampFontSize(math.floor(s + 0.5))
end

--- Sizes every role's font for the saved font size (at login, once the saved variables are in).
function Theme.ApplyFontSize()
    local size = Theme.GetFontSize()
    for _, own in pairs(ownFonts) do
        own.font:SetFont(own.path, Theme.FontSizeFor(own.size, size), own.flags)
    end
end

--- Saves a font size (clamped; unset at the default) and applies it.
function Theme.SetFontSize(size)
    if type(size) ~= "number" or size ~= size then return end
    size = clampFontSize(math.floor(size + 0.5))
    if type(_G.AltArmyTBC_Options) == "table" then
        _G.AltArmyTBC_Options.fontSize = size ~= Theme.DEFAULT_FONT_SIZE and size or nil
    end
    Theme.ApplyFontSize()
end

Theme.HOVER_TINT_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
Theme.HOVER_TINT_ALPHA = 0.22
-- Native list-row hover (additive), used when the client has native chrome.
Theme.NATIVE_ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
Theme.NATIVE_ROW_HIGHLIGHT_ALPHA = 0.6

Theme.COLORS = {
    -- Shell: semi-transparent so gaps between opaque section panels show the game through.
    windowBg      = { 0.08, 0.08, 0.10, 0.55 },
    windowBorder  = { 0.45, 0.38, 0.22, 0.75 },
    -- In-tab panels: nearly opaque cards on top of the shell.
    panelBg       = { 0.08, 0.08, 0.10, 0.95 },
    sectionBg     = { 0.08, 0.08, 0.10, 0.95 },
    graphBg       = { 0.08, 0.08, 0.10, 0.95 },
    dialogBg      = { 0.08, 0.08, 0.10, 0.97 },
    inputBg       = { 0.06, 0.06, 0.08, 1.00 },

    panelBorder   = { 0.45, 0.38, 0.22, 0.90 },
    sectionBorder = { 0.45, 0.38, 0.22, 0.90 },
    inputBorder   = { 0.22, 0.22, 0.26, 0.80 },

    sepLine       = { 0.55, 0.46, 0.22, 0.70 },

    title         = { 0.85, 0.78, 0.42, 1.00 },
    label         = { 0.69, 0.69, 0.69, 1.00 },
    value         = { 0.92, 0.92, 0.92, 1.00 },
    groupHeader   = { 0.55, 0.55, 0.60, 1.00 },
    -- Warning text: caution (yellow) and blocking/error (red), as on Gear compare warnings.
    warningCaution  = { 1.00, 0.82, 0.00, 1.00 },
    warningBlocking = { 1.00, 0.40, 0.30, 1.00 },

    btnBg         = { 0.14, 0.14, 0.18, 1.00 },
    btnBorder     = { 0.28, 0.25, 0.20, 0.90 },
    btnHoverBg    = { 0.20, 0.18, 0.14, 1.00 },
    btnHoverBorder= { 0.45, 0.38, 0.18, 1.00 },
    btnPressBg    = { 0.08, 0.08, 0.10, 1.00 },
    btnActiveBg   = { 0.30, 0.24, 0.08, 1.00 },
    btnActiveBorder = { 0.82, 0.68, 0.22, 1.00 },
    btnText       = { 0.90, 0.88, 0.80, 1.00 },
    btnTextHover  = { 1.00, 0.94, 0.70, 1.00 },

    btnDangerBg       = { 0.24, 0.06, 0.06, 1.00 },
    btnDangerBorder   = { 0.78, 0.20, 0.14, 1.00 },
    btnDangerHoverBg  = { 0.34, 0.08, 0.06, 1.00 },
    btnDangerHoverBorder = { 0.92, 0.28, 0.18, 1.00 },
    btnDangerPressBg  = { 0.16, 0.04, 0.04, 1.00 },
    btnDangerText     = { 1.00, 0.55, 0.45, 1.00 },

    rowHover      = { 0.20, 0.18, 0.12, 0.40 },
    rowSelected   = { 0.22, 0.20, 0.10, 0.60 },
    rowAccent     = { 0.55, 0.46, 0.22, 1.00 },

    -- Same RGB as sectionBg/graphBg; alpha 1 for opaque pinned overlays.
    gridHeaderBg  = { 0.08, 0.08, 0.10, 1.00 },
    scrollTrack   = { 0.08, 0.08, 0.08, 0.80 },
    scrollThumb   = { 0.50, 0.50, 0.60, 1.00 },

    headerBg      = { 0.10, 0.10, 0.12, 0.65 },
    settingsGlow  = { 1.00, 0.82, 0.20, 0.55 },

    green         = { 0.20, 0.85, 0.35, 1.00 },
    red           = { 1.00, 0.28, 0.18, 1.00 },
    yellow        = { 0.92, 0.82, 0.18, 1.00 },

    -- Graph tooltip palette (aligned with GraphCore)
    tooltipBg     = { 0.12, 0.12, 0.14, 0.97 },
    tooltipBorder = { 0.70, 0.58, 0.28, 0.90 },
}

local C = Theme.COLORS

local BG_FILE = "Interface\\ChatFrame\\ChatFrameBackground"
local EDGE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"

Theme.WINDOW_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

Theme.SECTION_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = false,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

Theme.GRAPH_BACKDROP = Theme.SECTION_BACKDROP

-- Main-window tab content: background only; the window's own border is the only outline.
Theme.CONTENT_BACKDROP = {
    bgFile = BG_FILE,
    tile = false,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

Theme.TOOLTIP_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

Theme.BUTTON_BACKDROP = {
    bgFile = BG_FILE,
    edgeFile = EDGE_FILE,
    tile = false,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local TIER_BACKDROP = {
    window = Theme.WINDOW_BACKDROP,
    section = Theme.SECTION_BACKDROP,
    content = Theme.CONTENT_BACKDROP,
    graph = Theme.GRAPH_BACKDROP,
    tooltip = Theme.TOOLTIP_BACKDROP,
    button = Theme.BUTTON_BACKDROP,
}

local TIER_BG = {
    window = C.windowBg,
    dialog = C.dialogBg,
    section = C.sectionBg,
    content = C.sectionBg,
    graph = C.graphBg,
    tooltip = C.tooltipBg,
    button = C.btnBg,
}

local TIER_BORDER = {
    window = C.windowBorder,
    dialog = C.panelBorder,
    section = C.sectionBorder,
    content = C.sectionBorder,
    graph = C.sectionBorder,
    tooltip = C.tooltipBorder,
    button = C.btnBorder,
}

function Theme.EnsureBackdrop(frame)
    if frame.SetBackdrop then return end
    if Mixin and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        if frame.HookScript and frame.OnBackdropSizeChanged then
            frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
        end
    end
end

-- Native Blizzard chrome per tier: NineSlice layout drawn onto the frame itself (BORDER layer,
-- below the frame's own text/art and all child frames) plus a tiled native background.
-- Layout names exist on both Forever and TBC Anniversary; Forever reskins their atlases in place.
Theme.NATIVE_TIERS = {
    section = { layout = "InsetFrameTemplate", bg = "Interface\\FrameGeneral\\UI-Background-Marble", bgInset = 0 },
    graph = { layout = "InsetFrameTemplate", bg = "Interface\\FrameGeneral\\UI-Background-Marble", bgInset = 0 },
    -- No layout: background only, so the portrait window's border is the single outline.
    content = { bg = "Interface\\FrameGeneral\\UI-Background-Marble", bgInset = 0 },
    window = { layout = "Dialog", bg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", bgInset = 6 },
    dialog = { layout = "Dialog", bg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", bgInset = 6 },
    -- GameTooltip default background tint.
    tooltip = { layout = "TooltipDefaultLayout", centerColor = { 0.09, 0.09, 0.19, 1 } },
}

local function nativeChromeAvailable()
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    return caps and caps.nineSlice or false
end

--- Apply native chrome for `tier`; returns false when the tier has no native recipe or the
--- client lacks NineSlice layouts (caller then uses the legacy backdrop).
function Theme.ApplyNativeChrome(frame, tier)
    local recipe = Theme.NATIVE_TIERS[tier]
    if not frame or not recipe or not nativeChromeAvailable() or not _G.NineSliceUtil then
        return false
    end
    if recipe.layout then
        _G.NineSliceUtil.ApplyLayoutByName(frame, recipe.layout)
    end
    if recipe.bg then
        local bg = frame.altArmyNativeBg
        if not bg then
            bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
            frame.altArmyNativeBg = bg
        end
        bg:SetTexture(recipe.bg, "REPEAT", "REPEAT")
        if bg.SetHorizTile then bg:SetHorizTile(true) end
        if bg.SetVertTile then bg:SetVertTile(true) end
        local inset = recipe.bgInset or 0
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    if recipe.centerColor and frame.Center and frame.Center.SetVertexColor then
        local c = recipe.centerColor
        frame.Center:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    frame.altArmyNativeTier = tier
    return true
end

--- Legacy flat-color backdrop (tintable via SetBackdropColor / SetBackdropBorderColor).
--- Use only where the tint itself carries meaning (attention flash, themed buttons).
function Theme.ApplyLegacyBackdrop(frame, tier)
    if not frame then return end
    Theme.EnsureBackdrop(frame)
    if not frame.SetBackdrop then return end

    local backdrop = TIER_BACKDROP[tier] or TIER_BACKDROP.section
    local bg = TIER_BG[tier] or C.sectionBg
    local border = TIER_BORDER[tier] or C.sectionBorder

    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

function Theme.ApplyBackdrop(frame, tier)
    if not frame then return end
    if Theme.ApplyNativeChrome(frame, tier) then return end
    Theme.ApplyLegacyBackdrop(frame, tier)
end

function Theme.CreatePanel(parent, tier, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(frame, tier or "section")
    return frame
end

local function applyButtonColors(btn, bg, border)
    if not btn or not btn.SetBackdropColor then return end
    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if btn.SetBackdropBorderColor and border then
        btn:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function getButtonFontString(btn)
    if btn.GetFontString then
        local fs = btn:GetFontString()
        if fs then return fs end
    end
    return btn.label
end

local function setButtonTextColor(btn, color)
    local fs = getButtonFontString(btn)
    if fs and fs.SetTextColor and color then
        fs:SetTextColor(color[1], color[2], color[3])
    end
end

local function stripButtonTemplate(btn)
    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt and nt.SetTexture then nt:SetTexture(nil) end
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht and ht.SetTexture then ht:SetTexture(nil) end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt and pt.SetTexture then pt:SetTexture(nil) end
end

-- UIPanelButtonTemplate art: plain texture files on both Forever and TBC Anniversary
-- (SecureUIPanelTemplates UIPanelButton_On*), so drawing them ourselves is identical to the template.
Theme.PANEL_BUTTON = {
    up = "Interface\\Buttons\\UI-Panel-Button-Up",
    down = "Interface\\Buttons\\UI-Panel-Button-Down",
    disabled = "Interface\\Buttons\\UI-Panel-Button-Disabled",
    highlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
}
-- NORMAL / HIGHLIGHT / DISABLED font colors for plain-button label FontStrings.
Theme.BUTTON_TEXT = {
    normal = { 1.00, 0.82, 0.00 },
    highlight = { 1.00, 1.00, 1.00 },
    disabled = { 0.50, 0.50, 0.50 },
    danger = { 1.00, 0.35, 0.30 },
    dangerHighlight = { 1.00, 0.55, 0.50 },
}

local PANEL_SLICES = {
    Left = { 0, 0.09375 },
    Middle = { 0.09375, 0.53125 },
    Right = { 0.53125, 0.625 },
}
local PANEL_TEX_BOTTOM = 0.6875

local function setPanelArt(btn, file)
    for key in pairs(PANEL_SLICES) do
        local tex = btn[key]
        if tex then tex:SetTexture(file) end
    end
end

--- Left/Right cap width scales with height (12px at the template's 22px) but never exceeds half the width.
local function layoutPanelCaps(btn)
    local h = btn.GetHeight and btn:GetHeight() or 22
    local w = btn.GetWidth and btn:GetWidth() or 40
    local cap = math.floor(math.min(12 * (h > 0 and h or 22) / 22, (w > 0 and w or 40) / 2) + 0.5)
    btn.Left:SetWidth(cap)
    btn.Right:SetWidth(cap)
end

local function createPanelButtonArt(btn)
    for key, coords in pairs(PANEL_SLICES) do
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetTexCoord(coords[1], coords[2], 0, PANEL_TEX_BOTTOM)
        btn[key] = tex
    end
    btn.Left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.Left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.Right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    btn.Right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.Middle:SetPoint("TOPLEFT", btn.Left, "TOPRIGHT", 0, 0)
    btn.Middle:SetPoint("BOTTOMRIGHT", btn.Right, "BOTTOMLEFT", 0, 0)
    layoutPanelCaps(btn)
    setPanelArt(btn, Theme.PANEL_BUTTON.up)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(Theme.PANEL_BUTTON.highlight)
    highlight:SetTexCoord(0, 0.625, 0, PANEL_TEX_BOTTOM)
    highlight:SetAllPoints(btn)
    if highlight.SetBlendMode then highlight:SetBlendMode("ADD") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture(highlight) end

    local function isEnabled(self)
        return not (self.IsEnabled and not self:IsEnabled())
    end
    btn:HookScript("OnMouseDown", function(self)
        if isEnabled(self) then setPanelArt(self, Theme.PANEL_BUTTON.down) end
    end)
    btn:HookScript("OnMouseUp", function(self)
        if isEnabled(self) then setPanelArt(self, Theme.PANEL_BUTTON.up) end
    end)
    btn:HookScript("OnShow", function(self)
        if isEnabled(self) then setPanelArt(self, Theme.PANEL_BUTTON.up) end
    end)
    btn:HookScript("OnSizeChanged", layoutPanelCaps)
end

--- Native look for any button: keeps UIPanelButtonTemplate art (instead of stripping it) or draws
--- the same art on plain buttons. `colors` = { normal, highlight } label colors (plain buttons only).
local function skinNativeButton(btn, isToggle, colors)
    local plain = not (btn.Left and btn.Middle and btn.Right)
    if plain then
        createPanelButtonArt(btn)
    end
    local label = btn.label
    local function applyLabel(color)
        if label and label.SetTextColor and color then
            label:SetTextColor(color[1], color[2], color[3])
        end
    end
    local function restore(self)
        if self.IsEnabled and not self:IsEnabled() then
            applyLabel(Theme.BUTTON_TEXT.disabled)
        elseif self._selected then
            applyLabel(colors.highlight)
        else
            applyLabel(colors.normal)
        end
    end

    local origEnable, origDisable = btn.Enable, btn.Disable
    btn.Enable = function(self)
        if origEnable then origEnable(self) end
        if plain then setPanelArt(self, Theme.PANEL_BUTTON.up) end
        restore(self)
    end
    btn.Disable = function(self)
        if origDisable then origDisable(self) end
        if plain then setPanelArt(self, Theme.PANEL_BUTTON.disabled) end
        restore(self)
    end
    btn:HookScript("OnEnter", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        applyLabel(colors.highlight)
    end)
    btn:HookScript("OnLeave", restore)

    if isToggle then
        btn.SetSelected = function(self, on)
            self._selected = on
            if on and self.LockHighlight then
                self:LockHighlight()
            elseif self.UnlockHighlight then
                self:UnlockHighlight()
            end
            restore(self)
        end
    end
    if plain and btn.IsEnabled and not btn:IsEnabled() then
        setPanelArt(btn, Theme.PANEL_BUTTON.disabled)
    end
    restore(btn)
end

function Theme.SkinButton(btn, isToggle)
    if not btn or btn._skinned then return end
    btn._skinned = true

    if nativeChromeAvailable() then
        skinNativeButton(btn, isToggle, {
            normal = Theme.BUTTON_TEXT.normal,
            highlight = Theme.BUTTON_TEXT.highlight,
        })
        return
    end

    stripButtonTemplate(btn)

    Theme.ApplyBackdrop(btn, "button")
    setButtonTextColor(btn, C.btnText)

    -- Skinned buttons lose Blizzard disabled textures; keep a muted look in sync with Enable/Disable.
    local mutedBg = { 0.10, 0.10, 0.12, 1.00 }
    local mutedBorder = { 0.20, 0.18, 0.16, 0.70 }
    local mutedText = { 0.45, 0.45, 0.48, 1.00 }

    local function applyEnabledLook(self)
        if self._selected then
            applyButtonColors(self, C.btnActiveBg, C.btnActiveBorder)
            setButtonTextColor(self, C.btnTextHover)
        else
            applyButtonColors(self, C.btnBg, C.btnBorder)
            setButtonTextColor(self, C.btnText)
        end
    end

    local function applyDisabledLook(self)
        applyButtonColors(self, mutedBg, mutedBorder)
        setButtonTextColor(self, mutedText)
    end

    local function restoreNormal(self)
        if self.IsEnabled and not self:IsEnabled() then
            applyDisabledLook(self)
            return
        end
        applyEnabledLook(self)
    end

    local origEnable = btn.Enable
    local origDisable = btn.Disable
    btn.Enable = function(self)
        if origEnable then origEnable(self) end
        applyEnabledLook(self)
    end
    btn.Disable = function(self)
        if origDisable then origDisable(self) end
        applyDisabledLook(self)
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if self.IsEnabled and not self:IsEnabled() then return end
            if not self._selected then
                applyButtonColors(self, C.btnHoverBg, C.btnHoverBorder)
            end
            setButtonTextColor(self, C.btnTextHover)
        end)
        btn:HookScript("OnLeave", restoreNormal)
        btn:HookScript("OnMouseDown", function(self)
            if self.IsEnabled and not self:IsEnabled() then return end
            applyButtonColors(self, C.btnPressBg, C.btnBorder)
        end)
        btn:HookScript("OnMouseUp", restoreNormal)
    end

    if isToggle then
        btn.SetSelected = function(self, on)
            self._selected = on
            if self.IsEnabled and not self:IsEnabled() then
                applyDisabledLook(self)
                return
            end
            applyEnabledLook(self)
        end
    end

    if btn.IsEnabled and not btn:IsEnabled() then
        applyDisabledLook(btn)
    end
end

function Theme.SkinDangerButton(btn)
    if not btn or btn._skinned then return end
    btn._skinned = true
    if nativeChromeAvailable() then
        -- Template buttons render their own Text; tint it red since there is no btn.label.
        if not btn.label and btn.GetFontString then
            btn.label = btn:GetFontString()
        end
        skinNativeButton(btn, false, {
            normal = Theme.BUTTON_TEXT.danger,
            highlight = Theme.BUTTON_TEXT.dangerHighlight,
        })
        return
    end
    stripButtonTemplate(btn)
    Theme.ApplyBackdrop(btn, "button")
    applyButtonColors(btn, C.btnDangerBg, C.btnDangerBorder)
    setButtonTextColor(btn, C.btnDangerText)

    local function restoreNormal(self)
        applyButtonColors(self, C.btnDangerBg, C.btnDangerBorder)
        setButtonTextColor(self, C.btnDangerText)
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            applyButtonColors(self, C.btnDangerHoverBg, C.btnDangerHoverBorder)
            setButtonTextColor(self, C.red)
        end)
        btn:HookScript("OnLeave", restoreNormal)
        btn:HookScript("OnMouseDown", function(self)
            applyButtonColors(self, C.btnDangerPressBg, C.btnDangerBorder)
        end)
        btn:HookScript("OnMouseUp", restoreNormal)
    end
end

function Theme.InstallHoverTint(target, layerOrBandHeight, bandCenter, bandYOffset)
    if not target or target.altArmyHoverTint then return end
    local layer = "BACKGROUND"
    local bandHeight = nil
    if type(layerOrBandHeight) == "string" then
        layer = layerOrBandHeight
    elseif type(layerOrBandHeight) == "number" then
        bandHeight = layerOrBandHeight
    end
    bandYOffset = bandYOffset or 0
    local t = target:CreateTexture(nil, layer)
    if nativeChromeAvailable() then
        -- Same additive glow Blizzard lists (quest log, reputation, skills) use for hover.
        t:SetTexture(Theme.NATIVE_ROW_HIGHLIGHT)
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t.altArmyHoverOnAlpha = Theme.NATIVE_ROW_HIGHLIGHT_ALPHA
    else
        t:SetTexture(Theme.HOVER_TINT_BG)
    end
    if bandHeight then
        t:SetPoint("LEFT", target, "LEFT", 0, bandYOffset)
        t:SetPoint("RIGHT", target, "RIGHT", 0, bandYOffset)
        t:SetHeight(bandHeight)
        if bandCenter then
            t:SetPoint("CENTER", target, "CENTER", 0, bandYOffset)
        else
            t:SetPoint("TOP", target, "TOP", 0, bandYOffset)
        end
    else
        t:SetAllPoints(true)
    end
    t:SetVertexColor(1, 1, 1, 0)
    target.altArmyHoverTint = t
end

function Theme.SetHoverTint(target, on)
    local t = target and target.altArmyHoverTint
    if t then
        t:SetVertexColor(1, 1, 1, on and (t.altArmyHoverOnAlpha or Theme.HOVER_TINT_ALPHA) or 0)
    end
end

--- Tab-strip settings gear: yellow square glow on hover (matches active settings state).
function Theme.InstallSettingsButtonGlow(btn, key)
    if not btn then return nil end
    key = key or "glow"
    if btn[key] then return btn[key] end
    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    Theme.ApplySettingsGlow(glow)
    glow:Hide()
    btn[key] = glow
    return glow
end

function Theme.SetSettingsButtonGlow(btn, on, key)
    local glow = btn and btn[key or "glow"]
    if glow and glow.SetShown then
        glow:SetShown(on)
    end
end

function Theme.SkinSettingsIconButton(btn)
    if not btn or btn._settingsIconSkinned then return end
    btn._settingsIconSkinned = true

    Theme.InstallSettingsButtonGlow(btn, "hoverGlow")

    local function setHoverGlow(on)
        if btn.glow and btn.glow.IsShown and btn.glow:IsShown() then
            return
        end
        Theme.SetSettingsButtonGlow(btn, on, "hoverGlow")
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function()
            setHoverGlow(true)
        end)
        btn:HookScript("OnLeave", function()
            setHoverGlow(false)
        end)
    end
end

--- Wire OnEnter/OnLeave row highlight (Graphs Compare panel style).
function Theme.BindInteractableHover(target, opts)
    if not target then return end
    opts = opts or {}
    Theme.InstallHoverTint(target, opts.bandHeight or opts.layer, opts.bandCenter, opts.bandYOffset)
    local function onEnter()
        Theme.SetHoverTint(target, true)
        if opts.onEnter then opts.onEnter(target) end
    end
    local function onLeave()
        Theme.SetHoverTint(target, false)
        if opts.onLeave then opts.onLeave(target) end
    end
    if target.EnableMouse then target:EnableMouse(true) end
    target:SetScript("OnEnter", onEnter)
    target:SetScript("OnLeave", onLeave)
    if opts.children then
        for i = 1, #opts.children do
            local child = opts.children[i]
            if child then
                if child.EnableMouse then child:EnableMouse(true) end
                child:SetScript("OnEnter", onEnter)
                child:SetScript("OnLeave", onLeave)
            end
        end
    end
    return onEnter, onLeave
end

function Theme.InstallRowHoverHighlight(row)
    if not row or row.altArmyRowHighlight then return end
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture(BG_FILE)
    highlight:SetAllPoints(row)
    highlight:SetVertexColor(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    row:SetHighlightTexture(highlight)
    row.altArmyRowHighlight = highlight
end

function Theme.InstallRowAccentBar(row)
    if not row or row.altArmyAccentBar then return end
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(2)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetColorTexture(C.rowAccent[1], C.rowAccent[2], C.rowAccent[3], C.rowAccent[4])
    bar:Hide()
    row.altArmyAccentBar = bar
end

function Theme.SetRowSelected(row, on)
    if not row then return end
    if row.altArmyRowBg and row.altArmyRowBg.SetVertexColor then
        if on then
            row.altArmyRowBg:SetVertexColor(C.rowSelected[1], C.rowSelected[2], C.rowSelected[3], C.rowSelected[4])
        else
            row.altArmyRowBg:SetVertexColor(0, 0, 0, 0)
        end
    end
    if row.altArmyAccentBar then
        if on then row.altArmyAccentBar:Show() else row.altArmyAccentBar:Hide() end
    end
end

Theme.SCROLL_KNOB_TEXTURE = "Interface\\Buttons\\UI-ScrollBar-Knob"
Theme.SCROLL_THUMB_LENGTH = 24
Theme.SCROLL_BAR_WIDTH = 14
Theme.SCROLL_BAR_GAP = 2 -- space between scroll viewport and track
Theme.SCROLL_BAR_RIGHT_INSET = 4 -- track ends this far inside the bronze border (Graphs Compare panel)

function Theme.StyleScrollKnob(texture)
    if texture then
        texture:SetTexture(Theme.SCROLL_KNOB_TEXTURE)
    end
end

--- @deprecated use StyleScrollKnob or SetupScrollBar
function Theme.StyleScrollThumb(texture)
    Theme.StyleScrollKnob(texture)
end

function Theme.StyleScrollTrack(texture)
    if not texture then return end
    local track = C.scrollTrack
    texture:SetColorTexture(track[1], track[2], track[3], track[4])
end

-- MinimalScrollBar art (Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml; same atlas names
-- on Forever and TBC Anniversary). Drawn onto our Slider so callers keep the Slider API.
-- The Slider's thumb is an invisible hit texture `stepperInset` longer at each end than the
-- visible thumb, so the visible thumb travels only between the two arrow stepper buttons
-- (MinimalScrollBar insets its track 19px for them) without resizing the caller's Slider.
Theme.MINIMAL_SCROLL = {
    width = 8,
    stepperInset = 19,
    stepperSize = { 17, 11 },
    minStep = 16,
    repeatDelay = 0.35,
    repeatInterval = 0.06,
    track = { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom" },
    thumbUp = {
        "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-middle",
        "minimal-scrollbar-small-thumb-bottom",
    },
    thumbOver = {
        "minimal-scrollbar-small-thumb-top-over", "minimal-scrollbar-small-thumb-middle-over",
        "minimal-scrollbar-small-thumb-bottom-over",
    },
    back = { normal = "minimal-scrollbar-arrow-top", over = "minimal-scrollbar-arrow-top-over",
        down = "minimal-scrollbar-arrow-top-down" },
    forward = { normal = "minimal-scrollbar-arrow-bottom", over = "minimal-scrollbar-arrow-bottom-over",
        down = "minimal-scrollbar-arrow-bottom-down" },
}

local function nativeScrollBarsAvailable()
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    return caps and caps.minimalScrollBar or false
end

local function atlasInfo(atlas)
    local tex = _G.C_Texture
    if not tex or not tex.GetAtlasInfo then return nil end
    local ok, info = pcall(tex.GetAtlasInfo, atlas)
    return ok and info or nil
end

--- Cap length along the scroll axis (atlas height of the vertical art).
local function capLength(atlas)
    local info = atlasInfo(atlas)
    return info and info.height or 4
end

--- Vertical bars use the atlas directly; horizontal bars draw it rotated 90 degrees so the
--- vertical art's top becomes the left end.
local function setBarAtlas(tex, atlas, horizontal)
    if not horizontal then
        tex:SetAtlas(atlas)
        return
    end
    local info = atlasInfo(atlas)
    if not info then
        tex:SetColorTexture(0.45, 0.45, 0.45, 1)
        return
    end
    tex:SetTexture(info.file or info.filename)
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    tex:SetTexCoord(r, t, l, t, r, b, l, b)
end

local function setThumbAtlases(slider, set)
    local horizontal = slider.altArmyNativeHorizontal
    local art = slider.altArmyNativeThumb
    setBarAtlas(art.Begin, set[1], horizontal)
    setBarAtlas(art.Middle, set[2], horizontal)
    setBarAtlas(art.End, set[3], horizontal)
end

--- Size a cap along the scroll axis; `across` is the bar's visual thickness.
local function sizeAlong(tex, horizontal, along, across)
    if horizontal then
        tex:SetSize(along, across)
    else
        tex:SetSize(across, along)
    end
end

--- Anchor offsets that move `inset` px inward from the start / end edge.
local function insetOffsets(horizontal, inset)
    if horizontal then
        return inset, 0, -inset, 0
    end
    return 0, -inset, 0, inset
end

local function stepSlider(slider, direction)
    local M = Theme.MINIMAL_SCROLL
    local step = slider.GetValueStep and slider:GetValueStep() or 0
    if not step or step < M.minStep then
        step = M.minStep
    end
    local lo, hi = slider:GetMinMaxValues()
    local value = (slider:GetValue() or 0) + direction * step
    slider:SetValue(math.max(lo or 0, math.min(hi or 0, value)))
end

--- Like MinimalScrollBar's steppers: an arrow is disabled (normal art, desaturated, inert) when the
--- value already sits at its end or there is nothing to scroll.
local function isStepperEnabled(slider, direction)
    local lo, hi = slider:GetMinMaxValues()
    lo, hi = lo or 0, hi or 0
    if hi - lo < 0.5 then
        return false
    end
    local value = slider:GetValue() or 0
    if direction < 0 then
        return value > lo + 0.5
    end
    return value < hi - 0.5
end

local function refreshSteppers(slider)
    local back, fwd = slider.altArmyStepBack, slider.altArmyStepForward
    if back then back.altArmyRefresh() end
    if fwd then fwd.altArmyRefresh() end
end

--- Arrow button at one end of the bar; click steps, holding repeats.
local function createStepper(slider, horizontal, direction, art)
    local M = Theme.MINIMAL_SCROLL
    local btn = CreateFrame("Button", nil, slider)
    if horizontal then
        btn:SetSize(M.stepperSize[2], M.stepperSize[1])
    else
        btn:SetSize(M.stepperSize[1], M.stepperSize[2])
    end
    if btn.SetFrameLevel and slider.GetFrameLevel then
        btn:SetFrameLevel((slider:GetFrameLevel() or 0) + 2)
    end
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetAllPoints(btn)
    btn.altArmyArrow = arrow
    local enabled = true
    local function show(state)
        setBarAtlas(arrow, art[enabled and state or "normal"], horizontal)
    end

    local held, elapsed = false, 0
    local function stopRepeat(self)
        held = false
        self:SetScript("OnUpdate", nil)
    end

    function btn.altArmyRefresh()
        local now = isStepperEnabled(slider, direction)
        if now == enabled and btn.altArmyStateApplied then return end
        enabled = now
        btn.altArmyStateApplied = true
        btn.altArmyEnabled = enabled
        if arrow.SetDesaturated then
            arrow:SetDesaturated(not enabled)
        end
        if not enabled then
            stopRepeat(btn)
        end
        show(enabled and btn.IsMouseOver and btn:IsMouseOver() and "over" or "normal")
    end

    btn:SetScript("OnClick", function()
        if not enabled then return end
        stepSlider(slider, direction)
    end)
    btn:SetScript("OnMouseDown", function(self)
        if not enabled then return end
        show("down")
        held, elapsed = true, -M.repeatDelay
        self:SetScript("OnUpdate", function(_, dt)
            if not held then return end
            elapsed = elapsed + (dt or 0)
            if elapsed >= M.repeatInterval then
                elapsed = 0
                stepSlider(slider, direction)
            end
        end)
    end)
    btn:SetScript("OnMouseUp", function(self)
        show(self.IsMouseOver and self:IsMouseOver() and "over" or "normal")
        stopRepeat(self)
    end)
    btn:SetScript("OnEnter", function() show("over") end)
    btn:SetScript("OnLeave", function() show("normal") end)
    btn:SetScript("OnHide", stopRepeat)
    return btn
end

local function setupNativeScrollBar(slider, horizontal, thumbLength)
    local M = Theme.MINIMAL_SCROLL
    local S = M.stepperInset
    local startPoint, endPoint = "TOP", "BOTTOM"
    local midStart, midEnd = { "TOPLEFT", "BOTTOMLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" }
    if horizontal then
        startPoint, endPoint = "LEFT", "RIGHT"
        midStart, midEnd = { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" }
    end
    local sx, sy, ex, ey = insetOffsets(horizontal, S)
    slider.altArmyNativeHorizontal = horizontal

    local track = slider.altArmyNativeTrack
    if not track then
        track = {
            Begin = slider:CreateTexture(nil, "BACKGROUND"),
            Middle = slider:CreateTexture(nil, "BACKGROUND"),
            End = slider:CreateTexture(nil, "BACKGROUND"),
        }
        slider.altArmyNativeTrack = track
    end
    setBarAtlas(track.Begin, M.track[1], horizontal)
    setBarAtlas(track.Middle, M.track[2], horizontal)
    setBarAtlas(track.End, M.track[3], horizontal)
    sizeAlong(track.Begin, horizontal, capLength(M.track[1]), M.width)
    sizeAlong(track.End, horizontal, capLength(M.track[3]), M.width)
    track.Begin:ClearAllPoints()
    track.Begin:SetPoint(startPoint, slider, startPoint, sx, sy)
    track.End:ClearAllPoints()
    track.End:SetPoint(endPoint, slider, endPoint, ex, ey)
    track.Middle:ClearAllPoints()
    track.Middle:SetPoint(midStart[1], track.Begin, midStart[2], 0, 0)
    track.Middle:SetPoint(midEnd[1], track.End, midEnd[2], 0, 0)

    -- Invisible hit thumb (positioned by the Slider); visible art is anchored inside it.
    local thumb = slider.altArmyScrollThumb
    if not thumb then
        thumb = slider:CreateTexture(nil, "OVERLAY")
        slider.altArmyScrollThumb = thumb
    end
    thumb:SetColorTexture(0, 0, 0, 0)
    sizeAlong(thumb, horizontal, thumbLength + 2 * S, M.width)

    local art = slider.altArmyNativeThumb
    if not art then
        art = {
            Begin = slider:CreateTexture(nil, "OVERLAY", nil, 1),
            Middle = slider:CreateTexture(nil, "OVERLAY", nil, 1),
            End = slider:CreateTexture(nil, "OVERLAY", nil, 1),
        }
        slider.altArmyNativeThumb = art
        -- Thumb is a texture (no mouse events); highlight it while the bar is hovered.
        slider:HookScript("OnEnter", function(self)
            setThumbAtlases(self, Theme.MINIMAL_SCROLL.thumbOver)
        end)
        slider:HookScript("OnLeave", function(self)
            setThumbAtlases(self, Theme.MINIMAL_SCROLL.thumbUp)
        end)
    end
    sizeAlong(art.Begin, horizontal, capLength(M.thumbUp[1]), M.width)
    sizeAlong(art.End, horizontal, capLength(M.thumbUp[3]), M.width)
    art.Begin:ClearAllPoints()
    art.Begin:SetPoint(startPoint, thumb, startPoint, sx, sy)
    art.End:ClearAllPoints()
    art.End:SetPoint(endPoint, thumb, endPoint, ex, ey)
    art.Middle:ClearAllPoints()
    art.Middle:SetPoint(midStart[1], art.Begin, midStart[2], 0, 0)
    art.Middle:SetPoint(midEnd[1], art.End, midEnd[2], 0, 0)
    setThumbAtlases(slider, M.thumbUp)

    if not slider.altArmyStepBack then
        slider.altArmyStepBack = createStepper(slider, horizontal, -1, M.back)
        slider.altArmyStepForward = createStepper(slider, horizontal, 1, M.forward)
        slider:HookScript("OnValueChanged", refreshSteppers)
        slider:HookScript("OnMinMaxChanged", refreshSteppers)
    end
    refreshSteppers(slider)
    slider.altArmyStepBack:ClearAllPoints()
    slider.altArmyStepBack:SetPoint(startPoint, slider, startPoint, 0, 0)
    slider.altArmyStepForward:ClearAllPoints()
    slider.altArmyStepForward:SetPoint(endPoint, slider, endPoint, 0, 0)

    slider:SetThumbTexture(thumb)
    return thumb
end

--- Apply scrollbar chrome to a Slider: native MinimalScrollBar art when the client has it,
--- else the legacy dark track + Blizzard knob thumb.
--- opts.thickness: bar width (vertical) or height (horizontal); defaults from slider size.
--- opts.thumbLength: knob length along the scroll axis (default 24).
--- opts.horizontal: true for horizontal scroll bars.
function Theme.SetupScrollBar(slider, opts)
    if not slider then return nil end
    opts = opts or {}
    local horizontal = opts.horizontal == true
    local thumbLength = opts.thumbLength or Theme.SCROLL_THUMB_LENGTH
    if nativeScrollBarsAvailable() then
        return setupNativeScrollBar(slider, horizontal, thumbLength)
    end
    local thickness = opts.thickness
    if not thickness then
        if horizontal and slider.GetHeight then
            thickness = slider:GetHeight() or 14
        elseif slider.GetWidth then
            thickness = slider:GetWidth() or 14
        else
            thickness = 14
        end
    end

    if not slider.altArmyScrollTrack then
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(slider)
        slider.altArmyScrollTrack = track
    end
    Theme.StyleScrollTrack(slider.altArmyScrollTrack)

    local thumb = slider.altArmyScrollThumb
    if not thumb then
        thumb = slider:CreateTexture(nil, "OVERLAY")
        slider.altArmyScrollThumb = thumb
    end
    if horizontal then
        thumb:SetSize(thumbLength, thickness + 4)
    else
        thumb:SetSize(thickness + 4, thumbLength)
    end
    Theme.StyleScrollKnob(thumb)
    slider:SetThumbTexture(thumb)
    return thumb
end

--- Horizontal space reserved beside a vertical scroll viewport (inset + track + gap).
function Theme.VerticalScrollBarGutter(opts)
    opts = opts or {}
    local w = opts.width or Theme.SCROLL_BAR_WIDTH
    local gap = opts.gap or Theme.SCROLL_BAR_GAP
    local inset = opts.rightInset
    if inset == nil then
        inset = Theme.SCROLL_BAR_RIGHT_INSET
    end
    return w + gap + inset
end

--- Anchor a vertical scrollbar beside scrollFrame; track ends rightInset inside gutterEdge's right edge.
--- scrollFrame should end at -(VerticalScrollBarGutter()) from gutterEdge's right edge.
--- Sets scrollBar.altArmyAnchorX (x offset used) so callers can re-anchor one end consistently.
function Theme.AnchorVerticalScrollBar(scrollBar, _gutterEdge, scrollFrame, opts)
    if not scrollBar or not scrollFrame then return scrollBar end
    opts = opts or {}
    local w = opts.width or Theme.SCROLL_BAR_WIDTH
    local gap = opts.gap or Theme.SCROLL_BAR_GAP
    if scrollBar.altArmyNativeScrollBar then
        -- Real MinimalScrollBar keeps its template width; center it in the gutter track slot.
        local barW = scrollBar:GetWidth() or Theme.MINIMAL_SCROLL.width
        local x = gap + math.max(0, (w - barW) / 2)
        scrollBar.altArmyAnchorX = x
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", x, 0)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", x, 0)
        return scrollBar
    end
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(w)
    scrollBar.altArmyAnchorX = gap
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", gap, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", gap, 0)
    Theme.SetupScrollBar(scrollBar, { thickness = w, thumbLength = opts.thumbLength })
    return scrollBar
end

-- Native mode: pinned-header fades read as a soft shadow over the textured inset background.
Theme.NATIVE_SCROLL_SHADOW = { 0, 0, 0, 0.55 }

--- Opaque fill for pinned grid headers / label columns (must hide rows scrolling beneath).
function Theme.StyleGridHeader(texture)
    if not texture then return end
    if nativeChromeAvailable() then
        texture:SetTexture(Theme.NATIVE_TIERS.section.bg, "REPEAT", "REPEAT")
        if texture.SetHorizTile then texture:SetHorizTile(true) end
        if texture.SetVertTile then texture:SetVertTile(true) end
        return
    end
    local hdr = C.gridHeaderBg
    texture:SetColorTexture(hdr[1], hdr[2], hdr[3], hdr[4])
end

--- The yellow sort arrow Blizzard's column headers draw (the Who frame, the auction house; Altoholic's too):
--- one texture, pointing down, flipped vertically for ascending. `gap` is the space between text and arrow.
Theme.SORT_ARROW = {
    texture = "Interface\\Buttons\\UI-SortArrow",
    width = 9,
    height = 8,
    gap = 3,
    -- On a sort-direction button (Theme.SetSortArrowButton) it is drawn larger: across its base, along its point.
    buttonWidth = 14,
    buttonHeight = 12,
    buttonNudge = 1, -- a left or right arrow sits this far off centre, towards where it points
}

--- Point a sort arrow texture "up", "down", "left" or "right" and size it to match. The art points down in
--- the left 0.5625 of the file: up flips it, and left and right turn it a quarter (each corner's coords given).
local function PointSortArrow(arrow, direction, across, along)
    local spec, r = Theme.SORT_ARROW, 0.5625
    across, along = across or spec.width, along or spec.height
    if direction == "left" or direction == "right" then
        arrow:SetSize(along, across)
        if direction == "right" then
            arrow:SetTexCoord(0, 0, r, 0, 0, 1, r, 1)
        else
            arrow:SetTexCoord(0, 1, r, 1, 0, 0, r, 0)
        end
    else
        arrow:SetSize(across, along)
        if direction == "up" then
            arrow:SetTexCoord(0, r, 1, 0)
        else
            arrow:SetTexCoord(0, r, 0, 1)
        end
    end
end

--- Show the sort arrow centred on a small sort-direction button, pointing `direction` ("up", "down", "left",
--- "right"). The texture is made once per button.
function Theme.SetSortArrowButton(btn, direction)
    if not btn then return end
    local arrow = btn.altArmySortArrow
    if not arrow then
        arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(Theme.SORT_ARROW.texture)
        btn.altArmySortArrow = arrow
    end
    local nudge = Theme.SORT_ARROW.buttonNudge
    local x = (direction == "right" and nudge) or (direction == "left" and -nudge) or 0
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", btn, "CENTER", x, 0)
    PointSortArrow(arrow, direction, Theme.SORT_ARROW.buttonWidth, Theme.SORT_ARROW.buttonHeight)
    arrow:Show()
end

--- Set a sortable column header's text and, when `isSorted`, show the sort arrow beside it (up = low→high,
--- down = high→low), else hide it. The arrow is a texture on the label's parent, made once per label; it sits
--- after the text of a left- or centre-justified label and before the text of a right-justified one, so it
--- stays inside the header's cell.
function Theme.SetSortHeaderLabel(label, baseLabel, isSorted, ascending)
    if not label then return end
    label:SetText(baseLabel or "")
    local arrow = label.altArmySortArrow
    if not isSorted then
        if arrow then arrow:Hide() end
        return
    end
    local spec = Theme.SORT_ARROW
    if not arrow then
        arrow = label:GetParent():CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(spec.texture)
        label.altArmySortArrow = arrow
    end
    PointSortArrow(arrow, ascending and "up" or "down")
    local textWidth = label:GetStringWidth() or 0
    local justify = label.GetJustifyH and label:GetJustifyH() or "LEFT"
    arrow:ClearAllPoints()
    if justify == "RIGHT" then
        arrow:SetPoint("RIGHT", label, "RIGHT", -(textWidth + spec.gap), 0)
    elseif justify == "CENTER" then
        arrow:SetPoint("LEFT", label, "CENTER", textWidth / 2 + spec.gap, 0)
    else
        arrow:SetPoint("LEFT", label, "LEFT", textWidth + spec.gap, 0)
    end
    arrow:Show()
end

--- Opaque gridHeaderBg fill for a pinned row/column label area (Gear slots, Reputation factions).
function Theme.ApplyGridLabelColumnBackground(frame)
    if not frame then return nil end
    if not frame.altArmyLabelColBg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        frame.altArmyLabelColBg = bg
    end
    Theme.StyleGridHeader(frame.altArmyLabelColBg)
    return frame.altArmyLabelColBg
end

Theme.PINNED_HEADER_SCROLL_FADE_HEIGHT = 20
Theme.PINNED_HORIZONTAL_SCROLL_FADE_WIDTH = 20
-- Matches TabGear / TabReputation HEADER_BG_BOTTOM_INSET (header bg stops above frame bottom).
Theme.GRID_HEADER_BG_BOTTOM_INSET = 6
local SCROLL_FADE_TEX = "Interface\\AddOns\\AltArmy_TBC\\Textures\\ScrollFade"

local function ApplyScrollFadeTexture(fadeFrame, color, orientation)
    if not fadeFrame or not color then return end
    if nativeChromeAvailable() then
        color = Theme.NATIVE_SCROLL_SHADOW
    end
    local tex = fadeFrame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(fadeFrame)
    tex:SetTexture(SCROLL_FADE_TEX)
    if orientation == "horizontal" then
        -- ScrollFade.tga is opaque at the top (v=0), transparent at the bottom (v=1).
        -- Map left edge to opaque, right edge to transparent.
        tex:SetTexCoord(0, 0, 0, 0, 1, 1, 1, 1)
    end
    tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

--- Gradient strip just below a pinned grid header; visible when vertical scroll offset > 0.
--- opts: headerFrame, scrollFrame, scrollBar, height, colorKey (Theme.COLORS key, default gridHeaderBg)
function Theme.CreatePinnedHeaderScrollFade(opts)
    opts = opts or {}
    local headerFrame = opts.headerFrame
    if not headerFrame then return { frame = nil, Update = function() end } end

    local height = opts.height or Theme.PINNED_HEADER_SCROLL_FADE_HEIGHT
    local colorKey = opts.colorKey or "gridHeaderBg"
    local fadeColor = C[colorKey] or C.gridHeaderBg
    local topOverlap = opts.headerBottomInset
    if topOverlap == nil then
        topOverlap = Theme.GRID_HEADER_BG_BOTTOM_INSET
    end

    -- Sibling overlay in the scroll viewport; sits just above scrolling content, below header chrome.
    local viewport = headerFrame.GetParent and headerFrame:GetParent() or headerFrame
    local headerLevel = headerFrame.GetFrameLevel and headerFrame:GetFrameLevel() or 0
    local fadeFrame = CreateFrame("Frame", nil, viewport)
    -- Align with the visible bottom of StyleGridHeader bg, not the header frame bottom.
    fadeFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, topOverlap)
    fadeFrame:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, topOverlap)
    fadeFrame:SetHeight(height)
    fadeFrame:SetFrameLevel(headerLevel + 50)
    fadeFrame:EnableMouse(false)
    ApplyScrollFadeTexture(fadeFrame, fadeColor)
    fadeFrame:Hide()

    local scrollFrame = opts.scrollFrame
    local scrollBar = opts.scrollBar

    local function getScrollOffset()
        if opts.getOffset then
            return opts.getOffset() or 0
        end
        if scrollBar and scrollBar.GetValue then
            return scrollBar:GetValue() or 0
        end
        if scrollFrame and scrollFrame.GetVerticalScroll then
            return scrollFrame:GetVerticalScroll() or 0
        end
        return 0
    end

    local function update()
        if getScrollOffset() > 0 then
            fadeFrame:Show()
        else
            fadeFrame:Hide()
        end
    end

    update()
    return { frame = fadeFrame, Update = update }
end

--- Vertical gradient strip on the left edge of a horizontally scrolling viewport; visible when scroll offset > 0.
--- opts: anchorScrollFrame, scrollFrame, scrollBar, width, colorKey
function Theme.CreatePinnedHorizontalScrollFade(opts)
    opts = opts or {}
    local anchorScrollFrame = opts.anchorScrollFrame
    if not anchorScrollFrame then return { frame = nil, Update = function() end } end

    local width = opts.width or Theme.PINNED_HORIZONTAL_SCROLL_FADE_WIDTH
    local colorKey = opts.colorKey or "gridHeaderBg"
    local fadeColor = C[colorKey] or C.gridHeaderBg

    local parent = anchorScrollFrame.GetParent and anchorScrollFrame:GetParent() or anchorScrollFrame
    local scrollLevel = anchorScrollFrame.GetFrameLevel and anchorScrollFrame:GetFrameLevel() or 0
    local fadeFrame = CreateFrame("Frame", nil, parent)
    fadeFrame:SetPoint("TOPLEFT", anchorScrollFrame, "TOPLEFT", 0, 0)
    fadeFrame:SetPoint("BOTTOMLEFT", anchorScrollFrame, "BOTTOMLEFT", 0, 0)
    fadeFrame:SetWidth(width)
    fadeFrame:SetFrameLevel(scrollLevel + 50)
    fadeFrame:EnableMouse(false)
    ApplyScrollFadeTexture(fadeFrame, fadeColor, "horizontal")
    fadeFrame:Hide()

    local scrollFrame = opts.scrollFrame or anchorScrollFrame
    local scrollBar = opts.scrollBar

    local function getScrollOffset()
        if scrollBar and scrollBar.GetValue then
            return scrollBar:GetValue() or 0
        end
        if scrollFrame and scrollFrame.GetHorizontalScroll then
            return scrollFrame:GetHorizontalScroll() or 0
        end
        return 0
    end

    local function update()
        if getScrollOffset() > 0 then
            fadeFrame:Show()
        else
            fadeFrame:Hide()
        end
    end

    update()
    return { frame = fadeFrame, Update = update }
end

Theme.SETTINGS_PANEL_PADDING = 8
Theme.TAB_CONTENT_PADDING = 8
-- Section panels sit flush on the tab frame; Core CONTENT_INSET (8px) is the window-edge gutter.
Theme.TAB_SECTION_INSET = 0
-- Gap between adjacent section panels within a tab (Graphs tab graph | selector).
Theme.SECTION_GAP = 4

--- Bordered section panel for main tab content (matches settings panel styling).
function Theme.CreateTabContentPanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(panel, "section")
    return panel
end

--- Borderless panel for a main-window tab's top-level content (sits inside the window border).
function Theme.CreateMainContentPanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(panel, "content")
    return panel
end

--- Inset content area inside a bordered panel (keeps controls off the edge).
function Theme.CreatePanelInnerContent(panel, padding)
    local p = padding or Theme.TAB_CONTENT_PADDING
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", p, -p)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -p, p)
    return content
end

--- Inset content area inside a bordered settings panel (keeps controls off the edge).
function Theme.CreateSettingsPanelContent(panel)
    return Theme.CreatePanelInnerContent(panel, Theme.SETTINGS_PANEL_PADDING)
end

function Theme.CreateSeparator(parent, width)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    if width then
        sep:SetWidth(width)
    else
        sep:SetPoint("LEFT", parent, "LEFT", 0, 0)
        sep:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end
    local line = C.sepLine
    sep:SetColorTexture(line[1], line[2], line[3], line[4])
    return sep
end

-- InputBoxVisualTemplate border (same atlases and anchors on Forever and TBC Anniversary).
Theme.INPUT_BORDER = {
    left = "common-search-border-left",
    middle = "common-search-border-middle",
    right = "common-search-border-right",
    capWidth = 8,
    leftOffset = -5,
}

function Theme.ApplyInputTextures(editBox)
    if not editBox then return end
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    if caps and caps.inputBox then
        if editBox.altArmyInputLeft then return end
        local B = Theme.INPUT_BORDER
        local left = editBox:CreateTexture(nil, "BACKGROUND")
        left:SetAtlas(B.left)
        left:SetWidth(B.capWidth)
        left:SetPoint("LEFT", editBox, "LEFT", B.leftOffset, 0)
        left:SetPoint("TOP", editBox, "TOP", 0, 0)
        left:SetPoint("BOTTOM", editBox, "BOTTOM", 0, 0)
        local right = editBox:CreateTexture(nil, "BACKGROUND")
        right:SetAtlas(B.right)
        right:SetWidth(B.capWidth)
        right:SetPoint("RIGHT", editBox, "RIGHT", 0, 0)
        right:SetPoint("TOP", editBox, "TOP", 0, 0)
        right:SetPoint("BOTTOM", editBox, "BOTTOM", 0, 0)
        local middle = editBox:CreateTexture(nil, "BACKGROUND")
        middle:SetAtlas(B.middle)
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        editBox.altArmyInputLeft = left
        editBox.altArmyInputMiddle = middle
        editBox.altArmyInputRight = right
        return
    end
    if not editBox.altArmyInputBg then
        local bg = editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(editBox)
        editBox.altArmyInputBg = bg
        local border = editBox:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", editBox, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 1, -1)
        editBox.altArmyInputBorder = border
    end
    local ibg = C.inputBg
    local ibr = C.inputBorder
    editBox.altArmyInputBg:SetColorTexture(ibg[1], ibg[2], ibg[3], ibg[4])
    editBox.altArmyInputBorder:SetColorTexture(ibr[1], ibr[2], ibr[3], ibr[4])
end

Theme.SEARCH_INPUT_ICON = "Interface\\Common\\UI-Searchbox-Icon"

--- Small muted magnifying-glass on the left of a search/filter EditBox.
--- Returns the left text inset so typed text and placeholders clear the icon.
function Theme.ApplySearchInputIcon(editBox, options)
    if not editBox then return 0 end
    options = options or {}
    local size = options.size or 12
    local leftPad = options.leftPad or 3
    local gap = options.gap or 3
    local rightInset = options.rightInset or 6
    local icon = editBox.altArmySearchIcon
    if not icon then
        icon = editBox:CreateTexture(nil, "OVERLAY")
        editBox.altArmySearchIcon = icon
    end
    icon:SetSize(size, size)
    if icon.ClearAllPoints then
        icon:ClearAllPoints()
    end
    icon:SetPoint("LEFT", editBox, "LEFT", leftPad, -1)
    icon:SetTexture(Theme.SEARCH_INPUT_ICON)
    icon:SetVertexColor(0.55, 0.55, 0.55, 0.9)
    local leftInset = leftPad + size + gap
    if editBox.SetTextInsets then
        editBox:SetTextInsets(leftInset, rightInset, 0, 0)
    end
    return leftInset
end

--- Search EditBox: native SearchBoxTemplate (magnifier, clear button, Instructions placeholder)
--- when the client has it, else the custom icon + placeholder + input textures.
--- opts: name, width, height (default 20), placeholder. Returns editBox, isNative.
--- Callers should HookScript (not SetScript) so the template's own handlers keep running.
function Theme.CreateSearchBox(parent, opts)
    opts = opts or {}
    local NativeUI = AltArmy.NativeUI
    local native = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps().searchBox or false
    local height = opts.height or 20
    local box
    if native then
        box = CreateFrame("EditBox", opts.name, parent, "SearchBoxTemplate")
        box:SetSize(opts.width or 200, height)
        box:SetAutoFocus(false)
        if box.Instructions then
            box.Instructions:SetText(opts.placeholder or "")
        end
        return box, true
    end
    box = CreateFrame("EditBox", opts.name, parent)
    box:SetSize(opts.width or 200, height)
    box:SetAutoFocus(false)
    box:SetFontObject(Theme.FONTS.body)
    local clearSize = 14
    local leftInset = Theme.ApplySearchInputIcon(box, { rightInset = clearSize + 6 })
    Theme.SetupEditBoxPlaceholder(box, opts.placeholder or "", {
        leftInset = leftInset,
        rightInset = clearSize + 6,
    })
    Theme.ApplyInputTextures(box)

    -- Clear (X) inside the right edge, like SearchBoxTemplate's; shown only while there is text.
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(clearSize, clearSize)
    clear:SetPoint("RIGHT", box, "RIGHT", -3, 0)
    local clearLabel = clear:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    clearLabel:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clearLabel:SetText("x")
    clearLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    clear:SetScript("OnEnter", function() clearLabel:SetTextColor(1, 1, 1, 1) end)
    clear:SetScript("OnLeave", function() clearLabel:SetTextColor(0.6, 0.6, 0.6, 1) end)
    clear:SetScript("OnClick", function()
        Theme.ClearEditBoxText(box)
        clear:Hide()
    end)
    clear:Hide()
    box.altArmyClearButton = clear
    box:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        clear:SetShown(text:match("^%s*(.-)%s*$") ~= "")
    end)
    return box, false
end

local PLACEHOLDER_HINT_KEY = "altArmyPlaceholderHint"

local function trimmedEditBoxText(editBox)
    local text = editBox and editBox.GetText and editBox:GetText()
    return text and text:match("^%s*(.-)%s*$") or ""
end

--- Native SetPlaceholderText when available; otherwise a gray hint FontString child.
function Theme.SetupEditBoxPlaceholder(editBox, placeholderText, options)
    if not editBox then return end
    options = options or {}
    local leftInset = options.leftInset or 6
    local rightInset = options.rightInset or 6
    local yOffset = options.yOffset or 0
    if editBox.SetPlaceholderText then
        editBox:SetPlaceholderText(placeholderText or "")
        return
    end
    local hint = editBox[PLACEHOLDER_HINT_KEY]
    if not hint then
        hint = editBox:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        hint:SetPoint("LEFT", editBox, "LEFT", leftInset, yOffset)
        hint:SetPoint("RIGHT", editBox, "RIGHT", -rightInset, yOffset)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(0.5, 0.5, 0.5, 1)
        editBox[PLACEHOLDER_HINT_KEY] = hint
    end
    hint:SetText(placeholderText or "")
    Theme.UpdateEditBoxPlaceholderVisibility(editBox)
end

--- Copy ref's input font (and its placeholder font) onto editBox so toolbar search boxes match.
function Theme.MatchSearchBoxFont(editBox, ref)
    if not editBox or not ref then return end
    local fontObject = ref.GetFontObject and ref:GetFontObject()
    if fontObject then
        editBox:SetFontObject(fontObject)
    end
    local hint = editBox[PLACEHOLDER_HINT_KEY]
    if not hint then return end
    local refHint = ref.Instructions or ref[PLACEHOLDER_HINT_KEY]
    local hintFont = refHint and refHint.GetFontObject and refHint:GetFontObject()
    if hintFont then
        hint:SetFontObject(hintFont)
        hint:SetTextColor(0.5, 0.5, 0.5, 1)
    end
end

function Theme.SetEditBoxPlaceholderText(editBox, placeholderText)
    if not editBox then return end
    -- SearchBoxTemplate: its own Instructions FontString (shown/hidden by the template).
    if editBox.Instructions and editBox.Instructions.SetText then
        editBox.Instructions:SetText(placeholderText or "")
        return
    end
    if editBox.SetPlaceholderText then
        editBox:SetPlaceholderText(placeholderText or "")
        return
    end
    local hint = editBox[PLACEHOLDER_HINT_KEY]
    if hint then
        hint:SetText(placeholderText or "")
    end
    Theme.UpdateEditBoxPlaceholderVisibility(editBox)
end

--- Show the fallback placeholder whenever the field is empty (including while focused).
function Theme.UpdateEditBoxPlaceholderVisibility(editBox)
    local hint = editBox and editBox[PLACEHOLDER_HINT_KEY]
    if not hint then return end
    if trimmedEditBoxText(editBox) == "" then
        hint:Show()
    else
        hint:Hide()
    end
end

function Theme.ClearEditBoxText(editBox)
    if not editBox then return end
    if editBox.SetText then
        editBox:SetText("")
    end
    if editBox.ClearFocus then
        editBox:ClearFocus()
    end
    Theme.UpdateEditBoxPlaceholderVisibility(editBox)
end

--- Set EditBox text and reset the cursor to the start.
--- WoW leaves the cursor at the end after SetText; when the box was sized while hidden
--- that scrolls the value out of view, so the field looks empty and later typing appends.
function Theme.SetEditBoxText(editBox, text)
    if not editBox or not editBox.SetText then return end
    editBox:SetText(text or "")
    if editBox.SetCursorPosition then
        editBox:SetCursorPosition(0)
    end
    Theme.UpdateEditBoxPlaceholderVisibility(editBox)
end

--- Wire placeholder refresh on text/focus changes. onTextChanged(editBox, isUserInput) optional.
function Theme.BindEditBoxPlaceholderHandlers(editBox, onTextChanged)
    if not editBox then return end
    editBox:SetScript("OnTextChanged", function(self, isUserInput)
        Theme.UpdateEditBoxPlaceholderVisibility(self)
        if onTextChanged then
            onTextChanged(self, isUserInput)
        end
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        Theme.UpdateEditBoxPlaceholderVisibility(self)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        Theme.UpdateEditBoxPlaceholderVisibility(self)
    end)
end

function Theme.SetTitleColor(fontString)
    if fontString and fontString.SetTextColor then
        local t = C.title
        fontString:SetTextColor(t[1], t[2], t[3], t[4])
    end
end

function Theme.SetGroupHeaderColor(fontString)
    if fontString and fontString.SetTextColor then
        local g = C.groupHeader
        fontString:SetTextColor(g[1], g[2], g[3], g[4])
    end
end

function Theme.SetLabelColor(fontString)
    if fontString and fontString.SetTextColor then
        local l = C.label
        fontString:SetTextColor(l[1], l[2], l[3], l[4])
    end
end

function Theme.ApplyHeaderBar(texture)
    if not texture then return end
    local h = C.headerBg
    texture:SetColorTexture(h[1], h[2], h[3], h[4])
end

function Theme.ApplySettingsGlow(texture)
    if not texture then return end
    local g = C.settingsGlow
    texture:SetColorTexture(g[1], g[2], g[3], g[4])
end

--- Alpha for a pulsing attention highlight. Returns nil when `elapsed >= duration`.
function Theme.AttentionFlashAlpha(elapsed, duration, pulses)
    duration = duration or 2
    pulses = pulses or 3
    if not elapsed or elapsed < 0 or elapsed >= duration or duration <= 0 then
        return nil
    end
    local t = (elapsed / duration) * pulses * math.pi * 2
    return 0.35 + 0.65 * math.abs(math.sin(t))
end

--- Flash a yellow bordered highlight around `frame` to draw attention (e.g. options deep-link).
--- opts: duration (seconds), pulses, pad (pixels outside the frame)
function Theme.FlashAttentionHighlight(frame, opts)
    if not frame then return end
    opts = opts or {}
    local duration = opts.duration or 2.0
    local pulses = opts.pulses or 3
    local pad = opts.pad or 4

    local hl = frame.altArmyAttentionHighlight
    if not hl then
        hl = CreateFrame("Frame", nil, frame)
        hl:EnableMouse(false)
        Theme.ApplyLegacyBackdrop(hl, "tooltip")
        local g = C.settingsGlow
        if hl.SetBackdropBorderColor then
            hl:SetBackdropBorderColor(g[1], g[2], g[3], 1)
        end
        if hl.SetBackdropColor then
            hl:SetBackdropColor(g[1], g[2], g[3], 0.12)
        end
        frame.altArmyAttentionHighlight = hl
    end

    local level = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
    if hl.SetFrameLevel then
        hl:SetFrameLevel(level + 20)
    end
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    hl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    hl:SetAlpha(1)
    hl:Show()

    local elapsed = 0
    hl:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        local alpha = Theme.AttentionFlashAlpha(elapsed, duration, pulses)
        if not alpha then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        self:SetAlpha(alpha)
    end)
end

function Theme.StyleHorizontalScrollBar(slider, opts)
    if not slider then return end
    local o = opts or {}
    o.horizontal = true
    Theme.SetupScrollBar(slider, o)
end

--- Scale-aware horizontal drag math shared by tab horizontal scroll bars.
--- thumbLength: knob size along the scroll axis; the thumb travels (barWidth - thumbLength).
function Theme.HorizontalDragValue(startValue, cursorPx, startPx, scale, barWidth, minVal, maxVal, thumbLength)
    if not barWidth or barWidth <= 0 or not scale or scale <= 0 or maxVal <= minVal then
        return startValue
    end
    local cursorX = cursorPx / scale
    local startX = startPx / scale
    local deltaX = cursorX - startX
    local travel = barWidth - (thumbLength or 0)
    if travel <= 0 then
        travel = barWidth
    end
    local value = startValue + deltaX * (maxVal - minVal) / travel
    return math.max(minVal, math.min(maxVal, value))
end

--- Horizontal scrollbar with manual scale-aware thumb drag (TBC Slider workaround).
--- opts: name, thickness, onScroll(value), isShown() -> bool
function Theme.CreateHorizontalScrollBar(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("Slider", opts.name, parent)
    bar:SetOrientation("HORIZONTAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:EnableMouse(true)

    local thumbLength = opts.thumbLength or Theme.SCROLL_THUMB_LENGTH
    local lastValue = nil
    local dragging = false
    local dragStartX = 0
    local dragStartValue = 0

    local function apply(value)
        lastValue = value
        if opts.onScroll then
            opts.onScroll(value)
        end
    end

    local function sync()
        local value = bar:GetValue()
        if lastValue == value then return end
        apply(value)
    end

    local function stopDragging()
        if not dragging then return end
        dragging = false
        bar:SetScript("OnUpdate", nil)
        if opts.onDragEnd then opts.onDragEnd() end
    end

    bar:SetScript("OnValueChanged", function()
        sync()
    end)

    bar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        dragging = true
        dragStartX = select(1, GetCursorPosition())
        dragStartValue = bar:GetValue()
        if opts.onDragStart then opts.onDragStart() end
        bar:SetScript("OnUpdate", function()
            if opts.isShown and not opts.isShown() then return end
            if not dragging then return end
            if not IsMouseButtonDown(1) then
                stopDragging()
                return
            end
            local minVal, maxVal = bar:GetMinMaxValues()
            local barWidth = bar:GetWidth()
            if barWidth and barWidth > 0 and maxVal > minVal then
                local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale())
                    or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                if scale <= 0 then scale = 1 end
                local cursorX = select(1, GetCursorPosition())
                local value = Theme.HorizontalDragValue(
                    dragStartValue, cursorX, dragStartX, scale, barWidth, minVal, maxVal,
                    bar.altArmyThumbTravelLength or thumbLength)
                if lastValue == nil or math.abs(value - lastValue) >= 0.5 then
                    bar:SetValue(value)
                end
            end
        end)
    end)

    if opts.thickness then
        bar:SetHeight(opts.thickness)
    end
    -- Opaque backing so grid content scrolled beneath the bar does not show through the track.
    local backing = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    backing:SetAllPoints(bar)
    local bg = C.gridHeaderBg
    backing:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    bar.altArmyOpaqueBacking = backing
    Theme.SetupScrollBar(bar, {
        horizontal = true,
        thickness = opts.thickness,
        thumbLength = thumbLength,
    })
    -- Native bars use a longer invisible hit thumb (see Theme.MINIMAL_SCROLL.stepperInset).
    if bar.altArmyNativeThumb then
        bar.altArmyThumbTravelLength = thumbLength + 2 * Theme.MINIMAL_SCROLL.stepperInset
    end

    local api = {}
    api.bar = bar

    function api:SetRange(minVal, maxVal)
        bar:SetMinMaxValues(minVal, maxVal)
        -- OnMinMaxChanged may not fire when the value is unchanged; keep end arrows in sync.
        refreshSteppers(bar)
    end

    function api:Apply(value)
        apply(value)
    end

    function api:Sync()
        sync()
    end

    function api:Reset()
        bar:SetValue(0)
        apply(0)
    end

    --- Reapply clamped bar value and onScroll after range/layout changes (preserves scroll on tab revisit).
    function api:Restore(maxVal)
        local v = Theme.ClampScroll(bar:GetValue() or 0, maxVal)
        bar:SetValue(v)
        apply(v)
    end

    return api
end

--- Max vertical scroll offset from content and viewport heights.
function Theme.ScrollMax(childHeight, viewHeight)
    return math.max(0, (childHeight or 0) - (viewHeight or 0))
end

--- Clamp a scroll offset to [0, maxScroll].
function Theme.ClampScroll(offset, maxScroll)
    return math.max(0, math.min(maxScroll or 0, offset or 0))
end

--- Vertical scroll bar bound to an existing ScrollFrame (its scroll child's height sets the range).
--- Native clients get a real MinimalScrollBar wired by ScrollUtil.InitScrollFrameWithScrollBar, which
--- owns the ScrollFrame's OnVerticalScroll / OnScrollRangeChanged / OnMouseWheel scripts: never
--- SetScript those afterwards; use onScroll / AddOnScroll. Other clients (and unit tests) get a Slider.
--- opts: parent (bar parent; default the ScrollFrame's parent), name, step (wheel/stepper px),
---   onScroll(offset) (once per offset change from any source), hideIfUnscrollable (default true),
---   minScrollToShow, getRange() (Slider path only: override max offset)
--- @return table binding: bar, native, GetOffset(), GetMaxScroll(), SetOffset(v), UpdateRange(),
---   Wheel(delta), SetStep(px), AddOnScroll(fn)
--- A vertical scroll bar over a list that draws its own rows (a fixed row pool whose first row the offset
--- picks), keeping its own offset and range instead of a ScrollFrame's: the client gives a ScrollFrame nested
--- in another one no range at times, which left such a list's bar hidden and its last rows out of reach.
--- opts: parent, name, step (px per wheel notch), getRange() -> max offset px, getViewHeight() -> visible px
--- (the thumb's size), onScroll(offset).
--- @return table the CreateVerticalScrollBinding API: bar, native, GetOffset(), SetOffset(v), GetMaxScroll(),
---   UpdateRange(), Wheel(delta), SetStep(px), AddOnScroll(fn), SetAllowShow(on)
function Theme.CreateVirtualScrollBinding(opts)
    opts = opts or {}
    local step = opts.step or (Theme.CHAR_LIST_ROW_HEIGHT * 2)
    local getRange = opts.getRange or function() return 0 end
    local getViewHeight = opts.getViewHeight or function() return 1 end
    local listeners = {}
    if opts.onScroll then listeners[1] = opts.onScroll end
    local offset, lastNotified = 0, nil
    local allowShow = true
    local binding = { native = false }

    local function range()
        return math.max(0, getRange() or 0)
    end
    binding.GetMaxScroll = range

    local function notify()
        if lastNotified and math.abs(offset - lastNotified) < 0.01 then return end
        lastNotified = offset
        for i = 1, #listeners do
            listeners[i](offset)
        end
    end

    function binding.AddOnScroll(fn)
        listeners[#listeners + 1] = fn
    end

    function binding.GetOffset()
        return offset
    end

    local bar
    local syncing = false -- the bar told of a new offset by us, not dragged
    local function syncBar()
        local r = range()
        syncing = true
        if binding.native then
            local view = math.max(1, getViewHeight() or 1)
            bar:SetVisibleExtentPercentage(r > 0 and view / (view + r) or 1)
            bar:SetPanExtentPercentage(r > 0 and math.min(1, step / r) or 0)
            bar:SetScrollPercentage(r > 0 and offset / r or 0, true)
            if not allowShow then bar:Hide() end
        else
            bar:SetMinMaxValues(0, r)
            bar:SetValueStep(step)
            bar:SetValue(offset)
            bar:SetShown(allowShow and r > 0)
        end
        syncing = false
    end

    local function setOffset(value, fromBar)
        offset = Theme.ClampScroll(value, range())
        if not fromBar then syncBar() end
        notify()
    end

    local ScrollBoxEvents = _G.BaseScrollBoxEvents
    if nativeScrollBarsAvailable() and ScrollBoxEvents then
        bar = CreateFrame("EventFrame", opts.name, opts.parent, "MinimalScrollBar")
        bar.altArmyNativeScrollBar = true
        binding.native = true
        if bar.SetHideIfUnscrollable then
            bar:SetHideIfUnscrollable(true)
        end
        bar:RegisterCallback(ScrollBoxEvents.OnScroll, function(_, pct)
            if syncing then return end
            setOffset((pct or 0) * range(), true)
        end, binding)
    else
        bar = CreateFrame("Slider", opts.name, opts.parent)
        bar:SetOrientation("VERTICAL")
        bar:SetMinMaxValues(0, 0)
        bar:SetValueStep(step)
        bar:SetValue(0)
        bar:EnableMouse(true)
        bar:SetScript("OnValueChanged", function(_, value)
            if syncing then return end
            setOffset(value, true)
        end)
    end
    binding.bar = bar

    function binding.SetOffset(value)
        setOffset(value, false)
    end

    --- After the list's length or the view's height changed: the range is read again.
    function binding.UpdateRange()
        offset = Theme.ClampScroll(offset, range())
        syncBar()
    end

    function binding.Wheel(delta)
        setOffset(offset - delta * step, false)
    end

    function binding.SetStep(px)
        step = px
        syncBar()
    end

    function binding.SetAllowShow(allowed)
        allowShow = allowed and true or false
        if allowShow and binding.native and bar.SetHideIfUnscrollable then
            bar:SetHideIfUnscrollable(true) -- shows the bar again when there is range
        end
        syncBar()
    end

    syncBar()
    return binding
end

function Theme.CreateVerticalScrollBinding(scrollFrame, opts)
    opts = opts or {}
    local parent = opts.parent or scrollFrame:GetParent()
    local step = opts.step or (Theme.CHAR_LIST_ROW_HEIGHT * 2)
    local hideIfUnscrollable = opts.hideIfUnscrollable ~= false
    local listeners = {}
    if opts.onScroll then listeners[1] = opts.onScroll end
    local lastNotified = nil

    local binding = { native = false }

    local function notify()
        local offset = scrollFrame:GetVerticalScroll() or 0
        if lastNotified and math.abs(offset - lastNotified) < 0.01 then return end
        lastNotified = offset
        for i = 1, #listeners do
            listeners[i](offset)
        end
    end

    function binding.AddOnScroll(fn)
        listeners[#listeners + 1] = fn
    end

    function binding.GetOffset()
        return scrollFrame:GetVerticalScroll() or 0
    end

    local ScrollUtil = _G.ScrollUtil
    if nativeScrollBarsAvailable() and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", opts.name, parent, "MinimalScrollBar")
        bar.altArmyNativeScrollBar = true
        binding.bar, binding.native = bar, true
        ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, bar)
        scrollFrame:SetPanExtent(step)
        if bar.SetHideIfUnscrollable then
            bar:SetHideIfUnscrollable(hideIfUnscrollable)
        end

        local function range()
            return scrollFrame:GetVerticalScrollRange() or 0
        end
        binding.GetMaxScroll = range

        -- Listener order on the bar is undefined, so apply the offset here as well instead of
        -- relying on ScrollUtil's own OnScroll listener having run first.
        bar:RegisterCallback(_G.BaseScrollBoxEvents.OnScroll, function(_, pct)
            scrollFrame:SetVerticalScroll((pct or 0) * range())
            notify()
        end, binding)

        function binding.SetOffset(value)
            local maxScroll = range()
            value = Theme.ClampScroll(value, maxScroll)
            scrollFrame:SetVerticalScroll(value)
            -- Drive the bar directly: nested ScrollFrames may not fire OnVerticalScroll.
            bar:SetScrollPercentage(maxScroll > 0 and value / maxScroll or 0, true)
            notify()
        end

        function binding.UpdateRange()
            if scrollFrame.UpdateScrollChildRect then
                scrollFrame:UpdateScrollChildRect()
            end
            -- Nested ScrollFrames may not fire OnScrollRangeChanged; run ScrollUtil's handler
            -- so the thumb size and pan step follow the new range.
            local onRange = scrollFrame:GetScript("OnScrollRangeChanged")
            if onRange then
                onRange(scrollFrame, scrollFrame:GetHorizontalScrollRange() or 0, range())
            end
            if binding.GetOffset() > range() then
                binding.SetOffset(range())
            end
        end

        function binding.Wheel(delta)
            bar:ScrollStepInDirection(-delta)
        end

        function binding.SetStep(px)
            step = px
            scrollFrame:SetPanExtent(px)
        end

        function binding.SetAllowShow(allowed)
            if allowed then
                -- Re-runs ScrollBar:Update, which shows the bar only when there is range.
                bar:SetHideIfUnscrollable(hideIfUnscrollable)
                if not hideIfUnscrollable then bar:Show() end
            else
                bar:SetHideIfUnscrollable(false)
                bar:Hide()
            end
        end

        return binding
    end

    local bar = CreateFrame("Slider", opts.name, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(step)
    bar:SetValue(0)
    bar:EnableMouse(true)
    binding.bar = bar

    local function range()
        if opts.getRange then
            return opts.getRange()
        end
        local child = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
        return Theme.ScrollMax(child and child:GetHeight() or 0, scrollFrame:GetHeight())
    end
    binding.GetMaxScroll = range

    bar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
        notify()
    end)

    function binding.SetOffset(value)
        value = Theme.ClampScroll(value, range())
        scrollFrame:SetVerticalScroll(value)
        bar:SetValue(value)
        notify()
    end

    local allowShow = true
    local function syncShown()
        if not allowShow then
            bar:Hide()
        elseif hideIfUnscrollable then
            bar:SetShown(range() > (opts.minScrollToShow or 0))
        end
    end

    function binding.UpdateRange()
        local maxScroll = range()
        local cur = Theme.ClampScroll(binding.GetOffset(), maxScroll)
        scrollFrame:SetVerticalScroll(cur)
        bar:SetMinMaxValues(0, maxScroll)
        bar:SetValueStep(step)
        bar:SetValue(cur)
        syncShown()
        notify()
    end

    function binding.SetAllowShow(allowed)
        allowShow = allowed and true or false
        if allowShow and not hideIfUnscrollable then bar:Show() end
        syncShown()
    end

    function binding.Wheel(delta)
        binding.SetOffset(binding.GetOffset() - delta * step)
    end

    function binding.SetStep(px)
        step = px
        bar:SetValueStep(px)
    end

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        binding.Wheel(delta)
    end)

    return binding
end

--- Vertical ScrollFrame + scroll bar (see CreateVerticalScrollBinding) with unified range/clamp.
--- opts: parent, gutterEdge, name, anchorTop/anchorBottom tables {point, rel, relPoint, x, y},
--- valueStep, wheelStep, wheelOnChild, enableMouse, enableMouseWheel, childWidth, syncChildWidth,
--- fallbackViewHeight, minScrollToShow, scrollBarWidth, scrollBarGap
--- @return table api: scroll, child, scrollBar, binding, UpdateRange(), SetOffset(v), GetOffset(),
---   OnScroll(fn), Wheel(delta)
function Theme.CreateVerticalScrollViewport(opts)
    opts = opts or {}
    local parent = opts.parent
    local gutterEdge = opts.gutterEdge or parent
    local scroll = CreateFrame("ScrollFrame", opts.name, parent)

    local function anchorFrame(frame, spec)
        if spec then
            frame:SetPoint(spec[1], spec[2], spec[3], spec[4], spec[5])
        end
    end
    anchorFrame(scroll, opts.anchorTop)
    anchorFrame(scroll, opts.anchorBottom)

    if opts.enableMouse then
        scroll:EnableMouse(true)
    end
    if opts.enableMouseWheel then
        scroll:EnableMouseWheel(true)
    end

    local child = CreateFrame("Frame", nil, scroll)
    child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    child:SetWidth(opts.childWidth or 1)
    scroll:SetScrollChild(child)

    local binding = Theme.CreateVerticalScrollBinding(scroll, {
        parent = gutterEdge,
        step = opts.wheelStep or ((opts.valueStep or Theme.CHAR_LIST_ROW_HEIGHT) * 2),
        minScrollToShow = opts.minScrollToShow,
        getRange = function()
            local h = scroll:GetHeight() or 0
            if h <= 0 and opts.fallbackViewHeight then
                h = opts.fallbackViewHeight
            end
            return Theme.ScrollMax(child:GetHeight(), h)
        end,
    })
    local scrollBar = binding.bar
    Theme.AnchorVerticalScrollBar(scrollBar, gutterEdge, scroll, {
        width = opts.scrollBarWidth,
        gap = opts.scrollBarGap,
        thumbLength = opts.scrollBarThumbLength,
    })

    if opts.wheelOnChild ~= false then
        child:SetScript("OnMouseWheel", function(_, delta)
            binding.Wheel(delta)
        end)
    end

    if opts.syncChildWidth ~= false then
        scroll:SetScript("OnSizeChanged", function(s, w)
            child:SetWidth(w or s:GetWidth() or 1)
            binding.UpdateRange()
        end)
    end

    return {
        scroll = scroll,
        child = child,
        scrollBar = scrollBar,
        binding = binding,
        UpdateRange = function() binding.UpdateRange() end,
        SetOffset = binding.SetOffset,
        GetOffset = binding.GetOffset,
        OnScroll = binding.AddOnScroll,
        Wheel = binding.Wheel,
    }
end

function Theme.ApplyCheckboxBackground(texture)
    if not texture then return end
    local bg = C.inputBg
    texture:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
end

function Theme.ApplyCheckboxBorder(texture)
    if not texture then return end
    local br = C.inputBorder
    texture:SetColorTexture(br[1], br[2], br[3], br[4])
end

Theme.CHAR_LIST_CHECKBOX_SIZE = 18
Theme.CHAR_LIST_ROW_HEIGHT = 20
Theme.OPTIONS_DROPDOWN_ROW_HEIGHT = Theme.CHAR_LIST_ROW_HEIGHT + 4
Theme.DROPDOWN_MAX_VISIBLE_ROWS = 8

-- The main window is DIALOG strata, and its border (the template's NineSlice) draws over anything of a lower
-- frame level inside it; a dropdown's popup goes one strata up, so neither the border nor the panels it
-- overhangs cover it, and is kept on screen.
Theme.DROPDOWN_POPUP_STRATA = "FULLSCREEN_DIALOG"

--- Put a dropdown's popup above the window it opens from.
function Theme.RaiseDropdownPopup(popup)
    if popup.SetFrameStrata then
        popup:SetFrameStrata(Theme.DROPDOWN_POPUP_STRATA)
    end
    if popup.SetClampedToScreen then
        popup:SetClampedToScreen(true)
    end
end

--- Themed checkbox chrome (background + border + check texture); callers own layout and labels.
--- 1px border is drawn inside the control bounds so the outer footprint matches `size`.
-- UICheckButtonTemplate art has transparent padding; grow the frame so the visible box matches.
Theme.NATIVE_CHECKBOX_PAD = 4

function Theme.CreateThemeCheckbox(parent, size)
    local checkSize = size or Theme.CHAR_LIST_CHECKBOX_SIZE
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    if caps and caps.checkButton then
        local native = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        local s = checkSize + Theme.NATIVE_CHECKBOX_PAD
        native:SetSize(s, s)
        return native
    end
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(checkSize, checkSize)
    local checkBorder = check:CreateTexture(nil, "BACKGROUND")
    checkBorder:SetAllPoints(check)
    Theme.ApplyCheckboxBorder(checkBorder)
    local checkBg = check:CreateTexture(nil, "BORDER")
    checkBg:SetPoint("TOPLEFT", check, "TOPLEFT", 1, -1)
    checkBg:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", -1, 1)
    Theme.ApplyCheckboxBackground(checkBg)
    local checkTex = check:CreateTexture(nil, "OVERLAY")
    checkTex:SetAllPoints(check)
    checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetCheckedTexture(checkTex)
    return check
end

--- Options panel section heading (e.g. Cooldowns "Transmute", Gear "Current Character").
function Theme.CreateOptionsSectionLabel(parent, opts)
    opts = opts or {}
    local label = parent:CreateFontString(nil, opts.layer or "OVERLAY", Theme.FONTS.heading)
    if opts.relativeTo then
        label:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "BOTTOMLEFT",
            opts.x or 0, opts.y or -14)
    else
        label:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    if opts.justifyH then
        label:SetJustifyH(opts.justifyH)
    end
    label:SetText(opts.text or "")
    return label
end

--- Settings-row checkbox (18px, hover band, label toggles).
function Theme.CreateLabeledCheckbox(parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or Theme.CHAR_LIST_ROW_HEIGHT
    local checkSize = opts.checkSize or Theme.CHAR_LIST_CHECKBOX_SIZE

    local row = CreateFrame("Frame", nil, parent)
    if opts.relativeTo then
        row:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "TOPLEFT",
            opts.x or 0, opts.y or 0)
    else
        row:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetHeight(rowHeight)
    local rightInset = opts.rightInset or 0
    row:SetPoint("RIGHT", parent, "RIGHT", -rightInset, 0)

    local hoverRegion = CreateFrame("Frame", nil, row)
    if opts.fullWidthHover then
        hoverRegion:SetAllPoints(row)
    else
        hoverRegion:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        hoverRegion:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    end
    Theme.InstallHoverTint(hoverRegion)

    local check = Theme.CreateThemeCheckbox(row, checkSize)
    check:SetPoint("LEFT", row, "LEFT", 0, 0)

    local label = check:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(opts.text or "")

    if not opts.fullWidthHover then
        hoverRegion:SetPoint("RIGHT", label, "RIGHT", 4, 0)
    end
    hoverRegion:EnableMouse(true)
    hoverRegion:SetScript("OnEnter", function()
        Theme.SetHoverTint(hoverRegion, true)
    end)
    hoverRegion:SetScript("OnLeave", function()
        Theme.SetHoverTint(hoverRegion, false)
    end)
    hoverRegion:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and check:IsEnabled() then
            check:Click()
        end
    end)

    check:HookScript("OnEnter", function()
        Theme.SetHoverTint(hoverRegion, true)
    end)
    check:HookScript("OnLeave", function()
        Theme.SetHoverTint(hoverRegion, false)
    end)

    if opts.onClick then
        check:SetScript("OnClick", function()
            opts.onClick(check:GetChecked())
        end)
    end

    hoverRegion:SetFrameLevel(row:GetFrameLevel())
    check:SetFrameLevel(row:GetFrameLevel() + 4)

    row.check = check
    row.label = label
    row.hoverRegion = hoverRegion
    return row
end

Theme.OPTIONS_SLIDER_ROW_HEIGHT = 44 -- label line, the slider, its end labels
Theme.OPTIONS_SLIDER_WIDTH = 200

--- Settings-row slider: a label with the value beside it, the slider under them (the stock
--- UI-SliderBar art, as OptionsSliderTemplate draws it, built here so no client needs the template)
--- and its ends labelled. Values snap to `step`; `format(value)` words the value ("100%").
--- opts: point/relativeTo/relativePoint/x/y (as CreateLabeledCheckbox), right = { relativeTo,
---   relativePoint, x, y } (the row's TOPRIGHT anchor; else its right edge is the parent's), text,
---   min, max, step (1), value, width (else the slider stretches to the row, SLIDER_INSET in from
---   each side), format(v) -> string, onChange(v): called when a drag or click moved the value,
---   never by SetValue.
--- Returns the row: { slider, label, valueText, SetValue(v) (sets without onChange), GetValue() }.
function Theme.CreateOptionsSlider(parent, opts)
    opts = opts or {}
    local minV, maxV = opts.min or 0, opts.max or 1
    local step = opts.step or 1
    local format = opts.format or function(v) return tostring(v) end

    local row = CreateFrame("Frame", nil, parent)
    if opts.relativeTo then
        row:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "TOPLEFT",
            opts.x or 0, opts.y or 0)
    else
        row:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetHeight(Theme.OPTIONS_SLIDER_ROW_HEIGHT)
    if opts.right then
        row:SetPoint("TOPRIGHT", opts.right.relativeTo or parent, opts.right.relativePoint or "TOPRIGHT",
            opts.right.x or 0, opts.right.y or 0)
    else
        row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end

    local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(opts.text or "")

    local valueText = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)

    local SLIDER_INSET = 4
    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", SLIDER_INSET, -6)
    slider:SetSize(opts.width or Theme.OPTIONS_SLIDER_WIDTH, 17)
    if not opts.width then
        -- Stretched to the row: its width follows the row's (the label's height may change with the
        -- font, so the width alone is set, not a right anchor).
        row:HookScript("OnSizeChanged", function(_, w)
            if w and w > 0 then
                slider:SetWidth(math.max(40, w - 2 * SLIDER_INSET))
            end
        end)
    end
    slider:SetOrientation("HORIZONTAL")
    if slider.SetBackdrop then
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
    end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:EnableMouse(true)

    local lowText = slider:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -2, 2)
    lowText:SetText(format(minV))
    local highText = slider:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 2, 2)
    highText:SetText(format(maxV))

    local function snapped(v)
        local n = math.floor((v - minV) / step + 0.5)
        return math.max(minV, math.min(maxV, minV + n * step))
    end

    local current = snapped(opts.value or minV)
    local setting = false
    slider:SetScript("OnValueChanged", function(_, v)
        local snappedValue = snapped(v)
        valueText:SetText(format(snappedValue))
        if setting or snappedValue == current then return end
        current = snappedValue
        if opts.onChange then
            opts.onChange(snappedValue)
        end
    end)

    --- Shows `v` without calling onChange (the saved value when the page opens).
    function row.SetValue(v)
        current = snapped(v)
        setting = true
        slider:SetValue(current)
        setting = false
        valueText:SetText(format(current))
    end
    function row.GetValue()
        return current
    end
    row.SetValue(current)

    row.slider = slider
    row.label = label
    row.valueText = valueText
    return row
end

Theme.RANGE_SLIDER_THUMB_INSET = 8 -- a thumb's centre stops this far in from each end of the bar

--- Which handle of a range slider a press at `v` takes: the one it is outside of, else the nearer
--- ("min" on a tie between them); nil when both handles sit at `v` (the first move decides).
function Theme.RangeSliderHandle(lo, hi, v)
    if v < lo then return "min" end
    if v > hi then return "max" end
    if lo == hi then return nil end
    return (v - lo <= hi - v) and "min" or "max"
end

--- Settings-row slider with two handles, a low and a high value: laid out as CreateOptionsSlider (a
--- label with the values beside it, the bar under them in the stock UI-SliderBar art, its ends
--- labelled), the stretch between the handles filled. A press on the bar takes the nearer handle
--- there and drags it; a handle never passes the other. Values snap to `step`.
--- opts: point/relativeTo/relativePoint/x/y, right, width (as CreateOptionsSlider), text, labelFont
---   (Theme.FONTS key's value; else body), min, max, step (1), low, high, format(lo, hi) -> the
---   values' text, formatEnd(v) -> an end's label, onChange(lo, hi): called when a drag moved either
---   value, never by SetValues.
--- Returns the row: { bar, label, valueText, SetValues(lo, hi) (sets without onChange), GetValues() }.
function Theme.CreateRangeSlider(parent, opts)
    opts = opts or {}
    local minV, maxV = opts.min or 0, opts.max or 1
    local step = opts.step or 1
    local format = opts.format or function(lo, hi) return lo .. " - " .. hi end
    local formatEnd = opts.formatEnd or function(v) return tostring(v) end
    local PAD = Theme.RANGE_SLIDER_THUMB_INSET

    local row = CreateFrame("Frame", nil, parent)
    if opts.relativeTo then
        row:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "TOPLEFT",
            opts.x or 0, opts.y or 0)
    else
        row:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetHeight(Theme.OPTIONS_SLIDER_ROW_HEIGHT)
    if opts.right then
        row:SetPoint("TOPRIGHT", opts.right.relativeTo or parent, opts.right.relativePoint or "TOPRIGHT",
            opts.right.x or 0, opts.right.y or 0)
    else
        row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end

    local label = row:CreateFontString(nil, "OVERLAY", opts.labelFont or Theme.FONTS.body)
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(opts.text or "")

    local valueText = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)

    local BAR_INSET = 4
    local bar = CreateFrame("Frame", nil, row, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", BAR_INSET, -6)
    bar:SetSize(opts.width or Theme.OPTIONS_SLIDER_WIDTH, 17)
    if not opts.width then
        row:HookScript("OnSizeChanged", function(_, w)
            if w and w > 0 then
                bar:SetWidth(math.max(40, w - 2 * BAR_INSET))
            end
        end)
    end
    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
    end
    bar:EnableMouse(true)

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(3)
    local accent = C.rowAccent
    fill:SetColorTexture(accent[1], accent[2], accent[3], 0.9)

    local function thumb()
        local tex = bar:CreateTexture(nil, "OVERLAY")
        tex:SetSize(32, 32)
        tex:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        return tex
    end
    local lowThumb, highThumb = thumb(), thumb()

    local lowText = bar:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    lowText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -2, 2)
    lowText:SetText(formatEnd(minV))
    local highText = bar:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    highText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 2, 2)
    highText:SetText(formatEnd(maxV))

    local function snapped(v)
        local n = math.floor((v - minV) / step + 0.5)
        return math.max(minV, math.min(maxV, minV + n * step))
    end

    local lo, hi = snapped(opts.low or minV), snapped(opts.high or maxV)

    local function xOf(v)
        local usable = math.max(1, (bar:GetWidth() or 0) - 2 * PAD)
        if maxV <= minV then return PAD end
        return PAD + (v - minV) / (maxV - minV) * usable
    end
    local function place()
        local xl, xh = xOf(lo), xOf(hi)
        lowThumb:ClearAllPoints()
        lowThumb:SetPoint("CENTER", bar, "LEFT", xl, 0)
        highThumb:ClearAllPoints()
        highThumb:SetPoint("CENTER", bar, "LEFT", xh, 0)
        fill:ClearAllPoints()
        fill:SetPoint("LEFT", bar, "LEFT", xl, 0)
        fill:SetWidth(math.max(1, xh - xl))
        valueText:SetText(format(lo, hi))
    end
    bar:HookScript("OnSizeChanged", place)

    local function cursorValue()
        local scale = bar:GetEffectiveScale() or 1
        local cx = select(1, GetCursorPosition()) / scale
        local usable = math.max(1, (bar:GetWidth() or 0) - 2 * PAD)
        local frac = (cx - (bar:GetLeft() or 0) - PAD) / usable
        frac = math.max(0, math.min(1, frac))
        return snapped(minV + frac * (maxV - minV))
    end

    local dragging -- "min", "max", or "either" while both handles sit where the press began
    local function moveTo(v)
        if dragging == "either" then
            if v < lo then
                dragging = "min"
            elseif v > hi then
                dragging = "max"
            else
                return
            end
        end
        local newLo, newHi = lo, hi
        if dragging == "min" then
            newLo = math.min(v, hi)
        else
            newHi = math.max(v, lo)
        end
        if newLo == lo and newHi == hi then return end
        lo, hi = newLo, newHi
        place()
        if opts.onChange then
            opts.onChange(lo, hi)
        end
    end
    local function stopDrag()
        dragging = nil
        bar:SetScript("OnUpdate", nil)
    end
    bar:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        local v = cursorValue()
        dragging = Theme.RangeSliderHandle(lo, hi, v) or "either"
        moveTo(v)
        bar:SetScript("OnUpdate", function() moveTo(cursorValue()) end)
    end)
    bar:SetScript("OnMouseUp", stopDrag)
    bar:SetScript("OnHide", stopDrag)

    --- Shows `newLo`..`newHi` without calling onChange (the saved values when the page opens).
    function row.SetValues(newLo, newHi)
        lo = snapped(newLo)
        hi = math.max(lo, snapped(newHi))
        place()
    end
    function row.GetValues()
        return lo, hi
    end
    place()

    row.bar = bar
    row.label = label
    row.valueText = valueText
    return row
end

local SETTINGS_INFO_ICON_SIZE = 14
Theme.SETTINGS_TOOLTIP_SECTION_GAP_REM = 0.5

local settingsTooltipGapFont

local function getSettingsTooltipGapFont()
    if settingsTooltipGapFont then
        return settingsTooltipGapFont
    end
    local baseFont = _G.GameFontHighlightSmall
    local fontPath, fontSize, flags = "Fonts\\FRIZQT__.TTF", 12, ""
    if baseFont and baseFont.GetFont then
        fontPath, fontSize, flags = baseFont:GetFont()
    end
    fontSize = fontSize or 12
    local gapSize = math.max(1, math.floor(fontSize * Theme.SETTINGS_TOOLTIP_SECTION_GAP_REM + 0.5))
    settingsTooltipGapFont = _G.CreateFont("AltArmy_SettingsTooltipGapFont")
    settingsTooltipGapFont:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", gapSize, flags or "")
    return settingsTooltipGapFont
end

local function addSettingsTooltipSectionGap(tooltip)
    tooltip:AddLine(" ", 0, 0, 0, true, getSettingsTooltipGapFont())
end

local function createSettingsHelpButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SETTINGS_INFO_ICON_SIZE, SETTINGS_INFO_ICON_SIZE)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    tex:SetTexture("Interface\\Common\\help-i")
    return btn
end

local function showSettingsHelpTooltip(tooltipAnchor, tooltipOpts)
    if not GameTooltip or not tooltipAnchor then return end
    tooltipOpts = tooltipOpts or {}
    local title = tooltipOpts.title or ""
    local lines = tooltipOpts.lines or {}
    GameTooltip:SetOwner(tooltipAnchor, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    if title ~= "" then
        GameTooltip:AddLine(title, 1, 1, 1, true)
    end
    local prevWasBody = false
    for i = 1, #lines do
        local line = lines[i]
        local text
        local r, g, b = 0.9, 0.9, 0.9
        local isHeading = false
        if type(line) == "table" then
            text = line.text or ""
            if line.heading then
                r, g, b = 1, 1, 1
                isHeading = true
            else
                r, g, b = 0.75, 0.75, 0.75
            end
        else
            text = line
        end
        if isHeading and prevWasBody then
            addSettingsTooltipSectionGap(GameTooltip)
        end
        if text ~= "" then
            GameTooltip:AddLine(text, r, g, b, true)
        end
        prevWasBody = text ~= "" and not isHeading
    end
    GameTooltip:SetPoint("TOPLEFT", tooltipAnchor, "TOPRIGHT", 8, 0)
    GameTooltip:Show()
end

local function hideSettingsHelpTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function wireSettingsHelpButton(btn, tooltipAnchor, tooltipOpts, row)
    local function showTooltip()
        showSettingsHelpTooltip(tooltipAnchor, tooltipOpts)
    end

    local function onTooltipEnter()
        if row and row.hoverRegion then
            Theme.SetHoverTint(row.hoverRegion, true)
        end
        showTooltip()
    end

    local function onTooltipLeave()
        if row and row.hoverRegion then
            Theme.SetHoverTint(row.hoverRegion, false)
        end
        hideSettingsHelpTooltip()
    end

    btn:SetScript("OnEnter", onTooltipEnter)
    btn:SetScript("OnLeave", onTooltipLeave)

    if row then
        if row.hoverRegion then
            row.hoverRegion:HookScript("OnEnter", showTooltip)
            row.hoverRegion:HookScript("OnLeave", hideSettingsHelpTooltip)
        end
        if row.check then
            row.check:HookScript("OnEnter", showTooltip)
            row.check:HookScript("OnLeave", hideSettingsHelpTooltip)
        end
    end
end

--- Help icon on the right of a settings row; tooltip matches Graphs option rows (title + gray body).
function Theme.AttachSettingsHelpIcon(row, tooltipOpts)
    tooltipOpts = tooltipOpts or {}
    local btn = createSettingsHelpButton(row)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    if row.label then
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.label:SetPoint("RIGHT", btn, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
    end

    wireSettingsHelpButton(btn, row, tooltipOpts, row)
    row.helpBtn = btn
    return btn
end

--- Help icon immediately after a FontString label (edit-row captions, etc.).
--- One hit region covers the label, gap, and icon so the tooltip does not flicker.
function Theme.AttachLabelHelpIcon(label, tooltipOpts)
    if not label then return nil end
    tooltipOpts = tooltipOpts or {}
    local parent = tooltipOpts.parent
    if not parent and label.GetParent then
        parent = label:GetParent()
    end
    if not parent then return nil end

    local btn = createSettingsHelpButton(parent)
    btn:SetPoint("LEFT", label, "RIGHT", 4, 0)
    if btn.EnableMouse then
        btn:EnableMouse(false)
    end

    -- FontStrings do not receive mouse events; cover label through icon (including gap).
    local hitRegion = CreateFrame("Frame", nil, parent)
    hitRegion:EnableMouse(true)
    hitRegion:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 2)
    hitRegion:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    if parent.GetFrameLevel and hitRegion.SetFrameLevel then
        hitRegion:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    end
    hitRegion:SetScript("OnEnter", function()
        showSettingsHelpTooltip(hitRegion, tooltipOpts)
    end)
    hitRegion:SetScript("OnLeave", hideSettingsHelpTooltip)

    btn.hitRegion = hitRegion
    return btn
end

function Theme.ApplyDropdownBackground(frame)
    if not frame then return end
    Theme.ApplyBackdrop(frame, "section")
end

local DROPDOWN_MENU_PAD_TOP = 2
local DROPDOWN_MENU_PAD_SIDE = 2

-- WowStyle1DropdownTemplate / MenuStyle1 art (Blizzard_Menu). Forever loads the mainline
-- family, TBC Anniversary the classic family; the atlas names differ between them.
Theme.DROPDOWN_ART = {
    mainline = {
        holder = "common-dropdown-textholder", holderPad = { -8, 7, 8, -9 },
        arrow = "common-dropdown-a-button", arrowPoint = { "RIGHT", 1, -3 },
        bg = "common-dropdown-bg", bgPad = { -10, 3, 10, -3 }, bgAlpha = 0.925,
        -- MenuStyle1Mixin:GetInset (mainline): the bg art has a thick bottom edge.
        insets = { left = 8, top = 8, right = 8, bottom = 15 },
    },
    classic = {
        holder = "common-dropdown-classic-textholder", holderPad = { -9, 8, 8, -9 },
        arrow = "common-dropdown-classic-a-buttonDown", arrowPoint = { "RIGHT", -1, 0 },
        bg = "common-dropdown-classic-bg", bgPad = { -3, 3, 3, -4 }, bgFill = { 0, 0, 0, 0.8 }, bgFillInset = 6,
        -- MenuStyle1Mixin:GetInset (classic).
        insets = { left = 16, top = 10, right = 16, bottom = 10 },
    },
}
Theme.DROPDOWN_ARROW_GUTTER = 24
-- Legacy UIDropDownMenu radio check (present on both clients): checked half of the sheet.
Theme.MENU_RADIO_CHECK = { file = "Interface\\Common\\UI-DropDownRadioChecks", coords = { 0, 0.5, 0.5, 1 } }

local function nativeDropdownsAvailable()
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    return caps and caps.wowStyleDropdown or false
end

-- Prefer the family matching WOW_PROJECT_ID, but Forever reports its own project id (18) while
-- shipping only the mainline atlases, so fall back to whichever family the client actually has.
local function dropdownArt()
    local art = Theme.DROPDOWN_ART
    local preferred, other = art.classic, art.mainline
    if _G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1) then
        preferred, other = other, preferred
    end
    local NativeUI = AltArmy.NativeUI
    if NativeUI and NativeUI.HasAtlas
        and not NativeUI.HasAtlas(preferred.holder) and NativeUI.HasAtlas(other.holder) then
        return other
    end
    return preferred
end

--- Native dropdown trigger look (text holder + arrow). Callers keep their own label FontString;
--- leave Theme.DROPDOWN_ARROW_GUTTER free on the right for the arrow.
--- Falls back to Theme.SkinButton when the client has no WowStyle dropdown art.
function Theme.SkinDropdownButton(btn)
    if not btn then return end
    if not nativeDropdownsAvailable() then
        Theme.SkinButton(btn)
        return
    end
    if btn.altArmyDropdownHolder then return end
    local art = dropdownArt()
    local holder = btn:CreateTexture(nil, "BACKGROUND")
    holder:SetAtlas(art.holder)
    holder:SetPoint("TOPLEFT", btn, "TOPLEFT", art.holderPad[1], art.holderPad[2])
    holder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", art.holderPad[3], art.holderPad[4])
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas(art.arrow, true)
    arrow:SetPoint(art.arrowPoint[1], btn, art.arrowPoint[1], art.arrowPoint[2], art.arrowPoint[3])
    btn.altArmyDropdownHolder = holder
    btn.altArmyDropdownArrow = arrow
    local function setDisabledLook(disabled)
        local v = disabled and 0.5 or 1
        holder:SetVertexColor(v, v, v)
        arrow:SetVertexColor(v, v, v)
    end
    local origEnable, origDisable = btn.Enable, btn.Disable
    btn.Enable = function(self)
        if origEnable then origEnable(self) end
        setDisabledLook(false)
    end
    btn.Disable = function(self)
        if origDisable then origDisable(self) end
        setDisabledLook(true)
    end
end

local LEGACY_POPUP_INSETS = { left = 2, top = 2, right = 2, bottom = 2 }

--- Content insets for a dropdown popup: rows start `top` below the popup top and stop
--- `bottom` above its bottom (native menu art needs the room). Size popups as
--- rows * rowHeight + top + bottom.
function Theme.GetDropdownPopupInsets()
    if nativeDropdownsAvailable() then
        return dropdownArt().insets
    end
    return LEGACY_POPUP_INSETS
end

--- Native menu background for a dropdown popup frame (falls back to the section panel).
function Theme.SkinDropdownPopup(popup)
    if not popup then return end
    if not nativeDropdownsAvailable() then
        Theme.ApplyBackdrop(popup, "section")
        return
    end
    if popup.altArmyMenuBg then return end
    local art = dropdownArt()
    local bg = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAtlas(art.bg)
    bg:SetPoint("TOPLEFT", popup, "TOPLEFT", art.bgPad[1], art.bgPad[2])
    bg:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", art.bgPad[3], art.bgPad[4])
    if art.bgAlpha and bg.SetAlpha then bg:SetAlpha(art.bgAlpha) end
    popup.altArmyMenuBg = bg
    if art.bgFill then
        local fill = popup:CreateTexture(nil, "BACKGROUND", nil, 0)
        local c, inset = art.bgFill, art.bgFillInset or 0
        fill:SetColorTexture(c[1], c[2], c[3], c[4])
        fill:SetPoint("TOPLEFT", bg, "TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -inset, inset)
        popup.altArmyMenuFill = fill
    end
end

--- Single selectable row inside a custom dropdown popup (hover matches settings list rows).
function Theme.CreateDropdownMenuItem(parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or Theme.CHAR_LIST_ROW_HEIGHT or 20
    local padTop = opts.padTop or DROPDOWN_MENU_PAD_TOP
    local padSide = opts.padSide or DROPDOWN_MENU_PAD_SIDE
    local padRight = opts.padRight or padSide
    local idx = opts.index or 1

    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", padSide, -padTop - (idx - 1) * rowHeight)
    btn:SetPoint("LEFT", parent, "LEFT", padSide, 0)
    btn:SetPoint("RIGHT", parent, "RIGHT", -padRight, 0)
    btn:SetHeight(rowHeight - 2)

    Theme.BindInteractableHover(btn, {
        onEnter = opts.onEnter,
        onLeave = opts.onLeave,
    })

    local selBg
    local labelLeft = 4
    if nativeDropdownsAvailable() then
        -- Native menus mark the current choice with a radio check, not a row fill.
        selBg = btn:CreateTexture(nil, "ARTWORK")
        selBg:SetTexture(Theme.MENU_RADIO_CHECK.file)
        local rc = Theme.MENU_RADIO_CHECK.coords
        selBg:SetTexCoord(rc[1], rc[2], rc[3], rc[4])
        selBg:SetSize(16, 16)
        selBg:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.altArmyRadioCheck = selBg
        labelLeft = 20
    else
        selBg = btn:CreateTexture(nil, "ARTWORK")
        selBg:SetAllPoints(true)
        selBg:SetColorTexture(C.rowSelected[1], C.rowSelected[2], C.rowSelected[3], C.rowSelected[4])
    end
    selBg:Hide()
    btn.altArmyDropdownSelectedBg = selBg

    local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("LEFT", btn, "LEFT", labelLeft, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false) -- a label too long for the popup ends in "..."
    label:SetText(opts.text or "")
    btn.label = label

    function btn:SetDropdownSelected(on)
        selBg:SetShown(on == true)
    end
    btn:SetDropdownSelected(opts.selected == true)

    if opts.onClick then
        btn:SetScript("OnClick", function(self)
            opts.onClick(self)
        end)
    end

    return btn
end

Theme._openSingleSelectDropdowns = Theme._openSingleSelectDropdowns or {}

function Theme.CloseSingleSelectDropdowns(exceptPopup)
    for popup in pairs(Theme._openSingleSelectDropdowns) do
        if popup ~= exceptPopup and popup.Hide then
            popup:Hide()
        end
    end
end

--- A single-select dropdown's section header: a divider line over a muted label, not clickable.
--- A divider row naming the group under it: a line, the text centered, a line (one line without text).
--- Lay it out with SetPoint / SetHeight; `row:SetText(text)` names it again.
function Theme.CreateLabeledDividerRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local leftLine = row:CreateTexture(nil, "ARTWORK")
    leftLine:SetColorTexture(1, 1, 1, 0.15)
    leftLine:SetHeight(1)
    local rightLine = row:CreateTexture(nil, "ARTWORK")
    rightLine:SetColorTexture(1, 1, 1, 0.15)
    rightLine:SetHeight(1)
    local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("CENTER", row, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetTextColor(0.6, 0.6, 0.6)
    row.leftLine, row.rightLine, row.label = leftLine, rightLine, label
    function row:SetText(text)
        text = text or ""
        label:SetText(text)
        leftLine:ClearAllPoints()
        rightLine:ClearAllPoints()
        if text == "" then
            leftLine:SetPoint("LEFT", row, "LEFT", 4, 0)
            leftLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            rightLine:Hide()
        else
            leftLine:SetPoint("LEFT", row, "LEFT", 4, 0)
            leftLine:SetPoint("RIGHT", label, "LEFT", -6, 0)
            rightLine:SetPoint("LEFT", label, "RIGHT", 6, 0)
            rightLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            rightLine:Show()
        end
    end
    row:SetText("")
    return row
end

local function CreateDropdownHeaderRow(parent, idx, rowHeight, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * rowHeight)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(rowHeight - 2)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
    line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    label:SetPoint("LEFT", row, "LEFT", 4, -1)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.6, 0.6, 0.6)
    label:SetText(text or "")
    row.label = label
    return row
end

--- A single-select dropdown's divider row: a labeled divider (Theme.CreateLabeledDividerRow) at row `idx`.
function Theme.CreateDropdownDividerRow(parent, idx, rowHeight, text)
    local row = Theme.CreateLabeledDividerRow(parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * rowHeight)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(rowHeight)
    row:SetText(text)
    return row
end

--- Custom single-select dropdown (Gear / Reputation / Search settings style).
--- opts.parent, opts.width, opts.rowHeight, opts.dropdownParent
--- opts.maxVisibleRows — cap visible rows before scrolling (default Theme.DROPDOWN_MAX_VISIBLE_ROWS)
--- opts.popupAlign — "right" aligns the popup's right edge with the button (default left)
--- opts.point/relativeTo/relativePoint/x/y — anchor the trigger button
--- opts.entries or opts.getEntries() -> { { id, label }, ... }; an entry with header = true is a section
---   header (a divider and its label), never selected
--- opts.getSelectedId(), opts.onSelect(id, entry)
--- opts.onEntryEnter(btn, entry), opts.onEntryLeave(btn, entry)
function Theme.CreateSingleSelectDropdown(opts)
    opts = opts or {}
    local parent = opts.parent
    if not parent then return nil end

    local rowHeight = opts.rowHeight or Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or Theme.CHAR_LIST_ROW_HEIGHT or 20
    local width = opts.width or 340
    local dropdownParent = opts.dropdownParent or parent
    local maxVisibleRows = opts.maxVisibleRows or Theme.DROPDOWN_MAX_VISIBLE_ROWS or 8
    local insets = Theme.GetDropdownPopupInsets()
    local popupPadTop = insets.top
    local popupPadBottom = insets.bottom
    local popupPadLeft = insets.left
    local popupPadRight = insets.right

    local function popupHeightForCount(count)
        local visibleRows = math.min(count, maxVisibleRows)
        if visibleRows < 1 then visibleRows = 1 end
        return visibleRows * rowHeight + popupPadTop + popupPadBottom
    end

    local btn = CreateFrame("Button", nil, parent)
    if opts.relativeTo then
        btn:SetPoint(opts.point or "TOPLEFT", opts.relativeTo, opts.relativePoint or "TOPLEFT",
            opts.x or 0, opts.y or 0)
    else
        btn:SetPoint(opts.point or "TOPLEFT", parent, opts.relativePoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    btn:SetSize(width, rowHeight)
    Theme.SkinDropdownButton(btn)

    local btnText = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", btn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -6, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetWordWrap(false) -- a label too long for the button ends in "..."

    local popup = CreateFrame("Frame", nil, dropdownParent, "BackdropTemplate")
    if opts.popupAlign == "right" then
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    else
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    end
    popup:SetWidth(width)
    popup:SetFrameLevel((dropdownParent.GetFrameLevel and dropdownParent:GetFrameLevel() or 0) + 100)
    Theme.RaiseDropdownPopup(popup)
    popup:Hide()
    Theme.SkinDropdownPopup(popup)

    popup:HookScript("OnHide", function()
        Theme._openSingleSelectDropdowns[popup] = nil
    end)

    local listHost = CreateFrame("Frame", nil, popup)
    listHost:SetPoint("TOPLEFT", popup, "TOPLEFT", popupPadLeft, -popupPadTop)
    listHost:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -popupPadRight, popupPadBottom)

    local listViewport = Theme.CreateVerticalScrollViewport({
        parent = popup,
        gutterEdge = popup,
        anchorTop = { "TOPLEFT", popup, "TOPLEFT", popupPadLeft, -popupPadTop },
        anchorBottom = {
            "BOTTOMRIGHT", popup, "BOTTOMRIGHT", -(popupPadRight + Theme.VerticalScrollBarGutter()), popupPadBottom,
        },
        valueStep = rowHeight,
        wheelStep = rowHeight,
        enableMouseWheel = true,
        enableMouse = true,
        minScrollToShow = 0,
    })
    listViewport.scroll:Hide()

    local itemButtons = {}
    local enabled = true

    local function resolveEntries()
        if opts.getEntries then
            return opts.getEntries() or {}
        end
        return opts.entries or {}
    end

    local function labelForId(id, entries)
        for i = 1, #entries do
            if not entries[i].header and entries[i].id == id then
                return entries[i].label or tostring(id)
            end
        end
        return tostring(id or "")
    end

    local function setButtonMuted(muted)
        if muted then
            btnText:SetTextColor(0.5, 0.5, 0.5)
        else
            btnText:SetTextColor(1, 1, 1)
        end
    end

    local function closePopup()
        popup:Hide()
    end

    local function updateSelection()
        local selectedId = opts.getSelectedId and opts.getSelectedId()
        for i = 1, #itemButtons do
            local b = itemButtons[i]
            if b.SetDropdownSelected then
                b:SetDropdownSelected(b.entryId == selectedId)
            end
        end
    end

    local function rebuildItems()
        for i = 1, #itemButtons do
            itemButtons[i]:Hide()
            itemButtons[i]:SetParent(nil)
        end
        for i = #itemButtons, 1, -1 do
            itemButtons[i] = nil
        end

        local entries = resolveEntries()
        local count = #entries
        local useScroll = count > maxVisibleRows
        popup:SetHeight(popupHeightForCount(count))

        local host
        if useScroll then
            listHost:Hide()
            listViewport.scroll:Show()
            host = listViewport.child
            host:SetHeight(count * rowHeight)
        else
            listViewport.scroll:Hide()
            listHost:Show()
            host = listHost
        end

        for idx, entry in ipairs(entries) do
            local b = entry.divider and Theme.CreateDropdownDividerRow(host, idx, rowHeight, entry.label)
                or entry.header and CreateDropdownHeaderRow(host, idx, rowHeight, entry.label)
                or Theme.CreateDropdownMenuItem(host, {
                index = idx,
                rowHeight = rowHeight,
                padTop = 0,
                padSide = 0,
                text = entry.label or entry.id,
                selected = opts.getSelectedId and opts.getSelectedId() == entry.id,
                onEnter = function(self)
                    if opts.onEntryEnter then
                        opts.onEntryEnter(self, entry)
                    end
                end,
                onLeave = function(self)
                    if opts.onEntryLeave then
                        opts.onEntryLeave(self, entry)
                    end
                end,
                onClick = function(self)
                    closePopup()
                    if opts.onSelect then
                        opts.onSelect(self.entryId, entry)
                    end
                    btnText:SetText(labelForId(self.entryId, resolveEntries()))
                    updateSelection()
                end,
            })
            b.entryId = entry.id
            itemButtons[idx] = b
        end

        -- Grow the popup (never below the button width) so long labels are not clipped.
        local widest = 0
        for i = 1, #itemButtons do
            local lbl = itemButtons[i].label
            local w = lbl and lbl.GetStringWidth and lbl:GetStringWidth() or 0
            if w > widest then widest = w end
        end
        local labelLeft = nativeDropdownsAvailable() and 20 or 4
        local chrome = popupPadLeft + popupPadRight + labelLeft + 8
        if useScroll then
            chrome = chrome + Theme.VerticalScrollBarGutter()
        end
        popup:SetWidth(math.max(width, math.ceil(widest + chrome)))

        if useScroll then
            listViewport.SetOffset(0)
            listViewport.UpdateRange()
        end
    end

    local api = {
        button = btn,
        popup = popup,
        label = btnText,
        listViewport = listViewport,
        scrollBar = listViewport.scrollBar,
    }

    function api:Update()
        rebuildItems()
        local selectedId = opts.getSelectedId and opts.getSelectedId()
        btnText:SetText(labelForId(selectedId, resolveEntries()))
        updateSelection()
    end

    function api:SetEnabled(on)
        enabled = on ~= false
        if enabled then
            btn:Enable()
            setButtonMuted(false)
        else
            btn:Disable()
            closePopup()
            setButtonMuted(true)
        end
    end

    function api:Close()
        closePopup()
    end

    btn:SetScript("OnClick", function()
        if not enabled or not btn:IsEnabled() then return end
        local show = not popup:IsShown()
        if show then
            Theme.CloseSingleSelectDropdowns(popup)
            api:Update()
            updateSelection()
            if listViewport.scroll:IsShown() then
                listViewport.UpdateRange()
            end
            Theme._openSingleSelectDropdowns[popup] = true
        end
        popup:SetShown(show)
    end)

    api:Update()
    return api
end

Theme._openMultiSelectCheckboxDropdowns = Theme._openMultiSelectCheckboxDropdowns or {}

function Theme.CloseMultiSelectCheckboxDropdowns(exceptPopup)
    for popup in pairs(Theme._openMultiSelectCheckboxDropdowns) do
        if popup ~= exceptPopup and popup.Hide then
            popup:Hide()
        end
    end
end

--- Multi-select settings dropdown with checkbox rows (Search settings style).
function Theme.CreateMultiSelectCheckboxDropdown(config)
    config = config or {}
    local parent = config.parent
    if not parent then return nil end

    local rowHeight = config.rowHeight or Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or Theme.CHAR_LIST_ROW_HEIGHT or 20
    local dropdownParent = config.dropdownParent or parent
    local keys = config.keys or {}
    local labels = config.labels or {}
    -- Keys always on: their row is checked, disabled and grey, and never toggles.
    local lockedKeys = config.lockedKeys or {}

    local header
    if config.title and config.title ~= "" then
        header = parent:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        header:SetPoint("TOP", config.relativeTo, config.relativePoint or "BOTTOMLEFT", config.x or 0, config.y or -8)
        header:SetPoint("LEFT", parent, "LEFT", config.leftInset or 0, 0)
        header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        header:SetJustifyH("LEFT")
        header:SetText(config.title)
    end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(rowHeight + 4)
    if config.sameLine and config.relativeTo then
        btn:SetPoint("TOP", config.relativeTo, "TOP", 0, 0)
        btn:SetPoint("BOTTOM", config.relativeTo, "BOTTOM", 0, 0)
        btn:SetPoint("LEFT", parent, "LEFT", config.leftInset or 0, 0)
        btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    elseif header then
        btn:SetPoint("TOP", header, "BOTTOM", 0, -4)
        btn:SetPoint("LEFT", parent, "LEFT", config.leftInset or 0, 0)
        btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    else
        btn:SetPoint("TOP", config.relativeTo, config.relativePoint or "BOTTOMLEFT", config.x or 0, config.y or -4)
        btn:SetPoint("LEFT", parent, "LEFT", config.leftInset or 0, 0)
        btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end
    Theme.SkinDropdownButton(btn)

    local btnText = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", btn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -4, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetWordWrap(false)
    -- Left padding + right gutter (arrow or plain) that btnText is inset by within btn.
    local btnTextInsets = 6 + (btn.altArmyDropdownArrow and Theme.DROPDOWN_ARROW_GUTTER or 4)

    local popup = CreateFrame("Frame", nil, dropdownParent, "BackdropTemplate")
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    -- Native menu insets are already roomier than the old 4px; legacy keeps 4 / 4 / 4 / 8.
    local popupInsets = nativeDropdownsAvailable() and Theme.GetDropdownPopupInsets()
        or { left = 4, top = 4, right = 8, bottom = 4 }
    popup:SetFrameLevel((dropdownParent:GetFrameLevel() or 0) + 100)
    Theme.RaiseDropdownPopup(popup)
    popup:Hide()
    Theme.SkinDropdownPopup(popup)
    Theme._openMultiSelectCheckboxDropdowns[popup] = true

    -- config.getKeys() / config.getLabels(): a list that changes (laid out again on refresh and when opened);
    -- config.maxVisibleRows: past that many rows the popup scrolls; config.isDivider(key): that key is a
    -- divider row naming the group under it (its label), not a checkbox; config.fitRows: a popup too narrow
    -- for its widest row grows to fit it, leftward from the button's right edge (a settings panel sits at the
    -- window's right edge).
    local maxVisibleRows = config.maxVisibleRows
    local isDivider = config.isDivider or function() return false end
    local viewport -- made when the rows first outgrow maxVisibleRows
    local pools = {} -- host frame -> rows by index
    local dividerPools = {} -- host frame -> divider lines by index
    local checks = {}
    local rows = {}
    local layoutSignature
    local enabled = true
    local refreshDropdown

    local function rowLabelText(key)
        if config.getRowLabel then
            return config.getRowLabel(key)
        end
        return labels[key] or key
    end

    local function onRowClick(key, checked)
        if not key or lockedKeys[key] then return end
        if config.setEnabled then
            config.setEnabled(key, checked)
        end
        refreshDropdown()
        if config.onChange then
            config.onChange(key, checked)
        end
    end

    --- The pooled row at `index` of `host` (the popup itself, or the scrolling viewport's child).
    local function rowAt(host, index, inset)
        pools[host] = pools[host] or {}
        local pool = pools[host]
        if pool[index] then return pool[index] end
        local row
        row = Theme.CreateLabeledCheckbox(host, {
            point = "TOPLEFT",
            relativeTo = host,
            relativePoint = "TOPLEFT",
            x = inset.left,
            y = -inset.top - (index - 1) * rowHeight,
            rowHeight = rowHeight,
            text = "",
            fullWidthHover = true,
            rightInset = inset.right,
            onClick = function(checked)
                onRowClick(row.altArmyKey, checked)
            end,
        })
        pool[index] = row
        return row
    end

    --- The pooled divider line at `index` of `host`.
    local function dividerAt(host, index, inset)
        dividerPools[host] = dividerPools[host] or {}
        local pool = dividerPools[host]
        if pool[index] then return pool[index] end
        local d = Theme.CreateLabeledDividerRow(host)
        d:SetPoint("TOPLEFT", host, "TOPLEFT", inset.left, -inset.top - (index - 1) * rowHeight)
        d:SetPoint("RIGHT", host, "RIGHT", -inset.right, 0)
        d:SetHeight(rowHeight)
        pool[index] = d
        return d
    end

    local function layoutRows()
        if config.getKeys then
            keys = config.getKeys() or {}
        end
        if config.getLabels then
            labels = config.getLabels() or {}
        end
        local signature = table.concat(keys, "\001")
        if signature == layoutSignature then return end
        layoutSignature = signature
        local n = #keys
        local scrolling = maxVisibleRows ~= nil and n > maxVisibleRows
        local shownRows = scrolling and maxVisibleRows or n
        popup:SetHeight(popupInsets.top + shownRows * rowHeight + popupInsets.bottom)
        local host, inset = popup, popupInsets
        if scrolling then
            if not viewport then
                viewport = Theme.CreateVerticalScrollViewport({
                    parent = popup,
                    gutterEdge = popup,
                    anchorTop = { "TOPLEFT", popup, "TOPLEFT", popupInsets.left, -popupInsets.top },
                    anchorBottom = { "BOTTOMRIGHT", popup, "BOTTOMRIGHT",
                        -(popupInsets.right + Theme.VerticalScrollBarGutter()), popupInsets.bottom },
                    valueStep = rowHeight,
                    wheelStep = rowHeight,
                    enableMouseWheel = true,
                    enableMouse = true,
                    minScrollToShow = 0,
                })
            end
            viewport.scroll:Show()
            viewport.child:SetHeight(n * rowHeight)
            host, inset = viewport.child, { left = 0, top = 0, right = 0 }
        elseif viewport then
            viewport.scroll:Hide()
        end
        -- pairs, not ipairs: rows and dividers share the positions, so each pool has holes where the other was
        for _, pool in pairs(pools) do
            for _, row in pairs(pool) do
                row:Hide()
                row.altArmyKey = nil
            end
        end
        for _, pool in pairs(dividerPools) do
            for _, d in pairs(pool) do
                d:Hide()
            end
        end
        checks, rows = {}, {}
        for i, key in ipairs(keys) do
            if isDivider(key) then
                local d = dividerAt(host, i, inset)
                d:SetText(labels[key] or "") -- the group under it
                d:Show()
            else
                local row = rowAt(host, i, inset)
                row.altArmyKey = key
                row:Show()
                if lockedKeys[key] then
                    row.check:SetChecked(true)
                    row.check:Disable()
                    if row.label then row.label:SetTextColor(0.6, 0.6, 0.6) end
                    row.altArmyGreyed = true
                else
                    row.check:Enable()
                    if row.altArmyGreyed and row.label then row.label:SetTextColor(1, 1, 1) end
                    row.altArmyGreyed = nil
                end
                checks[key] = row.check
                rows[key] = row
            end
        end
        if viewport and scrolling then
            viewport.SetOffset(0)
            viewport.UpdateRange()
        end
    end

    local function setButtonSummary(summary)
        btn.fullSummaryText = summary
        local maxW = (btn:GetWidth() or 0) - btnTextInsets
        if maxW <= 0 then
            btnText:SetText(summary)
            btn.wasSummaryTruncated = false
            return
        end
        local Text = AltArmy.Text
        if Text and Text.TruncateFontString then
            btn.wasSummaryTruncated = Text.TruncateFontString(btnText, summary, maxW, { returnBoolean = true })
        else
            btnText:SetText(summary)
            btn.wasSummaryTruncated = false
        end
    end

    local function setButtonMuted(muted)
        if muted then
            btnText:SetTextColor(0.5, 0.5, 0.5)
        else
            btnText:SetTextColor(1, 1, 1)
        end
    end

    local function fitPopupWidth()
        if not config.fitRows then return end
        local widest = 0
        for _, row in pairs(rows) do
            local w = row.label and row.label.GetStringWidth and row.label:GetStringWidth() or 0
            if w > widest then widest = w end
        end
        local checkSize = Theme.CHAR_LIST_CHECKBOX_SIZE or 18
        local gutter = (viewport and viewport.scroll:IsShown()) and Theme.VerticalScrollBarGutter() or 0
        local need = math.ceil(popupInsets.left + checkSize + 2 + widest + 8 + popupInsets.right + gutter)
        popup:ClearAllPoints()
        if need > (btn:GetWidth() or 0) then
            popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
            popup:SetWidth(need)
        else
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        end
    end

    refreshDropdown = function()
        layoutRows()
        local filterMap = config.getFilter and config.getFilter() or {}
        local summary
        if not enabled and config.formatSummaryDisabled then
            summary = config.formatSummaryDisabled(keys, labels, filterMap)
        elseif config.formatSummary then
            summary = config.formatSummary(keys, labels, filterMap)
        else
            summary = table.concat(keys, ", ")
        end
        setButtonSummary(summary)
        setButtonMuted(not enabled)
        for key, check in pairs(checks) do
            if check and check.SetChecked then
                check:SetChecked(lockedKeys[key] or filterMap[key] ~= false)
            end
            local row = rows[key]
            if row and row.label and row.label.SetText then
                row.label:SetText(rowLabelText(key))
            end
        end
        fitPopupWidth()
    end

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if self.wasSummaryTruncated and self.fullSummaryText and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.fullSummaryText, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    btn:SetScript("OnClick", function()
        if not enabled or not btn:IsEnabled() then return end
        local show = not popup:IsShown()
        Theme.CloseMultiSelectCheckboxDropdowns(show and popup or nil)
        Theme.CloseSingleSelectDropdowns(nil)
        if show and config.getKeys then
            refreshDropdown()
        end
        popup:SetShown(show)
    end)

    local api = {
        button = btn,
        popup = popup,
        header = header,
        refresh = refreshDropdown,
    }

    function api:SetEnabled(on)
        enabled = on ~= false
        if enabled then
            btn:Enable()
            setButtonMuted(false)
        else
            btn:Disable()
            popup:Hide()
            setButtonMuted(true)
        end
        refreshDropdown()
    end

    function api:Close()
        popup:Hide()
    end

    refreshDropdown()
    return api
end

Theme.FILTER_DROPDOWN_WIDTH = 93
Theme.FILTER_DROPDOWN_HEIGHT = 22

local function filterDropdownNative()
    local NativeUI = AltArmy.NativeUI
    local caps = NativeUI and NativeUI.GetCaps and NativeUI.GetCaps()
    return caps and caps.filterDropdown or false
end

local function filterEntryLabel(entry)
    local SFM = AltArmy.SearchFilterMenu
    if SFM and SFM.FormatLabel then
        return SFM.FormatLabel(entry)
    end
    return entry.label or ""
end

--- Professions-style "Filter" button whose menu holds checkboxes, dividers and buttons.
--- opts.parent, opts.text (default "Filter")
--- opts.getEntries() -> { { kind = "checkbox"|"divider"|"button", key, label, checked, enabled, icon }, ... }
---   (re-read on open and after every toggle, so checked/enabled stay live)
--- opts.onToggle(key, checked) for checkboxes; opts.onSelect(key) for buttons (closes the menu).
--- Native: WowStyle1FilterDropdownTemplate + Blizzard_Menu. Fallback: skinned button + popup.
function Theme.CreateFilterDropdown(opts)
    opts = opts or {}
    local parent = opts.parent
    if not parent then return nil end
    local text = opts.text or "Filter"
    local function entries()
        return opts.getEntries and opts.getEntries() or {}
    end
    local function liveEntry(key)
        for _, e in ipairs(entries()) do
            if e.key == key then return e end
        end
        return nil
    end

    if filterDropdownNative() then
        local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1FilterDropdownTemplate")
        if dd.Text and dd.Text.SetText then
            dd.Text:SetText(text)
        elseif dd.SetText then
            dd:SetText(text)
        end
        dd:SetupMenu(function(_, root)
            for _, e in ipairs(entries()) do
                local key = e.key
                if e.kind == "checkbox" then
                    local cb = root:CreateCheckbox(filterEntryLabel(e), function()
                        local live = liveEntry(key)
                        return live and live.checked or false
                    end, function()
                        local live = liveEntry(key)
                        if opts.onToggle then opts.onToggle(key, not (live and live.checked)) end
                    end)
                    if cb and cb.SetEnabled then
                        cb:SetEnabled(function()
                            local live = liveEntry(key)
                            return live ~= nil and live.enabled ~= false
                        end)
                    end
                elseif e.kind == "divider" then
                    root:CreateDivider()
                elseif e.kind == "button" then
                    root:CreateButton(filterEntryLabel(e), function()
                        if opts.onSelect then opts.onSelect(key) end
                    end)
                end
            end
        end)
        return { button = dd, Close = function() if dd.CloseMenu then dd:CloseMenu() end end }
    end

    -- Fallback: skinned trigger + popup rebuilt from getEntries() on every open/toggle.
    local rowHeight = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or Theme.CHAR_LIST_ROW_HEIGHT or 20
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(Theme.FILTER_DROPDOWN_WIDTH, Theme.FILTER_DROPDOWN_HEIGHT)
    Theme.SkinDropdownButton(btn)
    local btnText = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", btn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -4, 0)
    btnText:SetText(text)

    local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:SetWidth(150)
    popup:SetFrameLevel((parent:GetFrameLevel() or 0) + 100)
    Theme.RaiseDropdownPopup(popup)
    popup:Hide()
    Theme.SkinDropdownPopup(popup)
    Theme._openMultiSelectCheckboxDropdowns[popup] = true
    local insets = Theme.GetDropdownPopupInsets()

    local rows, dividers = {}, {}
    local rebuild
    local function rowFor(e)
        local row = rows[e.key]
        if row then return row end
        if e.kind == "checkbox" then
            row = Theme.CreateLabeledCheckbox(popup, {
                rowHeight = rowHeight,
                fullWidthHover = true,
                rightInset = insets.right,
                onClick = function(checked)
                    if opts.onToggle then opts.onToggle(e.key, checked) end
                    rebuild()
                end,
            })
        else
            row = Theme.CreateDropdownMenuItem(popup, {
                rowHeight = rowHeight,
                onClick = function()
                    popup:Hide()
                    if opts.onSelect then opts.onSelect(e.key) end
                end,
            })
        end
        rows[e.key] = row
        return row
    end

    rebuild = function()
        for _, row in pairs(rows) do row:Hide() end
        for _, d in ipairs(dividers) do d:Hide() end
        local y, nDiv = insets.top, 0
        for _, e in ipairs(entries()) do
            if e.kind == "divider" then
                nDiv = nDiv + 1
                local d = dividers[nDiv]
                if not d then
                    d = popup:CreateTexture(nil, "ARTWORK")
                    d:SetColorTexture(1, 1, 1, 0.15)
                    d:SetHeight(1)
                    dividers[nDiv] = d
                end
                d:ClearAllPoints()
                d:SetPoint("TOPLEFT", popup, "TOPLEFT", insets.left, -y - 4)
                d:SetPoint("RIGHT", popup, "RIGHT", -insets.right, 0)
                d:Show()
                y = y + 9
            else
                local row = rowFor(e)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", popup, "TOPLEFT", insets.left, -y)
                row:SetPoint("RIGHT", popup, "RIGHT", -insets.right, 0)
                row:SetHeight(rowHeight)
                if e.kind == "checkbox" then
                    row.label:SetText(filterEntryLabel(e))
                    row.check:SetChecked(e.checked and true or false)
                    local on = e.enabled ~= false
                    if on then row.check:Enable() else row.check:Disable() end
                    local v = on and 1 or 0.5
                    row.label:SetTextColor(v, v, v)
                else
                    row.label:SetText(filterEntryLabel(e))
                end
                row:Show()
                y = y + rowHeight
            end
        end
        popup:SetHeight(y + insets.bottom)
    end

    btn:SetScript("OnClick", function()
        local show = not popup:IsShown()
        Theme.CloseMultiSelectCheckboxDropdowns(show and popup or nil)
        Theme.CloseSingleSelectDropdowns(nil)
        if show then rebuild() end
        popup:SetShown(show)
    end)

    return { button = btn, popup = popup, Close = function() popup:Hide() end }
end

--- Collapsible settings section, built like the Settings panel's own (SettingsExpandableSectionTemplate,
--- the Keybindings page): one frame holding its header and its content, whose height is worked out from
--- the content's declared height rather than measured on screen. The header is the Options_ListExpand bar
--- (both WoW Forever and TBC Anniversary have its atlases); a client without them gets the trade skill
--- window's plus/minus buttons. Blizzard's template itself can't be used here: it is abstract and reads its
--- state from the Settings list's scroll box.
--- opts: text, contentHeight (the content's height, from its rows' own heights), defaultExpanded (false),
---   onToggle(expanded).
--- Returns { frame, header, content, native, SetExpanded(on, silent), IsExpanded(), SetShown(on), IsShown(),
---   SetContentHeight(h), GetHeight() }. Place `frame` (Theme.StackCollapsibleSections stacks several); put
---   the controls in `content`, anchored from its top.
function Theme.CreateCollapsibleSection(parent, opts)
    opts = opts or {}
    local expanded = opts.defaultExpanded == true
    local shown = true
    local contentHeight = opts.contentHeight or 0
    local NativeUI = AltArmy.NativeUI
    local native = NativeUI and NativeUI.HasAtlas and NativeUI.HasAtlas("Options_ListExpand_Left") or false

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(Theme.COLLAPSIBLE_HEADER_HEIGHT)

    local label = header:CreateFontString(nil, "OVERLAY", native and "GameFontNormal" or Theme.FONTS.heading)
    label:SetJustifyH("LEFT")
    label:SetText(opts.text or "")
    header.label = label

    local right, icon
    if native then
        -- As SettingsExpandableSectionTemplate: Left and Right caps, a stretched Middle, text at x 21.
        local left = header:CreateTexture(nil, "BACKGROUND")
        left:SetAtlas("Options_ListExpand_Left", true)
        left:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        right = header:CreateTexture(nil, "BACKGROUND")
        right:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        local middle = header:CreateTexture(nil, "BACKGROUND")
        middle:SetAtlas("_Options_ListExpand_Middle", true)
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        middle:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
        label:SetPoint("LEFT", header, "LEFT", 21, 2)
        header.Left, header.Right, header.Middle = left, right, middle
        -- Hover: the bar's own art again, added on top in the HIGHLIGHT layer (shown only under the
        -- mouse), and the label white instead of gold.
        local glow = {}
        for key, tex in pairs({ Left = left, Middle = middle, Right = right }) do
            local g = header:CreateTexture(nil, "HIGHLIGHT")
            g:SetAllPoints(tex)
            g:SetBlendMode("ADD")
            g:SetAlpha(0.35)
            glow[key] = g
        end
        glow.Left:SetAtlas("Options_ListExpand_Left", true)
        glow.Middle:SetAtlas("_Options_ListExpand_Middle", true)
        header.Highlight = glow
        header:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
        header:SetScript("OnLeave", function() label:SetTextColor(1, 0.82, 0) end)
    else
        Theme.BindInteractableHover(header)
        icon = header:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", header, "LEFT", 0, 0)
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        header.collapseIcon = icon
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -Theme.COLLAPSIBLE_CONTENT_GAP)
    content:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local function height()
        if not expanded then
            return Theme.COLLAPSIBLE_HEADER_HEIGHT
        end
        return Theme.COLLAPSIBLE_HEADER_HEIGHT + Theme.COLLAPSIBLE_CONTENT_GAP + contentHeight
            + Theme.COLLAPSIBLE_BOTTOM_PAD
    end

    local function update()
        frame:SetShown(shown)
        content:SetShown(expanded)
        content:SetHeight(math.max(1, contentHeight))
        frame:SetHeight(height())
        if native then
            local atlas = expanded and "Options_ListExpand_Right_Expanded" or "Options_ListExpand_Right"
            right:SetAtlas(atlas, true)
            header.Highlight.Right:SetAtlas(atlas, true)
        else
            icon:SetTexture(expanded and "Interface\\Buttons\\UI-MinusButton-UP"
                or "Interface\\Buttons\\UI-PlusButton-UP")
        end
    end

    local function setExpanded(on, silent)
        expanded = on == true
        update()
        if not silent and opts.onToggle then
            opts.onToggle(expanded)
        end
    end

    header:SetScript("OnClick", function()
        setExpanded(not expanded)
    end)
    update()

    return {
        frame = frame,
        header = header,
        content = content,
        label = label,
        native = native,
        SetExpanded = setExpanded,
        IsExpanded = function() return expanded end,
        SetShown = function(on)
            shown = on ~= false
            update()
        end,
        IsShown = function() return shown end,
        SetContentHeight = function(h)
            contentHeight = h or 0
            update()
        end,
        GetHeight = height,
    }
end

Theme.COLLAPSIBLE_HEADER_HEIGHT = 30 -- SettingsExpandableSectionTemplate's button
Theme.COLLAPSIBLE_CONTENT_GAP = 8 -- between the header and the content
Theme.COLLAPSIBLE_BOTTOM_PAD = 8 -- below an open section's content

--- Stack collapsible sections one under another, skipping hidden ones. opts: parent, gap (default 8),
--- x/y (the first section's offset from the parent's top left). Returns a function that anchors them and
--- returns the height they take; call it again after a section opens, closes, shows or hides.
function Theme.StackCollapsibleSections(sections, opts)
    opts = opts or {}
    local gap = opts.gap or 8
    return function()
        local previous
        local total = 0
        for _, s in ipairs(sections) do
            if s.IsShown() then
                s.frame:ClearAllPoints()
                if previous then
                    s.frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -gap)
                    total = total + gap
                else
                    s.frame:SetPoint("TOPLEFT", opts.parent, "TOPLEFT", opts.x or 0, opts.y or 0)
                end
                s.frame:SetPoint("RIGHT", opts.parent, "RIGHT", 0, 0)
                total = total + s.GetHeight()
                previous = s
            end
        end
        return total
    end
end
