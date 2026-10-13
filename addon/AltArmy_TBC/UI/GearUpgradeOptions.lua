-- AltArmy TBC — Gear upgrade options (Options > AddOns > AltArmy > Gear page).
-- Loaded after UI/Options.lua.

if not AltArmy then return end

local Theme = AltArmy.Theme
local LEFT_INSET = 0
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

local function hookHostShow(panel)
    local host = panel and panel.tabGearUpgradesHost
    if not host or host.gearUpgradeShowHooked then return end
    host.gearUpgradeShowHooked = true
    host:HookScript("OnShow", function()
        if AltArmy.BuildGearUpgradeOptionsUI then
            AltArmy.BuildGearUpgradeOptionsUI(panel)
        end
        if panel.UpdateGearUpgradeScrollRange then
            panel.UpdateGearUpgradeScrollRange()
        end
        if panel.RefreshGearUpgradeOptionsFromVars then
            panel.RefreshGearUpgradeOptionsFromVars()
        end
    end)
end

local function refreshQuestRewardIndicators()
    local QRI = AltArmy.QuestRewardIndicators
    if QRI and QRI.Refresh then
        QRI.Refresh()
    end
end

function AltArmy.BuildGearUpgradeOptionsUI(panel)
    panel = panel or AltArmy.OptionsPanel
    if not panel or not panel.tabGearUpgradesHost then return false end
    local host = panel.tabGearUpgradesHost
    if host.gearUpgradeUiBuilt then return true end

    local GU = AltArmy.GearUpgrade
    if not GU then
        local msg = host:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        msg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        msg:SetWidth(520)
        msg:SetJustifyH("LEFT")
        msg:SetText("Gear upgrade options are unavailable.")
        host.gearUpgradeUiBuilt = true
        return false
    end

    host.gearUpgradeUiBuilt = true

    local viewport = Theme.CreateVerticalScrollViewport({
        name = "AltArmyTBC_GearUpgradeOptionsScroll",
        parent = host,
        gutterEdge = host:GetParent(), -- the Gear page
        anchorTop = { "TOPLEFT", host, "TOPLEFT", LEFT_INSET, -4 },
        anchorBottom = { "BOTTOMRIGHT", host:GetParent(), "BOTTOMRIGHT", -SCROLL_GUTTER, 4 },
        wheelStep = 40,
        valueStep = 20,
        wheelOnChild = false,
        wheelSource = "slider",
        minScrollToShow = 1,
    })
    local scrollChild = viewport.child

    local currentCharSection = Theme.CreateOptionsSectionLabel(scrollChild, {
        text = "Current Character",
        justifyH = "LEFT",
        y = 0,
    })

    local currentCharRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = currentCharSection,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Notify me when a quest reward or soulbound loot is an upgrade",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().notifyCurrentCharacter = checked
        end,
    })
    local currentCharChk = currentCharRow.check

    local showUpgradeRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = currentCharRow,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Show best upgrade indicator in quest rewards",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().showQuestRewardUpgradeIndicator = checked
            refreshQuestRewardIndicators()
        end,
    })
    local showUpgradeChk = showUpgradeRow.check

    local showVendorRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = showUpgradeRow,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Show best vendor price indicator in quest rewards",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().showQuestRewardVendorIndicator = checked
            refreshQuestRewardIndicators()
        end,
    })
    local showVendorChk = showVendorRow.check

    local otherCharSection = Theme.CreateOptionsSectionLabel(scrollChild, {
        relativeTo = showVendorRow,
        text = "Other characters",
        justifyH = "LEFT",
    })

    local otherCharRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = otherCharSection,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Notify me when non-soulbound loot is an upgrade for any of my characters",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().notifyOtherCharacters = checked
        end,
    })
    local otherCharChk = otherCharRow.check

    local comparisonSection = Theme.CreateOptionsSectionLabel(scrollChild, {
        relativeTo = otherCharRow,
        text = "Comparison settings",
        justifyH = "LEFT",
    })

    local levelsLabel = scrollChild:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    levelsLabel:SetPoint("TOPLEFT", comparisonSection, "BOTTOMLEFT", 0, -10)
    levelsLabel:SetText("Level look-ahead")
    Theme.AttachLabelHelpIcon(levelsLabel, {
        title = "Level look-ahead",
        lines = {
            "When checking whether an item is an upgrade, include items that cannot "
                .. "be equipped for this many levels.",
        },
    })

    -- Native input border's left cap overhangs the box; inset so the scroll child doesn't clip it.
    local inputInset = -Theme.INPUT_BORDER.leftOffset
    local levelsEdit = CreateFrame("EditBox", nil, scrollChild)
    levelsEdit:SetPoint("TOPLEFT", levelsLabel, "BOTTOMLEFT", inputInset, -4)
    levelsEdit:SetSize(44, 20)
    levelsEdit:SetFontObject(Theme.FONTS.body)
    levelsEdit:SetAutoFocus(false)
    levelsEdit:SetNumeric(true)
    levelsEdit:SetJustifyH("CENTER")
    Theme.ApplyInputTextures(levelsEdit)

    local function saveLevelsAhead()
        local n = tonumber(levelsEdit:GetText()) or 0
        GU.EnsureGearUpgradeOptions().levelsAhead = math.max(0, math.floor(n))
    end

    levelsEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        saveLevelsAhead()
    end)
    levelsEdit:SetScript("OnEditFocusLost", saveLevelsAhead)

    local thresholdLabel = scrollChild:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
    thresholdLabel:SetPoint("TOPLEFT", levelsEdit, "BOTTOMLEFT", -inputInset, -14)
    thresholdLabel:SetText("Upgrade threshold (% vs equipped)")
    Theme.AttachLabelHelpIcon(thresholdLabel, {
        title = "Upgrade threshold",
        lines = {
            "Alt Army will draw your attention to an item upgrade only if it is this "
                .. "percent of an upgrade or more. Smaller upgrades can still be viewed, "
                .. "but we won't point them out.",
        },
    })

    local thresholdEdit = CreateFrame("EditBox", nil, scrollChild)
    thresholdEdit:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", inputInset, -4)
    thresholdEdit:SetSize(44, 20)
    thresholdEdit:SetFontObject(Theme.FONTS.body)
    thresholdEdit:SetAutoFocus(false)
    thresholdEdit:SetNumeric(true)
    thresholdEdit:SetJustifyH("CENTER")
    Theme.ApplyInputTextures(thresholdEdit)

    local function saveUpgradeThreshold()
        local n = tonumber(thresholdEdit:GetText()) or 0
        GU.EnsureGearUpgradeOptions().upgradeThresholdPercent =
            GU.ResolveUpgradeThresholdPercent(n)
        thresholdEdit:SetText(tostring(GU.GetOptions().upgradeThresholdPercent))
    end

    thresholdEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        saveUpgradeThreshold()
    end)
    thresholdEdit:SetScript("OnEditFocusLost", saveUpgradeThreshold)

    scrollChild:SetHeight(320)

    local function UpdateGearUpgradeScrollRange()
        viewport:UpdateRange()
    end

    local function RefreshGearUpgradeOptionsFromVars()
        GU.EnsureGearUpgradeOptions()
        local opts = GU.GetOptions()
        currentCharChk:SetChecked(opts.notifyCurrentCharacter ~= false)
        showUpgradeChk:SetChecked(opts.showQuestRewardUpgradeIndicator ~= false)
        showVendorChk:SetChecked(opts.showQuestRewardVendorIndicator ~= false)
        otherCharChk:SetChecked(opts.notifyOtherCharacters ~= false)
        levelsEdit:SetText(tostring(opts.levelsAhead))
        thresholdEdit:SetText(tostring(opts.upgradeThresholdPercent))
        UpdateGearUpgradeScrollRange()
    end

    panel.RefreshGearUpgradeOptionsFromVars = RefreshGearUpgradeOptionsFromVars
    panel.UpdateGearUpgradeScrollRange = UpdateGearUpgradeScrollRange

    RefreshGearUpgradeOptionsFromVars()
    hookHostShow(panel)
    return true
end

if AltArmy.OptionsPanel then
    AltArmy.BuildGearUpgradeOptionsUI(AltArmy.OptionsPanel)
    hookHostShow(AltArmy.OptionsPanel)
end
