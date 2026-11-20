-- AltArmy TBC — auction house listings probe.
-- Manual diagnostic only: /altarmy debug ahprobe, at an open auction house. Asks the client for every
-- listing once (C_AuctionHouse.ReplicateItems, which the client allows once per 15 minutes per account)
-- and records what came back: how many listings, which fields they carry, and the first rows as a sample.
-- The result goes to AltArmyTBC_Options.debug.auctionProbe (read it from the SavedVariables .lua file
-- after /reload); chat only gets a one-line status. Answers whether the client (WoW: Forever) serves
-- full listings to addons — see docs/WOW_FOREVER_COMPAT.md.
-- luacheck: globals GetServerTime

if not AltArmy then return end

AltArmy.AuctionProbe = AltArmy.AuctionProbe or {}
local P = AltArmy.AuctionProbe

P.VERSION = 1
P.SAMPLE = 25 -- rows kept as they came
P.MAX_READ = 5000 -- rows read for the field counts: one frame's work
P.TIMEOUT = 60 -- seconds to wait for the listings

P.REQUIRED = {
    "ReplicateItems",
    "GetNumReplicateItems",
    "GetReplicateItemInfo",
    "GetReplicateItemLink",
    "GetReplicateItemTimeLeft",
}

local waiting = false
local run = 0 -- which Start the timer belongs to
local frame

local function now()
    if GetServerTime then return GetServerTime() end
    return time and time() or 0
end

local function notify(msg)
    local D = AltArmy.Debug
    if D and D.NotifyChat then
        D.NotifyChat("|cff00ccff[Alt Army:AHProbe]|r " .. msg)
    end
end

local function save(result)
    result.version = P.VERSION
    result.t = now()
    result.interface = GetBuildInfo and select(4, GetBuildInfo()) or nil
    result.realm = AltArmy.CurrentRealm and AltArmy.CurrentRealm() or GetRealmName and GetRealmName() or nil
    result.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local D = AltArmy.Debug
    if D and D.SaveAuctionProbe then
        D.SaveAuctionProbe(result)
    end
    return result
end

local function finish(result)
    waiting = false
    if frame then
        frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        frame:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    end
    return save(result)
end

--- The names in P.REQUIRED the client lacks.
function P.Missing()
    local api = C_AuctionHouse
    local missing = {}
    for _, name in ipairs(P.REQUIRED) do
        if type(api) ~= "table" or type(api[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    return missing
end

function P.IsWaiting()
    return waiting
end

--- What the client has after REPLICATE_ITEM_LIST_UPDATE: the listing count, how many of the rows read
--- carry each field, and the first rows.
function P.Read()
    local listings = C_AuctionHouse.GetNumReplicateItems() or 0
    local fields = { name = 0, count = 0, buyout = 0, minBid = 0, owner = 0, itemID = 0, hasAllInfo = 0,
        link = 0, timeLeft = 0 }
    local sample = {}
    local read = math.min(listings, P.MAX_READ)
    for i = 0, read - 1 do
        local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo =
            C_AuctionHouse.GetReplicateItemInfo(i)
        local link = C_AuctionHouse.GetReplicateItemLink(i)
        local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft(i)
        local got = { name = name, count = count, buyout = buyout, minBid = minBid, owner = owner,
            itemID = itemID, hasAllInfo = hasAllInfo or nil, link = link, timeLeft = timeLeft }
        for field in pairs(fields) do
            if got[field] ~= nil and got[field] ~= "" then
                fields[field] = fields[field] + 1
            end
        end
        if #sample < P.SAMPLE then
            got.owner = nil -- never keep a player's name
            sample[#sample + 1] = got
        end
    end
    return { outcome = "listed", listings = listings, read = read, fields = fields, sample = sample }
end

function P.OnEvent(event)
    if not waiting then return end
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        local ok, result = pcall(P.Read)
        if not ok then
            finish({ outcome = "error", error = tostring(result) })
            notify("Reading the listings failed. /reload, then see debug.auctionProbe.")
            return
        end
        finish(result)
        notify(string.format("%d listing(s), %d read. /reload, then see debug.auctionProbe.",
            result.listings, result.read))
    elseif event == "AUCTION_HOUSE_CLOSED" then
        finish({ outcome = "closed" })
        notify("The auction house closed before the listings came.")
    end
end

--- Ask for every listing. Returns true once asked; false and why otherwise ("missing": the client lacks
--- the API, "waiting": already asked, "error": the client refused).
function P.Start()
    if waiting then
        notify("Still waiting for the listings.")
        return false, "waiting"
    end
    local missing = P.Missing()
    if #missing > 0 then
        save({ outcome = "missing", missing = missing })
        notify("This client has no full scan: " .. table.concat(missing, ", ") .. ".")
        return false, "missing"
    end
    if not frame and CreateFrame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event) P.OnEvent(event) end)
    end
    if frame then
        frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    end
    waiting = true
    run = run + 1
    local mine = run
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        finish({ outcome = "error", error = tostring(err) })
        notify("The client refused the scan: " .. tostring(err))
        return false, "error"
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(P.TIMEOUT, function()
            if waiting and run == mine then
                finish({ outcome = "timeout" })
                notify("No listings after " .. P.TIMEOUT .. " seconds. Is the auction house open, and has "
                    .. "no addon scanned in the last 15 minutes?")
            end
        end)
    end
    notify("Asked for every listing. Keep the auction house open.")
    return true
end

function P._ResetForTests()
    waiting = false
    run = 0
    frame = nil
end
