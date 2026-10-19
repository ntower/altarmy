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
