-- AltArmy TBC — The Summary's "Group characters": a character list as sections per realm
-- and faction, each under a header, flattened to one element per row so the Summary's row pool scrolls it by
-- index; and where the sticky headers go (SearchStickyHeaders' rule: a header sticks to the top until the
-- next one pushes it out). Pure.

AltArmy = AltArmy or {}
AltArmy.CharacterSections = AltArmy.CharacterSections or {}
local CS = AltArmy.CharacterSections

-- Realms as RealmFilter has them (Forever's coalesced realms are one), the names themselves without it.
local function group(realm)
    local RF = AltArmy.RealmFilter
    return RF and RF.realmGroup and RF.realmGroup(realm) or (realm or "")
end

local function label(realm)
    local RF = AltArmy.RealmFilter
    return RF and RF.realmLabel and RF.realmLabel(realm) or (realm or "")
end

--- The key a section is saved under (the Summary's collapsed sections): "Realm|Faction".
function CS.SectionKey(realm, faction)
    return (realm or "") .. "|" .. (faction or "")
end

--- "Realm — Faction (n)", or "Realm (n)" when the faction isn't known.
--- "Realm — Faction", or "Realm" when the faction isn't known (a group's name in dropdowns and lists).
function CS.GroupLabel(realm, faction)
    if faction and faction ~= "" then
        return label(realm) .. " — " .. faction
    end
    return label(realm)
end

function CS.SectionLabel(realm, faction, count)
    local text = label(realm)
    if faction and faction ~= "" then
        text = text .. " — " .. faction
    end
    return text .. " (" .. (count or 0) .. ")"
end

--- Section order: this realm first, other realms A to Z; within a realm the current faction, then the
--- others A to Z, an unknown faction last.
local function sectionBefore(a, b, currentRealm, currentFaction)
    local aHome, bHome = a.group == currentRealm, b.group == currentRealm
    if aHome ~= bHome then
        return aHome
    end
    if a.group ~= b.group then
        return a.group < b.group
    end
    local function rank(s)
        if s.faction == "" then return 2 end
        if s.faction == currentFaction then return 0 end
        return 1
    end
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then
        return ra < rb
    end
    return a.faction < b.faction
end

--- `list` split by realm and faction, in section order: { { realm, group, faction, entries }, ... }, each
--- section's entries in `list`'s order (the Summary's sections, the pin and hide dropdowns' groups). Coalesced
--- realms are one section: `group` is theirs (RealmFilter.realmGroup), `realm` its first character's.
function CS.Group(list, currentRealm, currentFaction)
    local sections, byKey = {}, {}
    for i = 1, #(list or {}) do
        local e = list[i]
        local realmGroup, faction = group(e.realm), e.faction or ""
        local key = CS.SectionKey(realmGroup, faction)
        local s = byKey[key]
        if not s then
            s = { realm = e.realm or "", group = realmGroup, faction = faction, entries = {} }
            byKey[key] = s
            sections[#sections + 1] = s
        end
        s.entries[#s.entries + 1] = e
    end
    currentRealm = group(currentRealm)
    table.sort(sections, function(a, b)
        return sectionBefore(a, b, currentRealm, currentFaction)
    end)
    return sections
end

--- The rows to draw: { kind = "char", entry } each, and when grouped a
--- { kind = "header", key, label, count, collapsed } before each realm and faction's characters (kept in
--- `list`'s order), which a collapsed section leaves out.
--- @param opts table { grouped, currentRealm, currentFaction, collapsed = { [SectionKey] = true } }
function CS.BuildElements(list, opts)
    opts = opts or {}
    local elements = {}
    if not opts.grouped then
        for i = 1, #(list or {}) do
            elements[i] = { kind = "char", entry = list[i] }
        end
        return elements
    end
    local collapsed = opts.collapsed or {}
    for _, s in ipairs(CS.Group(list, opts.currentRealm, opts.currentFaction)) do
        local n = #s.entries
        local key = CS.SectionKey(s.group, s.faction)
        local folded = collapsed[key] == true
        elements[#elements + 1] = {
            kind = "header",
            key = key,
            realm = s.realm,
            faction = s.faction,
            count = n,
            collapsed = folded,
            label = CS.SectionLabel(s.realm, s.faction, n),
        }
        if not folded then
            for _, e in ipairs(s.entries) do
                elements[#elements + 1] = { kind = "char", entry = e }
            end
        end
    end
    return elements
end

--- Where to draw each header in a viewport showing `visibleRows` rows from element `offset + 1`:
--- { { elementIndex, top (px below the viewport's top), key, label, collapsed }, ... }, only those in view.
function CS.StickyHeaderLayout(elements, offset, visibleRows, rowHeight)
    local Sticky = AltArmy.SearchStickyHeaders
    local headerTops, indices = {}, {}
    for i, el in ipairs(elements or {}) do
        if el.kind == "header" then
            headerTops[#headerTops + 1] = (i - 1) * rowHeight
            indices[#indices + 1] = i
        end
    end
    if #headerTops == 0 or not (Sticky and Sticky.ComputeStickyTops) then
        return {}
    end
    local stickyTops = Sticky.ComputeStickyTops(headerTops, (offset or 0) * rowHeight, rowHeight)
    local out = {}
    local bottom = (visibleRows or 0) * rowHeight
    for k, top in ipairs(stickyTops) do
        if top > -rowHeight and top < bottom then
            local i = indices[k]
            local el = elements[i]
            out[#out + 1] = { elementIndex = i, top = top, key = el.key, label = el.label,
                collapsed = el.collapsed == true }
        end
    end
    return out
end
