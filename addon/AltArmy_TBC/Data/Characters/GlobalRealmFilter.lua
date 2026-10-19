-- AltArmy TBC — Which characters the tabs without a realm filter of their own show (Search, Inventory, Graphs,
-- Cooldowns, cooldown alerts, the gear compare panel): the Summary tab's realm filter
-- (AltArmyTBC_SummarySettings.filter.scope, CharacterFilter.lua), which the Summary's settings panel edits.
-- This realm's characters of your faction always show; the other faction on this realm, other realms and
-- linked accounts' characters each by its toggle (RealmFilter.inScope). Summary, Gear, Reputation and Currency
-- filter by their own CharacterFilter.
-- The old global scope (AltArmyTBC_Options.characterScope, and realmFilter before it) only seeds each tab's
-- first filter (CharacterFilter.Ensure); nothing writes it any more.

if not AltArmy then return end

AltArmy.GlobalRealmFilter = AltArmy.GlobalRealmFilter or {}
local G = AltArmy.GlobalRealmFilter

--- After a realm filter changed: tabs rebuild their lists when shown; drop the cached character list and
--- redraw the Summary and the open grids.
function AltArmy.RefreshCharacterViews()
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.SearchData and AltArmy.SearchData.ClearCaches then
        AltArmy.SearchData.ClearCaches() -- its item and recipe lists include linked accounts' or not
    end
    if AltArmy.RefreshSummary then
        AltArmy.RefreshSummary()
    end
    -- the open grid tab redraws (the others rebuild when shown)
    local tabs = AltArmy.TabFrames or {}
    for _, key in ipairs({ "Gear", "Reputation" }) do
        local f = tabs[key]
        if f and f.RefreshGrid and f.IsVisible and f:IsVisible() then
            f:RefreshGrid()
        end
    end
    local economy = tabs.Economy
    if economy and economy.RefreshCurrency then
        economy.RefreshCurrency() -- only while its panel is visible
    end
end

--- The Summary tab's filter (made if missing).
function G.Ensure()
    _G.AltArmyTBC_SummarySettings = _G.AltArmyTBC_SummarySettings or {}
    return AltArmy.CharacterFilter.Ensure(AltArmyTBC_SummarySettings)
end

--- The scope: { otherFaction, otherRealms, linked } (the saved table: change it through the Summary's panel).
function G.GetScope()
    return G.Ensure().scope
end

--- @return "all"|"currentRealm" whether other realms show ("all") or only this one
function G.Get()
    return G.GetScope().otherRealms and "all" or "currentRealm"
end

local function context(currentRealm)
    return AltArmy.CharacterFilter.Context(currentRealm)
end

--- `list` (entries with .realm, and .faction or a name to look it up by) narrowed to the scope.
--- @param currentRealm string|nil defaults to GetRealmName()
function G.FilterList(list, currentRealm)
    return AltArmy.CharacterFilter.FilterList(list or {}, G.Ensure(), context(currentRealm), { scopeOnly = true })
end

--- Whether one character (realm, faction, linkId) is in scope.
function G.Includes(entry, currentRealm)
    return AltArmy.CharacterFilter.InScope(entry, G.Ensure(), context(currentRealm))
end
