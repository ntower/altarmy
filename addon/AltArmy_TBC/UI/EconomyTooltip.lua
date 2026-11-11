-- AltArmy TBC — what a Waylaid Crate or a Craftsman's Writ costs, in its tooltip: the Economy tab's rows
-- (Tabs/TabEconomy.lua, Tabs/TabEconomyWrits.lua) and, on WoW Forever, every other item tooltip (bags, bank,
-- links, other addons' bags) unless turned off in Options -> General -> Economy
-- (AltArmyTBC_Options.economy.itemTooltips). Rows: Data/Economy/WaylaidCosts.lua and WritCosts.lua, from
-- the newest auction house scan of the player's realm and faction; no scan, no lines.
-- luacheck: globals GameTooltip ItemRefTooltip TooltipDataProcessor Enum GetServerTime C_CurrencyInfo

if not AltArmy then return end

AltArmy.EconomyTooltip = AltArmy.EconomyTooltip or {}
local ET = AltArmy.EconomyTooltip

-- The greyed-out text (the dearer way, the bundles not picked): as dark as the hints.
local DIM = 0.5
local DIM_CODE = "|cff808080"
local ICON_SIZE = 14
-- The scan age line's colours: grey within the hour, orange after.
ET.FRESH_COLOR = { 0.5, 0.5, 0.5 }
ET.OLD_COLOR = { 1, 0.5, 0.15 }
-- How long a built row is reused while its scan is the newest (characters' recipes, bags and quest log move).
ET.CACHE_SECONDS = 30

--- True while the Economy tab sets a row's item on the tooltip: the item hook then adds nothing (the tab adds
--- the same lines itself).
ET.suppress = false

local function Money(copper)
    if copper == nil then return "—" end
    local SD = AltArmy.SummaryData
    if copper < 0 then return "-" .. SD.GetMoneyString(-copper) end
    return SD.GetMoneyString(copper)
end

--- "~" before a cost that rests on an estimate, or on units the auction house is short of.
local function Mark(approx, short)
    return (approx or (short or 0) > 0) and "~" or ""
end

local function MoneyMarked(copper, approx, short)
    if copper == nil then return "—" end
    return Mark(approx, short) .. Money(copper)
end

--- A character's name in their class colour (white when their class isn't known).
local function CharName(name, classOf)
    local CC = AltArmy.ClassColor
    if not CC then return name end
    return CC.formatName(name, classOf and classOf[name])
end

-- Merchant's Favor (currency 3402): its icon from the game, else the one Forever gives it.
local FAVOR_CURRENCY, FAVOR_ICON = 3402, 135725
function ET.FavorIcon()
    local CI = C_CurrencyInfo
    local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(FAVOR_CURRENCY)
    local icon = info and info.iconFileID or FAVOR_ICON
    return "|T" .. icon .. ":" .. ICON_SIZE .. ":" .. ICON_SIZE .. ":0:0|t"
end

local function ItemName(items, itemID)
    local entry = items and items[itemID]
    return entry and entry.name or ("item " .. tostring(itemID))
end

--- A step's tooltip line: its text, and its cost (nil for a craft: it costs nothing more). Counts read "3x"
--- (a craft's is its casts). `plain`: names without their class colour (a greyed-out line).
local function StepText(step, items, classOf, plain)
    local name = ItemName(items, step.item)
    local who = plain and step.who or CharName(step.who, classOf)
    if step.kind == "craft" then
        return "Craft " .. step.casts .. "x " .. name .. " on " .. who, nil
    end
    local left = "Buy " .. step.qty .. "x " .. name
    if step.kind == "vendor" then
        left = left .. " from a vendor on " .. who
    else
        left = left .. " on the auction house"
    end
    return left, MoneyMarked(step.cost, step.approx, step.short)
end

--- A tooltip cost line: the cost in white, or "n/a" in grey when there is none.
local function AddCostLine(tt, label, cost)
    if cost then
        tt:AddDoubleLine(label, cost, 1, 1, 1, 1, 1, 1)
    else
        tt:AddDoubleLine(label, "n/a", 1, 1, 1, 0.7, 0.7, 0.7)
    end
end

--- A fulfil line with no way to fulfil that way: label and "n/a" both grey, as a dearer way's line is.
local function AddUnavailableLine(tt, label)
    tt:AddDoubleLine(label, "n/a", DIM, DIM, DIM, DIM, DIM, DIM)
end

--- A bundle's tooltip line: what it costs on the auction house and to craft, or why it can't be had.
--- With both prices, the dearer one is grey (a tie greys the craft, as on the fulfil lines).
local function BundleText(opt)
    local both = opt.cost and opt.craft
    local parts = {}
    if opt.cost then
        local text = "AH " .. MoneyMarked(opt.cost, opt.approx)
        if both and opt.best ~= "buy" then text = DIM_CODE .. text .. "|r" end
        parts[#parts + 1] = text
    elseif opt.listed > 0 then
        parts[#parts + 1] = "only " .. opt.listed .. " listed"
    else
        parts[#parts + 1] = "not listed"
    end
    if opt.craft then
        local text = "craft " .. MoneyMarked(opt.craft, opt.craftApprox, opt.craftShort)
        if both and opt.best ~= "craft" then text = DIM_CODE .. text .. "|r" end
        parts[#parts + 1] = text
    end
    return table.concat(parts, ", ")
end

--- The blank line that parts our lines from the item's own.
local function AddHead(tt)
    tt:AddLine(" ")
end

--- Last, the scan's age in parentheses ("(Scanned 12 min ago)", ", summary scan" after a summary scan): grey
--- within the hour, orange once the scan is over an hour old (WaylaidCosts.IsOldData).
local function AddAge(tt, opts, afterHint)
    if not (opts.scanTime and opts.now) then return end
    local W = AltArmy.WaylaidCosts
    local text = W.AgeText(opts.scanTime, opts.now, AltArmy.SummaryData.GetTimeString)
    if opts.summary then text = text .. ", summary scan" end
    local c = W.IsOldData(opts.scanTime, opts.now) and ET.OLD_COLOR or ET.FRESH_COLOR
    if not afterHint then tt:AddLine(" ") end -- under the Auctionator hint, the two grey lines go together
    tt:AddLine("(" .. text .. ")", c[1], c[2], c[3])
end

--- "Click to search with Auctionator" at the end, when asked (the Economy tab's rows) and Auctionator can.
local function AddClickHint(tt, opts)
    local AZ = AltArmy.AuctionatorSearch
    if opts.clickHint and AZ and AZ.IsAvailable() then
        tt:AddLine(" ")
        tt:AddLine("Click to search with Auctionator", 0.5, 0.5, 0.5)
        return true
    end
    return false
end

--- A Waylaid Crate row's lines (WaylaidCosts.BuildRow), after the item's own. `opts`: `classOf` (character
--- name -> class file), `scanTime`, `now` (server time) and `summary` for the age line, `clickHint`.
function ET.AddCrateLines(tt, rd, opts)
    opts = opts or {}
    local classOf = opts.classOf
    local items = AltArmy.WaylaidCrates and AltArmy.WaylaidCrates.ITEMS
    AddHead(tt)
    if rd.favor then
        tt:AddDoubleLine("Turn-in reward", rd.favor .. " " .. ET.FavorIcon() .. " and " .. Money(rd.goldBack),
            1, 0.82, 0, 1, 1, 1)
    end
    AddCostLine(tt, "Crate on the auction house", rd.price and Money(rd.price))
    if rd.random then
        tt:AddLine("Its shipment is random until you read the label, so there is no fill cost.",
            0.7, 0.7, 0.7, true)
    else
        -- With both ways priced, the dearer line is grey, label and cost (a tie greys the craft: the row buys);
        -- its crafter's name then loses the class colour, which would show through the grey.
        local both = rd.buy and rd.craft
        local buyC = both and rd.best ~= "buy" and DIM or 1
        local craftC = both and rd.best ~= "craft" and DIM or 1
        if rd.buy then
            tt:AddDoubleLine("Fill via AH", MoneyMarked(rd.buy, rd.buyApprox), buyC, buyC, buyC,
                buyC, buyC, buyC)
        else
            AddUnavailableLine(tt, "Fill via AH")
        end
        if rd.craft then
            local who = craftC < 1 and rd.who or CharName(rd.who, classOf)
            tt:AddDoubleLine("Fill via craft on " .. who,
                MoneyMarked(rd.craft, rd.craftApprox, rd.craftShort), craftC, craftC, craftC, craftC, craftC, craftC)
        else
            AddUnavailableLine(tt, "Fill via craft")
        end
        if rd.total then
            tt:AddDoubleLine("Total cost", Money(rd.total), 1, 0.82, 0, 1, 1, 1)
            tt:AddDoubleLine("Total cost per " .. ET.FavorIcon(), Money(rd.perFavor), 1, 0.82, 0, 1, 1, 1)
        end
        if #rd.options > 0 then
            tt:AddLine(" ")
            tt:AddLine("Fill it with any one of these bundles:", 1, 0.82, 0)
            for _, opt in ipairs(rd.options) do
                local left = opt.count .. " x " .. opt.name
                -- Only the cheapest bundle is white: the others are grey, name and costs.
                local c = opt == rd.bundle and 1 or DIM
                tt:AddDoubleLine(left, BundleText(opt), c, c, c, c, c, c)
            end
        end
        if rd.best == "craft" then
            tt:AddLine(" ")
            tt:AddLine("To craft " .. rd.bundle.count .. "x " .. rd.bundle.name .. ":", 1, 0.82, 0)
            for _, step in ipairs(rd.steps or {}) do
                local left, right = StepText(step, items, classOf)
                if right then
                    tt:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
                else
                    tt:AddLine(left, 1, 1, 1)
                end
            end
        end
        if rd.best == "craft" and (rd.craftShort or 0) > 0 then
            tt:AddLine(" ")
            tt:AddLine("~ " .. rd.craftShort .. " unit(s) are not listed: priced at the dearest listing.",
                0.9, 0.6, 0.2, true)
        end
    end
    AddAge(tt, opts, AddClickHint(tt, opts))
end

--- A Craftsman's Writ row's lines (WritCosts.BuildRow), after the item's own. `opts` as AddCrateLines'.
function ET.AddWritLines(tt, rd, opts)
    opts = opts or {}
    local classOf = opts.classOf
    local items = AltArmy.Writs and AltArmy.Writs.ITEMS
    AddHead(tt)
    tt:AddLine("Wants " .. rd.count .. "x " .. ItemName(items, rd.item), 1, 0.82, 0, true)
    tt:AddDoubleLine(rd.tier .. " writ", "+" .. rd.rep .. " reputation", 1, 1, 1, 1, 1, 1)
    tt:AddLine(" ")
    AddCostLine(tt, "Writ on the auction house", rd.writPrice and Money(rd.writPrice))
    -- With both ways priced, the dearer line is grey, label and cost (a tie greys the craft: the writ buys),
    -- and so are the craft's steps when crafting is the dearer way; a greyed line's names lose their class
    -- colour, which would show through the grey.
    local both = rd.buy and rd.craft
    local buyC = both and rd.best ~= "buy" and DIM or 1
    local craftC = both and rd.best ~= "craft" and DIM or 1
    if rd.buy then
        tt:AddDoubleLine("Fill via AH", MoneyMarked(rd.buy, rd.buyApprox, rd.buyShort),
            buyC, buyC, buyC, buyC, buyC, buyC)
    else
        AddUnavailableLine(tt, "Fill via AH")
    end
    if rd.craft then
        local who = craftC < 1 and rd.who or CharName(rd.who, classOf)
        tt:AddDoubleLine("Fill via craft on " .. who,
            MoneyMarked(rd.craft, rd.craftApprox, rd.craftShort), craftC, craftC, craftC, craftC, craftC, craftC)
    else
        AddUnavailableLine(tt, "Fill via craft")
    end
    if rd.bestCost and rd.writPrice then
        tt:AddDoubleLine("Total cost", Money(rd.bestCost + rd.writPrice), 1, 0.82, 0, 1, 1, 1)
        if rd.perRep then
            tt:AddDoubleLine("Total cost per rep", Money(rd.perRep), 1, 0.82, 0, 1, 1, 1)
        end
    end
    if rd.craft then
        tt:AddLine(" ")
        local r, g, b = 1, 0.82, 0
        if craftC < 1 then r, g, b = craftC, craftC, craftC end
        tt:AddLine("To craft " .. rd.count .. "x " .. ItemName(items, rd.item) .. ":", r, g, b)
        for _, step in ipairs(rd.steps or {}) do
            local left, right = StepText(step, items, classOf, craftC < 1)
            if right then
                tt:AddDoubleLine(left, right, craftC, craftC, craftC, craftC, craftC, craftC)
            else
                tt:AddLine(left, craftC, craftC, craftC)
            end
        end
    end
    local short = (rd.best == "craft" and rd.craftShort or rd.buyShort) or 0
    if short > 0 then
        tt:AddLine(" ")
        tt:AddLine("~ " .. short .. " unit(s) are not listed: priced at the dearest listing.",
            0.9, 0.6, 0.2, true)
    elseif rd.best and (rd.best == "craft" and rd.craftApprox or rd.buyApprox) then
        tt:AddLine(" ")
        tt:AddLine("~ An estimate: the scan folded the dearer listings together.", 0.9, 0.6, 0.2, true)
    end
    AddAge(tt, opts, AddClickHint(tt, opts))
end

--- Set `itemID` on `tt` for the Economy tab: the item hook stays out of it, since the tab adds the lines.
function ET.SetItem(tt, itemID)
    ET.suppress = true
    tt:SetItemByID(itemID)
    ET.suppress = false
end

-- Rows built for the item hook, reused while their scan is the newest and for CACHE_SECONDS.
local cache = { scan = nil, book = nil, rows = {} }

function ET.ResetCache()
    cache.scan, cache.book, cache.rows = nil, nil, {}
end

local function Now()
    return GetServerTime and GetServerTime() or time()
end

--- The crate's or writ's row from the newest scan of the player's realm and faction, with the scan and the
--- characters' classes; nil when `itemID` is neither or there is no scan.
function ET.Lookup(itemID, now)
    local Crates, Writs = AltArmy.WaylaidCrates, AltArmy.Writs
    local crate = Crates and Crates.ById and Crates.ById[itemID]
    local writ = not crate and Writs and Writs.ById and Writs.ById[itemID]
    if not (crate or writ) then return nil end
    local Book = AltArmy.AuctionBook
    if not Book then return nil end
    local realm = GetRealmName and GetRealmName() or ""
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    local scan = Book.Newest(realm, faction)
    if not scan then return nil end
    if cache.scan ~= scan then
        cache.scan, cache.book, cache.rows = scan, Book.Decode(scan.items), {}
    end
    local hit = cache.rows[itemID]
    if hit and now - hit.at <= ET.CACHE_SECONDS then
        return hit.kind, hit.row, scan, hit.classOf
    end
    local CX = AltArmy.CraftContext
    local ctx, classOf
    if CX and AltArmy.CraftPlan and AltArmy.DataStore then
        ctx, classOf = CX.Build(AltArmy.DataStore, realm, faction, cache.book, crate and Crates or Writs)
    end
    local kind, row
    if crate then
        kind, row = "crate", AltArmy.WaylaidCosts.BuildRow(crate, cache.book, scan.summary, ctx)
    else
        if not ctx then return nil end -- WritCosts.BuildRow needs the context
        local orders = AltArmy.WritOrders and AltArmy.WritOrders.Orders() or nil
        kind, row = "writ", AltArmy.WritCosts.BuildRow(writ, cache.book, orders, ctx)
    end
    cache.rows[itemID] = { kind = kind, row = row, classOf = classOf or {}, at = now }
    return kind, row, scan, classOf or {}
end

--- The item id `tt` shows, from its link (or the tooltip data's id, when the client hands it over).
local function TooltipItemID(tt, data)
    if type(data) == "table" and type(data.id) == "number" then return data.id end
    if not tt.GetItem then return nil end
    local _, link = tt:GetItem()
    local id = link and link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

--- The item hook: a crate's or writ's costs after its own lines, unless the setting is off, the Economy tab
--- is the one setting it, or there is no scan.
function ET.OnTooltipItem(tt, data)
    if ET.suppress or not tt or not tt.AddLine then return end
    local W = AltArmy.WaylaidCosts
    if not (W and W.EnsureOptions().itemTooltips) then return end
    local itemID = TooltipItemID(tt, data)
    if not itemID then return end
    local now = Now()
    local kind, row, scan, classOf = ET.Lookup(itemID, now)
    if not kind then return end
    local opts = { classOf = classOf, scanTime = scan.t, now = now, summary = scan.summary }
    if kind == "crate" then
        ET.AddCrateLines(tt, row, opts)
    else
        ET.AddWritLines(tt, row, opts)
    end
    tt:Show() -- resize to the lines added
end

--- Hook every item tooltip (WoW Forever only: crates and writs, and the full scan, exist only there).
function ET.Install()
    if ET.installed then return end
    local DS = AltArmy.DataStore
    if not (DS and DS.IsWowForever == true) then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ET.OnTooltipItem)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                tt:HookScript("OnTooltipSetItem", function(self) ET.OnTooltipItem(self) end)
            end
        end
    end
    ET.installed = true
end

ET.Install()
