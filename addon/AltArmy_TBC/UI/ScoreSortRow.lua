-- AltArmy TBC — Reusable "score sort row" used by the Gear and Reputation grids.
-- Provides: provider resolution, the column-sort comparator, per-column score display,
-- and a factory that builds the corner controls (provider selector + sort-direction button).

AltArmy = AltArmy or {}
AltArmy.ScoreSortRow = AltArmy.ScoreSortRow or {}

local SSR = AltArmy.ScoreSortRow
local Theme = AltArmy.Theme

local DEFAULT_PROVIDER = "level"
SSR.DEFAULT_PROVIDER = DEFAULT_PROVIDER

-- ---------------------------------------------------------------------------
-- Logic (provider resolution + comparator + per-column value)
-- ---------------------------------------------------------------------------

function SSR.GetAvailableProviders()
    local GS = AltArmy.GearScore
    if GS and GS.RefreshProviders then
        GS.RefreshProviders("score-sort-row")
    end
    if GS and GS.GetAvailableProviders then
        return GS.GetAvailableProviders()
    end
    return {}
end

function SSR.ValidateProvider(id)
    local providers = SSR.GetAvailableProviders()
    for _, p in ipairs(providers) do
        if p.id == id then return id end
    end
    if id == "gs_lite" then
        for _, p in ipairs(providers) do
            if p.id:sub(1, 3) == "gs:" then
                return p.id
            end
        end
    end
    return DEFAULT_PROVIDER
end

function SSR.GetProviderLabel(id)
    local GS = AltArmy.GearScore
    if GS and GS.GetProviderShortLabel then
        return GS.GetProviderShortLabel(id)
    end
    local provider = GS and GS.GetProvider and GS.GetProvider(id)
    if provider then return provider.shortLabel or provider.label end
    return "Level"
end

local function GetSortKey(id)
    local GS = AltArmy.GearScore
    if GS and GS.GetProvider then
        local provider = GS.GetProvider(id)
        if provider then
            return provider.sortLabel or provider.label
        end
    end
    return "Level"
end

function SSR.IsScoreMissing(entry, id)
    local GS = AltArmy.GearScore
    local DS = AltArmy.DataStore
    if not GS or not GS.IsScoreMissing then return false end
    if not DS or not DS.GetCharacter then return false end
    local char = DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    return GS.IsScoreMissing(char, id)
end

--- Column-sort comparator: missing scores last, then by selected metric, then name.
function SSR.Compare(entryA, entryB, providerId, descending)
    local missingA = SSR.IsScoreMissing(entryA, providerId)
    local missingB = SSR.IsScoreMissing(entryB, providerId)
    if missingA ~= missingB then
        return not missingA
    end

    local sortKey = GetSortKey(providerId)
    local GetSortValue = AltArmy.CharacterSort.GetSortValue
    local va = GetSortValue(entryA, sortKey)
    local vb = GetSortValue(entryB, sortKey)
    if va ~= vb then
        if descending then return va > vb else return va < vb end
    end

    return (entryA.name or "") < (entryB.name or "")
end

--- Pre-compute provider-specific fields on a display entry (e.g. cached scores).
function SSR.DecorateEntry(entry)
    local GS = AltArmy.GearScore
    local DS = AltArmy.DataStore
    if not entry or not GS or not GS.DecorateEntry then return end
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    if charData then
        GS.DecorateEntry(entry, charData)
    end
end

--- Populate a column's score FontString (+ optional hover frame for missing-data tooltip).
--- @param scoreText FontString
--- @param scoreHover Frame|nil mouse frame shown only when the score is missing
--- @param entry table display entry { name, realm, classFile }
--- @param providerId string
--- @param gray boolean dim the value (e.g. for offline / stale columns)
--- @param opts table|nil optional; playedUnitStyle = "full" for word units on Time Played
function SSR.ApplyColumnScore(scoreText, scoreHover, entry, providerId, gray, opts)
    if not scoreText then return end
    local GS = AltArmy.GearScore
    local DS = AltArmy.DataStore
    local charData = DS and DS.GetCharacter and DS:GetCharacterFor(entry.name, entry.realm, entry.linkId)
    local scoreMissing = GS and GS.IsScoreMissing and GS.IsScoreMissing(charData, providerId)

    if scoreMissing then
        scoreText:SetText("!")
        scoreText:SetTextColor(1, 0.82, 0, 1)
        if scoreHover then
            scoreHover.scoreMissingEntry = {
                name = entry.name or "",
                realm = entry.realm or "",
                classFile = entry.classFile,
            }
            scoreHover:Show()
            scoreHover:EnableMouse(true)
        end
    else
        local scoreValue = GS and GS.GetDisplayScore and GS.GetDisplayScore(entry, providerId) or 0
        local scoreDisplay = GS and GS.FormatDisplayScore and GS.FormatDisplayScore(providerId, scoreValue, opts) or "0"
        scoreText:SetText(scoreDisplay)
        if scoreHover then
            scoreHover.scoreMissingEntry = nil
            scoreHover:Hide()
            scoreHover:EnableMouse(false)
        end
        if gray then
            scoreText:SetTextColor(0.5, 0.5, 0.5, 1)
        else
            local sr, sg, sb
            if GS and GS.GetDisplayScoreColor then
                sr, sg, sb = GS.GetDisplayScoreColor(providerId, scoreValue)
            end
            if sr and sg and sb then
                scoreText:SetTextColor(sr, sg, sb, 1)
            else
                scoreText:SetTextColor(0.9, 0.9, 0.9, 1)
            end
        end
    end
    scoreText:Show()
end

-- ---------------------------------------------------------------------------
-- UI factory: corner controls (provider selector + sort-direction button)
-- ---------------------------------------------------------------------------

local SETTINGS_ROW_HEIGHT = 22
local SORT_BTN_GAP = 2
local DEFAULT_DROPDOWN_WIDTH = 150

--- Build the provider selector + direction toggle anchored to the bottom of `parent`.
--- opts:
---   getProviderId() -> string, setProviderId(id), getDescending() -> bool, setDescending(bool)
---   onChange()             called after any change (caller refreshes its grid)
---   btnSize                square size for the direction button (and content height)
---   bottomInset            bottom inset for the row within parent
---   dropdownParent         frame to parent the dropdown to (defaults to parent)
---   dropdownWidth          width of the provider dropdown (defaults to 150)
---   isDirectionShown()     optional -> bool; when false the direction button is hidden and the
---                          provider selector expands to fill its space (re-evaluated on :Update())
---   onProviderActivate()   optional; called when the provider button is clicked (e.g. to cancel an
---                          overriding sort and return to score sorting). Return true to consume the
---                          click so the dropdown menu does not also open.
--- Returns an api table with :Update() to re-sync the controls to current settings.
function SSR.CreateCornerControls(parent, opts)
    opts = opts or {}
    local btnSize = opts.btnSize or 14
    local bottomInset = opts.bottomInset or 0
    local dropdownParent = opts.dropdownParent or parent
    local dropdownWidth = opts.dropdownWidth or DEFAULT_DROPDOWN_WIDTH

    local function getProviderId()
        return SSR.ValidateProvider(opts.getProviderId and opts.getProviderId() or DEFAULT_PROVIDER)
    end

    local sortBtn = CreateFrame("Button", nil, parent)
    sortBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomInset)
    sortBtn:SetSize(btnSize, btnSize)
    if Theme and Theme.SkinButton then Theme.SkinButton(sortBtn) end

    local staticLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    staticLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, bottomInset)
    staticLabel:SetPoint("BOTTOMRIGHT", sortBtn, "BOTTOMLEFT", -SORT_BTN_GAP, 0)
    staticLabel:SetHeight(btnSize)
    staticLabel:SetJustifyH("LEFT")
    staticLabel:SetJustifyV("MIDDLE")
    staticLabel:SetText("Level")

    local providerBtn = CreateFrame("Button", nil, parent)
    providerBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, bottomInset)
    providerBtn:SetPoint("BOTTOMRIGHT", sortBtn, "BOTTOMLEFT", -SORT_BTN_GAP, 0)
    providerBtn:SetHeight(btnSize)
    providerBtn:Hide()
    if Theme and Theme.SkinDropdownButton then Theme.SkinDropdownButton(providerBtn) end
    local providerBtnText = providerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    providerBtnText:SetPoint("LEFT", providerBtn, "LEFT", 6, 0)
    providerBtnText:SetPoint("RIGHT", providerBtn, "RIGHT",
        providerBtn.altArmyDropdownArrow and -Theme.DROPDOWN_ARROW_GUTTER or -2, 0)
    providerBtnText:SetJustifyH("LEFT")

    local dropdown = CreateFrame("Frame", nil, dropdownParent, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", providerBtn, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(dropdownWidth)
    dropdown:SetFrameLevel(dropdownParent:GetFrameLevel() + 100)
    dropdown:Hide()
    if Theme and Theme.SkinDropdownPopup then Theme.SkinDropdownPopup(dropdown) end
    local dropdownButtons = {}

    local api = {}

    local function updateDropdownSelection()
        local selectedId = getProviderId()
        for i = 1, #dropdownButtons do
            local b = dropdownButtons[i]
            if b.SetDropdownSelected then
                b:SetDropdownSelected(b.providerId == selectedId)
            end
        end
    end

    local function updateProviderControl()
        local providers = SSR.GetAvailableProviders()
        local label = SSR.GetProviderLabel(getProviderId())
        if #providers <= 1 then
            staticLabel:SetText(label)
            staticLabel:Show()
            providerBtn:Hide()
            dropdown:Hide()
            return
        end
        staticLabel:Hide()
        providerBtn:Show()
        providerBtnText:SetText(label)
    end

    local function rebuildDropdown()
        for i = 1, #dropdownButtons do
            dropdownButtons[i]:Hide()
            dropdownButtons[i]:SetParent(nil)
        end
        wipe(dropdownButtons)
        local providers = SSR.GetAvailableProviders()
        if #providers <= 1 then
            dropdown:Hide()
            return
        end
        local insets = Theme.GetDropdownPopupInsets and Theme.GetDropdownPopupInsets()
            or { left = 2, top = 2, right = 2, bottom = 2 }
        dropdown:SetHeight(#providers * SETTINGS_ROW_HEIGHT + insets.top + insets.bottom)
        dropdown:SetWidth(dropdownWidth)
        for idx, provider in ipairs(providers) do
            local b = Theme.CreateDropdownMenuItem(dropdown, {
                index = idx,
                rowHeight = SETTINGS_ROW_HEIGHT,
                padTop = insets.top,
                padSide = insets.left,
                padRight = insets.right,
                text = provider.label,
                selected = provider.id == getProviderId(),
                onClick = function(self)
                    if opts.setProviderId then opts.setProviderId(self.providerId) end
                    updateDropdownSelection()
                    dropdown:Hide()
                    updateProviderControl()
                    if opts.onChange then opts.onChange() end
                end,
            })
            b.providerId = provider.id
            dropdownButtons[idx] = b
        end
    end

    local function updateSortButton()
        local descending = opts.getDescending and opts.getDescending() ~= false
        Theme.SetSortArrowButton(sortBtn, descending and "right" or "left")
    end

    -- The direction button can be hidden by the caller (e.g. while another sort is overriding it);
    -- when hidden, the provider selector expands to fill the freed space.
    local function applyDirectionLayout()
        local shown = (opts.isDirectionShown == nil) or (opts.isDirectionShown() ~= false)
        sortBtn:SetShown(shown)
        if shown then
            staticLabel:SetPoint("BOTTOMRIGHT", sortBtn, "BOTTOMLEFT", -SORT_BTN_GAP, 0)
            providerBtn:SetPoint("BOTTOMRIGHT", sortBtn, "BOTTOMLEFT", -SORT_BTN_GAP, 0)
        else
            staticLabel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, bottomInset)
            providerBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomInset)
        end
    end

    sortBtn:SetScript("OnClick", function()
        local descending = opts.getDescending and opts.getDescending() ~= false
        if opts.setDescending then opts.setDescending(not descending) end
        updateSortButton()
        if opts.onChange then opts.onChange() end
    end)

    providerBtn:SetScript("OnClick", function()
        -- Interacting with the score selector re-activates score sorting in the caller.
        -- If it consumed the click (returns true), don't also open the menu.
        if opts.onProviderActivate and opts.onProviderActivate() then return end
        local show = not dropdown:IsShown()
        if show then updateDropdownSelection() end
        dropdown:SetShown(show)
    end)

    function api:Update()
        rebuildDropdown()
        updateProviderControl()
        updateSortButton()
        applyDirectionLayout()
    end

    api.sortButton = sortBtn
    api.providerButton = providerBtn
    api.dropdown = dropdown
    api:Update()
    return api
end
