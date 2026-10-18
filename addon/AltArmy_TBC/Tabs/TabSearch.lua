-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then
    return
end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
-- Layout / list metrics packed to stay under Lua 5.1's 200-local / function limit.
local UI = {
    PAD = 4,
    SECTION_INSET = Theme.TAB_SECTION_INSET,
    SECTION_GAP = Theme.SECTION_GAP,
    ROW_HEIGHT = 20,
    -- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
    OVERLAY_ICON_SIZE = 14,
    HEADER_HEIGHT = 18,
    HEADER_ROW_GAP = 3, -- space between section header and first data row
    -- Extra space between the last recipe row and the "You may also be interested in" header.
    SECTION_GAP_BEFORE_TOOLTIP = 2,
    HORIZONTAL_SCROLL_BAR_HEIGHT = 20,
    TOOLTIP_CHUNK_SIZE = 80,
    GRID_SPLIT_FRACTION = 0.6,
    SEARCH_SETTINGS_WIDTH_TRIM = 60,
    SETTINGS_ROW_HEIGHT = 22,
    RECIPE_LEVEL_LABEL_GAP = 6,
    RECIPE_LEVEL_MIN_MAX_GAP = 12,
    RECIPE_LEVEL_RESET_GAP = 4,
    RECIPE_LEVEL_MIN_EDIT_WIDTH = 28,
    RECIPE_LEVEL_DEFAULT_EDIT_WIDTH = 40,
    RECIPE_LEVEL_ROW_GAP = 10,
    FILTER_SECTION_GAP = 12,
    FILTER_DROPDOWN_GAP = 4,
    FILTER_DROPDOWN_POPUP_PAD_LEFT = 10,
    FILTER_DROPDOWN_POPUP_PAD_TOP = 6,
    FILTER_DROPDOWN_POPUP_PAD_BOTTOM = 8,
    FILTER_DROPDOWN_POPUP_PAD_RIGHT = 8,
    FILTER_DROPDOWN_TEXT_INSET = 10,
    -- Bumped by ApplySearchColumnLayout; pooled rows re-anchor their cells when stale.
    colLayoutGen = 0,
    -- Per-refresh fill context for ScrollBox row initializers (set in UpdateResults).
    rowCtx = { showRealmSuffix = false, highlightOpts = {}, tooltipOpts = {} },
}

local SD = AltArmy.SearchEngine or AltArmy.SearchData
if not SD or not (SD.SearchItems or SD.SearchWithLocationGroups) or not SD.SearchRecipes then
    return
end
-- Results are a virtualized WowScrollBoxList (TBC Anniversary and Forever both ship it).
do
    local caps = AltArmy.NativeUI and AltArmy.NativeUI.GetCaps and AltArmy.NativeUI.GetCaps()
    if not (caps and caps.scrollBoxList) or not AltArmy.SearchListModel then
        return
    end
end

local GTD = AltArmy.GuildTabData
local RF = AltArmy.RealmFilter

local function GlobalRealmFilterValue()
    local G = AltArmy.GlobalRealmFilter
    if G and G.Get then
        return G.Get()
    end
    return "all"
end

--- True if the account has characters on more than one realm (used to decide whether to show realm suffix).
local function AccountHasMultipleRealms()
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms then return false end
    local realms = DS:GetRealms()
    local n = 0
    for _ in pairs(realms or {}) do
        n = n + 1
        if n > 1 then return true end
    end
    return false
end

local ItemActions = AltArmy.ItemActions

--- Route a left-click on an item result row: Ctrl previews in the Dressing Room, Shift links to chat.
local function HandleItemRowClick(itemLinkOrID, button)
    if not ItemActions then return end
    local action = ItemActions.GetClickAction(
        button,
        IsShiftKeyDown and IsShiftKeyDown() or false,
        IsControlKeyDown and IsControlKeyDown() or false)
    if action == "preview" then
        ItemActions.PreviewInDressingRoom(itemLinkOrID)
    elseif action == "chatlink" then
        ItemActions.InsertLinkIntoChat(itemLinkOrID)
    end
end

-- Recipe link for display/tooltip: the crafted item (resultItemID) is reliable — recipeID
-- isn't reliably a spell or item ID itself (it can be a pattern/link id in an unrelated
-- namespace depending on profession/client), so guessing off it can link the wrong thing
-- entirely. Only fall back to recipeID-based guesses when resultItemID is unavailable.
local function GetRecipeLink(recipeID, resultItemID)
    local compatGetItemInfo = AltArmy.DataStore and AltArmy.DataStore.CompatGetItemInfo
    if resultItemID and compatGetItemInfo then
        local _, link = compatGetItemInfo(resultItemID)
        if link and link ~= "" then return link end
    end
    if not recipeID then return nil end
    local compatGetSpellLink = AltArmy.DataStore and AltArmy.DataStore.CompatGetSpellLink
    if compatGetSpellLink then
        local link = compatGetSpellLink(recipeID)
        if link and link ~= "" then return link end
    end
    if compatGetItemInfo then
        local _, link = compatGetItemInfo(recipeID)
        if link and link ~= "" then return link end
    end
    return nil
end

-- Hidden edit box for header search flow (SearchWithQuery sets text, DoSearch reads it)
local searchEdit = CreateFrame("EditBox", "AltArmyTBC_SearchEditBox", frame)
searchEdit:SetPoint("LEFT", frame, "LEFT", -1000, 0)
searchEdit:SetSize(1, 1)
searchEdit:Hide()
searchEdit:SetAutoFocus(false)
searchEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    if frame.DoSearch then frame:DoSearch() end
end)
searchEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

local SearchColumns = AltArmy.SearchColumns
local colOrder = SearchColumns and SearchColumns.ITEM_COLUMN_ORDER
    or { "Item", "Character", "Total" }
local recipeColOrder = SearchColumns and SearchColumns.RECIPE_COLUMN_ORDER
    or { "Recipe", "Character", "Skill" }
local colWidths = {}
local recipeColWidths = {}

local function SyncSearchColumnWidths(settingsOpen, fitWidth)
    local item = SearchColumns and SearchColumns.GetItemColumnWidths(settingsOpen, fitWidth)
        or { Item = 344, Character = 180, Total = 72 }
    local recipe = SearchColumns and SearchColumns.GetRecipeColumnWidths(settingsOpen, fitWidth)
        or { Recipe = 344, Character = 180, Skill = 72 }
    for k, v in pairs(item) do
        colWidths[k] = v
    end
    for k, v in pairs(recipe) do
        recipeColWidths[k] = v
    end
end

SyncSearchColumnWidths(false)

local function SetCharacterCellTruncated(cell, namePartColored, suffixText, maxTotalWidth)
    if TruncateFontString then
        TruncateFontString(cell, namePartColored, maxTotalWidth, {
            preserveColorCodes = true,
            suffix = suffixText,
        })
    else
        cell:SetText((namePartColored or "") .. (suffixText or ""))
    end
end

local function SetItemCellTruncated(cell, itemName, countSuffix, iconPrefix, maxTotalWidth)
    if TruncateFontString then
        TruncateFontString(cell, itemName, maxTotalWidth, {
            prefix = iconPrefix or "",
            suffix = countSuffix,
            preserveColorCodes = itemName:find("|c", 1, true) ~= nil,
        })
    else
        cell:SetText((iconPrefix or "") .. itemName .. countSuffix)
    end
end

local function buildCharacterNamePart(entry, showRealmSuffix)
    local name = entry.characterName or ""
    if RF and RF.formatColoredCharacterNameRealm then
        return RF.formatColoredCharacterNameRealm(name, entry.realm, showRealmSuffix, entry.classFile)
    end
    local r, g, b = 1, 0.82, 0
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
    end
    return CC and CC.formatHex and CC.formatHex(r, g, b, name)
        or string.format(
            "|cFF%02x%02x%02x%s|r",
            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255),
            name
        )
end

local function maybeHighlightSearchText(text, highlightSearch, query)
    if highlightSearch and query and query ~= "" and GTD and GTD.FormatTextWithSearchHighlight then
        return GTD.FormatTextWithSearchHighlight(text, nil, query)
    end
    return text
end

-- Main tab content: bordered panel (same styling as settings panel).
local tabContentPanel = Theme.CreateMainContentPanel(frame)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)

-- List viewport: clips results; horizontal scroll when viewport is narrower than totalColWidth.
local listViewport = CreateFrame("Frame", nil, tabContentInner)
listViewport:SetClipsChildren(true)
-- Points set in ApplySearchListLayout

local HINT_NO_SEARCH_RESULTS_BOTH = "No matching items or recipes\nwere found for your search."
local noResultsHint = tabContentInner:CreateFontString(nil, "OVERLAY", Theme.FONTS.muted)
noResultsHint:SetPoint("CENTER", listViewport, "CENTER", 0, 0)
noResultsHint:SetWidth(280)
noResultsHint:SetJustifyH("CENTER")
noResultsHint:SetText(HINT_NO_SEARCH_RESULTS_BOTH)
noResultsHint:Hide()

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_SearchHorizontalScroll", listViewport)
horizontalScroll:SetAllPoints(listViewport)
horizontalScroll:EnableMouse(true)

-- horizontalScrollChild created after totalColWidth is known; scrollBox reparented into it below

-- Results list: virtualized WowScrollBoxList (only rows in view have frames). Section headers are
-- spacer elements in the list; the visible headers are sticky overlays on listViewport.
local scrollBox = CreateFrame("Frame", "AltArmyTBC_SearchScrollBox", frame, "WowScrollBoxList")

-- Vertical scroll bar (native MinimalScrollBar); bound to scrollBox once the view exists.
UI.SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local searchScrollBar = CreateFrame("EventFrame", "AltArmyTBC_SearchScrollBar", tabContentInner, "MinimalScrollBar")
searchScrollBar.altArmyNativeScrollBar = true
searchScrollBar:SetHideIfUnscrollable(true)

-- Horizontal scroll bar at bottom of list area (like Summary tab)
local UpdateStickyHeaders
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_SearchHorizontalScrollBar",
    thickness = UI.HORIZONTAL_SCROLL_BAR_HEIGHT - UI.PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
        if UpdateStickyHeaders then
            UpdateStickyHeaders()
        end
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar

-- Sticky headers overlay the list; forward their wheel to the ScrollBox.
local function OnSearchScrollWheel(_, delta)
    scrollBox:OnMouseWheel(delta)
end

-- Results area (scroll child; stacks Items section then Recipes section)
local function getTotalColWidth()
    local w = 0
    for _, colName in ipairs(colOrder) do w = w + (colWidths[colName] or 80) end
    return w
end
local function getRecipeColWidth()
    local w = 0
    for _, colName in ipairs(recipeColOrder) do w = w + (recipeColWidths[colName] or 80) end
    return w
end
local totalColWidth = SearchColumns and SearchColumns.GetResultsTableWidth(false)
    or math.max(getTotalColWidth(), getRecipeColWidth())

-- Horizontal scroll child: holds the vertical scroll box so the whole results area can scroll horizontally
local horizontalScrollChild = CreateFrame("Frame", nil, horizontalScroll)
horizontalScrollChild:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
horizontalScrollChild:SetHeight(1)
horizontalScrollChild:SetWidth(totalColWidth)
horizontalScroll:SetScrollChild(horizontalScrollChild)

-- Reparent scroll box into horizontal scroll child so it scrolls with the grid (rows stretch to
-- the box width = totalColWidth). Sticky headers have no background, so rows must never scroll
-- under the pinned header: the box starts below the first header block (whose spacer is left
-- out of the list), which leaves every row's on-screen position and the scroll range unchanged.
-- The extra 2px keeps row text off the header's bottom edge.
UI.LIST_TOP_INSET = 2 + UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP
scrollBox:ClearAllPoints()
scrollBox:SetParent(horizontalScrollChild)
scrollBox:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, -UI.LIST_TOP_INSET)
scrollBox:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, 0)
scrollBox:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, 0)

-- Sticky headers are transparent (the page background shows through, so nothing appears to move
-- behind them); see UI.LIST_TOP_INSET for why rows never pass underneath.
local function StyleStickySearchHeader(headerRow)
    headerRow:EnableMouse(true)
    headerRow:SetScript("OnMouseWheel", OnSearchScrollWheel)
    headerRow:SetFrameLevel((listViewport:GetFrameLevel() or 0) + 40)
end

-- Result list state (declared before section headers; header clicks update sort and refresh).
local itemList = {}
local recipeList = {}
local localRecipeList = {}
local tooltipOnlyItemList = {}
-- Raw merged recipe hits (pre-collapse). Display list is recipeList after sort+collapse.
-- expandedIDs: set of recipeIDs whose guild rows are currently expanded.
local recipeCollapseState = { mergedList = {}, expandedIDs = {} }
-- Built in UpdateResults; reused by row initializers so scroll does not rebuild guild roster.
local searchRosterByName = nil
local PlaceGroupOverlays
local UpdateResults
local RefreshSearchHeaderSortLabels

local sectionSort = {
    items = { key = "Item", ascending = true },
    recipes = { key = "Recipe", ascending = true },
    tooltip = { key = "Item", ascending = true },
}

local function resetSectionSorts()
    sectionSort.items.key = "Item"
    sectionSort.items.ascending = true
    sectionSort.recipes.key = "Recipe"
    sectionSort.recipes.ascending = true
    sectionSort.tooltip.key = "Item"
    sectionSort.tooltip.ascending = true
end

local function resetRecipeCollapseExpanded()
    recipeCollapseState.expandedIDs = {}
end

local function isRecipeDataAvailable()
    local RI = AltArmy and AltArmy.RecipeInfo
    return RI and RI.IsAvailable and RI.IsAvailable() or false
end

local function applySectionSorts()
    if sectionSort.items.key then
        itemList = SD.SortItemResults(itemList, sectionSort.items.key, sectionSort.items.ascending)
    end
    if sectionSort.recipes.key then
        local uiTimings = SD.BeginUiTiming and SD.BeginUiTiming() or nil
        local merged = recipeCollapseState.mergedList
        local nIn = #(merged or {})
        local sorted = SD.SortRecipeResults(
            merged,
            sectionSort.recipes.key,
            sectionSort.recipes.ascending,
            isRecipeDataAvailable())
        if uiTimings and SD.MarkUiTiming then
            SD.MarkUiTiming(uiTimings, "sort")
        end
        if SD.CollapseGuildRecipeRows then
            recipeList = SD.CollapseGuildRecipeRows(
                sorted, recipeCollapseState.expandedIDs, searchRosterByName)
        else
            recipeList = sorted
        end
        if uiTimings and SD.MarkUiTiming then
            SD.MarkUiTiming(uiTimings, "collapse")
        end
        if uiTimings and SD.LogRecipeUiTimings then
            SD.LogRecipeUiTimings(uiTimings, {
                nIn = nIn,
                nOut = #(recipeList or {}),
            })
        end
    end
    if sectionSort.tooltip.key then
        tooltipOnlyItemList = SD.SortItemResults(
            tooltipOnlyItemList, sectionSort.tooltip.key, sectionSort.tooltip.ascending)
    end
end

-- Sticky section headers overlay the clipping viewport (not the nested scroll-child),
-- so they seal the top edge above scrolling row text. X is synced to horizontal scroll.
local itemsHeaderRow = CreateFrame("Frame", nil, listViewport)
itemsHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(itemsHeaderRow)
itemsHeaderRow:Hide()
local itemsHeaderButtons = {}
-- Recipes section header
local recipesHeaderRow = CreateFrame("Frame", nil, listViewport)
recipesHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(recipesHeaderRow)
recipesHeaderRow:Hide()
local recipesHeaderButtons = {}

-- "You may also be interested in:" section header: same columns as items (Item/Character/Total),
-- with the first column label replaced by the section title.
local alsoInterestedHeaderRow = CreateFrame("Frame", nil, listViewport)
alsoInterestedHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(alsoInterestedHeaderRow)
alsoInterestedHeaderRow:Hide()
local alsoInterestedHeaderButtons = {}

local function defaultAscendingForSortKey(sortKey)
    return sortKey ~= "Skill"
end

local function createSearchHeaderButton(headerRow, sectionId, colName, justifyLeft)
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetHeight(UI.HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetJustifyH(justifyLeft and "LEFT" or "RIGHT")
    btn.label = label
    btn.colName = colName
    Theme.BindInteractableHover(btn)
    local clickCol = colName
    btn:SetScript("OnClick", function()
        local sortState = sectionSort[sectionId]
        if sortState.key == clickCol then
            sortState.ascending = not sortState.ascending
        else
            sortState.key = clickCol
            sortState.ascending = defaultAscendingForSortKey(clickCol)
        end
        UpdateResults()
    end)
    return btn
end

local function initSearchSectionHeader(headerRow, sectionId, columnOrder, buttonsByCol)
    for _, colName in ipairs(columnOrder) do
        local justifyLeft = colName == "Item" or colName == "Recipe"
        buttonsByCol[colName] = createSearchHeaderButton(headerRow, sectionId, colName, justifyLeft)
    end
end

initSearchSectionHeader(itemsHeaderRow, "items", colOrder, itemsHeaderButtons)
initSearchSectionHeader(recipesHeaderRow, "recipes", recipeColOrder, recipesHeaderButtons)
initSearchSectionHeader(alsoInterestedHeaderRow, "tooltip", colOrder, alsoInterestedHeaderButtons)

local scrollTopFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = itemsHeaderRow,
})
local stickyHeaderFadeFrame = scrollTopFade.frame

-- Debounce for tooltip-only search: main results appear immediately.
-- Delay: 1 char → 0.4s; 2 chars → 0.1s; 3+ → start chunked scan immediately.
-- Guild recipes always merge in the same frame as local recipe results.
local tooltipDebounceFrame = CreateFrame("Frame")
local tooltipDebounceRemaining = 0
local tooltipDebounceQuery = nil
local tooltipChunkFrame = CreateFrame("Frame")
local tooltipChunkState = nil
local tooltipChunkGeneration = 0

local function ApplyTooltipOnlyRealmFilter(rows)
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        return AltArmy.GlobalRealmFilter.FilterList(rows or {}, currentRealm)
    end
    return rows or {}
end

local function ApplyRecipeRealmFilter(rows)
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        return AltArmy.GlobalRealmFilter.FilterList(rows or {}, currentRealm)
    end
    return rows or {}
end

local function StopTooltipChunkSearch()
    tooltipChunkFrame:SetScript("OnUpdate", nil)
    tooltipChunkState = nil
end

local function StartTooltipChunkSearch(query)
    StopTooltipChunkSearch()
    if not query or query == "" or not frame:IsShown() then return end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if not categories.Items then return end
    local all = SD.GetAllContainerSlots and SD.GetAllContainerSlots() or {}
    local queryLower, queryID = SD._ParseItemSearchQuery(query)
    if not queryLower then
        tooltipOnlyItemList = {}
        UpdateResults()
        return
    end
    tooltipChunkState = {
        generation = tooltipChunkGeneration,
        query = query,
        queryLower = queryLower,
        queryID = queryID,
        all = all,
        index = 1,
        total = #all,
        matches = {},
    }
    tooltipChunkFrame:SetScript("OnUpdate", function()
        local state = tooltipChunkState
        if not state then
            StopTooltipChunkSearch()
            return
        end
        if state.generation ~= tooltipChunkGeneration then
            StopTooltipChunkSearch()
            return
        end
        if not frame:IsShown() then
            StopTooltipChunkSearch()
            return
        end
        local currentQuery = frame.lastQuery
        if currentQuery and currentQuery ~= state.query then
            StopTooltipChunkSearch()
            return
        end
        local categoriesNow = AltArmy.SearchCategories or { Items = true, Recipes = true }
        if not categoriesNow.Items then
            StopTooltipChunkSearch()
            tooltipOnlyItemList = {}
            UpdateResults()
            return
        end

        local processed = 0
        while processed < UI.TOOLTIP_CHUNK_SIZE and state.index <= state.total do
            local entry = state.all[state.index]
            state.index = state.index + 1
            processed = processed + 1
            if entry and not SD._IsMainSearchMatch(entry, state.queryLower, state.queryID) then
                local searchableText = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
                if searchableText and searchableText:find(state.queryLower, 1, true) then
                    if SD._EnsureItemName then
                        SD._EnsureItemName(entry)
                    end
                    table.insert(state.matches, entry)
                end
            end
        end

        if state.index > state.total then
            StopTooltipChunkSearch()
            if state.generation ~= tooltipChunkGeneration then return end
            local rows
            if SD._AggregateAndSort then
                rows = SD._AggregateAndSort(state.matches, state.queryLower)
            else
                local _, fallback = SD.SearchWithLocationGroups(state.query)
                rows = fallback or {}
            end
            tooltipOnlyItemList = ApplyTooltipOnlyRealmFilter(rows)
            UpdateResults()
        end
    end)
end

local function tooltipDebounceOnUpdate(_, elapsed)
    tooltipDebounceRemaining = tooltipDebounceRemaining - elapsed
    if tooltipDebounceRemaining <= 0 then
        tooltipDebounceFrame:SetScript("OnUpdate", nil)
        local query = tooltipDebounceQuery
        tooltipDebounceQuery = nil
        StartTooltipChunkSearch(query)
    end
end

local function ScheduleTooltipSearch(query)
    tooltipChunkGeneration = tooltipChunkGeneration + 1
    StopTooltipChunkSearch()
    tooltipDebounceQuery = nil
    tooltipDebounceFrame:SetScript("OnUpdate", nil)
    if not query or query == "" then
        return
    end
    local delay = (SD.GetSearchTailDebounceSecs and SD.GetSearchTailDebounceSecs(query)) or 0.4
    if delay <= 0 then
        StartTooltipChunkSearch(query)
        return
    end
    tooltipDebounceQuery = query
    tooltipDebounceRemaining = delay
    tooltipDebounceFrame:SetScript("OnUpdate", tooltipDebounceOnUpdate)
end

local function IsTooltipSearchPending()
    if tooltipDebounceFrame:GetScript("OnUpdate") then
        return true
    end
    return tooltipChunkState ~= nil
end

--- Merge guild recipe hits into mergedList in the same frame as local results (no layout).
local function MergeGuildRecipesNow(query)
    if not query or query == "" then
        return
    end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if not categories.Recipes then
        return
    end
    if not SD.SearchGuildRecipes then
        return
    end
    local guildHits = ApplyRecipeRealmFilter(SD.SearchGuildRecipes(query) or {})
    if SD.MergeRecipeSearchResults then
        recipeCollapseState.mergedList = SD.MergeRecipeSearchResults(localRecipeList, guildHits)
    else
        local merged = {}
        for i = 1, #localRecipeList do
            merged[i] = localRecipeList[i]
        end
        for i = 1, #guildHits do
            merged[#merged + 1] = guildHits[i]
        end
        recipeCollapseState.mergedList = merged
    end
end

local function ScheduleGuildRecipeSearch(query)
    MergeGuildRecipesNow(query)
end

local function CountSearchResults(categories)
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = categories.Items and #tooltipOnlyItemList or 0
    return nItems + nRecipes + nTooltipOnly
end

local function GetNoSearchResultsHintText(categories)
    categories = categories or {}
    local items = categories.Items and true or false
    local recipes = categories.Recipes and true or false
    if not items and not recipes then
        return "Choose Items and/or Recipes\nin the Filter menu"
    end
    if items and recipes then
        return HINT_NO_SEARCH_RESULTS_BOTH
    end
    if items then
        return "No matching items\nwere found for your search."
    end
    return "No matching recipes\nwere found for your search."
end
frame.GetNoSearchResultsHintText = GetNoSearchResultsHintText

local function ShouldShowNoSearchResultsHint(query, categories, resultCount, tooltipPending)
    if not query or query == "" then
        return false
    end
    if resultCount > 0 then
        return false
    end
    if categories.Items and tooltipPending then
        return false
    end
    return true
end

local function UpdateNoResultsHint()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local show = ShouldShowNoSearchResultsHint(
        frame.lastQuery,
        categories,
        CountSearchResults(categories),
        IsTooltipSearchPending())
    if show then
        noResultsHint:SetText(GetNoSearchResultsHintText(categories))
        noResultsHint:Show()
    else
        noResultsHint:Hide()
    end
end

-- Group overlay: total count (centered in group) + item icon to the right. Children of the
-- ScrollBox's scroll target so they move and clip with the rows they span.
local groupOverlayPool = {}
local function getGroupOverlay(i)
    if not groupOverlayPool[i] then
        local target = scrollBox:GetScrollTarget()
        local overlay = CreateFrame("Frame", nil, target)
        overlay:SetFrameLevel(target:GetFrameLevel() + 5)
        overlay.total = overlay:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        overlay.total:SetJustifyH("RIGHT")
        overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
        overlay.icon:SetSize(UI.OVERLAY_ICON_SIZE, UI.OVERLAY_ICON_SIZE)
        groupOverlayPool[i] = overlay
    end
    return groupOverlayPool[i]
end

--- One-time build of an item-row frame from the ScrollBox pool (AltArmySearchItemRowTemplate).
local function buildItemRow(row)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(colOrder) do
        local w = colWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(UI.ROW_HEIGHT)
        cell:SetJustifyV("MIDDLE")
        cell:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
        cell:SetNonSpaceWrap(false)
        if colName == "Item" or colName == "Character" then cell:SetWordWrap(false) end
        row.cells[colName] = cell
        cx = cx + w
    end
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            if entry.itemLink and entry.itemLink ~= "" then
                GameTooltip:SetHyperlink(entry.itemLink)
            elseif entry.itemID then
                GameTooltip:SetItemByID(entry.itemID)
            else
                GameTooltip:SetText("Item " .. tostring(entry.itemID or "?"))
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        local entry = self.entry
        if not entry then return end
        HandleItemRowClick(entry.itemLink or entry.itemID, button)
    end)
end

--- One-time build of a recipe-row frame from the ScrollBox pool (AltArmySearchRecipeRowTemplate).
local function buildRecipeRow(row)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(recipeColOrder) do
        local w = recipeColWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(UI.ROW_HEIGHT)
        cell:SetJustifyV("MIDDLE")
        cell:SetJustifyH(colName == "Recipe" and "LEFT" or "RIGHT")
        cell:SetNonSpaceWrap(false)
        if colName == "Recipe" or colName == "Character" then cell:SetWordWrap(false) end
        row.cells[colName] = cell
        cx = cx + w
    end
    -- Clickable Character overlay for guildmate rows (whisper) and collapsed summaries.
    local charBtn = CreateFrame("Button", nil, row)
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row.cells.Character, "RIGHT", 0, 0)
    charBtn:SetFrameLevel(row:GetFrameLevel() + 2)
    charBtn:Hide()
    charBtn:RegisterForClicks("LeftButtonUp")
    charBtn:SetScript("OnClick", function(self)
        local entry = self:GetParent().entry
        if not entry then return end
        -- Summary "Multiple guildmates" row: full-row button; shift-click link, else toggle.
        if entry.isGuildCollapsed and entry.recipeID ~= nil then
            if IsShiftKeyDown() then
                local link = GetRecipeLink(entry.recipeID, entry.resultItemID)
                if link and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(link)
                end
                return
            end
            if entry.isGuildExpanded or recipeCollapseState.expandedIDs[entry.recipeID] then
                recipeCollapseState.expandedIDs[entry.recipeID] = nil
            else
                recipeCollapseState.expandedIDs[entry.recipeID] = true
            end
            UpdateResults()
            return
        end
        -- Online guildmates: whisper. Own-account rows are tooltip-only.
        if not entry.isGuild then
            return
        end
        local Nav = AltArmy.SearchGuildNav
        if Nav and Nav.OpenGuildRecipeWhisper then
            Nav.OpenGuildRecipeWhisper(entry.characterName, entry.realm, {
                rosterByName = searchRosterByName,
            })
        end
    end)
    Theme.InstallHoverTint(row)
    Theme.BindInteractableHover(charBtn, {
        onEnter = function(self)
            local entry = self:GetParent().entry
            if not entry or not GameTooltip then return end
            local Nav = AltArmy.SearchGuildNav
            if entry.isGuildCollapsed then
                -- Full-row click highlight lives on the row; suppress the Character/Skill-only tint.
                Theme.SetHoverTint(self, false)
                Theme.SetHoverTint(self:GetParent(), true)
                local lines = Nav and Nav.GetCollapsedGuildRecipeTooltipLines
                    and Nav.GetCollapsedGuildRecipeTooltipLines(entry, {
                        rosterByName = searchRosterByName,
                    })
                if not lines or not lines[1] then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                for i = 1, #lines do
                    local line = lines[i]
                    if type(line) == "table" then
                        -- Name left, last-online right-aligned (embedded colors; RGB neutral).
                        GameTooltip:AddDoubleLine(
                            line.left or "", line.right or "", 1, 1, 1, 1, 1, 1)
                    else
                        GameTooltip:AddLine(line, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
                return
            end
            local hoverOpts = { rosterByName = searchRosterByName }
            if not entry.isGuild then
                hoverOpts.forceLocal = true
            end
            local RYB = AltArmy and AltArmy.RecipeYieldBonus
            local specLabel = RYB and RYB.GetMatchingSpecLabel
                and RYB.GetMatchingSpecLabel(entry)
            if specLabel then
                hoverOpts.specializationLabel = specLabel
            end
            if (not entry.isGuild)
                or (entry.isGuild and Nav and Nav.IsGuildRecipeCharacterClickable
                    and not Nav.IsGuildRecipeCharacterClickable(entry, hoverOpts)) then
                -- Own-account or offline guildmate: keep tooltip, no interactable highlight.
                Theme.SetHoverTint(self, false)
            end
            local lines = Nav and Nav.GetGuildCharacterHoverTooltipLines
                and Nav.GetGuildCharacterHoverTooltipLines(
                    entry.characterName, entry.realm, hoverOpts)
            if not lines or not lines[1] then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            for i = 1, #lines do
                -- Embedded white/gray + class colors; keep AddLine RGB neutral.
                GameTooltip:AddLine(lines[i], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end,
        onLeave = function(self)
            local parent = self:GetParent()
            local entry = parent and parent.entry
            if entry and entry.isGuildCollapsed then
                Theme.SetHoverTint(parent, false)
            end
            if GameTooltip then GameTooltip:Hide() end
        end,
    })
    row.characterBtn = charBtn
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        if entry.isGuildCollapsed then
            Theme.SetHoverTint(self, true)
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            local link = GetRecipeLink(entry.recipeID, entry.resultItemID)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetText("Recipe " .. tostring(entry.recipeID or "?"))
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.entry and self.entry.isGuildCollapsed then
            Theme.SetHoverTint(self, false)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local entry = self.entry
        if not entry then return end
        if IsShiftKeyDown() then
            local link = GetRecipeLink(entry.recipeID, entry.resultItemID)
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
            end
            return
        end
        if entry.isGuildCollapsed and entry.recipeID ~= nil then
            if entry.isGuildExpanded or recipeCollapseState.expandedIDs[entry.recipeID] then
                recipeCollapseState.expandedIDs[entry.recipeID] = nil
            else
                recipeCollapseState.expandedIDs[entry.recipeID] = true
            end
            UpdateResults()
        elseif entry._aaFromCollapse and entry.recipeID ~= nil then
            recipeCollapseState.expandedIDs[entry.recipeID] = nil
            UpdateResults()
        end
    end)
    -- Indent rail for expanded child rows (recipe name omitted).
    local childRail = row:CreateTexture(nil, "ARTWORK")
    childRail:SetWidth(2)
    childRail:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -3)
    childRail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 3)
    childRail:SetColorTexture(0.55, 0.55, 0.60, 0.85)
    childRail:Hide()
    row.collapseChildRail = childRail
end

local function fillItemRow(row, entry, showRealmSuffix, rowOpts)
    if not row or not entry then return end
    rowOpts = rowOpts or {}
    if rowOpts.scrollDebug then
        if rowOpts.scrollDebugIsTooltip then
            SD.NoteScrollTooltipPaint(rowOpts.scrollDebug)
        else
            SD.NoteScrollItemPaint(rowOpts.scrollDebug)
        end
    end
    local highlightSearch = rowOpts.highlightSearch ~= false
    local searchQuery = rowOpts.searchQuery
    row.entry = entry
    local count = entry.count or 1
    local itemText = (entry.itemName and entry.itemName ~= "") and entry.itemName
        or ("Item " .. (entry.itemID or ""))
    itemText = maybeHighlightSearchText(itemText, highlightSearch, searchQuery)
    local countSuffix = " x" .. tostring(count)
    local iconPrefix = ""
    local compatGetItemInfo = AltArmy.DataStore and AltArmy.DataStore.CompatGetItemInfo
    if entry.itemLink and compatGetItemInfo and compatGetItemInfo(entry.itemLink) then
        local icon = select(10, compatGetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        iconPrefix = "|T" .. icon .. ":0|t "
    end
    SetItemCellTruncated(row.cells.Item, itemText, countSuffix, iconPrefix, colWidths.Item or 344)
    local locLabel = entry.location == "bank" and "Bank"
        or (entry.location == "mail" and "Mail")
        or (entry.location == "equipped" and "Equipped")
        or (entry.location == "equipped-bank" and "Equipped-bank")
        or (entry.location == "keyring" and "Keyring")
        or "Bags"
    local namePart = buildCharacterNamePart(entry, showRealmSuffix)
    local suffixText = "|cffffffff (" .. locLabel .. ")|r"
    SetCharacterCellTruncated(row.cells.Character, namePart, suffixText, colWidths.Character or 160)
    row.cells.Total:SetText("")
end

local function restoreRecipeCharacterBtnAnchors(row)
    local charBtn = row.characterBtn
    if not charBtn or not row._aaCollapsedBtnWide then
        return
    end
    charBtn:ClearAllPoints()
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row.cells.Character, "RIGHT", 0, 0)
    row._aaCollapsedBtnWide = false
end

local function widenRecipeCharacterBtnForCollapse(row)
    local charBtn = row.characterBtn
    if not charBtn then return end
    -- Character + Skill only: player-list tooltip here; Recipe column keeps the recipe tooltip.
    -- Full-row click highlight is drawn on the row itself.
    charBtn:ClearAllPoints()
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row._aaCollapsedBtnWide = true
end

local function fillRecipeRow(row, entry, showRealmSuffix, rowOpts)
    if not row or not entry then return end
    rowOpts = rowOpts or {}
    local highlightSearch = rowOpts.highlightSearch ~= false
    local searchQuery = rowOpts.searchQuery
    row.entry = entry
    if rowOpts.scrollDebug and SD.NoteScrollRecipePaint then
        SD.NoteScrollRecipePaint(rowOpts.scrollDebug, entry)
    end
    -- Viewport-only recipe data enrich (search defers this unless filters need it).
    if SD._EnrichRecipeEntry then
        SD._EnrichRecipeEntry(entry)
    end
    if SD.EnsureRecipeDisplayCache then
        SD.EnsureRecipeDisplayCache(entry)
    end

    local isCollapseChild = entry._aaFromCollapse and true or false
    if row.collapseChildRail then
        row.collapseChildRail:SetShown(isCollapseChild)
    end
    if isCollapseChild then
        row.cells.Recipe:SetText("")
    else
        local recipeName = SD.FormatHighlightedRecipeName
            and SD.FormatHighlightedRecipeName(entry, searchQuery, function(text, query)
                return maybeHighlightSearchText(text, highlightSearch, query)
            end)
        if not recipeName then
            recipeName = entry._aaRecipeBaseName
                or ("Recipe " .. tostring(entry.recipeID or "?"))
            recipeName = maybeHighlightSearchText(recipeName, highlightSearch, searchQuery)
        end
        local iconPath = entry._aaIconPath or "Interface\\Icons\\INV_Misc_QuestionMark"
        local iconPrefix = ("|T%s:0|t "):format(iconPath)
        SetItemCellTruncated(row.cells.Recipe, recipeName, "", iconPrefix, recipeColWidths.Recipe or 344)
    end

    if entry.isGuildCollapsed then
        SetCharacterCellTruncated(
            row.cells.Character,
            "|cff8ab4f8Multiple guildmates|r",
            nil,
            recipeColWidths.Character or 160)
        row.cells.Skill:SetText(entry._aaSkillCellText or "*")
        if row.characterBtn then
            widenRecipeCharacterBtnForCollapse(row)
            row.characterBtn:Show()
        end
        return
    end

    Theme.SetHoverTint(row, false)
    restoreRecipeCharacterBtnAnchors(row)
    local namePart = buildCharacterNamePart(entry, showRealmSuffix)
    local RYB = AltArmy and AltArmy.RecipeYieldBonus
    if RYB and RYB.GetMatchingSpecLabel and RYB.GetMatchingSpecLabel(entry)
        and RYB.FormatSpecialistPrefixMarkup then
        namePart = RYB.FormatSpecialistPrefixMarkup() .. namePart
    end
    local Nav = AltArmy.SearchGuildNav
    local charSuffix
    if entry.isGuild then
        if Nav and Nav.FormatGuildRecipeCharacterSuffix then
            charSuffix = Nav.FormatGuildRecipeCharacterSuffix(
                entry.characterName, entry.realm, rowOpts)
        else
            charSuffix = "|cff8ab4f8 (|r|cff808080Offline|r|cff8ab4f8)|r"
        end
    end
    SetCharacterCellTruncated(row.cells.Character, namePart, charSuffix, recipeColWidths.Character or 160)
    -- Guildmates: tooltip; click/highlight only when online.
    -- Own-account: tooltip only (no hover tint, no click).
    if row.characterBtn then
        row.characterBtn:SetShown(true)
    end
    local skillText = entry._aaSkillCellText
    if not skillText then
        local RI = AltArmy and AltArmy.RecipeInfo
        if RI and RI.FormatSkillCell then
            skillText = RI.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
        else
            skillText = tostring(entry.skillRank or 0)
        end
    end
    row.cells.Skill:SetText(skillText)
end

local function UpdateStickyHeaderFade(headerRows, stickyTops, scrollValue)
    if not stickyHeaderFadeFrame then
        return
    end

    if scrollValue <= 0 or #headerRows == 0 then
        stickyHeaderFadeFrame:Hide()
        return
    end

    local pinnedHeader = nil
    for i = #headerRows, 1, -1 do
        if stickyTops[i] == 0 then
            pinnedHeader = headerRows[i]
            break
        end
    end

    if not pinnedHeader then
        stickyHeaderFadeFrame:Hide()
        return
    end

    local topOverlap = 0
    stickyHeaderFadeFrame:ClearAllPoints()
    stickyHeaderFadeFrame:SetPoint("TOPLEFT", pinnedHeader, "BOTTOMLEFT", 0, topOverlap)
    stickyHeaderFadeFrame:SetPoint("TOPRIGHT", pinnedHeader, "BOTTOMRIGHT", 0, topOverlap)
    stickyHeaderFadeFrame:SetFrameLevel(pinnedHeader:GetFrameLevel() + 50)
    stickyHeaderFadeFrame:Show()
end

local function buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly)
    local sections = {}
    if nItems > 0 then
        sections[#sections + 1] = { id = "items", rowCount = nItems }
    end
    if nRecipes > 0 then
        sections[#sections + 1] = { id = "recipes", rowCount = nRecipes }
    end
    if nTooltipOnly > 0 then
        sections[#sections + 1] = {
            id = "tooltip",
            rowCount = nTooltipOnly,
            gapBefore = (nRecipes > 0) and UI.SECTION_GAP_BEFORE_TOOLTIP or 0,
        }
    end
    return sections
end

UpdateStickyHeaders = function()
    local StickyMod = AltArmy.SearchStickyHeaders
    if not StickyMod or not listViewport then
        return
    end

    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = #tooltipOnlyItemList

    local sections = buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly)
    local headerTops = StickyMod.ComputeSectionLayout(
        sections, UI.HEADER_HEIGHT, UI.HEADER_ROW_GAP, UI.ROW_HEIGHT)
    local scrollValue = scrollBox:GetDerivedScrollOffset()
    local stickyTops = StickyMod.ComputeStickyTops(headerTops, scrollValue, UI.HEADER_HEIGHT)

    local headerById = {
        items = itemsHeaderRow,
        recipes = recipesHeaderRow,
        tooltip = alsoInterestedHeaderRow,
    }
    local headerRows = {}
    for i = 1, #sections do
        headerRows[#headerRows + 1] = headerById[sections[i].id]
    end

    local hScroll = (horizontalScroll and horizontalScroll.GetHorizontalScroll
        and horizontalScroll:GetHorizontalScroll()) or 0
    local headerWidth = totalColWidth or 0
    for i, headerRow in ipairs(headerRows) do
        local stickyTop = stickyTops[i] or 0
        headerRow:ClearAllPoints()
        headerRow:SetPoint("TOPLEFT", listViewport, "TOPLEFT", -hScroll, -stickyTop)
        headerRow:SetWidth(headerWidth)
    end

    UpdateStickyHeaderFade(headerRows, stickyTops, scrollValue)
end

-- Place a Total-column group overlay spanning row frames firstRowFrame..lastRowFrame.
local function placeGroupOverlay(overlay, firstRowFrame, lastRowFrame, totalColX, totalColW, firstEntry, groupTotal)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", firstRowFrame, "TOPLEFT", totalColX, 2)
    overlay:SetPoint("BOTTOMLEFT", lastRowFrame, "BOTTOMLEFT", totalColX, 2)
    overlay:SetPoint("TOPRIGHT", firstRowFrame, "TOPLEFT", totalColX + totalColW, 2)
    overlay:SetPoint("BOTTOMRIGHT", lastRowFrame, "BOTTOMLEFT", totalColX + totalColW, 2)
    overlay.icon:ClearAllPoints()
    overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - UI.OVERLAY_ICON_SIZE / 2, 0)
    local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    local compatGetItemInfo = AltArmy.DataStore and AltArmy.DataStore.CompatGetItemInfo
    if firstEntry and firstEntry.itemLink and compatGetItemInfo then
        local _, _, _, _, _, _, _, _, _, tex = compatGetItemInfo(firstEntry.itemLink)
        if tex then iconPath = tex end
    end
    overlay.icon:SetTexture(iconPath)
    overlay.icon:Show()
    overlay.total:ClearAllPoints()
    overlay.total:SetPoint("RIGHT", overlay.icon, "LEFT", -3, 0)
    overlay.total:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.total:SetWidth(math.max(1, totalColW - UI.OVERLAY_ICON_SIZE - 2))
    overlay.total:SetText(tostring(groupTotal))
    overlay:Show()
end

local function hideUnusedOverlays(pool, usedCount)
    for idx = usedCount + 1, #pool do
        if pool[idx] then pool[idx]:Hide() end
    end
end

local function RelayoutSearchResultRow(row, order, widths)
    if not row or not row.cells then
        return
    end
    local cx = 0
    for _, colName in ipairs(order) do
        local w = widths[colName] or 80
        local cell = row.cells[colName]
        if cell then
            cell:SetWidth(w)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
            cx = cx + w
        end
    end
end

-- ScrollBox row initializers. The list is virtualized by WowScrollBoxList: only elements in view
-- have frames, and a frame whose element stays in view is not re-initialized while scrolling.
local function syncRowColumns(row, order, widths)
    if row.colLayoutGen ~= UI.colLayoutGen then
        RelayoutSearchResultRow(row, order, widths)
        row.colLayoutGen = UI.colLayoutGen
    end
end

-- Scroll paint debug: one timing log per ScrollBox update that filled rows (ended in OnUpdate).
local function beginPaintDebug()
    local ctx = UI.rowCtx
    if not ctx.paintDbg and SD.BeginScrollPaintDebug then
        ctx.paintDbg = SD.BeginScrollPaintDebug()
        ctx.highlightOpts.scrollDebug = ctx.paintDbg
        ctx.tooltipOpts.scrollDebug = ctx.paintDbg
    end
end

local function endPaintDebug()
    local ctx = UI.rowCtx
    if not ctx.paintDbg then return end
    if SD.EndScrollPaintDebug then
        SD.EndScrollPaintDebug(ctx.paintDbg)
    end
    ctx.paintDbg = nil
    ctx.highlightOpts.scrollDebug = nil
    ctx.tooltipOpts.scrollDebug = nil
end

local function initItemRow(row, element)
    if not row.cells then
        buildItemRow(row)
    end
    syncRowColumns(row, colOrder, colWidths)
    beginPaintDebug()
    local ctx = UI.rowCtx
    local opts = element.sectionId == "tooltip" and ctx.tooltipOpts or ctx.highlightOpts
    fillItemRow(row, element.entry, ctx.showRealmSuffix, opts)
end

local function initRecipeRow(row, element)
    if not row.cells then
        buildRecipeRow(row)
    end
    syncRowColumns(row, recipeColOrder, recipeColWidths)
    beginPaintDebug()
    fillRecipeRow(row, element.entry, UI.rowCtx.showRealmSuffix, UI.rowCtx.highlightOpts)
end

-- Section header slot: the visible header is a sticky overlay on listViewport.
local function initSpacerRow(row)
    row:EnableMouse(false)
end

do
    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(function(factory, element)
        if element.kind == "header" then
            factory("AltArmySearchSpacerTemplate", initSpacerRow)
        elseif element.sectionId == "recipes" then
            factory("AltArmySearchRecipeRowTemplate", initRecipeRow)
        else
            factory("AltArmySearchItemRowTemplate", initItemRow)
        end
    end)
    view:SetElementExtentCalculator(function(_, element)
        return element.extent
    end)
    -- Default pan extent is the first element's height (a section header); wheel by two rows.
    view:SetPanExtent(UI.ROW_HEIGHT * 2)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, searchScrollBar, view)
end

-- Total overlays span the visible frames of each item group; re-place whenever the set of
-- frames changes (frames move with the scroll target, so plain scrolling needs no work).
PlaceGroupOverlays = function()
    local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
    local totalColW = colWidths.Total or 72
    local spans, order = {}, {}
    for _, rowFrame in scrollBox:EnumerateFrames() do
        local element = rowFrame.GetElementData and rowFrame:GetElementData()
        local group = element and element.group
        if group then
            local span = spans[group]
            if not span then
                span = { first = rowFrame }
                spans[group] = span
                order[#order + 1] = group
            end
            span.last = rowFrame
        end
    end
    for i, group in ipairs(order) do
        local span = spans[group]
        placeGroupOverlay(getGroupOverlay(i), span.first, span.last, totalColX, totalColW,
            group.firstEntry, group.total)
    end
    hideUnusedOverlays(groupOverlayPool, #order)
end

scrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function()
    UpdateStickyHeaders()
end, frame)
scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function()
    PlaceGroupOverlays()
end, frame)
scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, endPaintDebug, frame)

UpdateResults = function()
    if GTD and GTD.BuildRosterLastOnlineMap then
        searchRosterByName = GTD.BuildRosterLastOnlineMap()
    else
        searchRosterByName = nil
    end
    applySectionSorts()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = #tooltipOnlyItemList
    itemsHeaderRow:SetShown(nItems > 0)
    recipesHeaderRow:SetShown(nRecipes > 0)
    alsoInterestedHeaderRow:SetShown(nTooltipOnly > 0)

    -- Fill context read by the row initializers until the next refresh.
    local ctx = UI.rowCtx
    -- Show realm suffix only when viewing all realms and account has characters on multiple realms.
    ctx.showRealmSuffix = (GlobalRealmFilterValue() == "all") and AccountHasMultipleRealms()
    ctx.highlightOpts = {
        searchQuery = frame.lastQuery or "",
        highlightSearch = true,
        rosterByName = searchRosterByName,
        onlineCache = searchRosterByName and {} or nil,
    }
    ctx.tooltipOpts = { highlightSearch = false, scrollDebugIsTooltip = true }
    ctx.paintDbg = nil

    -- Horizontal scroll: list viewport may be narrower than totalColWidth
    if listViewport and horizontalScroll and horizontalScrollChild and horizontalScrollBar then
        local vw = listViewport:GetWidth()
        local settingsOpen = frame.IsSearchSettingsShown and frame:IsSearchSettingsShown()
        -- Settings closed: columns fill the viewport (re-fit when its width changes).
        if vw and vw > 0 and not settingsOpen and UI.fitWidth ~= math.floor(vw) and UI.ApplyColumnLayout then
            UI.fitWidth = math.floor(vw)
            UI.ApplyColumnLayout()
        end
        if vw and vw > 0 then
            horizontalScrollChild:SetWidth(totalColWidth)
            local vh = listViewport:GetHeight()
            if not vh or vh <= 0 then
                vh = scrollBox:GetHeight()
            end
            horizontalScrollChild:SetHeight(vh)
            -- Horizontal scroll only while the settings panel narrows the list.
            local maxHorzScroll = settingsOpen and math.max(0, totalColWidth - vw) or 0
            horizontalScrollApi:SetRange(0, maxHorzScroll, vw)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            local hVal = horizontalScrollBar:GetValue()
            if hVal > maxHorzScroll then
                horizontalScrollBar:SetValue(maxHorzScroll)
                horizontalScrollApi:Apply(maxHorzScroll)
            else
                horizontalScrollApi:Sync()
            end
        end
    end

    local listsById = { items = itemList, recipes = recipeList, tooltip = tooltipOnlyItemList }
    local sections = buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly)
    for _, section in ipairs(sections) do
        section.list = listsById[section.id]
        section.grouped = section.id ~= "recipes"
    end
    local elements = AltArmy.SearchListModel.Build(sections, {
        headerHeight = UI.HEADER_HEIGHT,
        headerRowGap = UI.HEADER_ROW_GAP,
        rowHeight = UI.ROW_HEIGHT,
        -- The first header is always pinned above the box (see UI.LIST_TOP_INSET).
        omitFirstHeader = true,
    })
    -- Synchronous full update: frames in view are (re)initialized, OnScroll places the sticky
    -- headers and OnDataRangeChanged the Total overlays. Keeps the pixel offset (clamped).
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    RefreshSearchHeaderSortLabels()
    if SD.StartRecipeResultPrewarm then
        SD.StartRecipeResultPrewarm(recipeList)
    end
    UpdateStickyHeaders()
    UpdateNoResultsHint()
end

-- Reset list to top.
local function ResetSearchVerticalScroll()
    scrollBox:ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation)
end

--- Shared search pipeline used by DoSearch and SearchWithQuery.
function frame.RunSearch(_self, query)
    local q = query or ""
    if q:match("^%s*$") then q = "" end
    frame.lastQuery = q
    resetSectionSorts()
    resetRecipeCollapseExpanded()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if q == "" then
        itemList = {}
        tooltipOnlyItemList = {}
        localRecipeList = {}
        recipeCollapseState.mergedList = {}
        recipeList = {}
    else
        if categories.Items then
            -- Skip tooltip scan for the immediate response; tooltip results arrive after debounce.
            local searchFn = SD.SearchItems or SD.SearchWithLocationGroups
            itemList = searchFn(q, true)
            itemList = itemList or {}
            tooltipOnlyItemList = {}
        else
            itemList = {}
            tooltipOnlyItemList = {}
        end
        if categories.Recipes then
            localRecipeList = SD.SearchRecipes(q) or {}
        else
            localRecipeList = {}
        end
        recipeCollapseState.mergedList = localRecipeList
        recipeList = localRecipeList
    end
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.FilterList then
        itemList = AltArmy.GlobalRealmFilter.FilterList(itemList, currentRealm)
        localRecipeList = AltArmy.GlobalRealmFilter.FilterList(localRecipeList, currentRealm)
        recipeCollapseState.mergedList = localRecipeList
        recipeList = localRecipeList
    end
    ScheduleGuildRecipeSearch(q)
    -- Reset before rebuild so shrinking results cannot desync bar (0) vs frame (mid-list).
    ResetSearchVerticalScroll()
    UpdateResults()
    ResetSearchVerticalScroll()
    ScheduleTooltipSearch(q)
end

function frame.DoSearch()
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    frame:RunSearch(query)
end

-- Expose for header search box: run search with query directly
function frame.SearchWithQuery(_self, query)
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    frame:RunSearch(q)
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
end


-- Search settings panel (see Tabs/TabSearchSettings.lua).
local searchSettingsApi = AltArmy.TabSearchSettings and AltArmy.TabSearchSettings.Install
    and AltArmy.TabSearchSettings.Install(frame, UI) or nil
local settingsPanel = searchSettingsApi and searchSettingsApi.panel
local ApplySettingsPanelLayout = searchSettingsApi and searchSettingsApi.ApplyLayout
local RefreshSearchSettingsControls = searchSettingsApi and searchSettingsApi.RefreshControls
if not settingsPanel then
    settingsPanel = CreateFrame("Frame", nil, frame)
    settingsPanel:Hide()
    ApplySettingsPanelLayout = function() end
    RefreshSearchSettingsControls = function() end
end

function frame:IsSearchSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

local function ApplyTabContentLayout()
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.SECTION_INSET, -UI.SECTION_INSET)
    if settingsPanel:IsShown() then
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -UI.SECTION_GAP, UI.SECTION_INSET)
    else
    tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.SECTION_INSET, UI.SECTION_INSET)
    end
end

-- List viewport and horizontal scroll bar layout.
-- Columns are sized to the viewport, so horizontal scroll is unused; do not reserve
-- UI.HORIZONTAL_SCROLL_BAR_HEIGHT (Summary only reserves that strip when columns overflow).
local function ApplySearchListLayout()
    ApplyTabContentLayout()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -UI.PAD)
    listViewport:SetPoint(
        "BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -UI.SCROLL_GUTTER, UI.PAD)
    horizontalScrollBar:ClearAllPoints()
    horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", UI.PAD, -4)
    horizontalScrollBar:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, -4)
    Theme.AnchorVerticalScrollBar(searchScrollBar, tabContentPanel, listViewport)
    if noResultsHint and listViewport then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            noResultsHint:SetWidth(math.max(200, vw - 40))
        end
    end
end

local function LayoutSearchHeaderButtons(buttonsByCol, headerRow, order, widths, sortState, labelTextForCol)
    local x = 0
    for _, colName in ipairs(order) do
        local w = widths[colName] or 80
        local btn = buttonsByCol[colName]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", x, 0)
            btn:SetWidth(w)
            btn:SetHeight(UI.HEADER_HEIGHT)
            local base = labelTextForCol and labelTextForCol(colName) or colName
            Theme.SetSortHeaderLabel(btn.label, base, sortState and sortState.key == colName,
                sortState and sortState.ascending)
        end
        x = x + w
    end
end

RefreshSearchHeaderSortLabels = function()
    LayoutSearchHeaderButtons(itemsHeaderButtons, itemsHeaderRow, colOrder, colWidths, sectionSort.items)
    LayoutSearchHeaderButtons(
        recipesHeaderButtons, recipesHeaderRow, recipeColOrder, recipeColWidths, sectionSort.recipes)
    LayoutSearchHeaderButtons(
        alsoInterestedHeaderButtons, alsoInterestedHeaderRow, colOrder, colWidths, sectionSort.tooltip,
        function(colName)
            return colName == "Item" and "You may also be interested in:" or colName
        end)
end

local function ApplySearchColumnLayout()
    local settingsOpen = settingsPanel and settingsPanel:IsShown()
    local fitWidth = not settingsOpen and UI.fitWidth or nil
    SyncSearchColumnWidths(settingsOpen, fitWidth)
    totalColWidth = SearchColumns and SearchColumns.GetResultsTableWidth(settingsOpen, fitWidth)
        or math.max(getTotalColWidth(), getRecipeColWidth())
    if horizontalScrollChild then
        horizontalScrollChild:SetWidth(totalColWidth)
    end
    RefreshSearchHeaderSortLabels()
    -- Pooled rows re-anchor their cells on next initialize (UpdateResults re-initializes all
    -- rows in view right after every column layout change).
    UI.colLayoutGen = UI.colLayoutGen + 1
end

UI.ApplyColumnLayout = ApplySearchColumnLayout

local searchLayoutUpdateFrame = CreateFrame("Frame")
local searchDeferredUpdatePending = false

local function ScheduleSearchUpdateAfterLayout()
    if searchDeferredUpdatePending then return end
    searchDeferredUpdatePending = true
    searchLayoutUpdateFrame:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        searchDeferredUpdatePending = false
        if frame and frame.IsVisible and frame:IsVisible() then
            UpdateResults()
        end
    end)
end

local function RefreshSearchListAfterLayout()
ApplySearchListLayout()
    ApplySearchColumnLayout()
UpdateResults()
    ScheduleSearchUpdateAfterLayout()
end

function frame:ToggleSearchSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySettingsPanelLayout()
        RefreshSearchSettingsControls()
    end
    RefreshSearchListAfterLayout()
    if AltArmy and AltArmy.UpdateSearchSettingsButtonGlow then
        AltArmy.UpdateSearchSettingsButtonGlow()
    end
    if not showSettings and AltArmy and AltArmy.OnSearchSettingsClosed then
        AltArmy.OnSearchSettingsClosed()
    end
end

frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        ApplySettingsPanelLayout()
    end
    RefreshSearchListAfterLayout()
end)

-- Initial empty state: layout list viewport then build results (horizontal scroll range set in UpdateResults)
RefreshSearchListAfterLayout()

-- When tab is shown, refresh layout (viewport may have been zero when hidden)
frame:SetScript("OnShow", function()
    RefreshSearchListAfterLayout()
end)
