--[[
  Unit tests for GearUpgradeAlerts.lua.
  Run from project root: npm test
]]

describe("GearUpgradeAlerts", function()
    local GA
    local openedLink

    local function defaultGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        if id == 11 then
            return "New Helm", "|Hitem:11:0|h[New Helm]|h"
        end
        return nil
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        openedLink = nil
        AltArmy.OpenGearTabFocused = function(itemLink)
            openedLink = itemLink
        end
        _G.GetItemInfo = defaultGetItemInfo
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
                HookScript = function() end,
            }
        end
        _G.SetItemRef = function() end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
    end)

    before_each(function()
        _G.GetItemInfo = defaultGetItemInfo
        openedLink = nil
    end)

    it("HandleSetItemRef opens gear tab for addon upgrade links", function()
        local ok = GA.HandleSetItemRef("addon:AltArmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef opens gear tab for altarmy upgrade links", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef accepts mixed-case link types", function()
        local ok = GA.HandleSetItemRef("AltArmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    describe("CHAT_MSG_LOOT secret-value guard", function()
        it("_IsSelfLootMessage treats an inaccessible (secret) message as not self-loot", function()
            _G.canaccessvalue = function() return false end
            local result = GA._IsSelfLootMessage("You receive loot: [Foo]x1.")
            _G.canaccessvalue = nil
            assert.is_false(result)
        end)

        it("_ExtractItemLink returns nil for an inaccessible (secret) message", function()
            _G.canaccessvalue = function() return false end
            local result = GA._ExtractItemLink("You receive loot: |Hitem:11:0|h[New Helm]|h.")
            _G.canaccessvalue = nil
            assert.is_nil(result)
        end)

        it("still works normally for plain (non-secret) messages", function()
            assert.is_true(GA._IsSelfLootMessage("You receive loot: [Foo]x1."))
            assert.are.equal(
                "|Hitem:11:0|h[New Helm]|h",
                GA._ExtractItemLink("You receive loot: |Hitem:11:0|h[New Helm]|h."))
        end)
    end)

    it("HandleSetItemRef falls back to bare item id when item is uncached", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:99999", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("item:99999", openedLink)
    end)

    it("HandleSetItemRef preserves random suffix item payload", function()
        _G.GetItemInfo = function(item)
            if type(item) == "string" and item:find("item:99:") then
                return "Greaves of the Boar", item
            end
            if item == 99 then
                return "Greaves", "|Hitem:99:0|h[Greaves]|h"
            end
            return nil
        end
        local ok = GA.HandleSetItemRef(
            "altarmy:upgrade:item:99:0:0:0:0:0:55:12345:0",
            "LeftButton")
        assert.is_true(ok)
        assert.matches("item:99:0:0:0:0:0:55:12345", openedLink)
    end)

    it("HandleSetItemRef ignores non-upgrade links", function()
        openedLink = nil
        assert.is_false(GA.HandleSetItemRef("item:11", "LeftButton"))
        assert.is_nil(openedLink)
    end)

    it("installUpgradeLinkInterceptors registers EventRegistry without replacing SetItemRef", function()
        local innerCalled = false
        local registryCalls = {}
        _G.SetItemRef = function()
            innerCalled = true
        end
        _G.EventRegistry = {
            RegisterCallback = function(_, eventName, handler, owner)
                registryCalls[#registryCalls + 1] = { eventName, handler, owner }
            end,
        }
        if GA then GA._upgradeLinkInterceptorsInstalled = nil end
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
        openedLink = nil
        assert.are.equal(1, #registryCalls)
        assert.are.equal("SetItemRef", registryCalls[1][1])
        assert.are.equal(GA, registryCalls[1][3])
        registryCalls[1][2](GA, "altarmy:upgrade:11", "View details", "LeftButton")
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
        assert.is_false(innerCalled)
        _G.EventRegistry = nil
    end)

    it("installUpgradeLinkInterceptors uses hooksecurefunc without replacing SetItemRef", function()
        local innerCalled = false
        local hookInstalled = false
        _G.SetItemRef = function()
            innerCalled = true
        end
        _G.EventRegistry = nil
        _G.hooksecurefunc = function(name, fn)
            hookInstalled = true
            assert.are.equal("SetItemRef", name)
            fn("altarmy:upgrade:11", "View details", "LeftButton")
        end
        if GA then GA._upgradeLinkInterceptorsInstalled = nil end
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
        openedLink = nil
        assert.is_true(hookInstalled)
        SetItemRef("item:11", "item", "LeftButton")
        assert.is_true(innerCalled)
        _G.hooksecurefunc = nil
    end)

    describe("AnnounceLootUpgrade", function()
        local chatLines

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            local notifyCurrent = overrides.notifyCurrentCharacter
            if notifyCurrent == nil then notifyCurrent = true end
            local notifyOther = overrides.notifyOtherCharacters
            if notifyOther == nil then notifyOther = true end
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = notifyOther,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForAllAlts = overrides.evaluateForAllAlts or function()
                    return {}
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function()
                    return false
                end,
            }
            AltArmy.DataStore = {
                GetCurrentCharacter = overrides.getCurrentCharacter or function()
                    return { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
                end,
                GetCurrentPlayerRealm = function() return "TestRealm" end,
                GetCharacterLevel = function(_, char) return char and char.level or 0 end,
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = overrides.isBindOnPickup or function() return false end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("includes the item link, character names, and view details link", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            local itemLink = "|Hitem:11:0|h[New Helm]|h"
            local ok = GA.AnnounceLootUpgrade(itemLink)
            assert.is_true(ok)
            assert.is_not_nil(chatLines[1]:find(itemLink, 1, true))
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.matches("%[View details%]", chatLines[1])
        end)

        it("lists every alt name when three or fewer match", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "Alpha", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                        { name = "Charlie", classFile = "WARLOCK" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, Charlie:", chatLines[1])
        end)

        it("summarizes four or more alts as two names plus others", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "Alpha", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                        { name = "Charlie", classFile = "WARLOCK" },
                        { name = "Delta", classFile = "HUNTER" },
                        { name = "Echo", classFile = "ROGUE" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, and 3 others:", chatLines[1])
        end)

        it("announces bind-on-pickup loot upgrades for the current character when enabled", function()
            loadWithMocks({
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_true(ok)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("skips bind-on-pickup loot when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                isBindOnPickup = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
        end)

        it("does not check other characters for bind-on-pickup loot", function()
            local evaluatedAllAlts = false
            loadWithMocks({
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
                evaluateForAllAlts = function()
                    evaluatedAllAlts = true
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(evaluatedAllAlts)
        end)

        it("announces when only the current character matches and current notifications are enabled", function()
            loadWithMocks({
                notifyOtherCharacters = false,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_true(ok)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("does not announce loot upgrades when other-character notifications are disabled and current does not match", function()
            loadWithMocks({
                notifyOtherCharacters = false,
                evaluateForCharacter = function() return false end,
            })
            AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                return { { name = "Bravo", classFile = "PRIEST" } }
            end
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
        end)

        it("excludes the current character when only other-character notifications are enabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                evaluateForAllAlts = function()
                    return {
                        { name = "MageAlt", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.is_nil(chatLines[1]:match("MageAlt"))
        end)

        it("includes the current character when both notification toggles are enabled", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "MageAlt", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for MageAlt, Bravo:", chatLines[1])
        end)

        describe("repeat-alert debounce", function()
            local mockTime
            local savedGetTime

            before_each(function()
                savedGetTime = _G.GetTime
                mockTime = 1000
                _G.GetTime = function() return mockTime end
                loadWithMocks({
                    evaluateForAllAlts = function()
                        return { { name = "Bravo", classFile = "PRIEST" } }
                    end,
                })
            end)

            after_each(function()
                _G.GetTime = savedGetTime
            end)

            it("does not re-announce the same item within 60 seconds", function()
                assert.is_true(GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h"))
                mockTime = 1059
                local ok, reason = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
                assert.is_false(ok)
                assert.are.equal("debounced", reason)
                assert.are.equal(1, #chatLines)
            end)

            it("announces the same item again after 60 seconds", function()
                GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
                mockTime = 1060
                assert.is_true(GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h"))
                assert.are.equal(2, #chatLines)
            end)

            it("keeps the window anchored to the last announcement", function()
                GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
                mockTime = 1030
                GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
                mockTime = 1061
                assert.is_true(GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h"))
                assert.are.equal(2, #chatLines)
            end)

            it("does not debounce a different item", function()
                GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
                assert.is_true(GA.AnnounceLootUpgrade("|Hitem:12:0|h[Other Helm]|h"))
                assert.are.equal(2, #chatLines)
            end)

            it("does not start the window when nothing was announced", function()
                AltArmy.GearUpgrade.EvaluateForAllAlts = function() return {} end
                assert.is_false(GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h"))
                AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end
                assert.is_true(GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h"))
            end)
        end)
    end)

    describe("AnnounceLootRollUpgrade", function()
        local chatLines
        local itemLink = "|Hitem:11:0|h[New Helm]|h"

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            local notifyCurrent = overrides.notifyCurrentCharacter
            if notifyCurrent == nil then notifyCurrent = true end
            local notifyOther = overrides.notifyOtherCharacters
            if notifyOther == nil then notifyOther = true end
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = notifyOther,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForAllAlts = overrides.evaluateForAllAlts or function()
                    return {}
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function()
                    return false
                end,
            }
            AltArmy.DataStore = {
                GetCurrentCharacter = overrides.getCurrentCharacter or function()
                    return { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
                end,
                GetCurrentPlayerRealm = function() return "TestRealm" end,
                GetCharacterLevel = function(_, char) return char and char.level or 0 end,
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = overrides.isBindOnPickup or function() return false end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            _G.GetLootRollItemLink = overrides.getLootRollItemLink
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("announces non-BoP roll upgrades using the loot upgrade message", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            local ok = GA.AnnounceLootRollUpgrade(itemLink)
            assert.is_true(ok)
            assert.are.equal(1, #chatLines)
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.matches("%[View details%]", chatLines[1])
        end)

        it("announces BoP roll upgrades for the current character when enabled", function()
            loadWithMocks({
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootRollUpgrade(itemLink)
            assert.is_true(ok)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("skips BoP rolls when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootRollUpgrade(itemLink)
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
            assert.is_false(GA.ShouldSuppressLootUpgrade(itemLink))
        end)

        it("suppresses the self-loot announce after a successful roll announce", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            assert.is_true(GA.AnnounceLootRollUpgrade(itemLink))
            assert.is_true(GA.ShouldSuppressLootUpgrade(itemLink))
            local ok = GA.AnnounceLootUpgrade(itemLink)
            assert.is_false(ok)
            assert.are.equal(1, #chatLines)
            assert.is_false(GA.ShouldSuppressLootUpgrade(itemLink))
        end)

        it("does not suppress loot when the roll announce finds no matches", function()
            loadWithMocks({
                evaluateForAllAlts = function() return {} end,
                evaluateForCharacter = function() return false end,
            })
            local ok = GA.AnnounceLootRollUpgrade(itemLink)
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
            assert.is_false(GA.ShouldSuppressLootUpgrade(itemLink))
        end)

        it("resolves the item from a roll ID via GetLootRollItemLink", function()
            loadWithMocks({
                getLootRollItemLink = function(rollId)
                    if rollId == 42 then return itemLink end
                end,
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            local ok = GA.AnnounceLootRollUpgrade(42)
            assert.is_true(ok)
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.is_true(GA.ShouldSuppressLootUpgrade(itemLink))
        end)

        it("ignores a secret roll item link", function()
            local evaluated = false
            loadWithMocks({
                getLootRollItemLink = function() return itemLink end,
                evaluateForAllAlts = function()
                    evaluated = true
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            _G.canaccessvalue = function(v) return v ~= itemLink end
            local ok = GA.AnnounceLootRollUpgrade(42)
            _G.canaccessvalue = nil
            assert.is_false(ok)
            assert.is_false(evaluated)
            assert.are.equal(0, #chatLines)
        end)

        it("clears roll suppression when entering the world", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            GA.AnnounceLootRollUpgrade(itemLink)
            assert.is_true(GA.ShouldSuppressLootUpgrade(itemLink))
            GA.OnEnteringWorld()
            assert.is_false(GA.ShouldSuppressLootUpgrade(itemLink))
        end)
    end)

    describe("AnnounceLevelUpUpgrades", function()
        local chatLines
        local helmLink = "|Hitem:11:0|h[New Helm]|h"

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            _G.GetContainerNumSlots = overrides.getContainerNumSlots or function() return 0 end
            _G.GetContainerItemLink = overrides.getContainerItemLink
            AltArmy.DataStore = {
                GetCurrentCharacter = function()
                    return overrides.char or { classFile = "MAGE", name = "MageAlt" }
                end,
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
                ScanBags = function() end,
                IterateBagSlots = overrides.iterateBagSlots,
                IterateBankSlots = overrides.iterateBankSlots,
                GetNumMails = overrides.getNumMails or function() return 0 end,
                GetMailInfo = overrides.getMailInfo,
                BANK_CONTAINER = -1,
                MIN_BANK_BAG_ID = 5,
                MAX_BANK_BAG_ID = 11,
            }
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    local notifyCurrent = overrides.notifyCurrentCharacter
                    if notifyCurrent == nil then notifyCurrent = true end
                    local notifyOther = overrides.notifyOtherCharacters
                    if notifyOther == nil then notifyOther = true end
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = notifyOther,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function()
                    return true
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = overrides.isBindOnPickup or function() return false end,
                NeedsProficiencyTraining = function() return false end,
                EffectiveRequiredLevel = overrides.effectiveRequiredLevel or function(_, link)
                    if link == helmLink then return 40 end
                    return 999
                end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("skips level-up announcements for bank alts", function()
            require("CharKey")
            package.loaded["BankAlt"] = nil
            require("BankAlt")
            AltArmy.BankAlt.Set("MageAlt", "TestRealm", true)
            loadWithMocks({
                char = { classFile = "MAGE", name = "MageAlt", realm = "TestRealm" },
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            AltArmy.DataStore.GetCurrentPlayerRealm = function() return "TestRealm" end
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("announces equippable bag upgrades at the new level", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(1, #chatLines)
            assert.matches("Congratulations! You can now equip ", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
            assert.is_nil(chatLines[1]:match("%(bank%)"))
            assert.is_nil(chatLines[1]:match("%(mail%)"))
        end)

        it("announces soulbound (bind-on-pickup) bag upgrades at the new level", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                isBindOnPickup = function() return true end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
        end)

        it("announces multiple upgrades in a single chat message", function()
            local chestLink = "|Hitem:22:0|h[New Chest]|h"
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                    cb(0, 2, 22, 1, chestLink)
                end,
                effectiveRequiredLevel = function(_, link)
                    if link == helmLink or link == chestLink then return 40 end
                    return 999
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(1, #chatLines)
            assert.matches(" and ", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
            assert.is_not_nil(chatLines[1]:find(chestLink, 1, true))
        end)

        it("summarizes three or more upgrades in one chat message", function()
            local chestLink = "|Hitem:22:0|h[New Chest]|h"
            local bootsLink = "|Hitem:33:0|h[New Boots]|h"
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                    cb(0, 2, 22, 1, chestLink)
                    cb(0, 3, 33, 1, bootsLink)
                end,
                effectiveRequiredLevel = function(_, link)
                    if link == helmLink or link == chestLink or link == bootsLink then
                        return 40
                    end
                    return 999
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(1, #chatLines)
            assert.matches("1 other upgrade", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
            assert.is_not_nil(chatLines[1]:find(chestLink, 1, true))
            assert.is_nil(chatLines[1]:find(bootsLink, 1, true))
        end)

        it("appends bank reminder when the upgrade is in the bank", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 11, 1, helmLink)
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.matches("%(bank%)", chatLines[1])
        end)

        it("appends mailbox reminder when the upgrade is in mail", function()
            loadWithMocks({
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, helmLink
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.matches("%(mail%)", chatLines[1])
        end)

        it("skips items that are not upgrades", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                evaluateForCharacter = function() return false end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("skips items whose required level does not match the new level", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function() return 41 end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("evaluates upgrades at the simulated new level", function()
            local seenLevel
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function() return 67 end,
                evaluateForCharacter = function(_, _, opts)
                    seenLevel = opts.level
                    return opts.level == 67
                end,
            })
            GA.AnnounceLevelUpUpgrades(67)
            assert.are.equal(67, seenLevel)
            assert.are.equal(1, #chatLines)
        end)

        it("SimulateLevelUp runs the level-up upgrade scan", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function(_, link)
                    if link == helmLink then return 61 end
                    return 999
                end,
            })
            local ok = GA.SimulateLevelUp(61)
            assert.is_true(ok)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
        end)

        it("SimulateLevelUp reports invalid level usage", function()
            loadWithMocks()
            local ok = GA.SimulateLevelUp("abc")
            assert.is_false(ok)
            assert.matches("Usage: /altarmy debug levelup", chatLines[1])
        end)

        it("does not announce level-up upgrades when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                getContainerNumSlots = function() return 1 end,
                getContainerItemLink = function(_, slot)
                    if slot == 1 then return helmLink end
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("SimulateLevelUp reports disabled current-character notifications", function()
            loadWithMocks({ notifyCurrentCharacter = false })
            local ok = GA.SimulateLevelUp(40)
            assert.is_false(ok)
            assert.matches("disabled in options", chatLines[1])
        end)

        it("ScheduleLevelUpUpgradeAnnouncement defers chat until the timer fires", function()
            local scheduled = {}
            _G.C_Timer = {
                After = function(delay, fn)
                    scheduled[#scheduled + 1] = { delay = delay, fn = fn }
                end,
            }
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            GA.ScheduleLevelUpUpgradeAnnouncement(40)
            assert.are.equal(0, #chatLines)
            assert.are.equal(1, #scheduled)
            assert.are.equal(GA.LEVEL_UP_UPGRADE_ANNOUNCE_DELAY_SEC, scheduled[1].delay)
            scheduled[1].fn()
            assert.are.equal(1, #chatLines)
            _G.C_Timer = nil
        end)

        it("ScheduleLevelUpUpgradeAnnouncement cancels a pending timer", function()
            local scheduled = {}
            _G.C_Timer = {
                After = function(_, fn)
                    scheduled[#scheduled + 1] = fn
                end,
            }
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            GA.ScheduleLevelUpUpgradeAnnouncement(40)
            GA.CancelLevelUpUpgradeAnnouncement()
            scheduled[1]()
            assert.are.equal(0, #chatLines)
            _G.C_Timer = nil
        end)

        it("OnEnteringWorld cancels a pending level-up announcement", function()
            local scheduled = {}
            _G.C_Timer = {
                After = function(_, fn)
                    scheduled[#scheduled + 1] = fn
                end,
            }
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            GA.ScheduleLevelUpUpgradeAnnouncement(40)
            GA.OnEnteringWorld()
            scheduled[1]()
            assert.are.equal(0, #chatLines)
            _G.C_Timer = nil
        end)
    end)

    describe("AnnounceLevelUpConsumables", function()
        local chatLines
        local potionLink = "|Hitem:118:0|h[Minor Healing Potion]|h"
        local elixirLink = "|Hitem:2454:0|h[Elixir of Lion's Strength]|h"
        local scrollLink = "|Hitem:954:0|h[Scroll of Strength]|h"
        local helmLink = "|Hitem:11:0|h[New Helm]|h"

        local function consumableGetItemInfo(item)
            local infoByLink = {
                [potionLink] = { name = "Minor Healing Potion", minLevel = 5, class = "Consumable" },
                [elixirLink] = { name = "Elixir of Lion's Strength", minLevel = 5, class = "Consumable" },
                [scrollLink] = { name = "Scroll of Strength", minLevel = 10, class = "Consumable" },
                [helmLink] = { name = "New Helm", minLevel = 5, class = "Armor" },
            }
            local info = infoByLink[item]
            if not info then
                local id = tonumber(tostring(item):match("item:(%d+)")) or tonumber(item)
                local infoById = {
                    [118] = { name = "Minor Healing Potion", minLevel = 5, class = "Consumable" },
                    [2454] = { name = "Elixir of Lion's Strength", minLevel = 5, class = "Consumable" },
                    [954] = { name = "Scroll of Strength", minLevel = 10, class = "Consumable" },
                    [11] = { name = "New Helm", minLevel = 5, class = "Armor" },
                }
                info = infoById[id]
            end
            if not info then return nil end
            return info.name, item, 1, 10, info.minLevel, info.class, "Potion"
        end

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            _G.GetItemInfo = consumableGetItemInfo
            _G.GetContainerNumSlots = function() return 0 end
            _G.GetContainerItemLink = nil
            AltArmy.DataStore = {
                GetCurrentCharacter = function()
                    return overrides.char or { classFile = "MAGE", name = "MageAlt" }
                end,
                ScanBags = function() end,
                IterateBagSlots = overrides.iterateBagSlots or function() end,
                IterateBankSlots = overrides.iterateBankSlots,
                GetNumMails = overrides.getNumMails or function() return 0 end,
                GetMailInfo = overrides.getMailInfo,
                BANK_CONTAINER = -1,
                MIN_BANK_BAG_ID = 5,
                MAX_BANK_BAG_ID = 11,
            }
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    local notifyCurrent = overrides.notifyCurrentCharacter
                    if notifyCurrent == nil then notifyCurrent = true end
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = true,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                EvaluateForCharacter = function() return false end,
                GetEffectiveTechnique = function(technique) return technique end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
                NeedsProficiencyTraining = function() return false end,
                EffectiveRequiredLevel = function() return 999 end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("announces a bank consumable usable at the new level", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.matches("Congratulations! You can now consume ", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(potionLink .. " (bank)", 1, true))
        end)

        it("announces a mail consumable usable at the new level", function()
            loadWithMocks({
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, potionLink
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(potionLink .. " (mail)", 1, true))
        end)

        it("merges bank and mail sources for the same consumable", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, potionLink
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(potionLink .. " (bank, mail)", 1, true))
        end)

        it("lists multiple consumables with commas and a final and", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                    cb(-1, 2, 2454, 1, elixirLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(
                potionLink .. " (bank) and " .. elixirLink .. " (bank)", 1, true))
        end)

        it("skips non-consumable items", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 11, 1, helmLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(0, #chatLines)
        end)

        it("skips consumables whose required level does not match", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 954, 1, scrollLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(0, #chatLines)
        end)

        it("announces bag consumables without a source suffix", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 118, 5, potionLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.matches("Congratulations! You can now consume ", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(potionLink, 1, true))
            assert.is_nil(chatLines[1]:match("%(bank%)"))
            assert.is_nil(chatLines[1]:match("%(mail%)"))
        end)

        it("omits the bank label when the consumable is also in bags", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 118, 5, potionLink)
                end,
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.is_nil(chatLines[1]:match("%(bank%)"))
        end)

        it("omits source labels when the consumable is also in bags", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 118, 5, potionLink)
                end,
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, potionLink
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(potionLink, 1, true))
            assert.is_nil(chatLines[1]:match("%(mail%)"))
            assert.is_nil(chatLines[1]:match("%(bank%)"))
        end)

        it("announces the same consumable once when bag and mail links differ", function()
            local bagLink = "|cff1eff00|Hitem:118:0:0:0:0:0:0:0|h[Minor Healing Potion]|h|r"
            local mailLink = "|Hitem:118:0|h[Minor Healing Potion]|h"
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 118, 5, bagLink)
                end,
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, mailLink
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(1, #chatLines)
            assert.matches("Congratulations! You can now consume ", chatLines[1])
            local _, count = chatLines[1]:gsub("%[Minor Healing Potion%]", "")
            assert.are.equal(1, count)
            assert.is_nil(chatLines[1]:match("%(mail%)"))
        end)

        it("does not announce when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(0, #chatLines)
        end)

        it("skips consumable announcements for bank alts", function()
            require("CharKey")
            package.loaded["BankAlt"] = nil
            require("BankAlt")
            AltArmy.BankAlt.Set("MageAlt", "TestRealm", true)
            loadWithMocks({
                char = { classFile = "MAGE", name = "MageAlt", realm = "TestRealm" },
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            AltArmy.DataStore.GetCurrentPlayerRealm = function() return "TestRealm" end
            GA.AnnounceLevelUpConsumables(5)
            assert.are.equal(0, #chatLines)
        end)

        it("ScheduleLevelUpUpgradeAnnouncement also announces consumables", function()
            local scheduled = {}
            _G.C_Timer = {
                After = function(_, fn)
                    scheduled[#scheduled + 1] = fn
                end,
            }
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            GA.ScheduleLevelUpUpgradeAnnouncement(5)
            assert.are.equal(0, #chatLines)
            scheduled[1]()
            assert.are.equal(1, #chatLines)
            assert.matches("You can now consume ", chatLines[1])
            _G.C_Timer = nil
        end)

        it("SimulateLevelUp runs the consumable scan", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 118, 5, potionLink)
                end,
            })
            local ok = GA.SimulateLevelUp(5)
            assert.is_true(ok)
            assert.are.equal(1, #chatLines)
            assert.matches("You can now consume ", chatLines[1])
        end)
    end)

    describe("CollectQuestRewardLinks", function()
        it("collects only choice links when choices exist", function()
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            _G.GetNumQuestRewards = function() return 1 end
            _G.GetNumQuestChoices = function() return 2 end
            _G.GetQuestItemLink = function(kind, index)
                if kind == "reward" and index == 1 then
                    return "|Hitem:11:0|h[Reward]|h"
                end
                if kind == "choice" and index == 1 then
                    return "|Hitem:22:0|h[Choice A]|h"
                end
                if kind == "choice" and index == 2 then
                    return "|Hitem:33:0|h[Choice B]|h"
                end
            end
            local links = GA.CollectQuestRewardLinks()
            assert.are.equal(2, #links)
            assert.is_not_nil(links[1]:find("item:22", 1, true))
            assert.is_not_nil(links[2]:find("item:33", 1, true))
        end)

        it("collects guaranteed reward links when there are no choices", function()
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            _G.GetNumQuestRewards = function() return 2 end
            _G.GetNumQuestChoices = function() return 0 end
            _G.GetQuestItemLink = function(kind, index)
                if kind == "reward" and index == 1 then
                    return "|Hitem:11:0|h[Reward A]|h"
                end
                if kind == "reward" and index == 2 then
                    return "|Hitem:22:0|h[Reward B]|h"
                end
            end
            local links = GA.CollectQuestRewardLinks()
            assert.are.equal(2, #links)
            assert.is_not_nil(links[1]:find("item:11", 1, true))
            assert.is_not_nil(links[2]:find("item:22", 1, true))
        end)

        it("returns empty list when quest APIs are missing", function()
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            _G.GetNumQuestRewards = nil
            _G.GetNumQuestChoices = nil
            _G.GetQuestItemLink = nil
            assert.are.same({}, GA.CollectQuestRewardLinks())
        end)
    end)

    describe("AnnounceQuestRewardUpgrades", function()
        local chatLines
        local linkA = "|Hitem:11:0|h[Choice A]|h"
        local linkB = "|Hitem:22:0|h[Choice B]|h"

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            if not AltArmy.BankAlt then
                package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
                require("CharKey")
                package.loaded["BankAlt"] = nil
                require("BankAlt")
            end
            _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
            AltArmy.BankAlt.Set("MageAlt", "TestRealm", false)
            local notifyCurrent = overrides.notifyCurrentCharacter
            if notifyCurrent == nil then notifyCurrent = true end
            local evaluatedAllAlts = false
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = overrides.notifyOtherCharacters ~= false,
                        technique = "custom",
                        levelsAhead = 5,
                        upgradeThresholdPercent = overrides.upgradeThresholdPercent or 5,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                ResolveCompareContext = function(char)
                    return (char and char.classFile) or "MAGE", "arcane"
                end,
                ScoreItem = overrides.scoreItem or function()
                    return 100
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function(_, link)
                    return link == linkA or link == linkB
                end,
                EvaluateForAllAlts = function()
                    evaluatedAllAlts = true
                    return {}
                end,
                GetCharacterUpgradeDelta = overrides.getCharacterUpgradeDelta or function(_, link)
                    if link == linkA then return 10 end
                    if link == linkB then return 50 end
                    return 0
                end,
                GetUpgradeHighlightKind = overrides.getUpgradeHighlightKind or function(delta, oldTotal, opts)
                    local threshold = (opts and opts.upgradeThresholdPercent) or 5
                    if not delta or delta <= 0 then return nil end
                    oldTotal = tonumber(oldTotal) or 0
                    local percent
                    if oldTotal > 0 then
                        percent = delta / oldTotal * 100
                    elseif delta > 0 then
                        percent = 100
                    else
                        percent = 0
                    end
                    if percent >= threshold then return "clear" end
                    return "minor"
                end,
            }
            AltArmy.DataStore = {
                GetCurrentCharacter = function()
                    return { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
                end,
                GetCurrentPlayerRealm = function() return "TestRealm" end,
                GetCharacterLevel = function(_, char) return char and char.level or 0 end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
                GetInventorySlotsForItem = overrides.getInventorySlotsForItem or function() return { 1 } end,
                IsEquippableWithin = overrides.isEquippableWithin or function() return true, 0, nil end,
                LacksTrainedProficiency = overrides.lacksTrainedProficiency,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            _G.GetNumQuestRewards = overrides.getNumQuestRewards or function() return 0 end
            _G.GetNumQuestChoices = overrides.getNumQuestChoices or function() return 2 end
            _G.GetQuestItemLink = overrides.getQuestItemLink or function(_, index)
                if index == 1 then return linkA end
                if index == 2 then return linkB end
            end
            local mockTime = overrides.mockTime or 1000
            _G.GetTime = overrides.getTime or function() return mockTime end
            _G.GetTitleText = overrides.getTitleText or function() return "Test Quest" end
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            return { evaluatedAllAlts = function() return evaluatedAllAlts end }
        end

        it("announces the best quest reward upgrade when multiple rewards match", function()
            loadWithMocks({
                getNumQuestRewards = function() return 1 end,
                getQuestItemLink = function(kind, index)
                    if kind == "reward" and index == 1 then
                        return "|Hitem:33:0|h[Reward]|h"
                    end
                    if kind == "choice" and index == 1 then return linkA end
                end,
                getNumQuestChoices = function() return 1 end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link:find("item:33", 1, true) then return 5 end
                    if link == linkA then return 10 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkA, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("does not alert on guaranteed rewards when choices exist", function()
            local linkReward = "|Hitem:33:0|h[Guaranteed]|h"
            loadWithMocks({
                getNumQuestRewards = function() return 1 end,
                getNumQuestChoices = function() return 2 end,
                getQuestItemLink = function(kind, index)
                    if kind == "reward" and index == 1 then return linkReward end
                    if kind == "choice" and index == 1 then return linkA end
                    if kind == "choice" and index == 2 then return linkB end
                end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkReward then return 100 end
                    if link == linkA then return 10 end
                    -- Below 5% of ScoreItem=100 baseline (3/97 ≈ 3.1%) so only linkA is clear
                    if link == linkB then return 3 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkA, 1, true))
            assert.is_nil(chatLines[1]:find(linkReward, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("does not announce when current-character notifications are disabled", function()
            loadWithMocks({ notifyCurrentCharacter = false })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(0, #chatLines)
        end)

        it("does not check other characters", function()
            local ctx = loadWithMocks({ notifyOtherCharacters = true })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_false(ctx.evaluatedAllAlts())
        end)

        it("announces all clear quest reward upgrades with the best first", function()
            loadWithMocks()
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.matches("is the best upgrade for MageAlt:", chatLines[1])
            assert.is_not_nil(chatLines[2]:find(linkA, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[2])
        end)

        it("uses standard upgrade wording for a single clear quest reward", function()
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkB end
                end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkB then return 50 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
            assert.is_nil(chatLines[1]:match("is the best upgrade"))
        end)

        it("announces a clear upgrade when the reward meets the equipped threshold", function()
            -- ScoreItem=100 ⇒ oldTotal = 100 - delta. 15/85 ≈ 17.6% clear; 3/97 ≈ 3.1% minor.
            loadWithMocks({
                upgradeThresholdPercent = 5,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 3 end
                    if link == linkB then return 15 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("announces a minor upgrade for the best positive reward below threshold", function()
            -- 4/96 ≈ 4.2% and 3/97 ≈ 3.1% both below 5% → announce best as minor.
            loadWithMocks({
                upgradeThresholdPercent = 5,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 4 end
                    if link == linkB then return 3 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkA, 1, true))
            assert.matches("is a minor upgrade for MageAlt:", chatLines[1])
        end)

        it("announces when no equippable quest rewards are upgrades for the current character", function()
            loadWithMocks({
                evaluateForCharacter = function() return false end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return -5 end
                    if link == linkB then return -2 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.matches("None of these rewards are an upgrade for MageAlt", chatLines[1])
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkB))
        end)

        it("skips quest reward checks when no rewards are equippable", function()
            loadWithMocks({
                getInventorySlotsForItem = function() return {} end,
                isEquippableWithin = function() return false end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(0, #chatLines)
        end)

        it("only evaluates equippable quest rewards", function()
            loadWithMocks({
                getNumQuestChoices = function() return 2 end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 100 end
                    if link == linkB then return 5 end
                    return 0
                end,
                getInventorySlotsForItem = function(link)
                    if link == linkB then return { 1 } end
                    return {}
                end,
                isEquippableWithin = function(_, _, link)
                    return link == linkB, 0, nil
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.is_nil(chatLines[1]:find(linkA, 1, true))
        end)

        it("skips quest rewards whose armor proficiency is not trained yet", function()
            loadWithMocks({
                getNumQuestChoices = function() return 2 end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 100 end
                    if link == linkB then return 5 end
                    return 0
                end,
                lacksTrainedProficiency = function(_, link) return link == linkA end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.is_nil(chatLines[1]:find(linkA, 1, true))
        end)

        it("suppresses duplicate loot announcements for announced quest rewards", function()
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkA end
                end,
                evaluateForCharacter = function(_, link)
                    return link == linkA
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            local ok = GA.AnnounceLootUpgrade(linkA)
            assert.is_false(ok)
            assert.are.equal(1, #chatLines)
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
        end)

        it("keeps suppressing loot until consumed, regardless of elapsed time", function()
            local mockTime = 1000
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkA end
                end,
                getTime = function() return mockTime end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            -- A large time jump must not expire the flag: suppression no longer uses a TTL.
            mockTime = 100000
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            local ok = GA.AnnounceLootUpgrade(linkA)
            assert.is_false(ok)
            assert.are.equal(1, #chatLines)
            -- The flag is consumed by the suppressed loot, so a later drop announces again.
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
        end)

        it("clears all suppressions when entering the world", function()
            loadWithMocks({
                getNumQuestChoices = function() return 2 end,
                notifyOtherCharacters = false,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkB))
            GA.ClearQuestLootUpgradeSuppression()
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkB))
            local ok = GA.AnnounceLootUpgrade(linkB)
            assert.is_true(ok)
            assert.are.equal(3, #chatLines)
        end)

        it("debounces rapid duplicate quest reward announcements", function()
            loadWithMocks()
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
        end)

        it("announces quest rewards again after debounce expires", function()
            local mockTime = 1000
            loadWithMocks({
                getTime = function() return mockTime end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            mockTime = 1002
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(4, #chatLines)
        end)
    end)

    describe("FormatQuestRewardMessages", function()
        it("formats minor, best, and no-upgrade quest messages", function()
            assert.matches("is a minor upgrade for Bravo:", GA.FormatQuestMinorUpgradeMessage(
                "|Hitem:11:0|h[New Helm]|h", "Bravo", "[View details]"))
            assert.matches("is the best upgrade for Bravo:", GA.FormatQuestBestUpgradeMessage(
                "|Hitem:11:0|h[New Helm]|h", "Bravo", "[View details]"))
            assert.are.equal(
                "None of these rewards are an upgrade for MageAlt",
                GA.FormatQuestNoUpgradeMessage("MageAlt"))
        end)

        it("FormatLootUpgradeMessage resets item link color before plain text", function()
            local coloredLink = "|cffa335ee|Hitem:11:0|h[Epic Helm]|h"
            local msg = GA.FormatLootUpgradeMessage(coloredLink, "MageAlt", "[View details]")
            assert.matches("|r is an upgrade for MageAlt:", msg)
        end)
    end)

    describe("FormatLevelUpEquipMessage", function()
        local helmLink = "|Hitem:11:0|h[New Helm]|h"
        local chestLink = "|Hitem:22:0|h[New Chest]|h"
        local bootsLink = "|Hitem:33:0|h[New Boots]|h"
        local glovesLink = "|Hitem:44:0|h[New Gloves]|h"

        it("adds location reminders only for bank or mail", function()
            assert.are.equal(
                "Congratulations! You can now equip " .. helmLink,
                GA.FormatLevelUpEquipMessage({ { link = helmLink, bag = true } }))
            assert.are.equal(
                "Congratulations! You can now equip " .. helmLink .. " (bank)",
                GA.FormatLevelUpEquipMessage({ { link = helmLink, bank = true } }))
            assert.are.equal(
                "Congratulations! You can now equip " .. helmLink,
                GA.FormatLevelUpEquipMessage({ { link = helmLink, bag = true, bank = true } }))
            assert.are.equal(
                "Congratulations! You can now equip " .. helmLink .. " (mail)",
                GA.FormatLevelUpEquipMessage({ { link = helmLink, mail = true } }))
            assert.are.equal(
                "Congratulations! You can now equip " .. helmLink .. " (mail)",
                GA.FormatLevelUpEquipMessage({ { link = helmLink, bank = true, mail = true } }))
        end)

        it("joins two upgrades with and", function()
            assert.are.equal(
                "Congratulations! You can now equip "
                    .. helmLink .. " and " .. chestLink,
                GA.FormatLevelUpEquipMessage({
                    { link = helmLink, bag = true },
                    { link = chestLink, bag = true },
                }))
        end)

        it("summarizes three or more upgrades", function()
            assert.are.equal(
                "Congratulations! You can now equip "
                    .. helmLink .. ", " .. chestLink .. ", and 1 other upgrade",
                GA.FormatLevelUpEquipMessage({
                    { link = helmLink, bag = true },
                    { link = chestLink, bag = true },
                    { link = bootsLink, bag = true },
                }))
            assert.are.equal(
                "Congratulations! You can now equip "
                    .. helmLink .. ", " .. chestLink .. ", and 2 other upgrades",
                GA.FormatLevelUpEquipMessage({
                    { link = helmLink, bag = true },
                    { link = chestLink, bag = true },
                    { link = bootsLink, bag = true },
                    { link = glovesLink, bag = true },
                }))
        end)
    end)

    describe("FormatLevelUpConsumeMessage", function()
        local potionLink = "|Hitem:118:0|h[Minor Healing Potion]|h"
        local elixirLink = "|Hitem:2454:0|h[Elixir of Lion's Strength]|h"
        local scrollLink = "|Hitem:954:0|h[Scroll of Strength]|h"

        it("labels non-inventory sources in parentheses", function()
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink .. " (bank)",
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, bank = true } }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink .. " (mail)",
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, mail = true } }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink .. " (bank, mail)",
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, bank = true, mail = true } }))
        end)

        it("omits source labels when the item is in bags", function()
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink,
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, bag = true } }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink,
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, bag = true, bank = true } }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink,
                GA.FormatLevelUpConsumeMessage({ { link = potionLink, bag = true, mail = true } }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink,
                GA.FormatLevelUpConsumeMessage({
                    { link = potionLink, bag = true, bank = true, mail = true },
                }))
        end)

        it("shows the same item once when sources use different item links", function()
            local bagLink = "|cff1eff00|Hitem:118:0:0:0:0:0:0:0|h[Minor Healing Potion]|h|r"
            local mailLink = "|Hitem:118:0|h[Minor Healing Potion]|h"
            assert.are.equal(
                "Congratulations! You can now consume " .. bagLink,
                GA.FormatLevelUpConsumeMessage({
                    { link = bagLink, bag = true },
                    { link = mailLink, mail = true },
                }))
            assert.are.equal(
                "Congratulations! You can now consume " .. potionLink .. " (bank, mail)",
                GA.FormatLevelUpConsumeMessage({
                    { link = potionLink, bank = true },
                    { link = mailLink, mail = true },
                }))
        end)

        it("joins two consumables with and", function()
            assert.are.equal(
                "Congratulations! You can now consume "
                    .. potionLink .. " (bank) and " .. elixirLink .. " (mail)",
                GA.FormatLevelUpConsumeMessage({
                    { link = potionLink, bank = true },
                    { link = elixirLink, mail = true },
                }))
        end)

        it("lists three or more consumables with commas and a final and", function()
            assert.are.equal(
                "Congratulations! You can now consume "
                    .. potionLink .. " (bank), "
                    .. elixirLink .. " (mail), and "
                    .. scrollLink .. " (bank, mail)",
                GA.FormatLevelUpConsumeMessage({
                    { link = potionLink, bank = true },
                    { link = elixirLink, mail = true },
                    { link = scrollLink, bank = true, mail = true },
                }))
        end)

        it("returns empty string for no candidates", function()
            assert.are.equal("", GA.FormatLevelUpConsumeMessage({}))
            assert.are.equal("", GA.FormatLevelUpConsumeMessage(nil))
        end)
    end)
end)
