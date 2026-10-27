--[[ Unit tests for Data/Characters/CharacterSections.lua: run with npm test ]]

describe("CharacterSections", function()
    local CS

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/Characters/?.lua;AltArmy_TBC/Tabs/?.lua"
        require("SearchStickyHeaders")
        require("CharacterSections")
        CS = AltArmy.CharacterSections
    end)

    local here = { currentRealm = "Home", currentFaction = "Horde" }

    local function grouped(list)
        return CS.BuildElements(list, { grouped = true, currentRealm = here.currentRealm,
            currentFaction = here.currentFaction })
    end

    local function shape(elements)
        local out = {}
        for _, el in ipairs(elements) do
            out[#out + 1] = el.kind == "header" and ("# " .. el.label) or el.entry.name
        end
        return out
    end

    it("lists characters alone when not grouped", function()
        local list = { { name = "A", realm = "Home" }, { name = "B", realm = "Far" } }
        local elements = CS.BuildElements(list, { grouped = false })
        assert.are.same({ "A", "B" }, shape(elements))
    end)

    it("puts this realm and faction first, then its other faction, then other realms A to Z", function()
        local list = {
            { name = "Z1", realm = "Zeta", faction = "Horde" },
            { name = "A1", realm = "Alpha", faction = "Alliance" },
            { name = "H2", realm = "Home", faction = "Alliance" },
            { name = "H1", realm = "Home", faction = "Horde" },
            { name = "A2", realm = "Alpha", faction = "Horde" },
            { name = "H3", realm = "Home", faction = "Horde" },
        }
        assert.are.same({
            "# Home — Horde (2)", "H1", "H3",
            "# Home — Alliance (1)", "H2",
            "# Alpha — Horde (1)", "A2",
            "# Alpha — Alliance (1)", "A1",
            "# Zeta — Horde (1)", "Z1",
        }, shape(grouped(list)))
    end)

    it("draws the header even when every character is in one section", function()
        local list = { { name = "A", realm = "Home", faction = "Horde" }, { name = "B", realm = "Home", faction = "Horde" } }
        assert.are.same({ "# Home — Horde (2)", "A", "B" }, shape(grouped(list)))
    end)

    it("folds a collapsed section's characters away under its header", function()
        local list = {
            { name = "H1", realm = "Home", faction = "Horde" },
            { name = "F1", realm = "Far", faction = "Horde" },
            { name = "F2", realm = "Far", faction = "Horde" },
        }
        local elements = CS.BuildElements(list, { grouped = true, currentRealm = "Home", currentFaction = "Horde",
            collapsed = { [CS.SectionKey("Far", "Horde")] = true } })
        assert.are.same({ "# Home — Horde (1)", "H1", "# Far — Horde (2)" }, shape(elements))
        assert.is_false(elements[1].collapsed)
        assert.is_true(elements[3].collapsed)
        assert.are.equal("Far|Horde", elements[3].key)
    end)

    it("files a character of unknown faction under the realm alone, last", function()
        local list = {
            { name = "U", realm = "Home" },
            { name = "H", realm = "Home", faction = "Horde" },
        }
        assert.are.same({ "# Home — Horde (1)", "H", "# Home (1)", "U" }, shape(grouped(list)))
    end)

    it("puts a linked account's character in its realm and faction's section", function()
        local list = {
            { name = "Mine", realm = "Home", faction = "Horde" },
            { name = "Theirs", realm = "Home", faction = "Horde", linkId = "x" },
            { name = "Away", realm = "Far", faction = "Horde" },
        }
        assert.are.same({ "# Home — Horde (2)", "Mine", "Theirs", "# Far — Horde (1)", "Away" },
            shape(grouped(list)))
    end)

    describe("StickyHeaderLayout", function()
        -- two sections of 3: header 1 at index 1, header 2 at index 5
        local elements
        before_each(function()
            elements = grouped({
                { name = "a", realm = "Home", faction = "Horde" },
                { name = "b", realm = "Home", faction = "Horde" },
                { name = "c", realm = "Home", faction = "Horde" },
                { name = "d", realm = "Far", faction = "Horde" },
                { name = "e", realm = "Far", faction = "Horde" },
                { name = "f", realm = "Far", faction = "Horde" },
            })
        end)

        local function tops(layout)
            local out = {}
            for _, h in ipairs(layout) do
                out[#out + 1] = { h.elementIndex, h.top }
            end
            return out
        end

        it("draws each header in its own slot at the top", function()
            assert.are.same({ { 1, 0 }, { 5, 80 } }, tops(CS.StickyHeaderLayout(elements, 0, 10, 20)))
        end)

        it("pins the first header once scrolled past it", function()
            assert.are.same({ { 1, 0 }, { 5, 40 } }, tops(CS.StickyHeaderLayout(elements, 2, 10, 20)))
        end)

        it("lets the next header push it out", function()
            assert.are.same({ { 5, 0 } }, tops(CS.StickyHeaderLayout(elements, 4, 10, 20)))
            assert.are.same({ { 5, 0 } }, tops(CS.StickyHeaderLayout(elements, 6, 10, 20)))
        end)

        it("leaves out headers below the visible rows", function()
            assert.are.same({ { 1, 0 } }, tops(CS.StickyHeaderLayout(elements, 0, 3, 20)))
        end)

        it("says which section each header is and whether it is collapsed", function()
            local layout = CS.StickyHeaderLayout(elements, 0, 10, 20)
            assert.are.equal("Home|Horde", layout[1].key)
            assert.is_false(layout[1].collapsed)
        end)

        it("gives nothing for an ungrouped list", function()
            local flat = CS.BuildElements({ { name = "a" } }, { grouped = false })
            assert.are.same({}, CS.StickyHeaderLayout(flat, 0, 10, 20))
        end)
    end)
    describe("Forever's coalesced realms", function()
        before_each(function()
            require("RealmFilter")
            AltArmy.DataStore = { IsWowForever = true }
        end)
        after_each(function()
            AltArmy.DataStore = nil
        end)

        it("puts one cluster, region and ruleset's realms in one section, first when it is this one", function()
            local list = {
                { name = "Ariel", realm = "CAMWOW EU4 Realm 1 PvE", faction = "Horde" },
                { name = "Frells", realm = "CAMWOW US2 Realm 3 PvE", faction = "Horde" },
                { name = "Frell", realm = "CAMWOW US3 Realm 5 PvE", faction = "Horde" },
            }
            local elements = CS.BuildElements(list, { grouped = true, currentRealm = "CAMWOW US3 Realm 5 PvE",
                currentFaction = "Horde" })
            assert.are.same({ "# US PvE — Horde (2)", "Frells", "Frell", "# EU PvE — Horde (1)", "Ariel" },
                shape(elements))
            assert.are.equal("CAMWOW US PvE|Horde", elements[1].key)
        end)
    end)
end)
