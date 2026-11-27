--[[
  Unit tests for DataStoreTalents.lua.
  Run from project root: npm test
]]

describe("DataStoreTalents", function()
    local DT
    local DS

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("DataStore")
        package.loaded["DataStoreTalents"] = nil
        require("DataStoreTalents")
        DT = AltArmy.DataStoreTalents
        DS = AltArmy.DataStore
    end)

    it("DerivePrimaryTabIndex picks tab with most points", function()
        assert.are.equal(3, DT.DerivePrimaryTabIndex({ 5, 10, 25 }))
    end)

    it("DerivePrimaryTabIndex returns nil when all zero", function()
        assert.is_nil(DT.DerivePrimaryTabIndex({ 0, 0, 0 }))
    end)

    it("GetSpecKeyForTab returns shadow for priest tab 3", function()
        assert.are.equal("shadow", DT.GetSpecKeyForTab("PRIEST", 3))
    end)

    it("GetLevelingSpecKey returns fury for warrior", function()
        assert.are.equal("fury", DT.GetLevelingSpecKey("WARRIOR"))
    end)

    it("GetLevelingSpecKey returns retribution for paladin", function()
        assert.are.equal("retribution", DT.GetLevelingSpecKey("PALADIN"))
    end)

    it("ResolveSpecKey uses stored spec when known", function()
        local char = {
            classFile = "PRIEST",
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "shadow" },
        }
        local key, known = DT.ResolveSpecKey(char)
        assert.are.equal("shadow", key)
        assert.is_true(known)
    end)

    it("ResolveSpecKey falls back to leveling spec when unknown", function()
        local char = { classFile = "PRIEST" }
        local key, known = DT.ResolveSpecKey(char)
        assert.are.equal("shadow", key)
        assert.is_false(known)
    end)

    it("HasTalentData is false when talents never scanned", function()
        assert.is_false(DT.HasTalentData({ classFile = "MAGE" }))
    end)

    it("HasTalentData is true after scan stored", function()
        assert.is_true(DT.HasTalentData({
            classFile = "MAGE",
            talents = { tabs = { 10, 0, 0 }, primary = 1, specKey = "arcane" },
        }))
    end)

    it("IsTalentEligible is false below level 10", function()
        assert.is_false(DT.IsTalentEligible({ level = 9 }))
    end)

    it("IsTalentEligible is true at level 10", function()
        assert.is_true(DT.IsTalentEligible({ level = 10 }))
    end)

    it("IsTalentEligible is false when level is missing", function()
        assert.is_false(DT.IsTalentEligible({ classFile = "MAGE" }))
    end)

    it("GetSpecKeyForSpecId maps canonical spec IDs to keys", function()
        assert.are.equal("fury", DT.GetSpecKeyForSpecId("WARRIOR", 72))
        assert.are.equal("retribution", DT.GetSpecKeyForSpecId("PALADIN", 70))
    end)

    it("GetSpecKeyForSpecId collapses both Druid Feral/Guardian IDs onto 'feral'", function()
        assert.are.equal("feral", DT.GetSpecKeyForSpecId("DRUID", 103))
        assert.are.equal("feral", DT.GetSpecKeyForSpecId("DRUID", 104))
    end)

    it("GetSpecKeyForSpecId returns nil for an unrecognized spec ID", function()
        assert.is_nil(DT.GetSpecKeyForSpecId("WARRIOR", 999))
    end)

    describe("ScanTalents specialization-API fallback (e.g. WoW Forever)", function()
        local oldGetNumTalentTabs, oldGetTalentTabInfo
        local oldGetSpecialization, oldGetSpecializationInfo, oldCSpecInfo
        local oldGetRealmName, oldUnitName
        local oldClassTalents, oldTraits

        before_each(function()
            oldClassTalents = _G.C_ClassTalents
            oldTraits = _G.C_Traits
            _G.C_ClassTalents = nil
            _G.C_Traits = nil
            oldGetNumTalentTabs = _G.GetNumTalentTabs
            oldGetTalentTabInfo = _G.GetTalentTabInfo
            oldGetSpecialization = _G.GetSpecialization
            oldGetSpecializationInfo = _G.GetSpecializationInfo
            oldCSpecInfo = _G.C_SpecializationInfo
            oldGetRealmName = _G.GetRealmName
            oldUnitName = _G.UnitName

            -- Legacy talent-tab API absent, same as WoW Forever (confirmed via /altarmy debug
            -- apicheck — see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md).
            _G.GetNumTalentTabs = nil
            _G.GetTalentTabInfo = nil
            _G.GetSpecialization = nil
            _G.GetSpecializationInfo = nil
            _G.C_SpecializationInfo = nil

            _G.GetRealmName = function() return "TestRealm" end
            _G.UnitName = function() return "TestChar" end
            _G.AltArmyTBC_Data.Characters = { TestRealm = { TestChar = { classFile = "WARRIOR" } } }
        end)

        after_each(function()
            _G.C_ClassTalents = oldClassTalents
            _G.C_Traits = oldTraits
            _G.GetNumTalentTabs = oldGetNumTalentTabs
            _G.GetTalentTabInfo = oldGetTalentTabInfo
            _G.GetSpecialization = oldGetSpecialization
            _G.GetSpecializationInfo = oldGetSpecializationInfo
            _G.C_SpecializationInfo = oldCSpecInfo
            _G.GetRealmName = oldGetRealmName
            _G.UnitName = oldUnitName
        end)

        it("does nothing when neither the legacy nor the specialization API exist", function()
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.is_nil(char.talents)
        end)

        it("resolves specKey via C_SpecializationInfo when legacy tabs are missing", function()
            _G.C_SpecializationInfo = {
                GetSpecialization = function() return 2 end,
                GetSpecializationInfo = function(specIndex)
                    assert.are.equal(2, specIndex)
                    return 72 -- Fury Warrior
                end,
            }
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.equal("fury", char.talents.specKey)
            assert.are.equal(2, char.talents.primary)
            assert.is_not_nil(char.talents.tabs)
            local key, known = DT.ResolveSpecKey(char)
            assert.are.equal("fury", key)
            assert.is_true(known)
        end)

        it("falls back to the bare GetSpecialization/GetSpecializationInfo globals", function()
            _G.GetSpecialization = function() return 3 end
            _G.GetSpecializationInfo = function() return 73 end -- Protection Warrior
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.equal("protection", char.talents.specKey)
            assert.are.equal(3, char.talents.primary)
        end)

        -- Forever's class talent tree: the three tabs as columns, nodes as a live Protection
        -- warrior's (level 26, 21 points) came back in a dev dump on 2026-11-25.
        local function stubTraitTree(spentByNode)
            local nodes = {
                [105958] = 1020, [105941] = 1620, [105952] = 2820, -- Arms column
                [105938] = 5620, [105930] = 5620, [105926] = 6820, -- Fury column
                [105976] = 9680, [105975] = 9080, [105972] = 10880, -- Protection column
            }
            local ids = {}
            for id in pairs(nodes) do ids[#ids + 1] = id end
            table.sort(ids)
            _G.C_ClassTalents = { GetActiveConfigID = function() return 279715 end }
            _G.C_Traits = {
                GetConfigInfo = function(configID)
                    assert.are.equal(279715, configID)
                    return { ID = configID, treeIDs = { 1117 }, name = "Warrior", type = 4 }
                end,
                GetTreeNodes = function(treeID)
                    assert.are.equal(1117, treeID)
                    return ids
                end,
                GetNodeInfo = function(_, nodeID)
                    local spent = spentByNode[nodeID] or 0
                    return { ID = nodeID, posX = nodes[nodeID], posY = 2130,
                        ranksPurchased = spent, activeRank = spent, maxRanks = 5 }
                end,
            }
            -- The specialization API answers with Forever's one placeholder spec.
            _G.C_SpecializationInfo = {
                GetSpecialization = function() return 1 end,
                GetSpecializationInfo = function() return 1491 end,
            }
        end

        it("reads the spec from Forever's class talent tree columns", function()
            stubTraitTree({ [105976] = 5, [105975] = 2, [105972] = 3, [105941] = 1 })
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.same({ 1, 0, 10 }, char.talents.tabs)
            assert.are.equal(3, char.talents.primary)
            assert.are.equal("protection", char.talents.specKey)
            local key, known = DT.ResolveSpecKey(char)
            assert.are.equal("protection", key)
            assert.is_true(known)
        end)

        it("leaves the spec unpicked when no talent points are spent", function()
            stubTraitTree({})
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.same({ 0, 0, 0 }, char.talents.tabs)
            assert.is_nil(char.talents.primary)
            assert.is_nil(char.talents.specKey)
            local _, known = DT.ResolveSpecKey(char)
            assert.is_false(known)
        end)

        it("TraitTabForPosX puts each column in its tab", function()
            assert.are.equal(1, DT.TraitTabForPosX(1020))
            assert.are.equal(1, DT.TraitTabForPosX(2820))
            assert.are.equal(2, DT.TraitTabForPosX(5020))
            assert.are.equal(2, DT.TraitTabForPosX(6820))
            assert.are.equal(3, DT.TraitTabForPosX(9080))
            assert.are.equal(3, DT.TraitTabForPosX(102800)) -- Hunter's hidden Survival node
        end)

        it("records a scan with no spec chosen yet when the API exists but returns nothing", function()
            _G.C_SpecializationInfo = {
                GetSpecialization = function() return nil end,
                GetSpecializationInfo = function() return nil end,
            }
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.is_not_nil(char.talents)
            assert.is_nil(char.talents.specKey)
            assert.is_true(DT.HasTalentData(char))
            local key, known = DT.ResolveSpecKey(char)
            assert.are.equal("fury", key) -- warrior leveling-spec fallback
            assert.is_false(known)
        end)
    end)

    describe("rescanning on a dual-spec swap", function()
        local frame, oldCreateFrame, oldTimer, oldScan, scans, timers

        before_each(function()
            oldCreateFrame, oldTimer, oldScan = _G.CreateFrame, _G.C_Timer, DS.ScanTalents
            frame = { events = {} }
            _G.CreateFrame = function()
                frame.RegisterEvent = function(self, name) self.events[name] = true end
                frame.SetScript = function(self, _, fn) self.onEvent = fn end
                return frame
            end
            timers = {}
            _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
            package.loaded["DataStoreTalents"] = nil
            require("DataStoreTalents")
            scans = 0
            DS.ScanTalents = function() scans = scans + 1 end
        end)

        after_each(function()
            _G.CreateFrame, _G.C_Timer, DS.ScanTalents = oldCreateFrame, oldTimer, oldScan
            package.loaded["DataStoreTalents"] = nil
            require("DataStoreTalents")
        end)

        it("listens for the talent group and talent tree changing", function()
            assert.is_true(frame.events.ACTIVE_TALENT_GROUP_CHANGED)
            assert.is_true(frame.events.TRAIT_CONFIG_UPDATED)
            assert.is_true(frame.events.ACTIVE_COMBAT_CONFIG_CHANGED)
        end)

        it("scans at once and again once the swap has settled", function()
            frame.onEvent(frame, "ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
            assert.are.equal(1, scans)
            assert.are.equal(1, #timers)
            timers[1].fn()
            assert.are.equal(2, scans)
        end)
    end)
end)
