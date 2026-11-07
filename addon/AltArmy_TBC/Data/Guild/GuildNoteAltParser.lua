-- AltArmy TBC — Parse guild public/officer notes for main/alt suggestions.
-- Pure: no frames. Candidates must match a roster name (false-positive guard).
-- Scan produces a review list; nothing is written automatically.

if not AltArmy then return end

AltArmy.GuildNoteAltParser = AltArmy.GuildNoteAltParser or {}
local GNP = AltArmy.GuildNoteAltParser

--- Patch 12.0+ clients (Forever included) can hand GetGuildRosterInfo() names/notes
--- to addons as Secret Values that error on any operation beyond store/pass.
--- `canaccessvalue()` (existence-checked) is the guard, matching
--- DataStoreProfessions.lua's fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

local function normalizeKey(name)
    local GTD = AltArmy.GuildTabData
    if GTD and GTD.NormalizeRosterName then
        return GTD.NormalizeRosterName(name)
    end
    if type(name) ~= "string" then return nil end
    local short = name:match("^[^%-]+") or name
    return short:lower()
end

local function resolveRosterMain(candidate, rosterNameSet)
    if type(candidate) ~= "string" or candidate == "" then return nil end
    local key = normalizeKey(candidate)
    if not key then return nil end
    local hit = rosterNameSet[key]
    if type(hit) == "string" then
        return hit
    end
    if hit then
        -- Boolean set: recover casing from key (caller should prefer name map).
        return candidate
    end
    return nil
end

--- Deterministic hash of note text (for detecting edits after accept).
function GNP.HashNote(text)
    text = tostring(text or "")
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % 2147483647
    end
    return h
end

-- Tokens that make a "Name - …" note look like profession / craft info rather than
-- a relationship or role label ("Unburdened - Wife").
local PROFESSION_LIKE_TOKENS = {
    alchemy = true, alch = true,
    blacksmithing = true, bs = true,
    enchanting = true, ench = true,
    engineering = true, eng = true,
    jewelcrafting = true, jc = true,
    leatherworking = true, lw = true,
    tailoring = true, tailor = true,
    herbalism = true, herb = true,
    mining = true, min = true,
    skinning = true, ski = true,
    -- Common TBC craft specializations / cloth lines
    spellfire = true,
    spellcloth = true,
    mooncloth = true,
    shadoweave = true,
    shadowcloth = true,
    transmute = true,
}

--- True when `suffix` looks like profession text (e.g. "lw/ski", "Spellfire Specialty").
function GNP.IsProfessionLikeSuffix(suffix)
    if type(suffix) ~= "string" then return false end
    local text = suffix:match("^%s*(.-)%s*$") or ""
    if text == "" then return false end
    text = text:lower()

    if text:find("/", 1, true) then
        local any = false
        for part in text:gmatch("[^/%s]+") do
            any = true
            if not PROFESSION_LIKE_TOKENS[part] then
                return false
            end
        end
        return any
    end

    if PROFESSION_LIKE_TOKENS[text] then
        return true
    end
    for word in text:gmatch("[%a%d]+") do
        if PROFESSION_LIKE_TOKENS[word] then
            return true
        end
    end
    return false
end

--- Parse a single note against a roster name set.
--- `rosterNameSet` maps lowercase short name → display name (preferred) or true.
--- Returns `{ main, pattern }` or nil.
function GNP.ParseNote(note, rosterNameSet)
    if type(note) ~= "string" then return nil end
    local trimmed = note:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return nil end
    rosterNameSet = rosterNameSet or {}

    local patterns = {
        { "alt_of", "[Aa][Ll][Tt]%s+[Oo][Ff]%s+([%a%d]+)" },
        { "possessive_alt", "([%a%d]+)'[Ss]%s+[Aa][Ll][Tt]" },
        -- "serint not berint alt" → Serint (must precede name_alt)
        { "not_other_alt", "([%a%d]+)%s+[Nn][Oo][Tt]%s+[%a%d]+%s+[Aa][Ll][Tt]" },
        { "name_alt", "([%a%d]+)%s+[Aa][Ll][Tt]" },
        { "main_is", "[Mm][Aa][Ii][Nn]%s+[Ii][Ss]%s+([%a%d]+)" },
        { "label", "[Mm][Aa][Ii][Nn]%s*:%s*([%a%d]+)" },
        { "label", "[Aa][Ll][Tt]%s*:%s*([%a%d]+)" },
        { "equals", "^=%s*([%a%d]+)" },
        { "parens", "%(([%a%d]+)%)" },
        -- "Celewi - Spellfire Specialty", "Serint - lw/ski" (suffix must be profession-like)
        { "name_dash", "^([%a%d]+)%s*%-%s*(%S.*)$", true },
        { "bare", "^([%a%d]+)%s*$" },
    }

    for _, entry in ipairs(patterns) do
        local patternName, pat, needsProfessionSuffix = entry[1], entry[2], entry[3]
        local cand, suffix = trimmed:match(pat)
        if cand then
            if needsProfessionSuffix and not GNP.IsProfessionLikeSuffix(suffix) then
                cand = nil
            end
        end
        if cand then
            local main = resolveRosterMain(cand, rosterNameSet)
            if main then
                return { main = main, pattern = patternName }
            end
        end
    end
    return nil
end

local function buildRosterNameSet(rosterEntries)
    local set = {}
    for _, e in ipairs(rosterEntries or {}) do
        if e and type(e.name) == "string" and e.name ~= "" then
            local key = normalizeKey(e.name)
            if key then
                local short = e.name:match("^[^%-]+") or e.name
                set[key] = short
            end
        end
    end
    return set
end

local function pickNoteText(entry)
    local public = type(entry.publicNote) == "string" and entry.publicNote or ""
    local officer = type(entry.officerNote) == "string" and entry.officerNote or ""
    local publicTrim = public:match("^%s*(.-)%s*$") or ""
    local officerTrim = officer:match("^%s*(.-)%s*$") or ""
    if publicTrim ~= "" then return publicTrim end
    if officerTrim ~= "" then return officerTrim end
    return nil
end

--- Scan roster entries for alt/main suggestions.
--- `existingMappings`: name → mapping entry (with optional noteHash/origin)
--- `storedChars`: name → truthy when addon data already covers the character
--- Returns list of `{ name, main, noteText, noteHash, pattern }`.
--- Lookups against existingMappings / storedChars are case-insensitive.
function GNP.ScanRoster(rosterEntries, existingMappings, storedChars)
    local out = {}
    existingMappings = existingMappings or {}
    storedChars = storedChars or {}
    local rosterSet = buildRosterNameSet(rosterEntries)

    local function lookupByName(map, name, short)
        if not map then return nil end
        local hit = map[short] or map[name]
        if hit then return hit end
        local key = normalizeKey(short or name)
        if not key then return nil end
        for k, v in pairs(map) do
            if type(k) == "string" and normalizeKey(k) == key then
                return v
            end
        end
        return nil
    end

    for _, entry in ipairs(rosterEntries or {}) do
        if entry and type(entry.name) == "string" and entry.name ~= "" then
            local short = entry.name:match("^[^%-]+") or entry.name
            if not lookupByName(storedChars, entry.name, short) then
                local noteText = pickNoteText(entry)
                if noteText then
                    local parsed = GNP.ParseNote(noteText, rosterSet)
                    if parsed and normalizeKey(parsed.main) ~= normalizeKey(short) then
                        local existing = lookupByName(existingMappings, entry.name, short)
                        local noteHash = GNP.HashNote(noteText)
                        local skip = false
                        if existing and existing.origin == "note"
                            and existing.noteHash == noteHash then
                            skip = true
                        elseif existing and existing.origin == "user" then
                            -- User-confirmed mapping: don't re-suggest from notes.
                            skip = true
                        end
                        if not skip then
                            out[#out + 1] = {
                                name = short,
                                main = parsed.main,
                                noteText = noteText,
                                noteHash = noteHash,
                                pattern = parsed.pattern,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

--- Walk name→main edges until a root (someone who is not themselves an alt).
--- `nameToMain` maps normalizeKey(name) → display main name.
--- Returns the root main, or nil if a cycle is detected.
local function resolveUltimateMain(claimedMain, nameToMain)
    if type(claimedMain) ~= "string" or claimedMain == "" then return nil end
    local current = claimedMain
    local seen = {}
    while true do
        local key = normalizeKey(current)
        if not key then return current end
        if seen[key] then
            return nil
        end
        local nextMain = nameToMain[key]
        if not nextMain then
            return current
        end
        seen[key] = true
        current = nextMain
    end
end

--- Rewrite suggestion mains so alt-of-alt chains point at the root main.
--- Chain edges (lowest to highest priority when building the graph):
---   1. `sharedEntries` — `{ name, main }` from Alt Army shared data (self-mains ignored)
---   2. `existingMappings` — name → { main = ... } local manual mappings
---   3. current note `suggestions` — name → main
--- Example: shared B→A plus note C→B ⇒ C collapses under A.
--- Does not mutate the input list or its entries. Drops suggestions that would
--- become self-mappings after collapse. On cycles, keeps the original main.
function GNP.CollapseSuggestionChains(suggestions, existingMappings, sharedEntries)
    local out = {}
    if not suggestions then return out end

    local nameToMain = {}
    for _, e in ipairs(sharedEntries or {}) do
        if e and type(e.name) == "string" and e.name ~= ""
            and type(e.main) == "string" and e.main ~= "" then
            local nameKey = normalizeKey(e.name)
            local mainKey = normalizeKey(e.main)
            if nameKey and mainKey and nameKey ~= mainKey then
                nameToMain[nameKey] = e.main
            end
        end
    end
    for name, mapping in pairs(existingMappings or {}) do
        if type(name) == "string" and mapping and type(mapping.main) == "string" and mapping.main ~= "" then
            local key = normalizeKey(name)
            local mainKey = normalizeKey(mapping.main)
            if key and mainKey and key ~= mainKey then
                nameToMain[key] = mapping.main
            end
        end
    end
    for _, s in ipairs(suggestions) do
        if s and type(s.name) == "string" and s.name ~= ""
            and type(s.main) == "string" and s.main ~= "" then
            local key = normalizeKey(s.name)
            if key then
                nameToMain[key] = s.main
            end
        end
    end

    for _, s in ipairs(suggestions) do
        if s and type(s.name) == "string" and s.name ~= ""
            and type(s.main) == "string" and s.main ~= "" then
            local resolved = resolveUltimateMain(s.main, nameToMain)
            if not resolved then
                resolved = s.main
            end
            if normalizeKey(resolved) ~= normalizeKey(s.name) then
                out[#out + 1] = {
                    name = s.name,
                    main = resolved,
                    noteText = s.noteText,
                    noteHash = s.noteHash,
                    pattern = s.pattern,
                }
            end
        end
    end
    return out
end

--- Collapse flat ScanRoster suggestions into one editable proposal per main.
--- Chains (alt-of-alt) are collapsed onto the root main first, including edges from
--- optional `existingMappings` and Alt Army `sharedEntries`.
--- Existing local mappings already under a proposed main are merged into `members`
--- (marked `alreadyMapped`) so prior accepts remain visible when reviewing again.
--- Mains that differ only by case are merged into one proposal (canonical casing
--- from the first suggestion that creates the group).
--- Returns `{ main, displayName, members = { name, noteText, noteHash, pattern, alreadyMapped? } }`
--- sorted by main. Members within a group are sorted by name. Does not include the main
--- as a member row (the main is implied by `main` / `displayName`).
function GNP.GroupSuggestionsByMain(suggestions, existingMappings, sharedEntries)
    suggestions = GNP.CollapseSuggestionChains(suggestions, existingMappings, sharedEntries)
    local byMain = {}
    local order = {}
    for _, s in ipairs(suggestions) do
        if s and type(s.main) == "string" and s.main ~= "" and type(s.name) == "string" and s.name ~= "" then
            local mainKey = normalizeKey(s.main)
            local g = mainKey and byMain[mainKey]
            if not g then
                g = {
                    main = s.main,
                    displayName = s.main,
                    members = {},
                }
                if mainKey then
                    byMain[mainKey] = g
                end
                order[#order + 1] = g
            end
            g.members[#g.members + 1] = {
                name = s.name,
                noteText = s.noteText,
                noteHash = s.noteHash,
                pattern = s.pattern,
            }
        end
    end
    for _, g in ipairs(order) do
        local mainKey = normalizeKey(g.main)
        local seen = {}
        if mainKey then
            seen[mainKey] = true
        end
        for _, m in ipairs(g.members) do
            local key = m and normalizeKey(m.name)
            if key then seen[key] = true end
        end
        for name, mapping in pairs(existingMappings or {}) do
            if type(name) == "string" and name ~= ""
                and mapping and type(mapping.main) == "string" and mapping.main ~= ""
                and normalizeKey(mapping.main) == mainKey then
                local nameKey = normalizeKey(name)
                if nameKey and not seen[nameKey] then
                    seen[nameKey] = true
                    local short = name:match("^[^%-]+") or name
                    g.members[#g.members + 1] = {
                        name = short,
                        noteText = mapping.noteText,
                        noteHash = mapping.noteHash,
                        origin = mapping.origin,
                        alreadyMapped = true,
                    }
                end
            end
        end
        table.sort(g.members, function(a, b)
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end
    table.sort(order, function(a, b)
        return (a.main or ""):lower() < (b.main or ""):lower()
    end)
    return order
end

local SHARED_REASON = "From Alt Army shared data"

--- Attach Alt Army shared-group context to note proposals.
--- `sharedEntries`: `{ name, main [, displayName] }` from guild share data (local/received).
--- Sets on each proposal:
---   `mainFromShared` — true when the proposed main is known from shared data
---   `knownMembers` — other shared characters under that main (excludes the main and
---     note-deduced `members`), sorted by name
---   `displayName` — shared preferred name when present (may differ from `main`)
--- Mutates and returns `proposals` (or `{}` when nil).
function GNP.EnrichProposalsWithSharedData(proposals, sharedEntries)
    if not proposals then return {} end
    local byMain = {}
    local nameIsShared = {}
    local preferredByMain = {}
    for _, e in ipairs(sharedEntries or {}) do
        if e and type(e.name) == "string" and e.name ~= ""
            and type(e.main) == "string" and e.main ~= "" then
            local nameKey = normalizeKey(e.name)
            local mainKey = normalizeKey(e.main)
            if nameKey then
                nameIsShared[nameKey] = true
            end
            if mainKey then
                local list = byMain[mainKey]
                if not list then
                    list = {}
                    byMain[mainKey] = list
                end
                list[#list + 1] = e.name
                if type(e.displayName) == "string" and e.displayName ~= "" then
                    local pref = preferredByMain[mainKey]
                    -- Prefer the main character's shared display name when available.
                    if not pref or nameKey == mainKey then
                        preferredByMain[mainKey] = e.displayName
                    end
                end
            end
        end
    end
    for _, p in ipairs(proposals) do
        if p and type(p.main) == "string" then
            local mainKey = normalizeKey(p.main)
            local exclude = {}
            if mainKey then
                exclude[mainKey] = true
            end
            for _, m in ipairs(p.members or {}) do
                local key = m and normalizeKey(m.name)
                if key then exclude[key] = true end
            end
            local group = (mainKey and byMain[mainKey]) or {}
            local known = {}
            local seen = {}
            for _, name in ipairs(group) do
                local key = normalizeKey(name)
                if key and not exclude[key] and not seen[key] then
                    seen[key] = true
                    known[#known + 1] = { name = name }
                end
            end
            table.sort(known, function(a, b)
                return (a.name or ""):lower() < (b.name or ""):lower()
            end)
            p.knownMembers = known
            p.mainFromShared = (mainKey and nameIsShared[mainKey] == true)
                or (#group > 0)
            p.sharedReason = SHARED_REASON
            if p.mainFromShared and mainKey and preferredByMain[mainKey] then
                p.displayName = preferredByMain[mainKey]
            end
        end
    end
    return proposals
end

--- Drop / trim note proposals that involve excluded account characters.
--- `excludedNames`: set of normalized (or raw) names — typically the player's
--- configured main plus local account characters. A proposal is removed when its
--- `main` is excluded, or when every note-deduced member was excluded. Excluded
--- names are also stripped from `members` and `knownMembers`.
--- Returns a new list (does not mutate the input proposals' member arrays in place
--- when filtering; proposal tables that are kept may be shallow-copied).
function GNP.FilterProposalsExcludingNames(proposals, excludedNames)
    if not proposals then return {} end
    if type(excludedNames) ~= "table" then
        local copy = {}
        for i, p in ipairs(proposals) do
            copy[i] = p
        end
        return copy
    end
    local excluded = {}
    for key, on in pairs(excludedNames) do
        if on then
            local nk = normalizeKey(key)
            if nk then excluded[nk] = true end
        end
    end
    local out = {}
    for _, p in ipairs(proposals) do
        if p and type(p.main) == "string" and p.main ~= "" then
            local mainKey = normalizeKey(p.main)
            if not (mainKey and excluded[mainKey]) then
                local members = {}
                for _, m in ipairs(p.members or {}) do
                    local key = m and normalizeKey(m.name)
                    if key and not excluded[key] then
                        members[#members + 1] = m
                    end
                end
                if #members > 0 then
                    local known = {}
                    for _, m in ipairs(p.knownMembers or {}) do
                        local key = m and normalizeKey(m.name)
                        if key and not excluded[key] then
                            known[#known + 1] = m
                        end
                    end
                    out[#out + 1] = {
                        main = p.main,
                        displayName = p.displayName,
                        members = members,
                        knownMembers = known,
                        mainFromShared = p.mainFromShared,
                        sharedReason = p.sharedReason,
                        manual = p.manual,
                    }
                end
            end
        end
    end
    return out
end

--- Normalized-name set of every main, member, and knownMember across all proposals.
--- Used by the notes wizard add-box so a character cannot be added to two proposals.
function GNP.CollectProposalOccupiedNames(proposals)
    local set = {}
    for _, p in ipairs(proposals or {}) do
        if p then
            local mainKey = normalizeKey(p.main)
            if mainKey then set[mainKey] = true end
            for _, m in ipairs(p.members or {}) do
                local key = m and normalizeKey(m.name)
                if key then set[key] = true end
            end
            for _, m in ipairs(p.knownMembers or {}) do
                local key = m and normalizeKey(m.name)
                if key then set[key] = true end
            end
        end
    end
    return set
end

--- Manual mappings whose character no longer appears on the roster.
--- Returns `{ name, main, origin }`.
function GNP.FindStaleMappings(existingMappings, rosterEntries)
    local onRoster = {}
    for _, e in ipairs(rosterEntries or {}) do
        if e and e.name then
            local key = normalizeKey(e.name)
            if key then onRoster[key] = true end
        end
    end
    local out = {}
    for name, mapping in pairs(existingMappings or {}) do
        local key = normalizeKey(name)
        if key and not onRoster[key] and mapping then
            out[#out + 1] = {
                name = name,
                main = mapping.main,
                origin = mapping.origin,
            }
        end
    end
    table.sort(out, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

--- Build roster entries with notes from injectable guild roster APIs.
--- `api` may override: isInGuild, getNumGuildMembers, getGuildRosterInfo.
function GNP.BuildRosterNoteEntries(api)
    api = api or {}
    local isInGuild = api.isInGuild or IsInGuild
    local getNum = api.getNumGuildMembers or GetNumGuildMembers
    local getInfo = api.getGuildRosterInfo or GetGuildRosterInfo
    local out = {}
    if not isInGuild or not isInGuild() then return out end
    if not getNum or not getInfo then return out end
    local n = getNum()
    if type(n) ~= "number" or n < 1 then return out end
    for i = 1, n do
        -- name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName
        local name, _, _, _, _, _, publicNote, officerNote = getInfo(i)
        if type(name) == "string" and canAccessSecretValue(name) and name ~= "" then
            local short = name:match("^[^%-]+") or name
            if not canAccessSecretValue(publicNote) then publicNote = "" end
            if not canAccessSecretValue(officerNote) then officerNote = "" end
            out[#out + 1] = {
                name = short,
                publicNote = publicNote or "",
                officerNote = officerNote or "",
            }
        end
    end
    return out
end
