--[[
  Unit tests for GearCompare.lua.
  Run from project root: npm test
]]

describe("GearCompare", function()
    local GC
    local DS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
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
        return {}
    end

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = {
            Characters = {
                TestRealm = {
                    MageAlt = {
                        name = "MageAlt",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                    EmptyHead = {
                        name = "EmptyHead",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = {},
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                    RingAlt = {
                        name = "RingAlt",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = {
                            [11] = "|Hitem:22:0|h[Ring One]|h",
                            [12] = "|Hitem:21:0|h[Ring Two]|h",
                        },
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                },
            },
        }
        _G.AltArmy.DB = _G.AltArmyTBC_Data
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        DS = AltArmy.DataStore
        DS.accountData = _G.AltArmyTBC_Data
        require("ItemUsability")
        package.loaded["DataStoreTalents"] = nil
        require("DataStoreTalents")
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        package.loaded["PawnScale"] = nil
        require("PawnScale")
        package.loaded["PawnScales"] = nil
        require("PawnScales")
        package.loaded["GearUpgrade"] = nil
        require("GearUpgrade")
        package.loaded["GearCompare"] = nil
        require("GearCompare")
        GC = AltArmy.GearCompare
    end)

    it("GetEquippedCompareItem returns equipped item in best slot", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.are.equal("|Hitem:10:0|h[Old Helm]|h", link)
        assert.are.equal(1, slot)
    end)

    it("GetEquippedCompareItem honors explicit inventory slot", function()
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:20:0|h[New Ring]|h", {
            technique = "ilvl",
            slot = 12,
        })
        assert.are.equal("|Hitem:21:0|h[Ring Two]|h", link)
        assert.are.equal(12, slot)
    end)

    it("GetEquippedCompareItem returns nil link for empty slot", function()
        local char = DS:GetCharacter("EmptyHead", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.is_nil(link)
        assert.are.equal(1, slot)
    end)

    it("BuildComparison custom uses Stat comparison section with changing stats", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local result = GC.BuildComparison(focused, equipped, "custom", char)
        assert.are.equal("New Helm", result.focusedName)
        assert.are.equal("Old Helm", result.equippedName)
        assert.are.equal("custom", result.techniqueId)
        assert.is_true(result.summary.delta > 0)
        assert.are.equal("Stat comparison", result.sections[1].title)
        local rows = result.sections[1].rows
        assert.are.equal(3, #rows)
        assert.are.equal("Stamina", rows[1].label)
        assert.is_false(rows[1].unimportant)
        assert.are.equal(0.5, rows[1].weight)
        assert.are.equal("Intellect", rows[2].label)
        assert.is_false(rows[2].unimportant)
        assert.are.equal(0.37, rows[2].weight)
        assert.are.equal("Weighted", rows[3].label)
        assert.are.equal(result.summary.delta, rows[3].delta)
        assert.is_true(rows[3].formatAsWeightedChange)
        assert.is_true(rows[3].hideWeight)
        local expectedPercent = result.summary.delta / result.summary.oldTotal * 100
        assert.are.equal(expectedPercent, rows[3].percent)
    end)

    it("BuildComparison weighted change percent ignores upgradeMaxDelta", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local result = GC.BuildComparison(focused, equipped, "custom", char, nil, {
            upgradeMaxDelta = 15,
        })
        local rows = result.sections[1].rows
        assert.are.equal("Weighted", rows[#rows].label)
        assert.are.equal(result.summary.delta / result.summary.oldTotal * 100, rows[#rows].percent)
    end)

    it("BuildComparison includes zero-weight changing stats marked unimportant", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 20,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                    ["ITEM_MOD_STRENGTH_SHORT"] = 8,
                }
            end
            if id == 10 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 5,
                    ["ITEM_MOD_STAMINA_SHORT"] = 5,
                }
            end
            return {}
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local rows = result.sections[1].rows
        assert.are.equal(4, #rows)
        assert.are.equal("Stamina", rows[1].label)
        assert.are.equal("Intellect", rows[2].label)
        assert.are.equal("Strength", rows[3].label)
        assert.is_true(rows[3].unimportant)
        assert.are.equal(0, rows[3].weight)
        assert.are.equal("Weighted", rows[4].label)
        assert.are.equal(result.summary.delta, rows[4].delta)
        assert.is_true(rows[4].hideWeight)
        assert.is_true(rows[4].formatAsWeightedChange)
    end)

    it("BuildComparison omits stats that do not change", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 20,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                }
            end
            if id == 10 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 5,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                }
            end
            return {}
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        assert.are.equal(2, #result.sections[1].rows)
        assert.are.equal("Intellect", result.sections[1].rows[1].label)
        assert.are.equal("Weighted", result.sections[1].rows[2].label)
        assert.are.equal(result.summary.delta, result.sections[1].rows[2].delta)
    end)

    it("BuildComparison shows conditional stats as rows but excludes them from the weighted total", function()
        -- Tooltip mock keyed by item id (via SetHyperlink) so the focused (11) and equipped (10)
        -- items can carry different lines instead of both getting whatever text was set last.
        local function makeTooltipMock(linesById)
            local tip = { SetOwner = function() end }
            tip.ClearLines = function(self) self.lineTexts = {} end
            tip.SetHyperlink = function(self, link)
                local id = tonumber(tostring(link):match("item:(%d+)"))
                self.lineTexts = linesById[id] or {}
            end
            tip.GetRegions = function(self)
                local fontStrings = {}
                for i, text in ipairs(self.lineTexts or {}) do
                    fontStrings[i] = {
                        IsObjectType = function(_, t) return t == "FontString" end,
                        GetText = function() return text end,
                    }
                end
                return unpack(fontStrings)
            end
            return tip
        end

        local oldGetItemStats = _G.GetItemStats
        local oldCreateFrame = _G.CreateFrame
        _G.GetItemStats = function() return {} end

        local function buildWithTooltipLine(equipLine)
            _G.CreateFrame = function(frameType)
                if frameType == "GameTooltip" then
                    return makeTooltipMock({
                        [11] = { "+5 Stamina", equipLine },
                        [10] = { "+5 Stamina" },
                    })
                end
                return oldCreateFrame(frameType)
            end
            -- ItemStats caches its scan tooltip in a module-level local; reload the module so
            -- each call gets a fresh tooltip mock instead of reusing a stale cached one.
            package.loaded["ItemStats"] = nil
            require("ItemStats")
            AltArmy.ItemStats.ClearCache()
            local char = DS:GetCharacter("MageAlt", "TestRealm")
            return GC.BuildComparison(
                "|Hitem:11:0|h[New Helm]|h",
                "|Hitem:10:0|h[Old Helm]|h",
                "custom",
                char)
        end

        local baseOnly, withConditional
        local ok, err = pcall(function()
            baseOnly = buildWithTooltipLine("Equip: Increases all Resistances by 3.")
            withConditional = buildWithTooltipLine(
                "Equip: Increases all Resistances by 3. Gain an additional 5 to all "
                    .. "Resistances in Forest and Grassland areas.")
        end)

        -- Restore globals/module state even if the code under test errors, so a red-phase
        -- failure here can't leak polluted mocks into later tests in this file.
        _G.GetItemStats = oldGetItemStats
        _G.CreateFrame = oldCreateFrame
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        AltArmy.ItemStats.ClearCache()

        assert.is_true(ok, tostring(err))

        -- The conditional addendum must not change the weighted totals at all.
        assert.are.equal(baseOnly.summary.newTotal, withConditional.summary.newTotal)
        assert.are.equal(baseOnly.summary.delta, withConditional.summary.delta)

        -- Base (always-on) resistances are identical across all six schools, so they collapse
        -- into a single "All Resistances" row instead of six separate rows.
        local baseRows = baseOnly.sections[1].rows
        assert.are.equal(2, #baseRows)
        assert.are.equal("All Resistances", baseRows[1].label)
        assert.is_true(baseRows[2].formatAsWeightedChange)
        for _, row in ipairs(baseRows) do
            assert.is_falsy(row.conditional)
            assert.is_falsy(row.isHeader)
        end

        -- The conditional group is rendered as a header row (the condition text) followed by an
        -- unindented stat row with no parenthetical; its six equal resistances also collapse.
        local headerRow, groupedRow, scalarRow
        for _, row in ipairs(withConditional.sections[1].rows) do
            if row.isHeader then
                headerRow = row
            elseif row.conditional then
                groupedRow = row
            elseif not row.formatAsWeightedChange then
                scalarRow = row
            end
        end
        assert.is_not_nil(scalarRow)
        assert.are.equal("All Resistances", scalarRow.label)
        assert.is_not_nil(headerRow)
        assert.are.equal("... in Forest and Grassland areas:", headerRow.label)
        assert.is_not_nil(groupedRow)
        assert.are.equal("All Resistances", groupedRow.label)
        assert.is_true(groupedRow.hideWeight)
        assert.is_nil(groupedRow.indent)
    end)

    it("BuildComparison shows equal resistances as one All Resistances row at the AllResist weight", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["RESISTANCE1_NAME"] = 5, ["RESISTANCE2_NAME"] = 5, ["RESISTANCE3_NAME"] = 5,
                    ["RESISTANCE4_NAME"] = 5, ["RESISTANCE5_NAME"] = 5, ["RESISTANCE6_NAME"] = 5,
                }
            end
            return {}
        end
        AltArmy.ItemStats.ClearCache()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        AltArmy.ItemStats.ClearCache()

        local rows = result.sections[1].rows
        assert.are.equal(2, #rows)
        assert.are.equal("All Resistances", rows[1].label)
        assert.are.equal(5, rows[1].delta)
        -- Scored once at AllResist (0.2), not six schools at AllResist + school weight each.
        assert.are.equal(0.2, rows[1].weight)
        assert.are.equal(1, rows[1].weightedDelta)
        assert.is_true(rows[2].formatAsWeightedChange)
    end)

    it("BuildComparison splits unequal resistances into All Resistances plus the extra per school", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["RESISTANCE1_NAME"] = 5, ["RESISTANCE2_NAME"] = 5, ["RESISTANCE3_NAME"] = 5,
                    ["RESISTANCE4_NAME"] = 5, ["RESISTANCE5_NAME"] = 5, ["RESISTANCE6_NAME"] = 3,
                }
            end
            return {}
        end
        AltArmy.ItemStats.ClearCache()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        AltArmy.ItemStats.ClearCache()

        local rows = result.sections[1].rows
        local deltaByLabel = {}
        for _, row in ipairs(rows) do
            if not row.formatAsWeightedChange then
                deltaByLabel[row.label] = row.delta
            end
        end
        assert.are.equal(3, deltaByLabel["All Resistances"])
        assert.are.equal(2, deltaByLabel["Holy Resistance"])
        assert.are.equal(2, deltaByLabel["Fire Resistance"])
        assert.are.equal(2, deltaByLabel["Nature Resistance"])
        assert.are.equal(2, deltaByLabel["Frost Resistance"])
        assert.are.equal(2, deltaByLabel["Shadow Resistance"])
        assert.is_nil(deltaByLabel["Arcane Resistance"])
    end)

    it("BuildComparison always places conditional groups after scalar stat rows", function()
        -- Tooltip mock keyed by item id, matching the pattern used by the other conditional test.
        local function makeTooltipMock(linesById)
            local tip = { SetOwner = function() end }
            tip.ClearLines = function(self) self.lineTexts = {} end
            tip.SetHyperlink = function(self, link)
                local id = tonumber(tostring(link):match("item:(%d+)"))
                self.lineTexts = linesById[id] or {}
            end
            tip.GetRegions = function(self)
                local fontStrings = {}
                for i, text in ipairs(self.lineTexts or {}) do
                    fontStrings[i] = {
                        IsObjectType = function(_, t) return t == "FontString" end,
                        GetText = function() return text end,
                    }
                end
                return unpack(fontStrings)
            end
            return tip
        end

        local oldGetItemStats = _G.GetItemStats
        local oldCreateFrame = _G.CreateFrame
        -- Item 11 keeps its normal (important) INT/STA stats from the API, plus a fully
        -- conditional, unrelated movement-speed line from the tooltip.
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 10 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
            end
            return {}
        end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return makeTooltipMock({
                    [11] = { "Equip: Movement speed increased by 2% in Silverpine Forest and "
                        .. "Hillsbrad Foothills." },
                })
            end
            return oldCreateFrame(frameType)
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        AltArmy.ItemStats.ClearCache()

        local ok, err = pcall(function()
            local char = DS:GetCharacter("MageAlt", "TestRealm")
            local result = GC.BuildComparison(
                "|Hitem:11:0|h[New Helm]|h",
                "|Hitem:10:0|h[Old Helm]|h",
                "custom",
                char)

            local rows = result.sections[1].rows
            assert.is_true(#rows >= 4) -- Stamina, Intellect, header, movement speed, Weighted

            local firstGroupedIndex = nil
            for i, row in ipairs(rows) do
                if (row.isHeader or row.conditional) and not firstGroupedIndex then
                    firstGroupedIndex = i
                end
            end
            assert.is_not_nil(firstGroupedIndex)

            -- Nothing before the first grouped/conditional row is itself grouped or conditional.
            for i = 1, firstGroupedIndex - 1 do
                assert.is_falsy(rows[i].isHeader)
                assert.is_falsy(rows[i].conditional)
            end

            -- Nothing after the first grouped/conditional row (other than the trailing Weighted
            -- summary row) is a plain scalar stat row.
            for i = firstGroupedIndex, #rows do
                local row = rows[i]
                assert.is_true(row.isHeader or row.conditional or row.formatAsWeightedChange)
            end

            assert.is_true(rows[#rows].formatAsWeightedChange)
        end)

        _G.GetItemStats = oldGetItemStats
        _G.CreateFrame = oldCreateFrame
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        AltArmy.ItemStats.ClearCache()

        assert.is_true(ok, tostring(err))
    end)

    it("BuildComparison ilvl returns item level summary", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "ilvl",
            char)
        assert.are.equal(35, result.summary.newTotal)
        assert.are.equal(20, result.summary.oldTotal)
        assert.are.equal(15, result.summary.delta)
    end)

    it("BuildComparison empty equipped shows (empty) name", function()
        local char = DS:GetCharacter("EmptyHead", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            nil,
            "custom",
            char)
        assert.are.equal("(empty)", result.equippedName)
        local rows = result.sections[1].rows
        local weighted = rows[#rows]
        assert.are.equal("Weighted", weighted.label)
        assert.is_nil(weighted.percent)
    end)

    it("BuildItemComparisonDebugReport lists all providers and character summaries", function()
        local lines = GC.BuildItemComparisonDebugReport("|Hitem:11:0|h[New Helm]|h")
        assert.is_true(#lines > 0)
        local text = table.concat(lines, "\n")
        assert.matches("New Helm", text)
        assert.matches("%[Alt Army%]", text)
        assert.matches("%[Item Level%]", text)
        assert.matches("MageAlt", text)
        assert.matches("upgrade", text)
        assert.matches("Stat comparison", text)
    end)

    it("BuildComparePanelDump captures items, weights, and comparison context", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local dump = GC.BuildComparePanelDump(focused, equipped, "custom", char, {
            name = "MageAlt",
            realm = "TestRealm",
        }, {
            invSlot = 1,
            upgradeMaxDelta = 15,
            timestamp = 12345,
        })
        assert.are.equal(1, dump.version)
        assert.are.equal(12345, dump.timestamp)
        assert.are.equal("MageAlt", dump.character.name)
        assert.are.equal("TestRealm", dump.character.realm)
        assert.are.equal("MAGE", dump.character.classFile)
        assert.are.equal(1, dump.context.invSlot)
        assert.are.equal(15, dump.context.upgradeMaxDelta)
        assert.are.equal("New Helm", dump.items.focused.name)
        assert.are.equal("Old Helm", dump.items.equipped.name)
        assert.is_table(dump.items.focused.parseSnapshot)
        assert.is_table(dump.items.focused.scoreBreakdown)
        assert.is_true(dump.items.focused.scoreBreakdown.total > 0)
        assert.is_table(dump.weights)
        assert.is_table(dump.comparison.sections)
    end)

    it("SaveComparePanelDump appends only when debug master switch is on", function()
        package.loaded["Debug"] = nil
        require("Debug")
        _G.AltArmyTBC_Options = { debug = { enabled = false, comparePanelDumps = {} } }
        AltArmy.Debug.Ensure()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local saved = GC.SaveComparePanelDump(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char,
            { name = "MageAlt", realm = "TestRealm" })
        assert.is_nil(saved)
        AltArmy.Debug.SetEnabled(true)
        saved = GC.SaveComparePanelDump(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char,
            { name = "MageAlt", realm = "TestRealm" })
        assert.are.equal(1, saved)
        assert.are.equal("MageAlt", AltArmyTBC_Options.debug.comparePanelDumps[1].character.name)
    end)

    it("BuildComparison includes weapon loadout row and note for 2H vs dual-wield", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [201] = { "Weak MH", nil, 2, 30, 30, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [202] = { "Weak OH", nil, 2, 25, 25, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [203] = { "Big 2H", nil, 3, 60, 60, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.WarriorDW = {
            name = "WarriorDW",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = {
                [16] = "|Hitem:201:0|h[Weak MH]|h",
                [17] = "|Hitem:202:0|h[Weak OH]|h",
            },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local char = DS:GetCharacter("WarriorDW", "TestRealm")
        local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local result = GC.BuildComparison(
            "|Hitem:203:0|h[Big 2H]|h",
            "|Hitem:201:0|h[Weak MH]|h",
            "ilvl",
            char,
            entry,
            { compareSlot = 16 })
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(5, result.summary.delta)
        assert.are.equal(55, result.summary.oldTotal)
        assert.are.equal(60, result.summary.newTotal)
        local rows = result.sections[1].rows
        assert.are.equal(60, rows[1].newValue)
        assert.are.equal(55, rows[1].oldValue)
    end)

    it("BuildComparison custom sums stats across weapon loadout items", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [204] = { "Small 2H", nil, 2, 50, 50, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
                [205] = { "New 1H", nil, 3, 40, 40, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [206] = { "Bag OH", nil, 2, 22, 22, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [207] = { "Bag 1H", nil, 2, 28, 28, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 204 then
                return { ["ITEM_MOD_STAMINA_SHORT"] = 50 }
            end
            if id == 205 then
                return { ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 207 then
                return { ["ITEM_MOD_STAMINA_SHORT"] = 8 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.Warrior2H = {
            name = "Warrior2H",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = {
                [16] = "|Hitem:204:0|h[Small 2H]|h",
            },
            Containers = {
                [0] = {
                    links = {
                        [1] = "|Hitem:206:0|h[Bag OH]|h",
                        [2] = "|Hitem:207:0|h[Bag 1H]|h",
                    },
                },
            },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local char = DS:GetCharacter("Warrior2H", "TestRealm")
        local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local result = GC.BuildComparison(
            "|Hitem:205:0|h[New 1H]|h",
            "|Hitem:204:0|h[Small 2H]|h",
            "custom",
            char,
            entry,
            { compareSlot = 16 })
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local rows = result.sections[1].rows
        local staminaRow
        for i = 1, #rows do
            if rows[i].label == "Stamina" then
                staminaRow = rows[i]
                break
            end
        end
        assert.is_not_nil(staminaRow)
        assert.are.equal(18, staminaRow.newValue)
        assert.are.equal(50, staminaRow.oldValue)
        assert.are.equal(-32, staminaRow.delta)
    end)

    it("BuildComparison custom sums equipped dual-wield stats vs 2H", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [201] = { "Weak MH", nil, 2, 30, 30, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [202] = { "Weak OH", nil, 2, 25, 25, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [203] = { "Big 2H", nil, 3, 60, 60, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 201 then
                return { ["ITEM_MOD_STRENGTH_SHORT"] = 12 }
            end
            if id == 202 then
                return { ["ITEM_MOD_STRENGTH_SHORT"] = 8 }
            end
            if id == 203 then
                return { ["ITEM_MOD_STRENGTH_SHORT"] = 25 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.WarriorDW = {
            name = "WarriorDW",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = {
                [16] = "|Hitem:201:0|h[Weak MH]|h",
                [17] = "|Hitem:202:0|h[Weak OH]|h",
            },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local char = DS:GetCharacter("WarriorDW", "TestRealm")
        local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local result = GC.BuildComparison(
            "|Hitem:203:0|h[Big 2H]|h",
            "|Hitem:201:0|h[Weak MH]|h",
            "custom",
            char,
            entry,
            { compareSlot = 16 })
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local rows = result.sections[1].rows
        local strengthRow
        for i = 1, #rows do
            if rows[i].label == "Strength" then
                strengthRow = rows[i]
                break
            end
        end
        assert.is_not_nil(strengthRow)
        assert.are.equal(25, strengthRow.newValue)
        assert.are.equal(20, strengthRow.oldValue)
        assert.are.equal(5, strengthRow.delta)
    end)

    it("BuildComparison merges conditional stats across a dual-wield loadout instead of erroring", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetNormalized = AltArmy.ItemStats.GetNormalized
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [211] = { "Old MH", nil, 2, 30, 30, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [212] = { "Old OH", nil, 2, 25, 25, "Weapon", "Daggers", nil, "INVTYPE_WEAPON" },
                [213] = { "New 1H", nil, 3, 40, 40, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        local zone = "in Forest and Grassland areas"
        AltArmy.ItemStats.GetNormalized = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 211 then return { str = 10, conditional = { [zone] = { sta = 4 } } } end
            if id == 212 then return { str = 6, conditional = { [zone] = { sta = 3 } } } end
            if id == 213 then return { str = 14 } end
            return {}
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.RogueDW = {
            name = "RogueDW",
            realm = "TestRealm",
            classFile = "ROGUE",
            level = 60,
            Inventory = {
                [16] = "|Hitem:211:0|h[Old MH]|h",
                [17] = "|Hitem:212:0|h[Old OH]|h",
            },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "combat" },
        }
        local char = DS:GetCharacter("RogueDW", "TestRealm")
        local entry = { name = "RogueDW", realm = "TestRealm", classFile = "ROGUE", level = 60 }
        local ok, result = pcall(GC.BuildComparison,
            "|Hitem:213:0|h[New 1H]|h",
            "|Hitem:211:0|h[Old MH]|h",
            "custom",
            char,
            entry,
            { compareSlot = 16 })
        _G.GetItemInfo = oldGetItemInfo
        AltArmy.ItemStats.GetNormalized = oldGetNormalized
        _G.AltArmyTBC_Data.Characters.TestRealm.RogueDW = nil

        assert.is_true(ok, tostring(result))
        local headerRow, groupedRow
        for _, row in ipairs(result.sections[1].rows) do
            if row.isHeader then
                headerRow = row
            elseif row.conditional then
                groupedRow = row
            end
        end
        assert.is_not_nil(headerRow)
        assert.are.equal("... " .. zone .. ":", headerRow.label)
        assert.is_not_nil(groupedRow)
        assert.are.equal("sta", groupedRow.statKey)
    end)

    it("BuildComparison scales off-hand melee DPS and flags the row with a hint", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [204] = { "Small 2H", nil, 2, 50, 50, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
                [205] = { "New 1H", nil, 3, 40, 40, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [206] = { "Bag OH", nil, 2, 22, 22, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [207] = { "Bag 1H", nil, 2, 28, 28, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 204 then
                return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 50 }
            end
            if id == 205 then
                return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 30 }
            end
            if id == 206 then
                return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 28 }
            end
            if id == 207 then
                return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 20 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        if AltArmy.GearUpgrade and AltArmy.GearUpgrade.ResetFocusPass then
            AltArmy.GearUpgrade.ResetFocusPass()
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.Warrior2H = {
            name = "Warrior2H",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = {
                [16] = "|Hitem:204:0|h[Small 2H]|h",
            },
            Containers = {
                [0] = {
                    links = {
                        [1] = "|Hitem:206:0|h[Bag OH]|h",
                        [2] = "|Hitem:207:0|h[Bag 1H]|h",
                    },
                },
            },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local char = DS:GetCharacter("Warrior2H", "TestRealm")
        local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local result = GC.BuildComparison(
            "|Hitem:205:0|h[New 1H]|h",
            "|Hitem:204:0|h[Small 2H]|h",
            "custom",
            char,
            entry,
            { compareSlot = 16 })
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local rows = result.sections[1].rows
        local dpsRow
        for i = 1, #rows do
            if rows[i].label == "Melee DPS" then
                dpsRow = rows[i]
                break
            end
        end
        assert.is_not_nil(dpsRow)
        -- Candidate loadout is New 1H (30 dps) + Bag OH (28 dps at 50% = 14).
        assert.are.equal(44, dpsRow.newValue)
        assert.are.equal(50, dpsRow.oldValue)
        assert.are.equal(-6, dpsRow.delta)
        assert.are.equal(GC.GetOffhandDpsHintText(), dpsRow.offhandHint)
        -- Only the affected DPS row carries the hint.
        for i = 1, #rows do
            if rows[i] ~= dpsRow then
                assert.is_nil(rows[i].offhandHint)
            end
        end
    end)

    it("BuildComparison rows carry no off-hand hint for armor items", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        local rows = result.sections[1].rows
        assert.is_true(#rows > 0)
        for i = 1, #rows do
            assert.is_nil(rows[i].offhandHint)
        end
    end)

    it("GetOffhandDpsHintText explains the off-hand DPS percentage", function()
        local text = GC.GetOffhandDpsHintText()
        assert.are.equal(
            "When dual wielding, the offhand weapon's damage is scaled to 50% of its listed amount",
            text)
    end)

    it("BuildComparison computes weapon loadout summary a bounded number of times", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [201] = { "Weak MH", nil, 2, 30, 30, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [202] = { "Weak OH", nil, 2, 25, 25, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [203] = { "Big 2H", nil, 3, 60, 60, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
            }
            local info = items[id]
            if info then
                local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
                return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
            end
            return oldGetItemInfo(item)
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.WarriorDW = {
            name = "WarriorDW",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = {
                [16] = "|Hitem:201:0|h[Weak MH]|h",
                [17] = "|Hitem:202:0|h[Weak OH]|h",
            },
            Containers = { [0] = { links = {} } },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local char = DS:GetCharacter("WarriorDW", "TestRealm")
        local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local GU = AltArmy.GearUpgrade
        if GU.ResetFocusPass then GU.ResetFocusPass() end
        local configCalls = 0
        local oldConfig = GU.GetWeaponConfigDelta
        GU.GetWeaponConfigDelta = function(...)
            configCalls = configCalls + 1
            return oldConfig(...)
        end
        local result = GC.BuildComparison(
            "|Hitem:203:0|h[Big 2H]|h",
            "|Hitem:201:0|h[Weak MH]|h",
            "ilvl",
            char,
            entry,
            { compareSlot = 16 })
        GU.GetWeaponConfigDelta = oldConfig
        _G.GetItemInfo = oldGetItemInfo
        assert.is_not_nil(result)
        assert.are.equal(5, result.summary.delta)
        -- resolveLoadoutStatSides + one shared buildSummary (no outer/ilvl duplicates).
        assert.are.equal(2, configCalls)
    end)
end)
