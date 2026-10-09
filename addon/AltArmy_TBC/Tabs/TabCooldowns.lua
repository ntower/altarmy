-- AltArmy TBC — Cooldowns tab: profession cooldown overview.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Cooldowns
if not frame then return end

local Theme = AltArmy.Theme
local SECTION_INSET = Theme.TAB_SECTION_INSET
local PAD = 4
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
-- Match TabSearch.lua result rows (items / recipes): row height, fonts, flush columns, icon scale.
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 20
local HEADER_ROW_GAP = 3 -- TabSearch.lua section headers use this gap above first row
local MAT_ICON_SIZE = 14 -- TabSearch OVERLAY_ICON_SIZE (inline "|Tpath:0|t" uses ~14px height)
local REFRESH_INTERVAL = 1
local TIP_ROW_HEIGHT = 22
local TIP_ICON_SIZE = 14
local SEND_COL_WIDTH = 28
local MATS_COMPOSE_WIDTH = 70
local SELECT_ALL_HEIGHT = 18
local COL_ANIM_DURATION = 0.2
local SEND_TIP_TEXT =
    "Tip: visit a mailbox on a bank alt, then open this page to distribute materials to your characters"

local CD = AltArmy.CooldownData
local DS = AltArmy.DataStore
local RF = AltArmy.RealmFilter
local SP = AltArmy.StockpilePlan
local SlideTransition = AltArmy.SlideTransition
if not CD or not DS then return end
if not SP or not SP.BuildItemPlan then return end

CD.EnsureCooldownOptions()
local LD = AltArmy.LockoutData
if LD and LD.EnsureLockoutListOptions then
    LD.EnsureLockoutListOptions()
end

--- Crafting vs Raids sub-views (persisted in AltArmyTBC_Options.cooldowns.activeView).
--- Switched by spellbook-style tabs hanging above the panel in the toolbar row (UI/TopTabs.lua).
local VIEW = {
    active = "crafting",
    tabs = nil,
    defs = {
        { name = "crafting", label = "Crafting", icon = "Interface\\Icons\\Trade_Alchemy" },
        { name = "raids", label = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_13" },
    },
}

--- Item counts for mats column and Mats sort (bags+bank+mail snapshot, same as tooltips).
local function GetItemCountForMats(char, itemId)
    if DS.GetTotalItemCount then
        return DS:GetTotalItemCount(char, itemId)
    end
    return DS:GetContainerItemCount(char, itemId)
end

local function ChatInfo(msg)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and msg and msg ~= "" then
        chat:AddMessage(string.format("|cfffecc00Alt Army|r %s", msg))
    end
end

local function ItemLinkForChat(itemID)
    if not itemID then return "?" end
    if DS.HasItemInfoApi() then
        local _, link = DS.CompatGetItemInfo(itemID)
        if link and link ~= "" and link:find("item:") then
            return link
        end
        local name = DS.CompatGetItemInfo(itemID)
        if name and name ~= "" then
            return string.format("[%s]", name)
        end
    end
    return string.format("[Item %s]", tostring(itemID))
end

local CC = AltArmy.ClassColor

local function ColorNameByClass(name, classFile)
    if CC and CC.formatName then
        return CC.formatName(name, classFile)
    end
    return name or "?"
end

--- Chat: insufficient stockpile for target, then "You have:" lines per recipe reagent.
local function ChatNotEnoughStockpile(displayName, classFile, spellId, getItemCount)
    local nameColored = displayName and ColorNameByClass(displayName, classFile) or nil
    if not CD.GetReagentList then
        if nameColored then
            ChatInfo(string.format("Not enough items to increase %s's stockpile.", nameColored))
        else
            ChatInfo("Not enough items to increase stockpile.")
        end
        return
    end
    local list = CD.GetReagentList(spellId)
    if not list or #list == 0 then
        if nameColored then
            ChatInfo(string.format("Not enough items to increase %s's stockpile.", nameColored))
        else
            ChatInfo("Not enough items to increase stockpile.")
        end
        return
    end
    if nameColored then
        ChatInfo(string.format("Not enough items to increase %s's stockpile. You have: ", nameColored))
    else
        ChatInfo("Not enough items to increase stockpile. You have: ")
    end
    for _, pair in ipairs(list) do
        local itemId = pair[1]
        local required = pair[2] or 1
        if required <= 0 then
            required = 1
        end
        local count = (getItemCount and getItemCount(itemId)) or 0
        local countText
        if count == 0 then
            countText = "|cffff33330|r"
        else
            countText = string.format("|cffffffff%d|r", count)
        end
        ChatInfo(string.format("  %s %s / %d", ItemLinkForChat(itemId), countText, required))
    end
end

local function GetCurrentIdentity()
    if DS and DS.GetCurrentPlayerIdentity then
        return DS:GetCurrentPlayerIdentity()
    end
    return "", ""
end

local function RecipeIconTexture(spellId, charTable)
    local fallback = "Interface\\Icons\\INV_Misc_QuestionMark"
    local resultItemID
    if charTable and charTable.Professions and spellId then
        for _, pdata in pairs(charTable.Professions) do
            local rec = pdata and pdata.Recipes and pdata.Recipes[spellId]
            if rec and rec.resultItemID then
                resultItemID = rec.resultItemID
                break
            end
        end
    end
    if resultItemID and DS.HasItemInfoApi() then
        local _, _, _, _, _, _, _, _, _, tex = DS.CompatGetItemInfo(resultItemID)
        if tex then return tex end
    end
    if spellId then
        local _, _, tex = DS.CompatGetSpellInfo(spellId)
        if tex and tex ~= "" then return tex end
    end
    if spellId and DS.HasItemInfoApi() then
        local _, _, _, _, _, _, _, _, _, tex = DS.CompatGetItemInfo(spellId)
        if tex then return tex end
    end
    return fallback
end

local function FormatRecipeColumnText(spellId, title, charTable)
    local icon = RecipeIconTexture(spellId, charTable)
    -- Match TabSearch "|Ttexture:0|t " …
    return ("|T%s:0|t %s"):format(icon, title or "")
end

--- GameTooltip:AddLine accepts inline |T…|t textures in the text.
local function TooltipReagentLine(itemID, label, have, need)
    local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
    if itemID and DS.HasItemInfoApi() then
        local t = select(10, DS.CompatGetItemInfo(itemID))
        if t and t ~= "" then
            tex = t
        end
    end
    local prefix = ("|T%s:%d:%d|t "):format(tex, MAT_ICON_SIZE, MAT_ICON_SIZE)
    return prefix .. string.format("%s: %d / %d", label, have, need)
end

local function AccountHasMultipleRealms()
    local n = 0
    for _ in pairs(DS:GetRealms()) do
        n = n + 1
        if n > 1 then return true end
    end
    return false
end

local colWidths = {
    Category = 226, -- leave ~4px before scrollbar so send checkboxes aren't flush
    Character = 190,
    Mats = 44,
    Time = 128,
    Send = 0,
}

local IDLE_COL_WIDTHS = {
    Category = 226,
    Character = 190,
    Mats = 44,
    Time = 128,
    Send = 0,
}
-- Compose: Send checkbox column; Mats 70; Recipe/Character each lose half of Send plus half of Mats growth.
local COMPOSE_COL_WIDTHS = {
    Category = 226 - (SEND_COL_WIDTH / 2) - ((MATS_COMPOSE_WIDTH - 44) / 2),
    Character = 190 - (SEND_COL_WIDTH / 2) - ((MATS_COMPOSE_WIDTH - 44) / 2),
    Mats = MATS_COMPOSE_WIDTH,
    Time = 128,
    Send = SEND_COL_WIDTH,
}

local SORT_KEYS_ORDER = { "recipe", "character", "mats", "time" }
local SORT_HEADER_LABEL = {
    recipe = "Recipe",
    character = "Character",
    mats = "Mats",
    time = "Time Remaining",
}
local SORT_COL_WIDTH = {
    recipe = colWidths.Category,
    character = colWidths.Character,
    mats = colWidths.Mats,
    time = colWidths.Time,
}
local SORT_HEADER_JUSTIFY = {
    recipe = "LEFT",
    character = "LEFT",
    mats = "CENTER",
    time = "RIGHT",
}

local currentSortKey = "recipe"
local sortAscending = true

local function GetCooldownListSort()
    CD.EnsureCooldownOptions()
    return AltArmyTBC_Options.cooldowns
end

local function SyncSortFromSaved()
    GetCooldownListSort()
    local cd = AltArmyTBC_Options.cooldowns
    currentSortKey = cd.listSortKey
    sortAscending = cd.listSortAscending
end

local RefreshList -- forward-declared; header buttons call this after sort changes
local ShowRecipeTooltip -- spell + reagent counts; used by rows and recipe picker
local ComputeMaxCraftsWithAttachmentCap -- forward-declared; used by send flow
local ApplyColumnWidths -- forward-declared; column animation + refresh
local SyncSendCheckFade -- forward-declared; checkbox fade with Select All
local UpdateSendBarMode -- forward-declared; mailbox / compose UI
local RecomputeSendAllocation -- forward-declared; preview mats + Send enablement
local headerButtons = {}
local sendHeaderBtn

local function UpdateHeaderSortIndicators()
    for _, sk in ipairs(SORT_KEYS_ORDER) do
        local btn = headerButtons and headerButtons[sk]
        if btn and btn.label then
            local base = SORT_HEADER_LABEL[sk]
            btn.label:SetText(Theme.FormatSortHeaderLabel(base, sk == currentSortKey, sortAscending))
        end
    end
end

local function TotalColWidth()
    return colWidths.Category + colWidths.Character + colWidths.Mats + colWidths.Time + (colWidths.Send or 0)
end

local totalColWidth = TotalColWidth()

local tabContentPanel = Theme.CreateMainContentPanel(frame)
tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)

local raidsPanel = Theme.CreateMainContentPanel(frame)
raidsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
raidsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
raidsPanel:Hide()

frame.CraftingView = tabContentPanel
frame.RaidsView = raidsPanel

local SetActiveCooldownsView -- forward-declared; defined after RefreshList

local headerRow = CreateFrame("Frame", nil, tabContentInner)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetWidth(totalColWidth)
headerRow:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
headerRow:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)

local hx = 0
for _, sk in ipairs(SORT_KEYS_ORDER) do
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
    btn:SetSize(SORT_COL_WIDTH[sk], HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    local sortKeyForClick = sk
    btn:SetScript("OnClick", function()
        if currentSortKey == sortKeyForClick then
            sortAscending = not sortAscending
        else
            currentSortKey = sortKeyForClick
            sortAscending = true
        end
        local cd = GetCooldownListSort()
        cd.listSortKey = currentSortKey
        cd.listSortAscending = sortAscending
        UpdateHeaderSortIndicators()
        if RefreshList then
            RefreshList()
        end
    end)
    local label = btn:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(HEADER_HEIGHT)
    label:SetJustifyH(SORT_HEADER_JUSTIFY[sk] or "LEFT")
    label:SetText(SORT_HEADER_LABEL[sk])
    btn.label = label
    Theme.BindInteractableHover(btn)
    headerButtons[sk] = btn
    hx = hx + SORT_COL_WIDTH[sk]
end

sendHeaderBtn = CreateFrame("Frame", nil, headerRow)
sendHeaderBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
sendHeaderBtn:SetSize(1, HEADER_HEIGHT)
sendHeaderBtn:Hide()
sendHeaderBtn:EnableMouse(false)

-- "All" select strip sits above the column headers in compose mode (header slides down).
local selectAllBar = CreateFrame("Frame", nil, tabContentInner)
selectAllBar:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, 0)
selectAllBar:SetHeight(SELECT_ALL_HEIGHT)
selectAllBar:SetWidth(totalColWidth)
selectAllBar:SetFrameLevel((headerRow:GetFrameLevel() or 0) + 1)
selectAllBar:Hide()
selectAllBar:EnableMouse(true)

local selectAllCheck = Theme.CreateThemeCheckbox(selectAllBar, 16)
selectAllCheck:SetPoint("RIGHT", selectAllBar, "RIGHT", 0, 0)

local selectAllLabel = selectAllBar:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
selectAllLabel:SetPoint("RIGHT", selectAllCheck, "LEFT", -4, 0)
selectAllLabel:SetJustifyH("RIGHT")
selectAllLabel:SetTextColor(1, 1, 1)
selectAllLabel:SetText("Select All")

local selectAllHit = CreateFrame("Button", nil, selectAllBar)
selectAllHit:SetPoint("TOPLEFT", selectAllLabel, "TOPLEFT", -4, 2)
selectAllHit:SetPoint("BOTTOMRIGHT", selectAllCheck, "BOTTOMRIGHT", 2, -2)
selectAllHit:SetFrameLevel(selectAllBar:GetFrameLevel() + 2)
selectAllHit:RegisterForClicks("LeftButtonUp")
Theme.BindInteractableHover(selectAllHit)

-- Bottom tip / send bar (list viewport sits above this so rows never overlap it).
local tipRow = CreateFrame("Frame", nil, tabContentInner)
tipRow:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", 0, 0)
tipRow:SetPoint("BOTTOMRIGHT", tabContentInner, "BOTTOMRIGHT", 0, 0)
tipRow:SetHeight(TIP_ROW_HEIGHT)

local tipIcon = tipRow:CreateTexture(nil, "ARTWORK")
tipIcon:SetTexture("Interface\\Common\\help-i")
tipIcon:SetSize(TIP_ICON_SIZE, TIP_ICON_SIZE)
tipIcon:SetPoint("LEFT", tipRow, "LEFT", 0, 0)

local tipLabel = tipRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
tipLabel:SetPoint("LEFT", tipIcon, "RIGHT", 4, 0)
tipLabel:SetPoint("RIGHT", tipRow, "RIGHT", 0, 0)
tipLabel:SetJustifyH("LEFT")
tipLabel:SetText(SEND_TIP_TEXT)

-- Scrollbar track aligns with listViewport (Gear / Reputation / Summary pattern).
local listViewport = CreateFrame("Frame", nil, tabContentInner)
listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -PAD)
listViewport:SetPoint("BOTTOMLEFT", tipRow, "TOPLEFT", 0, PAD)
listViewport:SetPoint("BOTTOMRIGHT", tipRow, "TOPRIGHT", -SCROLL_GUTTER, PAD)

local rowParent = CreateFrame("Frame", nil, listViewport)
rowParent:SetPoint("TOPLEFT", listViewport, "TOPLEFT", 0, -(HEADER_HEIGHT + HEADER_ROW_GAP - PAD))
rowParent:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0)

local scroll = CreateFrame("ScrollFrame", nil, rowParent)
scroll:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", rowParent, "BOTTOMRIGHT", 0, 0)

local scrollChild = CreateFrame("Frame", nil, scroll)
scroll:SetScrollChild(scrollChild)

local cooldownHeaderFade
local scrollBinding = Theme.CreateVerticalScrollBinding(scroll, {
    parent = tabContentPanel,
    step = ROW_HEIGHT * 3,
    minScrollToShow = 1,
    onScroll = function()
        if cooldownHeaderFade then
            cooldownHeaderFade:Update()
        end
    end,
})
local scrollBar = scrollBinding.bar
Theme.AnchorVerticalScrollBar(scrollBar, tabContentPanel, listViewport)

-- Empty state: replaces the table when no character has a tracked crafting cooldown.
local craftingEmptyLabel = tabContentInner:CreateFontString(nil, "OVERLAY", Theme.FONTS.emptyState)
craftingEmptyLabel:SetPoint("CENTER", tabContentInner, "CENTER", 0, 0)
craftingEmptyLabel:SetWidth(400)
craftingEmptyLabel:SetJustifyH("CENTER")
craftingEmptyLabel:SetText("Your crafting cooldowns will appear here")
craftingEmptyLabel:Hide()

-- Gradient under the pinned header when the list is scrolled (Gear / Summary pattern).
headerRow:SetFrameLevel((tabContentInner:GetFrameLevel() or 0) + 10)
cooldownHeaderFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = headerRow,
    scrollFrame = scroll,
    scrollBar = scrollBar,
    headerBottomInset = 2,
})


local rowPool = {}
local activeRows = {}

-- ---------------------------------------------------------------------------
-- Bottom send bar (mailbox-gated) + column layout helpers
-- ---------------------------------------------------------------------------

local function IsMailboxActuallyOpen()
    -- Prefer IsVisible (parent chain). Do not trust InboxFrame:IsShown() alone — it can
    -- remain "shown" after MailFrame is hidden, which falsely keeps send-materials mode up.
    local mf = _G.MailFrame
    if mf then
        if mf.IsVisible and mf:IsVisible() then
            return true
        end
        if mf.IsShown and mf:IsShown() then
            return true
        end
    end
    return false
end

local RunSendStockpile -- assigned later (mail compose + attachment engine)

--- Packed UI/state for the bottom bar (avoids Lua 5.1 local limit).
local sendBar = {
    mode = "tip", -- "tip" | "idle" | "compose"
    targetN = 1,
    checks = {}, -- rowKey -> bool
    allocByKey = {}, -- rowKey -> { willHave, delta, shortfall }
    anyChecked = false,
    allEligibleChecked = false,
    sending = false,
    animating = false,
    animElapsed = 0,
    animFrom = nil,
    animTo = nil,
    headerOffset = 0,
    animFromHeader = 0,
    animToHeader = 0,
    -- Full list rebuild deferred while LMB is down (ReleaseRows cancels Button OnClick).
    pendingRefresh = false,
}

--- Shared Auto/recipe dropdown for grouped cooldown rows (one popup, not per-row).
local recipePicker = {
    char = nil,
    categoryKey = nil,
    row = nil,
    query = "",
    edit = nil,
    cancelBtn = nil,
}

function recipePicker.FormatEntryLabel(entry, char)
    local icon = entry and entry.spellId and RecipeIconTexture(entry.spellId, char)
    local prefix = icon and ("|T%s:0|t "):format(icon) or ""
    local GTD = AltArmy.GuildTabData
    local text = CD.FormatGroupRecipeChoiceDisplayLabel
        and CD.FormatGroupRecipeChoiceDisplayLabel(entry, recipePicker.query, function(plain, query, formatSegment)
            if GTD and GTD.FormatTextWithSearchHighlight then
                return GTD.FormatTextWithSearchHighlight(plain, nil, query, formatSegment)
            end
            return formatSegment and formatSegment(plain) or plain
        end)
        or (entry and entry.label)
        or "Auto"
    return prefix .. text
end

recipePicker.dropdown = Theme.CreateSingleSelectDropdown({
    parent = frame,
    dropdownParent = frame,
    width = 280,
    getEntries = function()
        if not CD.ListGroupRecipeChoiceEntries then
            return { { id = "auto", label = "Auto" } }
        end
        local raw = CD.ListGroupRecipeChoiceEntries(
            recipePicker.char,
            recipePicker.categoryKey,
            DS.CompatGetSpellInfo,
            recipePicker.query
        )
        local out = {}
        for i, entry in ipairs(raw) do
            out[i] = {
                id = entry.id,
                label = recipePicker.FormatEntryLabel(entry, recipePicker.char),
                spellId = entry.spellId,
            }
        end
        return out
    end,
    getSelectedId = function()
        if not CD.GetGroupRecipeChoice then
            return "auto"
        end
        return CD.GetGroupRecipeChoice(recipePicker.char, recipePicker.categoryKey)
    end,
    onSelect = function(id)
        if CD.SetGroupRecipeChoice then
            CD.SetGroupRecipeChoice(recipePicker.char, recipePicker.categoryKey, id)
        end
        recipePicker:Close()
        if RefreshList then
            RefreshList()
        end
    end,
    onEntryEnter = function(btn, entry)
        if ShowRecipeTooltip and entry and entry.spellId then
            ShowRecipeTooltip(btn, entry.spellId, recipePicker.char)
        end
    end,
    onEntryLeave = function()
        GameTooltip:Hide()
    end,
})
if recipePicker.dropdown and recipePicker.dropdown.button then
    recipePicker.dropdown.button:Hide()
    recipePicker.dropdown.button:EnableMouse(false)
end
if recipePicker.dropdown and recipePicker.dropdown.popup and recipePicker.dropdown.popup.HookScript then
    recipePicker.dropdown.popup:HookScript("OnHide", function()
        GameTooltip:Hide()
        if recipePicker.edit and recipePicker.edit:IsShown() then
            recipePicker:HideSearch()
        end
    end)
end

function recipePicker:IsOpen()
    return self.dropdown and self.dropdown.popup and self.dropdown.popup:IsShown()
end

function recipePicker:EnsureSearchWidgets()
    if self.edit then
        return
    end
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(56, ROW_HEIGHT)
    cancelBtn:SetText("Cancel")
    Theme.SkinButton(cancelBtn)
    cancelBtn:Hide()
    cancelBtn:SetScript("OnClick", function()
        recipePicker:Close()
    end)
    self.cancelBtn = cancelBtn

    local edit = CreateFrame("EditBox", nil, frame)
    edit:SetHeight(ROW_HEIGHT)
    edit:SetAutoFocus(false)
    edit:SetFontObject(Theme.FONTS.body)
    Theme.ApplyInputTextures(edit)
    local leftInset = Theme.ApplySearchInputIcon(edit, { size = 11, leftPad = 2, gap = 2, rightInset = 4 })
    Theme.SetupEditBoxPlaceholder(edit, "Search", { leftInset = leftInset, rightInset = 4 })
    Theme.BindEditBoxPlaceholderHandlers(edit, function(box)
        recipePicker.query = box:GetText() or ""
        local dd = recipePicker.dropdown
        if dd and dd.Update and recipePicker:IsOpen() then
            dd:Update()
            if dd.popup then
                dd.popup:Show()
                if Theme._openSingleSelectDropdowns then
                    Theme._openSingleSelectDropdowns[dd.popup] = true
                end
            end
        end
    end)
    edit:SetScript("OnEscapePressed", function()
        recipePicker:Close()
    end)
    edit:SetScript("OnEnterPressed", function()
        local raw = CD.ListGroupRecipeChoiceEntries
            and CD.ListGroupRecipeChoiceEntries(
                recipePicker.char,
                recipePicker.categoryKey,
                DS.CompatGetSpellInfo,
                recipePicker.query
            ) or {}
        local first = raw[1]
        if first and CD.SetGroupRecipeChoice then
            CD.SetGroupRecipeChoice(recipePicker.char, recipePicker.categoryKey, first.id)
        end
        recipePicker:Close()
        if RefreshList then
            RefreshList()
        end
    end)
    edit:Hide()
    self.edit = edit
end

function recipePicker:HideSearch()
    local row = self.row
    if self.edit then
        if self.edit.ClearFocus then
            self.edit:ClearFocus()
        end
        if Theme.ClearEditBoxText then
            Theme.ClearEditBoxText(self.edit)
        else
            self.edit:SetText("")
        end
        self.edit:Hide()
        self.edit:SetParent(frame)
    end
    if self.cancelBtn then
        self.cancelBtn:Hide()
        self.cancelBtn:SetParent(frame)
    end
    self.query = ""
    if row and row.catCell then
        row.catCell:Show()
    end
end

function recipePicker:AttachSearch(row, reset)
    self:EnsureSearchWidgets()
    local host = row and row.catBtn
    if not host or not self.edit or not self.cancelBtn then
        return
    end
    if row.catCell then
        row.catCell:Hide()
    end
    local hostLevel = (host.GetFrameLevel and host:GetFrameLevel()) or 0
    self.cancelBtn:SetParent(host)
    self.cancelBtn:ClearAllPoints()
    self.cancelBtn:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    self.cancelBtn:SetSize(56, ROW_HEIGHT)
    if self.cancelBtn.SetFrameLevel then
        self.cancelBtn:SetFrameLevel(hostLevel + 2)
    end
    self.edit:SetParent(host)
    self.edit:ClearAllPoints()
    self.edit:SetPoint("LEFT", host, "LEFT", 0, 0)
    self.edit:SetPoint("RIGHT", self.cancelBtn, "LEFT", -4, 0)
    self.edit:SetHeight(ROW_HEIGHT)
    if self.edit.SetFrameLevel then
        self.edit:SetFrameLevel(hostLevel + 2)
    end
    self.cancelBtn:Show()
    self.edit:Show()
    if reset then
        self.query = ""
        if Theme.ClearEditBoxText then
            Theme.ClearEditBoxText(self.edit)
        else
            self.edit:SetText("")
        end
        self.edit:SetFocus()
    end
end

function recipePicker:Close()
    self:HideSearch()
    self.row = nil
    self.char = nil
    self.categoryKey = nil
    self.query = ""
    GameTooltip:Hide()
    if self.dropdown and self.dropdown.Close then
        self.dropdown:Close()
    end
end

function recipePicker:Open(row)
    local rd = row and row.rowData
    local char = row and row.charTableRef
    local dd = self.dropdown
    if not rd or not char or not dd or not CD.IsGroupCategory or not CD.IsGroupCategory(rd.categoryKey) then
        return
    end
    if dd.popup and dd.popup:IsShown() and self.row == row then
        self:Close()
        return
    end
    if self.row and self.row ~= row then
        self:HideSearch()
    end
    self.row = row
    self.char = char
    self.categoryKey = rd.categoryKey
    self.query = ""
    self:AttachSearch(row, true)
    if Theme.CloseSingleSelectDropdowns then
        Theme.CloseSingleSelectDropdowns(dd.popup)
    end
    if dd.Update then
        dd:Update()
    end
    if dd.popup and row.catBtn then
        dd.popup:ClearAllPoints()
        dd.popup:SetPoint("TOPLEFT", row.catBtn, "BOTTOMLEFT", 0, -2)
        dd.popup:SetFrameStrata("DIALOG")
        dd.popup:Show()
        if Theme._openSingleSelectDropdowns then
            Theme._openSingleSelectDropdowns[dd.popup] = true
        end
    end
end

sendBar.openBtn = CreateFrame("Button", nil, tipRow, "UIPanelButtonTemplate")
sendBar.openBtn:SetSize(120, 20)
sendBar.openBtn:SetPoint("LEFT", tipRow, "LEFT", 0, 0)
sendBar.openBtn:SetText("Send Materials")
Theme.SkinButton(sendBar.openBtn)
sendBar.openBtn:Hide()

sendBar.cancelBtn = CreateFrame("Button", nil, tipRow, "UIPanelButtonTemplate")
sendBar.cancelBtn:SetSize(70, 20)
sendBar.cancelBtn:SetPoint("LEFT", tipRow, "LEFT", 0, 0)
sendBar.cancelBtn:SetText("Cancel")
Theme.SkinButton(sendBar.cancelBtn)
sendBar.cancelBtn:Hide()

sendBar.minusBtn = CreateFrame("Button", nil, tipRow, "UIPanelButtonTemplate")
sendBar.minusBtn:SetSize(24, 20)
sendBar.minusBtn:SetText("-")
Theme.SkinButton(sendBar.minusBtn)
sendBar.minusBtn:Hide()

sendBar.plusBtn = CreateFrame("Button", nil, tipRow, "UIPanelButtonTemplate")
sendBar.plusBtn:SetSize(24, 20)
sendBar.plusBtn:SetText("+")
Theme.SkinButton(sendBar.plusBtn)
sendBar.plusBtn:Hide()

sendBar.countLabel = tipRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
sendBar.countLabel:SetJustifyH("CENTER")
sendBar.countLabel:SetWidth(36)
sendBar.countLabel:Hide()

sendBar.sendBtn = CreateFrame("Button", nil, tipRow, "UIPanelButtonTemplate")
sendBar.sendBtn:SetSize(70, 20)
sendBar.sendBtn:SetPoint("RIGHT", tipRow, "RIGHT", 0, 0)
sendBar.sendBtn:SetText("Send")
Theme.SkinButton(sendBar.sendBtn)
sendBar.sendBtn:Hide()

-- Disabled buttons do not receive OnEnter; overlay provides the empty-selection tooltip.
sendBar.sendHit = CreateFrame("Frame", nil, tipRow)
sendBar.sendHit:SetAllPoints(sendBar.sendBtn)
sendBar.sendHit:EnableMouse(true)
sendBar.sendHit:Hide()
sendBar.sendHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Choose at least one character to send materials to", nil, nil, nil, nil, true)
    GameTooltip:Show()
end)
sendBar.sendHit:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function RowSendKey(rd)
    if not rd then return nil end
    return tostring(rd.realm or "") .. "\0" .. tostring(rd.charKeyName or "") .. "\0" .. tostring(rd.spellId or "")
end

local function CopyWidths(src)
    return {
        Category = src.Category,
        Character = src.Character,
        Mats = src.Mats,
        Time = src.Time,
        Send = src.Send or 0,
    }
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

ApplyColumnWidths = function(widths)
    if not widths then return end
    colWidths.Category = widths.Category
    colWidths.Character = widths.Character
    colWidths.Mats = widths.Mats
    colWidths.Time = widths.Time
    colWidths.Send = widths.Send or 0
    SORT_COL_WIDTH.recipe = colWidths.Category
    SORT_COL_WIDTH.character = colWidths.Character
    SORT_COL_WIDTH.mats = colWidths.Mats
    SORT_COL_WIDTH.time = colWidths.Time
    totalColWidth = TotalColWidth()
    headerRow:SetWidth(math.max(1, totalColWidth))
    if selectAllBar then
        selectAllBar:SetWidth(math.max(1, totalColWidth))
    end

    local x = 0
    for _, sk in ipairs(SORT_KEYS_ORDER) do
        local btn = headerButtons[sk]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", x, 0)
            btn:SetSize(SORT_COL_WIDTH[sk], HEADER_HEIGHT)
            x = x + SORT_COL_WIDTH[sk]
        end
    end
    if sendHeaderBtn then
        sendHeaderBtn:ClearAllPoints()
        sendHeaderBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", x, 0)
        if colWidths.Send > 0.5 then
            sendHeaderBtn:SetSize(colWidths.Send, HEADER_HEIGHT)
            sendHeaderBtn:Show()
        else
            sendHeaderBtn:SetSize(1, HEADER_HEIGHT)
            sendHeaderBtn:Hide()
        end
    end

    local function layoutRow(row)
        if not row or not row.catCell then return end
        row:SetWidth(totalColWidth)
        if row.catBtn then
            row.catBtn:SetSize(colWidths.Category, ROW_HEIGHT)
        end
        row.catCell:SetSize(colWidths.Category, ROW_HEIGHT)
        row.charCell:SetSize(colWidths.Character, ROW_HEIGHT)
        if row.matSlot then
            row.matSlot:SetSize(colWidths.Mats, ROW_HEIGHT)
        end
        row.timeCell:SetSize(colWidths.Time, ROW_HEIGHT)
        if row.sendSlot then
            if colWidths.Send > 0.5 then
                row.sendSlot:SetSize(colWidths.Send, ROW_HEIGHT)
            end
        end
    end
    for _, row in ipairs(activeRows) do
        layoutRow(row)
    end
    for _, row in ipairs(rowPool) do
        layoutRow(row)
    end
    if scrollChild then
        local _, h = scrollChild:GetSize()
        scrollChild:SetSize(totalColWidth, h or 1)
    end
    -- Keep checkbox fade in sync with Select All (header offset).
    do
        local fadeAlpha = 0
        if SELECT_ALL_HEIGHT > 0 then
            fadeAlpha = math.min(1, (sendBar.headerOffset or 0) / SELECT_ALL_HEIGHT)
        end
        SyncSendCheckFade(fadeAlpha)
    end
end

SyncSendCheckFade = function(alpha)
    alpha = tonumber(alpha) or 0
    if alpha < 0 then alpha = 0 end
    if alpha > 1 then alpha = 1 end
    local sendW = colWidths.Send or 0
    local function apply(row)
        if not row or not row.sendSlot then return end
        -- Own character / cross-realm: no Send checkbox.
        if row.sendEligible and sendW > 0.5 and alpha > 0.01 then
            row.sendSlot:SetSize(sendW, ROW_HEIGHT)
            row.sendSlot:Show()
            row.sendSlot:SetAlpha(alpha)
        else
            row.sendSlot:SetAlpha(0)
            row.sendSlot:Hide()
        end
    end
    for _, row in ipairs(activeRows) do
        apply(row)
    end
    for _, row in ipairs(rowPool) do
        apply(row)
    end
end

local function ApplyHeaderOffset(offset)
    offset = tonumber(offset) or 0
    if offset < 0 then offset = 0 end
    sendBar.headerOffset = offset
    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -offset)
    local fadeAlpha = 0
    if SELECT_ALL_HEIGHT > 0 then
        fadeAlpha = math.min(1, offset / SELECT_ALL_HEIGHT)
    end
    if selectAllBar then
        selectAllBar:SetWidth(math.max(1, totalColWidth))
        if offset > 0.5 then
            selectAllBar:Show()
            selectAllBar:SetAlpha(fadeAlpha)
        else
            selectAllBar:SetAlpha(0)
            selectAllBar:Hide()
        end
    end
    SyncSendCheckFade(fadeAlpha)
    rowParent:ClearAllPoints()
    rowParent:SetPoint(
        "TOPLEFT",
        listViewport,
        "TOPLEFT",
        0,
        -(HEADER_HEIGHT + HEADER_ROW_GAP - PAD + offset)
    )
    rowParent:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0)
    if cooldownHeaderFade then
        cooldownHeaderFade:Update()
    end
end

local function StartColumnAnim(toWidths, toHeaderOffset)
    sendBar.animFrom = CopyWidths(colWidths)
    sendBar.animTo = CopyWidths(toWidths)
    sendBar.animFromHeader = sendBar.headerOffset or 0
    sendBar.animToHeader = tonumber(toHeaderOffset) or sendBar.animFromHeader
    sendBar.animElapsed = 0
    sendBar.animating = true
end

local function StepColumnAnim(dt)
    if not sendBar.animating then return end
    sendBar.animElapsed = (sendBar.animElapsed or 0) + (dt or 0)
    local duration = COL_ANIM_DURATION
    if SlideTransition and SlideTransition.DEFAULT_DURATION then
        duration = SlideTransition.DEFAULT_DURATION
    end
    local t = sendBar.animElapsed / duration
    if t >= 1 then
        sendBar.animating = false
        ApplyColumnWidths(sendBar.animTo)
        ApplyHeaderOffset(sendBar.animToHeader)
        return
    end
    local ease = (SlideTransition and SlideTransition.EaseOut and SlideTransition.EaseOut(t)) or t
    local from, to = sendBar.animFrom, sendBar.animTo
    ApplyColumnWidths({
        Category = Lerp(from.Category, to.Category, ease),
        Character = Lerp(from.Character, to.Character, ease),
        Mats = Lerp(from.Mats, to.Mats, ease),
        Time = Lerp(from.Time, to.Time, ease),
        Send = Lerp(from.Send, to.Send, ease),
    })
    ApplyHeaderOffset(Lerp(sendBar.animFromHeader, sendBar.animToHeader, ease))
end

local function SyncQtyControls()
    local n = sendBar.targetN or 1
    sendBar.countLabel:SetText(tostring(n))
    if n <= 1 or sendBar.sending then
        sendBar.minusBtn:Disable()
    else
        sendBar.minusBtn:Enable()
    end
    if sendBar.sending then
        sendBar.plusBtn:Disable()
    else
        sendBar.plusBtn:Enable()
    end
end

local function SyncSelectAllCheck()
    if not selectAllCheck then return end
    local allChecked = true
    local anyEligible = false
    for _, row in ipairs(activeRows) do
        if row.sendEligible then
            anyEligible = true
            if not row.sendChecked then
                allChecked = false
                break
            end
        end
    end
    sendBar.allEligibleChecked = anyEligible and allChecked
    selectAllCheck:SetChecked(sendBar.allEligibleChecked)
    if sendBar.mode == "compose" and not sendBar.sending and anyEligible then
        selectAllCheck:Enable()
        if selectAllHit then selectAllHit:Enable() end
    else
        selectAllCheck:Disable()
        if selectAllHit then selectAllHit:Disable() end
    end
end

local function SetAllEligibleChecked(checked)
    checked = checked and true or false
    for _, row in ipairs(activeRows) do
        if row.sendEligible then
            row.sendChecked = checked
            if row.sendKey then
                sendBar.checks[row.sendKey] = checked
            end
            if row.sendCheck then
                row.sendCheck:SetChecked(checked)
            end
        end
    end
    if RecomputeSendAllocation then
        RecomputeSendAllocation()
    else
        SyncSelectAllCheck()
    end
end

selectAllCheck:SetScript("OnClick", function(checkBtn)
    if sendBar.mode ~= "compose" or sendBar.sending then
        checkBtn:SetChecked(sendBar.allEligibleChecked and true or false)
        return
    end
    -- CheckButton already toggled; use the new checked state as the target.
    SetAllEligibleChecked(checkBtn:GetChecked() and true or false)
end)

selectAllHit:SetScript("OnClick", function()
    if sendBar.mode ~= "compose" or sendBar.sending then return end
    selectAllCheck:Click()
end)

local function SyncSendButtonState()
    local canSend = sendBar.mode == "compose" and sendBar.anyChecked and not sendBar.sending
    if canSend then
        sendBar.sendBtn:Enable()
        sendBar.sendHit:Hide()
    else
        sendBar.sendBtn:Disable()
        if sendBar.mode == "compose" and not sendBar.anyChecked and not sendBar.sending then
            sendBar.sendHit:Show()
        else
            sendBar.sendHit:Hide()
        end
    end
end

local function SetRowInteractive(row, on)
    if not row then return end
    if row.EnableMouse then
        row:EnableMouse(on and true or false)
    end
    if row.matSlot and row.matSlot.EnableMouse then
        row.matSlot:EnableMouse(on and true or false)
    end
    if not on and Theme.SetHoverTint then
        Theme.SetHoverTint(row, false)
    end
end

local function ApplyRowInteractivity()
    local composeOn = sendBar.mode == "compose" and not sendBar.sending
    for _, row in ipairs(activeRows) do
        -- Own character / ineligible targets: no hover highlight or click-to-toggle.
        SetRowInteractive(row, composeOn and row.sendEligible)
    end
    SyncSelectAllCheck()
end

UpdateSendBarMode = function(forceMode, opts)
    opts = opts or {}
    -- MAIL_CLOSED can fire before DataStore/MailFrame flags clear; allow an explicit override.
    local mailboxOpen = false
    if not opts.forceClosed then
        mailboxOpen = (DS.IsMailOpen and DS:IsMailOpen()) and IsMailboxActuallyOpen()
    end
    local mode
    if not mailboxOpen then
        mode = "tip"
    elseif forceMode == "compose" or forceMode == "idle" then
        mode = forceMode
    elseif sendBar.mode == "compose" then
        mode = "compose"
    else
        mode = "idle"
    end
    local prev = sendBar.mode
    sendBar.mode = mode

    local showTip = mode == "tip"
    tipIcon:SetShown(showTip)
    tipLabel:SetShown(showTip)
    sendBar.openBtn:SetShown(mode == "idle")
    local showCompose = mode == "compose"
    sendBar.cancelBtn:SetShown(showCompose)
    sendBar.minusBtn:SetShown(showCompose)
    sendBar.plusBtn:SetShown(showCompose)
    sendBar.countLabel:SetShown(showCompose)
    sendBar.sendBtn:SetShown(showCompose)
    if showCompose then
        sendBar.minusBtn:ClearAllPoints()
        sendBar.countLabel:ClearAllPoints()
        sendBar.plusBtn:ClearAllPoints()
        sendBar.countLabel:SetPoint("CENTER", tipRow, "CENTER", 0, 0)
        sendBar.minusBtn:SetPoint("RIGHT", sendBar.countLabel, "LEFT", -4, 0)
        sendBar.plusBtn:SetPoint("LEFT", sendBar.countLabel, "RIGHT", 4, 0)
        SyncQtyControls()
        SyncSendButtonState()
    else
        sendBar.sendHit:Hide()
        if mode ~= "compose" then
            sendBar.sending = false
        end
    end

    if prev ~= mode then
        if mode == "compose" then
            sendBar.targetN = sendBar.targetN or 1
            if sendBar.targetN < 1 then sendBar.targetN = 1 end
            sendBar.checks = {}
            StartColumnAnim(COMPOSE_COL_WIDTHS, SELECT_ALL_HEIGHT)
        elseif prev == "compose" then
            sendBar.checks = {}
            sendBar.allocByKey = {}
            StartColumnAnim(IDLE_COL_WIDTHS, 0)
        end
        ApplyRowInteractivity()
        if RefreshList then
            RefreshList()
        end
    else
        ApplyRowInteractivity()
        if mode == "compose" and RecomputeSendAllocation then
            RecomputeSendAllocation()
        end
    end
end

local function ExitComposeMode(opts)
    opts = opts or {}
    sendBar.sending = false
    -- Do not set sendBar.mode here — UpdateSendBarMode must see prev == "compose"
    -- so it can animate columns back to idle widths.
    if opts.keepIdle and (DS.IsMailOpen and DS:IsMailOpen()) and IsMailboxActuallyOpen() then
        UpdateSendBarMode("idle")
    else
        UpdateSendBarMode()
    end
end

sendBar.openBtn:SetScript("OnClick", function()
    if sendBar.mode ~= "idle" then return end
    sendBar.targetN = 1
    UpdateSendBarMode("compose")
end)

sendBar.cancelBtn:SetScript("OnClick", function()
    if sendBar.sending then
        if sendBar.AbortSending then
            sendBar.AbortSending("Send cancelled.")
        end
        if sendBar.mode == "compose" then
            ExitComposeMode({ keepIdle = true })
        end
        return
    end
    ExitComposeMode({ keepIdle = true })
end)

sendBar.minusBtn:SetScript("OnClick", function()
    if sendBar.sending then return end
    local n = (sendBar.targetN or 1) - 1
    if n < 1 then n = 1 end
    sendBar.targetN = n
    SyncQtyControls()
    if RecomputeSendAllocation then RecomputeSendAllocation() end
end)

sendBar.plusBtn:SetScript("OnClick", function()
    if sendBar.sending then return end
    sendBar.targetN = (sendBar.targetN or 1) + 1
    SyncQtyControls()
    if RecomputeSendAllocation then RecomputeSendAllocation() end
end)

sendBar.sendBtn:SetScript("OnClick", function()
    if sendBar.StartSending then
        sendBar.StartSending()
    end
end)

ShowRecipeTooltip = function(owner, spellId, charTable, anchor)
    if not spellId then
        return
    end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOMLEFT")
    local link = DS.CompatGetSpellLink(spellId)
    if link and link ~= "" then
        GameTooltip:SetHyperlink(link)
    else
        if GameTooltip_Clear then
            GameTooltip_Clear(GameTooltip)
        elseif GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
        local title = DS.CompatGetSpellInfo(spellId)
        GameTooltip:AddLine(title or ("Spell " .. tostring(spellId)), 1, 1, 1)
    end
    GameTooltip:AddLine(" ", 1, 1, 1)
    local qty = nil
    if charTable and CD.GetMaxCraftableQuantity then
        qty = CD.GetMaxCraftableQuantity(charTable, spellId, function(ch, itemId)
            if DS.GetTotalItemCount then
                return DS:GetTotalItemCount(ch, itemId)
            end
            return DS:GetContainerItemCount(ch, itemId)
        end)
    end
    if qty == nil then
        GameTooltip:AddLine(
            "Open this profession's tradeskill window once to load material counts.",
            0.75,
            0.75,
            0.75,
            true
        )
    end
    if charTable and CD.GetReagentHaveCounts then
        local showRealm = (AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Get() == "all")
            and AccountHasMultipleRealms()
            and charTable.realm
            and charTable.realm ~= ""
        local _, classFile = DS:GetCharacterClass(charTable)
        local displayName = charTable.name or "?"
        local displayRealm = charTable.realm or ""
        local nameStr = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(displayName, displayRealm, showRealm, classFile)
            or displayName
        GameTooltip:AddLine(nameStr .. " has:", 1, 1, 1, true)
        local rrows = CD.GetReagentHaveCounts(charTable, spellId, function(ch, itemId)
            if DS.GetTotalItemCount then
                return DS:GetTotalItemCount(ch, itemId)
            end
            return DS:GetContainerItemCount(ch, itemId)
        end)
        for _, rr in ipairs(rrows) do
            local have, need = rr.have or 0, rr.need or 0
            local label
            if DS.HasItemInfoApi() then
                local itemName = DS.CompatGetItemInfo(rr.itemID)
                label = itemName or ("Item " .. tostring(rr.itemID))
            else
                label = "Item " .. tostring(rr.itemID)
            end
            local color = have >= need and { 0, 1, 0 } or { 1, 0.3, 0.3 }
            GameTooltip:AddLine(
                TooltipReagentLine(rr.itemID, label, have, need),
                color[1],
                color[2],
                color[3],
                true
            )
        end
    end
    GameTooltip:Show()
end

local function PoolRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)

        local catBtn = CreateFrame("Button", nil, row)
        catBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        catBtn:SetSize(colWidths.Category, ROW_HEIGHT)
        catBtn:RegisterForClicks("LeftButtonUp")
        local cat = catBtn:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        cat:SetAllPoints(catBtn)
        cat:SetJustifyH("LEFT")
        cat:SetJustifyV("MIDDLE")
        cat:SetNonSpaceWrap(false)
        row.catBtn = catBtn
        row.catCell = cat

        Theme.InstallHoverTint(catBtn)
        catBtn:EnableMouse(true)
        catBtn:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            local rd = parent and parent.rowData
            local pickable = rd and CD.IsGroupCategory and CD.IsGroupCategory(rd.categoryKey)
            if pickable and Theme.SetHoverTint then
                Theme.SetHoverTint(self, true)
            elseif Theme.SetHoverTint then
                Theme.SetHoverTint(self, false)
            end
            if recipePicker.edit and recipePicker.edit:IsShown() and recipePicker.row == parent then
                return
            end
            if parent then
                ShowRecipeTooltip(self, parent.spellId, parent.charTableRef)
            end
        end)
        catBtn:SetScript("OnLeave", function(self)
            if Theme.SetHoverTint then
                Theme.SetHoverTint(self, false)
            end
            GameTooltip:Hide()
        end)
        catBtn:SetScript("OnClick", function(self)
            GameTooltip:Hide()
            local parent = self:GetParent()
            local rd = parent and parent.rowData
            if parent and rd and CD.IsGroupCategory and CD.IsGroupCategory(rd.categoryKey) then
                recipePicker:Open(parent)
            end
        end)

        local char = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        char:SetPoint("TOPLEFT", catBtn, "TOPRIGHT", 0, 0)
        char:SetSize(colWidths.Character, ROW_HEIGHT)
        char:SetJustifyH("LEFT")
        char:SetJustifyV("MIDDLE")
        char:SetNonSpaceWrap(false)
        char:SetWordWrap(false)
        row.charCell = char

        -- Fixed-height cell so the waiting icon stays vertically centered; centering on a hidden
        -- FontString used an unstable height and misaligned the ? on some rows.
        local matSlot = CreateFrame("Frame", nil, row)
        matSlot:SetSize(colWidths.Mats, ROW_HEIGHT)
        matSlot:SetPoint("TOPLEFT", char, "TOPRIGHT", 0, 0)
        row.matSlot = matSlot

        local matIcon = matSlot:CreateTexture(nil, "ARTWORK")
        matIcon:SetSize(MAT_ICON_SIZE, MAT_ICON_SIZE)
        matIcon:SetPoint("CENTER", matSlot, "CENTER", 0, 0)
        row.matIcon = matIcon

        local matNum = matSlot:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        matNum:SetAllPoints(matSlot)
        matNum:SetJustifyH("CENTER")
        matNum:SetJustifyV("MIDDLE")
        matNum:SetNonSpaceWrap(false)
        row.matCountLabel = matNum

        local tm = row:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
        tm:SetPoint("TOPLEFT", matSlot, "TOPRIGHT", 0, 0)
        tm:SetSize(colWidths.Time, ROW_HEIGHT)
        tm:SetJustifyH("RIGHT")
        tm:SetJustifyV("MIDDLE")
        tm:SetNonSpaceWrap(false)
        row.timeCell = tm

        local sendSlot = CreateFrame("Frame", nil, row)
        sendSlot:SetSize(math.max(1, colWidths.Send or 1), ROW_HEIGHT)
        sendSlot:SetPoint("TOPLEFT", tm, "TOPRIGHT", 0, 0)
        row.sendSlot = sendSlot
        local check = Theme.CreateThemeCheckbox(sendSlot, 16)
        check:SetPoint("RIGHT", sendSlot, "RIGHT", 0, 0)
        row.sendCheck = check
        sendSlot:Hide()

        Theme.BindInteractableHover(row, {
            onEnter = function(self)
                if sendBar.mode ~= "compose" then
                    return
                end
                -- Ineligible rows (e.g. current character) stay non-highlighted.
                if not self.sendEligible then
                    if Theme.SetHoverTint then
                        Theme.SetHoverTint(self, false)
                    end
                    return
                end
                ShowRecipeTooltip(self, self.spellId, self.charTableRef)
            end,
            onLeave = function()
                GameTooltip:Hide()
            end,
        })

        local function ToggleRowSendCheck(self)
            if sendBar.mode ~= "compose" or sendBar.sending then return end
            if not self.sendEligible then return end
            local key = self.sendKey
            if not key then return end
            local newVal = not self.sendChecked
            self.sendChecked = newVal
            sendBar.checks[key] = newVal
            if self.sendCheck then
                self.sendCheck:SetChecked(newVal)
            end
            if RecomputeSendAllocation then
                RecomputeSendAllocation()
            end
        end

        local function ShowMatsSendTooltip(self)
            if sendBar.mode ~= "compose" then return end
            local rd = self.rowData
            local alloc = self.allocPreview
            if not rd or not alloc or not self.sendEligible or not self.sendChecked then
                return
            end
            local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
            local curName = (DS.GetCharacterName and currentChar and DS:GetCharacterName(currentChar))
                or (select(1, GetCurrentIdentity()))
            local srcClass = currentChar and select(2, DS:GetCharacterClass(currentChar)) or nil
            local tgtClass = self.charTableRef and select(2, DS:GetCharacterClass(self.charTableRef)) or nil
            local srcName = ColorNameByClass(curName or "?", srcClass)
            local tgtName = ColorNameByClass(rd.name or rd.charKeyName or "?", tgtClass)
            local delta = alloc.delta or 0
            local willHave = alloc.willHave or 0
            local desired = sendBar.targetN or 1
            local recipeName = rd.categoryTitle
                or DS.CompatGetSpellInfo(self.spellId or rd.spellId)
                or "Recipe"
            GameTooltip:SetOwner(self.matSlot or self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(recipeName, 1, 1, 1, true)
            GameTooltip:AddLine(srcName .. " will send " .. tostring(delta) .. "x", 1, 1, 1, true)
            GameTooltip:AddLine(tgtName .. " will have " .. tostring(willHave) .. "x", 1, 1, 1, true)
            if willHave < desired then
                GameTooltip:AddLine(
                    srcName .. " does not have enough materials to give everyone " .. tostring(desired) .. "x.",
                    0.6,
                    0.6,
                    0.6,
                    true
                )
            end
            GameTooltip:Show()
        end

        local function RowFromChild(child)
            if not child then return nil end
            if child.catCell then return child end
            local p = child:GetParent()
            if p and p.catCell then return p end
            if p then
                local gp = p:GetParent()
                if gp and gp.catCell then return gp end
            end
            return nil
        end

        local function ApplyRowHoverFromChild(child, showTooltip)
            local parent = RowFromChild(child)
            if not parent or sendBar.mode ~= "compose" or not parent.sendEligible then
                return
            end
            if Theme.SetHoverTint then
                for _, r in ipairs(activeRows) do
                    if r ~= parent then
                        Theme.SetHoverTint(r, false)
                    end
                end
                Theme.SetHoverTint(parent, true)
            end
            if showTooltip and parent:GetScript("OnEnter") then
                parent:GetScript("OnEnter")(parent)
            end
        end

        local function ClearRowHoverFromChild(child)
            local parent = RowFromChild(child)
            GameTooltip:Hide()
            if parent and Theme.SetHoverTint and not (MouseIsOver and MouseIsOver(parent)) then
                Theme.SetHoverTint(parent, false)
            end
        end

        -- Mats cell owns mouse for its send tooltip, but must keep row hover + click-to-toggle.
        -- Use GetParent() (not a closed-over row) so recycled pool frames always tint themselves.
        -- Require MouseDown+Up on the same matSlot so a mid-click list rebuild cannot toggle the wrong row.
        matSlot:EnableMouse(true)
        matSlot:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            if not parent then return end
            if sendBar.mode == "compose" and parent.sendEligible and Theme.SetHoverTint then
                for _, r in ipairs(activeRows) do
                    if r ~= parent then
                        Theme.SetHoverTint(r, false)
                    end
                end
                Theme.SetHoverTint(parent, true)
            end
            if sendBar.mode == "compose" and parent.sendChecked and parent.allocPreview then
                ShowMatsSendTooltip(parent)
            elseif sendBar.mode == "compose" and parent.sendEligible and parent:GetScript("OnEnter") then
                parent:GetScript("OnEnter")(parent)
            end
        end)
        matSlot:SetScript("OnLeave", function(self)
            ClearRowHoverFromChild(self)
        end)
        matSlot:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                self._sendClickDown = true
            end
        end)
        matSlot:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not self._sendClickDown then
                return
            end
            self._sendClickDown = false
            ToggleRowSendCheck(self:GetParent())
        end)
        matSlot:SetScript("OnHide", function(self)
            self._sendClickDown = false
        end)

        -- Checkbox steals mouse from the row; forward hover so highlight appears immediately.
        row.sendCheck:SetScript("OnEnter", function(self)
            ApplyRowHoverFromChild(self, true)
        end)
        row.sendCheck:SetScript("OnLeave", function(self)
            ClearRowHoverFromChild(self)
        end)

        row.sendCheck:SetScript("OnClick", function(checkBtn)
            local parent = RowFromChild(checkBtn)
            if not parent then
                return
            end
            if sendBar.mode ~= "compose" or sendBar.sending or not parent.sendEligible then
                checkBtn:SetChecked(parent.sendChecked and true or false)
                return
            end
            local newVal = checkBtn:GetChecked() and true or false
            parent.sendChecked = newVal
            if parent.sendKey then
                sendBar.checks[parent.sendKey] = newVal
            end
            if RecomputeSendAllocation then
                RecomputeSendAllocation()
            end
        end)

        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self)
            ToggleRowSendCheck(self)
        end)

        row:EnableMouse(false)
    end
    row:Show()
    return row
end

-- ---------------------------------------------------------------------------
-- Mail compose + attachments
-- ---------------------------------------------------------------------------

local ATTACHMENTS_MAX_SEND = 12

local function IterateLiveBagSlots(callback)
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not getSlots or not getInfo then return end
    for bagID = 0, maxBagId do
        local numSlots = getSlots(bagID) or 0
        for slot = 1, numSlots do
            local itemID, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = getInfo(bagID, slot)
                itemID = info and info.itemID or nil
                -- Some clients expose quantity instead of stackCount
                count = info and (info.stackCount or info.quantity) or nil
            else
                local link = getLink and getLink(bagID, slot)
                itemID = link and tonumber(link:match("item:(%d+)")) or nil
                local _, c = getInfo(bagID, slot)
                count = c
            end
            if itemID and itemID > 0 then
                local link = getLink and getLink(bagID, slot) or nil
                if callback(bagID, slot, itemID, (count and count > 0) and count or 1, link) then
                    return
                end
            end
        end
    end
end

local function GetLiveBagSlotCount(bagID, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local c = info and (info.stackCount or info.quantity)
        if type(c) == "number" and c > 0 then
            return c
        end
        return 0
    end
    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bagID, slot)
        if type(count) == "number" and count > 0 then
            return count
        end
        return 0
    end
    return 0
end

local function FindFirstEmptyBagSlot()
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bagID = 0, maxBagId do
            local n = C_Container.GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if not info or not info.itemID then
                    return bagID, slot
                end
            end
        end
        return nil, nil
    end
    if GetContainerNumSlots and GetContainerItemLink then
        for bagID = 0, maxBagId do
            local n = GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bagID, slot)
                if not link then
                    return bagID, slot
                end
            end
        end
    end
    return nil, nil
end

local function CountEmptyBagSlotsLive()
    local maxBagId = DS.NUM_BAG_SLOTS or 4
    local total = 0
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bagID = 0, maxBagId do
            local n = C_Container.GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if not info or not info.itemID then
                    total = total + 1
                end
            end
        end
        return total
    end
    if GetContainerNumSlots and GetContainerItemLink then
        for bagID = 0, maxBagId do
            local n = GetContainerNumSlots(bagID) or 0
            for slot = 1, n do
                if not GetContainerItemLink(bagID, slot) then
                    total = total + 1
                end
            end
        end
        return total
    end
    return 0
end

local function GetItemStackLimit(itemID)
    if type(itemID) ~= "number" then
        return 20
    end
    local cItem = _G.C_Item
    if cItem and cItem.GetItemMaxStackSizeByID then
        local n = cItem.GetItemMaxStackSizeByID(itemID)
        if type(n) == "number" and n > 0 then
            return n
        end
    end
    if DS.HasItemInfoApi() then
        local maxStack = select(8, DS.CompatGetItemInfo(itemID))
        if type(maxStack) == "number" and maxStack > 0 then
            return maxStack
        end
    end
    return 20
end

local function CollectLiveStacksByItemID()
    local out = {}
    IterateLiveBagSlots(function(bagID, slot, itemID, count)
        out[itemID] = out[itemID] or {}
        -- count can differ by client API; always re-check live count at attach time
        out[itemID][#out[itemID] + 1] = { bagID = bagID, slot = slot, count = count }
        return false
    end)
    return out
end

ComputeMaxCraftsWithAttachmentCap = function(targetChar, sourceChar, spellId, minCrafts, maxCrafts)
    local minV = tonumber(minCrafts) or 0
    local maxV = tonumber(maxCrafts) or minV
    if maxV < minV then maxV = minV end
    if maxV == minV then return minV end

    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local stacksById = CollectLiveStacksByItemID()
    local emptySlotsAvailable0 = CountEmptyBagSlotsLive()

    local function fits(crafts)
        local sendPlan = CD.GetReagentSendPlan and CD.GetReagentSendPlan(
            targetChar,
            sourceChar,
            spellId,
            crafts,
            getTargetCount,
            getSourceCount
        )
        if not sendPlan then
            return false
        end
        local totalAttachments = 0
        local emptySlotsAvailable = emptySlotsAvailable0
        for _, rr in ipairs(sendPlan) do
            local needToSend = rr.requiredToSend or 0
            if needToSend > 0 then
                local plan = SP.BuildItemPlan(needToSend, stacksById[rr.itemID] or {}, {
                    allowMerge = true,
                    preferExact = true,
                    stackLimit = GetItemStackLimit(rr.itemID),
                    maxAttachments = ATTACHMENTS_MAX_SEND,
                    emptySlotsAvailable = emptySlotsAvailable,
                })
                if not plan or not plan.ok then
                    return false
                end
                totalAttachments = totalAttachments + (plan.attachments or 0)
                if totalAttachments > ATTACHMENTS_MAX_SEND then
                    return false
                end
                for _, op in ipairs(plan.ops or {}) do
                    if op.op == "split_attach" then
                        emptySlotsAvailable = emptySlotsAvailable - 1
                        if emptySlotsAvailable < 0 then
                            return false
                        end
                    end
                end
            end
        end
        return true
    end

    local lo, hi = minV, maxV
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if fits(mid) then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo
end

local function EnsureSendMailTab()
    local tab2 = _G.MailFrameTab2
    if tab2 and tab2.Click then
        tab2:Click()
        return true
    end
    local smf = _G.SendMailFrame
    if smf and smf.Show then
        smf:Show()
        return true
    end
    return false
end

local function SetSendMailRecipient(name)
    if not name or name == "" then return false end
    local eb = _G.SendMailNameEditBox
    if eb and eb.SetText then
        eb:SetText(name)
        if eb.HighlightText then
            eb:HighlightText()
        end
        return true
    end
    return false
end

local function FormatMailRecipient(name, realm)
    if not name or name == "" then return "" end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function FirstFreeAttachmentIndex()
    local getSendMailItem = _G.GetSendMailItem
    if not getSendMailItem then
        return 1
    end
    for i = 1, ATTACHMENTS_MAX_SEND do
        local name = getSendMailItem(i)
        if not name then
            return i
        end
    end
    return nil
end

-- Sequential attach state machine (split -> place -> wait unlock -> attach).
local stockpileAttachSeq = {
    active = false,
    queue = nil,
    queueIndex = 1,
    phase = nil, -- "waitingPlacedUnlock"
    bagID = nil, -- placed split slot bag
    slot = nil, -- placed split slot slot
    expectedCount = nil, -- optional: when waiting on a merged stack to reach a count
    startedAt = 0,
    lastLogAt = 0,
    successTargetDisplayName = nil,
    successTargetClassFile = nil,
    recipient = nil, -- "Name" or "Name-Realm", what SendMail is given
}

--- /alta sendall N queue (one table to avoid Lua 5.1 local limit).
local sendAllSeq = {
    active = false,
    targetN = 0,
    rows = nil,
    index = 1,
    waitingForMail = false,
    ADVANCE_DELAY = 1,
}

--- Outgoing mail announce (shown on MAIL_SEND_SUCCESS).
local stockpileMailPendingAnnounce = nil -- { displayName = string, classFile = string|nil }

local function DebugIsSlotLocked(bagID, slot)
    local cItem = _G.C_Item
    local itemLoc = _G.ItemLocation
    if not (cItem and itemLoc and cItem.IsLocked and cItem.DoesItemExist) then
        return false
    end
    local loc = itemLoc:CreateFromBagAndSlot(bagID, slot)
    if not cItem.DoesItemExist(loc) then
        return false
    end
    return cItem.IsLocked(loc) == true
end

local function ResetAttachSeqState()
    stockpileAttachSeq.active = false
    stockpileAttachSeq.queue = nil
    stockpileAttachSeq.queueIndex = 1
    stockpileAttachSeq.phase = nil
    stockpileAttachSeq.bagID = nil
    stockpileAttachSeq.slot = nil
    stockpileAttachSeq.expectedCount = nil
    stockpileAttachSeq.startedAt = 0
    stockpileAttachSeq.lastLogAt = 0
    stockpileAttachSeq.successTargetDisplayName = nil
    stockpileAttachSeq.successTargetClassFile = nil
    stockpileAttachSeq.recipient = nil
end

sendAllSeq.Finish = function(msg)
    local fromCompose = sendAllSeq.fromCompose
    sendAllSeq.active = false
    sendAllSeq.targetN = 0
    sendAllSeq.rows = nil
    sendAllSeq.index = 1
    sendAllSeq.waitingForMail = false
    sendAllSeq.usePreallocated = false
    sendAllSeq.fromCompose = false
    sendBar.sending = false
    if msg then
        ChatInfo(msg)
    end
    if fromCompose then
        if (DS.IsMailOpen and DS:IsMailOpen()) and IsMailboxActuallyOpen() then
            UpdateSendBarMode("idle")
        else
            -- Leave mode as compose so UpdateSendBarMode sees the transition and
            -- reverts column widths; mailbox-closed forces tip inside the updater.
            UpdateSendBarMode()
        end
        if RefreshList then
            RefreshList()
        end
    else
        SyncQtyControls()
        SyncSendButtonState()
        ApplyRowInteractivity()
    end
end

sendAllSeq.ScheduleAdvance = function(delay)
    local function go()
        if not sendAllSeq.active then
            return
        end
        sendAllSeq.waitingForMail = false
        sendAllSeq.Advance()
    end
    local d = delay
    if d == nil then
        d = sendAllSeq.ADVANCE_DELAY
    end
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After and d > 0 then
        ctimer.After(d, go)
    else
        go()
    end
end

--- opts.abortSendAll: mailbox closed — stop the whole send-all run.
--- opts.skipSendAllContinue: clear attach without continuing send-all (e.g. superseding a prior attach).
--- Otherwise, if send-all was waiting on this attach, continue to the next row.
local function AbortAttachSeq(msg, opts)
    ResetAttachSeqState()
    ClearCursor()
    if msg then
        ChatInfo(msg)
    end
    opts = opts or {}
    if opts.abortSendAll then
        if sendAllSeq.active then
            sendAllSeq.Finish("Send-all aborted (mailbox closed).")
        end
        return
    end
    if opts.skipSendAllContinue then
        return
    end
    if sendAllSeq.active and sendAllSeq.waitingForMail then
        sendAllSeq.ScheduleAdvance(0.5)
    end
end

--- The subject Blizzard's Send button would give the mail: what the player typed, else the first
--- attachment's name, else a dot (the UI's gate wants one).
local function StockpileMailSubject()
    local subj = _G.SendMailSubjectEditBox
    local text = subj and subj.GetText and subj:GetText() or ""
    if text ~= "" then
        return text
    end
    local getSendMailItem = _G.GetSendMailItem
    if getSendMailItem then
        local name = getSendMailItem(1)
        if name and name ~= "" then
            return name
        end
    end
    return "."
end

--- Send the attached stockpile through the client's SendMail API, never Blizzard's mail UI functions
--- (SendMailFrame_Update, SendMailFrame_CanSend, SendMailFrame_SendMail, StationeryPopupButton_OnClick or
--- a Click on SendMailMailButton): Lua run from an addon is tainted, and those would leave tainted state in
--- Blizzard's mail frame. The recipient is the one this send set; the edit box is only read as a fallback.
local function FireStockpileMailSend(recipient)
    local sendMail = _G.SendMail
    if type(sendMail) ~= "function" then
        ChatInfo("Cannot send: this client has no SendMail API.")
        return false
    end
    if not recipient or recipient == "" then
        local eb = _G.SendMailNameEditBox
        recipient = eb and eb.GetText and eb:GetText() or ""
    end
    if recipient == "" then
        ChatInfo("Cannot send: no recipient.")
        return false
    end
    local body = _G.SendMailBodyEditBox
    local bodyText = body and body.GetText and body:GetText() or ""
    sendMail(recipient, StockpileMailSubject(), bodyText)
    return true
end

local function CompleteAttachSeqAndSendMail()
    local pending = nil
    if stockpileAttachSeq.successTargetDisplayName then
        pending = {
            displayName = stockpileAttachSeq.successTargetDisplayName,
            classFile = stockpileAttachSeq.successTargetClassFile,
        }
    end
    local recipient = stockpileAttachSeq.recipient
    ResetAttachSeqState()
    ClearCursor()
    stockpileMailPendingAnnounce = pending

    local function runSend()
        FireStockpileMailSend(recipient)
    end
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(0, runSend)
    else
        runSend()
    end
end

-- Abort attachment when mailbox closes; announce stockpile send on mail sent; sync send bar.
-- TBC Anniversary often does not fire MAIL_CLOSED — also listen to interaction-manager + MailFrame hooks.
local MAIL_INTERACTION_TYPE = (
    _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.MailInfo
) or 17

local function OnMailboxOpened()
    UpdateSendBarMode()
end

local function OnMailboxClosed()
    stockpileMailPendingAnnounce = nil
    if stockpileAttachSeq.active then
        AbortAttachSeq(nil, { abortSendAll = true })
    elseif sendAllSeq.active then
        sendAllSeq.Finish("Send-all aborted (mailbox closed).")
    end
    sendBar.sending = false
    UpdateSendBarMode(nil, { forceClosed = true })
end

local function EnsureMailFrameHooks()
    local mf = _G.MailFrame
    if not mf or mf.altArmyCooldownsMailHooked then
        return
    end
    mf.altArmyCooldownsMailHooked = true
    if mf.HookScript then
        mf:HookScript("OnShow", OnMailboxOpened)
        mf:HookScript("OnHide", OnMailboxClosed)
    end
end

local mailCloseWatcher = CreateFrame("Frame", nil, frame)
mailCloseWatcher:RegisterEvent("MAIL_CLOSED")
mailCloseWatcher:RegisterEvent("MAIL_SHOW")
mailCloseWatcher:RegisterEvent("MAIL_SEND_SUCCESS")
mailCloseWatcher:RegisterEvent("MAIL_FAILED")
pcall(function()
    mailCloseWatcher:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    mailCloseWatcher:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
end)
mailCloseWatcher:SetScript("OnEvent", function(_, event, ...)
    if event == "MAIL_SEND_SUCCESS" then
        local p = stockpileMailPendingAnnounce
        if p and p.displayName and p.displayName ~= "" then
            local nameColored = ColorNameByClass(p.displayName, p.classFile)
            ChatInfo("Items sent to " .. nameColored .. ".")
        end
        stockpileMailPendingAnnounce = nil
        if sendAllSeq.active and sendAllSeq.waitingForMail then
            sendAllSeq.ScheduleAdvance(sendAllSeq.ADVANCE_DELAY)
        end
        return
    end
    if event == "MAIL_FAILED" then
        stockpileMailPendingAnnounce = nil
        if sendAllSeq.active and sendAllSeq.waitingForMail then
            ChatInfo("Mail send failed; continuing send-all.")
            sendAllSeq.ScheduleAdvance(sendAllSeq.ADVANCE_DELAY)
        end
        return
    end
    if event == "MAIL_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            local interactionType = ...
            if interactionType ~= MAIL_INTERACTION_TYPE then
                return
            end
        end
        EnsureMailFrameHooks()
        OnMailboxOpened()
        return
    end
    if event == "MAIL_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local interactionType = ...
            if interactionType ~= MAIL_INTERACTION_TYPE then
                return
            end
        end
        OnMailboxClosed()
    end
end)

EnsureMailFrameHooks()

local function StartAttachSeq(steps)
    if not steps or #steps == 0 then
        return
    end
    stockpileAttachSeq.active = true
    stockpileAttachSeq.queue = steps
    stockpileAttachSeq.queueIndex = 1
    stockpileAttachSeq.phase = nil
    stockpileAttachSeq.bagID = nil
    stockpileAttachSeq.slot = nil
    stockpileAttachSeq.expectedCount = nil
    stockpileAttachSeq.startedAt = (time and time()) or 0
    stockpileAttachSeq.lastLogAt = 0
end

local function TryAdvanceAttachSeq()
    if not stockpileAttachSeq.active then return end
    local now = (time and time()) or 0
    local useItem = (C_Container and C_Container.UseContainerItem) or _G.UseContainerItem
    if not useItem then
        AbortAttachSeq("Missing UseContainerItem/C_Container.UseContainerItem")
        return
    end

    local step = stockpileAttachSeq.queue and stockpileAttachSeq.queue[stockpileAttachSeq.queueIndex] or nil
    if not step then
        CompleteAttachSeqAndSendMail()
        return
    end

    if now - (stockpileAttachSeq.startedAt or now) > 10 then
        AbortAttachSeq("Timed out attaching items")
        return
    end

    local attachIndex = FirstFreeAttachmentIndex()
    if not attachIndex then
        AbortAttachSeq("Not enough attachment slots to send stockpile")
        return
    end

    -- If we're waiting on a placed split slot, attach from it once unlocked.
    if stockpileAttachSeq.phase == "waitingPlacedUnlock" then
        local bagID, slot = stockpileAttachSeq.bagID, stockpileAttachSeq.slot
        local count = (bagID and slot) and GetLiveBagSlotCount(bagID, slot) or 0
        local locked = (bagID and slot) and DebugIsSlotLocked(bagID, slot) or false
        local exp = stockpileAttachSeq.expectedCount
        if count <= 0 or locked or (type(exp) == "number" and exp > 0 and count < exp) then
            return
        end
        useItem(bagID, slot)
        stockpileAttachSeq.phase = nil
        stockpileAttachSeq.bagID = nil
        stockpileAttachSeq.slot = nil
        stockpileAttachSeq.expectedCount = nil
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    -- Otherwise, start the next step.
    if step.op == "split_merge_attach" then
        local splitFn = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
        local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
        if not splitFn or not pickup then
            AbortAttachSeq("Missing stack split APIs")
            return
        end
        if DebugIsSlotLocked(step.srcBagID, step.srcSlot) or DebugIsSlotLocked(step.dstBagID, step.dstSlot) then
            return
        end
        ClearCursor()
        splitFn(step.srcBagID, step.srcSlot, step.count)
        pickup(step.dstBagID, step.dstSlot) -- merge cursor split into destination stack
        ClearCursor()
        stockpileAttachSeq.phase = "waitingPlacedUnlock"
        stockpileAttachSeq.bagID = step.dstBagID
        stockpileAttachSeq.slot = step.dstSlot
        stockpileAttachSeq.expectedCount = step.finalCount
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        return
    end

    if step.op == "merge" then
        local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
        if not pickup then
            AbortAttachSeq("Missing pickup API for merges")
            return
        end
        if DebugIsSlotLocked(step.srcBagID, step.srcSlot) or DebugIsSlotLocked(step.dstBagID, step.dstSlot) then
            return
        end
        ClearCursor()
        pickup(step.srcBagID, step.srcSlot)
        pickup(step.dstBagID, step.dstSlot)
        ClearCursor()
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    if step.op == "attach" then
        if DebugIsSlotLocked(step.bagID, step.slot) then
            return
        end
        useItem(step.bagID, step.slot)
        stockpileAttachSeq.queueIndex = stockpileAttachSeq.queueIndex + 1
        stockpileAttachSeq.startedAt = now
        stockpileAttachSeq.lastLogAt = 0
        TryAdvanceAttachSeq()
        return
    end

    -- step.op == "split_attach": split then place into empty slot, then wait unlock+attach.
    local splitFn = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
    local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
    if not splitFn or not pickup then
        AbortAttachSeq("Missing stack split APIs")
        return
    end
    local emptyBag, emptySlot = FindFirstEmptyBagSlot()
    if not emptyBag or not emptySlot then
        AbortAttachSeq("No free bag slots to split stacks")
        return
    end
    stockpileAttachSeq.phase = "waitingPlacedUnlock"
    stockpileAttachSeq.bagID = emptyBag
    stockpileAttachSeq.slot = emptySlot
    stockpileAttachSeq.startedAt = now
    stockpileAttachSeq.lastLogAt = 0
    ClearCursor()
    splitFn(step.bagID, step.slot, step.count)
    pickup(emptyBag, emptySlot)
    ClearCursor()
end

-- Event-driven wakeups for split debug
local stockpileSplitEventFrame = CreateFrame("Frame", nil, UIParent)
stockpileSplitEventFrame:RegisterEvent("BAG_UPDATE")
stockpileSplitEventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
stockpileSplitEventFrame:SetScript("OnEvent", function()
    TryAdvanceAttachSeq()
end)
stockpileSplitEventFrame:SetScript("OnUpdate", function()
    if not stockpileAttachSeq.active then return end
    -- Poll fallback (some clients are noisy on events)
    TryAdvanceAttachSeq()
end)

RunSendStockpile = function(ctx)
    if not ctx or not ctx.spellId or not ctx.targetName or not ctx.requestedCrafts then
        return false
    end
    if DS.IsMailOpen and not DS:IsMailOpen() then
        ChatInfo("Visit a mailbox and click again to send stockpile")
        return false
    end
    local _, curRealm = GetCurrentIdentity()
    if ctx.targetRealm ~= curRealm then
        ChatInfo("Can't send stockpile across realms")
        return false
    end

    local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
    local targetChar = DS.GetCharacter and DS:GetCharacter(ctx.targetName, ctx.targetRealm) or nil
    if not currentChar or not targetChar then
        return false
    end

    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local minCrafts = CD.GetMaxCraftableQuantity
        and CD.GetMaxCraftableQuantity(targetChar, ctx.spellId, getTargetCount)
    local maxCrafts = CD.GetMaxCraftableQuantityAfterTransfer
        and CD.GetMaxCraftableQuantityAfterTransfer(
            targetChar,
            currentChar,
            ctx.spellId,
            getTargetCount,
            getSourceCount
        )
    if minCrafts == nil or maxCrafts == nil then
        return false
    end
    if ctx.requestedCrafts <= minCrafts then
        return false
    end
    if ctx.requestedCrafts > maxCrafts then
        ChatNotEnoughStockpile(
            ctx.targetDisplayName or ctx.targetName,
            ctx.targetClassFile,
            ctx.spellId,
            function(itemId)
                return getSourceCount(currentChar, itemId)
            end
        )
        return false
    end

    if not EnsureSendMailTab() then
        return false
    end

    local clearSendMail = _G.ClearSendMail
    if clearSendMail then
        clearSendMail()
    end

    local recipient = FormatMailRecipient(ctx.targetName, ctx.targetRealm)
    if not SetSendMailRecipient(recipient) then
        return false
    end

    local sendPlan = CD.GetReagentSendPlan and CD.GetReagentSendPlan(
        targetChar,
        currentChar,
        ctx.spellId,
        ctx.requestedCrafts,
        getTargetCount,
        getSourceCount
    )
    if not sendPlan then
        return false
    end

    if stockpileAttachSeq.active then
        AbortAttachSeq(nil, { skipSendAllContinue = true })
    end

    local stacksById = CollectLiveStacksByItemID()
    for _, rr in ipairs(sendPlan) do
        local needToSend = rr.requiredToSend or 0
        if needToSend > 0 then
            local stacks = stacksById[rr.itemID] or {}
            local have = 0
            for _, st in ipairs(stacks) do
                have = have + (st.count or 1)
            end
            if have < needToSend then
                ChatNotEnoughStockpile(
                    ctx.targetDisplayName or ctx.targetName,
                    ctx.targetClassFile,
                    ctx.spellId,
                    function(itemId)
                        return getSourceCount(currentChar, itemId)
                    end
                )
                return false
            end
        end
    end

    local emptySlotsAvailable = CountEmptyBagSlotsLive()
    local steps = {}
    local totalAttachments = 0
    for _, rr in ipairs(sendPlan) do
        local needToSend = rr.requiredToSend or 0
        if needToSend > 0 then
            local itemStacks = stacksById[rr.itemID] or {}
            local stackLimit = GetItemStackLimit(rr.itemID)
            local plan = SP.BuildItemPlan(needToSend, itemStacks, {
                allowMerge = true,
                preferExact = true,
                stackLimit = stackLimit,
                maxAttachments = ATTACHMENTS_MAX_SEND,
                emptySlotsAvailable = emptySlotsAvailable,
            })
            if not plan or not plan.ok then
                local reason = plan and plan.reason or "unknown"
                if reason == "too_many_attachments" then
                    ChatInfo("Too many attachments needed (limit 12)")
                elseif reason == "no_empty_slot_for_split" then
                    ChatInfo("No free bag slots to split stacks")
                else
                    ChatNotEnoughStockpile(nil, ctx.targetClassFile, ctx.spellId, function(itemId)
                        return getSourceCount(currentChar, itemId)
                    end)
                end
                return false
            end
            for _, op in ipairs(plan.ops or {}) do
                steps[#steps + 1] = op
            end
            totalAttachments = totalAttachments + (plan.attachments or 0)
            for _, op in ipairs(plan.ops or {}) do
                if op.op == "split_attach" then
                    emptySlotsAvailable = math.max(0, emptySlotsAvailable - 1)
                end
            end
        end
    end

    if #steps == 0 then
        return false
    end

    ChatInfo("Attaching items...")
    stockpileAttachSeq.successTargetDisplayName = ctx.targetDisplayName or ctx.targetName
    stockpileAttachSeq.successTargetClassFile = ctx.targetClassFile
    stockpileAttachSeq.recipient = recipient
    StartAttachSeq(steps)
    TryAdvanceAttachSeq()
    return true
end

sendAllSeq.SnapshotVisibleRows = function()
    RefreshList()
    local snap = {}
    for _, row in ipairs(activeRows) do
        local rd = row.rowData
        if rd and rd.spellId then
            snap[#snap + 1] = {
                charKeyName = rd.charKeyName,
                name = rd.name,
                realm = rd.realm,
                spellId = rd.spellId,
            }
        end
    end
    return snap
end

sendAllSeq.Advance = function()
    if not sendAllSeq.active then
        return
    end
    if DS.IsMailOpen and not DS:IsMailOpen() then
        sendAllSeq.Finish("Send-all aborted (mailbox closed).")
        return
    end
    if not IsMailboxActuallyOpen() then
        sendAllSeq.Finish("Send-all aborted (mailbox closed).")
        return
    end

    local curName, curRealm = GetCurrentIdentity()
    local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
    if not currentChar or not curName or curName == "" then
        sendAllSeq.Finish("Send-all aborted (no current character).")
        return
    end

    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local rows = sendAllSeq.rows or {}
    local n = sendAllSeq.targetN
    while sendAllSeq.index <= #rows do
        local rd = rows[sendAllSeq.index]
        sendAllSeq.index = sendAllSeq.index + 1
        if rd then
            local targetChar = DS.GetCharacter and DS:GetCharacter(rd.charKeyName, rd.realm) or nil
            local decision

            if sendAllSeq.usePreallocated then
                local req = tonumber(rd.requestedCrafts)
                if req and req >= 1 then
                    decision = { action = "send", requestedCrafts = req }
                else
                    decision = { action = "skip", reason = "enough" }
                end
            else
                local minCrafts, maxCrafts, cappedMax
                if targetChar and rd.spellId then
                    minCrafts = CD.GetMaxCraftableQuantity
                        and CD.GetMaxCraftableQuantity(targetChar, rd.spellId, getTargetCount)
                    maxCrafts = CD.GetMaxCraftableQuantityAfterTransfer
                        and CD.GetMaxCraftableQuantityAfterTransfer(
                            targetChar,
                            currentChar,
                            rd.spellId,
                            getTargetCount,
                            getSourceCount
                        )
                    if minCrafts ~= nil and maxCrafts ~= nil then
                        cappedMax = ComputeMaxCraftsWithAttachmentCap(
                            targetChar,
                            currentChar,
                            rd.spellId,
                            minCrafts,
                            maxCrafts
                        )
                    end
                end

                decision = CD.EvaluateSendAllRow
                    and CD.EvaluateSendAllRow(
                        curName,
                        curRealm,
                        rd.charKeyName,
                        rd.realm,
                        n,
                        minCrafts,
                        cappedMax
                    )
                if not decision then
                    decision = { action = "skip", reason = "unknown" }
                end
            end

            if decision.action == "skip" then
                if decision.reason == "unknown" then
                    local classFile = targetChar and select(2, DS:GetCharacterClass(targetChar))
                    local nameColored = ColorNameByClass(rd.name or rd.charKeyName, classFile)
                    ChatInfo(
                        "Skipping "
                            .. nameColored
                            .. ": open this profession's tradeskill window once to load material counts."
                    )
                elseif decision.reason == "insufficient" then
                    ChatNotEnoughStockpile(
                        rd.name or rd.charKeyName,
                        targetChar and select(2, DS:GetCharacterClass(targetChar)),
                        rd.spellId,
                        function(itemId)
                            return getSourceCount(currentChar, itemId)
                        end
                    )
                end
                -- self / realm / enough: silent skip
            else
                local tgtClass = targetChar and select(2, DS:GetCharacterClass(targetChar))
                local srcClass = select(2, DS:GetCharacterClass(currentChar))
                local started = RunSendStockpile({
                    spellId = rd.spellId,
                    targetName = rd.charKeyName,
                    targetDisplayName = rd.name,
                    targetRealm = rd.realm,
                    targetClassFile = tgtClass,
                    sourceDisplayName = (DS.GetCharacterName and DS:GetCharacterName(currentChar))
                        or curName,
                    sourceClassFile = srcClass,
                    requestedCrafts = decision.requestedCrafts or n,
                })
                if started then
                    sendAllSeq.waitingForMail = true
                    return
                end
                -- RunSendStockpile already logged; continue to next row
            end
        end
    end

    sendAllSeq.Finish("Send-all finished.")
end

--- Kick off /alta sendall N. Requires open mailbox. Snapshots the visible crafting list.
frame.StartSendAllStockpile = function(_, n)
    local targetN = tonumber(n)
    if not targetN or targetN < 1 then
        ChatInfo("Usage: /alta sendall <n>")
        return
    end
    if sendAllSeq.active then
        ChatInfo("Send-all is already in progress.")
        return
    end
    if DS.IsMailOpen and not DS:IsMailOpen() then
        ChatInfo("Visit a mailbox and run /alta sendall again.")
        return
    end
    if not IsMailboxActuallyOpen() then
        ChatInfo("Visit a mailbox and run /alta sendall again.")
        return
    end
    if sendBar.mode == "compose" then
        sendBar.sending = false
        UpdateSendBarMode("idle")
    end
    SetActiveCooldownsView("crafting")
    local snap = sendAllSeq.SnapshotVisibleRows()
    if #snap == 0 then
        ChatInfo("No crafting cooldown rows to send.")
        return
    end
    sendAllSeq.active = true
    sendAllSeq.targetN = targetN
    sendAllSeq.rows = snap
    sendAllSeq.index = 1
    sendAllSeq.waitingForMail = false
    sendAllSeq.usePreallocated = false
    sendAllSeq.fromCompose = false
    ChatInfo(string.format("Send-all started: target %dx across %d row(s).", targetN, #snap))
    sendAllSeq.Advance()
end

local function ReleaseRows()
    recipePicker:Close()
    for _, r in ipairs(activeRows) do
        if Theme.SetHoverTint then
            Theme.SetHoverTint(r, false)
        end
        r:Hide()
        r:SetParent(scrollChild)
        rowPool[#rowPool + 1] = r
    end
    activeRows = {}
end

--- After a list rebuild, row frames are reshuffled under the cursor; re-apply hover/tooltip.
local function SyncRowHoverUnderMouse()
    if sendBar.mode ~= "compose" then
        return
    end
    if not MouseIsOver then
        return
    end
    local under = nil
    for _, row in ipairs(activeRows) do
        if Theme.SetHoverTint then
            Theme.SetHoverTint(row, false)
        end
        if not under and row.sendEligible and row:IsShown() and MouseIsOver(row) then
            under = row
        end
    end
    if not under then
        return
    end
    if Theme.SetHoverTint then
        Theme.SetHoverTint(under, true)
    end
    -- Prefer mats send tooltip when the cursor is still over that cell.
    if under.matSlot and MouseIsOver(under.matSlot) and under.sendChecked and under.allocPreview then
        local enter = under.matSlot:GetScript("OnEnter")
        if enter then
            enter(under.matSlot)
        end
    elseif under:GetScript("OnEnter") then
        under:GetScript("OnEnter")(under)
    end
end

local function CompareCooldownRows(a, b)
    local asc = sortAscending

    local function lessStr(sa, sb)
        if sa == sb then return nil end
        if asc then
            return sa < sb
        end
        return sa > sb
    end

    local function lessNum(na, nb)
        if na == nb then return nil end
        if asc then
            return na < nb
        end
        return na > nb
    end

    if currentSortKey == "recipe" then
        local r = lessStr(a.categoryTitle or "", b.categoryTitle or "")
        if r ~= nil then return r end
    elseif currentSortKey == "character" then
        local r = lessStr(a.name or "", b.name or "")
        if r ~= nil then return r end
        r = lessStr(a.realm or "", b.realm or "")
        if r ~= nil then return r end
    elseif currentSortKey == "mats" then
        local qa, qb = a._sortCraftQty, b._sortCraftQty
        if qa ~= nil or qb ~= nil then
            if qa == nil then
                return false
            elseif qb == nil then
                return true
            else
                local r = lessNum(qa, qb)
                if r ~= nil then return r end
            end
        end
    elseif currentSortKey == "time" then
        local ea, eb = a.expiresUnix, b.expiresUnix
        if ea ~= nil or eb ~= nil then
            if ea == nil then
                return false
            elseif eb == nil then
                return true
            else
                local r = lessNum(ea, eb)
                if r ~= nil then return r end
            end
        end
    end

    local r = lessStr(a.categoryTitle or "", b.categoryTitle or "")
    if r ~= nil then return r end
    r = lessStr(a.name or "", b.name or "")
    if r ~= nil then return r end
    r = lessStr(a.realm or "", b.realm or "")
    if r ~= nil then return r end
    return false
end

local function SoftUpdateActiveRowTimes(now)
    now = now or (time and time() or 0)
    for _, row in ipairs(activeRows) do
        local rd = row.rowData
        if rd then
            local expUnix = rd.expiresUnix
            local text = CD.FormatTimeRemaining(expUnix, now)
            rd.timeText = text
            row.timeCell:SetText(text or "")
            if expUnix == nil then
                row.timeCell:SetTextColor(1, 1, 0.4, 1)
            elseif expUnix <= now then
                row.timeCell:SetTextColor(0, 1, 0, 1)
            else
                row.timeCell:SetTextColor(1, 0.35, 0.35, 1)
            end
        end
    end
end

--- True when the visible row set matches existing frames (same keys, same order).
--- Avoids ReleaseRows/Hide which cancels in-flight Button clicks and hover.
local function CanReuseActiveCooldownRows(rows)
    if #activeRows ~= #rows then
        return false
    end
    for i, rd in ipairs(rows) do
        local row = activeRows[i]
        if not row or row.sendKey ~= RowSendKey(rd) then
            return false
        end
    end
    return true
end

local function IsLeftMouseDown()
    return IsMouseButtonDown and IsMouseButtonDown("LeftButton")
end

local function FillCooldownListRow(row, rd, now, compose, curName, curRealm, opts)
    opts = opts or {}
    row.charTableRef = DS:GetCharacter(rd.charKeyName, rd.realm)
    row.catCell:SetText(FormatRecipeColumnText(rd.spellId, rd.categoryTitle or "", row.charTableRef))
    local groupPickable = CD.IsGroupCategory and CD.IsGroupCategory(rd.categoryKey)
    local pickerOpenOnRow = recipePicker.row == row and recipePicker:IsOpen()
    if row.catCell then
        row.catCell:SetShown(not pickerOpenOnRow)
    end
    if row.catBtn then
        row.catBtn:EnableMouse(true)
        if not groupPickable and Theme.SetHoverTint then
            Theme.SetHoverTint(row.catBtn, false)
        end
    end
    if pickerOpenOnRow then
        recipePicker:AttachSearch(row, false)
    end
    local _, classFile = DS:GetCharacterClass(row.charTableRef)
    row.charCell:SetTextColor(1, 1, 1, 1)
    local showRealm = (AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Get() == "all")
        and AccountHasMultipleRealms()
        and rd.realm
        and rd.realm ~= ""
    local charText = RF and RF.formatColoredCharacterNameRealm
        and RF.formatColoredCharacterNameRealm(rd.name or "", rd.realm, showRealm, classFile)
        or ((rd.name or "") .. (showRealm and (" — " .. rd.realm) or ""))
    row.charCell:SetText(charText)
    row.timeCell:SetText(rd.timeText or "")
    local expUnix = rd.expiresUnix
    if expUnix == nil then
        row.timeCell:SetTextColor(1, 1, 0.4, 1)
    elseif expUnix <= now then
        row.timeCell:SetTextColor(0, 1, 0, 1)
    else
        row.timeCell:SetTextColor(1, 0.35, 0.35, 1)
    end
    row.spellId = rd.spellId
    row.rowData = rd
    row.allocPreview = nil

    local key = RowSendKey(rd)
    row.sendKey = key
    local isSelf = (rd.charKeyName == curName) and (rd.realm == curRealm)
    local sameRealm = (rd.realm == curRealm)
    row.sendEligible = (not isSelf) and sameRealm
    local fadingSend = (sendBar.headerOffset or 0) > 0.5 or (colWidths.Send or 0) > 0.5
    if compose or fadingSend then
        local checked
        if compose then
            if sendBar.checks[key] ~= nil then
                checked = sendBar.checks[key] and true or false
            else
                checked = row.sendEligible and true or false
                sendBar.checks[key] = checked
            end
            if not row.sendEligible then
                checked = false
                sendBar.checks[key] = false
            end
        else
            checked = false
        end
        row.sendChecked = checked
        -- Avoid SetChecked/Enable mid-click; they can cancel CheckButton OnClick.
        if row.sendCheck and not opts.preserveChecks then
            row.sendCheck:SetChecked(checked)
            if compose and row.sendEligible and not sendBar.sending then
                row.sendCheck:Enable()
            else
                row.sendCheck:Disable()
            end
        end
    else
        row.sendChecked = false
    end

    -- Default mats display; RecomputeSendAllocation may replace with preview.
    local craftQty = rd._sortCraftQty
    if craftQty == nil then
        row.matCountLabel:Hide()
        row.matIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
        row.matIcon:Show()
    elseif craftQty >= 1 then
        row.matIcon:Hide()
        local label = craftQty >= 100 and "99+x" or (tostring(craftQty) .. "x")
        row.matCountLabel:SetText(label)
        row.matCountLabel:SetTextColor(0, 1, 0, 1)
        row.matCountLabel:Show()
    else
        row.matIcon:Hide()
        row.matCountLabel:SetText("0x")
        row.matCountLabel:SetTextColor(1, 0.25, 0.25, 1)
        row.matCountLabel:Show()
    end

    -- Apply current column sizes (animation may be mid-flight).
    if row.catCell then
        if row.catBtn then
            row.catBtn:SetSize(colWidths.Category, ROW_HEIGHT)
        end
        row.catCell:SetSize(colWidths.Category, ROW_HEIGHT)
        row.charCell:SetSize(colWidths.Character, ROW_HEIGHT)
        if row.matSlot then
            row.matSlot:SetSize(colWidths.Mats, ROW_HEIGHT)
        end
        row.timeCell:SetSize(colWidths.Time, ROW_HEIGHT)
        if row.sendSlot and colWidths.Send > 0.5 then
            row.sendSlot:SetSize(colWidths.Send, ROW_HEIGHT)
        end
    end
end

RefreshList = function()
    CD.EnsureCooldownOptions()
    local opts = AltArmyTBC_Options and AltArmyTBC_Options.cooldowns
    if not opts then return end

    local now = time and time() or 0
    local rows = CD.BuildRows(DS, opts, now)
    do
        local GRF = AltArmy.GlobalRealmFilter
        local rf = GRF and GRF.Get and GRF.Get() or "all"
        if rf == "currentRealm" then
            local _, curRealm = GetCurrentIdentity()
            local filtered = {}
            for _, rd in ipairs(rows) do
                if rd.realm == curRealm then
                    filtered[#filtered + 1] = rd
                end
            end
            rows = filtered
        end
    end

    for _, rd in ipairs(rows) do
        local ch = DS:GetCharacter(rd.charKeyName, rd.realm)
        rd._sortCraftQty = nil
        if ch and rd.spellId and CD.GetMaxCraftableQuantity then
            rd._sortCraftQty = CD.GetMaxCraftableQuantity(ch, rd.spellId, GetItemCountForMats)
        end
    end

    table.sort(rows, CompareCooldownRows)

    local reuse = CanReuseActiveCooldownRows(rows)
    -- Hiding/repooling frames while LMB is down cancels Button OnClick (and matSlot down/up).
    if IsLeftMouseDown() and #activeRows > 0 and not reuse then
        sendBar.pendingRefresh = true
        SoftUpdateActiveRowTimes(now)
        return
    end
    sendBar.pendingRefresh = false

    if not reuse then
        ReleaseRows()
    end

    local totalH = math.max(1, #rows) * ROW_HEIGHT
    scrollChild:SetSize(totalColWidth, totalH)

    local curName, curRealm = GetCurrentIdentity()
    local compose = sendBar.mode == "compose"
    local preserveChecks = reuse and IsLeftMouseDown()

    local y = 0
    for i, rd in ipairs(rows) do
        local row
        if reuse then
            row = activeRows[i]
        else
            row = PoolRow()
            activeRows[#activeRows + 1] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetWidth(totalColWidth)
        y = y - ROW_HEIGHT
        FillCooldownListRow(row, rd, now, compose, curName, curRealm, {
            preserveChecks = preserveChecks,
        })
    end

    do
        local fadeAlpha = 0
        if SELECT_ALL_HEIGHT > 0 then
            fadeAlpha = math.min(1, (sendBar.headerOffset or 0) / SELECT_ALL_HEIGHT)
        end
        SyncSendCheckFade(fadeAlpha)
    end

    ApplyRowInteractivity()

    if compose and RecomputeSendAllocation then
        RecomputeSendAllocation()
    end

    scrollBinding.UpdateRange()
    if cooldownHeaderFade then
        cooldownHeaderFade:Update()
    end
    local isEmpty = #rows == 0
    headerRow:SetShown(not isEmpty)
    listViewport:SetShown(not isEmpty)
    tipRow:SetShown(not isEmpty)
    if isEmpty then
        scrollBar:Hide()
    end
    craftingEmptyLabel:SetShown(isEmpty)
    -- Only re-sync hover after a real frame reshuffle; in-place updates keep the same widgets.
    if not reuse then
        SyncRowHoverUnderMouse()
    end
end

local function FormatMatsPreview(craftQty, willHave, desiredN)
    local left = craftQty >= 100 and "99+" or tostring(craftQty)
    local rightN = willHave or craftQty
    local right = rightN >= 100 and "99+" or tostring(rightN)
    local leftColor = craftQty >= 1 and "|cff00ff00" or "|cffff4040"
    local rightColor = (rightN >= (desiredN or 1)) and "|cff00ff00" or "|cffffc033"
    return leftColor .. left .. "x|r -> " .. rightColor .. right .. "x|r"
end

RecomputeSendAllocation = function()
    sendBar.allocByKey = {}
    sendBar.anyChecked = false
    if sendBar.mode ~= "compose" then
        SyncSendButtonState()
        SyncSelectAllCheck()
        return
    end

    local curName, curRealm = GetCurrentIdentity()
    local currentChar = DS.GetCurrentCharacter and DS:GetCurrentCharacter() or nil
    local getTargetCount = function(ch, itemId)
        return DS.GetTotalItemCount and DS:GetTotalItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end
    local getSourceCount = function(ch, itemId)
        return DS.GetBagItemCount and DS:GetBagItemCount(ch, itemId) or DS:GetContainerItemCount(ch, itemId)
    end

    local sourceCounts = {}
    local inputs = {}
    local desired = sendBar.targetN or 1

    for _, row in ipairs(activeRows) do
        local rd = row.rowData
        local selected = row.sendChecked and row.sendEligible and true or false
        if selected then
            sendBar.anyChecked = true
        end
        local skip = nil
        if rd then
            if (rd.charKeyName == curName) and (rd.realm == curRealm) then
                skip = "self"
            elseif rd.realm ~= curRealm then
                skip = "realm"
            end
        end
        local minCrafts = nil
        local reagents = nil
        local targetChar = row.charTableRef
        if targetChar and rd and rd.spellId and CD.GetReagentList then
            local list = CD.GetReagentList(rd.spellId)
            if list then
                minCrafts = CD.GetMaxCraftableQuantity
                    and CD.GetMaxCraftableQuantity(targetChar, rd.spellId, getTargetCount)
                reagents = {}
                for _, pair in ipairs(list) do
                    local itemId, need = pair[1], pair[2] or 1
                    local targetHave = getTargetCount(targetChar, itemId) or 0
                    reagents[#reagents + 1] = {
                        itemID = itemId,
                        need = need,
                        targetHave = targetHave,
                    }
                    if currentChar and selected and not skip then
                        if sourceCounts[itemId] == nil then
                            sourceCounts[itemId] = getSourceCount(currentChar, itemId) or 0
                        end
                    end
                end
            end
        end
        inputs[#inputs + 1] = {
            selected = selected,
            skip = skip,
            minCrafts = minCrafts,
            reagents = reagents,
        }
    end

    local result = CD.AllocateSendAllCrafts and CD.AllocateSendAllCrafts(desired, sourceCounts, inputs)
        or { rows = {} }
    for i, row in ipairs(activeRows) do
        local alloc = result.rows[i] or { willHave = 0, delta = 0, shortfall = false }
        row.allocPreview = alloc
        local key = row.sendKey
        if key then
            sendBar.allocByKey[key] = alloc
        end
        local rd = row.rowData
        local craftQty = rd and rd._sortCraftQty
        if craftQty == nil then
            row.matCountLabel:Hide()
            row.matIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
            row.matIcon:Show()
        elseif row.sendChecked and row.sendEligible then
            row.matIcon:Hide()
            row.matCountLabel:SetText(FormatMatsPreview(craftQty, alloc.willHave, desired))
            row.matCountLabel:SetTextColor(1, 1, 1, 1)
            row.matCountLabel:Show()
        elseif craftQty >= 1 then
            row.matIcon:Hide()
            local label = craftQty >= 100 and "99+x" or (tostring(craftQty) .. "x")
            row.matCountLabel:SetText(label)
            row.matCountLabel:SetTextColor(0, 1, 0, 1)
            row.matCountLabel:Show()
        else
            row.matIcon:Hide()
            row.matCountLabel:SetText("0x")
            row.matCountLabel:SetTextColor(1, 0.25, 0.25, 1)
            row.matCountLabel:Show()
        end
    end
    SyncSendButtonState()
    SyncSelectAllCheck()
end

sendBar.AbortSending = function(msg)
    if stockpileAttachSeq.active then
        ResetAttachSeqState()
        ClearCursor()
    end
    if sendAllSeq.active then
        sendAllSeq.Finish(msg or "Send cancelled.")
    else
        sendBar.sending = false
    end
end

sendBar.StartSending = function()
    if sendBar.mode ~= "compose" or sendBar.sending then
        return
    end
    if DS.IsMailOpen and not DS:IsMailOpen() then
        ChatInfo("Visit a mailbox to send materials.")
        return
    end
    if not IsMailboxActuallyOpen() then
        ChatInfo("Visit a mailbox to send materials.")
        return
    end
    if RecomputeSendAllocation then
        RecomputeSendAllocation()
    end
    if not sendBar.anyChecked then
        return
    end
    local snap = {}
    for _, row in ipairs(activeRows) do
        local rd = row.rowData
        local alloc = row.allocPreview
        if rd and row.sendChecked and row.sendEligible and alloc and (alloc.delta or 0) > 0 then
            snap[#snap + 1] = {
                charKeyName = rd.charKeyName,
                name = rd.name,
                realm = rd.realm,
                spellId = rd.spellId,
                requestedCrafts = alloc.willHave,
            }
        end
    end
    if #snap == 0 then
        ChatInfo("Nothing to send for the selected characters.")
        return
    end
    sendBar.sending = true
    SyncQtyControls()
    SyncSendButtonState()
    ApplyRowInteractivity()
    for _, row in ipairs(activeRows) do
        if row.sendCheck then
            row.sendCheck:Disable()
        end
    end
    sendAllSeq.active = true
    sendAllSeq.targetN = sendBar.targetN or 1
    sendAllSeq.rows = snap
    sendAllSeq.index = 1
    sendAllSeq.waitingForMail = false
    sendAllSeq.usePreallocated = true
    sendAllSeq.fromCompose = true
    ChatInfo(string.format("Sending materials: target %dx across %d character(s).", sendAllSeq.targetN, #snap))
    sendAllSeq.Advance()
end

frame.RefreshCooldownList = RefreshList

SetActiveCooldownsView = function(which)
    if which ~= "crafting" and which ~= "raids" then
        which = "crafting"
    end
    if which == "raids" and sendBar.mode == "compose" then
        if sendBar.sending and sendBar.AbortSending then
            sendBar.AbortSending("Send cancelled.")
        end
        ExitComposeMode({ keepIdle = true })
    end
    VIEW.active = which
    if LD and LD.EnsureLockoutListOptions then
        local opts = LD.EnsureLockoutListOptions()
        opts.activeView = which
    elseif AltArmyTBC_Options and AltArmyTBC_Options.cooldowns then
        AltArmyTBC_Options.cooldowns.activeView = which
    end
    tabContentPanel:SetShown(which == "crafting")
    raidsPanel:SetShown(which == "raids")
    if VIEW.tabs then
        VIEW.tabs:SetSelected(which)
    end
    if which == "raids" then
        recipePicker:Close()
        if DS.RequestLockoutInfo then
            DS:RequestLockoutInfo()
        end
        if frame.RefreshRaidsList then
            frame.RefreshRaidsList()
        end
    else
        SyncSortFromSaved()
        UpdateHeaderSortIndicators()
        UpdateSendBarMode()
        RefreshList()
    end
end
frame.SetCooldownsView = SetActiveCooldownsView

-- Tabs hang from the panel top up into the main window's toolbar row (left of the search box).
-- Parented to the tab frame so they hide with it (other tabs, Search mode).
VIEW.tabs = AltArmy.TopTabs.Create(frame, VIEW.defs, {
    mainTab = "Cooldowns",
    onSelect = function(id)
        if VIEW.active ~= id then
            SetActiveCooldownsView(id)
        end
    end,
})
VIEW.tabs.frame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", AltArmy.MainToolbarInsetX or 54, 0)
frame.ViewTabs = VIEW.tabs -- `/alta <tab> <view>` opens only the views that have a tab (Core.lua)

frame:HookScript("OnHide", function()
    recipePicker:Close()
end)

frame:SetScript("OnShow", function()
    local which = "crafting"
    if LD and LD.EnsureLockoutListOptions then
        which = LD.EnsureLockoutListOptions().activeView or "crafting"
    elseif AltArmyTBC_Options and AltArmyTBC_Options.cooldowns and AltArmyTBC_Options.cooldowns.activeView then
        which = AltArmyTBC_Options.cooldowns.activeView
    end
    SetActiveCooldownsView(which)
end)

local upd = 0
frame:SetScript("OnUpdate", function(_, dt)
    StepColumnAnim(dt)
    if AltArmy.CurrentTab ~= "Cooldowns" then
        recipePicker:Close()
        if sendBar.mode == "compose" then
            if sendBar.sending and sendBar.AbortSending then
                sendBar.AbortSending("Send cancelled.")
            end
            if sendBar.mode == "compose" then
                ExitComposeMode()
            end
        end
        return
    end
    -- Finish a deferred full rebuild after LMB release (see RefreshList).
    if sendBar.pendingRefresh and VIEW.active ~= "raids" and not IsLeftMouseDown() then
        sendBar.pendingRefresh = false
        RefreshList()
    end
    upd = upd + dt
    if upd >= REFRESH_INTERVAL then
        upd = 0
        if VIEW.active == "raids" then
            if frame.RefreshRaidsList then
                frame.RefreshRaidsList()
            end
        else
            UpdateSendBarMode()
            RefreshList()
        end
    end
end)
