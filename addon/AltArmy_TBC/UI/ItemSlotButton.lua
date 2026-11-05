-- AltArmy TBC — an item slot drawn like the stock bag windows (ItemButtonTemplate's pieces, by hand so
-- both clients draw the same): the UI-Quickslot2 slot art, the empty-slot well, the icon, the stack count
-- in the outlined number font and the quality border. Hovering shows the item tooltip; Shift-click links
-- it to chat and Ctrl-click previews it, through UI/ItemActions.lua like the Gear and Search tabs.
-- Used by the Inventory tab for bags, bank and mail attachments; ApplySearch draws its item search (a ring
-- on a match, the rest dimmed).
-- luacheck: globals GameTooltip ITEM_QUALITY_COLORS

AltArmy = AltArmy or {}
AltArmy.ItemSlotButton = AltArmy.ItemSlotButton or {}
local ISB = AltArmy.ItemSlotButton

ISB.SIZE = 37 -- ContainerFrameItemButtonTemplate
ISB.SPACING = 5 -- the stock 42 px pitch
ISB.SLOT_ART_SIZE = 64 -- UI-Quickslot2 is drawn 64 px around a 37 px button
ISB.NORMAL_TEXTURE = "Interface\\Buttons\\UI-Quickslot2"
ISB.PUSHED_TEXTURE = "Interface\\Buttons\\UI-Quickslot-Depress"
ISB.HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"
ISB.BORDER_TEXTURE = "Interface\\Common\\WhiteIconFrame" -- ItemButtonTemplate's IconBorder
ISB.EMPTY_ATLAS = "bags-item-slot64" -- retail / Forever ContainerFrame (NativeUI caps.bagSlotAtlas)
ISB.EMPTY_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot" -- the classic well
ISB.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
ISB.MIN_BORDER_QUALITY = 2 -- uncommon and better, as the stock bags
ISB.SEARCH_GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border" -- the action bar's glow ring
ISB.SEARCH_GLOW_SCALE = 1.8 -- the ring's art is drawn inside a larger square
ISB.SEARCH_GLOW_COLOR = { 1, 0.82, 0 } -- gold
ISB.DIMMED_ALPHA = 0.3 -- a slot the search leaves out
-- Retail's combined bags' BagIndicator: the blue glow on a hovered bag's slots (in every client's art).
ISB.BAG_HIGHLIGHT_TEXTURE = "Interface\\Store\\store-item-highlight"
ISB.BAG_BACKGROUND_ALPHA = 0.3 -- the bag's icon behind a combined layout's slot

-- Fallbacks for ITEM_QUALITY_COLORS (uncommon, rare, epic, legendary).
local QUALITY_RGB = { [2] = { 0, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

local function resolveCaps(opts)
    if opts and opts.caps then return opts.caps end
    local NativeUI = AltArmy.NativeUI
    return NativeUI and NativeUI.GetCaps and NativeUI.GetCaps() or {}
end

-- Theme.FONTS.count (NumberFontNormal, as ItemButtonTemplate's Count); Theme loads before this file.
local function countFont()
    local Theme = AltArmy.Theme
    return Theme and Theme.FONTS and Theme.FONTS.count
end

--- name, quality, texture for an item id or link, from whichever item API the client has.
local function itemInfo(itemIDOrLink)
    local DS = AltArmy.DataStore
    local name, quality, texture
    if DS and DS.CompatGetItemInfo then
        local n, _, q, _, _, _, _, _, _, t = DS.CompatGetItemInfo(itemIDOrLink)
        name, quality, texture = n, q, t
    elseif _G.GetItemInfo then
        local n, _, q, _, _, _, _, _, _, t = _G.GetItemInfo(itemIDOrLink)
        name, quality, texture = n, q, t
    end
    return name, quality, texture
end

local function itemIcon(itemID)
    if not itemID then return nil end
    if _G.GetItemIcon then
        local icon = _G.GetItemIcon(itemID)
        if icon then return icon end
    end
    local CI = _G.C_Item
    if CI and CI.GetItemIconByID then
        return CI.GetItemIconByID(itemID)
    end
    return nil
end

local function itemQuality(itemID)
    local CI = _G.C_Item
    if itemID and CI and CI.GetItemQualityByID then
        return CI.GetItemQualityByID(itemID)
    end
    return nil
end

--- The border colour for a quality, or nil when no border is drawn.
function ISB.QualityColor(quality)
    if type(quality) ~= "number" or quality < ISB.MIN_BORDER_QUALITY then return nil end
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if c and c.r then return c.r, c.g, c.b end
    local f = QUALITY_RGB[quality] or QUALITY_RGB[5]
    return f[1], f[2], f[3]
end

local function onEnter(btn)
    if btn.onHover then btn.onHover(btn, true) end
    local entry = btn.entry
    if not entry or not GameTooltip then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if entry.link and entry.link ~= "" then
        GameTooltip:SetHyperlink(entry.link)
    elseif entry.itemID and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(entry.itemID)
    elseif entry.name then
        GameTooltip:SetText(entry.name)
    else
        GameTooltip:Hide()
        return
    end
    if btn.tooltipExtra then
        btn.tooltipExtra(btn, GameTooltip, entry)
    end
    GameTooltip:Show()
end

local function onLeave(btn)
    if btn.onHover then btn.onHover(btn, false) end
    if GameTooltip then GameTooltip:Hide() end
end

local function onClick(btn, button)
    local entry = btn.entry
    local IA = AltArmy.ItemActions
    if not entry or not IA then return end
    local target = entry.link or entry.itemID
    if not target then return end
    local shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown()
    local ctrl = _G.IsControlKeyDown and _G.IsControlKeyDown()
    local action = IA.GetClickAction(button, shift, ctrl)
    if action == "preview" then
        IA.PreviewInDressingRoom(target)
    elseif action == "chatlink" then
        IA.InsertLinkIntoChat(target)
    end
end

--- A slot button on `parent`. opts.size (default ISB.SIZE), opts.caps (tests).
function ISB.Create(parent, opts)
    opts = opts or {}
    local caps = resolveCaps(opts)
    local size = opts.size or ISB.SIZE
    local scale = size / ISB.SIZE
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    -- The well behind the icon: the retail atlas where the client has it, else the classic texture.
    local empty = btn:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints(btn)
    if caps.bagSlotAtlas and empty.SetAtlas then
        empty:SetAtlas(ISB.EMPTY_ATLAS)
        btn.emptyIsAtlas = true
    else
        empty:SetTexture(ISB.EMPTY_TEXTURE)
    end
    btn.emptyBg = empty

    -- The combined layout's slot background: its bag's icon, faint and grey, in place of the well (as
    -- Blizzard's combined backpack draws it); the item's icon covers it.
    local bagBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    bagBg:SetAllPoints(btn)
    if bagBg.SetAlpha then bagBg:SetAlpha(ISB.BAG_BACKGROUND_ALPHA) end
    if bagBg.SetDesaturated then bagBg:SetDesaturated(true) end -- grey, as Blizzard's
    bagBg:Hide()
    btn.bagBg = bagBg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:Hide()
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture(ISB.BORDER_TEXTURE)
    border:SetSize(size, size)
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:Hide()
    btn.border = border

    -- The ring around a slot the Inventory search matches.
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(ISB.SEARCH_GLOW_TEXTURE)
    if glow.SetBlendMode then glow:SetBlendMode("ADD") end
    glow:SetVertexColor(ISB.SEARCH_GLOW_COLOR[1], ISB.SEARCH_GLOW_COLOR[2], ISB.SEARCH_GLOW_COLOR[3])
    glow:SetSize(size * ISB.SEARCH_GLOW_SCALE, size * ISB.SEARCH_GLOW_SCALE)
    glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    glow:Hide()
    btn.searchGlow = glow

    -- The glow on the slots of the bag the combined layout's bag bar is hovering (OVERLAY sublevel 2, as
    -- retail draws it); the art is drawn larger than the button, like the slot art.
    local bagHighlight = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    bagHighlight:SetTexture(ISB.BAG_HIGHLIGHT_TEXTURE)
    bagHighlight:SetSize(ISB.SLOT_ART_SIZE * scale, ISB.SLOT_ART_SIZE * scale)
    bagHighlight:SetPoint("CENTER", btn, "CENTER", 0, 0)
    bagHighlight:Hide()
    btn.bagHighlight = bagHighlight

    local count = btn:CreateFontString(nil, "OVERLAY", countFont())
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5 * scale, 2 * scale)
    count:SetJustifyH("RIGHT")
    count:Hide()
    btn.count = count

    -- The slot frame around the button (ItemButtonTemplate's NormalTexture), with its push and hover art.
    if btn.SetNormalTexture then
        btn:SetNormalTexture(ISB.NORMAL_TEXTURE)
        local normal = btn.GetNormalTexture and btn:GetNormalTexture()
        if normal and normal.SetSize then
            normal:SetSize(ISB.SLOT_ART_SIZE * scale, ISB.SLOT_ART_SIZE * scale)
            normal:ClearAllPoints()
            normal:SetPoint("CENTER", btn, "CENTER", 0, -1 * scale)
        end
    end
    if btn.SetPushedTexture then btn:SetPushedTexture(ISB.PUSHED_TEXTURE) end
    if btn.SetHighlightTexture then btn:SetHighlightTexture(ISB.HIGHLIGHT_TEXTURE, "ADD") end

    btn:SetScript("OnEnter", onEnter)
    btn:SetScript("OnLeave", onLeave)
    btn:SetScript("OnClick", onClick)
    btn.entry = nil
    return btn
end

--- Whether an item called `name` matches the lowercased search `queryLower`: a plain, case-insensitive
--- substring; everything matches an empty query, and nothing a nil name (not cached yet).
function ISB.NameMatches(name, queryLower)
    if not queryLower or queryLower == "" then return true end
    if type(name) ~= "string" then return false end
    return name:lower():find(queryLower, 1, true) ~= nil
end

local function setSearchLook(btn, glow, dimmed)
    if glow then btn.searchGlow:Show() else btn.searchGlow:Hide() end
    if btn.SetAlpha then btn:SetAlpha(dimmed and ISB.DIMMED_ALPHA or 1) end
    if btn.icon.SetDesaturated then btn.icon:SetDesaturated(dimmed) end
end

--- Draw the slot for the lowercased search `queryLower`: an item whose name matches gets the ring, every
--- other slot (empty ones too) is dimmed and greyed; an empty query draws the slot plainly.
function ISB.ApplySearch(btn, queryLower)
    if not queryLower or queryLower == "" then
        setSearchLook(btn, false, false)
        return
    end
    local entry = btn.entry
    local isItem = entry ~= nil and (entry.itemID ~= nil or entry.link ~= nil)
    local match = isItem and ISB.NameMatches(btn.itemName, queryLower)
    setSearchLook(btn, match, not match)
end

--- Show or hide the hovered bag's glow on the slot.
function ISB.SetBagHighlight(btn, shown)
    if shown then btn.bagHighlight:Show() else btn.bagHighlight:Hide() end
end

--- Draw `texture` (a bag's icon) faintly behind the slot in place of the empty-slot well, or the well again
--- with nil. Call after SetItem or SetEmpty (which bring the well back).
function ISB.SetBagBackground(btn, texture)
    if texture then
        btn.bagBg:SetTexture(texture)
        btn.bagBg:Show()
        btn.emptyBg:Hide()
    else
        btn.bagBg:Hide()
        btn.emptyBg:Show()
    end
end

--- Show nothing in the slot.
function ISB.SetEmpty(btn)
    btn.entry = nil
    btn.itemName = nil
    setSearchLook(btn, false, false)
    btn.bagHighlight:Hide()
    btn.bagBg:Hide()
    btn.icon:Hide()
    btn.border:Hide()
    btn.count:Hide()
    btn.count:SetText("")
    btn.emptyBg:Show()
end

--- Show an item: entry = { itemID, count, link, icon }. Returns the item id when its icon is not in the
--- client's cache yet (shown as a question mark), so the caller can redraw on GET_ITEM_INFO_RECEIVED.
--- An entry with only `icon` (and a `name` for its tooltip) draws that icon: the bag bar's backpack.
function ISB.SetItem(btn, entry)
    if not entry or not (entry.itemID or entry.link or entry.icon) then
        ISB.SetEmpty(btn)
        return nil
    end
    btn.entry = entry
    local name, quality, texture
    if entry.itemID or entry.link then
        name, quality, texture = itemInfo(entry.link or entry.itemID)
    end
    btn.itemName = name or entry.name
    local icon = entry.icon or texture or itemIcon(entry.itemID)
    local pending = nil
    if not icon then
        icon = ISB.UNKNOWN_ICON
        pending = entry.itemID
    end
    btn.icon:SetTexture(icon)
    btn.icon:Show()
    btn.emptyBg:Show()

    if quality == nil and entry.itemID then
        quality = itemQuality(entry.itemID)
    end
    local r, g, b = ISB.QualityColor(quality)
    if r then
        btn.border:SetVertexColor(r, g, b)
        btn.border:Show()
    else
        btn.border:Hide()
    end

    local n = entry.count or 1
    if n > 1 then
        btn.count:SetText(tostring(n))
        btn.count:Show()
    else
        btn.count:SetText("")
        btn.count:Hide()
    end
    return pending
end

--- A pool of slot buttons on `parent`: Acquire() hands out a shown button (made with opts), ReleaseAll()
--- hides them all. `active` lists the objects handed out since the last release. Other frame kinds pool
--- the same way with opts.create(parent) -> frame and opts.reset(frame) (run on release).
function ISB.CreatePool(parent, opts)
    opts = opts or {}
    local create = opts.create or function(p) return ISB.Create(p, opts) end
    local reset = opts.reset or ISB.SetEmpty
    local pool = { free = {}, active = {} }
    function pool.Acquire()
        local obj = table.remove(pool.free)
        if not obj then
            obj = create(parent)
        end
        obj:Show()
        pool.active[#pool.active + 1] = obj
        return obj
    end
    function pool.ReleaseAll()
        for i = #pool.active, 1, -1 do
            local obj = pool.active[i]
            pool.active[i] = nil
            reset(obj)
            obj:Hide()
            obj:ClearAllPoints()
            pool.free[#pool.free + 1] = obj
        end
    end
    return pool
end
