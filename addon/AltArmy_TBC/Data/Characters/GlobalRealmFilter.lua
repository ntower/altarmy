-- AltArmy TBC — Which characters every tab shows (Summary/Gear/Reputation/Search/Cooldowns/Graphs/...).
-- The scope, AltArmyTBC_Options.characterScope = { version, otherFaction, otherRealms, linked }: this realm's
-- characters of your faction always show; the other faction on this realm, other realms, and linked
-- accounts' characters each by a toggle (RealmFilter.inScope). Default: only this realm and faction (linked
-- accounts on, once there are any).
-- AltArmyTBC_Options.realmFilter ("all" | "currentRealm") was the setting before it and is kept in step
-- (otherRealms), so G.Get() still answers "all" | "currentRealm" for the realm suffixes and an older addon
-- still reads it. The scope is made from it once: "all realms" turns on other realms and the other faction,
-- "current realm" neither. realmFilter itself came from the per-tab settings once: "all" only when
-- every legacy per-tab setting (Summary, Gear, Reputation, Search) was "all".

if not AltArmy then return end

AltArmy.GlobalRealmFilter = AltArmy.GlobalRealmFilter or {}
local G = AltArmy.GlobalRealmFilter

--- @param tab table|nil
--- @return string|nil "all", "currentRealm", or nil if missing / invalid
local function legacyRealmFromTab(tab)
    if type(tab) ~= "table" then
        return nil
    end
    local v = tab.realmFilter
    if v == "all" or v == "currentRealm" then
        return v
    end
    return nil
end

--- Exported for unit tests: four legacy values (each nil | "all" | "currentRealm").
--- @return string "all" or "currentRealm"
function G.ResolveFromLegacyValues(summary, gear, rep, search)
    if summary == "all" and gear == "all" and rep == "all" and search == "all" then
        return "all"
    end
    return "currentRealm"
end

local function readLegacyTabs()
    return
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_SummarySettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_GearSettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_ReputationSettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_SearchSettings"))
end

function G.MigrateFromLegacyIfNeeded()
    local root = rawget(_G, "AltArmyTBC_Options")
    if not root or type(root) ~= "table" then
        return
    end
    if root.realmFilter ~= nil then
        return
    end
    local s, ge, r, se = readLegacyTabs()
    root.realmFilter = G.ResolveFromLegacyValues(s, ge, r, se)
end

G.SCOPE_VERSION = 1

--- After the scope changed: tabs rebuild their lists when shown; drop the cached character list and redraw
--- the Summary if it is open.
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

--- The scope made from a realmFilter value (exported for tests).
function G.ScopeFromRealmFilter(realmFilter)
    return {
        version = G.SCOPE_VERSION,
        otherFaction = realmFilter == "all",
        otherRealms = realmFilter == "all",
        linked = true,
    }
end

function G.Ensure()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    G.MigrateFromLegacyIfNeeded()
    if AltArmyTBC_Options.realmFilter ~= "all" and AltArmyTBC_Options.realmFilter ~= "currentRealm" then
        AltArmyTBC_Options.realmFilter = "currentRealm"
    end
    local scope = AltArmyTBC_Options.characterScope
    if type(scope) ~= "table" or scope.version ~= G.SCOPE_VERSION then
        AltArmyTBC_Options.characterScope = G.ScopeFromRealmFilter(AltArmyTBC_Options.realmFilter)
    end
    -- an older addon may have changed realmFilter since: it wins for the realms
    AltArmyTBC_Options.characterScope.otherRealms = AltArmyTBC_Options.realmFilter == "all"
end

--- @return "all"|"currentRealm" whether other realms show ("all") or only this one
function G.Get()
    G.Ensure()
    return AltArmyTBC_Options.realmFilter
end

--- @param v "all"|"currentRealm"
function G.Set(v)
    G.Ensure()
    if v == "all" or v == "currentRealm" then
        G.SetScope("otherRealms", v == "all")
    end
end

--- The scope: { otherFaction, otherRealms, linked } (booleans; the table is the saved one: don't change it).
function G.GetScope()
    G.Ensure()
    return AltArmyTBC_Options.characterScope
end

--- Turn one of the scope's toggles on or off ("otherFaction", "otherRealms", "linked").
function G.SetScope(key, on)
    G.Ensure()
    if key ~= "otherFaction" and key ~= "otherRealms" and key ~= "linked" then
        return
    end
    AltArmyTBC_Options.characterScope[key] = on and true or false
    if key == "otherRealms" then
        AltArmyTBC_Options.realmFilter = on and "all" or "currentRealm"
    end
    if AltArmy.RefreshCharacterViews then
        AltArmy.RefreshCharacterViews()
    end
end

--- Back to the defaults (Options' Defaults button).
function G.ResetScope()
    G.Ensure()
    AltArmyTBC_Options.realmFilter = "currentRealm"
    AltArmyTBC_Options.characterScope = G.ScopeFromRealmFilter("currentRealm")
    if AltArmy.RefreshCharacterViews then
        AltArmy.RefreshCharacterViews()
    end
end

local function currentFaction()
    return UnitFactionGroup and UnitFactionGroup("player") or nil --luacheck: ignore 113
end

--- A saved character's faction, for a list entry that doesn't carry one (by realm and name).
local function factionLookup()
    local DS = AltArmy.DataStore
    local cache = {}
    return function(e)
        local name = e.name or e.characterName or e.charName
        if not (DS and DS.GetCharacter and name and e.realm) then
            return nil
        end
        local key = e.realm .. "|" .. name
        if cache[key] == nil then
            local char = DS.GetCharacterAny and DS:GetCharacterAny(name, e.realm) or DS:GetCharacter(name, e.realm)
            cache[key] = char and char.faction or false
        end
        return cache[key] or nil
    end
end

--- `list` (entries with .realm, and .faction or a name to look it up by) narrowed to the scope.
--- @param currentRealm string|nil defaults to GetRealmName()
function G.FilterList(list, currentRealm)
    local RF = AltArmy.RealmFilter
    currentRealm = currentRealm or (GetRealmName and GetRealmName()) or "" --luacheck: ignore 113
    return RF.filterListByScope(list or {}, G.GetScope(), currentRealm, currentFaction(), factionLookup())
end

--- Whether one character (realm, faction, linkId) is in scope.
function G.Includes(entry, currentRealm)
    local RF = AltArmy.RealmFilter
    currentRealm = currentRealm or (GetRealmName and GetRealmName()) or "" --luacheck: ignore 113
    local faction = entry.faction
    if faction == nil then
        faction = factionLookup()(entry)
    end
    return RF.inScope(entry, faction, G.GetScope(), currentRealm, currentFaction())
end

G.Ensure()
