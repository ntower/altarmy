--[[
  Unit tests for GearUpgrade.lua.
  Run from project root: npm test
]]

describe("GearUpgrade", function()
    local GU
    local DS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [12] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [50] = { "Sparkling Wand", nil, 2, 25, 25, "Weapon", "Wand", nil, "INVTYPE_RANGEDRIGHT" },
            [80] = { "Heal Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [81] = { "Dmg Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [60] = { "Hit Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
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
        if id == 13 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
        end
        if id == 50 then
            return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 15.5, ["ITEM_MOD_INTELLECT_SHORT"] = 5 }
        end
        if id == 51 then
            return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.0, ["ITEM_MOD_INTELLECT_SHORT"] = 5 }
        end
        if id == 60 then
            return { ["ITEM_MOD_HIT_RATING_SHORT"] = 10, ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = 10 }
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
                },
            },
        }
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmy.DB = _G.AltArmyTBC_Data
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_Options = { realmFilter = "all" }
        _G.AltArmy.GlobalRealmFilter = {
            Get = function() return "all" end,
        }
        _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
            SHAMAN = { r = 0, g = 0.44, b = 0.87 },
            MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        }
        package.loaded["ClassColor"] = nil
        require("ClassColor")
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        package.loaded["DataStoreCharacter"] = nil
        require("DataStoreCharacter")
        package.loaded["DataStoreMail"] = nil
        require("DataStoreMail")
        DS = AltArmy.DataStore
        DS.accountData = _G.AltArmyTBC_Data
        AltArmy.DB = _G.AltArmyTBC_Data
        DS.GetCurrentPlayerRealm = function() return "TestRealm" end
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
        package.loaded["PawnScalesForever"] = nil
        require("PawnScalesForever")
        package.loaded["CharKey"] = nil
        require("CharKey")
        package.loaded["BankAlt"] = nil
        require("BankAlt")
        package.loaded["GearUpgrade"] = nil
        require("GearUpgrade")
        GU = AltArmy.GearUpgrade
        if GU.ResetFocusPass then
            GU.ResetFocusPass()
        end
        if AltArmy.ItemUsability and AltArmy.ItemUsability.ClearCache then
            AltArmy.ItemUsability.ClearCache()
        end
    end)

    before_each(function()
        if GU and GU.ResetFocusPass then
            GU.ResetFocusPass()
        end
        if AltArmy.ItemUsability and AltArmy.ItemUsability.ClearCache then
            AltArmy.ItemUsability.ClearCache()
        end
        if AltArmy.BankAlt then
            _G.AltArmyTBC_Options.bankAlts = {}
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
    end)

    it("ScoreItemCustom sums stat weights", function()
        local score = GU.ScoreItemCustom("|Hitem:11:0|h[New Helm]|h", "MAGE", "frost")
        assert.is_true(score > 0)
    end)

    it("ScoreItemCustom values wand ranged_dps for leveling mages", function()
        local wand = "|Hitem:50:0|h[Sparkling Wand]|h"
        local leveling = GU.ScoreItemCustom(wand, "MAGE", "frost", 30)
        local maxLevel = GU.ScoreItemCustom(wand, "MAGE", "frost", 70)
        local nilLevel = GU.ScoreItemCustom(wand, "MAGE", "frost")
        assert.is_true(leveling > maxLevel)
        assert.are.equal(maxLevel, nilLevel)
        local weights = GU.GetWeights("MAGE", "frost", 30)
        assert.are.equal(3.5, weights.ranged_dps)
        assert.are.equal(0.25, weights.melee_dps)
        assert.are.equal(0, GU.GetWeights("MAGE", "frost", 70).ranged_dps or 0)
    end)

    it("ScoreItemCustom does not dedupe when an item carries both hit and spell_hit", function()
        -- Documents current (non-deduped) summing behavior: GU.ScoreItemCustom
        -- sums value*weight per stat key independently, with no special-casing
        -- for a stat pair that happens to represent "the same" underlying
        -- concept (relevant since WoW Forever's merged Pawn scales write the
        -- same weight into both the hit and spell_hit keys).
        local ring = "|Hitem:60:0|h[Hit Ring]|h"
        local weights = GU.GetWeights("PALADIN", "retribution")
        local expected = 10 * weights.hit + 10 * weights.spell_hit
        local score = GU.ScoreItemCustom(ring, "PALADIN", "retribution")
        assert.are.equal(expected, score)
    end)

    describe("WoW Forever scale selection", function()
        after_each(function()
            AltArmy.DataStore.IsWowForever = nil
        end)

        it("uses PawnScales (TBC) weights when IsWowForever is false/unset", function()
            AltArmy.DataStore.IsWowForever = nil
            local weights = GU.GetWeights("MAGE", "frost")
            assert.is_nil(weights.hit)
            assert.are.equal(1.22, weights.spell_hit)
        end)

        it("uses PawnScalesForever's merged weights when IsWowForever is true", function()
            AltArmy.DataStore.IsWowForever = true
            local weights = GU.GetWeights("MAGE", "frost")
            assert.are.equal(1.22, weights.hit)
            assert.are.equal(1.22, weights.spell_hit)
        end)
    end)

    it("ScoreItem memoizes separately for leveling vs max-level weights", function()
        local wand = "|Hitem:50:0|h[Sparkling Wand]|h"
        GU.ResetFocusPass()
        local leveling = GU.ScoreItem(wand, "custom", "MAGE", "frost", 30)
        local maxLevel = GU.ScoreItem(wand, "custom", "MAGE", "frost", 70)
        assert.is_true(leveling > maxLevel)
        assert.are.equal(leveling, GU.ScoreItem(wand, "custom", "MAGE", "frost", 30))
        assert.are.equal(maxLevel, GU.ScoreItem(wand, "custom", "MAGE", "frost", 70))
    end)

    -- Repro: compare panel showed Weighted +100% while every stat row dropped.
    -- ScoreItem memoized 0 while ItemStats was still pending; rows later used
    -- refreshed GetNormalized stats, but summary.oldTotal stayed 0.
    it("ScoreItem recomputes after ItemStats pending resolves", function()
        local IS = AltArmy.ItemStats
        local link = "|Hitem:11:0|h[New Helm]|h"
        IS.ClearCache()
        GU.InvalidateScoreDependentMemos()

        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function()
            return nil
        end
        local pendingScore = GU.ScoreItem(link, "custom", "MAGE", "frost")
        assert.are.equal(0, pendingScore)
        assert.are.equal("pending", IS.GetSource(link))

        _G.GetItemInfo = oldGetItemInfo
        local stats = IS.GetNormalized(link)
        assert.is_true((stats.int or 0) > 0)

        local scoreAfter = GU.ScoreItem(link, "custom", "MAGE", "frost")
        assert.is_true(scoreAfter > 0)

        local breakdown = GU.BuildScoreBreakdown(link, "custom", "MAGE", "frost")
        assert.is_not_nil(breakdown)
        assert.is_true(breakdown.weightedSum > 0)
        assert.are.equal(breakdown.weightedSum, breakdown.total)
    end)

    it("ScoreItemCustom uses item required level when higher than character level", function()
        local endgameWand = "|Hitem:90:0|h[Endgame Wand]|h"
        local midWand = "|Hitem:91:0|h[Mid Wand]|h"
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 90 then
                return "Endgame Wand", endgameWand, 4, 100, 70, "Weapon", "Wand", nil,
                    "INVTYPE_RANGEDRIGHT"
            end
            if id == 91 then
                return "Mid Wand", midWand, 3, 50, 35, "Weapon", "Wand", nil,
                    "INVTYPE_RANGEDRIGHT"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 90 or id == 91 then
                return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 20 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemUsability and AltArmy.ItemUsability.ClearCache then
            AltArmy.ItemUsability.ClearCache()
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end

        local at20For70 = GU.ScoreItemCustom(endgameWand, "MAGE", "frost", 20)
        local at70 = GU.ScoreItemCustom(endgameWand, "MAGE", "frost", 70)
        assert.are.equal(at70, at20For70)
        assert.are.equal(0, GU.GetWeights("MAGE", "frost", 70).ranged_dps or 0)

        local at20For35 = GU.ScoreItemCustom(midWand, "PRIEST", "shadow", 20)
        local at35 = GU.ScoreItemCustom(midWand, "PRIEST", "shadow", 35)
        assert.are.equal(at35, at20For35)
        assert.is_true(at20For35 > GU.ScoreItemCustom(midWand, "PRIEST", "shadow", 70))

        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("ResolveCompareContext returns character level", function()
        local char = { classFile = "MAGE", level = 42, talents = { primary = 3, specKey = "frost" } }
        local entry = { classFile = "MAGE", level = 42 }
        local classFile, specKey, level = GU.ResolveCompareContext(char, entry)
        assert.are.equal("MAGE", classFile)
        assert.are.equal("frost", specKey)
        assert.are.equal(42, level)
    end)

    it("FormatCompareSpecWarningText describes assumed spec with class-colored name", function()
        local text = GU.FormatCompareSpecWarningText("Totem", "Enhancement", "SHAMAN")
        assert.is_true(text:find("|cff", 1, true) ~= nil)
        assert.is_true(text:find("Totem", 1, true) ~= nil)
        assert.matches("spec is unknown%. Assuming Enhancement", text)
    end)

    it("FormatCompareSpecWarningText shows first name only", function()
        local text = GU.FormatCompareSpecWarningText("Totem Earthsong", "Enhancement", "SHAMAN")
        assert.is_true(text:find("Totem", 1, true) ~= nil)
        assert.is_nil(text:find("Earthsong", 1, true))
    end)

    it("GetCompareRealmWarning flags a character on another server by first name", function()
        local w = GU.GetCompareRealmWarning(
            { name = "Totem Earthsong", realm = "Faerlina", classFile = "SHAMAN" }, "Benediction", false)
        assert.are.equal("different_realm", w.kind)
        assert.are.equal("Totem Earthsong", w.charName)
        assert.are.equal("SHAMAN", w.classFile)
        assert.are.equal(w.nameText .. " is on a different server", w.text)
        assert.is_nil(w.text:find("Earthsong", 1, true))
    end)

    it("GetCompareRealmWarning says ruleset on WoW Forever", function()
        local w = GU.GetCompareRealmWarning(
            { name = "Totem", realm = "Hardcore", classFile = "SHAMAN" }, "Normal", true)
        assert.matches("is on a different ruleset$", w.text)
    end)

    it("GetCompareRealmWarning is nil on the same realm or unknown realm", function()
        assert.is_nil(GU.GetCompareRealmWarning({ name = "A", realm = "X" }, "X", false))
        assert.is_nil(GU.GetCompareRealmWarning({ name = "A", realm = "" }, "X", false))
        assert.is_nil(GU.GetCompareRealmWarning({ name = "A", realm = "X" }, "", false))
        assert.is_nil(GU.GetCompareRealmWarning(nil, "X", false))
    end)

    it("GetCompareSpecWarning when talent data is missing", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function(name)
                if name == "NoTalents" then
                    return { hasMissing = true, instructions = { "* Log in with this character" } }
                end
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = { classFile = "SHAMAN" }
        local entry = {
            name = "NoTalents",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.is_truthy(warning)
        assert.are.equal("missing_spec", warning.kind)
        assert.matches("NoTalents", warning.text)
        assert.matches("spec is unknown", warning.text)
        assert.matches("Enhancement", warning.text)
        assert.are.equal("Enhancement", warning.assumedSpec)
    end)

    it("GetCompareSpecWarning is nil when talent data shows a picked spec", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function()
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = {
            classFile = "MAGE",
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        assert.is_nil(GU.GetCompareSpecWarning(entry, char))
    end)

    it("GetCompareSpecWarning uses unpicked message when talents scanned but no points spent", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function()
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = {
            classFile = "SHAMAN",
            talents = { tabs = { 0, 0, 0 }, primary = nil, specKey = nil },
        }
        local entry = {
            name = "FreshSixty",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.is_truthy(warning)
        assert.are.equal("unpicked_spec", warning.kind)
        assert.are.equal("Assuming Enhancement spec for " .. warning.nameText, warning.text)
        assert.is_nil(warning.text:match("spec is unknown"))
        assert.matches("FreshSixty", warning.text)
    end)

    it("GetCompareSpecWarning uses unpicked message for low-level characters with talent data", function()
        local char = {
            classFile = "MAGE",
            talents = { tabs = { 0, 0, 0 }, primary = nil, specKey = nil },
        }
        local entry = { name = "Lowbie", realm = "TestRealm", classFile = "MAGE", level = 8 }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.are.equal("unpicked_spec", warning.kind)
        assert.matches("^Assuming %a+ spec for ", warning.text)
    end)

    it("ScoreItemCustom weights wand ranged_dps for hunters", function()
        local better = GU.ScoreItemCustom("|Hitem:50:0|h[Sparkling Wand]|h", "HUNTER", "beast")
        local worse = GU.ScoreItemCustom("|Hitem:51:0|h[Old Wand]|h", "HUNTER", "beast")
        assert.is_true(better > worse)
        assert.is_true(GU.CompareItems(
            "|Hitem:50:0|h[Sparkling Wand]|h",
            "|Hitem:51:0|h[Old Wand]|h",
            "custom",
            "HUNTER",
            "beast"))
    end)

    it("ScoreItemCustom values hunter ranged_dps heavily", function()
        local bowLink = "|Hitem:70:0|h[Bow]|h"
        local weakBowLink = "|Hitem:71:0|h[Weak Bow]|h"
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 70 then
                return "Strong Bow", bowLink, 3, 60, 60, "Weapon", "Bow", nil, "INVTYPE_RANGED"
            end
            if id == 71 then
                return "Weak Bow", weakBowLink, 2, 40, 40, "Weapon", "Bow", nil, "INVTYPE_RANGED"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 70 then
                return { ["ITEM_MOD_AGILITY_SHORT"] = 10, ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 50 }
            end
            if id == 71 then
                return { ["ITEM_MOD_AGILITY_SHORT"] = 10, ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 40 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local strong = GU.ScoreItemCustom(bowLink, "HUNTER", "beast")
        local weak = GU.ScoreItemCustom(weakBowLink, "HUNTER", "beast")
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
        assert.is_true(strong > weak)
        assert.is_true((strong - weak) > 20)
    end)

    it("ScoreItemCustom scores priest holy healing not spell damage", function()
        local healItem = "|Hitem:80:0|h[Heal Ring]|h"
        local dmgItem = "|Hitem:81:0|h[Dmg Ring]|h"
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 80 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10, ["ITEM_MOD_SPELL_HEALING_DONE"] = 50 }
            end
            if id == 81 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10, ["ITEM_MOD_SPELL_DAMAGE_DONE"] = 50 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local healScore = GU.ScoreItemCustom(healItem, "PRIEST", "holy")
        local dmgScore = GU.ScoreItemCustom(dmgItem, "PRIEST", "holy")
        _G.GetItemStats = oldGetItemStats
        assert.is_true(healScore > dmgScore)
    end)

    it("ScoreItemCustom scores fire mage fire spell damage", function()
        local fireItem = "|Hitem:82:0|h[Fire Staff]|h"
        local frostItem = "|Hitem:83:0|h[Frost Staff]|h"
        local oldGetItemStats = _G.GetItemStats
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    GetRegions = function() return end,
                    NumLines = function() return 0 end,
                    GetName = function() return "AltArmyTBC_ItemStatsScanTooltip" end,
                }
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 82 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10 }
            end
            if id == 83 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10 }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        AltArmy.ItemStats.ClearCache()
        local IS = AltArmy.ItemStats
        local oldGetNormalized = IS.GetNormalized
        local oldGetNormalizedRef = IS.GetNormalizedRef
        local function mockNormalized(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 82 then return { int = 10, fire_sp = 40, sp = 10 } end
            if id == 83 then return { int = 10, frost_sp = 40, sp = 10 } end
            return oldGetNormalized(link)
        end
        IS.GetNormalized = mockNormalized
        IS.GetNormalizedRef = mockNormalized
        local fireScore = GU.ScoreItemCustom(fireItem, "MAGE", "fire")
        local frostScore = GU.ScoreItemCustom(frostItem, "MAGE", "fire")
        IS.GetNormalized = oldGetNormalized
        IS.GetNormalizedRef = oldGetNormalizedRef
        _G.GetItemStats = oldGetItemStats
        assert.is_true(fireScore > frostScore)
    end)

    it("GetWeights returns weebly-derived weights for all classes", function()
        local classes = {
            "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
            "SHAMAN", "MAGE", "WARLOCK", "DRUID",
        }
        for i = 1, #classes do
            local classFile = classes[i]
            local w = GU.GetWeights(classFile, "unknown")
            assert.is_truthy(w, classFile .. " should have leveling weights")
            assert.is_true(next(w) ~= nil)
        end
        local hunter = GU.GetWeights("HUNTER", "beast")
        assert.are.equal(2.4, hunter.ranged_dps)
        assert.are.equal(1, hunter.agi)
    end)

    it("GetNormalizedItemStats delegates to ItemStats", function()
        local link = "|Hitem:11:0|h[New Helm]|h"
        local stats = GU.GetNormalizedItemStats(link)
        assert.are.equal(20, stats.int)
        assert.are.equal(10, stats.sta)
    end)

    it("CompareItems ilvl detects upgrade", function()
        local isUp = GU.CompareItems(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "ilvl",
            "MAGE",
            "frost")
        assert.is_true(isUp)
    end)

    it("EvaluateForAllAlts finds upgrade for alt", function()
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        assert.are.equal(1, #matches)
        assert.are.equal("MageAlt", matches[1].name)
        assert.is_true(matches[1].isUpgrade)
    end)

    it("EvaluateForAllAlts ignores GlobalRealmFilter and only matches current realm", function()
        _G.AltArmyTBC_Data.Characters.OtherRealm = {
            OtherMage = {
                name = "OtherMage",
                realm = "OtherRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
        }
        _G.AltArmy.GlobalRealmFilter = {
            Get = function() return "all" end,
        }
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        assert.are.equal(1, #matches)
        assert.are.equal("MageAlt", matches[1].name)
        assert.are.equal("TestRealm", matches[1].realm)
    end)

    it("EvaluateForAllAlts skips opposite-faction alts but keeps unknown faction", function()
        local savedUFG = _G.UnitFactionGroup
        _G.UnitFactionGroup = function() return "Alliance" end
        local chars = _G.AltArmyTBC_Data.Characters.TestRealm
        chars.MageAlt.faction = "Alliance"
        chars.HordeMage = {
            name = "HordeMage",
            realm = "TestRealm",
            faction = "Horde",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        chars.OldMage = {
            name = "OldMage",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local entries = GU.BuildFocusEntriesForCurrentRealm()
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        chars.HordeMage = nil
        chars.OldMage = nil
        chars.MageAlt.faction = nil
        _G.UnitFactionGroup = savedUFG
        local names = {}
        for i = 1, #entries do names[entries[i].name] = true end
        assert.is_nil(names.HordeMage)
        assert.is_true(names.MageAlt)
        assert.is_true(names.OldMage)
        for i = 1, #matches do
            assert.are_not.equal("HordeMage", matches[i].name)
        end
    end)

    it("EvaluateForAllAlts skips bank alts", function()
        AltArmy.BankAlt.Set("MageAlt", "TestRealm", true)
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        assert.are.equal(0, #matches)
    end)

    it("EvaluateForAllAlts matches gear tab: only in-range clear upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 13 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
            end
            if id == 10 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
            end
            return oldGetItemStats(link)
        end
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 5,
        })
        assert.are.equal(2, #matches)
        local names = {}
        for i = 1, #matches do names[i] = matches[i].name end
        assert.are.equal("MageAlt", names[1])
        assert.are.equal("SidegradeAlt", names[2])
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("EvaluateForAllAlts sorts matches in gear tab focus order", function()
        _G.AltArmyTBC_Data.Characters.TestRealm = {
            MageAlt = {
                name = "MageAlt",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
            SmallUpgrader = {
                name = "SmallUpgrader",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
            BigUpgrader = {
                name = "BigUpgrader",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
        }
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        local names = {}
        for i = 1, #matches do names[i] = matches[i].name end
        assert.are.equal(3, #names)
        assert.are.equal("BigUpgrader", names[1])
        assert.are.equal("MageAlt", names[2])
        assert.are.equal("SmallUpgrader", names[3])
    end)

    it("EvaluateForCharacter uses opts.level override for level-up scans", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local link = "|Hitem:11:0|h[New Helm]|h"
        local opts = { technique = "ilvl", levelsAhead = 0 }
        assert.is_true(GU.EvaluateForCharacter(char, link, { technique = "ilvl", levelsAhead = 0, level = 60 }))
        assert.is_false(GU.EvaluateForCharacter(char, link, { technique = "ilvl", levelsAhead = 0, level = 28 }))
        assert.is_true(GU.EvaluateForCharacter(char, link, opts))
    end)

    it("GetUpgradePercentForCharacter returns the weighted change vs equipped, nil when not an upgrade", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local link = "|Hitem:11:0|h[New Helm]|h"
        -- ilvl 35 over an equipped ilvl 20: +75%.
        assert.are.equal(75, GU.GetUpgradePercentForCharacter(char, link, { technique = "ilvl", levelsAhead = 0 }))
        assert.is_nil(GU.GetUpgradePercentForCharacter(char, link, { technique = "ilvl", levelsAhead = 0, level = 28 }))
        assert.is_nil(GU.GetUpgradePercentForCharacter(char, "|Hitem:10:0|h[Old Helm]|h",
            { technique = "ilvl", levelsAhead = 0 }))
    end)

    it("EnsureGearUpgradeOptions applies defaults", function()
        _G.AltArmyTBC_Options = {}
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_true(opts.notifyCurrentCharacter)
        assert.is_true(opts.notifyOtherCharacters)
        assert.is_true(opts.showQuestRewardUpgradeIndicator)
        assert.is_true(opts.showQuestRewardVendorIndicator)
        assert.are.equal("custom", opts.technique)
        assert.are.equal(5, opts.levelsAhead)
        assert.are.equal(5, opts.upgradeThresholdPercent)
    end)

    it("GetUpgradeHighlightKind uses equipped-relative percent vs threshold", function()
        -- 3/35 ≈ 8.6%: clear at 5%, minor at 50%
        assert.are.equal("clear", GU.GetUpgradeHighlightKind(3, 35, { upgradeThresholdPercent = 5 }))
        assert.are.equal("minor", GU.GetUpgradeHighlightKind(3, 35, { upgradeThresholdPercent = 50 }))
        -- empty equipped baseline → 100% → clear
        assert.are.equal("clear", GU.GetUpgradeHighlightKind(10, 0, { upgradeThresholdPercent = 5 }))
        assert.are.equal("clear", GU.GetUpgradeHighlightKind(10, nil, { upgradeThresholdPercent = 5 }))
    end)

    it("GetWeightedChangeColor uses threshold bands and smooth blends", function()
        local opts = { upgradeThresholdPercent = 10 }
        local gr, gg, gb = GU.GetWeightedChangeColor(10, opts)
        assert.are.equal(0.2, gr)
        assert.are.equal(1, gg)
        assert.are.equal(0.2, gb)
        local rr, rg, rb = GU.GetWeightedChangeColor(-10, opts)
        assert.are.equal(1, rr)
        assert.are.equal(0.4, rg)
        assert.are.equal(0.3, rb)
        local yr, yg, yb = GU.GetWeightedChangeColor(0, opts)
        assert.are.equal(1, yr)
        assert.are.equal(0.82, yg)
        assert.are.equal(0, yb)
        local midUpR, midUpG, midUpB = GU.GetWeightedChangeColor(5, opts)
        assert.is_true(math.abs(0.6 - midUpR) < 0.001)
        assert.is_true(math.abs(0.91 - midUpG) < 0.001)
        assert.is_true(math.abs(0.1 - midUpB) < 0.001)
        local midDownR, midDownG, midDownB = GU.GetWeightedChangeColor(-5, opts)
        assert.is_true(math.abs(1 - midDownR) < 0.001)
        assert.is_true(math.abs(0.61 - midDownG) < 0.001)
        assert.is_true(math.abs(0.15 - midDownB) < 0.001)
    end)

    it("ResolveUpgradeThresholdPercent clamps to 0-100", function()
        assert.are.equal(5, GU.ResolveUpgradeThresholdPercent(nil))
        assert.are.equal(0, GU.ResolveUpgradeThresholdPercent(-10))
        assert.are.equal(100, GU.ResolveUpgradeThresholdPercent(150))
    end)

    it("EnsureGearUpgradeOptions migrates legacy enabled to both notification toggles", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = { enabled = false, technique = "ilvl", levelsAhead = 0 },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_false(opts.notifyCurrentCharacter)
        assert.is_false(opts.notifyOtherCharacters)
        assert.are.equal("custom", opts.technique)
        assert.are.equal(0, opts.levelsAhead)
    end)

    it("EnsureGearUpgradeOptions preserves explicit notification toggles", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = {
                notifyCurrentCharacter = true,
                notifyOtherCharacters = false,
                levelsAhead = 3,
            },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_true(opts.notifyCurrentCharacter)
        assert.is_false(opts.notifyOtherCharacters)
        assert.are.equal(3, opts.levelsAhead)
    end)

    it("GetProviders lists techniques in display order", function()
        local providers = GU.GetProviders()
        assert.are.equal("custom", providers[1].id)
        assert.are.equal("ilvl", providers[2].id)
        assert.are.equal("gearscore", providers[3].id)
    end)

    it("GetProviderDisplayLabel marks not-recommended techniques", function()
        assert.are.equal("Alt Army", GU.GetProviderDisplayLabel(GU.GetProvider("custom")))
        assert.are.equal(
            "Item Level |cffFF664C(not recommended)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("ilvl")))
        assert.are.equal(
            "Gear Score |cffFF664C(not recommended)|r |cffaaaaaa(not installed)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("gearscore")))
    end)

    it("GetProviders lists all techniques", function()
        local providers = GU.GetProviders()
        local ids = {}
        for i = 1, #providers do ids[providers[i].id] = true end
        assert.is_true(ids.ilvl)
        assert.is_true(ids.custom)
        assert.is_true(ids.gearscore)
    end)

    it("GetEffectiveTechnique migrates removed pawn and sgj to custom", function()
        assert.are.equal("custom", GU.GetEffectiveTechnique("pawn"))
        assert.are.equal("custom", GU.GetEffectiveTechnique("sgj"))
    end)

    it("EnsureGearUpgradeOptions always uses custom comparison technique", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = { enabled = true, technique = "pawn", levelsAhead = 5 },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
        _G.AltArmyTBC_Options.gearUpgrades.technique = "sgj"
        opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
        _G.AltArmyTBC_Options.gearUpgrades.technique = "ilvl"
        opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
    end)

    it("GetCharacterUpgradeDelta returns score difference for ilvl technique", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local delta = GU.GetCharacterUpgradeDelta(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.are.equal(15, delta)
    end)

    it("GetFocusUpgradeDelta is zero for non-upgrade characters", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local delta = GU.GetFocusUpgradeDelta(entry, char, worseLink, { technique = "ilvl" })
        assert.are.equal(0, delta)
    end)

    it("GetSlotUpgradeDelta compares one inventory slot at a time", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.RingAlt = {
            name = "RingAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = {
                [11] = "|Hitem:22:0|h[Ring One]|h",
                [12] = "|Hitem:21:0|h[Ring Two]|h",
            },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local ringLink = "|Hitem:20:0|h[New Ring]|h"
        local slot11 = GU.GetSlotUpgradeDelta(char, ringLink, 11, { technique = "ilvl" })
        local slot12 = GU.GetSlotUpgradeDelta(char, ringLink, 12, { technique = "ilvl" })
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(10, slot11)
        assert.are.equal(20, slot12)
    end)

    it("GetBestFocusCompareSlot picks the ring with the biggest upgrade", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.RingAlt = {
            name = "RingAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = {
                [11] = "|Hitem:22:0|h[Ring One]|h",
                [12] = "|Hitem:21:0|h[Ring Two]|h",
            },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local entry = { name = "RingAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local ringLink = "|Hitem:20:0|h[New Ring]|h"
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries({ entry }, ringLink, opts)
        local slot = GU.GetBestFocusCompareSlot(entry, char, ringLink, { 11, 12 }, opts, upgradeMaxDelta)
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(12, slot)
    end)

    it("GetSlotCompareDelta is negative for downgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local delta = GU.GetSlotCompareDelta(char, worseLink, 1, { technique = "ilvl" })
        assert.is_true(delta < 0)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("GetSlotCompareDelta treats zero-score item vs equipped gear as downgrade", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Useless Helm", "|Hitem:99:0|h[Useless Helm]|h", 0, 1, 1,
                    "Armor", "Cloth", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 99 then return {} end
            return oldGetItemStats(link)
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local uselessLink = "|Hitem:99:0|h[Useless Helm]|h"
        local delta = GU.GetSlotCompareDelta(char, uselessLink, 1, { technique = "custom" })
        assert.is_true(delta < 0)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, uselessLink, 1, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Downgrade", verdict.label)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetSlotCompareDelta uses entry classFile and enhancement weights for shamans", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 98 then
                return "Monkey Greaves", "|Hitem:98:0|h[Monkey Greaves]|h", 0, 15, 15,
                    "Armor", "Mail", nil, "INVTYPE_FEET"
            end
            if id == 97 then
                return "Veteran Boots", "|Hitem:97:0|h[Veteran Boots]|h", 3, 45, 45,
                    "Armor", "Mail", nil, "INVTYPE_FEET"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 98 then
                return {
                    ["ITEM_MOD_AGILITY_SHORT"] = 8,
                    ["ITEM_MOD_STAMINA_SHORT"] = 8,
                }
            end
            if id == 97 then
                return {
                    ["ITEM_MOD_AGILITY_SHORT"] = 12,
                    ["ITEM_MOD_STAMINA_SHORT"] = 12,
                }
            end
            return oldGetItemStats(link)
        end
        local char = {
            classFile = "",
            Inventory = { [8] = "|Hitem:97:0|h[Veteran Boots]|h" },
        }
        local entry = {
            name = "Totem",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local classFile, specKey = GU.ResolveCompareContext(char, entry)
        assert.are.equal("SHAMAN", classFile)
        assert.are.equal("enhancement", specKey)
        local monkeyLink = "|Hitem:98:0|h[Monkey Greaves]|h"
        local delta = GU.GetSlotCompareDelta(char, monkeyLink, 8, { technique = "custom" }, entry)
        assert.is_true(delta < 0)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, monkeyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Downgrade", verdict.label)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetFocusCellBadgeKind returns unusable for equippable worse item", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 98 then
                return "Crappy Boots", "|Hitem:98:0|h[Crappy Boots]|h", 0, 30, 30,
                    "Armor", "Cloth", nil, "INVTYPE_FEET"
            end
            if id == 97 then
                return "Veteran Boots", "|Hitem:97:0|h[Veteran Boots]|h", 0, 30, 30,
                    "Armor", "Cloth", nil, "INVTYPE_FEET"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 98 or id == 97 then return {} end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[8] = "|Hitem:97:0|h[Veteran Boots]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 20 }
        local crappyLink = "|Hitem:98:0|h[Crappy Boots]|h"
        local info = GU.ClassifyFocusSlot(entry, char, crappyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal(GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND, info.category)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, crappyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Eventual sidegrade", verdict.label)
        char.Inventory[8] = nil
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetFocusCellBadgeKind returns unusable for equippable worse item", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, worseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("unusable", kind)
    end)

    it("GetFocusCellBadgeKind returns white plus when upgrade is beyond level threshold", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local char = DS:GetCharacter("LowLevel", "TestRealm")
        local entry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("upgradeFuture", kind)
    end)

    it("GetFocusCellBadgeKind returns upgrade for equippable clear upgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("upgrade", kind)
    end)

    it("HasAnyFocusUpgradeOrEventual is true when a character has a clear upgrade", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
    end)

    it("HasAnyFocusUpgradeOrEventual is true for eventual upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
    end)

    it("HasAnyFocusUpgradeOrEventual is true for in-range sidegrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("HasAnyFocusUpgradeOrEventual is false when no character has a comparable focus result", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local itemLink = "|Hitem:10:0|h[Old Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_false(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("GetFocusVerdictForSlot returns colored verdict labels", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Upgrade", verdict.label)
        assert.are.equal(0.2, verdict.r)
    end)

    it("GetFocusVerdictForSlot returns Downgrade for worse items", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, worseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("Downgrade", verdict.label)
    end)

    it("GetFocusVerdictForSlot returns Sidegrade for minor weighted downgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local slightlyWorseLink = "|Hitem:13:0|h[Newer Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, slightlyWorseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
            -- -3 ilvl on equipped 35 ≈ -8.6%; keep at 10% so this stays in the sidegrade band
            upgradeThresholdPercent = 10,
        }, 100)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("Sidegrade", verdict.label)
    end)

    it("GetWeightedChangePercent is equipped-relative and ignores upgradeMaxDelta", function()
        assert.are.equal(-3 / 35 * 100, GU.GetWeightedChangePercent(-3, 35))
        assert.are.equal(-3 / 35 * 100, GU.GetWeightedChangePercent(-3, 35, 15))
        assert.are.equal(-100, GU.GetWeightedChangePercent(-35, 35))
        assert.are.equal(100, GU.GetWeightedChangePercent(10, 0))
        assert.are.equal(0, GU.GetWeightedChangePercent(0, 0))
    end)

    it("BuildFocusSlotDebugLines reports classification and delta", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local lines = GU.BuildFocusSlotDebugLines(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15, { sessionTechnique = "custom" })
        local text = table.concat(lines, "\n")
        assert.matches("Focus compare selection", text)
        assert.matches("Grid scores:", text)
        assert.matches("ClassifyFocusSlot:", text)
        assert.matches("MISMATCH", text)
        assert.matches("Verdict:", text)
    end)

    it("GetFocusCellBadgeKind returns unusable for never-equip classes", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Plate Helm", "|Hitem:99:0|h[Plate Helm]|h", 3, 60, 60,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local plateLink = "|Hitem:99:0|h[Plate Helm]|h"
        local info = GU.ClassifyFocusSlot(entry, char, plateLink, 1, { technique = "ilvl" }, 15)
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal("unusable", info.badge)
        assert.are.equal(GU.FOCUS_CATEGORY.NEVER, info.category)
        assert.is_true(info.dimmed)
    end)

    it("focus sort tier ranks eventual upgrades before in-range sidegrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 13 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
            end
            if id == 10 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
            end
            return oldGetItemStats(link)
        end
        local opts = { technique = "ilvl", levelsAhead = 5 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local eventualEntry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 }
        local sidegradeEntry = { name = "SidegradeAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local eventualTier = GU.GetFocusTier(
            eventualEntry, DS:GetCharacter("LowLevel", "TestRealm"), newLink, opts, 15)
        local sidegradeTier = GU.GetFocusTier(
            sidegradeEntry, DS:GetCharacter("SidegradeAlt", "TestRealm"), newLink, opts, 15)
        assert.is_true(sidegradeTier < eventualTier)
        assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_BEYOND,
            GU.SummarizeFocusEntry(eventualEntry, DS:GetCharacter("LowLevel", "TestRealm"), newLink, opts, 15).category)
        assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE,
            GU.SummarizeFocusEntry(sidegradeEntry, DS:GetCharacter("SidegradeAlt", "TestRealm"), newLink, opts, 15).category)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("CompareFocusEntries ranks sidegrades before eventual upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 10,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:11:0|h[New Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local eventualEntry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 10 }
        local sidegradeEntry = { name = "SidegradeAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local eventualChar = DS:GetCharacter("LowLevel", "TestRealm")
        local sidegradeChar = DS:GetCharacter("SidegradeAlt", "TestRealm")
        assert.is_true(GU.CompareFocusEntries(
            sidegradeEntry, eventualEntry, sidegradeChar, eventualChar, newLink, opts, 15))
        assert.are.equal(2, GU.GetFocusCompareSortTier(sidegradeEntry, sidegradeChar, newLink, opts, 15))
        assert.are.equal(3, GU.GetFocusCompareSortTier(eventualEntry, eventualChar, newLink, opts, 15))
    end)

    it("CompareFocusEntries ranks downgrades before unusable", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Plate Helm", "|Hitem:99:0|h[Plate Helm]|h", 3, 50, 50,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            if id == 100 then
                return "Better Plate Helm", "|Hitem:100:0|h[Better Plate Helm]|h", 3, 60, 60,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.WarriorAlt = {
            name = "WarriorAlt",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = { [1] = "|Hitem:100:0|h[Better Plate Helm]|h" },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local plateLink = "|Hitem:99:0|h[Plate Helm]|h"
        local downgradeEntry = { name = "WarriorAlt", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local unusableEntry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local downgradeChar = DS:GetCharacter("WarriorAlt", "TestRealm")
        local unusableChar = DS:GetCharacter("MageAlt", "TestRealm")
        assert.is_true(GU.CompareFocusEntries(
            downgradeEntry, unusableEntry, downgradeChar, unusableChar, plateLink, opts, 10))
        assert.are.equal(5, GU.GetFocusCompareSortTier(
            downgradeEntry, downgradeChar, plateLink, opts, 10))
        assert.are.equal(6, GU.GetFocusCompareSortTier(
            unusableEntry, unusableChar, plateLink, opts, 10))
        _G.GetItemInfo = oldGetItemInfo
    end)

    it("CompareFocusEntries puts sub-max-level before max-level within same tier", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.SubMax = {
            name = "SubMax",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.AtMax = {
            name = "AtMax",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 70,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local subMax = { name = "SubMax", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local maxLevel = { name = "AtMax", realm = "TestRealm", classFile = "MAGE", level = 70 }
        assert.is_true(GU.CompareFocusEntries(
            subMax, maxLevel,
            DS:GetCharacter("SubMax", "TestRealm"),
            DS:GetCharacter("AtMax", "TestRealm"),
            newLink, opts, 15))
        assert.is_true(GU.IsMaxLevelCharacter(maxLevel, DS:GetCharacter("AtMax", "TestRealm")))
        assert.is_false(GU.IsMaxLevelCharacter(subMax, DS:GetCharacter("SubMax", "TestRealm")))
    end)

    it("CompareFocusEntries sorts by upgrade percent then levels until equippable", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.BigUpgrader = {
            name = "BigUpgrader",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SmallUpgrader = {
            name = "SmallUpgrader",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local big = { name = "BigUpgrader", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local small = { name = "SmallUpgrader", realm = "TestRealm", classFile = "MAGE", level = 60 }
        assert.is_true(GU.CompareFocusEntries(
            big, small,
            DS:GetCharacter("BigUpgrader", "TestRealm"),
            DS:GetCharacter("SmallUpgrader", "TestRealm"),
            newLink, opts, 15))
        assert.is_true(GU.GetFocusUpgradePercent(
            big, DS:GetCharacter("BigUpgrader", "TestRealm"), newLink, opts, 15) >
            GU.GetFocusUpgradePercent(
                small, DS:GetCharacter("SmallUpgrader", "TestRealm"), newLink, opts, 15))
    end)

    it("SummarizeFocusCharacter uses best ring slot for sort tier", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.RingAlt = {
            name = "RingAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = {
                [11] = "|Hitem:22:0|h[Ring One]|h",
                [12] = "|Hitem:21:0|h[Ring Two]|h",
            },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local entry = { name = "RingAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local ringLink = "|Hitem:20:0|h[New Ring]|h"
        local summary = GU.SummarizeFocusEntry(entry, char, ringLink, { technique = "ilvl" }, 20)
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(1, summary.sortTier)
        assert.are.equal(20, summary.sortDelta)
        assert.is_false(summary.dimmed)
    end)

    describe("weapon loadout comparison", function()
        local MAIN = 16
        local OFF = 17

        local function weaponGetItemInfo(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [201] = { "Weak MH", nil, 2, 30, 30, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [202] = { "Weak OH", nil, 2, 25, 25, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [203] = { "Big 2H", nil, 3, 60, 60, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
                [204] = { "Small 2H", nil, 2, 50, 50, "Weapon", "Two-Handed Swords", nil, "INVTYPE_2HWEAPON" },
                [205] = { "New 1H", nil, 3, 40, 40, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [206] = { "Bag OH", nil, 2, 22, 22, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [207] = { "Bag 1H", nil, 2, 28, 28, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [208] = { "Shield", nil, 2, 20, 20, "Armor", "Shields", nil, "INVTYPE_SHIELD" },
                [209] = { "Better 1H", nil, 3, 35, 35, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
                [210] = { "MH Only", nil, 3, 40, 40, "Weapon", "Daggers", nil, "INVTYPE_WEAPONMAINHAND" },
                [211] = { "Strong MH", nil, 3, 60, 60, "Weapon", "Daggers", nil, "INVTYPE_WEAPONMAINHAND" },
                [212] = { "Held OH", nil, 2, 20, 20, "Armor", "Miscellaneous", nil, "INVTYPE_HOLDABLE" },
                [213] = { "Fishing Pole", nil, 3, 70, 1, "Weapon", "Fishing Poles", nil, "INVTYPE_2HWEAPON" },
                [214] = { "Ahead OH", nil, 3, 50, 64, "Weapon", "Daggers", nil, "INVTYPE_WEAPONOFFHAND" },
                [215] = { "Ahead 1H", nil, 3, 55, 64, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPON" },
            }
            local info = items[id]
            if not info then return mockGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end

        local function setupWarriorDualWield()
            _G.AltArmyTBC_Data.Characters.TestRealm.WarriorDW = {
                name = "WarriorDW",
                realm = "TestRealm",
                classFile = "WARRIOR",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:201:0|h[Weak MH]|h",
                    [OFF] = "|Hitem:202:0|h[Weak OH]|h",
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
            return DS:GetCharacter("WarriorDW", "TestRealm")
        end

        local function setupWarriorTwoHand()
            _G.AltArmyTBC_Data.Characters.TestRealm.Warrior2H = {
                name = "Warrior2H",
                realm = "TestRealm",
                classFile = "WARRIOR",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:204:0|h[Small 2H]|h",
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
            return DS:GetCharacter("Warrior2H", "TestRealm")
        end

        local function setupRogueDualWield()
            _G.AltArmyTBC_Data.Characters.TestRealm.RogueDW = {
                name = "RogueDW",
                realm = "TestRealm",
                classFile = "ROGUE",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:201:0|h[Weak MH]|h",
                    [OFF] = "|Hitem:202:0|h[Weak OH]|h",
                },
                Containers = {
                    [0] = {
                        links = {
                            [1] = "|Hitem:206:0|h[Bag OH]|h",
                            [2] = "|Hitem:207:0|h[Bag 1H]|h",
                        },
                    },
                },
                talents = { tabs = { 21, 0, 0 }, primary = 1, specKey = "combat" },
            }
            return DS:GetCharacter("RogueDW", "TestRealm")
        end

        local function setupRogueTwoHand()
            _G.AltArmyTBC_Data.Characters.TestRealm.Rogue2H = {
                name = "Rogue2H",
                realm = "TestRealm",
                classFile = "ROGUE",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:204:0|h[Small 2H]|h",
                },
                Containers = {
                    [0] = {
                        links = {
                            [1] = "|Hitem:206:0|h[Bag OH]|h",
                            [2] = "|Hitem:207:0|h[Bag 1H]|h",
                        },
                    },
                },
                talents = { tabs = { 21, 0, 0 }, primary = 1, specKey = "combat" },
            }
            return DS:GetCharacter("Rogue2H", "TestRealm")
        end

        local function setupPaladinTwoHand()
            _G.AltArmyTBC_Data.Characters.TestRealm.Paladin2H = {
                name = "Paladin2H",
                realm = "TestRealm",
                classFile = "PALADIN",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:204:0|h[Small 2H]|h",
                },
                Containers = {
                    [0] = {
                        links = {
                            [1] = "|Hitem:208:0|h[Shield]|h",
                            [2] = "|Hitem:207:0|h[Bag 1H]|h",
                        },
                    },
                },
                talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "retribution" },
            }
            return DS:GetCharacter("Paladin2H", "TestRealm")
        end

        local function setupMageMainHand()
            _G.AltArmyTBC_Data.Characters.TestRealm.MageMH = {
                name = "MageMH",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:211:0|h[Strong MH]|h",
                    [OFF] = "|Hitem:212:0|h[Held OH]|h",
                },
                Containers = {
                    [0] = { links = {} },
                },
                talents = { tabs = { 21, 0, 0 }, primary = 1, specKey = "arcane" },
            }
            return DS:GetCharacter("MageMH", "TestRealm")
        end

        setup(function()
            _G.GetItemInfo = weaponGetItemInfo
        end)

        before_each(function()
            if GU and GU.ResetFocusPass then
                GU.ResetFocusPass()
            end
        end)

        it("IsWeaponPairItem is true for main-hand weapon types", function()
            assert.is_true(GU.IsWeaponPairItem("|Hitem:205:0|h[New 1H]|h"))
            assert.is_true(GU.IsWeaponPairItem("|Hitem:203:0|h[Big 2H]|h"))
            assert.is_true(GU.IsWeaponPairItem("|Hitem:208:0|h[Shield]|h"))
            assert.is_false(GU.IsWeaponPairItem("|Hitem:11:0|h[New Helm]|h"))
        end)

        it("GetEquippedLoadoutValue sums main and off hand scores", function()
            local char = setupRogueDualWield()
            local val = GU.GetEquippedLoadoutValue(char, "ilvl", "ROGUE", "combat")
            assert.are.equal(55, val)
        end)

        it("2H vs dual-wield uses selection loadout when MH is selected", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:203:0|h[Big 2H]|h", {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.are.equal(5, delta)
            assert.are.equal(55, info.currentValue)
            assert.are.equal(60, info.candidateValue)
            assert.are.equal("one_v_one", info.config)
            assert.are.equal(MAIN, info.targetSlot)
            local perSlot = GU.GetSlotCompareDelta(char, "|Hitem:203:0|h[Big 2H]|h", MAIN, {
                technique = "ilvl",
            }, entry)
            assert.are.equal(30, perSlot)
        end)

        it("2H vs 2H compares 1v1 when MH is selected", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local delta = GU.GetWeaponConfigDelta(char, "|Hitem:203:0|h[Big 2H]|h", {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.are.equal(10, delta)
        end)

        it("1H vs selected 2H pairs off-hand from bags", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.are.equal(18, delta)
            assert.are.equal(68, info.candidateValue)
            assert.is_not_nil(info.offHandLink)
            assert.are.equal("paired_candidate", info.config)
        end)

        it("1H vs selected 2H non-dual-wield class uses shield from bags", function()
            local char = setupPaladinTwoHand()
            local entry = { name = "Paladin2H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.are.equal(10, delta)
            assert.are.equal(60, info.candidateValue)
        end)

        it("1H vs selected 1H compares 1v1 not full loadout", function()
            local char = setupRogueDualWield()
            local entry = { name = "RogueDW", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:209:0|h[Better 1H]|h", {
                technique = "ilvl",
                compareSlot = OFF,
            }, entry)
            assert.are.equal(10, delta)
            assert.are.equal(OFF, info.targetSlot)
            assert.are.equal("one_v_one", info.config)
        end)

        it("GetCharacterUpgradeDelta uses loadout comparison for 2H vs dual-wield", function()
            local char = setupWarriorDualWield()
            local delta = GU.GetCharacterUpgradeDelta(char, "|Hitem:203:0|h[Big 2H]|h", {
                technique = "ilvl",
            })
            assert.are.equal(5, delta)
        end)

        it("GetCharacterUpgradeDelta uses loadout comparison for 1H vs selected 2H", function()
            local char = setupWarriorTwoHand()
            local delta = GU.GetCharacterUpgradeDelta(char, "|Hitem:205:0|h[New 1H]|h", {
                technique = "ilvl",
            })
            assert.are.equal(18, delta)
        end)

        it("GetWeaponConfigDelta auto-select ignores empty off-hand main-hand compare", function()
            local char = setupWarriorTwoHand()
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local delta = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", {
                technique = "ilvl",
            }, entry)
            assert.are.equal(18, delta)
        end)

        it("shield vs selected 2H pairs main-hand from bags when off-hand is selected", function()
            local char = setupPaladinTwoHand()
            local entry = { name = "Paladin2H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:208:0|h[Shield]|h", {
                technique = "ilvl",
                compareSlot = OFF,
            }, entry)
            assert.are.equal(-2, delta)
            assert.are.equal(50, info.currentValue)
            assert.are.equal(48, info.candidateValue)
            assert.are.equal("paired_candidate", info.config)
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", info.mainHandLink)
        end)

        it("GetWeaponConfigDelta auto-select uses loadout compare for shield vs 2H", function()
            local char = setupPaladinTwoHand()
            local entry = { name = "Paladin2H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local delta = GU.GetWeaponConfigDelta(char, "|Hitem:208:0|h[Shield]|h", {
                technique = "ilvl",
            }, entry)
            assert.are.equal(-2, delta)
        end)

        local function withWeaponDpsStats(dpsById, fn)
            local oldGetItemStats = _G.GetItemStats
            _G.GetItemStats = function(link)
                local id = tonumber(tostring(link):match("item:(%d+)"))
                local stats = id and dpsById[id]
                if stats then return stats end
                return oldGetItemStats(link)
            end
            if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
                AltArmy.ItemStats.ClearCache()
            end
            local ok, err = pcall(fn)
            _G.GetItemStats = oldGetItemStats
            if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
                AltArmy.ItemStats.ClearCache()
            end
            assert(ok, err)
        end

        it("ScoreItemCustom counts off-hand melee DPS at OFFHAND_DPS_FACTOR", function()
            withWeaponDpsStats({
                [206] = {
                    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 20,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                },
            }, function()
                assert.are.equal(0.5, GU.OFFHAND_DPS_FACTOR)
                local weights = GU.GetWeights("WARRIOR", "fury", 60)
                assert.is_true((weights.melee_dps or 0) > 0)
                local oh = "|Hitem:206:0|h[Bag OH]|h"
                local mainScore = GU.ScoreItemCustom(oh, "WARRIOR", "fury", 60)
                local offScore = GU.ScoreItemCustom(oh, "WARRIOR", "fury", 60, true)
                local expected = mainScore
                    - 20 * weights.melee_dps * (1 - GU.OFFHAND_DPS_FACTOR)
                assert.is_true(math.abs(offScore - expected) < 1e-9)
                assert.is_true(offScore < mainScore)
            end)
        end)

        it("1H vs 2H custom compare counts deduced off-hand DPS at half value", function()
            withWeaponDpsStats({
                [204] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 50 },
                [205] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 30 },
                [206] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 28 },
                [207] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 20 },
            }, function()
                local char = setupWarriorTwoHand()
                local entry = {
                    name = "Warrior2H", realm = "TestRealm",
                    classFile = "WARRIOR", level = 60,
                }
                local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", {
                    technique = "custom",
                    compareSlot = MAIN,
                }, entry)
                local newScore = GU.ScoreItemCustom(
                    "|Hitem:205:0|h[New 1H]|h", "WARRIOR", "fury", 60)
                local ohFull = GU.ScoreItemCustom(
                    "|Hitem:206:0|h[Bag OH]|h", "WARRIOR", "fury", 60)
                local ohScaled = GU.ScoreItemCustom(
                    "|Hitem:206:0|h[Bag OH]|h", "WARRIOR", "fury", 60, true)
                local equipped = GU.ScoreItemCustom(
                    "|Hitem:204:0|h[Small 2H]|h", "WARRIOR", "fury", 60)
                assert.are.equal("paired_candidate", info.config)
                -- Naive sum (30 + 28 dps) beats the 2H (50 dps)...
                assert.is_true(newScore + ohFull > equipped)
                -- ...but with the off-hand counted at 50% (30 + 14) it does not.
                assert.is_true(math.abs(info.candidateValue - (newScore + ohScaled)) < 1e-9)
                assert.is_true(math.abs(info.currentValue - equipped) < 1e-9)
                assert.is_true(delta < 0)
            end)
        end)

        it("GetEquippedLoadoutValue counts off-hand DPS at half value", function()
            withWeaponDpsStats({
                [201] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 30 },
                [202] = { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 24 },
            }, function()
                local char = setupWarriorDualWield()
                local val = GU.GetEquippedLoadoutValue(char, "custom", "WARRIOR", "fury", 60)
                local mh = GU.ScoreItemCustom(
                    "|Hitem:201:0|h[Weak MH]|h", "WARRIOR", "fury", 60)
                local ohFull = GU.ScoreItemCustom(
                    "|Hitem:202:0|h[Weak OH]|h", "WARRIOR", "fury", 60)
                local ohScaled = GU.ScoreItemCustom(
                    "|Hitem:202:0|h[Weak OH]|h", "WARRIOR", "fury", 60, true)
                assert.is_true(ohScaled < ohFull)
                assert.is_true(math.abs(val - (mh + ohScaled)) < 1e-9)
            end)
        end)

        it("GetCharacterUpgradeDelta uses loadout comparison for shield vs 2H", function()
            local char = setupPaladinTwoHand()
            local delta = GU.GetCharacterUpgradeDelta(char, "|Hitem:208:0|h[Shield]|h", {
                technique = "ilvl",
            })
            assert.are.equal(-2, delta)
        end)

        it("shield vs 2H without bag 1H compares shield against 2H only", function()
            _G.AltArmyTBC_Data.Characters.TestRealm.Paladin2HNo1H = {
                name = "Paladin2HNo1H",
                realm = "TestRealm",
                classFile = "PALADIN",
                level = 60,
                Inventory = {
                    [MAIN] = "|Hitem:204:0|h[Small 2H]|h",
                },
                Containers = {
                    [0] = {
                        links = {
                            [1] = "|Hitem:208:0|h[Shield]|h",
                        },
                    },
                },
                talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "retribution" },
            }
            local char = DS:GetCharacter("Paladin2HNo1H", "TestRealm")
            local entry = { name = "Paladin2HNo1H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local delta, info = GU.GetWeaponConfigDelta(char, "|Hitem:208:0|h[Shield]|h", {
                technique = "ilvl",
                compareSlot = OFF,
            }, entry)
            assert.are.equal(-30, delta)
            assert.are.equal("one_v_one", info.config)
        end)

        it("FindBestBagItemForRole returns highest scoring usable item", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local link, score = GU.FindBestBagItemForRole(char, "onehand", {
                technique = "ilvl",
            }, entry)
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", link)
            assert.are.equal(28, score)
        end)

        it("ClassifyFocusSlot differs per selected weapon cell", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
            local link = "|Hitem:203:0|h[Big 2H]|h"
            local mainInfo = GU.ClassifyFocusSlot(entry, char, link, MAIN, opts, 5)
            local offInfo = GU.ClassifyFocusSlot(entry, char, link, OFF, opts, 5)
            assert.are.equal(5, mainInfo.delta)
            assert.are.equal(5, offInfo.delta)
        end)

        it("GetFocusVerdictForSlot uses selected slot for 2H focus", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            -- Loadout +5 on equipped 55 ≈ 9.1% vs equipped → clear at default 5% threshold
            local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 5 }
            local link = "|Hitem:203:0|h[Big 2H]|h"
            local verdict = GU.GetFocusVerdictForSlot(entry, char, link, OFF, opts, 5)
            assert.are.equal("Upgrade", verdict.label)
        end)

        it("SummarizeFocusEntry uses loadout delta for 1H vs selected 2H", function()
            local char = setupWarriorTwoHand()
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local opts = {
                technique = "ilvl",
                levelsAhead = 0,
                upgradeThresholdPercent = 10,
                compareSlot = MAIN,
            }
            local summary = GU.SummarizeFocusEntry(entry, char, "|Hitem:205:0|h[New 1H]|h", opts, 18)
            assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE, summary.category)
            assert.are.equal(18, summary.sortDelta)
        end)

        it("BuildWeaponLoadoutHeaderLinks adds equipped off-hand for 2H vs dual-wield", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local header = GU.BuildWeaponLoadoutHeaderLinks("|Hitem:203:0|h[Big 2H]|h", char, {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.is_not_nil(header)
            assert.are.equal(1, #header.focusedLinks)
            assert.are.equal("|Hitem:203:0|h[Big 2H]|h", header.focusedLinks[1])
            assert.are.equal(2, #header.equippedLinks)
            assert.are.equal("|Hitem:201:0|h[Weak MH]|h", header.equippedLinks[1])
            assert.are.equal("|Hitem:202:0|h[Weak OH]|h", header.equippedLinks[2])
        end)

        it("BuildWeaponLoadoutHeaderLinks adds bag off-hand for 1H vs 2H", function()
            local char = setupWarriorTwoHand()
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local header = GU.BuildWeaponLoadoutHeaderLinks("|Hitem:205:0|h[New 1H]|h", char, {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.is_not_nil(header)
            assert.are.equal(2, #header.focusedLinks)
            assert.are.equal("|Hitem:205:0|h[New 1H]|h", header.focusedLinks[1])
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", header.focusedLinks[2])
            assert.are.equal(1, #header.equippedLinks)
            assert.are.equal("|Hitem:204:0|h[Small 2H]|h", header.equippedLinks[1])
            assert.is_nil(header.focusedHints[1])
            assert.is_not_nil(header.focusedHints[2])
            assert.is_true(header.focusedHints[2]:find("best item we could find", 1, true) ~= nil)
            assert.is_true(header.focusedHints[2]:find("2-hander", 1, true) ~= nil)
            assert.is_true(header.focusedHints[2]:find("Warrior2H", 1, true) ~= nil)
            assert.is_nil(header.equippedHints[1])
        end)

        it("BuildWeaponLoadoutHeaderLinks puts focused shield first when pairing deduced main-hand", function()
            local char = setupPaladinTwoHand()
            local entry = { name = "Paladin2H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local header = GU.BuildWeaponLoadoutHeaderLinks("|Hitem:208:0|h[Shield]|h", char, {
                technique = "ilvl",
                compareSlot = OFF,
            }, entry)
            assert.is_not_nil(header)
            assert.are.equal(2, #header.focusedLinks)
            assert.are.equal("|Hitem:208:0|h[Shield]|h", header.focusedLinks[1])
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", header.focusedLinks[2])
            assert.is_nil(header.focusedHints[1])
            assert.is_not_nil(header.focusedHints[2])
            assert.is_true(header.focusedHints[2]:find("best item we could find", 1, true) ~= nil)
        end)

        it("BuildWeaponLoadoutHeaderLinks omits hints for equipped loadout icons", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local header = GU.BuildWeaponLoadoutHeaderLinks("|Hitem:203:0|h[Big 2H]|h", char, {
                technique = "ilvl",
                compareSlot = MAIN,
            }, entry)
            assert.is_not_nil(header)
            assert.is_nil(header.focusedHints[1])
            assert.is_nil(header.equippedHints[1])
            assert.is_nil(header.equippedHints[2])
        end)

        it("BuildSelectionLoadoutCompare uses mail item as deduced partner", function()
            local char = setupWarriorTwoHand()
            char.Containers = {}
            char.Mails = {
                { link = "|Hitem:206:0|h[Bag OH]|h", itemID = 206 },
            }
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local result = GU.BuildSelectionLoadoutCompare(char, "|Hitem:205:0|h[New 1H]|h", MAIN, {
                technique = "ilvl",
            }, entry)
            assert.are.equal("paired_candidate", result.mode)
            assert.are.equal(2, #result.candidateLinks)
            assert.are.equal("|Hitem:206:0|h[Bag OH]|h", result.candidateLinks[2])
        end)

        it("BuildSelectionLoadoutCompare deduced partner ignores levelsAhead", function()
            local char = setupWarriorTwoHand()
            char.Containers = {
                [0] = {
                    links = {
                        [1] = "|Hitem:214:0|h[Ahead OH]|h",
                        [2] = "|Hitem:206:0|h[Bag OH]|h",
                    },
                },
            }
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local result = GU.BuildSelectionLoadoutCompare(char, "|Hitem:205:0|h[New 1H]|h", MAIN, {
                technique = "ilvl",
                levelsAhead = 5,
            }, entry)
            assert.are.equal("paired_candidate", result.mode)
            assert.are.equal("|Hitem:206:0|h[Bag OH]|h", result.candidateLinks[2])
        end)

        it("BuildSelectionLoadoutCompare skips deduced partner that is not yet usable", function()
            local char = setupWarriorTwoHand()
            char.Containers = {
                [0] = {
                    links = {
                        [1] = "|Hitem:214:0|h[Ahead OH]|h",
                    },
                },
            }
            local entry = { name = "Warrior2H", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local result = GU.BuildSelectionLoadoutCompare(char, "|Hitem:205:0|h[New 1H]|h", MAIN, {
                technique = "ilvl",
                levelsAhead = 5,
            }, entry)
            assert.are.equal("one_v_one", result.mode)
            assert.are.equal(1, #result.candidateLinks)
        end)

        it("BuildSelectionLoadoutCompare never deduces a fishing pole as MH partner", function()
            local char = setupPaladinTwoHand()
            char.Containers = {
                [0] = {
                    links = {
                        [1] = "|Hitem:213:0|h[Fishing Pole]|h",
                        [2] = "|Hitem:207:0|h[Bag 1H]|h",
                    },
                },
            }
            local entry = { name = "Paladin2H", realm = "TestRealm", classFile = "PALADIN", level = 60 }
            local result = GU.BuildSelectionLoadoutCompare(char, "|Hitem:208:0|h[Shield]|h", OFF, {
                technique = "ilvl",
            }, entry)
            assert.are.equal("paired_candidate", result.mode)
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", result.candidateLinks[1])
            assert.are.equal("|Hitem:208:0|h[Shield]|h", result.candidateLinks[2])
        end)

        it("BuildSelectionLoadoutCompare 2H focus empty MH uses deduced MH from bags", function()
            local char = setupWarriorDualWield()
            char.Inventory[MAIN] = nil
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local result = GU.BuildSelectionLoadoutCompare(char, "|Hitem:203:0|h[Big 2H]|h", MAIN, {
                technique = "ilvl",
            }, entry)
            assert.are.equal("empty_2h", result.mode)
            assert.are.equal(2, #result.equippedLinks)
            assert.are.equal("|Hitem:207:0|h[Bag 1H]|h", result.equippedLinks[1])
            assert.are.equal("|Hitem:202:0|h[Weak OH]|h", result.equippedLinks[2])
        end)

        it("FindBestStoredItemForSlot memoizes within a focus pass", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local getItemInfoCalls = 0
            local oldGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(item)
                getItemInfoCalls = getItemInfoCalls + 1
                return weaponGetItemInfo(item)
            end
            GU.ResetFocusPass()
            local opts = { technique = "ilvl" }
            local link1 = select(1, GU.FindBestStoredItemForSlot(char, OFF, opts, entry))
            local callsAfterFirst = getItemInfoCalls
            local link2 = select(1, GU.FindBestStoredItemForSlot(char, OFF, opts, entry))
            _G.GetItemInfo = oldGetItemInfo
            assert.is_not_nil(link1)
            assert.are.equal(link1, link2)
            assert.are.equal(callsAfterFirst, getItemInfoCalls)
            GU.ResetFocusPass()
        end)

        it("GetWeaponConfigDelta memoizes within a focus pass", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local getItemInfoCalls = 0
            local oldGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(item)
                getItemInfoCalls = getItemInfoCalls + 1
                return weaponGetItemInfo(item)
            end
            GU.ResetFocusPass()
            local opts = { technique = "ilvl", compareSlot = MAIN }
            local delta1 = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            local callsAfterFirst = getItemInfoCalls
            local delta2 = GU.GetWeaponConfigDelta(char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            _G.GetItemInfo = oldGetItemInfo
            assert.are.equal(delta1, delta2)
            assert.are.equal(callsAfterFirst, getItemInfoCalls)
            GU.ResetFocusPass()
        end)

        it("storedItemsFingerprint is frozen for a focus pass until ResetFocusPass", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local opts = { technique = "ilvl", compareSlot = MAIN }
            GU.ResetFocusPass()
            local delta1, info1 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            assert.are.equal("paired_candidate", info1.config)
            assert.is_not_nil(info1.offHandLink)

            -- Mutate bags mid-pass; fingerprint must stay frozen.
            char.Containers[0].links[1] = nil
            char.Containers[0].links[2] = nil
            local delta2, info2 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            assert.are.equal(delta1, delta2)
            assert.are.equal(info1.offHandLink, info2.offHandLink)

            GU.ResetFocusPass()
            local delta3, info3 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            assert.are_not.equal(delta1, delta3)
            assert.is_nil(info3.offHandLink)
            assert.are.equal("one_v_one", info3.config)
        end)

        it("FindBestStoredItemForSlot persists across ResetFocusPass until bags change", function()
            local char = setupWarriorDualWield()
            local entry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local opts = { technique = "ilvl" }
            local mailScans = 0
            local oldIterate = DS.IterateMailItemLinks
            DS.IterateMailItemLinks = function(self, c, callback)
                mailScans = mailScans + 1
                return oldIterate(self, c, callback)
            end
            GU.ResetFocusPass()
            local link1 = select(1, GU.FindBestStoredItemForSlot(char, OFF, opts, entry))
            local scansAfterFirst = mailScans
            GU.ResetFocusPass()
            local link2 = select(1, GU.FindBestStoredItemForSlot(char, OFF, opts, entry))
            assert.are.equal(link1, link2)
            assert.are.equal(scansAfterFirst, mailScans)

            char.Containers[0].links[1] = "|Hitem:209:0|h[Better 1H]|h"
            GU.ResetFocusPass()
            local link3 = select(1, GU.FindBestStoredItemForSlot(char, OFF, opts, entry))
            DS.IterateMailItemLinks = oldIterate
            assert.are_not.equal(link1, link3)
            assert.is_true(mailScans > scansAfterFirst)
        end)

        it("GetWeaponConfigDelta persists across ResetFocusPass until bags change", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local opts = { technique = "ilvl", compareSlot = MAIN }
            local mailScans = 0
            local oldIterate = DS.IterateMailItemLinks
            DS.IterateMailItemLinks = function(self, c, callback)
                mailScans = mailScans + 1
                return oldIterate(self, c, callback)
            end
            GU.ResetFocusPass()
            local delta1, info1 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            local scansAfterFirst = mailScans
            GU.ResetFocusPass()
            local delta2, info2 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            assert.are.equal(delta1, delta2)
            assert.are.equal(info1.offHandLink, info2.offHandLink)
            assert.are.equal(scansAfterFirst, mailScans)

            char.Containers[0].links[1] = nil
            char.Containers[0].links[2] = nil
            GU.ResetFocusPass()
            local delta3, info3 = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            DS.IterateMailItemLinks = oldIterate
            assert.are_not.equal(delta1, delta3)
            assert.is_nil(info3.offHandLink)
            assert.is_true(mailScans > scansAfterFirst)
        end)

        it("GetWeaponLoadoutCompareLinks reuses GetWeaponConfigDelta selection cache", function()
            local char = setupRogueTwoHand()
            local entry = { name = "Rogue2H", realm = "TestRealm", classFile = "ROGUE", level = 60 }
            local opts = { technique = "ilvl", compareSlot = MAIN }
            GU.ResetFocusPass()
            local buildCalls = 0
            local oldBuild = GU.BuildSelectionLoadoutCompare
            GU.BuildSelectionLoadoutCompare = function(...)
                buildCalls = buildCalls + 1
                return oldBuild(...)
            end
            local delta, info = GU.GetWeaponConfigDelta(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            local callsAfterDelta = buildCalls
            local links = GU.GetWeaponLoadoutCompareLinks(
                char, "|Hitem:205:0|h[New 1H]|h", opts, entry)
            GU.BuildSelectionLoadoutCompare = oldBuild
            assert.is_true(callsAfterDelta > 0)
            assert.are.equal(callsAfterDelta, buildCalls)
            assert.is_not_nil(links)
            assert.is_not_nil(info.selection)
            assert.are.same(info.selection.candidateLinks, links.candidateLinks)
            assert.are.same(info.selection.equippedLinks, links.equippedLinks)
        end)

        describe("main-hand-only weapon cannot be considered for off-hand", function()
            local entry = { name = "MageMH", realm = "TestRealm", classFile = "MAGE", level = 60 }
            local mhOnlyLink = "|Hitem:210:0|h[MH Only]|h"

            it("CanEquipFocusItemInWeaponSlot rejects off-hand, allows main-hand", function()
                local char = setupMageMainHand()
                assert.is_true(GU.CanEquipFocusItemInWeaponSlot(char, mhOnlyLink, MAIN, entry))
                assert.is_false(GU.CanEquipFocusItemInWeaponSlot(char, mhOnlyLink, OFF, entry))
            end)

            it("CanEquipFocusItemInWeaponSlot rejects off-hand even for dual-wield class", function()
                local warrior = setupWarriorDualWield()
                local wEntry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
                assert.is_false(
                    GU.CanEquipFocusItemInWeaponSlot(warrior, mhOnlyLink, OFF, wEntry))
                -- Generic one-hander is still allowed in off-hand for dual-wield class.
                assert.is_true(
                    GU.CanEquipFocusItemInWeaponSlot(warrior, "|Hitem:205:0|h[New 1H]|h", OFF, wEntry))
            end)

            it("two-hand weapon is still relevant to both weapon rows", function()
                local warrior = setupWarriorDualWield()
                local wEntry = { name = "WarriorDW", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
                assert.is_true(
                    GU.CanEquipFocusItemInWeaponSlot(warrior, "|Hitem:203:0|h[Big 2H]|h", MAIN, wEntry))
                assert.is_true(
                    GU.CanEquipFocusItemInWeaponSlot(warrior, "|Hitem:203:0|h[Big 2H]|h", OFF, wEntry))
            end)

            it("GetWeaponConfigDelta auto-select compares main-hand only, not off-hand", function()
                local char = setupMageMainHand()
                local delta, info = GU.GetWeaponConfigDelta(char, mhOnlyLink, {
                    technique = "ilvl",
                }, entry)
                assert.are.equal(-20, delta)
                assert.are.equal(MAIN, info.targetSlot)
            end)

            it("GetCharacterUpgradeDelta is a downgrade, not a false off-hand upgrade", function()
                local char = setupMageMainHand()
                local delta = GU.GetCharacterUpgradeDelta(char, mhOnlyLink, {
                    technique = "ilvl",
                }, entry)
                assert.are.equal(-20, delta)
            end)

            it("ClassifyFocusSlot returns nil for off-hand and downgrade for main-hand", function()
                local char = setupMageMainHand()
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                local mainInfo = GU.ClassifyFocusSlot(entry, char, mhOnlyLink, MAIN, opts, 20)
                local offInfo = GU.ClassifyFocusSlot(entry, char, mhOnlyLink, OFF, opts, 20)
                assert.are.equal(GU.FOCUS_CATEGORY.DOWNGRADE, mainInfo.category)
                assert.is_nil(offInfo)
            end)

            it("GetFocusCellBadgeKind and GetFocusVerdictForSlot are nil for off-hand", function()
                local char = setupMageMainHand()
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                assert.is_nil(GU.GetFocusCellBadgeKind(entry, char, mhOnlyLink, OFF, opts, 20))
                assert.is_nil(GU.GetFocusVerdictForSlot(entry, char, mhOnlyLink, OFF, opts, 20))
            end)

            it("GetBestFocusCompareSlot picks main-hand for a main-hand-only weapon", function()
                local char = setupMageMainHand()
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries({ entry }, mhOnlyLink, opts)
                local slot = GU.GetBestFocusCompareSlot(
                    entry, char, mhOnlyLink, { MAIN, OFF }, opts, upgradeMaxDelta)
                assert.are.equal(MAIN, slot)
            end)
        end)

        describe("one-hander that only upgrades the off-hand (strong MH + weak shield)", function()
            local entry = { name = "WarriorShield", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
            local oneHandLink = "|Hitem:205:0|h[New 1H]|h"

            local function setupWarriorShield()
                _G.AltArmyTBC_Data.Characters.TestRealm.WarriorShield = {
                    name = "WarriorShield",
                    realm = "TestRealm",
                    classFile = "WARRIOR",
                    level = 60,
                    Inventory = {
                        [MAIN] = "|Hitem:211:0|h[Strong MH]|h",
                        [OFF] = "|Hitem:208:0|h[Shield]|h",
                    },
                    Containers = { [0] = { links = {} } },
                    talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
                }
                return DS:GetCharacter("WarriorShield", "TestRealm")
            end

            it("GetFocusInventorySlots includes both hands for a one-hander", function()
                assert.are.same({ MAIN, OFF }, GU.GetFocusInventorySlots(oneHandLink))
            end)

            it("auto upgrade delta (quest reward / alerts) is positive via the off-hand", function()
                local char = setupWarriorShield()
                local delta, info = GU.GetWeaponConfigDelta(char, oneHandLink, { technique = "ilvl" }, entry)
                assert.is_true(delta > 0)
                assert.are.equal(OFF, info.targetSlot)
            end)

            it("focus compare slot picks the off-hand, matching the auto delta", function()
                local char = setupWarriorShield()
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries({ entry }, oneHandLink, opts)
                local slot = GU.GetBestFocusCompareSlot(
                    entry, char, oneHandLink, GU.GetFocusInventorySlots(oneHandLink), opts, upgradeMaxDelta)
                assert.are.equal(OFF, slot)
            end)

            it("focus summary is an upgrade, not a main-hand downgrade", function()
                local char = setupWarriorShield()
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries({ entry }, oneHandLink, opts)
                local summary = GU.SummarizeFocusEntry(entry, char, oneHandLink, opts, upgradeMaxDelta)
                assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE, summary.category)
            end)
        end)

        describe("off-hand-only item cannot be considered for main-hand", function()
            local entry = { name = "MageMH", realm = "TestRealm", classFile = "MAGE", level = 60 }

            it("CanEquipFocusItemInWeaponSlot rejects main-hand for a shield/holdable", function()
                local char = setupMageMainHand()
                local shieldLink = "|Hitem:208:0|h[Shield]|h"
                local heldLink = "|Hitem:212:0|h[Held OH]|h"
                assert.is_false(GU.CanEquipFocusItemInWeaponSlot(char, shieldLink, MAIN, entry))
                assert.is_true(GU.CanEquipFocusItemInWeaponSlot(char, shieldLink, OFF, entry))
                assert.is_false(GU.CanEquipFocusItemInWeaponSlot(char, heldLink, MAIN, entry))
                assert.is_true(GU.CanEquipFocusItemInWeaponSlot(char, heldLink, OFF, entry))
            end)

            it("ClassifyFocusSlot returns nil for main-hand of an off-hand-only item", function()
                local char = setupMageMainHand()
                local heldLink = "|Hitem:212:0|h[Held OH]|h"
                local opts = { technique = "ilvl", levelsAhead = 0, upgradeThresholdPercent = 10 }
                local mainInfo = GU.ClassifyFocusSlot(entry, char, heldLink, MAIN, opts, 20)
                local offInfo = GU.ClassifyFocusSlot(entry, char, heldLink, OFF, opts, 20)
                assert.is_nil(mainInfo)
                assert.is_not_nil(offInfo)
            end)
        end)

        it("scoreItem memoizes within a focus pass", function()
            local link = "|Hitem:11:0|h[New Helm]|h"
            GU.ResetFocusPass()
            local getItemStatsCalls = 0
            local oldGetItemStats = _G.GetItemStats
            _G.GetItemStats = function(itemLink)
                getItemStatsCalls = getItemStatsCalls + 1
                return oldGetItemStats(itemLink)
            end
            local score1 = GU.ScoreItem(link, "custom", "MAGE", "frost")
            local callsAfterFirst = getItemStatsCalls
            local score2 = GU.ScoreItem(link, "custom", "MAGE", "frost")
            _G.GetItemStats = oldGetItemStats
            assert.are.equal(score1, score2)
            assert.are.equal(callsAfterFirst, getItemStatsCalls)
            GU.ResetFocusPass()
        end)
    end)
end)
