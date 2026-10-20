-- AltArmy TBC — Pure helper: flattens Search result sections into WowScrollBoxList elements.

if not AltArmy then return end

AltArmy.SearchListModel = AltArmy.SearchListModel or {}

local Model = AltArmy.SearchListModel

--- Consecutive item rows with the same key share one Total-column overlay.
local function itemGroupKey(entry)
    return (entry.itemID or 0) .. "\t" .. (entry.itemName or "")
end

--- Build the element list for the ScrollBox data provider.
--- sections: ordered { id, list, grouped (item sections), gapBefore (px above the header) }.
--- metrics: { headerHeight, headerRowGap, rowHeight, omitFirstHeader }.
--- Each non-empty section yields a "header" spacer (gapBefore + headerHeight + headerRowGap; the
--- visible header is a sticky overlay drawn over it) then one "row" per entry. Offsets match
--- SearchStickyHeaders.ComputeSectionLayout. Grouped rows share a `group` table
--- { total, firstEntry, top, bottom } for consecutive entries with the same item; `top`/`bottom`
--- are the group's list offsets (as is each element's `top`), so its Total overlay can span rows
--- that have no frame.
--- omitFirstHeader: skip the first section's spacer (caller starts the list below that header).
--- @return table elements { kind, sectionId, extent, top, entry?, group?, gapBefore? }
function Model.Build(sections, metrics)
    local elements = {}
    local skipHeader = metrics.omitFirstHeader and true or false
    local headerBlock = (metrics.headerHeight or 0) + (metrics.headerRowGap or 0)
    local rowHeight = metrics.rowHeight or 0
    local offset = 0
    for _, section in ipairs(sections or {}) do
        local list = section.list or {}
        if #list > 0 then
            local gapBefore = tonumber(section.gapBefore) or 0
            if skipHeader then
                skipHeader = false
            else
                elements[#elements + 1] = {
                    kind = "header",
                    sectionId = section.id,
                    gapBefore = gapBefore,
                    extent = gapBefore + headerBlock,
                    top = offset,
                }
                offset = offset + gapBefore + headerBlock
            end
            local group, prevKey = nil, nil
            for i = 1, #list do
                local entry = list[i]
                local element = {
                    kind = "row", sectionId = section.id, entry = entry, extent = rowHeight, top = offset,
                }
                offset = offset + rowHeight
                if section.grouped then
                    local key = itemGroupKey(entry)
                    if not group or key ~= prevKey then
                        group = { total = 0, firstEntry = entry, top = element.top }
                        prevKey = key
                    end
                    group.total = group.total + (entry.count or 1)
                    group.bottom = offset
                    element.group = group
                end
                elements[#elements + 1] = element
            end
        end
    end
    return elements
end

--- Where a group's Total content (`size` tall) sits, as a center offset, so it stays in view:
--- centered on the group's span [spanTop, spanBottom] while that fits the view, else slid toward
--- the view's middle and pinned `size / 2` inside the view's edge [viewTop, viewBottom], but never
--- out of its own span (it leaves the view with the group's last row). Offsets grow downward.
function Model.PinnedCenter(spanTop, spanBottom, viewTop, viewBottom, size)
    local half = size / 2
    local center = (spanTop + spanBottom) / 2
    center = math.min(math.max(center, viewTop + half), viewBottom - half)
    return math.min(math.max(center, spanTop + half), spanBottom - half)
end
