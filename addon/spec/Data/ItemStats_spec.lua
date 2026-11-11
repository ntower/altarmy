--[[
  Unit tests for ItemStats.lua.
  Run from project root: npm test
]]

describe("ItemStats", function()
    local IS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [99] = { "Monkey Greaves", nil, 2, 43, 43, "Armor", "Mail", nil, "INVTYPE_FEET" },
            [50] = { "Sparkling Wand", nil, 2, 25, 25, "Weapon", "Wand", nil, "INVTYPE_RANGEDRIGHT" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    local function mockGetItemStats(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id == 11 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
        end
        if id == 10 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
        end
        if id == 50 then
            return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 15.5, ["ITEM_MOD_INTELLECT_SHORT"] = 5 }
        end
        return {}
    end

    local function makeTooltipMock(lineTexts)
        local fontStrings = {}
        for i, text in ipairs(lineTexts) do
            fontStrings[i] = {
                IsObjectType = function(_, t)
                    return t == "FontString"
                end,
                GetText = function()
                    return text
                end,
            }
        end
        return {
            lineTexts = lineTexts,
            SetOwner = function() end,
            ClearLines = function(self)
                self.lineTexts = {}
            end,
            SetHyperlink = function(self, _)
                self.lineTexts = lineTexts
            end,
            GetRegions = function()
                return unpack(fontStrings)
            end,
            NumLines = function(self)
                return #(self.lineTexts or {})
            end,
            GetName = function()
                return "AltArmyTBC_ItemStatsScanTooltip"
            end,
        }
    end

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.ITEM_MOD_AGILITY_SHORT = "Agility"
        _G.ITEM_MOD_STAMINA_SHORT = "Stamina"
        _G.ITEM_MOD_AGILITY = "+ %d Agility"
        _G.ITEM_MOD_STAMINA = "+ %d Stamina"
        _G.CreateFrame = _G.CreateFrame or function(frameType, name)
            if frameType == "GameTooltip" then
                return makeTooltipMock({})
            end
            if frameType == "Frame" then
                return {
                    RegisterEvent = function() end,
                    SetScript = function() end,
                }
            end
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()
        IS.SetOnUpdated(nil)
    end)

    before_each(function()
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.C_Item = nil
        _G.CreateFrame = _G.CreateFrame or function(frameType, name)
            if frameType == "GameTooltip" then
                return makeTooltipMock({})
            end
            if frameType == "Frame" then
                return {
                    RegisterEvent = function() end,
                    SetScript = function() end,
                }
            end
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()
        IS.SetOnUpdated(nil)
    end)

    it("GetNormalized uses GetItemStats API", function()
        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(20, stats.int)
        assert.are.equal(10, stats.sta)
        assert.are.equal("api", IS.GetSource("|Hitem:11:0|h[New Helm]|h"))
    end)

    it("GetNormalizedRef returns cached table without copying", function()
        local link = "|Hitem:11:0|h[New Helm]|h"
        local first = IS.GetNormalizedRef(link)
        local second = IS.GetNormalizedRef(link)
        assert.is_not_nil(first)
        assert.are.equal(first, second)
        assert.are.equal(20, first.int)
    end)

    it("GetNormalized parses wand damage per second from API as ranged_dps", function()
        local stats = IS.GetNormalized("|Hitem:50:0|h[Wand]|h")
        assert.are.equal(15.5, stats.ranged_dps)
        assert.is_nil(stats.dps)
        assert.are.equal(5, stats.int)
    end)

    it("GetNormalized merges weapon DPS from tooltip when API returns other stats", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 60 then
                return { ["ITEM_MOD_STRENGTH_SHORT"] = 20 }
            end
            return mockGetItemStats(link)
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 60 then
                return "War Axe", "|Hitem:60:0|h[War Axe]|h", 3, 60, 60,
                    "Weapon", "Axe", nil, "INVTYPE_WEAPON"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+20 Strength",
                    "(52.5 damage per second)",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:60:0|h[War Axe]|h")
        assert.are.equal(20, stats.str)
        assert.are.equal(52.5, stats.melee_dps)
    end)

    describe("C_Item.GetItemStats fallback (WoW Forever)", function()
        local function reloadWithTooltip(lines)
            _G.CreateFrame = function(frameType)
                if frameType == "GameTooltip" then
                    return makeTooltipMock(lines)
                end
                if frameType == "Frame" then
                    return { RegisterEvent = function() end, SetScript = function() end }
                end
                return {}
            end
            package.loaded["ItemStats"] = nil
            require("ItemStats")
            IS = AltArmy.ItemStats
            IS.ClearCache()
        end

        it("uses C_Item.GetItemStats when the legacy global is missing", function()
            _G.GetItemStats = nil
            _G.C_Item = { GetItemStats = mockGetItemStats }
            reloadWithTooltip({})

            local link = "|Hitem:11:0|h[New Helm]|h"
            local stats = IS.GetNormalized(link)
            assert.are.equal(20, stats.int)
            assert.are.equal(10, stats.sta)
            assert.are.equal("api", IS.GetSource(link))
        end)

        it("still merges weapon DPS from the tooltip on the C_Item path", function()
            _G.GetItemStats = nil
            _G.C_Item = {
                GetItemStats = function() return { ["ITEM_MOD_STRENGTH_SHORT"] = 20 } end,
            }
            _G.GetItemInfo = function(item)
                local id = type(item) == "number" and item
                    or tonumber(tostring(item):match("item:(%d+)"))
                if id == 60 then
                    return "War Axe", "|Hitem:60:0|h[War Axe]|h", 3, 60, 60,
                        "Weapon", "Axe", nil, "INVTYPE_WEAPON"
                end
                return mockGetItemInfo(item)
            end
            reloadWithTooltip({ "+20 Strength", "(52.5 damage per second)" })

            local stats = IS.GetNormalized("|Hitem:60:0|h[War Axe]|h")
            assert.are.equal(20, stats.str)
            assert.are.equal(52.5, stats.melee_dps)
        end)

        it("falls back to tooltip parsing when neither API exists", function()
            _G.GetItemStats = nil
            _G.C_Item = nil
            reloadWithTooltip({
                "+15 Intellect",
                "Equip: Increases damage done by Fire spells and effects by up to 42.",
            })

            local link = "|Hitem:11:0|h[New Helm]|h"
            local stats = IS.GetNormalized(link)
            assert.are.equal(42, stats.fire_sp)
            assert.are.equal("tooltip", IS.GetSource(link))
        end)

        it("prefers the legacy global when both exist", function()
            _G.GetItemStats = mockGetItemStats
            _G.C_Item = {
                GetItemStats = function() return { ["ITEM_MOD_INTELLECT_SHORT"] = 999 } end,
            }
            reloadWithTooltip({})

            local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
            assert.are.equal(20, stats.int)
        end)
    end)

    it("GetNormalized splits spell and physical hit rating from API", function()
        _G.GetItemStats = function()
            return {
                ["ITEM_MOD_HIT_RATING_SHORT"] = 10,
                ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = 12,
            }
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(10, stats.hit)
        assert.are.equal(12, stats.spell_hit)
    end)

    it("GetNormalized parses fire spell damage from tooltip", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+15 Intellect",
                    "Equip: Increases damage done by Fire spells and effects by up to 42.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(42, stats.fire_sp)
    end)

    it("GetNormalized merges API per-school damage key with tooltip school stat", function()
        _G.GetItemStats = function()
            return { ["ITEM_MOD_FIRE_DAMAGE_DONE_SHORT"] = 9, ["RESISTANCE0_NAME"] = 24 }
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "24 Armor",
                    "Equip: Increases damage done by Fire spells and effects by up to 9.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(9, stats.fire_sp)
        assert.is_nil(stats.ITEM_MOD_FIRE_DAMAGE_DONE_SHORT)
        assert.are.equal(24, stats.armor)
    end)

    it("GetNormalized maps API-only per-school damage key to school spell stat", function()
        _G.GetItemStats = function()
            return { ["ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT"] = 12 }
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[New Helm]|h")
        assert.are.equal(12, stats.shadow_sp)
        assert.is_nil(stats.ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT)
    end)

    it("GetNormalized parses +Shadow Damage tooltip line from addon reformatted stats", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "81 Armor",
                    "+59 Shadow Damage",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[Archmage Belt of Shadow Wrath]|h")
        assert.are.equal(81, stats.armor)
        assert.are.equal(59, stats.shadow_sp)
    end)

    it("GetNormalized parses +Shadow Spell Damage tooltip line", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "81 Armor",
                    "+58 Shadow Spell Damage",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:11:0|h[Archmage Belt of Shadow Wrath]|h")
        assert.are.equal(58, stats.shadow_sp)
    end)

    it("GetNormalized parses wand damage per second from tooltip as ranged_dps", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+5 Intellect",
                    "(15.5 damage per second)",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:50:0|h[Wand]|h")
        assert.are.equal(15.5, stats.ranged_dps)
        assert.are.equal(5, stats.int)
        assert.are.equal("tooltip", IS.GetSource("|Hitem:50:0|h[Wand]|h"))
    end)

    it("GetNormalized parses color-coded tooltip lines", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "|cffffffff+10 Agility|r",
                    "+10 Stamina",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:99:0|h[Monkey Greaves]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal("tooltip", IS.GetSource(link))
    end)

    it("GetNormalized normalizes reversed stat order", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({ "Stamina +10", "+8 Agility" })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(8, stats.agi)
        assert.are.equal(10, stats.sta)
    end)

    it("GetNormalized returns pending when item is not cached", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function()
            return nil
        end
        IS.ClearCache()
        local link = "|Hitem:404:0|h[Unknown]|h"
        local stats = IS.GetNormalized(link)
        assert.are.same({}, stats)
        assert.are.equal("pending", IS.GetSource(link))
        _G.GetItemInfo = oldGetItemInfo
    end)

    it("GetNormalized maps RESISTANCE0_NAME to armor", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 99 then
                return { ["RESISTANCE0_NAME"] = 181, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Greaves]|h")
        assert.are.equal(181, stats.armor)
        assert.are.equal(10, stats.sta)
    end)

    it("GetNormalized maps legacy spell damage keys to sp", function()
        _G.GetItemStats = function()
            return { ["ITEM_MOD_SPELL_DAMAGE"] = 42, ["ITEM_MOD_SPELL_DAMAGE_DONE"] = 10 }
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:50:0|h[Wand]|h")
        assert.are.equal(52, stats.sp)
    end)

    it("GetDisplayLabel returns friendly names for normalized keys", function()
        assert.are.equal("Armor", IS.GetDisplayLabel("armor"))
        assert.are.equal("Spell Damage", IS.GetDisplayLabel("sp"))
        assert.are.equal("Spell Damage", IS.GetDisplayLabel("ITEM_MOD_SPELL_DAMAGE"))
        assert.are.equal("Armor", IS.GetDisplayLabel("RESISTANCE0_NAME"))
    end)

    it("GetDisplayLabel falls back to WoW global strings for unmapped keys", function()
        _G.ITEM_MOD_FOO_SHORT = "Bar Stat"
        assert.are.equal("Bar Stat", IS.GetDisplayLabel("ITEM_MOD_FOO_SHORT"))
        _G.ITEM_MOD_FOO_SHORT = nil
    end)

    it("GetNormalized parses armor from tooltip", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Agility",
                    "+10 Stamina",
                    "181 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(181, stats.armor)
    end)

    it("GetNormalized parses green suffix item when API is empty", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Agility",
                    "+10 Stamina",
                    "181 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:99:0|h[Monkey Greaves]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal(181, stats.armor)
        assert.are.equal("tooltip", IS.GetSource(link))
    end)

    it("GetNormalized parses +Healing tooltip line for physician suffix items", function()
        _G.GetItemStats = function() return {} end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 100 then
                return "Feralfen Hood of the Physician", "|Hitem:100:0|h[Feralfen Hood of the Physician]|h",
                    3, 85, 85, "Armor", "Leather", nil, "INVTYPE_HEAD"
            end
            return mockGetItemInfo(item)
        end
        _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing"
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+36 Stamina",
                    "+24 Intellect",
                    "+53 Healing",
                    "100 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:100:0|h[Feralfen Hood of the Physician]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(36, stats.sta)
        assert.are.equal(24, stats.int)
        assert.are.equal(53, stats.heal)
        assert.are.equal(100, stats.armor)
        assert.are.equal("tooltip", IS.GetSource(link))
    end)

    it("GetNormalized replaces API -1 healing sentinel with tooltip value", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 100 then
                return {
                    ["RESISTANCE0_NAME"] = 100,
                    ["ITEM_MOD_STAMINA_SHORT"] = 36,
                    ["ITEM_MOD_INTELLECT_SHORT"] = 24,
                    ["ITEM_MOD_SPELL_HEALING_DONE"] = -1,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 100 then
                return "Feralfen Hood of the Physician", "|Hitem:100:0|h[Feralfen Hood of the Physician]|h",
                    3, 85, 85, "Armor", "Leather", nil, "INVTYPE_HEAD"
            end
            return mockGetItemInfo(item)
        end
        _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing"
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+36 Stamina",
                    "+24 Intellect",
                    "+53 Healing",
                    "100 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:100:0|h[Feralfen Hood of the Physician]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(36, stats.sta)
        assert.are.equal(24, stats.int)
        assert.are.equal(53, stats.heal)
        assert.are.equal(100, stats.armor)
    end)

    -- Ring of Scorn (3235): "-3 Spirit" is a real negative stat, not GetItemStats' -1 sentinel.
    local function loadNegativeStatItem(apiStats, tooltipLines)
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 3235 then return apiStats end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 3235 then
                return "Ring of Scorn", "|Hitem:3235:0|h[Ring of Scorn]|h",
                    2, 25, 20, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock(tooltipLines)
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()
        return IS.GetNormalized("|Hitem:3235:0|h[Ring of Scorn]|h")
    end

    it("GetNormalized keeps a negative stat the tooltip confirms", function()
        local stats = loadNegativeStatItem(
            { ["ITEM_MOD_SPIRIT_SHORT"] = -3, ["ITEM_MOD_STAMINA_SHORT"] = 4 },
            { "Ring of Scorn", "Finger", "+4 Stamina", "-3 Spirit" })
        assert.are.equal(4, stats.sta)
        assert.are.equal(-3, stats.spi)
    end)

    it("GetNormalized reads a negative stat from the tooltip alone", function()
        local stats = loadNegativeStatItem({}, { "Ring of Scorn", "Finger", "+4 Stamina", "-3 Spirit" })
        assert.are.equal(4, stats.sta)
        assert.are.equal(-3, stats.spi)
    end)

    it("GetNormalized keeps a real -1 stat the tooltip confirms", function()
        local stats = loadNegativeStatItem(
            { ["ITEM_MOD_SPIRIT_SHORT"] = -1, ["ITEM_MOD_STAMINA_SHORT"] = 4 },
            { "Ring of Scorn", "Finger", "+4 Stamina", "-1 Spirit" })
        assert.are.equal(4, stats.sta)
        assert.are.equal(-1, stats.spi)
    end)

    it("GetNormalized still drops a negative API stat the tooltip does not show", function()
        local stats = loadNegativeStatItem(
            { ["ITEM_MOD_SPIRIT_SHORT"] = -1, ["ITEM_MOD_STAMINA_SHORT"] = 4 },
            { "Ring of Scorn", "Finger", "+4 Stamina" })
        assert.are.equal(4, stats.sta)
        assert.is_nil(stats.spi)
    end)

    it("GetNormalized parses +Healing when global SHORT is Bonus Healing", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 100 then
                return {
                    ["RESISTANCE0_NAME"] = 100,
                    ["ITEM_MOD_STAMINA_SHORT"] = 36,
                    ["ITEM_MOD_INTELLECT_SHORT"] = 24,
                    ["ITEM_MOD_SPELL_HEALING_DONE"] = -1,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 100 then
                return "Feralfen Hood of the Physician", "|Hitem:100:0|h[Feralfen Hood of the Physician]|h",
                    3, 85, 85, "Armor", "Cloth", nil, "INVTYPE_HEAD"
            end
            return mockGetItemInfo(item)
        end
        _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Bonus Healing"
        _G.ITEM_MOD_SPELL_HEALING_DONE = "Increases healing done by magical spells and effects by up to %s."
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "100 Armor",
                    "+36 Stamina",
                    "+24 Intellect",
                    "+53 Healing",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:100:0|h[Feralfen Hood of the Physician]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(53, stats.heal)
        assert.are.equal(36, stats.sta)
        assert.are.equal(24, stats.int)
        assert.are.equal(100, stats.armor)
    end)

    it("GetNormalized merges suffix stats from tooltip when API returns armor only", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 99 then
                return { ["RESISTANCE0_NAME"] = 181 }
            end
            return {}
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Agility",
                    "+10 Stamina",
                    "181 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:99:0|h[Warmonger's Greaves of the Monkey]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(10, stats.agi)
        assert.are.equal(10, stats.sta)
        assert.are.equal(181, stats.armor)
        assert.are.equal("api", IS.GetSource(link))
    end)

    it("BuildStatParseDebugLines reports api, tooltip, and healing parse details", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 100 then
                return {
                    ["RESISTANCE0_NAME"] = 100,
                    ["ITEM_MOD_SPELL_HEALING_DONE"] = -1,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 100 then
                return "Feralfen Hood of the Physician", "|Hitem:100:0|h[Feralfen Hood of the Physician]|h",
                    3, 85, 85, "Armor", "Leather", nil, "INVTYPE_HEAD"
            end
            return mockGetItemInfo(item)
        end
        _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing"
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+53 Healing",
                    "100 Armor",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:100:0|h[Feralfen Hood of the Physician]|h"
        IS.GetNormalized(link)
        local lines = IS.BuildStatParseDebugLines(link)
        local text = table.concat(lines, "\n")
        assert.is_true(text:find("GetItemStats:", 1, true) ~= nil)
        assert.is_true(text:find("ITEM_MOD_SPELL_HEALING_DONE=-1", 1, true) ~= nil)
        assert.is_true(text:find("+53 Healing [parsed]", 1, true) ~= nil)
        assert.is_true(text:find("healing keys:", 1, true) ~= nil)
        assert.is_true(text:find("normalized heal=53", 1, true) ~= nil)
    end)

    it("GetNormalized maps combined damage and healing equip line to sp and heal", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 22108 then
                return {
                    ["RESISTANCE0_NAME"] = 79,
                    ["ITEM_MOD_INTELLECT_SHORT"] = 12,
                    ["ITEM_MOD_STRENGTH_SHORT"] = 6,
                    ["ITEM_MOD_STAMINA_SHORT"] = 6,
                    ["ITEM_MOD_AGILITY_SHORT"] = 6,
                    ["ITEM_MOD_SPIRIT_SHORT"] = 5,
                    ["ITEM_MOD_SPELL_POWER"] = 4,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 22108 then
                return "Feralheart Bracers", "|Hitem:22108:0|h[Feralheart Bracers]|h",
                    3, 85, 85, "Armor", "Leather", nil, "INVTYPE_WRIST"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Feralheart Bracers",
                    "79 Armor",
                    "+6 Strength",
                    "+6 Agility",
                    "+6 Stamina",
                    "+12 Intellect",
                    "+5 Spirit",
                    "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:22108:0|h[Feralheart Bracers]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(5, stats.sp)
        assert.are.equal(5, stats.heal)
        assert.are.equal(12, stats.int)
    end)

    it("CollectParseSnapshot forceRefresh updates normalized cache", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 22108 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 12,
                    ["ITEM_MOD_SPELL_POWER"] = 4,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 22108 then
                return "Feralheart Bracers", "|Hitem:22108:0|h[Feralheart Bracers]|h",
                    3, 85, 85, "Armor", "Leather", nil, "INVTYPE_WRIST"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+12 Intellect",
                    "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:22108:0|h[Feralheart Bracers]|h"
        IS.GetNormalized(link)

        local snap = IS.CollectParseSnapshot(link, { forceRefresh = true })
        local refreshed = IS.GetNormalized(link)
        assert.are.equal(5, refreshed.sp)
        assert.are.equal(5, refreshed.heal)
        assert.are.equal(snap.normalized.sp, refreshed.sp)
        assert.are.equal(snap.normalized.heal, refreshed.heal)
    end)

    it("GetNormalized parses +Spell Damage and Healing when API spell power is -1", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 24648 then
                return {
                    ["RESISTANCE0_NAME"] = 81,
                    ["ITEM_MOD_INTELLECT_SHORT"] = 18,
                    ["ITEM_MOD_STAMINA_SHORT"] = 28,
                    ["ITEM_MOD_SPELL_POWER"] = -1,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 24648 then
                return "Astralaan Gloves of the Sorcerer",
                    "|Hitem:24648:0|h[Astralaan Gloves of the Sorcerer]|h",
                    2, 85, 85, "Armor", "Cloth", nil, "INVTYPE_HAND"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "81 Armor",
                    "+28 Stamina",
                    "+18 Intellect",
                    "+22 Spell Damage and Healing",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:24648:0|h[Astralaan Gloves of the Sorcerer]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(22, stats.sp)
        assert.are.equal(22, stats.heal)
        assert.are.equal(18, stats.int)
    end)

    -- Staff of the Four Golden Coins: form-only AP is exposed by the client as
    -- ITEM_MOD_MELEE_ATTACK_POWER_SHORT, which must not count as generic ap.
    it("GetNormalized maps form-only attack power to feral_ap, not ap", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 25622 then
                return {
                    ["ITEM_MOD_STRENGTH_SHORT"] = 25,
                    ["ITEM_MOD_MELEE_ATTACK_POWER_SHORT"] = 213,
                    ["ITEM_MOD_STAMINA_SHORT"] = 37,
                    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 57.5,
                    ["ITEM_MOD_AGILITY_SHORT"] = 24,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 25622 then
                return "Staff of the Four Golden Coins",
                    "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h",
                    2, 100, 100, "Weapon", "Staves", nil, "INVTYPE_2HWEAPON"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Staff of the Four Golden Coins",
                    "Two-Hand",
                    "Staff",
                    "156 - 258 Damage",
                    "Speed 3.60",
                    "(57.5 damage per second)",
                    "+25 Strength",
                    "+24 Agility",
                    "+37 Stamina",
                    "Equip: Increases attack power by 214 in Cat, Bear, Dire Bear, and Moonkin forms only.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h"
        local stats = IS.GetNormalized(link)
        assert.is_nil(stats.ap)
        assert.are.equal(214, stats.feral_ap)
        assert.are.equal(25, stats.str)
        assert.are.equal(24, stats.agi)
        assert.are.equal(37, stats.sta)
    end)

    it("GetNormalized keeps generic attack power as ap", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 31733 then
                return {
                    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 51.84,
                    ["ITEM_MOD_ATTACK_POWER_SHORT"] = 13,
                    ["ITEM_MOD_CRIT_RATING"] = 8,
                    ["ITEM_MOD_HIT_RATING"] = 7,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 31733 then
                return "Akuno's Blade", "|Hitem:31733:0|h[Akuno's Blade]|h",
                    2, 100, 100, "Weapon", "Dagger", nil, "INVTYPE_WEAPON"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Akuno's Blade",
                    "Equip: Improves hit rating by 7.",
                    "Equip: Improves critical strike rating by 8.",
                    "Equip: Increases attack power by 14.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:31733:0|h[Akuno's Blade]|h"
        local stats = IS.GetNormalized(link)
        assert.are.equal(13, stats.ap)
        assert.is_nil(stats.feral_ap)
    end)

    it("GetNormalized remaps API melee AP to feral_ap without tooltip", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 25622 then
                return {
                    ["ITEM_MOD_MELEE_ATTACK_POWER_SHORT"] = 213,
                    ["ITEM_MOD_STRENGTH_SHORT"] = 25,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 25622 then
                return "Staff of the Four Golden Coins",
                    "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h",
                    2, 100, 100, "Weapon", "Staves", nil, "INVTYPE_2HWEAPON"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Staff of the Four Golden Coins",
                    "+25 Strength",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h"
        local stats = IS.GetNormalized(link)
        assert.is_nil(stats.ap)
        assert.are.equal(213, stats.feral_ap)
    end)

    it("GetNormalized remaps form-only API attack power when labeled as ATTACK_POWER", function()
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 25622 then
                return {
                    ["ITEM_MOD_ATTACK_POWER_SHORT"] = 213,
                    ["ITEM_MOD_STRENGTH_SHORT"] = 25,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 25622 then
                return "Staff of the Four Golden Coins",
                    "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h",
                    2, 100, 100, "Weapon", "Staves", nil, "INVTYPE_2HWEAPON"
            end
            return mockGetItemInfo(item)
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Staff of the Four Golden Coins",
                    "+25 Strength",
                    "Equip: Increases attack power by 214 in Cat, Bear, Dire Bear, and Moonkin forms only.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local link = "|Hitem:25622:0|h[Staff of the Four Golden Coins]|h"
        local stats = IS.GetNormalized(link)
        assert.is_nil(stats.ap)
        assert.are.equal(214, stats.feral_ap)
    end)

    it("GetNormalized does not double-count mp5 from API POWER_REGEN0 and tooltip MANA_REGENERATION", function()
        -- Repro: Hexxer's Belt / Protectorate Waistband dump — GetItemStats exposes
        -- ITEM_MOD_POWER_REGEN0_SHORT while tooltip parse uses MANA_REGENERATION_SHORT.
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 31472 then
                return {
                    ["RESISTANCE0_NAME"] = 297,
                    ["ITEM_MOD_ATTACK_POWER_SHORT"] = 29,
                    ["ITEM_MOD_POWER_REGEN0_SHORT"] = 3,
                    ["ITEM_MOD_AGILITY_SHORT"] = 26,
                }
            end
            if id == 30342 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 18,
                    ["ITEM_MOD_POWER_REGEN0_SHORT"] = 6,
                    ["ITEM_MOD_STAMINA_SHORT"] = 27,
                    ["ITEM_MOD_SPELL_POWER"] = 20,
                    ["RESISTANCE0_NAME"] = 330,
                }
            end
            return {}
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 31472 then
                return "Hexxer's Belt", "|Hitem:31472:0|h[Hexxer's Belt]|h",
                    2, 69, 69, "Armor", "Mail", nil, "INVTYPE_WAIST"
            end
            if id == 30342 then
                return "Protectorate Waistband", "|Hitem:30342:0|h[Protectorate Waistband]|h",
                    2, 69, 69, "Armor", "Mail", nil, "INVTYPE_WAIST"
            end
            return mockGetItemInfo(item)
        end
        local tooltipById = {
            [31472] = {
                "Hexxer's Belt",
                "297 Armor",
                "+26 Agility",
                "Equip: Increases attack power by 30.",
                "Equip: Restores 4 mana per 5 sec.",
            },
            [30342] = {
                "Protectorate Waistband",
                "330 Armor",
                "+27 Stamina",
                "+18 Intellect",
                "Equip: Increases damage and healing done by magical spells and effects by up to 21.",
                "Equip: Restores 7 mana per 5 sec.",
            },
        }
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                local tip = makeTooltipMock({})
                tip.SetHyperlink = function(self, link)
                    local id = tonumber(tostring(link):match("item:(%d+)"))
                    self.lineTexts = tooltipById[id] or {}
                    local fontStrings = {}
                    for i, text in ipairs(self.lineTexts) do
                        fontStrings[i] = {
                            IsObjectType = function(_, t)
                                return t == "FontString"
                            end,
                            GetText = function()
                                return text
                            end,
                        }
                    end
                    self.GetRegions = function()
                        return unpack(fontStrings)
                    end
                end
                return tip
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local oldStats = IS.GetNormalized("|Hitem:31472:0|h[Hexxer's Belt]|h")
        local newStats = IS.GetNormalized("|Hitem:30342:0|h[Protectorate Waistband]|h")
        assert.are.equal(4, oldStats.mp5)
        assert.are.equal(7, newStats.mp5)
        assert.are.equal(3, newStats.mp5 - oldStats.mp5)
    end)

    it("GetNormalized parses all-resistances equip line with a conditional addendum", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Stamina",
                    "Equip: Increases all Resistances by 3. Gain an additional 5 to all "
                        .. "Resistances in Forest and Grassland areas.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(3, stats.holy_res)
        assert.are.equal(3, stats.fire_res)
        assert.are.equal(3, stats.nature_res)
        assert.are.equal(3, stats.frost_res)
        assert.are.equal(3, stats.shadow_res)
        assert.are.equal(3, stats.arcane_res)
        assert.is_not_nil(stats.conditional)
        local conditional = stats.conditional["in Forest and Grassland areas"]
        assert.is_not_nil(conditional)
        assert.are.equal(5, conditional.holy_res)
        assert.are.equal(5, conditional.fire_res)
        assert.are.equal(5, conditional.nature_res)
        assert.are.equal(5, conditional.frost_res)
        assert.are.equal(5, conditional.shadow_res)
        assert.are.equal(5, conditional.arcane_res)
    end)

    it("GetNormalized parses all-resistances equip line without a conditional addendum", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Stamina",
                    "Equip: Increases all Resistances by 3.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(3, stats.holy_res)
        assert.are.equal(3, stats.fire_res)
        assert.are.equal(3, stats.nature_res)
        assert.are.equal(3, stats.frost_res)
        assert.are.equal(3, stats.shadow_res)
        assert.are.equal(3, stats.arcane_res)
        assert.is_nil(stats.conditional)
    end)

    it("GetNormalized parses mp5 equip line with a capitalized conditional addendum", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Intellect",
                    "Equip: Restores 3 Mana per 5 sec. Restores an additional 6 Mana per 5 sec "
                        .. "in Forest and Grassland areas.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(3, stats.mp5)
        assert.is_not_nil(stats.conditional)
        assert.are.equal(6, stats.conditional["in Forest and Grassland areas"].mp5)
    end)

    it("GetNormalized still parses the existing lowercase mp5 equip line wording", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "Equip: Restores 3 mana per 5 sec.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.are.equal(3, stats.mp5)
        assert.is_nil(stats.conditional)
    end)

    it("GetNormalized parses a fully-conditional movement speed equip line", function()
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    "+10 Agility",
                    "Equip: Movement speed increased by 2% in Silverpine Forest and "
                        .. "Hillsbrad Foothills.",
                })
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        IS = AltArmy.ItemStats
        IS.ClearCache()

        local stats = IS.GetNormalized("|Hitem:99:0|h[Monkey Greaves]|h")
        assert.is_nil(stats.move_speed)
        assert.is_not_nil(stats.conditional)
        assert.are.equal(
            2, stats.conditional["in Silverpine Forest and Hillsbrad Foothills"].move_speed)
    end)
end)
