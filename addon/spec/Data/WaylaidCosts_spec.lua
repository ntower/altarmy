--[[ Unit tests for WaylaidCosts.lua (Economy tab, Waylaid Crates) — run: npm test ]]

describe("WaylaidCosts", function()
    local W

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["CraftPlan"] = nil
        package.loaded["WaylaidCosts"] = nil
        require("CraftPlan")
        require("WaylaidCosts")
        W = AltArmy.WaylaidCosts
        assert.truthy(W)
    end)

    local function lv(price, units, tail)
        return { price = price, units = units, listings = 1, tail = tail == true }
    end

    describe("CostForUnits", function()
        it("buys the cheapest units first", function()
            assert.equals(60, W.CostForUnits({ lv(10, 3), lv(15, 9) }, 5))
        end)

        it("fits exactly on a level boundary", function()
            assert.equals(30, W.CostForUnits({ lv(10, 3), lv(15, 9) }, 3))
        end)

        it("is nil when too few units are listed", function()
            assert.is_nil(W.CostForUnits({ lv(10, 3) }, 4))
            assert.is_nil(W.CostForUnits(nil, 1))
        end)

        it("prices the tail at its cheapest price and says so", function()
            local cost, approx = W.CostForUnits({ lv(10, 1), lv(20, 5, true) }, 3)
            assert.equals(50, cost)
            assert.is_true(approx)
            local _, exact = W.CostForUnits({ lv(10, 1), lv(20, 5, true) }, 1)
            assert.is_false(exact)
        end)

        it("costs nothing for no units", function()
            assert.equals(0, W.CostForUnits({}, 0))
        end)
    end)

    local CRATES = {
        GENERIC = 900,
        LIST = {},
        ById = {
            [900] = { id = 900, name = "Waylaid Crate", short = "Waylaid Crate (unread)", random = true, bundles = {} },
            [901] = { id = 901, name = "Waylaid Crate: Apprentice Ore", short = "Apprentice Ore", tier = "Apprentice",
                kind = "Gathered", bundles = { { item = 1, count = 20, name = "Copper Ore" },
                    { item = 2, count = 20, name = "Tin Ore" } } },
            [902] = { id = 902, name = "Waylaid Crate: Expert Ingots", short = "Expert Ingots", tier = "Expert",
                kind = "Crafted", bundles = { { item = 3, count = 10, name = "Gold Bar" } } },
            [903] = { id = 903, name = "Waylaid Crate: Artisan Parts", short = "Artisan Parts", tier = "Artisan",
                kind = "Crafted", bundles = { { item = 4, count = 5, name = "Thorium Widget" } } },
        },
    }
    for _, id in ipairs({ 900, 901, 902, 903 }) do
        CRATES.LIST[#CRATES.LIST + 1] = CRATES.ById[id]
    end

    local function byId(rows)
        local out = {}
        for _, r in ipairs(rows) do
            out[r.id] = r
        end
        return out
    end

    -- Smelt Gold: one Gold Ore (item 5) makes a Gold Bar (item 3); a character called Miner knows it.
    local RECIPES = {
        [500] = { out = 3, n = 1, prof = "Mining", name = "Smelt Gold", reagents = { { item = 5, count = 1 } } },
    }
    local function context(book, known)
        return {
            book = book, items = { [3] = { name = "Gold Bar", stack = 20 }, [5] = { name = "Gold Ore", stack = 20 } },
            recipes = RECIPES, byOutput = { [3] = { 500 } }, current = "Me",
            knownBy = function(spell) return (known or { [500] = "Miner" })[spell] end,
            discountOf = function() return 0 end,
        }
    end

    describe("BuildRows", function()
        local book = {
            [900] = { lv(500, 4) },
            [901] = { lv(1000, 1), lv(1200, 2) },
            [902] = { lv(3000, 1) },
            [1] = { lv(50, 20) }, -- Copper Ore: 1000c for 20
            [2] = { lv(30, 25) }, -- Tin Ore: 600c for 20, cheaper
            [3] = { lv(900, 4) }, -- Gold Bar: only 4 of 10 listed
            [5] = { lv(50, 20) }, -- Gold Ore: 10 smelt into the 10 Gold Bars for 500c
        }

        it("lists every crate, those not on the auction house without a price", function()
            local rows = byId(W.BuildRows(book, CRATES))
            assert.truthy(rows[900])
            assert.truthy(rows[901])
            assert.truthy(rows[902])
            local r = rows[903]
            assert.is_nil(r.price)
            assert.equals(0, r.listed)
            assert.is_nil(r.bestCost)
            assert.is_nil(r.perFavor)
        end)

        it("fills from the auction house with the cheapest bundle listed in full", function()
            local r = byId(W.BuildRows(book, CRATES))[901]
            assert.equals(1000, r.price)
            assert.equals(3, r.listed)
            assert.equals("Tin Ore", r.buyBundle.name)
            assert.equals(600, r.buy)
            assert.equals("buy", r.best)
            assert.equals(r.buyBundle, r.bundle)
            assert.equals("Gathered", r.kind)
            assert.equals("Apprentice", r.tier)
        end)

        it("takes the turn-in's gold off the total and divides by its Favor", function()
            local r = byId(W.BuildRows(book, CRATES))[901] -- Apprentice, gathered: 5 Favor and 2.5s back
            assert.equals(5, r.favor)
            assert.is_nil(r.favorGuess)
            assert.is_true(byId(W.BuildRows(book, CRATES))[903].favorGuess) -- Artisan: a guess
            assert.equals(250, r.goldBack)
            assert.equals(1350, r.total) -- 1000 crate + 600 Tin Ore - 250
            assert.equals(270, r.perFavor)
        end)

        it("still prices the fill of a crate that is not listed, without a total", function()
            local r = byId(W.BuildRows({ [2] = { lv(30, 25) } }, CRATES))[901]
            assert.is_nil(r.price)
            assert.equals(600, r.buy)
            assert.is_nil(r.total)
            assert.is_nil(r.perFavor)
        end)

        it("fills by crafting when the bundle can't be bought in full, and plans the steps", function()
            local r = byId(W.BuildRows(book, CRATES, false, context(book)))[902]
            assert.is_nil(r.buy) -- only 4 of 10 Gold Bars listed
            assert.equals(500, r.craft)
            assert.equals("Miner", r.who)
            assert.is_true(r.canCraft)
            assert.equals("craft", r.best)
            assert.equals("Gold Bar", r.bundle.name)
            assert.equals(2000, r.total) -- 3000 crate + 500 crafted - 1500 back
            assert.equals(67, r.perFavor) -- / 30 Favor, rounded
            assert.equals("ah", r.steps[1].kind)
            assert.equals(5, r.steps[1].item)
            assert.equals("craft", r.steps[#r.steps].kind)
        end)

        it("prices both ways and takes the cheaper", function()
            local cheapBars = { [902] = { lv(3000, 1) }, [3] = { lv(40, 10) }, [5] = { lv(50, 20) } }
            local r = byId(W.BuildRows(cheapBars, CRATES, false, context(cheapBars)))[902]
            assert.equals(400, r.buy)
            assert.equals(500, r.craft)
            assert.equals("buy", r.best)
            assert.equals(400, r.bestCost)
        end)

        it("has no craft price when nobody knows the recipe", function()
            local r = byId(W.BuildRows(book, CRATES, false, context(book, {})))[902]
            assert.is_nil(r.craft)
            assert.is_false(r.canCraft)
            assert.is_nil(r.best)
            assert.equals(30, r.favor)
            assert.equals(1500, r.goldBack)
            assert.is_nil(r.perFavor)
        end)

        it("goes negative when the turn-in gives back more than the crate cost", function()
            local r = byId(W.BuildRows({ [901] = { lv(100, 1) }, [2] = { lv(5, 20) } }, CRATES))[901]
            assert.equals(-50, r.total) -- 100 + 100 - 250
            assert.equals(-10, r.perFavor)
        end)

        it("prices an unread crate without a fill or a reward", function()
            local r = byId(W.BuildRows(book, CRATES, false, context(book)))[900]
            assert.equals(500, r.price)
            assert.is_true(r.random)
            assert.is_nil(r.favor)
            assert.is_nil(r.perFavor)
            assert.is_nil(r.bestCost)
        end)

        it("keeps every bundle priced both ways for the tooltip, cheapest first", function()
            local rows = byId(W.BuildRows(book, CRATES, false, context(book)))
            assert.equals(2, #rows[901].options)
            assert.equals("Tin Ore", rows[901].options[1].name)
            assert.equals(600, rows[901].options[1].cost)
            assert.equals("Copper Ore", rows[901].options[2].name)
            assert.equals(1000, rows[901].options[2].cost)
            local bar = rows[902].options[1]
            assert.is_nil(bar.cost)
            assert.equals(4, bar.listed)
            assert.equals(500, bar.craft)
        end)

        it("marks the row from a summary scan, not its costs", function()
            local r = byId(W.BuildRows(book, CRATES, true))[901]
            assert.is_true(r.summary)
            assert.equals(600, r.buy)
            assert.is_false(r.buyApprox)
            local exact = byId(W.BuildRows(book, CRATES))[901]
            assert.is_nil(exact.summary)
            assert.is_false(exact.buyApprox)
        end)

        it("lists bundles that cannot be had after the priced ones", function()
            local r = byId(W.BuildRows({ [901] = { lv(1000, 1) }, [2] = { lv(30, 25) } }, CRATES))[901]
            assert.equals("Tin Ore", r.options[1].name)
            assert.equals("Copper Ore", r.options[2].name)
            assert.is_nil(r.options[2].cost)
        end)
    end)

    describe("BuildRow", function()
        it("builds one crate's row as BuildRows does", function()
            local book = { [902] = { lv(3000, 1) }, [5] = { lv(50, 20) } }
            local one = W.BuildRow(CRATES.ById[902], book, false, context(book))
            local all = byId(W.BuildRows(book, CRATES, false, context(book)))[902]
            assert.equals(all.craft, one.craft)
            assert.equals(all.perFavor, one.perFavor)
            assert.equals(all.who, one.who)
            assert.equals(#all.steps, #one.steps)
        end)
    end)

    describe("IsOldData", function()
        it("is old only past an hour", function()
            assert.is_false(W.IsOldData(1000, 1000 + 3600))
            assert.is_true(W.IsOldData(1000, 1000 + 3601))
            assert.is_false(W.IsOldData(1000, 900))
        end)
    end)

    describe("FilterRows", function()
        local book = {
            [900] = { lv(500, 4) },
            [901] = { lv(1000, 1) },
            [902] = { lv(3000, 1) },
            [2] = { lv(30, 25) },
            [3] = { lv(900, 4) }, -- Gold Bar: too few to fill Expert Ingots
        }

        local function ids(rows)
            local out = {}
            for i, r in ipairs(rows) do out[i] = r.id end
            table.sort(out)
            return out
        end

        it("keeps every crate unless asked", function()
            assert.equals(4, #W.FilterRows(W.BuildRows(book, CRATES), {}))
            assert.equals(4, #W.FilterRows(W.BuildRows(book, CRATES)))
        end)

        it("hides crates not listed, and those no bundle can fill (the unread crate is kept)", function()
            assert.same({ 900, 901 }, ids(W.FilterRows(W.BuildRows(book, CRATES), { hideUnavailable = true })))
        end)

        it("counts a crate a craft can fill as available", function()
            local withOre = { [5] = { lv(50, 20) } }
            for k, v in pairs(book) do withOre[k] = v end
            local rows = W.BuildRows(withOre, CRATES, false, context(withOre))
            assert.same({ 900, 901, 902 }, ids(W.FilterRows(rows, { hideUnavailable = true })))
        end)

        it("hides the crates the characters can't fill by crafting", function()
            local withOre = { [5] = { lv(50, 20) } }
            for k, v in pairs(book) do withOre[k] = v end
            local rows = W.BuildRows(withOre, CRATES, false, context(withOre))
            assert.same({ 902 }, ids(W.FilterRows(rows, { hideUncraftable = true })))
        end)

        it("hides the levels unticked, keeping a crate without a tier", function()
            local rows = W.BuildRows(book, CRATES)
            assert.equals(4, #W.FilterRows(rows, { hiddenTiers = {} }))
            assert.same({ 900, 903 }, ids(W.FilterRows(rows, { hiddenTiers = { Apprentice = true, Expert = true } })))
        end)
    end)

    describe("Reward", function()
        it("gives the Favor and gold measured per tier, crafted crates twice gathered", function()
            assert.same({ favor = 5, copper = 250 }, W.Reward("Apprentice", "Gathered"))
            assert.same({ favor = 10, copper = 500 }, W.Reward("Apprentice", "Crafted"))
            assert.same({ favor = 10, copper = 500 }, W.Reward("Journeyman", "Gathered"))
            assert.same({ favor = 20, copper = 1000 }, W.Reward("Journeyman", "Crafted"))
            assert.same({ favor = 15, copper = 750 }, W.Reward("Expert", "Gathered"))
            assert.same({ favor = 30, copper = 1500 }, W.Reward("Expert", "Crafted"))
        end)

        it("assumes Artisan continues the steps (not measured yet)", function()
            assert.same({ favor = 20, copper = 1000, guess = true }, W.Reward("Artisan", "Gathered"))
            assert.same({ favor = 40, copper = 2000, guess = true }, W.Reward("Artisan", "Crafted"))
            assert.is_nil(W.Reward("Expert", "Crafted").guess)
        end)

        it("knows nothing for the unread crate", function()
            assert.is_nil(W.Reward(nil, nil))
        end)
    end)

    describe("Compare", function()
        local a = { name = "A", tier = "Apprentice", price = 10, favor = 5, perFavor = 100, buy = 90 }
        local b = { name = "B", tier = "Expert", price = 20, favor = 30, perFavor = 50, buy = 30, craft = 25 }
        local n = { name = "C", tier = "Artisan", price = 5 }

        local function sorted(key, asc)
            local rows = { a, b, n }
            table.sort(rows, function(x, y) return W.Compare(x, y, key, asc) end)
            return { rows[1].name, rows[2].name, rows[3].name }
        end

        it("sorts by total cost per Favor, rows without one last either way", function()
            assert.same({ "B", "A", "C" }, sorted("perFavor", true))
            assert.same({ "A", "B", "C" }, sorted("perFavor", false))
        end)

        it("sorts by Favor, rows without it last either way", function()
            assert.same({ "A", "B", "C" }, sorted("favor", true))
            assert.same({ "B", "A", "C" }, sorted("favor", false))
        end)

        it("sorts by either way to fulfil, rows without it last", function()
            assert.same({ "B", "A", "C" }, sorted("buy", true))
            assert.same({ "A", "B", "C" }, sorted("buy", false))
            assert.same({ "B", "A", "C" }, sorted("craft", true)) -- A and C tie on no craft: by tier
        end)

        it("sorts by crate price, crates not listed last either way", function()
            assert.same({ "C", "A", "B" }, sorted("price", true))
            local unlisted = { name = "D", tier = "Journeyman" }
            local rows = { a, unlisted, b }
            table.sort(rows, function(x, y) return W.Compare(x, y, "price", false) end)
            assert.same({ "B", "A", "D" }, { rows[1].name, rows[2].name, rows[3].name })
            table.sort(rows, function(x, y) return W.Compare(x, y, "price", true) end)
            assert.same({ "A", "B", "D" }, { rows[1].name, rows[2].name, rows[3].name })
        end)

        it("sorts crates by tier in game order", function()
            assert.same({ "A", "B", "C" }, sorted("crate", true))
            assert.same({ "C", "B", "A" }, sorted("crate", false))
        end)
    end)

    describe("AgeLevel", function()
        it("is fresh under 15 minutes, stale up to 30, then old", function()
            assert.equals("fresh", W.AgeLevel(1000, 1000 + 14 * 60 + 59))
            assert.equals("stale", W.AgeLevel(1000, 1000 + 15 * 60))
            assert.equals("stale", W.AgeLevel(1000, 1000 + 30 * 60))
            assert.equals("old", W.AgeLevel(1000, 1000 + 30 * 60 + 1))
        end)

        it("is fresh if the clock went back", function()
            assert.equals("fresh", W.AgeLevel(1000, 900))
        end)
    end)

    describe("AgeText", function()
        local function fmt(s)
            return s .. "s"
        end

        it("says how long ago the scan was taken", function()
            assert.equals("Scanned 120s ago", W.AgeText(1000, 1120, fmt))
        end)

        it("rounds to the nearest minute", function()
            assert.equals("Scanned 60s ago", W.AgeText(1000, 1089, fmt))
            assert.equals("Scanned 180s ago", W.AgeText(1000, 1150, fmt))
            assert.equals("Scanned 3600s ago", W.AgeText(1000, 1000 + 3599, fmt))
        end)

        it("names a summary scan", function()
            assert.equals("Scanned 120s ago (summary)", W.AgeText(1000, 1120, fmt, true))
            assert.equals("Scanned just now (summary)", W.AgeText(1000, 1030, fmt, true))
        end)

        it("says just now within a minute, or if the clock went back", function()
            assert.equals("Scanned just now", W.AgeText(1000, 1030, fmt))
            assert.equals("Scanned just now", W.AgeText(1000, 900, fmt))
        end)
    end)


    describe("EnsureOptions", function()
        it("defaults to the currency view, crates sorted by cost per Favor", function()
            _G.AltArmyTBC_Options = nil
            local o = W.EnsureOptions()
            assert.equals("currency", o.activeView)
            assert.equals("perFavor", o.waylaidSortKey)
            assert.is_true(o.waylaidSortAscending)
            assert.equals("perRep", o.writsSortKey)
            assert.is_true(o.writsSortAscending)
            assert.is_false(o.writsOnlyCraftable)
            assert.is_true(o.writsOnlyAvailable)
            assert.is_true(o.waylaidOnlyAvailable)
            assert.is_false(o.waylaidOnlyCraftable)
            assert.is_true(o.itemTooltips)
            assert.same({}, o.waylaidHiddenTiers)
            assert.same({}, o.writsHiddenTiers)
            assert.equals(o, AltArmyTBC_Options.economy)
        end)

        it("keeps the levels hidden, dropping bad entries", function()
            _G.AltArmyTBC_Options = { economy = { waylaidHiddenTiers = { Apprentice = true, Bogus = true,
                Expert = false }, writsHiddenTiers = "nope" } }
            local o = W.EnsureOptions()
            assert.same({ Apprentice = true }, o.waylaidHiddenTiers)
            assert.same({}, o.writsHiddenTiers)
        end)

        it("keeps item tooltips turned off", function()
            _G.AltArmyTBC_Options = { economy = { itemTooltips = false } }
            assert.is_false(W.EnsureOptions().itemTooltips)
        end)

        it("keeps the writs view and its choices", function()
            _G.AltArmyTBC_Options = { economy = { activeView = "writs", writsSortKey = "rep",
                writsSortAscending = false, writsOnlyCraftable = true } }
            local o = W.EnsureOptions()
            assert.equals("writs", o.activeView)
            assert.equals("rep", o.writsSortKey)
            assert.is_false(o.writsSortAscending)
            assert.is_true(o.writsOnlyCraftable)
            _G.AltArmyTBC_Options.economy.writsSortKey = "who" -- a column that is gone
            assert.equals("perRep", W.EnsureOptions().writsSortKey)
        end)

        it("keeps the availability filters turned off, and drops the old writs key", function()
            _G.AltArmyTBC_Options = { economy = { writsOnlyAvailable = false, waylaidOnlyAvailable = false,
                writsHideUnavailable = false } }
            local o = W.EnsureOptions()
            assert.is_false(o.writsOnlyAvailable)
            assert.is_false(o.waylaidOnlyAvailable)
            assert.is_nil(o.writsHideUnavailable)
        end)

        it("keeps saved choices and repairs bad ones", function()
            _G.AltArmyTBC_Options = { economy = { activeView = "supply", waylaidSortKey = "bogus",
                waylaidSortAscending = false } }
            local o = W.EnsureOptions()
            assert.equals("supply", o.activeView)
            assert.equals("perFavor", o.waylaidSortKey)
            assert.is_false(o.waylaidSortAscending)
            _G.AltArmyTBC_Options.economy.activeView = "nope"
            assert.equals("currency", W.EnsureOptions().activeView)
            _G.AltArmyTBC_Options.economy.activeView = "waylaid"
            assert.equals("waylaid", W.EnsureOptions().activeView)
            _G.AltArmyTBC_Options.economy.waylaidSortKey = "total" -- the column Cost / Favor replaced
            assert.equals("perFavor", W.EnsureOptions().waylaidSortKey)
        end)
    end)

    describe("SearchTerms", function()
        it("searches the crate, then the bundle it is bought with at its count", function()
            local tin = { name = "Tin Ore", count = 20, cost = 100 }
            local row = { name = "Waylaid Crate: Apprentice Ore", best = "buy", bundle = tin, options = {
                tin,
                { name = "Copper Ore", count = 20, cost = 200 },
            } }
            assert.same({
                { searchString = "Waylaid Crate: Apprentice Ore", quantity = 1, isExact = true },
                { searchString = "Tin Ore", quantity = 20, isExact = true },
            }, W.SearchTerms(row))
        end)

        it("searches what a craft buys when the fill is crafted", function()
            local row = { name = "Waylaid Crate: Expert Ingots", best = "craft",
                bundle = { name = "Gold Bar", count = 10 }, steps = {
                    { kind = "ah", item = 5, qty = 10, cost = 500 },
                    { kind = "craft", item = 3, qty = 10, casts = 10, who = "Miner", spell = 500 },
                } }
            assert.same({
                { searchString = "Waylaid Crate: Expert Ingots", quantity = 1, isExact = true },
                { searchString = "Gold Ore", quantity = 10, isExact = true },
            }, W.SearchTerms(row, { [5] = { name = "Gold Ore" } }))
        end)

        it("searches only the crate when no fill can be had", function()
            assert.same({ { searchString = "Waylaid Crate: Apprentice Ore", quantity = 1, isExact = true } },
                W.SearchTerms({ name = "Waylaid Crate: Apprentice Ore", options = {
                    { name = "Tin Ore", count = 20, listed = 5 },
                } }))
        end)

        it("searches only the crate when it has no bundles", function()
            assert.same({ { searchString = "Waylaid Crate", quantity = 1, isExact = true } },
                W.SearchTerms({ name = "Waylaid Crate", random = true, options = {} }))
        end)
    end)
end)
