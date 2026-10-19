-- AltArmy TBC — Economy tab, Currency view: rows, sorting and formatting for the currency × character grid.
-- Pure: reads char.CurrencyList and the account-wide details DataStoreCurrencies saves (CurrencyMeta).
-- luacheck: globals AltArmyTBC_Options

if not AltArmy then return end

AltArmy.CurrencyGrid = AltArmy.CurrencyGrid or {}
local G = AltArmy.CurrencyGrid

-- The Gold row (character money, not a native currency) sits at the top, above every header.
G.GOLD_ID = "gold"
G.GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Currencies we have amounts for but no details (name, group) go in this group, last.
G.OTHER_HEADER = "Other"
local OTHER_HEADER_ORDER = math.huge

--- The Currency view's saved state (column pin/hide, score sort and character filter), repaired and created
--- on first use.
function G.EnsureSettings()
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    if type(AltArmyTBC_Options.economy) ~= "table" then
        AltArmyTBC_Options.economy = {}
    end
    local s = AltArmyTBC_Options.economy.currency
    if type(s) ~= "table" then
        s = {}
        AltArmyTBC_Options.economy.currency = s
    end
    if type(s.showSelfFirst) ~= "boolean" then s.showSelfFirst = true end
    if type(s.scoreSortDescending) ~= "boolean" then s.scoreSortDescending = true end
    if type(s.characters) ~= "table" then s.characters = {} end
    if AltArmy.CharacterFilter then AltArmy.CharacterFilter.Ensure(s) end
    return s
end

--- Grid rows: every currency any of `charDatas` has an amount for, grouped under header rows in the
--- native Currency tab's order. opts.gold adds a Gold row first when there is any character.
--- @return table[] { isHeader = true, name } and { currencyID, name, icon, max, isGold }
function G.BuildRows(charDatas, meta, opts)
    meta = meta or {}
    local ids = {}
    for _, char in ipairs(charDatas or {}) do
        if type(char) == "table" and type(char.CurrencyList) == "table" then
            for id in pairs(char.CurrencyList) do
                ids[id] = true
            end
        end
    end

    local groups, groupList = {}, {}
    for id in pairs(ids) do
        local m = meta[id]
        local header = m and m.header or G.OTHER_HEADER
        local headerOrder = m and m.header and m.headerOrder or OTHER_HEADER_ORDER
        local group = groups[header]
        if not group then
            group = { name = header, order = headerOrder, rows = {} }
            groups[header] = group
            groupList[#groupList + 1] = group
        elseif headerOrder < group.order then
            group.order = headerOrder
        end
        group.rows[#group.rows + 1] = {
            currencyID = id,
            name = m and m.name or ("#" .. tostring(id)),
            icon = m and m.icon,
            max = m and m.max,
            order = m and m.order or math.huge,
        }
    end

    table.sort(groupList, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    local rows = {}
    if opts and opts.gold and charDatas and #charDatas > 0 then
        rows[1] = { currencyID = G.GOLD_ID, name = "Gold", icon = G.GOLD_ICON, isGold = true, order = 0 }
    end
    for _, group in ipairs(groupList) do
        table.sort(group.rows, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.currencyID < b.currencyID
        end)
        rows[#rows + 1] = { isHeader = true, name = group.name }
        for _, r in ipairs(group.rows) do
            rows[#rows + 1] = r
        end
    end
    return rows
end

--- Keep only currencies whose name contains `filterText` (trimmed, case-insensitive, plain text; the
--- Reputation faction filter's rule). A header stays only while one of its currencies does.
function G.FilterRows(rows, filterText)
    local needle = ((filterText or ""):match("^%s*(.-)%s*$") or ""):lower()
    if needle == "" then return rows end
    local out = {}
    local pendingHeader = nil
    for _, r in ipairs(rows or {}) do
        if r.isHeader then
            pendingHeader = r
        elseif string.find((r.name or ""):lower(), needle, 1, true) then
            if pendingHeader then
                out[#out + 1] = pendingHeader
                pendingHeader = nil
            end
            out[#out + 1] = r
        end
    end
    return out
end


--- Column comparator: sort characters by their amount of one currency; no data sorts last.
--- @param amountOf function(entry) -> number|nil
--- @param tieBreak function(a, b) -> boolean
function G.CompareByAmount(entryA, entryB, amountOf, highFirst, tieBreak)
    local va, vb = amountOf(entryA), amountOf(entryB)
    if (va == nil) ~= (vb == nil) then return va ~= nil end
    if va ~= nil and va ~= vb then
        if highFirst then return va > vb end
        return va < vb
    end
    return tieBreak(entryA, entryB)
end

--- Money as display strings, most detailed first: gold silver copper, then without copper, then
--- without silver ("12,345g 67s 89c", "12,345g 67s", "12,345g"). Leading zero parts are skipped (as
--- SummaryData.GetMoneyString does) and at least one part is kept. The caller shows the first that fits.
--- @param icons table { gold, silver, copper } suffix per part (coin textures in game)
function G.MoneyVariants(copper, icons)
    if copper == nil then return { "—" } end
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local parts = {}
    if gold > 0 then parts[#parts + 1] = G.FormatAmount(gold) .. icons.gold end
    if gold > 0 or silver > 0 then parts[#parts + 1] = silver .. icons.silver end
    parts[#parts + 1] = (copper % 100) .. icons.copper
    local out = {}
    for n = #parts, 1, -1 do
        out[#out + 1] = table.concat(parts, " ", 1, n)
    end
    return out
end

--- "1,500"; a dash when there is no amount.
function G.FormatAmount(n)
    if n == nil then return "—" end
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if grouped:sub(1, 1) == "," then grouped = grouped:sub(2) end
    return sign .. grouped
end
