-- AltArmy TBC — the auction house's order book, as the website reads it.
-- Pure (no events, no client calls): AuctionScan.lua feeds it every listing of a full scan.
--
-- AltArmyTBC_AuctionBook = { version = 1, lastRequest = <t>, scans = { <scan>, ... } } oldest first, its own
-- SavedVariable so the website's uploader need not parse AltArmyTBC_Data. A scan:
--   { t, realm, faction, complete, listings, bidOnly, source, items }
--   t         GetServerTime() when the listings arrived
--   realm     GetRealmName(); faction: UnitFactionGroup("player") — whose auction house it is
--   complete  every listing was read (only complete scans are stored)
--   listings  listings read; bidOnly: those without a buyout (counted, never priced)
--   source    "own" (Alt Army asked for the listings) or "heard" (another addon did)
--   items     "<item>;<item>;..." by item id, each "<itemID>:<level>,<level>,..." cheapest first, a level
--             being "<unit price>*<units>*<listings>". Unit prices are a listing's buyout over its count,
--             rounded up. Past MAX_LEVELS levels the rest is one tail level, "~<its cheapest unit
--             price>*<units>*<listings>".
-- Items are keyed by item id alone: gear with a random suffix shares its base item's ladder.
--
-- `summaries` (beside `scans`) holds summary scans: the client's browse results, one row per item with its
-- cheapest unit price and units listed. One per realm and faction, newest only, pruned by MAX_AGE:
--   { t, realm, faction, summary = true, listings, items }   `listings`: items read; `items` as above, one
--   level per item ("<cheapest unit price>*<units>*1"). Kept apart so the website, which reads `scans`
--   only, never sees one and a summary never displaces a full scan.
-- The site's book.py parses this; spec/fixtures/auction_book_v1.lua is the golden file both test against.
-- luacheck: globals AltArmyTBC_AuctionBook

if not AltArmy then return end

AltArmy.AuctionBook = AltArmy.AuctionBook or {}
local B = AltArmy.AuctionBook

-- Whether two realms are one (Forever's coalesced realms are: RealmFilter.sameRealm).
local function sameRealm(a, b)
    local RF = AltArmy.RealmFilter
    if RF and RF.sameRealm then return RF.sameRealm(a, b) end
    return (a or "") == (b or "")
end

B.VERSION = 1
B.MAX_LEVELS = 12 -- price levels kept per item, before the tail
B.MAX_SCANS = 3 -- scans kept per realm and faction
B.MAX_AGE = 7 * 24 * 60 * 60 -- seconds
B.COOLDOWN = 15 * 60 -- seconds between full scans the client allows an account

--- An empty tally of one scan's listings.
function B.NewTally()
    return { items = {}, listings = 0, bidOnly = 0 }
end

--- Add one listing: `count` units of `itemID` for `buyout` copper in all (0: no buyout).
function B.Add(tally, itemID, count, buyout)
    if type(itemID) ~= "number" or itemID <= 0 then return end
    if type(count) ~= "number" or count <= 0 then return end
    if type(buyout) ~= "number" or buyout < 0 then return end
    tally.listings = tally.listings + 1
    if buyout == 0 then
        tally.bidOnly = tally.bidOnly + 1
        return
    end
    local price = math.ceil(buyout / count)
    local levels = tally.items[itemID]
    if not levels then
        levels = {}
        tally.items[itemID] = levels
    end
    local level = levels[price]
    if not level then
        level = { units = 0, listings = 0 }
        levels[price] = level
    end
    level.units = level.units + count
    level.listings = level.listings + 1
end

--- Add one summary row: `itemID` listed from `minPrice` copper a unit, `quantity` units in all. Rows of one
--- item id merge at the cheapest price with their units summed.
function B.AddSummary(tally, itemID, minPrice, quantity)
    if type(itemID) ~= "number" or itemID <= 0 then return end
    if type(minPrice) ~= "number" or minPrice <= 0 then return end
    if type(quantity) ~= "number" or quantity <= 0 then return end
    local levels = tally.items[itemID]
    local price, level
    if levels then
        price, level = next(levels)
        levels[price] = nil
        level.units = level.units + quantity
        price = math.min(price, minPrice)
    else
        tally.listings = tally.listings + 1
        levels, price, level = {}, minPrice, { units = quantity, listings = 1 }
        tally.items[itemID] = levels
    end
    levels[price] = level
end

local function encodeItem(itemID, levels)
    local prices = {}
    for price in pairs(levels) do
        prices[#prices + 1] = price
    end
    table.sort(prices)
    local parts = {}
    for i = 1, math.min(#prices, B.MAX_LEVELS) do
        local level = levels[prices[i]]
        parts[#parts + 1] = prices[i] .. "*" .. level.units .. "*" .. level.listings
    end
    if #prices > B.MAX_LEVELS then
        local units, listings = 0, 0
        for i = B.MAX_LEVELS + 1, #prices do
            units = units + levels[prices[i]].units
            listings = listings + levels[prices[i]].listings
        end
        parts[#parts + 1] = "~" .. prices[B.MAX_LEVELS + 1] .. "*" .. units .. "*" .. listings
    end
    return itemID .. ":" .. table.concat(parts, ",")
end

--- The tally's `items` text (see the header).
function B.Encode(tally)
    local ids = {}
    for itemID in pairs(tally.items) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids)
    local out = {}
    for i = 1, #ids do
        out[i] = encodeItem(ids[i], tally.items[ids[i]])
    end
    return table.concat(out, ";")
end

--- Encode's text read back: itemID -> its levels cheapest first, each { price, units, listings, tail }
--- (`tail`: the folded levels past MAX_LEVELS, at their cheapest price). Unreadable pieces are skipped.
function B.Decode(itemsText)
    local book = {}
    if type(itemsText) ~= "string" then return book end
    for item in itemsText:gmatch("[^;]+") do
        local id, ladder = item:match("^(%d+):(.*)$")
        if id then
            local levels = {}
            for level in ladder:gmatch("[^,]+") do
                local tail, price, units, listings = level:match("^(~?)(%d+)%*(%d+)%*(%d+)$")
                if price then
                    levels[#levels + 1] = { price = tonumber(price), units = tonumber(units),
                        listings = tonumber(listings), tail = tail == "~" }
                end
            end
            if #levels > 0 then
                book[tonumber(id)] = levels
            end
        end
    end
    return book
end

--- The newest complete scan of `realm`'s `faction` auction house, or nil.
function B.Latest(realm, faction)
    local log = AltArmyTBC_AuctionBook
    if type(log) ~= "table" or type(log.scans) ~= "table" then return nil end
    for i = #log.scans, 1, -1 do
        local s = log.scans[i]
        if type(s) == "table" and sameRealm(s.realm, realm) and s.faction == faction and s.complete then
            return s
        end
    end
    return nil
end

--- The newest summary scan of `realm`'s `faction` auction house, or nil.
function B.LatestSummary(realm, faction)
    local log = AltArmyTBC_AuctionBook
    if type(log) ~= "table" or type(log.summaries) ~= "table" then return nil end
    for i = #log.summaries, 1, -1 do
        local s = log.summaries[i]
        if type(s) == "table" and sameRealm(s.realm, realm) and s.faction == faction then
            return s
        end
    end
    return nil
end

--- The newer of the full scan (Latest) and the summary (LatestSummary), or nil.
function B.Newest(realm, faction)
    local full, summary = B.Latest(realm, faction), B.LatestSummary(realm, faction)
    if full and summary then
        return (summary.t or 0) > (full.t or 0) and summary or full
    end
    return full or summary
end

--- The log, created on first use.
function B.GetLog()
    local log = AltArmyTBC_AuctionBook
    if type(log) ~= "table" or type(log.scans) ~= "table" then
        log = { version = B.VERSION, scans = {} }
        AltArmyTBC_AuctionBook = log
    end
    return log
end

--- Append `scan`, keeping each realm and faction's newest MAX_SCANS and nothing older than MAX_AGE.
function B.Store(scan, now)
    local log = B.GetLog()
    local scans = log.scans
    scans[#scans + 1] = scan
    local kept = {} -- realm\faction -> scans kept, counted from the newest
    local keep = {}
    for i = #scans, 1, -1 do
        local s = scans[i]
        local key = tostring(s.realm) .. "\\" .. tostring(s.faction)
        local count = (kept[key] or 0) + 1
        if count <= B.MAX_SCANS and now - (s.t or 0) <= B.MAX_AGE then
            kept[key] = count
            table.insert(keep, 1, s)
        end
    end
    log.scans = keep
end

--- Keep `scan` as its realm and faction's summary (replacing the last one), dropping any past MAX_AGE.
function B.StoreSummary(scan, now)
    local log = B.GetLog()
    local keep = {}
    for _, s in ipairs(type(log.summaries) == "table" and log.summaries or {}) do
        if type(s) == "table" and not (sameRealm(s.realm, scan.realm) and s.faction == scan.faction)
            and now - (s.t or 0) <= B.MAX_AGE then
            keep[#keep + 1] = s
        end
    end
    keep[#keep + 1] = scan
    log.summaries = keep
end

--- Forget every stored scan and summary (all realms and factions); returns how many there were. The client's cooldown
--- (lastRequest) is kept: it is the client's state, not ours.
function B.Clear()
    local log = B.GetLog()
    local count = #log.scans + (type(log.summaries) == "table" and #log.summaries or 0)
    log.scans = {}
    log.summaries = nil
    return count
end

--- Remember that someone asked the client for every listing at `now`: its cooldown starts over.
function B.NoteRequest(now)
    B.GetLog().lastRequest = now
end

--- Seconds until the client allows another full scan; 0 if it does now.
function B.CooldownLeft(now)
    local last = B.GetLog().lastRequest
    if type(last) ~= "number" or last > now then
        return 0
    end
    return math.max(0, B.COOLDOWN - (now - last))
end
