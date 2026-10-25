-- AltArmy TBC — the Inventory tab's layout model: turns a stored character record (DataStore containers
-- and mail) into the blocks, grids and inbox rows the tab draws. No WoW API and no frames: bag names
-- and icons come from the caller (opts.resolveBag), which container is which from DataStore's bag
-- roles (opts.ids = DS:GetBagRoles()), and slot counts for data saved before containers v3 are
-- estimated here (ResolveNumSlots).

if not AltArmy then return end

AltArmy.InventoryLayout = AltArmy.InventoryLayout or {}
local IL = AltArmy.InventoryLayout

IL.CONST = {
    DEFAULT_BACKPACK_SLOTS = 16,
    DEFAULT_BANK_SLOTS = 28, -- TBC Anniversary's NUM_BANKGENERIC_SLOTS; the tab passes the client's live value
    KEYRING_COLUMNS = 4, -- the keyring grows by rows of four, so an estimate rounds up to one
    -- Stock ContainerFrame geometry: 37 px slots on a 42 px pitch.
    SLOT = 37,
    SPACING = 5,
    BLOCK_COLUMNS = 5, -- every block of the per-bag layout at the stock width, bank and keyring included
    BLOCK_COLUMN_CHOICES = { 5, 6 }, -- a wider window may give the blocks 6 (BlockArrangement)
    MAIL_ATTACHMENTS_MAX = 12,
}
local C = IL.CONST

IL.DEFAULT_NAMES = {
    backpack = "Backpack", bank = "Bank", keyring = "Keyring", reagentbag = "Reagent Bag", bag = "Bag %d",
    bankbag = "Bank Bag %d",
}

-- Which stored container id plays which role: DataStore's bag roles (DS:GetBagRoles(), the table
-- DS._BuildBagRoles makes: backpack, bags, reagentBag, keyring, bank, bankBags, bankBagName,
-- firstBankBagName, bagSet, bankBagSet), passed as opts.ids. Without one the loaded DataStore's roles
-- are used, so the two never disagree.
local function defaultIds()
    local DS = AltArmy.DataStore
    return DS and DS.GetBagRoles and DS:GetBagRoles() or nil
end

local function indexOf(list, value)
    for i, v in ipairs(list or {}) do
        if v == value then return i end
    end
    return nil
end

--- The role a container id plays under a roles table: "backpack", "bag", "reagentbag", "keyring",
--- "bank", "bankbag" or nil (the same answers as DS:GetBagRole for the running client's roles).
local function kindOf(bagID, ids)
    ids = ids or defaultIds()
    if not ids or type(bagID) ~= "number" then return nil end
    if bagID == ids.backpack then return "backpack" end
    if ids.reagentBag ~= nil and bagID == ids.reagentBag then return "reagentbag" end
    if (ids.bagSet and ids.bagSet[bagID]) or indexOf(ids.bags, bagID) then return "bag" end
    if ids.keyring ~= nil and bagID == ids.keyring then return "keyring" end
    if ids.bank ~= nil and bagID == ids.bank then return "bank" end
    if (ids.bankBagSet and ids.bankBagSet[bagID]) or indexOf(ids.bankBags, bagID) then return "bankbag" end
    return nil
end
IL.KindOf = kindOf

local function maxUsedSlot(bag)
    local maxUsed = 0
    for slot, data in pairs(bag and bag.items or {}) do
        local n = tonumber(slot)
        if n and data and n > maxUsed then
            maxUsed = n
        end
    end
    return maxUsed
end

--- Slot count for one stored container. `defaults` = { backpack = n, bank = n } (the client's live
--- sizes, read by the tab). Returns the count and whether it is an estimate (data saved before
--- containers v3 has no numSlots: the highest used slot, raised to the default size for the backpack
--- and the main bank, rounded up to whole rows for the keyring).
function IL.ResolveNumSlots(bagID, bag, defaults, ids)
    defaults = defaults or {}
    local used = maxUsedSlot(bag)
    local stored = bag and bag.numSlots
    if type(stored) == "number" and stored >= 0 then
        return math.max(stored, used), false
    end
    local kind = kindOf(bagID, ids)
    if kind == "backpack" then
        return math.max(used, defaults.backpack or C.DEFAULT_BACKPACK_SLOTS), true
    elseif kind == "bank" then
        return math.max(used, defaults.bank or C.DEFAULT_BANK_SLOTS), true
    elseif kind == "keyring" then
        return math.ceil(used / C.KEYRING_COLUMNS) * C.KEYRING_COLUMNS, true
    end
    return used, true
end

local function defaultName(kind, bagID, ids)
    local fmt = IL.DEFAULT_NAMES[kind] or "Bag"
    if kind == "bag" then return string.format(fmt, indexOf(ids.bags, bagID) or bagID) end
    if kind == "bankbag" then
        local index = indexOf(ids.bankBags, bagID)
        if index == 1 and ids.firstBankBagName then return ids.firstBankBagName end
        return string.format(ids.bankBagName or fmt, index or bagID)
    end
    return fmt
end

--- Build one block per bag id, in the order given. A block: { bagID, kind, name, icon, numSlots,
--- sizeIsEstimate, used, bagItemID, bagLink, slots[slot] = { slot, itemID, count, link } }.
--- The backpack and the main bank always appear (even unscanned); an equippable bag slot appears when a
--- bag is recorded there (identity, contents or a size); the keyring only when it holds a key.
--- opts.ids (IdsForClient; Classic by default), opts.defaults as for ResolveNumSlots;
--- opts.resolveBag(block) -> name, icon may override both.
function IL.BuildBlocks(char, bagIDs, opts)
    opts = opts or {}
    local ids = opts.ids or defaultIds() or {}
    local containers = char and char.Containers or {}
    local blocks = {}
    for _, bagID in ipairs(bagIDs) do
        local kind = kindOf(bagID, ids)
        local bag = containers[bagID]
        local numSlots, estimate = IL.ResolveNumSlots(bagID, bag, opts.defaults, ids)
        local present
        if kind == "backpack" or kind == "bank" then
            present = true
        elseif kind == "keyring" then
            present = maxUsedSlot(bag) > 0
        else
            present = bag ~= nil and (bag.bagItemID ~= nil or numSlots > 0)
        end
        if present then
            -- Forever's built-in first bank tab holds a placeholder item, "Character Bank Tab Bag (DNT)":
            -- DataStore no longer records it, but a bank scanned by an older addon may still carry it.
            local builtIn = kind == "bankbag" and ids.firstBankBagName ~= nil and indexOf(ids.bankBags, bagID) == 1
            local block = {
                bagID = bagID,
                kind = kind,
                numSlots = numSlots,
                sizeIsEstimate = estimate,
                used = 0,
                bagItemID = not builtIn and bag and bag.bagItemID or nil,
                bagLink = not builtIn and bag and bag.bagLink or nil,
                slots = {},
            }
            for slot = 1, numSlots do
                local data = bag and bag.items and bag.items[slot]
                if data and data.itemID then
                    block.slots[slot] = {
                        slot = slot,
                        itemID = data.itemID,
                        count = data.count or 1,
                        link = bag.links and bag.links[slot] or nil,
                    }
                    block.used = block.used + 1
                end
            end
            local name, icon
            if opts.resolveBag then
                name, icon = opts.resolveBag(block)
            end
            block.name = name or defaultName(kind, bagID, ids)
            block.icon = icon
            blocks[#blocks + 1] = block
        end
    end
    return blocks
end

--- The Bags view: backpack, the bags, then the keyring (opts.includeKeyring ~= false).
function IL.BagsBlocks(char, opts)
    opts = opts or {}
    local ids = opts.ids or defaultIds()
    if not ids then return {} end
    opts.ids = ids
    local list = { ids.backpack }
    for _, bagID in ipairs(ids.bags) do list[#list + 1] = bagID end
    if opts.includeKeyring ~= false and ids.keyring ~= nil then
        list[#list + 1] = ids.keyring
    end
    return IL.BuildBlocks(char, list, opts)
end

--- The Bank view: the main bank (where the client has one), then the bank bags. nil until the
--- character's bank was scanned once (no bank container stored).
function IL.BankBlocks(char, opts)
    opts = opts or {}
    local ids = opts.ids or defaultIds()
    local containers = char and char.Containers
    if not containers or not ids then return nil end
    opts.ids = ids
    local list = {}
    if ids.bank ~= nil then list[#list + 1] = ids.bank end
    for _, bagID in ipairs(ids.bankBags) do list[#list + 1] = bagID end
    local scanned = false
    for _, bagID in ipairs(list) do
        if containers[bagID] then scanned = true end
    end
    if not scanned then return nil end
    return IL.BuildBlocks(char, list, opts)
end

--- The combined layout of a block list: every slot in block order (empty ones as { bagID, slot }), the
--- bag bar (one entry per block) and the totals.
function IL.Combined(blocks)
    local out = { slots = {}, bagBar = {}, totalSlots = 0, usedSlots = 0 }
    for _, block in ipairs(blocks or {}) do
        out.bagBar[#out.bagBar + 1] = {
            bagID = block.bagID,
            kind = block.kind,
            name = block.name,
            icon = block.icon,
            itemID = block.bagItemID,
            link = block.bagLink,
            numSlots = block.numSlots,
            used = block.used,
        }
        for slot = 1, block.numSlots do
            local entry = block.slots[slot]
            if entry then
                entry.bagID = block.bagID
            else
                entry = { bagID = block.bagID, slot = slot }
            end
            out.slots[#out.slots + 1] = entry
        end
        out.totalSlots = out.totalSlots + block.numSlots
        out.usedSlots = out.usedSlots + block.used
    end
    return out
end

-- DataStore owns the expiry arithmetic (DS.MailRowDaysLeft, as GetMailInfo uses).
local function daysLeftNow(row, now)
    local DS = AltArmy.DataStore
    if not DS or not DS.MailRowDaysLeft then return nil end
    return DS.MailRowDaysLeft(row, now)
end

--- How the inbox marks a message: "returned" when the game marked it returned (a return predicted
--- from the hook too), "sent" when it was predicted from a send, nil otherwise.
function IL.MessageMark(msg)
    if not msg then return nil end
    if msg.returned then return "returned" end
    if msg.predicted then return "sent" end
    return nil
end

--- Inbox messages from char.Mails (scanned) then char.MailCache (predicted from sends and returns),
--- grouped by mailIndex (mail v2); a row without one is a message of its own. A message:
--- { index, sender, subject, returned, predicted, money, daysLeft (remaining now, like DS:GetMailInfo),
---   items = { { itemID, count, link, icon }, ... } }, in inbox order.
function IL.MailMessages(char, now)
    now = now or 0
    local messages = {}
    local function consume(rows, predicted)
        local byIndex = {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                local idx = row.mailIndex
                local msg = idx ~= nil and byIndex[idx] or nil
                if not msg then
                    msg = {
                        index = idx,
                        sender = row.sender,
                        subject = row.subject,
                        returned = row.returned and true or false,
                        predicted = predicted,
                        money = 0,
                        daysLeft = nil,
                        items = {},
                    }
                    messages[#messages + 1] = msg
                    if idx ~= nil then byIndex[idx] = msg end
                end
                if type(row.money) == "number" and row.money > 0 then
                    msg.money = msg.money + row.money
                end
                if row.itemID then
                    msg.items[#msg.items + 1] = {
                        itemID = row.itemID,
                        count = row.count or 1,
                        link = row.link,
                        icon = row.icon,
                    }
                end
                local left = daysLeftNow(row, now)
                if left and (msg.daysLeft == nil or left < msg.daysLeft) then
                    msg.daysLeft = left
                end
            end
        end
    end
    consume(char and char.Mails, false)
    consume(char and char.MailCache, true)
    return messages
end

IL.MAIL_URGENT_DAYS = 3 -- red below this
IL.MAIL_SOON_DAYS = 7 -- yellow below this

--- A message's remaining time as the inbox shows it, and how urgent it is: "ok", "soon" or "urgent".
--- nil days (no expiry recorded) gives "", "ok".
function IL.FormatDaysLeft(days)
    if type(days) ~= "number" then return "", "ok" end
    local level = "ok"
    if days < IL.MAIL_URGENT_DAYS then
        level = "urgent"
    elseif days < IL.MAIL_SOON_DAYS then
        level = "soon"
    end
    if days <= 0 then return "Expired", level end
    if days < 1 then
        local hours = math.max(1, math.floor(days * 24))
        return hours == 1 and "1 hour" or (hours .. " hours"), level
    end
    local whole = math.floor(days)
    return whole == 1 and "1 day" or (whole .. " days"), level
end

local function lowerText(s)
    return type(s) == "string" and s:lower() or ""
end

--- Sort a message list in place by "subject" / "sender" (A-Z when ascending), "money" or "expires"
--- (smallest first when ascending; messages without an expiry go last either way). Ties keep the
--- inbox order. Any other key leaves the inbox order.
function IL.SortMessages(messages, key, ascending)
    if not messages or not (key == "subject" or key == "sender" or key == "money" or key == "expires") then
        return messages
    end
    local order = {}
    for i, msg in ipairs(messages) do order[msg] = i end
    local function value(msg)
        if key == "subject" then return lowerText(msg.subject) end
        if key == "sender" then return lowerText(msg.sender) end
        if key == "money" then return msg.money or 0 end
        return msg.daysLeft
    end
    table.sort(messages, function(a, b)
        local va, vb = value(a), value(b)
        if va == vb then return order[a] < order[b] end
        if va == nil then return false end
        if vb == nil then return true end
        if ascending then return va < vb end
        return va > vb
    end)
    return messages
end

--- The attachments of a message list as slot entries { slot, itemID, count, link, icon, message }.
function IL.MailGrid(messages)
    local slots = {}
    for _, msg in ipairs(messages or {}) do
        for _, item in ipairs(msg.items) do
            slots[#slots + 1] = {
                slot = #slots + 1,
                itemID = item.itemID,
                count = item.count,
                link = item.link,
                icon = item.icon,
                message = msg,
            }
        end
    end
    return slots
end

--- Used and total slots of a block list by group: "bags" (backpack and bags), "reagent" (the reagent
--- bag) and "keyring", as { used, total, icon } for the groups present, in that order. The icon is the
--- group's first block's.
IL.SLOT_GROUP_ORDER = { "bags", "reagent", "keyring" }

function IL.SlotGroups(blocks)
    local byKey = {}
    local function add(key, block)
        local g = byKey[key]
        if not g then
            g = { key = key, used = 0, total = 0, icon = block.icon }
            byKey[key] = g
        end
        g.used = g.used + block.used
        g.total = g.total + block.numSlots
    end
    for _, block in ipairs(blocks or {}) do
        if block.kind == "reagentbag" then
            add("reagent", block)
        elseif block.kind == "keyring" then
            add("keyring", block)
        else
            add("bags", block)
        end
    end
    local groups = {}
    for _, key in ipairs(IL.SLOT_GROUP_ORDER) do
        if byKey[key] then groups[#groups + 1] = byKey[key] end
    end
    return groups
end

--- Columns that fit `width` at a slot size and spacing, between 1 and maxColumns.
function IL.ColumnsForWidth(width, slot, spacing, maxColumns)
    slot = slot or C.SLOT
    spacing = spacing or C.SPACING
    local columns = math.floor(((width or 0) + spacing) / (slot + spacing))
    if maxColumns and columns > maxColumns then columns = maxColumns end
    if columns < 1 then columns = 1 end
    return columns
end

--- How the per-bag layout fits a row `width` wide: every bag is a block of 5 or 6 columns
--- (C.BLOCK_COLUMN_CHOICES), and the arrangement that shows the most slot columns a row wins (more bags a
--- row on a tie), so a wider window goes from three 5-column bags to three 6-column ones, then to four
--- 5-column ones. What the row has beyond its blocks and their smallest gap (minGap) is spread between
--- the bags. Returns { perRow, columns, blockWidth, gap }; one 5-column bag a row when nothing fits.
function IL.BlockArrangement(width, slot, spacing, minGap)
    slot = slot or C.SLOT
    spacing = spacing or C.SPACING
    minGap = minGap or spacing
    -- A frame not laid out yet can report an infinite or NaN width: with it every bag would get the same
    -- gap-less spot (infinite bags a row, a NaN gap). Treat it as no room.
    if type(width) ~= "number" or width ~= width or width == math.huge or width == -math.huge then
        width = 0
    end
    local best
    for _, columns in ipairs(C.BLOCK_COLUMN_CHOICES) do
        local blockWidth = columns * slot + (columns - 1) * spacing
        local perRow = math.floor((width + minGap) / (blockWidth + minGap))
        if perRow >= 1 then
            local cells = perRow * columns
            if not best or cells > best.cells or (cells == best.cells and perRow > best.perRow) then
                best = { perRow = perRow, columns = columns, blockWidth = blockWidth, cells = cells }
            end
        end
    end
    if not best then
        local columns = C.BLOCK_COLUMNS
        return { perRow = 1, columns = columns, blockWidth = columns * slot + (columns - 1) * spacing,
            gap = minGap }
    end
    local gap = minGap
    if best.perRow > 1 then
        local used = best.perRow * best.blockWidth + (best.perRow - 1) * minGap
        gap = minGap + math.floor((width - used) / (best.perRow - 1))
    end
    return { perRow = best.perRow, columns = best.columns, blockWidth = best.blockWidth, gap = gap }
end

--- Geometry for `n` cells: { columns, rows, width, height, pitch, x(i), y(i) } where x and y are the
--- cell's offsets (y downward, positive) from the grid's top-left, 1-based.
function IL.GridMetrics(n, slot, spacing, maxColumns)
    slot = slot or C.SLOT
    spacing = spacing or C.SPACING
    n = math.max(0, n or 0)
    local columns = math.min(n, maxColumns or C.BLOCK_COLUMNS)
    if columns < 1 then columns = 1 end
    local rows = math.ceil(n / columns)
    local pitch = slot + spacing
    local m = {
        columns = columns,
        rows = rows,
        pitch = pitch,
        width = columns * slot + (columns - 1) * spacing,
        height = rows > 0 and (rows * slot + (rows - 1) * spacing) or 0,
    }
    function m.x(i) return ((i - 1) % columns) * pitch end
    function m.y(i) return math.floor((i - 1) / columns) * pitch end
    return m
end
