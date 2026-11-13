--[[ Unit tests for WritCosts.lua (Economy tab, Craftsman's Writs rows) — run: npm test ]]

describe("WritCosts", function()
    local WC, P

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["CraftPlan"] = nil
        package.loaded["WritCosts"] = nil
        require("CraftPlan")
        require("WritCosts")
        WC = AltArmy.WritCosts
        P = AltArmy.CraftPlan
        assert.truthy(WC)
        assert.truthy(P)
    end)

    local function lv(price, units)
        return { price = price, units = units, listings = 1, tail = false }
    end

    -- A robe (craftable), a suit (needs a bind-on-pickup reagent: buy only) and shot (no route at all).
    local ITEMS = {
        [1] = { name = "Robe", stack = 1 },
        [3] = { name = "Cloth", stack = 20 },
        [4] = { name = "Thread", stack = 20, vendor = 100, per = 1 },
        [6] = { name = "Tannin", stack = 20, bop = true },
        [7] = { name = "Suit", stack = 1 },
        [8] = { name = "Shot", stack = 200 },
        [12] = { name = "Robe", stack = 1 },
    }
    local RECIPES = {
        [100] = { out = 1, n = 1, prof = "Tailoring", name = "Robe",
            reagents = { { item = 3, count = 4 }, { item = 4, count = 2 } } },
        [102] = { out = 7, n = 1, prof = "Leatherworking", name = "Suit", reagents = { { item = 6, count = 1 } } },
        [103] = { out = 8, n = 200, prof = "Engineering", name = "Shot", reagents = { { item = 3, count = 1 } } },
        [112] = { out = 12, n = 1, prof = "Tailoring", name = "Robe", reagents = { { item = 3, count = 1 } } },
    }
    local WRITS = { LIST = {
        { id = 264047, quest = 94247, tier = "Journeyman", rep = 75, items = { 1, 12 }, count = 1,
            name = "Craftsman's Writ: Robe", short = "Robe" },
        { id = 264144, quest = 94344, tier = "Artisan", rep = 200, items = { 7 }, count = 1,
            name = "Craftsman's Writ: Suit", short = "Suit" },
        { id = 264037, quest = 94237, tier = "Expert", rep = 125, items = { 8 }, count = 200,
            name = "Craftsman's Writ: Shot", short = "Shot" },
    } }
    local KNOWN = { [100] = "Tailor", [102] = "Leather", [112] = "Tailor" }

    local function context(over)
        local ctx = {
            book = { [1] = { lv(1000, 2) }, [3] = { lv(20, 100) }, [7] = { lv(2000, 1) }, [12] = { lv(900, 2) },
                [264047] = { lv(500, 1), lv(700, 3) }, [264144] = { lv(300, 2) } },
            items = ITEMS, recipes = RECIPES, byOutput = { [1] = { 100 }, [7] = { 102 }, [8] = { 103 }, [12] = { 112 } },
            current = "Me",
            knownBy = function(spell) return KNOWN[spell] end,
            discountOf = function() return 0 end,
            heldBy = function(writID) return writID == 264047 and 2 or 0 end,
        }
        for k, v in pairs(over or {}) do ctx[k] = v end
        return ctx
    end

    local function byId(rows)
        local out = {}
        for _, row in ipairs(rows) do out[row.id] = row end
        return out
    end

    describe("BuildRows", function()
        it("prices buying and crafting every writ's order and picks the better", function()
            local rows = byId(WC.BuildRows(context().book, WRITS, nil, context()))
            local robe = rows[264047]
            assert.equals(900, robe.buy) -- the second Robe's: it is the one priced, crafted for 20
            assert.equals(20, robe.craft) -- one cloth, where the first Robe takes 4 cloth and 2 thread (280)
            assert.equals(12, robe.item)
            assert.equals("craft", robe.best)
            assert.equals(20, robe.bestCost)
            assert.equals("Tailor", robe.who)
            assert.is_true(robe.canCraft)
            assert.is_true(robe.assumed)
            assert.equals(1, robe.count)
            assert.equals(2, robe.held)
            assert.equals(500, robe.writPrice) -- the writ's own cheapest listing
            assert.equals(3300, robe.goldBack) -- a Journeyman's pouch
            assert.equals(-2780, robe.total) -- 20 crafted + 500 for the writ - 3300 back
            assert.equals(-37, robe.perRep) -- -2780 / 75 rep, rounded
            assert.equals("craft", robe.plan.option)
            assert.equals("craft", robe.steps[#robe.steps].kind)

            local suit = rows[264144]
            assert.equals(2000, suit.buy)
            assert.is_nil(suit.craft)
            assert.equals("buy", suit.best)
            assert.is_false(suit.canCraft)
            assert.is_nil(suit.who)
            assert.equals(-15200, suit.total) -- 2000 bought + 300 - an Artisan's 17500
            assert.equals(-76, suit.perRep) -- -15200 / 200 rep

            local shot = rows[264037]
            assert.is_nil(shot.buy)
            assert.is_nil(shot.craft)
            assert.is_nil(shot.best)
            assert.equals(0, shot.held)
            assert.is_nil(shot.writPrice)
            assert.is_nil(shot.total)
            assert.is_nil(shot.perRep)
        end)

        it("takes the order the game told us over the assumed one", function()
            local orders = { [94247] = { item = 1, count = 3, t = 1 } }
            local robe = byId(WC.BuildRows(context().book, WRITS, orders, context()))[264047]
            assert.equals(1, robe.item)
            assert.equals(3, robe.count)
            assert.is_false(robe.assumed)
            assert.equals(3 * (80 + 200), robe.craft)
            assert.equals(1000 + 1000 + 1000, robe.buy) -- two listed, one short
            assert.equals(1, robe.buyShort)
        end)

        it("still plans without a scan", function()
            local rows = byId(WC.BuildRows({}, WRITS, nil, context({ book = {} })))
            assert.is_nil(rows[264047].buy)
            assert.is_nil(rows[264047].craft) -- cloth has no route without the auction house
            assert.is_nil(rows[264144].best)
        end)

        it("does not mark a summary scan's costs as estimates", function()
            local ctx = context({ summary = true })
            local orders = { [94247] = { item = 12, count = 2, t = 1 } }
            local robe = byId(WC.BuildRows(ctx.book, WRITS, orders, ctx))[264047]
            assert.is_false(robe.craftApprox)
            assert.is_false(robe.buyApprox)
        end)
    end)

    describe("BuildRow", function()
        it("builds one writ's row as BuildRows does", function()
            local ctx = context()
            local one = WC.BuildRow(WRITS.LIST[1], ctx.book, nil, ctx)
            local all = byId(WC.BuildRows(ctx.book, WRITS, nil, ctx))[264047]
            assert.equals(all.craft, one.craft)
            assert.equals(all.perRep, one.perRep)
            assert.equals(all.held, one.held)
            assert.equals(all.item, one.item)
        end)
    end)

    describe("Filter", function()
        local function ids(rows)
            local out = {}
            for i, row in ipairs(rows) do out[i] = row.id end
            return out
        end

        it("keeps every row with no filter on", function()
            local rows = WC.BuildRows(context().book, WRITS, nil, context())
            assert.equals(3, #WC.Filter(rows, nil))
            assert.equals(3, #WC.Filter(rows, {}))
        end)

        it("hides the writs nobody can craft", function()
            local rows = WC.BuildRows(context().book, WRITS, nil, context())
            assert.same({ 264047 }, ids(WC.Filter(rows, { hideUncraftable = true })))
        end)

        it("hides writs not listed, or whose order can't be fulfilled either way", function()
            local rows = WC.BuildRows(context().book, WRITS, nil, context())
            assert.same({ 264047, 264144 }, ids(WC.Filter(rows, { hideUnavailable = true })))
            local unlisted = context()
            unlisted.book[264144] = nil -- the Suit writ: its order can be bought, but the writ isn't listed
            rows = WC.BuildRows(unlisted.book, WRITS, nil, unlisted)
            assert.same({ 264047 }, ids(WC.Filter(rows, { hideUnavailable = true })))
        end)

        it("hides the levels unticked", function()
            local rows = WC.BuildRows(context().book, WRITS, nil, context())
            assert.equals(3, #WC.Filter(rows, { hiddenTiers = {} }))
            assert.same({ 264037 }, ids(WC.Filter(rows, { hiddenTiers = { Journeyman = true, Artisan = true } })))
        end)

        it("applies both together", function()
            local rows = WC.BuildRows(context().book, WRITS, nil, context())
            assert.same({ 264047 }, ids(WC.Filter(rows, { hideUncraftable = true, hideUnavailable = true })))
        end)
    end)

    describe("Compare", function()
        local rows
        setup(function()
            rows = WC.BuildRows(context().book, WRITS, nil, context())
        end)

        local function sorted(key, ascending)
            local copy = {}
            for i, row in ipairs(rows) do copy[i] = row end
            table.sort(copy, function(a, b) return WC.Compare(a, b, key, ascending) end)
            local ids = {}
            for i, row in ipairs(copy) do ids[i] = row.id end
            return ids
        end

        it("orders by name for the writ column, whatever the tier", function()
            local rows = {
                { id = 1, tier = "Artisan", short = "Arcanite Rod" },
                { id = 2, tier = "Journeyman", short = "Wizard's Robe" },
                { id = 3, tier = "Expert", short = "Mithril Shot" },
                { id = 4, tier = "Journeyman", short = "Mithril Shot" },
            }
            local function ids(asc)
                table.sort(rows, function(a, b) return WC.Compare(a, b, "writ", asc) end)
                local out = {}
                for _, r in ipairs(rows) do out[#out + 1] = r.id end
                return out
            end
            assert.same({ 1, 4, 3, 2 }, ids(true)) -- a name at two tiers: the lower tier first
            assert.same({ 2, 3, 4, 1 }, ids(false))
        end)

        it("orders money with the unpriced last either way", function()
            assert.same({ 264047, 264144, 264037 }, sorted("best", true))
            assert.same({ 264144, 264047, 264037 }, sorted("best", false))
            assert.same({ 264047, 264037, 264144 }, sorted("craft", true)) -- the uncraftable by tier
            assert.same({ 264144, 264047, 264037 }, sorted("writPrice", true)) -- the unlisted last
            assert.same({ 264047, 264144, 264037 }, sorted("writPrice", false))
        end)

        it("orders reputation and cost per reputation", function()
            assert.same({ 264047, 264037, 264144 }, sorted("rep", true))
            assert.same({ 264144, 264047, 264037 }, sorted("perRep", true))
            assert.same({ 264047, 264144, 264037 }, sorted("perRep", false)) -- the unpriced last either way
        end)
    end)

    describe("SearchTerms", function()
        local function term(s, q) return { searchString = s, quantity = q, isExact = true } end

        it("searches the writ, its order, and what crafting it buys", function()
            local rows = byId(WC.BuildRows(context().book, WRITS, nil, context()))
            assert.same({ term("Craftsman's Writ: Robe", 1), term("Robe", 1), term("Cloth", 1) },
                WC.SearchTerms(rows[264047], ITEMS))
        end)

        it("searches every reagent the plan buys, vendor ones too, each once", function()
            local orders = { [94247] = { item = 1, count = 3, t = 1 } }
            local rows = byId(WC.BuildRows(context().book, WRITS, orders, context()))
            assert.same({ term("Craftsman's Writ: Robe", 1), term("Robe", 3), term("Thread", 6), term("Cloth", 12) },
                WC.SearchTerms(rows[264047], ITEMS))
        end)

        it("searches an item with random suffixes by name, not exactly", function()
            local suffixed = {}
            for id, entry in pairs(ITEMS) do suffixed[id] = entry end
            suffixed[7] = { name = "Suit", stack = 1, suffix = true }
            local rows = byId(WC.BuildRows(context().book, WRITS, nil, context()))
            assert.same({ term("Craftsman's Writ: Suit", 1), { searchString = "Suit", quantity = 1, isExact = false } },
                WC.SearchTerms(rows[264144], suffixed))
        end)

        it("searches just the writ and its order when nobody can craft it", function()
            local rows = byId(WC.BuildRows(context().book, WRITS, nil, context()))
            assert.same({ term("Craftsman's Writ: Suit", 1), term("Suit", 1) }, WC.SearchTerms(rows[264144], ITEMS))
            assert.same({ term("Craftsman's Writ: Shot", 1), term("Shot", 200) }, WC.SearchTerms(rows[264037], ITEMS))
        end)
    end)
end)
