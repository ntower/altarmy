--[[
  Unit tests for Summary tab display list ordering (showSelfFirst + pin/hide).
  Mirrors the split logic from TabSummary.lua Update().
  Run from project root: npm test
]]

describe("Summary display list showSelfFirst", function()
    local CharKey

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Characters/?.lua"
        require("CharKey")
        require("RealmFilter")
        require("CharacterFilter")
        CharKey = AltArmy.CharKey
    end)

    --- Mirror TabSummary Update() filter/split (list is pre-sorted; order preserved within groups).
    local function buildDisplayList(inputList, opts)
        opts = opts or {}
        local showSelfFirst = opts.showSelfFirst == true
        local currentName = opts.currentName or "Me"
        local currentRealm = opts.currentRealm or "RealmA"
        local charSettings = opts.charSettings or {}

        local function GetCharSetting(name, realm, key)
            local c = charSettings[CharKey(name, realm)]
            if not c then return false end
            return c[key] == true
        end

        local function isSelf(entry)
            return entry.name == currentName and entry.realm == currentRealm
        end

        if opts.filter then
            inputList = AltArmy.CharacterFilter.FilterList(inputList, opts.filter, opts.ctx, {
                keep = function(e) return showSelfFirst and isSelf(e) end,
            })
        end

        local pinned, rest = {}, {}
        for i = 1, #inputList do
            local e = inputList[i]
            local isHidden = GetCharSetting(e.name, e.realm, "hide")
            if not isHidden or (showSelfFirst and isSelf(e)) then
                if GetCharSetting(e.name, e.realm, "pin") or (showSelfFirst and isSelf(e)) then
                    pinned[#pinned + 1] = e
                else
                    rest[#rest + 1] = e
                end
            end
        end

        local list = {}
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #rest do list[#list + 1] = rest[i] end
        return list
    end

    local sampleChars = {
        { name = "Alice", realm = "RealmA" },
        { name = "Me", realm = "RealmA" },
        { name = "Bob", realm = "RealmA" },
    }

    it("does not pin self by default (showSelfFirst false)", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = false })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Me", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("puts self in pinned group when showSelfFirst is enabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = true })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("shows hidden current character when showSelfFirst is enabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA" },
            { name = "Me", realm = "RealmA" },
            { name = "Bob", realm = "RealmA" },
        }
        local charSettings = {
            [CharKey("Me", "RealmA")] = { hide = true },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            charSettings = charSettings,
        })
        assert.are.equal(3, #list)
        assert.are.equal("Me", list[1].name)
    end)

    it("respects hide for current character when showSelfFirst is disabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA" },
            { name = "Me", realm = "RealmA" },
            { name = "Bob", realm = "RealmA" },
        }
        local charSettings = {
            [CharKey("Me", "RealmA")] = { hide = true },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            charSettings = charSettings,
        })
        assert.are.equal(2, #list)
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
    end)

    it("sorts pin-current-character with other pinned characters in list order", function()
        local chars = {
            { name = "Alice", realm = "RealmA" },
            { name = "Me", realm = "RealmA" },
            { name = "Bob", realm = "RealmA" },
        }
        local charSettings = {
            [CharKey("Bob", "RealmA")] = { pin = true },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            charSettings = charSettings,
        })
        assert.are.equal(3, #list)
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Alice", list[3].name)
    end)

    it("includes bank alts in the summary list", function()
        local chars = {
            { name = "Alice", realm = "RealmA" },
            { name = "Banker", realm = "RealmA" },
            { name = "Bob", realm = "RealmA" },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
        })
        assert.are.equal(3, #list)
        assert.are.equal("Banker", list[2].name)
    end)

    it("keeps the current character outside the filters when pinned, and drops the rest", function()
        local ctx = { currentRealm = "RealmA", currentFaction = "Horde", maxLevel = 60 }
        local filter = AltArmy.CharacterFilter.Ensure({}, { maxLevel = 60 })
        AltArmy.CharacterFilter.SetLevelRange(filter, 10, 60, 60)
        local chars = {
            { name = "Alice", realm = "RealmA", faction = "Horde", level = 5 },
            { name = "Me", realm = "RealmA", faction = "Horde", level = 5 },
            { name = "Far", realm = "RealmB", faction = "Horde", level = 40 },
            { name = "Bob", realm = "RealmA", faction = "Horde", level = 40 },
        }
        local list = buildDisplayList(chars, { showSelfFirst = true, filter = filter, ctx = ctx })
        assert.are.equal(2, #list)
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Bob", list[2].name)
    end)
end)
