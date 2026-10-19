--[[
  Unit tests for DataStoreLegacy.lua (WoW Forever Legacy Talent capture + rest-XP multiplier).
  Run from project root: npm test
]]

describe("DataStoreLegacy", function()
    local DL
    local DS

    local savedGlobals = {}
    local function stashGlobal(name)
        savedGlobals[name] = _G[name]
    end
    local function restoreGlobal(name)
        _G[name] = savedGlobals[name]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("DataStore")
        package.loaded["DataStoreLegacy"] = nil
        require("DataStoreLegacy")
        DL = AltArmy.DataStoreLegacy
        DS = AltArmy.DataStore
    end)

    before_each(function()
        stashGlobal("C_ClassTalents")
        stashGlobal("C_Traits")
        stashGlobal("GetSpellInfo")
        stashGlobal("C_Spell")
        stashGlobal("UnitName")
        stashGlobal("GetRealmName")
        AltArmyTBC_Data.Characters = {}
    end)

    after_each(function()
        restoreGlobal("C_ClassTalents")
        restoreGlobal("C_Traits")
        restoreGlobal("GetSpellInfo")
        restoreGlobal("C_Spell")
        restoreGlobal("UnitName")
        restoreGlobal("GetRealmName")
    end)

    describe("HasTraitsApi", function()
        it("false when C_Traits is absent", function()
            _G.C_Traits = nil
            assert.is_false(DL.HasTraitsApi())
        end)

        it("true when the required C_Traits functions exist", function()
            _G.C_Traits = { GetTreeNodes = function() end, GetNodeInfo = function() end }
            assert.is_true(DL.HasTraitsApi())
        end)
    end)

    describe("ScanActiveConfig", function()
        it("returns nil when the API is entirely absent (e.g. TBC Classic)", function()
            _G.C_Traits = nil
            _G.C_ClassTalents = nil
            assert.is_nil(DL.ScanActiveConfig())
        end)

        it("returns nil when no Legacy config resolves", function()
            _G.C_Traits = {
                GetTreeNodes = function() end,
                GetNodeInfo = function() end,
                GetConfigIDBySystemID = function() return nil end,
                GetConfigIDByTreeID = function() return 0 end,
            }
            assert.is_nil(DL.ScanActiveConfig())
        end)

        it("never reads the class-talent config", function()
            _G.C_ClassTalents = { GetActiveConfigID = function() return 111 end }
            _G.C_Traits = { GetTreeNodes = function() return { 1 } end, GetNodeInfo = function()
                return { activeRank = 3, entryIDs = {} }
            end }
            assert.is_nil(DL.ScanActiveConfig())
        end)

        it("resolves the config by the Legacy trait system", function()
            local asked
            _G.C_Traits = {
                GetConfigIDBySystemID = function(systemID)
                    asked = systemID
                    return 77
                end,
                GetConfigInfo = function(configID)
                    assert.are.equal(77, configID)
                    return { treeIDs = { 1187 } }
                end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function() return { activeRank = 1, entryIDs = {} } end,
            }
            local result = DL.ScanActiveConfig()
            assert.are.equal(45, asked)
            assert.are.equal(1, result.nodes[5])
        end)

        it("falls back to a Legacy tree's config", function()
            _G.C_Traits = {
                GetConfigIDByTreeID = function(treeID)
                    if treeID == 1188 then return 88 end
                    return nil
                end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function(configID)
                    assert.are.equal(88, configID)
                    return { activeRank = 1, entryIDs = {} }
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.is_not_nil(result)
            assert.are.equal(3, result.totalRanksSpent) -- the same node in each of the three known trees
        end)

        it("walks only the Legacy trees of the config", function()
            _G.C_Traits = {
                GetConfigIDBySystemID = function() return 1 end,
                GetConfigInfo = function() return { treeIDs = { 900, 1187, 1189 } } end,
                GetTreeNodes = function(treeID)
                    if treeID == 1187 then return { 10, 11 } end
                    if treeID == 1189 then return { 20 } end
                    return { 99 }
                end,
                GetNodeInfo = function(_configID, nodeID)
                    local ranks = { [10] = 2, [11] = 0, [20] = 3, [99] = 5 }
                    return { activeRank = ranks[nodeID], entryIDs = {} }
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.are.equal(2, result.nodes[10])
            assert.is_nil(result.nodes[11]) -- zero-rank nodes are not recorded
            assert.are.equal(3, result.nodes[20])
            assert.is_nil(result.nodes[99]) -- not a Legacy tree
            assert.are.equal(5, result.totalRanksSpent)
            assert.are.equal(0, result.restRank)
        end)

        it("records each ranked node's definition spell", function()
            _G.C_Traits = {
                GetConfigIDBySystemID = function() return 1 end,
                GetConfigInfo = function() return { treeIDs = { 1187 } } end,
                GetTreeNodes = function() return { 110289, 110286 } end,
                GetNodeInfo = function(_configID, nodeID)
                    if nodeID == 110289 then return { activeRank = 3, entryIDs = { 136850 } } end
                    return { activeRank = 2, entryIDs = { 136843 } }
                end,
                GetEntryInfo = function(_configID, entryID)
                    return { definitionID = entryID == 136850 and 141613 or 141606 }
                end,
                GetDefinitionInfo = function(definitionID)
                    return { spellID = definitionID == 141613 and DL.SPELL_MASTER_CHEF or DL.SPELL_BARTERING }
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.are.equal(3, result.spells[DL.SPELL_MASTER_CHEF])
            assert.are.equal(2, result.spells[DL.SPELL_BARTERING])
        end)

        it("identifies the rest-XP talent's rank by resolved name", function()
            _G.C_Spell = { GetSpellInfo = function(spellID)
                if spellID == 999 then return { name = "Well Rested" } end
                return { name = "Something Else" }
            end }
            _G.C_Traits = {
                GetConfigIDBySystemID = function() return 1 end,
                GetConfigInfo = function() return { treeIDs = { 1187 } } end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function(_configID, nodeID)
                    if nodeID == 5 then return { activeRank = 3, entryIDs = { 500 } } end
                    return nil
                end,
                GetEntryInfo = function(_configID, entryID)
                    if entryID == 500 then return { definitionID = 700 } end
                    return nil
                end,
                GetDefinitionInfo = function(definitionID)
                    if definitionID == 700 then return { spellID = 999 } end
                    return nil
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.are.equal(3, result.restRank)
        end)
    end)

    describe("GetWellRestedRank", function()
        it("is 0 without data, for v1 data and for no ranks", function()
            assert.are.equal(0, DL.GetWellRestedRank(nil))
            assert.are.equal(0, DL.GetWellRestedRank({}))
            assert.are.equal(0, DL.GetWellRestedRank({ legacyTalents = { restRank = 3 } }))
            assert.are.equal(0, DL.GetWellRestedRank({ legacyTalents = { spells = {}, restRank = 0 } }))
        end)

        it("returns the captured rank, clamped to the max rank", function()
            assert.are.equal(2, DL.GetWellRestedRank({ legacyTalents = { spells = {}, restRank = 2 } }))
            assert.are.equal(5, DL.GetWellRestedRank({ legacyTalents = { spells = {}, restRank = 9 } }))
        end)
    end)

    describe("GetRestXpMultiplier", function()
        it("returns 1 when char has no legacyTalents", function()
            assert.are.equal(1, DL.GetRestXpMultiplier({}))
        end)

        it("returns 1 when char is nil", function()
            assert.are.equal(1, DL.GetRestXpMultiplier(nil))
        end)

        it("returns 1 when restRank is 0", function()
            assert.are.equal(1, DL.GetRestXpMultiplier({ legacyTalents = { spells = {}, restRank = 0 } }))
        end)

        it("applies 4% per rank", function()
            assert.are.equal(1.12, DL.GetRestXpMultiplier({ legacyTalents = { spells = {}, restRank = 3 } }))
        end)

        it("clamps at the max rank (5 -> 20%)", function()
            assert.are.equal(1.2, DL.GetRestXpMultiplier({ legacyTalents = { spells = {}, restRank = 9 } }))
        end)

        it("ignores v1 data (read from the class-talent config)", function()
            assert.are.equal(1, DL.GetRestXpMultiplier({ legacyTalents = { restRank = 3 } }))
        end)
    end)

    describe("ScanLegacyTalents", function()
        before_each(function()
            _G.UnitName = function() return "Legacychar" end
            _G.GetRealmName = function() return "Faerlina" end
        end)

        it("does nothing when the API doesn't resolve", function()
            _G.C_Traits = nil
            _G.C_ClassTalents = nil
            DS:ScanLegacyTalents()
            local char = AltArmyTBC_Data.Characters.Faerlina and AltArmyTBC_Data.Characters.Faerlina.Legacychar
            assert.is_nil(char.legacyTalents)
        end)

        it("drops v1 data when the Legacy config doesn't resolve", function()
            _G.C_Traits = nil
            DS:ScanLegacyTalents()
            local char = AltArmyTBC_Data.Characters.Faerlina.Legacychar
            char.legacyTalents = { nodes = { [1] = 3 }, totalRanksSpent = 3, restRank = 0 }
            DS:ScanLegacyTalents()
            assert.is_nil(char.legacyTalents)
            char.legacyTalents = { spells = { [7] = 1 }, nodes = {}, totalRanksSpent = 1, restRank = 0 }
            DS:ScanLegacyTalents()
            assert.are.equal(1, char.legacyTalents.spells[7])
        end)

        it("stores captured data and bumps dataVersions.legacyTalents", function()
            _G.C_Traits = {
                GetConfigIDBySystemID = function() return 1 end,
                GetConfigInfo = function() return { treeIDs = { 1187 } } end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function() return { activeRank = 2, entryIDs = {} } end,
            }
            DS:ScanLegacyTalents()
            local char = AltArmyTBC_Data.Characters.Faerlina.Legacychar
            assert.are.equal(2, char.legacyTalents.nodes[5])
            assert.are.equal(2, char.legacyTalents.totalRanksSpent)
            assert.are.equal(2, char.dataVersions.legacyTalents)
        end)
    end)

    describe("the Legacy talents' cooldowns at login", function()
        local onEvent, scanned, savedCreateFrame, savedScanLegacy, savedTryScan, savedCD

        before_each(function()
            onEvent, scanned = nil, {}
            savedCreateFrame, savedCD = _G.CreateFrame, AltArmy.CooldownData
            savedScanLegacy, savedTryScan = DS.ScanLegacyTalents, DS.TryScanTrackedCooldownFromSpellApi
            _G.CreateFrame = function()
                return {
                    RegisterEvent = function() end,
                    SetScript = function(_, script, handler)
                        if script == "OnEvent" then onEvent = handler end
                    end,
                }
            end
            _G.UnitName = function() return "Legacychar" end
            _G.GetRealmName = function() return "Faerlina" end
            AltArmyTBC_Data.Characters = { Faerlina = { Legacychar = {
                legacyTalents = { spells = { [1225469] = 1, [1225470] = 1, [1225459] = 2 } },
            } } }
            package.loaded["CooldownData"] = nil
            require("CooldownData")
            package.loaded["DataStoreLegacy"] = nil
            require("DataStoreLegacy")
            DS.ScanLegacyTalents = function() end
            DS.TryScanTrackedCooldownFromSpellApi = function(_, spellId) scanned[#scanned + 1] = spellId end
        end)

        after_each(function()
            _G.CreateFrame, AltArmy.CooldownData = savedCreateFrame, savedCD
            DS.ScanLegacyTalents, DS.TryScanTrackedCooldownFromSpellApi = savedScanLegacy, savedTryScan
        end)

        it("reads Dedicated Study's and Essence of Innovation's cooldowns, even while the latter is hidden", function()
            onEvent(nil, "PLAYER_ENTERING_WORLD")
            table.sort(scanned)
            assert.are.same({ 1225469, 1225470 }, scanned)
        end)

        it("reads nothing for a character without those talents", function()
            AltArmyTBC_Data.Characters.Faerlina.Legacychar.legacyTalents = { spells = { [1225459] = 2 } }
            onEvent(nil, "PLAYER_ENTERING_WORLD")
            assert.are.same({}, scanned)
        end)
    end)
end)
