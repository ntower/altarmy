-- AltArmy TBC — finding this player's other WoW game accounts that are online now (linked accounts).
-- A multiboxer's accounts share one Battle.net account: each client sees the others among its own
-- Battle.net game accounts. Nothing in the game lists them, so this walks the game account ids
-- (C_BattleNet.GetGameAccountInfoByID) and keeps those online in WoW, in the same game (wowProjectID) and
-- region, on this Battle.net account, other than this client. Pure: the client's API is passed in
-- (LD.LiveApi() in game) so the specs can fake it.
--
-- Measured on Forever (1.60.1, interface 16001, /altarmy debug bnprobe): the game account struct carries no
-- `bnetAccountID` and there is no legacy BNGetGameAccountInfo, so another account is placed on a Battle.net
-- account by its character: C_BattleNet.GetAccountInfoByGUID(playerGuid), whose bnetAccountID (else
-- battleTag) is compared with ours. BNGetInfo's third return is not our game account id there (it read 1
-- with ours 3), so we are told apart by our GUID. `bnetAccountFrom` says which source answered.

AltArmy = AltArmy or {}
AltArmy.LinkDiscovery = AltArmy.LinkDiscovery or {}
local LD = AltArmy.LinkDiscovery

LD.MAX_GAME_ACCOUNT_ID = 128 -- game account ids are small and per session
LD.WOW_CLIENT = "WoW" -- BNET_CLIENT_WOW
LD.LEGACY_BNET_ACCOUNT_INDEX = 17 -- BNGetGameAccountInfo: ..., isOnline, bnetIDGameAccount, bnetIDAccount

--- The client's API, as LD reads it.
function LD.LiveApi()
    local bn = C_BattleNet --luacheck: ignore 113
    return {
        BNGetInfo = BNGetInfo, --luacheck: ignore 113
        GetGameAccountInfoByID = bn and bn.GetGameAccountInfoByID,
        GetAccountInfoByGUID = bn and bn.GetAccountInfoByGUID,
        GetGameAccountInfoByGUID = bn and bn.GetGameAccountInfoByGUID,
        BNGetGameAccountInfo = BNGetGameAccountInfo, --luacheck: ignore 113
        UnitGUID = UnitGUID, --luacheck: ignore 113
        wowProjectID = WOW_PROJECT_ID, --luacheck: ignore 113
    }
end

local function call(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end

--- One game account as LD uses it, or nil if the client knows no such id. `raw` is the struct as given.
function LD.Info(api, id)
    local ok, info = call(api.GetGameAccountInfoByID, id)
    if not ok or type(info) ~= "table" then
        return nil
    end
    local out = {
        gameAccountID = info.gameAccountID or id,
        clientProgram = info.clientProgram,
        isOnline = info.isOnline,
        isWowMobile = info.isWowMobile,
        wowProjectID = info.wowProjectID,
        regionID = info.regionID,
        characterName = info.characterName,
        realmName = info.realmName,
        factionName = info.factionName,
        playerGuid = info.playerGuid,
        bnetAccountID = info.bnetAccountID,
        bnetAccountFrom = info.bnetAccountID and "struct" or nil,
        raw = info,
    }
    if out.bnetAccountID == nil and type(info.playerGuid) == "string" and info.playerGuid ~= "" then
        local okA, acct = call(api.GetAccountInfoByGUID, info.playerGuid)
        if okA and type(acct) == "table" then
            out.bnetAccountID, out.battleTag = acct.bnetAccountID, acct.battleTag
            out.bnetAccountFrom = (acct.bnetAccountID or acct.battleTag) and "guid" or nil
            out.accountRaw = acct
        end
    end
    if out.bnetAccountID == nil and out.battleTag == nil then
        local legacy = { call(api.BNGetGameAccountInfo, id) }
        if legacy[1] then
            out.bnetAccountID = legacy[LD.LEGACY_BNET_ACCOUNT_INDEX + 1]
            out.bnetAccountFrom = out.bnetAccountID and "legacy" or nil
        end
    end
    return out
end

--- This client: its character's GUID, Battle.net account and tag, game account, game and region. Fields
--- are nil where the client doesn't say (our own presence can be blank for a while after login).
function LD.Me(api)
    local me = {}
    local okGuid, guid = call(api.UnitGUID, "player")
    me.guid = okGuid and guid or nil
    local okAcct, acct = call(api.GetAccountInfoByGUID, me.guid)
    if okAcct and type(acct) == "table" then
        me.bnetAccountID, me.battleTag = acct.bnetAccountID, acct.battleTag
        local game = acct.gameAccountInfo
        if type(game) == "table" then
            me.gameAccountID, me.wowProjectID, me.regionID = game.gameAccountID, game.wowProjectID, game.regionID
        end
    end
    if me.bnetAccountID == nil or me.battleTag == nil then
        local ok, presenceID, battleTag = call(api.BNGetInfo)
        if ok then
            me.bnetAccountID = me.bnetAccountID or presenceID
            me.battleTag = me.battleTag or battleTag
        end
    end
    if me.wowProjectID == nil or me.regionID == nil then
        local okG, game = call(api.GetGameAccountInfoByGUID, me.guid)
        if okG and type(game) == "table" then
            me.gameAccountID = me.gameAccountID or game.gameAccountID
            me.wowProjectID = me.wowProjectID or game.wowProjectID
            me.regionID = me.regionID or game.regionID
        end
    end
    me.wowProjectID = me.wowProjectID or api.wowProjectID
    return me
end

local function isSelf(info, me)
    if me.guid ~= nil and info.playerGuid == me.guid then
        return true
    end
    return me.gameAccountID ~= nil and info.gameAccountID == me.gameAccountID
end

local function sameBattleNet(info, me)
    if me.bnetAccountID ~= nil and info.bnetAccountID == me.bnetAccountID then
        return true
    end
    return me.battleTag ~= nil and info.battleTag == me.battleTag
end

--- Whether `info` is another of this player's game accounts online in the same game now; else false and
--- why ("self", "offline", "client", "mobile", "project", "region", "bnetUnknown", "bnetAccount").
function LD.IsCandidate(info, me)
    if type(info) ~= "table" or type(me) ~= "table" then
        return false, "bnetUnknown"
    end
    if isSelf(info, me) then
        return false, "self"
    end
    if not info.isOnline then
        return false, "offline"
    end
    if info.clientProgram ~= LD.WOW_CLIENT then
        return false, "client"
    end
    if info.isWowMobile then
        return false, "mobile"
    end
    if me.wowProjectID == nil or info.wowProjectID ~= me.wowProjectID then
        return false, "project"
    end
    if me.regionID ~= nil and info.regionID ~= nil and info.regionID ~= me.regionID then
        return false, "region"
    end
    local known = (me.bnetAccountID ~= nil and info.bnetAccountID ~= nil)
        or (me.battleTag ~= nil and info.battleTag ~= nil)
    if not known then
        return false, "bnetUnknown"
    end
    if not sameBattleNet(info, me) then
        return false, "bnetAccount"
    end
    return true
end

--- Every game account id the client knows (1..MAX_GAME_ACCOUNT_ID), each with `candidate` and `reason`.
--- Our own entry fills in what our presence left blank (region, game account id).
function LD.Scan(api, me)
    local out = {}
    for id = 1, LD.MAX_GAME_ACCOUNT_ID do
        local info = LD.Info(api, id)
        if info then
            out[#out + 1] = info
            if isSelf(info, me) then
                me.gameAccountID = me.gameAccountID or info.gameAccountID
                me.regionID = me.regionID or info.regionID
                me.wowProjectID = me.wowProjectID or info.wowProjectID
            end
        end
    end
    for _, info in ipairs(out) do
        info.candidate, info.reason = LD.IsCandidate(info, me)
    end
    return out
end

--- The candidates of a Scan.
function LD.Candidates(scan)
    local out = {}
    for _, info in ipairs(scan or {}) do
        if info.candidate then
            out[#out + 1] = info
        end
    end
    return out
end

return LD
