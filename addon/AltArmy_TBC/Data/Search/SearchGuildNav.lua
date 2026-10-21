-- AltArmy TBC — Navigation state for opening a guild character from search results.
-- Pure helpers (no frames). Core / TabSearch / TabGuild drive the UI from this state.

local Nav = {}
AltArmy.SearchGuildNav = Nav

-- Whether two realms are one (Forever's coalesced realms are: RealmFilter.sameRealm).
local function sameRealm(a, b)
    local RF = AltArmy.RealmFilter
    if RF and RF.sameRealm then return RF.sameRealm(a, b) end
    return (a or "") == (b or "")
end

local active = false

function Nav.Begin()
    active = true
end

function Nav.End()
    active = false
end

function Nav.IsActive()
    return active and true or false
end

--- While a search→character drill-in is open, any header search change ends it.
--- @return "ignore"|"show_search"|"exit_search"
function Nav.OnHeaderSearchTextChanged(trimmed)
    if not active then
        return "ignore"
    end
    active = false
    if not trimmed or trimmed == "" then
        return "exit_search"
    end
    return "show_search"
end

function Nav.ShouldBackReturnToSearch()
    return active and true or false
end

--- True when a recipe-result Character cell should highlight and accept clicks.
--- Guildmate rows: only when someone in their main-group is online (whisper).
--- Own-account rows: never (tooltip only).
--- opts.rosterByName / opts.onlineCache may be injected (tests / search layout cache).
function Nav.IsGuildRecipeCharacterClickable(entry, opts)
    if not entry or not entry.isGuild then
        return false
    end
    if not entry.characterName or entry.characterName == "" then
        return false
    end
    return Nav.IsGuildRecipePlayerOnline(entry.characterName, entry.realm, opts)
end

--- Index of the preferred profession in a GetPrimaryProfessions-style list (1-based).
--- Prefers professionKey match; falls back to case-insensitive name/key; defaults to 1.
function Nav.FindProfessionIndex(profs, professionKey, professionName)
    if type(profs) ~= "table" or #profs == 0 then
        return 1
    end
    if professionKey and professionKey ~= "" then
        for i, prof in ipairs(profs) do
            if prof.key == professionKey then
                return i
            end
        end
    end
    if professionName and professionName ~= "" then
        local want = professionName:lower()
        for i, prof in ipairs(profs) do
            local name = (prof.name or ""):lower()
            local key = (prof.key or ""):lower()
            if name == want or key == want then
                return i
            end
        end
    end
    return 1
end

--- 1-based index of recipeID in a recipe list, or nil.
function Nav.FindRecipeRowIndex(recipes, recipeID)
    if type(recipes) ~= "table" or not recipeID then
        return nil
    end
    local want = tonumber(recipeID) or recipeID
    for i, recipe in ipairs(recipes) do
        if recipe then
            local id = recipe.recipeID
            if id == recipeID or id == want or tonumber(id) == want then
                return i
            end
        end
    end
    return nil
end

--- Desired scroll offset to reveal a row, or nil if already fully visible.
--- Prefers centering the row; clamps to [0, contentHeight - viewHeight].
function Nav.ScrollOffsetToRevealRow(rowTopY, rowHeight, viewHeight, currentOffset, contentHeight)
    rowTopY = tonumber(rowTopY) or 0
    rowHeight = tonumber(rowHeight) or 0
    viewHeight = tonumber(viewHeight) or 0
    currentOffset = tonumber(currentOffset) or 0
    contentHeight = tonumber(contentHeight) or 0
    if viewHeight <= 0 or rowHeight <= 0 then
        return nil
    end
    local rowBottom = rowTopY + rowHeight
    local visibleTop = currentOffset
    local visibleBottom = currentOffset + viewHeight
    if rowTopY >= visibleTop and rowBottom <= visibleBottom then
        return nil
    end
    local target = rowTopY - (viewHeight - rowHeight) / 2
    local maxScroll = contentHeight - viewHeight
    if maxScroll < 0 then maxScroll = 0 end
    if target < 0 then target = 0 end
    if target > maxScroll then target = maxScroll end
    -- Integer-ish for stable tests (WoW scroll accepts floats)
    return math.floor(target + 0.5)
end

--- Build a guild-tab member entry for an own-account character (DataStore).
function Nav.ResolveLocalMember(characterName, realm)
    if not characterName or characterName == "" then
        return nil
    end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacter then
        return nil
    end
    local char = DS:GetCharacter(characterName, realm)
    if not char then
        return nil
    end
    local GSD = AltArmy.GuildShareData
    local GSS = AltArmy.GuildShareSettings
    local guild = char.guildName
    local displayName = GSS and GSS.GetDisplayName and GSS.GetDisplayName(realm) or nil
    local savedMain = GSS and GSS.GetMain and GSS.GetMain(realm) or nil
    local mainDeclared = savedMain ~= nil
    local mainName = savedMain or characterName
    if GSD and GSD.BuildLocalMemberEntry then
        return GSD.BuildLocalMemberEntry(
            characterName, realm, char, guild, mainName, displayName, mainDeclared)
    end
    return {
        name = (char.name) or characterName,
        realm = realm,
        classFile = char.classFile or "",
        faction = char.faction or "",
        level = char.level or 0,
        guildName = guild,
        main = mainName,
        displayName = displayName,
        isMain = (mainName ~= nil and characterName == mainName),
        mainDeclared = mainDeclared,
        source = "local",
        Professions = {},
    }
end

--- Resolve the guild-tab member entry for a search recipe row.
--- Prefers received guildmate data; falls back to own-account DataStore characters.
function Nav.ResolveGuildMember(characterName, realm)
    if not characterName or characterName == "" then
        return nil
    end
    local GSD = AltArmy.GuildShareData
    if GSD and GSD.GetCharacter then
        local entry = GSD.GetCharacter(characterName, realm)
        if entry then
            return entry
        end
    end
    return Nav.ResolveLocalMember(characterName, realm)
end

local function resolveMemberGroup(entry, realm)
    local GTD = AltArmy.GuildTabData
    local GSD = AltArmy.GuildShareData
    local group
    local guild = entry and entry.guildName
    if guild and GSD and GSD.GetGuildMembersForDisplay and GTD and GTD.GroupMembersByMain then
        local members = GSD.GetGuildMembersForDisplay(guild, realm, true)
        local groups = GTD.GroupMembersByMain(members)
        for _, g in ipairs(groups or {}) do
            for _, m in ipairs(g.members or {}) do
                if m.name == entry.name
                    and (not realm or not m.realm or sameRealm(m.realm, realm)) then
                    group = g
                    break
                end
            end
            if group then break end
        end
    end
    if not group and entry then
        group = {
            main = entry.main or entry.name,
            preferredName = entry.displayName or entry.main or entry.name,
            members = { entry },
        }
    end
    return group
end

local function rosterMapForOpts(opts)
    opts = opts or {}
    if opts.rosterByName ~= nil then
        return opts.rosterByName
    end
    local GTD = AltArmy.GuildTabData
    if GTD and GTD.BuildRosterLastOnlineMap then
        return GTD.BuildRosterLastOnlineMap()
    end
    return {}
end

--- Online whisper target for a guildmate recipe row (the character currently playing), or nil.
--- opts.rosterByName may inject a roster map (tests / search layout cache).
function Nav.ResolveGuildRecipeWhisperTarget(characterName, realm, opts)
    local entry = Nav.ResolveGuildMember(characterName, realm)
    if not entry or entry.source == "local" then
        return nil
    end
    local GTD = AltArmy.GuildTabData
    local GSD = AltArmy.GuildShareData
    if not GTD or not GTD.ResolveOnlineWhisperTarget then
        return nil
    end
    local members
    if entry.guildName and GSD and GSD.GetGuildMembersForDisplay then
        members = GSD.GetGuildMembersForDisplay(entry.guildName, realm, true)
    end
    return GTD.ResolveOnlineWhisperTarget(entry, rosterMapForOpts(opts), members)
end

--- Open a whisper to the online character for a guildmate recipe row.
--- @return boolean true when a whisper was opened
function Nav.OpenGuildRecipeWhisper(characterName, realm, opts)
    local target = Nav.ResolveGuildRecipeWhisperTarget(characterName, realm, opts)
    if not target or target == "" then
        return false
    end
    if _G.ChatFrame_SendTell then
        _G.ChatFrame_SendTell(target)
        return true
    end
    if _G.ChatFrame_OpenChat then
        _G.ChatFrame_OpenChat("/w " .. target .. " ")
        return true
    end
    return false
end

--- True when any character in the recipe owner's main-group is online on the guild roster.
--- opts.rosterByName / opts.onlineCache may be injected (tests / search layout cache).
function Nav.IsGuildRecipePlayerOnline(characterName, realm, opts)
    opts = opts or {}
    local cache = opts.onlineCache
    local cacheKey = (realm or "") .. "\0" .. (characterName or "")
    if cache and cache[cacheKey] ~= nil then
        return cache[cacheKey]
    end
    local entry = Nav.ResolveGuildMember(characterName, realm)
    local online = false
    if entry then
        local GTD = AltArmy.GuildTabData
        local group = resolveMemberGroup(entry, realm)
        local status = GTD and GTD.GetGroupLastOnlineStatus
            and GTD.GetGroupLastOnlineStatus(group, rosterMapForOpts(opts))
        online = status and status.online and true or false
    end
    if cache then
        cache[cacheKey] = online
    end
    return online
end

--- Colored "(Online/Offline)" suffix for a guildmate recipe row.
function Nav.FormatGuildRecipeCharacterSuffix(characterName, realm, opts)
    local GTD = AltArmy.GuildTabData
    if not GTD or not GTD.FormatGuildSearchCharacterSuffix then
        return "|cff8ab4f8 (|r|cff808080Offline|r|cff8ab4f8)|r"
    end
    return GTD.FormatGuildSearchCharacterSuffix(
        Nav.IsGuildRecipePlayerOnline(characterName, realm, opts))
end

--- Sort search guild-char rows by main-group last-online (any alt), then A–Z.
--- Mutates `chars` in place. opts.rosterByName may inject a roster map.
function Nav.SortGuildRecipeCharsByLastOnline(chars, opts)
    if type(chars) ~= "table" or #chars < 2 then
        return chars
    end
    local GTD = AltArmy.GuildTabData
    if not GTD or not GTD.SortGuildSearchCharsByLastOnline then
        return chars
    end
    local rosterByName = rosterMapForOpts(opts)
    local statusCache = {}
    local function getStatus(row)
        if not row or not row.characterName or row.characterName == "" then
            return nil
        end
        local cacheKey = (row.realm or "") .. "\0" .. row.characterName
        local cached = statusCache[cacheKey]
        if cached ~= nil then
            return cached.status
        end
        local status
        local member = Nav.ResolveGuildMember(row.characterName, row.realm)
        if member and GTD.GetGroupLastOnlineStatus then
            local group = resolveMemberGroup(member, row.realm)
            status = GTD.GetGroupLastOnlineStatus(group, rosterByName)
        end
        statusCache[cacheKey] = { status = status }
        return status
    end
    return GTD.SortGuildSearchCharsByLastOnline(chars, rosterByName, { getStatus = getStatus })
end

--- Tooltip lines for a collapsed "Multiple guildmates" recipe search row.
--- Resolves each character's main/class via ResolveGuildMember, and presence via the
--- main-group (player) last-online status — online on any alt counts as online.
--- Formats via GuildTabData.BuildCollapsedGuildRecipeTooltipLines. Caches on the entry.
--- opts.rosterByName may inject a roster map (tests / search layout cache).
function Nav.GetCollapsedGuildRecipeTooltipLines(entry, opts)
    if not entry or not entry.isGuildCollapsed then
        return nil
    end
    if entry._aaCollapsedTooltipLines then
        return entry._aaCollapsedTooltipLines
    end
    local GTD = AltArmy.GuildTabData
    if not GTD or not GTD.BuildCollapsedGuildRecipeTooltipLines then
        return nil
    end
    opts = opts or {}
    local guildChars = entry.guildChars
    if type(guildChars) ~= "table" or #guildChars == 0 then
        return nil
    end

    local rosterByName = rosterMapForOpts(opts)
    local chars = {}
    local mainClassCache = {}
    local RYB = AltArmy and AltArmy.RecipeYieldBonus
    for i = 1, #guildChars do
        local row = guildChars[i]
        if row and row.characterName and row.characterName ~= "" then
            local member = Nav.ResolveGuildMember(row.characterName, row.realm)
            local name = (member and member.name) or row.characterName
            local classFile = (member and member.classFile) or row.classFile
            local mainName = (member and (member.main or member.displayName)) or name
            local mainClassFile = classFile
            if mainName and mainName:lower() ~= name:lower() then
                local cacheKey = (row.realm or "") .. "\0" .. mainName
                local cached = mainClassCache[cacheKey]
                if cached == nil then
                    local mainMember = Nav.ResolveGuildMember(mainName, row.realm)
                    cached = (mainMember and mainMember.classFile) or classFile or ""
                    mainClassCache[cacheKey] = cached
                end
                mainClassFile = cached ~= "" and cached or classFile
            end
            -- Player presence: any character in the main-group online counts as online.
            local status
            if member and GTD.GetGroupLastOnlineStatus then
                local group = resolveMemberGroup(member, row.realm)
                status = GTD.GetGroupLastOnlineStatus(group, rosterByName)
            end
            local namePrefix
            if RYB then
                if RYB.StampEntry then
                    RYB.StampEntry(row)
                end
                if RYB.GetMatchingSpecLabel and RYB.GetMatchingSpecLabel(row)
                    and RYB.FormatSpecialistPrefixMarkup then
                    namePrefix = RYB.FormatSpecialistPrefixMarkup()
                end
            end
            chars[#chars + 1] = {
                name = name,
                classFile = classFile,
                mainName = mainName,
                mainClassFile = mainClassFile,
                status = status,
                namePrefix = namePrefix,
            }
        end
    end

    local buildOpts = {
        formatName = opts.formatName,
        isExpanded = entry.isGuildExpanded and true or false,
    }
    local lines = GTD.BuildCollapsedGuildRecipeTooltipLines(
        chars, rosterByName, buildOpts)
    entry._aaCollapsedTooltipLines = lines
    return lines
end

--- Tooltip lines for a clickable character name in search results, or nil.
--- Own-account characters get a short name + optional spec + level/class tooltip;
--- guildmates get the full preferred-name + presence tooltip.
--- opts.rosterByName may inject a roster map (tests); defaults to live guild roster.
--- opts.forceLocal uses DataStore (own-account) even when the name exists in guild data.
function Nav.GetGuildCharacterHoverTooltipLines(characterName, realm, opts)
    opts = opts or {}
    local entry
    if opts.forceLocal then
        entry = Nav.ResolveLocalMember(characterName, realm)
    else
        entry = Nav.ResolveGuildMember(characterName, realm)
    end
    if not entry then
        return nil
    end
    local GTD = AltArmy.GuildTabData
    if not GTD then
        return nil
    end

    if entry.source == "local" then
        if not GTD.BuildOwnCharacterHoverTooltipLines then
            return nil
        end
        return GTD.BuildOwnCharacterHoverTooltipLines({
            name = entry.name,
            classFile = entry.classFile,
            level = entry.level,
            specializationLabel = opts.specializationLabel,
        })
    end

    if not GTD.BuildGuildCharacterHoverTooltipLines then
        return nil
    end

    local group = resolveMemberGroup(entry, realm)

    local preferred = (GTD.ResolveGroupDisplayName and GTD.ResolveGroupDisplayName(group))
        or (group and group.preferredName)
        or entry.displayName
        or entry.main
        or entry.name

    local presence = GTD.GetGroupMostRecentOnlineDetail
        and GTD.GetGroupMostRecentOnlineDetail(group, rosterMapForOpts(opts))

    local lines = GTD.BuildGuildCharacterHoverTooltipLines({
        name = entry.name,
        preferredName = preferred,
        preferredClassFile = group and group.classFile,
        classFile = entry.classFile,
        level = entry.level,
        presenceDetail = presence,
        specializationLabel = opts.specializationLabel,
    })
    if lines and lines.presenceOnline then
        lines[#lines + 1] = "|cff808080Click to whisper|r"
    end
    return lines
end
