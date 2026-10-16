-- AltArmy TBC — auction house scans: full scans for the website, summary scans as the fallback.
-- A full scan asks the client for every listing (C_AuctionHouse.ReplicateItems: once per 15 minutes per
-- account) and reads what comes back into AuctionBook's ladders, a batch a frame. It also reads a full scan
-- another addon asked for (Auctionator's full scan): the listings event is the client's, whoever asked.
-- A summary scan is a blank browse query (C_AuctionHouse.SendBrowseQuery), paged until the client has every
-- result: one row per item, its cheapest unit price and units listed. No cooldown, far fewer rows, but no
-- ladder. Which runs is the player's scan mode (AltArmyTBC_Options.auctionScanMode, Options → General →
-- Auction House): "prefer_full" (the default) runs a full scan when the client allows one and a summary when
-- it cannot (cooldown, the client refused, no full-scan API); "only_full" runs full scans alone, and nothing
-- during the cooldown; "only_summary" runs summaries alone. Summaries are stored apart
-- (AuctionBook.StoreSummary) so the website only ever gets full scans.
-- Only a scan read to its end is stored; one the auction house closed on is dropped.
-- With the automatic scan on (AltArmyTBC_Options.auctionAutoScan, the Auction House options), a scan starts
-- AUTO_DELAY seconds after the auction house opens, if the client allows one, none is under way and this
-- auction house's newest scan (full or summary) is at least AUTO_GAP old. A scan asked for runs regardless.
-- A scan Alt Army starts (the button, /altarmy scan or the automatic scan) says in chat which kind it is when
-- it starts and how it ended; a full scan another addon asked for is read quietly.
-- luacheck: globals GetServerTime AltArmyTBC_Options

if not AltArmy then return end

AltArmy.AuctionScan = AltArmy.AuctionScan or {}
local S = AltArmy.AuctionScan

S.BATCH = 2000 -- listings read a frame
S.TIMEOUT = 60 -- seconds to wait for the listings (for a summary: for each page)
S.REPEAT = 30 -- seconds after a scan in which the client repeating its event is not a new scan
S.AUTO_DELAY = 1 -- seconds after the auction house opens before the automatic scan (the frame settles first)
S.AUTO_GAP = 120 -- seconds after this auction house's newest scan before the automatic scan runs again
S.REPLACED = 0.9 -- a summary ending with fewer rows than this share of the most it saw was someone else's search

-- The browse query of a summary scan: every item, as Auctionator's summary scan asks.
local BLANK_QUERY = { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }

local state = "idle" -- idle | waiting (asked, no listings yet) | reading
local kind -- "full" | "summary": the scan under way
local open = false
local visit = 0 -- which opening of the auction house the automatic scan's timer belongs to
local run = 0 -- which scan the timers belong to
local tally, index, total, source
local peak = 0 -- most browse rows a summary has seen
local deadline = 0 -- which summary timeout is current
local pending -- a browse call waiting for the client's query throttle
local finishedAt
local ours = false -- the scan under way is one Start asked for, so its end is said in chat
local listeners = {}

local function now()
    if GetServerTime then return GetServerTime() end
    return time and time() or 0
end

local ALTARMY_GOLD = "|cfffecc00"

local function say(text)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage then
        chat:AddMessage(ALTARMY_GOLD .. "Alt Army|r " .. text)
    end
end

local function kindName()
    return kind == "summary" and "Summary" or "Full"
end

local function book()
    return AltArmy.AuctionBook
end

local function set(new)
    state = new
    for i = 1, #listeners do
        listeners[i](state)
    end
end

--- idle, waiting or reading.
function S.State()
    return state
end

--- "full" or "summary" while a scan is under way; nil when idle.
function S.Kind()
    return kind
end

--- How much of the scan being read is read, 0..1; nil for a summary (its size is unknown until it ends).
function S.Progress()
    if kind == "summary" then return nil end
    if state ~= "reading" or not total or total == 0 then return 0 end
    return index / total
end

--- Seconds until the client allows another full scan.
function S.CooldownLeft()
    return book().CooldownLeft(now())
end

function S.IsOpen()
    return open
end

--- Call `fn(state)` whenever the state changes or a batch was read.
function S.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function isForever()
    local DS = AltArmy.DataStore
    return DS and DS.IsWowForever and true or false
end

--- True where Alt Army can full-scan: WoW Forever (the website takes Forever's prices from these scans
--- alone), with the client's full-scan API. Off elsewhere (TBC Anniversary) even if the client has the API.
function S.HasFullApi()
    if not isForever() then return false end
    local api = C_AuctionHouse
    return type(api) == "table" and type(api.ReplicateItems) == "function"
        and type(api.GetNumReplicateItems) == "function" and type(api.GetReplicateItemInfo) == "function"
end

--- True where Alt Army can summary-scan: WoW Forever, with the client's browse API.
function S.HasSummaryApi()
    if not isForever() then return false end
    local api = C_AuctionHouse
    return type(api) == "table" and type(api.SendBrowseQuery) == "function"
        and type(api.GetBrowseResults) == "function" and type(api.HasFullBrowseResults) == "function"
        and type(api.RequestMoreBrowseResults) == "function"
end

--- True where Alt Army scans at all: no button, options section, automatic scan or reading of other addons'
--- scans otherwise.
function S.HasApi()
    return S.HasFullApi() or S.HasSummaryApi()
end

S.SCAN_MODES = { "prefer_full", "only_full", "only_summary" }
local SCAN_MODE = { prefer_full = true, only_full = true, only_summary = true }

--- Which scans run (see the header): "prefer_full" unless set. Before the mode existed, a "Prefer full scans"
--- checkbox turned off (auctionPreferFullScan = false) meant summaries alone.
function S.GetScanMode()
    local o = type(AltArmyTBC_Options) == "table" and AltArmyTBC_Options or {}
    if SCAN_MODE[o.auctionScanMode] then return o.auctionScanMode end
    if o.auctionPreferFullScan == false then return "only_summary" end
    return "prefer_full"
end

function S.SetScanMode(mode)
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    AltArmyTBC_Options.auctionScanMode = SCAN_MODE[mode] and mode or "prefer_full"
    AltArmyTBC_Options.auctionPreferFullScan = nil
end

--- The kind of scan Start would run now: "full", "summary", or nil (none the mode allows can run: a full
--- scan still cooling down, or no API for the kind the mode wants).
function S.NextKind()
    local mode = S.GetScanMode()
    local fullReady = S.HasFullApi() and S.CooldownLeft() <= 0
    if mode == "only_full" then
        return fullReady and "full" or nil
    end
    if mode == "only_summary" then
        return S.HasSummaryApi() and "summary" or nil
    end
    if fullReady then return "full" end
    if S.HasSummaryApi() then return "summary" end
    return nil
end

local function stop()
    if ours then
        say(kindName() .. " auction house scan stopped before it finished; nothing was saved.")
        ours = false
    end
    run = run + 1
    tally, index, total, source, kind, pending = nil, nil, nil, nil, nil, nil
    peak = 0
    set("idle")
end

local function store()
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    if tally.listings > 0 and faction and faction ~= "" and realm and realm ~= "" then
        book().Store({
            t = now(),
            realm = realm,
            faction = faction,
            complete = true,
            listings = tally.listings,
            bidOnly = tally.bidOnly,
            source = source,
            items = book().Encode(tally),
        }, now())
        if ours then
            say(string.format("Full auction house scan complete: %d listings saved.", tally.listings))
        end
    elseif ours then
        say("Full auction house scan complete: no listings to save.")
    end
    ours = false
    finishedAt = now()
end

local function readBatch(mine)
    if run ~= mine or state ~= "reading" then return end
    local last = math.min(index + S.BATCH, total)
    local ok = pcall(function()
        for i = index, last - 1 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                C_AuctionHouse.GetReplicateItemInfo(i)
            book().Add(tally, itemID, count, buyout)
        end
    end)
    if not ok then
        stop()
        return
    end
    index = last
    if index >= total then
        store()
        stop()
        return
    end
    set("reading")
    C_Timer.After(0, function() readBatch(mine) end)
end

local function read()
    local asked = state == "waiting"
    if not asked then
        if finishedAt and now() - finishedAt < S.REPEAT then return end
        book().NoteRequest(now()) -- another addon's scan spends the cooldown too
    end
    run = run + 1
    tally, index, total = book().NewTally(), 0, C_AuctionHouse.GetNumReplicateItems() or 0
    source = asked and "own" or "heard"
    kind = "full"
    state = "reading"
    readBatch(run)
end

-- Summary scans ----------------------------------------------------------------------------------------

--- Run `fn` once the client's query throttle allows a query (now, or on AUCTION_HOUSE_THROTTLED_SYSTEM_READY).
local function whenReady(fn)
    local api = C_AuctionHouse
    if type(api.IsThrottledMessageSystemReady) ~= "function" or api.IsThrottledMessageSystemReady() then
        pending = nil
        fn()
    else
        pending = fn
    end
end

--- Stop the summary if no page arrives within TIMEOUT.
local function armTimeout()
    deadline = deadline + 1
    local mine, due = run, deadline
    C_Timer.After(S.TIMEOUT, function()
        if run == mine and deadline == due and state ~= "idle" then
            stop()
        end
    end)
end

local function storeSummary(rows)
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    if rows < peak * S.REPLACED then
        stop() -- someone else's search replaced ours: its few rows are not the auction house
        return
    end
    if tally.listings > 0 and faction and faction ~= "" and realm and realm ~= "" then
        book().StoreSummary({
            t = now(),
            realm = realm,
            faction = faction,
            summary = true,
            listings = tally.listings,
            items = book().Encode(tally),
        }, now())
        say(string.format("Summary auction house scan complete: %d items saved.", tally.listings))
    else
        say("Summary auction house scan complete: no listings to save.")
    end
    ours = false
    stop()
end

--- A page of browse results arrived: read them all again (the client keeps every page so far) and either
--- ask for the next page or store the summary.
local function readSummary()
    local mine = run
    local ok, rows, full = pcall(function()
        local results = C_AuctionHouse.GetBrowseResults() or {}
        local t = book().NewTally()
        for _, r in ipairs(results) do
            book().AddSummary(t, r.itemKey and r.itemKey.itemID, r.minPrice, r.totalQuantity)
        end
        tally = t
        return #results, C_AuctionHouse.HasFullBrowseResults()
    end)
    if not ok then
        stop()
        return
    end
    if full then
        storeSummary(rows)
        return
    end
    peak = math.max(peak, rows)
    set("reading")
    armTimeout()
    whenReady(function()
        if run ~= mine then return end
        if not pcall(C_AuctionHouse.RequestMoreBrowseResults) then stop() end
    end)
end

local function startSummary()
    run = run + 1
    local mine = run
    kind, ours, peak = "summary", true, 0
    say("Summary auction house scan started. Keep the auction house open until it completes.")
    set("waiting")
    armTimeout()
    whenReady(function()
        if run ~= mine then return end
        if not pcall(C_AuctionHouse.SendBrowseQuery, BLANK_QUERY) then stop() end
    end)
    return true
end

-- Automatic scan ---------------------------------------------------------------------------------------

--- Whether a scan starts by itself when the auction house opens (off until turned on).
function S.IsAutoScanEnabled()
    return type(AltArmyTBC_Options) == "table" and AltArmyTBC_Options.auctionAutoScan == true
end

function S.SetAutoScanEnabled(on)
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    AltArmyTBC_Options.auctionAutoScan = on == true
end

--- True when the auction house the player stands at was scanned (full or summary) under AUTO_GAP ago.
local function scannedRecently()
    local realm = GetRealmName and GetRealmName() or nil
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local newest = realm and faction and book().Newest(realm, faction)
    return newest ~= nil and now() - (newest.t or 0) < S.AUTO_GAP
end

local function scheduleAutoScan()
    if not S.IsAutoScanEnabled() or not S.HasApi() or not (C_Timer and C_Timer.After) then return end
    local mine = visit
    C_Timer.After(S.AUTO_DELAY, function()
        -- Start refuses when closed, busy (another addon's scan came first) or cooling down without a summary.
        if visit == mine and open and state == "idle" and not scannedRecently() then
            S.Start()
        end
    end)
end

local SUMMARY_EVENTS = {
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = true,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = true,
}

function S.OnEvent(event)
    if event == "AUCTION_HOUSE_SHOW" then
        open = true
        visit = visit + 1
        set(state)
        scheduleAutoScan()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        open = false
        visit = visit + 1
        stop()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if not S.HasFullApi() then return end
        if kind == "summary" then
            stop() -- another addon's full scan is worth more than our summary
        end
        if state ~= "reading" then
            read()
        end
    elseif SUMMARY_EVENTS[event] then
        if kind == "summary" and state ~= "idle" then
            readSummary()
        end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if kind == "summary" and state ~= "idle" then
            stop()
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if pending then
            local fn = pending
            pending = nil
            fn()
        end
    end
end

--- Start a scan of the kind the scan mode allows now (see NextKind). Returns true once asked; false and why
--- otherwise: "missing" (the client has neither scan), "closed" (no auction house open), "busy", "cooldown"
--- (nothing the scan mode allows can run: a full scan still cooling down), "error" (the client refused).
function S.Start()
    if not S.HasApi() then return false, "missing" end
    if not open then return false, "closed" end
    if state ~= "idle" then return false, "busy" end
    local nextKind = S.NextKind()
    if not nextKind then return false, "cooldown" end
    if nextKind == "summary" then
        return startSummary()
    end
    if not pcall(C_AuctionHouse.ReplicateItems) then
        if S.HasSummaryApi() and S.GetScanMode() ~= "only_full" then
            return startSummary()
        end
        return false, "error"
    end
    book().NoteRequest(now())
    run = run + 1
    local mine = run
    ours, kind = true, "full"
    say("Full auction house scan started. Keep the auction house open until it completes.")
    set("waiting")
    C_Timer.After(S.TIMEOUT, function()
        if run == mine and state == "waiting" then
            stop()
        end
    end)
    return true
end

function S._ResetForTests()
    state, open, run, visit = "idle", false, 0, 0
    tally, index, total, source, finishedAt, kind, pending = nil, nil, nil, nil, nil, nil, nil
    peak, deadline = 0, 0
    ours = false
    listeners = {}
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    -- Not every client has these events: registering an unknown one raises.
    for _, event in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
        "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event) S.OnEvent(event) end)
end
