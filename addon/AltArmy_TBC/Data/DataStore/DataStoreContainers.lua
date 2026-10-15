-- luacheck: globals GetServerTime
-- AltArmy TBC — DataStore module: containers (bags + bank).
-- Requires DataStore.lua (core) and DataStoreCurrencies.lua (for ScanCurrencies) loaded before events run.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local function notifyContainerDataChanged()
    local SD = AltArmy and AltArmy.SearchData
    if SD and SD.NotifyContainerDataChanged then
        SD.NotifyContainerDataChanged()
    end
    if DS.FireContainerDataChanged then
        DS:FireContainerDataChanged()
    end
end

local BACKPACK_FALLBACK_SLOTS = 16

--- Which container id plays which role on this client. TBC Anniversary numbers them the Classic way:
--- backpack 0, bags 1-4, keyring -2, the bank -1 and bank bags 5-11. WoW Forever's Enum.BagIndex is
--- retail's: the keyring is -1, bag 5 is a carried (reagent) bag, there is no bank container, and the
--- bank is tabs CharacterBankTab_1..9 (6-14), each a bag slot (checked against Alts Forever's scanner).
--- Everything else here (scans, counts, Search's locations, the Inventory tab) reads these roles.
--- `bagIndex` is Enum.BagIndex (nil on a client without it).
function DS._BuildBagRoles(bagIndex)
    local roles = {
        backpack = 0,
        bags = {}, -- carried bag slots, in order (the reagent bag included, where the client has one)
        reagentBag = nil, -- Forever's bag 5; counted apart from the other bags
        keyring = nil,
        bank = nil, -- the generic bank container, where the client has one
        bankBags = {}, -- bank bag slots (Forever: bank tabs), in order
        bankBagName = "Bank Bag %d",
        retail = false, -- retail-style ids (WoW Forever)
    }
    if type(bagIndex) == "table" and bagIndex.CharacterBankTab_1 ~= nil and bagIndex.Bank == nil then
        roles.retail = true
        for i = 1, 4 do roles.bags[#roles.bags + 1] = bagIndex["Bag_" .. i] or i end
        if bagIndex.ReagentBag ~= nil then
            roles.bags[#roles.bags + 1] = bagIndex.ReagentBag
            roles.reagentBag = bagIndex.ReagentBag
        end
        roles.keyring = bagIndex.Keyring
        for i = 1, 9 do
            local id = bagIndex["CharacterBankTab_" .. i]
            if id ~= nil then roles.bankBags[#roles.bankBags + 1] = id end
        end
        roles.bankBagName = "Bank Tab %d"
        roles.firstBankBagName = "Bank Bag" -- the first tab is the built-in bank (a placeholder bag item)
    else
        roles.bags = { 1, 2, 3, 4 }
        roles.keyring = -2
        roles.bank = -1
        roles.bankBags = { 5, 6, 7, 8, 9, 10, 11 }
    end
    roles.bagSet, roles.bankBagSet = {}, {}
    for _, id in ipairs(roles.bags) do roles.bagSet[id] = true end
    for _, id in ipairs(roles.bankBags) do roles.bankBagSet[id] = true end
    return roles
end

-- The Classic names other modules read (contiguous on both clients); set with the roles.
local NUM_BAG_SLOTS, BANK_CONTAINER, KEYRING_CONTAINER, MIN_BANK_BAG_ID, MAX_BANK_BAG_ID
local ROLES = {}
DS.BagRoles = ROLES
function DS:GetBagRoles() return ROLES end

--- Build the roles for `bagIndex` (Enum.BagIndex) into the shared table. Done once at load; tests
--- call it to switch clients.
function DS.RebuildBagRoles(bagIndex)
    local roles = DS._BuildBagRoles(bagIndex)
    for k in pairs(ROLES) do ROLES[k] = nil end
    for k, v in pairs(roles) do ROLES[k] = v end
    NUM_BAG_SLOTS = #ROLES.bags
    BANK_CONTAINER = ROLES.bank
    KEYRING_CONTAINER = ROLES.keyring
    MIN_BANK_BAG_ID = ROLES.bankBags[1]
    MAX_BANK_BAG_ID = ROLES.bankBags[#ROLES.bankBags]
    DS.NUM_BAG_SLOTS = NUM_BAG_SLOTS
    DS.BANK_CONTAINER = BANK_CONTAINER
    DS.KEYRING_CONTAINER = KEYRING_CONTAINER
    DS.MIN_BANK_BAG_ID = MIN_BANK_BAG_ID
    DS.MAX_BANK_BAG_ID = MAX_BANK_BAG_ID
end
DS.RebuildBagRoles(_G.Enum and _G.Enum.BagIndex)

--- "backpack", "bag", "reagentbag", "keyring", "bank", "bankbag", or nil for an id this client does not use.
function DS:GetBagRole(bagID)
    if type(bagID) ~= "number" then return nil end
    if bagID == ROLES.backpack then return "backpack" end
    if ROLES.reagentBag ~= nil and bagID == ROLES.reagentBag then return "reagentbag" end
    if ROLES.bagSet[bagID] then return "bag" end
    if ROLES.keyring ~= nil and bagID == ROLES.keyring then return "keyring" end
    if ROLES.bank ~= nil and bagID == ROLES.bank then return "bank" end
    if ROLES.bankBagSet[bagID] then return "bankbag" end
    return nil
end

local function IsPlayerCarriedBagID(bagID)
    local role = DS:GetBagRole(bagID)
    return role == "backpack" or role == "bag" or role == "reagentbag" or role == "keyring"
end
DS._IsPlayerCarriedBagID = IsPlayerCarriedBagID

local function GetNumSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID)
    end
    return GetContainerNumSlots and GetContainerNumSlots(bagID)
end

local function GetItemLink(bagID, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bagID, slot)
    end
    return GetContainerItemLink and GetContainerItemLink(bagID, slot)
end

--- The slot's stack count, and whether this copy is soulbound (`C_Container`'s isBound; nil where the
--- client has no C_Container: the legacy API doesn't say).
local function GetItemInfoForSlot(bagID, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        return info and info.stackCount or 1, info and info.isBound or nil
    end
    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bagID, slot)
        return (count and count > 0) and count or 1
    end
    return 1
end

local function IsEquippableBagSlot(bagID)
    local role = DS:GetBagRole(bagID)
    return role == "bag" or role == "reagentbag" or role == "bankbag"
end

local function GetContainer(char, bagID)
    if not char then return nil end
    char.Containers = char.Containers or {}
    local bag = char.Containers[bagID]
    if not bag then
        bag = { links = {}, items = {} }
        char.Containers[bagID] = bag
    end
    return bag
end

local function ClearContainerContents(bag)
    if not bag then return end
    bag.links = bag.links or {}
    bag.items = bag.items or {}
    for k in pairs(bag.links) do bag.links[k] = nil end
    for k in pairs(bag.items) do bag.items[k] = nil end
end

local function ClearBagIdentity(bag)
    if not bag then return end
    bag.bagLink = nil
    bag.bagItemID = nil
end

local INV_BAG_SLOT_NAMES = { "Bag0Slot", "Bag1Slot", "Bag2Slot", "Bag3Slot" }
local TBC_FIRST_BAG_INV_SLOT = 20
local TBC_FIRST_BANK_BAG_INV_SLOT = 68

local function GetBagInventorySlot(bagID)
    local conv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if conv then
        local ok, invSlot = pcall(conv, bagID)
        if ok and type(invSlot) == "number" then
            return invSlot
        end
    end
    if ROLES.bagSet[bagID] then
        local name = INV_BAG_SLOT_NAMES[bagID]
        if name and GetInventorySlotInfo then
            local slot = GetInventorySlotInfo(name)
            if type(slot) == "number" then
                return slot
            end
        end
        if INVSLOT_BAG_0 then
            return INVSLOT_BAG_0 + (bagID - 1)
        end
        return TBC_FIRST_BAG_INV_SLOT + (bagID - 1)
    end
    if ROLES.bankBagSet[bagID] then
        if BankButtonIDToInvSlotID then
            local ok, invSlot = pcall(BankButtonIDToInvSlotID, bagID - NUM_BAG_SLOTS, 1)
            if ok and type(invSlot) == "number" then
                return invSlot
            end
        end
        return TBC_FIRST_BANK_BAG_INV_SLOT + (bagID - MIN_BANK_BAG_ID)
    end
    return nil
end

--- WoW Forever's first bank tab is the built-in bank: its slot holds a placeholder item, "Character
--- Bank Tab Bag (DNT)" (Blizzard's do-not-translate marker), not a bag anyone owns.
local function IsBuiltInBankTab(bagID)
    return ROLES.retail and bagID == ROLES.bankBags[1]
end

local function ScanBagIdentity(char, bagID, preserveIfUnknown)
    if not char or not IsEquippableBagSlot(bagID) then return end
    local bag = GetContainer(char, bagID)
    if IsBuiltInBankTab(bagID) then
        ClearBagIdentity(bag) -- never recorded, so no reader shows the placeholder as a bag
        return
    end
    local invSlot = GetBagInventorySlot(bagID)
    if not invSlot then
        if not preserveIfUnknown then
            ClearBagIdentity(bag)
        end
        return
    end
    local link = GetInventoryItemLink and GetInventoryItemLink("player", invSlot) or nil
    local itemID = GetInventoryItemID and GetInventoryItemID("player", invSlot) or nil
    if not itemID and type(link) == "string" then
        itemID = tonumber(link:match("item:(%d+)"))
    end
    if itemID then
        bag.bagItemID = itemID
        bag.bagLink = link
    elseif not preserveIfUnknown then
        ClearBagIdentity(bag)
    end
end

local function ScanContainer(char, bagID, sizeOverride)
    local numSlots = sizeOverride or GetNumSlots(bagID)
    if not numSlots or numSlots <= 0 then
        if IsEquippableBagSlot(bagID) and char and char.Containers and char.Containers[bagID] then
            local bag = char.Containers[bagID]
            ClearContainerContents(bag)
            bag.numSlots = 0
            ScanBagIdentity(char, bagID, false)
            char.lastUpdate = time()
        end
        return
    end
    if not GetItemLink then return end
    local bag = GetContainer(char, bagID)
    ClearContainerContents(bag)
    bag.numSlots = numSlots -- containers v3: lets the Inventory tab draw empty slots
    for slot = 1, numSlots do
        local link = GetItemLink(bagID, slot)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            local count, bound = GetItemInfoForSlot(bagID, slot)
            bag.links[slot] = link
            bag.items[slot] = { itemID = itemID, count = count, bound = bound or nil }
        end
    end
    if IsEquippableBagSlot(bagID) then
        ScanBagIdentity(char, bagID, true)
    end
    char.lastUpdate = time()
end

function DS:ScanBags()
    local char = GetCurrentCharTable()
    if not char then return end
    local backpackSlots = GetNumSlots(ROLES.backpack)
    if not backpackSlots or backpackSlots <= 0 then
        backpackSlots = BACKPACK_FALLBACK_SLOTS
    end
    ScanContainer(char, ROLES.backpack, backpackSlots)
    for _, bagID in ipairs(ROLES.bags) do
        -- Equippable slots: always scan (clears identity/contents when empty).
        ScanContainer(char, bagID, GetNumSlots(bagID))
    end
    if KEYRING_CONTAINER ~= nil then
        local keyringSlots = GetNumSlots(KEYRING_CONTAINER)
        if keyringSlots and keyringSlots > 0 then
            ScanContainer(char, KEYRING_CONTAINER, keyringSlots)
        end
    end
    local totalSlots, freeSlots = backpackSlots, 0
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if getFree and getFree(ROLES.backpack) then
        freeSlots = freeSlots + getFree(ROLES.backpack)
    end
    for _, bagID in ipairs(ROLES.bags) do
        totalSlots = totalSlots + (GetNumSlots(bagID) or 0)
        if getFree and getFree(bagID) then
            freeSlots = freeSlots + getFree(bagID)
        end
    end
    char.bagInfo = { totalSlots = totalSlots, freeSlots = freeSlots }
    char.bagsScannedAt = GetServerTime and GetServerTime() or time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    if self.ScanCurrencies then self:ScanCurrencies() end
    notifyContainerDataChanged()
end

function DS:ScanBank()
    if self.IsBankOpen and not self:IsBankOpen() then
        return
    end
    local char = GetCurrentCharTable()
    if not char then return end
    if BANK_CONTAINER ~= nil and GetNumSlots(BANK_CONTAINER) and GetNumSlots(BANK_CONTAINER) > 0 then
        ScanContainer(char, BANK_CONTAINER)
    end
    for _, bagID in ipairs(ROLES.bankBags) do
        -- Always scan equippable bank bag slots so empty slots clear stale identity/contents.
        ScanContainer(char, bagID)
    end
    local totalSlots, freeSlots = 0, 0
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if BANK_CONTAINER ~= nil and GetNumSlots(BANK_CONTAINER) then
        totalSlots = totalSlots + GetNumSlots(BANK_CONTAINER)
        if getFree and getFree(BANK_CONTAINER) then
            freeSlots = freeSlots + getFree(BANK_CONTAINER)
        end
    end
    for _, bagID in ipairs(ROLES.bankBags) do
        local n = GetNumSlots(bagID) or 0
        totalSlots = totalSlots + n
        if getFree and getFree(bagID) then
            freeSlots = freeSlots + getFree(bagID)
        end
    end
    char.bankInfo = { totalSlots = totalSlots, freeSlots = freeSlots }
    char.bankScannedAt = GetServerTime and GetServerTime() or time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    if self.ScanCurrencies then self:ScanCurrencies() end
    notifyContainerDataChanged()
end

DS.ScanContainer = function(_self, char, bagID, sizeOverride)
    ScanContainer(char, bagID, sizeOverride)
end

function DS:GetContainers(char)
    return (char and char.Containers) or {}
end

function DS:GetContainer(char, bagID)
    if not char or not char.Containers then return nil end
    return char.Containers[bagID]
end

--- Slot count recorded at the last scan (containers v3), or nil for older data.
function DS:GetContainerNumSlots(char, bagID)
    local bag = self:GetContainer(char, bagID)
    local n = bag and bag.numSlots
    if type(n) == "number" and n >= 0 then
        return n
    end
    return nil
end

function DS:GetContainerItemCount(char, itemID)
    if not char or not char.Containers or not itemID then return 0 end
    local total = 0
    for _, bag in pairs(char.Containers) do
        if bag.items then
            for _, slotData in pairs(bag.items) do
                if slotData and slotData.itemID == itemID then
                    total = total + (slotData.count or 1)
                end
            end
        end
    end
    return total
end

--- Returns merged item count across containers (bags+bank snapshot) and mail snapshot/cache.
--- This is the default "have" total for gameplay-facing displays; use GetBagItemCount for sendable (bag-only) items.
function DS:GetTotalItemCount(char, itemID)
    local containerCount = self:GetContainerItemCount(char, itemID)
    local mailCount = 0
    if self.GetMailItemCount then
        mailCount = self:GetMailItemCount(char, itemID)
    end
    return containerCount + (mailCount or 0)
end

--- Counts items in player bags only (excludes bank bags).
--- Uses the character snapshot in SavedVariables; does not query live bag APIs.
function DS:GetBagItemCount(char, itemID)
    if not char or not char.Containers or not itemID then return 0 end
    local total = 0
    for bagID, bag in pairs(char.Containers) do
        if IsPlayerCarriedBagID(tonumber(bagID)) then
            if bag and bag.items then
                for _, slotData in pairs(bag.items) do
                    if slotData and slotData.itemID == itemID then
                        total = total + (slotData.count or 1)
                    end
                end
            end
        end
    end
    return total
end

function DS:GetNumBagSlots(char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.totalSlots or 0
end

function DS:GetNumFreeBagSlots(char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.freeSlots or 0
end

function DS:IterateContainerSlots(char, callback)
    if not char or not char.Containers or not callback then return end
    for bagID, bag in pairs(char.Containers) do
        if bag and bag.items then
            for slot, slotData in pairs(bag.items) do
                if slotData and slotData.itemID then
                    local link = (bag.links and bag.links[slot]) or nil
                    if callback(bagID, slot, slotData.itemID, slotData.count or 1, link) then
                        return
                    end
                end
            end
        end
    end
end

function DS:IterateBagSlots(char, callback)
    if not char or not char.Containers or not callback then return end
    for bagID, bag in pairs(char.Containers) do
        bagID = tonumber(bagID)
        if bagID and IsPlayerCarriedBagID(bagID) then
            if bag and bag.items then
                for slot, slotData in pairs(bag.items) do
                    if slotData and slotData.itemID then
                        local link = (bag.links and bag.links[slot]) or nil
                        if callback(bagID, slot, slotData.itemID, slotData.count or 1, link) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function DS:IterateBankSlots(char, callback)
    if not char or not char.Containers or not callback then return end
    for bagID, bag in pairs(char.Containers) do
        bagID = tonumber(bagID)
        local role = DS:GetBagRole(bagID)
        if role == "bank" or role == "bankbag" then
            if bag and bag.items then
                for slot, slotData in pairs(bag.items) do
                    if slotData and slotData.itemID then
                        local link = (bag.links and bag.links[slot]) or nil
                        if callback(bagID, slot, slotData.itemID, slotData.count or 1, link) then
                            return
                        end
                    end
                end
            end
        end
    end
end

--- Yields equipped bag items (inventory bags 1-4 and bank bags 5-11), not bag contents.
--- callback(bagID, itemID, link) — return true to stop early.
function DS:IterateEquippedBags(char, callback)
    if not char or not char.Containers or not callback then return end
    for bagID, bag in pairs(char.Containers) do
        bagID = tonumber(bagID)
        -- Forever's built-in bank tab: a placeholder an older addon may have recorded as a bag.
        if bagID and IsEquippableBagSlot(bagID) and not IsBuiltInBankTab(bagID) and bag and bag.bagItemID then
            if callback(bagID, bag.bagItemID, bag.bagLink) then
                return
            end
        end
    end
end

function DS:ScanCurrentCharacterBags()
    local char = GetCurrentCharTable()
    if char then self:ScanBags() end
end

function DS:ScanBagsAndLog()
    local char = GetCurrentCharTable()
    if char then self:ScanBags() end
end
