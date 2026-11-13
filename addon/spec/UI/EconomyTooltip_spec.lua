--[[
  Unit tests for EconomyTooltip.lua (Waylaid Crate and Craftsman's Writ costs in item tooltips).
  Run from project root: npm test
]]

describe("EconomyTooltip", function()
    local ET, W

    --- A tooltip that records what is added to it.
    local function fakeTooltip(itemID)
        local tt = { lines = {}, shown = 0 }
        function tt:AddLine(text, r, g, b)
            self.lines[#self.lines + 1] = { left = text, r = r, g = g, b = b }
        end
        function tt:AddDoubleLine(left, right, r, g, b, rr, rg, rb)
            self.lines[#self.lines + 1] = { left = left, right = right, r = r, g = g, b = b,
                rr = rr, rg = rg, rb = rb }
        end
        function tt:Show() self.shown = self.shown + 1 end
        function tt:GetItem()
            if not itemID then return nil end
            return "Item", "|cffffffff|Hitem:" .. itemID .. "::::::::60:::::|h[Item]|h|r"
        end
        function tt:SetItemByID(id)
            self.item = id
            if ET.OnTooltipItem then ET.OnTooltipItem(self) end
        end
        return tt
    end

    local function texts(tt)
        local out = {}
        for _, l in ipairs(tt.lines) do out[#out + 1] = l.left end
        return out
    end

    local function firstText(tt)
        for _, l in ipairs(tt.lines) do
            if l.left ~= " " then return l end
        end
    end

    local function hasLine(tt, needle)
        for _, l in ipairs(tt.lines) do
            if type(l.left) == "string" and l.left:find(needle, 1, true) then return true end
        end
        return false
    end

    local CRATE = { id = 901, name = "Waylaid Crate: Apprentice Ore", short = "Apprentice Ore", tier = "Apprentice",
        kind = "Gathered", bundles = { { item = 2, count = 20, name = "Tin Ore" } } }
    local WRIT = { id = 264047, quest = 94247, tier = "Journeyman", rep = 75, items = { 12 }, count = 1,
        name = "Craftsman's Writ: Robe", short = "Robe" }
    local scan

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["CraftPlan"] = nil
        package.loaded["WaylaidCosts"] = nil
        package.loaded["WritCosts"] = nil
        require("CraftPlan")
        require("WaylaidCosts")
        require("WritCosts")
        W = AltArmy.WaylaidCosts
        AltArmy.SummaryData = {
            GetMoneyString = function(c) return c .. "c" end,
            GetTimeString = function(s) return math.floor(s / 3600) .. " hr" end,
        }
        AltArmy.WaylaidCrates = { LIST = { CRATE }, ById = { [901] = CRATE },
            ITEMS = { [2] = { name = "Tin Ore", stack = 20 } }, RECIPES = {}, ByOutput = {} }
        AltArmy.Writs = { LIST = { WRIT }, ById = { [264047] = WRIT },
            ITEMS = { [12] = { name = "Robe", stack = 1 } }, RECIPES = {}, ByOutput = {} }
        AltArmy.CraftContext = {
            Build = function(_, _, _, book, data)
                return { book = book, items = data.ITEMS, recipes = data.RECIPES, byOutput = data.ByOutput,
                    current = "Me", knownBy = function() return nil end, discountOf = function() return 0 end,
                    heldBy = function() return 0 end }, {}
            end,
        }
        AltArmy.AuctionBook = {
            Newest = function() return scan end,
            Decode = function(items) return items end,
        }
        AltArmy.DataStore = {}
        _G.GetRealmName = function() return "Realm" end
        _G.UnitFactionGroup = function() return "Horde" end
        package.loaded["EconomyTooltip"] = nil
        require("EconomyTooltip")
        ET = AltArmy.EconomyTooltip
        assert.truthy(ET)
    end)

    local NOW = 100000

    before_each(function()
        _G.AltArmyTBC_Options = nil
        _G.GetServerTime = function() return NOW end
        scan = { t = NOW - 30, items = {
            [901] = { { price = 1000, units = 1, listings = 1 } },
            [2] = { { price = 30, units = 25, listings = 1 } },
            [264047] = { { price = 500, units = 1, listings = 1 } },
            [12] = { { price = 900, units = 2, listings = 1 } },
        } }
        ET.ResetCache()
    end)

    describe("OnTooltipItem", function()
        it("adds a crate's costs to a bag tooltip, without the Auctionator hint", function()
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            assert.is_true(hasLine(tt, "Turn-in reward"))
            assert.is_true(hasLine(tt, "Fill via AH"))
            assert.is_false(hasLine(tt, "Auctionator"))
            assert.is_true(tt.shown > 0)
        end)

        it("ends with the scan's age in parentheses, grey within the hour", function()
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            local last = tt.lines[#tt.lines]
            assert.equals("(Scanned just now)", last.left)
            assert.same({ 0.5, 0.5, 0.5 }, { last.r, last.g, last.b })
        end)

        it("names a summary scan in the age line", function()
            scan.summary = true
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            assert.equals("(Scanned just now, summary scan)", tt.lines[#tt.lines].left)
        end)

        it("adds a writ's costs", function()
            local tt = fakeTooltip(264047)
            ET.OnTooltipItem(tt)
            assert.is_true(hasLine(tt, "Wants 1x Robe"))
            assert.is_true(hasLine(tt, "Writ on the auction house"))
        end)

        it("lays a writ out as a crate: the reward, the costs, then the total less the pouch", function()
            local tt = fakeTooltip(264047)
            ET.OnTooltipItem(tt)
            local at, right, line = {}, {}, {}
            for i, l in ipairs(tt.lines) do
                at[l.left] = at[l.left] or i
                right[l.left] = l.right
                line[l.left] = l
            end
            assert.equals("75 reputation and ~3300c", right["Turn-in reward"])
            -- 900 bought + 500 for the writ - 3300 back: a gain, in green
            assert.equals("gain ~1900c", right["Total cost"])
            assert.equals("gain ~25c", right["Total cost per rep"])
            assert.same({ 0.1, 1, 0.1 }, { line["Total cost"].rr, line["Total cost"].rg, line["Total cost"].rb })
            assert.is_true(at["Turn-in reward"] < at["Writ on the auction house"])
            assert.is_true(at["Writ on the auction house"] < at["Fill via AH"])
            assert.is_true(at["Fill via AH"] < at["Total cost"])
        end)

        it("turns the age line orange when the scan is over an hour old", function()
            scan.t = NOW - 2 * 3600
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            local last = tt.lines[#tt.lines]
            assert.equals("(Scanned 2 hr ago)", last.left)
            assert.same({ 1, 0.5, 0.15 }, { last.r, last.g, last.b })
        end)

        it("adds nothing without an auction house scan", function()
            scan = nil
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            assert.same({}, texts(tt))
        end)

        it("adds nothing when turned off in the options", function()
            _G.AltArmyTBC_Options = { economy = { itemTooltips = false } }
            local tt = fakeTooltip(901)
            ET.OnTooltipItem(tt)
            assert.same({}, texts(tt))
        end)

        it("adds nothing for other items", function()
            local tt = fakeTooltip(12345)
            ET.OnTooltipItem(tt)
            assert.same({}, texts(tt))
            local none = fakeTooltip(nil)
            ET.OnTooltipItem(none)
            assert.same({}, texts(none))
        end)
    end)

    describe("SetItem", function()
        it("leaves the item's own tooltip to the Economy tab, even with the option on", function()
            local tt = fakeTooltip(901)
            ET.SetItem(tt, 901)
            assert.equals(901, tt.item)
            assert.same({}, texts(tt))
        end)
    end)

    describe("AddCrateLines", function()
        it("puts the Auctionator hint just above the age line when asked and Auctionator can search", function()
            AltArmy.AuctionatorSearch = { IsAvailable = function() return true end }
            local rd = W.BuildRow(CRATE, scan.items, false, nil)
            local tt = fakeTooltip(901)
            ET.AddCrateLines(tt, rd, { scanTime = scan.t, now = NOW, clickHint = true })
            assert.equals("Click to search with Auctionator", tt.lines[#tt.lines - 1].left)
            assert.equals("(Scanned just now)", tt.lines[#tt.lines].left)
            AltArmy.AuctionatorSearch = nil
        end)

        it("starts with a blank line, then the reward", function()
            local rd = W.BuildRow(CRATE, scan.items, false, nil)
            local tt = fakeTooltip(901)
            ET.AddCrateLines(tt, rd, { scanTime = NOW - 3601, now = NOW })
            assert.equals(" ", tt.lines[1].left)
            assert.equals("Turn-in reward", firstText(tt).left)
        end)
    end)
end)
