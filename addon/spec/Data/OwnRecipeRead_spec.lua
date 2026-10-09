--[[ Unit tests for OwnRecipeRead.lua (reading recipes through trade links: the player's own and guildmates') — run: npm test ]]

describe("OwnRecipeRead", function()
    local R, DS
    local timers, links, closes, combat, panel, chatActive
    local frame
    local profs, spellbook
    local saved = {}
    local TOUCHED = {
        "C_Timer", "UnitGUID", "UnitName", "GetRealmName", "GetProfessions", "GetProfessionInfo", "C_SpellBook",
        "C_TradeSkillUI", "GetNumTradeSkills", "GetTradeSkillLine", "InCombatLockdown", "GetUIPanel",
        "ProfessionsFrame", "ChatEdit_GetActiveWindow", "CreateFrame", "UIParent",
        "AltArmyTBC_Options", "AltArmyTBC_Data", "time", "GetTime",
        "GetFramesRegisteredForEvent", "GetMouseFoci", "GetMouseFocus", "WorldFrame",
    }
    local savedSearchSettings

    local clock = 0

    --- Move the clock `seconds` on, running each timer that comes due (and those they queue) in time order.
    local function advance(seconds)
        local target = clock + seconds
        local guard = 0
        while true do
            local idx
            for i, t in ipairs(timers) do
                if t.at <= target and (not idx or t.at < timers[idx].at) then idx = i end
            end
            if not idx then break end
            local t = table.remove(timers, idx)
            clock = t.at
            t.fn()
            guard = guard + 1
            assert.is_true(guard < 1000)
        end
        clock = target
    end

    --- A fake frame that runs hooked OnShow/OnHide scripts.
    local function newFrame(name)
        local f = { name = name, shown = false, alpha = 1, scale = 1, mouse = true, hooks = {} }
        function f:HookScript(script, fn)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], fn)
        end
        local function run(self, script)
            for _, fn in ipairs(self.hooks[script] or {}) do fn(self) end
        end
        function f:Show() if not self.shown then self.shown = true; run(self, "OnShow") end end
        function f:Hide() if self.shown then self.shown = false; run(self, "OnHide") end end
        function f:IsShown() return self.shown end
        function f:SetAlpha(a) self.alpha = a end
        function f:GetAlpha() return self.alpha end
        function f:SetScale(s) self.scale = s end
        function f:GetScale() return self.scale end
        function f:EnableMouse(on) self.mouse = on end
        function f:IsMouseEnabled() return self.mouse end
        function f:GetParent() return nil end
        return f
    end

    local function lastLink() return links[#links] end

    --- The server's answer to an own read: the window opens and the DataStore scan stores it.
    local function reply(professionName)
        frame:Show()
        R.OnRecipesScanned(professionName)
    end

    local function login()
        R.OnEvent("PLAYER_ENTERING_WORLD", true, false)
        advance(R.LOGIN_DELAY)
    end

    setup(function()
        for _, k in ipairs(TOUCHED) do saved[k] = _G[k] end
        _G.AltArmy = _G.AltArmy or {}
        savedSearchSettings = AltArmy.SearchSettings
        _G.AltArmyTBC_Data = { Characters = {} }
        _G.CreateFrame = function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = {}
        require("DataStore")
        require("DataStoreItemSpellCompat")
        require("CooldownData")
        require("DataStoreProfessions")
        package.loaded["OwnRecipeRead"] = nil
        require("OwnRecipeRead")
        R = AltArmy.OwnRecipeRead
        DS = AltArmy.DataStore
        assert.truthy(R)
    end)

    teardown(function()
        for _, k in ipairs(TOUCHED) do _G[k] = saved[k] end
        AltArmy.SearchSettings = savedSearchSettings
    end)

    before_each(function()
        R._ResetForTests()
        R.REQUIRE_LINKED_NAME = true
        timers, links, closes, combat, panel, chatActive = {}, {}, 0, false, nil, nil
        _G.AltArmyTBC_Options = nil
        _G.AltArmyTBC_Data = { Characters = {} }
        DS.accountData = _G.AltArmyTBC_Data
        _G.time = function() return 1000 end
        clock = 0
        _G.GetTime = function() return clock end
        _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end }
        _G.UnitGUID = function(unit) if unit == "player" then return "Player-1-ABC" end end
        _G.UnitName = function() return "Me" end
        _G.GetRealmName = function() return "Realm" end
        -- Slots: 1 Tailoring, 2 Alchemy (its first spellbook spell opens nothing), 5 Cooking (rank 0).
        profs = {
            [1] = { name = "Tailoring", rank = 150, max = 225, numSpells = 1, offset = 10, line = 197 },
            [2] = { name = "Alchemy", rank = 75, max = 150, numSpells = 2, offset = 20, line = 171 },
            [5] = { name = "Cooking", rank = 0, max = 75, numSpells = 1, offset = 30, line = 185 },
        }
        spellbook = { [11] = 3908, [21] = 1111, [22] = 2259, [31] = 2550 }
        _G.GetProfessions = function() return 1, 2, nil, nil, 5, nil end
        _G.GetProfessionInfo = function(i)
            local p = profs[i]
            if not p then return nil end
            return p.name, "icon", p.rank, p.max, p.numSpells, p.offset, p.line
        end
        _G.C_SpellBook = {
            GetSpellBookItemInfo = function(slot)
                return spellbook[slot] and { spellID = spellbook[slot] } or nil
            end,
        }
        _G.GetNumTradeSkills, _G.GetTradeSkillLine = nil, nil
        frame = newFrame("ProfessionsFrame")
        _G.ProfessionsFrame = frame
        _G.C_TradeSkillUI = {
            GetAllRecipeIDs = function() return {} end,
            GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end,
            GetRecipeInfo = function() return nil end,
            IsTradeSkillLinked = function() return false end,
            CloseTradeSkill = function()
                closes = closes + 1
                frame:Hide()
            end,
        }
        AltArmy.SearchSettings = {
            ResolveProfessionKey = function(name)
                return ({ Tailoring = "tailoring", Alchemy = "alchemy", Cooking = "cooking" })[name]
            end,
        }
        -- Silencing is off unless a test gives the client GetFramesRegisteredForEvent.
        _G.GetFramesRegisteredForEvent, _G.GetMouseFoci, _G.GetMouseFocus = nil, nil, nil
        _G.WorldFrame = { name = "WorldFrame" }
        _G.InCombatLockdown = function() return combat end
        _G.GetUIPanel = function() return panel end
        _G.ChatEdit_GetActiveWindow = function() return chatActive end
        _G.CreateFrame = function(kind)
            if kind == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    Hide = function() end,
                    SetHyperlink = function(_, link) links[#links + 1] = link end,
                }
            end
            return { SetScript = function() end, RegisterEvent = function() end }
        end
    end)

    describe("when it runs", function()
        it("is on by default and can be turned off", function()
            assert.is_true(R.IsEnabled())
            R.SetEnabled(false)
            assert.is_false(R.IsEnabled())
            assert.is_false(AltArmyTBC_Options.autoReadRecipes)
            R.SetEnabled(true)
            assert.is_true(R.IsEnabled())
        end)

        it("reads the first profession after login, with a trade link to the player", function()
            R.OnEvent("PLAYER_ENTERING_WORLD", true, false)
            advance(R.LOGIN_DELAY - 1)
            assert.are.equal(0, #links)
            advance(1)
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)

        it("reads after a UI reload but not after zoning", function()
            R.OnEvent("PLAYER_ENTERING_WORLD", false, false)
            advance(60)
            assert.are.equal(0, #links)
            R.OnEvent("PLAYER_ENTERING_WORLD", false, true)
            advance(R.LOGIN_DELAY)
            assert.are.equal(1, #links)
        end)

        it("does nothing when turned off", function()
            R.SetEnabled(false)
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("does nothing on clients with the legacy trade skill API (TBC)", function()
            _G.GetNumTradeSkills = function() return 0 end
            _G.GetTradeSkillLine = function() return "Tailoring" end
            assert.is_false(R.HasApi())
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("skips professions the game won't link, such as Fishing", function()
            profs[2] = { name = "Fishing", rank = 75, max = 150, numSpells = 1, offset = 20, line = 356 }
            assert.are.equal(1, R.QueueAll())
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
            assert.is_false(R.CanRead("Fishing"))
        end)

        it("says which professions it can read", function()
            assert.is_true(R.CanRead("Tailoring"))
            for _, name in ipairs({ "Fishing", "Mining", "Herbalism", "Skinning", "Comprehension" }) do
                assert.is_false(R.CanRead(name), name)
            end
        end)

        it("skips professions without a rank or without a recipe window", function()
            profs[2] = { name = "Riding", rank = 75, max = 75, numSpells = 1, offset = 20, line = 762 }
            assert.are.equal(1, R.QueueAll())
        end)
    end)

    describe("a read", function()
        it("runs one profession at a time and closes the window once it is scanned", function()
            login()
            assert.are.equal(1, #links)
            advance(R.TIMEOUT - 1)
            assert.are.equal(1, #links)
            assert.is_true(R.IsReading())
            reply("Tailoring")
            assert.are.equal(1, closes)
            assert.is_false(R.IsReading())
            advance(R.GAP)
            assert.are.same({ "trade:Player-1-ABC:3908:197", "trade:Player-1-ABC:1111:171" }, links)
        end)

        it("is finished by the DataStore's own recipe scan", function()
            _G.C_TradeSkillUI.GetAllRecipeIDs = function() return { 100 } end
            _G.C_TradeSkillUI.GetRecipeInfo = function()
                return { name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 0 }
            end
            login()
            DS:ScanRecipes()
            assert.is_false(R.IsReading())
            local char = AltArmyTBC_Data.Characters.Realm["Player-1-ABC"]
            assert.truthy(char.Professions.Tailoring.Recipes[100])
        end)

        it("tries the profession's next spell when one gets no answer, and remembers the one that worked", function()
            login()
            reply("Tailoring")
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:1111:171", lastLink())
            advance(R.TIMEOUT)
            assert.are.equal(2, closes)
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2259:171", lastLink())
            reply("Alchemy")
            advance(R.GAP)
            assert.are.equal(3, #links)

            R.Queue("Alchemy")
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:2259:171", lastLink())
        end)

        it("gives up on a profession once every spell went unanswered", function()
            login()
            advance(R.TIMEOUT)
            assert.is_false(R.IsReading())
            advance(R.GAP)
            assert.are.equal("trade:Player-1-ABC:1111:171", lastLink())
            advance(R.TIMEOUT + R.GAP)
            assert.are.equal("trade:Player-1-ABC:2259:171", lastLink())
            advance(60)
            assert.are.equal(3, #links)
            assert.is_false(R.IsReading())
        end)
    end)

    describe("waiting its turn", function()
        local function blockedThenFreed(block, free)
            block()
            login()
            assert.are.equal(0, #links)
            advance(R.RETRY)
            assert.are.equal(0, #links)
            free()
            advance(R.RETRY)
            assert.are.equal(1, #links)
        end

        it("waits out combat", function()
            blockedThenFreed(function() combat = true end, function() combat = false end)
        end)

        it("waits while another panel is open", function()
            blockedThenFreed(function() panel = {} end, function() panel = nil end)
        end)

        it("waits while the player has a profession window open", function()
            blockedThenFreed(function() frame:Show() end, function() frame:Hide() end)
        end)

        it("waits while the player is typing", function()
            blockedThenFreed(function() chatActive = {} end, function() chatActive = nil end)
        end)

        it("waits until the client knows the player's GUID", function()
            local guid = _G.UnitGUID
            blockedThenFreed(function() _G.UnitGUID = function() return nil end end,
                function() _G.UnitGUID = guid end)
        end)

        it("stops for combat mid-read and tries again afterwards", function()
            login()
            frame:Show()
            combat = true
            R.OnEvent("PLAYER_REGEN_DISABLED")
            assert.is_false(R.IsReading())
            assert.are.equal(1, closes)
            assert.are.equal(1, frame.alpha)
            combat = false
            advance(R.RETRY)
            assert.are.same({ "trade:Player-1-ABC:3908:197", "trade:Player-1-ABC:3908:197" }, links)
        end)
    end)

    describe("staying out of sight", function()
        it("conceals the window that opens for a read, and restores it on close", function()
            login()
            frame:Show()
            assert.are.equal(0, frame.alpha)
            assert.is_true(frame.scale < 0.1)
            assert.is_false(frame.mouse)
            R.OnRecipesScanned("Tailoring")
            assert.is_false(frame.shown)
            assert.are.equal(1, frame.alpha)
            assert.are.equal(1, frame.scale)
            assert.is_true(frame.mouse)
        end)

        it("closes and restores the window after a read that got no answer", function()
            login()
            frame:Show()
            advance(R.TIMEOUT)
            assert.are.equal(1, closes)
            assert.is_false(frame.shown)
            assert.are.equal(1, frame.alpha)
        end)

        it("leaves a window the player opens alone", function()
            frame:Show()
            assert.are.equal(1, frame.alpha)
        end)
    end)

    describe("only stale professions", function()
        local function professions(entries)
            local char = DS._GetCurrentCharTable()
            char.Professions = entries
            return char
        end
        local recipes = { [100] = { color = 1 } }

        it("reads nothing at login when every profession has its recipes", function()
            professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Alchemy = { rank = 75, Recipes = recipes },
            })
            assert.are.equal(0, R.QueueAll())
            login()
            advance(60)
            assert.are.equal(0, #links)
        end)

        it("reads a profession marked stale, and only that one", function()
            local char = professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Alchemy = { rank = 75, Recipes = recipes },
            })
            char.professionsNeedingRecipeScan = { Alchemy = true }
            login()
            reply("Alchemy")
            advance(60)
            assert.are.same({ "trade:Player-1-ABC:1111:171" }, links)
        end)

        it("reads a profession with no recipes stored", function()
            professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Alchemy = { rank = 75, Recipes = {} },
            })
            login()
            reply("Alchemy")
            advance(60)
            assert.are.same({ "trade:Player-1-ABC:1111:171" }, links)
        end)

        it("reads stale professions in the game's order", function()
            login()
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)

        it("doesn't read a profession asked for by name unless it is stale", function()
            local char = professions({
                Tailoring = { rank = 150, Recipes = recipes },
                Alchemy = { rank = 75, Recipes = recipes },
            })
            assert.are.equal(0, R.Queue("Tailoring"))
            char.professionsNeedingRecipeScan = { Tailoring = true }
            assert.are.equal(1, R.Queue("Tailoring"))
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
        end)
    end)

    describe("after learning a recipe", function()
        it("reads that profession again", function()
            R.OnRecipeLearned("Alchemy")
            advance(R.LEARN_DELAY)
            assert.are.same({ "trade:Player-1-ABC:1111:171" }, links)
        end)

        it("reads every profession when it can't tell which", function()
            R.OnRecipeLearned(nil)
            advance(R.LEARN_DELAY)
            reply("Tailoring")
            advance(R.GAP)
            assert.are.equal(2, #links)
        end)

        it("doesn't read when the bundled recipe data stored the learned recipe", function()
            local savedRI = AltArmy.RecipeInfo
            AltArmy.RecipeInfo = {
                FindRecipeLearnInfo = function()
                    return { professionName = "Tailoring", recipeID = 200, resultItemID = 2996 }
                end,
                GetRecipe = function() return {} end,
                GetDifficulty = function() return "orange" end,
            }
            local char = DS._GetCurrentCharTable()
            char.Professions = { Tailoring = { rank = 150, maxRank = 225, Recipes = { [100] = { color = 1 } } } }
            DS:OnRecipeLearnDetected(200, nil)
            AltArmy.RecipeInfo = savedRI
            advance(60)
            assert.truthy(char.Professions.Tailoring.Recipes[200])
            assert.are.equal(0, #links)
        end)

        it("is told by the DataStore when a recipe is learned", function()
            local char = DS._GetCurrentCharTable()
            char.Professions = { Tailoring = { rank = 150, maxRank = 225, Recipes = {} } }
            DS:OnRecipeLearnDetected(nil, nil)
            advance(R.LEARN_DELAY)
            assert.are.equal(1, #links)
        end)
    end)

    describe("reading a guildmate", function()
        local results

        local function guildJob(overrides)
            local job = {
                guid = "Player-1-DEF", name = "Alice", skillLine = 197,
                onResult = function(outcome, result, elapsed)
                    results[#results + 1] = { outcome = outcome, result = result, elapsed = elapsed }
                end,
            }
            for k, v in pairs(overrides or {}) do job[k] = v end
            return job
        end

        --- The server's answer to a guild read: a linked window, filled, and the client's event for it.
        local function windowOpens(opts)
            opts = opts or {}
            _G.C_TradeSkillUI.IsTradeSkillLinked = function() return opts.linked ~= false, opts.name end
            _G.C_TradeSkillUI.GetBaseProfessionInfo = function()
                return {
                    professionName = opts.profession or "Tailoring",
                    skillLevel = opts.rank or 142,
                    maxSkillLevel = opts.maxRank or 225,
                }
            end
            _G.C_TradeSkillUI.GetAllRecipeIDs = function() return opts.ids or { 300, 100, 200 } end
            _G.C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = id ~= 200 } end
            frame:Show()
            if not opts.noEvent then R.OnEvent("TRADE_SKILL_DATA_SOURCE_CHANGED") end
        end

        before_each(function()
            results = {}
        end)

        it("builds the link with the profession's Apprentice spell", function()
            assert.is_true(R.Enqueue(guildJob()))
            assert.are.same({ "trade:Player-1-DEF:3908:197" }, links)
            assert.is_true(R.IsReadingGuild())
            assert.is_false(R.IsReading())
            assert.is_true(R.IsQueued(R.JobTag("Player-1-DEF", 197)))
        end)

        it("refuses a job it can't build a link for, a malformed one, and a duplicate", function()
            assert.is_false(R.Enqueue(guildJob({ skillLine = 356 })))
            assert.is_false(R.Enqueue(guildJob({ guid = "" })))
            assert.is_true(R.Enqueue(guildJob()))
            assert.is_false(R.Enqueue(guildJob()))
            assert.are.equal(1, #links)
        end)

        it("does nothing when reads are turned off", function()
            R.SetEnabled(false)
            assert.is_false(R.Enqueue(guildJob()))
            assert.are.equal(0, #links)
        end)

        it("reads the player's own professions before guildmates'", function()
            DS._GetCurrentCharTable().Professions = { Alchemy = { rank = 75, Recipes = { [100] = { color = 1 } } } }
            combat = true
            assert.is_true(R.Enqueue(guildJob()))
            assert.are.equal(1, R.QueueAll())
            combat = false
            advance(R.RETRY)
            assert.are.same({ "trade:Player-1-ABC:3908:197" }, links)
            reply("Tailoring")
            advance(R.GAP)
            assert.are.equal("trade:Player-1-DEF:3908:197", lastLink())
        end)

        it("delivers the linked window's learned recipes and skill, then closes it", function()
            R.Enqueue(guildJob())
            advance(1)
            windowOpens({ name = "Alice" })
            assert.are.equal(1, #results)
            assert.are.equal("ok", results[1].outcome)
            local r = results[1].result
            assert.are.same({ 100, 300 }, r.ids)
            assert.are.equal(142, r.rank)
            assert.are.equal(225, r.maxRank)
            assert.are.equal("tailoring", r.key)
            assert.are.equal("Tailoring", r.professionName)
            assert.are.equal("Player-1-DEF", r.guid)
            assert.are.equal("Alice", r.name)
            assert.are.equal(1, results[1].elapsed)
            assert.are.equal(1, closes)
            assert.is_false(frame.shown)
            assert.is_false(R.IsReadingGuild())
        end)

        it("scans the window a moment after TRADE_SKILL_SHOW", function()
            R.Enqueue(guildJob())
            windowOpens({ name = "Alice", noEvent = true })
            R.OnEvent("TRADE_SKILL_SHOW")
            assert.are.equal(0, #results)
            advance(R.SHOW_SCAN_DELAY)
            assert.are.equal("ok", results[1].outcome)
        end)

        it("waits for the window to fill", function()
            R.Enqueue(guildJob())
            windowOpens({ name = "Alice", ids = {} })
            assert.are.equal(0, #results)
            windowOpens({ name = "Alice" })
            assert.are.equal("ok", results[1].outcome)
        end)

        it("matches the linked name whatever realm suffix or surname it carries", function()
            assert.is_true(R._NamesMatch("alice-Realm", "Alice"))
            assert.is_true(R._NamesMatch("Alice Smith", "Alice"))
            assert.is_true(R._NamesMatch("Alice", "Alice Smith-Realm"))
            assert.is_false(R._NamesMatch("Bob", "Alice"))
            assert.is_false(R._NamesMatch("", "Alice"))
            assert.is_false(R._NamesMatch(nil, "Alice"))
        end)

        it("ends with 'wrong name' when the window is someone else's", function()
            R.Enqueue(guildJob())
            windowOpens({ name = "Bob" })
            assert.are.equal("wrong name", results[1].outcome)
            assert.are.equal("Bob", results[1].result.linkedName)
            assert.are.equal(1, closes)
        end)

        it("ends with 'absent' for the empty window the server sends for a profession they haven't got", function()
            R.Enqueue(guildJob())
            windowOpens({ name = "Alice", rank = 0, maxRank = 0, ids = { 200 } })
            assert.are.equal("absent", results[1].outcome)
            assert.are.equal("tailoring", results[1].result.key)
            assert.are.equal(197, results[1].result.skillLine)
            assert.are.equal(1, closes)
        end)

        it("ends with 'wrong profession' when another profession opened", function()
            R.Enqueue(guildJob())
            windowOpens({ name = "Alice", profession = "Alchemy" })
            assert.are.equal("wrong profession", results[1].outcome)
        end)

        it("doesn't trust a linked window that names nobody, and says so at the timeout", function()
            R.Enqueue(guildJob())
            windowOpens({ name = nil })
            assert.are.equal(0, #results)
            advance(R.TIMEOUT)
            assert.are.equal("unnamed", results[1].outcome)
        end)

        it("doesn't trust a window that isn't linked", function()
            R.Enqueue(guildJob())
            windowOpens({ linked = false })
            assert.are.equal(0, #results)
            advance(R.TIMEOUT)
            assert.are.equal("timeout", results[1].outcome)
        end)

        it("trusts an unlinked or unnamed window of the right profession when names aren't required", function()
            R.REQUIRE_LINKED_NAME = false
            R.Enqueue(guildJob())
            windowOpens({ linked = false })
            assert.are.equal("ok", results[1].outcome)
            R.Enqueue(guildJob({ skillLine = 171 }))
            advance(R.GUILD_GAP)
            windowOpens({ name = nil, profession = "Alchemy" })
            assert.are.equal("ok", results[2].outcome)
            assert.are.equal("alchemy", results[2].result.key)
        end)

        it("reports a timeout and goes on to the next job after GUILD_GAP", function()
            R.Enqueue(guildJob())
            R.Enqueue(guildJob({ skillLine = 171 }))
            advance(R.TIMEOUT)
            assert.are.equal("timeout", results[1].outcome)
            assert.are.equal(1, closes)
            advance(R.GAP)
            assert.are.equal(1, #links)
            advance(R.GUILD_GAP - R.GAP)
            assert.are.equal("trade:Player-1-DEF:2259:171", lastLink())
        end)

        it("drops queued jobs on request, never the one being read", function()
            R.Enqueue(guildJob())
            R.Enqueue(guildJob({ skillLine = 171 }))
            R.Enqueue(guildJob({ guid = "Player-1-GHI", name = "Bob", skillLine = 171 }))
            assert.are.equal(1, R.CancelWhere(function(job) return job.guid == "Player-1-DEF" end))
            assert.is_true(R.IsReadingGuild())
            assert.is_false(R.IsQueued(R.JobTag("Player-1-DEF", 171)))
            assert.is_true(R.IsQueued(R.JobTag("Player-1-GHI", 171)))
        end)

        it("isn't finished by the DataStore's own scan", function()
            R.Enqueue(guildJob())
            R.OnRecipesScanned("Tailoring")
            assert.is_true(R.IsReadingGuild())
            assert.are.equal(0, #results)
        end)

        it("stops for combat and tries again afterwards", function()
            R.Enqueue(guildJob())
            combat = true
            R.OnEvent("PLAYER_REGEN_DISABLED")
            assert.is_false(R.IsReadingGuild())
            assert.are.equal(0, #results)
            combat = false
            advance(R.RETRY)
            assert.are.same({ "trade:Player-1-DEF:3908:197", "trade:Player-1-DEF:3908:197" }, links)
        end)

        it("names its Apprentice spells after RecipeInfo's professions", function()
            require("RecipeInfo")
            local RI = AltArmy.RecipeInfo
            assert.truthy(RI and RI.PROFESSION_SPELL_IDS)
            for key, skillLine in pairs(R.SKILL_LINE_BY_KEY) do
                assert.are.equal(RI.PROFESSION_SPELL_IDS[key], R.APPRENTICE_SPELLS[skillLine], key)
            end
        end)
    end)

    describe("keeping the window shut", function()
        local listeners, router, button, otherAddon, mine, store, results

        --- A frame listening for events; `onShow` is what it does on TRADE_SKILL_SHOW.
        local function listener(name, onShow, protected)
            local f = { name = name, events = { TRADE_SKILL_SHOW = true }, onShow = onShow }
            function f:RegisterEvent(e) self.events[e] = true end
            function f:UnregisterEvent(e) self.events[e] = nil end
            function f:IsProtected() return protected == true end
            listeners[#listeners + 1] = f
            return f
        end

        --- Make one of the module's own event frames (plain tables in this harness) a listener.
        local function adopt(f, name, onShow)
            f.name, f.events, f.onShow = name, { TRADE_SKILL_SHOW = true }, onShow
            f.RegisterEvent = function(self, e) self.events[e] = true end
            f.UnregisterEvent = function(self, e) self.events[e] = nil end
            listeners[#listeners + 1] = f
            return f
        end

        --- The client fires TRADE_SKILL_SHOW at whoever still listens for it.
        local function fireShow()
            for _, f in ipairs(listeners) do
                if f.events.TRADE_SKILL_SHOW and f.onShow then f.onShow() end
            end
        end

        local function listening(f) return f.events.TRADE_SKILL_SHOW == true end

        local function guildJob(guid)
            return {
                guid = guid or "Player-1-DEF", name = "Alice", skillLine = 197,
                onResult = function(outcome) results[#results + 1] = outcome end,
            }
        end

        --- What the client says about the window: linked or not, and under whose name.
        local function linkedTo(name)
            _G.C_TradeSkillUI.IsTradeSkillLinked = function() return name ~= nil, name end
        end

        before_each(function()
            listeners, results = {}, {}
            -- Blizzard's event routing opens the window; the others only listen.
            router = listener("EventRouting", function() frame:Show() end)
            button = listener("ActionButton1", nil, true)
            otherAddon = listener("SomeAddonFrame")
            mine = adopt(R._EventFrame(), "OwnRecipeRead", function() R.OnEvent("TRADE_SKILL_SHOW") end)
            store = adopt(DS.eventFrame, "DataStore")
            _G.GetFramesRegisteredForEvent = function(event)
                local found = {}
                for _, f in ipairs(listeners) do
                    if f.events[event] then found[#found + 1] = f end
                end
                return unpack(found)
            end
            _G.ShowUIPanel = function() error("the addon must never show Blizzard's window: it taints the cast bar") end
        end)

        after_each(function()
            _G.ShowUIPanel = nil
        end)

        it("takes TRADE_SKILL_SHOW from the window's openers while a read waits, so it never opens", function()
            login()
            assert.is_true(R.IsReading())
            assert.is_false(listening(router))
            assert.is_false(listening(otherAddon))
            assert.is_true(listening(mine))
            assert.is_true(listening(store))
            assert.is_true(listening(button)) -- protected: left alone
            fireShow()
            assert.is_false(frame.shown)
            R.OnRecipesScanned("Tailoring")
            assert.is_true(listening(router))
            assert.is_true(listening(otherAddon))
            assert.are.equal(0, R.QuietState().silenced)
        end)

        it("reads a guildmate's window without it ever showing", function()
            R.Enqueue(guildJob())
            linkedTo("Alice")
            _G.C_TradeSkillUI.GetBaseProfessionInfo = function()
                return { professionName = "Tailoring", skillLevel = 142, maxSkillLevel = 225 }
            end
            _G.C_TradeSkillUI.GetAllRecipeIDs = function() return { 100 } end
            _G.C_TradeSkillUI.GetRecipeInfo = function() return { learned = true } end
            fireShow()
            R.OnEvent("TRADE_SKILL_LIST_UPDATE")
            assert.are.same({ "ok" }, results)
            assert.is_false(frame.shown)
            assert.is_true(listening(router))
            assert.are.equal(1, R.QuietState().works)
        end)

        it("gives the event back when a read gets no answer, and on combat and logout", function()
            R.Enqueue(guildJob())
            advance(R.TIMEOUT)
            assert.is_true(listening(router))
            advance(R.GUILD_GAP)
            R.Enqueue(guildJob("Player-1-GHI"))
            assert.is_false(listening(router))
            R.OnEvent("PLAYER_REGEN_DISABLED")
            assert.is_true(listening(router))
            advance(R.RETRY)
            assert.is_false(listening(router))
            R.OnEvent("PLAYER_LOGOUT")
            assert.is_true(listening(router))
        end)

        it("gives silencing up after QUIET_GIVE_UP silenced reads that all went unanswered", function()
            for i = 1, R.QUIET_GIVE_UP do
                R.Enqueue(guildJob("Player-1-" .. i))
                advance(R.TIMEOUT + R.GUILD_GAP)
            end
            assert.is_true(R.QuietState().off)
            R.Enqueue(guildJob("Player-1-X"))
            assert.is_true(listening(router))
            linkedTo("Alice")
            fireShow()
            assert.is_true(frame.shown)
            assert.are.equal(0, frame.alpha) -- only concealed now
        end)

        it("keeps silencing once a silenced read was answered", function()
            login()
            R.OnRecipesScanned("Tailoring")
            for i = 1, R.QUIET_GIVE_UP do
                R.Enqueue(guildJob("Player-1-" .. i))
                advance(R.TIMEOUT + R.GUILD_GAP)
            end
            assert.is_false(R.QuietState().off)
        end)

        it("steps aside for a click on the interface, and reads again later", function()
            _G.GetMouseFoci = function() return { { name = "SomeButton" } } end
            login()
            R.OnEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
            assert.is_false(R.IsReading())
            assert.is_true(listening(router))
            assert.are.equal(1, closes)
            advance(R.RETRY)
            assert.are.same({ "trade:Player-1-ABC:3908:197", "trade:Player-1-ABC:3908:197" }, links)
        end)

        it("goes on reading through a click in the world", function()
            _G.GetMouseFoci = function() return { WorldFrame } end
            login()
            R.OnEvent("GLOBAL_MOUSE_DOWN", "RightButton")
            assert.is_true(R.IsReading())
            assert.is_false(listening(router))
        end)

        it("closes the trade skill the player opens mid-read, never showing the window itself", function()
            -- The silenced openers never heard of it; the addon showing it would taint the cast bar, so it
            -- is closed and the player's next click opens it with the openers listening again.
            R.Enqueue(guildJob())
            linkedTo(nil) -- the player's own profession: not linked
            fireShow()
            assert.is_false(R.IsReadingGuild())
            assert.is_true(listening(router))
            assert.are.equal(1, closes)
            advance(0)
            assert.is_false(frame.shown)
            assert.are.equal(1, frame.alpha)
            advance(R.RETRY)
            -- Reads again once the window is gone.
            assert.are.same({ "trade:Player-1-DEF:3908:197", "trade:Player-1-DEF:3908:197" }, links)
        end)

        it("steps aside when the player opens another profession during an own read", function()
            login()
            _G.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end
            fireShow()
            assert.is_false(R.IsReading())
            assert.is_true(listening(router))
            assert.are.equal(1, closes)
            advance(0)
            assert.is_false(frame.shown)
        end)

        it("takes the asked-for profession's window during an own read as its answer", function()
            login()
            fireShow()
            assert.is_true(R.IsReading())
            assert.is_false(frame.shown)
        end)

        it("closes, out of sight, a window that is a late answer to a read that timed out", function()
            R.Enqueue(guildJob())
            advance(R.TIMEOUT)
            assert.are.same({ "timeout" }, results)
            linkedTo("Alice")
            fireShow()
            assert.is_true(frame.shown)
            assert.are.equal(0, frame.alpha)
            advance(R.LATE_CLOSE)
            assert.is_false(frame.shown)
            assert.are.equal(1, frame.alpha)
        end)

        it("leaves alone a profession link the player clicked, and windows long after a read", function()
            R.Enqueue(guildJob())
            advance(R.TIMEOUT)
            R.OnLinkClicked("trade:Player-1-XYZ:3908:197")
            linkedTo("Bob")
            fireShow()
            assert.is_true(frame.shown)
            assert.are.equal(1, frame.alpha)
            frame:Hide()
            advance(R.LATE + 1)
            fireShow()
            assert.are.equal(1, frame.alpha)
        end)
    end)
end)
