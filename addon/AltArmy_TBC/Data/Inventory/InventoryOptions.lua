-- AltArmy TBC — the Inventory tab's saved state (AltArmyTBC_Options.inventory): each view's layout,
-- the mail sort and the Mail view's "Combine stacks" (mailCombineStacks). The chosen
-- character and sub-view are per opening (Tabs/TabInventory.lua), not saved.
-- Pure: no WoW API, so the tab's choices are unit-tested.
-- luacheck: globals AltArmyTBC_Options

if not AltArmy then return end

AltArmy.InventoryOptions = AltArmy.InventoryOptions or {}
local IO = AltArmy.InventoryOptions

IO.VIEWS = { bags = true, bank = true, mail = true }
IO.DEFAULT_VIEW = "bags"

-- Bags and Bank: one block per bag (the classic bag windows) or one grid (retail's combined bags).
-- Mail: inbox rows (one per message) or the attachments as item slots.
IO.BAG_LAYOUTS = { blocks = true, combined = true }
IO.MAIL_LAYOUTS = { rows = true, grid = true }
IO.LAYOUT_ORDER = {
    bags = { "blocks", "combined" },
    bank = { "blocks", "combined" },
    mail = { "rows", "grid" },
}
IO.LAYOUT_LABELS = {
    blocks = "Per bag",
    combined = "Combined bags",
    rows = "Inbox view",
    grid = "Combined items",
}
-- The Mail view's inbox rows sort by one of these; latest expiry first is the stock inbox's order.
IO.MAIL_SORT_KEYS = { subject = true, sender = true, money = true, expires = true }
IO.DEFAULT_MAIL_SORT = { key = "expires", ascending = false }

local LAYOUT_KEYS = { bags = "bagLayout", bank = "bankLayout", mail = "mailLayout" }
local LAYOUT_DEFAULTS = { bags = "blocks", bank = "blocks", mail = "rows" }

--- The option key holding a view's layout ("bagLayout", "bankLayout", "mailLayout"), or nil.
function IO.LayoutKey(view)
    return LAYOUT_KEYS[view]
end

local function validLayouts(view)
    if view == "mail" then return IO.MAIL_LAYOUTS end
    if IO.VIEWS[view] then return IO.BAG_LAYOUTS end
    return nil
end

--- The Inventory tab's saved state, repaired and created on first use.
function IO.EnsureOptions()
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    local o = AltArmyTBC_Options.inventory
    if type(o) ~= "table" then
        o = {}
        AltArmyTBC_Options.inventory = o
    end
    for view, key in pairs(LAYOUT_KEYS) do
        if not validLayouts(view)[o[key]] then
            o[key] = LAYOUT_DEFAULTS[view]
        end
    end
    if not IO.MAIL_SORT_KEYS[o.mailSortKey] then
        o.mailSortKey = IO.DEFAULT_MAIL_SORT.key
        o.mailSortAscending = IO.DEFAULT_MAIL_SORT.ascending
    end
    if type(o.mailSortAscending) ~= "boolean" then
        o.mailSortAscending = IO.DEFAULT_MAIL_SORT.ascending
    end
    if type(o.mailCombineStacks) ~= "boolean" then
        o.mailCombineStacks = false
    end
    return o
end

--- The layout a view uses; the view's default when the options are missing.
function IO.GetLayout(o, view)
    local key = LAYOUT_KEYS[view]
    if not key then return nil end
    local layout = o and o[key]
    if validLayouts(view)[layout] then
        return layout
    end
    return LAYOUT_DEFAULTS[view]
end

--- Set a view's layout; false (and no change) for an unknown view or layout.
function IO.SetLayout(o, view, layout)
    local key = LAYOUT_KEYS[view]
    if not o or not key or not validLayouts(view)[layout] then
        return false
    end
    o[key] = layout
    return true
end

--- A click on a mail column header: the same column flips the direction, another column sorts by it
--- (text columns A-Z first, money and expiry largest first, as the stock inbox).
function IO.ClickMailSort(o, key)
    if not o or not IO.MAIL_SORT_KEYS[key] then return false end
    if o.mailSortKey == key then
        o.mailSortAscending = not o.mailSortAscending
    else
        o.mailSortKey = key
        o.mailSortAscending = (key == "subject" or key == "sender")
    end
    return true
end

--- Dropdown entries for a view's layouts: { { id, label }, ... } in display order.
function IO.LayoutEntries(view)
    local out = {}
    for _, id in ipairs(IO.LAYOUT_ORDER[view] or {}) do
        out[#out + 1] = { id = id, label = IO.LAYOUT_LABELS[id] }
    end
    return out
end
