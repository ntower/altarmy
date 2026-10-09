-- AltArmy TBC — Guild data sharing: first-run welcome / onboarding dialog.
-- Prompts once per realm (when the guildShare feature flag is on and the player is in a guild)
-- to choose a main, set a display name, and opt in to sharing. Writes to GuildShareSettings.

if not AltArmy then return end

local Theme = AltArmy.Theme
if not Theme then return end

AltArmy.GuildShareOnboarding = AltArmy.GuildShareOnboarding or {}
local GSO = AltArmy.GuildShareOnboarding

local ADDON_NAME = "Alt Army"
local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28
local CONTROL_GAP = 14
local SECTION_GAP = 12
local LIST_ITEM_GAP = 4
local BULLET_TEXT_COLOR = { 0.54, 0.71, 0.97, 1 } -- soft blue accent (matches guild source tags)
local MUTED_TEXT_COLOR = { 0.75, 0.75, 0.75, 1 }

GSO.SHARED_HEADING = "What is shared:"
GSO.SHARED_BULLET = "• Character names, levels, classes, professions, and recipes"
GSO.NOT_SHARED_HEADING = "What is not shared:"
GSO.NOT_SHARED_LIST = "Everything else: gear, inventory, gold, playtime, cooldowns, favorite ice cream, etc"
GSO.NOT_SHARED_BULLET = "• Everything else"
GSO.NOT_SHARED_EXAMPLE =
    "Eg, no gear, inventory, gold, playtime, cooldowns, or favorite ice cream"

--- Tooltip body for the Options share checkbox.
function GSO.GetSharingDisclosureTooltip()
    return {
        lines = {
            { text = GSO.SHARED_HEADING, heading = true },
            { text = "Character names, levels, classes, professions, and recipes" },
            { text = GSO.NOT_SHARED_HEADING, heading = true },
            { text = GSO.NOT_SHARED_LIST },
            { text = "Who it is shared with:", heading = true },
            {
                text = "Characters in a guild are shared with that guild."
                    .. " Characters with no guild are not shared, unless you set up an exception.",
            },
        },
    }
end

local CC = AltArmy.ClassColor

local function currentRealm()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm then return GSS._CurrentRealm() end
    return (GetRealmName and GetRealmName()) or ""
end

local function currentPlayer()
    local DS = AltArmy.DataStore
    if DS and DS.GetCurrentPlayerName then return DS:GetCurrentPlayerName() end
    return (UnitName and UnitName("player")) or ""
end

local function charLevel(char)
    local DS = AltArmy.DataStore
    if DS and DS.GetCharacterLevel then
        return DS:GetCharacterLevel(char) or 0
    end
    return tonumber(char and char.level) or 0
end

local function charItemLevel(char)
    local DS = AltArmy.DataStore
    if DS and DS.GetAverageItemLevel then
        return DS:GetAverageItemLevel(char) or 0
    end
    return 0
end

--- Gear score from the first available gear-score addon provider, or 0 when none is installed.
local function charGearScore(char)
    local GS = AltArmy.GearScore
    if not GS or not GS.GetAvailableProviders or not GS.ScoreCharacter then
        return 0
    end
    local providers = GS.GetAvailableProviders() or {}
    for i = 1, #providers do
        local provider = providers[i]
        if provider.id and provider.id:sub(1, 3) == "gs:"
            and provider.isAvailable and provider.isAvailable() then
            return GS.ScoreCharacter(provider.id, char) or 0
        end
    end
    return 0
end

local function defaultMainCompareOpts()
    return {
        getLevel = charLevel,
        getGearScore = charGearScore,
        getItemLevel = charItemLevel,
    }
end

--- Returns positive when `a` outranks `b` as a default main pick.
function GSO.CompareMainCandidates(a, b, opts)
    opts = opts or defaultMainCompareOpts()
    local getLevel = opts.getLevel or charLevel
    local getGearScore = opts.getGearScore or charGearScore
    local getItemLevel = opts.getItemLevel or charItemLevel

    local levelA = getLevel(a.char)
    local levelB = getLevel(b.char)
    if levelA ~= levelB then
        return levelA > levelB and 1 or -1
    end

    local gsA = getGearScore(a.char)
    local gsB = getGearScore(b.char)
    if gsA ~= gsB then
        return gsA > gsB and 1 or -1
    end

    local ilvlA = getItemLevel(a.char)
    local ilvlB = getItemLevel(b.char)
    if ilvlA ~= ilvlB then
        return ilvlA > ilvlB and 1 or -1
    end

    local nameA = a.name or ""
    local nameB = b.name or ""
    if nameA == nameB then return 0 end
    return nameA < nameB and 1 or -1
end

--- Pick the default main from realm characters: highest level, then gear score, then iLevel,
--- then alphabetical name.
function GSO.PickDefaultMain(candidates, opts)
    local best
    for i = 1, #(candidates or {}) do
        local candidate = candidates[i]
        if not best or GSO.CompareMainCandidates(candidate, best, opts) > 0 then
            best = candidate
        end
    end
    return best and best.name or nil
end

--- WoW FontString label: class-colored name + gray "(level N)" suffix (level floored).
function GSO.FormatCharacterDropdownLabel(name, classFile, level, formatName)
    local levelText = math.floor(tonumber(level) or 0)
    local namePart = name or "?"
    if formatName then
        namePart = formatName(name, classFile)
    elseif CC and CC.formatName then
        namePart = CC.formatName(name, classFile)
    end
    return namePart .. " |cff808080(level " .. levelText .. ")|r"
end

--- Build dropdown entries for every character on the realm, sorted by the same ranking
--- used for the default main pick (level, gear score, item level, then name).
--- `charsByName` is DataStore:GetCharacters(realm) (keyed by GUID); entry ids are character names.
function GSO.BuildRealmCharEntries(charsByName, formatName, opts)
    opts = opts or {}
    local getLevel = opts.getLevel or charLevel
    local candidates = {}
    for key, char in pairs(charsByName or {}) do
        if char then
            candidates[#candidates + 1] = { name = (type(char) == "table" and char.name) or key, char = char }
        end
    end
    table.sort(candidates, function(a, b)
        return GSO.CompareMainCandidates(a, b, opts) > 0
    end)
    local entries = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local label = GSO.FormatCharacterDropdownLabel(
            candidate.name,
            candidate.char.classFile,
            getLevel(candidate.char),
            formatName
        )
        entries[#entries + 1] = { id = candidate.name, label = label }
    end
    return entries
end

local function realmCandidates()
    local DS = AltArmy.DataStore
    local realm = currentRealm()
    local out = {}
    if DS and DS.GetCharacters then
        for key, char in pairs(DS:GetCharacters(realm) or {}) do
            if char then
                out[#out + 1] = { name = (type(char) == "table" and char.name) or key, char = char }
            end
        end
    end
    if #out == 0 then
        local player = currentPlayer()
        if player ~= "" then
            out[#out + 1] = { name = player, char = { name = player } }
        end
    end
    return out
end

--- All characters on the current realm as dropdown entries.
local function realmCharEntries()
    local DS = AltArmy.DataStore
    local realm = currentRealm()
    local chars = (DS and DS.GetCharacters and DS:GetCharacters(realm)) or {}
    if next(chars) == nil then
        local player = currentPlayer()
        if player ~= "" then
            local classFile = UnitClass and select(2, UnitClass("player")) or nil
            local level = (UnitLevel and UnitLevel("player")) or 0
            local function formatName(name, cf)
                if CC and CC.formatName then return CC.formatName(name, cf) end
                return name
            end
            return {
                {
                    id = player,
                    label = GSO.FormatCharacterDropdownLabel(player, classFile, level, formatName),
                },
            }
        end
        return {}
    end
    local function formatName(name, classFile)
        if CC and CC.formatName then return CC.formatName(name, classFile) end
        return name
    end
    return GSO.BuildRealmCharEntries(chars, formatName, defaultMainCompareOpts())
end

local function resolveDefaultMain(savedMain)
    if savedMain then return savedMain end
    return GSO.PickDefaultMain(realmCandidates(), defaultMainCompareOpts())
        or currentPlayer()
end

-- *** Dialog (built lazily on first show) ***

local dialog
local mainDropdown
local displayNameEdit
local onDoneCallback
local selectedMain
local footnote

local function buildDialog()
    if dialog then return end

    dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_GuildShareOnboarding")
    dialog:SetSize(460, 350)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    dialog:Hide()
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    if UISpecialFrames then
        tinsert(UISpecialFrames, "AltArmyTBC_GuildShareOnboarding") -- never assign the global: that taints it
    end

    local headerPanel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    headerPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    headerPanel:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    headerPanel:SetHeight(HEADER_PANEL_HEIGHT)
    headerPanel:EnableMouse(true)
    headerPanel:RegisterForDrag("LeftButton")
    headerPanel:SetScript("OnDragStart", function() dialog:StartMoving() end)
    headerPanel:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    Theme.ApplyBackdrop(headerPanel, "section")

    local headerTitle = headerPanel:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
    headerTitle:SetPoint("LEFT", headerPanel, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
    headerTitle:SetText(ADDON_NAME)
    Theme.SetTitleColor(headerTitle)

    local closeBtn = CreateFrame("Button", nil, headerPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", headerPanel, "RIGHT", 2, 0)

    local bodyPanel = Theme.CreateTabContentPanel(dialog)
    bodyPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET,
        -(CONTENT_INSET + HEADER_PANEL_HEIGHT + HEADER_SECTION_GAP))
    bodyPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
    local bodyInner = Theme.CreatePanelInnerContent(bodyPanel)

    local headline = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.headline)
    headline:SetPoint("TOPLEFT", bodyInner, "TOPLEFT", 0, 0)
    headline:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    headline:SetJustifyH("LEFT")
    headline:SetWordWrap(true)
    headline:SetText("Share with your guild")
    headline:SetTextColor(1, 1, 1, 1)

    local introText = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    introText:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -12)
    introText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    introText:SetJustifyH("LEFT")
    introText:SetWordWrap(true)
    introText:SetTextColor(MUTED_TEXT_COLOR[1], MUTED_TEXT_COLOR[2], MUTED_TEXT_COLOR[3], MUTED_TEXT_COLOR[4])
    introText:SetText(
        "With your permission, Alt Army can share data with other members of your guild.")

    local sharedHeading = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.heading)
    sharedHeading:SetPoint("TOPLEFT", introText, "BOTTOMLEFT", 0, -SECTION_GAP)
    sharedHeading:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    sharedHeading:SetJustifyH("LEFT")
    sharedHeading:SetWordWrap(true)
    sharedHeading:SetText(GSO.SHARED_HEADING)

    local sharedBullet = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    sharedBullet:SetPoint("TOPLEFT", sharedHeading, "BOTTOMLEFT", 0, -LIST_ITEM_GAP)
    sharedBullet:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    sharedBullet:SetJustifyH("LEFT")
    sharedBullet:SetWordWrap(true)
    sharedBullet:SetTextColor(
        BULLET_TEXT_COLOR[1], BULLET_TEXT_COLOR[2], BULLET_TEXT_COLOR[3], BULLET_TEXT_COLOR[4])
    sharedBullet:SetText(GSO.SHARED_BULLET)

    local notSharedHeading = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.heading)
    notSharedHeading:SetPoint("TOPLEFT", sharedBullet, "BOTTOMLEFT", 0, -SECTION_GAP)
    notSharedHeading:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    notSharedHeading:SetJustifyH("LEFT")
    notSharedHeading:SetWordWrap(true)
    notSharedHeading:SetText(GSO.NOT_SHARED_HEADING)

    local notSharedBullet = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    notSharedBullet:SetPoint("TOPLEFT", notSharedHeading, "BOTTOMLEFT", 0, -LIST_ITEM_GAP)
    notSharedBullet:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    notSharedBullet:SetJustifyH("LEFT")
    notSharedBullet:SetWordWrap(true)
    notSharedBullet:SetTextColor(
        BULLET_TEXT_COLOR[1], BULLET_TEXT_COLOR[2], BULLET_TEXT_COLOR[3], BULLET_TEXT_COLOR[4])
    notSharedBullet:SetText(GSO.NOT_SHARED_BULLET)

    local notSharedEg = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    notSharedEg:SetPoint("TOPLEFT", notSharedBullet, "BOTTOMLEFT", 0, -LIST_ITEM_GAP)
    notSharedEg:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
    notSharedEg:SetJustifyH("LEFT")
    notSharedEg:SetWordWrap(true)
    notSharedEg:SetTextColor(MUTED_TEXT_COLOR[1], MUTED_TEXT_COLOR[2], MUTED_TEXT_COLOR[3], MUTED_TEXT_COLOR[4])
    notSharedEg:SetText(GSO.NOT_SHARED_EXAMPLE)

    local mainLabel = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    mainLabel:SetPoint("TOPLEFT", notSharedEg, "BOTTOMLEFT", 0, -SECTION_GAP)
    mainLabel:SetText("What is your main character?")

    local function stretchHorizontally(control, topRelative, topPoint, topYOffset, height, horizontalInset)
        horizontalInset = horizontalInset or 0
        control:ClearAllPoints()
        control:SetPoint("TOP", topRelative, topPoint, 0, topYOffset)
        control:SetPoint("LEFT", bodyInner, "LEFT", horizontalInset, 0)
        control:SetPoint("RIGHT", bodyInner, "RIGHT", -horizontalInset, 0)
        if height then control:SetHeight(height) end
    end

    mainDropdown = Theme.CreateSingleSelectDropdown({
        parent = bodyInner,
        dropdownParent = dialog,
        relativeTo = mainLabel,
        relativePoint = "BOTTOMLEFT",
        y = -4,
        getEntries = realmCharEntries,
        getSelectedId = function() return selectedMain end,
        onSelect = function(id)
            local previousMain = selectedMain
            local previousDisplay = displayNameEdit and displayNameEdit:GetText() or nil
            selectedMain = id
            local GSS = AltArmy.GuildShareSettings
            local DS = AltArmy.DataStore
            local realmChars = DS and DS.GetCharacters and DS:GetCharacters(currentRealm()) or nil
            local syncDisplay = not GSS or not GSS.ShouldSyncDisplayNameWithMain
                or GSS.ShouldSyncDisplayNameWithMain(previousMain, previousDisplay, realmChars)
            if displayNameEdit and id and syncDisplay then
                local firstName = (GSS and GSS.FirstName and GSS.FirstName(id)) or id
                if Theme.SetEditBoxText then
                    Theme.SetEditBoxText(displayNameEdit, firstName)
                else
                    displayNameEdit:SetText(firstName)
                end
            end
        end,
    })
    stretchHorizontally(mainDropdown.button, mainLabel, "BOTTOM", -4, mainDropdown.button:GetHeight())
    mainDropdown.popup:ClearAllPoints()
    mainDropdown.popup:SetPoint("TOPLEFT", mainDropdown.button, "BOTTOMLEFT", 0, -2)
    mainDropdown.popup:SetPoint("TOPRIGHT", mainDropdown.button, "BOTTOMRIGHT", 0, -2)

    local nameLabel = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    nameLabel:SetPoint("TOPLEFT", mainDropdown.button, "BOTTOMLEFT", 0, -CONTROL_GAP)
    nameLabel:SetText("What should people call you?")

    displayNameEdit = CreateFrame("EditBox", nil, bodyInner)
    stretchHorizontally(displayNameEdit, nameLabel, "BOTTOM", -4, 22, 2)
    displayNameEdit:SetFontObject(Theme.FONTS.body)
    displayNameEdit:SetAutoFocus(false)
    displayNameEdit:SetTextInsets(6, 6, 0, 0)
    local maxDisplayNameLen = AltArmy.GuildShareSettings
        and AltArmy.GuildShareSettings.DISPLAY_NAME_MAX_LENGTH
    if displayNameEdit.SetMaxLetters and maxDisplayNameLen then
        displayNameEdit:SetMaxLetters(maxDisplayNameLen)
    end
    Theme.ApplyInputTextures(displayNameEdit)
    displayNameEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    displayNameEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

    local btnConfirm = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
    btnConfirm:SetSize(168, 24)
    btnConfirm:SetPoint("TOP", displayNameEdit, "BOTTOM", 0, -CONTROL_GAP)
    btnConfirm:SetPoint("RIGHT", bodyInner, "CENTER", -6, 0)
    btnConfirm:SetText("Yes, share with guild")
    Theme.SkinButton(btnConfirm)

    local btnSkip = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
    btnSkip:SetSize(168, 24)
    btnSkip:SetPoint("TOP", displayNameEdit, "BOTTOM", 0, -CONTROL_GAP)
    btnSkip:SetPoint("LEFT", bodyInner, "CENTER", 6, 0)
    btnSkip:SetText("No, don't share")
    Theme.SkinButton(btnSkip)

    footnote = bodyInner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
    footnote:SetPoint("TOP", btnConfirm, "BOTTOM", 0, -10)
    footnote:SetPoint("LEFT", bodyInner, "LEFT", 0, 0)
    footnote:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)

    footnote:SetJustifyH("CENTER")
    footnote:SetWordWrap(true)
    footnote:SetTextColor(0.55, 0.55, 0.55, 1)
    footnote:SetText(AltArmy.Text and AltArmy.Text.ONBOARDING_DISMISS_FOOTNOTE
        or "This message will only show once but you can make changes later in Options")

    local function finish()
        dialog:Hide()
        local cb = onDoneCallback
        onDoneCallback = nil
        if cb then cb() end
    end

    local function completeAndClose(share)
        local GSS = AltArmy.GuildShareSettings
        local realm = currentRealm()
        if GSS then
            if share then
                if selectedMain then GSS.SetMain(realm, selectedMain) end
                local dn = displayNameEdit:GetText()
                GSS.SetDisplayName(realm, (dn and dn ~= "" and dn) or nil)
                GSS.SetSharingEnabled(true)
            else
                GSS.SetSharingEnabled(false)
            end
            GSS.SetOnboardingCompleted(realm, true)
        end
        if AltArmy.RefreshGuildTab then AltArmy.RefreshGuildTab() end
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then Comm.ScheduleBroadcast() end
        finish()
    end

    btnConfirm:SetScript("OnClick", function() completeAndClose(true) end)
    btnSkip:SetScript("OnClick", function() completeAndClose(false) end)
    closeBtn:SetScript("OnClick", function() completeAndClose(false) end)
end

--- Grow/shrink the dialog so the footnote (last element) sits inside the body panel.
local function fitDialogHeight()
    if not (dialog and footnote) then return end
    local top, bottom = dialog:GetTop(), footnote:GetBottom()
    if not (top and bottom) then return end
    local needed = (top - bottom) + Theme.TAB_CONTENT_PADDING + CONTENT_INSET
    dialog:SetHeight(math.ceil(needed))
end

local function show(done)
    buildDialog()
    onDoneCallback = done
    local GSS = AltArmy.GuildShareSettings
    local realm = currentRealm()
    selectedMain = resolveDefaultMain(GSS and GSS.GetMain(realm))
    if mainDropdown and mainDropdown.Update then mainDropdown:Update() end
    if displayNameEdit then
        local savedDisplay = GSS and GSS.GetDisplayName(realm)
        local text = (savedDisplay and savedDisplay ~= "" and savedDisplay) or (selectedMain or "")
        if Theme.SetEditBoxText then
            Theme.SetEditBoxText(displayNameEdit, text)
        else
            displayNameEdit:SetText(text)
        end
    end
    dialog:Show()
    fitDialogHeight()
    -- Wrapped text heights can settle a frame after Show.
    if C_Timer and C_Timer.After then C_Timer.After(0, fitDialogHeight) end
end

--- Open the guild-share onboarding dialog (used by the onboarding queue).
function GSO.Show(done)
    show(done)
end

--- Debug: force-show the onboarding dialog even if already completed.
--- @return boolean
function GSO.ShowDebug()
    GSO.Show()
    return true
end

local function shouldPrompt()
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return false end
    return not GSS.IsOnboardingCompleted(currentRealm())
end

if AltArmy.OnboardingDialogQueue and AltArmy.OnboardingDialogQueue.Register then
    AltArmy.OnboardingDialogQueue.Register({
        id = "guildShareOnboarding",
        priority = 60,
        shouldPrompt = shouldPrompt,
        show = show,
    })
end
