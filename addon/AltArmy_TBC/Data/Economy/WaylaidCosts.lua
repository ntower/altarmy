-- AltArmy TBC — what each Waylaid Crate costs to buy and fill, from the auction house or by crafting, per
-- point of the Merchant's Favor it gives (Economy tab). Pure: reads a decoded order book (AuctionBook.Decode),
-- the crate list (WaylaidCrates.lua) and a CraftPlan context (CraftContext.Build).
-- luacheck: globals AltArmyTBC_Options

if not AltArmy then return end

AltArmy.WaylaidCosts = AltArmy.WaylaidCosts or {}
local W = AltArmy.WaylaidCosts

W.SORT_KEYS = { "crate", "favor", "price", "buy", "craft", "perFavor" }
W.VIEWS = { currency = true, waylaid = true, writs = true, supply = true }
W.WRITS_SORT_KEYS = { "writ", "rep", "writPrice", "buy", "craft", "perRep" } -- WritCosts.Compare's keys

local TIER_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

-- What turning in a filled crate (its Sealed crate) gives, by tier and kind: Merchant's Favor and copper.
-- Gathered crates are white, Crafted ones green; green gives twice white. Not in the game data: Apprentice,
-- Journeyman and Expert were measured in game (2026-10-07).
-- ASSUMED, revisit: no Artisan crate has been turned in yet. Its numbers continue the other tiers' steps
-- (+5 / +10 Favor, +2.5s / +5s a tier); check them in game and correct them here and in docs/tabs/economy.md.
W.REWARDS = {
    Apprentice = { Gathered = { favor = 5, copper = 250 }, Crafted = { favor = 10, copper = 500 } },
    Journeyman = { Gathered = { favor = 10, copper = 500 }, Crafted = { favor = 20, copper = 1000 } },
    Expert = { Gathered = { favor = 15, copper = 750 }, Crafted = { favor = 30, copper = 1500 } },
    Artisan = { Gathered = { favor = 20, copper = 1000, guess = true },
        Crafted = { favor = 40, copper = 2000, guess = true } }, -- assumed: the view shows "40?"
}

--- A crate's turn-in reward ({ favor, copper, guess }), or nil when unknown (the unread crate). `guess`: not
--- measured yet.
function W.Reward(tier, kind)
    local byKind = W.REWARDS[tier]
    return byKind and byKind[kind] or nil
end

--- The Economy tab's saved state, repaired and created on first use.
function W.EnsureOptions()
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    local o = AltArmyTBC_Options.economy
    if type(o) ~= "table" then
        o = {}
        AltArmyTBC_Options.economy = o
    end
    if not W.VIEWS[o.activeView] then
        o.activeView = "currency"
    end
    local validKey = false
    for _, k in ipairs(W.SORT_KEYS) do
        if o.waylaidSortKey == k then validKey = true end
    end
    if not validKey then
        o.waylaidSortKey = "perFavor"
    end
    if type(o.waylaidSortAscending) ~= "boolean" then
        o.waylaidSortAscending = true
    end
    local validWritKey = false
    for _, k in ipairs(W.WRITS_SORT_KEYS) do
        if o.writsSortKey == k then validWritKey = true end
    end
    if not validWritKey then
        o.writsSortKey = "perRep"
    end
    if type(o.writsSortAscending) ~= "boolean" then
        o.writsSortAscending = true
    end
    if type(o.writsOnlyCraftable) ~= "boolean" then -- Hide writs I can not fulfill via crafting
        o.writsOnlyCraftable = false
    end
    -- Hide unavailable writs / crates: on by default (keys new with that default, so an earlier saved off
    -- doesn't carry over).
    if type(o.writsOnlyAvailable) ~= "boolean" then
        o.writsOnlyAvailable = true
    end
    if type(o.waylaidOnlyAvailable) ~= "boolean" then
        o.waylaidOnlyAvailable = true
    end
    if type(o.waylaidOnlyCraftable) ~= "boolean" then -- Hide crates I can not fulfill via crafting
        o.waylaidOnlyCraftable = false
    end
    -- Item tooltips outside the Economy tab (bags, links): on unless turned off in Options -> Economy.
    if type(o.itemTooltips) ~= "boolean" then
        o.itemTooltips = true
    end
    o.writsHideUnavailable = nil
    return o
end

--- Copper to buy `n` units, cheapest first up the ladder, or nil if fewer are listed.
--- Second result: true when units came from the tail level, priced at its cheapest (an estimate).
function W.CostForUnits(levels, n)
    if n <= 0 then return 0, false end
    if type(levels) ~= "table" then return nil end
    local left, cost, approx = n, 0, false
    for _, level in ipairs(levels) do
        local take = math.min(left, level.units)
        cost = cost + take * level.price
        if level.tail and take > 0 then approx = true end
        left = left - take
        if left == 0 then return cost, approx end
    end
    return nil
end

local function unitsListed(levels)
    local units = 0
    for _, level in ipairs(levels or {}) do
        units = units + level.units
    end
    return units
end

--- Bundles that can be bought or crafted first, cheapest (by the cheaper way) first; then those short on the
--- auction house, then those not listed at all, in list order.
local function sortOptions(options)
    local order = {}
    for i, opt in ipairs(options) do
        order[opt] = i
    end
    table.sort(options, function(a, b)
        if a.bestCost and b.bestCost then
            if a.bestCost ~= b.bestCost then return a.bestCost < b.bestCost end
        elseif a.bestCost or b.bestCost then
            return a.bestCost ~= nil
        elseif (a.listed > 0) ~= (b.listed > 0) then
            return a.listed > 0
        end
        return order[a] < order[b]
    end)
end

--- One bundle priced both ways: bought in full on the auction house (`cost`, `approx`; nil when fewer units
--- are listed than it takes) and crafted the cheapest way by the realm's characters (`craft`, its `plan`,
--- `craftShort`, `craftApprox`, `who`; nil without `ctx` or when nobody can).
local function priceBundle(b, book, ctx)
    local cost, approx = W.CostForUnits(book[b.item], b.count)
    local opt = { item = b.item, name = b.name, count = b.count, cost = cost, approx = approx,
        listed = unitsListed(book[b.item]) }
    local P = AltArmy.CraftPlan
    local plan = ctx and P and P.Craft(b.item, b.count, ctx)
    if plan then
        plan = P.Share(plan, ctx)
        opt.plan, opt.craft, opt.craftShort, opt.craftApprox, opt.who = plan, plan.cost, plan.short,
            plan.approx, plan.who
    end
    if opt.craft and (not opt.cost or opt.craft < opt.cost) then
        opt.best, opt.bestCost = "craft", opt.craft
    elseif opt.cost then
        opt.best, opt.bestCost = "buy", opt.cost
    end
    return opt
end

--- One crate's row (BuildRows makes one for every crate the game has, listed or not): its cheapest price
--- in `book` (itemID -> ladder; nil when the crate isn't listed), what the turn-in gives (`favor`,
--- `goldBack`; `favorGuess` when not measured yet), and the cheapest way to fill it with any one of its
--- bundles: bought on the auction house (`buy`, `buyBundle`, `buyApprox`: only a bundle listed in full) or
--- crafted by the realm's characters (`craft`, `craftBundle`, its `plan` and `steps`, `who`, `craftShort`,
--- `craftApprox`; `canCraft`), the cheaper of the two (`best`, `bestCost`, `bundle`: the bundle it fills
--- with). `total`: the crate plus that fill less the gold the turn-in gives back; `perFavor` that per point
--- of Merchant's Favor, rounded (negative when the turn-in pays more than it cost; nil without a crate
--- price, a fill or a known reward). `options`: every bundle priced both ways for the tooltip. `crate` is
--- one of AltArmy.WaylaidCrates.LIST. `summary`: the book is a summary scan's (one level per item, its
--- cheapest price), so a fill of more than one unit is a lower bound; only the row is marked `summary` (the
--- view says so on the scan's age, not on each cost). `ctx`: a CraftPlan context (CraftContext.Build) for
--- the craft prices.
function W.BuildRow(crate, book, summary, ctx)
    local ladder = book[crate.id]
    local row = {
        id = crate.id, name = crate.name, short = crate.short, tier = crate.tier, kind = crate.kind,
        random = crate.random == true, price = ladder and ladder[1] and ladder[1].price or nil,
        listed = unitsListed(ladder), options = {}, summary = summary and true or nil,
    }
    local reward = W.Reward(crate.tier, crate.kind)
    if reward then
        row.favor, row.goldBack, row.favorGuess = reward.favor, reward.copper, reward.guess
    end
    for _, b in ipairs(crate.bundles) do
        local opt = priceBundle(b, book, ctx)
        row.options[#row.options + 1] = opt
        if opt.cost and (not row.buyBundle or opt.cost < row.buy) then
            row.buyBundle, row.buy, row.buyApprox = opt, opt.cost, opt.approx
        end
        if opt.craft and (not row.craftBundle or opt.craft < row.craft) then
            row.craftBundle, row.craft, row.craftShort, row.craftApprox = opt, opt.craft, opt.craftShort,
                opt.craftApprox
            row.plan, row.who = opt.plan, opt.who
        end
    end
    sortOptions(row.options)
    row.canCraft = row.craftBundle ~= nil
    if row.plan then row.steps = AltArmy.CraftPlan.Steps(row.plan) end
    if row.craft and (not row.buy or row.craft < row.buy) then
        row.best, row.bestCost, row.bundle = "craft", row.craft, row.craftBundle
    elseif row.buy then
        row.best, row.bestCost, row.bundle = "buy", row.buy, row.buyBundle
    end
    if row.bestCost and row.price and reward then
        row.total = row.price + row.bestCost - reward.copper
        row.perFavor = math.floor(row.total / reward.favor + 0.5)
    end
    return row
end

--- One row per crate of `crates.LIST` (W.BuildRow each).
function W.BuildRows(book, crates, summary, ctx)
    local rows = {}
    for _, crate in ipairs(crates.LIST) do
        rows[#rows + 1] = W.BuildRow(crate, book, summary, ctx)
    end
    return rows
end

--- The rows the filters keep: `opts.hideUnavailable` drops the crates not listed on the auction house and
--- those no bundle can fill either way (the unread crate, whose shipment is random, needs only to be
--- listed); `opts.hideUncraftable` those the characters can't fill by crafting.
function W.FilterRows(rows, opts)
    opts = opts or {}
    if not (opts.hideUnavailable or opts.hideUncraftable) then return rows end
    local out = {}
    for _, row in ipairs(rows) do
        local keep = true
        if opts.hideUnavailable and not (row.price and (row.bestCost or row.random)) then keep = false end
        if opts.hideUncraftable and not row.canCraft then keep = false end
        if keep then out[#out + 1] = row end
    end
    return out
end

--- Auctionator shopping-list terms for a row: the crate, then what its cheapest fill buys: the bundle at its
--- count when bought, or every reagent the craft plan buys (from a vendor or the auction house, each at its
--- quantity) when crafted. `items` names a craft's reagents (WaylaidCrates.ITEMS). Each item once.
function W.SearchTerms(row, items)
    local terms, seen = {}, {}
    local function add(searchString, quantity)
        if seen[searchString] then return end
        seen[searchString] = true
        terms[#terms + 1] = { searchString = searchString, quantity = quantity, isExact = true }
    end
    add(row.name, 1)
    if row.best == "craft" then
        for _, step in ipairs(row.steps or {}) do
            if step.kind == "ah" or step.kind == "vendor" then
                local entry = items and items[step.item]
                add(entry and entry.name or tostring(step.item), step.qty)
            end
        end
    elseif row.bundle then
        add(row.bundle.name, row.bundle.count)
    end
    return terms
end

local function tierRank(row)
    return TIER_ORDER[row.tier] or 99
end

--- table.sort order for rows by `key` (one of SORT_KEYS: "crate" goes by tier then name). Rows without the
--- number being sorted stay last in both directions; ties fall back to tier then name.
function W.Compare(a, b, key, ascending)
    local function ordered(x, y)
        if x == y then return nil end
        if ascending then return x < y end
        return x > y
    end
    local r
    if key == "crate" then
        r = ordered(tierRank(a), tierRank(b))
        if r == nil then r = ordered(a.name or "", b.name or "") end
    else -- favor, price, buy, craft, perFavor
        local x, y = a[key], b[key]
        if x == nil and y ~= nil then return false end
        if y == nil and x ~= nil then return true end
        if x ~= nil then r = ordered(x, y) end
    end
    if r ~= nil then return r end
    r = ordered(tierRank(a), tierRank(b))
    if r ~= nil then return r end
    return (a.name or "") < (b.name or "")
end

--- How much to trust a scan's prices by its age: "fresh" under 15 min, "stale" up to 30, then "old".
function W.AgeLevel(scanTime, now)
    local age = (now or 0) - (scanTime or 0)
    if age < 15 * 60 then
        return "fresh"
    elseif age <= 30 * 60 then
        return "stale"
    end
    return "old"
end

-- Prices older than this get a warning in the tooltips (Tabs and UI/EconomyTooltip.lua).
W.OLD_DATA_SECONDS = 60 * 60

--- True when a scan taken at `scanTime` is over an hour old at `now` (server time).
function W.IsOldData(scanTime, now)
    return (now or 0) - (scanTime or 0) > W.OLD_DATA_SECONDS
end

--- "Scanned 2 hr ago", from the scan's time and now (server time), in whole minutes rounded to the nearest
--- ("Scanned just now" under a minute); `fmt` formats seconds. `summary` adds " (summary)".
function W.AgeText(scanTime, now, fmt, summary)
    local age = (now or 0) - (scanTime or 0)
    local suffix = summary and " (summary)" or ""
    if age < 60 then
        return "Scanned just now" .. suffix
    end
    -- Whole minutes, rounded to the nearest: the client's SecondsToTime would show seconds too.
    return "Scanned " .. fmt(math.floor(age / 60 + 0.5) * 60) .. " ago" .. suffix
end

