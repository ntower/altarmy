-- AltArmy TBC — Search tab column layout (item and recipe result tables).

AltArmy.SearchColumns = AltArmy.SearchColumns or {}

local SC = AltArmy.SearchColumns

SC.ITEM_COLUMN_ORDER = { "Item", "Character", "Total" }
SC.RECIPE_COLUMN_ORDER = { "Recipe", "Character", "Skill" }

-- Closed-settings total (344+210+72=626) matches listViewport width on the 670px main frame
-- (654 content − 8 inner pad − 20 scroll gutter).
SC.ITEM_COLUMN_WIDTHS = { Item = 344, Character = 210, Total = 72 }
SC.RECIPE_COLUMN_WIDTHS = { Recipe = 344, Character = 210, Skill = 72 }

--- Pixels to subtract from Item/Recipe when the search settings panel is open.
--- Open-settings widths: 145 (Item/Recipe) and 188 (Character).
SC.SETTINGS_FIRST_COLUMN_SHRINK = 199
--- Pixels to subtract from Character when the search settings panel is open.
SC.SETTINGS_CHARACTER_COLUMN_SHRINK = 22

local DEFAULT_COL_WIDTH = 80
--- Floor for the Item/Recipe column when it is fitted to the list viewport with the settings closed.
SC.MIN_FIRST_COLUMN_WIDTH = 200
--- A wider viewport than the table's stock total: the Character column takes this share of the extra
--- (realm and location suffixes get cut off), up to MAX_CHARACTER_WIDTH, and the Item/Recipe column the rest.
SC.CHARACTER_FLEX = 1 / 3
SC.MAX_CHARACTER_WIDTH = 300

local function SumWidths(widths)
    local total = 0
    for _, w in pairs(widths) do
        total = total + w
    end
    return total
end

--- With a known viewport width: size the columns so the table fills it exactly (no horizontal scroll
--- unless it is narrower than the minimums). Character grows by CHARACTER_FLEX of what the viewport has
--- beyond the stock total; firstCol takes what is left, never under minFirst.
local function FitColumns(widths, firstCol, fitWidth, minFirst)
    if not fitWidth or fitWidth <= 0 then
        return widths
    end
    local extra = math.max(0, fitWidth - SumWidths(widths))
    widths.Character = math.min(SC.MAX_CHARACTER_WIDTH,
        widths.Character + math.floor(extra * SC.CHARACTER_FLEX))
    local others = 0
    for name, w in pairs(widths) do
        if name ~= firstCol then
            others = others + w
        end
    end
    widths[firstCol] = math.max(minFirst, math.floor(fitWidth - others))
    return widths
end

local function CopyWidths(widths)
    local out = {}
    for k, v in pairs(widths) do
        out[k] = v
    end
    return out
end

--- The open-settings stock widths: the first column and Character shrunk, the last column as it is.
local function SettingsWidths(widths, firstCol)
    local out = CopyWidths(widths)
    out[firstCol] = widths[firstCol] - SC.SETTINGS_FIRST_COLUMN_SHRINK
    out.Character = widths.Character - SC.SETTINGS_CHARACTER_COLUMN_SHRINK
    return out
end

--- fitWidth (optional): the list viewport's width to fill. Settings closed: from the stock widths, the first
--- column never under MIN_FIRST_COLUMN_WIDTH; open: from the open-settings widths, the first column never
--- under its open-settings stock width (so the stock open layout still fits its viewport).
function SC.GetItemColumnWidths(settingsOpen, fitWidth)
    if not settingsOpen then
        return FitColumns(CopyWidths(SC.ITEM_COLUMN_WIDTHS), "Item", fitWidth, SC.MIN_FIRST_COLUMN_WIDTH)
    end
    local widths = SettingsWidths(SC.ITEM_COLUMN_WIDTHS, "Item")
    return FitColumns(widths, "Item", fitWidth, widths.Item)
end

function SC.GetRecipeColumnWidths(settingsOpen, fitWidth)
    if not settingsOpen then
        return FitColumns(CopyWidths(SC.RECIPE_COLUMN_WIDTHS), "Recipe", fitWidth, SC.MIN_FIRST_COLUMN_WIDTH)
    end
    local widths = SettingsWidths(SC.RECIPE_COLUMN_WIDTHS, "Recipe")
    return FitColumns(widths, "Recipe", fitWidth, widths.Recipe)
end

--- Sum of column widths for a table layout.
function SC.GetTableWidth(order, widths)
    local w = 0
    for _, colName in ipairs(order) do
        w = w + (widths[colName] or DEFAULT_COL_WIDTH)
    end
    return w
end

--- Left edge (x offset) of a column within a table layout.
function SC.GetColumnOffset(order, widths, colName)
    local x = 0
    for _, name in ipairs(order) do
        if name == colName then
            return x
        end
        x = x + (widths[name] or DEFAULT_COL_WIDTH)
    end
    return nil
end

--- Item and recipe result columns share the same horizontal positions (default layout).
function SC.AreResultColumnsAligned()
    return SC.AreResultColumnsAlignedForSettings(false)
end

--- Item and recipe result columns share the same horizontal positions for a layout mode.
function SC.AreResultColumnsAlignedForSettings(settingsOpen, fitWidth)
    local itemWidths = SC.GetItemColumnWidths(settingsOpen, fitWidth)
    local recipeWidths = SC.GetRecipeColumnWidths(settingsOpen, fitWidth)
    local pairs = {
        { "Item", "Recipe" },
        { "Character", "Character" },
        { "Total", "Skill" },
    }
    for _, pair in ipairs(pairs) do
        local itemCol, recipeCol = pair[1], pair[2]
        local itemOffset = SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, itemWidths, itemCol)
        local recipeOffset = SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, recipeWidths, recipeCol)
        if itemOffset ~= recipeOffset then
            return false
        end
        if itemWidths[itemCol] ~= recipeWidths[recipeCol] then
            return false
        end
    end
    return true
end

function SC.GetItemTableWidth(settingsOpen)
    local widths = settingsOpen and SC.GetItemColumnWidths(true) or SC.ITEM_COLUMN_WIDTHS
    return SC.GetTableWidth(SC.ITEM_COLUMN_ORDER, widths)
end

function SC.GetRecipeTableWidth(settingsOpen)
    local widths = settingsOpen and SC.GetRecipeColumnWidths(true) or SC.RECIPE_COLUMN_WIDTHS
    return SC.GetTableWidth(SC.RECIPE_COLUMN_ORDER, widths)
end

function SC.GetResultsTableWidth(settingsOpen, fitWidth)
    if fitWidth or settingsOpen then
        return math.max(
            SC.GetTableWidth(SC.ITEM_COLUMN_ORDER, SC.GetItemColumnWidths(settingsOpen, fitWidth)),
            SC.GetTableWidth(SC.RECIPE_COLUMN_ORDER, SC.GetRecipeColumnWidths(settingsOpen, fitWidth))
        )
    end
    return math.max(SC.GetItemTableWidth(), SC.GetRecipeTableWidth())
end
