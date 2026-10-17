-- AltArmy TBC — Net worth across characters (vendor + Auctionator AH prices).
-- luacheck: globals Auctionator GetItemInfo CreateFrame UIParent GetRealmName

AltArmy = AltArmy or {}
AltArmy.NetWorth = AltArmy.NetWorth or {}

local NW = AltArmy.NetWorth

-- Self-contained (no AltArmy.DataStore dependency) so this module's unit tests,
-- which stub GetItemInfo directly without loading the DataStore layer, keep working.
-- See docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md for why the C_Item fallback exists.
local function hasItemInfoApi()
    return GetItemInfo ~= nil or (C_Item ~= nil and C_Item.GetItemInfo ~= nil)
end

local function compatGetItemInfo(item)
    if GetItemInfo then return GetItemInfo(item) end
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
end

local DEFAULT_SCALE = 0.9
local CALLER_ID = "AltArmy"
local AUCTIONATOR_REQUIRED_MSG = "Auctionator is required to calculate your net worth"
local ARGS_USAGE_MSG = "Usage: /altarmy networth [all] [scale]. Scale must be between 0 and 1."

local function notify(msg)
    local D = AltArmy.Debug
    if D and D.NotifyChat then
        D.NotifyChat(msg)
    end
end

local function formatMoney(copper)
    local SD = AltArmy.SummaryData
    if SD and SD.GetMoneyString then
        return SD.GetMoneyString(copper)
    end
    return tostring(copper or 0)
end

function NW.IsAuctionatorAvailable()
    local atr = Auctionator
    return atr
        and atr.API
        and atr.API.v1
        and type(atr.API.v1.GetAuctionPriceByItemID) == "function"
        and true
        or false
end

local function parseScaleToken(token)
    local n = tonumber(token)
    if not n then
        return nil, ARGS_USAGE_MSG
    end
    if n < 0 or n > 1 then
        return nil, "Scale factor must be a number between 0 and 1."
    end
    return n, nil
end

--- Parse slash args after "networth". Returns { scale, allRealms }, errMessage.
--- Accepts optional "all" and optional scale in either order.
function NW.ParseArgs(arg)
    local scale = DEFAULT_SCALE
    local allRealms = false
    if arg == nil then
        return { scale = scale, allRealms = allRealms }, nil
    end
    if type(arg) == "number" then
        local n, err = parseScaleToken(arg)
        if not n then return nil, err end
        return { scale = n, allRealms = false }, nil
    end
    if type(arg) ~= "string" then
        return nil, ARGS_USAGE_MSG
    end
    arg = arg:match("^%s*(.-)%s*$") or ""
    if arg == "" then
        return { scale = scale, allRealms = allRealms }, nil
    end

    local sawScale = false
    for token in arg:gmatch("%S+") do
        local lower = token:lower()
        if lower == "all" then
            if allRealms then
                return nil, ARGS_USAGE_MSG
            end
            allRealms = true
        else
            if sawScale then
                return nil, ARGS_USAGE_MSG
            end
            local n, err = parseScaleToken(token)
            if not n then return nil, err end
            scale = n
            sawScale = true
        end
    end
    return { scale = scale, allRealms = allRealms }, nil
end

--- Parse optional scale argument. Returns scale, errMessage.
--- Kept for callers/tests that only need the scale.
function NW.ParseScaleFactor(arg)
    local opts, err = NW.ParseArgs(arg)
    if not opts then return nil, err end
    return opts.scale, nil
end

local function getScanTooltip()
    if not CreateFrame then return nil end
    if not NW._scanTooltip then
        NW._scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_NetWorthScanTooltip", UIParent, "GameTooltipTemplate")
        if NW._scanTooltip and NW._scanTooltip.SetOwner then
            NW._scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
    end
    return NW._scanTooltip
end

local function isAccountBound(link)
    if NW._IsAccountBoundForTests then
        return NW._IsAccountBoundForTests(link) == true
    end
    if not link then return false end
    local tip = getScanTooltip()
    if not tip or not tip.SetHyperlink then return false end
    tip:ClearLines()
    tip:SetHyperlink(link)
    for i = 1, tip:NumLines() do
        local line = _G["AltArmyTBC_NetWorthScanTooltipTextLeft" .. i]
        if line and line.GetText then
            local text = line:GetText() or ""
            if text:find("Binds to account", 1, true)
                or text:find("Battle.net Account Bound", 1, true)
                or text:find("Account Bound", 1, true)
            then
                return true
            end
        end
    end
    return false
end

local function isSoulboundOrUnsellable(link)
    if not link then return false end
    local IU = AltArmy.ItemUsability
    if IU and IU.IsBindOnPickup and IU.IsBindOnPickup(link) then
        return true
    end
    return isAccountBound(link)
end

local function getVendorPrice(itemID, link)
    if not hasItemInfoApi() then return 0 end
    local sellPrice
    if link then
        sellPrice = select(11, compatGetItemInfo(link))
    end
    if (not sellPrice or sellPrice == 0) and itemID then
        sellPrice = select(11, compatGetItemInfo(itemID))
    end
    return tonumber(sellPrice) or 0
end

local function getAuctionPrice(itemID, link)
    if not NW.IsAuctionatorAvailable() then return 0 end
    local api = Auctionator.API.v1
    local price
    if itemID and api.GetAuctionPriceByItemID then
        price = api.GetAuctionPriceByItemID(CALLER_ID, itemID)
    end
    if (not price or price == 0) and link and api.GetAuctionPriceByItemLink then
        price = api.GetAuctionPriceByItemLink(CALLER_ID, link)
    end
    return tonumber(price) or 0
end

--- Unit value in copper for one item (not multiplied by stack count).
function NW.GetItemUnitValue(itemID, link, scaleFactor)
    scaleFactor = scaleFactor or DEFAULT_SCALE
    local vendor = getVendorPrice(itemID, link)
    if isSoulboundOrUnsellable(link) then
        return vendor
    end
    local ah = getAuctionPrice(itemID, link)
    local scaled = ah * scaleFactor
    if vendor > scaled then
        return vendor
    end
    return scaled
end

local function charKey(realm, name)
    return tostring(realm or "") .. "\t" .. tostring(name or "")
end

local function displayName(realm, name, multiRealm)
    if multiRealm and realm and realm ~= "" then
        return tostring(name) .. "-" .. tostring(realm)
    end
    return tostring(name or "?")
end

local function currentRealmName()
    return (GetRealmName and GetRealmName()) or ""
end

local function realmAllowed(realm, allRealms, currentRealm)
    if allRealms then return true end
    return (realm or "") == (currentRealm or "")
end

--- Returns sorted rows { { name, copper }, ... }, totalCopper. Linked accounts' characters (the same player's
--- other WoW accounts) count too, while the character scope shows them.
--- opts.allRealms: when true, include every realm; default is current realm only.
function NW.Compute(scaleFactor, opts)
    if not NW.IsAuctionatorAvailable() then
        return {}, 0
    end
    scaleFactor = scaleFactor or DEFAULT_SCALE
    opts = opts or {}
    local allRealms = opts.allRealms == true
    local currentRealm = currentRealmName()

    local DS = AltArmy.DataStore
    local SD = AltArmy.SearchData
    if not DS or not DS.ForEachCharacter then
        return {}, 0
    end

    local realmsSeen = {}
    local realmCount = 0
    local byChar = {}

    -- a linked account's character is its own row, never one of ours of the same name
    local function rowKey(realm, name, linkId)
        return charKey(realm, name) .. (linkId and ("" .. linkId) or "")
    end

    local forEach = DS.ForEachCharacterInScope or DS.ForEachCharacter
    forEach(DS, function(realm, charName, charData, linkId)
        if not realmAllowed(realm, allRealms, currentRealm) then
            return
        end
        local name = (DS.GetCharacterName and DS:GetCharacterName(charData)) or charName
        if realm and not realmsSeen[realm] then
            realmsSeen[realm] = true
            realmCount = realmCount + 1
        end
        local key = rowKey(realm, name, linkId)
        local gold = (DS.GetMoney and DS:GetMoney(charData)) or 0
        byChar[key] = {
            realm = realm,
            name = name,
            copper = tonumber(gold) or 0,
        }
    end)

    local slots = (SD and SD.GetAllContainerSlots and SD.GetAllContainerSlots()) or {}
    for _, entry in ipairs(slots) do
        local name = entry.characterName
        local realm = entry.realm
        if realmAllowed(realm, allRealms, currentRealm) then
            local key = rowKey(realm, name, entry.linkId)
            local row = byChar[key]
            if not row then
                if realm and not realmsSeen[realm] then
                    realmsSeen[realm] = true
                    realmCount = realmCount + 1
                end
                row = { realm = realm, name = name, copper = 0 }
                byChar[key] = row
            end
            local count = tonumber(entry.count) or 1
            local unit = NW.GetItemUnitValue(entry.itemID, entry.itemLink, scaleFactor)
            row.copper = row.copper + (unit * count)
        end
    end

    local multiRealm = realmCount > 1
    local rows = {}
    local total = 0
    for _, row in pairs(byChar) do
        local copper = math.floor(row.copper + 0.5)
        table.insert(rows, {
            name = displayName(row.realm, row.name, multiRealm),
            copper = copper,
        })
        total = total + copper
    end
    table.sort(rows, function(a, b)
        if a.copper == b.copper then
            return (a.name or "") < (b.name or "")
        end
        return a.copper < b.copper
    end)
    return rows, total
end

function NW.PrintSummary(scaleFactor, opts)
    if not NW.IsAuctionatorAvailable() then
        notify(AUCTIONATOR_REQUIRED_MSG)
        return
    end
    scaleFactor = scaleFactor or DEFAULT_SCALE
    opts = opts or {}
    local rows, total = NW.Compute(scaleFactor, opts)
    local percent = math.floor(scaleFactor * 100 + 0.5)
    notify(string.format(
        "Networth by character, assuming all items sell at %d%% of AH value",
        percent
    ))
    for _, row in ipairs(rows) do
        notify(string.format("%s: %s", row.name, formatMoney(row.copper)))
    end
    notify("------------")
    notify(string.format("Total: %s", formatMoney(total)))
end

--- Slash-friendly entry: optional raw arg string after "networth".
function NW.PrintSummaryFromArg(arg)
    local opts, err = NW.ParseArgs(arg)
    if not opts then
        notify(err or ARGS_USAGE_MSG)
        return
    end
    NW.PrintSummary(opts.scale, { allRealms = opts.allRealms })
end
