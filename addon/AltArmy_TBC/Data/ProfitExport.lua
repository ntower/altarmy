-- AltArmy TBC — Export for the Alt Army website: characters, professions and learned recipes as one
-- printable string, pasted on the site's Upload tab instead of uploading AltArmy_TBC.lua.
--
-- Format (v2): "AAX1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(lines)), where lines are
--   V|2|<interface>|<build>|<account id>          the client, so the site knows which game it is, and this
--                                                 WoW account (AltArmyTBC_Data.accountId; omitted if unset)
--   C|<realm>|<name>|<faction>|<CLASS_FILE>|<level>|<guid>
--   P|<profession>|<rank>|<maxRank>|<recipe ids>  belongs to the C line before it; ids comma-separated
--   T|<spell id>|<rank>                           a Legacy talent of the C line before it (rank > 0)
--   R|<faction id>|<standing>                     its standing (1 Hated .. 8 Exalted) with a city faction
-- Recipe ids are craft spell ids, aliases resolved to primaryRecipeID (as the site reads the file). Talents
-- are char.legacyTalents.spells (DataStoreLegacy.lua, data version 2), sorted by spell id. Reputations are
-- char.Reputations (DataStoreReputations.lua, data version 2) for CITY_FACTIONS only, sorted by faction id:
-- the site discounts vendor prices by them, and no other faction's vendors stand in the cities. A faction
-- with no saved row (untouched Neutral) gets no line.
-- Characters are sorted by name within a realm. The name is char.name (the full name), else the storage key;
-- the GUID is char.guid, empty for entries saved before GUIDs (character data v3 keys entries by GUID).
-- v1 had no GUID and wrote the storage key as the name, which is a GUID since character data v3.
-- The site parses it in site/src/altarmy_site/paste.py; spec/fixtures/profit_export_v2.txt is the golden
-- string both test against.

AltArmy = AltArmy or {}

local ProfitExport = {}
AltArmy.ProfitExport = ProfitExport

ProfitExport.PREFIX = "AAX1:"

-- The factions whose vendors stand in the cities (the site's reputation.CITY_FACTIONS: change both together).
ProfitExport.CITY_FACTIONS = {
    47, -- Ironforge
    54, -- Gnomeregan Exiles
    68, -- Undercity
    69, -- Darnassus
    72, -- Stormwind
    76, -- Orgrimmar
    81, -- Thunder Bluff
    530, -- Darkspear Trolls
}

local function field(value)
    return (tostring(value or ""):gsub("[|\r\n]", ""))
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- Recipe ids a profession has learned, each alias counted once under its primary id, ascending.
local function recipeIds(prof)
    local seen, ids = {}, {}
    for key, row in pairs(prof.Recipes or {}) do
        local id = type(row) == "table" and type(row.primaryRecipeID) == "number" and row.primaryRecipeID or key
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- A realm's characters as sorted { name, char } pairs: by name, then storage key.
local function charactersByName(byKey)
    local out = {}
    for key, char in pairs(byKey or {}) do
        if type(char) == "table" then
            local name = type(char.name) == "string" and char.name ~= "" and char.name or tostring(key)
            out[#out + 1] = { name, char, tostring(key) }
        end
    end
    table.sort(out, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[3] < b[3]
    end)
    return out
end

--- A character's Legacy talents as sorted {spell id, rank} pairs; none from v1 data (no `spells`).
local function legacyTalents(char)
    local spells = type(char.legacyTalents) == "table" and char.legacyTalents.spells
    local out = {}
    if type(spells) ~= "table" then
        return out
    end
    for spellID, rank in pairs(spells) do
        if type(spellID) == "number" and type(rank) == "number" and rank > 0 then
            out[#out + 1] = { spellID, rank }
        end
    end
    table.sort(out, function(a, b)
        return a[1] < b[1]
    end)
    return out
end

--- A character's standings with the city factions as {faction id, standing} pairs, by faction id; none from
--- v1 rows (bare numbers) or a standing the game doesn't have.
local function cityReputations(char)
    local saved = type(char.Reputations) == "table" and char.Reputations or {}
    local out = {}
    for _, factionID in ipairs(ProfitExport.CITY_FACTIONS) do
        local row = saved[factionID]
        local standing = type(row) == "table" and row.s
        if type(standing) == "number" and standing >= 1 and standing <= 8 then
            out[#out + 1] = { factionID, standing }
        end
    end
    return out
end

--- The export's text: `characters` is AltArmyTBC_Data.Characters (realm -> storage key -> character).
--- @return string
function ProfitExport.Lines(characters, interface, build, accountId)
    local head = { "V", "2", field(interface), field(build) }
    if accountId and accountId ~= "" then
        head[#head + 1] = field(accountId)
    end
    local out = { table.concat(head, "|") }
    for _, realm in ipairs(sortedKeys(characters)) do
        for _, entry in ipairs(charactersByName(characters[realm])) do
            local name, char = entry[1], entry[2]
            out[#out + 1] = table.concat({
                "C", field(realm), field(name), field(char.faction), field(char.classFile), field(char.level or 0),
                field(char.guid),
            }, "|")
            for _, profName in ipairs(sortedKeys(char.Professions)) do
                local prof = char.Professions[profName]
                if type(prof) == "table" then
                    out[#out + 1] = table.concat({
                        "P", field(profName), field(prof.rank or 0), field(prof.maxRank or 0),
                        table.concat(recipeIds(prof), ","),
                    }, "|")
                end
            end
            for _, talent in ipairs(legacyTalents(char)) do
                out[#out + 1] = table.concat({ "T", field(talent[1]), field(talent[2]) }, "|")
            end
            for _, rep in ipairs(cityReputations(char)) do
                out[#out + 1] = table.concat({ "R", field(rep[1]), field(rep[2]) }, "|")
            end
        end
    end
    return table.concat(out, "\n")
end

--- Characters whose export is known to lack data, as { label, instructions } in the export's order.
--- `missingFn(char, realm)` gives { instructions = {"* ..."} } (SummaryData.GetExportMissingDataInfo); the
--- label is the name, with the realm when the characters span several. Never-scanned stubs (no faction and
--- no class) are left out: the site passes over them.
--- @return table[]
function ProfitExport.MissingData(characters, missingFn)
    local out = {}
    if type(missingFn) ~= "function" then return out end
    local realms = sortedKeys(characters)
    for _, realm in ipairs(realms) do
        for _, entry in ipairs(charactersByName(characters[realm])) do
            local name, char = entry[1], entry[2]
            local info = (char.faction or char.classFile) and missingFn(char, realm)
            local instructions = {}
            for _, line in ipairs(info and info.instructions or {}) do
                instructions[#instructions + 1] = (line:gsub("^%* ", ""))
            end
            if #instructions > 0 then
                local label = #realms > 1 and (name .. " (" .. realm .. ")") or name
                out[#out + 1] = { label = label, instructions = instructions }
            end
        end
    end
    return out
end

--- The export dialog's warning for MissingData's rows: one line per character, at most `limit`, then how
--- many more. "" when nothing is missing.
--- @return string
function ProfitExport.MissingDataText(rows, limit)
    if not rows or #rows == 0 then return "" end
    limit = limit or #rows
    local lines = { "Some data has not been gathered yet, so this export lacks it:" }
    for i = 1, math.min(#rows, limit) do
        lines[#lines + 1] = rows[i].label .. ": " .. table.concat(rows[i].instructions, "; ")
    end
    if #rows > limit then
        local more = #rows - limit
        lines[#lines + 1] = "...and " .. more .. " more character" .. (more == 1 and "" or "s")
    end
    return table.concat(lines, "\n")
end

--- The printable string for `text`, compressed with `libDeflate`.
--- @return string
function ProfitExport.Encode(text, libDeflate)
    return ProfitExport.PREFIX .. libDeflate:EncodeForPrint(libDeflate:CompressDeflate(text, { level = 9 }))
end

--- Every character this account has saved, from the running client. nil if LibDeflate is missing.
--- @return string|nil
function ProfitExport.Build()
    local libDeflate = LibStub and LibStub("LibDeflate", true)
    if not libDeflate then
        return nil
    end
    local data = AltArmyTBC_Data --luacheck: ignore 113
    local _, build, _, interface = GetBuildInfo()
    local lines = ProfitExport.Lines(data and data.Characters, interface, build, data and data.accountId)
    return ProfitExport.Encode(lines, libDeflate)
end
