--[[ Unit tests for AuctionBook.lua — run: npm test ]]

describe("AuctionBook", function()
    local B

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["AuctionBook"] = nil
        require("AuctionBook")
        B = AltArmy.AuctionBook
        assert.truthy(B)
    end)

    before_each(function()
        _G.AltArmyTBC_AuctionBook = nil
    end)

    local function tally(listings)
        local t = B.NewTally()
        for _, l in ipairs(listings) do
            B.Add(t, l[1], l[2], l[3])
        end
        return t
    end

    describe("Add", function()
        it("prices a stack per unit, rounded up", function()
            local t = tally({ { 5631, 39, 10686 } })
            assert.equals("5631:274*39*1", B.Encode(t))
        end)

        it("pools listings at the same unit price", function()
            local t = tally({ { 2770, 20, 3340 }, { 2770, 5, 835 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1,167*25*2", B.Encode(t))
            assert.equals(3, t.listings)
        end)

        it("counts a listing without a buyout but does not price it", function()
            local t = tally({ { 2770, 20, 0 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1", B.Encode(t))
            assert.equals(2, t.listings)
            assert.equals(1, t.bidOnly)
        end)

        it("skips rows the client returned without an item, count or buyout", function()
            local t = tally({ { nil, 1, 100 }, { 2770, 0, 100 }, { 2770, nil, 100 }, { 0, 1, 100 },
                { 2770, 1, nil } })
            assert.equals("", B.Encode(t))
            assert.equals(0, t.listings)
        end)
    end)

    describe("Encode", function()
        it("lists items by id and levels cheapest first", function()
            local t = tally({ { 7067, 1, 12000 }, { 2770, 1, 167 }, { 7067, 1, 700 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1,167*1*1;7067:700*1*1,12000*1*1", B.Encode(t))
        end)

        it("folds the levels past the limit into a tail at their cheapest price", function()
            local listings = {}
            for i = 1, B.MAX_LEVELS + 3 do
                listings[#listings + 1] = { 2770, 2, 2 * (100 + i) }
            end
            local text = B.Encode(tally(listings))
            local levels = {}
            for level in text:gmatch("[^,]+") do
                levels[#levels + 1] = level
            end
            assert.equals(B.MAX_LEVELS + 1, #levels)
            assert.equals("2770:101*2*1", levels[1])
            assert.equals("~" .. (100 + B.MAX_LEVELS + 1) .. "*6*3", levels[#levels])
        end)
    end)

    describe("Store", function()
        local function scan(t, realm, faction)
            return { t = t, realm = realm or "Classic Beta PvE", faction = faction or "Horde",
                complete = true, listings = 1, bidOnly = 0, source = "own", items = "2770:64*1*1" }
        end

        it("creates the log on first use", function()
            B.Store(scan(1000), 1000)
            assert.equals(B.VERSION, AltArmyTBC_AuctionBook.version)
            assert.equals(1, #AltArmyTBC_AuctionBook.scans)
            assert.equals(1000, AltArmyTBC_AuctionBook.scans[1].t)
        end)

        it("keeps only the newest scans of an auction house", function()
            for i = 1, B.MAX_SCANS + 2 do
                B.Store(scan(1000 * i), 1000 * i)
            end
            local scans = AltArmyTBC_AuctionBook.scans
            assert.equals(B.MAX_SCANS, #scans)
            assert.equals(3000, scans[1].t)
            assert.equals(1000 * (B.MAX_SCANS + 2), scans[#scans].t)
        end)

        it("counts each realm and faction on its own", function()
            for i = 1, B.MAX_SCANS do
                B.Store(scan(1000 * i), 1000 * i)
            end
            B.Store(scan(9000, "Classic Beta PvE", "Alliance"), 9000)
            B.Store(scan(9500, "Classic Beta PvP 2", "Horde"), 9500)
            assert.equals(B.MAX_SCANS + 2, #AltArmyTBC_AuctionBook.scans)
        end)

        it("drops scans past their age", function()
            B.Store(scan(1000), 1000)
            B.Store(scan(2000 + B.MAX_AGE), 2000 + B.MAX_AGE)
            local scans = AltArmyTBC_AuctionBook.scans
            assert.equals(1, #scans)
            assert.equals(2000 + B.MAX_AGE, scans[1].t)
        end)

        it("replaces a log it cannot read", function()
            _G.AltArmyTBC_AuctionBook = "garbage"
            B.Store(scan(1000), 1000)
            assert.equals(1, #AltArmyTBC_AuctionBook.scans)
        end)
    end)

    describe("Decode", function()
        it("reads Encode's text back into ladders, cheapest first", function()
            local book = B.Decode("2770:64*3*2,167*5020*2;7067:700*1*1")
            assert.same({ { price = 64, units = 3, listings = 2, tail = false },
                { price = 167, units = 5020, listings = 2, tail = false } }, book[2770])
            assert.same({ { price = 700, units = 1, listings = 1, tail = false } }, book[7067])
        end)

        it("flags the tail level", function()
            local listings = {}
            for i = 1, B.MAX_LEVELS + 3 do
                listings[#listings + 1] = { 2770, 2, 2 * (100 + i) }
            end
            local levels = B.Decode(B.Encode(tally(listings)))[2770]
            assert.equals(B.MAX_LEVELS + 1, #levels)
            assert.is_false(levels[1].tail)
            assert.same({ price = 100 + B.MAX_LEVELS + 1, units = 6, listings = 3, tail = true },
                levels[#levels])
        end)

        it("reads the golden scan", function()
            dofile("spec/fixtures/auction_book_v1.lua")
            local book = B.Decode(AltArmyTBC_AuctionBook.scans[2].items)
            assert.equals(80, book[2589][1].price)
            assert.equals(13, #book[14048])
            assert.is_true(book[14048][13].tail)
        end)

        it("gives nothing for empty or unreadable text", function()
            assert.same({}, B.Decode(nil))
            assert.same({}, B.Decode(""))
            assert.same({}, B.Decode("junk;2770:abc"))
        end)
    end)

    describe("Latest", function()
        local function scan(t, realm, faction, complete)
            return { t = t, realm = realm, faction = faction, complete = complete ~= false, items = "" }
        end

        it("is nil before any scan", function()
            assert.is_nil(B.Latest("Classic Beta PvE", "Horde"))
        end)

        it("picks the newest complete scan of that realm and faction", function()
            _G.AltArmyTBC_AuctionBook = { version = 1, scans = {
                scan(1000, "R", "Horde"), scan(2000, "R", "Horde"), scan(3000, "R", "Alliance"),
                scan(4000, "Other", "Horde"), scan(5000, "R", "Horde", false),
            } }
            assert.equals(2000, B.Latest("R", "Horde").t)
            assert.equals(3000, B.Latest("R", "Alliance").t)
            assert.is_nil(B.Latest("Nope", "Horde"))
        end)
    end)

    describe("Clear", function()
        it("drops every scan but keeps the client's cooldown", function()
            _G.AltArmyTBC_AuctionBook = { version = 1, lastRequest = 5000, scans = {
                { t = 1000, realm = "R", faction = "Horde", complete = true, items = "" },
            } }
            assert.equals(1, B.Clear())
            assert.is_nil(B.Latest("R", "Horde"))
            assert.equals(0, #B.GetLog().scans)
            assert.equals(B.COOLDOWN, B.CooldownLeft(5000))
        end)

        it("is fine before any scan", function()
            assert.equals(0, B.Clear())
            assert.equals(0, #B.GetLog().scans)
        end)
    end)

    describe("summaries", function()
        local function summary(rows)
            local t = B.NewTally()
            for _, r in ipairs(rows) do
                B.AddSummary(t, r[1], r[2], r[3])
            end
            return t
        end

        it("keeps one level per item: its cheapest price and every unit listed", function()
            local t = summary({ { 2770, 64, 340 }, { 2771, 90, 12 } })
            assert.equals("2770:64*340*1;2771:90*12*1", B.Encode(t))
            assert.equals(2, t.listings)
        end)

        it("merges rows of one item id at their cheapest price", function()
            local t = summary({ { 2770, 70, 10 }, { 2770, 64, 5 } })
            assert.equals("2770:64*15*1", B.Encode(t))
        end)

        it("skips rows with nothing listed or no price", function()
            local t = summary({ { 2770, 64, 0 }, { 2771, 0, 4 }, { nil, 5, 5 } })
            assert.equals("", B.Encode(t))
            assert.equals(0, t.listings)
        end)

        local function stored(t, realm, faction)
            return { t = t, realm = realm or "R", faction = faction or "Horde", summary = true, items = "" }
        end

        it("are stored apart from full scans, one per realm and faction", function()
            B.Store({ t = 1000, realm = "R", faction = "Horde", complete = true, items = "" }, 1000)
            B.StoreSummary(stored(2000), 2000)
            B.StoreSummary(stored(3000), 3000)
            B.StoreSummary(stored(3500, "R", "Alliance"), 3500)
            local log = B.GetLog()
            assert.equals(1, #log.scans)
            assert.equals(1000, log.scans[1].t)
            assert.equals(2, #log.summaries)
            assert.equals(3000, B.LatestSummary("R", "Horde").t)
            assert.equals(3500, B.LatestSummary("R", "Alliance").t)
            assert.equals(1000, B.Latest("R", "Horde").t)
        end)

        it("drop past their age", function()
            B.StoreSummary(stored(1000, "R", "Alliance"), 1000)
            B.StoreSummary(stored(1000 + B.MAX_AGE + 1), 1000 + B.MAX_AGE + 1)
            assert.is_nil(B.LatestSummary("R", "Alliance"))
        end)

        it("Newest picks the newer of the full scan and the summary", function()
            assert.is_nil(B.Newest("R", "Horde"))
            B.Store({ t = 1000, realm = "R", faction = "Horde", complete = true, items = "" }, 1000)
            assert.equals(1000, B.Newest("R", "Horde").t)
            B.StoreSummary(stored(2000), 2000)
            assert.is_true(B.Newest("R", "Horde").summary)
            B.Store({ t = 3000, realm = "R", faction = "Horde", complete = true, items = "" }, 3000)
            assert.equals(3000, B.Newest("R", "Horde").t)
            assert.is_nil(B.Newest("R", "Horde").summary)
        end)

        it("Newest says there is none while the debug option hides the scans, which stay stored", function()
            B.Store({ t = 1000, realm = "R", faction = "Horde", complete = true, items = "" }, 1000)
            local saved = AltArmy.Debug
            AltArmy.Debug = { IsHideAuctionData = function() return true end }
            assert.is_nil(B.Newest("R", "Horde"))
            AltArmy.Debug = saved
            assert.equals(1000, B.Newest("R", "Horde").t)
        end)

        it("are cleared with the full scans", function()
            B.Store({ t = 1000, realm = "R", faction = "Horde", complete = true, items = "" }, 1000)
            B.StoreSummary(stored(2000), 2000)
            assert.equals(2, B.Clear())
            assert.is_nil(B.Newest("R", "Horde"))
        end)
    end)

    describe("the client's cooldown", function()
        it("is none before any request", function()
            assert.equals(0, B.CooldownLeft(5000))
        end)

        it("counts down from the last request, whoever made it", function()
            B.NoteRequest(5000)
            assert.equals(B.COOLDOWN, B.CooldownLeft(5000))
            assert.equals(B.COOLDOWN - 60, B.CooldownLeft(5060))
            assert.equals(0, B.CooldownLeft(5000 + B.COOLDOWN))
            assert.equals(0, B.CooldownLeft(5000 + B.COOLDOWN + 99))
        end)

        it("is none when the clock went backwards", function()
            B.NoteRequest(5000)
            assert.equals(0, B.CooldownLeft(100))
        end)
    end)
end)
