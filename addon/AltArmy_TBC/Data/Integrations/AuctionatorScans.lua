-- AltArmy TBC — records when Auctionator stores auction house prices, and on which faction.
-- Auctionator keys a modern auction house's prices (WoW: Forever) by realm alone, so its SavedVariables
-- cannot say which faction's auction house they came from. The website's uploader reads this log
-- (AltArmyTBC_AuctionScans, its own SavedVariable so it is cheap to read) to name the faction.
-- luacheck: globals Auctionator AltArmyTBC_AuctionScans GetRealmName UnitFactionGroup time

if not AltArmy then return end

AltArmy.AuctionatorScans = AltArmy.AuctionatorScans or {}
local AS = AltArmy.AuctionatorScans

AS.VERSION = 1
AS.MAX_SCANS = 50
AS.MAX_AGE = 30 * 24 * 60 * 60 -- seconds
AS.COALESCE = 5 * 60 -- seconds: Auctionator's incremental scans report prices often

local CALLER_ID = "AltArmy"
local registered = false

--- The log, created on first use: { version = 1, scans = { { t, faction, realm, key }, ... } } oldest first.
function AS.GetLog()
    local log = AltArmyTBC_AuctionScans
    if type(log) ~= "table" or type(log.scans) ~= "table" then
        log = { version = AS.VERSION, scans = {} }
        AltArmyTBC_AuctionScans = log
    end
    return log
end

local function auctionatorKey()
    local state = Auctionator and Auctionator.State
    return state and state.CurrentRealm or nil
end

--- Record that Auctionator stored prices now, on the current character's faction.
function AS.Record(now)
    now = now or time()
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if not faction or faction == "" then return end
    local realm = AltArmy.CurrentRealm and AltArmy.CurrentRealm() or GetRealmName and GetRealmName() or ""
    local key = auctionatorKey() or realm
    local scans = AS.GetLog().scans

    local last = scans[#scans]
    if last and last.key == key and last.faction == faction and now - (last.t or 0) < AS.COALESCE then
        last.t = now
    else
        scans[#scans + 1] = { t = now, faction = faction, realm = realm, key = key }
    end

    local keep = {}
    for i = 1, #scans do
        if now - (scans[i].t or 0) <= AS.MAX_AGE then
            keep[#keep + 1] = scans[i]
        end
    end
    while #keep > AS.MAX_SCANS do
        table.remove(keep, 1)
    end
    AS.GetLog().scans = keep
end

--- Register with Auctionator's public API (full scans, searches and incremental scans on both the legacy
--- and the modern auction house). Returns true once registered; safe to call again.
function AS.Register()
    if registered then return true end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.RegisterForDBUpdate) then return false end
    local ok = pcall(api.RegisterForDBUpdate, CALLER_ID, function()
        AS.Record()
    end)
    registered = ok
    return ok
end

function AS._ResetForTests()
    registered = false
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function()
        AS.Register()
    end)
end
