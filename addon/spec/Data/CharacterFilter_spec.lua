--[[ Unit tests for Data/Characters/CharacterFilter.lua: run with npm test ]]

describe("CharacterFilter", function()
    local CF

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Characters/?.lua"
        require("ClassColor")
        require("CharKey")
        require("RealmFilter")
        require("CharacterSections")
        require("CharacterFilter")
        CF = AltArmy.CharacterFilter
    end)

    before_each(function()
        _G.AltArmyTBC_Options = nil
    end)

    describe("the level range's text", function()
        it("says All for every level, one level alone, else the range", function()
            assert.are.equal("All", CF.FormatLevelRange(1, 60, 60))
            assert.are.equal("42", CF.FormatLevelRange(42, 42, 60))
            assert.are.equal("10–59", CF.FormatLevelRange(10, 59, 60))
            assert.are.equal("1–60", CF.FormatLevelRange(1, 60, 70))
        end)
    end)

    describe("Ensure", function()
        it("defaults to this realm and faction plus linked accounts, every level and class", function()
            local s = {}
            local f = CF.Ensure(s, { maxLevel = 60 })
            assert.are.equal(s.filter, f)
            assert.are.equal(CF.VERSION, f.version)
            assert.are.same({ otherFaction = false, otherRealms = false, linked = true }, f.scope)
            assert.are.equal(1, f.levelMin)
            assert.are.equal(60, f.levelMax)
            assert.are.equal(9, #CF.CLASS_ORDER)
            for _, classFile in ipairs(CF.CLASS_ORDER) do
                assert.is_true(f.classes[classFile])
            end
        end)

        it("keeps what was chosen and is idempotent", function()
            local s = {}
            CF.Ensure(s, { maxLevel = 60 })
            CF.SetLevelRange(s.filter, 20, 45, 60)
            s.filter.classes.MAGE = false
            s.filter.scope.otherRealms = true
            local f = CF.Ensure(s, { maxLevel = 60 })
            assert.are.equal(20, f.levelMin)
            assert.are.equal(45, f.levelMax)
            assert.is_false(f.classes.MAGE)
            assert.is_true(f.scope.otherRealms)
        end)

        it("turns the old level buckets into the range from the lowest shown to the highest", function()
            local s = { filter = { version = CF.VERSION, levels = { ["1-9"] = false, ["10-19"] = true,
                ["20-29"] = false, ["30-39"] = true, ["40-49"] = false, ["50-59"] = false, ["60"] = false } } }
            local f = CF.Ensure(s, { maxLevel = 60 })
            assert.are.equal(10, f.levelMin)
            assert.are.equal(39, f.levelMax)
            assert.is_nil(f.levels)
            s = { filter = { version = CF.VERSION, levels = { ["50-59"] = true, ["60"] = true } } }
            f = CF.Ensure(s, { maxLevel = 60 })
            assert.are.equal(50, f.levelMin)
            assert.are.equal(60, f.levelMax)
        end)

        it("shows every level when no old bucket was on, and keeps the range inside the cap", function()
            local f = CF.Ensure({ filter = { version = CF.VERSION, levels = { ["1-9"] = false } } },
                { maxLevel = 60 })
            assert.are.equal(1, f.levelMin)
            assert.are.equal(60, f.levelMax)
            f = CF.Ensure({ filter = { version = CF.VERSION, levelMin = 65, levelMax = 70 } }, { maxLevel = 60 })
            assert.are.equal(60, f.levelMin)
            assert.are.equal(60, f.levelMax)
            CF.SetLevelRange(f, 40, 12.7, 60)
            assert.are.equal(40, f.levelMin)
            assert.are.equal(40, f.levelMax)
        end)

        it("seeds the scope once from the old global one", function()
            _G.AltArmyTBC_Options = {
                characterScope = { version = 1, otherFaction = true, otherRealms = false, linked = false },
            }
            local f = CF.Ensure({}, { maxLevel = 60 })
            assert.are.same({ otherFaction = true, otherRealms = false, linked = false }, f.scope)
        end)

        it("seeds other realms and the other faction from an old realm filter of all", function()
            _G.AltArmyTBC_Options = { realmFilter = "all" }
            local f = CF.Ensure({}, { maxLevel = 60 })
            assert.are.same({ otherFaction = true, otherRealms = true, linked = true }, f.scope)
        end)

        it("starts again when the version is not this one", function()
            local s = { filter = { version = 0, levels = { ["1-9"] = false } } }
            local f = CF.Ensure(s, { maxLevel = 60 })
            assert.are.equal(CF.VERSION, f.version)
            assert.are.equal(1, f.levelMin)
            assert.is_nil(f.levels)
        end)
    end)

    describe("Matches and FilterList", function()
        local ctx = { currentRealm = "R", currentFaction = "Horde", maxLevel = 60 }
        local function filter()
            return CF.Ensure({}, { maxLevel = 60 })
        end

        it("goes by realm and faction through RealmFilter", function()
            local f = filter()
            assert.is_true(CF.Matches({ realm = "R", faction = "Horde", level = 30 }, f, ctx))
            assert.is_false(CF.Matches({ realm = "R", faction = "Alliance", level = 30 }, f, ctx))
            assert.is_false(CF.Matches({ realm = "X", faction = "Horde", level = 30 }, f, ctx))
            f.scope.otherFaction = true
            assert.is_true(CF.Matches({ realm = "R", faction = "Alliance", level = 30 }, f, ctx))
            f.scope.otherRealms = true
            assert.is_true(CF.Matches({ realm = "X", faction = "Alliance", level = 30 }, f, ctx))
        end)

        it("drops linked accounts' characters when linked is off", function()
            local f = filter()
            local linked = { realm = "R", faction = "Horde", level = 30, linkId = "abc" }
            assert.is_true(CF.Matches(linked, f, ctx))
            f.scope.linked = false
            assert.is_false(CF.Matches(linked, f, ctx))
        end)

        it("goes by level range and class; an unknown class or level passes", function()
            local f = filter()
            CF.SetLevelRange(f, 10, 29, 60)
            f.classes.MAGE = false
            assert.is_false(CF.Matches({ realm = "R", faction = "Horde", level = 9.9 }, f, ctx))
            assert.is_true(CF.Matches({ realm = "R", faction = "Horde", level = 10 }, f, ctx))
            assert.is_true(CF.Matches({ realm = "R", faction = "Horde", level = 29.9 }, f, ctx))
            assert.is_false(CF.Matches({ realm = "R", faction = "Horde", level = 30 }, f, ctx))
            assert.is_false(CF.Matches({ realm = "R", faction = "Horde", level = 35.5 }, f, ctx))
            assert.is_false(CF.Matches({ realm = "R", faction = "Horde", level = 20, classFile = "MAGE" }, f, ctx))
            assert.is_true(CF.Matches({ realm = "R", faction = "Horde", level = 20, classFile = "" }, f, ctx))
            assert.is_true(CF.Matches({ realm = "R", faction = "Horde", classFile = "PRIEST" }, f, ctx))
        end)

        it("looks the faction up when an entry has none", function()
            local f = filter()
            local c = { currentRealm = "R", currentFaction = "Horde", maxLevel = 60,
                factionOf = function() return "Alliance" end }
            assert.is_false(CF.Matches({ realm = "R", level = 10 }, f, c))
        end)

        it("keeps what `keep` says whatever the filter, and scopeOnly ignores level and class", function()
            local f = filter()
            CF.SetLevelRange(f, 10, 60, 60)
            local me = { name = "Me", realm = "R", faction = "Horde", level = 5 }
            local far = { name = "Far", realm = "X", faction = "Horde", level = 5 }
            assert.are.same({}, CF.FilterList({ me, far }, f, ctx))
            assert.are.same({ me }, CF.FilterList({ me, far }, f, ctx, {
                keep = function(e) return e.name == "Me" end,
            }))
            assert.are.same({ me }, CF.FilterList({ me, far }, f, ctx, { scopeOnly = true }))
        end)
    end)

    describe("the dropdowns' maps and summaries", function()
        it("always shows this realm and faction on", function()
            local f = CF.Ensure({}, { maxLevel = 60 })
            assert.are.same({ own = true, otherFaction = false, otherRealms = false, linked = true },
                CF.ScopeFilterMap(f))
            CF.SetScope(f, "own", false)
            assert.is_true(CF.ScopeFilterMap(f).own)
            CF.SetScope(f, "otherRealms", true)
            assert.is_true(f.scope.otherRealms)
            assert.is_true(CF.ShowsOtherRealms(f))
        end)

        it("says All, None or the ones chosen", function()
            local keys = { "a", "b", "c" }
            local labels = { a = "A", b = "B", c = "C" }
            assert.are.equal("All", CF.FormatMultiSelectSummary(keys, labels, { a = true, b = true, c = true }))
            assert.are.equal("None", CF.FormatMultiSelectSummary(keys, labels, { a = false, b = false, c = false }))
            assert.are.equal("A, C", CF.FormatMultiSelectSummary(keys, labels, { a = true, b = false, c = true }))
        end)

        it("sums the realm filter up shortly", function()
            local f = CF.Ensure({}, { maxLevel = 60 })
            f.scope.linked = false
            assert.are.equal("This faction", CF.FormatScopeSummary(f, true))
            f.scope.otherFaction = true
            assert.are.equal("This realm", CF.FormatScopeSummary(f, true))
            f.scope.otherFaction = false
            f.scope.otherRealms = true
            assert.are.equal("This faction, Other realms", CF.FormatScopeSummary(f, true))
            f.scope.linked = true
            assert.are.equal("This faction, Other realms, Linked accounts", CF.FormatScopeSummary(f, true))
            assert.are.equal("This faction, Other realms", CF.FormatScopeSummary(f, false))
        end)

        it("says All when everything is on, All realms when only linked accounts are off", function()
            local f = CF.Ensure({}, { maxLevel = 60 })
            f.scope.otherFaction = true
            f.scope.otherRealms = true
            f.scope.linked = true
            assert.are.equal("All", CF.FormatScopeSummary(f, true))
            f.scope.linked = false
            assert.are.equal("All realms", CF.FormatScopeSummary(f, true))
            assert.are.equal("All", CF.FormatScopeSummary(f, false))
        end)

        it("offers linked accounts only when there are any", function()
            assert.are.same({ "own", "otherFaction", "otherRealms", "linked" }, CF.ScopeKeys(true))
            assert.are.same({ "own", "otherFaction", "otherRealms" }, CF.ScopeKeys(false))
        end)

        it("groups any character list by realm and faction, by name within each", function()
            local list = {
                { name = "b", realm = "Home", faction = "Horde" },
                { name = "x", realm = "Away", faction = "Horde" },
                { name = "A", realm = "Home", faction = "Horde" },
                { name = "c", realm = "Home", faction = "Alliance" },
            }
            local groups = CF.GroupByRealmFaction(list, { currentRealm = "Home", currentFaction = "Horde" })
            local names = {}
            for g, group in ipairs(groups) do
                names[g] = {}
                for i, e in ipairs(group) do names[g][i] = e.name end
            end
            assert.are.same({ { "A", "b" }, { "c" }, { "x" } }, names)
        end)

        it("says None or the chosen ones for the pin and hide dropdowns", function()
            local keys = { "self", "a", "b" }
            local labels = { self = "Current character", a = "A", b = "B" }
            assert.are.equal("None", CF.FormatChosenSummary(keys, labels, { self = false, a = false, b = false }))
            assert.are.equal("Current character, B", CF.FormatChosenSummary(keys, labels, { self = true, b = true }))
        end)

        it("lists characters to pin or hide by name, once each, the realm added when there are several", function()
            local list = {
                { name = "Zed", realm = "R" },
                { name = "amy", realm = "S" },
                { name = "Zed", realm = "R", linkId = "x" },
                { name = "Bank", realm = "R" },
            }
            local keys, labels, byKey = CF.CharacterChoices(list, {
                skip = function(e) return e.name == "Bank" end,
            })
            assert.are.same({ "divider:1", "R\\Zed", "divider:2", "S\\amy" }, keys)
            assert.are.same({ ["S\\amy"] = "amy — S", ["R\\Zed"] = "Zed — R", ["divider:1"] = "R",
                ["divider:2"] = "S" }, labels)
            assert.are.equal("amy", byKey["S\\amy"].name)
            local oneKeys, oneLabels = CF.CharacterChoices({ { name = "Zed", realm = "R" } })
            assert.are.same({ "divider:1", "R\\Zed" }, oneKeys)
            assert.are.equal("Zed", oneLabels["R\\Zed"])
        end)

        it("groups them by realm and faction, this realm and faction first, a divider between groups", function()
            local list = {
                { name = "Zed", realm = "Home", faction = "Horde" },
                { name = "Ally", realm = "Home", faction = "Alliance" },
                { name = "amy", realm = "Home", faction = "Horde" },
                { name = "Far", realm = "Away", faction = "Horde" },
            }
            local keys, labels = CF.CharacterChoices(list, { currentRealm = "Home", currentFaction = "Horde" })
            assert.are.same({ "divider:1", "Home\\amy", "Home\\Zed", "divider:2", "Home\\Ally", "divider:3",
                "Away\\Far" }, keys)
            assert.are.equal("Home — Horde", labels["divider:1"])
            assert.are.equal("Home — Alliance", labels["divider:2"])
            assert.are.equal("Away — Horde", labels["divider:3"])
            assert.is_true(CF.IsDividerKey("divider:1"))
            assert.is_false(CF.IsDividerKey("Home\\amy"))
        end)

        it("colours a class row and names it", function()
            _G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
            assert.are.equal("Mage", CF.ClassLabel("MAGE"))
            assert.are.equal("|cff40c7ebMage|r", CF.ClassRowLabel("MAGE"))
            _G.RAID_CLASS_COLORS = nil
        end)
    end)
end)
