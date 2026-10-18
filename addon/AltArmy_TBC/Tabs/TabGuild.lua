-- AltArmy TBC — Guild tab: guildmates shared via guild data sharing, grouped by main.
-- Always present when the guildShare feature flag is on (button visibility handled in Core.lua).
-- Layout:
--   * fixed header: guild name + tabard (left), search field aligned with main header search (right, extended to close)
--   * scroll body: fixed Name / Character Count / Online column headers (click to sort), then
--     one row per main (preferred name + character count + last online), expandable to reveal
--     each character (class-colored name, gray level, primary professions, last online)
--   * recipe detail: Back + character title, profession tabs, recipe search (top right), scrollable recipe list
-- Two content states, driven by the user's OWN sharing setting (not the feature flag):
--   * sharing enabled  -> the header + list above
--   * sharing disabled -> a message plus a link to open the sharing options.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Guild
if not frame then return end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local GTD = AltArmy.GuildTabData
local DS = AltArmy.DataStore
local SECTION_INSET = Theme.TAB_SECTION_INSET
local PAD = Theme.TAB_CONTENT_PADDING
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
-- Layout metrics packed to stay under Lua 5.1's 200-local / function limit.
local UI = {
    HEADER_HEIGHT = 32,
    RECIPE_TITLE_HEIGHT = 32,
    PROF_TAB_HEIGHT = 26,
    PROF_TAB_GAP = 4,
    RECIPE_ROW_HEIGHT = 20,
    RECIPE_SKILL_COL_WIDTH = 72,
    RECIPE_COL_HEADER_HEIGHT = 20,
    -- Match TabCooldowns row height (20) and flush row packing (no inter-group gap).
    MAIN_ROW_HEIGHT = 20,
    CHAR_ROW_HEIGHT = 20,
    GROUP_GAP = 0,
    CHAR_INDENT = 12,
    LIST_COL_HEADER_HEIGHT = 20,
    LIST_FOOTER_HEIGHT = 28,
    -- Nudge footer action buttons slightly below vertical center.
    FOOTER_BUTTON_Y = -2,
    -- Notes wizard member table columns.
    NOTES_REASON_COL_WIDTH = 150,
    NOTES_ACTION_COL_WIDTH = 78,
    NOTES_MAIN_BTN_WIDTH = 50,
    NOTES_ACTION_BTN_GAP = 4,
    NOTES_COL_GAP = 8,
    GRAY = "|cff808080",
    -- Second column (group character count, character professions) shares one left edge.
    SECOND_COLUMN = 220,
    NAME_COLUMN_GAP = 8,
    -- Third column on main rows: most recent last-online across the group's characters.
    LAST_ONLINE_COLUMN_WIDTH = 72,
    OLD_DATA_ICON_WIDTH = 14,
    MANUAL_DATA_ICON_WIDTH = 14,
    SETTINGS_ICON_WIDTH = 18,
    PIN_ICON_SIZE = 14,
    PIN_ICON_GAP = 2,
    MAIN_STAR_ICON_SIZE = 12,
    MAIN_STAR_ICON_GAP = 2,
    RIGHT_ICON_GAP = 2,
    LEFT_ICON_PAD = 4,
    TABARD_SIZE = 24,
    SEARCH_PLACEHOLDER = "Search for characters or professions",
    MAIN_STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}
-- Right edge reserves space for the settings gear only (old-data warning lives on the left).
UI.RIGHT_TRAILING_RESERVE = UI.SETTINGS_ICON_WIDTH + UI.RIGHT_ICON_GAP + 4

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end

local function currentRealm()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm then
        local r = GSS._CurrentRealm()
        if r and r ~= "" then return r end
    end
    return (GetRealmName and GetRealmName()) or ""
end

--- Guilds owned by account characters on the current realm (picker / auto-browse).
local function collectCurrentRealmGuilds()
    if GTD.CollectGuildsOnRealm then
        return GTD.CollectGuildsOnRealm(currentRealm())
    end
    return GTD.CollectAccountGuilds and GTD.CollectAccountGuilds() or {}
end

local function formatName(name, classFile)
    if CC and CC.formatName then return CC.formatName(name, classFile) end
    return name or "?"
end

-- Session-only expand state, keyed by group main character name.
local expandedMains = {}
-- Snapshot of expand state before search began; restored when the search box is cleared.
local savedExpandedMains = nil
-- Current search text (trimmed lower handled by GuildTabData.NormalizeSearchQuery).
local searchText = ""
-- Recipe detail view: filter recipes by name (session-only).
local recipeSearchText = ""
-- Recipe detail view state (session-only).
local selectedCharacter = nil
local selectedCharacterKey = nil
local selectedProfIndex = 1
local recipeSortKey = "recipe"
local recipeSortAscending = true
-- Focused recipe when opened from search (green border + scroll-into-view once).
local focusRecipeID = nil
local focusScrollPending = false
-- Guild list column sort (session-only). Defaults applied when guild lookup mode changes.
local listSortKey = "name"
local listSortAscending = true
-- Tracks whether the current default was applied for in-guild roster lookup capability.
local listSortCanLookupOnline = nil
-- When the current character is not guilded, browse a guild from account alts.
local selectedBrowseGuild = nil
local updateGuildHeaderForListMode
local applyListColumnLayout
local syncMainRowSettingsIcons
-- Manual grouping edit UI + session state (packed to limit locals).
local ME = {
    wizardMode = nil, -- "notes" | "manual" | "edit" while a full-panel wizard is open
    suggestMax = 40,
    -- Visible dropdown height before scrolling (~8 name-only rows + padding).
    suggestMaxHeight = 160,
    suggestPool = {},
    editSourceGroup = nil,
    deleteConfirmPending = false,
}

local function activeGuild()
    local g = currentGuild()
    if g then return g end
    return selectedBrowseGuild
end

local function isBrowsingWithoutGuild()
    return not currentGuild() and selectedBrowseGuild ~= nil
end

local function shouldShowGuildPicker()
    if currentGuild() or selectedBrowseGuild then return false end
    return #(collectCurrentRealmGuilds()) > 1
end

local function shouldShowBrowseBackButton()
    return isBrowsingWithoutGuild() and #(collectCurrentRealmGuilds()) > 1
end

local function memberKey(entry)
    return (entry.realm or "") .. "\0" .. (entry.name or "")
end

-- Spell link via the compat shim (Forever has only C_Spell.GetSpellLink); then the crafted item.
-- recipeID-as-item is a last resort — a spell id read as an item id links an unrelated item.
local function GetRecipeLink(recipeID, resultItemID)
    if not recipeID then return nil end
    local link = DS.CompatGetSpellLink(recipeID)
    if link and link ~= "" then return link end
    if not DS.HasItemInfoApi() then return nil end
    if resultItemID then
        local _, itemLink = DS.CompatGetItemInfo(resultItemID)
        if itemLink and itemLink ~= "" then return itemLink end
    end
    local _, itemLink = DS.CompatGetItemInfo(recipeID)
    if itemLink and itemLink ~= "" then return itemLink end
    return nil
end

local function resolveRecipeDisplay(recipe)
    return GTD.ResolveRecipeDisplay(recipe.recipeID, recipe.resultItemID, recipe.name)
end

local showRecipeView
local showGuildList
local layoutRecipeView
local refresh
local clearRecipeFocus
local applyRecipeFocus
local updateWhisperButton

-- Item ids whose icons were missing on last layout; the view redraws (once) when they arrive.
local recipeIcons = AltArmy.PendingItemIcons and AltArmy.PendingItemIcons.Create(function()
    if selectedCharacter then
        layoutRecipeView(selectedCharacter)
    end
end)

local function clearPendingRecipeIcons()
    if recipeIcons then recipeIcons.Clear() end
end

local function trackPendingRecipeIcon(itemID)
    if recipeIcons then recipeIcons.Track(itemID) end
end

local function copyExpandState(src)
    local out = {}
    for key, value in pairs(src or {}) do
        if value then out[key] = true end
    end
    return out
end

local function normalizedSearchText()
    return GTD.NormalizeSearchQuery(searchText)
end

local function applySearchExpansion(groups)
    if normalizedSearchText() == "" then
        if savedExpandedMains ~= nil then
            expandedMains = copyExpandState(savedExpandedMains)
            savedExpandedMains = nil
        end
        return
    end
    if savedExpandedMains == nil then
        savedExpandedMains = copyExpandState(expandedMains)
    end
    for _, g in ipairs(groups) do
        expandedMains[g.main] = true
    end
end

local function groupPrefsRealm(group)
    for _, m in ipairs((group and group.members) or {}) do
        if m.realm and m.realm ~= "" then
            return m.realm
        end
    end
    if group and group.prefsRealm and group.prefsRealm ~= "" then
        return group.prefsRealm
    end
    local GSS = AltArmy.GuildShareSettings
    return (GSS and GSS._CurrentRealm and GSS._CurrentRealm())
        or (GetRealmName and GetRealmName())
        or ""
end

local function applyGroupUiPrefs(groups)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return end
    for _, g in ipairs(groups or {}) do
        local realm = groupPrefsRealm(g)
        g.prefsRealm = realm
        g.overrideName = (GSS.GetGroupOverrideName and GSS.GetGroupOverrideName(g.main, realm)) or nil
        g.pinned = (GSS.IsGroupPinned and GSS.IsGroupPinned(g.main, realm)) and true or false
    end
end

-- *** Layout: panel + message state ***

local panel = Theme.CreateMainContentPanel(frame)
panel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local inner = Theme.CreatePanelInnerContent(panel)

-- Autocomplete dropdown for add-character (wizard / edit modes).
ME.suggestFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(ME.suggestFrame, "section")
-- Above Accept/Skip and other tab chrome while the notes wizard is open.
ME.suggestFrame:SetFrameStrata("TOOLTIP")
ME.suggestFrame:SetToplevel(true)
ME.suggestFrame:Hide()
ME.suggestFrame:SetHeight(1)

ME.suggestScrollBarOpts = { width = 6, gap = 2, rightInset = 2 }
ME.suggestGutter = Theme.VerticalScrollBarGutter(ME.suggestScrollBarOpts)
ME.suggestViewport = Theme.CreateVerticalScrollViewport({
    parent = ME.suggestFrame,
    gutterEdge = ME.suggestFrame,
    anchorTop = { "TOPLEFT", ME.suggestFrame, "TOPLEFT", 2, -2 },
    anchorBottom = { "BOTTOMRIGHT", ME.suggestFrame, "BOTTOMRIGHT", -(2 + ME.suggestGutter), 2 },
    enableMouseWheel = true,
    valueStep = 18,
    wheelStep = 18,
    scrollBarWidth = ME.suggestScrollBarOpts.width,
    scrollBarGap = ME.suggestScrollBarOpts.gap,
})
ME.suggestList = ME.suggestViewport.child
-- Keep the track/thumb from overlapping the dropdown's top border.
do
    local sb = ME.suggestViewport.scrollBar
    local scroll = ME.suggestViewport.scroll
    local gap = ME.suggestScrollBarOpts.gap or 2
    if sb and scroll then
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", gap, -2)
        sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", gap, 0)
    end
end

ME.hideManualSuggest = function()
    ME.suggestFrame:Hide()
    for _, btn in ipairs(ME.suggestPool) do
        btn.suggestUnavailable = nil
        if Theme.SetHoverTint then
            Theme.SetHoverTint(btn, false)
        end
        btn:Hide()
    end
    if ME.suggestDivider then
        ME.suggestDivider:Hide()
    end
    if ME.suggestUnavailableHeader then
        ME.suggestUnavailableHeader:Hide()
    end
end

--- Hover tint for add-character suggest rows (skipped when unavailable).
--- Blizzard dropdowns and most addons do not change the hardware cursor for
--- non-clickable list rows; they disable hover affordance and show why in-text.
ME.bindSuggestHover = function(btn)
    if not btn or btn._suggestHoverBound then return end
    Theme.InstallHoverTint(btn)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    btn:SetScript("OnEnter", function(self)
        if self.suggestUnavailable then
            return
        end
        Theme.SetHoverTint(self, true)
    end)
    btn:SetScript("OnLeave", function(self)
        Theme.SetHoverTint(self, false)
    end)
    btn._suggestHoverBound = true
end

ME.currentRosterDisplayNames = function()
    local map = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or {}
    return (GTD.RosterDisplayNames and GTD.RosterDisplayNames(map)) or {}
end

ME.currentDisplayMembers = function()
    local GSD = AltArmy.GuildShareData
    local GMG = AltArmy.GuildManualGroups
    local guild = activeGuild()
    if not guild or not GSD or not GSD.GetGuildMembersForDisplay then
        return {}
    end
    local map = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or nil
    if map and GMG and GMG.RefreshFromRosterInfo then
        GMG.RefreshFromRosterInfo(map, currentRealm())
    end
    return GSD.GetGuildMembersForDisplay(guild, currentRealm(), isBrowsingWithoutGuild(), map) or {}
end

--- classFile, level from the live guild roster for a character name (or nil, nil).
ME.rosterClassLevel = function(name)
    if type(name) ~= "string" or name == "" or not GTD.BuildRosterInfoMap then
        return nil, nil
    end
    local map = GTD.BuildRosterInfoMap() or {}
    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
    local info = key and map[key]
    if not info then return nil, nil end
    local classFile = info.classFile
    if type(classFile) ~= "string" or classFile == "" then
        classFile = nil
    end
    local lvl = tonumber(info.level)
    return classFile, (lvl and lvl > 0) and lvl or nil
end

ME.showManualSuggest = function(anchorEdit, names, onPick)
    ME.hideManualSuggest()
    if not names or #names == 0 then return end
    local count = math.min(#names, ME.suggestMax)
    local rosterInfo = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or {}
    local occupied = (ME.wizardOccupiedNames and ME.wizardOccupiedNames()) or {}
    local query = GTD.NormalizeSearchQuery and GTD.NormalizeSearchQuery(anchorEdit:GetText() or "") or ""
    local topPad = 2
    local nameLineH = 14
    local noteTopPad = 2
    local noteLineH = 14
    local reasonLineH = 14
    local bottomPad = 2
    local charGap = 0
    local dividerPad = 4
    local dividerH = 1
    local y = 2
    local listParent = ME.suggestList or ME.suggestFrame
    local sawSelectable = false
    local unavailableSectionStarted = false
    if ME.suggestDivider then
        ME.suggestDivider:Hide()
    end
    if ME.suggestUnavailableHeader then
        ME.suggestUnavailableHeader:Hide()
    end
    ME.suggestFrame:ClearAllPoints()
    ME.suggestFrame:SetPoint("TOPLEFT", anchorEdit, "BOTTOMLEFT", 0, -2)
    ME.suggestFrame:SetPoint("TOPRIGHT", anchorEdit, "BOTTOMRIGHT", 0, -2)
    ME.suggestFrame:SetFrameLevel(math.max((frame:GetFrameLevel() or 0) + 50, 200))
    for i = 1, count do
        local charName = names[i]
        local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(charName)
        local info = (key and rosterInfo[key]) or nil
        local noteText = info and info.note or ""
        local hasNote = type(noteText) == "string" and noteText ~= ""
        local disabledInfo = (GTD.RosterAddDisabledReason
            and GTD.RosterAddDisabledReason(occupied, charName)) or nil
        local disabledText = disabledInfo and GTD.FormatRosterAddDisabledReason
            and GTD.FormatRosterAddDisabledReason(disabledInfo, formatName) or nil
        if disabledText == "" then disabledText = nil end
        if disabledInfo then
            if not unavailableSectionStarted then
                if sawSelectable then
                    if not ME.suggestDivider and Theme.CreateSeparator then
                        ME.suggestDivider = Theme.CreateSeparator(listParent)
                    end
                    local sep = ME.suggestDivider
                    if sep then
                        if sep.SetParent then
                            sep:SetParent(listParent)
                        end
                        sep:ClearAllPoints()
                        sep:SetHeight(dividerH)
                        sep:SetPoint("TOPLEFT", listParent, "TOPLEFT", 6, -(y + dividerPad))
                        sep:SetPoint("TOPRIGHT", listParent, "TOPRIGHT", -6, -(y + dividerPad))
                        sep:Show()
                        y = y + dividerPad + dividerH + dividerPad
                    end
                end
                if not ME.suggestUnavailableHeader then
                    local header = listParent:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
                    header:SetJustifyH("LEFT")
                    header:SetWordWrap(false)
                    ME.suggestUnavailableHeader = header
                end
                local header = ME.suggestUnavailableHeader
                if header.SetParent then
                    header:SetParent(listParent)
                end
                header:SetFontObject(Theme.FONTS.muted)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", listParent, "TOPLEFT", 6, -y)
                header:SetPoint("TOPRIGHT", listParent, "TOPRIGHT", -6, -y)
                header:SetHeight(nameLineH)
                header:SetText("|cff808080Unavailable matches:|r")
                header:Show()
                y = y + nameLineH + noteTopPad
                unavailableSectionStarted = true
            end
        else
            sawSelectable = true
        end
        local rowH = topPad + nameLineH + bottomPad
        if hasNote then
            rowH = rowH + noteTopPad + noteLineH
        end
        if disabledText then
            rowH = rowH + noteTopPad + reasonLineH
        end
        local btn = ME.suggestPool[i]
        if not btn then
            btn = CreateFrame("Button", nil, listParent)
            local nameFS = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            btn.nameFS = nameFS
            local noteFS = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            noteFS:SetJustifyH("LEFT")
            noteFS:SetWordWrap(false)
            btn.noteFS = noteFS
            local reasonFS = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            reasonFS:SetJustifyH("LEFT")
            reasonFS:SetWordWrap(false)
            btn.reasonFS = reasonFS
            ME.bindSuggestHover(btn)
            ME.suggestPool[i] = btn
        elseif not btn._suggestHoverBound then
            ME.bindSuggestHover(btn)
        end
        -- Migrate older single-label pool buttons if present.
        if not btn.nameFS and btn.label then
            btn.nameFS = btn.label
        end
        if not btn.reasonFS then
            local reasonFS = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            reasonFS:SetJustifyH("LEFT")
            reasonFS:SetWordWrap(false)
            btn.reasonFS = reasonFS
        end
        if btn.SetParent then
            btn:SetParent(listParent)
        end
        if btn.nameFS then
            btn.nameFS:ClearAllPoints()
            btn.nameFS:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -topPad)
            btn.nameFS:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -topPad)
            btn.nameFS:SetHeight(nameLineH)
        end
        local belowNameAnchor = btn.nameFS
        if btn.noteFS then
            btn.noteFS:SetFontObject(Theme.FONTS.body)
            btn.noteFS:ClearAllPoints()
            btn.noteFS:SetPoint("TOPLEFT", belowNameAnchor, "BOTTOMLEFT", 8, -noteTopPad)
            btn.noteFS:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, 0)
            btn.noteFS:SetHeight(noteLineH)
        end
        if btn.reasonFS then
            btn.reasonFS:SetFontObject(Theme.FONTS.body)
            btn.reasonFS:ClearAllPoints()
            if hasNote and btn.noteFS then
                btn.reasonFS:SetPoint("TOPLEFT", btn.noteFS, "BOTTOMLEFT", 0, -noteTopPad)
            else
                btn.reasonFS:SetPoint("TOPLEFT", belowNameAnchor, "BOTTOMLEFT", 8, -noteTopPad)
            end
            btn.reasonFS:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, 0)
            btn.reasonFS:SetHeight(reasonLineH)
        end
        btn:SetHeight(rowH)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", listParent, "TOPLEFT", 0, -y)
        btn:SetPoint("TOPRIGHT", listParent, "TOPRIGHT", 0, -y)
        if btn.nameFS then
            if GTD.FormatRosterSuggestName then
                btn.nameFS:SetText(GTD.FormatRosterSuggestName(
                    info or { name = charName }, formatName, query ~= "" and query or nil))
            else
                btn.nameFS:SetText(charName)
            end
        end
        if btn.noteFS then
            if hasNote then
                if GTD.FormatNotesWizardMemberNote then
                    btn.noteFS:SetText(GTD.FormatNotesWizardMemberNote(
                        noteText, query ~= "" and query or nil))
                elseif query ~= "" and GTD.FormatTextWithSearchHighlight then
                    btn.noteFS:SetText(GTD.FormatTextWithSearchHighlight(noteText, nil, query))
                else
                    btn.noteFS:SetText(noteText)
                end
                btn.noteFS:Show()
            else
                btn.noteFS:SetText("")
                btn.noteFS:Hide()
            end
        end
        if btn.reasonFS then
            if disabledText then
                btn.reasonFS:SetText(disabledText)
                btn.reasonFS:Show()
            else
                btn.reasonFS:SetText("")
                btn.reasonFS:Hide()
            end
        end
        btn.suggestUnavailable = disabledInfo and true or nil
        if disabledInfo and Theme.SetHoverTint then
            Theme.SetHoverTint(btn, false)
        end
        do
            local picked = charName
            if disabledInfo then
                btn:SetScript("OnClick", nil)
            else
                btn:SetScript("OnClick", function()
                    ME.hideManualSuggest()
                    if onPick then onPick(picked) end
                end)
            end
            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", function(_, delta)
                if ME.suggestViewport then ME.suggestViewport.Wheel(delta) end
            end)
        end
        btn:Show()
        y = y + rowH
        if i < count then
            y = y + charGap
        end
    end
    for i = count + 1, #ME.suggestPool do
        if ME.suggestPool[i] then ME.suggestPool[i]:Hide() end
    end
    local contentH = math.max(1, y + 2)
    local maxH = ME.suggestMaxHeight or 160
    local viewH = math.min(contentH, maxH)
    -- Outer frame: content/view height plus top/bottom padding around the viewport.
    ME.suggestFrame:SetHeight(viewH + 4)
    if ME.suggestViewport then
        local frameW = ME.suggestFrame:GetWidth() or 0
        if frameW < 1 then
            frameW = anchorEdit:GetWidth() or 200
        end
        local scrollW = math.max(1, frameW - 4 - (ME.suggestGutter or 0))
        listParent:SetWidth(scrollW)
        listParent:SetHeight(contentH)
        if ME.suggestViewport.SetOffset then
            ME.suggestViewport.SetOffset(0)
        end
        if ME.suggestViewport.UpdateRange then
            ME.suggestViewport.UpdateRange()
        end
    end
    ME.suggestFrame:Show()
    if ME.suggestViewport and ME.suggestViewport.UpdateRange then
        ME.suggestViewport.UpdateRange()
    end
end


-- Disabled / no-guild message state
local messageView = CreateFrame("Frame", nil, inner)
messageView:SetAllPoints(inner)
messageView:Hide()

local messageText = messageView:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
messageText:SetPoint("TOP", messageView, "TOP", 0, -60)
messageText:SetWidth(360)
messageText:SetJustifyH("CENTER")

local optionsBtn = CreateFrame("Button", nil, messageView)
optionsBtn:SetSize(180, 24)
optionsBtn:SetPoint("TOP", messageText, "BOTTOM", 0, -16)
Theme.SkinButton(optionsBtn)
local optionsBtnLabel = optionsBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
optionsBtnLabel:SetPoint("CENTER", optionsBtn, "CENTER", 0, 0)
optionsBtnLabel:SetText("Open sharing options")
optionsBtn:SetScript("OnClick", function()
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions("general", { flash = "guildShare" })
    end
end)

-- *** List state (header + scroll body) ***

local listView = CreateFrame("Frame", nil, inner)
listView:SetAllPoints(inner)
listView:Hide()
if listView.SetClipsChildren then
    listView:SetClipsChildren(true)
end

-- Fixed header (does not scroll)
local header = CreateFrame("Frame", nil, listView)
header:SetPoint("TOPLEFT", listView, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", listView, "TOPRIGHT", 0, 0)
header:SetHeight(UI.HEADER_HEIGHT)
header:SetFrameLevel(listView:GetFrameLevel() + 5)

local guildNameText = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
guildNameText:SetJustifyH("LEFT")
Theme.SetTitleColor(guildNameText)

-- Guild tabard: three stacked textures composed by SetLargeGuildTabardTextures.
local tabardFrame = CreateFrame("Frame", nil, header)
tabardFrame:SetSize(UI.TABARD_SIZE, UI.TABARD_SIZE)
tabardFrame:SetPoint("LEFT", guildNameText, "RIGHT", 6, 0)
tabardFrame:Hide()
local tabardBackground = tabardFrame:CreateTexture(nil, "BACKGROUND")
tabardBackground:SetAllPoints(tabardFrame)
local tabardEmblem = tabardFrame:CreateTexture(nil, "ARTWORK")
tabardEmblem:SetAllPoints(tabardFrame)
local tabardBorder = tabardFrame:CreateTexture(nil, "OVERLAY")
tabardBorder:SetAllPoints(tabardFrame)

local function updateTabard()
    -- Keep the tabard off while list-header chrome is replaced (notes wizard / recipe detail).
    if ME.notesWizardActive or selectedCharacter then
        tabardFrame:Hide()
        return
    end
    if not currentGuild() or isBrowsingWithoutGuild() then
        tabardFrame:Hide()
        return
    end
    -- Same crest as the Guild side tab and window portrait (UI/GuildCrest.lua).
    local GuildCrest = AltArmy.GuildCrest
    local drawn = GuildCrest and GuildCrest.Apply(tabardBackground, tabardEmblem, tabardBorder)
    tabardFrame:SetShown(drawn and true or false)
end

-- Recipe search (character view): same horizontal span as the main toolbar search box.
local headerSearchRef = _G.AltArmyTBC_HeaderSearchEdit

local function anchorGuildHeaderSearch(edit)
    edit:SetHeight(20)
    edit:SetPoint("TOP", header, "TOP", 0, -6)
    if headerSearchRef then
        edit:SetPoint("LEFT", headerSearchRef, "LEFT", 0, 0)
        edit:SetPoint("RIGHT", headerSearchRef, "RIGHT", 0, 0)
    else
        edit:SetSize(288, 20)
        edit:SetPoint("RIGHT", header, "RIGHT", -20, 0)
    end
end

-- Character/profession search lives in the main toolbar row (where Summary's item search
-- sits); parented to the tab frame because the list header clips its children.
-- Same search box as Summary's item search (native SearchBoxTemplate: magnifier, clear button).
local searchEdit = Theme.CreateSearchBox(frame, {
    name = "AltArmyTBC_GuildSearchEdit",
    placeholder = UI.SEARCH_PLACEHOLDER,
})
if AltArmy.PlaceInToolbarSearchSlot then
    AltArmy.PlaceInToolbarSearchSlot(searchEdit, frame)
else
    anchorGuildHeaderSearch(searchEdit)
end

-- Recipe detail search: same toolbar-row slot as the character search it replaces.
local recipeSearchEdit = Theme.CreateSearchBox(frame, {
    name = "AltArmyTBC_GuildRecipeSearchEdit",
    placeholder = "Search for recipes on this character",
})
if AltArmy.PlaceInToolbarSearchSlot then
    AltArmy.PlaceInToolbarSearchSlot(recipeSearchEdit, frame)
else
    anchorGuildHeaderSearch(recipeSearchEdit)
end
recipeSearchEdit:Hide()

local function updateRecipeSearchPlaceholder(entry)
    Theme.SetEditBoxPlaceholderText(recipeSearchEdit, GTD.FormatRecipeSearchPlaceholder(entry and entry.name))
end

local function updateRecipeSearchClearVisibility()
    if selectedCharacter and updateWhisperButton then
        updateWhisperButton(selectedCharacter)
    end
end

local function clearRecipeSearch()
    recipeSearchText = ""
    Theme.ClearEditBoxText(recipeSearchEdit)
    updateRecipeSearchClearVisibility()
end

local suppressRecipeSearchLayout = false

local function clearRecipeSearchQuiet()
    suppressRecipeSearchLayout = true
    clearRecipeSearch()
    suppressRecipeSearchLayout = false
end

-- Recipe detail header chrome (Back + title + profession tabs).
local guildBackBtn = CreateFrame("Button", nil, header)
guildBackBtn:SetSize(52, 22)
guildBackBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
guildBackBtn:Hide()
Theme.SkinButton(guildBackBtn)
local guildBackBtnLabel = guildBackBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
guildBackBtnLabel:SetPoint("CENTER", guildBackBtn, "CENTER", 0, 0)
guildBackBtnLabel:SetText("Back")

local backBtn = CreateFrame("Button", nil, header)
backBtn:SetSize(52, 22)
backBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
backBtn:Hide()
Theme.SkinButton(backBtn)
local backBtnLabel = backBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
backBtnLabel:SetPoint("CENTER", backBtn, "CENTER", 0, 0)
backBtnLabel:SetText("Back")

-- Right edge of the title line's free space (the header edge).
ME.recipeRightGuard = CreateFrame("Frame", nil, header)
ME.recipeRightGuard:SetSize(1, 1)

local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString

local recipeTitleFS = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
recipeTitleFS:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
recipeTitleFS:SetPoint("RIGHT", ME.recipeRightGuard, "LEFT", -8, 0)
recipeTitleFS:SetJustifyH("LEFT")
recipeTitleFS:SetWordWrap(false)
recipeTitleFS:Hide()

local whisperBtn = CreateFrame("Button", nil, header)
whisperBtn:SetHeight(22)
whisperBtn:Hide()
Theme.SkinButton(whisperBtn)
local whisperBtnLabel = whisperBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
whisperBtnLabel:SetPoint("CENTER", whisperBtn, "CENTER", 0, 0)
whisperBtnLabel:SetText("Whisper")
whisperBtn:SetWidth(math.max(64, (whisperBtnLabel:GetStringWidth() or 40) + 16))
whisperBtn:SetScript("OnClick", function(self)
    local target = self.whisperTarget
    if not target or target == "" then return end
    if _G.ChatFrame_SendTell then
        _G.ChatFrame_SendTell(target)
    elseif _G.ChatFrame_OpenChat then
        _G.ChatFrame_OpenChat("/w " .. target .. " ")
    end
end)

--- Right edge of the title line's free space.
local function recipeTitleRightGuard()
    local guard = ME.recipeRightGuard
    guard:ClearAllPoints()
    guard:SetPoint("RIGHT", header, "RIGHT", 6, 0)
    return guard, "LEFT"
end

local function anchorWhisperFlushRight()
    local guard, point = recipeTitleRightGuard()
    whisperBtn:ClearAllPoints()
    whisperBtn:SetPoint("RIGHT", guard, point, -8, 0)
end

local function anchorRecipeTitleTo(rightFrame)
    recipeTitleFS:ClearAllPoints()
    recipeTitleFS:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
    recipeTitleFS:SetPoint("RIGHT", rightFrame, "LEFT", -8, 0)
end

local function recipeTitleMaxWidth()
    local left = backBtn:GetRight() or 0
    local rightFrame = whisperBtn:IsShown() and whisperBtn or select(1, recipeTitleRightGuard())
    local right = rightFrame and rightFrame:GetLeft() or 0
    return math.max(0, right - left - 16)
end

local function applyRecipeTitleText(entry)
    if not entry then
        recipeTitleFS:SetText("")
        return
    end
    local nameColored = GTD.FormatCharacterTitle(entry, formatName)
    local level = math.floor(tonumber(entry.level) or 0)
    local fullSuffix = GTD.FormatCharacterLevelSuffix(level, "full", UI.GRAY)
    local shortSuffix = GTD.FormatCharacterLevelSuffix(level, "short", UI.GRAY)
    local maxW = recipeTitleMaxWidth()

    recipeTitleFS:SetText(nameColored .. fullSuffix)
    local fitsFull = maxW <= 0 or (recipeTitleFS:GetStringWidth() or 0) <= maxW
    recipeTitleFS:SetText(nameColored .. shortSuffix)
    local fitsShort = maxW <= 0 or (recipeTitleFS:GetStringWidth() or 0) <= maxW
    local mode = GTD.ChooseCharacterTitleLevelMode(fitsFull, fitsShort)

    if mode == "full" then
        recipeTitleFS:SetText(nameColored .. fullSuffix)
    elseif mode == "short" then
        recipeTitleFS:SetText(nameColored .. shortSuffix)
    elseif TruncateFontString then
        TruncateFontString(recipeTitleFS, nameColored, maxW, {
            preserveColorCodes = true,
            suffix = shortSuffix,
        })
    else
        recipeTitleFS:SetText(nameColored .. shortSuffix)
    end
end

updateWhisperButton = function(entry)
    whisperBtn.whisperTarget = nil
    if not entry then
        whisperBtn:Hide()
        anchorRecipeTitleTo(select(1, recipeTitleRightGuard()))
        applyRecipeTitleText(nil)
        return
    end
    local rosterByName = (GTD.BuildRosterLastOnlineMap and GTD.BuildRosterLastOnlineMap()) or {}
    local members
    local GSD = AltArmy.GuildShareData
    if entry.guildName and GSD and GSD.GetGuildMembersForDisplay then
        members = GSD.GetGuildMembersForDisplay(entry.guildName, entry.realm, true)
    end
    local target = GTD.ResolveOnlineWhisperTarget and GTD.ResolveOnlineWhisperTarget(entry, rosterByName, members)
    if target then
        whisperBtn.whisperTarget = target
        whisperBtn:Show()
        anchorWhisperFlushRight()
        anchorRecipeTitleTo(whisperBtn)
    else
        whisperBtn:Hide()
        anchorRecipeTitleTo(select(1, recipeTitleRightGuard()))
    end
    applyRecipeTitleText(entry)
end

header:SetScript("OnSizeChanged", function()
    if selectedCharacter and recipeTitleFS:IsShown() then
        updateWhisperButton(selectedCharacter)
    end
end)

local profTabStrip = CreateFrame("Frame", nil, header)
profTabStrip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
profTabStrip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
profTabStrip:SetHeight(UI.PROF_TAB_HEIGHT)
profTabStrip:Hide()

-- Forever (spellbook icon tab art available): profession tabs move to the toolbar row as icons.
ME.useProfIconTabs = (AltArmy.NativeUI and AltArmy.NativeUI.GetCaps().iconTabs) and true or false
ME.profIconTabSets = {}

local function isRecipeDataAvailable()
    local RI = AltArmy and AltArmy.RecipeInfo
    return RI and RI.IsAvailable and RI.IsAvailable() or false
end

local function layoutRecipeRowColumns(row, showSkillCol)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    if showSkillCol then
        row.label:SetPoint("RIGHT", row, "RIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        row.skillCell:Show()
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.skillCell:Hide()
    end
end

updateGuildHeaderForListMode = function()
    if ME.notesWizardActive then
        ME.showNotesWizardChrome()
        if ME.syncListFooter then ME.syncListFooter() end
        return
    end
    if shouldShowGuildPicker() then
        guildBackBtn:Hide()
        guildNameText:ClearAllPoints()
        guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
        guildNameText:SetText("Select a guild")
        Theme.SetTitleColor(guildNameText)
        guildNameText:Show()
        searchEdit:Hide()
        tabardFrame:Hide()
        if ME.syncListFooter then ME.syncListFooter() end
        return
    end
    if isBrowsingWithoutGuild() and shouldShowBrowseBackButton() then
        guildBackBtn:Show()
        guildNameText:ClearAllPoints()
        guildNameText:SetPoint("LEFT", guildBackBtn, "RIGHT", 8, 0)
        guildNameText:SetText(selectedBrowseGuild or "")
        Theme.SetTitleColor(guildNameText)
        guildNameText:Show()
        searchEdit:Show()
        tabardFrame:Hide()
        if ME.syncListFooter then ME.syncListFooter() end
        return
    end
    guildBackBtn:Hide()
    guildNameText:ClearAllPoints()
    guildNameText:SetPoint("LEFT", header, "LEFT", 2, 0)
    guildNameText:SetText(activeGuild() or "")
    Theme.SetTitleColor(guildNameText)
    guildNameText:Show()
    searchEdit:Show()
    updateTabard()
    if ME.syncListFooter then ME.syncListFooter() end
end

local function setListHeaderVisible(visible)
    if visible then
        updateGuildHeaderForListMode()
        recipeSearchEdit:Hide()
        whisperBtn:Hide()
        if ME.hideProfIconTabs then ME.hideProfIconTabs() end
        anchorRecipeTitleTo(select(1, recipeTitleRightGuard()))
    else
        guildNameText:Hide()
        guildBackBtn:Hide()
        searchEdit:Hide()
        tabardFrame:Hide()
        recipeSearchEdit:Show()
        updateRecipeSearchClearVisibility()
        Theme.UpdateEditBoxPlaceholderVisibility(recipeSearchEdit)
    end
    backBtn:SetShown(not visible)
    recipeTitleFS:SetShown(not visible)
    if visible then
        whisperBtn:Hide()
    end
    profTabStrip:SetShown(not visible and not ME.useProfIconTabs)
end

-- Member-list page body (slides against recipeBody / notesWizard).
ME.listBody = CreateFrame("Frame", nil, listView)
ME.listBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
ME.listBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", 0, 0)

-- Scroll body below the guild header and fixed column headers.
local listColHeader = CreateFrame("Frame", nil, ME.listBody)
listColHeader:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
listColHeader:SetPoint("TOPLEFT", ME.listBody, "TOPLEFT", 0, 0)
listColHeader:SetPoint("TOPRIGHT", ME.listBody, "TOPRIGHT", -SCROLL_GUTTER, 0)
listColHeader:Hide()

local LIST_HEADER_LABEL = {
    name = "Name",
    characterCount = "Character Count",
    online = "Online",
}
local listHeaderButtons = {}

local function updateListHeaderSortIndicators()
    for key, btn in pairs(listHeaderButtons) do
        if btn.label then
            local base = LIST_HEADER_LABEL[key] or key
            Theme.SetSortHeaderLabel(btn.label, base, key == listSortKey, listSortAscending)
        end
    end
end

--- Apply default column sort when switching between in-guild and browse-without-guild modes.
local function ensureDefaultListSort(canLookupOnline)
    if listSortCanLookupOnline == canLookupOnline then
        return
    end
    listSortCanLookupOnline = canLookupOnline
    if GTD.GetDefaultListSort then
        listSortKey, listSortAscending = GTD.GetDefaultListSort(canLookupOnline)
    elseif canLookupOnline then
        listSortKey, listSortAscending = "online", true
    else
        listSortKey, listSortAscending = "name", true
    end
    updateListHeaderSortIndicators()
end

local function createListHeaderButton(sortKey, justifyH, anchorFn)
    local btn = CreateFrame("Button", nil, listColHeader)
    btn:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    anchorFn(btn)
    local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
    label:SetJustifyH(justifyH or "LEFT")
    label:SetWordWrap(false)
    btn.label = label
    Theme.BindInteractableHover(btn)
    local sortKeyForClick = sortKey
    btn:SetScript("OnClick", function()
        if listSortKey == sortKeyForClick then
            listSortAscending = not listSortAscending
        else
            listSortKey = sortKeyForClick
            -- Character count: first click highest→lowest; other columns: A→Z / least→most.
            listSortAscending = sortKeyForClick ~= "characterCount"
        end
        updateListHeaderSortIndicators()
        refresh()
    end)
    listHeaderButtons[sortKey] = btn
    return btn
end

createListHeaderButton("online", "RIGHT", function(btn)
    btn:SetPoint("RIGHT", listColHeader, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
    btn:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
end)
createListHeaderButton("name", "LEFT", function(btn)
    btn:SetPoint("LEFT", listColHeader, "LEFT", 4, 0)
    btn:SetPoint("RIGHT", listColHeader, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
end)
createListHeaderButton("characterCount", "LEFT", function(btn)
    btn:SetPoint("LEFT", listColHeader, "LEFT", UI.SECOND_COLUMN, 0)
    btn:SetPoint("RIGHT", listHeaderButtons.online, "LEFT", -UI.NAME_COLUMN_GAP, 0)
end)
updateListHeaderSortIndicators()

local listViewport = CreateFrame("Frame", nil, ME.listBody)
-- Footer sits under the list; viewport leaves room so rows don't cover the buttons.
ME.listFooter = CreateFrame("Frame", nil, ME.listBody)
ME.listFooter:SetHeight(UI.LIST_FOOTER_HEIGHT)
ME.listFooter:SetPoint("BOTTOMLEFT", ME.listBody, "BOTTOMLEFT", 0, 0)
ME.listFooter:SetPoint("BOTTOMRIGHT", ME.listBody, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
ME.listFooter:Hide()

ME.addGroupBtn = CreateFrame("Button", nil, ME.listFooter, "UIPanelButtonTemplate")
ME.addGroupBtn:SetHeight(22)
ME.addGroupBtn:SetText("Add Manual Group")
Theme.SkinButton(ME.addGroupBtn)
ME.addGroupBtn:SetWidth(140)
ME.addGroupBtn:SetScript("OnClick", function()
    if ME.slideSwap then
        ME.slideSwap(function() ME.openManualCreate() end)
    else
        ME.openManualCreate()
    end
end)

ME.scanNotesBtn = CreateFrame("Button", nil, ME.listFooter, "UIPanelButtonTemplate")
ME.scanNotesBtn:SetHeight(22)
ME.scanNotesBtn:SetText("Add Groups from Notes")
Theme.SkinButton(ME.scanNotesBtn)
ME.scanNotesBtn:SetWidth(170)
ME.scanNotesBtn:SetScript("OnClick", function()
    if ME.slideSwap then
        ME.slideSwap(function() ME.openScanReview() end)
    else
        ME.openScanReview()
    end
end)

ME.layoutListFooterButtons = function()
    local gap = 8
    local y = UI.FOOTER_BUTTON_Y or 0
    local addW = ME.addGroupBtn:GetWidth() or 140
    local scanShown = ME.scanNotesBtn:IsShown()
    local scanW = scanShown and (ME.scanNotesBtn:GetWidth() or 170) or 0
    local total = addW + (scanShown and (gap + scanW) or 0)
    ME.addGroupBtn:ClearAllPoints()
    ME.addGroupBtn:SetPoint("LEFT", ME.listFooter, "CENTER", -total / 2, y)
    if scanShown then
        ME.scanNotesBtn:ClearAllPoints()
        ME.scanNotesBtn:SetPoint("LEFT", ME.addGroupBtn, "RIGHT", gap, 0)
    end
end

ME.syncListFooter = function()
    -- Guild member list only (not recipe detail, picker, message view, or notes wizard).
    local showList = listView:IsShown()
        and ME.listBody and ME.listBody:IsShown()
        and listViewport:IsShown()
        and listColHeader:IsShown()
        and not shouldShowGuildPicker()
        and not ME.notesWizardActive
    if not showList then
        ME.listFooter:Hide()
        return
    end
    ME.listFooter:Show()
    ME.addGroupBtn:Show()
    -- Note scan needs the live guild roster.
    if currentGuild() then
        ME.scanNotesBtn:Show()
    else
        ME.scanNotesBtn:Hide()
    end
    ME.layoutListFooterButtons()
end

-- *** Notes grouping wizard (full-panel, one proposed group at a time) ***
ME.notesWizardActive = false
ME.notesProposals = {}
ME.notesIndex = 1
ME.notesMemberRows = {}

ME.notesBackBtn = CreateFrame("Button", nil, header)
ME.notesBackBtn:SetSize(52, 22)
ME.notesBackBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
ME.notesBackBtn:Hide()
Theme.SkinButton(ME.notesBackBtn)
ME.notesBackBtnLabel = ME.notesBackBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
ME.notesBackBtnLabel:SetPoint("CENTER", ME.notesBackBtn, "CENTER", 0, 0)
ME.notesBackBtnLabel:SetText("Back")

ME.notesTitleFS = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
ME.notesTitleFS:SetPoint("LEFT", ME.notesBackBtn, "RIGHT", 8, 0)
ME.notesTitleFS:SetJustifyH("LEFT")
ME.notesTitleFS:SetWordWrap(false)
ME.notesTitleFS:Hide()
Theme.SetTitleColor(ME.notesTitleFS)

ME.notesDeleteBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
ME.notesDeleteBtn:SetSize(130, 22)
ME.notesDeleteBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
ME.notesDeleteBtn:SetText("Delete local data")
Theme.SkinDangerButton(ME.notesDeleteBtn)
ME.notesDeleteBtn:Hide()

ME.notesProgressFS = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
ME.notesProgressFS:SetPoint("RIGHT", header, "RIGHT", -8, 0)
ME.notesProgressFS:SetJustifyH("RIGHT")
ME.notesProgressFS:SetWordWrap(false)
ME.notesProgressFS:Hide()
Theme.SetTitleColor(ME.notesProgressFS)
ME.notesTitleFS:SetPoint("RIGHT", ME.notesProgressFS, "LEFT", -12, 0)

ME.notesWizard = CreateFrame("Frame", nil, listView)
ME.notesWizard:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
ME.notesWizard:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", 0, 0)
ME.notesWizard:Hide()

ME.notesFooter = CreateFrame("Frame", nil, ME.notesWizard)
ME.notesFooter:SetHeight(UI.LIST_FOOTER_HEIGHT)
ME.notesFooter:SetPoint("BOTTOMLEFT", ME.notesWizard, "BOTTOMLEFT", 0, 0)
ME.notesFooter:SetPoint("BOTTOMRIGHT", ME.notesWizard, "BOTTOMRIGHT", 0, 0)
ME.notesFooter:SetFrameLevel((ME.notesWizard:GetFrameLevel() or 0) + 20)

ME.notesAcceptBtn = CreateFrame("Button", nil, ME.notesFooter, "UIPanelButtonTemplate")
ME.notesAcceptBtn:SetSize(120, 22)
ME.notesAcceptBtn:SetText("Accept group")
Theme.SkinButton(ME.notesAcceptBtn)

ME.notesSkipBtn = CreateFrame("Button", nil, ME.notesFooter, "UIPanelButtonTemplate")
ME.notesSkipBtn:SetSize(100, 22)
ME.notesSkipBtn:SetText("Skip group")
Theme.SkinButton(ME.notesSkipBtn)

-- Match the members-table scrollbar gutter so Pin / Override line up with
-- "Characters in this group" / "Reason for inclusion" below.
ME.notesScrollBarOpts = { width = 6, gap = 2, rightInset = 2 }
ME.notesMembersGutter = Theme.VerticalScrollBarGutter(ME.notesScrollBarOpts)

-- Edit-mode options (Pin / Override name), shown above the member table.
-- One row: left 50% Pin, right 50% Override name + Reset.
ME.editOptions = CreateFrame("Frame", nil, ME.notesWizard)
ME.editOptions:SetHeight(22)
ME.editOptions:SetPoint("TOPLEFT", ME.notesWizard, "TOPLEFT", 0, 0)
ME.editOptions:SetPoint("TOPRIGHT", ME.notesWizard, "TOPRIGHT", -ME.notesMembersGutter, 0)
ME.editOptions:Hide()

ME.editPinCol = CreateFrame("Frame", nil, ME.editOptions)
ME.editPinCol:SetPoint("TOPLEFT", ME.editOptions, "TOPLEFT", 0, 0)
ME.editPinCol:SetPoint("BOTTOMRIGHT", ME.editOptions, "BOTTOM", -(UI.NOTES_COL_GAP / 2), 0)

ME.editOverrideCol = CreateFrame("Frame", nil, ME.editOptions)
ME.editOverrideCol:SetPoint("TOPRIGHT", ME.editOptions, "TOPRIGHT", 0, 0)
ME.editOverrideCol:SetPoint("BOTTOMLEFT", ME.editOptions, "BOTTOM", UI.NOTES_COL_GAP / 2, 0)

ME.editPinRow = Theme.CreateLabeledCheckbox(ME.editPinCol, {
    point = "TOPLEFT",
    x = 0,
    y = 0,
    text = "Pin",
    fullWidthHover = true,
    onClick = function(checked)
        local p = ME.currentNotesProposal and ME.currentNotesProposal()
        local group = ME.editSourceGroup
        if not p or not group then return end
        local pinned = checked and true or false
        local GSS = AltArmy.GuildShareSettings
        local realm = groupPrefsRealm(group)
        if GSS and GSS.SetGroupPinned then
            GSS.SetGroupPinned(group.main, realm, pinned)
        end
        p.pinned = pinned
        group.pinned = pinned
    end,
})

ME.editOverrideResetBtn = CreateFrame("Button", nil, ME.editOverrideCol, "UIPanelButtonTemplate")
ME.editOverrideResetBtn:SetSize(56, 22)
ME.editOverrideResetBtn:SetPoint("TOPRIGHT", ME.editOverrideCol, "TOPRIGHT", 0, 0)
ME.editOverrideResetBtn:SetText("Reset")
Theme.SkinButton(ME.editOverrideResetBtn)

ME.editOverrideEdit = CreateFrame("EditBox", nil, ME.editOverrideCol)
ME.editOverrideEdit:SetPoint("TOPLEFT", ME.editOverrideCol, "TOPLEFT", 0, 0)
ME.editOverrideEdit:SetPoint("RIGHT", ME.editOverrideResetBtn, "LEFT", -6, 0)
ME.editOverrideEdit:SetHeight(22)
ME.editOverrideEdit:SetFontObject(Theme.FONTS.body)
ME.editOverrideEdit:SetAutoFocus(false)
ME.editOverrideEdit:SetTextInsets(6, 6, 0, 0)
do
    local overrideMaxLen = AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.DISPLAY_NAME_MAX_LENGTH
    if ME.editOverrideEdit.SetMaxLetters and overrideMaxLen then
        ME.editOverrideEdit:SetMaxLetters(overrideMaxLen)
    end
end
Theme.ApplyInputTextures(ME.editOverrideEdit)
if Theme.SetupEditBoxPlaceholder then
    Theme.SetupEditBoxPlaceholder(ME.editOverrideEdit, "Override name in my UI")
end

ME.applyEditOverrideFromEdit = function(box)
    local p = ME.currentNotesProposal and ME.currentNotesProposal()
    local group = ME.editSourceGroup
    if not p or not group then return end
    local text = box:GetText() or ""
    text = text:match("^%s*(.-)%s*$") or text
    local GSS = AltArmy.GuildShareSettings
    local realm = groupPrefsRealm(group)
    if GSS and GSS.SetGroupOverrideName then
        GSS.SetGroupOverrideName(group.main, realm, text)
    end
    local applied = (GSS and GSS.GetGroupOverrideName
        and GSS.GetGroupOverrideName(group.main, realm)) or nil
    if applied == "" then applied = nil end
    if applied == p.overrideName and applied == group.overrideName then
        return
    end
    p.overrideName = applied
    group.overrideName = applied
    if ME.updateNotesWizardTitle then ME.updateNotesWizardTitle() end
end

ME.editOverrideEdit:SetScript("OnEnterPressed", function(box)
    ME.applyEditOverrideFromEdit(box)
    box:ClearFocus()
end)
ME.editOverrideEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
ME.editOverrideEdit:SetScript("OnTextChanged", function(box)
    if Theme.UpdateEditBoxPlaceholderVisibility then
        Theme.UpdateEditBoxPlaceholderVisibility(box)
    end
    ME.applyEditOverrideFromEdit(box)
end)
ME.editOverrideEdit:SetScript("OnEditFocusLost", function(box)
    ME.applyEditOverrideFromEdit(box)
end)
ME.editOverrideResetBtn:SetScript("OnClick", function()
    if Theme.ClearEditBoxText then
        Theme.ClearEditBoxText(ME.editOverrideEdit)
    else
        ME.editOverrideEdit:SetText("")
        if ME.editOverrideEdit.ClearFocus then
            ME.editOverrideEdit:ClearFocus()
        end
    end
    ME.applyEditOverrideFromEdit(ME.editOverrideEdit)
end)

ME.anchorNotesWizardBody = function()
    if not ME.notesClip then return end
    ME.notesClip:ClearAllPoints()
    if ME.wizardMode == "edit" and ME.editOptions and ME.editOptions:IsShown() then
        ME.notesClip:SetPoint("TOPLEFT", ME.editOptions, "BOTTOMLEFT", 0, -8)
    else
        ME.notesClip:SetPoint("TOPLEFT", ME.notesWizard, "TOPLEFT", 0, 0)
    end
    -- Settings apply immediately: no Save/Cancel footer; use full height.
    if ME.wizardMode == "edit" then
        if ME.notesFooter then ME.notesFooter:Hide() end
        ME.notesClip:SetPoint("BOTTOMRIGHT", ME.notesWizard, "BOTTOMRIGHT", 0, 0)
    else
        if ME.notesFooter then ME.notesFooter:Show() end
        ME.notesClip:SetPoint("BOTTOMRIGHT", ME.notesFooter, "TOPRIGHT", 0, 0)
    end
end

ME.syncEditOptionsFromProposal = function()
    local p = ME.currentNotesProposal and ME.currentNotesProposal()
    if not p or not ME.editOptions then return end
    if ME.editPinRow and ME.editPinRow.check then
        ME.editPinRow.check:SetChecked(p.pinned and true or false)
    end
    local override = p.overrideName or ""
    if ME.editOverrideEdit:GetText() ~= override then
        if Theme.SetEditBoxText then
            Theme.SetEditBoxText(ME.editOverrideEdit, override)
        else
            ME.editOverrideEdit:SetText(override)
        end
    end
    if Theme.UpdateEditBoxPlaceholderVisibility then
        Theme.UpdateEditBoxPlaceholderVisibility(ME.editOverrideEdit)
    end
end

ME.notesClip = CreateFrame("Frame", nil, ME.notesWizard)
ME.notesClip:SetPoint("TOPLEFT", ME.notesWizard, "TOPLEFT", 0, 0)
ME.notesClip:SetPoint("BOTTOMRIGHT", ME.notesFooter, "TOPRIGHT", 0, 0)
if ME.notesClip.SetClipsChildren then
    ME.notesClip:SetClipsChildren(true)
end

ME.notesSlide = CreateFrame("Frame", nil, ME.notesClip)
ME.notesSlide:SetPoint("TOPLEFT", ME.notesClip, "TOPLEFT", 0, 0)
ME.notesSlide:SetPoint("BOTTOMRIGHT", ME.notesClip, "BOTTOMRIGHT", 0, 0)

ME.notesEmptyFS = ME.notesSlide:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
ME.notesEmptyFS:SetPoint("CENTER", ME.notesSlide, "CENTER", 0, 0)
ME.notesEmptyFS:SetWidth(420)
ME.notesEmptyFS:SetJustifyH("CENTER")
ME.notesEmptyFS:SetJustifyV("MIDDLE")
ME.notesEmptyFS:Hide()

-- Manual-create intro (above the character list). Hidden in notes/edit modes.
ME.notesManualDesc = CreateFrame("Frame", nil, ME.notesSlide)
ME.notesManualDesc:SetPoint("TOPLEFT", ME.notesSlide, "TOPLEFT", 0, 0)
ME.notesManualDesc:SetPoint("TOPRIGHT", ME.notesSlide, "TOPRIGHT", -ME.notesMembersGutter, 0)
ME.notesManualDesc:Hide()
ME.notesManualDescFS = ME.notesManualDesc:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
ME.notesManualDescFS:SetPoint("TOPLEFT", ME.notesManualDesc, "TOPLEFT", 0, 0)
ME.notesManualDescFS:SetPoint("TOPRIGHT", ME.notesManualDesc, "TOPRIGHT", 0, 0)
ME.notesManualDescFS:SetJustifyH("LEFT")
ME.notesManualDescFS:SetJustifyV("TOP")
ME.notesManualDescFS:SetWordWrap(true)
ME.notesManualDescFS:SetTextColor(1, 1, 1, 1)
ME.notesManualDescFS:SetText(
    (GTD.GetManualGroupCreateDescription and GTD.GetManualGroupCreateDescription())
        or "Manual groups let you link guildmates who don't use Alt Army as main and alts.")

-- Members table header + scrolling list. Add-character control lives at the bottom of the list.
ME.notesMembersHeader = CreateFrame("Frame", nil, ME.notesSlide)
ME.notesMembersHeader:SetPoint("TOPLEFT", ME.notesSlide, "TOPLEFT", 0, 0)
-- Inset by the members scrollbar gutter so headers line up with row columns.
ME.notesMembersHeader:SetPoint("TOPRIGHT", ME.notesSlide, "TOPRIGHT", -ME.notesMembersGutter, 0)
ME.notesMembersHeader:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
-- Keep a legacy alias so empty-state show/hide paths stay simple.
ME.notesMembersLabel = ME.notesMembersHeader

do
    local actionW = UI.NOTES_ACTION_COL_WIDTH
    local gap = UI.NOTES_COL_GAP
    local charLabel = ME.notesMembersHeader:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    charLabel:SetPoint("LEFT", ME.notesMembersHeader, "LEFT", 0, 0)
    charLabel:SetPoint("RIGHT", ME.notesMembersHeader, "CENTER", -gap / 2, 0)
    charLabel:SetJustifyH("LEFT")
    charLabel:SetWordWrap(false)
    charLabel:SetText("Characters in this group")
    ME.notesMembersCharHeader = charLabel

    local reasonLabel = ME.notesMembersHeader:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    reasonLabel:SetPoint("LEFT", ME.notesMembersHeader, "CENTER", gap / 2, 0)
    reasonLabel:SetPoint("RIGHT", ME.notesMembersHeader, "RIGHT", -(actionW + gap), 0)
    reasonLabel:SetJustifyH("LEFT")
    reasonLabel:SetWordWrap(false)
    reasonLabel:SetText("Reason for inclusion")
    ME.notesMembersReasonHeader = reasonLabel
end

ME.notesScrollHost = CreateFrame("Frame", nil, ME.notesSlide)
ME.notesScrollHost:SetPoint("TOPLEFT", ME.notesMembersHeader, "BOTTOMLEFT", 0, -4)
ME.notesScrollHost:SetPoint("BOTTOMRIGHT", ME.notesSlide, "BOTTOMRIGHT", 0, 0)

-- Anchor description / column headers / scroll host for notes, manual, and edit wizards.
-- Manual create: show intro copy; hide column headers while the group has no characters.
ME.anchorNotesMembersChrome = function(hasMembers)
    if not ME.notesMembersHeader or not ME.notesScrollHost then return end
    local isManual = ME.wizardMode == "manual"
    local showDesc = isManual and ME.notesManualDesc ~= nil
    local showHeaders = (not isManual) or (hasMembers and true or false)

    if ME.notesManualDesc then
        if showDesc then
            ME.notesManualDesc:ClearAllPoints()
            ME.notesManualDesc:SetPoint("TOPLEFT", ME.notesSlide, "TOPLEFT", 0, 0)
            ME.notesManualDesc:SetPoint("TOPRIGHT", ME.notesSlide, "TOPRIGHT",
                -ME.notesMembersGutter, 0)
            local width = ME.notesManualDesc:GetWidth() or 0
            if width < 1 and ME.notesSlide and ME.notesSlide.GetWidth then
                width = (ME.notesSlide:GetWidth() or 0) - (ME.notesMembersGutter or 0)
            end
            if width < 1 then width = 420 end
            ME.notesManualDescFS:SetWidth(width)
            local textH = (ME.notesManualDescFS.GetStringHeight
                and ME.notesManualDescFS:GetStringHeight()) or 28
            ME.notesManualDesc:SetHeight(math.max(12, textH))
            ME.notesManualDesc:Show()
        else
            ME.notesManualDesc:Hide()
        end
    end

    local topAnchor = ME.notesSlide
    local topRel = "TOPLEFT"
    local topY = 0
    if showDesc and ME.notesManualDesc and ME.notesManualDesc:IsShown() then
        topAnchor = ME.notesManualDesc
        topRel = "BOTTOMLEFT"
        topY = -8
    end

    ME.notesMembersHeader:ClearAllPoints()
    ME.notesScrollHost:ClearAllPoints()
    if showHeaders then
        ME.notesMembersHeader:SetPoint("TOPLEFT", topAnchor, topRel, 0, topY)
        if showDesc and ME.notesManualDesc and ME.notesManualDesc:IsShown() then
            ME.notesMembersHeader:SetPoint("TOPRIGHT", ME.notesManualDesc, "BOTTOMRIGHT", 0, topY)
        else
            ME.notesMembersHeader:SetPoint("TOPRIGHT", ME.notesSlide, "TOPRIGHT",
                -ME.notesMembersGutter, 0)
        end
        ME.notesMembersHeader:SetHeight(UI.LIST_COL_HEADER_HEIGHT)
        ME.notesMembersHeader:Show()
        ME.notesScrollHost:SetPoint("TOPLEFT", ME.notesMembersHeader, "BOTTOMLEFT", 0, -4)
    else
        ME.notesMembersHeader:Hide()
        ME.notesScrollHost:SetPoint("TOPLEFT", topAnchor, topRel, 0, topY)
    end
    ME.notesScrollHost:SetPoint("BOTTOMRIGHT", ME.notesSlide, "BOTTOMRIGHT", 0, 0)
end

ME.notesViewport = Theme.CreateVerticalScrollViewport({
    parent = ME.notesScrollHost,
    gutterEdge = ME.notesScrollHost,
    anchorTop = { "TOPLEFT", ME.notesScrollHost, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", ME.notesScrollHost, "BOTTOMRIGHT", -ME.notesMembersGutter, 0 },
    enableMouseWheel = true,
    valueStep = 24,
    scrollBarWidth = ME.notesScrollBarOpts.width,
    scrollBarGap = ME.notesScrollBarOpts.gap,
})
ME.notesMembersList = ME.notesViewport.child

ME.notesAddRowH = 22
ME.notesAddDockPad = 4

-- Add-character row: inline after members when the list fits; sticky at the host
-- bottom when it overflows (never use a 0-height dock as the scroll bottom anchor —
-- that collapses the viewport on some clients).
ME.notesAddRow = CreateFrame("Frame", nil, ME.notesMembersList)
ME.notesAddRow:SetHeight(ME.notesAddRowH)
ME.notesAddRow:Hide()

ME.notesAddBtn = CreateFrame("Button", nil, ME.notesAddRow, "UIPanelButtonTemplate")
ME.notesAddBtn:SetSize(120, 22)
ME.notesAddBtn:SetPoint("LEFT", ME.notesAddRow, "LEFT", 0, 0)
ME.notesAddBtn:SetText("Add character")
Theme.SkinButton(ME.notesAddBtn)

ME.notesAddCancelBtn = CreateFrame("Button", nil, ME.notesAddRow, "UIPanelButtonTemplate")
ME.notesAddCancelBtn:SetSize(70, 22)
-- Keep Cancel inside the characters column (left 50%) so it does not overlap Reason.
ME.notesAddCancelBtn:SetPoint("RIGHT", ME.notesAddRow, "CENTER", -UI.NOTES_COL_GAP / 2, 0)
ME.notesAddCancelBtn:SetText("Cancel")
Theme.SkinButton(ME.notesAddCancelBtn)
ME.notesAddCancelBtn:Hide()

ME.notesAddEdit = CreateFrame("EditBox", nil, ME.notesAddRow)
ME.notesAddEdit:SetPoint("LEFT", ME.notesAddRow, "LEFT", 0, 0)
ME.notesAddEdit:SetPoint("RIGHT", ME.notesAddCancelBtn, "LEFT", -8, 0)
ME.notesAddEdit:SetHeight(22)
ME.notesAddEdit:SetFontObject(Theme.FONTS.body)
ME.notesAddEdit:SetAutoFocus(false)
ME.notesAddEdit:SetTextInsets(6, 6, 0, 0)
Theme.ApplyInputTextures(ME.notesAddEdit)
if Theme.SetupEditBoxPlaceholder then
    Theme.SetupEditBoxPlaceholder(ME.notesAddEdit, "Type a guild member name")
end
ME.notesAddEdit:Hide()

ME.anchorNotesMembersScroll = function(bottomInset)
    local scroll = ME.notesViewport and ME.notesViewport.scroll
    if not scroll then return end
    bottomInset = bottomInset or 0
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", ME.notesScrollHost, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", ME.notesScrollHost, "BOTTOMRIGHT", -ME.notesMembersGutter, bottomInset)
end

ME.positionNotesAddRow = function(membersHeight)
    if not ME.notesAddRow or not ME.notesScrollHost then return end
    local addH = ME.notesAddRowH or 22
    local pad = ME.notesAddDockPad or 4
    local scroll = ME.notesViewport and ME.notesViewport.scroll
    -- Measure against the full host height (no sticky inset).
    ME.anchorNotesMembersScroll(0)
    if ME.notesViewport and ME.notesViewport.UpdateRange then
        ME.notesViewport.UpdateRange()
    end
    local viewH = (scroll and scroll.GetHeight and scroll:GetHeight()) or 0
    local needsSticky = viewH > 1 and (membersHeight + addH + pad) > (viewH + 0.5)

    ME.notesAddSticky = needsSticky and true or false
    if needsSticky then
        ME.anchorNotesMembersScroll(addH + pad)
        ME.notesAddRow:SetParent(ME.notesScrollHost)
        ME.notesAddRow:ClearAllPoints()
        ME.notesAddRow:SetPoint("BOTTOMLEFT", ME.notesScrollHost, "BOTTOMLEFT", 0, 0)
        ME.notesAddRow:SetPoint("BOTTOMRIGHT", ME.notesScrollHost, "BOTTOMRIGHT", -ME.notesMembersGutter, 0)
        ME.notesAddRow:SetHeight(addH)
        ME.notesMembersList:SetHeight(math.max(1, membersHeight))
        local hostLevel = ME.notesScrollHost:GetFrameLevel() or 0
        ME.notesAddRow:SetFrameLevel(hostLevel + 20)
    else
        ME.anchorNotesMembersScroll(0)
        ME.notesAddRow:SetParent(ME.notesMembersList)
        ME.notesAddRow:ClearAllPoints()
        ME.notesAddRow:SetPoint("TOPLEFT", ME.notesMembersList, "TOPLEFT", 0, -membersHeight)
        ME.notesAddRow:SetPoint("TOPRIGHT", ME.notesMembersList, "TOPRIGHT", 0, -membersHeight)
        ME.notesAddRow:SetHeight(addH)
        ME.notesMembersList:SetHeight(math.max(1, membersHeight + addH))
    end
    ME.notesAddRow:Show()
    if ME.updateNotesMembersScroll then
        ME.updateNotesMembersScroll()
    end
end

ME.showNotesAddInput = function()
    ME.notesAddBtn:Hide()
    ME.notesAddCancelBtn:Show()
    ME.notesAddEdit:Show()
    if Theme.ClearEditBoxText then
        Theme.ClearEditBoxText(ME.notesAddEdit)
    else
        ME.notesAddEdit:SetText("")
    end
    ME.notesAddEdit:SetFocus()
    -- Only scroll to the add row when it is inline in the list.
    if not ME.notesAddSticky
        and ME.notesViewport and ME.notesViewport.scroll and ME.notesViewport.SetOffset then
        local scroll = ME.notesViewport.scroll
        local maxScroll = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
        ME.notesViewport.SetOffset(maxScroll)
    end
end

ME.hideNotesAddInput = function()
    ME.hideManualSuggest()
    if ME.notesAddEdit:IsShown() then
        ME.notesAddEdit:ClearFocus()
    end
    if Theme.ClearEditBoxText then
        Theme.ClearEditBoxText(ME.notesAddEdit)
    else
        ME.notesAddEdit:SetText("")
    end
    ME.notesAddEdit:Hide()
    ME.notesAddCancelBtn:Hide()
    ME.notesAddBtn:Show()
end

ME.notesAddBtn:SetScript("OnClick", function()
    ME.showNotesAddInput()
end)
ME.notesAddCancelBtn:SetScript("OnClick", function()
    ME.hideNotesAddInput()
end)

ME.updateNotesWizardTitle = function()
    local isManual = ME.wizardMode == "manual"
    local isEdit = ME.wizardMode == "edit"
    local total = #ME.notesProposals
    local proposal = ME.notesProposals[ME.notesIndex]
    if isEdit then
        if ME.notesProgressFS then
            ME.notesProgressFS:SetText("")
            ME.notesProgressFS:Hide()
        end
        local group = ME.editSourceGroup
        local displayName
        if proposal and type(proposal.overrideName) == "string" and proposal.overrideName ~= "" then
            displayName = proposal.overrideName
        else
            -- Prefer preferred/main; ignore the group's persisted override when staging a clear.
            displayName = (group and (group.preferredName or group.main))
                or (proposal and proposal.main)
                or "?"
        end
        local classFile = group and group.classFile
        if not classFile and proposal and proposal.main then
            classFile = select(1, ME.rosterClassLevel(proposal.main))
        end
        local coloredName = formatName(displayName, classFile)
        local suffix = " settings"
        local t = Theme.COLORS and Theme.COLORS.title
        if t and CC and CC.formatHex then
            suffix = CC.formatHex(t[1], t[2], t[3], suffix)
        end
        ME.notesTitleFS:SetText(coloredName .. suffix)
        ME.notesTitleFS:SetTextColor(1, 1, 1, 1)
        return
    end
    if isManual then
        if ME.notesProgressFS then
            ME.notesProgressFS:SetText("")
            ME.notesProgressFS:Hide()
        end
        if not proposal or not proposal.main or proposal.main == "" then
            ME.notesTitleFS:SetText("New manual group")
            Theme.SetTitleColor(ME.notesTitleFS)
        else
            local groupName = proposal.displayName or proposal.main
            local classFile, _ = ME.rosterClassLevel(proposal.main)
            local coloredName = formatName(groupName, classFile)
            local prefix = "New group: "
            local t = Theme.COLORS and Theme.COLORS.title
            if t and CC and CC.formatHex then
                prefix = CC.formatHex(t[1], t[2], t[3], prefix)
            end
            ME.notesTitleFS:SetText(prefix .. coloredName)
            ME.notesTitleFS:SetTextColor(1, 1, 1, 1)
        end
        return
    end
    if total < 1 or not proposal then
        ME.notesTitleFS:SetText("Review note groupings")
        Theme.SetTitleColor(ME.notesTitleFS)
        if ME.notesProgressFS then
            ME.notesProgressFS:SetText("")
            ME.notesProgressFS:Hide()
        end
    else
        local groupName = proposal.displayName or proposal.main or "?"
        local classFile, _ = ME.rosterClassLevel(proposal.main)
        local coloredName = formatName(groupName, classFile)
        local prefix = "Suggested group: "
        local t = Theme.COLORS and Theme.COLORS.title
        if t and CC and CC.formatHex then
            prefix = CC.formatHex(t[1], t[2], t[3], prefix)
        end
        ME.notesTitleFS:SetText(prefix .. coloredName)
        -- White base so embedded class/title color codes render as authored.
        ME.notesTitleFS:SetTextColor(1, 1, 1, 1)
        if ME.notesProgressFS then
            ME.notesProgressFS:SetText(tostring(ME.notesIndex) .. " of " .. tostring(total))
            ME.notesProgressFS:Show()
            Theme.SetTitleColor(ME.notesProgressFS)
        end
    end
end

ME.updateNotesMembersScroll = function()
    if not ME.notesViewport or not ME.notesMembersList then return end
    local child = ME.notesMembersList
    local width = (ME.notesViewport.scroll and ME.notesViewport.scroll:GetWidth()) or child:GetWidth() or 1
    child:SetWidth(math.max(1, width))
    if ME.notesViewport.UpdateRange then
        ME.notesViewport.UpdateRange()
    end
end

--- Show/hide header Delete and retarget the title's right edge (delete vs progress).
ME.syncNotesHeaderActions = function()
    local isEdit = ME.wizardMode == "edit"
    local showDelete = false
    if isEdit and ME.notesDeleteBtn then
        local group = ME.editSourceGroup
        local GSS = AltArmy.GuildShareSettings
        local ownMain = GSS and GSS.GetMain and GSS.GetMain(groupPrefsRealm(group)) or nil
        local isOwn = GTD.IsOwnGroup and GTD.IsOwnGroup(group, ownMain)
        showDelete = not isOwn
        if showDelete then
            ME.notesDeleteBtn:Show()
            if not ME.deleteConfirmPending then
                ME.notesDeleteBtn:SetText("Delete local data")
            end
        else
            ME.notesDeleteBtn:Hide()
            ME.deleteConfirmPending = false
            ME.notesDeleteBtn:SetText("Delete local data")
        end
    elseif ME.notesDeleteBtn then
        ME.notesDeleteBtn:Hide()
        ME.deleteConfirmPending = false
        ME.notesDeleteBtn:SetText("Delete local data")
    end

    if ME.notesTitleFS then
        ME.notesTitleFS:ClearAllPoints()
        ME.notesTitleFS:SetPoint("LEFT", ME.notesBackBtn, "RIGHT", 8, 0)
        if showDelete then
            ME.notesTitleFS:SetPoint("RIGHT", ME.notesDeleteBtn, "LEFT", -12, 0)
        else
            ME.notesTitleFS:SetPoint("RIGHT", ME.notesProgressFS, "LEFT", -12, 0)
        end
    end
end

ME.layoutNotesFooterButtons = function()
    local isManual = ME.wizardMode == "manual"
    local isEdit = ME.wizardMode == "edit"
    if ME.syncNotesHeaderActions then
        ME.syncNotesHeaderActions()
    end
    if isEdit then
        -- Immediate-apply settings: no footer actions.
        ME.notesAcceptBtn:Hide()
        ME.notesSkipBtn:Hide()
        if ME.notesFooter then ME.notesFooter:Hide() end
        if ME.anchorNotesWizardBody then ME.anchorNotesWizardBody() end
        return
    end
    if ME.notesFooter then ME.notesFooter:Show() end
    local y = UI.FOOTER_BUTTON_Y or 0
    if isManual then
        ME.notesAcceptBtn:SetText("Create group")
        ME.notesSkipBtn:SetText("Cancel")
        ME.notesAcceptBtn:SetWidth(120)
        ME.notesSkipBtn:SetWidth(100)
    else
        ME.notesAcceptBtn:SetText("Accept group")
        ME.notesSkipBtn:SetText("Skip group")
        ME.notesAcceptBtn:SetWidth(120)
        ME.notesSkipBtn:SetWidth(100)
    end
    ME.notesAcceptBtn:Show()
    ME.notesSkipBtn:Show()
    local gap = 8
    local acceptW = ME.notesAcceptBtn:GetWidth() or 120
    local skipW = ME.notesSkipBtn:GetWidth() or 100
    local total = acceptW + gap + skipW
    ME.notesAcceptBtn:ClearAllPoints()
    ME.notesAcceptBtn:SetPoint("LEFT", ME.notesFooter, "CENTER", -total / 2, y)
    ME.notesSkipBtn:ClearAllPoints()
    ME.notesSkipBtn:SetPoint("LEFT", ME.notesAcceptBtn, "RIGHT", gap, 0)
end

ME.hideNotesMemberRowsFrom = function(index)
    for i = index, #ME.notesMemberRows do
        if ME.notesMemberRows[i] then ME.notesMemberRows[i]:Hide() end
    end
end

ME.currentNotesProposal = function()
    return ME.notesProposals[ME.notesIndex]
end

-- Accept enablement for notes/manual wizards (settings has no Accept/Save).
ME.syncNotesAcceptEnabled = function()
    if ME.wizardMode == "edit" then
        return
    end
    local proposal = ME.currentNotesProposal()
    local count = (GTD.CountNotesProposalCharacters and GTD.CountNotesProposalCharacters(proposal)) or 0
    if count > 1 then
        ME.notesAcceptBtn:Enable()
    else
        ME.notesAcceptBtn:Disable()
    end
end

ME.layoutNotesMembers = function()
    if ME.isEditingOwnGroup and ME.isEditingOwnGroup() then
        if ME.notesManualDesc then ME.notesManualDesc:Hide() end
        ME.notesMembersLabel:Hide()
        if ME.notesScrollHost then ME.notesScrollHost:Hide() end
        if ME.notesAddRow then ME.notesAddRow:Hide() end
        ME.hideNotesMemberRowsFrom(1)
        return
    end
    local proposal = ME.currentNotesProposal()
    local members = (proposal and proposal.members) or {}
    local knownMembers = (proposal and proposal.knownMembers) or {}
    local isManual = ME.wizardMode == "manual"
    local isEdit = ME.wizardMode == "edit"
    local displayRows = {}
    if isEdit then
        local order = proposal and proposal.order or {}
        local mainKey = proposal and proposal.main and GTD.NormalizeRosterName
            and GTD.NormalizeRosterName(proposal.main)
        local memberByKey = {}
        for _, member in ipairs(members) do
            if member and member.name then
                local k = GTD.NormalizeRosterName and GTD.NormalizeRosterName(member.name)
                if k then memberByKey[k] = member end
            end
        end
        for _, name in ipairs(order) do
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
            local isMain = mainKey and key == mainKey
            local member = memberByKey[key]
            if isMain then
                displayRows[#displayRows + 1] = {
                    name = name,
                    locked = true,
                    isMain = true,
                    reasonKind = (proposal and proposal.mainReasonKind) or "main",
                    showMainStar = proposal and proposal.mainDeclared and true or false,
                }
            else
                local removable = member and (member.removable or member.addedManually
                    or member.reasonKind == "manual" or member.reasonKind == "note"
                    or member.reasonKind == "conflict")
                displayRows[#displayRows + 1] = {
                    name = name,
                    locked = not removable,
                    member = member or { name = name, removable = true, reasonKind = "manual",
                        addedManually = true },
                    reasonKind = (member and member.reasonKind) or "manual",
                    origin = member and member.origin,
                    addedManually = removable and true or false,
                }
            end
        end
    elseif isManual then
        -- Stable add-order; changing main must not reshuffle rows.
        local order = (GTD.ManualProposalDisplayOrder and GTD.ManualProposalDisplayOrder(proposal)) or {}
        local mainKey = proposal and proposal.main and GTD.NormalizeRosterName
            and GTD.NormalizeRosterName(proposal.main)
        local memberByKey = {}
        for _, member in ipairs(members) do
            if member and member.name then
                local k = GTD.NormalizeRosterName and GTD.NormalizeRosterName(member.name)
                if k then memberByKey[k] = member end
            end
        end
        for _, name in ipairs(order) do
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
            local isMain = mainKey and key == mainKey
            displayRows[#displayRows + 1] = {
                name = name,
                locked = false,
                isMain = isMain and true or false,
                addedManually = true,
                member = (not isMain) and (memberByKey[key] or { name = name, addedManually = true }) or nil,
            }
        end
    else
        if proposal and proposal.main and proposal.main ~= "" then
            displayRows[#displayRows + 1] = {
                name = proposal.main,
                locked = true,
                isMain = true,
                showMainStar = proposal.mainDeclared and true or false,
            }
        end
        for _, member in ipairs(members) do
            if member and member.name and not member.addedManually
                and (not proposal
                    or GTD.NormalizeRosterName(member.name)
                        ~= GTD.NormalizeRosterName(proposal.main)) then
                displayRows[#displayRows + 1] = {
                    name = member.name,
                    locked = false,
                    member = member,
                    noteText = member.noteText,
                    alreadyMapped = member.alreadyMapped,
                    origin = member.origin,
                }
            end
        end
        for _, known in ipairs(knownMembers) do
            if known and known.name then
                displayRows[#displayRows + 1] = {
                    name = known.name,
                    locked = true,
                    isKnownShared = true,
                }
            end
        end
        -- Manually added characters stay at the bottom (above the Add control), in add order.
        for _, member in ipairs(members) do
            if member and member.addedManually and member.name
                and (not proposal
                    or GTD.NormalizeRosterName(member.name)
                        ~= GTD.NormalizeRosterName(proposal.main)) then
                displayRows[#displayRows + 1] = {
                    name = member.name,
                    locked = false,
                    member = member,
                    noteText = member.noteText,
                    alreadyMapped = member.alreadyMapped,
                    origin = member.origin,
                    addedManually = true,
                }
            end
        end
    end
    if ME.anchorNotesMembersChrome then
        ME.anchorNotesMembersChrome(#displayRows > 0)
    end
    local y = 0
    local removeW = UI.NOTES_ACTION_COL_WIDTH
    local mainBtnW = UI.NOTES_MAIN_BTN_WIDTH or 50
    local actionBtnGap = UI.NOTES_ACTION_BTN_GAP or 4
    -- Manual mode reserves room for Main + Remove on non-main rows.
    local actionColW = removeW
    if isManual then
        actionColW = removeW + actionBtnGap + mainBtnW
    end
    local colGap = UI.NOTES_COL_GAP
    local textTopPad = 2
    local lineGap = 2
    local nameLineH = 14
    local subLineH = 14
    local bottomPad = 2
    if ME.notesMembersReasonHeader then
        ME.notesMembersReasonHeader:ClearAllPoints()
        ME.notesMembersReasonHeader:SetPoint("LEFT", ME.notesMembersHeader, "CENTER", colGap / 2, 0)
        ME.notesMembersReasonHeader:SetPoint("RIGHT", ME.notesMembersHeader, "RIGHT", -(actionColW + colGap), 0)
    end
    local rosterInfo = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or {}
    for i, entry in ipairs(displayRows) do
        local row = ME.notesMemberRows[i]
        if not row then
            row = CreateFrame("Frame", nil, ME.notesMembersList)
            local nameFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            row.nameFS = nameFS
            local noteFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            noteFS:SetJustifyH("LEFT")
            noteFS:SetWordWrap(false)
            row.noteFS = noteFS
            local reasonFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            reasonFS:SetJustifyH("LEFT")
            reasonFS:SetWordWrap(false)
            row.reasonFS = reasonFS
            local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            removeBtn:SetSize(removeW, 22)
            removeBtn:SetText("Remove")
            Theme.SkinButton(removeBtn)
            row.removeBtn = removeBtn
            local setMainBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            setMainBtn:SetSize(mainBtnW, 22)
            setMainBtn:SetText("Main")
            Theme.SkinButton(setMainBtn)
            setMainBtn:Hide()
            row.setMainBtn = setMainBtn
            ME.notesMemberRows[i] = row
        end
        if not row.setMainBtn then
            local setMainBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            setMainBtn:SetSize(mainBtnW, 22)
            setMainBtn:SetText("Main")
            Theme.SkinButton(setMainBtn)
            setMainBtn:Hide()
            row.setMainBtn = setMainBtn
        end
        if not row.mainStarIcon then
            local mainStarIcon = CreateFrame("Frame", nil, row)
            mainStarIcon:SetSize(UI.MAIN_STAR_ICON_SIZE, nameLineH)
            mainStarIcon:EnableMouse(true)
            mainStarIcon:Hide()
            local starTex = mainStarIcon:CreateTexture(nil, "ARTWORK")
            starTex:SetSize(UI.MAIN_STAR_ICON_SIZE, UI.MAIN_STAR_ICON_SIZE)
            starTex:SetPoint("CENTER", mainStarIcon, "CENTER", 0, 0)
            starTex:SetTexture(UI.MAIN_STAR_TEXTURE)
            mainStarIcon.tex = starTex
            mainStarIcon:SetScript("OnEnter", function(self)
                if not self.showMainStarTooltip then return end
                if GTD.PresentMainStarTooltip then
                    GTD.PresentMainStarTooltip(self, "ANCHOR_BOTTOMLEFT", {
                        name = self.starName,
                        classFile = self.starClassFile,
                        isOwn = self.starIsOwn,
                        showConfigureHint = false,
                    })
                end
            end)
            mainStarIcon:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            row.mainStarIcon = mainStarIcon
        end
        if row.attrFS then
            row.attrFS:Hide()
        end
        if row.stripeBg then
            row.stripeBg:Hide()
        end
        if not row.reasonFS then
            local reasonFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
            reasonFS:SetJustifyH("LEFT")
            reasonFS:SetWordWrap(false)
            row.reasonFS = reasonFS
        end
        local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(entry.name)
        local info = key and rosterInfo[key] or nil
        -- Prefer the scan/provenance note when present; otherwise show the live guild note.
        local noteText = entry.noteText
        if (not noteText or noteText == "") and info and info.note and info.note ~= "" then
            noteText = info.note
        end
        local noteLine = (noteText and GTD.FormatNotesWizardMemberNote
            and GTD.FormatNotesWizardMemberNote(noteText)) or ""
        local hasNoteLine = noteLine ~= ""
        local rowH = textTopPad + nameLineH + bottomPad
        if hasNoteLine then
            rowH = rowH + lineGap + subLineH
        end
        rowH = math.max(rowH, 22 + bottomPad)
        row:SetHeight(rowH)

        local reasonKind = entry.reasonKind
            or (GTD.ClassifyNotesWizardInclusionReason
                and GTD.ClassifyNotesWizardInclusionReason({
                    isMain = entry.isMain,
                    mainFromShared = proposal and proposal.mainFromShared,
                    isKnownShared = entry.isKnownShared,
                    noteText = entry.noteText,
                    alreadyMapped = entry.alreadyMapped,
                    origin = entry.origin,
                })) or "manual"
        local reasonText
        if isManual then
            -- Manual create: every character was added by the user.
            reasonText = (GTD.NotesWizardInclusionReasonLabel
                and GTD.NotesWizardInclusionReasonLabel("manual")) or "Manually added"
        else
            reasonText = (GTD.NotesWizardInclusionReasonLabel
                and GTD.NotesWizardInclusionReasonLabel(reasonKind)) or ""
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ME.notesMembersList, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", ME.notesMembersList, "TOPRIGHT", 0, -y)

        row.removeBtn:ClearAllPoints()
        row.removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.removeBtn:SetSize(removeW, 22)

        local showSetMain = isManual and not entry.isMain and not entry.locked
        if row.setMainBtn then
            row.setMainBtn:ClearAllPoints()
            row.setMainBtn:SetSize(mainBtnW, 22)
            row.setMainBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -actionBtnGap, 0)
            if showSetMain then
                row.setMainBtn:Show()
                do
                    local setMainName = entry.name
                    row.setMainBtn:SetScript("OnClick", function()
                        local p = ME.currentNotesProposal()
                        if not p or not GTD.SetManualProposalMain then return end
                        if GTD.SetManualProposalMain(p, setMainName) then
                            if ME.updateNotesWizardTitle then ME.updateNotesWizardTitle() end
                            ME.layoutNotesMembers()
                        end
                    end)
                end
            else
                row.setMainBtn:Hide()
                row.setMainBtn:SetScript("OnClick", nil)
            end
        end

        -- Characters column = left 50%; reason fills from center to the actions column.
        -- Star only when this character explicitly set themselves as main via Alt Army.
        local showMainStar = entry.showMainStar and true or false
        if row.mainStarIcon then
            if showMainStar then
                local GSS = AltArmy.GuildShareSettings
                local ownMain = GSS and GSS.GetMain and GSS.GetMain(currentRealm()) or nil
                local mainKey = proposal and proposal.main and GTD.NormalizeRosterName
                    and GTD.NormalizeRosterName(proposal.main)
                local ownKey = ownMain and GTD.NormalizeRosterName and GTD.NormalizeRosterName(ownMain)
                row.mainStarIcon.starName = entry.name
                row.mainStarIcon.starClassFile = info and info.classFile
                row.mainStarIcon.starIsOwn = (mainKey and ownKey and mainKey == ownKey) and true or false
                row.mainStarIcon.showMainStarTooltip = true
                row.mainStarIcon:ClearAllPoints()
                row.mainStarIcon:SetSize(UI.MAIN_STAR_ICON_SIZE, nameLineH)
                row.mainStarIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -textTopPad)
                row.mainStarIcon:Show()
            else
                row.mainStarIcon.showMainStarTooltip = false
                row.mainStarIcon:Hide()
            end
        end

        row.nameFS:ClearAllPoints()
        if showMainStar and row.mainStarIcon then
            row.nameFS:SetPoint("TOPLEFT", row.mainStarIcon, "TOPRIGHT", UI.MAIN_STAR_ICON_GAP, 0)
        else
            row.nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -textTopPad)
        end
        row.nameFS:SetPoint("TOPRIGHT", row, "TOP", -colGap / 2, -textTopPad)
        row.nameFS:SetHeight(nameLineH)
        row.nameFS:SetText((GTD.FormatNotesWizardMemberName
            and GTD.FormatNotesWizardMemberName(
                entry.name, info and info.classFile, info and info.level, formatName))
            or formatName(entry.name, info and info.classFile))

        row.reasonFS:ClearAllPoints()
        row.reasonFS:SetPoint("LEFT", row, "CENTER", colGap / 2, 0)
        row.reasonFS:SetPoint("RIGHT", row, "RIGHT", -(actionColW + colGap), 0)
        row.reasonFS:SetHeight(nameLineH)
        row.reasonFS:SetText(reasonText)
        row.reasonFS:Show()

        if hasNoteLine then
            row.noteFS:ClearAllPoints()
            -- Note stays flush left; only the name is indented for the star.
            row.noteFS:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(textTopPad + nameLineH + lineGap))
            row.noteFS:SetPoint("TOPRIGHT", row, "TOP", -colGap / 2, 0)
            row.noteFS:SetHeight(subLineH)
            row.noteFS:SetText(noteLine)
            row.noteFS:Show()
        else
            row.noteFS:SetText("")
            row.noteFS:Hide()
        end

        if entry.locked then
            row.removeBtn:Hide()
            row.removeBtn:SetScript("OnClick", nil)
        else
            row.removeBtn:Show()
            do
                local mem = entry.member
                local removeName = entry.name
                row.removeBtn:SetScript("OnClick", function()
                    local p = ME.currentNotesProposal()
                    if not p then return end
                    if ME.wizardMode == "manual" then
                        if GTD.RemoveManualProposalMember then
                            GTD.RemoveManualProposalMember(p, removeName)
                        end
                        if ME.updateNotesWizardTitle then ME.updateNotesWizardTitle() end
                        ME.layoutNotesMembers()
                        return
                    end
                    if ME.wizardMode == "edit" then
                        local group = ME.editSourceGroup
                        local GMG = AltArmy.GuildManualGroups
                        local realm = group and groupPrefsRealm(group)
                        if GMG and GMG.RemoveMapping and removeName then
                            GMG.RemoveMapping(removeName, realm)
                        end
                        local removeKey = GTD.NormalizeRosterName and GTD.NormalizeRosterName(removeName)
                        if p.members then
                            for j = #p.members, 1, -1 do
                                local m = p.members[j]
                                if m and GTD.NormalizeRosterName(m.name) == removeKey then
                                    table.remove(p.members, j)
                                    break
                                end
                            end
                        end
                        if p.order then
                            for j = #p.order, 1, -1 do
                                if GTD.NormalizeRosterName(p.order[j]) == removeKey then
                                    table.remove(p.order, j)
                                    break
                                end
                            end
                        end
                        if group and group.members and removeKey then
                            for j = #group.members, 1, -1 do
                                local m = group.members[j]
                                if m and GTD.NormalizeRosterName(m.name) == removeKey then
                                    table.remove(group.members, j)
                                    break
                                end
                            end
                        end
                        ME.layoutNotesMembers()
                        return
                    end
                    if not mem then return end
                    for j, m in ipairs(p.members) do
                        if m == mem or m.name == mem.name then
                            if m.alreadyMapped and m.name then
                                p.removedMappedNames = p.removedMappedNames or {}
                                p.removedMappedNames[#p.removedMappedNames + 1] = m.name
                            end
                            table.remove(p.members, j)
                            break
                        end
                    end
                    ME.layoutNotesMembers()
                end)
            end
        end
        row:Show()
        y = y + rowH + 4
    end
    ME.hideNotesMemberRowsFrom(#displayRows + 1)

    if ME.positionNotesAddRow then
        ME.positionNotesAddRow(y)
    elseif ME.notesAddRow then
        ME.notesAddRow:ClearAllPoints()
        ME.notesAddRow:SetPoint("TOPLEFT", ME.notesMembersList, "TOPLEFT", 0, -y)
        ME.notesAddRow:SetPoint("TOPRIGHT", ME.notesMembersList, "TOPRIGHT", 0, -y)
        ME.notesAddRow:SetHeight(22)
        ME.notesAddRow:Show()
        ME.notesMembersList:SetHeight(math.max(1, y + 22))
        if ME.updateNotesMembersScroll then
            ME.updateNotesMembersScroll()
        end
    end
    if ME.syncNotesAcceptEnabled then
        ME.syncNotesAcceptEnabled()
    end
    if ME.updateNotesWizardTitle then
        ME.updateNotesWizardTitle()
    end
end

ME.isEditingOwnGroup = function()
    if ME.wizardMode ~= "edit" or not ME.editSourceGroup then return false end
    local GSS = AltArmy.GuildShareSettings
    local ownMain = GSS and GSS.GetMain and GSS.GetMain(groupPrefsRealm(ME.editSourceGroup)) or nil
    return GTD.IsOwnGroup and GTD.IsOwnGroup(ME.editSourceGroup, ownMain) and true or false
end

ME.fillNotesProposalForm = function()
    local proposal = ME.currentNotesProposal()
    if not proposal then
        if ME.notesManualDesc then ME.notesManualDesc:Hide() end
        ME.notesMembersLabel:Hide()
        if ME.notesAddRow then ME.notesAddRow:Hide() end
        ME.notesAcceptBtn:Hide()
        ME.notesSkipBtn:Hide()
        if ME.notesDeleteBtn then ME.notesDeleteBtn:Hide() end
        if ME.editOptions then ME.editOptions:Hide() end
        if ME.anchorNotesWizardBody then ME.anchorNotesWizardBody() end
        if ME.notesScrollHost then ME.notesScrollHost:Hide() end
        ME.notesEmptyFS:SetText("No new groupings found from guild notes.")
        ME.notesEmptyFS:Show()
        if ME.updateNotesWizardTitle then ME.updateNotesWizardTitle() end
        return
    end
    ME.notesEmptyFS:Hide()
    ME.hideNotesAddInput()
    if ME.wizardMode == "edit" then
        if ME.editOptions then ME.editOptions:Show() end
        if ME.syncEditOptionsFromProposal then ME.syncEditOptionsFromProposal() end
    else
        if ME.editOptions then ME.editOptions:Hide() end
    end
    if ME.anchorNotesWizardBody then ME.anchorNotesWizardBody() end
    ME.layoutNotesFooterButtons()
    if ME.updateNotesWizardTitle then ME.updateNotesWizardTitle() end
    -- Own-group settings: pin/override only — no member table or add control.
    if ME.isEditingOwnGroup and ME.isEditingOwnGroup() then
        if ME.notesManualDesc then ME.notesManualDesc:Hide() end
        ME.notesMembersLabel:Hide()
        if ME.notesScrollHost then ME.notesScrollHost:Hide() end
        if ME.notesAddRow then ME.notesAddRow:Hide() end
        if ME.hideNotesMemberRowsFrom then ME.hideNotesMemberRowsFrom(1) end
        return
    end
    if ME.notesScrollHost then ME.notesScrollHost:Show() end
    -- Header/description visibility is owned by layoutNotesMembers via anchorNotesMembersChrome.
    if ME.notesViewport and ME.notesViewport.SetOffset then
        ME.notesViewport.SetOffset(0)
    end
    ME.layoutNotesMembers()
end

ME.deleteEditedGroup = function()
    local group = ME.editSourceGroup
    if not group then return end
    local main = group.main
    local realm = groupPrefsRealm(group)
    local displayName = (GTD.ResolveGroupDisplayName and GTD.ResolveGroupDisplayName(group))
        or main or "?"
    local classFile = group.classFile
    if (not classFile or classFile == "") and main and ME.rosterClassLevel then
        classFile = select(1, ME.rosterClassLevel(main))
    end
    local GSD = AltArmy.GuildShareData
    local GSS = AltArmy.GuildShareSettings
    local GMG = AltArmy.GuildManualGroups
    if GSD and GSD.RemoveGroup then
        GSD.RemoveGroup(main, realm)
    end
    if GMG and GMG.RemoveGroup then
        GMG.RemoveGroup(main, realm)
    end
    if GSS and GSS.ClearGroupUiPrefs then
        GSS.ClearGroupUiPrefs(main, realm)
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(
            "Local data for " .. formatName(displayName, classFile) .. " deleted.")
    end
    ME.closeNotesWizard(false)
    local Comm = AltArmy.GuildShareComm
    if Comm and Comm.NotifyDataChanged then
        Comm.NotifyDataChanged()
    elseif refresh then
        refresh()
    end
end

ME.acceptCurrentNotesProposal = function()
    local proposal = ME.currentNotesProposal()
    if not proposal then return end
    local GMG = AltArmy.GuildManualGroups
    local guild = activeGuild()
    local realm = currentRealm()
    if not GMG or not guild then return end
    -- Group display uses the default name (main character, or shared preferred name
    -- when EnrichProposalsWithSharedData already set proposal.displayName).
    if GMG.ApplyProposal then
        local origin = (ME.wizardMode == "manual") and "user" or "note"
        GMG.ApplyProposal(proposal, realm, guild, function(name)
            return ME.rosterClassLevel(name)
        end, { origin = origin })
    end
end

ME.advanceNotesWizard = function(accepted)
    local function closeWithSlide()
        if ME.slideSwap then
            ME.slideSwap(function() ME.closeNotesWizard(true) end)
        else
            ME.closeNotesWizard(true)
        end
    end
    if ME.wizardMode == "edit" then
        -- Settings apply immediately; footer actions are unused.
        closeWithSlide()
        return
    end
    if accepted then
        ME.acceptCurrentNotesProposal()
    end
    ME.notesIndex = ME.notesIndex + 1
    if ME.notesIndex > #ME.notesProposals then
        -- Same back-slide as notesBackBtn (manual Cancel / finished scan).
        closeWithSlide()
        return
    end
    ME.fillNotesProposalForm()
end

ME.closeNotesWizard = function(refreshAfter)
    ME.notesWizardActive = false
    ME.wizardMode = nil
    ME.notesProposals = {}
    ME.notesIndex = 1
    ME.editSourceGroup = nil
    ME.deleteConfirmPending = false
    ME.notesWizard:Hide()
    ME.notesBackBtn:Hide()
    ME.notesTitleFS:Hide()
    if ME.notesProgressFS then ME.notesProgressFS:Hide() end
    if ME.editOptions then ME.editOptions:Hide() end
    if ME.notesDeleteBtn then
        ME.notesDeleteBtn:Hide()
        ME.notesDeleteBtn:SetText("Delete local data")
    end
    ME.hideManualSuggest()
    if showGuildList then showGuildList() end
    if refreshAfter and refresh then
        refresh()
    elseif ME.syncListFooter then
        ME.syncListFooter()
    end
end

ME.showNotesWizardChrome = function()
    guildNameText:Hide()
    guildBackBtn:Hide()
    searchEdit:Hide()
    tabardFrame:Hide()
    backBtn:Hide()
    recipeTitleFS:Hide()
    recipeSearchEdit:Hide()
    whisperBtn:Hide()
    ME.notesBackBtn:Show()
    if ME.syncNotesHeaderActions then
        ME.syncNotesHeaderActions()
    end
    if ME.updateNotesWizardTitle then
        ME.updateNotesWizardTitle()
    else
        ME.notesTitleFS:SetText("Review note groupings")
        Theme.SetTitleColor(ME.notesTitleFS)
    end
    ME.notesTitleFS:Show()
    if ME.wizardMode ~= "edit"
        and ME.notesProgressFS and ME.notesProgressFS:GetText() ~= "" then
        ME.notesProgressFS:Show()
    elseif ME.notesProgressFS then
        ME.notesProgressFS:Hide()
    end
end

ME.openScanReview = function()
    local GNP = AltArmy.GuildNoteAltParser
    local GMG = AltArmy.GuildManualGroups
    local GSD = AltArmy.GuildShareData
    if not GNP then return end
    local rosterEntries = GNP.BuildRosterNoteEntries and GNP.BuildRosterNoteEntries() or {}
    local existing = {}
    local guild = activeGuild()
    if GMG and GMG.GetMappingsForGuild and guild then
        for _, m in ipairs(GMG.GetMappingsForGuild(guild)) do
            existing[m.name] = m
        end
    end
    local storedChars = {}
    if GSD and GSD.GetGuildMembers and guild then
        for _, entry in ipairs(GSD.GetGuildMembers(guild)) do
            -- A character read by link shared nothing about its group: its note may still say.
            if entry and entry.name and not entry.linkOnly then
                storedChars[entry.name] = entry
            end
        end
    end
    for _, entry in ipairs(ME.currentDisplayMembers()) do
        if entry and entry.source == "local" and entry.name then
            storedChars[entry.name] = entry
        end
    end
    local suggestions = GNP.ScanRoster(rosterEntries, existing, storedChars) or {}
    local sharedEntries = {}
    for _, entry in pairs(storedChars) do
        if entry and type(entry) == "table" and entry.name and entry.main then
            sharedEntries[#sharedEntries + 1] = entry
        end
    end
    local proposals = (GNP.GroupSuggestionsByMain
        and GNP.GroupSuggestionsByMain(suggestions, existing, sharedEntries)) or {}
    if GNP.EnrichProposalsWithSharedData then
        proposals = GNP.EnrichProposalsWithSharedData(proposals, sharedEntries)
    end
    -- Never propose groupings under (or including) the player's own characters —
    -- a guild note matching the player's main/alt is a false positive.
    local ownNames = ME.collectOwnCharacterNames and ME.collectOwnCharacterNames() or {}
    if GNP.FilterProposalsExcludingNames then
        proposals = GNP.FilterProposalsExcludingNames(proposals, ownNames)
    end
    ME.notesProposals = proposals
    ME.notesIndex = 1
    ME.notesWizardActive = true
    ME.wizardMode = "notes"
    ME.editSourceGroup = nil
    selectedCharacter = nil
    selectedCharacterKey = nil
    -- Only hide the sliding page frame; child Hide() would leave an empty listBody
    -- when SlideTransition re-Shows it for the outgoing animation.
    if ME.listBody then ME.listBody:Hide() end
    if ME.updateListHeaderFade then
        ME.updateListHeaderFade()
    end
    ME.showNotesWizardChrome()
    ME.notesWizard:Show()
    ME.fillNotesProposalForm()
end

ME.openManualCreate = function()
    ME.notesProposals = { { main = nil, members = {}, order = {}, manual = true } }
    ME.notesIndex = 1
    ME.notesWizardActive = true
    ME.wizardMode = "manual"
    ME.editSourceGroup = nil
    selectedCharacter = nil
    selectedCharacterKey = nil
    if ME.listBody then ME.listBody:Hide() end
    if ME.updateListHeaderFade then
        ME.updateListHeaderFade()
    end
    ME.showNotesWizardChrome()
    ME.notesWizard:Show()
    ME.fillNotesProposalForm()
end

ME.openGroupEdit = function(group)
    if not group then return end
    -- Toggle-close when re-clicking the same group's gear while editor is open.
    if ME.notesWizardActive and ME.wizardMode == "edit" and ME.editSourceGroup
        and ME.editSourceGroup.main == group.main then
        ME.closeNotesWizard(true)
        return
    end
    local proposal = GTD.BuildGroupEditProposal and GTD.BuildGroupEditProposal(group)
    if not proposal then return end
    ME.notesProposals = { proposal }
    ME.notesIndex = 1
    ME.notesWizardActive = true
    ME.wizardMode = "edit"
    ME.editSourceGroup = group
    ME.deleteConfirmPending = false
    selectedCharacter = nil
    selectedCharacterKey = nil
    if ME.listBody then ME.listBody:Hide() end
    if ME.updateListHeaderFade then
        ME.updateListHeaderFade()
    end
    ME.showNotesWizardChrome()
    ME.notesWizard:Show()
    ME.fillNotesProposalForm()
end

ME.notesBackBtn:SetScript("OnClick", function()
    if ME.slideSwap then
        ME.slideSwap(function() ME.closeNotesWizard(true) end)
    else
        ME.closeNotesWizard(true)
    end
end)
ME.notesAcceptBtn:SetScript("OnClick", function()
    if ME.notesAcceptBtn.IsEnabled and not ME.notesAcceptBtn:IsEnabled() then
        return
    end
    ME.advanceNotesWizard(true)
end)
ME.notesSkipBtn:SetScript("OnClick", function()
    ME.advanceNotesWizard(false)
end)
ME.notesDeleteBtn:SetScript("OnClick", function(self)
    if ME.wizardMode ~= "edit" then return end
    if ME.deleteConfirmPending then
        ME.deleteConfirmPending = false
        ME.deleteEditedGroup()
    else
        ME.deleteConfirmPending = true
        self:SetText("Really delete?")
    end
end)

--- Normalized-name set of the player's configured main plus local account characters.
--- Used to keep the notes wizard from proposing (or manually adding) own characters.
ME.collectOwnCharacterNames = function()
    local set = {}
    local GSS = AltArmy.GuildShareSettings
    local ownMain = GSS and GSS.GetMain and GSS.GetMain(currentRealm()) or nil
    if type(ownMain) == "string" and ownMain ~= "" then
        local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(ownMain)
        if key then set[key] = true end
    end
    for _, entry in ipairs(ME.currentDisplayMembers()) do
        if entry and entry.source == "local" and entry.name then
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(entry.name)
            if key then set[key] = true end
        end
    end
    return set
end

--- Occupied names for the wizard add-character autocomplete.
--- Values are reason strings or `{ groupName, classFile }` so the suggest list can
--- explain why a match cannot be selected.
ME.wizardOccupiedNames = function()
    local function proposalGroupReason(proposal)
        if not proposal then return { groupName = "?" } end
        local groupName = proposal.overrideName
        if type(groupName) ~= "string" or groupName == "" then
            groupName = proposal.displayName
        end
        if type(groupName) ~= "string" or groupName == "" then
            groupName = proposal.main
        end
        if type(groupName) ~= "string" or groupName == "" then
            groupName = "?"
        end
        local classFile
        if proposal.main and ME.rosterClassLevel then
            classFile = ME.rosterClassLevel(proposal.main)
        end
        return { groupName = groupName, classFile = classFile }
    end

    if ME.wizardMode == "manual" or ME.wizardMode == "edit" then
        local occupied = (GTD.BuildOccupiedGroupReasons
            and GTD.BuildOccupiedGroupReasons(ME.currentDisplayMembers(), function(group)
                local GSS = AltArmy.GuildShareSettings
                if not GSS or not GSS.GetGroupOverrideName then return nil end
                return GSS.GetGroupOverrideName(group.main, groupPrefsRealm(group))
            end)) or {}
        local proposal = ME.currentNotesProposal()
        if proposal then
            local reason = proposalGroupReason(proposal)
            if proposal.main and proposal.main ~= "" then
                local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(proposal.main)
                if key then occupied[key] = reason end
            end
            for _, member in ipairs(proposal.members or {}) do
                if member and member.name then
                    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(member.name)
                    if key then occupied[key] = reason end
                end
            end
            for _, name in ipairs(proposal.order or {}) do
                local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
                if key then occupied[key] = reason end
            end
        end
        return occupied
    end
    local occupied = {}
    for _, proposal in ipairs(ME.notesProposals or {}) do
        local reason = proposalGroupReason(proposal)
        if proposal.main and proposal.main ~= "" then
            local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(proposal.main)
            if key then occupied[key] = reason end
        end
        for _, member in ipairs(proposal.members or {}) do
            if member and member.name then
                local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(member.name)
                if key then occupied[key] = reason end
            end
        end
        for _, known in ipairs(proposal.knownMembers or {}) do
            if known and known.name then
                local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(known.name)
                if key then occupied[key] = reason end
            end
        end
    end
    for key, on in pairs(ME.collectOwnCharacterNames()) do
        if on then occupied[key] = "Your character" end
    end
    return occupied
end

ME.addWizardMember = function(name)
    local p = ME.currentNotesProposal()
    if not p or type(name) ~= "string" or name == "" then return false end
    local occupied = ME.wizardOccupiedNames()
    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(name)
    if key and occupied[key] then return false end
    if ME.wizardMode == "manual" then
        if not GTD.AddManualProposalMember or not GTD.AddManualProposalMember(p, name) then
            return false
        end
    elseif ME.wizardMode == "edit" then
        local group = ME.editSourceGroup
        local GMG = AltArmy.GuildManualGroups
        local guild = activeGuild()
        local realm = group and groupPrefsRealm(group)
        if not group or not group.main or not GMG or not guild then return false end
        local classFile, level = ME.rosterClassLevel(name)
        if GMG.AssignToGroup then
            GMG.AssignToGroup(name, realm, group.main, {
                guild = guild, origin = "user", classFile = classFile, level = level,
            })
        elseif GMG.SetMapping then
            GMG.SetMapping(name, realm, group.main, {
                guild = guild, origin = "user", classFile = classFile, level = level,
            })
        else
            return false
        end
        p.members = p.members or {}
        p.order = p.order or {}
        p.members[#p.members + 1] = {
            name = name, removable = true, reasonKind = "manual",
            addedManually = true, origin = "user",
        }
        p.order[#p.order + 1] = name
        group.members = group.members or {}
        group.members[#group.members + 1] = {
            name = name, main = group.main, source = "manual", origin = "user",
            classFile = classFile, level = level, realm = realm,
        }
    else
        p.members[#p.members + 1] = {
            name = name, noteText = nil, noteHash = nil, addedManually = true,
        }
    end
    ME.layoutNotesMembers()
    return true
end

ME.notesAddEdit:SetScript("OnTextChanged", function(box)
    if Theme.UpdateEditBoxPlaceholderVisibility then
        Theme.UpdateEditBoxPlaceholderVisibility(box)
    end
    if box:HasFocus() then
        local occupied = ME.wizardOccupiedNames()
        local matches = GTD.FilterRosterNamesForAdd
            and GTD.FilterRosterNamesForAdd(ME.currentRosterDisplayNames(), box:GetText() or "", occupied, {
                maxResults = ME.suggestMax,
                rosterInfo = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or {},
            }) or {}
        ME.showManualSuggest(box, matches, function(picked)
            if ME.addWizardMember(picked) then
                ME.hideNotesAddInput()
            end
        end)
    end
end)
ME.notesAddEdit:SetScript("OnEditFocusGained", function(box)
    box:GetScript("OnTextChanged")(box)
end)
ME.notesAddEdit:SetScript("OnEditFocusLost", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, ME.hideManualSuggest)
    else
        ME.hideManualSuggest()
    end
end)
ME.notesAddEdit:SetScript("OnEnterPressed", function(box)
    local text = box:GetText() or ""
    text = text:match("^%s*(.-)%s*$") or text
    ME.hideManualSuggest()
    local added = false
    if text ~= "" then
        local occupied = ME.wizardOccupiedNames()
        local rosterInfo = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or {}
        local matches = GTD.FilterRosterNamesForAdd
            and GTD.FilterRosterNamesForAdd(ME.currentRosterDisplayNames(), text, occupied, {
                rosterInfo = rosterInfo,
            }) or {}
        local selectable = {}
        for _, name in ipairs(matches) do
            local disabled = GTD.RosterAddDisabledReason
                and GTD.RosterAddDisabledReason(occupied, name)
            if not disabled then
                selectable[#selectable + 1] = name
            end
        end
        local pick = (#selectable == 1) and selectable[1] or nil
        if not pick and GTD.ResolveRosterName then
            pick = GTD.ResolveRosterName(text, rosterInfo)
            if pick and GTD.RosterAddDisabledReason
                and GTD.RosterAddDisabledReason(occupied, pick) then
                pick = nil
            end
        end
        if pick then
            added = ME.addWizardMember(pick) and true or false
        end
    end
    if added then
        ME.hideNotesAddInput()
    else
        if Theme.ClearEditBoxText then
            Theme.ClearEditBoxText(box)
        else
            box:SetText("")
        end
        box:ClearFocus()
        box:SetFocus()
    end
end)
ME.notesAddEdit:SetScript("OnEscapePressed", function()
    ME.hideNotesAddInput()
end)

-- No horizontal scroll bar on this list; pin above the footer (panel padding
-- already provides the bronze-border gutter — do not reserve an extra PAD strip).
local function anchorListViewportBelowColHeader()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", listColHeader, "BOTTOMLEFT", 0, -2)
    listViewport:SetPoint("BOTTOMRIGHT", ME.listFooter, "TOPRIGHT", 0, 0)
end
local function anchorListViewportBelowGuildHeader()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", ME.listBody, "TOPLEFT", 0, 0)
    listViewport:SetPoint("BOTTOMRIGHT", ME.listBody, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
end
anchorListViewportBelowColHeader()

local viewport = Theme.CreateVerticalScrollViewport({
    parent = listViewport,
    gutterEdge = listViewport,
    anchorTop = { "TOPLEFT", listViewport, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = UI.MAIN_ROW_HEIGHT,
    wheelStep = UI.MAIN_ROW_HEIGHT * 3,
})
local scrollChild = viewport.child

-- Gradient under the Name / Character Count / Online header when the list is scrolled.
listColHeader:SetFrameLevel((listView:GetFrameLevel() or 0) + 10)
local listHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = listColHeader,
    scrollFrame = viewport.scroll,
    scrollBar = viewport.scrollBar,
    headerBottomInset = 0,
})

local function updateListHeaderFade()
    if not listHeaderFade then
        return
    end
    if listColHeader:IsShown() then
        listHeaderFade:Update()
    elseif listHeaderFade.frame then
        listHeaderFade.frame:Hide()
    end
end
ME.updateListHeaderFade = updateListHeaderFade

viewport.OnScroll(updateListHeaderFade)

local function forwardWheel(_, delta)
    viewport.Wheel(delta)
end

-- Empty-state hint shown inside the list area (header stays visible).
local emptyText = listViewport:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
emptyText:SetPoint("TOP", listViewport, "TOP", 0, -40)
emptyText:SetWidth(360)
emptyText:SetJustifyH("CENTER")
emptyText:Hide()

-- Recipe detail body (below header / profession tabs).
local recipeBody = CreateFrame("Frame", nil, listView)
recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
recipeBody:Hide()

local recipeViewportFrame = CreateFrame("Frame", nil, recipeBody)
recipeViewportFrame:Hide()

local recipeColHeader = CreateFrame("Frame", nil, recipeBody)
recipeColHeader:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
recipeColHeader:SetPoint("TOPLEFT", recipeBody, "TOPLEFT", 0, 0)
recipeColHeader:SetPoint("TOPRIGHT", recipeBody, "TOPRIGHT", 0, 0)
recipeColHeader:Hide()

local RECIPE_HEADER_LABEL = { recipe = "Recipe", skill = "Skill" }
local recipeHeaderButtons = {}

local function updateRecipeHeaderSortIndicators()
    for key, btn in pairs(recipeHeaderButtons) do
        if btn.label then
            local base = RECIPE_HEADER_LABEL[key] or key
            Theme.SetSortHeaderLabel(btn.label, base, key == recipeSortKey, recipeSortAscending)
        end
    end
end

local function createRecipeHeaderButton(sortKey, anchorFn)
    local btn = CreateFrame("Button", nil, recipeColHeader)
    btn:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    anchorFn(btn)
    local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(UI.RECIPE_COL_HEADER_HEIGHT)
    label:SetJustifyH(sortKey == "skill" and "RIGHT" or "LEFT")
    btn.label = label
    Theme.BindInteractableHover(btn)
    local sortKeyForClick = sortKey
    btn:SetScript("OnClick", function()
        if recipeSortKey == sortKeyForClick then
            recipeSortAscending = not recipeSortAscending
        else
            recipeSortKey = sortKeyForClick
            recipeSortAscending = sortKeyForClick ~= "skill"
        end
        updateRecipeHeaderSortIndicators()
        if selectedCharacter then
            clearRecipeFocus()
            layoutRecipeView(selectedCharacter)
        end
    end)
    recipeHeaderButtons[sortKey] = btn
    return btn
end

createRecipeHeaderButton("recipe", function(btn)
    btn:SetPoint("TOPLEFT", recipeColHeader, "TOPLEFT", 4, 0)
    btn:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
end)
createRecipeHeaderButton("skill", function(btn)
    btn:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -4, 0)
    btn:SetWidth(UI.RECIPE_SKILL_COL_WIDTH)
end)
updateRecipeHeaderSortIndicators()

local function applyRecipeSkillColumnLayout(showSkillCol)
    local skillHeader = recipeHeaderButtons.skill
    local recipeHeader = recipeHeaderButtons.recipe
    if skillHeader then
        skillHeader:SetShown(showSkillCol)
    end
    if recipeHeader then
        recipeHeader:ClearAllPoints()
        recipeHeader:SetPoint("TOPLEFT", recipeColHeader, "TOPLEFT", 4, 0)
        if showSkillCol then
            recipeHeader:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        else
            recipeHeader:SetPoint("TOPRIGHT", recipeColHeader, "TOPRIGHT", -4, 0)
        end
    end
end

recipeViewportFrame:SetPoint("TOPLEFT", recipeColHeader, "BOTTOMLEFT", 0, 0)
recipeViewportFrame:SetPoint("BOTTOMRIGHT", recipeBody, "BOTTOMRIGHT", 0, 0)

local recipeViewport = Theme.CreateVerticalScrollViewport({
    parent = recipeViewportFrame,
    gutterEdge = recipeBody,
    anchorTop = { "TOPLEFT", recipeViewportFrame, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", recipeViewportFrame, "BOTTOMRIGHT", 0, 0 },
    enableMouseWheel = true,
    valueStep = UI.RECIPE_ROW_HEIGHT,
    wheelStep = UI.RECIPE_ROW_HEIGHT * 3,
})
local recipeScrollChild = recipeViewport.child

-- Gradient under the recipe column header when the list is scrolled (Gear / Search pattern).
recipeColHeader:SetFrameLevel((recipeBody:GetFrameLevel() or 0) + 10)
local recipeHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = recipeColHeader,
    scrollFrame = recipeViewport.scroll,
    scrollBar = recipeViewport.scrollBar,
    -- Pull fade up so it meets the header edge (avoids a 1–2px seam).
    headerBottomInset = 2,
})
recipeViewport.OnScroll(function()
    if recipeHeaderFade then
        recipeHeaderFade:Update()
    end
end)

local function forwardRecipeWheel(_, delta)
    recipeViewport.Wheel(delta)
end

-- Empty-state copy region ignores the profession tab strip so "no professions" and
-- "no recipes" messages share the same vertical position under the character title.
-- Parented to recipeBody so it slides with the recipe page.
local emptyMsgRegion = CreateFrame("Frame", nil, recipeBody)
emptyMsgRegion:SetAllPoints(recipeBody)
emptyMsgRegion:EnableMouse(false)
emptyMsgRegion:Hide()

local noProfText = emptyMsgRegion:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
-- TOP at region center (+ half line) so the first line matches a single-line CENTER message.
noProfText:SetPoint("TOP", emptyMsgRegion, "CENTER", 0, 7)
noProfText:SetWidth(360)
noProfText:SetJustifyH("CENTER")
noProfText:SetJustifyV("TOP")
noProfText:Hide()

local loadingText = recipeBody:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
loadingText:SetPoint("CENTER", recipeBody, "CENTER", 0, 0)
loadingText:SetWidth(360)
loadingText:SetJustifyH("CENTER")
loadingText:SetText("Loading recipes…")
loadingText:Hide()

local profTabPool = {}
local recipeRowPool = {}

-- *** Row pools ***

local mainRowPool = {}
local charRowPool = {}
-- Repositioning frames during layout fires OnLeave; ignore those and resync after layout.
local suppressMainRowHoverEvents = false

local function isMainRowSettingsActive(row)
    return ME.notesWizardActive
        and ME.wizardMode == "edit"
        and ME.editSourceGroup
        and row
        and row.settingsGroup
        and ME.editSourceGroup.main == row.settingsGroup.main
end

local function mainRowIsUnderMouse(row)
    if not row or not row:IsShown() then
        return false
    end
    if MouseIsOver then
        return MouseIsOver(row) and true or false
    end
    local focus = GetMouseFocus and GetMouseFocus()
    return focus == row or (row.settingsBtn and focus == row.settingsBtn) or false
end

local function syncMainRowHoverFromMouse()
    local hoveredRow = nil
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if mainRowIsUnderMouse(row) then
            hoveredRow = row
            break
        end
    end
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row == hoveredRow then
            local focus = GetMouseFocus and GetMouseFocus()
            row.settingsBtnHovered = (row.settingsBtn and focus == row.settingsBtn) and true or false
            if row.setMainRowHover then
                row.setMainRowHover(true)
            end
        elseif row and row.clearMainRowHoverState then
            row.clearMainRowHoverState()
        end
    end
end

syncMainRowSettingsIcons = function()
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row.updateSettingsBtnVisibility then
            row.updateSettingsBtnVisibility()
        elseif row and row.settingsBtn then
            local active = isMainRowSettingsActive(row)
            Theme.SetSettingsButtonGlow(row.settingsBtn, active, "glow")
            Theme.SetSettingsButtonGlow(row.settingsBtn, false, "hoverGlow")
            if active or row.rowHovered or row.settingsBtnHovered then
                row.settingsBtn:Show()
            else
                row.settingsBtn:Hide()
            end
        end
    end
end

applyListColumnLayout = function()
    local showOnline = true
    local onlineBtn = listHeaderButtons.online
    local countBtn = listHeaderButtons.characterCount
    if onlineBtn then
        onlineBtn:SetShown(showOnline)
    end
    if countBtn then
        countBtn:ClearAllPoints()
        countBtn:SetPoint("LEFT", listColHeader, "LEFT", UI.SECOND_COLUMN, 0)
        if showOnline and onlineBtn then
            countBtn:SetPoint("RIGHT", onlineBtn, "LEFT", -UI.NAME_COLUMN_GAP, 0)
        else
            countBtn:SetPoint("RIGHT", listColHeader, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        end
    end
    for i = 1, #mainRowPool do
        local row = mainRowPool[i]
        if row and row.countFS then
            if row.lastOnlineFS then
                row.lastOnlineFS:SetShown(showOnline)
            end
            row.countFS:ClearAllPoints()
            row.countFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
            if showOnline and row.lastOnlineFS then
                row.countFS:SetPoint("RIGHT", row.lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            elseif row.settingsBtn then
                row.countFS:SetPoint("RIGHT", row.settingsBtn, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            else
                row.countFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
            end
        end
    end
    for i = 1, #charRowPool do
        local row = charRowPool[i]
        if row and row.profFS then
            if row.lastOnlineFS then
                row.lastOnlineFS:SetShown(showOnline)
            end
            row.profFS:ClearAllPoints()
            row.profFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN + UI.CHAR_INDENT, 0)
            if showOnline and row.lastOnlineFS then
                row.profFS:SetPoint("RIGHT", row.lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
            else
                row.profFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
            end
        end
    end
end

-- Left chain: [pin] name [!] [M]. Pin only consumes space when visible.
-- Stale "!" and manual "M" sit immediately to the right of the name text.
local function layoutMainRowLeftIcons(row, showOld, pinned, showManual)
    local leftAnchor = row
    local leftPoint = "LEFT"
    local leftX = UI.LEFT_ICON_PAD

    if row.pinIcon then
        if pinned then
            row.pinIcon:ClearAllPoints()
            row.pinIcon:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
            row.pinIcon:Show()
            leftAnchor = row.pinIcon
            leftPoint = "RIGHT"
            leftX = UI.PIN_ICON_GAP
        else
            row.pinIcon:Hide()
        end
    end

    local nameColRight = UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP
    local afterNameReserve = 0
    if showOld and row.oldDataIcon then
        afterNameReserve = afterNameReserve + UI.OLD_DATA_ICON_WIDTH + UI.PIN_ICON_GAP
    end
    if showManual and row.manualDataIcon then
        afterNameReserve = afterNameReserve + UI.MANUAL_DATA_ICON_WIDTH + UI.PIN_ICON_GAP
    end
    local nameRightLimit = nameColRight - afterNameReserve

    if row.nameFS then
        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
        row.nameFS:SetPoint("RIGHT", row, "LEFT", nameRightLimit, 0)
    end

    local fsW = (row.nameFS and row.nameFS.GetWidth and row.nameFS:GetWidth()) or 0
    local textW = (row.nameFS and row.nameFS.GetStringWidth and row.nameFS:GetStringWidth()) or 0
    if textW > fsW then
        textW = fsW
    end
    local trailingOffset = textW + UI.PIN_ICON_GAP
    local maxTrailing = fsW + UI.PIN_ICON_GAP

    local function placeAfterName(icon, width)
        if trailingOffset > maxTrailing then
            trailingOffset = maxTrailing
        end
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row.nameFS, "LEFT", trailingOffset, 0)
        trailingOffset = trailingOffset + width + UI.PIN_ICON_GAP
        maxTrailing = maxTrailing + width + UI.PIN_ICON_GAP
    end

    if row.oldDataIcon then
        row.oldDataIcon.showOldDataTooltip = showOld and true or false
        if showOld then
            placeAfterName(row.oldDataIcon, UI.OLD_DATA_ICON_WIDTH)
            row.oldDataIcon:EnableMouse(true)
            row.oldDataIcon:Show()
            if row.oldDataIcon.mark then
                row.oldDataIcon.mark:Show()
            end
        else
            row.oldDataIcon:EnableMouse(false)
            row.oldDataIcon:Hide()
            if row.oldDataIcon.mark then
                row.oldDataIcon.mark:Hide()
            end
        end
    end

    if row.manualDataIcon then
        row.manualDataIcon.showManualDataTooltip = showManual and true or false
        if showManual then
            placeAfterName(row.manualDataIcon, UI.MANUAL_DATA_ICON_WIDTH)
            row.manualDataIcon:EnableMouse(true)
            row.manualDataIcon:Show()
            if row.manualDataIcon.mark then
                row.manualDataIcon.mark:Show()
            end
        else
            row.manualDataIcon:EnableMouse(false)
            row.manualDataIcon:Hide()
            if row.manualDataIcon.mark then
                row.manualDataIcon.mark:Hide()
            end
        end
    end
end

-- Left chain for character rows: [star?] name [M?] (level). Star only when main was set
-- explicitly; manual "M" and level sit immediately to the right of the name text.
local function layoutCharRowLeftIcons(row, showMainStar, showManual)
    local leftAnchor = row
    local leftPoint = "LEFT"
    local leftX = UI.CHAR_INDENT

    if row.mainStarIcon then
        row.mainStarIcon.showMainStarTooltip = showMainStar and true or false
        if showMainStar then
            row.mainStarIcon:ClearAllPoints()
            row.mainStarIcon:SetPoint("LEFT", row, "LEFT", UI.CHAR_INDENT, 0)
            row.mainStarIcon:EnableMouse(true)
            row.mainStarIcon:Show()
            leftAnchor = row.mainStarIcon
            leftPoint = "RIGHT"
            leftX = UI.MAIN_STAR_ICON_GAP
        else
            row.mainStarIcon:EnableMouse(false)
            row.mainStarIcon:Hide()
        end
    end

    local nameColRight = UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP
    local afterNameReserve = 0
    if showManual and row.manualDataIcon then
        afterNameReserve = afterNameReserve + UI.MANUAL_DATA_ICON_WIDTH + UI.PIN_ICON_GAP
    end
    local levelW = 0
    if row.levelFS and row.levelFS.GetStringWidth then
        levelW = row.levelFS:GetStringWidth() or 0
    end
    if levelW > 0 then
        afterNameReserve = afterNameReserve + levelW + UI.PIN_ICON_GAP
    end
    local nameRightLimit = nameColRight - afterNameReserve

    if row.nameFS then
        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", leftAnchor, leftPoint, leftX, 0)
        row.nameFS:SetPoint("RIGHT", row, "LEFT", nameRightLimit, 0)
    end

    local fsW = (row.nameFS and row.nameFS.GetWidth and row.nameFS:GetWidth()) or 0
    local textW = (row.nameFS and row.nameFS.GetStringWidth and row.nameFS:GetStringWidth()) or 0
    if textW > fsW then
        textW = fsW
    end
    local trailingOffset = textW + UI.PIN_ICON_GAP
    local maxTrailing = fsW + UI.PIN_ICON_GAP

    local function placeAfterName(widget, width)
        if trailingOffset > maxTrailing then
            trailingOffset = maxTrailing
        end
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", row.nameFS, "LEFT", trailingOffset, 0)
        trailingOffset = trailingOffset + width + UI.PIN_ICON_GAP
        maxTrailing = maxTrailing + width + UI.PIN_ICON_GAP
    end

    if row.manualDataIcon then
        row.manualDataIcon.showManualDataTooltip = showManual and true or false
        if showManual then
            placeAfterName(row.manualDataIcon, UI.MANUAL_DATA_ICON_WIDTH)
            row.manualDataIcon:EnableMouse(true)
            row.manualDataIcon:Show()
            if row.manualDataIcon.mark then
                row.manualDataIcon.mark:Show()
            end
        else
            row.manualDataIcon:EnableMouse(false)
            row.manualDataIcon:Hide()
            if row.manualDataIcon.mark then
                row.manualDataIcon.mark:Hide()
            end
        end
    end

    if row.levelFS then
        if levelW > 0 then
            placeAfterName(row.levelFS, levelW)
            row.levelFS:Show()
        else
            row.levelFS:Hide()
        end
    end
end

local function acquireMainRow(index)
    local row = mainRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(UI.MAIN_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        -- Keep hover tint off the settings icon so it does not brighten on row hover.
        if row.altArmyHoverTint then
            local tint = row.altArmyHoverTint
            tint:ClearAllPoints()
            tint:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            tint:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            tint:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        end
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)

        local function updateSettingsBtnVisibility()
            if not row.settingsBtn then return end
            local active = isMainRowSettingsActive(row)
            Theme.SetSettingsButtonGlow(row.settingsBtn, active, "glow")
            if not active then
                Theme.SetSettingsButtonGlow(row.settingsBtn, row.settingsBtnHovered and true or false, "hoverGlow")
            else
                Theme.SetSettingsButtonGlow(row.settingsBtn, false, "hoverGlow")
            end
            if active or row.rowHovered or row.settingsBtnHovered then
                row.settingsBtn:Show()
            else
                row.settingsBtn:Hide()
            end
        end
        row.updateSettingsBtnVisibility = updateSettingsBtnVisibility

        local function clearMainRowHoverState()
            row.rowHovered = false
            row.settingsBtnHovered = false
            Theme.SetHoverTint(row, false)
            updateSettingsBtnVisibility()
        end

        local function setMainRowHover(on)
            Theme.SetHoverTint(row, on)
            row.rowHovered = on and true or false
            if not on then
                row.settingsBtnHovered = false
            end
            updateSettingsBtnVisibility()
        end
        row.setMainRowHover = setMainRowHover
        row.clearMainRowHoverState = clearMainRowHoverState

        row:SetScript("OnEnter", function()
            -- Moving between rows can skip OnLeave on the previous row; clear others.
            for i = 1, #mainRowPool do
                local other = mainRowPool[i]
                if other and other ~= row and other.clearMainRowHoverState then
                    other.clearMainRowHoverState()
                end
            end
            setMainRowHover(true)
        end)
        row:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            -- Entering the settings child fires row OnLeave first; ignore that transition.
            if GetMouseFocus and GetMouseFocus() == row.settingsBtn then
                return
            end
            setMainRowHover(false)
        end)

        -- Far-left stale warning; only participates in layout when shown (see layoutMainRowLeftIcons).
        local oldDataIcon = CreateFrame("Button", nil, row)
        oldDataIcon:SetSize(UI.OLD_DATA_ICON_WIDTH, UI.MAIN_ROW_HEIGHT)
        oldDataIcon:EnableMouse(false)
        oldDataIcon:RegisterForClicks("LeftButtonUp")
        oldDataIcon:Hide()
        local mark = oldDataIcon:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        mark:SetText("!")
        mark:SetPoint("CENTER", oldDataIcon, "CENTER", 0, 0)
        mark:SetTextColor(1, 0.82, 0, 1)
        oldDataIcon.mark = mark
        oldDataIcon:SetScript("OnEnter", function(self)
            setMainRowHover(true)
            if not self.showOldDataTooltip or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Shared data is outdated", 1, 1, 1)
            local receivedAt = GTD.GetGroupOldestReceivedAt and GTD.GetGroupOldestReceivedAt(row.settingsGroup)
            local ageDays = GTD.GetDataAgeDays and GTD.GetDataAgeDays(receivedAt)
            GameTooltip:AddLine(GTD.GetOldDataTooltipText(ageDays), 1, 0.82, 0, true)
            local GSS = AltArmy.GuildShareSettings
            if GSS and GSS.IsAutoDeleteOldDataEnabled and GSS.IsAutoDeleteOldDataEnabled() then
                local daysLeft = GTD.GetDaysUntilAutoDelete and GTD.GetDaysUntilAutoDelete(receivedAt)
                if daysLeft ~= nil and GTD.GetOldDataAutoDeleteTooltipText then
                    GameTooltip:AddLine(
                        GTD.GetOldDataAutoDeleteTooltipText(daysLeft), 0.5, 0.5, 0.5, true)
                    GameTooltip:AddLine("Click to configure", 0.5, 0.5, 0.5, true)
                end
            end
            GameTooltip:Show()
        end)
        oldDataIcon:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            if GetMouseFocus and GetMouseFocus() == row.settingsBtn then
                return
            end
            setMainRowHover(false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        oldDataIcon:SetScript("OnClick", function()
            if GameTooltip then GameTooltip:Hide() end
            if AltArmy.OpenInterfaceOptions then
                AltArmy.OpenInterfaceOptions("general", { flash = "autoDelete" })
            end
        end)
        row.oldDataIcon = oldDataIcon

        local manualDataIcon = CreateFrame("Frame", nil, row)
        manualDataIcon:SetSize(UI.MANUAL_DATA_ICON_WIDTH, UI.MAIN_ROW_HEIGHT)
        manualDataIcon:EnableMouse(false)
        manualDataIcon:Hide()
        local manualMark = manualDataIcon:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        manualMark:SetText("M")
        manualMark:SetPoint("CENTER", manualDataIcon, "CENTER", 0, 0)
        manualMark:SetTextColor(0.7, 0.7, 0.7, 1)
        manualDataIcon.mark = manualMark
        manualDataIcon:SetScript("OnEnter", function(self)
            setMainRowHover(true)
            if not self.showManualDataTooltip or not GameTooltip then return end
            local firstManual
            local g = row.settingsGroup
            if g then
                for _, m in ipairs(g.members or {}) do
                    if GTD.IsManualMember and GTD.IsManualMember(m) then
                        firstManual = m
                        break
                    end
                end
            end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Manual grouping", 1, 1, 1)
            GameTooltip:AddLine(
                (GTD.GetManualDataTooltipText and GTD.GetManualDataTooltipText(firstManual)) or "",
                1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        manualDataIcon:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            if GetMouseFocus and GetMouseFocus() == row.settingsBtn then
                return
            end
            setMainRowHover(false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.manualDataIcon = manualDataIcon

        local settingsBtn = CreateFrame("Button", nil, row)
        settingsBtn:SetSize(UI.SETTINGS_ICON_WIDTH, UI.SETTINGS_ICON_WIDTH)
        settingsBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        settingsBtn:RegisterForClicks("LeftButtonUp")
        local settingsIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
        settingsIcon:SetAllPoints(settingsBtn)
        settingsIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
        settingsBtn.icon = settingsIcon
        Theme.SkinSettingsIconButton(settingsBtn)
        Theme.InstallSettingsButtonGlow(settingsBtn, "glow")
        settingsBtn:Hide()
        settingsBtn:SetScript("OnEnter", function()
            row.settingsBtnHovered = true
            Theme.SetHoverTint(row, true)
            updateSettingsBtnVisibility()
        end)
        settingsBtn:SetScript("OnLeave", function()
            if suppressMainRowHoverEvents then
                return
            end
            row.settingsBtnHovered = false
            local focus = GetMouseFocus and GetMouseFocus()
            if focus == row then
                row.rowHovered = true
                Theme.SetHoverTint(row, true)
            else
                row.rowHovered = false
                Theme.SetHoverTint(row, false)
            end
            updateSettingsBtnVisibility()
        end)
        settingsBtn:SetScript("OnClick", function()
            if not row.settingsGroup then return end
            local group = row.settingsGroup
            if ME.slideSwap then
                ME.slideSwap(function() ME.openGroupEdit(group) end)
            else
                ME.openGroupEdit(group)
            end
        end)
        row.settingsBtn = settingsBtn

        local pinIcon = row:CreateTexture(nil, "ARTWORK")
        pinIcon:SetSize(UI.PIN_ICON_SIZE, UI.PIN_ICON_SIZE)
        pinIcon:SetTexture("Interface\\AddOns\\AltArmy_TBC\\Media\\PushPin")
        pinIcon:Hide()
        row.pinIcon = pinIcon

        local nameFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        nameFS:SetPoint("LEFT", row, "LEFT", UI.LEFT_ICON_PAD, 0)
        nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS
        local lastOnlineFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        lastOnlineFS:SetPoint("RIGHT", settingsBtn, "LEFT", -2, 0)
        lastOnlineFS:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
        lastOnlineFS:SetJustifyH("RIGHT")
        lastOnlineFS:SetWordWrap(false)
        row.lastOnlineFS = lastOnlineFS
        local countFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        countFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN, 0)
        countFS:SetPoint("RIGHT", lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
        countFS:SetJustifyH("LEFT")
        countFS:SetWordWrap(false)
        row.countFS = countFS
        mainRowPool[index] = row
    end
    row:Show()
    return row
end

local function acquireCharRow(index)
    local row = charRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(UI.CHAR_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)

        local mainStarIcon = CreateFrame("Frame", nil, row)
        mainStarIcon:SetSize(UI.MAIN_STAR_ICON_SIZE, UI.CHAR_ROW_HEIGHT)
        mainStarIcon:EnableMouse(false)
        mainStarIcon:Hide()
        local starTex = mainStarIcon:CreateTexture(nil, "ARTWORK")
        starTex:SetSize(UI.MAIN_STAR_ICON_SIZE, UI.MAIN_STAR_ICON_SIZE)
        starTex:SetPoint("CENTER", mainStarIcon, "CENTER", 0, 0)
        starTex:SetTexture(UI.MAIN_STAR_TEXTURE)
        mainStarIcon.tex = starTex
        mainStarIcon:SetScript("OnEnter", function(self)
            Theme.SetHoverTint(row, true)
            if not self.showMainStarTooltip then return end
            local m = row.memberEntry
            local isOwn = not m or m.source == "local" or not m.source
            if GTD.PresentMainStarTooltip then
                GTD.PresentMainStarTooltip(self, "ANCHOR_BOTTOMLEFT", {
                    name = m and m.name,
                    classFile = m and m.classFile,
                    isOwn = isOwn,
                    showConfigureHint = isOwn,
                })
            end
        end)
        mainStarIcon:SetScript("OnLeave", function()
            Theme.SetHoverTint(row, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        mainStarIcon:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            local m = row.memberEntry
            local isOwn = not m or m.source == "local" or not m.source
            if isOwn and AltArmy.OpenInterfaceOptions then
                AltArmy.OpenInterfaceOptions("general", { flash = "main" })
            end
        end)
        row.mainStarIcon = mainStarIcon

        local nameFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        nameFS:SetPoint("LEFT", row, "LEFT", UI.CHAR_INDENT, 0)
        nameFS:SetPoint("RIGHT", row, "LEFT", UI.SECOND_COLUMN - UI.NAME_COLUMN_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS

        local manualDataIcon = CreateFrame("Frame", nil, row)
        manualDataIcon:SetSize(UI.MANUAL_DATA_ICON_WIDTH, UI.CHAR_ROW_HEIGHT)
        manualDataIcon:EnableMouse(false)
        manualDataIcon:Hide()
        local manualMark = manualDataIcon:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        manualMark:SetText("M")
        manualMark:SetPoint("CENTER", manualDataIcon, "CENTER", 0, 0)
        manualMark:SetTextColor(0.7, 0.7, 0.7, 1)
        manualDataIcon.mark = manualMark
        manualDataIcon:SetScript("OnEnter", function(self)
            Theme.SetHoverTint(row, true)
            if not self.showManualDataTooltip or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Manual grouping", 1, 1, 1)
            GameTooltip:AddLine(
                (GTD.GetManualCharacterTooltipText
                    and GTD.GetManualCharacterTooltipText(row.memberEntry)) or "",
                1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        manualDataIcon:SetScript("OnLeave", function()
            Theme.SetHoverTint(row, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.manualDataIcon = manualDataIcon

        local levelFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        levelFS:SetJustifyH("LEFT")
        levelFS:SetWordWrap(false)
        levelFS:Hide()
        row.levelFS = levelFS

        local lastOnlineFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        lastOnlineFS:SetPoint("RIGHT", row, "RIGHT", -UI.RIGHT_TRAILING_RESERVE, 0)
        lastOnlineFS:SetWidth(UI.LAST_ONLINE_COLUMN_WIDTH)
        lastOnlineFS:SetJustifyH("RIGHT")
        lastOnlineFS:SetWordWrap(false)
        row.lastOnlineFS = lastOnlineFS
        local profFS = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        profFS:SetPoint("LEFT", row, "LEFT", UI.SECOND_COLUMN + UI.CHAR_INDENT, 0)
        profFS:SetPoint("RIGHT", lastOnlineFS, "LEFT", -UI.NAME_COLUMN_GAP, 0)
        profFS:SetJustifyH("LEFT")
        profFS:SetWordWrap(false)
        row.profFS = profFS

        charRowPool[index] = row
    end
    row:Show()
    return row
end

local function hideMainRowsFrom(index)
    for i = index, #mainRowPool do
        local row = mainRowPool[i]
        if row then
            if row.clearMainRowHoverState then
                row.clearMainRowHoverState()
            end
            row:Hide()
        end
    end
end

local function hideCharRowsFrom(index)
    for i = index, #charRowPool do
        if charRowPool[i] then charRowPool[i]:Hide() end
    end
end

local guildPickerRowPool = {}

local function hideGuildPickerRowsFrom(index)
    for i = index, #guildPickerRowPool do
        if guildPickerRowPool[i] then guildPickerRowPool[i]:Hide() end
    end
end

local function acquireGuildPickerRow(index)
    local row = guildPickerRowPool[index]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(UI.MAIN_ROW_HEIGHT)
        Theme.InstallHoverTint(row)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardWheel)
        row:SetScript("OnEnter", function() Theme.SetHoverTint(row, true) end)
        row:SetScript("OnLeave", function() Theme.SetHoverTint(row, false) end)
        local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
        guildPickerRowPool[index] = row
    end
    row:Show()
    return row
end

local function layoutGuildPicker(guilds)
    hideMainRowsFrom(1)
    hideCharRowsFrom(1)
    listColHeader:Hide()
    anchorListViewportBelowGuildHeader()
    emptyText:Hide()
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))
    for i, guild in ipairs(guilds) do
        local row = acquireGuildPickerRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        row.label:SetText(guild)
        row:SetScript("OnClick", function()
            selectedBrowseGuild = guild
            refresh()
        end)
        y = y + UI.MAIN_ROW_HEIGHT
    end
    hideGuildPickerRowsFrom(#guilds + 1)
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
    updateListHeaderFade()
    if ME.syncListFooter then ME.syncListFooter() end
end

local function hideRecipeRowsFrom(index)
    for i = index, #recipeRowPool do
        if recipeRowPool[i] then recipeRowPool[i]:Hide() end
    end
end

local function hideProfTabsFrom(index)
    for i = index, #profTabPool do
        if profTabPool[i] then profTabPool[i]:Hide() end
    end
end

local FOCUS_BORDER_COLOR = (Theme.COLORS and Theme.COLORS.green) or { 0.20, 0.85, 0.35, 1 }
local RECIPE_FOCUS_SCROLL_DURATION = 0.28
local recipeFocusAnim = CreateFrame("Frame")
-- Preferred profession for search drill-in (re-applied when profs arrive after load).
local focusProfessionKey = nil
local focusProfessionName = nil
-- Skip the automatic OnShow refresh while opening from search (avoids list flash + races).
local suppressGuildOnShowRefresh = false

local function stopRecipeFocusScroll()
    recipeFocusAnim:SetScript("OnUpdate", nil)
end

local function clearRecipeFocusBorders()
    for i = 1, #recipeRowPool do
        local row = recipeRowPool[i]
        if row and row.focusBorder then
            row.focusBorder:Hide()
        end
    end
end

clearRecipeFocus = function()
    stopRecipeFocusScroll()
    clearRecipeFocusBorders()
    focusRecipeID = nil
    focusScrollPending = false
    focusProfessionKey = nil
    focusProfessionName = nil
end

local function ensureRecipeFocusBorder(row)
    if not row or row.focusBorder then return end
    local border = CreateFrame("Frame", nil, row)
    border:SetAllPoints(row)
    border:SetFrameLevel(row:GetFrameLevel() + 5)
    local r = FOCUS_BORDER_COLOR[1] or 0.2
    local g = FOCUS_BORDER_COLOR[2] or 0.85
    local b = FOCUS_BORDER_COLOR[3] or 0.35
    local a = FOCUS_BORDER_COLOR[4] or 1
    local top = border:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(r, g, b, a)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    local bottom = border:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    local left = border:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(r, g, b, a)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    local right = border:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(r, g, b, a)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    border:Hide()
    row.focusBorder = border
end

local function smoothScrollRecipeListTo(targetOffset)
    stopRecipeFocusScroll()
    local start = recipeViewport.scroll:GetVerticalScroll() or 0
    if math.abs(start - targetOffset) < 0.5 then
        recipeViewport.SetOffset(targetOffset)
        return
    end
    local elapsed = 0
    recipeFocusAnim:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        local t = elapsed / RECIPE_FOCUS_SCROLL_DURATION
        if t >= 1 then
            recipeViewport.SetOffset(targetOffset)
            stopRecipeFocusScroll()
            return
        end
        -- Cubic ease-in-out
        local eased
        if t < 0.5 then
            eased = 4 * t * t * t
        else
            local u = -2 * t + 2
            eased = 1 - (u * u * u) / 2
        end
        recipeViewport.SetOffset(start + (targetOffset - start) * eased)
    end)
end

--- Apply green border + deferred scroll until the viewport has a real height.
--- Retries across frames (and across later layouts) while focusScrollPending is set.
--- preserveScroll: when true and there is no focused recipe, leave the current offset alone
--- (guild presence refreshes rebuild the row tables without changing recipe IDs).
applyRecipeFocus = function(recipes, preserveScroll)
    if not focusRecipeID then
        clearRecipeFocusBorders()
        if not preserveScroll then
            recipeViewport.SetOffset(0)
        end
        return
    end

    local Nav = AltArmy.SearchGuildNav
    local idx = Nav and Nav.FindRecipeRowIndex and Nav.FindRecipeRowIndex(recipes, focusRecipeID)

    local function findRow()
        if idx and recipeRowPool[idx] and recipeRowPool[idx].recipeID then
            local row = recipeRowPool[idx]
            local id = row.recipeID
            if id == focusRecipeID or tonumber(id) == tonumber(focusRecipeID) then
                return row, idx
            end
        end
        for i = 1, #recipeRowPool do
            local row = recipeRowPool[i]
            if row and row:IsShown() and row.recipeID then
                local id = row.recipeID
                if id == focusRecipeID or tonumber(id) == tonumber(focusRecipeID) then
                    return row, i
                end
            end
        end
        return nil, nil
    end

    local row, rowIndex = findRow()
    if not row then
        -- Recipes may still be loading; keep focusScrollPending for a later layout.
        return
    end

    clearRecipeFocusBorders()
    ensureRecipeFocusBorder(row)
    row.focusBorder:Show()

    if not focusScrollPending then
        return
    end

    local attempts = 0
    stopRecipeFocusScroll()
    recipeFocusAnim:SetScript("OnUpdate", function(f)
        attempts = attempts + 1
        local liveRow, liveIndex = findRow()
        if liveRow then
            clearRecipeFocusBorders()
            ensureRecipeFocusBorder(liveRow)
            liveRow.focusBorder:Show()
            rowIndex = liveIndex
        end
        local viewH = recipeViewport.scroll:GetHeight() or 0
        local contentH = recipeScrollChild:GetHeight() or 0
        if (not liveRow or viewH <= 0) and attempts < 60 then
            return
        end
        f:SetScript("OnUpdate", nil)
        focusScrollPending = false
        if not liveRow or viewH <= 0 or not rowIndex then
            return
        end
        recipeViewport.SetOffset(0)
        local rowTop = (rowIndex - 1) * UI.RECIPE_ROW_HEIGHT
        local target = Nav.ScrollOffsetToRevealRow
            and Nav.ScrollOffsetToRevealRow(rowTop, UI.RECIPE_ROW_HEIGHT, viewH, 0, contentH)
        if target then
            smoothScrollRecipeListTo(target)
        end
    end)
end

local function isLoadingRecipes(entry, profKey)
    if not entry or entry.source == "local" or not entry.source then return false end
    local Comm = AltArmy.GuildShareComm
    if not Comm or not Comm.IsGuildMemberOnline or not Comm.IsGuildMemberOnline(entry.source) then
        return false
    end
    local prof = entry.Professions and entry.Professions[profKey]
    if not prof then return false end
    if prof.Recipes and prof.recipesRv == prof.rv then return false end
    return (prof.rv or 0) ~= 0 or (prof.count or 0) > 0
end

local function acquireRecipeRow(index)
    local row = recipeRowPool[index]
    if not row then
        row = CreateFrame("Frame", nil, recipeScrollChild)
        row:SetHeight(UI.RECIPE_ROW_HEIGHT)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", forwardRecipeWheel)
        local label = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -(UI.RECIPE_SKILL_COL_WIDTH + 4), 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label
        local skillCell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        skillCell:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        skillCell:SetWidth(UI.RECIPE_SKILL_COL_WIDTH)
        skillCell:SetJustifyH("RIGHT")
        row.skillCell = skillCell
        row:SetScript("OnEnter", function(self)
            local recipeID = self.recipeID
            if not recipeID or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            local link = GetRecipeLink(recipeID, self.resultItemID)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetText(self.recipeName or ("Recipe " .. tostring(recipeID)))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not IsShiftKeyDown() then return end
            local link = GetRecipeLink(self.recipeID, self.resultItemID)
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
            end
        end)
        recipeRowPool[index] = row
    end
    row:Show()
    return row
end

-- Forever: profession tabs are spellbook-style icon tabs in the main toolbar row (same spot as
-- the Gear / Cooldowns sub-view tabs). One TopTabs set per profession list, reused per session.
function ME.hideProfIconTabs()
    for _, set in pairs(ME.profIconTabSets) do
        set.frame:Hide()
    end
end

function ME.showProfIconTabs(profs, selectedIndex)
    local keys = {}
    for i, prof in ipairs(profs) do keys[i] = prof.key end
    local signature = table.concat(keys, ",")
    local set = ME.profIconTabSets[signature]
    if not set then
        local defs = {}
        for i, prof in ipairs(profs) do
            defs[i] = { name = prof.key, label = prof.name or prof.key, icon = GTD.GetProfessionIcon(prof.key) }
        end
        set = AltArmy.TopTabs.Create(frame, defs, {
            onSelect = function(key)
                for i, k in ipairs(keys) do
                    if k == key then
                        clearRecipeFocus()
                        selectedProfIndex = i
                        layoutRecipeView(selectedCharacter)
                        return
                    end
                end
            end,
        })
        set.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)
        ME.profIconTabSets[signature] = set
    end
    ME.hideProfIconTabs()
    set.frame:Show()
    set:SetSelected(keys[selectedIndex])
end

layoutRecipeView = function(entry)
    if not entry then return end
    clearPendingRecipeIcons()
    updateRecipeSearchPlaceholder(entry)
    local profs = GTD.GetCraftingProfessions(entry)
    -- Re-resolve preferred profession while search focus is still pending (profs may load late).
    if focusScrollPending and (focusProfessionKey or focusProfessionName) then
        local Nav = AltArmy.SearchGuildNav
        if Nav and Nav.FindProfessionIndex then
            selectedProfIndex = Nav.FindProfessionIndex(profs, focusProfessionKey, focusProfessionName)
        end
    end
    if selectedProfIndex < 1 or selectedProfIndex > #profs then
        selectedProfIndex = 1
    end

    updateWhisperButton(entry)

    noProfText:Hide()
    loadingText:Hide()
    recipeViewportFrame:Hide()
    recipeColHeader:Hide()
    if recipeHeaderFade and recipeHeaderFade.frame then
        recipeHeaderFade.frame:Hide()
    end
    hideRecipeRowsFrom(1)
    hideProfTabsFrom(1)

    recipeBody:ClearAllPoints()
    recipeBody:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)

    if #profs == 0 then
        profTabStrip:Hide()
        ME.hideProfIconTabs()
        header:SetHeight(UI.RECIPE_TITLE_HEIGHT)
        recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
        noProfText:SetText(GTD.FormatNoProfessionsMessage(entry, formatName))
        noProfText:Show()
        return
    end

    header:SetHeight(UI.RECIPE_TITLE_HEIGHT)
    if ME.useProfIconTabs then
        profTabStrip:Hide()
        recipeBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PAD)
        ME.showProfIconTabs(profs, selectedProfIndex)
    else
        profTabStrip:Show()
        recipeBody:SetPoint("TOPLEFT", profTabStrip, "BOTTOMLEFT", 0, -PAD)
        local tabX = 0
        for i, prof in ipairs(profs) do
            local tab = profTabPool[i]
            if not tab then
                tab = CreateFrame("Button", nil, profTabStrip)
                tab:SetHeight(UI.PROF_TAB_HEIGHT - 4)
                Theme.SkinButton(tab, true)
                local tabLabel = tab:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
                tabLabel:SetPoint("CENTER", tab, "CENTER", 0, 0)
                tab.label = tabLabel
                profTabPool[i] = tab
            end
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", profTabStrip, "LEFT", tabX, 0)
            local labelText = (prof.name or prof.key or "?") .. " (" .. (prof.rank or 0) .. ")"
            tab.label:SetText(labelText)
            local textWidth = tab.label:GetStringWidth() or 40
            tab:SetWidth(math.max(64, textWidth + 16))
            tab:SetSelected(i == selectedProfIndex)
            tab:Show()
            tab:SetScript("OnClick", function()
                clearRecipeFocus()
                selectedProfIndex = i
                layoutRecipeView(selectedCharacter)
            end)
            tabX = tabX + tab:GetWidth() + UI.PROF_TAB_GAP
        end
        hideProfTabsFrom(#profs + 1)
    end

    local selectedProf = profs[selectedProfIndex]
    local profKey = selectedProf and selectedProf.key
    local recipesPending = isLoadingRecipes(entry, profKey)
    local allRecipes = GTD.GetProfessionRecipes(entry, profKey)
    if recipesPending and #allRecipes == 0 then
        loadingText:Show()
        -- Keep retrying focus once recipes finish loading (RefreshGuildTab also re-layouts).
        if focusRecipeID and focusScrollPending then
            stopRecipeFocusScroll()
            local attempts = 0
            recipeFocusAnim:SetScript("OnUpdate", function(f)
                attempts = attempts + 1
                if not focusRecipeID or not focusScrollPending then
                    f:SetScript("OnUpdate", nil)
                    return
                end
                if attempts > 120 then
                    f:SetScript("OnUpdate", nil)
                    return
                end
                if selectedCharacter and (
                    not isLoadingRecipes(selectedCharacter, profKey)
                    or #(GTD.GetProfessionRecipes(selectedCharacter, profKey)) > 0
                ) then
                    f:SetScript("OnUpdate", nil)
                    layoutRecipeView(selectedCharacter)
                end
            end)
        end
        return
    end
    loadingText:Hide()

    if #allRecipes == 0 then
        recipeColHeader:Hide()
        recipeViewportFrame:Hide()
        hideRecipeRowsFrom(1)
        noProfText:SetText(GTD.FormatNoProfessionRecipesMessage(
            entry, formatName, selectedProf and selectedProf.name))
        noProfText:Show()
        return
    end

    local filteredRecipes = GTD.FilterRecipesBySearch(allRecipes, recipeSearchText, function(recipe)
        return select(1, resolveRecipeDisplay(recipe))
    end)
    local showSkillCol = isRecipeDataAvailable()
    if not showSkillCol and recipeSortKey == "skill" then
        recipeSortKey = "recipe"
        recipeSortAscending = true
    end
    local recipes = GTD.SortRecipes(filteredRecipes, recipeSortKey, recipeSortAscending, {
        professionName = selectedProf and selectedProf.name,
        skillRank = selectedProf and selectedProf.rank or 0,
        getRecipeName = function(recipe)
            return select(1, resolveRecipeDisplay(recipe))
        end,
    })
    local preserveScroll = GTD.AreRecipeListsEqual(recipeViewport._lastRecipes, recipes)
    recipeViewport._lastRecipes = recipes
    applyRecipeSkillColumnLayout(showSkillCol)
    recipeColHeader:Show()
    updateRecipeHeaderSortIndicators()
    recipeViewportFrame:Show()
    local profName = selectedProf and selectedProf.name
    local skillRank = selectedProf and selectedProf.rank or 0
    local y = 0
    local width = math.max(1, (recipeScrollChild:GetWidth() or recipeBody:GetWidth() or 1))
    for i, recipe in ipairs(recipes) do
        local row = acquireRecipeRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", recipeScrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", recipeScrollChild, "TOPRIGHT", 0, -y)
        row.recipeID = recipe.recipeID
        row.resultItemID = recipe.resultItemID
        layoutRecipeRowColumns(row, showSkillCol)
        local enriched = GTD.EnrichRecipeEntry(recipe, profName, skillRank)
        local recipeName, iconPath, pendingItemID = resolveRecipeDisplay(recipe)
        row.recipeName = recipeName
        trackPendingRecipeIcon(pendingItemID)
        local highlightedName = GTD.FormatTextWithSearchHighlight(recipeName, nil, recipeSearchText)
        row.label:SetText(("|T%s:0|t %s"):format(iconPath, highlightedName))
        if showSkillCol then
            local RI = AltArmy and AltArmy.RecipeInfo
            if RI and RI.FormatSkillCell then
                row.skillCell:SetText(RI.FormatSkillCell(
                    enriched.recipeSkillRequired, enriched.skillRank, enriched.difficulty))
            else
                row.skillCell:SetText(GTD.FormatRecipeSkillCell(recipe, profName, skillRank))
            end
        end
        y = y + UI.RECIPE_ROW_HEIGHT
    end
    hideRecipeRowsFrom(#recipes + 1)
    recipeScrollChild:SetWidth(width)
    recipeScrollChild:SetHeight(math.max(1, y))
    if recipeViewport.UpdateRange then recipeViewport.UpdateRange() end
    if recipeHeaderFade then
        recipeHeaderFade:Update()
    end
    applyRecipeFocus(recipes, preserveScroll)
end

showGuildList = function()
    clearRecipeFocus()
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedProfIndex = 1
    recipeViewport._lastRecipes = nil
    clearPendingRecipeIcons()
    clearRecipeSearch()
    header:SetHeight(UI.HEADER_HEIGHT)
    if ME.notesWizardActive then
        ME.notesWizardActive = false
        ME.notesProposals = {}
        ME.notesIndex = 1
        ME.wizardMode = nil
        ME.editSourceGroup = nil
        ME.deleteConfirmPending = false
    end
    if ME.notesWizard then ME.notesWizard:Hide() end
    if ME.notesBackBtn then ME.notesBackBtn:Hide() end
    if ME.notesTitleFS then ME.notesTitleFS:Hide() end
    if ME.notesProgressFS then ME.notesProgressFS:Hide() end
    if ME.editOptions then ME.editOptions:Hide() end
    if ME.notesDeleteBtn then ME.notesDeleteBtn:Hide() end
    setListHeaderVisible(true)
    if ME.listBody then ME.listBody:Show() end
    listColHeader:Show()
    anchorListViewportBelowColHeader()
    listViewport:Show()
    recipeBody:Hide()
    emptyMsgRegion:Hide()
    profTabStrip:Hide()
    ME.hideProfIconTabs()
    updateListHeaderFade()
    if ME.syncListFooter then ME.syncListFooter() end
end

showRecipeView = function(entry, preferredProfKey, preferredProfName, preferredRecipeID)
    if ME.notesWizardActive then
        ME.closeNotesWizard(false)
    end
    selectedCharacter = entry
    selectedCharacterKey = memberKey(entry)
    selectedProfIndex = 1
    recipeViewport._lastRecipes = nil
    local Nav = AltArmy.SearchGuildNav
    if (preferredProfKey or preferredProfName) and Nav and Nav.FindProfessionIndex then
        selectedProfIndex = Nav.FindProfessionIndex(
            GTD.GetCraftingProfessions(entry), preferredProfKey, preferredProfName)
    end
    recipeSortKey, recipeSortAscending = GTD.GetDefaultRecipeSort(isRecipeDataAvailable())
    -- Quiet clear so OnTextChanged does not layout/wipe focus mid-open.
    clearRecipeSearchQuiet()
    if preferredRecipeID then
        focusRecipeID = preferredRecipeID
        focusScrollPending = true
        focusProfessionKey = preferredProfKey
        focusProfessionName = preferredProfName
    else
        clearRecipeFocus()
    end
    setListHeaderVisible(false)
    -- Hide only the sliding page; keep list children shown so an outgoing slide
    -- still paints the character list (SlideTransition re-Shows listBody).
    if ME.listBody then ME.listBody:Hide() end
    emptyText:Hide()
    updateListHeaderFade()
    recipeBody:Show()
    emptyMsgRegion:Show()
    if entry.source and entry.source ~= "local" then
        local Comm = AltArmy.GuildShareComm
        if Comm and Comm.RequestRecipesForCharacter then
            Comm.RequestRecipesForCharacter(entry.name, entry.realm, entry.source, entry.guid)
        end
        -- Online on WoW Forever: their professions are read from the server next (GuildLinkRead).
        local GLR = AltArmy.GuildLinkRead
        if GLR and GLR.RequestNow then
            pcall(GLR.RequestNow, entry)
        end
    end
    layoutRecipeView(entry)
    if ME.syncListFooter then ME.syncListFooter() end
end

-- Slide between listBody / recipeBody / notesWizard. Direction: to list = back, else forward.
ME.slideSwap = function(switchFn)
    if type(switchFn) ~= "function" then return end
    local ST = AltArmy.SlideTransition
    local function visiblePage()
        if ME.notesWizard and ME.notesWizard:IsShown() then
            return ME.notesWizard
        end
        if recipeBody:IsShown() then
            return recipeBody
        end
        if ME.listBody and ME.listBody:IsShown() then
            return ME.listBody
        end
        return nil
    end
    if not ST or not ST.Run or not frame:IsShown() then
        switchFn()
        return
    end
    local fromPage = visiblePage()
    switchFn()
    local toPage = visiblePage()
    if not fromPage or not toPage or fromPage == toPage then
        return
    end
    -- switchFn may leave listBody hidden; restore list chrome so the outgoing
    -- page still shows rows/header/footer while SlideTransition animates it.
    if fromPage == ME.listBody then
        listColHeader:Show()
        listViewport:Show()
        if ME.listFooter then
            ME.listFooter:Show()
            if ME.layoutListFooterButtons then ME.layoutListFooterButtons() end
        end
        if ME.updateListHeaderFade then ME.updateListHeaderFade() end
    end
    local direction = (toPage == ME.listBody) and "back" or "forward"
    local width = (listView.GetWidth and listView:GetWidth()) or 0
    if width <= 0 and toPage.GetWidth then
        width = toPage:GetWidth() or 0
    end
    ST.Run({
        from = fromPage,
        to = toPage,
        width = width,
        direction = direction,
    })
end

--- Open character recipe detail from search; Back returns via SearchGuildNav / Core.
function frame:ShowCharacterFromSearch(entry, professionKey, professionName, recipeID)
    if not entry then return end
    messageView:Hide()
    listView:Show()
    -- Show first so viewport sizes exist; suppress OnShow refresh which would race list layout.
    suppressGuildOnShowRefresh = true
    self:Show()
    suppressGuildOnShowRefresh = false
    showRecipeView(entry, professionKey, professionName, recipeID)
end

--- Leave search drill-in without switching to the guild member list as the active destination.
function frame:ClearSearchDrillIn()
    showGuildList()
    self:Hide()
end

backBtn:SetScript("OnClick", function()
    local Nav = AltArmy.SearchGuildNav
    if Nav and Nav.ShouldBackReturnToSearch and Nav.ShouldBackReturnToSearch()
        and AltArmy.ReturnToSearchFromGuildCharacter then
        AltArmy.ReturnToSearchFromGuildCharacter()
        return
    end
    local goList = function()
        showGuildList()
        refresh()
    end
    if ME.slideSwap then
        ME.slideSwap(goList)
    else
        goList()
    end
end)

guildBackBtn:SetScript("OnClick", function()
    selectedBrowseGuild = nil
    selectedCharacter = nil
    selectedCharacterKey = nil
    refresh()
end)

-- *** Refresh ***

local function showMessage(text, withButton)
    if ME.notesWizardActive then
        ME.closeNotesWizard(false)
    end
    selectedCharacter = nil
    selectedCharacterKey = nil
    selectedBrowseGuild = nil
    listView:Hide()
    messageView:Show()
    messageText:SetText(text)
    optionsBtn:SetShown(withButton and true or false)
    if ME.syncListFooter then ME.syncListFooter() end
end

local function ensureGuildRosterIncludesOffline()
    if SetGuildRosterShowOffline then
        pcall(SetGuildRosterShowOffline, true)
    end
    local Comm = AltArmy.GuildShareComm
    if Comm and Comm.RequestGuildRoster then
        Comm.RequestGuildRoster()
    elseif GuildRoster then
        pcall(GuildRoster)
    end
end

local function layoutList(groups, query, rosterByName, forceHoverMain)
    suppressMainRowHoverEvents = true
    hideGuildPickerRowsFrom(1)
    local mainIndex = 0
    local charIndex = 0
    local y = 0
    local width = math.max(1, (scrollChild:GetWidth() or listViewport:GetWidth() or 1))
    local activeQuery = GTD.NormalizeSearchQuery(query)
    rosterByName = rosterByName or {}
    local lastOnlineOpts = nil
    if not currentGuild() then
        lastOnlineOpts = { showUnknownWhenMissing = true }
    end

    local GSS = AltArmy.GuildShareSettings
    for _, g in ipairs(groups) do
        mainIndex = mainIndex + 1
        local isExpanded = expandedMains[g.main] and true or false
        local row = acquireMainRow(mainIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        local ownMain = GSS and GSS.GetMain and GSS.GetMain(groupPrefsRealm(g)) or nil
        local isOwn = GTD.IsOwnGroup and GTD.IsOwnGroup(g, ownMain)
        row.nameFS:SetText(GTD.FormatMainRowName(
            g, formatName, activeQuery ~= "" and activeQuery or nil, isOwn))
        local isOld = GTD.GroupHasOldData and GTD.GroupHasOldData(g)
        local isManual = GTD.GroupIsEntirelyManual and GTD.GroupIsEntirelyManual(g)
        layoutMainRowLeftIcons(
            row, isOld and true or false, g.pinned and true or false, isManual and true or false)
        row.countFS:SetText(GTD.FormatMainRowCount(g))
        if row.lastOnlineFS then
            local status = GTD.GetGroupLastOnlineStatus and GTD.GetGroupLastOnlineStatus(g, rosterByName)
            row.lastOnlineFS:SetText(
                (GTD.FormatRosterLastOnline and GTD.FormatRosterLastOnline(status, lastOnlineOpts)) or "")
        end
        row.groupMain = g.main
        row.settingsGroup = g
        row:SetScript("OnClick", function()
            expandedMains[g.main] = not expandedMains[g.main]
            layoutList(groups, query, rosterByName, g.main)
        end)
        y = y + UI.MAIN_ROW_HEIGHT

        if isExpanded then
            for _, m in ipairs(g.members) do
                charIndex = charIndex + 1
                local charRow = acquireCharRow(charIndex)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                charRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
                local charQuery = activeQuery ~= "" and activeQuery or nil
                charRow.nameFS:SetText(
                    (GTD.FormatCharacterNamePart and GTD.FormatCharacterNamePart(
                        m, formatName, charQuery))
                    or GTD.FormatCharacterName(m, formatName, charQuery))
                if charRow.levelFS then
                    local levelText = (GTD.FormatCharacterLevelSuffix
                        and GTD.FormatCharacterLevelSuffix(m.level, "full", UI.GRAY)) or ""
                    if levelText:sub(1, 1) == " " then
                        levelText = levelText:sub(2)
                    end
                    charRow.levelFS:SetText(levelText)
                end
                layoutCharRowLeftIcons(
                    charRow,
                    GTD.IsExplicitMain(m),
                    GTD.IsManualMember and GTD.IsManualMember(m))
                charRow.profFS:SetText(GTD.FormatProfessions(m, charQuery))
                if charRow.lastOnlineFS then
                    local key = GTD.NormalizeRosterName and GTD.NormalizeRosterName(m.name)
                    local status = key and rosterByName[key] or nil
                    charRow.lastOnlineFS:SetText(
                        (GTD.FormatRosterLastOnline and GTD.FormatRosterLastOnline(status, lastOnlineOpts)) or "")
                end
                charRow.memberEntry = m
                charRow:SetScript("OnClick", function()
                    if ME.slideSwap then
                        ME.slideSwap(function() showRecipeView(m) end)
                    else
                        showRecipeView(m)
                    end
                end)
                y = y + UI.CHAR_ROW_HEIGHT
            end
        end
        y = y + UI.GROUP_GAP
    end

    hideMainRowsFrom(mainIndex + 1)
    hideCharRowsFrom(charIndex + 1)
    if applyListColumnLayout then
        applyListColumnLayout()
    end
    suppressMainRowHoverEvents = false
    if forceHoverMain then
        local forced = nil
        for i = 1, #mainRowPool do
            local row = mainRowPool[i]
            if row and row:IsShown() and row.groupMain == forceHoverMain then
                forced = row
                break
            end
        end
        for i = 1, #mainRowPool do
            local row = mainRowPool[i]
            if row and row == forced and row.setMainRowHover then
                row.setMainRowHover(true)
            elseif row and row.clearMainRowHoverState then
                row.clearMainRowHoverState()
            end
        end
    else
        syncMainRowHoverFromMouse()
    end
    if syncMainRowSettingsIcons then
        syncMainRowSettingsIcons()
    end
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(1, y))
    if viewport.UpdateRange then viewport.UpdateRange() end
    updateListHeaderFade()
end

local function refreshImpl()
    if not frame:IsShown() then return end
    local GSS = AltArmy.GuildShareSettings
    local GSD = AltArmy.GuildShareData

    if not GSS or not GSS.IsSharingEnabled() then
        selectedCharacter = nil
        selectedCharacterKey = nil
        selectedBrowseGuild = nil
        showMessage("Guild sharing is disabled.\n\nEnable it to see the professions and characters"
            .. " your guildmates are sharing, and to share your own.", true)
        return
    end

    if currentGuild() then
        selectedBrowseGuild = nil
    elseif not selectedBrowseGuild then
        local autoBrowse = GTD.GetAutoBrowseGuild(collectCurrentRealmGuilds())
        if autoBrowse then
            selectedBrowseGuild = autoBrowse
        end
    end

    local guild = activeGuild()
    if not guild then
        selectedCharacter = nil
        selectedCharacterKey = nil
        if shouldShowGuildPicker() then
            messageView:Hide()
            listView:Show()
            showGuildList()
            Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)
            layoutGuildPicker(collectCurrentRealmGuilds())
            return
        end
        showMessage("You are not in a guild.", false)
        return
    end

    messageView:Hide()
    listView:Show()

    -- Incoming share/roster refreshes must not tear down an in-progress notes review.
    -- (showGuildList clears notesWizardActive, so this guard must run before that call.)
    if ME.notesWizardActive then
        return
    end

    local realm = currentRealm()
    local browseAllRealms = isBrowsingWithoutGuild()
    local rosterInfoMap = (GTD.BuildRosterInfoMap and GTD.BuildRosterInfoMap()) or nil
    local GMG = AltArmy.GuildManualGroups
    if rosterInfoMap and GMG and GMG.RefreshFromRosterInfo then
        GMG.RefreshFromRosterInfo(rosterInfoMap, realm)
    end
    local members = (GSD and GSD.GetGuildMembersForDisplay(guild, realm, browseAllRealms, rosterInfoMap)) or {}

    if selectedCharacterKey then
        local resolved
        for _, entry in ipairs(members) do
            if memberKey(entry) == selectedCharacterKey then
                resolved = entry
                break
            end
        end
        selectedCharacter = resolved or selectedCharacter
        if selectedCharacter then
            setListHeaderVisible(false)
            if ME.listBody then ME.listBody:Hide() end
            listColHeader:Hide()
            listViewport:Hide()
            emptyText:Hide()
            updateListHeaderFade()
            recipeBody:Show()
            emptyMsgRegion:Show()
            layoutRecipeView(selectedCharacter)
            return
        end
        selectedCharacterKey = nil
    end

    showGuildList()
    Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)

    local groups = GTD.ListedGroups(GTD.GroupMembersByMain(members))
    applyGroupUiPrefs(groups)
    local filtered = GTD.FilterGroups(groups, searchText)
    applySearchExpansion(filtered)

    local rosterByName = {}
    local canLookupOnline = currentGuild() and true or false
    ensureDefaultListSort(canLookupOnline)
    if canLookupOnline and GTD.BuildRosterLastOnlineMap then
        rosterByName = GTD.BuildRosterLastOnlineMap()
    end
    if GTD.SortGroups then
        filtered = GTD.SortGroups(filtered, listSortKey, listSortAscending, rosterByName)
    end

    if #filtered == 0 then
        hideMainRowsFrom(1)
        hideCharRowsFrom(1)
        scrollChild:SetHeight(1)
        if viewport.UpdateRange then viewport.UpdateRange() end
        updateListHeaderFade()
        if #members == 0 then
            emptyText:SetText("No guild data received yet.\n\n"
                .. "Data is exchanged as guildmates using Alt Army log in.")
        else
            emptyText:SetText("No guild members match your search.")
        end
        emptyText:Show()
        return
    end

    emptyText:Hide()
    layoutList(filtered, searchText, rosterByName)
end
refresh = refreshImpl

-- HookScript keeps SearchBoxTemplate's own handlers (clear button, Instructions placeholder).
searchEdit:HookScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    searchText = text
    Theme.UpdateEditBoxPlaceholderVisibility(searchEdit)
    refresh()
end)
searchEdit:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
searchEdit:HookScript("OnEscapePressed", function(box)
    Theme.ClearEditBoxText(box)
end)

recipeSearchEdit:HookScript("OnTextChanged", function(box)
    recipeSearchText = box:GetText() or ""
    Theme.UpdateEditBoxPlaceholderVisibility(recipeSearchEdit)
    updateRecipeSearchClearVisibility()
    if suppressRecipeSearchLayout or not selectedCharacter then
        return
    end
    -- Programmatic clears / Show of this field during search→character open must not
    -- wipe recipe focus. Only user-typed filter text dismisses the highlight.
    local trimmed = recipeSearchText:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
        clearRecipeFocus()
    end
    layoutRecipeView(selectedCharacter)
end)
recipeSearchEdit:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
recipeSearchEdit:HookScript("OnEscapePressed", function(box)
    Theme.ClearEditBoxText(box)
end)
updateRecipeSearchClearVisibility()

-- Refresh the tabard when guild identity changes while the tab is visible.
local tabardEvents = CreateFrame("Frame")
tabardEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
-- GUILDTABARD_UPDATE fires when the tabard changes; not present on every client build.
pcall(function() tabardEvents:RegisterEvent("GUILDTABARD_UPDATE") end)
tabardEvents:SetScript("OnEvent", function()
    if frame:IsShown() then
        updateTabard()
    end
end)

-- Roster last-online updates asynchronously after GuildRoster(); refresh when data arrives.
local rosterEvents = CreateFrame("Frame")
rosterEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterEvents:SetScript("OnEvent", function()
    if frame:IsShown() then
        refresh()
    end
end)

AltArmy.RefreshGuildTab = refresh
frame:SetScript("OnShow", function()
    if suppressGuildOnShowRefresh then
        return
    end
    ensureGuildRosterIncludesOffline()
    refresh()
end)
frame:HookScript("OnHide", function()
    if ME.notesWizardActive then
        ME.closeNotesWizard(false)
    end
end)
