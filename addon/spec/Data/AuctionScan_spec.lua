--[[ Unit tests for AuctionScan.lua — run: npm test ]]

describe("AuctionScan", function()
    local S, B
    local timers, rows, requested, now, states, chat
    local savedDataStore

    local function installApi()
        _G.C_AuctionHouse = {
            ReplicateItems = function() requested = requested + 1 end,
            GetNumReplicateItems = function() return #rows end,
            GetReplicateItemInfo = function(i)
                local r = rows[i + 1]
                if not r then return nil end
                return "name", 1, r[2], 1, true, 10, "", 0, 5, r[3], 0, nil, nil, nil, nil, 0, r[1], true
            end,
        }
    end

    --- Run the timers queued so far, and those they queue, until none are due within `seconds`.
    local function runTimers(seconds)
        local guard = 0
        while true do
            local due
            for i, t in ipairs(timers) do
                if t.seconds <= (seconds or 0) then
                    due = table.remove(timers, i)
                    break
                end
            end
            if not due then return end
            due.fn()
            guard = guard + 1
            assert.is_true(guard < 10000)
        end
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end
        package.loaded["AuctionBook"] = nil
        package.loaded["AuctionScan"] = nil
        require("AuctionBook")
        require("AuctionScan")
        S = AltArmy.AuctionScan
        B = AltArmy.AuctionBook
        assert.truthy(S)
    end)

    before_each(function()
        _G.AltArmyTBC_AuctionBook = nil
        _G.AltArmyTBC_Options = nil
        timers, rows, requested, now, states, chat = {}, {}, 0, 50000, {}, {}
        _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = text end }
        _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
        _G.GetServerTime = function() return now end
        _G.GetRealmName = function() return "Classic Beta PvE" end
        _G.UnitFactionGroup = function() return "Horde" end
        installApi()
        savedDataStore = AltArmy.DataStore
        AltArmy.DataStore = { IsWowForever = true }
        S._ResetForTests()
        S.OnChange(function(state) states[#states + 1] = state end)
        S.OnEvent("AUCTION_HOUSE_SHOW")
    end)

    after_each(function()
        AltArmy.DataStore = savedDataStore
    end)

    local function scans()
        return AltArmyTBC_AuctionBook and AltArmyTBC_AuctionBook.scans or {}
    end

    describe("automatic scan", function()
        local function reopen()
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            timers = {}
            S.OnEvent("AUCTION_HOUSE_SHOW")
        end

        it("is off unless turned on", function()
            assert.is_false(S.IsAutoScanEnabled())
            reopen()
            runTimers(S.AUTO_DELAY)
            assert.equals(0, requested)
        end)

        it("is kept in the account's options", function()
            S.SetAutoScanEnabled(true)
            assert.is_true(AltArmyTBC_Options.auctionAutoScan)
            assert.is_true(S.IsAutoScanEnabled())
            S.SetAutoScanEnabled(false)
            assert.is_false(AltArmyTBC_Options.auctionAutoScan)
        end)

        it("scans a moment after the auction house opens", function()
            S.SetAutoScanEnabled(true)
            reopen()
            assert.equals(0, requested)
            assert.equals(S.AUTO_DELAY, timers[1].seconds)
            runTimers(S.AUTO_DELAY)
            assert.equals(1, requested)
            assert.equals("waiting", S.State())
        end)

        it("waits for the client's cooldown instead of asking early", function()
            S.SetAutoScanEnabled(true)
            B.NoteRequest(now - 60)
            reopen()
            runTimers(S.AUTO_DELAY)
            assert.equals(0, requested)
        end)

        it("skips a house scanned under AUTO_GAP ago", function()
            S.SetAutoScanEnabled(true)
            B.StoreSummary({ t = now - S.AUTO_GAP + 1, realm = "Classic Beta PvE", faction = "Horde",
                summary = true, listings = 1, items = "2770:64*1*1" }, now)
            reopen()
            runTimers(S.AUTO_DELAY)
            assert.equals(0, requested)
            assert.equals("idle", S.State())
            assert.is_true((S.Start())) -- a scan asked for still runs
            assert.equals(1, requested)
        end)

        it("scans again once AUTO_GAP has passed, and only the house scanned counts", function()
            S.SetAutoScanEnabled(true)
            B.Store({ t = now - S.AUTO_GAP, realm = "Classic Beta PvE", faction = "Horde", complete = true,
                listings = 1, items = "2770:64*1*1" }, now)
            B.StoreSummary({ t = now - 10, realm = "Classic Beta PvE", faction = "Alliance",
                summary = true, listings = 1, items = "2770:64*1*1" }, now)
            reopen()
            runTimers(S.AUTO_DELAY)
            assert.equals(1, requested)
        end)

        it("does nothing if the auction house closed in the meantime", function()
            S.SetAutoScanEnabled(true)
            reopen()
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            runTimers(S.AUTO_DELAY)
            assert.equals(0, requested)
        end)

        it("leaves a scan another addon already started alone", function()
            S.SetAutoScanEnabled(true)
            rows = { { 2770, 1, 64 } }
            for i = 2, S.BATCH + 1 do
                rows[i] = { 2770, 1, 100 }
            end
            reopen()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE") -- Auctionator asked first
            assert.equals("reading", S.State())
            local due = table.remove(timers, 1)
            assert.equals(S.AUTO_DELAY, due.seconds)
            due.fn()
            assert.equals(0, requested)
        end)

        it("needs the full-scan API", function()
            S.SetAutoScanEnabled(true)
            _G.C_AuctionHouse = {}
            reopen()
            runTimers(S.AUTO_DELAY)
            assert.equals(0, requested)
        end)
    end)

    describe("Start", function()
        it("asks the client for every listing", function()
            assert.is_true((S.Start()))
            assert.equals(1, requested)
            assert.equals("waiting", S.State())
        end)

        it("needs an open auction house", function()
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("closed", reason)
            assert.equals(0, requested)
        end)

        it("waits out the client's cooldown", function()
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            now = now + B.COOLDOWN - 1
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("cooldown", reason)
            assert.equals(1, requested)
            now = now + 1
            assert.is_true((S.Start()))
        end)

        it("does not ask twice while one scan runs", function()
            S.Start()
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("busy", reason)
            assert.equals(1, requested)
        end)

        it("is WoW Forever's alone, even where the client has the full scan", function()
            AltArmy.DataStore.IsWowForever = false
            assert.is_false(S.HasApi())
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("missing", reason)
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE") -- another addon's scan is not read either
            assert.equals("idle", S.State())
            assert.equals(0, requested)
        end)

        it("says so when the client has no full scan", function()
            _G.C_AuctionHouse = {}
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("missing", reason)
        end)

        it("survives the client refusing", function()
            _G.C_AuctionHouse.ReplicateItems = function() error("nope") end
            local ok, reason = S.Start()
            assert.is_false(ok)
            assert.equals("error", reason)
            assert.equals("idle", S.State())
        end)

        it("gives up waiting after a while", function()
            S.Start()
            runTimers(S.TIMEOUT)
            assert.equals("idle", S.State())
            assert.equals(0, #scans())
        end)
    end)

    describe("reading", function()
        it("stores the book of a scan it asked for", function()
            rows = { { 2770, 20, 3340 }, { 2770, 1, 64 }, { 7067, 1, 700 }, { 7067, 3, 0 } }
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.same({ {
                t = 50000,
                realm = "Classic Beta PvE",
                faction = "Horde",
                complete = true,
                listings = 4,
                bidOnly = 1,
                source = "own",
                items = "2770:64*1*1,167*20*1;7067:700*1*1",
            } }, scans())
            assert.equals("idle", S.State())
        end)

        it("reads a big scan over several frames", function()
            for i = 1, S.BATCH * 2 + 10 do
                rows[i] = { 2770, 1, 100 }
            end
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            assert.equals("reading", S.State())
            assert.equals(0, #scans())
            local nextFrame = 0
            for _, t in ipairs(timers) do
                if t.seconds == 0 then nextFrame = nextFrame + 1 end
            end
            assert.equals(1, nextFrame)
            runTimers()
            assert.equals(S.BATCH * 2 + 10, scans()[1].listings)
            assert.equals("2770:100*" .. (S.BATCH * 2 + 10) .. "*" .. (S.BATCH * 2 + 10), scans()[1].items)
        end)

        it("reports its progress", function()
            for i = 1, S.BATCH * 2 do
                rows[i] = { 2770, 1, 100 }
            end
            states = {}
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            assert.equals(0.5, S.Progress())
            runTimers()
            assert.same({ "waiting", "reading", "idle" }, states)
        end)

        it("captures a scan another addon asked for", function()
            rows = { { 2770, 1, 64 } }
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals("heard", scans()[1].source)
            assert.equals(B.COOLDOWN, B.CooldownLeft(now))
        end)

        it("ignores the client repeating the event for the same scan", function()
            rows = { { 2770, 1, 64 } }
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            now = now + 5
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(1, #scans())
        end)

        it("drops a scan the auction house closed on", function()
            for i = 1, S.BATCH * 2 do
                rows[i] = { 2770, 1, 100 }
            end
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            runTimers()
            assert.equals(0, #scans())
            assert.equals("idle", S.State())
        end)

        it("stores nothing for an empty auction house", function()
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(0, #scans())
        end)

        it("stores nothing without a faction", function()
            _G.UnitFactionGroup = function() return nil end
            rows = { { 2770, 1, 64 } }
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(0, #scans())
        end)

        it("drops the scan when the client fails mid-read", function()
            rows = { { 2770, 1, 64 } }
            S.Start()
            _G.C_AuctionHouse.GetReplicateItemInfo = function() error("gone") end
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(0, #scans())
            assert.equals("idle", S.State())
        end)
    end)

    describe("chat", function()
        local function said(pattern)
            for _, line in ipairs(chat) do
                if line:find(pattern) then return true end
            end
            return false
        end

        it("says when a scan starts and when it is saved", function()
            rows = { { 2770, 20, 3340 }, { 2770, 1, 64 } }
            S.Start()
            assert.equals(1, #chat)
            assert.is_true(said("scan started"))
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(2, #chat)
            assert.is_true(said("scan complete: 2 listings saved"))
        end)

        it("speaks for the automatic scan too", function()
            S.SetAutoScanEnabled(true)
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            timers = {}
            S.OnEvent("AUCTION_HOUSE_SHOW")
            runTimers(S.AUTO_DELAY)
            assert.is_true(said("scan started"))
        end)

        it("says nothing when the scan could not start", function()
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            S.Start()
            assert.equals(0, #chat)
        end)

        it("says so when the auction house closed on the scan", function()
            for i = 1, S.BATCH * 2 do
                rows[i] = { 2770, 1, 100 }
            end
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            runTimers()
            assert.equals(2, #chat)
            assert.is_true(said("nothing was saved"))
        end)

        it("says so when the listings never came", function()
            S.Start()
            runTimers(S.TIMEOUT)
            assert.is_true(said("nothing was saved"))
        end)

        it("says so when there was nothing to save", function()
            S.Start()
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(2, #chat)
            assert.is_true(said("no listings"))
        end)

        it("stays quiet about a scan another addon asked for", function()
            rows = { { 2770, 1, 64 } }
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(1, #scans())
            assert.equals(0, #chat)
        end)
    end)

    describe("summary scan", function()
        local browse, queries, more, ready, pageSize, shown

        --- The client's browse API: `browse` is every result row { itemID, minPrice, totalQuantity };
        --- `pageSize` of them arrive per page.
        local function installBrowse()
            browse, queries, more, ready, shown, pageSize = {}, 0, 0, true, 0, 1000
            local api = _G.C_AuctionHouse
            api.SendBrowseQuery = function(q)
                assert.equals("", q.searchString)
                queries = queries + 1
                shown = math.min(#browse, pageSize)
            end
            api.GetBrowseResults = function()
                local out = {}
                for i = 1, shown do
                    local r = browse[i]
                    out[i] = { itemKey = { itemID = r[1] }, minPrice = r[2], totalQuantity = r[3] }
                end
                return out
            end
            api.HasFullBrowseResults = function() return shown >= #browse end
            api.RequestMoreBrowseResults = function()
                more = more + 1
                shown = math.min(#browse, shown + pageSize)
            end
            api.IsThrottledMessageSystemReady = function() return ready end
        end

        local function summaries()
            return AltArmyTBC_AuctionBook and AltArmyTBC_AuctionBook.summaries or {}
        end

        local function said(pattern)
            for _, line in ipairs(chat) do
                if line:find(pattern) then return true end
            end
            return false
        end

        before_each(installBrowse)

        it("is the fallback while the full scan cools down", function()
            B.NoteRequest(now - 60)
            assert.equals("summary", S.NextKind())
            assert.is_true((S.Start()))
            assert.equals(0, requested)
            assert.equals(1, queries)
            assert.equals("summary", S.Kind())
            assert.is_true(said("Summary auction house scan started"))
        end)

        it("is not used when a full scan is allowed and preferred", function()
            assert.equals("prefer_full", S.GetScanMode())
            assert.equals("full", S.NextKind())
            S.Start()
            assert.equals(1, requested)
            assert.equals(0, queries)
            assert.is_true(said("Full auction house scan started"))
        end)

        it("is always used with only summary scans", function()
            S.SetScanMode("only_summary")
            assert.equals("only_summary", AltArmyTBC_Options.auctionScanMode)
            assert.equals("summary", S.NextKind())
            S.Start()
            assert.equals(0, requested)
            assert.equals(1, queries)
            S.SetScanMode("prefer_full")
            assert.equals("prefer_full", S.GetScanMode())
        end)

        it("falls back to a full scan when there is no summary, when full scans are preferred", function()
            _G.C_AuctionHouse.SendBrowseQuery = nil
            assert.equals("full", S.NextKind())
        end)

        it("runs nothing with only summary scans and no summary", function()
            S.SetScanMode("only_summary")
            _G.C_AuctionHouse.SendBrowseQuery = nil
            assert.is_nil(S.NextKind())
            S.SetScanMode("prefer_full")
        end)

        it("is never used with only full scans: nothing runs during the cooldown", function()
            S.SetScanMode("only_full")
            assert.equals("full", S.NextKind())
            B.NoteRequest(now - 60)
            assert.is_nil(S.NextKind())
            local ok, why = S.Start()
            assert.is_false(ok)
            assert.equals("cooldown", why)
            assert.equals(0, queries)
            S.SetScanMode("prefer_full")
        end)

        it("is not the fallback for a refused full scan with only full scans", function()
            S.SetScanMode("only_full")
            _G.C_AuctionHouse.ReplicateItems = function() error("nope") end
            local ok, why = S.Start()
            assert.is_false(ok)
            assert.equals("error", why)
            assert.equals(0, queries)
            S.SetScanMode("prefer_full")
        end)

        it("reads the old Prefer full scans checkbox turned off as only summary scans", function()
            _G.AltArmyTBC_Options = { auctionPreferFullScan = false } -- saved before the scan mode
            assert.equals("only_summary", S.GetScanMode())
            S.SetScanMode("only_full")
            assert.is_nil(AltArmyTBC_Options.auctionPreferFullScan)
            assert.equals("only_full", S.GetScanMode())
            S.SetScanMode("bogus")
            assert.equals("prefer_full", S.GetScanMode())
        end)

        it("runs when the client refuses the full scan", function()
            _G.C_AuctionHouse.ReplicateItems = function() error("nope") end
            assert.is_true((S.Start()))
            assert.equals(1, queries)
            assert.equals("summary", S.Kind())
        end)

        it("pages through the results and stores them apart from full scans", function()
            B.Store({ t = 1, realm = "Classic Beta PvE", faction = "Horde", complete = true, items = "" }, 1)
            B.NoteRequest(now - 60)
            browse = { { 2770, 64, 340 }, { 2771, 90, 12 }, { 2772, 500, 3 } }
            pageSize = 2
            S.Start()
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            assert.equals("reading", S.State())
            assert.equals(1, more)
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
            assert.equals("idle", S.State())
            assert.same({ {
                t = 50000,
                realm = "Classic Beta PvE",
                faction = "Horde",
                summary = true,
                listings = 3,
                items = "2770:64*340*1;2771:90*12*1;2772:500*3*1",
            } }, summaries())
            assert.equals(1, #scans())
            assert.equals(1, scans()[1].t)
            assert.is_true(said("Summary auction house scan complete: 3 items saved"))
        end)

        it("does not spend the full scan's cooldown", function()
            S.SetScanMode("only_summary")
            browse = { { 2770, 64, 340 } }
            S.Start()
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            assert.equals(0, S.CooldownLeft())
            S.SetScanMode("prefer_full")
            assert.equals("full", S.NextKind())
        end)

        it("waits for the client's query throttle", function()
            ready = false
            B.NoteRequest(now - 60)
            S.Start()
            assert.equals(0, queries)
            assert.equals("waiting", S.State())
            ready = true
            S.OnEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
            assert.equals(1, queries)
        end)

        it("ignores browse results while no summary of ours runs", function()
            browse = { { 2770, 64, 340 } }
            shown = 1
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            assert.equals("idle", S.State())
            assert.equals(0, #summaries())
        end)

        it("drops a summary someone else's search replaced", function()
            B.NoteRequest(now - 60)
            for i = 1, 10 do browse[i] = { 3000 + i, 10, 1 } end
            pageSize = 6
            S.Start()
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            browse = { { 2770, 64, 340 } } -- the player searched for one item
            shown = 1
            S.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            assert.equals("idle", S.State())
            assert.equals(0, #summaries())
            assert.is_true(said("nothing was saved"))
        end)

        it("is dropped when the auction house closes, the client fails or nothing comes", function()
            B.NoteRequest(now - 60)
            S.Start()
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            assert.equals("idle", S.State())
            S.OnEvent("AUCTION_HOUSE_SHOW")
            S.Start()
            S.OnEvent("AUCTION_HOUSE_BROWSE_FAILURE")
            assert.equals("idle", S.State())
            S.Start()
            runTimers(S.TIMEOUT)
            assert.equals("idle", S.State())
            assert.equals(0, #summaries())
        end)

        it("gives way to a full scan another addon asked for", function()
            B.NoteRequest(now - 60)
            S.Start()
            rows = { { 2770, 1, 64 } }
            now = now + B.COOLDOWN
            S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
            runTimers()
            assert.equals(1, #scans())
            assert.equals("heard", scans()[1].source)
            assert.equals(0, #summaries())
        end)

        it("is what the automatic scan runs during the cooldown", function()
            S.SetAutoScanEnabled(true)
            B.NoteRequest(now - 60)
            S.OnEvent("AUCTION_HOUSE_CLOSED")
            timers = {}
            S.OnEvent("AUCTION_HOUSE_SHOW")
            runTimers(S.AUTO_DELAY)
            assert.equals(1, queries)
        end)

        it("has no progress to report", function()
            B.NoteRequest(now - 60)
            S.Start()
            assert.is_nil(S.Progress())
        end)
    end)

    -- spec/fixtures/auction_book_v1.lua is the golden SavedVariable of the two scans below. The site's
    -- tests (site/tests/test_book.py) read that same file, so its parser must read back any change here.
    it("writes the golden book", function()
        now = 1790725000
        rows = { { 2770, 20, 3340 }, { 2770, 20, 3340 }, { 2770, 20, 3340 }, { 7067, 1, 12000 },
            { 7067, 1, 12000 } }
        S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        runTimers()

        now = 1790726574
        rows = { { 2589, 20, 1600 }, { 2589, 20, 1600 }, { 2770, 1, 64 }, { 2770, 2, 128 }, { 2770, 20, 3340 },
            { 2770, 5000, 835000 }, { 5631, 39, 10686 }, { 7067, 1, 700 }, { 7067, 1, 10199 },
            { 7067, 2, 24000 }, { 7067, 1, 0 }, { 14048, 3, 339 }, { 14048, 3, 342 } }
        for price = 101, 112 do
            rows[#rows + 1] = { 14048, 1, price }
        end
        S.Start()
        S.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        runTimers()

        local written = AltArmyTBC_AuctionBook
        local env = {}
        local chunk = assert(loadfile("spec/fixtures/auction_book_v1.lua"))
        setfenv(chunk, env)
        chunk()
        assert.same(env.AltArmyTBC_AuctionBook, written)
    end)
end)
