--[[
  Unit tests for the reusable ScoreSortRow logic (provider resolution + comparator).
  The UI factory is not exercised here (requires WoW frames); only pure logic.
]]

describe("ScoreSortRow logic", function()
    local SSR

    local providerDefs
    local fakeProviders
    local missingChars

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/UI/?.lua"
        require("CharKey")
        require("CharacterSort")

        providerDefs = {
            level = { id = "level", label = "Level", sortLabel = "Level", shortLabel = "Lvl" },
            ["gs:Foo"] = { id = "gs:Foo", label = "GearScore", sortLabel = "GearScore", shortLabel = "GS" },
            played = {
                id = "played",
                label = "Time Played",
                sortLabel = "Time Played",
                shortLabel = "Played",
            },
        }
        _G.AltArmy.GearScore = {
            RefreshProviders = function() end,
            GetAvailableProviders = function() return fakeProviders end,
            GetProvider = function(id) return providerDefs[id] end,
            GetProviderShortLabel = function(id)
                local p = providerDefs[id]
                return p and p.shortLabel or "Level"
            end,
            IsScoreMissing = function(char) return char ~= nil and char.__missing == true end,
        }
        _G.AltArmy.DataStore = {
            GetCharacter = function(_, name) return missingChars[name] end,
            GetCharacterFor = function(_, name) return missingChars[name] end,
        }

        assert(loadfile("AltArmy_TBC/UI/ScoreSortRow.lua"))()
        SSR = AltArmy.ScoreSortRow
    end)

    before_each(function()
        fakeProviders = { { id = "level" } }
        missingChars = {}
    end)

    local function entry(name, level)
        return { name = name, realm = "R", level = level }
    end

    describe("ValidateProvider", function()
        it("returns the id when it is available", function()
            fakeProviders = { { id = "level" }, { id = "gs:Foo" } }
            assert.are.equal("gs:Foo", SSR.ValidateProvider("gs:Foo"))
        end)
        it("falls back to level when the id is not available", function()
            fakeProviders = { { id = "level" } }
            assert.are.equal("level", SSR.ValidateProvider("gs:Missing"))
        end)
        it("maps legacy gs_lite to the first available gs: provider", function()
            fakeProviders = { { id = "level" }, { id = "gs:Foo" } }
            assert.are.equal("gs:Foo", SSR.ValidateProvider("gs_lite"))
        end)
    end)

    describe("Compare", function()
        it("sorts higher value first when descending", function()
            local a, b = entry("Alice", 70), entry("Bob", 60)
            assert.is_true(SSR.Compare(a, b, "level", true))
            assert.is_false(SSR.Compare(b, a, "level", true))
        end)
        it("sorts lower value first when ascending", function()
            local a, b = entry("Alice", 70), entry("Bob", 60)
            assert.is_true(SSR.Compare(b, a, "level", false))
        end)
        it("breaks ties by name", function()
            local a, b = entry("Alice", 70), entry("Bob", 70)
            assert.is_true(SSR.Compare(a, b, "level", true))
        end)
        it("sorts characters with missing scores last", function()
            missingChars = { Bob = { __missing = true } }
            local a, b = entry("Alice", 10), entry("Bob", 99)
            assert.is_true(SSR.Compare(a, b, "level", true))
            assert.is_false(SSR.Compare(b, a, "level", true))
        end)
        it("sorts by Time Played when played provider selected", function()
            fakeProviders = { { id = "level" }, { id = "played" } }
            local a = { name = "Alice", realm = "R", played = 10000 }
            local b = { name = "Bob", realm = "R", played = 5000 }
            assert.is_true(SSR.Compare(a, b, "played", true))
            assert.is_false(SSR.Compare(b, a, "played", true))
        end)
    end)
end)
