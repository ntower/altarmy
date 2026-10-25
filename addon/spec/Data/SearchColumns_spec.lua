--[[
  Unit tests for SearchColumns.lua (search result table column alignment).
]]

describe("SearchColumns", function()
    local SC

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("SearchColumns")
        SC = AltArmy.SearchColumns
    end)

    it("aligns item and recipe name columns", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Item"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Recipe")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Item, SC.RECIPE_COLUMN_WIDTHS.Recipe)
    end)

    it("aligns item and recipe character columns", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Character"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Character")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Character, SC.RECIPE_COLUMN_WIDTHS.Character)
    end)

    it("aligns item Total column with recipe Skill column", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Total"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Skill")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Total, SC.RECIPE_COLUMN_WIDTHS.Skill)
    end)

    it("reports aligned layouts via AreResultColumnsAligned", function()
        assert.is_true(SC.AreResultColumnsAligned())
    end)

    it("uses the same total width for item and recipe tables", function()
        assert.are.equal(SC.GetItemTableWidth(), SC.GetRecipeTableWidth())
    end)

    it("uses a first-column width that fills the closed-settings viewport", function()
        -- Main 670 − content insets 16 → 654; listViewport = 654 − inner pad 8 − scroll gutter 20.
        -- Closed: first column 40px narrower, character 40px wider than the prior even split.
        assert.are.equal(344, SC.ITEM_COLUMN_WIDTHS.Item)
        assert.are.equal(344, SC.RECIPE_COLUMN_WIDTHS.Recipe)
        assert.are.equal(210, SC.ITEM_COLUMN_WIDTHS.Character)
        assert.are.equal(210, SC.RECIPE_COLUMN_WIDTHS.Character)
        assert.are.equal(626, SC.GetResultsTableWidth(false))
    end)

    it("shrinks the first column when settings are open", function()
        assert.are.equal(145, SC.GetItemColumnWidths(true).Item)
        assert.are.equal(145, SC.GetRecipeColumnWidths(true).Recipe)
        assert.are.equal(199, SC.SETTINGS_FIRST_COLUMN_SHRINK)
    end)

    it("shrinks the character column when settings are open", function()
        assert.are.equal(188, SC.GetItemColumnWidths(true).Character)
        assert.are.equal(188, SC.GetRecipeColumnWidths(true).Character)
        assert.are.equal(22, SC.SETTINGS_CHARACTER_COLUMN_SHRINK)
    end)

    it("keeps columns aligned when settings are open", function()
        assert.is_true(SC.AreResultColumnsAlignedForSettings(true))
        assert.are.equal(SC.GetItemTableWidth(true), SC.GetRecipeTableWidth(true))
    end)
    it("fits the first column to the viewport width when settings are closed", function()
        local item = SC.GetItemColumnWidths(false, 560)
        local recipe = SC.GetRecipeColumnWidths(false, 560)
        assert.are.equal(560 - 210 - 72, item.Item)
        assert.are.equal(item.Item, recipe.Recipe)
        assert.are.equal(560, SC.GetResultsTableWidth(false, 560))
    end)

    it("never fits the first column below its minimum", function()
        assert.are.equal(SC.MIN_FIRST_COLUMN_WIDTH, SC.GetItemColumnWidths(false, 100).Item)
    end)

    it("gives the character column a third of a wider viewport, the first column the rest", function()
        -- 776 = stock 626 + 150 extra: Character 210 + 50, Item the remainder.
        local item = SC.GetItemColumnWidths(false, 776)
        assert.are.equal(260, item.Character)
        assert.are.equal(776 - 260 - 72, item.Item)
        assert.are.equal(776, SC.GetResultsTableWidth(false, 776))
        assert.are.equal(item.Character, SC.GetRecipeColumnWidths(false, 776).Character)
    end)

    it("caps the character column", function()
        assert.are.equal(SC.MAX_CHARACTER_WIDTH, SC.GetItemColumnWidths(false, 2000).Character)
        assert.are.equal(300, SC.MAX_CHARACTER_WIDTH)
    end)

    it("fits the columns to the viewport while settings are open too", function()
        -- Open stock 145 + 188 + 72 = 405; at 560 the extra 155 goes a third to Character, the rest to Item.
        local item = SC.GetItemColumnWidths(true, 560)
        assert.are.equal(188 + 51, item.Character)
        assert.are.equal(560 - 239 - 72, item.Item)
        assert.are.equal(560, SC.GetResultsTableWidth(true, 560))
        assert.is_true(SC.AreResultColumnsAlignedForSettings(true, 560))
    end)

    it("never fits the first column below its open-settings stock width", function()
        assert.are.equal(145, SC.GetItemColumnWidths(true, 300).Item)
        assert.are.equal(188, SC.GetItemColumnWidths(true, 300).Character)
    end)
end)
