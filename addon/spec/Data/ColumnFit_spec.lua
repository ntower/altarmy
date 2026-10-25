--[[ Unit tests for ColumnFit.lua (table columns that share a wider window) — run: npm test ]]

describe("ColumnFit", function()
    local CF

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["ColumnFit"] = nil
        require("ColumnFit")
        CF = AltArmy.ColumnFit
    end)

    local stock = { name = 190, favor = 36, price = 100 }
    local order = { "name", "favor", "price" }

    describe("Fit", function()
        it("returns the stock widths at the stock total", function()
            local w = CF.Fit(stock, { name = 1 }, 326)
            assert.are.same({ name = 190, favor = 36, price = 100 }, w)
        end)

        it("returns the stock widths when the viewport is narrower (no shrinking)", function()
            local w = CF.Fit(stock, { name = 1 }, 200)
            assert.are.same({ name = 190, favor = 36, price = 100 }, w)
        end)

        it("gives one flex column all the extra", function()
            local w = CF.Fit(stock, { name = 1 }, 426)
            assert.are.same({ name = 290, favor = 36, price = 100 }, w)
        end)

        it("shares the extra by ratio, floored", function()
            local w = CF.Fit(stock, { name = 0.6, price = 0.4 }, 427) -- extra 101
            assert.are.equal(190 + 60, w.name)
            assert.are.equal(100 + 40, w.price)
            assert.are.equal(36, w.favor)
        end)

        it("holds a capped column at its cap and drops the rest", function()
            local w = CF.Fit(stock, { name = 0.5, price = 0.5 }, 526, { price = 120 }) -- extra 200
            assert.are.equal(290, w.name)
            assert.are.equal(120, w.price)
        end)

        it("ignores flex keys the widths lack and never mutates its input", function()
            local w = CF.Fit(stock, { name = 0.5, ghost = 0.5 }, 426)
            assert.are.equal(240, w.name)
            assert.is_nil(w.ghost)
            assert.are.equal(190, stock.name)
        end)

        it("treats a missing or non-positive width as the stock total", function()
            assert.are.same(stock, CF.Fit(stock, { name = 1 }, nil))
            assert.are.same(stock, CF.Fit(stock, { name = 1 }, 0))
        end)
    end)

    describe("Total", function()
        it("sums the widths in order", function()
            assert.are.equal(326, CF.Total(order, stock))
        end)

        it("counts a missing column as nothing", function()
            assert.are.equal(226, CF.Total({ "name", "favor", "nope" }, stock))
        end)
    end)
end)
