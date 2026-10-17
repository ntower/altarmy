--[[ Unit tests for GlobalRealmFilter.lua — run: npm test ]]

describe("GlobalRealmFilter", function()
    local G

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("GlobalRealmFilter")
        G = AltArmy.GlobalRealmFilter
        assert.truthy(G)
    end)

    it("ResolveFromLegacyValues returns all only when all four are explicitly all", function()
        assert.are.equal("all", G.ResolveFromLegacyValues("all", "all", "all", "all"))
    end)

    it("ResolveFromLegacyValues returns currentRealm when any legacy value is nil", function()
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues(nil, "all", "all", "all"))
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues("all", nil, "all", "all"))
    end)

    it("ResolveFromLegacyValues returns currentRealm when any tab is currentRealm", function()
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues("all", "all", "all", "currentRealm"))
    end)

    describe("scope", function()
        before_each(function()
            _G.AltArmyTBC_Options = {}
            _G.UnitFactionGroup = function() return "Horde" end
        end)

        after_each(function()
            _G.UnitFactionGroup = nil
        end)

        it("comes from the old realm filter: all realms turns on both, current realm neither", function()
            AltArmyTBC_Options.realmFilter = "currentRealm"
            assert.are.same({ version = 1, otherFaction = false, otherRealms = false, linked = true }, G.GetScope())
            _G.AltArmyTBC_Options = { realmFilter = "all" }
            assert.are.same({ version = 1, otherFaction = true, otherRealms = true, linked = true }, G.GetScope())
        end)

        it("keeps realmFilter in step, so Get still answers all or currentRealm", function()
            G.SetScope("otherRealms", true)
            assert.are.equal("all", G.Get())
            G.Set("currentRealm")
            assert.is_false(G.GetScope().otherRealms)
            G.SetScope("otherFaction", true)
            assert.are.equal("currentRealm", G.Get())
            assert.is_true(G.GetScope().otherFaction)
        end)

        it("follows an older addon that changed realmFilter since", function()
            G.GetScope()
            AltArmyTBC_Options.realmFilter = "all"
            assert.is_true(G.GetScope().otherRealms)
        end)

        it("ignores unknown toggles and resets to the defaults", function()
            G.SetScope("everything", true)
            assert.is_nil(G.GetScope().everything)
            G.SetScope("otherFaction", true)
            G.SetScope("otherRealms", true)
            G.ResetScope()
            assert.are.same({ version = 1, otherFaction = false, otherRealms = false, linked = true }, G.GetScope())
            assert.are.equal("currentRealm", G.Get())
        end)

        it("filters a list by the scope, looking factions up by name", function()
            package.path = package.path .. ";AltArmy_TBC/Data/Characters/?.lua"
            require("RealmFilter")
            AltArmy.DataStore = {
                GetCharacter = function(_, name)
                    return name == "Ally" and { faction = "Alliance" } or { faction = "Horde" }
                end,
            }
            G.SetScope("otherFaction", false)
            local list = { { realm = "R", name = "Me" }, { realm = "R", name = "Ally" },
                { realm = "X", characterName = "Far" } }
            local out = G.FilterList(list, "R")
            assert.are.equal(1, #out)
            assert.are.equal("Me", out[1].name)
            G.SetScope("otherFaction", true)
            G.SetScope("otherRealms", true)
            assert.are.equal(3, #G.FilterList(list, "R"))
            AltArmy.DataStore = nil
        end)
    end)
end)
