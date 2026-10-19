-- AltArmy TBC — Guild data sharing: received guildmate data store.
-- Persists to AltArmyTBC_GuildData, kept fully separate from AltArmyTBC_Data so guild
-- data never contaminates account data and can be wiped independently.
-- Structure: AltArmyTBC_GuildData.chars[realm][key] = { identity + main + Professions }.
-- `key` is the character's ID (GUID) when its sender runs a version that shares IDs, else its
-- name (older senders). Entries always carry `name`; look characters up with GetCharacter, which
-- accepts an ID or a name.
-- A profession can also come straight from the character's own window, read through a profession link
-- while they are online (Guild/GuildLinkRead.lua, SaveLinkRead): `linkReadAt`, `linkRv`, `maxRank` and
-- `skillLine` on the profession, and for a character nobody ever shared (no addon) an entry of its own,
-- `linkOnly`, keyed by GUID like the rest. `linkProbes[realm][guid][skillLine]` remembers the links that
-- went unanswered, so a profession a member hasn't got isn't asked for again soon.

if not AltArmy then return end

AltArmy.GuildShareData = AltArmy.GuildShareData or {}
local GSD = AltArmy.GuildShareData

local function now()
    return (time and time()) or 0
end

local function isNonEmptyString(v)
    return type(v) == "string" and v ~= ""
end
local isNonEmptyGuid = isNonEmptyString

local function ensure()
    _G.AltArmyTBC_GuildData = _G.AltArmyTBC_GuildData or {}
    local d = _G.AltArmyTBC_GuildData
    d.chars = d.chars or {}
    d.linkProbes = d.linkProbes or {}
    return d
end
GSD._Ensure = ensure

local function realmTable(realm, create)
    local d = ensure()
    if not d.chars[realm] and create then
        d.chars[realm] = {}
    end
    return d.chars[realm]
end

--- Key and entry of a stored character: by `guid` when given, else by storage key (ID or legacy
--- name), else by stored name. An entry that carries a different ID than `guid` never matches;
--- a legacy entry without an ID does, so it can be adopted under the ID.
local function findEntry(rt, nameOrKey, guid)
    if not rt then return nil end
    if guid and rt[guid] then return guid, rt[guid] end
    if nameOrKey == nil then return nil end
    local function compatible(entry)
        return type(entry) == "table" and not (guid and entry.guid and entry.guid ~= guid)
    end
    local direct = rt[nameOrKey]
    if compatible(direct) then return nameOrKey, direct end
    for key, entry in pairs(rt) do
        if compatible(entry) and entry.name == nameOrKey then
            return key, entry
        end
    end
    return nil
end

--- Stored entry for a character named in a payload (presence char, card or recipe list).
--- Payloads with an ID match by ID (adopting a legacy name-keyed entry); payloads from older
--- senders match only the legacy name key, never an ID-keyed entry.
local function findPayloadEntry(rt, c)
    if not rt or not c then return nil end
    if c.guid then return findEntry(rt, c.name, c.guid) end
    local entry = rt[c.name]
    if type(entry) == "table" and not entry.guid then return c.name, entry end
    return nil
end

--- Storage key for a payload character: its ID, or its name when the sender shares no IDs.
local function payloadKey(c)
    return c.guid or c.name
end

--- True when `entry` was stored from the character that sent a message. Matches by the sender's
--- ID when both sides have one. An ID-keyed sender never matches a message without an ID (an
--- older client that only shares a short name); a legacy entry matches by sender name.
local function sameSource(entry, sender, fromGuid)
    if type(entry) ~= "table" then return false end
    if entry.sourceGuid then
        return fromGuid ~= nil and entry.sourceGuid == fromGuid
    end
    return sender ~= nil and entry.source == sender
end

--- Whether a received character is a stale first-name copy of another one in `others`
--- (AltArmy.IsFirstNameStub): older senders still share them, and they are never stored or shown.
local function isFirstNameStub(c, others)
    return AltArmy.IsFirstNameStub ~= nil and AltArmy.IsFirstNameStub(c, others)
end

--- Effective main name for a presence: the character with the main's ID when present (so a stale
--- main name cannot split a group), else the declared name.
local function declaredMainName(presence)
    if presence.mainGuid then
        for _, c in ipairs(presence.chars or {}) do
            if c.guid == presence.mainGuid then return c.name end
        end
    end
    return presence.main
end

--- The player's own characters on `realm` (the DataStore's), and those of their linked accounts (the same
--- player's: never guildmates, though each account shares itself with the guild): by GUID and by name.
local function ownCharacters(realm)
    local byGuid, byName = {}, {}
    local DS = AltArmy.DataStore
    if not (DS and DS.GetCharacters) or not realm then return byGuid, byName end
    local function add(key, char)
        if type(char) == "table" then
            if isNonEmptyString(char.guid) then byGuid[char.guid] = true end
            local name = isNonEmptyString(char.name) and char.name or (type(key) == "string" and key or nil)
            if name then byName[name] = true end
        end
    end
    local ok, chars = pcall(DS.GetCharacters, DS, realm)
    if ok and type(chars) == "table" then
        for key, char in pairs(chars) do add(key, char) end
    end
    if DS.ForEachLinkedCharacter then
        pcall(DS.ForEachLinkedCharacter, DS, function(r, key, char)
            if r == realm then add(key, char) end
        end)
    end
    return byGuid, byName
end

--- Whether a received character (a payload character or a stored entry) is one of the player's own: the
--- account's characters are never guildmates. By GUID when it carries one, else by full name. Older
--- clients could store the player's own broadcast as a guildmate: on WoW Forever the sender's full name
--- ("Frell Ofelements") never matched the short name the echo check compared it with ("Frell").
function GSD.IsOwnCharacter(c, realm)
    if type(c) ~= "table" then return false end
    local byGuid, byName = ownCharacters(realm or c.realm)
    if isNonEmptyString(c.guid) then
        if byGuid[c.guid] then return true end
        -- A GUID unknown here can still be ours when the DataStore entry predates GUIDs.
    end
    return isNonEmptyString(c.name) and byName[c.name] == true
end

--- Remove every stored entry that is one of the player's own characters. Returns how many.
function GSD.PurgeOwnCharacters()
    local removed = 0
    for realm, rt in pairs(ensure().chars) do
        for key, entry in pairs(rt) do
            if type(entry) == "table" and GSD.IsOwnCharacter(entry, realm) then
                rt[key] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

--- Pick an implicit main from a candidate list ({ name, char }) so a person's characters
--- still group together when no main was declared. Reuses the onboarding ranking when the UI
--- helper is loaded; otherwise ranks by level, then item level, then name. `opts` (optional)
--- overrides the stat accessors — used for received data whose stats live on the char entry.
local function pickMain(candidates, opts)
    if #candidates == 0 then return nil end
    local GSO = AltArmy.GuildShareOnboarding
    if GSO and GSO.PickDefaultMain then
        local pick = GSO.PickDefaultMain(candidates, opts)
        if pick then return pick end
    end
    local getLevel = (opts and opts.getLevel) or function(c) return (c and c.level) or 0 end
    local getItemLevel = (opts and opts.getItemLevel)
        or function(c) return (c and c.itemLevel) or 0 end
    local best
    for _, cand in ipairs(candidates) do
        if not best then
            best = cand
        else
            local bl, cl = getLevel(best.char), getLevel(cand.char)
            local bi, ci = getItemLevel(best.char), getItemLevel(cand.char)
            local better = cl > bl
                or (cl == bl and ci > bi)
                or (cl == bl and ci == bi and (cand.name or "") < (best.name or ""))
            if better then best = cand end
        end
    end
    return best and best.name or nil
end

--- Implicit main for the local account (chars are DataStore tables ranked by the onboarding
--- accessors: level, gear score, item level, name).
local function defaultLocalMain(entries)
    local candidates = {}
    for _, e in ipairs(entries) do
        candidates[#candidates + 1] = { name = e.name, char = e.char }
    end
    return pickMain(candidates, nil)
end
GSD._DefaultLocalMain = defaultLocalMain

-- Received chars carry only level + item level (no local gear-score provider); rank on those.
local RECEIVED_MAIN_OPTS = {
    getLevel = function(c) return (c and c.level) or 0 end,
    getGearScore = function() return 0 end,
    getItemLevel = function(c) return (c and c.itemLevel) or 0 end,
}

--- Implicit main for a received presence that didn't declare one (chars are payload entries).
local function defaultReceivedMain(chars)
    local candidates = {}
    for _, c in ipairs(chars or {}) do
        candidates[#candidates + 1] = { name = c.name, char = c }
    end
    return pickMain(candidates, RECEIVED_MAIN_OPTS)
end
GSD._DefaultReceivedMain = defaultReceivedMain

GSD.RECIPE_REQUEST_BACKOFF_SEC = 3600

local function profSummaryMatches(storedProf, parsedProf)
    if not storedProf or not parsedProf then return false end
    return storedProf.rank == (parsedProf.rank or 0)
        and storedProf.count == (parsedProf.count or 0)
        and storedProf.rv == (parsedProf.rv or 0)
        and storedProf.spec == parsedProf.spec
end

local function charPresenceMatches(stored, parsedChar)
    if not stored or not parsedChar then return false end
    if stored.classFile ~= parsedChar.classFile then return false end
    if stored.faction ~= parsedChar.faction then return false end
    if stored.level ~= (parsedChar.level or 0) then return false end
    if stored.itemLevel ~= (parsedChar.itemLevel or 0) then return false end

    -- Slim v2 presence: identity + checksum; profession card may still be pending.
    if parsedChar.ch ~= nil then
        if stored.ch ~= parsedChar.ch then return false end
        if stored.needsProfessionCard then return false end
        return true
    end

    local storedProfs = stored.Professions or {}
    local parsedProfs = parsedChar.profs or {}
    if #parsedProfs ~= 0 then
        local seen = {}
        for _, pr in ipairs(parsedProfs) do
            if not profSummaryMatches(storedProfs[pr.key], pr) then
                return false
            end
            seen[pr.key] = true
        end
        for key in pairs(storedProfs) do
            if not seen[key] then return false end
        end
    elseif next(storedProfs) ~= nil then
        return false
    end
    return true
end
GSD._CharPresenceMatches = charPresenceMatches

local function mergeProfessionSummaries(entry, profList)
    local newProfs = {}
    for _, pr in ipairs(profList or {}) do
        local prev = entry.Professions and entry.Professions[pr.key]
        local prof = {
            key = pr.key,
            name = pr.name or pr.key,
            rank = pr.rank or 0,
            count = pr.count or 0,
            rv = pr.rv or 0,
            spec = pr.spec,
        }
        if prev and prev.linkReadAt then
            -- Recipes read from the character's own window outlive the card: they are the server's
            -- answer, newer than whatever the sender's saved data says. A card whose rv is the read's own
            -- means the sender caught up; any other rv asks for another read (or a pull while offline).
            prof.Recipes = prev.Recipes
            prof.linkRv = prev.linkRv
            prof.linkReadAt = prev.linkReadAt
            prof.maxRank = prev.maxRank
            prof.skillLine = prev.skillLine
            prof.recipesRv = (prof.rv == prev.linkRv) and prof.rv or prev.recipesRv
        elseif prev and prev.Recipes and prev.recipesRv == prof.rv then
            prof.Recipes = prev.Recipes
            prof.recipesRv = prev.recipesRv
        end
        if prev and prev.rv == prof.rv and prev.recipesRequestedAt then
            prof.recipesRequestedAt = prev.recipesRequestedAt
        end
        newProfs[pr.key] = prof
    end
    entry.Professions = newProfs
end

--- True when an inbound (parsed) presence matches what is already stored for its chars.
--- Empty presence matches only when this sender has no stored characters on the realm
--- (peers use empty presence to clear after opting out of sharing).
function GSD.PresenceMatchesStored(sender, presence, realm)
    if not presence or type(presence.chars) ~= "table" then
        return false
    end
    realm = realm or "?"
    local rt = realmTable(realm, false)
    if #presence.chars == 0 then
        if not rt or not sender then return true end
        for _, entry in pairs(rt) do
            if sameSource(entry, sender, presence.from) then
                return false
            end
        end
        return true
    end
    local declared = declaredMainName(presence)
    local effectiveMain = declared or defaultReceivedMain(presence.chars)
    local mainDeclared = declared ~= nil
    local displayName = presence.displayName
    local inPresence = {}
    for _, c in ipairs(presence.chars) do
        -- A stale first-name copy is never stored: one stored before makes this a change (below), so
        -- SaveReceived drops it.
        if not isFirstNameStub(c, presence.chars) then
            local key, stored = findPayloadEntry(rt, c)
            if not stored then return false end
            -- A legacy name-keyed entry that now has an ID still needs re-keying.
            if key ~= payloadKey(c) then return false end
            inPresence[key] = true
            if stored.name ~= c.name then return false end
            if stored.main ~= effectiveMain then return false end
            if (stored.mainDeclared == true) ~= mainDeclared then return false end
            if stored.displayName ~= displayName then return false end
            if not charPresenceMatches(stored, c) then return false end
        end
    end
    -- A char previously shared by this sender but omitted from the new presence is a change.
    if rt and sender then
        for key, entry in pairs(rt) do
            if sameSource(entry, sender, presence.from) and not inPresence[key] then
                return false
            end
        end
    end
    return true
end

--- Refresh receivedAt for stored chars advertised in an unchanged presence.
--- Does not rewrite profession/recipe content. Returns true when any timestamp was updated.
function GSD.TouchReceivedAt(sender, presence, realm)
    if not presence or type(presence.chars) ~= "table" or #presence.chars == 0 then
        return false
    end
    realm = realm or "?"
    local ts = now()
    local touched = false
    local rt = realmTable(realm, false)
    for _, c in ipairs(presence.chars) do
        if c and c.name then
            local _, stored = findPayloadEntry(rt, c)
            if stored and (not sender or sameSource(stored, sender, presence.from)) then
                stored.receivedAt = ts
                touched = true
            end
        end
    end
    return touched
end

--- Store an inbound (already parsed) presence for a guild on a realm.
--- Preserves previously pulled recipes when the advertised version is unchanged.
--- Slim v2 chars carry `ch` only: keep Professions when checksum matches, otherwise clear
--- and mark needsProfessionCard for a follow-up CQ.
--- Characters previously received from `sender` that are absent from this presence
--- (including an empty char list after opt-out) are removed.
function GSD.SaveReceived(sender, presence, guild, realm)
    if not presence or type(presence.chars) ~= "table" then return end
    realm = realm or "?"
    local rt = realmTable(realm, true)
    local ts = now()
    -- Honor a sender-declared main; otherwise guess one so their alts still group together.
    local declared = declaredMainName(presence)
    local mainDeclared = declared ~= nil
    local effectiveMain = declared or defaultReceivedMain(presence.chars)
    local keep, keptNames = {}, {}
    local chars = {}
    for _, c in ipairs(presence.chars) do
        if not GSD.IsOwnCharacter(c, realm) and not isFirstNameStub(c, presence.chars) then
            chars[#chars + 1] = c
        end
    end
    for _, c in ipairs(chars) do
        local key = payloadKey(c)
        local oldKey, existing = findPayloadEntry(rt, c)
        if oldKey and oldKey ~= key then
            rt[oldKey] = nil
        end
        local entry = existing or {}
        entry.name = c.name
        entry.realm = realm
        entry.guid = c.guid or entry.guid
        entry.classFile = c.classFile
        entry.faction = c.faction
        entry.level = c.level or 0
        entry.itemLevel = c.itemLevel or 0
        if guild then
            entry.guildName = guild
        end
        entry.main = effectiveMain
        entry.mainGuid = presence.mainGuid
        entry.displayName = presence.displayName
        entry.isMain = (effectiveMain ~= nil and c.name == effectiveMain)
        entry.mainDeclared = mainDeclared
        entry.source = sender
        entry.sourceGuid = presence.from
        entry.receivedAt = ts
        entry.linkOnly = nil

        local hasProfs = type(c.profs) == "table" and #c.profs > 0
        if hasProfs then
            mergeProfessionSummaries(entry, c.profs)
            if c.ch ~= nil then
                entry.ch = c.ch
            end
            entry.needsProfessionCard = false
        elseif c.ch ~= nil then
            local keepProfs = (entry.ch == c.ch)
                and type(entry.Professions) == "table"
                and next(entry.Professions) ~= nil
            entry.ch = c.ch
            if keepProfs then
                entry.needsProfessionCard = false
            else
                -- Keep what was read from the character's own window until the card merges it.
                local linkRead = {}
                for profKey, prof in pairs(entry.Professions or {}) do
                    if type(prof) == "table" and prof.linkReadAt then linkRead[profKey] = prof end
                end
                entry.Professions = linkRead
                entry.needsProfessionCard = true
            end
        else
            -- Legacy empty-profs char: store empty profession map.
            mergeProfessionSummaries(entry, c.profs or {})
            entry.needsProfessionCard = false
        end

        rt[key] = entry
        keep[key] = true
        keptNames[#keptNames + 1] = c.name
    end
    if sender then
        for key, entry in pairs(rt) do
            -- A character nobody shared (read by link) isn't theirs to withdraw.
            if not keep[key] and not entry.linkOnly and sameSource(entry, sender, presence.from) then
                rt[key] = nil
            end
        end
    end
    -- Retire manual mappings that the addon presence confirms.
    local GMG = AltArmy.GuildManualGroups
    if GMG and GMG.RetireIfAgrees and effectiveMain then
        for _, name in ipairs(keptNames) do
            GMG.RetireIfAgrees(name, realm, effectiveMain)
        end
    end
end

--- Characters from a (parsed) presence that still need a whispered profession card.
function GSD.CharsNeedingProfessionCard(presence, realm)
    local out = {}
    if not presence or type(presence.chars) ~= "table" then return out end
    realm = realm or "?"
    local rt = realmTable(realm, false)
    for _, c in ipairs(presence.chars) do
        if c and c.name then
            local _, stored = findPayloadEntry(rt, c)
            if stored and stored.needsProfessionCard then
                out[#out + 1] = { name = c.name, realm = realm, guid = c.guid }
            end
        end
    end
    return out
end

--- Merge an inbound CC profession card into the stored character.
function GSD.SaveCharCard(sender, card, guild, realm)
    if not card or not card.name then return end
    realm = realm or card.realm or "?"
    if GSD.IsOwnCharacter(card, realm) then return end
    local rt = realmTable(realm, true)
    local key = payloadKey(card)
    local oldKey, existing = findPayloadEntry(rt, card)
    if oldKey and oldKey ~= key then
        rt[oldKey] = nil
    end
    local entry = existing or {}
    entry.name = card.name
    entry.realm = realm
    entry.guid = card.guid or entry.guid
    if card.from then entry.sourceGuid = card.from end
    if card.classFile then entry.classFile = card.classFile end
    if card.faction then entry.faction = card.faction end
    entry.level = card.level or entry.level or 0
    entry.itemLevel = card.itemLevel or entry.itemLevel or 0
    if guild then entry.guildName = guild end
    if sender then entry.source = sender end
    entry.receivedAt = now()
    entry.linkOnly = nil
    if card.ch ~= nil then entry.ch = card.ch end
    mergeProfessionSummaries(entry, card.profs or {})
    entry.needsProfessionCard = false
    rt[key] = entry
end

--- Store a pulled recipe payload; reconstructs a minimal Recipes map ({ [id] = { primaryRecipeID = id } }).
--- A profession read from the character's own window within LINK_READ_WINS_SEC is left alone: the
--- payload comes from the sender's saved data, the read from the server.
function GSD.SaveRecipes(realm, payload)
    if not payload or not payload.name or type(payload.profs) ~= "table" then return end
    local rt = realmTable(realm, false)
    local _, entry = findPayloadEntry(rt, payload)
    if not entry then return end
    entry.Professions = entry.Professions or {}
    local P = AltArmy.GuildShareProtocol
    local ts = now()
    for _, pr in ipairs(payload.profs) do
        local prof = entry.Professions[pr.key]
        if not prof then
            prof = { key = pr.key, name = pr.key, rank = 0, count = 0, rv = 0 }
            entry.Professions[pr.key] = prof
        end
        if not (prof.linkReadAt and (ts - prof.linkReadAt) < GSD.LINK_READ_WINS_SEC) then
            local recipes = {}
            for _, id in ipairs(pr.ids or {}) do
                recipes[id] = { primaryRecipeID = id }
            end
            prof.Recipes = recipes
            prof.count = #(pr.ids or {})
            prof.recipesRv = P and P.HashRecipeIDs(pr.ids or {}) or 0
            prof.linkReadAt = nil
            prof.linkRv = nil
        end
    end
end

-- *** Professions read through profession links (Guild/GuildLinkRead.lua) ***

GSD.LINK_READ_WINS_SEC = 600            -- a pulled list this soon after a read is older than the read
GSD.LINK_REREAD_SEC = 3 * 24 * 3600     -- a character nobody shares is read again after this long
GSD.LINK_NEGATIVE_BACKOFF_DAYS = { 1, 3, 7, 30 } -- days before a profession that never answered is asked again

local function probeTable(realm, guid, create)
    local d = ensure()
    local byRealm = d.linkProbes[realm]
    if not byRealm then
        if not create then return nil end
        byRealm = {}
        d.linkProbes[realm] = byRealm
    end
    local probes = byRealm[guid]
    if not probes and create then
        probes = {}
        byRealm[guid] = probes
    end
    return probes
end

--- How long a profession whose link went unanswered `misses` times waits before it is asked again.
function GSD.LinkProbeBackoffSec(misses)
    local days = GSD.LINK_NEGATIVE_BACKOFF_DAYS
    local n = math.max(1, math.min(tonumber(misses) or 1, #days))
    return days[n] * 24 * 3600
end

--- What is remembered of a member's unanswered link for a skill line: { triedAt, misses }, or nil.
function GSD.GetLinkProbe(realm, guid, skillLine)
    local probes = probeTable(realm, guid, false)
    return probes and probes[skillLine] or nil
end

--- Remember that a member's link for a skill line went unanswered.
function GSD.MarkLinkTried(realm, guid, skillLine, nowTs)
    if type(guid) ~= "string" or guid == "" or type(skillLine) ~= "number" then return end
    local probes = probeTable(realm, guid, true)
    local probe = probes[skillLine] or { misses = 0 }
    probe.triedAt = nowTs or now()
    probe.misses = (probe.misses or 0) + 1
    probes[skillLine] = probe
end

function GSD.ClearLinkProbe(realm, guid, skillLine)
    local probes = probeTable(realm, guid, false)
    if probes then probes[skillLine] = nil end
end

--- Forget every profession read from a window whose recipe list was another profession's: a read taken
--- before the client refreshed the list (a guildmate's First Aid stored as their Cooking, seen 2026-10-18),
--- stored before OwnRecipeRead checked for it. The planner reads them again. Returns how many were dropped.
function GSD.DropForeignLinkReads()
    local RI = AltArmy.RecipeInfo
    if not (RI and RI.RecipesFitProfession and RI.IsAvailable and RI.IsAvailable()) then return 0 end
    local dropped = 0
    for _, rt in pairs(ensure().chars) do
        for _, entry in pairs(rt) do
            local profs = type(entry) == "table" and entry.Professions or nil
            if type(profs) == "table" then
                for key, prof in pairs(profs) do
                    if type(prof) == "table" and prof.linkReadAt and type(prof.Recipes) == "table" then
                        local ids = {}
                        for id in pairs(prof.Recipes) do ids[#ids + 1] = id end
                        if not RI.RecipesFitProfession(ids, prof.key or key) then
                            profs[key] = nil
                            dropped = dropped + 1
                        end
                    end
                end
            end
        end
    end
    return dropped
end

--- Remember that a member hasn't got a profession (the server answered its link with an empty window), and
--- forget any stored copy of it read from their window before (they dropped it). Asked again after
--- LINK_REREAD_SEC or when their level moved. Returns true when a stored profession was removed.
function GSD.MarkLinkAbsent(realm, guid, skillLine, profKey, nowTs, level)
    if type(guid) ~= "string" or guid == "" or type(skillLine) ~= "number" then return false end
    local probes = probeTable(realm, guid, true)
    probes[skillLine] = { triedAt = nowTs or now(), absent = true, misses = 0, level = tonumber(level) }
    local _, entry = findEntry(realmTable(realm, false), nil, guid)
    local profs = entry and entry.Professions
    local prof = profs and isNonEmptyString(profKey) and profs[profKey] or nil
    if prof and prof.linkReadAt then
        profs[profKey] = nil
        return true
    end
    return false
end

--- Remove professions stored from an empty answer (skill 0 of max 0, no recipes) by builds that didn't
--- know the server answers links for professions a player hasn't got, remembering them as absent.
--- Returns how many.
function GSD.PurgeEmptyLinkReads()
    local removed = 0
    for realm, rt in pairs(ensure().chars) do
        for _, entry in pairs(rt) do
            if type(entry) == "table" and type(entry.Professions) == "table" then
                for key, prof in pairs(entry.Professions) do
                    if type(prof) == "table" and prof.linkReadAt and (tonumber(prof.maxRank) or 0) == 0
                        and (tonumber(prof.count) or 0) == 0 then
                        entry.Professions[key] = nil
                        removed = removed + 1
                        if isNonEmptyString(entry.guid) and type(prof.skillLine) == "number" then
                            probeTable(realm, entry.guid, true)[prof.skillLine] = {
                                triedAt = prof.linkReadAt, absent = true, misses = 0,
                                level = tonumber(entry.linkLevel),
                            }
                        end
                    end
                end
            end
        end
    end
    return removed
end

--- Store one profession read from a character's own window. For a character nobody shared this makes the
--- entry (`linkOnly`, grouped by any manual mapping, else on its own). After it, the profession's
--- recipesRv equals its rv, so nothing is pulled for it until the sender's card says it changed.
--- info = { guid, name, guildName, classFile, level, profKey, profName, skillLine, rank, maxRank, ids,
--- readAt }. Returns the entry.
function GSD.SaveLinkRead(realm, info)
    if type(info) ~= "table" or not isNonEmptyGuid(info.guid) or not isNonEmptyString(info.name)
        or not isNonEmptyString(info.profKey) then
        return nil
    end
    realm = realm or "?"
    if GSD.IsOwnCharacter({ guid = info.guid, name = info.name }, realm) then return nil end
    local rt = realmTable(realm, true)
    local oldKey, existing = findEntry(rt, info.name, info.guid)
    if oldKey and oldKey ~= info.guid then
        rt[oldKey] = nil
    end
    local ts = info.readAt or now()
    local entry = existing or {}
    local shared = existing ~= nil and not existing.linkOnly
    if not shared then
        entry.linkOnly = true
        entry.name = info.name
        entry.source = info.name
        entry.sourceGuid = info.guid
        if isNonEmptyString(info.classFile) then entry.classFile = info.classFile end
        if tonumber(info.level) then entry.level = tonumber(info.level) end
        entry.level = entry.level or 0
        entry.itemLevel = entry.itemLevel or 0
        local GMG = AltArmy.GuildManualGroups
        local mapped = GMG and GMG.GetMainOf and GMG.GetMainOf(info.name, realm) or nil
        entry.main = mapped or info.name
        entry.isMain = entry.main == info.name
        entry.mainDeclared = false
        entry.needsProfessionCard = false
    end
    entry.realm = realm
    entry.guid = info.guid
    if isNonEmptyString(info.guildName) then entry.guildName = info.guildName end
    if tonumber(info.level) then entry.linkLevel = tonumber(info.level) end
    entry.receivedAt = ts

    entry.Professions = entry.Professions or {}
    local prof = entry.Professions[info.profKey]
    if not prof then
        prof = { key = info.profKey, name = info.profName or info.profKey, rank = 0, count = 0, rv = 0 }
        entry.Professions[info.profKey] = prof
    end
    if isNonEmptyString(info.profName) then prof.name = info.profName end
    if tonumber(info.rank) then prof.rank = tonumber(info.rank) end
    if tonumber(info.maxRank) then prof.maxRank = tonumber(info.maxRank) end
    prof.skillLine = info.skillLine
    local ids = {}
    for _, id in ipairs(info.ids or {}) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local recipes = {}
    for _, id in ipairs(ids) do recipes[id] = { primaryRecipeID = id } end
    prof.Recipes = recipes
    prof.count = #ids
    local P = AltArmy.GuildShareProtocol
    prof.linkRv = P and P.HashRecipeIDs(ids) or 0
    prof.linkReadAt = ts
    if not shared or not prof.rv or prof.rv == 0 then
        prof.rv = prof.linkRv
    end
    prof.recipesRv = prof.rv
    prof.recipesRequestedAt = nil
    GSD.ClearLinkProbe(realm, info.guid, info.skillLine)
    rt[info.guid] = entry
    return entry
end

--- The skill lines worth reading for an online member, in the order of `lines` ({ { skillLine, key },
--- ... }): each as { skillLine, key, reason }. A member who shares through Alt Army (an entry from their
--- presence) needs none: their recipes come by the guild share messages. Anyone else (no Alt Army, or
--- Alt Army with sharing off) is probed line by line (`probe`), each unanswered line waiting out its
--- backoff, and a line read before is read again after LINK_REREAD_SEC (`stale`) or when the member's
--- level moved (`level-changed`). member = { guid, name, level }.
function GSD.GetSkillLinesNeedingLinkRead(realm, member, nowTs, lines)
    nowTs = nowTs or now()
    local out = {}
    if type(member) ~= "table" or not isNonEmptyGuid(member.guid) then return out end
    local rt = realmTable(realm or "?", false)
    local _, entry = findEntry(rt, member.name, member.guid)
    if entry and not entry.linkOnly then return out end -- shares through Alt Army
    local profs = entry and entry.Professions or {}
    for _, line in ipairs(lines or {}) do
        local prof = profs[line.key]
        local probe = GSD.GetLinkProbe(realm, member.guid, line.skillLine)
        if prof and prof.linkReadAt then
            if (nowTs - prof.linkReadAt) >= GSD.LINK_REREAD_SEC then
                out[#out + 1] = { skillLine = line.skillLine, key = line.key, reason = "stale" }
            elseif tonumber(member.level) and tonumber(entry.linkLevel)
                and tonumber(member.level) ~= tonumber(entry.linkLevel) then
                out[#out + 1] = { skillLine = line.skillLine, key = line.key, reason = "level-changed" }
            end
        elseif probe and probe.absent then
            -- They hadn't got it: ask again once LINK_REREAD_SEC passed or they levelled.
            local levelled = tonumber(member.level) and tonumber(probe.level)
                and tonumber(member.level) ~= tonumber(probe.level)
            if levelled or (nowTs - (probe.triedAt or 0)) >= GSD.LINK_REREAD_SEC then
                out[#out + 1] = { skillLine = line.skillLine, key = line.key, reason = "probe" }
            end
        elseif not (probe and probe.triedAt
            and (nowTs - probe.triedAt) < GSD.LinkProbeBackoffSec(probe.misses)) then
            out[#out + 1] = { skillLine = line.skillLine, key = line.key, reason = "probe" }
        end
    end
    return out
end

-- *** Getters ***

--- A stored character on `realm`, by ID (storage key) or by name.
function GSD.GetCharacter(nameOrKey, realm)
    local _, entry = findEntry(realmTable(realm, false), nameOrKey)
    return entry
end

--- Find a stored character by name or ID. When realm is omitted, searches all realms.
function GSD.FindCharacter(name, realm)
    if realm then
        return GSD.GetCharacter(name, realm)
    end
    local d = ensure()
    for _, rt in pairs(d.chars) do
        local _, hit = findEntry(rt, name)
        if hit then return hit end
    end
    return nil
end

--- All stored characters in a guild (across realms), as a flat list.
function GSD.GetGuildMembers(guild)
    local out = {}
    local d = ensure()
    for _, rt in pairs(d.chars) do
        for _, entry in pairs(rt) do
            if entry.guildName == guild then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

local function professionsFromChar(char)
    local profs = {}
    local P = AltArmy.GuildShareProtocol
    if not P or not P.BuildProfessionSummaries then return profs end
    for _, pr in ipairs(P.BuildProfessionSummaries(char)) do
        profs[pr.key] = {
            key = pr.key,
            name = pr.name or pr.key,
            rank = pr.rank or 0,
            count = pr.count or 0,
            rv = pr.rv or 0,
            spec = pr.spec,
        }
    end
    return profs
end

--- Build a guild-tab member entry from local account data (not received over comm).
--- `mainDeclared` is true when `mainName` came from the player's saved main setting.
function GSD.BuildLocalMemberEntry(name, realm, char, guild, mainName, displayName, mainDeclared)
    local charName = (char and char.name) or name
    return {
        name = charName,
        realm = realm,
        guid = char and char.guid,
        classFile = char and char.classFile or "",
        faction = char and char.faction or "",
        level = (char and char.level) or 0,
        guildName = guild,
        main = mainName,
        displayName = displayName,
        isMain = (mainName ~= nil and charName == mainName),
        mainDeclared = mainDeclared and true or false,
        source = "local",
        Professions = professionsFromChar(char),
    }
end

--- Account characters in `guild` on `realm` formatted for the guild tab.
function GSD.GetLocalGuildMembers(guild, realm)
    local out = {}
    if not guild then return out end
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm and not realm then
        realm = GSS._CurrentRealm()
    end
    realm = realm or ""
    local displayName = GSS and GSS.GetDisplayName and GSS.GetDisplayName(realm) or nil
    local entries = (GSS and GSS.GetAllGuildedCharacters
        and GSS.GetAllGuildedCharacters(guild, realm)) or {}
    -- Without an explicit main, group everyone under an implicit default main.
    local savedMain = GSS and GSS.GetMain and GSS.GetMain(realm) or nil
    local mainDeclared = savedMain ~= nil
    local mainName = savedMain or defaultLocalMain(entries)
    for _, entry in ipairs(entries) do
        out[#out + 1] = GSD.BuildLocalMemberEntry(
            entry.name, entry.realm, entry.char, guild, mainName, displayName, mainDeclared)
    end
    return out
end

--- Account characters in `guild` across every stored realm (for browsing when not guilded).
function GSD.GetLocalGuildMembersAllRealms(guild)
    local out = {}
    if not guild then return out end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms then return out end
    for realm in pairs(DS:GetRealms()) do
        for _, entry in ipairs(GSD.GetLocalGuildMembers(guild, realm)) do
            out[#out + 1] = entry
        end
    end
    return out
end

local function memberKey(entry)
    return (entry.realm or "") .. "\0" .. (entry.name or "")
end

--- Received guildmates plus local account characters (local wins on name+realm conflict).
--- When `allLocalRealms` is true, merges local account characters from every realm.
--- Unshadowed manual mappings (GuildManualGroups) are appended with source = "manual".
--- Optional `rosterInfoMap` (from GTD.BuildRosterInfoMap) enriches classFile/level on
--- manual stubs; keys are normalized lowercase short names. When roster info is missing
--- (e.g. not currently in a guild), falls back to classFile/level stored on the mapping.
function GSD.GetGuildMembersForDisplay(guild, realm, allLocalRealms, rosterInfoMap)
    local byKey = {}
    for _, entry in ipairs(GSD.GetGuildMembers(guild)) do
        byKey[memberKey(entry)] = entry
    end
    if allLocalRealms then
        for _, entry in ipairs(GSD.GetLocalGuildMembersAllRealms(guild)) do
            byKey[memberKey(entry)] = entry
        end
    else
        for _, entry in ipairs(GSD.GetLocalGuildMembers(guild, realm)) do
            byKey[memberKey(entry)] = entry
        end
    end

    local GMG = AltArmy.GuildManualGroups
    -- Characters a manual or note mapping places in a group: as a member, or as the group's main.
    local mapped = {}
    if GMG and GMG.GetMappingsForGuild and guild then
        for _, mapping in ipairs(GMG.GetMappingsForGuild(guild)) do
            mapped[memberKey({ realm = mapping.realm, name = mapping.name })] = true
            if type(mapping.main) == "string" and mapping.main ~= "" then
                mapped[memberKey({ realm = mapping.realm, name = mapping.main })] = true
            end
        end
    end
    if GMG and GMG.GetMappingsForGuild and guild then
        local GTD = AltArmy.GuildTabData
        local normalize = GTD and GTD.NormalizeRosterName
        local function rosterInfoFor(name)
            if not rosterInfoMap or not name then return nil end
            local key = normalize and normalize(name) or (name and name:lower())
            return key and rosterInfoMap[key] or nil
        end
        local function makeManualEntry(name, entryRealm, main, mapping, isMain)
            local info = rosterInfoFor(name)
            local classFile = ""
            if info and type(info.classFile) == "string" and info.classFile ~= "" then
                classFile = info.classFile
            elseif mapping and type(mapping.classFile) == "string" and mapping.classFile ~= "" then
                classFile = mapping.classFile
            end
            local level = 0
            local rosterLevel = info and tonumber(info.level)
            local storedLevel = mapping and tonumber(mapping.level)
            if rosterLevel and rosterLevel > 0 then
                level = rosterLevel
            elseif storedLevel and storedLevel > 0 then
                level = storedLevel
            end
            return {
                name = name,
                realm = entryRealm,
                classFile = classFile,
                level = level,
                guildName = guild,
                main = main,
                isMain = isMain and true or false,
                mainDeclared = false,
                source = "manual",
                origin = mapping and mapping.origin or "user",
                noteText = mapping and mapping.noteText or nil,
                Professions = {},
            }
        end
        local mainsNeeded = {}
        for _, mapping in ipairs(GMG.GetMappingsForGuild(guild)) do
            local key = memberKey({ realm = mapping.realm, name = mapping.name })
            local existing = byKey[key]
            if not existing then
                byKey[key] = makeManualEntry(
                    mapping.name, mapping.realm, mapping.main, mapping, mapping.name == mapping.main)
            elseif existing.linkOnly and mapping.main and mapping.main ~= "" then
                -- A character read by link, nobody's to group: the mapping says whose alt it is.
                local shown = {}
                for k, v in pairs(existing) do shown[k] = v end
                shown.main = mapping.main
                shown.isMain = mapping.name == mapping.main
                shown.origin = mapping.origin
                shown.noteText = mapping.noteText
                byKey[key] = shown
            end
            if (not existing or existing.linkOnly) and mapping.main and mapping.main ~= "" then
                mainsNeeded[memberKey({ realm = mapping.realm, name = mapping.main })] = {
                    name = mapping.main,
                    realm = mapping.realm,
                }
            end
        end
        for key, mainInfo in pairs(mainsNeeded) do
            if not byKey[key] then
                local mainMapping = GMG.GetMapping and GMG.GetMapping(mainInfo.name, mainInfo.realm)
                byKey[key] = makeManualEntry(
                    mainInfo.name, mainInfo.realm, mainInfo.name, mainMapping, true)
            end
        end
    end

    -- Received characters per sender, to hide the stale first-name copies stored before SaveReceived
    -- dropped them (gone with the sender's next presence).
    local bySender = {}
    local function senderKey(entry)
        local sender = entry.sourceGuid or entry.source
        if entry.source == "local" or entry.source == "manual" or sender == nil then return nil end
        return (entry.realm or "") .. "\0" .. tostring(sender)
    end
    for _, entry in pairs(byKey) do
        local sk = senderKey(entry)
        if sk then
            bySender[sk] = bySender[sk] or {}
            table.insert(bySender[sk], entry)
        end
    end
    local GTD = AltArmy.GuildTabData
    local normalize = GTD and GTD.NormalizeRosterName

    local out = {}
    for key, entry in pairs(byKey) do
        local sk = senderKey(entry)
        if sk and isFirstNameStub(entry, bySender[sk]) then
            entry = nil
        elseif sk and rosterInfoMap then
            -- A received character's level is the one it was shared at; the live roster's is now.
            local info = rosterInfoMap[normalize and normalize(entry.name) or (entry.name or ""):lower()]
            local rosterLevel = info and tonumber(info.level)
            local rosterClass = info and info.classFile
            local newLevel = rosterLevel and rosterLevel > 0 and rosterLevel ~= entry.level
            local newClass = (entry.classFile == nil or entry.classFile == "")
                and type(rosterClass) == "string" and rosterClass ~= ""
            if newLevel or newClass then
                local shown = {}
                for k, v in pairs(entry) do shown[k] = v end
                if newLevel then shown.level = rosterLevel end
                if newClass then shown.classFile = rosterClass end
                entry = shown
            end
        end
        if entry and entry.linkOnly and not mapped[key] then
            -- Read by link and grouped by nothing (no presence, note or mapping): shown as a group of its
            -- own that the group editor treats as free to place elsewhere (autoGroup).
            local shown = {}
            for k, v in pairs(entry) do shown[k] = v end
            shown.autoGroup = true
            entry = shown
        end
        if entry then out[#out + 1] = entry end
    end
    return out
end

--- Resolve an alt to its main. A main resolves to itself. Unknown characters return nil.
--- Falls through to GuildManualGroups when no received/local stored character matches.
function GSD.GetMainOf(name, realm)
    -- If a realm is supplied, use it; otherwise search all realms.
    local function fromEntry(entry)
        if not entry then return nil end
        if entry.linkOnly then
            -- Nobody shared this character: any grouping the user or a guild note gives it wins.
            local GMG = AltArmy.GuildManualGroups
            local mapped = GMG and GMG.GetMainOf and GMG.GetMainOf(entry.name, entry.realm)
            if mapped then return mapped end
        end
        return entry.main or entry.name
    end
    if realm then
        local hit = fromEntry(GSD.GetCharacter(name, realm))
        if hit then return hit end
    else
        local d = ensure()
        for _, rt in pairs(d.chars) do
            local _, entry = findEntry(rt, name)
            local hit = fromEntry(entry)
            if hit then return hit end
        end
    end
    local GMG = AltArmy.GuildManualGroups
    if GMG and GMG.GetMainOf then
        return GMG.GetMainOf(name, realm)
    end
    return nil
end

--- Professions map for a stored character (each prof may carry a Recipes map once pulled).
function GSD.GetRecipesFor(name, realm)
    local entry = GSD.GetCharacter(name, realm)
    return entry and entry.Professions or {}
end

--- Profession keys for a character whose recipe lists still need to be pulled.
function GSD.GetProfessionsNeedingRecipes(name, realm, nowTs)
    nowTs = nowTs or now()
    local out = {}
    local entry = GSD.GetCharacter(name, realm)
    if not entry or not entry.Professions then return out end
    local backoff = GSD.RECIPE_REQUEST_BACKOFF_SEC or 3600
    for key, prof in pairs(entry.Professions) do
        if not prof.Recipes or prof.recipesRv ~= prof.rv then
            local requestedAt = prof.recipesRequestedAt
            local inBackoff = requestedAt and (nowTs - requestedAt) < backoff
            if not inBackoff then
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

--- Record that recipe lists were requested for the given profession keys.
function GSD.MarkRecipesRequested(name, realm, profKeys, nowTs)
    if type(profKeys) ~= "table" or #profKeys == 0 then return end
    local entry = GSD.GetCharacter(name, realm)
    if not entry or not entry.Professions then return end
    nowTs = nowTs or now()
    for _, key in ipairs(profKeys) do
        local prof = entry.Professions[key]
        if prof then
            prof.recipesRequestedAt = nowTs
        end
    end
end

-- *** Purging ***

function GSD.PurgeGuild(guild)
    local d = ensure()
    for _, rt in pairs(d.chars) do
        for name, entry in pairs(rt) do
            if entry.guildName == guild then
                rt[name] = nil
            end
        end
    end
    local GMG = AltArmy.GuildManualGroups
    if GMG and GMG.ClearGuild then
        GMG.ClearGuild(guild)
    end
end

--- Remove entries older than maxAgeSeconds. Returns the number removed.
--- Stale received characters are converted to local manual mappings (grouping only;
--- recipes and other share payloads are discarded) unless a mapping already exists.
function GSD.PurgeStale(maxAgeSeconds, nowTs)
    nowTs = nowTs or now()
    local removed = 0
    local d = ensure()
    for realm, rt in pairs(d.chars) do
        for key, entry in pairs(rt) do
            local ts = entry.receivedAt or 0
            if (nowTs - ts) > maxAgeSeconds then
                -- Manual mappings are keyed by name (roster names), never by ID.
                GSD.ConvertReceivedToManual(entry.name or key, realm, entry)
                rt[key] = nil
                removed = removed + 1
            end
        end
    end
    for realm, byGuid in pairs(d.linkProbes) do
        for guid, probes in pairs(byGuid) do
            for skillLine, probe in pairs(probes) do
                if (nowTs - (probe.triedAt or 0)) > maxAgeSeconds then probes[skillLine] = nil end
            end
            if next(probes) == nil then byGuid[guid] = nil end
        end
        if next(byGuid) == nil then d.linkProbes[realm] = nil end
    end
    return removed
end

--- Write a manual name→main mapping from a received character about to be purged.
--- Does not overwrite an existing mapping (including user/note groupings).
--- @return boolean true when a mapping was written
function GSD.ConvertReceivedToManual(name, realm, entry)
    local GMG = AltArmy.GuildManualGroups
    if not (GMG and GMG.SetMapping and GMG.GetMapping) then return false end
    if type(name) ~= "string" or name == "" then return false end
    if GMG.GetMapping(name, realm) then return false end
    entry = entry or {}
    local main = entry.main
    if type(main) ~= "string" or main == "" then
        main = name
    end
    GMG.SetMapping(name, realm, main, {
        guild = entry.guildName,
        origin = "user",
        classFile = entry.classFile,
        level = entry.level,
    })
    return true
end

function GSD.PurgeAll()
    local d = ensure()
    d.chars = {}
    local GMG = AltArmy.GuildManualGroups
    if GMG and GMG.ClearAll then
        GMG.ClearAll()
    end
end

--- Remove every stored character whose effective main equals `main`.
--- When `realm` is set, only that realm is searched. Returns the number removed.
function GSD.RemoveGroup(main, realm)
    if type(main) ~= "string" or main == "" then return 0 end
    local removed = 0
    local d = ensure()
    local function purgeRealmTable(rt)
        if not rt then return end
        for name, entry in pairs(rt) do
            local entryMain = (entry and (entry.main or entry.name)) or name
            if entryMain == main then
                rt[name] = nil
                removed = removed + 1
            end
        end
    end
    if realm then
        purgeRealmTable(d.chars[realm])
    else
        for _, rt in pairs(d.chars) do
            purgeRealmTable(rt)
        end
    end
    return removed
end
