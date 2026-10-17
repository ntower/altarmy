--[[
  Unit tests for NetWorth.lua.
  Run from project root: npm test
]]

describe("NetWorth", function()
    local NW
    local chatMessages
    local vendorPrices
    local ahPrices
    local soulboundLinks
    local accountBoundLinks
    local containerSlots
    local characters

    local function notifyChat(msg)
        table.insert(chatMessages, tostring(msg))
    end

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        local vendor = vendorPrices[id]
        if vendor == nil and not id then return end
        -- name, link, rarity, level, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice
        local name = "Item" .. tostring(id or "?")
        local link = type(item) == "string" and item or ("|cff|Hitem:" .. tostring(id) .. "|h[" .. name .. "]|h|r")
        return name, link, 1, 1, nil, "Misc", "Junk", nil, nil, nil, vendor or 0
    end

    local function reloadModule()
        package.loaded["NetWorth"] = nil
        require("NetWorth")
        NW = AltArmy.NetWorth
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.GetItemInfo = mockGetItemInfo
        _G.GetRealmName = function() return "RealmA" end
        reloadModule()
    end)

    before_each(function()
        chatMessages = {}
        vendorPrices = {}
        ahPrices = {}
        soulboundLinks = {}
        accountBoundLinks = {}
        containerSlots = {}
        characters = {}
        _G.GetRealmName = function() return "RealmA" end

        AltArmy.Debug = {
            NotifyChat = notifyChat,
        }
        AltArmy.SummaryData = {
            GetMoneyString = function(copper)
                return tostring(copper or 0) .. "c"
            end,
        }
        AltArmy.ItemUsability = {
            IsBindOnPickup = function(link)
                return soulboundLinks[link] == true
            end,
        }
        AltArmy.SearchData = {
            GetAllContainerSlots = function()
                return containerSlots
            end,
        }
        AltArmy.DataStore = {
            ForEachCharacter = function(_, fn)
                for _, row in ipairs(characters) do
                    if fn(row.realm, row.name, row.data) == true then
                        break
                    end
                end
            end,
            GetCharacterName = function(_, char)
                return char and char.name
            end,
            GetMoney = function(_, char)
                return (char and char.money) or 0
            end,
        }

        _G.Auctionator = {
            API = {
                v1 = {
                    GetAuctionPriceByItemID = function(_, itemID)
                        return ahPrices[itemID]
                    end,
                    GetAuctionPriceByItemLink = function(_, link)
                        local id = tonumber(tostring(link):match("item:(%d+)"))
                        return id and ahPrices[id] or nil
                    end,
                },
            },
        }

        -- Hook for account-bound detection used by NetWorth
        NW._IsAccountBoundForTests = function(link)
            return accountBoundLinks[link] == true
        end
    end)

    after_each(function()
        NW._IsAccountBoundForTests = nil
        _G.Auctionator = nil
    end)

    describe("IsAuctionatorAvailable", function()
        it("returns true when Auctionator API is present", function()
            assert.is_true(NW.IsAuctionatorAvailable())
        end)

        it("returns false when Auctionator is missing", function()
            _G.Auctionator = nil
            assert.is_false(NW.IsAuctionatorAvailable())
        end)

        it("returns false when v1 price API is missing", function()
            _G.Auctionator = { API = { v1 = {} } }
            assert.is_false(NW.IsAuctionatorAvailable())
        end)
    end)

    describe("ParseArgs", function()
        it("defaults to scale 0.9 and current realm when arg is nil or empty", function()
            local opts = NW.ParseArgs(nil)
            assert.are.equal(0.9, opts.scale)
            assert.is_false(opts.allRealms)

            opts = NW.ParseArgs("")
            assert.are.equal(0.9, opts.scale)
            assert.is_false(opts.allRealms)
        end)

        it("parses a valid scale in [0, 1]", function()
            assert.are.equal(0.85, NW.ParseArgs("0.85").scale)
            assert.are.equal(0, NW.ParseArgs("0").scale)
            assert.are.equal(1, NW.ParseArgs("1").scale)
            assert.is_false(NW.ParseArgs("0.85").allRealms)
        end)

        it("parses all to include every realm", function()
            local opts = NW.ParseArgs("all")
            assert.are.equal(0.9, opts.scale)
            assert.is_true(opts.allRealms)

            opts = NW.ParseArgs("all 0.85")
            assert.are.equal(0.85, opts.scale)
            assert.is_true(opts.allRealms)

            opts = NW.ParseArgs("0.75 all")
            assert.are.equal(0.75, opts.scale)
            assert.is_true(opts.allRealms)
        end)

        it("rejects invalid tokens and out-of-range scale", function()
            local opts, err = NW.ParseArgs("abc")
            assert.is_nil(opts)
            assert.is_truthy(err)

            opts, err = NW.ParseArgs("1.5")
            assert.is_nil(opts)
            assert.is_truthy(err)

            opts, err = NW.ParseArgs("all nope")
            assert.is_nil(opts)
            assert.is_truthy(err)
        end)
    end)

    describe("GetItemUnitValue", function()
        it("uses vendor price only for soulbound items", function()
            local link = "|Hitem:10|h[Bound]|h"
            soulboundLinks[link] = true
            vendorPrices[10] = 500
            ahPrices[10] = 10000
            assert.are.equal(500, NW.GetItemUnitValue(10, link, 0.9))
        end)

        it("uses vendor price only for account-bound items", function()
            local link = "|Hitem:11|h[BoA]|h"
            accountBoundLinks[link] = true
            vendorPrices[11] = 200
            ahPrices[11] = 8000
            assert.are.equal(200, NW.GetItemUnitValue(11, link, 0.9))
        end)

        it("uses max of vendor and scaled AH for tradeable items", function()
            local link = "|Hitem:20|h[Trade]|h"
            vendorPrices[20] = 100
            ahPrices[20] = 1000
            -- 1000 * 0.9 = 900 > 100
            assert.are.equal(900, NW.GetItemUnitValue(20, link, 0.9))
        end)

        it("falls back to vendor when AH is lower after scale", function()
            local link = "|Hitem:21|h[Trade]|h"
            vendorPrices[21] = 500
            ahPrices[21] = 400
            -- 400 * 0.9 = 360 < 500
            assert.are.equal(500, NW.GetItemUnitValue(21, link, 0.9))
        end)

        it("treats missing AH price as 0", function()
            local link = "|Hitem:22|h[Trade]|h"
            vendorPrices[22] = 50
            assert.are.equal(50, NW.GetItemUnitValue(22, link, 0.9))
        end)
    end)

    describe("Compute", function()
        local function addChar(realm, name, money)
            local data = { name = name, money = money or 0 }
            table.insert(characters, { realm = realm, name = name, data = data })
            return data
        end

        it("sums item values times count plus on-hand gold", function()
            addChar("RealmA", "Alice", 1000)
            local link = "|Hitem:30|h[Ore]|h"
            vendorPrices[30] = 10
            ahPrices[30] = 1000
            containerSlots = {
                {
                    characterName = "Alice",
                    realm = "RealmA",
                    itemID = 30,
                    itemLink = link,
                    count = 3,
                },
            }
            -- unit = max(10, 900) = 900; items = 2700; + gold 1000 = 3700
            local rows, total = NW.Compute(0.9)
            assert.are.equal(1, #rows)
            assert.are.equal("Alice", rows[1].name)
            assert.are.equal(3700, rows[1].copper)
            assert.are.equal(3700, total)
        end)

        it("sorts characters by net worth ascending", function()
            addChar("RealmA", "Rich", 5000)
            addChar("RealmA", "Poor", 100)
            containerSlots = {}
            local rows = NW.Compute(0.9)
            assert.are.equal("Poor", rows[1].name)
            assert.are.equal("Rich", rows[2].name)
        end)

        it("counts linked accounts' characters, apart from ours of the same name", function()
            addChar("RealmA", "Alice", 100)
            AltArmy.DataStore.ForEachCharacterInScope = function(self, fn)
                self:ForEachCharacter(function(realm, name, data) fn(realm, name, data, nil) end)
                fn("RealmA", "Alice", { name = "Alice", money = 400 }, "acct")
            end
            containerSlots = {}
            local rows, total = NW.Compute(0.9)
            AltArmy.DataStore.ForEachCharacterInScope = nil
            assert.are.equal(2, #rows)
            assert.are.equal(500, total)
        end)

        it("defaults to current realm only", function()
            addChar("RealmA", "Alice", 100)
            addChar("RealmB", "Bob", 200)
            containerSlots = {}
            local rows, total = NW.Compute(0.9)
            assert.are.equal(1, #rows)
            assert.are.equal("Alice", rows[1].name)
            assert.are.equal(100, total)
        end)

        it("includes all realms when allRealms is true", function()
            addChar("RealmA", "Alice", 100)
            addChar("RealmB", "Bob", 200)
            containerSlots = {}
            local rows = NW.Compute(0.9, { allRealms = true })
            assert.are.equal(2, #rows)
            assert.are.equal("Alice-RealmA", rows[1].name)
            assert.are.equal("Bob-RealmB", rows[2].name)
        end)

        it("returns empty when Auctionator is unavailable", function()
            _G.Auctionator = nil
            addChar("RealmA", "Alice", 100)
            local rows, total = NW.Compute(0.9)
            assert.are.equal(0, #rows)
            assert.are.equal(0, total)
        end)
    end)

    describe("PrintSummary", function()
        local function addChar(realm, name, money)
            local data = { name = name, money = money or 0 }
            table.insert(characters, { realm = realm, name = name, data = data })
        end

        it("prints Auctionator required message when missing", function()
            _G.Auctionator = nil
            NW.PrintSummary(0.9)
            assert.are.equal(1, #chatMessages)
            assert.are.equal("Auctionator is required to calculate your net worth", chatMessages[1])
        end)

        it("prints header, sorted rows, separator, and total", function()
            addChar("RealmA", "Alice", 2000)
            addChar("RealmA", "Bob", 500)
            containerSlots = {}
            NW.PrintSummary(0.9)
            assert.are.equal(
                "Networth by character, assuming all items sell at 90% of AH value",
                chatMessages[1]
            )
            assert.are.equal("Bob: 500c", chatMessages[2])
            assert.are.equal("Alice: 2000c", chatMessages[3])
            assert.are.equal("------------", chatMessages[4])
            assert.are.equal("Total: 2500c", chatMessages[5])
        end)

        it("shows custom scale percent in the header", function()
            addChar("RealmA", "Alice", 0)
            containerSlots = {}
            NW.PrintSummary(0.85)
            assert.are.equal(
                "Networth by character, assuming all items sell at 85% of AH value",
                chatMessages[1]
            )
        end)

        it("prints parse error for invalid args and does not print totals", function()
            NW.PrintSummaryFromArg("nope")
            assert.are.equal(1, #chatMessages)
            assert.is_truthy(chatMessages[1])
        end)

        it("all flag includes characters from other realms", function()
            addChar("RealmA", "Alice", 100)
            addChar("RealmB", "Bob", 200)
            containerSlots = {}
            NW.PrintSummaryFromArg("all")
            assert.are.equal("Alice-RealmA: 100c", chatMessages[2])
            assert.are.equal("Bob-RealmB: 200c", chatMessages[3])
            assert.are.equal("Total: 300c", chatMessages[5])
        end)
    end)
end)
