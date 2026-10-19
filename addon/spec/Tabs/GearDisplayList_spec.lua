--[[
  Unit tests for Gear tab display list ordering (showSelfFirst + score sort).
  Mirrors the split/sort logic from TabGear.lua GetDisplayList.
  Run from project root: npm test
]]

describe("Gear display list showSelfFirst", function()
    local GetSortValue
    local CharKey

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Characters/?.lua"
        require("CharKey")
        require("CharacterSort")
        require("RealmFilter")
        require("CharacterFilter")
        GetSortValue = AltArmy.CharacterSort.GetSortValue
        CharKey = AltArmy.CharKey
    end)

    local function compareBySelectedScore(entryA, entryB, sortKey, descending)
        local va = GetSortValue(entryA, sortKey)
        local vb = GetSortValue(entryB, sortKey)
        if va ~= vb then
            if descending then return va > vb else return va < vb end
        end
        return (entryA.name or "") < (entryB.name or "")
    end

    --- Mirror TabGear GetDisplayList split/sort (no realm filter or item drop).
    local function buildDisplayList(visible, opts)
        opts = opts or {}
        local sortKey = opts.sortKey or "Time Played"
        local descending = opts.scoreSortDescending ~= false
        local showSelfFirst = opts.showSelfFirst ~= false
        local currentName = opts.currentName or "Me"
        local currentRealm = opts.currentRealm or "RealmA"
        local charSettings = opts.charSettings or {}
        local inputList = opts.inputList

        local function GetCharSetting(name, realm, key)
            local c = charSettings[CharKey(name, realm)]
            if not c then return false end
            return c[key] == true
        end

        local function IsBankAlt(name, realm)
            return opts.bankAlts and opts.bankAlts[CharKey(name, realm)] == true
        end

        local filtered = visible
        if inputList then
            filtered = {}
            for i = 1, #inputList do
                local e = inputList[i]
                local isSelf = (e.name == currentName and e.realm == currentRealm)
                local isHidden = GetCharSetting(e.name, e.realm, "hide")
                    or IsBankAlt(e.name, e.realm)
                    or (opts.filter and not AltArmy.CharacterFilter.Matches(e, opts.filter, opts.ctx))
                if not isHidden or (showSelfFirst and isSelf) then
                    filtered[#filtered + 1] = e
                end
            end
        end

        local pinned = {}
        local nonPinned = {}
        for i = 1, #filtered do
            local e = filtered[i]
            local isSelf = (e.name == currentName and e.realm == currentRealm)
            local isPinned = GetCharSetting(e.name, e.realm, "pin")
            if isPinned or (showSelfFirst and isSelf) then
                pinned[#pinned + 1] = e
            else
                nonPinned[#nonPinned + 1] = e
            end
        end

        table.sort(pinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)
        table.sort(nonPinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)

        local list = {}
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
        return list
    end

    local sampleChars = {
        { name = "Alice", realm = "RealmA", played = 100 },
        { name = "Me", realm = "RealmA", played = 50 },
        { name = "Bob", realm = "RealmA", played = 75 },
    }

    it("puts self in pinned group when showSelfFirst is enabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = true })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts pin-current-character with other pinned characters by selected score", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            charSettings = {
                ["RealmA\\Alice"] = { pin = true },
            },
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Me", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts self by selected score when showSelfFirst is disabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = false })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Me", list[3].name)
    end)

    it("respects pin when showSelfFirst is disabled for self", function()
        local list = buildDisplayList(sampleChars, {
            showSelfFirst = false,
            charSettings = {
                ["RealmA\\Me"] = { pin = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts by selected score descending with name tie-break", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
            { name = "Zed", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = true,
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Zed", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts ascending when scoreSortDescending is false", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = false,
        })
        assert.are.equal("Bob", list[1].name)
        assert.are.equal("Alice", list[2].name)
    end)

    it("shows hidden current character when pin current character is enabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal(3, #list)
    end)

    it("respects hide for current character when pin current character is disabled", function()
        local chars = {
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Alice", realm = "RealmA", played = 100 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal(1, #list)
        assert.are.equal("Alice", list[1].name)
    end)

    it("excludes bank alts from the grid", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Banker", realm = "RealmA", played = 10 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            inputList = chars,
            bankAlts = {
                ["RealmA\\Banker"] = true,
            },
        })
        assert.are.equal(2, #list)
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
    end)

    it("shows bank alt current character when pin current character is enabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 10 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            inputList = chars,
            bankAlts = {
                ["RealmA\\Me"] = true,
            },
        })
        assert.are.equal(3, #list)
        assert.are.equal("Me", list[1].name)
    end)

    it("bank alt hide is not overrideable by pin", function()
        local chars = {
            { name = "Banker", realm = "RealmA", played = 10 },
            { name = "Alice", realm = "RealmA", played = 100 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            inputList = chars,
            bankAlts = {
                ["RealmA\\Banker"] = true,
            },
            charSettings = {
                ["RealmA\\Banker"] = { pin = true },
            },
        })
        assert.are.equal(1, #list)
        assert.are.equal("Alice", list[1].name)
    end)

    describe("with the Gear tab's character filter", function()
        local CF = function() return AltArmy.CharacterFilter end
        local ctx = { currentRealm = "RealmA", currentFaction = "Horde", maxLevel = 70 }
        local chars = {
            { name = "Me", realm = "RealmA", faction = "Horde", level = 70, classFile = "MAGE", played = 50 },
            { name = "Ally", realm = "RealmA", faction = "Alliance", level = 70, classFile = "MAGE", played = 90 },
            { name = "Low", realm = "RealmA", faction = "Horde", level = 12, classFile = "PRIEST", played = 10 },
        }

        local function names(list)
            local out = {}
            for i, e in ipairs(list) do out[i] = e.name end
            return out
        end

        it("lists an opposite-faction alt only when its realm filter says so", function()
            local filter = CF().Ensure({}, { maxLevel = 70 })
            local list = buildDisplayList(chars, { showSelfFirst = false, inputList = chars, filter = filter,
                ctx = ctx })
            assert.are.same({ "Me", "Low" }, names(list))
            filter.scope.otherFaction = true
            list = buildDisplayList(chars, { showSelfFirst = false, inputList = chars, filter = filter, ctx = ctx })
            assert.are.same({ "Ally", "Me", "Low" }, names(list))
        end)

        it("drops a level or class the filter leaves out, but pin current character overrides it", function()
            local filter = CF().Ensure({}, { maxLevel = 70 })
            CF().SetLevelRange(filter, 20, 70, 70)
            filter.classes.MAGE = false
            local list = buildDisplayList(chars, { showSelfFirst = false, inputList = chars, filter = filter,
                ctx = ctx })
            assert.are.same({}, names(list))
            list = buildDisplayList(chars, { showSelfFirst = true, inputList = chars, filter = filter, ctx = ctx })
            assert.are.same({ "Me" }, names(list))
        end)
    end)
end)

describe("Gear display list focus mode", function()
    local GU
    local IU
    local DS
    local CharKey

    local SLOT_ORDER = {
        16, 17, 18,
        1, 2, 3, 5,
        15,
        9, 10,
        6, 7, 8,
        11, 12, 13, 14,
        4, 19,
    }

    local function mockGetItemInfo(item)
        local id = tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [12] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [14] = { "Sword", nil, 3, 10, 10, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPONMAINHAND" },
            [15] = { "Weak Ring 1", nil, 2, 35, 35, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [16] = { "Weak Ring 2", nil, 2, 25, 25, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [17] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = {
            Characters = {
                RealmA = {
                    Upgrader = {
                        name = "Upgrader",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                    },
                    SmallUpgrader = {
                        name = "SmallUpgrader",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
                    },
                    Usable = {
                        name = "Usable",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:11:0|h[New Helm]|h" },
                    },
                    LowLevel = {
                        name = "LowLevel",
                        classFile = "MAGE",
                        level = 10,
                        Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                    },
                    WrongClass = {
                        name = "WrongClass",
                        classFile = "WARRIOR",
                        level = 60,
                        Inventory = {},
                    },
                    RingUpgrader = {
                        name = "RingUpgrader",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = {
                            [11] = "|Hitem:15:0|h[Weak Ring 1]|h",
                            [12] = "|Hitem:16:0|h[Weak Ring 2]|h",
                        },
                    },
                },
            },
        }
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        package.loaded["DataStoreTalents"] = nil
        package.loaded["GearUpgrade"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        require("ItemUsability")
        require("DataStoreTalents")
        require("GearUpgrade")
        require("CharKey")
        DS = AltArmy.DataStore
        CharKey = AltArmy.CharKey
        DS.accountData = _G.AltArmyTBC_Data
        IU = AltArmy.ItemUsability
        GU = AltArmy.GearUpgrade
    end)

    --- Mirror TabGear focus sort (uses GU.CompareFocusEntries).
    local function sortByFocusTier(list, itemLink, upgradeOpts, sortOpts)
        sortOpts = sortOpts or {}
        local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries(list, itemLink, upgradeOpts)
        local copy = {}
        for i = 1, #list do copy[i] = list[i] end
        table.sort(copy, function(a, b)
            if sortOpts.soulbound then
                local aSelf = (a.name == sortOpts.currentName and a.realm == sortOpts.currentRealm)
                local bSelf = (b.name == sortOpts.currentName and b.realm == sortOpts.currentRealm)
                if aSelf ~= bSelf then return aSelf end
            end
            local charA = DS:GetCharacter(a.name, a.realm)
            local charB = DS:GetCharacter(b.name, b.realm)
            return GU.CompareFocusEntries(a, b, charA, charB, itemLink, upgradeOpts, upgradeMaxDelta)
        end)
        return copy
    end

    --- Mirror TabGear IsDisplaySlotVisible (uses focus display slots for row filtering).
    local function isDisplaySlotVisible(displayIdx, itemLink)
        local slots = IU.GetFocusDisplaySlotsForItem(itemLink)
        if not slots or #slots == 0 then return true end
        local focused = {}
        for i = 1, #slots do focused[slots[i]] = true end
        local invSlot = SLOT_ORDER[displayIdx]
        return focused[invSlot] == true
    end

    --- Mirror TabGear GetFocusedInventorySlots.
    local function getFocusedInventorySlots(itemLink)
        return GU.GetFocusInventorySlots(itemLink)
    end

    --- Mirror TabGear PickBestCompareSlotForEntry.
    local function pickBestCompareSlotForEntry(entry, list, itemLink, upgradeOpts)
        local slots = getFocusedInventorySlots(itemLink)
        if #slots == 0 then return nil end
        if not entry then return slots[1] end
        local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries(list, itemLink, upgradeOpts)
        local charData = DS:GetCharacter(entry.name, entry.realm)
        local slot = GU.GetBestFocusCompareSlot(
            entry, charData, itemLink, slots, upgradeOpts, upgradeMaxDelta) or slots[1]
        return slot
    end

    --- Mirror TabGear PickInitialCompareSelection.
    local function pickInitialCompareSelection(list, itemLink, upgradeOpts)
        if not GU.HasAnyFocusUpgradeOrEventual(list, itemLink, upgradeOpts) then
            return nil, nil
        end
        if not list or #list == 0 or not itemLink then return nil, nil end
        local e = list[1]
        local slot = pickBestCompareSlotForEntry(e, list, itemLink, upgradeOpts)
        if not slot then return nil, nil end
        return CharKey(e.name, e.realm), slot
    end

    --- Mirror TabGear PickCurrentCharacterCompareSelection.
    local function pickCurrentCharacterCompareSelection(list, currentName, currentRealm, itemLink, upgradeOpts)
        if not list or #list == 0 or not currentName or not currentRealm then
            return nil, nil
        end
        for i = 1, #list do
            local e = list[i]
            if e.name == currentName and e.realm == currentRealm then
                local slot = pickBestCompareSlotForEntry(e, list, itemLink, upgradeOpts)
                if not slot then return nil, nil end
                return CharKey(e.name, e.realm), slot
            end
        end
        return nil, nil
    end

    --- Mirror TabGear ApplyFocusCompareSelection soulbound policy.
    local function applyFocusCompareSelection(list, itemLink, upgradeOpts, soulbound, currentName, currentRealm)
        if soulbound then
            return pickCurrentCharacterCompareSelection(
                list, currentName, currentRealm, itemLink, upgradeOpts)
        end
        return pickInitialCompareSelection(list, itemLink, upgradeOpts)
    end

    --- Mirror TabGear PickBestCompareSelection (in-range upgrade/sidegrade only).
    local function pickBestCompareSelection(list, itemLink, upgradeOpts)
        if not list or #list == 0 or not itemLink then return nil, nil end
        local slots = getFocusedInventorySlots(itemLink)
        if #slots == 0 then return nil, nil end
        local upgradeMaxDelta
        for i = 1, #list do
            local charData = DS:GetCharacter(list[i].name, list[i].realm)
            for s = 1, #slots do
                local delta = GU.GetSlotCompareDelta(charData, itemLink, slots[s], upgradeOpts, list[i]) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        end
        local bestKey, bestSlot, bestDelta = nil, nil, 0
        for i = 1, #list do
            local e = list[i]
            local charData = DS:GetCharacter(e.name, e.realm)
            for s = 1, #slots do
                local invSlot = slots[s]
                local info = GU.ClassifyFocusSlot(e, charData, itemLink, invSlot, upgradeOpts, upgradeMaxDelta)
                if info
                    and (info.category == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
                        or info.category == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE)
                    and info.delta > bestDelta then
                    bestDelta = info.delta
                    bestKey = CharKey(e.name, e.realm)
                    bestSlot = invSlot
                end
            end
        end
        if bestKey and bestSlot then
            return bestKey, bestSlot
        end
        return nil, nil
    end

    it("sorts columns by focus tier: upgrade, sidegrade, eventual upgrade, then neutral", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "LowLevel", realm = "RealmA", classFile = "MAGE", level = 10 },
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal("Upgrader", sorted[1].name)
        assert.are.equal("Usable", sorted[2].name)
        assert.are.equal("LowLevel", sorted[3].name)
    end)

    it("sorts sub-max-level characters before max-level within the same tier", function()
        _G.AltArmyTBC_Data.Characters.RealmA.MaxUpgrader = {
            name = "MaxUpgrader",
            classFile = "MAGE",
            level = 70,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
        }
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "MaxUpgrader", realm = "RealmA", classFile = "MAGE", level = 70 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal("Upgrader", sorted[1].name)
        assert.are.equal("MaxUpgrader", sorted[2].name)
    end)

    it("sorts upgrade columns by biggest upgrade first", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal("Upgrader", sorted[1].name)
        assert.are.equal("SmallUpgrader", sorted[2].name)
        assert.are.equal(15, GU.GetFocusUpgradeDelta(sorted[1], DS:GetCharacter("Upgrader", "RealmA"), itemLink, {
            technique = "ilvl",
            levelsAhead = 0,
        }, 15))
        assert.are.equal(3, GU.GetFocusUpgradeDelta(sorted[2], DS:GetCharacter("SmallUpgrader", "RealmA"), itemLink, {
            technique = "ilvl",
            levelsAhead = 0,
        }, 15))
    end)

    it("auto-selects the first sorted character when an upgrade or eventual upgrade exists", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        local key, slot = pickInitialCompareSelection(sorted, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal(CharKey("Upgrader", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("sorts current character first for soulbound focus before upgrade tier", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts, {
            soulbound = true,
            currentName = "Me",
            currentRealm = "RealmA",
        })
        assert.are.equal("Me", sorted[1].name)
        assert.are.equal("Upgrader", sorted[2].name)
        assert.are.equal("SmallUpgrader", sorted[3].name)
    end)

    it("auto-selects current character for soulbound focus even when another alt is a bigger upgrade", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts, {
            soulbound = true,
            currentName = "Me",
            currentRealm = "RealmA",
        })
        assert.are.equal("Me", sorted[1].name)
        local key, slot = pickCurrentCharacterCompareSelection(
            sorted, "Me", "RealmA", itemLink, upgradeOpts)
        assert.are.equal(CharKey("Me", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("auto-selects current character for soulbound focus even when another alt sorts first", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts, {
            soulbound = true,
            currentName = "Me",
            currentRealm = "RealmA",
        })
        local bestKey = pickInitialCompareSelection(sorted, itemLink, upgradeOpts)
        assert.are.equal(CharKey("Me", "RealmA"), bestKey)
        local key, slot = pickCurrentCharacterCompareSelection(
            sorted, "Me", "RealmA", itemLink, upgradeOpts)
        assert.are.equal(CharKey("Me", "RealmA"), key)
        assert.are.equal(bestKey, key)
        assert.are.equal(1, slot)
    end)

    it("applyFocusCompareSelection picks current character for soulbound regardless of manual drop", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts)
        local key, slot = applyFocusCompareSelection(
            sorted, itemLink, upgradeOpts, true, "Me", "RealmA")
        assert.are.equal(CharKey("Me", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("applyFocusCompareSelection picks best upgrade for non-soulbound focus", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts)
        local key, slot = applyFocusCompareSelection(
            sorted, itemLink, upgradeOpts, false, "Me", "RealmA")
        assert.are.equal(CharKey("Upgrader", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("does not auto-select when no character has a comparable focus result", function()
        local itemLink = "|Hitem:10:0|h[Old Helm]|h"
        local entries = {
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local key, slot = pickInitialCompareSelection(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.is_nil(key)
        assert.is_nil(slot)
    end)

    it("auto-selects for in-range sidegrade characters", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        _G.AltArmyTBC_Data.Characters.RealmA.SidegradeOnly = {
            name = "SidegradeOnly",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:11:0|h[New Helm]|h" },
        }
        local sidegradeEntries = {
            { name = "SidegradeOnly", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(sidegradeEntries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        local key, slot = pickInitialCompareSelection(sorted, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal(CharKey("SidegradeOnly", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("auto-selects first sorted character for eventual upgrade only", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "LowLevel", realm = "RealmA", classFile = "MAGE", level = 10 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        local key, slot = pickInitialCompareSelection(sorted, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal(CharKey("LowLevel", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    --- Mirror TabGear.GetFocusColumnDimmed (incl. soulbound policy).
    local function getFocusColumnDimmed(list, entry, itemLink, upgradeOpts, sortOpts)
        sortOpts = sortOpts or {}
        if sortOpts.soulbound then
            local isSelf = (entry.name == sortOpts.currentName and entry.realm == sortOpts.currentRealm)
            if not isSelf then return true end
        end
        local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries(list, itemLink, upgradeOpts)
        local charData = DS:GetCharacter(entry.name, entry.realm)
        return GU.GetFocusColumnDimmed(entry, charData, itemLink, upgradeOpts, upgradeMaxDelta)
    end

    it("dims alt upgrade columns when focused item is soulbound", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Me", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local upgrader = entries[1]
        assert.is_false(getFocusColumnDimmed(entries, upgrader, itemLink, upgradeOpts))
        assert.is_true(getFocusColumnDimmed(entries, upgrader, itemLink, upgradeOpts, {
            soulbound = true,
            currentName = "Me",
            currentRealm = "RealmA",
        }))
    end)

    it("pickBestCompareSelection still prefers biggest in-range upgrade", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        local key, slot = pickBestCompareSelection(sorted, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal(CharKey("Upgrader", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("filters display rows to focused item inventory slots", function()
        local headLink = "|Hitem:11:0|h[New Helm]|h"
        local ringLink = "|Hitem:12:0|h[Ring]|h"
        local headRowIdx
        local ringRowIdx
        for i = 1, #SLOT_ORDER do
            if SLOT_ORDER[i] == 1 then headRowIdx = i end
            if SLOT_ORDER[i] == 11 then ringRowIdx = i end
        end
        assert.is_true(isDisplaySlotVisible(headRowIdx, headLink))
        assert.is_false(isDisplaySlotVisible(ringRowIdx, headLink))
        assert.is_true(isDisplaySlotVisible(ringRowIdx, ringLink))
        assert.is_false(isDisplaySlotVisible(headRowIdx, ringLink))
    end)

    it("shows main hand and off hand rows when a weapon is focused", function()
        local swordLink = "|Hitem:14:0|h[Sword]|h"
        local mainHandRowIdx
        local offHandRowIdx
        local headRowIdx
        for i = 1, #SLOT_ORDER do
            if SLOT_ORDER[i] == 16 then mainHandRowIdx = i end
            if SLOT_ORDER[i] == 17 then offHandRowIdx = i end
            if SLOT_ORDER[i] == 1 then headRowIdx = i end
        end
        assert.is_true(isDisplaySlotVisible(mainHandRowIdx, swordLink))
        assert.is_true(isDisplaySlotVisible(offHandRowIdx, swordLink))
        assert.is_false(isDisplaySlotVisible(headRowIdx, swordLink))
    end)

    --- Mirror TabGear GetFirstFocusedColumnSlot: topmost visible compare row.
    local function getFirstFocusedColumnSlot(itemLink)
        local visible = {}
        for slot = 1, #SLOT_ORDER do
            if isDisplaySlotVisible(slot, itemLink) then
                visible[#visible + 1] = slot
            end
        end
        if #visible > 0 then
            return SLOT_ORDER[visible[1]]
        end
        local slots = IU.GetInventorySlotsForItem(itemLink)
        return slots[1]
    end

    it("picks the topmost visible slot for header compare selection", function()
        local ringLink = "|Hitem:12:0|h[Ring]|h"
        assert.are.equal(11, getFirstFocusedColumnSlot(ringLink))
        local headLink = "|Hitem:11:0|h[New Helm]|h"
        assert.are.equal(1, getFirstFocusedColumnSlot(headLink))
    end)

    it("auto-selects the ring finger with the biggest upgrade for the best character", function()
        local itemLink = "|Hitem:17:0|h[New Ring]|h"
        local upgradeOpts = { technique = "ilvl", levelsAhead = 0 }
        local entries = {
            { name = "RingUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, upgradeOpts)
        local key, slot = pickInitialCompareSelection(sorted, itemLink, upgradeOpts)
        assert.are.equal(CharKey("RingUpgrader", "RealmA"), key)
        assert.are.equal(12, slot)
    end)
end)
