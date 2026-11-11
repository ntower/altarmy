-- AltArmy TBC — what each Craftsman's Writ's order costs to buy or to craft (Economy tab).
-- Pure: reads a decoded order book (AuctionBook.Decode), the writ list (Writs.lua), the orders the game
-- told us (WritOrders: quest -> { item, count }) and a CraftPlan context. The view's sort keys and saved
-- options live in WaylaidCosts (WRITS_SORT_KEYS, EnsureOptions), which keeps the Economy tab's state.

if not AltArmy then return end

AltArmy.WritCosts = AltArmy.WritCosts or {}
local WC = AltArmy.WritCosts

local TIER_ORDER = { Journeyman = 1, Expert = 2, Artisan = 3 }

local function P()
    return AltArmy.CraftPlan
end

--- One candidate item of a writ priced both ways: bought on the auction house and crafted.
local function price(item, count, book, ctx)
    local out = { item = item }
    local cost, short, approx = P().AhCost(book[item], count)
    if cost then
        out.buy, out.buyShort, out.buyApprox = cost, short, approx
    end
    local plan = P().Craft(item, count, ctx)
    if plan then
        plan = P().Share(plan, ctx)
        out.plan, out.craft, out.craftShort, out.craftApprox = plan, plan.cost, plan.short, plan.approx
        out.who = plan.who
    end
    if out.craft and (not out.buy or out.craft < out.buy) then
        out.best, out.bestCost = "craft", out.craft
    elseif out.buy then
        out.best, out.bestCost = "buy", out.buy
    end
    return out
end

--- One writ's row (BuildRows makes one per writ): what the writ itself costs on the auction house
--- (`writPrice`, its cheapest listing), its order (`item`, `count`; `assumed` until the game told us the
--- order), what buying `count` units costs on the auction house (`buy`, `buyShort`, `buyApprox`) and what
--- crafting them costs (`craft`, the `plan`, its `steps`, `who` crafts; `canCraft`), the better of the two
--- (`best`, `bestCost`), `perRep`: copper per point of reputation, the writ bought and its order fulfilled
--- the cheaper way ((bestCost + writPrice) / rep, rounded; nil without either), and `held`: how many of the
--- writ the characters hold (`ctx.heldBy`). A writ naming several items is priced as whichever comes
--- cheapest.
function WC.BuildRow(writ, book, orders, ctx)
    local order = orders and orders[writ.quest]
    local candidates = writ.items
    if order and order.item then candidates = { order.item } end
    local count = order and order.count or writ.count
    local chosen
    for _, item in ipairs(candidates) do
        local priced = price(item, count, book, ctx)
        if not chosen or (priced.bestCost and (not chosen.bestCost or priced.bestCost < chosen.bestCost)) then
            chosen = priced
        end
    end
    local row = {
        id = writ.id, quest = writ.quest, name = writ.name, short = writ.short, tier = writ.tier,
        rep = writ.rep, count = count, assumed = not (order and order.count),
        writPrice = book[writ.id] and book[writ.id][1] and book[writ.id][1].price or nil,
        held = ctx.heldBy and ctx.heldBy(writ.id) or 0,
    }
    for k, v in pairs(chosen) do row[k] = v end
    row.canCraft = row.plan ~= nil
    if row.bestCost and row.writPrice and (row.rep or 0) > 0 then
        row.perRep = math.floor((row.bestCost + row.writPrice) / row.rep + 0.5)
    end
    if row.plan then row.steps = P().Steps(row.plan) end
    return row
end

--- One row per writ of `writs.LIST` (WC.BuildRow each).
function WC.BuildRows(book, writs, orders, ctx)
    local rows = {}
    for _, writ in ipairs(writs.LIST) do
        rows[#rows + 1] = WC.BuildRow(writ, book, orders, ctx)
    end
    return rows
end

--- The rows the filters keep: `opts.hideUncraftable` drops those nobody can craft, `opts.hideUnavailable`
--- those whose writ isn't listed or whose order can't be fulfilled either way.
function WC.Filter(rows, opts)
    opts = opts or {}
    if not (opts.hideUncraftable or opts.hideUnavailable) then return rows end
    local out = {}
    for _, row in ipairs(rows) do
        local keep = true
        if opts.hideUncraftable and not row.canCraft then keep = false end
        if opts.hideUnavailable and (row.writPrice == nil or (row.buy == nil and row.craft == nil)) then
            keep = false
        end
        if keep then out[#out + 1] = row end
    end
    return out
end

local function tierRank(row)
    return TIER_ORDER[row.tier] or 99
end

--- table.sort order for rows by `key` (one of WaylaidCosts.WRITS_SORT_KEYS, or "best": the cheaper way to
--- fulfil it; "writ" goes by tier then name). Rows without the money (or crafter) being sorted stay last in
--- both directions; ties fall back to tier then name.
function WC.Compare(a, b, key, ascending)
    local function ordered(x, y)
        if x == y then return nil end
        if ascending then return x < y end
        return x > y
    end
    local r
    if key == "buy" or key == "craft" or key == "best" or key == "writPrice" or key == "perRep" then
        local x, y = a[key], b[key]
        if key == "best" then x, y = a.bestCost, b.bestCost end
        if x == nil and y ~= nil then return false end
        if y == nil and x ~= nil then return true end
        if x ~= nil then r = ordered(x, y) end
    elseif key == "who" then
        if a.who == nil and b.who ~= nil then return false end
        if b.who == nil and a.who ~= nil then return true end
        if a.who ~= nil then r = ordered(a.who, b.who) end
    elseif key == "rep" then
        r = ordered(a.rep or 0, b.rep or 0)
    else -- writ: tier, then name
        r = ordered(tierRank(a), tierRank(b))
        if r == nil then r = ordered(a.short or "", b.short or "") end
    end
    if r ~= nil then return r end
    r = ordered(tierRank(a), tierRank(b))
    if r ~= nil then return r end
    return (a.short or "") < (b.short or "")
end

--- Auctionator shopping-list terms for a row: the writ itself, the item its order wants (at the order's
--- count), then, when a character can craft it, every reagent the craft plan buys (from a vendor or the
--- auction house, each at its quantity), each item once. `items` names them (Writs.ITEMS).
function WC.SearchTerms(row, items)
    local function name(item)
        return items[item] and items[item].name or tostring(item)
    end
    local terms, seen = {}, {}
    local function add(searchString, quantity)
        if seen[searchString] then return end
        seen[searchString] = true
        terms[#terms + 1] = { searchString = searchString, quantity = quantity, isExact = true }
    end
    add(row.name, 1)
    add(name(row.item), row.count)
    for _, step in ipairs(row.canCraft and row.steps or {}) do
        if step.kind == "ah" or step.kind == "vendor" then
            add(name(step.item), step.qty)
        end
    end
    return terms
end
