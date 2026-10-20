--[[
  Unit tests for SearchListModel.lua: flattens Search result sections into ScrollBox elements.
]]

describe("SearchListModel", function()
    local Model, Sticky

    local METRICS = { headerHeight = 18, headerRowGap = 3, rowHeight = 20 }

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Tabs/?.lua"
        package.loaded["SearchStickyHeaders"] = nil
        package.loaded["SearchListModel"] = nil
        require("SearchStickyHeaders")
        require("SearchListModel")
        Model = AltArmy.SearchListModel
        Sticky = AltArmy.SearchStickyHeaders
    end)

    local function item(id, name, count)
        return { itemID = id, itemName = name, count = count }
    end

    it("returns no elements when every section is empty", function()
        local elements = Model.Build({
            { id = "items", list = {} },
            { id = "recipes", list = {} },
        }, METRICS)
        assert.are.same({}, elements)
    end)

    it("emits a header spacer then one row per entry for each non-empty section", function()
        local items = { item(1, "A", 1), item(2, "B", 1) }
        local recipes = { { recipeID = 7 } }
        local elements = Model.Build({
            { id = "items", list = items, grouped = true },
            { id = "recipes", list = recipes },
        }, METRICS)
        assert.are.equal(5, #elements)
        assert.are.equal("header", elements[1].kind)
        assert.are.equal("items", elements[1].sectionId)
        assert.are.equal(21, elements[1].extent)
        assert.are.equal("row", elements[2].kind)
        assert.are.equal(items[1], elements[2].entry)
        assert.are.equal(20, elements[2].extent)
        assert.are.equal("header", elements[4].kind)
        assert.are.equal("recipes", elements[4].sectionId)
        assert.are.equal("recipes", elements[5].sectionId)
        assert.are.equal(recipes[1], elements[5].entry)
    end)

    it("skips empty sections entirely", function()
        local elements = Model.Build({
            { id = "items", list = {} },
            { id = "recipes", list = { { recipeID = 1 } } },
        }, METRICS)
        assert.are.equal(2, #elements)
        assert.are.equal("recipes", elements[1].sectionId)
    end)

    it("adds gapBefore to the header spacer extent", function()
        local elements = Model.Build({
            { id = "recipes", list = { { recipeID = 1 } } },
            { id = "tooltip", list = { item(3, "C", 1) }, gapBefore = 2 },
        }, METRICS)
        assert.are.equal(23, elements[3].extent)
    end)

    it("header spacers start exactly where SearchStickyHeaders places each header", function()
        local sections = {
            { id = "items", list = { item(1, "A", 1), item(1, "A", 2), item(2, "B", 1) }, grouped = true },
            { id = "recipes", list = { { recipeID = 1 }, { recipeID = 2 } } },
            { id = "tooltip", list = { item(5, "E", 1) }, grouped = true, gapBefore = 2 },
        }
        local elements = Model.Build(sections, METRICS)
        local stickySections = {}
        for i, s in ipairs(sections) do
            stickySections[i] = { id = s.id, rowCount = #s.list, gapBefore = s.gapBefore }
        end
        local headerTops = Sticky.ComputeSectionLayout(
            stickySections, METRICS.headerHeight, METRICS.headerRowGap, METRICS.rowHeight)
        local top, h = 0, 0
        for _, el in ipairs(elements) do
            if el.kind == "header" then
                h = h + 1
                assert.are.equal(headerTops[h], top + (el.gapBefore or 0))
            end
            top = top + el.extent
        end
        assert.are.equal(3, h)
    end)

    it("groups consecutive rows of the same item and totals their counts", function()
        local items = { item(1, "A", 2), item(1, "A", 3), item(2, "B", 1), item(1, "A", 4) }
        local elements = Model.Build({ { id = "items", list = items, grouped = true } }, METRICS)
        local g1, g2, g3 = elements[2].group, elements[4].group, elements[5].group
        assert.are.equal(g1, elements[3].group)
        assert.are.equal(5, g1.total)
        assert.are.equal(items[1], g1.firstEntry)
        assert.are.equal(1, g2.total)
        -- Non-adjacent repeat starts a new group.
        assert.are_not.equal(g1, g3)
        assert.are.equal(4, g3.total)
    end)

    it("omitFirstHeader drops only the first section's header spacer", function()
        local elements = Model.Build({
            { id = "items", list = { item(1, "A", 1) }, grouped = true },
            { id = "recipes", list = { { recipeID = 1 } } },
        }, { headerHeight = 18, headerRowGap = 3, rowHeight = 20, omitFirstHeader = true })
        assert.are.equal(3, #elements)
        assert.are.equal("row", elements[1].kind)
        assert.are.equal("header", elements[2].kind)
        assert.are.equal("recipes", elements[2].sectionId)
    end)

    it("treats a missing count as 1 and leaves ungrouped sections without groups", function()
        local elements = Model.Build({
            { id = "items", list = { item(1, "A", nil) }, grouped = true },
            { id = "recipes", list = { { recipeID = 1 } } },
        }, METRICS)
        assert.are.equal(1, elements[2].group.total)
        assert.is_nil(elements[4].group)
    end)
    it("gives each element and group its list offset", function()
        local elements = Model.Build({
            { id = "items", list = { item(1, "A", 1), item(1, "A", 2), item(2, "B", 1) }, grouped = true },
            { id = "recipes", list = { { recipeID = 1 } } },
        }, { headerHeight = 18, headerRowGap = 3, rowHeight = 20, omitFirstHeader = true })
        assert.are.same({ 0, 20, 40, 60, 81 }, {
            elements[1].top, elements[2].top, elements[3].top, elements[4].top, elements[5].top,
        })
        assert.are.equal(0, elements[1].group.top)
        assert.are.equal(40, elements[1].group.bottom)
        assert.are.equal(40, elements[3].group.top)
        assert.are.equal(60, elements[3].group.bottom)
    end)

    describe("PinnedCenter", function()
        -- A 200px group, content 20px tall.
        it("centers on the group while it is wholly in view", function()
            assert.are.equal(100, Model.PinnedCenter(0, 200, -50, 300, 20))
        end)

        it("slides with the scroll, then pins inside the view's top edge", function()
            assert.are.equal(110, Model.PinnedCenter(0, 200, 100, 300, 20))
            assert.are.equal(160, Model.PinnedCenter(0, 200, 150, 300, 20))
        end)

        it("pins inside the view's bottom edge", function()
            assert.are.equal(70, Model.PinnedCenter(0, 200, -200, 80, 20))
        end)

        it("leaves the view with the group's last row", function()
            assert.are.equal(190, Model.PinnedCenter(0, 200, 195, 400, 20))
            assert.are.equal(190, Model.PinnedCenter(0, 200, 250, 400, 20))
            assert.are.equal(10, Model.PinnedCenter(0, 200, -400, 5, 20))
        end)
    end)
end)
