-- AltArmy TBC — which of a row's Auctionator searches to make first (Economy tab): the one whose cheap listings
-- you would lose the most on if someone else bought them first. Pure: reads a decoded order book
-- (AuctionBook.Decode: itemID -> its levels cheapest first, each { price, units, listings, tail }).

if not AltArmy then return end

AltArmy.SnipeOrder = AltArmy.SnipeOrder or {}
local S = AltArmy.SnipeOrder

-- A price level at least this many percent dearer than the one before it ends the cheap block. A whole percent,
-- so the test stays in whole numbers (100 * 1.10 is 110.00000000000001 in floating point).
S.JUMP_PERCENT = 10
-- A cheap block of more than this many times the quantity wanted is too deep for anyone to buy out first.
S.THIN = 5

--- Copper for `qty` units from `levels`, starting at level `from`, cheapest first; nil if fewer are listed.
local function costFrom(levels, from, qty)
    local left, cost = qty, 0
    for i = from, #levels do
        local take = math.min(left, levels[i].units)
        cost = cost + take * levels[i].price
        left = left - take
        if left == 0 then return cost end
    end
    return nil
end

--- What a snipe of an item is worth: how much more `qty` units cost once its cheap block is bought out. The
--- cheap block is the levels before the first price jump (a level JUMP_PERCENT dearer than the one before it),
--- counted only when it's thin (at most THIN times `qty` units). 0 on a smooth ladder, a deep block, one price
--- level (a summary scan) or a ladder that can't fill `qty` at all; math.huge when only the block can.
function S.Value(levels, qty)
    if type(levels) ~= "table" or type(qty) ~= "number" or qty <= 0 then return 0 end
    local units, block = 0, nil
    for i = 1, #levels - 1 do
        units = units + levels[i].units
        if levels[i + 1].price * 100 >= levels[i].price * (100 + S.JUMP_PERCENT) then
            block = i
            break
        end
    end
    if not block or units > S.THIN * qty then return 0 end
    local now = costFrom(levels, 1, qty)
    if not now then return 0 end
    local without = costFrom(levels, block + 1, qty)
    if not without then return math.huge end
    return without - now
end

--- `terms` (Auctionator shopping-list terms, each with the `item` it searches and its `quantity`) with the most
--- valuable snipe first (S.Value in `book`); terms of equal value (no snipe: 0) keep their order. The `item`
--- field is dropped: Auctionator takes { searchString, quantity, isExact }. No book: the order as given.
function S.Order(terms, book)
    local scored = {}
    for i, term in ipairs(terms) do
        local value = 0
        if book and term.item then value = S.Value(book[term.item], term.quantity or 1) end
        scored[i] = { term = term, value = value, index = i }
    end
    table.sort(scored, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.index < b.index
    end)
    local out = {}
    for i, s in ipairs(scored) do
        local t = s.term
        out[i] = { searchString = t.searchString, quantity = t.quantity, isExact = t.isExact }
    end
    return out
end
