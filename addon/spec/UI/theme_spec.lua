--[[
  Unit tests for AltArmy_TBC/UI/Theme.lua
  Run from project root: npm test
]]

describe("AltArmy.Theme", function()
    local Theme
    local framesCreated

    local function makeStubTexture()
        local t = { _color = nil, _vertex = nil, _texture = nil }
        function t:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
        function t:SetAtlas(a) self._atlas = a end
        function t:SetBlendMode(m) self._blendMode = m end
        function t:SetAlpha(a) self._alpha = a end
        function t:SetTexture(tex) self._texture = tex end
        function t:SetTexCoord(a, b, c, d, e, f, g, h)
            self._texCoord = { a, b, c, d, e, f, g, h }
        end
        function t:SetGradientAlpha(orientation, sr, sg, sb, sa, er, eg, eb, ea)
            self._gradientAlpha = {
                orientation = orientation,
                start = { sr, sg, sb, sa },
                ["end"] = { er, eg, eb, ea },
            }
        end
        function t:SetGradient(orientation, minColor, maxColor)
            self._gradient = { orientation = orientation, minColor = minColor, maxColor = maxColor }
        end
        function t:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
        function t:SetDesaturated(on) self._desaturated = on end
        function t:SetAllPoints(frame)
            self._allPoints = frame or true
        end
        function t:SetPoint(...)
            self._points = self._points or {}
            table.insert(self._points, { ... })
        end
        function t:ClearAllPoints()
            self._points = {}
        end
        function t:SetHeight() end
        function t:SetWidth(w) self._width = w end
        function t:SetSize(w, h) self._width = w self._height = h end
        t._shown = false
        function t:Show() self._shown = true end
        function t:Hide() self._shown = false end
        function t:SetShown(on) self._shown = on end
        function t:IsShown() return self._shown end
        return t
    end

    local function makeStubFrame()
        local f = {
            _scripts = {},
            _backdrop = nil,
            _backdropColor = nil,
            _backdropBorderColor = nil,
            _children = {},
            _textures = {},
            _fontStrings = {},
            _alpha = 1,
            _shown = true,
            _enabled = true,
            _selected = false,
            _skinned = false,
            _text = "",
            Left = { SetAlpha = function() end },
            Right = { SetAlpha = function() end },
            Middle = { SetAlpha = function() end },
        }
        function f:SetBackdrop(bd) self._backdrop = bd end
        function f:GetBackdrop() return self._backdrop end
        function f:SetBackdropColor(r, g, b, a) self._backdropColor = { r, g, b, a } end
        function f:GetBackdropColor() local c = self._backdropColor return c and c[1], c[2], c[3], c[4] end
        function f:SetBackdropBorderColor(r, g, b, a) self._backdropBorderColor = { r, g, b, a } end
        function f:GetBackdropBorderColor() local c = self._backdropBorderColor return c and c[1], c[2], c[3], c[4] end
        function f:HookScript(event, fn) self._scripts[event] = fn end
        function f:GetScript(event) return self._scripts[event] end
        function f:SetScript(event, fn) self._scripts[event] = fn end
        function f:CreateTexture(_, layer)
            local tex = makeStubTexture()
            tex._layer = layer
            table.insert(f._textures, tex)
            return tex
        end
        function f:SetThumbTexture() end
        function f:GetWidth() return self._width or 14 end
        function f:GetHeight() return self._height or 20 end
        function f:SetSize(w, h) self._width = w self._height = h end
        function f:SetWidth(w) self._width = w end
        function f:SetHeight(h) self._height = h end
        function f:GetFrameLevel() return self._frameLevel or 0 end
        function f:SetFrameLevel(level) self._frameLevel = level end
        function f:EnableMouse() end
        function f:EnableMouseWheel() end
        function f:SetPoint(...)
            self._points = self._points or {}
            table.insert(self._points, { ... })
        end
        function f:SetCheckedTexture(tex) self._checkedTexture = tex end
        function f:SetMinMaxValues(min, max) self._minVal = min self._maxVal = max end
        function f:GetMinMaxValues() return self._minVal or 0, self._maxVal or 0 end
        function f:SetValue(v)
            if self._value == v then return end
            self._value = v
            local fn = self._scripts and self._scripts["OnValueChanged"]
            if fn then fn(self, v) end
        end
        function f:GetValue() return self._value or 0 end
        function f:SetValueStep() end
        function f:SetOrientation() end
        function f:ClearAllPoints() end
        function f:SetAllPoints(other) self._allPoints = other or true end
        function f:SetFrameStrata(strata) self._strata = strata end
        function f:SetClampedToScreen(on) self._clamped = on end
        function f:GetEffectiveScale() return self._scale or 1 end
        function f:SetVerticalScroll(v) self._verticalScroll = v end
        function f:GetVerticalScroll() return self._verticalScroll or 0 end
        function f:SetScrollChild(c) self._scrollChild = c end
        function f:GetScrollChild() return self._scrollChild end
        function f:HookScript(event, fn) self._scripts[event] = fn end
        function f:GetChecked() return self._checked end
        function f:SetChecked(checked) self._checked = checked end
        function f:Click()
            if self._scripts.OnClick then
                self._scripts.OnClick(self)
            end
        end
        function f:CreateFontString(_, layer, template)
            local fs = {
                _shown = true,
                _text = "",
                _layer = layer,
                _template = template,
                _textColorCalls = 0,
                _parent = f,
                SetTextColor = function(self, r, g, b, a)
                    self._textColor = { r, g, b, a }
                    self._textColorCalls = (self._textColorCalls or 0) + 1
                end,
                SetText = function(self, t) self._text = t end,
                GetStringWidth = function(self) return #(self._text or "") * 7 end,
                SetPoint = function(self, ...)
                    self._points = self._points or {}
                    table.insert(self._points, { ... })
                end,
                GetParent = function(self) return self._parent end,
                SetWidth = function() end,
                SetJustifyH = function(self, h) self._justifyH = h end,
                GetJustifyH = function(self) return self._justifyH or "LEFT" end,
                SetJustifyV = function(self, v) self._justifyV = v end,
                SetWordWrap = function(self, on) self._wordWrap = on end,
                Show = function(self) self._shown = true end,
                Hide = function(self) self._shown = false end,
                SetShown = function(self, on) self._shown = on end,
                IsShown = function(self) return self._shown end,
            }
            table.insert(f._fontStrings, fs)
            return fs
        end
        function f:GetFontString() return { SetTextColor = function() end } end
        function f:GetNormalTexture() return nil end
        function f:GetHighlightTexture() return nil end
        function f:GetPushedTexture() return nil end
        function f:SetAlpha(a) self._alpha = a end
        function f:Show() self._shown = true end
        function f:Hide() self._shown = false end
        function f:SetShown(on) self._shown = on end
        function f:IsShown() return self._shown ~= false end
        function f:Enable() self._enabled = true end
        function f:Disable() self._enabled = false end
        function f:IsEnabled() return self._enabled ~= false end
        function f:SetParent() end
        function f:OnBackdropSizeChanged() end
        function f:SetAutoFocus() end
        function f:SetTextInsets(left, right, top, bottom)
            self._textInsets = { left, right, top, bottom }
        end
        function f:SetFontObject() end
        function f:HighlightText() end
        function f:SetFocus() end
        function f:ClearFocus() end
        function f:GetText() return self._text or "" end
        function f:SetText(t) self._text = t or "" end
        table.insert(framesCreated, f)
        return f
    end

    setup(function()
        framesCreated = {}
        _G.AltArmy = {}
        _G.CreateFrame = function()
            return makeStubFrame()
        end
        _G.Mixin = function(target, mixin)
            for k, v in pairs(mixin) do
                target[k] = v
            end
        end
        _G.BackdropTemplateMixin = {
            OnBackdropSizeChanged = function() end,
            SetBackdrop = function(self, bd) self._backdrop = bd end,
            SetBackdropColor = function(self, r, g, b, a) self._backdropColor = { r, g, b, a } end,
            SetBackdropBorderColor = function(self, r, g, b, a)
                self._backdropBorderColor = { r, g, b, a }
            end,
        }
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["Theme"] = nil
        require("Theme")
        Theme = AltArmy.Theme
    end)

    describe("RangeSliderHandle", function()
        it("takes the handle a press is outside of, else the nearer, the low one on a tie", function()
            assert.are.equal("min", Theme.RangeSliderHandle(20, 40, 5))
            assert.are.equal("max", Theme.RangeSliderHandle(20, 40, 55))
            assert.are.equal("min", Theme.RangeSliderHandle(20, 40, 29))
            assert.are.equal("min", Theme.RangeSliderHandle(20, 40, 30))
            assert.are.equal("max", Theme.RangeSliderHandle(20, 40, 31))
        end)

        it("leaves it to the first move when both handles sit where the press is", function()
            assert.is_nil(Theme.RangeSliderHandle(30, 30, 30))
            assert.are.equal("max", Theme.RangeSliderHandle(30, 30, 31))
        end)
    end)

    describe("COLORS", function()
        it("defines tiered background roles", function()
            assert.are.same({ 0.08, 0.08, 0.10, 0.55 }, Theme.COLORS.windowBg)
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.sectionBg)
            assert.are.same({ 0.08, 0.08, 0.10, 0.95 }, Theme.COLORS.graphBg)
            assert.is_true(Theme.COLORS.windowBg[4] < Theme.COLORS.sectionBg[4])
        end)

        it("defines warm bronze panel border", function()
            assert.are.same({ 0.45, 0.38, 0.22, 0.90 }, Theme.COLORS.panelBorder)
        end)

        it("defines button and row interaction colors", function()
            assert.is_not_nil(Theme.COLORS.btnBg)
            assert.is_not_nil(Theme.COLORS.rowHover)
            assert.is_not_nil(Theme.COLORS.rowAccent)
        end)

        it("gridHeaderBg matches sectionBg RGB at full opacity for pinned overlays", function()
            local panel = Theme.COLORS.sectionBg
            local header = Theme.COLORS.gridHeaderBg
            assert.are.equal(panel[1], header[1])
            assert.are.equal(panel[2], header[2])
            assert.are.equal(panel[3], header[3])
            assert.are.equal(1, header[4])
        end)
    end)

    describe("backdrop tables", function()
        it("WINDOW_BACKDROP is tiled with 16px edge", function()
            assert.is_true(Theme.WINDOW_BACKDROP.tile)
            assert.are.equal(16, Theme.WINDOW_BACKDROP.edgeSize)
        end)

        it("SECTION_BACKDROP is stretched with 12px edge", function()
            assert.is_false(Theme.SECTION_BACKDROP.tile)
            assert.are.equal(12, Theme.SECTION_BACKDROP.edgeSize)
        end)

        it("TOOLTIP_BACKDROP is tiled", function()
            assert.is_true(Theme.TOOLTIP_BACKDROP.tile)
        end)
    end)

    describe("ApplyBackdrop", function()
        it("applies window tier with semi-transparent shell bg", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "window")
            assert.are.equal(0.55, f._backdropColor[4])
        end)

        it("applies section tier colors to a frame", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "section")
            assert.is_not_nil(f._backdrop)
            assert.are.equal(0.08, f._backdropColor[1])
            assert.are.equal(0.95, f._backdropColor[4])
            assert.are.equal(0.45, f._backdropBorderColor[1])
        end)

        it("applies graph tier with graphBg", function()
            local f = makeStubFrame()
            Theme.ApplyBackdrop(f, "graph")
            assert.are.equal(0.08, f._backdropColor[1])
        end)

        it("mixes BackdropTemplateMixin when SetBackdrop missing", function()
            local f = makeStubFrame()
            f.SetBackdrop = nil
            Theme.EnsureBackdrop(f)
            assert.is_not_nil(f.SetBackdrop)
            assert.is_not_nil(f.OnBackdropSizeChanged)
        end)

        describe("native nine-slice chrome", function()
            local savedNativeUI, savedNineSlice, applied

            before_each(function()
                savedNativeUI, savedNineSlice = AltArmy.NativeUI, _G.NineSliceUtil
                applied = {}
                AltArmy.NativeUI = { GetCaps = function() return { nineSlice = true } end }
                _G.NineSliceUtil = {
                    ApplyLayoutByName = function(frame, layout)
                        table.insert(applied, { frame = frame, layout = layout })
                        frame.Center = frame.Center or makeStubTexture()
                    end,
                }
            end)

            after_each(function()
                AltArmy.NativeUI, _G.NineSliceUtil = savedNativeUI, savedNineSlice
            end)

            local function nativeBg(f)
                return f.altArmyNativeBg
            end

            it("draws section panels as a native inset with the marble background", function()
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "section")
                assert.are.equal("InsetFrameTemplate", applied[1].layout)
                assert.are.equal(f, applied[1].frame)
                assert.is_nil(f._backdrop)
                assert.are.equal(Theme.NATIVE_TIERS.section.bg, nativeBg(f)._texture)
                assert.are.equal("BACKGROUND", nativeBg(f)._layer)
            end)

            it("uses the inset for graph panels too", function()
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "graph")
                assert.are.equal("InsetFrameTemplate", applied[1].layout)
            end)

            it("uses the Dialog border for window and dialog tiers", function()
                local w, d = makeStubFrame(), makeStubFrame()
                Theme.ApplyBackdrop(w, "window")
                Theme.ApplyBackdrop(d, "dialog")
                assert.are.equal("Dialog", applied[1].layout)
                assert.are.equal("Dialog", applied[2].layout)
                assert.are.equal(Theme.NATIVE_TIERS.dialog.bg, nativeBg(d)._texture)
            end)

            it("uses the tooltip layout and tints its center", function()
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "tooltip")
                assert.are.equal("TooltipDefaultLayout", applied[1].layout)
                assert.is_nil(nativeBg(f))
                assert.are.same(Theme.NATIVE_TIERS.tooltip.centerColor, f.Center._vertex)
            end)

            it("reuses the background texture when applied twice", function()
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "section")
                local bg = nativeBg(f)
                local count = #f._textures
                Theme.ApplyBackdrop(f, "section")
                assert.are.equal(bg, nativeBg(f))
                assert.are.equal(count, #f._textures)
            end)

            it("keeps the legacy backdrop for the button tier", function()
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "button")
                assert.are.equal(0, #applied)
                assert.is_not_nil(f._backdrop)
            end)

            it("falls back to the legacy backdrop without nine-slice support", function()
                AltArmy.NativeUI = { GetCaps = function() return { nineSlice = false } end }
                local f = makeStubFrame()
                Theme.ApplyBackdrop(f, "section")
                assert.are.equal(0, #applied)
                assert.is_not_nil(f._backdrop)
            end)
        end)
    end)

    describe("CreatePanel", function()
        it("returns a frame with section backdrop applied", function()
            local parent = makeStubFrame()
            local panel = Theme.CreatePanel(parent, "section")
            assert.is_not_nil(panel._backdrop)
            assert.are.equal(0.08, panel._backdropColor[1])
        end)
    end)

    describe("SkinButton", function()
        it("applies button backdrop and wires hover script", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, false)
            assert.is_true(btn._skinned)
            assert.is_not_nil(btn._backdrop)
            assert.is_not_nil(btn._scripts.OnEnter)
            btn._scripts.OnEnter(btn)
            assert.are.equal(0.20, btn._backdropColor[1])
        end)

        it("toggle buttons get SetSelected", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, true)
            assert.is_not_nil(btn.SetSelected)
            btn:SetSelected(true)
            assert.is_true(btn._selected)
            assert.are.equal(0.30, btn._backdropColor[1])
            assert.are.equal(0.82, btn._backdropBorderColor[1])
        end)

        it("SetSelected keeps gold active look when the button stays enabled", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, true)
            btn:Enable()
            btn:SetSelected(true)
            assert.are.equal(0.30, btn._backdropColor[1])
            assert.are.equal(0.82, btn._backdropBorderColor[1])
            btn:SetSelected(false)
            assert.are.equal(0.14, btn._backdropColor[1])
        end)

        it("Disable mutes colors and ignores hover until re-enabled", function()
            local btn = makeStubFrame()
            Theme.SkinButton(btn, false)
            btn:Disable()
            assert.is_false(btn:IsEnabled())
            assert.are.equal(0.10, btn._backdropColor[1])
            btn._scripts.OnEnter(btn)
            assert.are.equal(0.10, btn._backdropColor[1])
            btn:Enable()
            assert.is_true(btn:IsEnabled())
            assert.are.equal(0.14, btn._backdropColor[1])
        end)
    end)

    describe("SkinDangerButton", function()
        it("applies red danger styling", function()
            local btn = makeStubFrame()
            Theme.SkinDangerButton(btn)
            assert.is_true(btn._skinned)
            assert.are.equal(0.24, btn._backdropColor[1])
            assert.are.equal(0.78, btn._backdropBorderColor[1])
            btn._scripts.OnEnter(btn)
            assert.are.equal(0.34, btn._backdropColor[1])
        end)
    end)

    describe("native panel buttons", function()
        local savedNativeUI

        before_each(function()
            savedNativeUI = AltArmy.NativeUI
            AltArmy.NativeUI = { GetCaps = function() return { nineSlice = true } end }
        end)

        after_each(function()
            AltArmy.NativeUI = savedNativeUI
        end)

        local function plainButton()
            local btn = makeStubFrame()
            btn.Left, btn.Right, btn.Middle = nil, nil, nil
            btn._width, btn._height = 80, 22
            function btn:SetHighlightTexture(t) self._highlightTexture = t end
            function btn:LockHighlight() self._lockedHighlight = true end
            function btn:UnlockHighlight() self._lockedHighlight = false end
            btn.label = btn:CreateFontString(nil, "OVERLAY")
            return btn
        end

        it("draws the three-slice UI-Panel-Button art on a plain button", function()
            local btn = plainButton()
            Theme.SkinButton(btn)
            assert.is_nil(btn._backdrop)
            assert.are.equal(Theme.PANEL_BUTTON.up, btn.Left._texture)
            assert.are.equal(Theme.PANEL_BUTTON.up, btn.Middle._texture)
            assert.are.equal(Theme.PANEL_BUTTON.up, btn.Right._texture)
            assert.are.equal(Theme.PANEL_BUTTON.highlight, btn._highlightTexture._texture)
        end)

        it("swaps to the pressed / disabled art like the template", function()
            local btn = plainButton()
            Theme.SkinButton(btn)
            btn._scripts.OnMouseDown(btn)
            assert.are.equal(Theme.PANEL_BUTTON.down, btn.Middle._texture)
            btn:Disable()
            assert.are.equal(Theme.PANEL_BUTTON.disabled, btn.Middle._texture)
            btn:Enable()
            assert.are.equal(Theme.PANEL_BUTTON.up, btn.Middle._texture)
        end)

        it("keeps an existing UIPanelButtonTemplate's own art", function()
            local btn = makeStubFrame()
            local alphaSet = false
            btn.Left = { SetAlpha = function() alphaSet = true end }
            Theme.SkinButton(btn)
            assert.is_false(alphaSet)
            assert.is_nil(btn._backdrop)
        end)

        it("shows toggle selection with a locked highlight", function()
            local btn = plainButton()
            Theme.SkinButton(btn, true)
            btn:SetSelected(true)
            assert.is_true(btn._lockedHighlight)
            btn:SetSelected(false)
            assert.is_false(btn._lockedHighlight)
        end)

        it("colors plain-button labels with the native button font colors", function()
            local btn = plainButton()
            Theme.SkinButton(btn)
            assert.are.same(Theme.BUTTON_TEXT.normal, { unpack(btn.label._textColor, 1, 3) })
            btn:Disable()
            assert.are.same(Theme.BUTTON_TEXT.disabled, { unpack(btn.label._textColor, 1, 3) })
        end)

        it("danger buttons use panel art with a red label", function()
            local btn = plainButton()
            Theme.SkinDangerButton(btn)
            assert.are.equal(Theme.PANEL_BUTTON.up, btn.Middle._texture)
            assert.are.same(Theme.BUTTON_TEXT.danger, { unpack(btn.label._textColor, 1, 3) })
        end)
    end)

    describe("InstallHoverTint", function()
        it("creates a hover tint texture on the frame", function()
            local f = makeStubFrame()
            Theme.InstallHoverTint(f)
            assert.is_not_nil(f.altArmyHoverTint)
            Theme.SetHoverTint(f, true)
            assert.are.equal(Theme.HOVER_TINT_ALPHA, f.altArmyHoverTint._vertex[4])
        end)

        it("uses the native quest-log list highlight when native chrome is available", function()
            local savedNativeUI = AltArmy.NativeUI
            AltArmy.NativeUI = { GetCaps = function() return { nineSlice = true } end }
            local f = makeStubFrame()
            Theme.InstallHoverTint(f)
            AltArmy.NativeUI = savedNativeUI
            local t = f.altArmyHoverTint
            assert.are.equal(Theme.NATIVE_ROW_HIGHLIGHT, t._texture)
            assert.are.equal("ADD", t._blendMode)
            Theme.SetHoverTint(f, true)
            assert.are.equal(Theme.NATIVE_ROW_HIGHLIGHT_ALPHA, t._vertex[4])
            Theme.SetHoverTint(f, false)
            assert.are.equal(0, t._vertex[4])
        end)
    end)

    describe("InstallSettingsButtonGlow", function()
        it("creates a yellow square glow behind the icon", function()
            local btn = makeStubFrame()
            local glow = Theme.InstallSettingsButtonGlow(btn)
            assert.is_not_nil(glow)
            assert.is_not_nil(btn.glow)
            assert.are.equal(Theme.COLORS.settingsGlow[1], glow._color[1])
            assert.is_false(glow._shown)
        end)
    end)

    describe("AttentionFlashAlpha", function()
        it("returns nil when the flash duration is complete", function()
            assert.is_nil(Theme.AttentionFlashAlpha(2, 2, 3))
            assert.is_nil(Theme.AttentionFlashAlpha(2.1, 2, 3))
        end)

        it("pulses between low and high alpha within the duration", function()
            local a0 = Theme.AttentionFlashAlpha(0, 2, 3)
            local aMid = Theme.AttentionFlashAlpha(1 / 6, 2, 3)
            assert.is_true(a0 >= 0.35 and a0 <= 1)
            assert.is_true(aMid > a0)
        end)
    end)

    describe("FlashAttentionHighlight", function()
        it("creates a bordered highlight and hides it when the pulse ends", function()
            local target = makeStubFrame()
            Theme.FlashAttentionHighlight(target, { duration = 0.5, pulses = 2, pad = 3 })
            local hl = target.altArmyAttentionHighlight
            assert.is_not_nil(hl)
            assert.is_not_nil(hl._backdropBorderColor)
            assert.is_true(hl._shown)
            assert.is_not_nil(hl._scripts.OnUpdate)
            hl._scripts.OnUpdate(hl, 0.6)
            assert.is_false(hl._shown)
            assert.is_nil(hl._scripts.OnUpdate)
        end)
    end)

    describe("SkinSettingsIconButton", function()
        it("shows yellow hover glow on enter when settings are not active", function()
            local btn = makeStubFrame()
            local icon = makeStubTexture()
            Theme.SkinSettingsIconButton(btn)
            assert.is_true(btn._settingsIconSkinned)
            assert.is_not_nil(btn.hoverGlow)
            btn._scripts.OnEnter(btn)
            assert.is_true(btn.hoverGlow._shown)
            btn._scripts.OnLeave(btn)
            assert.is_false(btn.hoverGlow._shown)
        end)

        it("does not duplicate glow on hover when settings panel is already open", function()
            local btn = makeStubFrame()
            btn.glow = makeStubTexture()
            btn.glow._shown = true
            local icon = makeStubTexture()
            Theme.SkinSettingsIconButton(btn)
            btn._scripts.OnEnter(btn)
            assert.is_false(btn.hoverGlow._shown)
        end)
    end)

    describe("native dropdown art", function()
        local savedNativeUI, savedProject, savedMainline

        before_each(function()
            savedNativeUI, savedProject, savedMainline = AltArmy.NativeUI, _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE
            AltArmy.NativeUI = { GetCaps = function() return { wowStyleDropdown = true } end }
            _G.WOW_PROJECT_MAINLINE = 1
        end)

        after_each(function()
            AltArmy.NativeUI, _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = savedNativeUI, savedProject, savedMainline
        end)

        local function atlases(f)
            local found = {}
            for _, t in ipairs(f._textures) do
                if t._atlas then found[t._atlas] = t end
            end
            return found
        end

        it("uses the mainline dropdown atlases on project 1", function()
            _G.WOW_PROJECT_ID = 1
            local btn = makeStubFrame()
            Theme.SkinDropdownButton(btn)
            local a = atlases(btn)
            assert.is_not_nil(a["common-dropdown-textholder"])
            assert.is_not_nil(a["common-dropdown-a-button"])
            assert.is_nil(btn._backdrop)
        end)

        it("uses the classic dropdown atlases on TBC Anniversary", function()
            _G.WOW_PROJECT_ID = 5
            local btn = makeStubFrame()
            Theme.SkinDropdownButton(btn)
            local a = atlases(btn)
            assert.is_not_nil(a["common-dropdown-classic-textholder"])
            assert.is_not_nil(a["common-dropdown-classic-a-buttonDown"])
        end)

        it("falls back to the atlas family the client has (Forever reports project 18)", function()
            _G.WOW_PROJECT_ID = 18
            AltArmy.NativeUI.HasAtlas = function(name)
                return name:find("classic", 1, true) == nil
            end
            local btn = makeStubFrame()
            Theme.SkinDropdownButton(btn)
            local a = atlases(btn)
            assert.is_not_nil(a["common-dropdown-textholder"])
            assert.is_not_nil(a["common-dropdown-a-button"])
        end)

        it("gives popups the native menu background", function()
            _G.WOW_PROJECT_ID = 5
            local popup = makeStubFrame()
            Theme.SkinDropdownPopup(popup)
            assert.is_not_nil(atlases(popup)["common-dropdown-classic-bg"])
            assert.is_nil(popup._backdrop)
        end)

        it("sizes single-select popups to fit every row inside the native menu insets", function()
            _G.WOW_PROJECT_ID = 1
            local dd = Theme.CreateSingleSelectDropdown({
                parent = makeStubFrame(),
                rowHeight = 20,
                entries = { { id = "a", label = "A" }, { id = "b", label = "B" }, { id = "c", label = "C" } },
            })
            local ins = Theme.DROPDOWN_ART.mainline.insets
            assert.are.same(ins, Theme.GetDropdownPopupInsets())
            assert.are.equal(3 * 20 + ins.top + ins.bottom, dd.popup._height)
        end)

        it("marks the selected menu row with a radio check instead of a fill", function()
            local parent = makeStubFrame()
            local row = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "A", selected = true })
            assert.is_not_nil(row.altArmyRadioCheck)
            assert.is_true(row.altArmyRadioCheck:IsShown())
            row:SetDropdownSelected(false)
            assert.is_false(row.altArmyRadioCheck:IsShown())
        end)
    end)

    describe("CreateDropdownMenuItem", function()
        it("installs hover tint and wires enter/leave on dropdown rows", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option" })
            assert.is_not_nil(btn.altArmyHoverTint)
            assert.is_not_nil(btn._scripts.OnEnter)
            btn._scripts.OnEnter()
            assert.are.equal(Theme.HOVER_TINT_ALPHA, btn.altArmyHoverTint._vertex[4])
            btn._scripts.OnLeave()
            assert.are.equal(0, btn.altArmyHoverTint._vertex[4])
        end)

        it("highlights the selected dropdown row", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option", selected = true })
            assert.is_not_nil(btn.altArmyDropdownSelectedBg)
            assert.is_true(btn.altArmyDropdownSelectedBg._shown)
            local c = btn.altArmyDropdownSelectedBg._color
            assert.are.equal(Theme.COLORS.rowSelected[1], c[1])
            assert.are.equal(Theme.COLORS.rowSelected[2], c[2])
            assert.are.equal(Theme.COLORS.rowSelected[3], c[3])
            assert.are.equal(Theme.COLORS.rowSelected[4], c[4])
        end)

        it("SetDropdownSelected toggles selected row highlight", function()
            local parent = makeStubFrame()
            local btn = Theme.CreateDropdownMenuItem(parent, { index = 1, text = "Option", selected = false })
            assert.is_false(btn.altArmyDropdownSelectedBg._shown)
            btn:SetDropdownSelected(true)
            assert.is_true(btn.altArmyDropdownSelectedBg._shown)
            btn:SetDropdownSelected(false)
            assert.is_false(btn.altArmyDropdownSelectedBg._shown)
        end)

        it("calls onEnter and onLeave while keeping hover tint", function()
            local parent = makeStubFrame()
            local entered, left
            local btn = Theme.CreateDropdownMenuItem(parent, {
                index = 1,
                text = "Option",
                onEnter = function(self)
                    entered = self
                end,
                onLeave = function(self)
                    left = self
                end,
            })
            btn._scripts.OnEnter()
            assert.are.equal(btn, entered)
            assert.are.equal(Theme.HOVER_TINT_ALPHA, btn.altArmyHoverTint._vertex[4])
            btn._scripts.OnLeave()
            assert.are.equal(btn, left)
            assert.are.equal(0, btn.altArmyHoverTint._vertex[4])
        end)
    end)

    describe("CreateSingleSelectDropdown", function()
        it("shows selected entry label on the trigger button", function()
            local parent = makeStubFrame()
            local selected = "all"
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                width = 200,
                entries = {
                    { id = "all", label = "All realms" },
                    { id = "current", label = "Current realm" },
                },
                getSelectedId = function() return selected end,
                onSelect = function(id) selected = id end,
            })
            assert.is_not_nil(dd)
            assert.are.equal("All realms", dd.label._text)
            selected = "current"
            dd:Update()
            assert.are.equal("Current realm", dd.label._text)
        end)

        it("calls onSelect and closes popup when an item is chosen", function()
            local parent = makeStubFrame()
            local selected = "chat"
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                entries = {
                    { id = "chat", label = "Chat message" },
                    { id = "both", label = "Both" },
                },
                getSelectedId = function() return selected end,
                onSelect = function(id) selected = id end,
            })
            dd.popup:Show()
            assert.is_true(dd.popup:IsShown())
            local bothItem
            for i = 1, #framesCreated do
                local f = framesCreated[i]
                if f.entryId == "both" and f._scripts and f._scripts.OnClick then
                    bothItem = f
                    break
                end
            end
            assert.is_not_nil(bothItem)
            bothItem._scripts.OnClick(bothItem)
            assert.are.equal("both", selected)
            assert.is_false(dd.popup:IsShown())
        end)

        it("calls onEntryEnter and onEntryLeave with the hovered entry", function()
            local parent = makeStubFrame()
            local enteredEntry, enteredBtn, leftEntry
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                entries = {
                    { id = "auto", label = "Auto", spellId = 29688 },
                    { id = 17187, label = "Arcanite", spellId = 17187 },
                },
                getSelectedId = function() return "auto" end,
                onEntryEnter = function(btn, entry)
                    enteredBtn = btn
                    enteredEntry = entry
                end,
                onEntryLeave = function(_btn, entry)
                    leftEntry = entry
                end,
            })
            local item
            for i = 1, #framesCreated do
                local f = framesCreated[i]
                if f.entryId == 17187 and f._scripts and f._scripts.OnEnter then
                    item = f
                    break
                end
            end
            assert.is_not_nil(item)
            item._scripts.OnEnter()
            assert.are.equal(item, enteredBtn)
            assert.is_not_nil(enteredEntry)
            assert.are.equal(17187, enteredEntry.id)
            assert.are.equal(17187, enteredEntry.spellId)
            item._scripts.OnLeave()
            assert.are.equal(17187, leftEntry.id)
        end)

        it("widens the popup past the button when a label does not fit", function()
            local parent = makeStubFrame()
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                width = 100,
                entries = {
                    { id = "a", label = "A" },
                    { id = "long", label = "Cumulative play time" },
                },
                getSelectedId = function() return "a" end,
            })
            -- 20 chars * 7px stub width = 140px of text alone.
            assert.is_true(dd.popup:GetWidth() > 140)
        end)

        it("anchors the popup's right edge to the button when popupAlign is right", function()
            local parent = makeStubFrame()
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                popupAlign = "right",
                entries = { { id = "a", label = "A" } },
                getSelectedId = function() return "a" end,
            })
            local p = dd.popup._points[#dd.popup._points]
            assert.are.equal("TOPRIGHT", p[1])
            assert.are.equal(dd.button, p[2])
            assert.are.equal("BOTTOMRIGHT", p[3])
        end)

        it("keeps the popup at button width when labels fit", function()
            local parent = makeStubFrame()
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                width = 200,
                entries = { { id = "a", label = "A" } },
                getSelectedId = function() return "a" end,
            })
            assert.are.equal(200, dd.popup:GetWidth())
        end)

        it("SetEnabled disables the trigger and closes the popup", function()
            local parent = makeStubFrame()
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                entries = { { id = "a", label = "A" } },
                getSelectedId = function() return "a" end,
            })
            dd.popup:Show()
            dd:SetEnabled(false)
            assert.is_false(dd.button:IsEnabled())
            assert.is_false(dd.popup:IsShown())
        end)

        it("does not scroll when entries fit within maxVisibleRows", function()
            local parent = makeStubFrame()
            local rowHeight = 24
            local entries = {}
            for i = 1, 12 do
                entries[i] = { id = tostring(i), label = "Row " .. i }
            end
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                rowHeight = rowHeight,
                maxVisibleRows = 12,
                entries = entries,
                getSelectedId = function() return "1" end,
            })
            dd.listViewport.scroll._height = dd.popup:GetHeight()
            dd.listViewport.UpdateRange()
            assert.are.equal(12 * rowHeight + 4, dd.popup:GetHeight())
            assert.is_false(dd.scrollBar:IsShown())
        end)

        it("shows a scrollbar when entries exceed maxVisibleRows", function()
            local parent = makeStubFrame()
            local rowHeight = 24
            local entries = {}
            for i = 1, 15 do
                entries[i] = { id = tostring(i), label = "Row " .. i }
            end
            local dd = Theme.CreateSingleSelectDropdown({
                parent = parent,
                rowHeight = rowHeight,
                maxVisibleRows = 12,
                entries = entries,
                getSelectedId = function() return "1" end,
            })
            dd.listViewport.scroll._height = dd.popup:GetHeight()
            dd.listViewport.UpdateRange()
            assert.are.equal(12 * rowHeight + 4, dd.popup:GetHeight())
            assert.is_true(dd.scrollBar:IsShown())
            assert.is_true((dd.listViewport.child:GetHeight() or 0) > dd.popup:GetHeight())
        end)
    end)

    describe("BindInteractableHover", function()
        it("installs tint and wires enter/leave scripts", function()
            local f = makeStubFrame()
            f._scripts = {}
            function f:EnableMouse() end
            Theme.BindInteractableHover(f)
            assert.is_not_nil(f.altArmyHoverTint)
            assert.is_not_nil(f._scripts.OnEnter)
            assert.is_not_nil(f._scripts.OnLeave)
        end)

        it("supports bandHeight for partial-row highlights", function()
            local f = makeStubFrame()
            f._scripts = {}
            function f:EnableMouse() end
            Theme.BindInteractableHover(f, { bandHeight = 18 })
            assert.is_not_nil(f.altArmyHoverTint)
        end)
    end)

    describe("vertical scroll bar layout", function()
        it("defines Graphs-tab width, gap, inset, and gutter", function()
            assert.are.equal(14, Theme.SCROLL_BAR_WIDTH)
            assert.are.equal(2, Theme.SCROLL_BAR_GAP)
            assert.are.equal(4, Theme.SCROLL_BAR_RIGHT_INSET)
            assert.are.equal(20, Theme.VerticalScrollBarGutter())
        end)
    end)

    describe("SetupScrollBar", function()
        it("styles track and knob thumb like the Compare panel", function()
            local slider = makeStubFrame()
            slider.GetWidth = function() return 14 end
            Theme.SetupScrollBar(slider, { thickness = 14 })
            assert.is_not_nil(slider.altArmyScrollTrack)
            assert.are.equal(0.08, slider.altArmyScrollTrack._color[1])
            assert.is_not_nil(slider.altArmyScrollThumb)
            assert.are.equal(Theme.SCROLL_KNOB_TEXTURE, slider.altArmyScrollThumb._texture)
            assert.are.equal(18, slider.altArmyScrollThumb._width)
            assert.are.equal(24, slider.altArmyScrollThumb._height)
        end)

        it("sizes horizontal thumbs along the bar width", function()
            local slider = makeStubFrame()
            slider.GetHeight = function() return 12 end
            Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            assert.are.equal(24, slider.altArmyScrollThumb._width)
            assert.are.equal(16, slider.altArmyScrollThumb._height)
        end)
    end)

    describe("native minimal scroll bars", function()
        local savedNativeUI, savedCTexture

        before_each(function()
            savedNativeUI, savedCTexture = AltArmy.NativeUI, _G.C_Texture
            AltArmy.NativeUI = { GetCaps = function() return { nineSlice = true, minimalScrollBar = true } end }
            _G.C_Texture = {
                GetAtlasInfo = function(name)
                    return {
                        file = "atlasfile:" .. name, width = 8, height = 10,
                        leftTexCoord = 0.1, rightTexCoord = 0.2, topTexCoord = 0.3, bottomTexCoord = 0.4,
                    }
                end,
            }
        end)

        after_each(function()
            AltArmy.NativeUI, _G.C_Texture = savedNativeUI, savedCTexture
        end)

        local function stubSlider()
            local slider = makeStubFrame()
            slider._minVal, slider._maxVal, slider._value = 0, 100, 0
            function slider:GetValueStep() return self._valueStep or 20 end
            function slider:SetValueStep(v) self._valueStep = v end
            return slider
        end

        it("draws the MinimalScrollBar track atlases inset for the stepper buttons", function()
            local slider = stubSlider()
            Theme.SetupScrollBar(slider, { thickness = 14 })
            local track = slider.altArmyNativeTrack
            local S = Theme.MINIMAL_SCROLL.stepperInset
            assert.are.equal("minimal-scrollbar-track-top", track.Begin._atlas)
            assert.are.equal("!minimal-scrollbar-track-middle", track.Middle._atlas)
            assert.are.equal("minimal-scrollbar-track-bottom", track.End._atlas)
            assert.are.same({ "TOP", slider, "TOP", 0, -S }, track.Begin._points[1])
            assert.are.same({ "BOTTOM", slider, "BOTTOM", 0, S }, track.End._points[1])
            assert.is_nil(slider.altArmyScrollTrack)
        end)

        it("uses an invisible hit thumb that spans the stepper insets", function()
            local slider = stubSlider()
            local thumb = Theme.SetupScrollBar(slider, { thickness = 14 })
            local S = Theme.MINIMAL_SCROLL.stepperInset
            assert.are.equal(0, thumb._color[4])
            assert.is_nil(thumb._atlas)
            assert.are.equal(Theme.SCROLL_THUMB_LENGTH + 2 * S, thumb._height)
        end)

        it("draws rounded caps with the middle piece strictly between them", function()
            local slider = stubSlider()
            local thumb = Theme.SetupScrollBar(slider, { thickness = 14 })
            local art = slider.altArmyNativeThumb
            local S = Theme.MINIMAL_SCROLL.stepperInset
            assert.are.equal("minimal-scrollbar-small-thumb-top", art.Begin._atlas)
            assert.are.equal("minimal-scrollbar-small-thumb-middle", art.Middle._atlas)
            assert.are.equal("minimal-scrollbar-small-thumb-bottom", art.End._atlas)
            assert.are.same({ "TOP", thumb, "TOP", 0, -S }, art.Begin._points[1])
            assert.are.same({ "BOTTOM", thumb, "BOTTOM", 0, S }, art.End._points[1])
            assert.are.same({ "TOPLEFT", art.Begin, "BOTTOMLEFT", 0, 0 }, art.Middle._points[1])
            assert.are.same({ "BOTTOMRIGHT", art.End, "TOPRIGHT", 0, 0 }, art.Middle._points[2])
        end)

        it("swaps thumb art to the -over atlases while hovered", function()
            local slider = stubSlider()
            Theme.SetupScrollBar(slider, { thickness = 14 })
            slider._scripts.OnEnter(slider)
            assert.are.equal("minimal-scrollbar-small-thumb-middle-over", slider.altArmyNativeThumb.Middle._atlas)
            slider._scripts.OnLeave(slider)
            assert.are.equal("minimal-scrollbar-small-thumb-middle", slider.altArmyNativeThumb.Middle._atlas)
        end)

        it("adds arrow stepper buttons that step the slider value", function()
            local slider = stubSlider()
            Theme.SetupScrollBar(slider, { thickness = 14 })
            local back, fwd = slider.altArmyStepBack, slider.altArmyStepForward
            assert.are.equal("minimal-scrollbar-arrow-top", back.altArmyArrow._atlas)
            assert.are.equal("minimal-scrollbar-arrow-bottom", fwd.altArmyArrow._atlas)
            fwd._scripts.OnClick(fwd)
            assert.are.equal(20, slider:GetValue())
            fwd._scripts.OnClick(fwd)
            back._scripts.OnClick(back)
            assert.are.equal(20, slider:GetValue())
            slider:SetValue(95)
            fwd._scripts.OnClick(fwd)
            assert.are.equal(100, slider:GetValue())
        end)

        it("grays out and disables the arrow at whichever end the value sits", function()
            local slider = stubSlider()
            Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            local back, fwd = slider.altArmyStepBack, slider.altArmyStepForward
            assert.is_true(back.altArmyArrow._desaturated)
            assert.is_false(fwd.altArmyArrow._desaturated)
            -- Disabled arrow ignores clicks and hover art.
            back._scripts.OnClick(back)
            assert.are.equal(0, slider:GetValue())
            back._scripts.OnEnter(back)
            assert.are.equal("atlasfile:minimal-scrollbar-arrow-top", back.altArmyArrow._texture)
            slider:SetValue(100)
            assert.is_false(back.altArmyArrow._desaturated)
            assert.is_true(fwd.altArmyArrow._desaturated)
            slider:SetValue(50)
            assert.is_false(back.altArmyArrow._desaturated)
            assert.is_false(fwd.altArmyArrow._desaturated)
        end)

        it("disables both arrows when there is no scroll range", function()
            local slider = stubSlider()
            slider._maxVal = 0
            Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            assert.is_true(slider.altArmyStepBack.altArmyArrow._desaturated)
            assert.is_true(slider.altArmyStepForward.altArmyArrow._desaturated)
        end)

        it("CreateHorizontalScrollBar refreshes arrow state when the range changes", function()
            local api = Theme.CreateHorizontalScrollBar(makeStubFrame(), { thickness = 12 })
            local fwd = api.bar.altArmyStepForward
            assert.is_true(fwd.altArmyArrow._desaturated)
            api:SetRange(0, 200)
            assert.is_false(fwd.altArmyArrow._desaturated)
        end)

        it("steps horizontal bars by at least the minimum step", function()
            local slider = stubSlider()
            slider:SetValueStep(1)
            Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            slider.altArmyStepForward._scripts.OnClick(slider.altArmyStepForward)
            assert.are.equal(Theme.MINIMAL_SCROLL.minStep, slider:GetValue())
        end)

        it("rotates the atlases for horizontal sliders", function()
            local slider = stubSlider()
            local thumb = Theme.SetupScrollBar(slider, { horizontal = true, thickness = 12 })
            local mid = slider.altArmyNativeThumb.Middle
            assert.are.equal("atlasfile:minimal-scrollbar-small-thumb-middle", mid._texture)
            -- 90 degree rotation: UL=(R,T) LL=(L,T) UR=(R,B) LR=(L,B)
            assert.are.same({ 0.2, 0.3, 0.1, 0.3, 0.2, 0.4, 0.1, 0.4 }, mid._texCoord)
            local S = Theme.MINIMAL_SCROLL.stepperInset
            assert.are.equal(Theme.SCROLL_THUMB_LENGTH + 2 * S, thumb._width)
            assert.are.equal("atlasfile:minimal-scrollbar-arrow-top", slider.altArmyStepBack.altArmyArrow._texture)
        end)

        it("is idempotent", function()
            local slider = stubSlider()
            Theme.SetupScrollBar(slider, { thickness = 14 })
            local count = #slider._textures
            Theme.SetupScrollBar(slider, { thickness = 14 })
            assert.are.equal(count, #slider._textures)
        end)
    end)

    describe("section layout spacing", function()
        it("defines tab section inset and inter-panel gap matching Graphs tab", function()
            assert.are.equal(0, Theme.TAB_SECTION_INSET)
            assert.are.equal(4, Theme.SECTION_GAP)
        end)
    end)

    describe("sort header arrows", function()
        local function makeLabel(justify)
            local btn = makeStubFrame()
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetJustifyH(justify)
            return btn, label
        end

        it("sets the label and draws no arrow when the column is not sorted", function()
            local btn, label = makeLabel("LEFT")
            Theme.SetSortHeaderLabel(label, "Item", false, true)
            assert.are.equal("Item", label._text)
            assert.are.equal(0, #btn._textures)
        end)

        it("draws Blizzard's sort arrow texture pointing up after a left-justified label when ascending", function()
            local btn, label = makeLabel("LEFT")
            Theme.SetSortHeaderLabel(label, "Recipe", true, true)
            assert.are.equal("Recipe", label._text)
            local arrow = btn._textures[1]
            assert.is_not_nil(arrow)
            assert.are.equal(Theme.SORT_ARROW.texture, arrow._texture)
            assert.are.equal(Theme.SORT_ARROW.width, arrow._width)
            assert.are.equal(Theme.SORT_ARROW.height, arrow._height)
            assert.are.same({ 0, 0.5625, 1, 0 }, arrow._texCoord)
            assert.is_true(arrow:IsShown())
            local gap = label:GetStringWidth() + Theme.SORT_ARROW.gap
            assert.are.same({ "LEFT", label, "LEFT", gap, 0 }, arrow._points[1])
        end)

        it("points the arrow down when descending", function()
            local btn, label = makeLabel("LEFT")
            Theme.SetSortHeaderLabel(label, "Skill", true, false)
            assert.are.same({ 0, 0.5625, 0, 1 }, btn._textures[1]._texCoord)
        end)

        it("puts the arrow before the text of a right-justified label", function()
            local btn, label = makeLabel("RIGHT")
            Theme.SetSortHeaderLabel(label, "Skill", true, true)
            local gap = label:GetStringWidth() + Theme.SORT_ARROW.gap
            assert.are.same({ "RIGHT", label, "RIGHT", -gap, 0 }, btn._textures[1]._points[1])
        end)

        it("puts the arrow after the text of a centred label", function()
            local btn, label = makeLabel("CENTER")
            Theme.SetSortHeaderLabel(label, "Name", true, true)
            local gap = label:GetStringWidth() / 2 + Theme.SORT_ARROW.gap
            assert.are.same({ "LEFT", label, "CENTER", gap, 0 }, btn._textures[1]._points[1])
        end)

        describe("SetSortArrowButton", function()
            local R = 0.5625

            it("draws the arrow centred on the button, pointing right", function()
                local btn = makeStubFrame()
                Theme.SetSortArrowButton(btn, "right")
                local arrow = btn._textures[1]
                assert.are.equal(Theme.SORT_ARROW.texture, arrow._texture)
                assert.are.same({ 0, 0, R, 0, 0, 1, R, 1 }, arrow._texCoord)
                assert.are.equal(12, arrow._width)
                assert.are.equal(14, arrow._height)
                assert.are.same({ "CENTER", btn, "CENTER", 1, 0 }, arrow._points[1])
                assert.is_true(arrow:IsShown())
            end)

            it("points left, up and down, reusing one texture", function()
                local btn = makeStubFrame()
                Theme.SetSortArrowButton(btn, "left")
                assert.are.same({ 0, 1, R, 1, 0, 0, R, 0 }, btn._textures[1]._texCoord)
                assert.are.same({ { "CENTER", btn, "CENTER", -1, 0 } }, btn._textures[1]._points)
                Theme.SetSortArrowButton(btn, "up")
                assert.are.same({ 0, R, 1, 0 }, btn._textures[1]._texCoord)
                assert.are.same({ { "CENTER", btn, "CENTER", 0, 0 } }, btn._textures[1]._points)
                assert.are.equal(14, btn._textures[1]._width)
                assert.are.equal(12, btn._textures[1]._height)
                Theme.SetSortArrowButton(btn, "down")
                assert.are.same({ 0, R, 0, 1 }, btn._textures[1]._texCoord)
                assert.are.equal(1, #btn._textures)
            end)
        end)

        it("reuses one arrow per label and hides it when the column stops being sorted", function()
            local btn, label = makeLabel("LEFT")
            Theme.SetSortHeaderLabel(label, "Recipe", true, true)
            Theme.SetSortHeaderLabel(label, "Recipe", true, false)
            Theme.SetSortHeaderLabel(label, "Recipe", false, false)
            assert.are.equal(1, #btn._textures)
            assert.is_false(btn._textures[1]:IsShown())
            assert.are.equal("Recipe", label._text)
        end)
    end)

    describe("CreateTabContentPanel", function()
        it("creates a section-backed panel for tab content", function()
            local parent = makeStubFrame()
            local panel = Theme.CreateTabContentPanel(parent)
            assert.is_not_nil(panel._backdrop)
            assert.are.equal(Theme.SECTION_BACKDROP.edgeSize, panel._backdrop.edgeSize)
        end)
    end)

    describe("CreateMainContentPanel", function()
        it("creates a background-only panel with no border edge", function()
            local parent = makeStubFrame()
            local panel = Theme.CreateMainContentPanel(parent)
            assert.is_not_nil(panel._backdrop)
            assert.is_nil(panel._backdrop.edgeFile)
            assert.is_not_nil(panel._backdrop.bgFile)
        end)

        it("native chrome draws the background without a NineSlice layout", function()
            local recipe = Theme.NATIVE_TIERS.content
            assert.is_not_nil(recipe)
            assert.is_nil(recipe.layout)
            assert.is_not_nil(recipe.bg)
        end)
    end)

    describe("CreateSettingsPanelContent", function()
        it("creates a child content frame with standard padding", function()
            local panel = makeStubFrame()
            assert.are.equal(8, Theme.SETTINGS_PANEL_PADDING)
            assert.are.equal(8, Theme.TAB_CONTENT_PADDING)
            local content = Theme.CreateSettingsPanelContent(panel)
            assert.is_not_nil(content)
        end)
    end)

    describe("CreateSeparator", function()
        it("creates a gold separator texture", function()
            local parent = makeStubFrame()
            local sep = Theme.CreateSeparator(parent, 100)
            assert.are.equal(Theme.COLORS.sepLine[1], sep._color[1])
        end)
    end)

    describe("ScrollMax and ClampScroll", function()
        it("computes max scroll from child and viewport heights", function()
            assert.are.equal(0, Theme.ScrollMax(100, 200))
            assert.are.equal(50, Theme.ScrollMax(250, 200))
        end)

        it("clamps scroll offset to valid range", function()
            assert.are.equal(0, Theme.ClampScroll(-10, 100))
            assert.are.equal(100, Theme.ClampScroll(150, 100))
            assert.are.equal(42, Theme.ClampScroll(42, 100))
        end)
    end)

    describe("CreateVerticalScrollViewport", function()
        it("scrolls by wheelStep on mouse wheel", function()
            local parent = makeStubFrame()
            parent._height = 100
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
                wheelStep = 40,
                valueStep = 20,
                wheelSource = "scroll",
            })
            viewport.child._height = 300
            viewport.scroll._height = 100
            viewport:UpdateRange()
            viewport.scroll._scripts.OnMouseWheel(viewport.scroll, -1)
            assert.are.equal(40, viewport.scroll:GetVerticalScroll())
            assert.are.equal(40, viewport.scrollBar:GetValue())
        end)

        it("clamps scroll position when range shrinks", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
                wheelStep = 20,
                valueStep = 20,
            })
            viewport.child._height = 500
            viewport.scroll._height = 100
            viewport.scroll:SetVerticalScroll(200)
            viewport.scrollBar:SetValue(200)
            viewport.child._height = 150
            viewport:UpdateRange()
            assert.are.equal(50, viewport.scroll:GetVerticalScroll())
            assert.are.equal(50, viewport.scrollBar:GetValue())
        end)

        it("hides scrollbar when content fits", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent,
                gutterEdge = parent,
            })
            viewport.child._height = 50
            viewport.scroll._height = 100
            viewport:UpdateRange()
            assert.is_false(viewport.scrollBar:IsShown())
        end)

        it("notifies OnScroll listeners on wheel (Slider fallback)", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({
                parent = parent, gutterEdge = parent, wheelStep = 40, valueStep = 20,
            })
            viewport.child._height = 300
            viewport.scroll._height = 100
            viewport.UpdateRange()
            local seen = {}
            viewport.OnScroll(function(offset) seen[#seen + 1] = offset end)
            viewport.scroll._scripts.OnMouseWheel(viewport.scroll, -1)
            assert.are.same({ 40 }, seen)
            assert.are.equal(40, viewport.GetOffset())
        end)
    end)

    describe("CreateVerticalScrollBinding (native MinimalScrollBar)", function()
        local savedNativeUI, savedScrollUtil, savedCreateFrame, savedEvents
        local created, initCalls

        local function makeNativeBar()
            local bar = makeStubFrame()
            bar._callbacks = {}
            bar._pct = 0
            function bar:RegisterCallback(event, fn, owner)
                self._callbacks[#self._callbacks + 1] = { event = event, fn = fn, owner = owner }
            end
            function bar:SetScrollPercentage(p, immediate)
                self._pct = p
                self._lastImmediate = immediate
                for _, cb in ipairs(self._callbacks) do
                    if cb.event == "OnScroll" then cb.fn(cb.owner, p) end
                end
            end
            function bar:GetScrollPercentage() return self._pct end
            function bar:SetHideIfUnscrollable(on) self._hideIfUnscrollable = on end
            function bar:ScrollStepInDirection(dir) self._steppedDir = dir end
            return bar
        end

        local function makeScrollFrame(childH, viewH)
            local scroll = makeStubFrame()
            scroll._height = viewH
            local child = makeStubFrame()
            child._height = childH
            scroll:SetScrollChild(child)
            function scroll:GetVerticalScrollRange()
                return math.max(0, self._scrollChild:GetHeight() - self:GetHeight())
            end
            function scroll:GetHorizontalScrollRange() return 0 end
            function scroll:UpdateScrollChildRect() self._rectUpdated = true end
            function scroll:GetParent() return self._parentFrame end
            scroll._parentFrame = makeStubFrame()
            return scroll
        end

        before_each(function()
            savedNativeUI, savedScrollUtil = AltArmy.NativeUI, _G.ScrollUtil
            savedCreateFrame, savedEvents = _G.CreateFrame, _G.BaseScrollBoxEvents
            created, initCalls = {}, {}
            AltArmy.NativeUI = { GetCaps = function() return { minimalScrollBar = true } end }
            _G.BaseScrollBoxEvents = { OnScroll = "OnScroll" }
            _G.CreateFrame = function(frameType, name, parent, template)
                local f = (template == "MinimalScrollBar") and makeNativeBar() or makeStubFrame()
                created[#created + 1] = { frameType = frameType, name = name, parent = parent, template = template, frame = f }
                return f
            end
            _G.ScrollUtil = {
                InitScrollFrameWithScrollBar = function(scrollFrame, bar)
                    initCalls[#initCalls + 1] = { scrollFrame = scrollFrame, bar = bar }
                    function scrollFrame:SetPanExtent(p) self._panExtent = p end
                    scrollFrame:SetScript("OnScrollRangeChanged", function(sf)
                        sf._rangeChangedCalls = (sf._rangeChangedCalls or 0) + 1
                    end)
                    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
                        bar:ScrollStepInDirection(-delta)
                    end)
                end,
            }
        end)

        after_each(function()
            AltArmy.NativeUI, _G.ScrollUtil = savedNativeUI, savedScrollUtil
            _G.CreateFrame, _G.BaseScrollBoxEvents = savedCreateFrame, savedEvents
        end)

        it("creates a MinimalScrollBar wired by ScrollUtil with our pan extent", function()
            local scroll = makeScrollFrame(300, 100)
            local binding = Theme.CreateVerticalScrollBinding(scroll, { step = 36 })
            assert.is_true(binding.native)
            assert.are.equal("EventFrame", created[1].frameType)
            assert.are.equal("MinimalScrollBar", created[1].template)
            assert.are.equal(1, #initCalls)
            assert.are.equal(scroll, initCalls[1].scrollFrame)
            assert.are.equal(binding.bar, initCalls[1].bar)
            assert.are.equal(36, scroll._panExtent)
            assert.is_true(binding.bar._hideIfUnscrollable)
            assert.is_true(binding.bar.altArmyNativeScrollBar)
        end)

        it("applies bar scrolls to the frame and notifies once per offset", function()
            local scroll = makeScrollFrame(300, 100)
            local seen = {}
            local binding = Theme.CreateVerticalScrollBinding(scroll, {
                onScroll = function(offset) seen[#seen + 1] = offset end,
            })
            binding.bar:SetScrollPercentage(0.5)
            assert.are.equal(100, scroll:GetVerticalScroll())
            binding.bar:SetScrollPercentage(0.5)
            assert.are.same({ 100 }, seen)
        end)

        it("SetOffset clamps and drives the bar immediately", function()
            local scroll = makeScrollFrame(300, 100)
            local seen = {}
            local binding = Theme.CreateVerticalScrollBinding(scroll)
            binding.AddOnScroll(function(offset) seen[#seen + 1] = offset end)
            binding.SetOffset(500)
            assert.are.equal(200, scroll:GetVerticalScroll())
            assert.are.equal(1, binding.bar:GetScrollPercentage())
            assert.is_true(binding.bar._lastImmediate)
            assert.are.same({ 200 }, seen)
            assert.are.equal(200, binding.GetOffset())
            assert.are.equal(200, binding.GetMaxScroll())
        end)

        it("UpdateRange refreshes the ScrollUtil range handler and clamps", function()
            local scroll = makeScrollFrame(300, 100)
            local binding = Theme.CreateVerticalScrollBinding(scroll)
            binding.SetOffset(200)
            scroll._scrollChild._height = 150
            binding.UpdateRange()
            assert.is_true(scroll._rectUpdated)
            assert.are.equal(1, scroll._rangeChangedCalls)
            assert.are.equal(50, scroll:GetVerticalScroll())
        end)

        it("Wheel steps the bar opposite to the wheel delta", function()
            local scroll = makeScrollFrame(300, 100)
            local binding = Theme.CreateVerticalScrollBinding(scroll)
            binding.Wheel(1)
            assert.are.equal(-1, binding.bar._steppedDir)
        end)

        it("viewport exposes the native bar and forwards child wheel to it", function()
            local parent = makeStubFrame()
            local viewport = Theme.CreateVerticalScrollViewport({ parent = parent, gutterEdge = parent })
            assert.is_true(viewport.scrollBar.altArmyNativeScrollBar)
            viewport.child._scripts.OnMouseWheel(viewport.child, -1)
            assert.are.equal(1, viewport.scrollBar._steppedDir)
        end)
    end)

    describe("native grid chrome", function()
        local savedNativeUI, savedNineSlice

        before_each(function()
            savedNativeUI, savedNineSlice = AltArmy.NativeUI, _G.NineSliceUtil
            AltArmy.NativeUI = { GetCaps = function() return { nineSlice = true } end }
            _G.NineSliceUtil = { ApplyLayoutByName = function() end }
        end)

        after_each(function()
            AltArmy.NativeUI, _G.NineSliceUtil = savedNativeUI, savedNineSlice
        end)

        it("fills pinned grid headers with the inset background texture", function()
            local tex = makeStubTexture()
            Theme.StyleGridHeader(tex)
            assert.are.equal(Theme.NATIVE_TIERS.section.bg, tex._texture)
            assert.is_nil(tex._color)
        end)

        it("tints pinned-header fades as a neutral shadow", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header.GetParent = function() return viewport end
            local fade = Theme.CreatePinnedHeaderScrollFade({ headerFrame = header })
            assert.are.same(Theme.NATIVE_SCROLL_SHADOW, fade.frame._textures[1]._vertex)
        end)
    end)

    describe("CreatePinnedHeaderScrollFade", function()
        it("creates a texture fade anchored below the pinned header", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header._frameLevel = 20
            header.GetParent = function() return viewport end
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
            })
            assert.is_not_nil(fade.frame)
            assert.are.equal(70, fade.frame:GetFrameLevel())
            assert.are.equal(1, #fade.frame._textures)
            local tex = fade.frame._textures[1]
            assert.are.equal("Interface\\AddOns\\AltArmy_TBC\\Textures\\ScrollFade", tex._texture)
            assert.is_not_nil(tex._vertex)
            assert.are.equal(1, tex._vertex[4])
        end)

        it("hides the fade at scroll offset zero and shows it when scrolled", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header.GetParent = function() return viewport end
            local scroll = makeStubFrame()
            scroll._verticalScroll = 0
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
                scrollFrame = scroll,
            })
            fade:Update()
            assert.is_false(fade.frame:IsShown())
            scroll._verticalScroll = 40
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)

        it("prefers scroll bar value for visibility", function()
            local viewport = makeStubFrame()
            local header = makeStubFrame()
            header.GetParent = function() return viewport end
            local scrollBar = makeStubFrame()
            scrollBar._value = 12
            local fade = Theme.CreatePinnedHeaderScrollFade({
                headerFrame = header,
                scrollBar = scrollBar,
            })
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)
    end)

    describe("CreatePinnedHorizontalScrollFade", function()
        it("creates a vertical strip on the left edge of a horizontal scroll viewport", function()
            local parent = makeStubFrame()
            local scroll = makeStubFrame()
            scroll._frameLevel = 10
            scroll.GetParent = function() return parent end
            local fade = Theme.CreatePinnedHorizontalScrollFade({
                anchorScrollFrame = scroll,
            })
            assert.is_not_nil(fade.frame)
            assert.are.equal(60, fade.frame:GetFrameLevel())
            assert.are.equal(Theme.PINNED_HORIZONTAL_SCROLL_FADE_WIDTH, fade.frame:GetWidth())
            local tex = fade.frame._textures[1]
            assert.are.equal("Interface\\AddOns\\AltArmy_TBC\\Textures\\ScrollFade", tex._texture)
            assert.are.same({ 0, 0, 0, 0, 1, 1, 1, 1 }, tex._texCoord)
        end)

        it("shows the fade when horizontal scroll offset is greater than zero", function()
            local parent = makeStubFrame()
            local scroll = makeStubFrame()
            scroll.GetParent = function() return parent end
            scroll._horizontalScroll = 0
            function scroll:GetHorizontalScroll() return self._horizontalScroll end
            local fade = Theme.CreatePinnedHorizontalScrollFade({
                anchorScrollFrame = scroll,
                scrollFrame = scroll,
            })
            fade:Update()
            assert.is_false(fade.frame:IsShown())
            scroll._horizontalScroll = 24
            fade:Update()
            assert.is_true(fade.frame:IsShown())
        end)
    end)

    describe("HorizontalDragValue", function()
        it("maps cursor delta across bar width to scroll range", function()
            assert.are.equal(50, Theme.HorizontalDragValue(0, 100, 0, 1, 200, 0, 100))
        end)

        it("accounts for UI scale", function()
            assert.are.equal(25, Theme.HorizontalDragValue(0, 100, 0, 2, 200, 0, 100))
        end)

        it("clamps to min and max", function()
            assert.are.equal(0, Theme.HorizontalDragValue(0, -500, 0, 1, 200, 0, 100))
            assert.are.equal(100, Theme.HorizontalDragValue(0, 500, 0, 1, 200, 0, 100))
        end)

        it("returns start value when bar width or scale is invalid", function()
            assert.are.equal(10, Theme.HorizontalDragValue(10, 200, 0, 1, 0, 0, 100))
            assert.are.equal(10, Theme.HorizontalDragValue(10, 200, 0, 0, 200, 0, 100))
        end)

        it("accounts for thumb length along the track", function()
            -- travel = 200 - 24 = 176; cursor delta 88 -> 50% of range
            assert.are.equal(50, Theme.HorizontalDragValue(0, 88, 0, 1, 200, 0, 100, 24))
        end)
    end)

    describe("CreateHorizontalScrollBar", function()
        it("invokes onScroll via Sync when value changes", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                thickness = 12,
                onScroll = function(value)
                    scrolled = value
                end,
                isShown = function() return true end,
            })
            hbar.bar:SetValue(42)
            hbar:Sync()
            assert.are.equal(42, scrolled)
            hbar:Sync()
            assert.are.equal(42, scrolled)
        end)

        it("Reset applies zero", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function(value)
                    scrolled = value
                end,
            })
            hbar.bar:SetValue(50)
            hbar:Reset()
            assert.are.equal(0, hbar.bar:GetValue())
            assert.are.equal(0, scrolled)
        end)

        it("Restore clamps and reapplies saved scroll offset", function()
            local parent = makeStubFrame()
            local scrolled = nil
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function(value)
                    scrolled = value
                end,
            })
            hbar.bar:SetValue(120)
            hbar:SetRange(0, 80)
            hbar:Restore(80)
            assert.are.equal(80, hbar.bar:GetValue())
            assert.are.equal(80, scrolled)
        end)

        it("SetRange updates slider min/max", function()
            local parent = makeStubFrame()
            local hbar = Theme.CreateHorizontalScrollBar(parent, {})
            hbar:SetRange(0, 300)
            local minVal, maxVal = hbar.bar:GetMinMaxValues()
            assert.are.equal(0, minVal)
            assert.are.equal(300, maxVal)
        end)

        it("drag OnUpdate applies onScroll once per value change via OnValueChanged", function()
            local parent = makeStubFrame()
            local scrollCount = 0
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onScroll = function()
                    scrollCount = scrollCount + 1
                end,
                isShown = function() return true end,
            })
            hbar.bar._width = 200
            hbar:SetRange(0, 100)
            local onMouseDown = hbar.bar:GetScript("OnMouseDown")
            local onUpdate = hbar.bar:GetScript("OnUpdate")
            assert.is_nil(onUpdate)
            _G.GetCursorPosition = function() return 0, 0 end
            _G.IsMouseButtonDown = function() return true end
            onMouseDown(hbar.bar, "LeftButton")
            onUpdate = hbar.bar:GetScript("OnUpdate")
            assert.is_not_nil(onUpdate)
            _G.GetCursorPosition = function() return 50, 0 end
            onUpdate(hbar.bar)
            assert.are.equal(1, scrollCount)
            onUpdate(hbar.bar)
            assert.are.equal(1, scrollCount)
        end)

        it("invokes onDragEnd when mouse button is released after drag", function()
            local parent = makeStubFrame()
            parent._width = 200
            local dragEnded = false
            local hbar = Theme.CreateHorizontalScrollBar(parent, {
                onDragEnd = function()
                    dragEnded = true
                end,
                isShown = function() return true end,
            })
            hbar:SetRange(0, 100)
            local onMouseDown = hbar.bar:GetScript("OnMouseDown")
            _G.GetCursorPosition = function() return 0, 0 end
            _G.IsMouseButtonDown = function() return true end
            onMouseDown(hbar.bar, "LeftButton")
            local onUpdate = hbar.bar:GetScript("OnUpdate")
            _G.IsMouseButtonDown = function() return false end
            onUpdate(hbar.bar)
            assert.is_true(dragEnded)
            assert.is_nil(hbar.bar:GetScript("OnUpdate"))
        end)
    end)

    describe("CreateThemeCheckbox", function()
        it("returns a themed CheckButton with background and checked textures", function()
            local parent = makeStubFrame()
            local check = Theme.CreateThemeCheckbox(parent)
            assert.is_not_nil(check)
            assert.are.equal(18, check._width)
            assert.are.equal(18, check._height)
            assert.are.equal(3, #check._textures)
            assert.are.equal("BACKGROUND", check._textures[1]._layer)
            assert.are.same(Theme.COLORS.inputBorder, check._textures[1]._color)
            assert.are.equal(check, check._textures[1]._allPoints)
            assert.are.equal("BORDER", check._textures[2]._layer)
            assert.are.same(Theme.COLORS.inputBg, check._textures[2]._color)
            assert.are.same({ "TOPLEFT", check, "TOPLEFT", 1, -1 }, check._textures[2]._points[1])
            assert.are.same({ "BOTTOMRIGHT", check, "BOTTOMRIGHT", -1, 1 }, check._textures[2]._points[2])
            assert.are.equal("OVERLAY", check._textures[3]._layer)
            assert.are.equal("Interface\\Buttons\\UI-CheckBox-Check", check._textures[3]._texture)
            assert.are.equal(check._textures[3], check._checkedTexture)
        end)

        it("honors custom size", function()
            local parent = makeStubFrame()
            local check = Theme.CreateThemeCheckbox(parent, 22)
            assert.are.equal(22, check._width)
            assert.are.equal(22, check._height)
        end)

        it("uses UICheckButtonTemplate, padded for its transparent art, when native", function()
            local savedNativeUI, savedCreateFrame = AltArmy.NativeUI, _G.CreateFrame
            local template
            AltArmy.NativeUI = { GetCaps = function() return { checkButton = true } end }
            _G.CreateFrame = function(kind, _, _, tmpl)
                template = tmpl
                local f = makeStubFrame()
                f._kind = kind
                return f
            end
            local check = Theme.CreateThemeCheckbox(makeStubFrame())
            AltArmy.NativeUI, _G.CreateFrame = savedNativeUI, savedCreateFrame
            assert.are.equal("UICheckButtonTemplate", template)
            assert.are.equal("CheckButton", check._kind)
            assert.are.equal(18 + Theme.NATIVE_CHECKBOX_PAD, check._width)
            assert.are.equal(0, #check._textures)
        end)
    end)

    describe("EditBox placeholder helpers", function()
        local function makeStubEditBox()
            local box = makeStubFrame()
            box._text = ""
            box._focused = false
            function box:GetText() return self._text end
            function box:SetText(text) self._text = text or "" end
            function box:HasFocus() return self._focused end
            function box:SetFocus() self._focused = true end
            function box:ClearFocus() self._focused = false end
            return box
        end

        it("shows the fallback hint when the field is empty, even while focused", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetFocus()
            Theme.UpdateEditBoxPlaceholderVisibility(box)
            assert.is_true(box.altArmyPlaceholderHint:IsShown())
        end)

        it("defaults the fallback hint to no vertical offset", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            local points = box.altArmyPlaceholderHint._points or {}
            assert.are.equal(0, points[1][5])
            assert.are.equal(0, points[2][5])
        end)

        it("honors an explicit placeholder yOffset", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Filter faction", {
                leftInset = 4,
                rightInset = 4,
                yOffset = -2,
            })
            local points = box.altArmyPlaceholderHint._points or {}
            assert.are.equal(-2, points[1][5])
            assert.are.equal(-2, points[2][5])
        end)

        it("hides the fallback hint when the field has text", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetText("abc")
            Theme.UpdateEditBoxPlaceholderVisibility(box)
            assert.is_false(box.altArmyPlaceholderHint:IsShown())
        end)

        it("restores the fallback hint after ClearEditBoxText", function()
            local box = makeStubEditBox()
            Theme.SetupEditBoxPlaceholder(box, "Search here")
            box:SetText("abc")
            box:SetFocus()
            Theme.ClearEditBoxText(box)
            assert.are.equal("", box:GetText())
            assert.is_false(box:HasFocus())
            assert.is_true(box.altArmyPlaceholderHint:IsShown())
        end)

        it("SetEditBoxText replaces text and resets cursor so the value is visible on load", function()
            local box = makeStubEditBox()
            box._cursor = 99
            function box:SetCursorPosition(pos) self._cursor = pos end
            function box:GetCursorPosition() return self._cursor end
            Theme.SetEditBoxText(box, "Frell")
            assert.are.equal("Frell", box:GetText())
            assert.are.equal(0, box:GetCursorPosition())
        end)

        it("SetEditBoxText tolerates EditBoxes without SetCursorPosition", function()
            local box = makeStubEditBox()
            Theme.SetEditBoxText(box, "Frell")
            assert.are.equal("Frell", box:GetText())
        end)
    end)

    describe("ApplySearchInputIcon", function()
        it("places a muted search icon on the left and indents typed text", function()
            local box = makeStubFrame()
            local leftInset = Theme.ApplySearchInputIcon(box)
            local icon = box.altArmySearchIcon
            assert.is_not_nil(icon)
            assert.are.equal("OVERLAY", icon._layer)
            assert.are.equal(Theme.SEARCH_INPUT_ICON, icon._texture)
            assert.are.equal(12, icon._width)
            assert.are.equal(12, icon._height)
            assert.are.same({ "LEFT", box, "LEFT", 3, -1 }, icon._points[1])
            assert.are.same({ 0.55, 0.55, 0.55, 0.9 }, icon._vertex)
            assert.are.equal(18, leftInset)
            assert.are.same({ 18, 6, 0, 0 }, box._textInsets)
        end)

        it("honors a smaller icon for compact filter fields", function()
            local box = makeStubFrame()
            local leftInset = Theme.ApplySearchInputIcon(box, {
                size = 10,
                leftPad = 2,
                gap = 2,
                rightInset = 4,
            })
            local icon = box.altArmySearchIcon
            assert.are.equal(10, icon._width)
            assert.are.equal(10, icon._height)
            assert.are.same({ "LEFT", box, "LEFT", 2, -1 }, icon._points[1])
            assert.are.equal(14, leftInset)
            assert.are.same({ 14, 4, 0, 0 }, box._textInsets)
        end)

        it("reuses the existing icon texture instead of creating another", function()
            local box = makeStubFrame()
            Theme.ApplySearchInputIcon(box)
            local first = box.altArmySearchIcon
            local textureCount = #box._textures
            Theme.ApplySearchInputIcon(box, { size = 10 })
            assert.are.equal(first, box.altArmySearchIcon)
            assert.are.equal(textureCount, #box._textures)
            assert.are.equal(10, first._width)
        end)

        it("does nothing when the edit box is missing", function()
            assert.are.equal(0, Theme.ApplySearchInputIcon(nil))
        end)
    end)

    describe("ApplyInputTextures (native)", function()
        it("draws the InputBoxTemplate three-slice border atlases", function()
            local savedNativeUI = AltArmy.NativeUI
            AltArmy.NativeUI = { GetCaps = function() return { inputBox = true } end }
            local box = makeStubFrame()
            Theme.ApplyInputTextures(box)
            AltArmy.NativeUI = savedNativeUI
            assert.are.equal("common-search-border-left", box.altArmyInputLeft._atlas)
            assert.are.equal("common-search-border-middle", box.altArmyInputMiddle._atlas)
            assert.are.equal("common-search-border-right", box.altArmyInputRight._atlas)
            assert.are.same({ "LEFT", box, "LEFT", -5, 0 }, box.altArmyInputLeft._points[1])
            assert.is_nil(box.altArmyInputBg)
        end)
    end)

    describe("CreateSearchBox", function()
        local savedCreateFrame, savedNativeUI, lastTemplate

        before_each(function()
            savedCreateFrame, savedNativeUI = _G.CreateFrame, AltArmy.NativeUI
            lastTemplate = nil
            _G.CreateFrame = function(_, _, _, template)
                lastTemplate = template
                local f = makeStubFrame()
                f.SetAutoFocus = function() end
                f.SetTextInsets = function(self, ...) self._textInsets = { ... } end
                if template == "SearchBoxTemplate" then
                    f.Instructions = f:CreateFontString(nil, "ARTWORK")
                end
                return f
            end
        end)

        after_each(function()
            _G.CreateFrame, AltArmy.NativeUI = savedCreateFrame, savedNativeUI
        end)

        it("uses SearchBoxTemplate and its Instructions placeholder when available", function()
            AltArmy.NativeUI = { GetCaps = function() return { searchBox = true } end }
            local box, isNative = Theme.CreateSearchBox(makeStubFrame(), {
                width = 180, placeholder = "Search for items",
            })
            assert.is_true(isNative)
            assert.are.equal("SearchBoxTemplate", lastTemplate)
            assert.are.equal("Search for items", box.Instructions._text)
            assert.are.equal(180, box._width)
            assert.is_nil(box.altArmySearchIcon)
        end)

        it("falls back to the custom icon + placeholder box", function()
            AltArmy.NativeUI = { GetCaps = function() return { searchBox = false } end }
            local box, isNative = Theme.CreateSearchBox(makeStubFrame(), {
                width = 200, placeholder = "Find",
            })
            assert.is_false(isNative)
            assert.is_nil(lastTemplate)
            assert.is_not_nil(box.altArmySearchIcon)
            assert.are.equal(200, box._width)
        end)

        it("SetEditBoxPlaceholderText updates the native Instructions placeholder", function()
            AltArmy.NativeUI = { GetCaps = function() return { searchBox = true } end }
            local box = Theme.CreateSearchBox(makeStubFrame(), { placeholder = "Old" })
            Theme.SetEditBoxPlaceholderText(box, "Search Bob's recipes")
            assert.are.equal("Search Bob's recipes", box.Instructions._text)
        end)

        it("fallback has a clear button inside the right edge, shown only with text", function()
            AltArmy.NativeUI = { GetCaps = function() return { searchBox = false } end }
            local box = Theme.CreateSearchBox(makeStubFrame(), { placeholder = "Find" })
            local clear = box.altArmyClearButton
            assert.is_not_nil(clear)
            assert.are.same({ "RIGHT", box, "RIGHT", -3, 0 }, clear._points[1])
            assert.is_false(clear:IsShown())
            box:SetText("felweed")
            box._scripts.OnTextChanged(box, true)
            assert.is_true(clear:IsShown())
            clear:Click()
            assert.are.equal("", box:GetText())
            box._scripts.OnTextChanged(box, false)
            assert.is_false(clear:IsShown())
        end)
    end)

    describe("CreateOptionsSectionLabel", function()
        it("uses GameFontNormal without custom title color", function()
            local parent = makeStubFrame()
            local anchor = makeStubFrame()
            local label = Theme.CreateOptionsSectionLabel(parent, {
                relativeTo = anchor,
                text = "Transmute",
            })
            assert.are.equal("GameFontNormal", label._template)
            assert.are.equal("Transmute", label._text)
            assert.are.equal(0, label._textColorCalls)
        end)
    end)

    describe("CreateOptionsSlider", function()
        it("snaps to the step, words the value and tells of moves but not of SetValue", function()
            local parent = makeStubFrame()
            local changes = {}
            local row = Theme.CreateOptionsSlider(parent, {
                text = "Window Scale",
                min = 50,
                max = 200,
                step = 5,
                value = 100,
                format = function(v) return v .. "%" end,
                onChange = function(v) changes[#changes + 1] = v end,
            })
            assert.are.equal("Window Scale", row.label._text)
            assert.are.equal("100%", row.valueText._text)
            assert.are.same({ 50, 200 }, { row.slider:GetMinMaxValues() })
            assert.are.equal(100, row.GetValue())

            row.slider:SetValue(123) -- a drag: snapped to 125
            assert.are.equal(125, row.GetValue())
            assert.are.equal("125%", row.valueText._text)
            assert.are.same({ 125 }, changes)

            row.slider:SetValue(126) -- the same step: no change told
            assert.are.same({ 125 }, changes)

            row.SetValue(75) -- the saved value shown: no change told
            assert.are.equal(75, row.GetValue())
            assert.are.equal("75%", row.valueText._text)
            assert.are.same({ 125 }, changes)

            row.slider:SetValue(500) -- past the end: clamped
            assert.are.equal(200, row.GetValue())
            assert.are.same({ 125, 200 }, changes)
        end)

        it("stretches the slider to the row unless given a width, and takes a right anchor", function()
            local parent = makeStubFrame()
            local row = Theme.CreateOptionsSlider(parent, {
                text = "Font size", min = 9, max = 18, value = 12,
                right = { relativeTo = parent, relativePoint = "TOP", x = -4, y = 0 },
            })
            local found
            for _, pt in ipairs(row._points) do
                if pt[1] == "TOPRIGHT" then found = pt end
            end
            assert.are.same({ "TOPRIGHT", parent, "TOP", -4, 0 }, found)
            row._scripts.OnSizeChanged(row, 300, 44)
            assert.are.equal(292, row.slider:GetWidth())

            local fixed = Theme.CreateOptionsSlider(parent, { text = "x", min = 0, max = 1, width = 120 })
            assert.are.equal(120, fixed.slider:GetWidth())
            assert.is_nil(fixed._scripts.OnSizeChanged)
        end)
    end)

    describe("CreateLabeledCheckbox", function()
        it("uses character-list checkbox size and hover region", function()
            local parent = makeStubFrame()
            local clicked = false
            local row = Theme.CreateLabeledCheckbox(parent, {
                text = "Pin current character",
                onClick = function()
                    clicked = true
                end,
            })
            assert.are.equal(18, row.check._width)
            assert.are.equal(18, row.check._height)
            assert.is_not_nil(row.hoverRegion.altArmyHoverTint)
            row.hoverRegion._scripts.OnMouseUp(row.hoverRegion, "LeftButton")
            assert.is_true(clicked)
        end)
    end)

    describe("CreateVirtualScrollBinding", function()
        it("keeps its own offset within the range it is given, and shows the bar only with range", function()
            local range, seen = 0, {}
            local b = Theme.CreateVirtualScrollBinding({
                parent = makeStubFrame(),
                step = 20,
                getRange = function() return range end,
                getViewHeight = function() return 100 end,
                onScroll = function(offset) seen[#seen + 1] = offset end,
            })
            assert.is_false(b.bar:IsShown())
            range = 80
            b.UpdateRange()
            assert.is_true(b.bar:IsShown())
            assert.are.equal(80, b.GetMaxScroll())
            b.SetOffset(150)
            assert.are.equal(80, b.GetOffset())
            b.Wheel(1)
            assert.are.equal(60, b.GetOffset())
            range = 40
            b.UpdateRange()
            assert.are.equal(40, b.GetOffset())
            assert.are.same({ 80, 60 }, seen)
        end)
    end)

    describe("CreateMultiSelectCheckboxDropdown", function()
        --- The popup row (a CreateLabeledCheckbox frame) whose label reads `text`.
        local function rowLabeled(text)
            for _, f in ipairs(framesCreated) do
                if f.check and f.label and f.label._text == text then
                    return f
                end
            end
        end

        it("keeps a locked key checked, disabled and grey whatever the filter says", function()
            local parent = makeStubFrame()
            local map = { own = false, other = false }
            local toggled = {}
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                keys = { "own", "other" },
                labels = { own = "Own", other = "Other" },
                lockedKeys = { own = true },
                getFilter = function() return map end,
                setEnabled = function(key, on) toggled[#toggled + 1] = key; map[key] = on end,
            })
            local own, other = rowLabeled("Own"), rowLabeled("Other")
            assert.is_true(own.check._checked)
            assert.is_false(own.check:IsEnabled())
            assert.are.same({ 0.6, 0.6, 0.6 }, { own.label._textColor[1], own.label._textColor[2],
                own.label._textColor[3] })
            assert.is_false(other.check._checked)
            api.refresh()
            assert.is_true(own.check._checked)
            own.hoverRegion._scripts.OnMouseUp(own.hoverRegion, "LeftButton")
            assert.are.same({}, toggled)
        end)

        it("opens its popup above the window it sits in, kept on screen", function()
            local parent = makeStubFrame()
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                keys = { "a" },
                getFilter = function() return {} end,
            })
            assert.are.equal("FULLSCREEN_DIALOG", api.popup._strata)
            assert.is_true(api.popup._clamped)
        end)

        it("with fitRows, widens its popup leftward to fit its widest row", function()
            local parent = makeStubFrame()
            local long = string.rep("x", 60) -- the stub measures 7 px a character: 420 px
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                keys = { "a", "b" },
                labels = { a = "short", b = long },
                fitRows = true,
                getFilter = function() return {} end,
            })
            api.button._width = 200
            api.refresh()
            assert.is_true(api.popup._width > 420)
            local last = api.popup._points[#api.popup._points]
            assert.are.equal("TOPRIGHT", last[1])
            assert.are.equal("BOTTOMRIGHT", last[3])
        end)

        it("lays its rows out again when getKeys gives another list", function()
            local parent = makeStubFrame()
            local keys = { "a", "b" }
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                getKeys = function() return keys end,
                getRowLabel = function(key) return "row " .. key end,
                getFilter = function() return { a = true, b = false, c = true } end,
            })
            assert.is_true(rowLabeled("row a"):IsShown())
            assert.is_false(rowLabeled("row b").check._checked)
            keys = { "c" }
            api.refresh()
            local c = rowLabeled("row c")
            assert.is_true(c:IsShown())
            assert.is_true(c.check._checked)
            local shownB = false
            for _, f in ipairs(framesCreated) do
                if f.label and f.label._text == "row b" and f:IsShown() then shownB = true end
            end
            assert.is_false(shownB)
        end)

        it("draws a divider line for a divider key, never a checkbox", function()
            local parent = makeStubFrame()
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                keys = { "a", "--", "b" },
                labels = { ["--"] = "Group --" },
                isDivider = function(key) return key == "--" end,
                getRowLabel = function(key) return "row " .. key end,
                getFilter = function() return {} end,
                formatSummary = function(keys) return table.concat(keys, ",") end,
            })
            assert.is_not_nil(rowLabeled("row a"))
            assert.is_not_nil(rowLabeled("row b"))
            assert.is_nil(rowLabeled("row --"))
            local dividers = {}
            for _, f in ipairs(framesCreated) do
                if f.leftLine and f:IsShown() then dividers[#dividers + 1] = f end
            end
            assert.are.equal(1, #dividers)
            assert.are.equal("Group --", dividers[1].label._text)
            assert.is_not_nil(api.popup)
        end)

        it("hides every old row and divider when relaid out, though each pool has gaps", function()
            local before = #framesCreated
            local parent = makeStubFrame()
            local keys = { "-1", "a", "b", "-2", "c" }
            local api = Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                getKeys = function() return keys end,
                getLabels = function() return { ["-1"] = "G1", ["-2"] = "G2", ["-3"] = "G3" } end,
                isDivider = function(key) return key:sub(1, 1) == "-" end,
                getRowLabel = function(key) return "row " .. key end,
                getFilter = function() return {} end,
            })
            keys = { "-3", "d" }
            api.refresh()
            local shownRows, shownDividers = {}, {}
            for i = before + 1, #framesCreated do
                local f = framesCreated[i]
                if f:IsShown() and f.leftLine then shownDividers[#shownDividers + 1] = f.label._text end
                if f:IsShown() and f.check and f.label then shownRows[#shownRows + 1] = f.label._text end
            end
            assert.are.same({ "G3" }, shownDividers)
            assert.are.same({ "row d" }, shownRows)
        end)

        it("shows each row's label from getRowLabel", function()
            local parent = makeStubFrame()
            Theme.CreateMultiSelectCheckboxDropdown({
                parent = parent,
                relativeTo = parent,
                keys = { "MAGE" },
                getRowLabel = function(key) return "|cff3fc7ebMage|r" .. key end,
                getFilter = function() return {} end,
            })
            assert.is_not_nil(rowLabeled("|cff3fc7ebMage|rMAGE"))
        end)
    end)

    describe("AttachLabelHelpIcon", function()
        it("places a help-i icon and wires one hit region spanning label through icon", function()
            local parent = makeStubFrame()
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetText("Level look-ahead")
            local btn = Theme.AttachLabelHelpIcon(label, {
                title = "Level look-ahead",
                lines = { "How many levels ahead an item may require." },
            })
            assert.are.equal(14, btn._width)
            assert.are.equal(14, btn._height)
            assert.are.equal("Interface\\Common\\help-i", btn._textures[1]._texture)
            assert.is_not_nil(btn.hitRegion)
            assert.is_not_nil(btn.hitRegion._scripts.OnEnter)
            assert.is_not_nil(btn.hitRegion._scripts.OnLeave)
            local points = btn.hitRegion._points
            assert.is_not_nil(points)
            local hasLeftOnLabel = false
            local hasRightOnBtn = false
            for _, point in ipairs(points) do
                if point[1] == "TOPLEFT" and point[2] == label then
                    hasLeftOnLabel = true
                end
                if point[1] == "BOTTOMRIGHT" and point[2] == btn then
                    hasRightOnBtn = true
                end
            end
            assert.is_true(hasLeftOnLabel)
            assert.is_true(hasRightOnBtn)
        end)
    end)

    describe("CreateCollapsibleSection", function()
        local savedNativeUI

        --- The frame's newest TOPLEFT anchor (the stub's ClearAllPoints keeps old ones).
        local function lastPoint(frame)
            for i = #(frame._points or {}), 1, -1 do
                if frame._points[i][1] == "TOPLEFT" then
                    return frame._points[i]
                end
            end
        end

        local function withAtlases(on)
            AltArmy.NativeUI = { HasAtlas = function() return on end }
        end

        before_each(function()
            savedNativeUI = AltArmy.NativeUI
        end)

        after_each(function()
            AltArmy.NativeUI = savedNativeUI
        end)

        describe("with the Settings panel's expandable-section art", function()
            before_each(function() withAtlases(true) end)

            it("draws the Options_ListExpand bar, collapsed by default", function()
                local section = Theme.CreateCollapsibleSection(makeStubFrame(), { text = "Guild" })
                assert.is_true(section.native)
                assert.are.equal("Options_ListExpand_Left", section.header.Left._atlas)
                assert.are.equal("_Options_ListExpand_Middle", section.header.Middle._atlas)
                assert.are.equal("Options_ListExpand_Right", section.header.Right._atlas)
                assert.are.equal("Guild", section.label._text)
                assert.is_false(section.content:IsShown())
                assert.are.equal(Theme.COLLAPSIBLE_HEADER_HEIGHT, section.frame:GetHeight())
            end)

            it("opens and closes from its header, taking its content's height", function()
                local toggled = {}
                local section = Theme.CreateCollapsibleSection(makeStubFrame(), {
                    text = "General",
                    contentHeight = 58,
                    defaultExpanded = true,
                    onToggle = function(on) toggled[#toggled + 1] = on end,
                })
                local open = Theme.COLLAPSIBLE_HEADER_HEIGHT + Theme.COLLAPSIBLE_CONTENT_GAP + 58
                    + Theme.COLLAPSIBLE_BOTTOM_PAD
                assert.are.equal(open, section.frame:GetHeight())
                assert.are.equal("Options_ListExpand_Right_Expanded", section.header.Right._atlas)
                assert.is_true(section.content:IsShown())
                section.header:Click()
                assert.is_false(section.IsExpanded())
                assert.are.equal(Theme.COLLAPSIBLE_HEADER_HEIGHT, section.frame:GetHeight())
                assert.are.equal("Options_ListExpand_Right", section.header.Right._atlas)
                assert.is_false(section.content:IsShown())
                section.SetExpanded(true, true)
                assert.are.equal(open, section.GetHeight())
                assert.same({ false }, toggled) -- a silent change calls nobody
            end)

            it("lights up its bar and brightens its label under the mouse", function()
                local section = Theme.CreateCollapsibleSection(makeStubFrame(), { text = "Guild" })
                local header = section.header
                for _, key in ipairs({ "Left", "Middle", "Right" }) do
                    local glow = header.Highlight[key]
                    assert.are.equal("HIGHLIGHT", glow._layer)
                    assert.are.equal("ADD", glow._blendMode)
                    assert.are.equal(header[key]._atlas, glow._atlas)
                end
                header:GetScript("OnEnter")(header)
                assert.same({ 1, 1, 1, nil }, section.label._textColor)
                header:GetScript("OnLeave")(header)
                assert.same({ 1, 0.82, 0, nil }, section.label._textColor)
                section.SetExpanded(true)
                assert.are.equal("Options_ListExpand_Right_Expanded", header.Highlight.Right._atlas)
            end)

            it("keeps its content inside its own frame, below the header", function()
                local section = Theme.CreateCollapsibleSection(makeStubFrame(), { text = "Guild" })
                assert.same({ "TOPLEFT", section.header, "BOTTOMLEFT", 0, -Theme.COLLAPSIBLE_CONTENT_GAP },
                    lastPoint(section.content))
                assert.same({ "TOPLEFT", section.frame, "TOPLEFT", 0, 0 }, lastPoint(section.header))
            end)
        end)

        describe("without it", function()
            before_each(function() withAtlases(false) end)

            it("draws the trade skill window's plus and minus buttons", function()
                local section = Theme.CreateCollapsibleSection(makeStubFrame(), { text = "Guild" })
                assert.is_false(section.native)
                local icon = section.header.collapseIcon
                assert.are.equal("Interface\\Buttons\\UI-PlusButton-UP", icon._texture)
                section.header:Click()
                assert.are.equal("Interface\\Buttons\\UI-MinusButton-UP", icon._texture)
                assert.is_true(section.content:IsShown())
            end)
        end)

        describe("StackCollapsibleSections", function()
            before_each(function() withAtlases(true) end)

            local function closed()
                return Theme.COLLAPSIBLE_HEADER_HEIGHT
            end

            local function open(h)
                return Theme.COLLAPSIBLE_HEADER_HEIGHT + Theme.COLLAPSIBLE_CONTENT_GAP + h
                    + Theme.COLLAPSIBLE_BOTTOM_PAD
            end

            local function sections(parent)
                local a = Theme.CreateCollapsibleSection(parent,
                    { text = "General", contentHeight = 60, defaultExpanded = true })
                local b = Theme.CreateCollapsibleSection(parent, { text = "Guild", contentHeight = 200 })
                local c = Theme.CreateCollapsibleSection(parent, { text = "Auction House", contentHeight = 30 })
                return a, b, c
            end

            it("puts each section under the one before, whatever it holds", function()
                local parent = makeStubFrame()
                local a, b, c = sections(parent)
                local layout = Theme.StackCollapsibleSections({ a, b, c }, { parent = parent, gap = 6 })
                assert.are.equal(open(60) + closed() * 2 + 6 * 2, layout())
                assert.same({ "TOPLEFT", parent, "TOPLEFT", 0, 0 }, lastPoint(a.frame))
                assert.same({ "TOPLEFT", a.frame, "BOTTOMLEFT", 0, -6 }, lastPoint(b.frame))
                assert.same({ "TOPLEFT", b.frame, "BOTTOMLEFT", 0, -6 }, lastPoint(c.frame))
                b.SetExpanded(true)
                assert.are.equal(open(60) + open(200) + closed() + 6 * 2, layout())
                assert.same({ "TOPLEFT", b.frame, "BOTTOMLEFT", 0, -6 }, lastPoint(c.frame))
            end)

            it("skips a hidden section", function()
                local parent = makeStubFrame()
                local a, b, c = sections(parent)
                b.SetShown(false)
                assert.is_false(b.frame:IsShown())
                local layout = Theme.StackCollapsibleSections({ a, b, c }, { parent = parent, gap = 6 })
                assert.are.equal(open(60) + closed() + 6, layout())
                assert.same({ "TOPLEFT", a.frame, "BOTTOMLEFT", 0, -6 }, lastPoint(c.frame))
            end)

            it("follows a section whose content changes height", function()
                local parent = makeStubFrame()
                local a, b, c = sections(parent)
                local layout = Theme.StackCollapsibleSections({ a, b, c }, { parent = parent, gap = 6 })
                a.SetContentHeight(100)
                assert.are.equal(open(100) + closed() * 2 + 6 * 2, layout())
            end)
        end)
    end)
end)
