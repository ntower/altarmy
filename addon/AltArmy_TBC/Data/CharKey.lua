-- AltArmy TBC — Canonical saved-var key for a character's per-character settings (realm\name).
-- Character data itself is keyed by GUID (see DataStore.lua); settings stay name-keyed and are
-- moved by RekeyCharSettings when a character's name changes (paid rename, surname now reported).

AltArmy = AltArmy or {}

--- @param name string|nil
--- @param realm string|nil
--- @return string
function AltArmy.CharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end

--- Per-character settings maps keyed by CharKey: { global SavedVariables name, field, field, ... }.
local CHAR_SETTINGS_TABLES = {
    { "AltArmyTBC_SummarySettings", "characters" },
    { "AltArmyTBC_GearSettings", "characters" },
    { "AltArmyTBC_ReputationSettings", "characters" },
    { "AltArmyTBC_Options", "economy", "currency", "characters" },
    { "AltArmyTBC_GraphSettings", "selected" },
    { "AltArmyTBC_Options", "bankAlts" },
    { "AltArmyTBC_Options", "bankAltPromptDismissed" },
}

--- The table at a CHAR_SETTINGS_TABLES path, or nil when any step is missing.
local function settingsMap(spec)
    local t = _G[spec[1]]
    for i = 2, #spec do
        if type(t) ~= "table" then
            return nil
        end
        t = t[spec[i]]
    end
    return type(t) == "table" and t or nil
end

--- Move every per-character setting saved for `oldName` on `realm` to `newName`. A setting already
--- saved under the new name is kept.
function AltArmy.RekeyCharSettings(realm, oldName, newName)
    if type(oldName) ~= "string" or oldName == "" or type(newName) ~= "string" or newName == ""
        or oldName == newName
    then
        return
    end
    local oldKey = AltArmy.CharKey(oldName, realm)
    local newKey = AltArmy.CharKey(newName, realm)
    for _, spec in ipairs(CHAR_SETTINGS_TABLES) do
        local map = settingsMap(spec)
        if map and map[oldKey] ~= nil then
            if map[newKey] == nil then
                map[newKey] = map[oldKey]
            end
            map[oldKey] = nil
        end
    end
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.RenameCharacter then
        GSS.RenameCharacter(realm, oldName, newName)
    end
end

--- Whether `char` is a stale copy a pre-v3 addon saved of a WoW Forever character under its first name
--- alone ("Not" for "Not Kaiborn"): it has no GUID, its name is one word, and `others` (a list of character
--- tables) holds a character of that first name and a surname, of the same class, at its level or higher.
--- DataStore's FoldLegacyEntries adopts only a legacy entry saved under the full name, so such a copy
--- stays in the account's data, and older guildmates' addons share it.
function AltArmy.IsFirstNameStub(char, others)
    if type(char) ~= "table" or char.guid ~= nil then return false end
    local name = char.name
    if type(name) ~= "string" or name == "" or name:find(" ", 1, true) then return false end
    local prefix = name .. " "
    for _, other in ipairs(others or {}) do
        if type(other) == "table" and other ~= char and type(other.name) == "string"
            and other.name:sub(1, #prefix) == prefix and #other.name > #prefix
            and (other.classFile or "") == (char.classFile or "")
            and (tonumber(other.level) or 0) >= (tonumber(char.level) or 0)
        then
            return true
        end
    end
    return false
end
