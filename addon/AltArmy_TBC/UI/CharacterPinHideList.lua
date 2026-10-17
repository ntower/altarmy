-- AltArmy TBC — Reusable character Pin/Hide list for settings panels (Gear, Summary).
-- Requires: AltArmy, AltArmy.Characters, AltArmy.RealmFilter (optional).

if not AltArmy then return end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local CHAR_LIST_ROW = 20
local ROW_RIGHT_INSET = 120
local ROW_RIGHT_INSET_HIDE_ONLY = 60
local CHAR_LIST_BOTTOM_INSET = 4
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local BANK_ALT_HEADER = "Hidden bank alts"
local DISABLED_LABEL_R, DISABLED_LABEL_G, DISABLED_LABEL_B = 0.45, 0.45, 0.45


--- Create a scrollable character list with Pin/Hide checkboxes.
--- @param parent Frame Parent (e.g. settings content frame).
--- @param anchorBelow Frame Anchor the top of the list below this frame (e.g. realm dropdown button).
--- @param opts table getSettings, getCharSetting, setCharSetting, onChange (optional)
--- @return Frame scrollFrame, function Refresh()
function AltArmy.CreateCharacterPinHideList(parent, anchorBelow, opts)
    opts = opts or {}
    local getSettings = opts.getSettings or function() return {} end
    local getCharSetting = opts.getCharSetting or function() return false end
    local setCharSetting = opts.setCharSetting or function() end
    local onChange = opts.onChange or function() end
    local splitBankAlts = opts.splitBankAlts ~= false
    -- Align scrollbar with section border (same as main tab listViewport + tabContentPanel).
    local gutterEdge = opts.gutterEdge or parent

    local bottomInset = opts.bottomInset ~= nil and opts.bottomInset or CHAR_LIST_BOTTOM_INSET
    local viewport = Theme.CreateVerticalScrollViewport({
        parent = parent,
        gutterEdge = gutterEdge,
        wheelStep = CHAR_LIST_ROW * 2,
        valueStep = CHAR_LIST_ROW,
        enableMouse = true,
        wheelSource = "scroll",
        wheelOnChild = true,
    })
    local scroll = viewport.scroll
    scroll:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", gutterEdge, "BOTTOMRIGHT", -SCROLL_GUTTER, bottomInset)
    local scrollBar = viewport.scrollBar
    scroll.scrollBar = scrollBar
    local child = viewport.child

    local rowPool = {}
    local function SetPinRegionHover(row, on)
        Theme.SetHoverTint(row.pinRegion, on)
    end
    local function SetHideRegionHover(row, on)
        Theme.SetHoverTint(row.hideRegion, on)
    end
    local function BindPinRegionHover(row, widget)
        if not widget then return end
        widget:HookScript("OnEnter", function() SetPinRegionHover(row, true) end)
        widget:HookScript("OnLeave", function() SetPinRegionHover(row, false) end)
    end
    local function BindHideRegionHover(row, widget)
        if not widget then return end
        widget:HookScript("OnEnter", function() SetHideRegionHover(row, true) end)
        widget:HookScript("OnLeave", function() SetHideRegionHover(row, false) end)
    end
    local function GetRow(i)
        if not rowPool[i] then
            local row = CreateFrame("Frame", nil, child)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * CHAR_LIST_ROW)
            row:SetHeight(CHAR_LIST_ROW)
            row:SetPoint("RIGHT", child, "RIGHT", 0, 0)

            row.pinRegion = CreateFrame("Frame", nil, row)
            row.pinRegion:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.pinRegion:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            Theme.InstallHoverTint(row.pinRegion)

            row.hideBtn = Theme.CreateThemeCheckbox(row)
            row.hideBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.hideLabel = row.hideBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            row.hideLabel:SetPoint("RIGHT", row.hideBtn, "LEFT", -2, 0)
            row.hideLabel:SetText("Hide")

            row.pinRegion:SetPoint("RIGHT", row.hideLabel, "LEFT", -4, 0)

            row.hideRegion = CreateFrame("Frame", nil, row)
            row.hideRegion:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            row.hideRegion:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.hideRegion:SetPoint("LEFT", row.hideLabel, "LEFT", -4, 0)
            Theme.InstallHoverTint(row.hideRegion)

            row.nameText = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -ROW_RIGHT_INSET, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)

            row.pinBtn = Theme.CreateThemeCheckbox(row)
            row.pinBtn:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.pinLabel = row.pinBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            row.pinLabel:SetPoint("RIGHT", row.pinBtn, "LEFT", -2, 0)
            row.pinLabel:SetText("Pin")

            local nameOverlay = CreateFrame("Button", nil, row)
            nameOverlay:SetPoint("LEFT", row, "LEFT", 0, 0)
            nameOverlay:SetPoint("RIGHT", row.hideLabel, "LEFT", -4, 0)
            nameOverlay:SetHeight(CHAR_LIST_ROW)
            nameOverlay:RegisterForClicks("LeftButtonUp")
            nameOverlay:SetScript("OnClick", function()
                row.pinBtn:Click()
            end)
            nameOverlay:SetScript("OnEnter", function(self)
                SetPinRegionHover(row, true)
                if self.fullNameDisplay and self.wasTruncated and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            nameOverlay:SetScript("OnLeave", function()
                SetPinRegionHover(row, false)
                if GameTooltip then GameTooltip:Hide() end
            end)
            row.nameOverlay = nameOverlay

            row.pinRegion:EnableMouse(true)
            row.pinRegion:SetScript("OnEnter", function() SetPinRegionHover(row, true) end)
            row.pinRegion:SetScript("OnLeave", function() SetPinRegionHover(row, false) end)
            row.pinRegion:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then row.pinBtn:Click() end
            end)

            row.hideRegion:EnableMouse(true)
            row.hideRegion:SetScript("OnEnter", function() SetHideRegionHover(row, true) end)
            row.hideRegion:SetScript("OnLeave", function() SetHideRegionHover(row, false) end)
            row.hideRegion:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then row.hideBtn:Click() end
            end)

            BindPinRegionHover(row, row.pinBtn)
            BindHideRegionHover(row, row.hideBtn)

            row.pinRegion:SetFrameLevel(row:GetFrameLevel())
            row.hideRegion:SetFrameLevel(row:GetFrameLevel())
            row.nameText:SetDrawLayer("OVERLAY")
            nameOverlay:SetFrameLevel(row:GetFrameLevel() + 2)
            row.pinBtn:SetFrameLevel(row:GetFrameLevel() + 4)
            row.hideBtn:SetFrameLevel(row:GetFrameLevel() + 4)

            row.headerText = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
            row.headerText:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.headerText:SetTextColor(0.65, 0.65, 0.65, 1)
            row.headerText:Hide()

            rowPool[i] = row
        end
        return rowPool[i]
    end

    local function partitionByBankAlt(list)
        local regular, bank = {}, {}
        local BA = AltArmy.BankAlt
        for i = 1, #list do
            local e = list[i]
            if BA and BA.Is and BA.Is(e.name, e.realm) then
                bank[#bank + 1] = e
            else
                regular[#regular + 1] = e
            end
        end
        return regular, bank
    end

    local function buildDisplayRows(list)
        if not splitBankAlts then
            local rows = {}
            for i = 1, #list do
                rows[#rows + 1] = { kind = "char", entry = list[i], isBankAlt = false }
            end
            return rows
        end
        local regular, bank = partitionByBankAlt(list)
        local rows = {}
        for i = 1, #regular do
            rows[#rows + 1] = { kind = "char", entry = regular[i], isBankAlt = false }
        end
        if #bank > 0 then
            rows[#rows + 1] = { kind = "header", text = BANK_ALT_HEADER }
            for i = 1, #bank do
                rows[#rows + 1] = { kind = "char", entry = bank[i], isBankAlt = true }
            end
        end
        return rows
    end

    local function setCheckboxMuted(checkBtn, muted)
        checkBtn:SetEnabled(not muted)
        checkBtn:SetAlpha(muted and 0.55 or 1)
        for ri = 1, checkBtn:GetNumRegions() do
            local region = select(ri, checkBtn:GetRegions())
            if region and region.SetVertexColor then
                if muted then
                    region:SetVertexColor(0.55, 0.55, 0.55, 1)
                else
                    region:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
    end

    local function setNameTextInset(row, hideOnly)
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", hideOnly and -ROW_RIGHT_INSET_HIDE_ONLY or -ROW_RIGHT_INSET, 0)
        row.nameText:SetJustifyH("LEFT")
    end

    local function bindNameOverlayNormal(row)
        row.nameOverlay:SetScript("OnClick", function()
            row.pinBtn:Click()
        end)
        row.nameOverlay:SetScript("OnEnter", function(self)
            SetPinRegionHover(row, true)
            if self.fullNameDisplay and self.wasTruncated and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row.nameOverlay:SetScript("OnLeave", function()
            SetPinRegionHover(row, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.nameOverlay:EnableMouse(true)
    end

    local function bindNameOverlayBankAlt(row)
        row.nameOverlay:SetScript("OnClick", nil)
        row.nameOverlay:SetScript("OnEnter", function(self)
            if self.fullNameDisplay and self.wasTruncated and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row.nameOverlay:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.nameOverlay:EnableMouse(true)
    end

    local function configureRowForHeader(row, text)
        row.pinBtn:Hide()
        row.pinLabel:Hide()
        row.pinRegion:Hide()
        row.hideBtn:Hide()
        row.hideLabel:Hide()
        row.hideRegion:Hide()
        row.nameOverlay:Hide()
        row.nameText:Hide()
        row.headerText:SetText(text or BANK_ALT_HEADER)
        row.headerText:Show()
    end

    local function configureRowForNormal(row)
        row.pinBtn:Show()
        row.pinLabel:Show()
        row.pinRegion:Show()
        row.hideBtn:Show()
        row.hideLabel:Show()
        row.hideRegion:Show()
        row.nameOverlay:Show()
        row.nameText:Show()
        row.headerText:Hide()
        setNameTextInset(row, false)
        row.pinLabel:SetTextColor(1, 1, 1, 1)
        row.hideLabel:SetTextColor(1, 1, 1, 1)
        setCheckboxMuted(row.pinBtn, false)
        setCheckboxMuted(row.hideBtn, false)
        row.pinBtn:Enable()
        row.hideBtn:Enable()
        row.pinRegion:EnableMouse(true)
        row.hideRegion:EnableMouse(true)
        bindNameOverlayNormal(row)
    end

    local function configureRowForBankAlt(row)
        row.pinBtn:Hide()
        row.pinLabel:Hide()
        row.pinRegion:Hide()
        row.hideBtn:Show()
        row.hideLabel:Show()
        row.hideRegion:Hide()
        row.nameOverlay:Show()
        row.nameText:Show()
        row.headerText:Hide()
        setNameTextInset(row, true)
        row.hideLabel:SetTextColor(DISABLED_LABEL_R, DISABLED_LABEL_G, DISABLED_LABEL_B, 1)
        row.hideBtn:SetChecked(true)
        setCheckboxMuted(row.hideBtn, true)
        bindNameOverlayBankAlt(row)
    end

    local function layoutDisplayRow(row, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * CHAR_LIST_ROW)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:SetHeight(CHAR_LIST_ROW)
    end

    function scroll:Refresh()
        local rawList = (AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList()) or {}
        local list = {}
        for i = 1, #rawList do list[i] = rawList[i] end
        table.sort(list, function(a, b)
            local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
            if na ~= nb then return na < nb end
            return (a.realm or ""):lower() < (b.realm or ""):lower()
        end)
        local s = getSettings()
        local currentRealm = (GetRealmName and GetRealmName()) or ""
        local realmFilter = "all"
        local GRF = AltArmy.GlobalRealmFilter
        if GRF and GRF.Get then
            realmFilter = GRF.Get()
        elseif s and s.realmFilter then
            realmFilter = s.realmFilter
        end
        local RF = AltArmy.RealmFilter
        if RF and RF.filterListByRealm then
            list = AltArmy.GlobalRealmFilter.FilterList(list, currentRealm)
        end
        local showRealmSuffix = (realmFilter == "all") and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
        for _, row in pairs(rowPool) do
            row:Hide()
        end
        local displayRows = buildDisplayRows(list)
        local n = #displayRows
        child:SetWidth(scroll:GetWidth() or 350)
        child:SetHeight(math.max(1, n * CHAR_LIST_ROW))
        viewport:UpdateRange()
        for i = 1, n do
            local dr = displayRows[i]
            local row = GetRow(i)
            row:Show()
            layoutDisplayRow(row, i)
            if dr.kind == "header" then
                configureRowForHeader(row, dr.text)
            else
                local entry = dr.entry
                local isBankAlt = dr.isBankAlt == true
                if isBankAlt then
                    configureRowForBankAlt(row)
                else
                    configureRowForNormal(row)
                end
                local r, g, b = 1, 0.82, 0
                if CC and CC.getRGBOr then
                    r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
                end
                local nameDisplayStr
                local tooltipDisplayStr
                if RF and RF.formatColoredCharacterNameRealm then
                    nameDisplayStr = RF.formatColoredCharacterNameRealm(
                        entry.name or "?",
                        entry.realm,
                        showRealmSuffix,
                        entry.classFile
                    )
                    tooltipDisplayStr = nameDisplayStr
                    row.nameText:SetText(nameDisplayStr)
                    row.nameText:SetTextColor(1, 1, 1, 1)
                else
                    nameDisplayStr = entry.name or "?"
                    tooltipDisplayStr = string.format("|cFF%02x%02x%02x%s|r",
                        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), nameDisplayStr)
                    row.nameText:SetText(nameDisplayStr)
                    row.nameText:SetTextColor(r, g, b, 1)
                end
                local nameW = row.nameText:GetWidth()
                local displayed = nameDisplayStr
                if nameW and nameW > 4 then
                    displayed = TruncateFontString and TruncateFontString(row.nameText, nameDisplayStr, nameW - 2)
                        or nameDisplayStr
                end
                if row.nameOverlay then
                    row.nameOverlay.fullNameDisplay = tooltipDisplayStr
                    row.nameOverlay.wasTruncated = (displayed ~= nameDisplayStr)
                end
                row.entry = entry
                if not isBankAlt then
                    local pin = getCharSetting(entry.name, entry.realm, "pin")
                    local hide = getCharSetting(entry.name, entry.realm, "hide")
                    row.pinBtn:SetChecked(pin)
                    row.hideBtn:SetChecked(hide)
                    row.pinBtn:SetScript("OnClick", function()
                        local newPin = not getCharSetting(entry.name, entry.realm, "pin")
                        setCharSetting(entry.name, entry.realm, newPin, false)
                        row.pinBtn:SetChecked(newPin)
                        row.hideBtn:SetChecked(false)
                        onChange()
                    end)
                    row.hideBtn:SetScript("OnClick", function()
                        local newHide = not getCharSetting(entry.name, entry.realm, "hide")
                        setCharSetting(entry.name, entry.realm, false, newHide)
                        row.hideBtn:SetChecked(newHide)
                        row.pinBtn:SetChecked(false)
                        onChange()
                    end)
                else
                    row.pinBtn:SetScript("OnClick", function() end)
                    row.hideBtn:SetScript("OnClick", function() end)
                end
            end
        end
    end

    return scroll, scroll.Refresh
end
