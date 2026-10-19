--[[ Unit tests for CooldownData.lua — run: npm test ]]

describe("CooldownData", function()
    local CD

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua;AltArmy_TBC/Data/Characters/?.lua"
        require("ClassColor")
        require("CharKey")
        require("RealmFilter")
        require("CharacterSections")
        require("CharacterFilter")
        require("CooldownData")
        CD = AltArmy.CooldownData
        assert.truthy(CD)
    end)

    before_each(function()
        _G.AltArmyTBC_SummarySettings = nil
        CD.ResetCooldownOptionsToDefaults()
        -- Same structure as in-game: filled when tradeskill/craft APIs run (see DataStoreProfessions).
        _G.AltArmyTBC_Data.RecipeReagents = {
            [29688] = { { 22452, 1 }, { 21885, 1 }, { 21884, 1 }, { 22451, 1 } },
            [28028] = { { 22450, 2 } },
            [28027] = { { 22449, 4 } },
        }
    end)

    local function mockDS(realmTable)
        local ds = {
            GetRealms = function()
                return { TestRealm = true }
            end,
            GetCharacters = function(_self, realm)
                return realmTable[realm] or {}
            end,
            ForEachCharacter = function(self, fn)
                for realm in pairs(self:GetRealms()) do
                    for charName, charData in pairs(self:GetCharacters(realm)) do
                        if fn(realm, charName, charData) == true then
                            return
                        end
                    end
                end
            end,
        }
        return ds
    end

    it("BuildRows omits hidden categories", function()
        AltArmyTBC_Options.cooldowns.categories.spellcloth.showInUI = false
        local char = {
            name = "A",
            Professions = { Tailoring = { Recipes = { [31373] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { X = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "spellcloth" then found = true end
        end
        assert.is_false(found)
    end)

    it("BuildRows includes bank alts", function()
        CD.ResetCooldownOptionsToDefaults()
        require("CharKey")
        package.loaded["BankAlt"] = nil
        require("BankAlt")
        AltArmy.BankAlt.Set("Banker", "TestRealm", true)
        local char = {
            name = "Banker",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { Banker = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        assert.is_true(#rows >= 1)
        assert.are.equal("Banker", rows[1].name)
    end)

    it("BuildRows names rows by character name, not by the GUID storage key", function()
        CD.ResetCooldownOptionsToDefaults()
        local char = {
            name = "Frell Blast",
            guid = "Player-1-B",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { ["Player-1-B"] = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        assert.is_true(#rows >= 1)
        assert.are.equal("Frell Blast", rows[1].name)
        -- Also the stockpile mail recipient, so it must be the name.
        assert.are.equal("Frell Blast", rows[1].charKeyName)
    end)

    it("BuildRows includes transmute when recipe in set", function()
        local char = {
            name = "T",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        assert.is_true(#rows >= 1)
        assert.are.equal("transmute", rows[1].categoryKey)
    end)

    it("ResolveEffectiveSpellId for transmute picks primal might over arcanite when no last cast", function()
        local char = {
            Professions = {
                Alchemy = { Recipes = { [29688] = { color = 1 }, [17187] = { color = 1 } } },
            },
        }
        local sid = CD.ResolveEffectiveSpellId("transmute", char, AltArmyTBC_Options.cooldowns)
        assert.are.equal(29688, sid)
    end)

    it("ResolveTransmuteSpellForCharacter uses automatic primal then arcanite order", function()
        local primalOnly = {
            Professions = { Alchemy = { Recipes = { [29688] = {} } } },
        }
        assert.are.equal(29688, CD.ResolveTransmuteSpellForCharacter(primalOnly))

        local arcaniteOnly = {
            Professions = { Alchemy = { Recipes = { [17187] = {} } } },
        }
        assert.are.equal(17187, CD.ResolveTransmuteSpellForCharacter(arcaniteOnly))

        local neither = {
            Professions = { Alchemy = { Recipes = { [28566] = {} } } },
        }
        assert.is_nil(CD.ResolveTransmuteSpellForCharacter(neither))
    end)

    it("ResolveTransmuteSpellForCharacter prefers last cast before primal fallback", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {} } } },
        }
        assert.are.equal(28566, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("ResolveTransmuteSpellForCharacter skips unknown last cast", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            Professions = { Alchemy = { Recipes = { [29688] = {} } } },
        }
        assert.are.equal(29688, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("RecordSuccessfulTransmuteCast saves known transmute spell ids", function()
        local char = {}
        CD.RecordSuccessfulTransmuteCast(char, 29688)
        assert.are.equal(29688, char.lastTransmute and char.lastTransmute.spellId)
    end)

    it("RecordSuccessfulTransmuteCast ignores non-transmute spells", function()
        local char = {}
        CD.RecordSuccessfulTransmuteCast(char, 999999)
        assert.is_nil(char.lastTransmute)
    end)

    it("GetTransmuteExpiryUnix uses max expiry across transmute spell ids", function()
        local char = {
            ProfCooldownExpiry = {
                [29688] = { expiresAtUnix = 500 },
                [28566] = { expiresAtUnix = 900 },
            },
        }
        assert.are.equal(900, CD.GetTransmuteExpiryUnix(char))
        assert.is_nil(CD.GetTransmuteExpiryUnix({}))
    end)

    it("FormatTimeRemaining shows Unscanned when remaining exceeds max profession CD", function()
        local now = 1000
        local expires = now + CD.MAX_PROF_COOLDOWN_SECONDS + 1
        assert.are.equal("Unscanned", CD.FormatTimeRemaining(expires, now))
    end)

    it("FormatTimeRemaining shows time when remaining is within max profession CD", function()
        local now = 1000
        local expires = now + CD.MAX_PROF_COOLDOWN_SECONDS
        assert.are_not.equal("Unscanned", CD.FormatTimeRemaining(expires, now))
        assert.are_not.equal("Ready", CD.FormatTimeRemaining(expires, now))
    end)

    it("BuildRows treats over-cap expiry as unscanned", function()
        local now = 1000
        local char = {
            name = "Tailor",
            Professions = { Tailoring = { Recipes = { [36686] = { color = 1 } } } },
            ProfCooldownExpiry = {
                [36686] = { expiresAtUnix = now + CD.MAX_PROF_COOLDOWN_SECONDS + 999999 },
            },
        }
        local ds = mockDS({ TestRealm = { T = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, now)
        local shadowRow
        for _, r in ipairs(rows) do
            if r.categoryKey == "shadowcloth" and r.name == "Tailor" then
                shadowRow = r
                break
            end
        end
        assert.is_not_nil(shadowRow)
        assert.is_nil(shadowRow.expiresUnix)
        assert.are.equal("Unscanned", shadowRow.timeText)
    end)

    it("BuildRows transmute time uses shared expiry when only another transmute id was scanned", function()
        local char = {
            name = "T",
            lastTransmute = { spellId = 28566 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {} } } },
            ProfCooldownExpiry = { [29688] = { expiresAtUnix = 5000 } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        local transmuteRow
        for _, r in ipairs(rows) do
            if r.categoryKey == "transmute" and r.name == "T" then
                transmuteRow = r
                break
            end
        end
        assert.is_not_nil(transmuteRow)
        assert.are.equal(28566, transmuteRow.spellId)
        assert.are.equal(5000, transmuteRow.expiresUnix)
        assert.are_not.equal("Unscanned", transmuteRow.timeText)
    end)

    it("TransmuteCategoryDisplayTitle takes text after Transmute colon", function()
        local function gsi()
            return "Alchemy: Transmute: Primal Might"
        end
        assert.are.equal("Primal Might", CD.TransmuteCategoryDisplayTitle(29688, gsi))
        assert.are.equal(
            "Primal Earth to Water",
            CD.TransmuteCategoryDisplayTitle(1, function()
                return "Transmute: Primal Earth to Water"
            end)
        )
    end)

    it("BuildRows sets transmute categoryTitle from spell name", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 29688 then
                return "Transmute: Primal Might"
            end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "T",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        assert.is_true(#rows >= 1)
        assert.are.equal("Primal Might", rows[1].categoryTitle)
    end)

    it("BuildRows omits transmute when automatic and neither Primal Might nor Arcanite known", function()
        local char = {
            name = "NoMeta",
            Professions = { Alchemy = { Recipes = { [28566] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        for _, r in ipairs(rows) do
            assert.are_not.equal("transmute", r.categoryKey)
        end
    end)

    it("CharacterHasReagents respects counts for sphere recipes", function()
        local char = {}
        assert.is_true(CD.CharacterHasReagents(char, 28028, function(_ch, itemId)
            return itemId == 22450 and 2 or 0
        end))
        assert.is_true(CD.CharacterHasReagents(char, 28027, function(_ch, itemId)
            return itemId == 22449 and 4 or 0
        end))
    end)

    it("EnsureCooldownOptions sets list sort key and ascending flag", function()
        CD.EnsureCooldownOptions()
        assert.are.equal("recipe", AltArmyTBC_Options.cooldowns.listSortKey)
        assert.is_true(AltArmyTBC_Options.cooldowns.listSortAscending)
        AltArmyTBC_Options.cooldowns.listSortKey = "invalid"
        CD.EnsureCooldownOptions()
        assert.are.equal("recipe", AltArmyTBC_Options.cooldowns.listSortKey)
    end)

    it("GetMaxCraftableQuantity is minimum over reagents", function()
        local char = {}
        local counts = {
            [22452] = 7,
            [21885] = 99,
            [21884] = 99,
            [22451] = 99,
        }
        local function count(_ch, itemId)
            return counts[itemId] or 0
        end
        local q = CD.GetMaxCraftableQuantity(char, 29688, count)
        assert.are.equal(7, q)
    end)

    it("GetMaxCraftableQuantity can reflect merged totals via callback (containers+mail)", function()
        local char = {}
        local containerCounts = { [22452] = 1, [21885] = 0, [21884] = 0, [22451] = 0 }
        local mailCounts = { [22452] = 4, [21885] = 5, [21884] = 5, [22451] = 5 }
        local function merged(_ch, itemId)
            return (containerCounts[itemId] or 0) + (mailCounts[itemId] or 0)
        end
        local q = CD.GetMaxCraftableQuantity(char, 29688, merged)
        assert.are.equal(5, q) -- reagent 22452 becomes limiting at 1+4
    end)

    it("GetMaxCraftableQuantityAfterTransfer sums source+target then takes minimum", function()
        local target, source = {}, {}
        local targetCounts = { [22452] = 1, [21885] = 0, [21884] = 0, [22451] = 0 }
        local sourceCounts = { [22452] = 2, [21885] = 5, [21884] = 5, [22451] = 5 }
        local function getTarget(_ch, itemId)
            return targetCounts[itemId] or 0
        end
        local function getSource(_ch, itemId)
            return sourceCounts[itemId] or 0
        end
        -- For spell 29688 all needs are 1; min across reagents will be 3 for item 22452.
        local q = CD.GetMaxCraftableQuantityAfterTransfer(target, source, 29688, getTarget, getSource)
        assert.are.equal(3, q)
    end)

    it("GetReagentSendPlan computes per-item requiredToSend for requested crafts", function()
        local target, source = {}, {}
        local targetCounts = { [22452] = 1, [21885] = 10, [21884] = 0, [22451] = 0 }
        local sourceCounts = { [22452] = 99, [21885] = 0, [21884] = 99, [22451] = 99 }
        local function getTarget(_ch, itemId)
            return targetCounts[itemId] or 0
        end
        local function getSource(_ch, itemId)
            return sourceCounts[itemId] or 0
        end
        local rows = CD.GetReagentSendPlan(target, source, 29688, 3, getTarget, getSource)
        assert.truthy(rows)
        local byId = {}
        for _, r in ipairs(rows) do
            byId[r.itemID] = r
        end
        assert.are.equal(2, byId[22452].requiredToSend) -- 3*1 - 1
        assert.are.equal(0, byId[21885].requiredToSend) -- already enough
        assert.are.equal(3, byId[21884].requiredToSend)
        assert.are.equal(3, byId[22451].requiredToSend)
    end)

    it("EvaluateAlerts includes classFile from character in alert rows", function()
        local char = {
            name = "Z",
            classFile = "MAGE",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
            ProfCooldownExpiry = { [29688] = { expiresAtUnix = 500 } },
        }
        local ds = mockDS({ TestRealm = { Z = char } })
        local state = {}
        local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, state)
        assert.are.equal(1, #alerts)
        assert.are.equal("MAGE", alerts[1].classFile)
    end)

    it("EvaluateAlerts fires available once until cooldown resumes", function()
        local char = {
            name = "Z",
            Professions = { Alchemy = { Recipes = { [29688] = { color = 1 } } } },
            ProfCooldownExpiry = { [29688] = { expiresAtUnix = 500 } },
        }
        local ds = mockDS({ TestRealm = { Z = char } })
        local state = {}
        local a1 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, state)
        assert.are.equal(1, #a1)
        local a2 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 601, state)
        assert.are.equal(0, #a2)
        char.ProfCooldownExpiry[29688] = { expiresAtUnix = 700 }
        local a3 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 650, state)
        assert.are.equal(0, #a3)
        local a4 = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 750, state)
        assert.are.equal(1, #a4)
    end)

    it("GetAllTrackedSpellIds includes meta gem and legacy transmutes", function()
        local _, seen = CD.GetAllTrackedSpellIds()
        assert.is_true(seen[11480])
        assert.is_true(seen[32765])
        assert.is_true(seen[32766])
    end)

    it("IsTrackedSpellId recognizes void and prismatic sphere spell ids", function()
        assert.is_true(CD.IsTrackedSpellId(28028))
        assert.is_true(CD.IsTrackedSpellId(28027))
        assert.is_false(CD.IsTrackedSpellId(45765))
        assert.is_false(CD.IsTrackedSpellId(33358))
    end)

    it("ResolveSphereSpellForCharacter prefers void sphere then prismatic sphere", function()
        local voidOnly = {
            Professions = { Enchanting = { Recipes = { [28028] = {} } } },
        }
        assert.are.equal(28028, CD.ResolveSphereSpellForCharacter(voidOnly))

        local prismaticOnly = {
            Professions = { Enchanting = { Recipes = { [28027] = {} } } },
        }
        assert.are.equal(28027, CD.ResolveSphereSpellForCharacter(prismaticOnly))

        local both = {
            Professions = { Enchanting = { Recipes = { [28028] = {}, [28027] = {} } } },
        }
        assert.are.equal(28028, CD.ResolveSphereSpellForCharacter(both))
    end)

    it("ResolveSphereSpellForCharacter prefers last cast before automatic fallback", function()
        local char = {
            lastSphere = { spellId = 28027 },
            Professions = { Enchanting = { Recipes = { [28028] = {}, [28027] = {} } } },
        }
        assert.are.equal(28027, CD.ResolveSphereSpellForCharacter(char))
    end)

    it("GetKnownGroupSpellIds returns known group recipes in category order", function()
        local char = {
            Professions = {
                Alchemy = { Recipes = { [17187] = {}, [28566] = {}, [29688] = {} } },
                Enchanting = { Recipes = { [28027] = {} } },
            },
        }
        assert.are.same({ 28566, 29688, 17187 }, CD.GetKnownGroupSpellIds(char, "transmute"))
        assert.are.same({ 28027 }, CD.GetKnownGroupSpellIds(char, "void_sphere"))
        assert.are.same({}, CD.GetKnownGroupSpellIds(char, "spellcloth"))
        assert.are.same({}, CD.GetKnownGroupSpellIds(nil, "transmute"))
    end)

    it("GetGroupRecipeChoice is auto when absent or invalid", function()
        local char = {
            Professions = { Alchemy = { Recipes = { [29688] = {}, [17187] = {} } } },
        }
        assert.are.equal("auto", CD.GetGroupRecipeChoice(char, "transmute"))
        char.cooldownGroupChoice = { transmute = 17187 }
        assert.are.equal(17187, CD.GetGroupRecipeChoice(char, "transmute"))
        char.cooldownGroupChoice.transmute = 28566
        assert.are.equal("auto", CD.GetGroupRecipeChoice(char, "transmute"))
        assert.are.equal("auto", CD.GetGroupRecipeChoice(char, "spellcloth"))
    end)

    it("SetGroupRecipeChoice stores known group spells and clears on auto", function()
        local char = {
            Professions = { Alchemy = { Recipes = { [29688] = {}, [17187] = {} } } },
        }
        CD.SetGroupRecipeChoice(char, "transmute", 17187)
        assert.are.equal(17187, char.cooldownGroupChoice and char.cooldownGroupChoice.transmute)
        CD.SetGroupRecipeChoice(char, "transmute", "auto")
        assert.is_nil(char.cooldownGroupChoice and char.cooldownGroupChoice.transmute)
        CD.SetGroupRecipeChoice(char, "transmute", 28566)
        assert.is_nil(char.cooldownGroupChoice and char.cooldownGroupChoice.transmute)
        CD.SetGroupRecipeChoice(char, "spellcloth", 31373)
        assert.is_nil(char.cooldownGroupChoice and char.cooldownGroupChoice.spellcloth)
    end)

    it("ListGroupRecipeChoiceEntries starts with Auto and lists only known recipes", function()
        local char = {
            Professions = {
                Alchemy = { Recipes = { [29688] = {}, [17187] = {} } },
                Enchanting = { Recipes = { [28028] = {} } },
            },
        }
        local transmute = CD.ListGroupRecipeChoiceEntries(char, "transmute", function(spellId)
            if spellId == 29688 then return "Transmute: Primal Might" end
            if spellId == 17187 then return "Transmute: Arcanite" end
            return "Spell " .. tostring(spellId)
        end)
        assert.are.equal(3, #transmute)
        assert.are.equal("auto", transmute[1].id)
        assert.are.equal("Auto", transmute[1].label)
        assert.are.equal(29688, transmute[1].spellId)
        assert.are.equal("Primal Might", transmute[1].autoLabel)
        assert.are.equal(17187, transmute[2].id)
        assert.are.equal("Arcanite", transmute[2].label)
        assert.are.equal(17187, transmute[2].spellId)
        assert.are.equal(29688, transmute[3].id)
        assert.are.equal("Primal Might", transmute[3].label)
        assert.are.equal(29688, transmute[3].spellId)

        local spheres = CD.ListGroupRecipeChoiceEntries(char, "void_sphere", function(spellId)
            if spellId == 28028 then return "Void Sphere" end
            return "Spell " .. tostring(spellId)
        end)
        assert.are.equal(2, #spheres)
        assert.are.equal("auto", spheres[1].id)
        assert.are.equal(28028, spheres[1].spellId)
        assert.are.equal("Void Sphere", spheres[1].autoLabel)
        assert.are.equal(28028, spheres[2].id)
        assert.are.equal("Void Sphere", spheres[2].label)
    end)

    it("ListGroupRecipeChoiceEntries filters by query after Auto", function()
        local char = {
            Professions = { Alchemy = { Recipes = { [29688] = {}, [17187] = {} } } },
        }
        local gsi = function(spellId)
            if spellId == 29688 then return "Transmute: Primal Might" end
            if spellId == 17187 then return "Transmute: Arcanite" end
            return "Spell " .. tostring(spellId)
        end
        local arc = CD.ListGroupRecipeChoiceEntries(char, "transmute", gsi, "arc")
        assert.are.equal(1, #arc)
        assert.are.equal(17187, arc[1].id)

        local autoQ = CD.ListGroupRecipeChoiceEntries(char, "transmute", gsi, "auto")
        assert.are.equal(1, #autoQ)
        assert.are.equal("auto", autoQ[1].id)

        local primalAuto = CD.ListGroupRecipeChoiceEntries(char, "transmute", gsi, "primal")
        assert.are.equal(2, #primalAuto)
        assert.are.equal("auto", primalAuto[1].id)
        assert.are.equal(29688, primalAuto[2].id)
    end)

    it("FormatGroupRecipeChoiceDisplayLabel formats Auto and recipe text", function()
        assert.are.equal("Auto", CD.FormatGroupRecipeChoiceDisplayLabel(nil))
        assert.are.equal("Auto", CD.FormatGroupRecipeChoiceDisplayLabel({ id = "auto" }))
        assert.are.equal(
            "Auto |cffaaaaaa(Primal Might)|r",
            CD.FormatGroupRecipeChoiceDisplayLabel({ id = "auto", autoLabel = "Primal Might" })
        )
        assert.are.equal("Arcanite", CD.FormatGroupRecipeChoiceDisplayLabel({ id = 17187, label = "Arcanite" }))
    end)

    it("FormatGroupRecipeChoiceDisplayLabel highlights query matches via highlightFn", function()
        local function hl(text, query, formatSegment)
            if query and query ~= "" and (text or ""):lower():find(query, 1, true) then
                return "<" .. text .. ">"
            end
            if formatSegment then
                return formatSegment(text)
            end
            return text
        end
        assert.are.equal(
            "<Auto> |cffaaaaaa(|r|cffaaaaaaPrimal Might|r|cffaaaaaa)|r",
            CD.FormatGroupRecipeChoiceDisplayLabel({ id = "auto", autoLabel = "Primal Might" }, "auto", hl)
        )
        assert.are.equal(
            "Auto |cffaaaaaa(|r<Primal Might>|cffaaaaaa)|r",
            CD.FormatGroupRecipeChoiceDisplayLabel({ id = "auto", autoLabel = "Primal Might" }, "primal", hl)
        )
        assert.are.equal(
            "<Arcanite>",
            CD.FormatGroupRecipeChoiceDisplayLabel({ id = 17187, label = "Arcanite" }, "arc", hl)
        )
    end)

    it("ListGroupRecipeChoiceEntries Auto label uses last-cast Auto resolve not override", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            cooldownGroupChoice = { transmute = 17187 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {}, [17187] = {} } } },
        }
        local entries = CD.ListGroupRecipeChoiceEntries(char, "transmute", function(spellId)
            if spellId == 28566 then return "Transmute: Earthstorm Diamond" end
            if spellId == 29688 then return "Transmute: Primal Might" end
            if spellId == 17187 then return "Transmute: Arcanite" end
            return "Spell " .. tostring(spellId)
        end)
        assert.are.equal("auto", entries[1].id)
        assert.are.equal(28566, entries[1].spellId)
        assert.are.equal("Earthstorm Diamond", entries[1].autoLabel)
    end)

    it("ResolveTransmuteSpellForCharacter uses known override before last cast", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            cooldownGroupChoice = { transmute = 17187 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {}, [17187] = {} } } },
        }
        assert.are.equal(17187, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("ResolveTransmuteSpellForCharacter ignores unknown override and uses Auto", function()
        local char = {
            lastTransmute = { spellId = 28566 },
            cooldownGroupChoice = { transmute = 32765 },
            Professions = { Alchemy = { Recipes = { [28566] = {}, [29688] = {} } } },
        }
        assert.are.equal(28566, CD.ResolveTransmuteSpellForCharacter(char))
    end)

    it("ResolveSphereSpellForCharacter uses known override before last cast", function()
        local char = {
            lastSphere = { spellId = 28028 },
            cooldownGroupChoice = { void_sphere = 28027 },
            Professions = { Enchanting = { Recipes = { [28028] = {}, [28027] = {} } } },
        }
        assert.are.equal(28027, CD.ResolveSphereSpellForCharacter(char))
    end)

    it("BuildRows uses cooldownGroupChoice for transmute spell and title", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 17187 then return "Transmute: Arcanite" end
            if spellId == 29688 then return "Transmute: Primal Might" end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "T",
            cooldownGroupChoice = { transmute = 17187 },
            Professions = { Alchemy = { Recipes = { [29688] = {}, [17187] = {} } } },
        }
        local ds = mockDS({ TestRealm = { P = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        local transmuteRow
        for _, r in ipairs(rows) do
            if r.categoryKey == "transmute" and r.name == "T" then
                transmuteRow = r
                break
            end
        end
        assert.is_not_nil(transmuteRow)
        assert.are.equal(17187, transmuteRow.spellId)
        assert.are.equal("Arcanite", transmuteRow.categoryTitle)
    end)

    it("GetSphereExpiryUnix uses max expiry across sphere spell ids", function()
        local char = {
            ProfCooldownExpiry = {
                [28028] = { expiresAtUnix = 500 },
                [28027] = { expiresAtUnix = 900 },
            },
        }
        assert.are.equal(900, CD.GetSphereExpiryUnix(char))
        assert.is_nil(CD.GetSphereExpiryUnix({}))
    end)

    it("RecordSuccessfulSphereCast saves known sphere spell ids", function()
        local char = {}
        CD.RecordSuccessfulSphereCast(char, 28027)
        assert.are.equal(28027, char.lastSphere and char.lastSphere.spellId)
    end)

    it("RecordSuccessfulSphereCast ignores non-sphere spells", function()
        local char = {}
        CD.RecordSuccessfulSphereCast(char, 999999)
        assert.is_nil(char.lastSphere)
    end)

    it("BuildRows includes void sphere group when either enchanting recipe known", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 28027 then return "Prismatic Sphere" end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "Enchanter",
            Professions = { Enchanting = { Recipes = { [28027] = { color = 1 } } } },
            ProfCooldownExpiry = { [28027] = { expiresAtUnix = 5000 } },
        }
        local ds = mockDS({ TestRealm = { E = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "void_sphere" and r.name == "Enchanter" then
                found = true
                assert.are.equal(28027, r.spellId)
                assert.are.equal(5000, r.expiresUnix)
                assert.are.equal("Prismatic Sphere", r.categoryTitle)
            end
        end
        assert.is_true(found)
    end)

    it("BuildRows sphere time uses shared expiry when only the other sphere id was scanned", function()
        local oldGi = _G.GetSpellInfo
        _G.GetSpellInfo = function(spellId)
            if spellId == 28028 then return "Void Sphere" end
            return oldGi and oldGi(spellId)
        end
        local char = {
            name = "Enchanter",
            lastSphere = { spellId = 28028 },
            Professions = { Enchanting = { Recipes = { [28028] = {}, [28027] = {} } } },
            ProfCooldownExpiry = { [28027] = { expiresAtUnix = 5000 } },
        }
        local ds = mockDS({ TestRealm = { E = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        _G.GetSpellInfo = oldGi
        local sphereRow
        for _, r in ipairs(rows) do
            if r.categoryKey == "void_sphere" and r.name == "Enchanter" then
                sphereRow = r
                break
            end
        end
        assert.is_not_nil(sphereRow)
        assert.are.equal(28028, sphereRow.spellId)
        assert.are.equal(5000, sphereRow.expiresUnix)
        assert.are.equal("Void Sphere", sphereRow.categoryTitle)
    end)

    it("BuildRows omits void sphere when hidden in options", function()
        AltArmyTBC_Options.cooldowns.categories.void_sphere.showInUI = false
        local char = {
            name = "Enchanter",
            Professions = { Enchanting = { Recipes = { [28028] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { E = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        for _, r in ipairs(rows) do
            assert.are_not.equal("void_sphere", r.categoryKey)
        end
    end)

    it("CharacterHasReagents for void sphere requires two void crystals", function()
        local char = {}
        assert.is_true(CD.CharacterHasReagents(char, 28028, function(_ch, itemId)
            return itemId == 22450 and 2 or 0
        end))
        assert.is_false(CD.CharacterHasReagents(char, 28028, function(_ch, itemId)
            return itemId == 22450 and 1 or 0
        end))
    end)

    it("EnsureCooldownOptions creates void_sphere category defaults", function()
        CD.EnsureCooldownOptions()
        local c = AltArmyTBC_Options.cooldowns.categories.void_sphere
        assert.is_not_nil(c)
        assert.is_true(c.showInUI)
        assert.is_true(c.alertWhenAvailable)
        assert.is_false(c.showOnlyIfSpecialization)
        assert.is_false(c.alertOnlyIfSpecialization)
    end)

    it("CATEGORIES void_sphere uses combined options label", function()
        assert.are.equal("Void Sphere / Prismatic Sphere", CD.CATEGORIES.void_sphere.title)
        assert.are.equal("group", CD.CATEGORIES.void_sphere.mode)
    end)

    it("CATEGORY_ORDER places brilliant_glass before void_sphere", function()
        local brilliantIdx, voidSphereIdx = nil, nil
        for i, key in ipairs(CD.CATEGORY_ORDER) do
            if key == "brilliant_glass" then brilliantIdx = i end
            if key == "void_sphere" then voidSphereIdx = i end
        end
        assert.is_not_nil(brilliantIdx)
        assert.is_not_nil(voidSphereIdx)
        assert.is_true(brilliantIdx < voidSphereIdx)
        assert.is_nil(CD.CATEGORIES.void_shatter)
    end)

    it("BuildRows includes brilliant glass when Jewelcrafting recipe known", function()
        local char = {
            name = "Gems",
            Professions = { Jewelcrafting = { Recipes = { [47280] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { Gems = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "brilliant_glass" then
                found = true
                assert.are.equal(47280, r.spellId)
            end
        end
        assert.is_true(found)
    end)

    it("EnsureCooldownOptions sets specialization defaults and clears legacy alert options", function()
        AltArmyTBC_Options.cooldowns.categories.spellcloth.alertType = "raidWarning"
        AltArmyTBC_Options.cooldowns.categories.spellcloth.remindMe = true
        AltArmyTBC_Options.cooldowns.categories.spellcloth.remindEveryMinutes = 15
        CD.EnsureCooldownOptions()
        local c = AltArmyTBC_Options.cooldowns.categories.spellcloth
        assert.is_false(c.showOnlyIfSpecialization)
        assert.is_false(c.alertOnlyIfSpecialization)
        assert.is_nil(c.alertType)
        assert.is_nil(c.remindMe)
        assert.is_nil(c.remindEveryMinutes)
    end)

    it("BuildRows omits spellcloth when showOnlyIfSpecialization without persisted spec", function()
        AltArmyTBC_Options.cooldowns.categories.spellcloth.showOnlyIfSpecialization = true
        local char = {
            name = "Tailor",
            Professions = { Tailoring = { Recipes = { [31373] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { T = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        for _, r in ipairs(rows) do
            assert.are_not.equal("spellcloth", r.categoryKey)
        end
    end)

    it("BuildRows includes spellcloth when showOnlyIfSpecialization and spellfire tailor known", function()
        AltArmyTBC_Options.cooldowns.categories.spellcloth.showOnlyIfSpecialization = true
        local char = {
            name = "Tailor",
            cooldownSpecs = { spellfireTailor = true },
            Professions = { Tailoring = { Recipes = { [31373] = { color = 1 } } } },
        }
        local ds = mockDS({ TestRealm = { T = char } })
        local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
        local found = false
        for _, r in ipairs(rows) do
            if r.categoryKey == "spellcloth" then found = true end
        end
        assert.is_true(found)
    end)

    describe("Master of Transmutation gate", function()
        local savedDS
        before_each(function()
            savedDS = AltArmy.DataStore
            AltArmy.DataStore = { IsWowForever = false }
            AltArmyTBC_Options.cooldowns.categories.transmute.showOnlyIfSpecialization = true
            AltArmyTBC_Options.cooldowns.categories.transmute.alertOnlyIfSpecialization = true
        end)
        after_each(function()
            AltArmy.DataStore = savedDS
        end)

        local function alchemist()
            return {
                name = "Alch",
                -- Primal Might is TBC's; Arcanite is in WoW Forever's transmute group too
                Professions = { Alchemy = { Recipes = { [29688] = { color = 1 }, [17187] = { color = 1 } } } },
            }
        end

        local function hasTransmuteRow(rows)
            for _, r in ipairs(rows) do
                if r.categoryKey == "transmute" then return true end
            end
            return false
        end

        it("CategoryHasSpecialization: transmute on TBC, not on WoW Forever", function()
            assert.is_true(CD.CategoryHasSpecialization("transmute"))
            assert.is_false(CD.CategoryHasSpecialization("research"))
            AltArmy.DataStore.IsWowForever = true
            assert.is_false(CD.CategoryHasSpecialization("transmute"))
        end)

        it("TBC honors the saved setting (omits a non-master alchemist)", function()
            local ds = mockDS({ TestRealm = { A = alchemist() } })
            assert.is_false(hasTransmuteRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)))
            assert.is_false(CD.RowMeetsSpecializationGate("transmute", alchemist(), true))
        end)

        it("WoW Forever ignores the saved setting", function()
            AltArmy.DataStore.IsWowForever = true
            local ds = mockDS({ TestRealm = { A = alchemist() } })
            assert.is_true(hasTransmuteRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)))
            assert.is_true(CD.RowMeetsSpecializationGate("transmute", alchemist(), true))
        end)
    end)

    it("CollectAccountKnownTransmuteSpellIds dedupes", function()
        _G.AltArmyTBC_Data = {
            Characters = {
                R1 = {
                    A = { Professions = { Alchemy = { Recipes = { [29688] = {} } } } },
                },
                R2 = {
                    B = { Professions = { Alchemy = { Recipes = { [29688] = {} } } } },
                },
            },
        }
        local ids = CD.CollectAccountKnownTransmuteSpellIds(_G.AltArmyTBC_Data, nil)
        assert.are.equal(1, #ids)
        assert.are.equal(29688, ids[1])
    end)

    describe("EvaluateSendAllRow", function()
        local function eval(opts)
            return CD.EvaluateSendAllRow(
                opts.curName or "Me",
                opts.curRealm or "RealmA",
                opts.rowName or "Alt",
                opts.rowRealm or "RealmA",
                opts.n or 2,
                opts.minCrafts,
                opts.maxAfterTransfer
            )
        end

        it("skips current character", function()
            local r = eval({ rowName = "Me", minCrafts = 0, maxAfterTransfer = 5 })
            assert.are.equal("skip", r.action)
            assert.are.equal("self", r.reason)
        end)

        it("skips other realm", function()
            local r = eval({ rowRealm = "Other", minCrafts = 0, maxAfterTransfer = 5 })
            assert.are.equal("skip", r.action)
            assert.are.equal("realm", r.reason)
        end)

        it("skips when target already has N crafts", function()
            local r = eval({ n = 2, minCrafts = 2, maxAfterTransfer = 5 })
            assert.are.equal("skip", r.action)
            assert.are.equal("enough", r.reason)
        end)

        it("skips when target has more than N crafts", function()
            local r = eval({ n = 2, minCrafts = 3, maxAfterTransfer = 5 })
            assert.are.equal("skip", r.action)
            assert.are.equal("enough", r.reason)
        end)

        it("sends delta when min is below N and max allows N", function()
            local r = eval({ n = 2, minCrafts = 1, maxAfterTransfer = 5 })
            assert.are.equal("send", r.action)
            assert.are.equal(2, r.requestedCrafts)
        end)

        it("skips when reagents unknown", function()
            local r = eval({ n = 2, minCrafts = nil, maxAfterTransfer = nil })
            assert.are.equal("skip", r.action)
            assert.are.equal("unknown", r.reason)
        end)

        it("skips when cannot reach N after transfer", function()
            local r = eval({ n = 2, minCrafts = 0, maxAfterTransfer = 1 })
            assert.are.equal("skip", r.action)
            assert.are.equal("insufficient", r.reason)
        end)
    end)

    describe("AllocateSendAllCrafts", function()
        -- Void Sphere: 2x Void Crystal (22450) per craft
        local voidSphereReagents = function(targetHave)
            return { { itemID = 22450, need = 2, targetHave = targetHave or 0 } }
        end
        -- Prismatic Sphere: 4x Large Prismatic Shard (22449) per craft
        local prismaticReagents = function(targetHave)
            return { { itemID = 22449, need = 4, targetHave = targetHave or 0 } }
        end

        it("fills two alts from a shared pool with partial shortfall on the second", function()
            -- Source has 6 void crystals → 3 crafts worth. N=2.
            -- Alt1 at 0 → gets 2 crafts (uses 4). Alt2 at 0 → gets 1 craft (uses 2).
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 6 }, {
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
            })
            assert.are.equal(2, result.rows[1].willHave)
            assert.are.equal(2, result.rows[1].delta)
            assert.is_false(result.rows[1].shortfall)
            assert.are.equal(1, result.rows[2].willHave)
            assert.are.equal(1, result.rows[2].delta)
            assert.is_true(result.rows[2].shortfall)
            assert.is_true(result.anyShortfall)
        end)

        it("does not consume pool for unselected rows", function()
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 4 }, {
                { selected = false, minCrafts = 0, reagents = voidSphereReagents(0) },
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
            })
            assert.are.equal(0, result.rows[1].willHave)
            assert.are.equal(0, result.rows[1].delta)
            assert.are.equal(2, result.rows[2].willHave)
            assert.are.equal(2, result.rows[2].delta)
            assert.is_false(result.anyShortfall)
        end)

        it("skips self and realm without consuming", function()
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 4 }, {
                { selected = true, skip = "self", minCrafts = 0, reagents = voidSphereReagents(0) },
                { selected = true, skip = "realm", minCrafts = 0, reagents = voidSphereReagents(0) },
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
            })
            assert.are.equal(0, result.rows[1].delta)
            assert.are.equal(0, result.rows[2].delta)
            assert.are.equal(2, result.rows[3].willHave)
            assert.are.equal(2, result.rows[3].delta)
        end)

        it("skips rows that already have enough crafts", function()
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 4 }, {
                { selected = true, minCrafts = 2, reagents = voidSphereReagents(4) },
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
            })
            assert.are.equal(2, result.rows[1].willHave)
            assert.are.equal(0, result.rows[1].delta)
            assert.is_false(result.rows[1].shortfall)
            assert.are.equal(2, result.rows[2].willHave)
            assert.are.equal(2, result.rows[2].delta)
        end)

        it("accounts for target already having some reagents", function()
            -- Target has 2 crystals (1 craft). Need N=2 → send 2 more. Source has 2.
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 2 }, {
                { selected = true, minCrafts = 1, reagents = voidSphereReagents(2) },
            })
            assert.are.equal(2, result.rows[1].willHave)
            assert.are.equal(1, result.rows[1].delta)
            assert.is_false(result.anyShortfall)
        end)

        it("handles different recipes without cross-consuming wrong mats", function()
            local result = CD.AllocateSendAllCrafts(1, { [22450] = 2, [22449] = 4 }, {
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
                { selected = true, minCrafts = 0, reagents = prismaticReagents(0) },
            })
            assert.are.equal(1, result.rows[1].willHave)
            assert.are.equal(1, result.rows[1].delta)
            assert.are.equal(1, result.rows[2].willHave)
            assert.are.equal(1, result.rows[2].delta)
            assert.is_false(result.anyShortfall)
        end)

        it("marks unknown reagents as no-op with shortfall for selected", function()
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 10 }, {
                { selected = true, minCrafts = nil, reagents = nil },
            })
            assert.are.equal(0, result.rows[1].willHave)
            assert.are.equal(0, result.rows[1].delta)
            assert.is_true(result.rows[1].shortfall)
            assert.is_true(result.anyShortfall)
        end)

        it("returns zero delta when source cannot increase crafts at all", function()
            local result = CD.AllocateSendAllCrafts(2, { [22450] = 0 }, {
                { selected = true, minCrafts = 0, reagents = voidSphereReagents(0) },
            })
            assert.are.equal(0, result.rows[1].willHave)
            assert.are.equal(0, result.rows[1].delta)
            assert.is_true(result.rows[1].shortfall)
        end)
    end)

    describe("GetOptionsCategoryOrder", function()
        it("returns TBC's crafts A to Z on TBC, without WoW Forever's Study and Dedicated Study", function()
            assert.are.same({
                "brilliant_glass", "primal_mooncloth", "shadowcloth", "spellcloth", "transmute", "void_sphere",
            }, CD.GetOptionsCategoryOrder(false))
        end)

        it("lists each client's cooldowns by title A to Z", function()
            for _, isForever in ipairs({ false, true }) do
                local order = CD.GetOptionsCategoryOrder(isForever)
                for i = 2, #order do
                    assert.is_true(CD.CATEGORIES[order[i - 1]].title < CD.CATEGORIES[order[i]].title)
                end
            end
        end)

        it("returns WoW Forever's cooldowns (A to Z), without the unannounced Essence of Innovation", function()
            assert.are.same({ "dedicated_study", "mooncloth", "salt_shaker", "research", "transmute" },
                CD.GetOptionsCategoryOrder(true))
        end)
    end)

    describe("Research (Comprehension, WoW Forever)", function()
        local STUDY = 1302508

        local function researcher(expiresAtUnix)
            return {
                name = "Frell Blast",
                classFile = "MAGE",
                Professions = { Comprehension = { Recipes = { [STUDY] = { color = 4, name = "Study" } } } },
                ProfCooldownExpiry = expiresAtUnix and { [STUDY] = { expiresAtUnix = expiresAtUnix } } or {},
            }
        end

        it("is a tracked single-recipe category", function()
            local found = false
            for _, key in ipairs(CD.CATEGORY_ORDER) do
                if key == "research" then found = true end
            end
            assert.is_true(found)
            assert.are.equal("Study", CD.CATEGORIES.research.title)
            assert.are.equal("single", CD.CATEGORIES.research.mode)
            assert.is_true(CD.IsTrackedSpellId(STUDY))
            assert.is_nil(CD.CategorySpecField("research"))
        end)

        it("EnsureCooldownOptions defaults research to shown and alerting", function()
            local c = AltArmyTBC_Options.cooldowns.categories.research
            assert.truthy(c)
            assert.is_true(c.showInUI)
            assert.is_true(c.alertWhenAvailable)
        end)

        it("BuildRows adds a Research row only for characters that know Study", function()
            local ds = mockDS({ TestRealm = {
                Mage = researcher(1000 + 3600),
                Other = { name = "Other", Professions = { Tailoring = { Recipes = { [2963] = {} } } } },
            } })
            local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
            local research = {}
            for _, r in ipairs(rows) do
                if r.categoryKey == "research" then research[#research + 1] = r end
            end
            assert.are.equal(1, #research)
            assert.are.equal("Study", research[1].categoryTitle)
            assert.are.equal("Frell Blast", research[1].name)
            assert.are.equal(STUDY, research[1].spellId)
            assert.are.equal(1000 + 3600, research[1].expiresUnix)
            assert.are.equal("1h 0m", research[1].timeText)
        end)

        it("Study needs one Light Feather even though Forever never scans reagents", function()
            assert.is_nil(AltArmyTBC_Data.RecipeReagents[STUDY])
            assert.are.same({ { 17056, 1 } }, CD.GetReagentList(STUDY))
            local char = researcher(nil)
            local function count(_ch, itemId)
                return itemId == 17056 and 3 or 0
            end
            assert.are.equal(3, CD.GetMaxCraftableQuantity(char, STUDY, count))
        end)

        it("a scanned reagent list still wins over the built-in Study list", function()
            AltArmyTBC_Data.RecipeReagents[STUDY] = { { 17056, 2 } }
            assert.are.same({ { 17056, 2 } }, CD.GetReagentList(STUDY))
        end)

        it("EvaluateAlerts fires when the one-hour cooldown is ready", function()
            local ds = mockDS({ TestRealm = { Mage = researcher(1000 + 3600) } })
            local state = {}
            assert.are.equal(0, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000, state))
            local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000 + 3600, state)
            assert.are.equal(1, #alerts)
            assert.are.equal("research", alerts[1].categoryKey)
        end)
    end)

    describe("Dedicated Study (Legacy talent, WoW Forever)", function()
        local DEDICATED_STUDY = 1225469

        local function student(expiresAtUnix)
            return {
                name = "Bookish",
                classFile = "PRIEST",
                legacyTalents = { nodes = {}, spells = { [DEDICATED_STUDY] = 1 }, totalRanksSpent = 1 },
                ProfCooldownExpiry = expiresAtUnix and { [DEDICATED_STUDY] = { expiresAtUnix = expiresAtUnix } } or {},
            }
        end

        it("is a tracked category that needs no reagents", function()
            assert.is_true(CD.IsTrackedSpellId(DEDICATED_STUDY))
            assert.are.equal("Dedicated Study", CD.CATEGORIES.dedicated_study.title)
            assert.is_true(CD.SpellNeedsNoReagents(DEDICATED_STUDY))
            assert.is_false(CD.SpellNeedsNoReagents(1302508))
            assert.is_nil(CD.GetReagentList(DEDICATED_STUDY))
        end)

        it("BuildRows adds a row only for characters with the Legacy talent", function()
            local ds = mockDS({ TestRealm = {
                Bookish = student(1000 + 23 * 3600),
                Other = { name = "Other", legacyTalents = { spells = { [1225459] = 2 } } },
                Unscanned = { name = "Unscanned" },
            } })
            local rows = CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000)
            local found = {}
            for _, r in ipairs(rows) do
                if r.categoryKey == "dedicated_study" then found[#found + 1] = r end
            end
            assert.are.equal(1, #found)
            assert.are.equal("Bookish", found[1].name)
            assert.are.equal(DEDICATED_STUDY, found[1].spellId)
            assert.are.equal("23h 0m", found[1].timeText)
            assert.is_true(found[1].noReagents)
        end)

        it("EvaluateAlerts fires when the 23-hour cooldown is ready", function()
            local ds = mockDS({ TestRealm = { Bookish = student(1000 + 23 * 3600) } })
            local state = {}
            assert.are.equal(0, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000, state))
            local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000 + 23 * 3600, state)
            assert.are.equal(1, #alerts)
            assert.are.equal("dedicated_study", alerts[1].categoryKey)
        end)
    end)

    describe("WoW Forever's cooldown groups", function()
        local ARCANITE, LEGIONITE, AIR_TO_FIRE, TRUESILVER = 17187, 1317279, 17559, 11480
        local MOONCLOTH, SALT_SHAKER_SPELL, SALT_SHAKER_ITEM, INNOVATION = 18560, 19566, 15846, 1225470
        local savedDS, savedDebug, showUnannounced

        before_each(function()
            savedDS, savedDebug = AltArmy.DataStore, AltArmy.Debug
            AltArmy.DataStore = { IsWowForever = true }
            showUnannounced = false
            AltArmy.Debug = { IsShowUnannouncedCooldowns = function() return showUnannounced end }
            _G.AltArmyTBC_Data.RecipeReagents = {}
        end)
        after_each(function()
            AltArmy.DataStore, AltArmy.Debug = savedDS, savedDebug
        end)

        local function alchemist(recipes, extra)
            local char = { name = "Alch", Professions = { Alchemy = { Recipes = {} } } }
            for _, id in ipairs(recipes) do
                char.Professions.Alchemy.Recipes[id] = { color = 1 }
            end
            for k, v in pairs(extra or {}) do
                char[k] = v
            end
            return char
        end

        local function rowsOf(rows, key)
            local out = {}
            for _, r in ipairs(rows) do
                if r.categoryKey == key then out[#out + 1] = r end
            end
            return out
        end

        local function nameOf(id)
            local names = {
                [ARCANITE] = "Transmute: Arcanite",
                [LEGIONITE] = "Transmute: Legionite",
                [AIR_TO_FIRE] = "Transmute: Air to Fire",
                [TRUESILVER] = "Transmute: Mithril to Truesilver",
            }
            return names[id]
        end

        it("lists its own categories, Essence of Innovation only when Debug shows unannounced ones", function()
            assert.are.same({ "transmute", "mooncloth", "salt_shaker", "research", "dedicated_study" },
                CD.GetCategoryOrder(true))
            showUnannounced = true
            assert.are.same(
                { "transmute", "mooncloth", "salt_shaker", "research", "dedicated_study", "essence_of_innovation" },
                CD.GetCategoryOrder(true))
            assert.are.same({ "dedicated_study", "essence_of_innovation", "mooncloth", "salt_shaker", "research",
                "transmute" }, CD.GetOptionsCategoryOrder(true))
        end)

        it("leaves TBC's categories and tracked spells as they were", function()
            assert.are.same({ "transmute", "spellcloth", "shadowcloth", "primal_mooncloth", "brilliant_glass",
                "void_sphere", "research", "dedicated_study" }, CD.GetCategoryOrder(false))
            AltArmy.DataStore.IsWowForever = false
            assert.is_true(CD.IsTrackedSpellId(TRUESILVER))
            assert.is_true(CD.IsTransmuteSpellId(TRUESILVER, nameOf))
            assert.is_false(CD.IsTrackedSpellId(MOONCLOTH))
            assert.is_false(CD.IsTrackedSpellId(LEGIONITE))
            assert.is_nil(CD.ItemForTrackedSpell(SALT_SHAKER_SPELL))
            local char = alchemist({ TRUESILVER, ARCANITE })
            char.Professions.Tailoring = { Recipes = { [MOONCLOTH] = { color = 1 } } }
            char.Containers = { [0] = { items = { [1] = { itemID = SALT_SHAKER_ITEM, count = 1 } } } }
            local rows = CD.BuildRows(mockDS({ TestRealm = { A = char } }), AltArmyTBC_Options.cooldowns, 1000)
            assert.are.equal(1, #rowsOf(rows, "transmute"))
            assert.are.equal(0, #rowsOf(rows, "mooncloth"))
            assert.are.equal(0, #rowsOf(rows, "salt_shaker"))
        end)

        it("groups its game data's transmutes: Legionite in, Iron to Gold and Truesilver out", function()
            assert.is_true(CD.IsTransmuteSpellId(LEGIONITE, nameOf))
            assert.is_true(CD.IsTransmuteSpellId(AIR_TO_FIRE, nameOf))
            -- a "Transmute:" name doesn't put a spell in the group here
            assert.is_false(CD.IsTransmuteSpellId(TRUESILVER, nameOf))
            assert.is_false(CD.IsTransmuteSpellId(11479, nameOf))
            assert.is_false(CD.IsTrackedSpellId(TRUESILVER))
            assert.is_true(CD.IsTrackedSpellId(LEGIONITE))
            assert.is_false(CD.CharacterKnowsTransmute(alchemist({ TRUESILVER }), nameOf))
            assert.is_true(CD.CharacterKnowsTransmute(alchemist({ LEGIONITE }), nameOf))
            -- the Search tab's yield label still counts every transmute recipe
            assert.is_true(CD.IsTransmuteRecipe(TRUESILVER, nameOf))
        end)

        it("gives no Transmute row to a character knowing only Mithril to Truesilver", function()
            local char = alchemist({ TRUESILVER }, { lastTransmute = { spellId = TRUESILVER } })
            local rows = CD.BuildRows(mockDS({ TestRealm = { A = char } }), AltArmyTBC_Options.cooldowns, 1000)
            assert.are.equal(0, #rowsOf(rows, "transmute"))
        end)

        it("ignores a Truesilver cast as the last transmute", function()
            local char = alchemist({ TRUESILVER, ARCANITE })
            CD.RecordSuccessfulTransmuteCast(char, TRUESILVER)
            assert.is_nil(char.lastTransmute)
            CD.RecordSuccessfulTransmuteCast(char, ARCANITE)
            assert.are.equal(ARCANITE, char.lastTransmute.spellId)
        end)

        it("Auto picks Arcanite, then Legionite", function()
            assert.are.equal(ARCANITE, CD.ResolveTransmuteSpellForCharacter(alchemist({ LEGIONITE, ARCANITE })))
            assert.are.equal(LEGIONITE, CD.ResolveTransmuteSpellForCharacter(alchemist({ LEGIONITE, TRUESILVER })))
            assert.is_nil(CD.ResolveTransmuteSpellForCharacter(alchemist({ AIR_TO_FIRE })))
            -- the last cast still wins
            assert.are.equal(AIR_TO_FIRE, CD.ResolveTransmuteSpellForCharacter(
                alchemist({ AIR_TO_FIRE, ARCANITE }, { lastTransmute = { spellId = AIR_TO_FIRE } })))
        end)

        it("the recipe picker lists only the group's known transmutes", function()
            local char = alchemist({ ARCANITE, TRUESILVER, LEGIONITE })
            assert.are.same({ ARCANITE, LEGIONITE }, CD.GetKnownGroupSpellIds(char, "transmute"))
        end)

        it("takes the group's expiry over its own transmutes alone", function()
            local char = alchemist({ ARCANITE }, { ProfCooldownExpiry = {
                [AIR_TO_FIRE] = { expiresAtUnix = 1000 + 23 * 3600 },
                [TRUESILVER] = { expiresAtUnix = 1000 + 3 * 86400 }, -- its own cooldown, not the group's
            } })
            assert.are.equal(1000 + 23 * 3600, CD.GetTransmuteExpiryUnix(char))
            local rows = CD.BuildRows(mockDS({ TestRealm = { A = char } }), AltArmyTBC_Options.cooldowns, 1000)
            local t = rowsOf(rows, "transmute")
            assert.are.equal(1, #t)
            assert.are.equal("23h 0m", t[1].timeText)
        end)

        it("gives a tailor knowing Mooncloth a row with its 95-hour cooldown and Felcloth mats", function()
            local char = {
                name = "Tailor",
                Professions = { Tailoring = { Recipes = { [MOONCLOTH] = { color = 1 } } } },
                ProfCooldownExpiry = { [MOONCLOTH] = { expiresAtUnix = 1000 + 95 * 3600 } },
            }
            local rows = CD.BuildRows(mockDS({ TestRealm = { A = char } }), AltArmyTBC_Options.cooldowns, 1000)
            local m = rowsOf(rows, "mooncloth")
            assert.are.equal(1, #m)
            assert.are.equal(MOONCLOTH, m[1].spellId)
            assert.are.equal("3d 23h 0m", m[1].timeText)
            assert.is_false(m[1].noReagents)
            assert.are.same({ { 14256, 2 } }, CD.GetReagentList(MOONCLOTH))
        end)

        it("built-in reagents give way to scanned ones", function()
            assert.are.same({ { 12359, 1 }, { 12363, 1 } }, CD.GetReagentList(ARCANITE))
            assert.are.same({ { 251291, 1 }, { 248819, 1 } }, CD.GetReagentList(LEGIONITE))
            _G.AltArmyTBC_Data.RecipeReagents[ARCANITE] = { { 99999, 3 } }
            assert.are.same({ { 99999, 3 } }, CD.GetReagentList(ARCANITE))
        end)

        it("gives a Salt Shaker row to whoever holds one, in bags or bank", function()
            local holder = {
                name = "Holder",
                Containers = { [-1] = { items = { [3] = { itemID = SALT_SHAKER_ITEM, count = 1 } } } },
                ProfCooldownExpiry = { [SALT_SHAKER_SPELL] = { expiresAtUnix = 1000 + 71 * 3600 } },
            }
            local other = { name = "Other", Containers = { [0] = { items = { [1] = { itemID = 8150, count = 5 } } } } }
            local ds = mockDS({ TestRealm = { Holder = holder, Other = other } })
            local rows = rowsOf(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000), "salt_shaker")
            assert.are.equal(1, #rows)
            assert.are.equal("Holder", rows[1].name)
            assert.are.equal(SALT_SHAKER_SPELL, rows[1].spellId)
            assert.are.equal("2d 23h 0m", rows[1].timeText)
            assert.are.same({ { 8150, 1 } }, CD.GetReagentList(SALT_SHAKER_SPELL))
            assert.are.equal(SALT_SHAKER_ITEM, CD.ItemForTrackedSpell(SALT_SHAKER_SPELL))
            assert.are.same({ { itemId = SALT_SHAKER_ITEM, spellId = SALT_SHAKER_SPELL } }, CD.TrackedItemCooldowns())

            local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000 + 71 * 3600, {})
            assert.are.equal(1, #alerts)
            assert.are.equal("salt_shaker", alerts[1].categoryKey)
        end)

        describe("Essence of Innovation (unannounced Legacy talent)", function()
            local function innovator(expiresAtUnix)
                return {
                    name = "Inventor",
                    legacyTalents = { spells = { [INNOVATION] = 1 } },
                    ProfCooldownExpiry = { [INNOVATION] = { expiresAtUnix = expiresAtUnix } },
                }
            end

            it("is tracked even while hidden, so its cooldown is saved", function()
                assert.is_true(CD.IsTrackedSpellId(INNOVATION))
            end)

            it("has no row or alert while hidden", function()
                local ds = mockDS({ TestRealm = { Inventor = innovator(900) } })
                assert.are.equal(0, #rowsOf(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000),
                    "essence_of_innovation"))
                assert.are.equal(0, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000, {}))
            end)

            it("shown, it is a row for the talent's holders with mats, and alerts when ready", function()
                showUnannounced = true
                local ds = mockDS({ TestRealm = {
                    Inventor = innovator(1000 + 23 * 3600),
                    Other = { name = "Other", legacyTalents = { spells = { [1225469] = 1 } } },
                } })
                local rows = rowsOf(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000), "essence_of_innovation")
                assert.are.equal(1, #rows)
                assert.are.equal("Inventor", rows[1].name)
                assert.are.equal("23h 0m", rows[1].timeText)
                assert.is_false(rows[1].noReagents)
                assert.is_false(CD.SpellNeedsNoReagents(INNOVATION))
                assert.are.equal(7, #CD.GetReagentList(INNOVATION))
                local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 1000 + 23 * 3600, {})
                local fired = rowsOf(alerts, "essence_of_innovation")
                assert.are.equal(1, #fired)
            end)
        end)
    end)

    describe("settings panel", function()
        local CF = AltArmy.CharacterFilter

        it("EnsureCooldownOptions seeds the realm filter, grouping and folded sections", function()
            local cd = CD.EnsureCooldownOptions()
            assert.are.equal(CF.VERSION, cd.filter.version)
            assert.is_table(cd.filter.scope)
            assert.is_true(cd.groupByRealmFaction)
            assert.are.same({}, cd.collapsedGroups)
            cd.groupByRealmFaction = false
            cd.collapsedGroups["TestRealm|Horde"] = true
            cd.filter.scope.otherRealms = true
            CD.EnsureCooldownOptions()
            assert.is_false(cd.groupByRealmFaction)
            assert.is_true(cd.collapsedGroups["TestRealm|Horde"])
            assert.is_true(cd.filter.scope.otherRealms)
        end)

        it("the first realm filter starts from the Summary's, which the tab followed until now", function()
            _G.AltArmyTBC_SummarySettings = {
                filter = { version = CF.VERSION, scope = { otherFaction = true, otherRealms = true, linked = false } },
            }
            AltArmyTBC_Options.cooldowns = nil
            local cd = CD.EnsureCooldownOptions()
            assert.are.same({ otherFaction = true, otherRealms = true, linked = false }, cd.filter.scope)
            -- and only the first time
            AltArmyTBC_SummarySettings.filter.scope.otherRealms = false
            CD.EnsureCooldownOptions()
            assert.is_true(cd.filter.scope.otherRealms)
        end)

        local function tailor(withSpec)
            return {
                name = "Tailor",
                cooldownSpecs = withSpec and { spellfireTailor = true } or nil,
                Professions = { Tailoring = { Recipes = { [31373] = { color = 1 } } } },
                ProfCooldownExpiry = { [31373] = { expiresAtUnix = 500 } },
            }
        end
        local function hasRow(rows, key)
            for _, r in ipairs(rows) do
                if r.categoryKey == key then return true end
            end
            return false
        end

        it("BuildRows with all lists hidden categories and characters without the specialization", function()
            local cat = AltArmyTBC_Options.cooldowns.categories.spellcloth
            local ds = mockDS({ TestRealm = { T = tailor(false) } })
            cat.showInUI = false
            assert.is_false(hasRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000), "spellcloth"))
            assert.is_true(hasRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000, { all = true }), "spellcloth"))
            cat.showInUI = true
            cat.showOnlyIfSpecialization = true
            assert.is_false(hasRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000), "spellcloth"))
            assert.is_true(hasRow(CD.BuildRows(ds, AltArmyTBC_Options.cooldowns, 1000, { all = true }), "spellcloth"))
        end)

        it("EvaluateAlerts fires for a category hidden from the list", function()
            local cat = AltArmyTBC_Options.cooldowns.categories.spellcloth
            cat.showInUI = false
            local ds = mockDS({ TestRealm = { T = tailor(false) } })
            local alerts = CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, {})
            assert.are.equal(1, #alerts)
            assert.are.equal("spellcloth", alerts[1].categoryKey)
        end)

        it("EvaluateAlerts applies only its own specialization gate", function()
            local cat = AltArmyTBC_Options.cooldowns.categories.spellcloth
            local ds = mockDS({ TestRealm = { T = tailor(false) } })
            cat.showOnlyIfSpecialization = true
            assert.are.equal(1, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, {}))
            cat.showOnlyIfSpecialization = false
            cat.alertOnlyIfSpecialization = true
            assert.are.equal(0, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, {}))
            local specced = tailor(true)
            ds = mockDS({ TestRealm = { T = specced } })
            ds.GetCharacter = function() return specced end -- the alert's own gate reads the character
            assert.are.equal(1, #CD.EvaluateAlerts(ds, AltArmyTBC_Options.cooldowns, 600, {}))
        end)

        describe("dropdown entries", function()
            local savedDS
            before_each(function()
                savedDS = AltArmy.DataStore
                AltArmy.DataStore = { IsWowForever = false }
            end)
            after_each(function()
                AltArmy.DataStore = savedDS
            end)

            it("lists every category, a specialization-only entry after each that has one", function()
                local keys, labels = CD.SettingsEntries(false)
                assert.are.same({
                    "brilliant_glass",
                    "primal_mooncloth", "primal_mooncloth:spec",
                    "shadowcloth", "shadowcloth:spec",
                    "spellcloth", "spellcloth:spec",
                    "transmute", "transmute:spec",
                    "void_sphere",
                }, keys)
                assert.are.equal("Transmute (all specs)", labels.transmute)
                assert.are.equal("Transmute (Master of Transmutation only)", labels["transmute:spec"])
                assert.are.equal("Spellcloth (Spellfire Tailor only)", labels["spellcloth:spec"])
                assert.are.equal("Shadowcloth (Shadoweave Tailor only)", labels["shadowcloth:spec"])
                assert.are.equal("Primal Mooncloth (Mooncloth Tailor only)", labels["primal_mooncloth:spec"])
                assert.are.equal("Brilliant Glass", labels.brilliant_glass)
                assert.is_nil(labels.research) -- WoW Forever's alone
                assert.is_nil(labels.dedicated_study)
            end)

            it("has no specialization entries on WoW Forever", function()
                AltArmy.DataStore.IsWowForever = true
                local keys, labels = CD.SettingsEntries(true)
                assert.are.same({ "dedicated_study", "mooncloth", "salt_shaker", "research", "transmute" }, keys)
                assert.are.equal("Transmute", labels.transmute)
                assert.are.equal("Salt Shaker", labels.salt_shaker)
                assert.are.equal("Study (mage)", labels.research)
                assert.are.equal("Dedicated Study (legacy talent)", labels.dedicated_study)
                assert.is_nil(labels["transmute:spec"])
                -- a gate saved on TBC is ignored there, so the plain entry reads ticked
                AltArmyTBC_Options.cooldowns.categories.transmute.showOnlyIfSpecialization = true
                assert.is_true(CD.SettingsMap(AltArmyTBC_Options.cooldowns, "show").transmute)
            end)

            it("SettingsMap says which entry is ticked, every key explicit", function()
                local cd = AltArmyTBC_Options.cooldowns
                local map = CD.SettingsMap(cd, "show")
                assert.is_true(map.transmute)
                assert.is_false(map["transmute:spec"])
                assert.is_true(map.brilliant_glass)
                cd.categories.transmute.showOnlyIfSpecialization = true
                map = CD.SettingsMap(cd, "show")
                assert.is_false(map.transmute)
                assert.is_true(map["transmute:spec"])
                cd.categories.transmute.showInUI = false
                map = CD.SettingsMap(cd, "show")
                assert.is_false(map.transmute)
                assert.is_false(map["transmute:spec"])
                -- alerts read their own pair
                assert.is_true(CD.SettingsMap(cd, "alert").transmute)
                cd.categories.transmute.alertWhenAvailable = false
                assert.is_false(CD.SettingsMap(cd, "alert").transmute)
                cd.categories.transmute.alertWhenAvailable = true
                cd.categories.transmute.alertOnlyIfSpecialization = true
                assert.is_false(CD.SettingsMap(cd, "alert").transmute)
                assert.is_true(CD.SettingsMap(cd, "alert")["transmute:spec"])
            end)

            it("SetSettingsEntry: ticking one entry unticks the other, unticking hides the category", function()
                local cd = AltArmyTBC_Options.cooldowns
                local cat = cd.categories.transmute
                CD.SetSettingsEntry(cd, "show", "transmute:spec", true)
                assert.is_true(cat.showInUI)
                assert.is_true(cat.showOnlyIfSpecialization)
                CD.SetSettingsEntry(cd, "show", "transmute", true)
                assert.is_true(cat.showInUI)
                assert.is_false(cat.showOnlyIfSpecialization)
                CD.SetSettingsEntry(cd, "show", "transmute", false)
                assert.is_false(cat.showInUI)
                CD.SetSettingsEntry(cd, "show", "transmute:spec", true)
                CD.SetSettingsEntry(cd, "show", "transmute:spec", false)
                assert.is_false(cat.showInUI)
                CD.SetSettingsEntry(cd, "alert", "transmute:spec", true)
                assert.is_true(cat.alertWhenAvailable)
                assert.is_true(cat.alertOnlyIfSpecialization)
                CD.SetSettingsEntry(cd, "alert", "transmute", false)
                assert.is_false(cat.alertWhenAvailable)
                CD.SetSettingsEntry(cd, "show", "nonsense", true) -- a no-op
                assert.is_nil(cd.categories.nonsense)
            end)

            it("FormatSettingsSummary names what is ticked by the cooldowns' plain names", function()
                local keys, labels = CD.SettingsEntries(false)
                local cd = AltArmyTBC_Options.cooldowns
                local function summary()
                    return CD.FormatSettingsSummary(keys, labels, CD.SettingsMap(cd, "show"))
                end
                assert.are.equal("All", summary())
                cd.categories.transmute.showOnlyIfSpecialization = true
                assert.are.equal("All", summary())
                -- WoW Forever's cooldowns aren't listed here, so their settings change nothing
                cd.categories.dedicated_study.showInUI = false
                assert.are.equal("All", summary())
                cd.categories.spellcloth.showInUI = false
                assert.are.equal("All but Spellcloth", summary())
                cd.categories.transmute.showInUI = false
                assert.are.equal("Brilliant Glass, Primal Mooncloth, Shadowcloth, Void Sphere / Prismatic Sphere",
                    summary())
                for _, key in ipairs(CD.CATEGORY_ORDER) do
                    cd.categories[key].showInUI = false
                end
                assert.are.equal("None", summary())
                cd.categories.transmute.showInUI = true
                cd.categories.brilliant_glass.showInUI = true
                -- neither "(all specs)" nor "(<spec> only)"
                assert.are.equal("Brilliant Glass, Transmute", summary())
                cd.categories.transmute.showOnlyIfSpecialization = false
                assert.are.equal("Brilliant Glass, Transmute", summary())
            end)

            it("FormatSettingsSummary on WoW Forever's", function()
                AltArmy.DataStore.IsWowForever = true
                local keys, labels = CD.SettingsEntries(true)
                local cd = AltArmyTBC_Options.cooldowns
                cd.categories.research.showInUI = false
                -- the note "(mage)" is the row's alone
                assert.are.equal("All but Study",
                    CD.FormatSettingsSummary(keys, labels, CD.SettingsMap(cd, "show")))
                cd.categories.transmute.showInUI = false
                cd.categories.mooncloth.showInUI = false
                assert.are.equal("Dedicated Study, Salt Shaker",
                    CD.FormatSettingsSummary(keys, labels, CD.SettingsMap(cd, "show")))
            end)
        end)
    end)
end)
