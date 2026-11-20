--[[ Unit tests for InventoryOptions.lua (Inventory tab saved state) — run: npm test ]]

describe("InventoryOptions", function()
    local IO

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["InventoryOptions"] = nil
        require("InventoryOptions")
        IO = AltArmy.InventoryOptions
        assert.truthy(IO)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = nil
    end)

    describe("EnsureOptions", function()
        it("creates the table with defaults", function()
            local o = IO.EnsureOptions()
            assert.are.equal(o, AltArmyTBC_Options.inventory)
            assert.are.equal("blocks", o.bagLayout)
            assert.are.equal("blocks", o.bankLayout)
            assert.are.equal("rows", o.mailLayout)
        end)

        it("keeps valid values and repairs invalid ones", function()
            _G.AltArmyTBC_Options = { inventory = {
                activeView = "mail", bagLayout = "combined", bankLayout = "nope", mailLayout = "grid",
            } }
            local o = IO.EnsureOptions()
            assert.are.equal("combined", o.bagLayout)
            assert.are.equal("blocks", o.bankLayout)
            assert.are.equal("grid", o.mailLayout)
        end)

        it("leaves keys it does not own alone", function()
            _G.AltArmyTBC_Options = { inventory = { somethingElse = 1 } }
            assert.are.equal(1, IO.EnsureOptions().somethingElse)
        end)
    end)

    describe("mail combine stacks", function()
        it("defaults to off, keeps a boolean and repairs anything else", function()
            assert.is_false(IO.EnsureOptions().mailCombineStacks)
            _G.AltArmyTBC_Options = { inventory = { mailCombineStacks = true } }
            assert.is_true(IO.EnsureOptions().mailCombineStacks)
            _G.AltArmyTBC_Options = { inventory = { mailCombineStacks = "yes" } }
            assert.is_false(IO.EnsureOptions().mailCombineStacks)
        end)
    end)

    describe("mail sort", function()
        it("defaults to latest expiry first and repairs bad values", function()
            local o = IO.EnsureOptions()
            assert.are.same({ "expires", false }, { o.mailSortKey, o.mailSortAscending })
            _G.AltArmyTBC_Options = { inventory = { mailSortKey = "colour", mailSortAscending = "yes" } }
            o = IO.EnsureOptions()
            assert.are.same({ "expires", false }, { o.mailSortKey, o.mailSortAscending })
            _G.AltArmyTBC_Options = { inventory = { mailSortKey = "money", mailSortAscending = 1 } }
            o = IO.EnsureOptions()
            assert.are.same({ "money", false }, { o.mailSortKey, o.mailSortAscending })
        end)

        it("ClickMailSort flips the same column and switches to another with its natural direction", function()
            local o = IO.EnsureOptions()
            assert.is_true(IO.ClickMailSort(o, "expires"))
            assert.is_true(o.mailSortAscending)
            assert.is_true(IO.ClickMailSort(o, "subject"))
            assert.are.same({ "subject", true }, { o.mailSortKey, o.mailSortAscending })
            assert.is_true(IO.ClickMailSort(o, "money"))
            assert.are.same({ "money", false }, { o.mailSortKey, o.mailSortAscending })
            assert.is_false(IO.ClickMailSort(o, "items"))
            assert.is_false(IO.ClickMailSort(nil, "money"))
        end)
    end)

    describe("layouts", function()
        it("maps each view to its option key", function()
            assert.are.equal("bagLayout", IO.LayoutKey("bags"))
            assert.are.equal("bankLayout", IO.LayoutKey("bank"))
            assert.are.equal("mailLayout", IO.LayoutKey("mail"))
            assert.is_nil(IO.LayoutKey("gear"))
        end)

        it("GetLayout returns the stored layout or the view's default", function()
            local o = IO.EnsureOptions()
            assert.are.equal("blocks", IO.GetLayout(o, "bank"))
            o.bankLayout = "combined"
            assert.are.equal("combined", IO.GetLayout(o, "bank"))
            assert.are.equal("rows", IO.GetLayout({}, "mail"))
            assert.are.equal("blocks", IO.GetLayout(nil, "bags"))
            assert.is_nil(IO.GetLayout(o, "gear"))
        end)

        it("SetLayout accepts only the view's layouts", function()
            local o = IO.EnsureOptions()
            assert.is_true(IO.SetLayout(o, "mail", "grid"))
            assert.are.equal("grid", o.mailLayout)
            assert.is_false(IO.SetLayout(o, "mail", "combined"))
            assert.are.equal("grid", o.mailLayout)
            assert.is_false(IO.SetLayout(o, "bags", "rows"))
            assert.is_false(IO.SetLayout(nil, "bags", "blocks"))
        end)

        it("LayoutEntries lists a view's layouts in order with labels", function()
            local entries = IO.LayoutEntries("bags")
            assert.are.same({ "blocks", "combined" }, { entries[1].id, entries[2].id })
            assert.are.equal("Per bag", entries[1].label)
            assert.are.equal("Combined bags", entries[2].label)
            assert.are.equal("Inbox view", IO.LayoutEntries("mail")[1].label)
            assert.are.equal("Combined items", IO.LayoutEntries("mail")[2].label)
            assert.are.same({}, IO.LayoutEntries("gear"))
        end)
    end)
end)
