-- AltArmy TBC — Gear upgrade chat alerts (loot + rolls + level-up + quest rewards).
-- luacheck: globals DEFAULT_CHAT_FRAME GetItemInfo IsUsableItem UnitName
-- luacheck: globals GetContainerItemLink GetContainerNumSlots SetItemRef ChatFrame_OnHyperlinkClick
-- luacheck: globals EventRegistry hooksecurefunc
-- luacheck: globals GetQuestItemLink GetNumQuestRewards GetNumQuestChoices QUEST_COMPLETE
-- luacheck: globals GetTitleText GetTime C_Timer
-- luacheck: globals GetLootRollItemLink START_LOOT_ROLL

if not AltArmy then return end

AltArmy.GearUpgradeAlerts = AltArmy.GearUpgradeAlerts or {}
local GA = AltArmy.GearUpgradeAlerts

local ALTARMY_GOLD = "|cfffecc00"
local IU = AltArmy.ItemUsability
local GU = AltArmy.GearUpgrade
local GC = AltArmy.GearCompare
local CC = AltArmy.ClassColor
local DS = AltArmy.DataStore

-- Self-contained (no AltArmy.DataStore dependency) so this module's unit tests,
-- which stub GetItemInfo directly without loading the DataStore layer, keep working.
-- See docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md for why the C_Item fallback exists.
local function hasItemInfoApi()
    return GetItemInfo ~= nil or (C_Item ~= nil and C_Item.GetItemInfo ~= nil)
end

local function compatGetItemInfo(item)
    if GetItemInfo then return GetItemInfo(item) end
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
end

local function postChat(line)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and line and line ~= "" then
        chat:AddMessage(line)
    end
end

local function classColorName(name, classFile)
    if CC and CC.wrapName then
        return CC.wrapName(name, classFile)
    end
    return name or "?"
end

local function formatUpgradeNameList(matches)
    if not matches or #matches == 0 then return "" end
    local names = {}
    for i = 1, #matches do
        local m = matches[i]
        names[#names + 1] = classColorName(m.name, m.classFile)
    end
    if #names <= 3 then
        return table.concat(names, ", ")
    end
    local others = #names - 2
    return names[1] .. ", " .. names[2] .. ", and " .. tostring(others) .. " others"
end

-- Blizzard's addon link type is ignored by default SetItemRef and handled via EventRegistry.
local UPGRADE_LINK_PREFIX = "addon:AltArmy:upgrade:"
local LEGACY_UPGRADE_LINK_PREFIX = "altarmy:upgrade:"

local function extractItemPayload(itemLink)
    if not itemLink then return nil end
    return itemLink:match("|H(item:[^|]+)|") or itemLink:match("^(item:[^|]+)")
end

local function extractItemId(itemLink)
    local payload = extractItemPayload(itemLink)
    if not payload then return nil end
    return tonumber(payload:match("^item:(%d+)"))
end

-- Loot-alert suppression for items already announced (quest reward window or
-- Need/Greed roll). Keyed by item id. A flag is set when an item is announced,
-- checked (and consumed) by the loot scan, and otherwise persists until the
-- next PLAYER_ENTERING_WORLD. No timers are involved, so a slow loot delivery
-- cannot outrace the suppression.
local lootUpgradeSuppressedIds = {}
-- Repeat loot alerts (e.g. crafting a stack of the same item) are debounced per
-- item id: after an announcement, the same id stays quiet for this many seconds.
-- In-memory only; resets on /reload or logout.
GA.LOOT_UPGRADE_REPEAT_DEBOUNCE_SEC = 60
local lootUpgradeAnnouncedAt = {}
local QUEST_REWARD_ANNOUNCE_DEBOUNCE_SEC = 1.0
local questRewardAnnounceDebounce = nil
GA.LEVEL_UP_UPGRADE_ANNOUNCE_DELAY_SEC = 0.5
local levelUpUpgradeAnnounceGeneration = 0

local function payloadToUsableLink(payload)
    if not payload or payload == "" then return nil end
    if hasItemInfoApi() then
        local _, link = compatGetItemInfo(payload)
        if link and link ~= "" then
            return link
        end
        local wrapped = "|H" .. payload .. "|h"
        local _, wrappedLink = compatGetItemInfo(wrapped)
        if wrappedLink and wrappedLink ~= "" then
            return wrappedLink
        end
    end
    return "|H" .. payload .. "|h[item]|h"
end

local function formatUpgradeLink(itemLink)
    local payload = extractItemPayload(itemLink)
    if not payload then return itemLink end
    return "|cfffecc00|H" .. UPGRADE_LINK_PREFIX .. payload .. "|h[View details]|h|r"
end

local function formatMessageItemLink(itemLink)
    if not itemLink or itemLink == "" then return "?" end
    if itemLink:find("|r$") then return itemLink end
    return itemLink .. "|r"
end

function GA.FormatLootUpgradeMessage(itemLink, nameList, actionLink)
    return formatMessageItemLink(itemLink)
        .. " is an upgrade for " .. nameList .. ": " .. actionLink
end

function GA.FormatQuestMinorUpgradeMessage(itemLink, nameList, actionLink)
    return formatMessageItemLink(itemLink)
        .. " is a minor upgrade for " .. nameList .. ": " .. actionLink
end

function GA.FormatQuestBestUpgradeMessage(itemLink, nameList, actionLink)
    return formatMessageItemLink(itemLink)
        .. " is the best upgrade for " .. nameList .. ": " .. actionLink
end

function GA.FormatQuestNoUpgradeMessage(nameList)
    return "None of these rewards are an upgrade for " .. nameList
end

local function resolveItemLinkForUpgrade(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    if hasItemInfoApi() then
        local _, cached = compatGetItemInfo(itemId)
        if cached and cached ~= "" then
            return cached
        end
    end
    return "item:" .. tostring(itemId)
end

local function upgradeLinkPayload(link)
    if not link then return nil end
    local lower = link:lower()
    for _, prefix in ipairs({ UPGRADE_LINK_PREFIX, LEGACY_UPGRADE_LINK_PREFIX }) do
        local prefixLower = prefix:lower()
        if lower:sub(1, #prefixLower) == prefixLower then
            return link:sub(#prefixLower + 1)
        end
    end
    return nil
end

local function parseUpgradeLink(link)
    local payload = upgradeLinkPayload(link)
    if not payload then return nil end
    if payload:match("^item:") then
        return payloadToUsableLink(payload)
    end
    local itemId = tonumber(payload)
    if itemId then
        return resolveItemLinkForUpgrade(itemId)
    end
    return nil
end

local function notifyCurrentCharacterEnabled()
    if not GU or not GU.GetOptions then return false end
    local opts = GU.GetOptions()
    return opts.notifyCurrentCharacter ~= false
end

local function notifyOtherCharactersEnabled()
    if not GU or not GU.GetOptions then return false end
    local opts = GU.GetOptions()
    return opts.notifyOtherCharacters ~= false
end

local function filterOtherCharacterMatches(matches)
    if not matches or #matches == 0 then return {} end
    if not DS or not DS.IsCurrentCharacter then return matches end
    local filtered = {}
    for i = 1, #matches do
        local m = matches[i]
        if not DS:IsCurrentCharacter(m.name, m.realm) then
            filtered[#filtered + 1] = m
        end
    end
    return filtered
end

local function buildCurrentCharacterDisplayMatch(char)
    if not char then return nil end
    local level = (DS and DS.GetCharacterLevel and DS:GetCharacterLevel(char))
        or tonumber(char.level) or 0
    local realm = char.realm or (DS and DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
    return {
        name = char.name or "",
        realm = realm,
        classFile = char.classFile or "",
        level = level,
    }
end

local function buildCurrentCharacterMatch(itemLink, evalOpts)
    if not GU or not GU.EvaluateForCharacter then return nil end
    if not DS or not DS.GetCurrentCharacter then return nil end
    local char = DS:GetCurrentCharacter()
    if not char then return nil end
    local BA = AltArmy.BankAlt
    if BA and BA.Is then
        local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
        if BA.Is(char.name or "", realm) then return nil end
    end
    if not GU.EvaluateForCharacter(char, itemLink, evalOpts) then return nil end
    local level = (DS.GetCharacterLevel and DS:GetCharacterLevel(char))
        or tonumber(char.level) or 0
    local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
    return {
        name = char.name or "",
        realm = realm,
        classFile = char.classFile or "",
        level = level,
        isUpgrade = true,
    }
end

local function collectLootUpgradeMatches(itemLink, currentEnabled, otherEnabled, evalOpts)
    local isBop = IU and IU.IsBindOnPickup and IU.IsBindOnPickup(itemLink)

    if isBop then
        if not currentEnabled then return nil, "bop" end
        local match = buildCurrentCharacterMatch(itemLink, evalOpts)
        if not match then return {}, "no_matches" end
        return { match }
    end

    local matches = {}
    if currentEnabled and otherEnabled then
        if GU.EvaluateForAllAlts then
            matches = GU.EvaluateForAllAlts(itemLink, evalOpts) or {}
        end
    elseif otherEnabled then
        if GU.EvaluateForAllAlts then
            matches = filterOtherCharacterMatches(GU.EvaluateForAllAlts(itemLink, evalOpts) or {})
        end
    elseif currentEnabled then
        local match = buildCurrentCharacterMatch(itemLink, evalOpts)
        if match then matches = { match } end
    end

    if #matches == 0 then return {}, "no_matches" end
    return matches
end

--- Patch 12.0+ clients (Forever included) can hand CHAT_MSG_LOOT handlers Secret
--- Value strings that error on any operation beyond store/pass. `canaccessvalue()`
--- (existence-checked) is the guard, matching DataStoreProfessions.lua's fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

local function extractItemLink(msg)
    if not msg then return nil end
    if not canAccessSecretValue(msg) then return nil end
    return msg:match("(|c.-|Hitem:.-|h[^|]*|h)")
        or msg:match("(|Hitem:.-|h[^|]*|h)")
        or msg:match("(item:%d+)")
end
GA._ExtractItemLink = extractItemLink

local function isSelfLootMessage(msg)
    if not msg then return false end
    if not canAccessSecretValue(msg) then return false end
    return msg:find("^You receive loot:") ~= nil
        or msg:find("^You receive item:") ~= nil
        or msg:find("^You create:") ~= nil
end
GA._IsSelfLootMessage = isSelfLootMessage

local function maybeLogItemComparison(itemLink)
    if GC and GC.LogItemComparisonDebug then
        GC.LogItemComparisonDebug(itemLink)
    end
end

function GA.ShouldSuppressLootUpgrade(itemLink)
    local itemId = extractItemId(itemLink)
    if not itemId then return false end
    return lootUpgradeSuppressedIds[itemId] == true
end

function GA.ConsumeLootUpgradeSuppression(itemLink)
    local itemId = extractItemId(itemLink)
    if itemId then
        lootUpgradeSuppressedIds[itemId] = nil
    end
end

function GA.ClearQuestLootUpgradeSuppression()
    lootUpgradeSuppressedIds = {}
end

function GA.BuildQuestRewardAnnounceKey()
    local parts = {}
    if GetTitleText then
        local title = GetTitleText()
        if title and title ~= "" then
            parts[#parts + 1] = title
        end
    end
    local links = GA.CollectQuestRewardLinks()
    local ids = {}
    for i = 1, #links do
        local itemId = extractItemId(links[i])
        if itemId then ids[#ids + 1] = itemId end
    end
    table.sort(ids)
    for i = 1, #ids do
        parts[#parts + 1] = tostring(ids[i])
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ":")
end

function GA.ShouldSkipQuestRewardDebounce(key)
    if not key or not questRewardAnnounceDebounce then return false end
    if questRewardAnnounceDebounce.key ~= key then return false end
    local now = GetTime and GetTime() or 0
    return (now - questRewardAnnounceDebounce.at) < QUEST_REWARD_ANNOUNCE_DEBOUNCE_SEC
end

function GA.MarkQuestRewardAnnounced(key)
    if not key then return end
    local now = GetTime and GetTime() or 0
    questRewardAnnounceDebounce = { key = key, at = now }
end

function GA.ClearQuestRewardAnnounceDebounce()
    questRewardAnnounceDebounce = nil
end

function GA.CancelLevelUpUpgradeAnnouncement()
    levelUpUpgradeAnnounceGeneration = levelUpUpgradeAnnounceGeneration + 1
end

function GA.ScheduleLevelUpUpgradeAnnouncement(newLevel)
    if not newLevel then return end
    GA.CancelLevelUpUpgradeAnnouncement()
    local generation = levelUpUpgradeAnnounceGeneration
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(GA.LEVEL_UP_UPGRADE_ANNOUNCE_DELAY_SEC, function()
            if generation ~= levelUpUpgradeAnnounceGeneration then return end
            GA.AnnounceLevelUpUpgrades(newLevel)
            GA.AnnounceLevelUpConsumables(newLevel)
        end)
    else
        GA.AnnounceLevelUpUpgrades(newLevel)
        GA.AnnounceLevelUpConsumables(newLevel)
    end
end

local function markLootUpgradeSuppressed(itemLink)
    local itemId = extractItemId(itemLink)
    if itemId then
        lootUpgradeSuppressedIds[itemId] = true
    end
end

function GA.CollectQuestRewardLinks()
    local links = {}
    local seenIds = {}
    local function addLink(link)
        if not link or link == "" then return end
        local itemId = extractItemId(link)
        if not itemId or seenIds[itemId] then return end
        seenIds[itemId] = true
        links[#links + 1] = link
    end
    -- When the player must choose among rewards, only evaluate those choices.
    -- Guaranteed rewards are always received and should not drive upgrade alerts.
    local numChoices = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if numChoices > 0 then
        if GetQuestItemLink then
            for i = 1, numChoices do
                addLink(GetQuestItemLink("choice", i))
            end
        end
        return links
    end
    if GetNumQuestRewards and GetQuestItemLink then
        local numRewards = GetNumQuestRewards() or 0
        for i = 1, numRewards do
            addLink(GetQuestItemLink("reward", i))
        end
    end
    return links
end

local function postLootUpgradeAnnouncement(itemLink, matches, opts)
    local nameList = formatUpgradeNameList(matches)
    local actionLink = formatUpgradeLink(itemLink)
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local techniqueNote = ""
    if technique ~= (opts.technique or "custom") then
        techniqueNote = " (using built-in comparison; selected addon not installed)"
    end
    postChat(ALTARMY_GOLD .. "Alt Army|r "
        .. GA.FormatLootUpgradeMessage(itemLink, nameList, actionLink) .. techniqueNote)
    pcall(function()
        if PlaySound then PlaySound("TellMessage", "Master") end
    end)
end

local function postQuestRewardAnnouncement(itemLink, match, opts, kind)
    local nameList = formatUpgradeNameList({ match })
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local techniqueNote = ""
    if technique ~= (opts.technique or "custom") then
        techniqueNote = " (using built-in comparison; selected addon not installed)"
    end
    local body
    local actionLink = formatUpgradeLink(itemLink)
    if kind == "minor" then
        body = GA.FormatQuestMinorUpgradeMessage(itemLink, nameList, actionLink)
    elseif kind == "best" then
        body = GA.FormatQuestBestUpgradeMessage(itemLink, nameList, actionLink)
    else
        body = GA.FormatLootUpgradeMessage(itemLink, nameList, actionLink)
    end
    postChat(ALTARMY_GOLD .. "Alt Army|r " .. body .. techniqueNote)
    pcall(function()
        if PlaySound then PlaySound("TellMessage", "Master") end
    end)
end

local function postQuestNoUpgradeAnnouncement(match, opts)
    local nameList = formatUpgradeNameList({ match })
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local techniqueNote = ""
    if technique ~= (opts.technique or "custom") then
        techniqueNote = " (using built-in comparison; selected addon not installed)"
    end
    postChat(ALTARMY_GOLD .. "Alt Army|r "
        .. GA.FormatQuestNoUpgradeMessage(nameList) .. techniqueNote)
    pcall(function()
        if PlaySound then PlaySound("TellMessage", "Master") end
    end)
end

local function questRewardUpgradeDelta(char, itemLink, evalOpts)
    if GU and GU.GetCharacterUpgradeDelta then
        return GU.GetCharacterUpgradeDelta(char, itemLink, evalOpts) or 0
    end
    return 0
end

function GA.IsQuestRewardEquippableForCharacter(char, link, evalOpts)
    if not IU or not char or not link then return false end
    local slots = IU.GetInventorySlotsForItem and IU.GetInventorySlotsForItem(link) or {}
    if #slots == 0 then return false end
    local classFile = char.classFile or ""
    local level = tonumber(char.level) or 0
    if DS and DS.GetCharacterLevel then
        level = DS:GetCharacterLevel(char) or level
    end
    local levelsAhead = evalOpts and evalOpts.levelsAhead or 0
    if not IU.IsEquippableWithin then return false end
    local equippable = IU.IsEquippableWithin(classFile, level, link, levelsAhead)
    if equippable ~= true then return false end
    -- Mail/plate the character hasn't trained yet isn't a reward they can wear.
    if IU.LacksTrainedProficiency and IU.LacksTrainedProficiency(classFile, link, char) then
        return false
    end
    return true
end

local function questRewardClearUpgrade(char, link, evalOpts, opts)
    if not GU or not GU.GetUpgradeHighlightKind then return false end
    local delta = questRewardUpgradeDelta(char, link, evalOpts)
    if delta <= 0 then return false end
    local oldTotal = 0
    if GU.GetEquippedBaselineFromUpgradeDelta then
        oldTotal = GU.GetEquippedBaselineFromUpgradeDelta(char, link, delta, evalOpts)
    elseif GU.ScoreItem then
        local technique = GU.GetEffectiveTechnique
            and GU.GetEffectiveTechnique(evalOpts and evalOpts.technique or "custom")
            or (evalOpts and evalOpts.technique) or "custom"
        local classFile, specKey, level = char.classFile or "", "unknown", nil
        if GU.ResolveCompareContext then
            classFile, specKey, level = GU.ResolveCompareContext(char, nil)
        end
        local newScore = GU.ScoreItem(link, technique, classFile, specKey, level) or 0
        oldTotal = math.max(0, newScore - delta)
    end
    return GU.GetUpgradeHighlightKind(delta, oldTotal, opts) == "clear"
end

local function collectEquippableQuestRewardLinks(char, links, evalOpts)
    local equippable = {}
    for i = 1, #links do
        local link = links[i]
        if GA.IsQuestRewardEquippableForCharacter(char, link, evalOpts) then
            equippable[#equippable + 1] = link
        end
    end
    return equippable
end

function GA.AnnounceQuestRewardUpgrades()
    if not notifyCurrentCharacterEnabled() or not GU then return end
    local announceKey = GA.BuildQuestRewardAnnounceKey()
    if announceKey and GA.ShouldSkipQuestRewardDebounce(announceKey) then
        return
    end
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end
    local BA = AltArmy.BankAlt
    if BA and BA.Is then
        local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
        if BA.Is(char.name or "", realm) then return end
    end

    local opts = GU.GetOptions() or {}
    local evalOpts = {
        technique = opts.technique,
        levelsAhead = opts.levelsAhead,
    }
    local displayMatch = buildCurrentCharacterDisplayMatch(char)
    if not displayMatch then return end

    local links = GA.CollectQuestRewardLinks()
    if #links == 0 then return end

    links = collectEquippableQuestRewardLinks(char, links, evalOpts)
    if #links == 0 then return end

    local candidates = {}
    for i = 1, #links do
        local link = links[i]
        maybeLogItemComparison(link)
        local delta = questRewardUpgradeDelta(char, link, evalOpts)
        local isClearUpgrade = questRewardClearUpgrade(char, link, evalOpts, opts)
        candidates[#candidates + 1] = {
            link = link,
            delta = delta,
            isClearUpgrade = isClearUpgrade,
        }
    end

    local best
    for i = 1, #candidates do
        local candidate = candidates[i]
        if not best or candidate.delta > best.delta then
            best = candidate
        end
    end
    if not best then return end

    if best.delta <= 0 then
        postQuestNoUpgradeAnnouncement(displayMatch, opts)
        if announceKey then
            GA.MarkQuestRewardAnnounced(announceKey)
        end
        return
    end

    local clearUpgrades = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.delta > 0 and candidate.isClearUpgrade then
            clearUpgrades[#clearUpgrades + 1] = candidate
        end
    end
    table.sort(clearUpgrades, function(a, b)
        if a.delta ~= b.delta then
            return a.delta > b.delta
        end
        return (extractItemId(a.link) or 0) < (extractItemId(b.link) or 0)
    end)

    if #clearUpgrades > 0 then
        for i = 1, #clearUpgrades do
            local kind = "clear"
            if #clearUpgrades > 1 and i == 1 then
                kind = "best"
            end
            postQuestRewardAnnouncement(clearUpgrades[i].link, displayMatch, opts, kind)
            markLootUpgradeSuppressed(clearUpgrades[i].link)
        end
    else
        postQuestRewardAnnouncement(best.link, displayMatch, opts, "minor")
        markLootUpgradeSuppressed(best.link)
    end
    if announceKey then
        GA.MarkQuestRewardAnnounced(announceKey)
    end
end

--- Reset per-session suppression/debounce state. Called on PLAYER_ENTERING_WORLD so
--- stale flags (e.g. from an unchosen quest reward) cannot silence a genuine later drop.
function GA.OnEnteringWorld()
    GA.ClearQuestLootUpgradeSuppression()
    GA.ClearQuestRewardAnnounceDebounce()
    GA.CancelLevelUpUpgradeAnnouncement()
end

function GA.AnnounceLootUpgrade(itemLink)
    if GA.ShouldSuppressLootUpgrade(itemLink) then
        GA.ConsumeLootUpgradeSuppression(itemLink)
        return false, "suppressed"
    end
    if not itemLink or not GU then return false, "disabled" end
    local currentEnabled = notifyCurrentCharacterEnabled()
    local otherEnabled = notifyOtherCharactersEnabled()
    if not currentEnabled and not otherEnabled then
        return false, "disabled"
    end

    local itemId = extractItemId(itemLink)
    local now = GetTime and GetTime() or 0
    local lastAt = itemId and lootUpgradeAnnouncedAt[itemId]
    if lastAt and (now - lastAt) < GA.LOOT_UPGRADE_REPEAT_DEBOUNCE_SEC then
        return false, "debounced"
    end

    local opts = GU.GetOptions() or {}
    local evalOpts = {
        technique = opts.technique,
        levelsAhead = opts.levelsAhead,
    }
    local matches, reason = collectLootUpgradeMatches(
        itemLink, currentEnabled, otherEnabled, evalOpts)
    if reason == "bop" then return false, "bop" end
    if not matches or #matches == 0 then return false, reason or "no_matches" end

    postLootUpgradeAnnouncement(itemLink, matches, opts)
    if itemId then
        lootUpgradeAnnouncedAt[itemId] = now
    end
    return true
end

--- Announce upgrades for an item shown in the Need/Greed roll UI.
--- Accepts an item link or a rollID (resolved via GetLootRollItemLink).
--- On success, marks the item so a subsequent self-loot of the same id is suppressed.
function GA.AnnounceLootRollUpgrade(itemLinkOrRollId)
    local itemLink = itemLinkOrRollId
    if type(itemLinkOrRollId) == "number" then
        if not GetLootRollItemLink then return false, "disabled" end
        itemLink = GetLootRollItemLink(itemLinkOrRollId)
    end
    if not canAccessSecretValue(itemLink) then return false, "disabled" end
    if not itemLink or itemLink == "" then return false, "disabled" end

    local ok, reason = GA.AnnounceLootUpgrade(itemLink)
    if ok then
        markLootUpgradeSuppressed(itemLink)
    end
    return ok, reason
end

--- Debug: run the same upgrade check as self-loot (CHAT_MSG_LOOT).
function GA.SimulateSelfLoot(rawInput)
    local link = extractItemLink(rawInput)
    if not link and rawInput and rawInput:find("item:") then
        link = rawInput:match("^%s*(.-)%s*$")
    end
    if not link or link == "" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: could not parse item link. "
            .. "Usage: /altarmy debug item {shift-click item}")
        return false
    end
    maybeLogItemComparison(link)
    local ok, reason = GA.AnnounceLootUpgrade(link)
    if ok then return true end
    if reason == "disabled" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: gear upgrade notifications are disabled in options.")
    elseif reason == "bop" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: skipped (bind-on-pickup; "
            .. "current-character notifications are disabled).")
    elseif reason == "no_matches" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: no upgrade matches for this item.")
    elseif reason == "debounced" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: skipped (this item was announced within the last "
            .. tostring(GA.LOOT_UPGRADE_REPEAT_DEBOUNCE_SEC) .. " seconds).")
    end
    return false
end

--- Debug: run the same upgrade check as PLAYER_LEVEL_UP.
function GA.SimulateLevelUp(rawLevel)
    local newLevel = tonumber(rawLevel)
    if not newLevel or newLevel < 1 then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: invalid level. "
            .. "Usage: /altarmy debug levelup {level}")
        return false
    end
    if not notifyCurrentCharacterEnabled() then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: gear upgrade notifications for the current character "
            .. "are disabled in options.")
        return false
    end
    GA.AnnounceLevelUpUpgrades(newLevel)
    GA.AnnounceLevelUpConsumables(newLevel)
    return true
end

local function resolveOwnedLink(itemId, storedLink)
    if storedLink and storedLink:find("item:") then
        return storedLink
    end
    if itemId and hasItemInfoApi() then
        local _, link = compatGetItemInfo(itemId)
        if link then return link end
    end
    if itemId then
        return "item:" .. tostring(itemId)
    end
    return nil
end

local function trainingSkillName(link)
    if not link or not hasItemInfoApi() or not IU then return "the required skill" end
    local _, _, _, _, _, itemClass, subclass = compatGetItemInfo(link)
    return IU.GetProficiencySkillName(itemClass, subclass)
end

local function formatLevelUpItemFragment(link, locations)
    locations = locations or {}
    local fragment = link or "?"
    if locations.mail then
        fragment = fragment .. " (mail)"
    elseif locations.bank and not locations.bag then
        fragment = fragment .. " (bank)"
    end
    return fragment
end

function GA.FormatLevelUpEquipMessage(candidates)
    if not candidates or #candidates == 0 then return "" end
    local count = #candidates
    if count == 1 then
        local candidate = candidates[1]
        return "Congratulations! You can now equip "
            .. formatLevelUpItemFragment(candidate.link, candidate)
    end
    if count == 2 then
        local first = candidates[1]
        local second = candidates[2]
        return "Congratulations! You can now equip "
            .. formatLevelUpItemFragment(first.link, first)
            .. " and "
            .. formatLevelUpItemFragment(second.link, second)
    end
    local first = candidates[1]
    local second = candidates[2]
    local others = count - 2
    local otherWord = others == 1 and "upgrade" or "upgrades"
    return "Congratulations! You can now equip "
        .. formatLevelUpItemFragment(first.link, first)
        .. ", "
        .. formatLevelUpItemFragment(second.link, second)
        .. ", and "
        .. tostring(others)
        .. " other "
        .. otherWord
end

local function noteLevelUpCandidate(candidates, candidateOrder, link, location)
    if not candidates[link] then
        candidates[link] = { link = link, bag = false, bank = false, mail = false }
        candidateOrder[#candidateOrder + 1] = link
    end
    if location == "bag" then
        candidates[link].bag = true
    elseif location == "bank" then
        candidates[link].bank = true
    elseif location == "mail" then
        candidates[link].mail = true
    end
end

local function considerLevelUpCandidate(candidates, candidateOrder, link, location, classFile, newLevel)
    if not link then return end
    local eff = IU and IU.EffectiveRequiredLevel(classFile, link) or 999
    if eff ~= newLevel then return end
    noteLevelUpCandidate(candidates, candidateOrder, link, location)
end

function GA.AnnounceLevelUpUpgrades(newLevel)
    if not notifyCurrentCharacterEnabled() or not newLevel or not GU then return end
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end
    local BA = AltArmy.BankAlt
    if BA and BA.Is then
        local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
        local name = char.name or ""
        if BA.Is(name, realm) then return end
    end
    if DS.ScanBags then DS:ScanBags() end

    local opts = GU.GetOptions()
    local classFile = char.classFile or ""
    local candidates = {}
    local candidateOrder = {}

    local function considerSavedContainerSlot(itemId, link, location)
        considerLevelUpCandidate(
            candidates, candidateOrder,
            resolveOwnedLink(itemId, link), location, classFile, newLevel)
    end

    if DS.IterateBagSlots then
        DS:IterateBagSlots(char, function(_, _, itemId, _, link)
            considerSavedContainerSlot(itemId, link, "bag")
        end)
    elseif GetContainerNumSlots and GetContainerItemLink then
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                considerLevelUpCandidate(
                    candidates, candidateOrder,
                    GetContainerItemLink(bag, slot), "bag", classFile, newLevel)
            end
        end
    end

    if DS.IterateBankSlots then
        DS:IterateBankSlots(char, function(_, _, itemId, _, link)
            considerSavedContainerSlot(itemId, link, "bank")
        end)
    end

    local numMails = DS.GetNumMails and DS:GetNumMails(char) or 0
    for i = 1, numMails do
        if DS.GetMailInfo then
            local _, _, link = DS:GetMailInfo(char, i)
            considerLevelUpCandidate(
                candidates, candidateOrder, link, "mail", classFile, newLevel)
        end
    end

    local upgrades = {}
    for i = 1, #candidateOrder do
        local candidate = candidates[candidateOrder[i]]
        local link = candidate.link
        if GU.EvaluateForCharacter(char, link, {
            technique = opts.technique,
            levelsAhead = 0,
            level = newLevel,
        }) then
            upgrades[#upgrades + 1] = candidate
        end
    end
    if #upgrades == 0 then return end

    postChat(ALTARMY_GOLD .. "Alt Army|r "
        .. GA.FormatLevelUpEquipMessage(upgrades))
    for i = 1, #upgrades do
        local link = upgrades[i].link
        if IU and IU.NeedsProficiencyTraining(classFile, newLevel, link, char) then
            postChat(ALTARMY_GOLD .. "Alt Army|r Note that you must train "
                .. trainingSkillName(link) .. " before you can equip this.")
        end
    end
end

-- Returns the required level when the link is a consumable, nil otherwise.
local function consumableRequiredLevel(link)
    if not link or not hasItemInfoApi() then return nil end
    local name, _, _, _, minLevel, itemClass = compatGetItemInfo(link)
    if not name then return nil end
    if (itemClass or ""):lower() ~= "consumable" then return nil end
    return tonumber(minLevel) or 0
end

-- Inventory copies need no reminder. If bags are a source, omit locations;
-- otherwise list non-inventory sources (bank, mail) in parentheses.
local CONSUME_SOURCE_ORDER = { "bank", "mail" }

local function formatLevelUpConsumeFragment(link, locations)
    locations = locations or {}
    local fragment = link or "?"
    if locations.bag then
        return fragment
    end
    local sources = {}
    for i = 1, #CONSUME_SOURCE_ORDER do
        local key = CONSUME_SOURCE_ORDER[i]
        if locations[key] then
            sources[#sources + 1] = key
        end
    end
    if #sources > 0 then
        fragment = fragment .. " (" .. table.concat(sources, ", ") .. ")"
    end
    return fragment
end

local function mergeConsumeCandidates(candidates)
    local merged = {}
    local order = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local key = extractItemId(candidate.link) or candidate.link or ("#" .. i)
        if not merged[key] then
            merged[key] = {
                link = candidate.link,
                bag = false,
                bank = false,
                mail = false,
            }
            order[#order + 1] = key
        end
        local entry = merged[key]
        if candidate.bag then entry.bag = true end
        if candidate.bank then entry.bank = true end
        if candidate.mail then entry.mail = true end
    end
    local result = {}
    for i = 1, #order do
        result[i] = merged[order[i]]
    end
    return result
end

function GA.FormatLevelUpConsumeMessage(candidates)
    if not candidates or #candidates == 0 then return "" end
    candidates = mergeConsumeCandidates(candidates)
    local fragments = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        fragments[i] = formatLevelUpConsumeFragment(candidate.link, candidate)
    end
    local list
    if #fragments == 1 then
        list = fragments[1]
    elseif #fragments == 2 then
        list = fragments[1] .. " and " .. fragments[2]
    else
        list = table.concat(fragments, ", ", 1, #fragments - 1)
            .. ", and " .. fragments[#fragments]
    end
    return "Congratulations! You can now consume " .. list
end

--- Announce consumables in the bags, bank, or mailbox that become usable at the new level.
function GA.AnnounceLevelUpConsumables(newLevel)
    if not notifyCurrentCharacterEnabled() or not newLevel then return end
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end
    local BA = AltArmy.BankAlt
    if BA and BA.Is then
        local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
        local name = char.name or ""
        if BA.Is(name, realm) then return end
    end
    if DS.ScanBags then DS:ScanBags() end

    local candidates = {}
    local candidateOrder = {}
    local function consider(link, location)
        if not link then return end
        if consumableRequiredLevel(link) ~= newLevel then return end
        local key = extractItemId(link) or link
        noteLevelUpCandidate(candidates, candidateOrder, key, location)
        local entry = candidates[key]
        if not entry then return end
        local stored = entry.link
        local storedIsHyperlink = type(stored) == "string" and stored:find("|H")
        if not storedIsHyperlink then
            entry.link = link
        end
    end

    if DS.IterateBagSlots then
        DS:IterateBagSlots(char, function(_, _, itemId, _, link)
            consider(resolveOwnedLink(itemId, link), "bag")
        end)
    elseif GetContainerNumSlots and GetContainerItemLink then
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                consider(GetContainerItemLink(bag, slot), "bag")
            end
        end
    end

    if DS.IterateBankSlots then
        DS:IterateBankSlots(char, function(_, _, itemId, _, link)
            consider(resolveOwnedLink(itemId, link), "bank")
        end)
    end

    local numMails = DS.GetNumMails and DS:GetNumMails(char) or 0
    for i = 1, numMails do
        if DS.GetMailInfo then
            local _, _, link = DS:GetMailInfo(char, i)
            consider(link, "mail")
        end
    end

    if #candidateOrder == 0 then return end
    local found = {}
    for i = 1, #candidateOrder do
        found[i] = candidates[candidateOrder[i]]
    end
    postChat(ALTARMY_GOLD .. "Alt Army|r "
        .. GA.FormatLevelUpConsumeMessage(found))
end

function GA.HandleSetItemRef(link, button)
    if button and button ~= "LeftButton" then return false end
    local itemLink = parseUpgradeLink(link)
    if not itemLink then return false end
    if AltArmy.OpenGearTabFocused then
        AltArmy.OpenGearTabFocused(itemLink)
        return true
    end
    return false
end

local function onUpgradeSetItemRef(_, link, _, button)
    GA.HandleSetItemRef(link, button)
end

--- Handle upgrade chat links without replacing SetItemRef (that taints player link menus).
local function installUpgradeLinkInterceptors()
    if GA._upgradeLinkInterceptorsInstalled then return end
    GA._upgradeLinkInterceptorsInstalled = true

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", onUpgradeSetItemRef, GA)
        return
    end

    if hooksecurefunc then
        hooksecurefunc("SetItemRef", function(link, _, _, button)
            GA.HandleSetItemRef(link, button)
        end)
        if ChatFrame_OnHyperlinkClick then
            hooksecurefunc("ChatFrame_OnHyperlinkClick", function(_, link, _, button)
                GA.HandleSetItemRef(link, button)
            end)
        end
    end
end

local alertFrame = CreateFrame("Frame", "AltArmyTBC_GearUpgradeAlertFrame", UIParent)
alertFrame:RegisterEvent("CHAT_MSG_LOOT")
alertFrame:RegisterEvent("START_LOOT_ROLL")
alertFrame:RegisterEvent("PLAYER_LEVEL_UP")
alertFrame:RegisterEvent("QUEST_COMPLETE")
alertFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
alertFrame:RegisterEvent("ADDON_LOADED")
alertFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        installUpgradeLinkInterceptors()
    elseif event == "CHAT_MSG_LOOT" then
        local msg = arg1
        if not isSelfLootMessage(msg) then return end
        local link = extractItemLink(msg)
        if link then
            maybeLogItemComparison(link)
            GA.AnnounceLootUpgrade(link)
        end
    elseif event == "START_LOOT_ROLL" then
        GA.AnnounceLootRollUpgrade(arg1)
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(arg1) or (UnitLevel and UnitLevel("player"))
        GA.ScheduleLevelUpUpgradeAnnouncement(newLevel)
    elseif event == "QUEST_COMPLETE" then
        local ctimer = _G.C_Timer
        if ctimer and ctimer.After then
            ctimer.After(0, GA.AnnounceQuestRewardUpgrades)
        else
            GA.AnnounceQuestRewardUpgrades()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        GA.OnEnteringWorld()
    end
end)

installUpgradeLinkInterceptors()
