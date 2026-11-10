-- AltArmy TBC — DataStore module: mail.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local DATA_VERSIONS = DS._DATA_VERSIONS

local MAIL_ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local MAIL_ICON_NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local ATTACHMENTS_MAX_SEND = 12
local MAIL_EXPIRY_DAYS = 30

-- Luacheck-friendly aliases (WoW API globals exist in-game; may be absent in tests)
local hooksecurefunc = _G.hooksecurefunc

local function notifyContainerDataChanged()
    local SD = AltArmy and AltArmy.SearchData
    if SD and SD.NotifyContainerDataChanged then
        SD.NotifyContainerDataChanged()
    end
    if DS.FireContainerDataChanged then
        DS:FireContainerDataChanged()
    end
end

local function Now()
    return (time and time()) or 0
end

local function NormalizeName(s)
    if not s or s == "" then return "" end
    return string.lower(s)
end

local function FindOnRealm(realm, wanted)
    local chars = DS.GetCharacters and DS:GetCharacters(realm) or nil
    for key, charTable in pairs(chars or {}) do
        local charName = (type(charTable) == "table" and charTable.name) or key
        if NormalizeName(charName) == wanted then
            return charTable
        end
    end
    return nil
end

--- Our character called `name` (any case) whom mail sent on `realm` reaches: on that realm, else on one coalesced
--- with it (Forever's US1 and US2 shards play together: RealmFilter.sameRealm).
local function FindCharacterByName(realm, name)
    if not realm or not name or name == "" then return nil end
    local wanted = NormalizeName(name)
    local found = FindOnRealm(realm, wanted)
    if found then return found end
    local RF = AltArmy.RealmFilter
    if not (RF and RF.sameRealm) then return nil end
    for r in pairs(type(AltArmyTBC_Data) == "table" and AltArmyTBC_Data.Characters or {}) do
        if r ~= realm and RF.sameRealm(realm, r) then
            found = FindOnRealm(r, wanted)
            if found then return found end
        end
    end
    return nil
end
DS._FindCharacterByName = FindCharacterByName

--- Days a mail row has left now: its daysLeft at the scan less the time since (nil without an expiry).
function DS.MailRowDaysLeft(row, now)
    if type(row) ~= "table" or type(row.daysLeft) ~= "number" then return nil end
    return row.daysLeft - ((now or Now()) - (row.lastCheck or 0)) / 86400
end

local function GetMailTable(char, index)
    if not char or not index or index < 1 then return nil end
    local mails = char.Mails or {}
    local cache = char.MailCache or {}
    if index <= #mails then
        return mails[index]
    end
    local j = index - #mails
    return cache[j]
end

function DS:ScanMailbox(_self)
    local getter = self and self._GetCurrentCharTable
    local char = getter and getter() or nil
    if not char then return end
    if not GetInboxNumItems then return end
    char.Mails = char.Mails or {}
    char.MailCache = char.MailCache or {}
    -- what the inbox shows now replaces the predicted rows, except mail from a linked account still on its way
    -- (items to another account arrive an hour later: Link/LinkMail.lua)
    local now = Now()
    local inTransit = {}
    for _, row in ipairs(char.MailCache) do
        if type(row) == "table" and type(row.arrivesAt) == "number" and row.arrivesAt > now then
            inTransit[#inTransit + 1] = row
        end
    end
    for k in pairs(char.Mails) do char.Mails[k] = nil end
    for k in pairs(char.MailCache) do char.MailCache[k] = nil end
    for i, row in ipairs(inTransit) do char.MailCache[i] = row end
    local numItems = GetInboxNumItems()
    if numItems == 0 then
        char.lastMailCheck = Now()
        char.dataVersions = char.dataVersions or {}
        char.dataVersions.mail = DATA_VERSIONS.mail
        notifyContainerDataChanged()
        return
    end
    if CheckInbox then CheckInbox() end
    for i = 1, numItems do
        local _, _, mailSender, mailSubject, mailMoney, _, daysLeft, numAttachments, _, wasReturned =
            GetInboxHeaderInfo(i)
        daysLeft = daysLeft or MAIL_EXPIRY_DAYS
        if numAttachments and numAttachments > 0 then
            for attachIndex = 1, ATTACHMENTS_MAX_SEND do
                local itemName, itemID, icon, count = GetInboxItem(i, attachIndex)
                if itemName and itemID then
                    local link = GetInboxItemLink and GetInboxItemLink(i, attachIndex)
                    table.insert(char.Mails, {
                        icon = icon or MAIL_ICON_NOTE,
                        itemID = itemID,
                        count = count or 1,
                        sender = mailSender,
                        link = link,
                        money = 0,
                        subject = mailSubject,
                        lastCheck = Now(),
                        daysLeft = daysLeft,
                        returned = wasReturned,
                        mailIndex = i, -- mail v2: the message this row belongs to
                    })
                end
            end
        end
        -- Do not call GetInboxText: it marks the message as read.
        -- Attachments and money are available from header/item APIs without that.
        if mailMoney and mailMoney > 0 then
            table.insert(char.Mails, {
                icon = MAIL_ICON_COIN,
                itemID = nil,
                count = nil,
                sender = mailSender,
                link = nil,
                money = mailMoney or 0,
                subject = mailSubject,
                lastCheck = Now(),
                daysLeft = daysLeft,
                returned = wasReturned,
                mailIndex = i,
            })
        end
    end
    char.lastMailCheck = Now()
    char.lastUpdate = Now()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.mail = DATA_VERSIONS.mail
    notifyContainerDataChanged()
end

function DS:GetNumMails(char)
    if not char then return 0 end
    local n = 0
    if char.Mails then n = n + #char.Mails end
    if char.MailCache then n = n + #char.MailCache end
    return n
end

function DS:GetMailInfo(char, index)
    local n = self:GetNumMails(char)
    if not char or not index or index < 1 or index > n then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end
    local data = GetMailTable(char, index)
    if not data then return nil, nil, nil, nil, nil, nil, nil, nil end
    local daysLeft = DS.MailRowDaysLeft(data, Now())
    return data.icon, data.count, data.link, data.money, data.subject, data.sender, daysLeft, data.returned
end

--- Soonest remaining days until any mail expires/returns (Mails + MailCache).
--- Adjusts each entry by elapsed time since its lastCheck.
--- @param char table|nil
--- @param now number|nil unix time (defaults to time())
--- @return number|nil fractional days remaining, or nil if no mail with expiry data
function DS:GetSoonestMailDaysLeft(char, now)
    if not char then return nil end
    now = now or Now()
    local soonest = nil
    local function consider(rows)
        for _, data in ipairs(rows or {}) do
            local left = DS.MailRowDaysLeft(data, now)
            if left and (soonest == nil or left < soonest) then
                soonest = left
            end
        end
    end
    consider(char.Mails)
    consider(char.MailCache)
    return soonest
end

function DS:GetMailItemCount(char, itemID)
    if not char or not itemID then return 0 end
    local count = 0
    if char.Mails then
        for _, v in ipairs(char.Mails) do
            if v.itemID == itemID then
                count = count + (v.count or 1)
            end
        end
    end
    if char.MailCache then
        for _, v in ipairs(char.MailCache) do
            if v.itemID == itemID then
                count = count + (v.count or 1)
            end
        end
    end
    return count
end

--- Iterate mail attachment rows that have item links (Mails + MailCache).
--- Callback(link, itemID, count) — return true to stop.
function DS:IterateMailItemLinks(char, callback)
    if not char or not callback then return end
    local function scan(rows)
        for _, v in ipairs(rows or {}) do
            if v and v.itemID and v.link and v.link ~= "" then
                if callback(v.link, v.itemID, v.count or 1) then
                    return true
                end
            end
        end
        return false
    end
    if scan(char.Mails) then return end
    scan(char.MailCache)
end

function DS:GetMailboxLastVisit(char)
    if not char then return 0 end
    return char.lastMailCheck or 0
end

function DS:GetMailMoneyTotal(char)
    if not char then return 0 end
    local total = 0
    if char.Mails then
        for _, v in ipairs(char.Mails) do
            local m = v and v.money
            if type(m) == "number" and m > 0 then
                total = total + m
            end
        end
    end
    if char.MailCache then
        for _, v in ipairs(char.MailCache) do
            local m = v and v.money
            if type(m) == "number" and m > 0 then
                total = total + m
            end
        end
    end
    return total
end

--- A fresh message index for rows predicted from a send or return (mail v2). Scanned rows use the
--- inbox position (1..n); predicted messages count down from -1 so the two never collide, and every
--- row written for one send shares the index the caller got here.
function DS:NextMailCacheIndex(char)
    local lowest = 0
    for _, row in ipairs(char and char.MailCache or {}) do
        local idx = row and row.mailIndex
        if type(idx) == "number" and idx < lowest then
            lowest = idx
        end
    end
    return lowest - 1
end

function DS:SaveMailToCache(char, money, body, subject, sender, returned, mailIndex)
    if not char then return end
    char.MailCache = char.MailCache or {}
    table.insert(char.MailCache, {
        icon = (money and money > 0) and MAIL_ICON_COIN or MAIL_ICON_NOTE,
        money = money or 0,
        text = body or "",
        subject = subject,
        sender = sender,
        lastCheck = Now(),
        daysLeft = MAIL_EXPIRY_DAYS,
        returned = returned or false,
        mailIndex = mailIndex,
    })
    notifyContainerDataChanged()
end

function DS:SaveMailAttachmentToCache(char, icon, itemID, link, count, sender, subject, returned, mailIndex)
    if not char or not itemID then return end
    char.MailCache = char.MailCache or {}
    table.insert(char.MailCache, {
        icon = icon or MAIL_ICON_NOTE,
        itemID = itemID,
        count = count or 1,
        sender = sender,
        subject = subject,
        link = link,
        money = 0,
        lastCheck = Now(),
        daysLeft = MAIL_EXPIRY_DAYS,
        returned = returned or false,
        mailIndex = mailIndex,
    })
    notifyContainerDataChanged()
end

-- ---------------------------------------------------------------------------
-- Local send/return prediction cache (no guild comm relay). A recipient on a linked account (none of ours by
-- that name) is handed to Link/LinkTransport.MailSent: its attachments and money, never the subject or text.
-- ---------------------------------------------------------------------------

--- Tell the link of mail to `name` on `realm`, none of our characters: rows of { itemID, count, link, icon }
--- and { money, icon }. Nothing for a mail that holds neither.
local function SendToLinked(realm, name, rows, sender, returned)
    local LT = AltArmy.LinkTransport
    if #rows == 0 or not (LT and LT.MailSent) then return end
    LT.MailSent(realm, name, rows, sender, returned)
end

local function CacheSentMailToAlt(recipient, subject, body)
    if not recipient or recipient == "" then return end
    local GetSendMailItem = _G.GetSendMailItem
    local GetSendMailItemLink = _G.GetSendMailItemLink
    local GetSendMailMoney = _G.GetSendMailMoney
    if not GetSendMailItem then return end

    local recipientName = recipient:match("^([^-]+)") or recipient -- "Name-Realm": the name

    local _playerName, realm = DS:GetCurrentPlayerIdentity()
    if not realm or realm == "" then return end

    local targetChar = FindCharacterByName(realm, recipientName)
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    if not targetChar then
        local rows = {}
        for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
            local itemName, itemID, icon, count = GetSendMailItem(attachmentIndex)
            if itemName and itemID then
                local link = GetSendMailItemLink and GetSendMailItemLink(attachmentIndex) or nil
                rows[#rows + 1] = { itemID = itemID, count = count or 1, link = link, icon = icon }
            end
        end
        if money and money > 0 then
            rows[#rows + 1] = { money = money, icon = MAIL_ICON_COIN }
        end
        SendToLinked(realm, recipientName, rows, _playerName, false)
        return
    end

    local mailIndex = DS:NextMailCacheIndex(targetChar)
    for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
        local itemName, itemID, icon, count = GetSendMailItem(attachmentIndex)
        if itemName and itemID then
            local link = GetSendMailItemLink and GetSendMailItemLink(attachmentIndex) or nil
            DS:SaveMailAttachmentToCache(targetChar, icon, itemID, link, count, _playerName, subject, false,
                mailIndex)
        end
    end

    body = body or ""
    if (money and money > 0) or (body and body ~= "") then
        DS:SaveMailToCache(targetChar, money or 0, body, subject, _playerName, false, mailIndex)
    end
end

local function CacheReturnedMailToAlt(index)
    if not index or not GetInboxHeaderInfo then return end
    if not GetInboxItem then return end

    local _, stationaryIcon, mailSender, mailSubject, mailMoney, _, _, numAttachments = GetInboxHeaderInfo(index)
    if not mailSender or mailSender == "" then return end

    local senderName = mailSender:match("^([^-]+)") or mailSender -- "Name-Realm": the name

    local _playerName, realm = DS:GetCurrentPlayerIdentity()
    if not realm or realm == "" then return end

    local targetChar = FindCharacterByName(realm, senderName)
    if not targetChar then
        local rows = {}
        for attachmentIndex = 1, (numAttachments and numAttachments > 0) and ATTACHMENTS_MAX_SEND or 0 do
            local itemName, itemID, icon, count = GetInboxItem(index, attachmentIndex)
            if itemName and itemID then
                local link = GetInboxItemLink and GetInboxItemLink(index, attachmentIndex) or nil
                rows[#rows + 1] = { itemID = itemID, count = count or 1, link = link, icon = icon or stationaryIcon }
            end
        end
        if mailMoney and mailMoney > 0 then
            rows[#rows + 1] = { money = mailMoney, icon = MAIL_ICON_COIN }
        end
        SendToLinked(realm, senderName, rows, _playerName, true)
        return
    end

    local mailIndex = DS:NextMailCacheIndex(targetChar)
    if numAttachments and numAttachments > 0 then
        for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
            local itemName, itemID, icon, count = GetInboxItem(index, attachmentIndex)
            if itemName and itemID then
                local link = GetInboxItemLink and GetInboxItemLink(index, attachmentIndex) or nil
                DS:SaveMailAttachmentToCache(
                    targetChar,
                    icon or stationaryIcon,
                    itemID,
                    link,
                    count,
                    _playerName,
                    mailSubject,
                    true,
                    mailIndex
                )
            end
        end
    end

    local inboxText = GetInboxText and GetInboxText(index) or nil
    if (mailMoney and mailMoney > 0) or (inboxText and inboxText ~= "") then
        DS:SaveMailToCache(targetChar, mailMoney or 0, inboxText or "", mailSubject, _playerName, true, mailIndex)
    end
end

DS._CacheSentMailToAlt = CacheSentMailToAlt

if hooksecurefunc then
    hooksecurefunc("SendMail", function(recipient, subject, body)
        CacheSentMailToAlt(recipient, subject, body)
    end)

    hooksecurefunc("ReturnInboxItem", function(index)
        CacheReturnedMailToAlt(index)
    end)
end
