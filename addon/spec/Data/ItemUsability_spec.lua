--[[
  Unit tests for ItemUsability.lua.
  Run from project root: npm test
]]

describe("ItemUsability", function()
    local IU
    local CC

    local function coloredName(name, classFile)
        return CC.wrapName(name, classFile)
    end

    local function warningText(warning)
        return IU.GetEquipWarningText(warning)
    end

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [1] = { "Cloth Hood", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [2] = { "Plate Helm", nil, 3, 35, 35, "Armor", "Plate", nil, "INVTYPE_HEAD" },
            [3] = { "Mail Vest", nil, 3, 30, 30, "Armor", "Mail", nil, "INVTYPE_CHEST" },
            [4] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [5] = { "Sword", nil, 3, 10, 10, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPONMAINHAND" },
            [6] = { "Wand", nil, 2, 5, 5, "Weapon", "Wands", nil, "INVTYPE_RANGEDRIGHT" },
            [7] = { "Shield", nil, 2, 10, 10, "Armor", "Shields", nil, "INVTYPE_SHIELD" },
            [8] = { "Health Potion", nil, 1, 1, 1, "Consumable", nil, nil, nil },
            [9] = { "Epic Helm", nil, 4, 70, 60, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [10] = { "One-Hand Axe", nil, 3, 10, 10, "Weapon", "One-Handed Axes", nil, "INVTYPE_WEAPON" },
            [11] = { "Two-Hand Sword", nil, 3, 30, 30, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
            [12] = { "Offhand Dagger", nil, 3, 15, 15, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
            [13] = { "Fishing Pole", nil, 2, 10, 10, "Weapon", "Fishing Poles", nil, "INVTYPE_2HWEAPON" },
            [15] = { "Halberd", nil, 3, 10, 10, "Weapon", "Polearms", nil, "INVTYPE_2HWEAPON" },
            [16] = { "Heavy Mace", nil, 3, 10, 10, "Weapon", "Two-Handed Maces", nil, "INVTYPE_2HWEAPON" },
            [17] = { "Throwing Knife", nil, 2, 10, 10, "Weapon", "Thrown", nil, "INVTYPE_THROWN" },
            [18] = { "Claw", nil, 3, 10, 10, "Weapon", "Fist Weapons", nil, "INVTYPE_WEAPON" },
            [19] = { "Tome", nil, 2, 10, 10, "Miscellaneous", nil, nil, "INVTYPE_HOLDABLE" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
            PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
            MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        }
        _G.GetItemInfo = mockGetItemInfo
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["ClassColor"] = nil
        require("ClassColor")
        CC = AltArmy.ClassColor
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        IU = AltArmy.ItemUsability
        if IU.ClearCache then
            IU.ClearCache()
        end
    end)

    before_each(function()
        if IU and IU.ClearCache then
            IU.ClearCache()
        end
    end)

    it("maps INVTYPE_FINGER to finger slots", function()
        local slots = IU.GetInventorySlotsForItem("|Hitem:4:0|h[Ring]|h")
        assert.are.same({ 11, 12 }, slots)
    end)

    it("maps INVTYPE_WEAPONMAINHAND to slot 16", function()
        local slots = IU.GetInventorySlotsForItem("|Hitem:5:0|h[Sword]|h")
        assert.are.same({ 16 }, slots)
    end)

    it("GetFocusDisplaySlotsForItem expands weapon focus to main and off hand rows", function()
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:5:0|h[Sword]|h"))
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:10:0|h[One-Hand Axe]|h"))
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:11:0|h[Two-Hand Sword]|h"))
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:12:0|h[Offhand Dagger]|h"))
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:7:0|h[Shield]|h"))
        assert.are.same({ 16, 17 }, IU.GetFocusDisplaySlotsForItem("|Hitem:19:0|h[Tome]|h"))
    end)

    it("GetFocusDisplaySlotsForItem leaves non-weapon slots unchanged", function()
        assert.are.same({ 11, 12 }, IU.GetFocusDisplaySlotsForItem("|Hitem:4:0|h[Ring]|h"))
        assert.are.same({ 1 }, IU.GetFocusDisplaySlotsForItem("|Hitem:1:0|h[Cloth Hood]|h"))
    end)

    it("GetWeaponRole maps equip locations to weapon roles", function()
        assert.are.equal("onehand", IU.GetWeaponRole("|Hitem:5:0|h[Sword]|h"))
        assert.are.equal("onehand", IU.GetWeaponRole("|Hitem:10:0|h[One-Hand Axe]|h"))
        assert.are.equal("twohand", IU.GetWeaponRole("|Hitem:11:0|h[Two-Hand Sword]|h"))
        assert.are.equal("offhand", IU.GetWeaponRole("|Hitem:12:0|h[Offhand Dagger]|h"))
        assert.are.equal("offhand", IU.GetWeaponRole("|Hitem:7:0|h[Shield]|h"))
        assert.are.equal("ranged", IU.GetWeaponRole("|Hitem:6:0|h[Wand]|h"))
        assert.is_nil(IU.GetWeaponRole("|Hitem:4:0|h[Ring]|h"))
        assert.is_nil(IU.GetWeaponRole(nil))
    end)

    it("CanClassDualWield follows TBC class and spec rules", function()
        assert.is_true(IU.CanClassDualWield("WARRIOR", "arms"))
        assert.is_true(IU.CanClassDualWield("ROGUE", "combat"))
        assert.is_true(IU.CanClassDualWield("HUNTER", "beastmastery"))
        assert.is_true(IU.CanClassDualWield("SHAMAN", "enhancement"))
        assert.is_false(IU.CanClassDualWield("SHAMAN", "restoration"))
        assert.is_false(IU.CanClassDualWield("SHAMAN", "elemental"))
        assert.is_false(IU.CanClassDualWield("PALADIN", "retribution"))
        assert.is_false(IU.CanClassDualWield("MAGE", "frost"))
        assert.is_false(IU.CanClassDualWield("PRIEST", "shadow"))
    end)

    it("CanClassDualWield denies enhancement shaman on WoW Forever (no dual-wield talent there)", function()
        AltArmy.DataStore = AltArmy.DataStore or {}
        AltArmy.DataStore.IsWowForever = true
        assert.is_false(IU.CanClassDualWield("SHAMAN", "enhancement"))
        assert.is_true(IU.CanClassDualWield("WARRIOR", "arms"))
        AltArmy.DataStore.IsWowForever = false
        assert.is_true(IU.CanClassDualWield("SHAMAN", "enhancement"))
    end)

    it("CanClassEverUseArmor blocks mage from leather", function()
        assert.is_false(IU.CanClassEverUseArmor("MAGE", "Leather"))
        assert.is_true(IU.CanClassEverUseArmor("MAGE", "Cloth"))
    end)

    it("CanClassEverUseArmor allows paladin plate eventually", function()
        assert.is_true(IU.CanClassEverUseArmor("PALADIN", "Plate"))
    end)

    it("CanClassEverUseWeapon blocks warrior from wands", function()
        assert.is_false(IU.CanClassEverUseWeapon("WARRIOR", "Wands"))
        assert.is_true(IU.CanClassEverUseWeapon("MAGE", "Wands"))
    end)

    it("CanClassEverUseWeapon allows shield classes to use shields", function()
        assert.is_true(IU.CanClassEverUseWeapon("WARRIOR", "Shields"))
        assert.is_true(IU.CanClassEverUseWeapon("PALADIN", "Shields"))
        assert.is_true(IU.CanClassEverUseWeapon("SHAMAN", "Shields"))
        assert.is_false(IU.CanClassEverUseWeapon("MAGE", "Shields"))
        assert.is_false(IU.CanClassEverUseWeapon("ROGUE", "Shields"))
    end)

    it("CanClassEverUseWeapon blocks rogue axes on TBC but allows them on WoW Forever", function()
        assert.is_false(IU.CanClassEverUseWeapon("ROGUE", "One-Handed Axes"))
        assert.is_false(IU.CanClassEverUseWeapon("ROGUE", "Two-Handed Axes"))

        AltArmy.DataStore = AltArmy.DataStore or {}
        AltArmy.DataStore.IsWowForever = true
        assert.is_true(IU.CanClassEverUseWeapon("ROGUE", "One-Handed Axes"))
        assert.is_false(IU.CanClassEverUseWeapon("ROGUE", "Two-Handed Axes"))
        AltArmy.DataStore.IsWowForever = false

        assert.is_false(IU.CanClassEverUseWeapon("ROGUE", "One-Handed Axes"))
    end)

    it("CanClassEverUseWeapon allows paladins to use polearms", function()
        assert.is_true(IU.CanClassEverUseWeapon("PALADIN", "Polearms"))
        assert.is_false(IU.CanNeverUseItem("PALADIN", "|Hitem:15:0|h[Halberd]|h"))
    end)

    it("EffectiveRequiredLevel gates polearm classes until level 20", function()
        assert.are.equal(20, IU.MinLevelToTrainProficiency("PALADIN", "Polearms", "Weapon"))
        assert.are.equal(20, IU.MinLevelToTrainProficiency("WARRIOR", "Polearms", "Weapon"))
        assert.are.equal(20, IU.MinLevelToTrainProficiency("HUNTER", "Polearms", "Weapon"))
        assert.are.equal(20, IU.EffectiveRequiredLevel("PALADIN", "|Hitem:15:0|h[Halberd]|h"))
        assert.are.equal(20, IU.EffectiveRequiredLevel("WARRIOR", "|Hitem:15:0|h[Halberd]|h"))
        assert.are.equal(20, IU.EffectiveRequiredLevel("HUNTER", "|Hitem:15:0|h[Halberd]|h"))
    end)

    it("CanClassEverUseWeapon allows druid two-handed maces", function()
        assert.is_true(IU.CanClassEverUseWeapon("DRUID", "Two-Handed Maces"))
        assert.is_false(IU.CanNeverUseItem("DRUID", "|Hitem:16:0|h[Heavy Mace]|h"))
        assert.is_false(IU.CanClassEverUseWeapon("DRUID", "Polearms"))
    end)

    it("CanClassEverUseWeapon allows druid polearms on WoW Forever, gated to level 20", function()
        AltArmy.DataStore = AltArmy.DataStore or {}
        AltArmy.DataStore.IsWowForever = true
        assert.is_true(IU.CanClassEverUseWeapon("DRUID", "Polearms"))
        assert.are.equal(20, IU.MinLevelToTrainProficiency("DRUID", "Polearms", "Weapon"))
        assert.are.equal(20, IU.EffectiveRequiredLevel("DRUID", "|Hitem:15:0|h[Halberd]|h"))
        AltArmy.DataStore.IsWowForever = false

        assert.is_false(IU.CanClassEverUseWeapon("DRUID", "Polearms"))
    end)

    it("CanClassEverUseWeapon allows hunter thrown and fist weapons", function()
        assert.is_true(IU.CanClassEverUseWeapon("HUNTER", "Thrown"))
        assert.is_true(IU.CanClassEverUseWeapon("HUNTER", "Fist Weapons"))
        assert.is_false(IU.CanNeverUseItem("HUNTER", "|Hitem:17:0|h[Throwing Knife]|h"))
        assert.is_false(IU.CanNeverUseItem("HUNTER", "|Hitem:18:0|h[Claw]|h"))
    end)

    it("GetItemUseInfo classifies shields as weapon subclass", function()
        local req, armor, weapon = IU.GetItemUseInfo("|Hitem:7:0|h[Shield]|h")
        assert.are.equal(10, req)
        assert.is_nil(armor)
        assert.are.equal("Shields", weapon)
    end)

    it("CanNeverUseItem allows paladin to equip shields", function()
        assert.is_false(IU.CanNeverUseItem("PALADIN", "|Hitem:7:0|h[Shield]|h"))
        assert.is_true(IU.CanNeverUseItem("MAGE", "|Hitem:7:0|h[Shield]|h"))
    end)

    it("EffectiveRequiredLevel for shields uses item min level only", function()
        assert.are.equal(10, IU.EffectiveRequiredLevel("PALADIN", "|Hitem:7:0|h[Shield]|h"))
        assert.are.equal(999, IU.EffectiveRequiredLevel("MAGE", "|Hitem:7:0|h[Shield]|h"))
    end)

    it("CanClassEverUseWeapon allows all classes to use fishing poles", function()
        assert.is_true(IU.CanClassEverUseWeapon("MAGE", "Fishing Poles"))
        assert.is_true(IU.CanClassEverUseWeapon("WARRIOR", "Fishing Pole"))
        assert.is_true(IU.IsFishingPoleSubclass("Fishing Poles"))
    end)

    it("CanNeverUseItem allows any class to equip fishing poles", function()
        assert.is_false(IU.CanNeverUseItem("MAGE", "|Hitem:13:0|h[Fishing Pole]|h"))
        assert.is_false(IU.CanNeverUseItem("ROGUE", "|Hitem:13:0|h[Fishing Pole]|h"))
    end)

    it("GetEquipWarnings includes fishing training when skill is missing", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 60, "Alt", "|Hitem:13:0|h[Fishing Pole]|h", nil)
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Alt", "MAGE") .. " must train Fishing to equip this",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.TRAINING, warnings[1].kind)
    end)

    it("GetEquipWarnings omits fishing training when character knows Fishing", function()
        local charData = {
            name = "Alt",
            classFile = "MAGE",
            Professions = { Fishing = { rank = 1, maxRank = 75 } },
        }
        local warnings = IU.GetEquipWarnings(
            "MAGE", 60, "Alt", "|Hitem:13:0|h[Fishing Pole]|h", charData)
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings omits fishing training when character is below item level", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 5, "Alt", "|Hitem:13:0|h[Fishing Pole]|h", nil)
        assert.are.equal(1, #warnings)
        assert.are.equal(IU.EQUIP_WARNING_KIND.LEVEL, warnings[1].kind)
    end)

    it("GetProficiencySkillName maps fishing poles to Fishing", function()
        assert.are.equal("Fishing", IU.GetProficiencySkillName("Weapon", "Fishing Poles"))
    end)

    it("MinLevelToTrainProficiency returns 40 for paladin plate", function()
        assert.are.equal(40, IU.MinLevelToTrainProficiency("PALADIN", "Plate", "Armor"))
    end)

    it("MinLevelToTrainProficiency returns 40 for hunter mail", function()
        assert.are.equal(40, IU.MinLevelToTrainProficiency("HUNTER", "Mail", "Armor"))
    end)

    it("MinLevelToTrainProficiency returns 1 for cloth on any class", function()
        assert.are.equal(1, IU.MinLevelToTrainProficiency("MAGE", "Cloth", "Armor"))
    end)

    it("EffectiveRequiredLevel uses max of reqLevel and train level", function()
        -- Plate helm req 35, paladin trains plate at 40
        local eff = IU.EffectiveRequiredLevel("PALADIN", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(40, eff)
        -- Cloth hood req 20
        local eff2 = IU.EffectiveRequiredLevel("MAGE", "|Hitem:1:0|h[Cloth Hood]|h")
        assert.are.equal(20, eff2)
    end)

    it("IsEquippableWithin allows item within levelsAhead", function()
        local ok, inLevels = IU.IsEquippableWithin(
            "MAGE", 18, "|Hitem:1:0|h[Cloth Hood]|h", 5)
        assert.is_true(ok)
        assert.are.equal(2, inLevels)
    end)

    it("IsEquippableWithin rejects class that can never use armor", function()
        local ok = IU.IsEquippableWithin(
            "MAGE", 60, "|Hitem:2:0|h[Plate Helm]|h", 0)
        assert.is_false(ok)
    end)

    it("GetItemUseInfo returns reqLevel and armor subclass", function()
        local req, armor, weapon = IU.GetItemUseInfo("|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(35, req)
        assert.are.equal("Plate", armor)
        assert.is_nil(weapon)
    end)

    it("GetItemUseInfo uses minLevel not itemLevel when they differ", function()
        local req = IU.GetItemUseInfo("|Hitem:9:0|h[Epic Helm]|h")
        assert.are.equal(60, req)
        assert.are.equal(60, IU.GetItemMinLevel("|Hitem:9:0|h[Epic Helm]|h"))
    end)

    it("GetEquipWarnings uses minLevel not itemLevel for level requirement", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 65, "Alt", "|Hitem:9:0|h[Epic Helm]|h")
        assert.are.equal(0, #warnings)
        warnings = IU.GetEquipWarnings("MAGE", 55, "Alt", "|Hitem:9:0|h[Epic Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Alt", "MAGE") .. " must gain 5 levels to equip this",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.LEVEL, warnings[1].kind)
    end)

    it("GetProficiencySkillName maps plate armor", function()
        assert.are.equal("Plate Armor", IU.GetProficiencySkillName("Armor", "Plate"))
    end)

    it("GetProficiencySkillName maps one-handed swords", function()
        assert.are.equal("One-Handed Swords", IU.GetProficiencySkillName("Weapon", "One-Handed Swords"))
    end)

    it("ValidateItemCheckDrop accepts equippable non-soulbound items", function()
        local ok, err = IU.ValidateItemCheckDrop("|Hitem:1:0|h[Cloth Hood]|h")
        assert.is_true(ok)
        assert.is_nil(err)
    end)

    it("ValidateItemCheckDrop rejects non-equippable items", function()
        local ok, err = IU.ValidateItemCheckDrop("|Hitem:8:0|h[Health Potion]|h")
        assert.is_false(ok)
        assert.are.equal("This item cannot be equipped.", err)
    end)

    it("ValidateItemCheckDrop accepts soulbound equippable items", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local ok, err = iu.ValidateItemCheckDrop("|Hitem:1:0|h[Cloth Hood]|h")
        assert.is_true(ok)
        assert.is_nil(err)
    end)

    it("GetEquipWarnings includes soulbound message", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Binds when picked up" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Alt", "|Hitem:1:0|h[Cloth Hood]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            "Cloth Hood is soulbound to " .. coloredName("Alt", "MAGE"),
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.SOULBOUND, warnings[1].kind)
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
    end)

    it("GetEquipWarnings soulbound message uses current character name when available", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Binds when picked up" end,
        }
        _G.AltArmy = _G.AltArmy or {}
        local savedDS = _G.AltArmy.DataStore
        _G.AltArmy.DataStore = {
            GetCurrentCharacter = function()
                return { name = "Hero", classFile = "WARRIOR" }
            end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Alt", "|Hitem:1:0|h[Cloth Hood]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            "Cloth Hood is soulbound to " .. coloredName("Hero", "WARRIOR"),
            warningText(warnings[1]))
        _G.AltArmy.DataStore = savedDS
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
    end)

    it("GetEquipWarnings soulbound message uses This item when name exceeds 30 characters", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Binds when picked up" end,
        }
        local longName = string.rep("A", 31)
        _G.GetItemInfo = function(item)
            if tostring(item):find("item:14:") or item == 14 then
                return longName, "|Hitem:14:0|h[" .. longName .. "]|h"
            end
            return mockGetItemInfo(item)
        end
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Alt", "|Hitem:14:0|h[Long]|h")
        assert.are.equal(
            "This item is soulbound to " .. coloredName("Alt", "MAGE"),
            warningText(warnings[1]))
        _G.GetItemInfo = mockGetItemInfo
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
    end)

    it("RequiresTrainerProficiency is true only for plate and class mail", function()
        assert.is_true(IU.RequiresTrainerProficiency("PALADIN", "Plate", "Armor"))
        assert.is_true(IU.RequiresTrainerProficiency("HUNTER", "Mail", "Armor"))
        assert.is_false(IU.RequiresTrainerProficiency("PALADIN", "Mail", "Armor"))
        assert.is_false(IU.RequiresTrainerProficiency("MAGE", "Cloth", "Armor"))
    end)

    it("GetEquipWarnings uses item level suffix when item level exceeds training level", function()
        _G.IsUsableItem = nil
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 2 then
                return "Plate Helm", "|Hitem:2:0|h[Plate Helm]|h", 3, 35, 45,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        local warnings = IU.GetEquipWarnings("PALADIN", 38, "Tome", "|Hitem:2:0|h[Plate Helm]|h")
        _G.GetItemInfo = oldGetItemInfo
        if IU.ClearCache then
            IU.ClearCache()
        end
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must gain 7 levels to equip this",
            warningText(warnings[1]))
    end)

    it("GetEquipWarnings includes level requirement for selected character", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("PALADIN", 35, "Tome", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must gain 5 levels to equip this",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.LEVEL, warnings[1].kind)
    end)

    it("GetEquipWarnings shows first name only and keeps full name for tooltip", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings(
            "PALADIN", 35, "Tome Lightbringer", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must gain 5 levels to equip this",
            warningText(warnings[1]))
        assert.are.equal("Tome Lightbringer", warnings[1].charName)
        assert.are.equal("PALADIN", warnings[1].classFile)
        assert.are.equal(coloredName("Tome", "PALADIN"), warnings[1].nameText)
    end)

    it("GetEquipWarnings includes proficiency training when skill is missing", function()
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        _G.IsUsableItem = function() return false end
        local warnings = IU.GetEquipWarnings("PALADIN", 60, "Tome", "|Hitem:2:0|h[Plate Helm]|h", nil)
        _G.IsUsableItem = nil
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must train Plate Armor to equip this",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.TRAINING, warnings[1].kind)
    end)

    it("GetEquipWarnings omits training when current character can use the item", function()
        _G.IsUsableItem = function() return true end
        _G.UnitName = function() return "Tome" end
        _G.UnitClass = function() return "Paladin", "PALADIN" end
        local warnings = IU.GetEquipWarnings(
            "PALADIN",
            60,
            "Tome",
            "|Hitem:2:0|h[Plate Helm]|h",
            { name = "Tome", classFile = "PALADIN" })
        _G.IsUsableItem = nil
        _G.UnitName = nil
        _G.UnitClass = nil
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings omits training when alt wears that armor type", function()
        local charData = {
            name = "Tome",
            classFile = "PALADIN",
            Inventory = { [1] = "|Hitem:2:0|h[Plate Helm]|h" },
        }
        local warnings = IU.GetEquipWarnings(
            "PALADIN", 60, "Tome", "|Hitem:2:0|h[Plate Helm]|h", charData)
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings never shows training for cloth armor", function()
        _G.IsUsableItem = function() return false end
        local warnings = IU.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:1:0|h[Cloth Hood]|h", nil)
        _G.IsUsableItem = nil
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings reports class proficiency the character can never learn", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.NEVER, warnings[1].kind)
    end)

    it("GetEquipWarnings omits level warnings when the character can never equip", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 10, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.NEVER, warnings[1].kind)
    end)

    it("GetEquipWarnings can return soulbound and never-equip messages together", function()
        _G.IsUsableItem = nil
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        assert.are.equal(2, #warnings)
        assert.are.equal(
            "Plate Helm is soulbound to " .. coloredName("Merlin", "MAGE"),
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.SOULBOUND, warnings[1].kind)
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warningText(warnings[2]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.NEVER, warnings[2].kind)
    end)

    it("GetEquipWarnings can return multiple messages", function()
        _G.IsUsableItem = function() return false end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("PALADIN", 35, "Tome", "|Hitem:2:0|h[Plate Helm]|h")
        _G.IsUsableItem = nil
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        assert.are.equal(2, #warnings)
        assert.are.equal(
            "Plate Helm is soulbound to " .. coloredName("Tome", "PALADIN"),
            warningText(warnings[1]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.SOULBOUND, warnings[1].kind)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must gain 5 levels to equip this",
            warningText(warnings[2]))
        assert.are.equal(IU.EQUIP_WARNING_KIND.LEVEL, warnings[2].kind)
    end)

    describe("LacksTrainedProficiency", function()
        local mail = "|Hitem:3:0|h[Mail Vest]|h"

        after_each(function()
            _G.IsSpellKnown = nil
            _G.IsUsableItem = nil
            _G.UnitName = nil
            _G.UnitClass = nil
        end)

        it("is true for a shaman's mail before it is trained, whatever the level", function()
            assert.is_true(IU.LacksTrainedProficiency("SHAMAN", mail, { name = "Thrall" }))
            local ok = IU.IsEquippableWithin("SHAMAN", 45, mail, 0)
            assert.is_true(ok)
        end)

        it("is false once the shaman wears mail", function()
            local charData = { name = "Thrall", Inventory = { [5] = mail } }
            assert.is_false(IU.LacksTrainedProficiency("SHAMAN", mail, charData))
        end)

        it("asks IsSpellKnown for the current character", function()
            _G.UnitName = function() return "Thrall" end
            _G.UnitClass = function() return "Shaman", "SHAMAN" end
            _G.IsUsableItem = function() return true end
            local asked
            _G.IsSpellKnown = function(id) asked = id; return false end
            assert.is_true(IU.LacksTrainedProficiency("SHAMAN", mail, { name = "Thrall" }))
            assert.are.equal(8737, asked)
            _G.IsSpellKnown = function() return true end
            assert.is_false(IU.LacksTrainedProficiency("SHAMAN", mail, { name = "Thrall" }))
        end)

        it("is false for armor that needs no training or that the class can never wear", function()
            assert.is_false(IU.LacksTrainedProficiency("WARRIOR", mail, nil))
            assert.is_false(IU.LacksTrainedProficiency("MAGE", mail, nil))
            assert.is_false(IU.LacksTrainedProficiency("SHAMAN", "|Hitem:1:0|h[Cloth Hood]|h", nil))
            assert.is_false(IU.LacksTrainedProficiency("SHAMAN", "|Hitem:7:0|h[Shield]|h", nil))
        end)
    end)

    describe("per-link cache", function()
        local getItemInfoCalls

        local function countingGetItemInfo(item)
            getItemInfoCalls = getItemInfoCalls + 1
            return mockGetItemInfo(item)
        end

        before_each(function()
            getItemInfoCalls = 0
            _G.GetItemInfo = countingGetItemInfo
            if IU.ClearCache then
                IU.ClearCache()
            end
        end)

        it("GetWeaponRole caches resolved links", function()
            local link = "|Hitem:5:0|h[Sword]|h"
            assert.are.equal("onehand", IU.GetWeaponRole(link))
            assert.are.equal("onehand", IU.GetWeaponRole(link))
            assert.are.equal(2, getItemInfoCalls)
        end)

        it("GetInventorySlotsForItem caches resolved links", function()
            local link = "|Hitem:4:0|h[Ring]|h"
            assert.are.same({ 11, 12 }, IU.GetInventorySlotsForItem(link))
            assert.are.same({ 11, 12 }, IU.GetInventorySlotsForItem(link))
            assert.are.equal(2, getItemInfoCalls)
        end)

        it("EffectiveRequiredLevel caches per class and link", function()
            local link = "|Hitem:5:0|h[Sword]|h"
            assert.are.equal(10, IU.EffectiveRequiredLevel("WARRIOR", link))
            assert.are.equal(10, IU.EffectiveRequiredLevel("WARRIOR", link))
            assert.are.equal(1, getItemInfoCalls)
        end)

        it("CanNeverUseItem caches per class and link", function()
            local link = "|Hitem:6:0|h[Wand]|h"
            assert.is_true(IU.CanNeverUseItem("WARRIOR", link))
            assert.is_true(IU.CanNeverUseItem("WARRIOR", link))
            assert.are.equal(1, getItemInfoCalls)
        end)

        it("ClearCache forces re-resolution", function()
            local link = "|Hitem:5:0|h[Sword]|h"
            IU.GetWeaponRole(link)
            IU.ClearCache()
            IU.GetWeaponRole(link)
            assert.are.equal(4, getItemInfoCalls)
        end)
    end)
end)
