-- AltArmy TBC — which table columns take the room a wider main window adds. Pure: no frames, no WoW API.
-- Every table is laid out for the stock 670 px window; when the window is wider its list viewport is
-- too, and the named flex columns share what is left over by their shares. Nothing ever shrinks below
-- its stock width: a viewport narrower than the stock total (a settings panel open) keeps the stock
-- widths and scrolls sideways, as before.

if not AltArmy then return end

AltArmy.ColumnFit = AltArmy.ColumnFit or {}
local CF = AltArmy.ColumnFit

--- The fitted widths for a viewport `width` wide: a new table, the fixed columns at their stock width,
--- each flex column at its stock width plus floor(share x extra), extra being what the viewport has
--- beyond the stock total (never under 0). `caps` (optional, key -> most it may be) holds a column
--- there; the unused part is dropped, not handed on. Flex keys the widths lack are ignored.
--- @param widths table key -> stock width
--- @param flex table key -> share of the extra (the shares of one table sum to 1)
--- @param width number|nil the viewport's width; nil or 0 (a hidden frame) means the stock total
--- @param caps table|nil key -> cap
function CF.Fit(widths, flex, width, caps)
    local total = 0
    for _, w in pairs(widths) do total = total + w end
    local extra = 0
    if type(width) == "number" and width > 0 then
        extra = math.max(0, width - total)
    end
    local out = {}
    for key, w in pairs(widths) do
        local share = flex and flex[key]
        if share and extra > 0 then
            w = w + math.floor(share * extra)
            local cap = caps and caps[key]
            if cap and w > cap then w = cap end
        end
        out[key] = w
    end
    return out
end

--- The sum of `widths` over `order` (a column without a width counts as nothing).
function CF.Total(order, widths)
    local total = 0
    for _, key in ipairs(order) do
        total = total + (widths[key] or 0)
    end
    return total
end
