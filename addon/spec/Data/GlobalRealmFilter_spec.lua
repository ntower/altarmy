--[[ Unit tests for GlobalRealmFilter.lua: the Summary tab's realm filter, for the other tabs. Run: npm test ]]

describe("GlobalRealmFilter", function()
    local G

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Characters/?.lua"
        require("RealmFilter")
        require("CharacterFilter")
        require("GlobalRealmFilter")
        G = AltArmy.GlobalRealmFilter
        assert.truthy(G)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        _G.AltArmyTBC_SummarySettings = nil
        _G.UnitFactionGroup = function() return "Horde" end
    end)

    after_each(function()
        _G.UnitFactionGroup = nil
        AltArmy.DataStore = nil
    end)

    it("is the Summary tab's realm filter", function()
        local scope = G.GetScope()
        assert.are.equal(AltArmyTBC_SummarySettings.filter.scope, scope)
        assert.are.same({ otherFaction = false, otherRealms = false, linked = true }, scope)
    end)

    it("starts from the old global scope", function()
        AltArmyTBC_Options.characterScope = { version = 1, otherFaction = true, otherRealms = true, linked = false }
        assert.are.same({ otherFaction = true, otherRealms = true, linked = false }, G.GetScope())
    end)

    it("answers all or currentRealm by other realms", function()
        assert.are.equal("currentRealm", G.Get())
        G.GetScope().otherRealms = true
        assert.are.equal("all", G.Get())
    end)

    it("filters a list by the scope, looking factions up by name", function()
        AltArmy.DataStore = {
            GetCharacter = function(_, name)
                return name == "Ally" and { faction = "Alliance" } or { faction = "Horde" }
            end,
        }
        local list = { { realm = "R", name = "Me", level = 5, classFile = "MAGE" }, { realm = "R", name = "Ally" },
            { realm = "X", characterName = "Far" } }
        AltArmyTBC_SummarySettings = {}
        G.Ensure().levelMin = 10 -- the Summary's level filter is its own
        local out = G.FilterList(list, "R")
        assert.are.equal(1, #out)
        assert.are.equal("Me", out[1].name)
        G.GetScope().otherFaction = true
        G.GetScope().otherRealms = true
        assert.are.equal(3, #G.FilterList(list, "R"))
        assert.is_true(G.Includes({ realm = "X", faction = "Alliance" }, "R"))
    end)

    it("drops linked accounts' characters when the Summary leaves them out", function()
        G.GetScope().linked = false
        assert.are.same({}, G.FilterList({ { realm = "R", faction = "Horde", linkId = "a" } }, "R"))
    end)
end)
