-- AltArmy TBC — A horizontal scroll bar for a list wider than its viewport (the Cooldowns tab's Crafting and
-- Dungeons lists, narrowed by the tab's settings panel). It scrolls the list's own ScrollFrame sideways rather
-- than nesting it in a second one (the client gives a ScrollFrame nested in another one no range at times; see
-- Theme.CreateVirtualScrollBinding) and hands the offset to the caller, which moves what scrolls with the rows
-- outside that frame (the column headers). The bar sits in `slot` (BAR_HEIGHT tall, anchored by the caller
-- under the list); `onBarShown(shown, height)` lets the caller lift the list's bottom over it. Nothing should be
-- anchored to the slot: a frame resting on a 0 px tall one gets no rect, and is never drawn.

if not AltArmy then return end

local Theme = AltArmy.Theme

AltArmy.HorizontalListScroll = AltArmy.HorizontalListScroll or {}
local H = AltArmy.HorizontalListScroll

H.BAR_HEIGHT = 20 -- the Summary, Gear and Reputation grids' horizontal bar
local BAR_INSET = 4

--- @param opts table scrollFrame (the list's ScrollFrame), barParent (drawn above the list),
---   getContentWidth() -> the list's full width, onScroll(offset), isShown(),
---   onBarShown(shown, height) when the bar appears or goes (height: the room it needs under the list)
--- @return table { slot, bar, offset, Update() }: Update() after the content's or the viewport's width moved
---   (the viewport's own size changes call it)
function H.Create(opts)
    local api = { offset = 0 }
    local scrollFrame = opts.scrollFrame

    local slot = CreateFrame("Frame", nil, opts.barParent)
    slot:SetHeight(H.BAR_HEIGHT)
    api.slot = slot
    local barShown -- nil until the first Update, so the caller hears the first state

    local function apply(value)
        local v = math.floor((value or 0) + 0.5)
        local moved = v ~= api.offset
        api.offset = v
        scrollFrame:SetHorizontalScroll(v)
        if moved and opts.onScroll then
            opts.onScroll(v)
        end
    end

    local barApi = Theme.CreateHorizontalScrollBar(opts.barParent, {
        thickness = H.BAR_HEIGHT - BAR_INSET * 2,
        onScroll = apply,
        isShown = opts.isShown,
    })
    local bar = barApi.bar
    bar:SetPoint("LEFT", slot, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
    bar:SetFrameLevel((opts.barParent:GetFrameLevel() or 0) + 30)
    bar:Hide()
    api.bar = bar

    function api.Update()
        local view = scrollFrame:GetWidth() or 0
        if view <= 0 then return end
        local content = opts.getContentWidth and opts.getContentWidth() or 0
        local maxScroll = math.max(0, math.floor(content - view + 0.5))
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        barApi:SetRange(0, maxScroll, view)
        local shown = maxScroll > 0
        bar:SetShown(shown)
        barApi:Restore(maxScroll) -- the kept offset, clamped to the new range
        if shown ~= barShown then
            barShown = shown
            if opts.onBarShown then
                opts.onBarShown(shown, H.BAR_HEIGHT)
            end
        end
    end

    scrollFrame:HookScript("OnSizeChanged", function()
        api.Update()
    end)

    return api
end
