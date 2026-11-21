--[[ Unit tests for SnipeOrder.lua (Economy tab: which Auctionator search comes first) — run: npm test ]]

describe("SnipeOrder", function()
    local S

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["SnipeOrder"] = nil
        require("SnipeOrder")
        S = AltArmy.SnipeOrder
        assert.truthy(S)
    end)

    local function lv(price, units, tail)
        return { price = price, units = units, listings = 1, tail = tail == true }
    end

    describe("Value", function()
        it("is what the quantity costs more once a thin cheap block before a price jump is gone", function()
            -- 3 crates at 10g, then 16g: one crate costs 6g more without them.
            assert.equals(60000, S.Value({ lv(100000, 3), lv(160000, 5) }, 1))
        end)

        it("counts only the units the quantity takes from the cheap block", function()
            -- 4 at 40c then 50c, 10 wanted: 4 * 40 + 6 * 50 = 460 now, 500 without them.
            assert.equals(40, S.Value({ lv(40, 4), lv(50, 300) }, 10))
        end)

        it("takes the block as every level before the first jump", function()
            -- 2 at 100 and 1 at 105 (no jump between them), then 200.
            assert.equals(100, S.Value({ lv(100, 2), lv(105, 1), lv(200, 9) }, 1))
        end)

        it("measures the jump from the level before, not the lowest price", function()
            -- 100, then 108 (+8%), then 112 (+3.7% on 108, though +12% on 100): no jump.
            assert.equals(0, S.Value({ lv(100, 1), lv(108, 1), lv(112, 10) }, 1))
        end)

        it("ends the block at a level 10% above the one before", function()
            assert.equals(10, S.Value({ lv(100, 1), lv(110, 10) }, 1))
            assert.equals(0, S.Value({ lv(100, 1), lv(109, 10) }, 1))
        end)

        it("is nothing on a smooth ladder", function()
            assert.equals(0, S.Value({ lv(50, 100), lv(51, 100), lv(52, 100) }, 10))
        end)

        it("is nothing when the cheap block is deep: nobody buys it out first", function()
            -- 300 at 50c, then 80c: far more than 10 wanted.
            assert.equals(0, S.Value({ lv(50, 300), lv(80, 50) }, 10))
        end)

        it("is nothing with one price level (a summary scan, or one listing)", function()
            assert.equals(0, S.Value({ lv(100, 3) }, 1))
        end)

        it("is nothing without a ladder or a quantity", function()
            assert.equals(0, S.Value(nil, 1))
            assert.equals(0, S.Value({ lv(100, 1), lv(200, 1) }, 0))
        end)

        it("is nothing when the whole ladder can't fill the quantity", function()
            assert.equals(0, S.Value({ lv(100, 2), lv(200, 1) }, 5))
        end)

        it("is infinite when the rest of the ladder can't fill the quantity without the block", function()
            assert.equals(math.huge, S.Value({ lv(40, 8), lv(80, 1) }, 5))
        end)
    end)

    describe("Order", function()
        local function t(name, item, qty)
            return { searchString = name, quantity = qty, isExact = true, item = item }
        end

        it("puts the biggest snipe first and keeps the rest in their order", function()
            local book = {
                [1] = { lv(100, 50), lv(101, 50) },     -- the crate: smooth
                [2] = { lv(10, 2), lv(20, 100) },       -- a reagent: 2 cheap, 10 wanted -> 20
                [3] = { lv(1000, 1), lv(2000, 10) },    -- the bundle: 1 cheap, 1 wanted -> 1000
            }
            local out = S.Order({ t("Crate", 1, 1), t("Reagent", 2, 10), t("Bundle", 3, 1) }, book)
            assert.same({ "Bundle", "Reagent", "Crate" }, { out[1].searchString, out[2].searchString,
                out[3].searchString })
        end)

        it("drops the item field Auctionator doesn't take", function()
            local out = S.Order({ t("Crate", 1, 1) }, {})
            assert.same({ { searchString = "Crate", quantity = 1, isExact = true } }, out)
        end)

        it("keeps the order without a book", function()
            local out = S.Order({ t("A", 1, 1), t("B", 2, 1) }, nil)
            assert.same({ "A", "B" }, { out[1].searchString, out[2].searchString })
        end)
    end)
end)
