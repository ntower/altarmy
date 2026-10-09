-- AltArmy TBC — Core: namespace, main frame, header, tabs, content frames

local ADDON_NAME = "Alt Army"
local ADDON_VERSION = "2.2.10"

-- Namespace
AltArmy = AltArmy or {}
AltArmy.Name = ADDON_NAME
AltArmy.Version = ADDON_VERSION
AltArmy.MainFrame = nil
AltArmy.TabFrames = {}
AltArmy.CurrentTab = "Summary"

-- Feature flags: unfinished features ship switched off until they are ready.
AltArmy.FeatureFlags = {
    economySupplyChain = false, -- Economy tab's Supply Chain sub-view (alt-army.com page)
}

AltArmyTBC_Options = AltArmyTBC_Options or {}

local Theme = AltArmy.Theme
local MainTabs = AltArmy.MainTabs

-- Height matches Forever's native CharacterFrame (CHARACTER_FRAME_HEIGHT = 484).
local FRAME_WIDTH = 670
local FRAME_HEIGHT = 484
local TAB_HEIGHT = 22 -- toolbar control height (settings button)
local CONTENT_INSET = 8
-- Toolbar row sits under the title bar, right of the portrait circle; content starts below it.
local LAYOUT = {
    toolbarLeft = 62,
    toolbarTop = -28,
    toolbarHeight = 29,
    contentTop = -65,
    -- Search box + settings button: nudge down to sit visually centered in the row.
    toolbarControlsY = -2,
    searchWidth = 360,
}

local setActiveTab -- forward-declare so header search scripts can call it
local exitSearchMode -- forward-declare; OpenGearTabFocused uses it when frame already visible
local UpdateSettingsButtonGlow -- forward-declare; defined after settings buttons exist
local searchModeHandlers = {}  -- enterSearchMode impl registered later (avoids nil if load errors)
local function enterSearchMode(trimmed)
    local fn = searchModeHandlers.enterSearchMode
    if fn then fn(trimmed) end
end
local lastTab = "Summary"
local pendingOpenTab = nil
local pendingGearFocusLink = nil

-- Create main frame: native portrait frame (rock background, NineSlice border, close button,
-- portrait circle, title bar). Falls back to the themed backdrop if the template is missing.
local nativeShell = AltArmy.NativeUI and AltArmy.NativeUI.GetCaps().portraitFrame
local main = CreateFrame("Frame", "AltArmyTBC_MainFrame", UIParent,
    nativeShell and "PortraitFrameTemplate" or "BackdropTemplate")
main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
main:SetPoint("CENTER", 0, 0)
main:SetFrameStrata("DIALOG")
main:SetFrameLevel(100)
if main.SetToplevel then
    main:SetToplevel(true)
end
main:SetMovable(true)
main:SetClampedToScreen(true)
main:EnableMouse(true)
main:HookScript("OnShow", function(f)
    if f.Raise then
        f:Raise()
    end
end)
if not nativeShell then
    Theme.ApplyBackdrop(main, "window")
end
main:Hide()

AltArmy.MainFrame = main

-- Dismiss UI when Escape is pressed (WoW closes topmost frame in UISpecialFrames)
if UISpecialFrames then
    tinsert(UISpecialFrames, "AltArmyTBC_MainFrame") -- never assign the global: that taints it
end

-- Drag by the title bar (template TitleContainer, or a top strip on the fallback shell).
local dragRegion = main.TitleContainer
if not dragRegion then
    dragRegion = CreateFrame("Frame", nil, main)
    dragRegion:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
    dragRegion:SetPoint("TOPRIGHT", main, "TOPRIGHT", -24, 0)
    dragRegion:SetHeight(24)
end
dragRegion:EnableMouse(true)
dragRegion:RegisterForDrag("LeftButton")
dragRegion:SetScript("OnDragStart", function()
    main:StartMoving()
end)
dragRegion:SetScript("OnDragStop", function()
    main:StopMovingOrSizing()
end)

-- Resize from the bottom-right corner (the chat window's size grabber), never below the stock
-- 670 x 484; the size is kept in AltArmyTBC_Options.window and applied when the window opens.
-- Tab content stretches with the window (the content area is anchored to its edges). Off until every
-- tab reflows: the Debug options' "Window resize" (/altarmy debug resize on|off) turns it on.
if main.SetResizeBounds then
    main:SetResizeBounds(FRAME_WIDTH, FRAME_HEIGHT)
elseif main.SetMinResize then
    main:SetMinResize(FRAME_WIDTH, FRAME_HEIGHT)
end

--- The saved window size, when it is a valid one no smaller than the stock size, clamped to the
--- screen so a size saved on a bigger monitor still opens with its grip reachable.
local function SavedWindowSize()
    local o = _G.AltArmyTBC_Options
    local w = type(o) == "table" and type(o.window) == "table" and o.window or nil
    if not w or type(w.width) ~= "number" or type(w.height) ~= "number" then return nil end
    if w.width < FRAME_WIDTH or w.height < FRAME_HEIGHT then return nil end
    local width, height = w.width, w.height
    if UIParent and UIParent.GetWidth then
        local maxW, maxH = UIParent:GetWidth(), UIParent:GetHeight()
        if maxW and maxW > 0 then width = math.min(width, math.max(FRAME_WIDTH, math.floor(maxW))) end
        if maxH and maxH > 0 then height = math.min(height, math.max(FRAME_HEIGHT, math.floor(maxH))) end
    end
    return width, height
end

local function ApplySavedWindowSize()
    local w, h = SavedWindowSize()
    if w then
        main:SetSize(w, h)
    end
end

local function SaveWindowSize()
    if type(_G.AltArmyTBC_Options) ~= "table" then return end
    local w, h = math.floor(main:GetWidth() + 0.5), math.floor(main:GetHeight() + 0.5)
    if w <= FRAME_WIDTH and h <= FRAME_HEIGHT then
        _G.AltArmyTBC_Options.window = nil -- back at the stock size: nothing to remember
    else
        _G.AltArmyTBC_Options.window = { width = w, height = h }
    end
end

local sizeGrip = CreateFrame("Button", nil, main)
sizeGrip:SetSize(16, 16)
sizeGrip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 4)
sizeGrip:SetFrameLevel(main:GetFrameLevel() + 200)
sizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
sizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
sizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
sizeGrip:SetScript("OnMouseDown", function()
    main:StartSizing("BOTTOMRIGHT")
end)
sizeGrip:SetScript("OnMouseUp", function()
    main:StopMovingOrSizing()
    SaveWindowSize()
end)
sizeGrip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Drag to resize", 1, 1, 1)
    GameTooltip:Show()
end)
sizeGrip:SetScript("OnLeave", function() GameTooltip:Hide() end)
sizeGrip:Hide()

--- Shows the grip and the saved size when the debug option is on; otherwise hides the grip and puts
--- the window back to its stock size, keeping the saved size for when it is turned on again.
AltArmy.ApplyWindowResize = function()
    local D = AltArmy.Debug
    local on = D and D.IsWindowResizeEnabled and D.IsWindowResizeEnabled() or false
    main:SetResizable(on)
    sizeGrip:SetShown(on)
    if on then
        ApplySavedWindowSize()
    else
        main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    end
end
main:HookScript("OnShow", AltArmy.ApplyWindowResize)
-- Tab content that sits in the window's bottom-right corner keeps clear of the grip.
AltArmy.WINDOW_GRIP_INSET = 16
AltArmy.ResetWindowSize = function()
    main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    SaveWindowSize()
end

-- Title bar text + portrait icon follow the active tab (see applyWindowChrome).
local fallbackTitle
if not main.SetTitle then
    fallbackTitle = main:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    fallbackTitle:SetPoint("TOP", main, "TOP", 0, -8)
end
-- Guild tab: the portrait shows the player's guild crest (clipped to the portrait circle),
-- over an opaque backing so the crest's transparent edges don't show the world through.
local portraitCrest
local function portraitTexture()
    local container = main.PortraitContainer
    return (container and container.portrait) or main.portrait
end
local function refreshPortraitCrest(def)
    local GuildCrest = AltArmy.GuildCrest
    local pt = portraitTexture()
    if not (def and def.guildCrest and GuildCrest and pt) then
        if portraitCrest then portraitCrest:SetShown(false) end
        return false
    end
    if not portraitCrest then
        local layer, sub = pt:GetDrawLayer()
        portraitCrest = GuildCrest.CreateLayers(pt:GetParent(), pt, {
            layer = layer,
            subLevel = math.min((sub or 0) + 1, 4),
            mask = main.PortraitContainer and main.PortraitContainer.CircleMask,
            backdrop = { 0, 0, 0, 1 },
        })
    end
    return portraitCrest:Refresh()
end

local function applyWindowChrome(tabName)
    local def = MainTabs.Get(tabName)
    local text = MainTabs.Title(tabName)
    if main.SetTitle then
        main:SetTitle(text)
    elseif fallbackTitle then
        fallbackTitle:SetText(text)
    end
    local crestDrawn = refreshPortraitCrest(def)
    local pt = portraitTexture()
    if pt and pt.SetAlpha then
        pt:SetAlpha(crestDrawn and 0 or 1)
    end
    if def and not crestDrawn and main.SetPortraitToAsset then
        main:SetPortraitToAsset(def.icon)
    end
end

local closeBtn = main.CloseButton
if not closeBtn then
    closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -2, -2)
end
_G.AltArmyTBC_HeaderCloseButton = closeBtn
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- Tab frames (content area) start CONTENT_INSET from the window edge; the toolbar starts right
-- of the portrait. Tabs that hang controls into the toolbar row (Cooldowns sub-view tabs) use this.
AltArmy.MainToolbarInsetX = LAYOUT.toolbarLeft - CONTENT_INSET

-- Toolbar row: search-mode Filter dropdown, global search and settings button (right).
local toolbar = CreateFrame("Frame", nil, main)
toolbar:SetPoint("TOPLEFT", main, "TOPLEFT", LAYOUT.toolbarLeft, LAYOUT.toolbarTop)
toolbar:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, LAYOUT.toolbarTop)
toolbar:SetHeight(LAYOUT.toolbarHeight)

local headerSearchEdit = Theme.CreateSearchBox(toolbar, {
    name = "AltArmyTBC_HeaderSearchEdit",
    width = LAYOUT.searchWidth,
    placeholder = "Search for items or recipes",
})

headerSearchEdit:HookScript("OnEnterPressed", function(box)
    box:ClearFocus()
    local query = box:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" and enterSearchMode then
        enterSearchMode(trimmed)
    end
end)
headerSearchEdit:HookScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)
-- OnTextChanged registered below after enterSearchMode/exitSearchMode are defined

local function itemLinksReferToSameItem(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local function itemId(link)
        return tonumber(tostring(link):match("item:(%d+)"))
    end
    local idA, idB = itemId(a), itemId(b)
    return idA ~= nil and idA == idB
end

-- Expose for clearing header search and switching to Summary (e.g. from other code)
function AltArmy.OpenGearTabFocused(itemLink)
    pendingOpenTab = "Gear"
    pendingGearFocusLink = itemLink
    lastTab = "Gear"
    if not AltArmy.MainFrame or not AltArmy.MainFrame.Show then return end
    if AltArmy.MainFrame.IsShown and AltArmy.MainFrame:IsShown() then
        local gearFrame = AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if AltArmy.CurrentTab == "Gear"
            and gearFrame
            and gearFrame.GetFocusedItemLink
            and itemLink
            and itemLinksReferToSameItem(gearFrame:GetFocusedItemLink(), itemLink) then
            pendingOpenTab = nil
            pendingGearFocusLink = nil
            AltArmy.MainFrame:Hide()
            return
        end
        pendingOpenTab = nil
        pendingGearFocusLink = nil
        if headerSearchEdit and headerSearchEdit.SetText then
            headerSearchEdit:SetText("")
        end
        exitSearchMode()
        setActiveTab("Gear")
        if gearFrame and gearFrame.FocusItem and itemLink then
            gearFrame:FocusItem(itemLink)
        end
        return
    end
    AltArmy.MainFrame:Show()
end

function AltArmy.SwitchToSummaryTab()
    lastTab = "Summary"
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
end

--- Open the main UI on a named tab (e.g. "Cooldowns", "Gear"). Clears header search.
--- If the frame is already shown, switches immediately; otherwise sets pendingOpenTab and Shows.
function AltArmy.ShowMainTab(tabName)
    if not tabName or tabName == "" then
        tabName = "Summary"
    end
    if not AltArmy.MainFrame or not AltArmy.MainFrame.Show then
        return
    end
    lastTab = tabName
    if AltArmy.MainFrame.IsShown and AltArmy.MainFrame:IsShown() then
        if headerSearchEdit and headerSearchEdit.SetText then
            headerSearchEdit:SetText("")
        end
        exitSearchMode()
        setActiveTab(tabName)
        return
    end
    pendingOpenTab = tabName
    AltArmy.MainFrame:Show()
end

-- Toolbar settings button: one button for every tab, routed through MainTabs[tab].settings.
local settingsBtn = CreateFrame("Button", nil, toolbar)
settingsBtn:SetSize(TAB_HEIGHT, TAB_HEIGHT)
settingsBtn:SetPoint("RIGHT", toolbar, "RIGHT", -2, LAYOUT.toolbarControlsY)
do
    local icon = settingsBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(settingsBtn)
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    local highlight = settingsBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(settingsBtn)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    settingsBtn:SetHighlightTexture(highlight)
    -- Same checked overlay as spellbook/side tabs marks "settings open" / "filters active".
    local active = settingsBtn:CreateTexture(nil, "OVERLAY")
    active:SetAllPoints(settingsBtn)
    active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    active:SetBlendMode("ADD")
    active:Hide()
    settingsBtn.activeOverlay = active
end
settingsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Settings")
end)
settingsBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function isRecipeFilterActive()
    local SS = AltArmy.SearchSettings
    return SS and SS.IsAnyRecipeFilterActive and SS.IsAnyRecipeFilterActive() or false
end

--- Settings entry + tab key for whatever the window currently shows (Search while searching).
local function activeSettings()
    local key = searchModeHandlers.inSearchMode and "Search" or AltArmy.CurrentTab
    local def = MainTabs.Get(key)
    local settings = def and def.settings
    if settings and settings.isAvailable then
        local frame = AltArmy.TabFrames[key]
        local isAvailable = frame and frame[settings.isAvailable]
        if not (isAvailable and isAvailable(frame)) then
            return nil, key
        end
    end
    return settings, key
end

local function isSettingsActive()
    local settings, key = activeSettings()
    if not settings then return false end
    if key == "Search" and isRecipeFilterActive() then return true end
    local frame = AltArmy.TabFrames[key]
    local isShown = settings.isShown and frame and frame[settings.isShown]
    return isShown and isShown(frame) and true or false
end

--- Header item/recipe search shows on tabs that opt in (MainTabs headerSearch) and while in
--- search mode (including Guild drill-in from a search result).
local function isHeaderSearchShown()
    if searchModeHandlers.inSearchMode then return true end
    local def = MainTabs.Get(AltArmy.CurrentTab)
    return def and def.headerSearch and true or false
end

--- Right side of the toolbar: [Filters Active] [Filter] [search] [settings]; search slides right when
--- the active tab has no settings.
local function layoutToolbarRight()
    local showSearch = isHeaderSearchShown()
    headerSearchEdit:SetShown(showSearch)
    if not showSearch and headerSearchEdit.HasFocus and headerSearchEdit:HasFocus() then
        headerSearchEdit:ClearFocus()
    end
    headerSearchEdit:ClearAllPoints()
    if settingsBtn:IsShown() then
        headerSearchEdit:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    else
        headerSearchEdit:SetPoint("RIGHT", toolbar, "RIGHT", 0, LAYOUT.toolbarControlsY)
    end
    local filterButton = searchModeHandlers.searchFilterButton
    if filterButton then
        -- Filter shows beside the search box once it has at least one character.
        local hasText = (headerSearchEdit:GetText() or "") ~= ""
        local showFilter = showSearch and hasText
        filterButton:SetShown(showFilter)
        if not showFilter and searchModeHandlers.closeSearchFilter then
            searchModeHandlers.closeSearchFilter()
        end
        filterButton:ClearAllPoints()
        filterButton:SetPoint("RIGHT", headerSearchEdit, "LEFT", -6, 0)
    end
    local label = searchModeHandlers.searchFiltersActiveLabel
    if label then
        label:ClearAllPoints()
        if filterButton and filterButton:IsShown() then
            label:SetPoint("RIGHT", filterButton, "LEFT", -6, 0)
        else
            label:SetPoint("RIGHT", headerSearchEdit, "LEFT", -8, 0)
        end
    end
end

UpdateSettingsButtonGlow = function()
    local settings = activeSettings()
    settingsBtn:SetShown(settings ~= nil)
    settingsBtn.activeOverlay:SetShown(settings ~= nil and isSettingsActive())
    local label = searchModeHandlers.searchFiltersActiveLabel
    if label then
        label:SetShown(searchModeHandlers.inSearchMode and isRecipeFilterActive() or false)
    end
    layoutToolbarRight()
end

AltArmy.UpdateSearchSettingsButtonGlow = UpdateSettingsButtonGlow

--- Put a tab's own search/filter box in the toolbar slot the header search occupies (same
--- position, width and font). The header search is hidden on those tabs. parent should be the
--- tab frame so the box hides with its tab; tab content frames sit below the toolbar row.
function AltArmy.PlaceInToolbarSearchSlot(edit, parent)
    if not edit then return end
    if parent then
        edit:SetParent(parent)
        edit:SetFrameLevel(parent:GetFrameLevel() + 50)
    end
    edit:ClearAllPoints()
    edit:SetHeight(headerSearchEdit:GetHeight())
    edit:SetPoint("LEFT", headerSearchEdit, "LEFT", 0, 0)
    edit:SetPoint("RIGHT", headerSearchEdit, "RIGHT", 0, 0)
    Theme.MatchSearchBoxFont(edit, headerSearchEdit)
end

--- Put a tab's own control (e.g. a Filter dropdown button) at the right end of the toolbar slot the header
--- search occupies, its natural width kept, `offsetX` pixels further right (negative: left). parent should be
--- the tab's (or view's) frame so it hides with it.
function AltArmy.PlaceInToolbarRight(widget, parent, offsetX)
    if not widget then return end
    if parent then
        widget:SetParent(parent)
        widget:SetFrameLevel(parent:GetFrameLevel() + 50)
    end
    widget:ClearAllPoints()
    widget:SetPoint("RIGHT", headerSearchEdit, "RIGHT", offsetX or 0, 0)
end

settingsBtn:SetScript("OnClick", function()
    local settings, key = activeSettings()
    if not settings then return end
    if settings.optionsKey then
        if AltArmy.OpenInterfaceOptions then
            AltArmy.OpenInterfaceOptions(settings.optionsKey)
        end
    else
        local frame = AltArmy.TabFrames[key]
        local toggle = frame and frame[settings.toggle]
        if toggle then
            toggle(frame)
        end
    end
    UpdateSettingsButtonGlow()
end)

-- Side tabs (right edge, CharacterFrame style); forward-declared so setActiveTab can use them.
local sideTabs

setActiveTab = function(tabName)
    AltArmy.CurrentTab = tabName
    for name, frame in pairs(AltArmy.TabFrames) do
        frame:SetShown(name == tabName)
    end
    if sideTabs then
        sideTabs:SetSelected(tabName)
    end
    applyWindowChrome(tabName)
    UpdateSettingsButtonGlow()
end

--- Let the clicked tab react to the click itself (e.g. Gear loads an item held on the cursor).
local function notifySideTabClicked(tabName)
    local tabFrame = AltArmy.TabFrames[tabName]
    if AltArmy.CurrentTab == tabName and tabFrame and tabFrame.OnSideTabClicked then
        tabFrame:OnSideTabClicked()
    end
end

--- Side tab click: leaves search mode (clearing the query) or switches tabs.
local function onSideTabSelected(tabName)
    local query = headerSearchEdit:GetText() or ""
    if searchModeHandlers.inSearchMode or query:match("%S") then
        lastTab = tabName
        -- Clearing fires OnTextChanged -> exitSearchMode -> setActiveTab(lastTab).
        headerSearchEdit:SetText("")
        if searchModeHandlers.inSearchMode then
            exitSearchMode()
        end
        notifySideTabClicked(tabName)
        return
    end
    if AltArmy.CurrentTab ~= tabName then
        setActiveTab(tabName)
    end
    notifySideTabClicked(tabName)
end

sideTabs = AltArmy.SideTabs.Create(main, MainTabs.List(), { onSelect = onSideTabSelected })
AltArmy.MainSideTabs = sideTabs

-- Guild tab: only visible when the guildShare feature flag is on and the current realm has at
-- least one guilded character. Debug.lua / DataStore load after Core, so we evaluate lazily (on
-- frame show / when the flag or guild membership changes) rather than at load.
local function updateGuildTabVisibility()
    local GTD = AltArmy.GuildTabData
    local on = GTD and GTD.CanShowGuildTab and GTD.CanShowGuildTab()
    sideTabs:SetTabShown("Guild", on and true or false)
    if on then
        sideTabs:RefreshCrest("Guild")
    end
    if not on and AltArmy.CurrentTab == "Guild" then
        setActiveTab("Summary")
    end
end
AltArmy.UpdateGuildTabVisibility = updateGuildTabVisibility
updateGuildTabVisibility()

--- Whether a side tab is there to open (Economy is hidden off WoW Forever, Guild without guild sharing).
function AltArmy.IsMainTabAvailable(tabName)
    if not (AltArmy.TabFrames and AltArmy.TabFrames[tabName] and sideTabs.tabs[tabName]) then return false end
    if tabName == "Guild" then
        updateGuildTabVisibility() -- otherwise only evaluated when the window opens
    end
    return not sideTabs.hidden[tabName]
end

--- `/alta <tab> [view]` (UI/Options.lua): open the window on a tab, and on one of its sub-views when named.
--- A tab or view that isn't there does nothing.
function AltArmy.OpenMainTabView(tabName, viewName)
    if not AltArmy.IsMainTabAvailable(tabName) then return end
    local frame = AltArmy.TabFrames[tabName]
    local def = MainTabs.Get(tabName)
    local setView = viewName and def and def.setView and frame[def.setView]
    if viewName and not (setView and frame.ViewTabs and frame.ViewTabs.buttons[viewName]) then return end
    -- Opening a closed window shows the tab on its remembered view first; the named one replaces it.
    AltArmy.ShowMainTab(tabName)
    if setView then
        setView(viewName)
    end
end

-- Content area: one frame per tab, below the toolbar row.
local contentArea = CreateFrame("Frame", nil, main)
contentArea:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, LAYOUT.contentTop)
contentArea:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

for _, tabName in ipairs(MainTabs.ORDER) do
    local cf = CreateFrame("Frame", nil, contentArea)
    cf:SetAllPoints(contentArea)
    cf:SetShown(tabName == "Summary")
    AltArmy.TabFrames[tabName] = cf
end

setActiveTab("Summary")

-- Search content frame (no tab button; shown when search box has text)
local searchFrame = CreateFrame("Frame", nil, contentArea)
searchFrame:SetAllPoints(contentArea)
searchFrame:Hide()
AltArmy.TabFrames.Search = searchFrame

-- Register enterSearchMode handler early (before check buttons etc.) so it exists even if later UI errors.
-- Handler reads refs from searchModeHandlers as we fill them in below.
searchModeHandlers.enterSearchMode = function(trimmed)
    if not searchModeHandlers.searchFilterButton then
        return
    end
    lastTab = AltArmy.CurrentTab
    searchModeHandlers.inSearchMode = true
    -- The tab search was started from (Summary) stays highlighted; clicking any side tab leaves search.
    sideTabs:SetSelected(lastTab)
    applyWindowChrome("Search")
    for name, tabFrame in pairs(AltArmy.TabFrames) do
        if name ~= "Search" then
            tabFrame:Hide()
        end
    end
    if AltArmy.TabFrames.Search then
        AltArmy.TabFrames.Search:Show()
        if AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
    UpdateSettingsButtonGlow()
end

-- Search "Filter" dropdown (left of the search box once it has text): Items /
-- Recipes / Guild recipes checkboxes and Advanced (opens the search settings panel).
AltArmy.SearchCategories = AltArmy.SearchCategories or { Items = true, Recipes = true }
local function refreshSearchIfActive()
    if AltArmy.TabFrames.Search and AltArmy.TabFrames.Search:IsShown() and headerSearchEdit then
        local query = headerSearchEdit:GetText()
        local trimmed = query and query:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" and AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
end

local function searchFilterState()
    local SS = AltArmy.SearchSettings
    local showGuild = SS and SS.CanShowIncludeGuildmatesToggle and SS.CanShowIncludeGuildmatesToggle() or false
    return {
        items = AltArmy.SearchCategories.Items,
        recipes = AltArmy.SearchCategories.Recipes,
        showGuild = showGuild,
        guild = showGuild and SS.IsIncludeGuildmatesEnabled and SS.IsIncludeGuildmatesEnabled() or false,
    }
end

local function openSearchSettingsPanel()
    local searchTab = AltArmy.TabFrames.Search
    if searchTab and searchTab.IsSearchSettingsShown and searchTab.ToggleSearchSettings
        and not searchTab:IsSearchSettingsShown() then
        searchTab:ToggleSearchSettings()
    end
    UpdateSettingsButtonGlow()
end

local searchFilterDropdown = Theme.CreateFilterDropdown({
    parent = toolbar,
    text = "Filter",
    getEntries = function()
        local SFM = AltArmy.SearchFilterMenu
        return SFM and SFM.BuildEntries(searchFilterState()) or {}
    end,
    onToggle = function(key, checked)
        if key == "Items" then
            AltArmy.SearchCategories.Items = checked
        elseif key == "Recipes" then
            AltArmy.SearchCategories.Recipes = checked
        elseif key == "GuildRecipes" then
            local SS = AltArmy.SearchSettings
            if SS and SS.SetIncludeGuildmatesEnabled then
                SS.SetIncludeGuildmatesEnabled(checked)
            end
        end
        refreshSearchIfActive()
    end,
    onSelect = function(key)
        if key == "Advanced" then
            openSearchSettingsPanel()
        end
    end,
})
local searchFilterButton = searchFilterDropdown.button
searchFilterButton:Hide()
searchModeHandlers.searchFilterButton = searchFilterButton

local function closeSearchFilter()
    if searchFilterDropdown.Close then searchFilterDropdown.Close() end
end
searchModeHandlers.closeSearchFilter = closeSearchFilter

--- Guild sharing toggled in Options: the Filter menu re-reads state on open; nothing to redraw.
function AltArmy.RefreshSearchCategoryBar()
end

-- "Filters Active" sits left of the search box (anchored in layoutToolbarRight).
local searchFiltersActiveLabel = toolbar:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
searchFiltersActiveLabel:SetJustifyH("RIGHT")
searchFiltersActiveLabel:SetText("Filters Active")
searchFiltersActiveLabel:Hide()
searchModeHandlers.searchFiltersActiveLabel = searchFiltersActiveLabel

exitSearchMode = function()
    searchModeHandlers.inSearchMode = false
    closeSearchFilter()
    if AltArmy.TabFrames.Search
        and AltArmy.TabFrames.Search.IsSearchSettingsShown
        and AltArmy.TabFrames.Search:IsSearchSettingsShown()
        and AltArmy.TabFrames.Search.ToggleSearchSettings then
        AltArmy.TabFrames.Search:ToggleSearchSettings()
    end
    if AltArmy.TabFrames.Search then AltArmy.TabFrames.Search:Hide() end
    if AltArmy.TabFrames[lastTab] then AltArmy.TabFrames[lastTab]:Show() end
    setActiveTab(lastTab)
end

--- Closing Search settings with an empty query returns to the tab search started from.
function AltArmy.OnSearchSettingsClosed()
    if not searchModeHandlers.inSearchMode then return end
    local query = headerSearchEdit:GetText() or ""
    if not query:match("%S") then
        exitSearchMode()
    end
end

--- Show Guild character recipe view from a search recipe row; Back returns to search.
--- Optional professionKey/professionName select the matching profession tab.
--- Optional recipeID focuses/scrolls to that recipe row.
function AltArmy.OpenGuildCharacterFromSearch(characterName, realm, professionKey, professionName, recipeID)
    local Nav = AltArmy.SearchGuildNav
    if not Nav or not Nav.ResolveGuildMember then return false end
    local entry = Nav.ResolveGuildMember(characterName, realm)
    if not entry then return false end
    local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
    if not guildFrame or not guildFrame.ShowCharacterFromSearch then return false end

    Nav.Begin()
    closeSearchFilter()
    if AltArmy.TabFrames.Search then
        AltArmy.TabFrames.Search:Hide()
    end
    guildFrame:ShowCharacterFromSearch(entry, professionKey, professionName, recipeID)
    return true
end

--- Called by Guild Back when the character view was opened from search.
function AltArmy.ReturnToSearchFromGuildCharacter()
    local Nav = AltArmy.SearchGuildNav
    if Nav then Nav.End() end
    local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
    if guildFrame and guildFrame.ClearSearchDrillIn then
        guildFrame:ClearSearchDrillIn()
    elseif guildFrame then
        guildFrame:Hide()
    end
    local query = headerSearchEdit and headerSearchEdit:GetText() or ""
    local trimmed = query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        exitSearchMode()
    else
        enterSearchMode(trimmed)
    end
end

local function applySearchBoxState()
    local query = headerSearchEdit:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    Theme.UpdateEditBoxPlaceholderVisibility(headerSearchEdit)

    local Nav = AltArmy.SearchGuildNav
    local navAction = Nav and Nav.OnHeaderSearchTextChanged and Nav.OnHeaderSearchTextChanged(trimmed) or "ignore"
    if navAction ~= "ignore" then
        local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
        if guildFrame and guildFrame.ClearSearchDrillIn then
            guildFrame:ClearSearchDrillIn()
        elseif guildFrame then
            guildFrame:Hide()
        end
    end

    if trimmed == "" then
        exitSearchMode()
    else
        enterSearchMode(trimmed)  -- switch to search results on any character
    end
end

-- HookScript keeps SearchBoxTemplate's own handlers (clear button, Instructions placeholder).
headerSearchEdit:HookScript("OnTextChanged", applySearchBoxState)
headerSearchEdit:HookScript("OnEditFocusGained", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
headerSearchEdit:HookScript("OnEditFocusLost", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
Theme.UpdateEditBoxPlaceholderVisibility(headerSearchEdit)

main:SetScript("OnShow", function()
    updateGuildTabVisibility()
    local openTab = pendingOpenTab or "Summary"
    pendingOpenTab = nil
    lastTab = openTab
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
    exitSearchMode()
    if AltArmy.TabFrames and AltArmy.TabFrames[openTab] then
        setActiveTab(openTab)
    else
        setActiveTab("Summary")
    end
    if openTab == "Gear" and pendingGearFocusLink then
        local gearFrame = AltArmy.TabFrames and AltArmy.TabFrames.Gear
        local link = pendingGearFocusLink
        pendingGearFocusLink = nil
        if gearFrame and gearFrame.FocusItem then
            gearFrame:FocusItem(link)
        end
    end
    local SD = AltArmy.SearchData
    if SD and SD.StartIndexPrewarm then
        SD.StartIndexPrewarm()
    end
end)
