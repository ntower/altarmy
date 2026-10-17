-- AltArmy TBC — A pretend linked account, for trying the linked-accounts display without a second client.
-- Manual diagnostic only (debug on): /altarmy debug link fake [n] copies n of this account's characters
-- (3 by default) into a linked account labelled "Test account", through the same path a sync takes
-- (LinkDomains.Extract, then LinkStore.Receive, which checks every unit): each copy gets its own GUID, a
-- name ending in "Copy" and, every other one, the other faction. /altarmy debug link clear unlinks it.

AltArmy = AltArmy or {}
AltArmy.LinkHarness = AltArmy.LinkHarness or {}
local H = AltArmy.LinkHarness

H.ACCOUNT_ID = "debugtestaccount"
H.LABEL = "Test account"

local OTHER_FACTION = { Horde = "Alliance", Alliance = "Horde" }

local function notify(msg)
    local D = AltArmy.Debug
    if D and D.NotifyChat then
        D.NotifyChat("|cff00ccff[Alt Army:Link]|r " .. msg)
    end
end

-- A GUID no real character has: the server's, then this copy's own hex.
local function fakeGuid(guid, i)
    local server = type(guid) == "string" and guid:match("^Player%-(%d+)%-") or "1"
    return string.format("Player-%s-FFFF%04X", server, i)
end

--- Copy up to `n` of `ownRoot`'s characters into the test account; returns how many went in, and the
--- reasons units were refused (reason -> count).
function H.Fake(n, ownRoot, now)
    local Dom, S = AltArmy.LinkDomains, AltArmy.LinkStore
    n = n or 3
    S.SetLink(H.ACCOUNT_ID, { kind = "own", label = H.LABEL, confirmed = true, linkedAt = now })
    local made, refused = 0, {}
    local sources = {}
    for realm, chars in pairs(ownRoot and ownRoot.Characters or {}) do
        for _, char in pairs(chars) do
            if type(char) == "table" and char.name and char.faction then
                sources[#sources + 1] = { realm = realm, char = char }
            end
        end
    end
    table.sort(sources, function(a, b) return (a.char.name or "") < (b.char.name or "") end)
    for i = 1, math.min(n, #sources) do
        local src = sources[i]
        local guid = fakeGuid(src.char.guid, i)
        local ok = true
        for _, domain in ipairs(Dom.ORDER) do
            local unit = Dom.Extract(src.char, domain)
            if domain == "identity" then
                unit.guid = guid
                unit.realm = src.realm
                unit.name = (src.char.name or "?") .. " Copy"
                if i % 2 == 0 then
                    unit.faction = OTHER_FACTION[unit.faction] or unit.faction
                end
            end
            local got, why = S.Receive(H.ACCOUNT_ID, src.realm, guid, domain, unit, now)
            if not got then
                refused[why] = (refused[why] or 0) + 1
                if domain == "identity" then
                    ok = false
                    break
                end
            end
        end
        if ok then
            made = made + 1
        end
    end
    S.ReceiveMeta(H.ACCOUNT_ID, Dom.ExtractMeta(ownRoot), ownRoot)
    return made, refused
end

function H.Clear()
    AltArmy.LinkStore.Unlink(H.ACCOUNT_ID)
end

--- /altarmy debug link fake [n] | clear
function H.Command(rest)
    local D = AltArmy.Debug
    if not (D and D.IsEnabled and D.IsEnabled()) then
        notify("Turn debug on first: /altarmy debug on")
        return
    end
    local verb, arg = (rest or ""):match("^(%S*)%s*(%S*)")
    if verb == "fake" then
        local made, refused = H.Fake(tonumber(arg) or 3, AltArmyTBC_Data, time and time() or 0) --luacheck: ignore 113
        local why = {}
        for k, v in pairs(refused) do
            why[#why + 1] = k .. " x" .. v
        end
        notify(string.format("Test account: %d character(s) linked.%s", made,
            #why > 0 and (" Refused: " .. table.concat(why, ", ")) or ""))
    elseif verb == "clear" then
        H.Clear()
        notify("Test account unlinked.")
    else
        notify("Usage: /altarmy debug link fake [n] | clear")
    end
end

return H
