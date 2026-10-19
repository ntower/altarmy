-- AltArmy TBC — Search tab settings panel (extracted from TabSearch).

AltArmy = AltArmy or {}
AltArmy.TabSearchSettings = AltArmy.TabSearchSettings or {}

local Theme = AltArmy.Theme
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString

--- Install the search settings panel on the Search tab frame.
--- @param frame Frame Search tab frame
--- @param UI table layout metrics from TabSearch
--- @return table { panel, ApplyLayout, RefreshControls, IsShown }
function AltArmy.TabSearchSettings.Install(frame, UI)
    if not frame or not UI or not Theme then
        return nil
    end

    -- Search settings panel: right 40% of frame when visible (list 60%, both full height).
    local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    Theme.ApplyBackdrop(settingsPanel, "section")

    local applyRecipeLevelFilterRowLayout
    local SyncCraftFilterDropdowns

    local function ApplySettingsPanelLayout()
        local w = frame:GetWidth()
        if w <= 0 then
            return
        end
        local settingsLeft = w * UI.GRID_SPLIT_FRACTION + UI.SECTION_GAP + UI.SEARCH_SETTINGS_WIDTH_TRIM
        settingsPanel:ClearAllPoints()
        settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", settingsLeft, -UI.SECTION_INSET)
        settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", settingsLeft, UI.SECTION_INSET)
        settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.SECTION_INSET, -UI.SECTION_INSET)
        settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.SECTION_INSET, UI.SECTION_INSET)
        if applyRecipeLevelFilterRowLayout then
            applyRecipeLevelFilterRowLayout()
        end
        if SyncCraftFilterDropdowns then
            SyncCraftFilterDropdowns()
        end
    end

    ApplySettingsPanelLayout()
    settingsPanel:Hide()

    local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
    local searchSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
    searchSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
    searchSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
    searchSettingsTitle:SetJustifyH("LEFT")
    searchSettingsTitle:SetText("Search Settings")
    Theme.SetTitleColor(searchSettingsTitle)

    local filterContent = CreateFrame("Frame", nil, settingsContent)
    filterContent:SetPoint("TOPLEFT", searchSettingsTitle, "BOTTOMLEFT", 0, -8)
    filterContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)

    local SS = AltArmy.SearchSettings
    local RI = AltArmy.RecipeInfo

    local UpdateRecipeLevelResetButtonVisibility

    local function RerunSearchIfActive()
        if frame.lastQuery and frame.lastQuery ~= "" and frame.SearchWithQuery then
            frame:SearchWithQuery(frame.lastQuery)
        elseif frame.DoSearch then
            frame:DoSearch()
        end
        if UpdateRecipeLevelResetButtonVisibility then
            UpdateRecipeLevelResetButtonVisibility()
        end
        if AltArmy and AltArmy.UpdateSearchSettingsButtonGlow then
            AltArmy.UpdateSearchSettingsButtonGlow()
        end
    end


    local function SetRecipeLevelHeaderColor(fontString)
        if not fontString or not fontString.SetTextColor then
            return
        end
        local value = Theme.COLORS and Theme.COLORS.value
        if value then
            fontString:SetTextColor(value[1], value[2], value[3], value[4])
        else
            fontString:SetTextColor(1, 1, 1, 1)
        end
    end

    local recipeLevelHeader = filterContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    recipeLevelHeader:SetText("Recipe Level")
    SetRecipeLevelHeaderColor(recipeLevelHeader)

    local professionSectionAnchor = CreateFrame("Frame", nil, filterContent)
    professionSectionAnchor:SetSize(1, 1)
    professionSectionAnchor:SetPoint("TOPLEFT", filterContent, "TOPLEFT", 0, 0)

    local minLevelLabel = filterContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    minLevelLabel:SetPoint("TOPLEFT", recipeLevelHeader, "BOTTOMLEFT", 0, -UI.RECIPE_LEVEL_ROW_GAP)
    minLevelLabel:SetText("Min")

    local minLevelEdit = CreateFrame("EditBox", nil, filterContent)
    minLevelEdit:SetSize(UI.RECIPE_LEVEL_DEFAULT_EDIT_WIDTH, UI.SETTINGS_ROW_HEIGHT)
    minLevelEdit:SetFontObject(Theme.FONTS.body)
    minLevelEdit:SetAutoFocus(false)
    minLevelEdit:SetNumeric(true)
    minLevelEdit:SetJustifyH("CENTER")
    minLevelEdit:SetPoint("LEFT", minLevelLabel, "RIGHT", 6, -2)
    Theme.ApplyInputTextures(minLevelEdit)
    minLevelEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    local suppressRecipeFilterTextChanged = false

    local function ApplyRecipeLevelFilterMin(box, normalizeDisplay)
        if suppressRecipeFilterTextChanged or not SS or not SS.SetRecipeLevelFilterMin then
            return
        end
        SS.SetRecipeLevelFilterMin(box:GetText())
        if normalizeDisplay then
            suppressRecipeFilterTextChanged = true
            box:SetText(tostring(SS.GetRecipeLevelFilter().min))
            suppressRecipeFilterTextChanged = false
        end
        RerunSearchIfActive()
    end

    local function ApplyRecipeLevelFilterMax(box, normalizeDisplay)
        if suppressRecipeFilterTextChanged or not SS or not SS.SetRecipeLevelFilterMax then
            return
        end
        SS.SetRecipeLevelFilterMax(box:GetText())
        if normalizeDisplay then
            suppressRecipeFilterTextChanged = true
            box:SetText(tostring(SS.GetRecipeLevelFilter().max))
            suppressRecipeFilterTextChanged = false
        end
        RerunSearchIfActive()
    end

    minLevelEdit:SetScript("OnTextChanged", function(box)
        ApplyRecipeLevelFilterMin(box, false)
    end)
    minLevelEdit:SetScript("OnEditFocusLost", function(box)
        ApplyRecipeLevelFilterMin(box, true)
    end)

    local maxLevelLabel = filterContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    maxLevelLabel:SetPoint("LEFT", minLevelEdit, "RIGHT", 12, 0)
    maxLevelLabel:SetPoint("TOP", minLevelLabel, "TOP", 0, 0)
    maxLevelLabel:SetText("Max")

    local maxLevelEdit = CreateFrame("EditBox", nil, filterContent)
    maxLevelEdit:SetSize(UI.RECIPE_LEVEL_DEFAULT_EDIT_WIDTH, UI.SETTINGS_ROW_HEIGHT)
    maxLevelEdit:SetFontObject(Theme.FONTS.body)
    maxLevelEdit:SetAutoFocus(false)
    maxLevelEdit:SetNumeric(true)
    maxLevelEdit:SetJustifyH("CENTER")
    maxLevelEdit:SetPoint("LEFT", maxLevelLabel, "RIGHT", 6, -2)
    maxLevelEdit:SetPoint("TOP", minLevelEdit, "TOP", 0, 0)
    Theme.ApplyInputTextures(maxLevelEdit)
    maxLevelEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    maxLevelEdit:SetScript("OnTextChanged", function(box)
        ApplyRecipeLevelFilterMax(box, false)
    end)
    maxLevelEdit:SetScript("OnEditFocusLost", function(box)
        ApplyRecipeLevelFilterMax(box, true)
    end)

    local function ResetRecipeLevelFilterControls()
        if not SS or not SS.ResetRecipeLevelFilter then
            return
        end
        SS.ResetRecipeLevelFilter()
        suppressRecipeFilterTextChanged = true
        minLevelEdit:SetText(tostring(SS.MIN_RECIPE_LEVEL or 0))
        maxLevelEdit:SetText(tostring(SS.MAX_RECIPE_LEVEL or 375))
        suppressRecipeFilterTextChanged = false
        minLevelEdit:ClearFocus()
        maxLevelEdit:ClearFocus()
        RerunSearchIfActive()
    end

    local recipeLevelResetBtn = CreateFrame("Button", nil, filterContent, "BackdropTemplate")
    recipeLevelResetBtn:SetSize(UI.SETTINGS_ROW_HEIGHT, UI.SETTINGS_ROW_HEIGHT)
    recipeLevelResetBtn:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
    recipeLevelResetBtn:SetPoint("TOP", minLevelEdit, "TOP", 0, 0)
    Theme.ApplyBackdrop(recipeLevelResetBtn, "section")
    if Theme.InstallHoverTint then
        Theme.InstallHoverTint(recipeLevelResetBtn)
    end
    local recipeLevelResetIcon = recipeLevelResetBtn:CreateTexture(nil, "ARTWORK")
    recipeLevelResetIcon:SetSize(14, 14)
    recipeLevelResetIcon:SetPoint("CENTER", recipeLevelResetBtn, "CENTER", 0, 0)
    recipeLevelResetIcon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Undo")
    recipeLevelResetBtn:SetScript("OnClick", ResetRecipeLevelFilterControls)

    applyRecipeLevelFilterRowLayout = function()
        local rowWidth = filterContent:GetWidth()
        if not rowWidth or rowWidth <= 0 then
            return
        end
        local resetW = UI.SETTINGS_ROW_HEIGHT
        local minLabelW = minLevelLabel:GetStringWidth()
        if not minLabelW or minLabelW <= 0 then
            minLabelW = 18
        end
        local maxLabelW = maxLevelLabel:GetStringWidth()
        if not maxLabelW or maxLabelW <= 0 then
            maxLabelW = 22
        end
        local fixed = minLabelW + UI.RECIPE_LEVEL_LABEL_GAP + UI.RECIPE_LEVEL_MIN_MAX_GAP + maxLabelW
            + UI.RECIPE_LEVEL_LABEL_GAP + resetW + UI.RECIPE_LEVEL_RESET_GAP
        local editW = math.max(UI.RECIPE_LEVEL_MIN_EDIT_WIDTH, math.floor((rowWidth - fixed) / 2 + 0.5))
        minLevelEdit:SetWidth(editW)
        maxLevelEdit:SetWidth(editW)
    end

    recipeLevelResetBtn:SetScript("OnEnter", function(self)
        if Theme.SetHoverTint then
            Theme.SetHoverTint(self, true)
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText("Reset recipe level filter (0–375)")
            GameTooltip:Show()
        end
    end)
    recipeLevelResetBtn:SetScript("OnLeave", function(self)
        if Theme.SetHoverTint then
            Theme.SetHoverTint(self, false)
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    UpdateRecipeLevelResetButtonVisibility = function()
        if not recipeLevelResetBtn or not minLevelEdit or not minLevelEdit:IsShown() then
            return
        end
        local filterActive = SS and SS.IsRecipeLevelFilterActive and SS.IsRecipeLevelFilterActive()
        recipeLevelResetBtn:SetShown(filterActive)
    end

    local craftFilterWidgets = {}
    local craftFilterDropdowns = {}

    local function AddCraftFilterWidget(widget)
        craftFilterWidgets[#craftFilterWidgets + 1] = widget
    end

    local function CloseCraftFilterDropdowns(exceptPopup)
        for i = 1, #craftFilterDropdowns do
            local popup = craftFilterDropdowns[i]
            if popup and popup ~= exceptPopup and popup.Hide then
                popup:Hide()
            end
        end
    end

    local function SetDropdownButtonSummary(btn, btnText, summary)
        btn.fullSummaryText = summary
        local maxW = (btn:GetWidth() or 0) - UI.FILTER_DROPDOWN_TEXT_INSET
        if maxW <= 0 then
            btnText:SetText(summary)
            btn.wasSummaryTruncated = false
            return
        end
        if TruncateFontString then
            btn.wasSummaryTruncated = TruncateFontString(btnText, summary, maxW, { returnBoolean = true })
        else
            btnText:SetText(summary)
            btn.wasSummaryTruncated = false
        end
    end

    local function CreateFilterSectionHeader(relativeTo, text, registerInCraftFilter)
        local header = filterContent:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        header:SetPoint("TOP", relativeTo, "BOTTOM", 0, -UI.FILTER_SECTION_GAP)
        header:SetPoint("LEFT", filterContent, "LEFT", 0, 0)
        header:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
        header:SetJustifyH("LEFT")
        header:SetText(text)
        SetRecipeLevelHeaderColor(header)
        if registerInCraftFilter ~= false then
            AddCraftFilterWidget(header)
        end
        return header
    end

    local function CreateMultiSelectFilterDropdown(config)
        local registerCraftFilterWidget = config.registerCraftFilterWidget ~= false
        local header = CreateFilterSectionHeader(
            config.relativeTo,
            config.title,
            registerCraftFilterWidget
        )

        local btn = CreateFrame("Button", nil, filterContent)
        local dropdownRowHeight = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or (Theme.CHAR_LIST_ROW_HEIGHT or 20) + 4
        btn:SetHeight(UI.SETTINGS_ROW_HEIGHT + 4)
        btn:SetPoint("TOP", header, "BOTTOM", 0, -UI.FILTER_DROPDOWN_GAP)
        btn:SetPoint("LEFT", filterContent, "LEFT", 0, 0)
        btn:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
        Theme.SkinDropdownButton(btn)
        if registerCraftFilterWidget then
            AddCraftFilterWidget(btn)
        end
        -- Native dropdown art reserves the menu border; legacy popups keep the tab's own padding.
        local popupPad = btn.altArmyDropdownArrow and Theme.GetDropdownPopupInsets() or {
            left = UI.FILTER_DROPDOWN_POPUP_PAD_LEFT, top = UI.FILTER_DROPDOWN_POPUP_PAD_TOP,
            right = UI.FILTER_DROPDOWN_POPUP_PAD_RIGHT, bottom = UI.FILTER_DROPDOWN_POPUP_PAD_BOTTOM,
        }

        local btnText = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", btn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -4, 0)
        btnText:SetJustifyH("LEFT")

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
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
        end

        local popup = CreateFrame("Frame", nil, filterContent, "BackdropTemplate")
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        local rowHeight = dropdownRowHeight
        popup:SetHeight(popupPad.top + #config.keys * rowHeight + popupPad.bottom)
        popup:SetFrameLevel(filterContent:GetFrameLevel() + 100)
        Theme.RaiseDropdownPopup(popup)
        popup:Hide()
        Theme.SkinDropdownPopup(popup)
        craftFilterDropdowns[#craftFilterDropdowns + 1] = popup

        local checks = {}
        local prevRow
        local RefreshDropdown
        for idx, key in ipairs(config.keys) do
            local rowOpts = {
                rowHeight = dropdownRowHeight,
                text = (config.getRowLabel and config.getRowLabel(key)) or config.labels[key] or key,
                fullWidthHover = true,
                rightInset = popupPad.right,
                onClick = function(checked)
                    if config.setEnabled then
                        config.setEnabled(key, checked)
                    end
                    RefreshDropdown()
                    RerunSearchIfActive()
                end,
            }
            if idx == 1 then
                rowOpts.point = "TOPLEFT"
                rowOpts.relativeTo = popup
                rowOpts.relativePoint = "TOPLEFT"
                rowOpts.x = popupPad.left
                rowOpts.y = -popupPad.top
            else
                rowOpts.relativeTo = prevRow
                rowOpts.relativePoint = "BOTTOMLEFT"
                rowOpts.point = "TOPLEFT"
                rowOpts.x = 0
                rowOpts.y = 0
            end
            local row = Theme.CreateLabeledCheckbox(popup, rowOpts)
            checks[key] = row.check
            prevRow = row
        end

        local function RefreshDropdownImpl()
            local filterMap = config.getFilter and config.getFilter() or {}
            local summary = SS and SS.FormatMultiSelectFilterSummary
                and SS.FormatMultiSelectFilterSummary(config.keys, config.labels, filterMap)
                or ""
            SetDropdownButtonSummary(btn, btnText, summary)
            for key, check in pairs(checks) do
                if check and check.SetChecked then
                    check:SetChecked(filterMap[key] ~= false)
                end
            end
        end
        RefreshDropdown = RefreshDropdownImpl

        btn:SetScript("OnClick", function()
            local show = not popup:IsShown()
            CloseCraftFilterDropdowns(show and popup or nil)
            popup:SetShown(show)
        end)

        RefreshDropdownImpl()
        return btn, { popup = popup, refresh = RefreshDropdownImpl, header = header }
    end

    local professionDropdownBtn
    local professionDropdown
    professionDropdownBtn, professionDropdown = CreateMultiSelectFilterDropdown({
        relativeTo = professionSectionAnchor,
        title = "Professions",
        keys = SS and SS.GetProfessionDropdownOrder and SS.GetProfessionDropdownOrder() or {},
        labels = SS and SS.PROFESSION_LABELS or {},
        registerCraftFilterWidget = false,
        getFilter = function()
            return SS and SS.GetProfessionFilter and SS.GetProfessionFilter() or {}
        end,
        setEnabled = function(key, checked)
            if SS and SS.SetProfessionEnabled then
                SS.SetProfessionEnabled(key, checked)
            end
        end,
    })

    recipeLevelHeader:SetPoint("TOPLEFT", professionDropdownBtn, "BOTTOMLEFT", 0, -UI.FILTER_SECTION_GAP)

    local DIFFICULTY_LABELS = {
        orange = "Orange",
        yellow = "Yellow",
        green = "Green",
        gray = "Gray",
    }
    local DIFFICULTY_DROPDOWN_ORDER = { "gray", "green", "yellow", "orange" }

    local function ColoredDifficultyLabel(band)
        local plain = DIFFICULTY_LABELS[band] or band
        local hex = RI and RI.GetDifficultyColorHex and RI.GetDifficultyColorHex(band)
        if not hex then
            return plain
        end
        return string.format("|c%s%s|r", hex, plain)
    end

    local SOURCE_LABELS = {
        trainer = "Trainer",
        vendor = "Vendor",
        quest = "Quest",
        drop = "Drop",
        reputation = "Reputation",
        starter = "Starter",
    }
    local SOURCE_DROPDOWN_ORDER = { "drop", "quest", "reputation", "starter", "trainer", "vendor" }

    local difficultyDropdownBtn
    local difficultyDropdown
    difficultyDropdownBtn, difficultyDropdown = CreateMultiSelectFilterDropdown({
        relativeTo = minLevelLabel,
        title = "Difficulty",
        keys = DIFFICULTY_DROPDOWN_ORDER,
        labels = DIFFICULTY_LABELS,
        getRowLabel = ColoredDifficultyLabel,
        getFilter = function()
            return SS and SS.GetDifficultyFilter and SS.GetDifficultyFilter() or {}
        end,
        setEnabled = function(key, checked)
            if SS and SS.SetDifficultyBandEnabled then
                SS.SetDifficultyBandEnabled(key, checked)
            end
        end,
    })
    local _, sourceDropdown = CreateMultiSelectFilterDropdown({
        relativeTo = difficultyDropdownBtn,
        title = "Source",
        keys = SOURCE_DROPDOWN_ORDER,
        labels = SOURCE_LABELS,
        getFilter = function()
            return SS and SS.GetSourceFilter and SS.GetSourceFilter() or {}
        end,
        setEnabled = function(key, checked)
            if SS and SS.SetSourceTypeEnabled then
                SS.SetSourceTypeEnabled(key, checked)
            end
        end,
    })

    SyncCraftFilterDropdowns = function()
        if professionDropdown and professionDropdown.refresh then
            professionDropdown.refresh()
        end
        if difficultyDropdown and difficultyDropdown.refresh then
            difficultyDropdown.refresh()
        end
        if sourceDropdown and sourceDropdown.refresh then
            sourceDropdown.refresh()
        end
    end

    settingsPanel:HookScript("OnHide", function()
        CloseCraftFilterDropdowns()
    end)

    local function SetCraftFilterWidgetsShown(shown)
        for i = 1, #craftFilterWidgets do
            local widget = craftFilterWidgets[i]
            if widget and widget.SetShown then
                widget:SetShown(shown)
            end
        end
    end

    local function RefreshSearchSettingsControls()
        if applyRecipeLevelFilterRowLayout then
            applyRecipeLevelFilterRowLayout()
        end
        if not SS or not SS.GetRecipeLevelFilter then
            return
        end
        local f = SS.GetRecipeLevelFilter()
        -- Recipe data ships with the addon; without it (unsupported client) the recipe filters hide.
        local recipeDataReady = RI and RI.IsAvailable and RI.IsAvailable()
        SyncCraftFilterDropdowns()
        if professionDropdown and professionDropdown.header then
            professionDropdown.header:Show()
            SetRecipeLevelHeaderColor(professionDropdown.header)
        end
        if professionDropdownBtn then
            professionDropdownBtn:Show()
        end
        if recipeDataReady then
            recipeLevelHeader:Show()
            minLevelLabel:Show()
            minLevelEdit:Show()
            maxLevelLabel:Show()
            maxLevelEdit:Show()
            SetCraftFilterWidgetsShown(true)
            suppressRecipeFilterTextChanged = true
            minLevelEdit:SetText(tostring(f.min or 0))
            maxLevelEdit:SetText(tostring(f.max or 375))
            suppressRecipeFilterTextChanged = false
            SetRecipeLevelHeaderColor(recipeLevelHeader)
            SetRecipeLevelHeaderColor(difficultyDropdown and difficultyDropdown.header)
            SetRecipeLevelHeaderColor(sourceDropdown and sourceDropdown.header)
            if UpdateRecipeLevelResetButtonVisibility then
                UpdateRecipeLevelResetButtonVisibility()
            end
            if Theme.SetLabelColor then
                Theme.SetLabelColor(minLevelLabel)
                Theme.SetLabelColor(maxLevelLabel)
            end
        else
            recipeLevelHeader:Hide()
            minLevelLabel:Hide()
            minLevelEdit:Hide()
            maxLevelLabel:Hide()
            maxLevelEdit:Hide()
            recipeLevelResetBtn:Hide()
            SetCraftFilterWidgetsShown(false)
            CloseCraftFilterDropdowns()
        end
    end

    RefreshSearchSettingsControls()

    return {
        panel = settingsPanel,
        ApplyLayout = ApplySettingsPanelLayout,
        RefreshControls = RefreshSearchSettingsControls,
        IsShown = function()
            return settingsPanel and settingsPanel:IsShown()
        end,
    }
end
