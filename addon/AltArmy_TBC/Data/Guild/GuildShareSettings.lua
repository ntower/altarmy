-- AltArmy TBC — Guild data sharing: the user's own sharing preferences (send-side privacy).
-- Backed by AltArmyTBC_SharingSettings. Sharing defaults to OFF (opt-in).
--
-- Two send-set resolvers are exposed for the comm layer:
--   GetShareableCharacters(guild, realm) — opt-in set, used when the feature flag is ON.
--   GetAllGuildedCharacters(guild, realm) — default set (ignores settings), used when the flag is OFF.
-- The flag branch itself lives in GuildShareComm; this module has no dependency on Debug.

if not AltArmy then return end

AltArmy.GuildShareSettings = AltArmy.GuildShareSettings or {}
local GSS = AltArmy.GuildShareSettings

local function ensure()
    _G.AltArmyTBC_SharingSettings = _G.AltArmyTBC_SharingSettings or {}
    local s = _G.AltArmyTBC_SharingSettings
    if s.enabled == nil then s.enabled = false end
    if s.chatInsertion == nil then s.chatInsertion = true end
    if s.autoDeleteOldData == nil then s.autoDeleteOldData = true end
    -- chatInsertionClassColor stays nil until first read; defaulted from Blizzard then.
    s.mains = s.mains or {}
    s.displayNames = s.displayNames or {}
    s.optOut = s.optOut or {}
    s.nonGuildedOptIn = s.nonGuildedOptIn or {}
    s.onboardingCompleted = s.onboardingCompleted or {}
    s.groupUiPrefs = s.groupUiPrefs or {}
    s.chatInsertionChannels = s.chatInsertionChannels or {}
    local channels = s.chatInsertionChannels
    if channels.say == nil then channels.say = true end
    if channels.yell == nil then channels.yell = true end
    if channels.emote == nil then channels.emote = true end
    if channels.guild == nil then channels.guild = true end
    if channels.party == nil then channels.party = true end
    if channels.raid == nil then channels.raid = true end
    if channels.battleground == nil then channels.battleground = true end
    if channels.whisper == nil then channels.whisper = true end
    return s
end
GSS._Ensure = ensure

local function currentRealm()
    local DS = AltArmy.DataStore
    if DS and DS.GetCurrentPlayerRealm then
        local r = DS:GetCurrentPlayerRealm()
        if r and r ~= "" then return r end
    end
    return (GetRealmName and GetRealmName()) or ""
end
GSS._CurrentRealm = currentRealm

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end
GSS._CurrentGuild = currentGuild

--- Characters on a realm as a name->charData map (canonical account store).
local function charactersOnRealm(realm)
    local DS = AltArmy.DataStore
    if DS and DS.GetCharacters then
        return DS:GetCharacters(realm) or {}
    end
    local data = _G.AltArmyTBC_Data
    return (data and data.Characters and data.Characters[realm]) or {}
end

-- *** Master enable ***

--- Tooltip for Options controls that are disabled until guild sharing is turned on.
GSS.SHARING_REQUIRED_CONTROL_TOOLTIP =
    "Turn on guild sharing to enable this option."
GSS.SHARING_REQUIRED_CONFIGURE_HINT = "Click to configure"

--- Present the sharing-required tooltip. opts.showConfigureHint adds a gray configure line.
--- @return boolean
function GSS.PresentSharingRequiredTooltip(owner, anchor, opts)
    if not owner or not GameTooltip then return false end
    opts = opts or {}
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(GSS.SHARING_REQUIRED_CONTROL_TOOLTIP, 1, 1, 1, true)
    if opts.showConfigureHint then
        GameTooltip:AddLine(GSS.SHARING_REQUIRED_CONFIGURE_HINT, 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
    return true
end

function GSS.IsSharingEnabled()
    return ensure().enabled == true
end

function GSS.SetSharingEnabled(on)
    ensure().enabled = on == true
end

-- *** Auto-delete stale received guild data ***

--- Received (non-local) share data older than this is pruned when auto-delete is on.
GSS.AUTO_DELETE_MAX_AGE_SEC = 60 * 60 * 24 * 180
GSS.AUTO_DELETE_OLD_DATA_TOOLTIP =
    "Data shared by others will be automatically deleted if it's more than 6 months old."

function GSS.IsAutoDeleteOldDataEnabled()
    return ensure().autoDeleteOldData == true
end

function GSS.SetAutoDeleteOldDataEnabled(on)
    ensure().autoDeleteOldData = on == true
end

-- *** Chat insertion (Phase 6) ***

function GSS.IsChatInsertionEnabled()
    return ensure().chatInsertion == true
end

function GSS.SetChatInsertionEnabled(on)
    ensure().chatInsertion = on == true
end

GSS.CHAT_INSERTION_CHANNEL_ORDER = {
    "say", "yell", "emote", "guild", "party", "raid", "battleground", "whisper",
}
GSS.CHAT_INSERTION_CHANNEL_LABELS = {
    say = "Say",
    yell = "Yell",
    emote = "Emote",
    guild = "Guild",
    party = "Party",
    raid = "Raid",
    battleground = "Battleground",
    whisper = "Whisper",
}

--- Blizzard chat types synced for each dropdown channel key.
GSS.CHAT_INSERTION_CHANNEL_CHAT_TYPES = {
    say = { "SAY" },
    yell = { "YELL" },
    emote = { "EMOTE" },
    guild = { "GUILD", "OFFICER" },
    party = { "PARTY", "PARTY_LEADER" },
    raid = { "RAID", "RAID_LEADER" },
    -- Modern Classic uses INSTANCE_CHAT; older TBC builds used BATTLEGROUND.
    battleground = {
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
        "BATTLEGROUND", "BATTLEGROUND_LEADER",
    },
    whisper = { "WHISPER" },
}

local function blizzardChatTypeClassColorOn(chatType)
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
    if not info then return false end
    return info.colorNameByClass == true or info.colorNameByClass == 1
end

--- True when Blizzard has class-colored names on for this dropdown channel key.
function GSS.IsBlizzardChatClassColorEnabled(key)
    local types = GSS.CHAT_INSERTION_CHANNEL_CHAT_TYPES[key]
    if not types or not types[1] then return false end
    return blizzardChatTypeClassColorOn(types[1])
end

--- Default checkbox on when ≥50% of listed channels already use Blizzard class colors.
function GSS.ShouldDefaultChatInsertionClassColorEnabled()
    local keys = GSS.CHAT_INSERTION_CHANNEL_ORDER
    local total = #keys
    if total == 0 then return false end
    local onCount = 0
    for _, key in ipairs(keys) do
        if GSS.IsBlizzardChatClassColorEnabled(key) then
            onCount = onCount + 1
        end
    end
    return (onCount / total) >= 0.5
end

function GSS.ApplyBlizzardChatClassColorForChannel(key, on)
    local types = GSS.CHAT_INSERTION_CHANNEL_CHAT_TYPES[key]
    local setter = _G.SetChatColorNameByClass
    if not types or type(setter) ~= "function" then return end
    local enabled = on == true
    for _, chatType in ipairs(types) do
        setter(chatType, enabled)
        local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
        if info then
            info.colorNameByClass = enabled
        end
    end
end

--- Sync Blizzard Class Color: on only when our global class-color setting is on
--- and that channel is enabled in the dropdown.
function GSS.SyncBlizzardChatClassColors()
    local classOn = GSS.IsChatInsertionClassColorEnabled()
    for _, key in ipairs(GSS.CHAT_INSERTION_CHANNEL_ORDER) do
        local channelOn = GSS.IsChatInsertionChannelEnabled(key)
        GSS.ApplyBlizzardChatClassColorForChannel(key, classOn and channelOn)
    end
end

--- Apply stored AltArmy class-color prefs to Blizzard (per-character chat flags + override CVar).
--- No-ops when chatInsertionClassColor has never been chosen (still nil), so first login
--- can still default from Blizzard without overwriting other characters' chat settings.
--- @return boolean true if Blizzard was synced
function GSS.ApplyStoredChatClassColorToBlizzard()
    local s = ensure()
    if s.chatInsertionClassColor == nil then
        return false
    end
    -- Classic: "2" respects per-channel class colors; "0" forces all; "1" forces off.
    if s.chatInsertionClassColor == true and type(_G.SetCVar) == "function" then
        _G.SetCVar("chatClassColorOverride", "2")
    end
    GSS.SyncBlizzardChatClassColors()
    return true
end

function GSS.IsChatInsertionClassColorEnabled()
    local s = ensure()
    if s.chatInsertionClassColor == nil then
        s.chatInsertionClassColor = GSS.ShouldDefaultChatInsertionClassColorEnabled()
    end
    return s.chatInsertionClassColor == true
end

function GSS.SetChatInsertionClassColorEnabled(on)
    ensure().chatInsertionClassColor = on == true
    GSS.ApplyStoredChatClassColorToBlizzard()
end

function GSS.GetChatInsertionChannels()
    local s = ensure()
    return s.chatInsertionChannels
end

function GSS.IsChatInsertionChannelEnabled(key)
    local channels = GSS.GetChatInsertionChannels()
    return channels[key] ~= false
end

function GSS.SetChatInsertionChannelEnabled(key, on)
    ensure().chatInsertionChannels[key] = on ~= false
    GSS.SyncBlizzardChatClassColors()
end

-- Blizzard default chat colors (Chat Settings / ChangeChatColor), as 0–1 floats.
GSS.CHAT_INSERTION_CHANNEL_COLORS = {
    say = { 255 / 255, 255 / 255, 255 / 255 },
    yell = { 255 / 255, 64 / 255, 64 / 255 },
    emote = { 255 / 255, 128 / 255, 64 / 255 },
    guild = { 64 / 255, 255 / 255, 64 / 255 },
    officer = { 64 / 255, 192 / 255, 64 / 255 },
    party = { 170 / 255, 170 / 255, 255 / 255 },
    partyLeader = { 118 / 255, 200 / 255, 255 / 255 },
    raid = { 255 / 255, 127 / 255, 0 / 255 },
    raidLeader = { 255 / 255, 72 / 255, 9 / 255 },
    battleground = { 255 / 255, 127 / 255, 0 / 255 },
    -- Classic/TBC uses INSTANCE_CHAT_LEADER (same red as RAID_LEADER), not the
    -- old WotLK BATTLEGROUND_LEADER peach (255, 219, 183).
    battlegroundLeader = { 255 / 255, 72 / 255, 9 / 255 },
    whisper = { 255 / 255, 128 / 255, 255 / 255 },
}

--- Checkbox-row segments: each option may cover multiple Blizzard chat channels.
--- Entries are { label, colorKey } where colorKey indexes CHAT_INSERTION_CHANNEL_COLORS.
GSS.CHAT_INSERTION_CHANNEL_DETAIL_SEGMENTS = {
    say = { { "Say", "say" } },
    yell = { { "Yell", "yell" } },
    emote = { { "Emote", "emote" } },
    guild = { { "Guild", "guild" }, { "Officer", "officer" } },
    party = { { "Party", "party" }, { "Party Leader", "partyLeader" } },
    raid = { { "Raid", "raid" }, { "Raid Leader", "raidLeader" } },
    battleground = {
        { "Battleground", "battleground" },
        { "Battleground Leader", "battlegroundLeader" },
    },
    whisper = { { "Whisper", "whisper" } },
}

local function colorizeChannelLabel(label, colorKey)
    local color = GSS.CHAT_INSERTION_CHANNEL_COLORS and GSS.CHAT_INSERTION_CHANNEL_COLORS[colorKey]
    local CC = AltArmy.ClassColor
    if color and CC and CC.formatHex then
        return CC.formatHex(color[1], color[2], color[3], label)
    end
    return label
end

--- Short single-word label with chat color (summary row).
function GSS.FormatChatInsertionChannelColoredLabel(key, labelMap)
    labelMap = labelMap or GSS.CHAT_INSERTION_CHANNEL_LABELS
    local label = labelMap[key] or key
    return colorizeChannelLabel(label, key)
end

--- Full checkbox-row label listing every affected channel, each colored.
function GSS.FormatChatInsertionChannelDetailLabel(key)
    local segments = GSS.CHAT_INSERTION_CHANNEL_DETAIL_SEGMENTS
        and GSS.CHAT_INSERTION_CHANNEL_DETAIL_SEGMENTS[key]
    if not segments or not segments[1] then
        return GSS.FormatChatInsertionChannelColoredLabel(key)
    end
    local parts = {}
    for i, seg in ipairs(segments) do
        parts[i] = colorizeChannelLabel(seg[1], seg[2])
    end
    return table.concat(parts, " / ")
end

--- Comma-separated enabled short labels with chat colors. Returns "None" when nothing is enabled.
function GSS.FormatChatInsertionChannelSummary(keys, labelMap, filter)
    filter = filter or {}
    local selected = {}
    for _, key in ipairs(keys) do
        if filter[key] ~= false then
            selected[#selected + 1] = GSS.FormatChatInsertionChannelColoredLabel(key, labelMap)
        end
    end
    if #selected == 0 then
        return "None"
    end
    return table.concat(selected, ", ")
end

--- Pick the top-ranked character as main when none is saved yet.
function GSS.EnsureDefaultMainIfMissing(realm)
    realm = realm or currentRealm()
    local existing = GSS.GetMain(realm)
    if existing then return existing end
    local GSO = AltArmy.GuildShareOnboarding
    local DS = AltArmy.DataStore
    if not GSO or not GSO.BuildRealmCharEntries or not DS or not DS.GetCharacters then
        return nil
    end
    local entries = GSO.BuildRealmCharEntries(DS:GetCharacters(realm) or {})
    local top = entries[1]
    if not top or not top.id then return nil end
    GSS.SetMain(realm, top.id)
    if not GSS.GetDisplayName(realm) then
        GSS.SetDisplayName(realm, GSS.FirstName(top.id))
    end
    return top.id
end

-- *** Main selection + display name (per realm) ***

function GSS.GetMain(realm)
    return ensure().mains[realm or currentRealm()]
end

--- True when `name` is this realm's explicitly saved main (Options / guild share).
function GSS.IsConfiguredMain(name, realm)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local main = GSS.GetMain(realm)
    return type(main) == "string" and main ~= "" and main == name
end

function GSS.SetMain(realm, name)
    ensure().mains[realm or currentRealm()] = name
end

GSS.DISPLAY_NAME_MAX_LENGTH = 20

local function displayMatchesCharacter(name, displayLower)
    if type(name) ~= "string" or name == "" then
        return false
    end
    return name:lower() == displayLower or GSS.FirstName(name):lower() == displayLower
end

--- Whether changing main should also update the preferred/display name.
--- Sync when the preferred name is empty, or matches (case-insensitive) the full
--- name or first name of the old main or any character in charsByName
--- (e.g. DataStore:GetCharacters(realm); each entry's `name`, else its key). Keep a custom name otherwise.
function GSS.ShouldSyncDisplayNameWithMain(oldMain, oldDisplayName, charsByName)
    if type(oldDisplayName) ~= "string" or oldDisplayName == "" then
        return true
    end
    local displayLower = oldDisplayName:lower()
    if displayMatchesCharacter(oldMain, displayLower) then
        return true
    end
    for key, char in pairs(charsByName or {}) do
        local name = (type(char) == "table" and char.name) or key
        if displayMatchesCharacter(name, displayLower) then
            return true
        end
    end
    return false
end

--- First name only, for copying a character name into the preferred-name field.
--- WoW Forever characters have "First Last" names; earlier clients have no space
--- to split on, so the whole name passes through unchanged.
function GSS.FirstName(name)
    if type(name) ~= "string" then
        return name
    end
    return name:match("^(%S+)") or name
end

--- Trim a display name to the allowed length, or nil when empty/absent.
function GSS.NormalizeDisplayName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if #name > GSS.DISPLAY_NAME_MAX_LENGTH then
        return name:sub(1, GSS.DISPLAY_NAME_MAX_LENGTH)
    end
    return name
end

function GSS.GetDisplayName(realm)
    return GSS.NormalizeDisplayName(ensure().displayNames[realm or currentRealm()])
end

function GSS.SetDisplayName(realm, name)
    ensure().displayNames[realm or currentRealm()] = GSS.NormalizeDisplayName(name)
end

-- *** Per-group local UI prefs (Guild tab pin / override name) ***

local function groupUiEntry(main, realm, create)
    if type(main) ~= "string" or main == "" then return nil end
    realm = realm or currentRealm()
    local byRealm = ensure().groupUiPrefs[realm]
    if not byRealm then
        if not create then return nil end
        byRealm = {}
        ensure().groupUiPrefs[realm] = byRealm
    end
    local entry = byRealm[main]
    if not entry then
        if not create then return nil end
        entry = {}
        byRealm[main] = entry
    end
    return entry
end

function GSS.IsGroupPinned(main, realm)
    local entry = groupUiEntry(main, realm, false)
    return entry ~= nil and entry.pin == true
end

function GSS.SetGroupPinned(main, realm, pinned)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    if pinned then
        local entry = groupUiEntry(main, realm, true)
        entry.pin = true
    else
        local entry = groupUiEntry(main, realm, false)
        if not entry then return end
        entry.pin = nil
        if not entry.overrideName then
            ensure().groupUiPrefs[realm][main] = nil
        end
    end
end

function GSS.GetGroupOverrideName(main, realm)
    local entry = groupUiEntry(main, realm, false)
    if not entry then return nil end
    return GSS.NormalizeDisplayName(entry.overrideName)
end

function GSS.SetGroupOverrideName(main, realm, name)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    local normalized = GSS.NormalizeDisplayName(name)
    if normalized then
        local entry = groupUiEntry(main, realm, true)
        entry.overrideName = normalized
    else
        local entry = groupUiEntry(main, realm, false)
        if not entry then return end
        entry.overrideName = nil
        if not entry.pin then
            ensure().groupUiPrefs[realm][main] = nil
        end
    end
end

function GSS.ClearGroupUiPrefs(main, realm)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    local byRealm = ensure().groupUiPrefs[realm]
    if byRealm then
        byRealm[main] = nil
    end
end

--- Main + display name for a presence broadcast.
--- Only an explicitly saved main is sent (receivers guess when nil so grouping still works).
--- Display falls back to the saved main's first name when the player has not set a preferred name.
--- `chars` is unused; kept for call-site compatibility.
function GSS.ResolvePresenceMainAndDisplay(_chars, realm)
    realm = realm or currentRealm()
    local mainName = GSS.GetMain(realm)
    local displayName = GSS.GetDisplayName(realm)
    if not displayName and mainName then
        displayName = GSS.FirstName(mainName)
    end
    return mainName, displayName
end

-- *** Onboarding completion (per realm) ***

function GSS.IsOnboardingCompleted(realm)
    return ensure().onboardingCompleted[realm or currentRealm()] == true
end

function GSS.SetOnboardingCompleted(realm, done)
    ensure().onboardingCompleted[realm or currentRealm()] = done == true
end

-- *** Per-character opt-out (guilded characters) ***

function GSS.IsCharacterOptedOut(name, realm)
    local byRealm = ensure().optOut[realm or currentRealm()]
    return byRealm ~= nil and byRealm[name] == true
end

function GSS.SetCharacterOptedOut(name, realm, optedOut)
    realm = realm or currentRealm()
    local s = ensure()
    s.optOut[realm] = s.optOut[realm] or {}
    s.optOut[realm][name] = optedOut and true or nil
end

-- *** Non-guilded opt-in (character -> guild to share it with) ***

function GSS.GetNonGuildedOptInGuild(name, realm)
    local byRealm = ensure().nonGuildedOptIn[realm or currentRealm()]
    return byRealm and byRealm[name] or nil
end

function GSS.IsNonGuildedOptedIn(name, realm)
    return GSS.GetNonGuildedOptInGuild(name, realm) ~= nil
end

function GSS.SetNonGuildedOptIn(name, realm, guild)
    realm = realm or currentRealm()
    local s = ensure()
    s.nonGuildedOptIn[realm] = s.nonGuildedOptIn[realm] or {}
    s.nonGuildedOptIn[realm][name] = guild
end

--- Move this realm's main, opt-out and non-guilded opt-in from `oldName` to `newName` (character
--- renamed). A setting already saved under the new name is kept.
function GSS.RenameCharacter(realm, oldName, newName)
    if not oldName or not newName or oldName == newName then return end
    realm = realm or currentRealm()
    local s = ensure()
    if s.mains[realm] == oldName then
        s.mains[realm] = newName
    end
    for _, byRealmMap in ipairs({ s.optOut, s.nonGuildedOptIn }) do
        local byName = byRealmMap[realm]
        if byName and byName[oldName] ~= nil then
            if byName[newName] == nil then
                byName[newName] = byName[oldName]
            end
            byName[oldName] = nil
        end
    end
end

-- *** Per-character share mode (tri-state UI) ***

GSS.CHARACTER_SHARE_MODE_LABELS = {
    share = "Always share",
    dont_share = "Never share",
}

function GSS.GetCharacterShareModeDefaultLabel()
    if GSS.IsSharingEnabled() then
        return "Use global setting (share)"
    end
    return "Use global setting (don't share)"
end

function GSS.GetCharacterShareModeEntries()
    local labels = GSS.CHARACTER_SHARE_MODE_LABELS
    return {
        { id = "default", label = GSS.GetCharacterShareModeDefaultLabel() },
        { id = "share", label = labels.share },
        { id = "dont_share", label = labels.dont_share },
    }
end

function GSS.GetCharacterShareMode(name, realm)
    if GSS.IsCharacterOptedOut(name, realm) then
        return "dont_share"
    end
    if GSS.IsNonGuildedOptedIn(name, realm) then
        return "share"
    end
    return "default"
end

function GSS.SetCharacterShareMode(name, realm, mode)
    realm = realm or currentRealm()
    if mode == "share" then
        GSS.SetCharacterOptedOut(name, realm, false)
        local guild = currentGuild()
        if guild then
            GSS.SetNonGuildedOptIn(name, realm, guild)
        end
    elseif mode == "dont_share" then
        GSS.SetCharacterOptedOut(name, realm, true)
        GSS.SetNonGuildedOptIn(name, realm, nil)
    else
        GSS.SetCharacterOptedOut(name, realm, false)
        GSS.SetNonGuildedOptIn(name, realm, nil)
    end
end

-- *** Send-set resolvers ***

--- `key` is the storage key (a GUID for scanned characters); entries carry the character's name.
local function makeEntry(key, realm, char)
    return { name = (char and char.name) or key, realm = realm, char = char }
end

--- The characters on a realm as a list, and a check for the stale first-name copies among them
--- (AltArmy.IsFirstNameStub), which are never shared or listed.
local function stubCheck(chars)
    local list = {}
    for key, char in pairs(chars) do
        if type(char) == "table" then
            list[#list + 1] = { name = char.name or key, guid = char.guid, classFile = char.classFile,
                level = char.level }
        end
    end
    return function(key, char)
        if not AltArmy.IsFirstNameStub or type(char) ~= "table" then return false end
        return AltArmy.IsFirstNameStub({ name = char.name or key, guid = char.guid,
            classFile = char.classFile, level = char.level }, list)
    end
end

--- Default set (used when the feature flag is OFF): every one of my characters in `guild`
--- on `realm`, ignoring the user's sharing settings entirely.
function GSS.GetAllGuildedCharacters(guild, realm)
    guild = guild or currentGuild()
    realm = realm or currentRealm()
    local out = {}
    if not guild then return out end
    local chars = charactersOnRealm(realm)
    local isStub = stubCheck(chars)
    for name, char in pairs(chars) do
        if char and char.guildName == guild and not isStub(name, char) then
            out[#out + 1] = makeEntry(name, realm, char)
        end
    end
    return out
end

--- Opt-in set (used when the feature flag is ON): empty unless sharing is enabled; then
--- guilded characters that are not opted out, plus non-guilded characters opted in to `guild`.
function GSS.GetShareableCharacters(guild, realm)
    guild = guild or currentGuild()
    realm = realm or currentRealm()
    local out = {}
    if not guild or not GSS.IsSharingEnabled() then return out end
    local chars = charactersOnRealm(realm)
    local isStub = stubCheck(chars)
    for key, char in pairs(chars) do
        if char and not isStub(key, char) then
            local name = char.name or key
            if char.guildName == guild then
                if not GSS.IsCharacterOptedOut(name, realm) then
                    out[#out + 1] = makeEntry(key, realm, char)
                end
            elseif char.guildName == nil and GSS.GetNonGuildedOptInGuild(name, realm) == guild then
                out[#out + 1] = makeEntry(key, realm, char)
            end
        end
    end
    return out
end

-- Per-character Blizzard chat class-color flags; re-apply account prefs on each login.
local loginFrame = CreateFrame and CreateFrame("Frame")
if loginFrame and loginFrame.RegisterEvent then
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            loginFrame:UnregisterEvent("PLAYER_LOGIN")
            GSS.ApplyStoredChatClassColorToBlizzard()
        end
    end)
end
