--[[ Unit tests for InventoryLayout.lua (Inventory tab layout model) — run: npm test ]]

describe("InventoryLayout", function()
    local IL

    local DS, CLASSIC, FOREVER
    local FOREVER_ENUM = {
        Keyring = -1, Characterbanktab = -2, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4,
        ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11, CharacterBankTab_7 = 12,
        CharacterBankTab_8 = 13, CharacterBankTab_9 = 14,
    }

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        -- The roles and the mail expiry arithmetic come from DataStore.
        require("DataStore")
        require("DataStoreContainers")
        require("DataStoreMail")
        DS = AltArmy.DataStore
        CLASSIC = DS._BuildBagRoles(nil)
        FOREVER = DS._BuildBagRoles(FOREVER_ENUM)
        package.loaded["InventoryLayout"] = nil
        require("InventoryLayout")
        IL = AltArmy.InventoryLayout
        assert.truthy(IL)
    end)

    local function bag(items, extra)
        local b = { items = {}, links = {} }
        for slot, spec in pairs(items or {}) do
            b.items[slot] = { itemID = spec[1], count = spec[2] }
            if spec[3] then b.links[slot] = spec[3] end
        end
        for k, v in pairs(extra or {}) do b[k] = v end
        return b
    end

    describe("ResolveNumSlots", function()
        it("uses the stored count (containers v3)", function()
            local n, estimate = IL.ResolveNumSlots(1, bag({ [3] = { 1, 1 } }, { numSlots = 18 }))
            assert.are.equal(18, n)
            assert.is_false(estimate)
            assert.are.equal(0, (IL.ResolveNumSlots(2, bag({}, { numSlots = 0 }))))
        end)

        it("never shrinks a stored count below a used slot", function()
            assert.are.equal(9, (IL.ResolveNumSlots(1, bag({ [9] = { 1, 1 } }, { numSlots = 8 }))))
        end)

        it("estimates v2 data from the highest used slot and the client's defaults", function()
            local n, estimate = IL.ResolveNumSlots(0, bag({ [5] = { 1, 1 } }), { backpack = 16 })
            assert.are.equal(16, n)
            assert.is_true(estimate)
            assert.are.equal(20, (IL.ResolveNumSlots(0, bag({ [20] = { 1, 1 } }), { backpack = 16 })))
            assert.are.equal(24, (IL.ResolveNumSlots(-1, bag({}), { bank = 24 })))
            assert.are.equal(28, (IL.ResolveNumSlots(-1, nil)))
            assert.are.equal(16, (IL.ResolveNumSlots(0, nil)))
        end)

        it("estimates the keyring in rows of four and other bags by their contents", function()
            assert.are.equal(12, (IL.ResolveNumSlots(-2, bag({ [9] = { 1, 1 } }))))
            assert.are.equal(0, (IL.ResolveNumSlots(-2, bag({}))))
            assert.are.equal(7, (IL.ResolveNumSlots(3, bag({ [7] = { 1, 1 }, [2] = { 1, 1 } }))))
            assert.are.equal(0, (IL.ResolveNumSlots(5, nil)))
        end)
    end)

    describe("BagsBlocks", function()
        local char = {
            Containers = {
                [0] = bag({ [1] = { 100, 5, "link100" }, [16] = { 200, 1 } }, { numSlots = 16 }),
                [1] = bag({ [2] = { 300, 20 } }, { numSlots = 16, bagItemID = 21841, bagLink = "baglink" }),
                [2] = bag({}, { numSlots = 0 }), -- empty bag slot
                [4] = bag({}, { bagItemID = 4500, numSlots = 6 }), -- a bag with nothing in it
                [-2] = bag({ [1] = { 7, 1 } }, { numSlots = 12 }),
                [5] = bag({ [1] = { 1, 1 } }, { numSlots = 16 }), -- bank bag: not a Bags block
            },
        }

        it("lists the backpack, each equipped bag and the keyring in order", function()
            local blocks = IL.BagsBlocks(char)
            local ids = {}
            for i, b in ipairs(blocks) do ids[i] = b.bagID end
            assert.are.same({ 0, 1, 4, -2 }, ids)
            assert.are.same({ "backpack", "bag", "bag", "keyring" },
                { blocks[1].kind, blocks[2].kind, blocks[3].kind, blocks[4].kind })
        end)

        it("fills slots with item, count and link and counts the used ones", function()
            local bp = IL.BagsBlocks(char)[1]
            assert.are.equal(16, bp.numSlots)
            assert.is_false(bp.sizeIsEstimate)
            assert.are.equal(2, bp.used)
            assert.are.same({ slot = 1, itemID = 100, count = 5, link = "link100" }, bp.slots[1])
            assert.is_nil(bp.slots[2])
            assert.are.equal(200, bp.slots[16].itemID)
            assert.are.equal(1, bp.slots[16].count)
        end)

        it("carries the bag item's identity and default names", function()
            local blocks = IL.BagsBlocks(char)
            assert.are.equal("Backpack", blocks[1].name)
            assert.are.equal(21841, blocks[2].bagItemID)
            assert.are.equal("baglink", blocks[2].bagLink)
            assert.are.equal("Bag 1", blocks[2].name)
            assert.are.equal("Bag 4", blocks[3].name)
            assert.are.equal(6, blocks[3].numSlots)
            assert.are.equal("Keyring", blocks[4].name)
        end)

        it("lets the caller name the bags and pick their icons", function()
            local blocks = IL.BagsBlocks(char, {
                resolveBag = function(block)
                    if block.bagItemID then return "Netherweave Bag", "icon" .. block.bagItemID end
                    return nil, "default-icon"
                end,
            })
            assert.are.equal("Backpack", blocks[1].name)
            assert.are.equal("default-icon", blocks[1].icon)
            assert.are.equal("Netherweave Bag", blocks[2].name)
            assert.are.equal("icon21841", blocks[2].icon)
        end)

        it("always shows the backpack, estimated for unscanned characters", function()
            local blocks = IL.BagsBlocks({ }, { defaults = { backpack = 16 }, includeKeyring = true })
            assert.are.equal(1, #blocks)
            assert.are.equal(16, blocks[1].numSlots)
            assert.is_true(blocks[1].sizeIsEstimate)
            assert.are.equal(0, blocks[1].used)
        end)

        it("hides an empty keyring", function()
            local blocks = IL.BagsBlocks({ Containers = {
                [0] = bag({}, { numSlots = 16 }),
                [-2] = bag({}, { numSlots = 12 }),
            } })
            assert.are.equal(1, #blocks)
            assert.are.equal("backpack", blocks[1].kind)
        end)

        it("can leave the keyring out", function()
            assert.are.equal(3, #IL.BagsBlocks(char, { includeKeyring = false }))
        end)
    end)

    describe("BankBlocks", function()
        it("is nil until the bank was scanned", function()
            assert.is_nil(IL.BankBlocks({ Containers = { [0] = bag({}) } }))
            assert.is_nil(IL.BankBlocks({ Containers = { [0] = bag({}) } }, { ids = FOREVER }))
            assert.is_nil(IL.BankBlocks(nil))
        end)

        it("lists the main bank then the bank bags", function()
            local char = { Containers = {
                [-1] = bag({ [3] = { 9, 2 } }, { numSlots = 24 }),
                [6] = bag({}, { bagItemID = 21841, numSlots = 16 }),
                [1] = bag({ [1] = { 1, 1 } }, { numSlots = 16 }),
            } }
            local blocks = IL.BankBlocks(char)
            assert.are.equal(2, #blocks)
            assert.are.same({ -1, 6 }, { blocks[1].bagID, blocks[2].bagID })
            assert.are.same({ "bank", "bankbag" }, { blocks[1].kind, blocks[2].kind })
            assert.are.equal("Bank Bag 2", blocks[2].name)
        end)
    end)

    describe("WoW Forever ids", function()
        -- What DataStore stores on Forever: -1 is the keyring, bags 5-11 are the bank (no main bank).
        local char = { Containers = {
            [0] = bag({ [20] = { 1, 1 } }, { numSlots = 20 }),
            [1] = bag({}, { numSlots = 6, bagItemID = 5572 }),
            [-1] = bag({ [2] = { 7, 1 } }, { numSlots = 12 }),
            [5] = bag({ [1] = { 9, 1 } }, { numSlots = 1, bagItemID = 277114 }),
            [6] = bag({ [48] = { 8, 1 } }, { numSlots = 48, bagItemID = 242709 }),
        } }

        it("shows -1 as the keyring and bag 5 as the reagent bag in Bags, and tabs with no main bank in Bank", function()
            local bags = IL.BagsBlocks(char, { ids = FOREVER })
            assert.are.same({ 0, 1, 5, -1 }, { bags[1].bagID, bags[2].bagID, bags[3].bagID, bags[4].bagID })
            assert.are.equal("reagentbag", bags[3].kind)
            assert.are.equal("Reagent Bag", bags[3].name)
            assert.are.equal("keyring", bags[4].kind)
            assert.are.equal(12, bags[4].numSlots)
            local bank = IL.BankBlocks(char, { ids = FOREVER })
            assert.are.equal(1, #bank)
            assert.are.equal(6, bank[1].bagID)
            assert.are.equal("bankbag", bank[1].kind)
            assert.are.equal("Bank Bag", bank[1].name) -- the built-in bank; later tabs are "Bank Tab N"
            assert.are.equal(48, bank[1].numSlots)
        end)

        it("ignores the placeholder item an older addon recorded in the built-in bank tab", function()
            local bank = IL.BankBlocks(char, {
                ids = FOREVER,
                resolveBag = function(block)
                    if block.bagItemID then return "Character Bank Tab Bag (DNT)" end
                    return nil
                end,
            })
            assert.is_nil(bank[1].bagItemID)
            assert.is_nil(bank[1].bagLink)
            assert.are.equal("Bank Bag", bank[1].name)
        end)

        it("KindOf follows the roles table and agrees with DS:GetBagRole", function()
            assert.are.equal("bank", IL.KindOf(-1))
            assert.are.equal("keyring", IL.KindOf(-1, FOREVER))
            assert.is_nil(IL.KindOf(-2, FOREVER))
            assert.are.equal("keyring", IL.KindOf(-2, CLASSIC))
            assert.are.equal("reagentbag", IL.KindOf(5, FOREVER))
            assert.are.equal("bankbag", IL.KindOf(14, FOREVER))
            assert.is_nil(IL.KindOf(12))
            assert.is_nil(IL.KindOf("x"))
            for _, roles in ipairs({ CLASSIC, FOREVER }) do
                DS.RebuildBagRoles(roles.retail and FOREVER_ENUM or nil)
                for bagID = -3, 16 do
                    assert.are.equal(DS:GetBagRole(bagID), IL.KindOf(bagID, roles), "bag " .. bagID)
                end
            end
            DS.RebuildBagRoles(nil)
        end)

        it("uses the loaded DataStore's roles when none are passed", function()
            local char = { Containers = { [0] = bag({}, { numSlots = 16 }), [-2] = bag({ [1] = { 1, 1 } }) } }
            local blocks = IL.BagsBlocks(char)
            assert.are.equal("keyring", blocks[#blocks].kind)
        end)

        it("estimates v2 data under the Forever map too", function()
            local n, estimate = IL.ResolveNumSlots(-1, bag({ [5] = { 1, 1 } }), {}, FOREVER)
            assert.are.equal(8, n)
            assert.is_true(estimate)
        end)
    end)

    describe("Combined", function()
        it("flattens blocks into one slot list with empty entries and a bag bar", function()
            local blocks = IL.BagsBlocks({ Containers = {
                [0] = bag({ [2] = { 100, 1 } }, { numSlots = 3 }),
                [1] = bag({ [1] = { 200, 4 } }, { numSlots = 2, bagItemID = 5, bagLink = "L" }),
            } }, { includeKeyring = false })
            local c = IL.Combined(blocks)
            assert.are.equal(5, c.totalSlots)
            assert.are.equal(2, c.usedSlots)
            assert.are.equal(5, #c.slots)
            assert.are.same({ bagID = 0, slot = 1 }, c.slots[1])
            assert.are.equal(100, c.slots[2].itemID)
            assert.are.equal(0, c.slots[2].bagID)
            assert.are.equal(200, c.slots[4].itemID)
            assert.are.equal(1, c.slots[4].bagID)
            assert.are.equal(2, #c.bagBar)
            assert.are.equal("Backpack", c.bagBar[1].name)
            assert.are.equal(5, c.bagBar[2].itemID)
            assert.are.equal("L", c.bagBar[2].link)
            assert.are.equal(2, c.bagBar[2].numSlots)
        end)

        it("is empty for no blocks", function()
            local c = IL.Combined(nil)
            assert.are.equal(0, c.totalSlots)
            assert.are.same({}, c.slots)
        end)
    end)

    describe("MailMessages", function()
        local DAY = 86400
        local char = {
            Mails = {
                { mailIndex = 1, itemID = 10, count = 2, link = "l10", icon = "i10", sender = "Alice",
                    subject = "Mats", money = 0, lastCheck = 1000, daysLeft = 10, returned = false },
                { mailIndex = 1, itemID = 11, count = 1, icon = "i11", sender = "Alice",
                    subject = "Mats", money = 0, lastCheck = 1000, daysLeft = 10, returned = false },
                { mailIndex = 1, money = 1500, sender = "Alice", subject = "Mats", lastCheck = 1000,
                    daysLeft = 10, returned = false },
                { mailIndex = 2, money = 50, sender = "Bob", subject = "Gold", lastCheck = 1000,
                    daysLeft = 3, returned = true },
                { itemID = 12, count = 1, sender = "Old", subject = "v1 row", lastCheck = 1000, daysLeft = 5 },
            },
            MailCache = {
                { mailIndex = -1, itemID = 20, count = 3, sender = "Me", subject = "Sent", money = 0,
                    lastCheck = 1000, daysLeft = 30 },
                { mailIndex = -1, money = 700, sender = "Me", subject = "Sent", lastCheck = 1000, daysLeft = 30 },
                { mailIndex = -2, itemID = 21, count = 1, sender = "Me", subject = "Back", money = 0,
                    lastCheck = 1000, daysLeft = 30, returned = true },
            },
        }

        it("groups rows by message in inbox order, scanned before predicted", function()
            local msgs = IL.MailMessages(char, 1000)
            assert.are.equal(5, #msgs)
            assert.are.same({ 1, 2, nil, -1, -2 },
                { msgs[1].index, msgs[2].index, msgs[3].index, msgs[4].index, msgs[5].index })
            assert.are.equal("Alice", msgs[1].sender)
            assert.are.equal("Mats", msgs[1].subject)
            assert.are.equal(2, #msgs[1].items)
            assert.are.same({ itemID = 10, count = 2, link = "l10", icon = "i10" }, msgs[1].items[1])
            assert.are.equal(1500, msgs[1].money)
            assert.is_false(msgs[1].predicted)
            assert.is_true(msgs[2].returned)
            assert.are.equal(50, msgs[2].money)
            assert.are.equal(0, #msgs[2].items)
            assert.are.equal(12, msgs[3].items[1].itemID)
            assert.is_true(msgs[4].predicted)
            assert.are.equal(700, msgs[4].money)
            assert.are.equal(20, msgs[4].items[1].itemID)
            -- a return predicted from the ReturnInboxItem hook: predicted and returned
            assert.is_true(msgs[5].predicted)
            assert.is_true(msgs[5].returned)
            assert.are.equal("returned", IL.MessageMark(msgs[5]))
            assert.are.equal("sent", IL.MessageMark(msgs[4]))
        end)

        it("adjusts days left by the time since the scan, keeping the soonest row", function()
            local msgs = IL.MailMessages(char, 1000 + 2 * DAY)
            assert.are.equal(8, msgs[1].daysLeft)
            assert.are.equal(1, msgs[2].daysLeft)
            assert.are.equal(28, msgs[4].daysLeft)
        end)

        it("takes the remaining days from DataStore's arithmetic", function()
            local m = IL.MailMessages({ Mails = { { daysLeft = 10, lastCheck = 0 } } }, 2 * 86400)
            assert.are.equal(8, m[1].daysLeft)
        end)

        it("is empty without mail", function()
            assert.are.same({}, IL.MailMessages(nil, 0))
            assert.are.same({}, IL.MailMessages({ Mails = {} }, 0))
        end)
    end)

    describe("MessageMark", function()
        it("prefers returned over sent", function()
            assert.are.equal("returned", IL.MessageMark({ returned = true, predicted = true }))
            assert.are.equal("returned", IL.MessageMark({ returned = true }))
            assert.are.equal("sent", IL.MessageMark({ predicted = true }))
            assert.is_nil(IL.MessageMark({}))
            assert.is_nil(IL.MessageMark(nil))
        end)
    end)

    describe("FormatDaysLeft", function()
        it("shows whole days, hours under a day, and expired", function()
            assert.are.same({ "29 days", "ok" }, { IL.FormatDaysLeft(29.6) })
            assert.are.same({ "7 days", "ok" }, { IL.FormatDaysLeft(7.9) })
            assert.are.same({ "4 days", "soon" }, { IL.FormatDaysLeft(4.5) })
            assert.are.same({ "1 day", "urgent" }, { IL.FormatDaysLeft(1.9) })
            assert.are.same({ "5 hours", "urgent" }, { IL.FormatDaysLeft(5.5 / 24) })
            assert.are.same({ "1 hour", "urgent" }, { IL.FormatDaysLeft(0.01) })
            assert.are.same({ "Expired", "urgent" }, { IL.FormatDaysLeft(-0.5) })
            assert.are.same({ "", "ok" }, { IL.FormatDaysLeft(nil) })
        end)
    end)

    describe("SortMessages", function()
        local function msgs()
            return {
                { subject = "beta", sender = "Zed", money = 0, daysLeft = 5 },
                { subject = "Alpha", sender = "amy", money = 300, daysLeft = nil },
                { subject = "gamma", sender = "Bob", money = 100, daysLeft = 29 },
                { subject = "alpha", sender = "bob", money = 100, daysLeft = 2 },
            }
        end
        local function subjects(list)
            local out = {}
            for i, m in ipairs(list) do out[i] = m.subject end
            return out
        end

        it("sorts text columns case-insensitively, ties in inbox order", function()
            assert.are.same({ "Alpha", "alpha", "beta", "gamma" }, subjects(IL.SortMessages(msgs(), "subject", true)))
            assert.are.same({ "gamma", "beta", "Alpha", "alpha" }, subjects(IL.SortMessages(msgs(), "subject", false)))
            assert.are.same({ "Alpha", "gamma", "alpha", "beta" }, subjects(IL.SortMessages(msgs(), "sender", true)))
        end)

        it("sorts money and expiry as numbers, unknown expiry last either way", function()
            assert.are.same({ "Alpha", "gamma", "alpha", "beta" }, subjects(IL.SortMessages(msgs(), "money", false)))
            assert.are.same({ "beta", "gamma", "alpha", "Alpha" }, subjects(IL.SortMessages(msgs(), "money", true)))
            assert.are.same({ "alpha", "beta", "gamma", "Alpha" }, subjects(IL.SortMessages(msgs(), "expires", true)))
            assert.are.same({ "gamma", "beta", "alpha", "Alpha" }, subjects(IL.SortMessages(msgs(), "expires", false)))
        end)

        it("leaves the inbox order for an unknown key", function()
            assert.are.same({ "beta", "Alpha", "gamma", "alpha" }, subjects(IL.SortMessages(msgs(), "items", true)))
            assert.is_nil(IL.SortMessages(nil, "money", true))
        end)
    end)

    describe("MailGrid", function()
        it("lists every attachment as a numbered slot that knows its message", function()
            local msgs = {
                { items = { { itemID = 1, count = 1 }, { itemID = 2, count = 5, icon = "i" } } },
                { items = {} },
                { items = { { itemID = 3, count = 1 } } },
            }
            local slots = IL.MailGrid(msgs)
            assert.are.equal(3, #slots)
            assert.are.same({ 1, 2, 3 }, { slots[1].slot, slots[2].slot, slots[3].slot })
            assert.are.equal(2, slots[2].itemID)
            assert.are.equal("i", slots[2].icon)
            assert.are.equal(msgs[3], slots[3].message)
        end)
    end)

    describe("SlotGroups", function()
        it("sums bags, the reagent bag and the keyring apart, in that order, only when present", function()
            local groups = IL.SlotGroups({
                { kind = "backpack", used = 10, numSlots = 20, icon = "bp" },
                { kind = "keyring", used = 2, numSlots = 12, icon = "key" },
                { kind = "bag", used = 3, numSlots = 6, icon = "bag" },
                { kind = "reagentbag", used = 1, numSlots = 1, icon = "reagent" },
            })
            assert.are.equal(3, #groups)
            assert.are.same({ "bags", 13, 26, "bp" }, { groups[1].key, groups[1].used, groups[1].total, groups[1].icon })
            assert.are.same({ "reagent", 1, 1 }, { groups[2].key, groups[2].used, groups[2].total })
            assert.are.same({ "keyring", 2, 12 }, { groups[3].key, groups[3].used, groups[3].total })
            assert.are.equal(1, #IL.SlotGroups({ { kind = "backpack", used = 0, numSlots = 16 } }))
            assert.are.same({}, IL.SlotGroups(nil))
        end)
    end)


    describe("grid math", function()
        it("GridMetrics lays cells out left to right, top to bottom", function()
            local m = IL.GridMetrics(16, 37, 5, 4)
            assert.are.same({ 4, 4, 42 }, { m.columns, m.rows, m.pitch })
            assert.are.equal(4 * 37 + 3 * 5, m.width)
            assert.are.equal(4 * 37 + 3 * 5, m.height)
            assert.are.same({ 0, 0 }, { m.x(1), m.y(1) })
            assert.are.same({ 42 * 3, 0 }, { m.x(4), m.y(4) })
            assert.are.same({ 0, 42 }, { m.x(5), m.y(5) })
            assert.are.same({ 42 * 3, 42 * 3 }, { m.x(16), m.y(16) })
        end)

        it("GridMetrics uses fewer columns than the cap for small grids and none for zero", function()
            local m = IL.GridMetrics(3, 37, 5, 7)
            assert.are.same({ 3, 1 }, { m.columns, m.rows })
            local z = IL.GridMetrics(0, 37, 5, 7)
            assert.are.same({ 1, 0, 0 }, { z.columns, z.rows, z.height })
        end)

        it("ColumnsForWidth fits whole columns and clamps", function()
            assert.are.equal(10, IL.ColumnsForWidth(626, 37, 5, 10))
            assert.are.equal(15, IL.ColumnsForWidth(626, 37, 5)) -- 15 x 37 + 14 x 5 = 625
            assert.are.equal(2, IL.ColumnsForWidth(84, 37, 5, 10))
            assert.are.equal(1, IL.ColumnsForWidth(10, 37, 5, 10))
            assert.are.equal(1, IL.ColumnsForWidth(nil, 37, 5, 10))
        end)
    end)
end)
