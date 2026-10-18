--[[ Unit tests for Debug.lua — run: npm test ]]

describe("AltArmy.Debug", function()
    local D

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["Debug"] = nil
        require("Debug")
        D = AltArmy.Debug
        assert.truthy(D)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        D.Ensure()
    end)

    it("Ensure defaults enabled, search, and cooldowns to false", function()
        assert.is_false(D.IsEnabled())
        assert.is_false(D.IsSearchEnabled())
        assert.is_false(D.IsCooldownsEnabled())
        assert.is_false(D.IsLevelHistoryEnabled())
        assert.is_false(D.IsItemComparisonEnabled())
        assert.is_false(AltArmyTBC_Options.debug.enabled)
        assert.is_false(AltArmyTBC_Options.debug.search)
        assert.is_false(AltArmyTBC_Options.debug.cooldowns)
        assert.is_false(AltArmyTBC_Options.debug.levelHistory)
        assert.is_false(AltArmyTBC_Options.debug.itemComparison)
        assert.is_false(AltArmyTBC_Options.debug.itemStats)
        assert.is_false(D.IsShowZygorMissingGuides())
        assert.is_false(D.IsWindowWidthResizeEnabled())
    end)

    it("IsGuildShareEnabled is always on (shipped feature, not a debug toggle)", function()
        assert.is_false(D.IsEnabled())
        assert.is_true(D.IsGuildShareEnabled())
    end)

    it("guildShareVerbose defaults false and is standalone (not requiring master enabled)", function()
        assert.is_false(D.IsGuildShareVerbose())
        assert.is_false(AltArmyTBC_Options.debug.guildShareVerbose)
        D.SetGuildShareVerbose(true)
        assert.is_true(D.IsGuildShareVerbose())
        D.SetGuildShareVerbose(false)
        assert.is_false(D.IsGuildShareVerbose())
    end)

    it("LogGuildShare only emits to chat when verbose is on", function()
        local messages = {}
        local original = D.NotifyChat
        D.NotifyChat = function(m) messages[#messages + 1] = m end

        D.SetGuildShareVerbose(false)
        D.LogGuildShare("hidden")
        assert.are.equal(0, #messages)

        D.SetGuildShareVerbose(true)
        D.LogGuildShare("visible")
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("GuildShare", messages[1])

        D.NotifyChat = original
    end)

    it("IsSearchEnabled is false when search is on but master is off", function()
        AltArmyTBC_Options.debug.search = true
        assert.is_false(D.IsSearchEnabled())
    end)

    it("IsSearchEnabled is true when master and search are on", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        assert.is_true(D.IsSearchEnabled())
    end)

    it("LogSearch only emits when master and search are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogSearch("hidden")
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        D.LogSearch("visible")
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
    end)

    it("IsCooldownsEnabled is false when cooldowns is on but master is off", function()
        AltArmyTBC_Options.debug.cooldowns = true
        assert.is_false(D.IsCooldownsEnabled())
    end)

    it("IsCooldownsEnabled is true when master and cooldowns are on", function()
        D.SetEnabled(true)
        D.SetCooldownsEnabled(true)
        assert.is_true(D.IsCooldownsEnabled())
    end)

    it("IsLevelHistoryEnabled is false when levelHistory is on but master is off", function()
        AltArmyTBC_Options.debug.levelHistory = true
        assert.is_false(D.IsLevelHistoryEnabled())
    end)

    it("IsLevelHistoryEnabled is true when master and levelHistory are on", function()
        D.SetEnabled(true)
        D.SetLevelHistoryEnabled(true)
        assert.is_true(D.IsLevelHistoryEnabled())
    end)

    it("IsItemComparisonEnabled is true when master and itemComparison are on", function()
        D.SetEnabled(true)
        D.SetItemComparisonEnabled(true)
        assert.is_true(D.IsItemComparisonEnabled())
    end)

    it("LogItemComparison only emits when master and itemComparison are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogItemComparison({ "hidden" })
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetItemComparisonEnabled(true)
        D.LogItemComparison({ "visible" })
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("Compare", messages[1])
    end)

    it("IsItemStatsEnabled is true when master and itemStats are on", function()
        D.SetEnabled(true)
        D.SetItemStatsEnabled(true)
        assert.is_true(D.IsItemStatsEnabled())
    end)

    it("LogItemStats only emits when master and itemStats are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogItemStats({ "hidden" })
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetItemStatsEnabled(true)
        D.LogItemStats({ "visible" })
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("ItemStats", messages[1])
    end)

    it("SetEnabled(false) does not clear search or cooldowns flags", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        D.SetCooldownsEnabled(true)
        D.SetEnabled(false)
        assert.is_false(D.IsEnabled())
        assert.is_true(AltArmyTBC_Options.debug.search)
        assert.is_true(AltArmyTBC_Options.debug.cooldowns)
    end)

    it("mutations persist in AltArmyTBC_Options.debug", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        assert.is_true(AltArmyTBC_Options.debug.enabled)
        assert.is_true(AltArmyTBC_Options.debug.search)
    end)

    it("AppendComparePanelDump stores payloads in comparePanelDumps", function()
        local payload = { version = 1, character = { name = "MageAlt" } }
        local index = D.AppendComparePanelDump(payload)
        assert.are.equal(1, index)
        assert.are.same(payload, AltArmyTBC_Options.debug.comparePanelDumps[1])
    end)

    it("IsShowZygorMissingGuides is standalone (not requiring master enabled)", function()
        assert.is_false(D.IsEnabled())
        D.SetShowZygorMissingGuides(true)
        assert.is_true(D.IsShowZygorMissingGuides())
        assert.is_true(AltArmyTBC_Options.debug.showZygorMissingGuides)
        D.SetShowZygorMissingGuides(false)
        assert.is_false(D.IsShowZygorMissingGuides())
    end)

    it("IsWindowWidthResizeEnabled is standalone and calls the window's resize hook", function()
        local applied = {}
        AltArmy.ApplyWindowResize = function() applied[#applied + 1] = D.IsWindowWidthResizeEnabled() end
        assert.is_false(D.IsEnabled())
        D.SetWindowWidthResizeEnabled(true)
        assert.is_true(D.IsWindowWidthResizeEnabled())
        assert.is_true(AltArmyTBC_Options.debug.windowWidthResize)
        D.SetWindowWidthResizeEnabled(false)
        assert.is_false(D.IsWindowWidthResizeEnabled())
        assert.are.same({ true, false }, applied)
        AltArmy.ApplyWindowResize = nil
    end)

    it("Ensure drops the legacy windowResize key", function()
        _G.AltArmyTBC_Options = { debug = { windowResize = true } }
        D.Ensure()
        assert.is_nil(AltArmyTBC_Options.debug.windowResize)
        assert.is_false(D.IsWindowWidthResizeEnabled())
    end)

    it("AppendComparePanelDump keeps only the newest MAX_COMPARE_PANEL_DUMPS entries", function()
        for i = 1, D.MAX_COMPARE_PANEL_DUMPS + 3 do
            D.AppendComparePanelDump({ version = 1, index = i })
        end
        local dumps = AltArmyTBC_Options.debug.comparePanelDumps
        assert.are.equal(D.MAX_COMPARE_PANEL_DUMPS, #dumps)
        assert.are.equal(4, dumps[1].index)
        assert.are.equal(D.MAX_COMPARE_PANEL_DUMPS + 3, dumps[#dumps].index)
    end)

    it("AppendGuildShareUndecodableDump stores payloads in guildShareUndecodableDumps", function()
        local payload = { version = 1, sender = "Orfinam", message = "^1^SP^T" }
        local index = D.AppendGuildShareUndecodableDump(payload)
        assert.are.equal(1, index)
        assert.are.same(payload, AltArmyTBC_Options.debug.guildShareUndecodableDumps[1])
    end)

    it("AppendGuildShareUndecodableDump keeps only the newest MAX_GUILD_SHARE_UNDECODABLE_DUMPS entries", function()
        for i = 1, D.MAX_GUILD_SHARE_UNDECODABLE_DUMPS + 3 do
            D.AppendGuildShareUndecodableDump({ version = 1, index = i })
        end
        local dumps = AltArmyTBC_Options.debug.guildShareUndecodableDumps
        assert.are.equal(D.MAX_GUILD_SHARE_UNDECODABLE_DUMPS, #dumps)
        assert.are.equal(4, dumps[1].index)
        assert.are.equal(D.MAX_GUILD_SHARE_UNDECODABLE_DUMPS + 3, dumps[#dumps].index)
    end)

    it("SaveApiCheckSnapshot overwrites rather than appends", function()
        D.SaveApiCheckSnapshot({ version = 1, counts = { total = 1 } })
        D.SaveApiCheckSnapshot({ version = 1, counts = { total = 2 } })
        assert.are.equal(2, AltArmyTBC_Options.debug.apiCheckSnapshot.counts.total)
    end)

    it("SaveApiCheckSnapshot silently ignores non-table input", function()
        D.SaveApiCheckSnapshot({ version = 1, counts = { total = 1 } })
        D.SaveApiCheckSnapshot("not a table")
        assert.are.equal(1, AltArmyTBC_Options.debug.apiCheckSnapshot.counts.total)
    end)

    describe("Dump (standing dev-dump tool, see docs/DEV_DUMPS.md)", function()
        it("Dump is a no-op when master debug is off: no SavedVariables write, no alert", function()
            local alerted = {}
            local oldAlert = D.ShowCenterAlert
            D.ShowCenterAlert = function(text) alerted[#alerted + 1] = text end
            D.Dump("myLabel", { foo = "bar" })
            D.ShowCenterAlert = oldAlert
            assert.is_nil(AltArmyTBC_Options.debug.devDumps)
            assert.are.equal(0, #alerted)
        end)

        it("Dump stores the payload under devDumps[label] and alerts when master debug is on", function()
            D.SetEnabled(true)
            local alerted = {}
            local oldAlert = D.ShowCenterAlert
            D.ShowCenterAlert = function(text) alerted[#alerted + 1] = text end
            D.Dump("myLabel", { foo = "bar" })
            D.ShowCenterAlert = oldAlert
            assert.are.same({ foo = "bar" }, AltArmyTBC_Options.debug.devDumps.myLabel)
            assert.are.equal(1, #alerted)
            assert.matches("myLabel", alerted[1])
        end)

        it("Dump keys by label so different call sites don't clobber each other", function()
            D.SetEnabled(true)
            D.Dump("labelA", { a = 1 })
            D.Dump("labelB", { b = 2 })
            assert.are.same({ a = 1 }, AltArmyTBC_Options.debug.devDumps.labelA)
            assert.are.same({ b = 2 }, AltArmyTBC_Options.debug.devDumps.labelB)
        end)

        it("Dump overwrites the previous payload for the same label", function()
            D.SetEnabled(true)
            D.Dump("myLabel", { version = 1 })
            D.Dump("myLabel", { version = 2 })
            assert.are.equal(2, AltArmyTBC_Options.debug.devDumps.myLabel.version)
        end)

        it("Dump silently ignores a missing or non-string label", function()
            D.SetEnabled(true)
            D.Dump(nil, { a = 1 })
            D.Dump(42, { a = 1 })
            assert.is_nil(AltArmyTBC_Options.debug.devDumps)
        end)
    end)

    describe("IsLinkedAccountsEnabled", function()
        local savedDS

        before_each(function()
            savedDS = AltArmy.DataStore
        end)

        after_each(function()
            AltArmy.DataStore = savedDS
        end)

        it("is on for WoW: Forever, whether or not debug is", function()
            AltArmy.DataStore = { IsWowForever = true }
            D.SetEnabled(false)
            assert.is_true(D.IsLinkedAccountsEnabled())
        end)

        it("is off on TBC Anniversary, even with debug on", function()
            AltArmy.DataStore = { IsWowForever = false }
            D.SetEnabled(true)
            assert.is_false(D.IsLinkedAccountsEnabled())
            D.SetEnabled(false)
        end)
    end)
end)
