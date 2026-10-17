-- AltArmy TBC — Raid/heroic lockout row building (data only).
-- Consumed by TabCooldownsRaids.lua. No WoW API calls beyond time().

if not AltArmy then return end

AltArmy.LockoutData = AltArmy.LockoutData or {}
local LD = AltArmy.LockoutData

--- Ensure cooldowns options include Crafting/Raids view + lockout list sort fields.
function LD.EnsureLockoutListOptions()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local root = _G.AltArmyTBC_Options
    root.cooldowns = root.cooldowns or {}
    local cd = root.cooldowns
    if cd.activeView ~= "crafting" and cd.activeView ~= "raids" then
        cd.activeView = "crafting"
    end
    local sk = cd.lockoutListSortKey
    if sk ~= "character" and sk ~= "instance" and sk ~= "time" then
        cd.lockoutListSortKey = "time"
    end
    if cd.lockoutListSortAscending == nil then
        -- Default: soonest reset first.
        cd.lockoutListSortAscending = true
    end
    return cd
end

function LD.FormatInstanceLabel(entry)
    if not entry then return "?" end
    local name = entry.name or "?"
    local diffName = entry.difficultyName
    if type(diffName) == "string" and diffName ~= "" then
        if diffName:lower():find("heroic", 1, true) then
            return "Heroic: " .. name
        end
    end
    if entry.difficultyId == 2 and entry.isRaid ~= true then
        return "Heroic: " .. name
    end
    return name
end

function LD.FormatProgressText(entry)
    if not entry then return "—" end
    local total = tonumber(entry.numEncounters) or 0
    if total <= 0 then
        return "—"
    end
    local progress = tonumber(entry.encounterProgress) or 0
    return string.format("%d/%d", progress, total)
end

function LD.FormatResetRemaining(resetAtUnix, now)
    now = now or (time and time() or 0)
    resetAtUnix = tonumber(resetAtUnix)
    if not resetAtUnix then
        return "—"
    end
    if resetAtUnix <= now then
        return "Ready"
    end
    local sec = math.floor(resetAtUnix - now)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h >= 24 then
        local d = math.floor(h / 24)
        local rh = h % 24
        return string.format("%dd %dh %dm", d, rh, m)
    end
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    if m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

--- Build display rows for all characters' active lockouts.
--- @return table[] rows with name, realm, classFile, charKeyName (the character's name), instanceName,
---   instanceLabel, progressText, resetAtUnix, timeText, extended, isRaid
function LD.BuildRows(DS, now)
    now = now or (time and time() or 0)
    local rows = {}
    if not DS or not DS.ForEachCharacter then
        return rows
    end

    (DS.ForEachCharacterInScope or DS.ForEachCharacter)(DS, function(realm, charName, char, linkId)
        local list = char and char.RaidLockouts
        if type(list) ~= "table" then
            return
        end
        local displayName = (char and char.name) or charName
        local classFile = (char and char.classFile) or ""
        if DS.GetCharacterClass then
            local _
            _, classFile = DS:GetCharacterClass(char)
            classFile = classFile or ""
        end
        for _, entry in ipairs(list) do
            local resetAt = entry and tonumber(entry.resetAtUnix)
            if resetAt and resetAt > now then
                rows[#rows + 1] = {
                    name = displayName,
                    charKeyName = displayName,
                    realm = realm,
                    linkId = linkId,
                    classFile = classFile or "",
                    instanceName = entry.name or "?",
                    instanceLabel = LD.FormatInstanceLabel(entry),
                    progressText = LD.FormatProgressText(entry),
                    resetAtUnix = resetAt,
                    timeText = LD.FormatResetRemaining(resetAt, now),
                    extended = entry.extended == true,
                    isRaid = entry.isRaid == true,
                    encounterProgress = tonumber(entry.encounterProgress) or 0,
                    numEncounters = tonumber(entry.numEncounters) or 0,
                }
            end
        end
    end)

    return rows
end
