-- AltArmy TBC — Guild data sharing: guild-chat main-name insertion.
-- Annotates chat messages with the poster's group display label (override → preferred →
-- main) when that label differs from the sender name, so you can tell who is behind an
-- unfamiliar alt (or a main using a preferred name). Also annotates guildmate
-- online/offline system messages the same way, and anniversary guild UI (Communities)
-- messages via a FormatMessage wrap. Pure Transform is unit-tested; chat filters / hooks
-- are installed once and gated at call time by the feature flag, sharing opt-in, and
-- chat settings.
-- luacheck: globals ChatFrame_AddMessageEventFilter CreateFrame IsAddOnLoaded
-- luacheck: globals C_Club CommunitiesChatMixin CommunitiesFrame

if not AltArmy then return end

AltArmy.GuildChatMainName = AltArmy.GuildChatMainName or {}
local GCM = AltArmy.GuildChatMainName

GCM.CHANNEL_EVENTS = {
    say = { "CHAT_MSG_SAY" },
    yell = { "CHAT_MSG_YELL" },
    emote = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" },
    guild = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" },
    party = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
    raid = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
    -- Modern Classic uses INSTANCE_CHAT; older TBC builds used BATTLEGROUND.
    battleground = {
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
    },
    whisper = { "CHAT_MSG_WHISPER" },
}

local ONLINE_FALLBACK = "|Hplayer:%s|h[%s]|h has come online."
local OFFLINE_FALLBACK = "%s has gone offline."

--- Pure annotation. getMain(sender) -> main name (or nil). getMainClass(sender, main) -> classFile
--- (optional). Prefixes the main in class color when the sender is a known alt of a different main;
--- otherwise returns the message unchanged. colorByClass=false skips color escapes entirely.
function GCM.FormatMainPrefix(main, classFile, colorByClass)
    if colorByClass == false then
        return "[" .. (main or "") .. "] "
    end
    local CC = AltArmy.ClassColor
    local namePart = (CC and CC.formatName) and CC.formatName(main, classFile) or main
    return "[" .. namePart .. "] "
end

--- Patch 12.0+ clients (Forever included) can hand chat handlers Secret Value
--- strings that error on any operation beyond store/pass. `canaccessvalue()`
--- (existence-checked) is the guard, matching DataStoreProfessions.lua's fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

--- Strip any realm suffix ("Name-Realm" -> "Name") for main lookups.
local function stripRealm(name)
    if type(name) ~= "string" then return name end
    return name:match("^[^%-]+") or name
end

--- Annotate with the group's display label (override → preferred → main).
--- Skips when there is no main, or when the resolved label matches the sender name
--- (nothing useful to add beyond the character already shown in chat).
--- Optional `colorByClass` (default true) controls class-color escapes on the bracket label.
function GCM.Transform(sender, message, getMain, getMainClass, getLabel, colorByClass)
    if not sender or not getMain then return message end
    local senderKey = stripRealm(sender)
    local main = getMain(sender)
    if not main or main == "" then
        return message
    end
    local label = (getLabel and getLabel(sender, main)) or main
    if not label or label == "" then
        label = main
    end
    if label == senderKey then
        return message
    end
    local useColor = colorByClass ~= false
    local classFile = (useColor and getMainClass) and getMainClass(sender, main) or nil
    return GCM.FormatMainPrefix(label, classFile, useColor) .. (message or "")
end

--- Turn a printf-style global string into a Lua pattern with (.+) captures for each %s.
local function formatToPattern(fmt)
    local escaped = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

local function onlinePattern()
    return formatToPattern(_G.ERR_FRIEND_ONLINE_SS or ONLINE_FALLBACK)
end

local function offlinePattern()
    return formatToPattern(_G.ERR_FRIEND_OFFLINE_S or OFFLINE_FALLBACK)
end

--- Parse an online/offline system message. Returns name, "online"|"offline", or nil.
function GCM.ParseOnlineOffline(message)
    if type(message) ~= "string" then return nil end
    local name1 = message:match(onlinePattern())
    if name1 then
        return stripRealm(name1), "online"
    end
    local name = message:match(offlinePattern())
    if name then
        return stripRealm(name), "offline"
    end
    return nil
end

--- Resolve label + class for annotation. Returns label, classFile, useColor, or nil if none.
local function resolveAnnotation(sender, getMain, getMainClass, getLabel, colorByClass)
    if not sender or not getMain then return nil end
    local senderKey = stripRealm(sender)
    local main = getMain(sender)
    if not main or main == "" then
        return nil
    end
    local label = (getLabel and getLabel(sender, main)) or main
    if not label or label == "" then
        label = main
    end
    if label == senderKey then
        return nil
    end
    local useColor = colorByClass ~= false
    local classFile = (useColor and getMainClass) and getMainClass(sender, main) or nil
    return label, classFile, useColor
end

--- Insert class-colored main after the character name in an online/offline system message.
function GCM.TransformOnlineOffline(message, getMain, getMainClass, getLabel, colorByClass)
    local name, kind = GCM.ParseOnlineOffline(message)
    if not name then return message end
    local label, classFile, useColor = resolveAnnotation(
        name, getMain, getMainClass, getLabel, colorByClass)
    if not label then return message end
    local prefix = GCM.FormatMainPrefix(label, classFile, useColor)
    if kind == "online" then
        -- "|Hplayer:Name|h[Name]|h has come online." → insert after the closing |h
        local linkEnd = message:find("|h ", 1, true)
        if not linkEnd then return message end
        -- linkEnd points at start of "|h "; keep "|h" then insert " [Main] " before the rest
        local before = message:sub(1, linkEnd + 1) -- includes "|h"
        local after = message:sub(linkEnd + 3) -- after "|h "
        return before .. " " .. prefix .. after
    end
    -- offline: "Name has gone offline." → "Name [Main] has gone offline."
    -- Forever names carry a surname ("First Surname"), so split after the whole
    -- captured name rather than the first word.
    local fullName = message:match(offlinePattern())
    local rest = message:sub(#fullName + 1):match("^%s+(.+)$")
    if not rest then return message end
    return fullName .. " " .. prefix .. rest
end

--- Shared GuildShareData resolvers used by both chat and system-message filters.
local function buildResolvers(author)
    local GSD = AltArmy.GuildShareData
    local GSS = AltArmy.GuildShareSettings
    if not GSD or not GSD.GetMainOf then return nil end
    local senderName = stripRealm(author)
    local senderEntry = GSD.FindCharacter and GSD.FindCharacter(senderName) or nil
    return function(s)
        return GSD.GetMainOf(stripRealm(s))
    end, function(_, main)
        local realm = senderEntry and senderEntry.realm
        local mainEntry = GSD.FindCharacter and GSD.FindCharacter(main, realm)
        if mainEntry and mainEntry.classFile and mainEntry.classFile ~= "" then
            return mainEntry.classFile
        end
        -- Manual-only mains live under .manual, not .chars.
        local GMG = AltArmy.GuildManualGroups
        local mapping = GMG and GMG.GetMapping and GMG.GetMapping(main, realm) or nil
        if mapping and type(mapping.classFile) == "string" and mapping.classFile ~= "" then
            return mapping.classFile
        end
        return nil
    end, function(_, main)
        local realm = senderEntry and senderEntry.realm
        local override = GSS and GSS.GetGroupOverrideName and GSS.GetGroupOverrideName(main, realm) or nil
        if override and override ~= "" then
            return override
        end
        local mainEntry = GSD.FindCharacter and GSD.FindCharacter(main, realm) or nil
        if mainEntry and mainEntry.displayName and mainEntry.displayName ~= "" then
            return mainEntry.displayName
        end
        return main
    end
end

local function chatInsertionAllowed()
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then return false end
    local GSS = AltArmy.GuildShareSettings
    -- Opt-out of guild sharing also disables chat main-name insertion.
    if not (GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled()) then return false end
    if not (GSS.IsChatInsertionEnabled and GSS.IsChatInsertionEnabled()) then return false end
    return true
end

local function chatInsertionClassColorEnabled()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.IsChatInsertionClassColorEnabled then
        return GSS.IsChatInsertionClassColorEnabled()
    end
    return true
end

--- Returns a modified message when annotation applies, or nil to leave it untouched.
--- Gated here (rather than by install/uninstall) so toggling takes effect immediately.
function GCM.FilterMessage(message, author, channelKey)
    if not chatInsertionAllowed() then return nil end
    if not canAccessSecretValue(message) or not canAccessSecretValue(author) then return nil end
    local GSS = AltArmy.GuildShareSettings
    if channelKey and GSS.IsChatInsertionChannelEnabled
        and not GSS.IsChatInsertionChannelEnabled(channelKey) then
        return nil
    end
    local getMain, getMainClass, getLabel = buildResolvers(author)
    if not getMain then return nil end
    local result = GCM.Transform(
        author, message, getMain, getMainClass, getLabel, chatInsertionClassColorEnabled())
    if result ~= message then
        return result
    end
    return nil
end

--- Annotate online/offline system messages when chat insertion is enabled.
function GCM.FilterSystemMessage(message)
    if not chatInsertionAllowed() then return nil end
    if not canAccessSecretValue(message) then return nil end
    local name = GCM.ParseOnlineOffline(message)
    if not name then return nil end
    local getMain, getMainClass, getLabel = buildResolvers(name)
    if not getMain then return nil end
    local result = GCM.TransformOnlineOffline(
        message, getMain, getMainClass, getLabel, chatInsertionClassColorEnabled())
    if result ~= message then
        return result
    end
    return nil
end

local CLUB_TYPE_GUILD = 2 -- Enum.ClubType.Guild when Enum is unavailable in tests

local function guildClubType()
    local enum = _G.Enum
    if enum and enum.ClubType and enum.ClubType.Guild ~= nil then
        return enum.ClubType.Guild
    end
    return CLUB_TYPE_GUILD
end

--- True when a Communities message should be considered for main-name annotation
--- (guild club, not destroyed, author name present). Settings gates are applied later.
function GCM.ShouldAnnotateClubMessage(clubInfo, message)
    if not clubInfo or clubInfo.clubType ~= guildClubType() then
        return false
    end
    if not message or message.destroyed then
        return false
    end
    local author = message.author
    local name = author and author.name
    if type(name) ~= "string" or name == "" then
        return false
    end
    if not canAccessSecretValue(name) then
        return false
    end
    return true
end

--- Annotate Communities message body using the same gates as guild chat insertion.
--- Returns modified content, or nil to leave it untouched.
function GCM.AnnotateClubMessageContent(authorName, content)
    return GCM.FilterMessage(content, authorName, "guild")
end

local function installChatFilter(channelKey, eventName)
    if not ChatFrame_AddMessageEventFilter then return end
    ChatFrame_AddMessageEventFilter(eventName, function(_, _, msg, author, ...)
        local newMsg = GCM.FilterMessage(msg, author, channelKey)
        if newMsg then
            return false, newMsg, author, ...
        end
        return false
    end)
end

for channelKey, events in pairs(GCM.CHANNEL_EVENTS) do
    for _, eventName in ipairs(events) do
        installChatFilter(channelKey, eventName)
    end
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        local newMsg = GCM.FilterSystemMessage(msg)
        if newMsg then
            return false, newMsg, ...
        end
        return false
    end)
end

-- Anniversary guild UI (Communities) message feed: wrap FormatMessage so live and
-- historical rows get the same [Main] prefix. hooksecurefunc cannot change returns.
-- Mixin copies FormatMessage onto the frame instance, so wrapping only
-- CommunitiesChatMixin leaves CommunitiesFrame.Chat on the original function —
-- always wrap the live Chat frame as well.

--- Wrap owner.FormatMessage to annotate guild club message content.
--- Returns true when newly wrapped, false if already wrapped or nothing to wrap.
function GCM.WrapCommunitiesFormatMessage(owner)
    if not owner or type(owner.FormatMessage) ~= "function" then
        return false
    end
    if owner._altArmyMainNameFormatHooked then
        return false
    end
    owner._altArmyMainNameFormatHooked = true
    local orig = owner.FormatMessage
    owner.FormatMessage = function(self, clubId, streamId, message)
        local clubApi = _G.C_Club
        local clubInfo = clubApi and clubApi.GetClubInfo and clubApi.GetClubInfo(clubId)
        if GCM.ShouldAnnotateClubMessage(clubInfo, message) then
            local author = message.author and message.author.name
            local newContent = GCM.AnnotateClubMessageContent(author, message.content)
            if newContent then
                local copy = {}
                for k, v in pairs(message) do
                    copy[k] = v
                end
                copy.content = newContent
                return orig(self, clubId, streamId, copy)
            end
        end
        return orig(self, clubId, streamId, message)
    end
    return true
end

local function installCommunitiesChatHook()
    GCM.WrapCommunitiesFormatMessage(_G.CommunitiesChatMixin)
    local frame = _G.CommunitiesFrame
    local chat = frame and frame.Chat
    if not chat then return end
    local newlyWrapped = GCM.WrapCommunitiesFormatMessage(chat)
    if newlyWrapped and chat.DisplayChat and chat.IsShown and chat:IsShown() then
        chat:DisplayChat()
    end
end

local function watchCommunitiesFrame()
    local frame = _G.CommunitiesFrame
    if not frame or frame._altArmyMainNameWatch then return end
    frame._altArmyMainNameWatch = true
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            installCommunitiesChatHook()
        end)
    end
    installCommunitiesChatHook()
end

local function tryInstallCommunitiesHooks()
    watchCommunitiesFrame()
    installCommunitiesChatHook()
end

tryInstallCommunitiesHooks()

if CreateFrame then
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_Communities" then
            tryInstallCommunitiesHooks()
        end
    end)
    if IsAddOnLoaded and IsAddOnLoaded("Blizzard_Communities") then
        tryInstallCommunitiesHooks()
    end
end
