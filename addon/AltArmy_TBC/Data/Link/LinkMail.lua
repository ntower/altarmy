-- AltArmy TBC — Mail sent to a linked account's character (linked accounts).
-- Pure: it talks through LinkSession's `env`. When one of our characters mails (or returns mail to) a
-- character of a linked account, the DataStore's SendMail hook hands the attachments and money here
-- (LinkSession.SendMail), as it writes them into our own recipient's MailCache for a send between our own:
--   - the rows are written into our copy of that character's MailCache at once (so Search, the Inventory tab
--     and the totals count them, whether or not that account is online), each tagged `lm` with the send's id;
--   - a note of the send is kept (AltArmyTBC_LinkedData.outMail[accountId][id]) and sent to that account as a
--     MAIL message: at once if it is online, else when its next session starts (its HELLO), again every
--     RESEND seconds up to TRIES times a session until it answers MAILA;
--   - that account writes the rows into its own character's MailCache (once: by id), so its own data, and
--     what it syncs back, knows of the mail even if it is logged in on another character;
--   - a sync of that character's mail replaces our copy: the note's rows are written in again, until the
--     mail data it sent carries them (`lm`) or says its mailbox was read since the mail arrived. Then the note
--     is dropped: from there on that account's own data is right.
-- Between accounts of one Battle.net account (links of kind "own", the only kind so far) mail arrives at
-- once. Mail with items to an unrelated account's character would arrive ITEM_DELAY later (money and text at
-- once): `DelayFor`. Such rows carry `arrivesAt`, and a mailbox scan before then keeps them (DataStoreMail's
-- ScanMailbox).
-- Of a mail only what is held travels: items, money and who sent it; never its subject or text.
--
-- Messages: MAIL { id, g = guid, r = realm, at, arr = arrivesAt, rows = { { itemID, count, link, icon,
--                  money }, ... }, s = sender's name, ret = a return }
--           MAILA { id }

AltArmy = AltArmy or {}
AltArmy.LinkMail = AltArmy.LinkMail or {}
local M = AltArmy.LinkMail

M.ITEM_DELAY = 3600 -- mail with items to an unrelated account's character arrives an hour later
M.RESEND = 120 -- seconds before a MAIL not answered is sent again
M.TRIES = 3 -- sends a session; the next session (its HELLO) sends again
M.KEEP = 31 * 86400 -- mail returns after 30 days: a note (or an id seen) older than this is forgotten
M.MAX_ROWS = 13 -- 12 attachments and the money
M.EXPIRY_DAYS = 30
M.MAX_NAME = 64
M.GUID_PATTERN = "^Player%-%d+%-%x+$"
M.ID_PATTERN = "^%x+:%d+:%d+$"
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local counter = 0

local function Store()
    return AltArmy.LinkStore
end

local function outbox(acct)
    local data = Store().Ensure()
    data.outMail[acct] = data.outMail[acct] or {}
    return data.outMail[acct]
end

local function isCount(n, max)
    return type(n) == "number" and n == math.floor(n) and n >= 0 and n <= max
end

--- A row as it travels and is kept, or nil if it isn't one: an item (id, count, link) or money.
local function cleanRow(row)
    if type(row) ~= "table" then
        return nil
    end
    local out = {}
    if row.itemID ~= nil then
        if not (isCount(row.itemID, 2 ^ 31) and row.itemID > 0) then return nil end
        if row.count ~= nil and not (isCount(row.count, 100000) and row.count > 0) then return nil end
        if row.link ~= nil and not (type(row.link) == "string" and #row.link <= 1024
            and row.link:find("|Hitem:", 1, true)) then
            return nil
        end
        out.itemID, out.count, out.link = row.itemID, row.count or 1, row.link
    elseif row.money ~= nil then
        if not (isCount(row.money, 2 ^ 50) and row.money > 0) then return nil end
        out.money = row.money
    else
        return nil
    end
    local icon = row.icon
    if (type(icon) == "string" and #icon <= 256) or (type(icon) == "number" and isCount(icon, 2 ^ 31)) then
        out.icon = icon
    end
    return out
end

local function cleanRows(rows)
    if type(rows) ~= "table" then
        return nil
    end
    local out = {}
    for i = 1, #rows do
        local row = cleanRow(rows[i])
        if not row then
            return nil
        end
        out[i] = row
    end
    if #out == 0 or #out > M.MAX_ROWS then
        return nil
    end
    return out
end
M._CleanRows = cleanRows

local function hasRow(char, id)
    for _, field in ipairs({ "Mails", "MailCache" }) do
        for _, row in ipairs(type(char[field]) == "table" and char[field] or {}) do
            if type(row) == "table" and row.lm == id then
                return true
            end
        end
    end
    return false
end

-- A fresh message index for predicted rows: below every cached one (DataStoreMail's NextMailCacheIndex).
local function nextIndex(char)
    local lowest = 0
    for _, row in ipairs(char.MailCache or {}) do
        local idx = type(row) == "table" and row.mailIndex
        if type(idx) == "number" and idx < lowest then
            lowest = idx
        end
    end
    return lowest - 1
end

--- Write a send's rows into `char`'s MailCache (once: a row tagged with its id means it is there).
local function writeRows(char, note)
    if hasRow(char, note.id) then
        return false
    end
    char.MailCache = type(char.MailCache) == "table" and char.MailCache or {}
    local index = nextIndex(char)
    for _, row in ipairs(note.rows) do
        char.MailCache[#char.MailCache + 1] = {
            icon = row.icon or (row.money and COIN_ICON) or nil,
            itemID = row.itemID,
            count = row.count,
            link = row.link,
            money = row.money or 0,
            sender = note.sender,
            lastCheck = note.at,
            daysLeft = M.EXPIRY_DAYS,
            returned = note.returned or false,
            mailIndex = index,
            lm = note.id,
            arrivesAt = note.arrivesAt > note.at and note.arrivesAt or nil,
        }
    end
    return true
end

--- How much later than sent mail with items reaches a character of `acct`: at once on our own Battle.net
--- account, ITEM_DELAY for any other kind of link.
function M.DelayFor(acct)
    local link = Store().GetLink(acct)
    if link and (link.kind == nil or link.kind == "own") then
        return 0
    end
    return M.ITEM_DELAY
end

--- Whether mail from `realm` reaches `r`: the same realm, or one coalesced with it (Forever's US1 and US2 shards
--- play together: RealmFilter.sameRealm).
local function reaches(realm, r)
    local RF = AltArmy.RealmFilter
    return r == realm or (RF and RF.sameRealm and RF.sameRealm(realm, r)) or false
end

--- The linked character called `name` (any case) whom mail sent on `realm` reaches, on that realm first: its
--- account, GUID, table and the realm it is kept under; nil if none.
function M.FindRecipient(realm, name)
    if type(realm) ~= "string" or type(name) ~= "string" or name == "" then
        return nil
    end
    local wanted = string.lower(name)
    local found
    Store().ForEachCharacter(function(r, g, c, id)
        if type(c.name) == "string" and string.lower(c.name) == wanted and reaches(realm, r) then
            found = { id, g, c, r }
            return r == realm -- the realm itself wins over a coalesced one
        end
    end)
    if not found then
        return nil
    end
    return found[1], found[2], found[3], found[4]
end

--- One of our characters (`sender`) on `realm` sent `rows` (cleanRow's shape) to `name`, or returned them
--- (`returned`). If a linked account has that character, the rows are shown on it now and a note is kept to
--- tell that account: returns the account and the note; nil when the name is no linked character.
function M.Sent(env, realm, name, rows, sender, returned)
    local acct, guid, char, charRealm = M.FindRecipient(realm, name)
    rows = cleanRows(rows)
    if not acct or not rows then
        return nil
    end
    local at = env.now()
    local items = false
    for _, row in ipairs(rows) do
        if row.itemID then items = true end
    end
    counter = counter + 1
    local note = {
        id = string.format("%s:%d:%d", env.myAccountId(), at, counter * 1000 + math.floor(env.random() * 1000)),
        g = guid, r = charRealm, at = at, arrivesAt = at + (items and M.DelayFor(acct) or 0), rows = rows,
        sender = type(sender) == "string" and sender:sub(1, M.MAX_NAME) or nil,
        returned = returned and true or nil,
    }
    outbox(acct)[note.id] = note
    writeRows(char, note)
    Store().Changed()
    return acct, note
end

--- Send `note` to `peer` (an online LinkSession peer of its account).
function M.Deliver(env, peer, note)
    note.sentAt = env.now()
    note.tries = (note.tries or 0) + 1
    env.send(peer.g, {
        t = "MAIL", id = note.id, g = note.g, r = note.r, at = note.at, arr = note.arrivesAt, rows = note.rows,
        s = note.sender, ret = note.returned,
    }, "NORMAL")
end

--- A session starts with `peer`: send it every note it hasn't answered.
function M.Flush(env, peer)
    for _, note in pairs(outbox(peer.acct)) do
        if not note.delivered then
            note.tries = 0
            M.Deliver(env, peer, note)
        end
    end
end

--- Every few seconds: send again what wasn't answered, forget what is too old. `peers`: accountId -> peer.
function M.Tick(env, peers)
    local now = env.now()
    local data = Store().Ensure()
    for acct, notes in pairs(data.outMail) do
        local peer = peers[acct]
        for id, note in pairs(notes) do
            if type(note) ~= "table" or (note.at or 0) + M.KEEP < now then
                notes[id] = nil
            elseif peer and not note.delivered and (note.tries or 0) < M.TRIES
                and now - (note.sentAt or 0) >= M.RESEND then
                M.Deliver(env, peer, note)
            end
        end
        if next(notes) == nil then
            data.outMail[acct] = nil
        end
    end
    for id, at in pairs(data.mailSeen) do
        if type(at) ~= "number" or at + M.KEEP < now then
            data.mailSeen[id] = nil
        end
    end
end

--- Our character with GUID `guid` on `realm`, in our own data root.
local function ownCharacter(root, realm, guid)
    local chars = type(root) == "table" and type(root.Characters) == "table" and root.Characters[realm]
    if type(chars) ~= "table" then
        return nil
    end
    local char = chars[guid]
    if type(char) == "table" and char.guid == guid then
        return char
    end
    return nil
end

--- A MAIL from `peer`: one of its characters mailed one of ours. Its rows go into that character's
--- MailCache (once), unless that mailbox was read since the mail arrived; answered MAILA whatever we did.
function M.OnMail(env, peer, msg)
    if type(msg.id) ~= "string" or #msg.id > 64 or not msg.id:match(M.ID_PATTERN) then
        return
    end
    local rows = cleanRows(msg.rows)
    local ok = rows and type(msg.g) == "string" and msg.g:match(M.GUID_PATTERN) and type(msg.r) == "string"
        and #msg.r <= M.MAX_NAME and type(msg.at) == "number" and type(msg.arr) == "number"
        and msg.at == msg.at and msg.arr == msg.arr and msg.arr >= msg.at and msg.arr - msg.at <= M.ITEM_DELAY
    if not ok then
        return
    end
    local data = Store().Ensure()
    local char = ownCharacter(env.ownRoot(), msg.r, msg.g)
    if char and not data.mailSeen[msg.id] and (tonumber(char.lastMailCheck) or 0) < msg.arr then
        local wrote = writeRows(char, {
            id = msg.id, at = msg.at, arrivesAt = msg.arr, rows = rows,
            sender = type(msg.s) == "string" and msg.s:sub(1, M.MAX_NAME) or nil, returned = msg.ret == true,
        })
        if wrote then
            if env.ownMailChanged then
                env.ownMailChanged(msg.g)
            end
            AltArmy.LinkSync.NoteLocalChange(env, msg.g) -- its own data says so: the sender's copy follows
        end
    end
    data.mailSeen[msg.id] = env.now()
    env.send(peer.g, { t = "MAILA", id = msg.id }, "NORMAL")
end

--- The answer to a MAIL: that account has it; the note stays until its mail data says so (Settle).
function M.OnAck(_, peer, msg)
    local notes = Store().Ensure().outMail[peer.acct]
    local note = notes and type(msg.id) == "string" and notes[msg.id]
    if type(note) == "table" then
        note.delivered = true
    end
end

--- `acct`'s mail of character `guid` on `realm` was just kept (LinkStore.Receive), replacing our copy's rows:
--- each note to it is dropped if that data carries it or that mailbox was read since it arrived, else its
--- rows are written in again.
function M.Settle(acct, realm, guid, char)
    local notes = Store().Ensure().outMail[acct]
    if not notes or type(char) ~= "table" then
        return
    end
    for id, note in pairs(notes) do
        if type(note) == "table" and note.g == guid and note.r == realm then
            if hasRow(char, id) or (tonumber(char.lastMailCheck) or 0) >= (note.arrivesAt or 0) then
                notes[id] = nil
            else
                writeRows(char, note)
            end
        end
    end
    if next(notes) == nil then
        Store().Ensure().outMail[acct] = nil
    end
end

-- Specs.
function M._Reset()
    counter = 0
end

return M
