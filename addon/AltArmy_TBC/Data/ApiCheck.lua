-- AltArmy TBC — Blizzard API existence check.
-- Manual diagnostic only: /altarmy debug apicheck. Never runs on its own (no
-- login hook, no event registration) — defining this file costs nothing.
-- Full per-entry results go to AltArmyTBC_Options.debug.apiCheckSnapshot
-- (read it from the SavedVariables .lua file after /reload); chat only gets
-- a one-line status.

if not AltArmy then return end

AltArmy.ApiCheck = AltArmy.ApiCheck or {}
local AC = AltArmy.ApiCheck

-- Each entry is ONE logical capability the addon depends on somewhere in its
-- code. `candidates` are dotted-path strings tried in order; the first one
-- that resolves wins. A fallback pair (old global vs. new namespaced API,
-- e.g. GetContainerItemInfo / C_Container.GetContainerItemInfo) is modeled
-- as a single entry with two candidates, not two independent checks — the
-- addon's own code already falls back the same way, so that's not a break.
AC.MANIFEST = {
    -- Bags/Containers
    { area = "Bags/Containers", label = "GetContainerNumSlots",
      candidates = { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" } },
    { area = "Bags/Containers", label = "GetContainerItemInfo",
      candidates = { "C_Container.GetContainerItemInfo", "GetContainerItemInfo" } },
    { area = "Bags/Containers", label = "GetContainerItemLink",
      candidates = { "C_Container.GetContainerItemLink", "GetContainerItemLink" } },
    { area = "Bags/Containers", label = "ContainerIDToInventoryID",
      candidates = { "C_Container.ContainerIDToInventoryID", "ContainerIDToInventoryID" } },
    { area = "Bags/Containers", label = "GetContainerNumFreeSlots",
      candidates = { "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" } },
    { area = "Bags/Containers", label = "UseContainerItem",
      candidates = { "C_Container.UseContainerItem", "UseContainerItem" } },
    { area = "Bags/Containers", label = "SplitContainerItem",
      candidates = { "C_Container.SplitContainerItem", "SplitContainerItem" } },
    { area = "Bags/Containers", label = "PickupContainerItem",
      candidates = { "C_Container.PickupContainerItem", "PickupContainerItem" } },

    -- Inventory/Equipment
    { area = "Inventory/Equipment", label = "GetInventorySlotInfo", candidates = { "GetInventorySlotInfo" } },
    { area = "Inventory/Equipment", label = "GetInventoryItemLink", candidates = { "GetInventoryItemLink" } },
    { area = "Inventory/Equipment", label = "GetInventoryItemID", candidates = { "GetInventoryItemID" } },

    -- Item/Spell Info
    { area = "Item Info", label = "GetItemInfo", candidates = { "GetItemInfo", "C_Item.GetItemInfo" } },
    { area = "Item Info", label = "GetItemInfoInstant",
      candidates = { "GetItemInfoInstant", "C_Item.GetItemInfoInstant" } },
    { area = "Item Info", label = "GetItemStats", candidates = { "GetItemStats", "C_Item.GetItemStats" } },
    { area = "Item Info", label = "IsUsableItem", candidates = { "IsUsableItem", "C_Item.IsUsableItem" } },
    { area = "Item Info", label = "GetItemQualityColor", candidates = { "GetItemQualityColor" } },
    { area = "Item Info", label = "GetSpellInfo", candidates = { "GetSpellInfo", "C_Spell.GetSpellInfo" } },
    { area = "Item Info", label = "GetSpellLink", candidates = { "GetSpellLink", "C_Spell.GetSpellLink" } },
    -- Profession cooldown capture after a cast (DataStoreProfessions GetSpellCooldownCompat).
    { area = "Item Info", label = "GetSpellCooldown",
      candidates = { "GetSpellCooldown", "C_Spell.GetSpellCooldown" } },

    -- Professions/Tradeskills
    { area = "Professions", label = "GetNumTradeSkills", candidates = { "GetNumTradeSkills" } },
    { area = "Professions", label = "GetTradeSkillInfo", candidates = { "GetTradeSkillInfo" } },
    { area = "Professions", label = "GetTradeSkillLine", candidates = { "GetTradeSkillLine" } },
    { area = "Professions", label = "GetTradeSkillItemLink", candidates = { "GetTradeSkillItemLink" } },
    { area = "Professions", label = "GetTradeSkillRecipeLink", candidates = { "GetTradeSkillRecipeLink" } },
    { area = "Professions", label = "ExpandTradeSkillSubClass", candidates = { "ExpandTradeSkillSubClass" } },
    { area = "Professions", label = "GetTradeSkillNumReagents", candidates = { "GetTradeSkillNumReagents" } },
    { area = "Professions", label = "GetTradeSkillReagentItemLink", candidates = { "GetTradeSkillReagentItemLink" } },
    { area = "Professions", label = "GetTradeSkillReagentInfo", candidates = { "GetTradeSkillReagentInfo" } },
    { area = "Professions", label = "GetNumSkillLines", candidates = { "GetNumSkillLines" } },
    { area = "Professions", label = "GetSkillLineInfo", candidates = { "GetSkillLineInfo" } },
    { area = "Professions", label = "GetMacroInfo", candidates = { "GetMacroInfo" } },
    -- Fallback for the GetNumSkillLines/GetSkillLineInfo pair above (profession presence + rank
    -- only, not recipes): stable since Patch 4.0.1, used by Thaoky's DataStore_Crafts on Cata+
    -- clients. Now wired into DataStoreProfessions.lua's ScanProfessionLinks as a fallback; these
    -- rows confirm whether it's actually present on WoW Forever.
    { area = "Professions", label = "GetProfessions", candidates = { "GetProfessions" } },
    { area = "Professions", label = "GetProfessionInfo", candidates = { "GetProfessionInfo" } },
    -- Fallback for GetNumTradeSkills/GetTradeSkillInfo/GetTradeSkillLine above (recipe presence,
    -- category, learned state, difficulty — not reagents, still deferred). Now wired into
    -- DataStoreProfessions.lua's ScanRecipes as a fallback; see
    -- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth".
    { area = "Professions", label = "C_TradeSkillUI.GetAllRecipeIDs",
      candidates = { "C_TradeSkillUI.GetAllRecipeIDs" } },
    { area = "Professions", label = "C_TradeSkillUI.GetRecipeInfo", candidates = { "C_TradeSkillUI.GetRecipeInfo" } },
    { area = "Professions", label = "C_TradeSkillUI.GetBaseProfessionInfo",
      candidates = { "C_TradeSkillUI.GetBaseProfessionInfo" } },
    -- Best-effort resultItemID source (falls back to nil, not a legacy API's replacement).
    { area = "Professions", label = "C_TradeSkillUI.GetRecipeOutputItemData",
      candidates = { "C_TradeSkillUI.GetRecipeOutputItemData" } },
    { area = "Professions", label = "C_TradeSkillUI.GetRecipeCooldown",
      candidates = { "C_TradeSkillUI.GetRecipeCooldown" } },
    -- Reading the player's own recipes in the background (DataStore/OwnRecipeRead.lua): the profession's
    -- spell from the spellbook, closing the window it opened, and telling a linked window from our own.
    { area = "Professions", label = "C_SpellBook.GetSpellBookItemInfo",
      candidates = { "C_SpellBook.GetSpellBookItemInfo" } },
    { area = "Professions", label = "C_TradeSkillUI.CloseTradeSkill",
      candidates = { "C_TradeSkillUI.CloseTradeSkill" } },
    { area = "Professions", label = "C_TradeSkillUI.IsTradeSkillLinked",
      candidates = { "C_TradeSkillUI.IsTradeSkillLinked" } },
    { area = "Professions", label = "C_TradeSkillUI.GetBaseProfessionInfo",
      candidates = { "C_TradeSkillUI.GetBaseProfessionInfo" } },

    -- Crafting (old-style profession UI; some TBC-era professions still use this)
    { area = "Crafting", label = "GetCraftSkillLine", candidates = { "GetCraftSkillLine" } },
    { area = "Crafting", label = "GetNumCrafts", candidates = { "GetNumCrafts" } },
    { area = "Crafting", label = "GetCraftInfo", candidates = { "GetCraftInfo" } },
    { area = "Crafting", label = "GetCraftRecipeLink", candidates = { "GetCraftRecipeLink" } },
    { area = "Crafting", label = "GetCraftNumReagents", candidates = { "GetCraftNumReagents" } },
    { area = "Crafting", label = "GetCraftReagentInfo", candidates = { "GetCraftReagentInfo" } },

    -- Reputations
    { area = "Reputations", label = "GetNumFactions",
      candidates = { "GetNumFactions", "C_Reputation.GetNumFactions" } },
    { area = "Reputations", label = "GetFactionInfo",
      candidates = { "GetFactionInfo", "C_Reputation.GetFactionDataByIndex" } },
    { area = "Reputations", label = "GetFactionInfoByID",
      candidates = { "GetFactionInfoByID", "C_Reputation.GetFactionDataByID" } },
    { area = "Reputations", label = "ExpandFactionHeader",
      candidates = { "ExpandFactionHeader", "C_Reputation.ExpandFactionHeader" } },

    -- Mail
    { area = "Mail", label = "GetInboxNumItems", candidates = { "GetInboxNumItems" } },
    { area = "Mail", label = "GetInboxHeaderInfo", candidates = { "GetInboxHeaderInfo" } },
    { area = "Mail", label = "GetInboxItem", candidates = { "GetInboxItem" } },
    { area = "Mail", label = "GetInboxItemLink", candidates = { "GetInboxItemLink" } },
    { area = "Mail", label = "SendMail", candidates = { "SendMail" } },
    { area = "Mail", label = "ReturnInboxItem", candidates = { "ReturnInboxItem" } },

    -- Auctions
    { area = "Auctions", label = "GetNumAuctionItems",
      candidates = { "GetNumAuctionItems", "C_AuctionHouse.GetNumOwnedAuctions" } },
    { area = "Auctions", label = "GetAuctionItemInfo",
      candidates = { "GetAuctionItemInfo", "C_AuctionHouse.GetOwnedAuctionInfo" } },
    { area = "Auctions", label = "GetAuctionItemLink", candidates = { "GetAuctionItemLink" } },
    { area = "Auctions", label = "GetNumBids", candidates = { "GetNumAuctionItems", "C_AuctionHouse.GetNumBids" } },
    { area = "Auctions", label = "GetBidInfo",
      candidates = { "GetAuctionItemInfo", "C_AuctionHouse.GetBidInfo" } },

    -- Auction house listings (every listing at once: the full scan the website's prices are to come
    -- from). Existing says nothing about what they return: /altarmy debug ahprobe asks once
    -- (AuctionProbe.lua). The browse and search entries are the fallback if the full scan is missing.
    { area = "Auction Listings", label = "ReplicateItems", candidates = { "C_AuctionHouse.ReplicateItems" } },
    { area = "Auction Listings", label = "GetNumReplicateItems",
      candidates = { "C_AuctionHouse.GetNumReplicateItems" } },
    { area = "Auction Listings", label = "GetReplicateItemInfo",
      candidates = { "C_AuctionHouse.GetReplicateItemInfo" } },
    { area = "Auction Listings", label = "GetReplicateItemLink",
      candidates = { "C_AuctionHouse.GetReplicateItemLink" } },
    { area = "Auction Listings", label = "GetReplicateItemTimeLeft",
      candidates = { "C_AuctionHouse.GetReplicateItemTimeLeft" } },
    { area = "Auction Listings", label = "SendBrowseQuery", candidates = { "C_AuctionHouse.SendBrowseQuery" } },
    { area = "Auction Listings", label = "GetBrowseResults",
      candidates = { "C_AuctionHouse.GetBrowseResults" } },
    { area = "Auction Listings", label = "SendSearchQuery", candidates = { "C_AuctionHouse.SendSearchQuery" } },
    { area = "Auction Listings", label = "GetCommoditySearchResultInfo",
      candidates = { "C_AuctionHouse.GetCommoditySearchResultInfo" } },
    { area = "Auction Listings", label = "GetItemSearchResultInfo",
      candidates = { "C_AuctionHouse.GetItemSearchResultInfo" } },
    { area = "Auction Listings", label = "GetServerTime", candidates = { "GetServerTime" } },

    -- Talents
    { area = "Talents", label = "GetNumTalentTabs", candidates = { "GetNumTalentTabs" } },
    { area = "Talents", label = "GetTalentTabInfo", candidates = { "GetTalentTabInfo" } },
    -- Fallback for the pair above on clients (e.g. WoW Forever) where the legacy talent-tree API is
    -- gone; wired into DataStoreTalents.lua's ScanTalents as an alternate spec-detection path. See
    -- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md.
    { area = "Talents", label = "GetSpecialization",
      candidates = { "C_SpecializationInfo.GetSpecialization", "GetSpecialization" } },
    { area = "Talents", label = "GetSpecializationInfo",
      candidates = { "C_SpecializationInfo.GetSpecializationInfo", "GetSpecializationInfo" } },

    -- Legacy Talents (WoW Forever's account-wide Legacy Points system). Unconfirmed guesses — see
    -- DataStoreLegacy.lua's header and docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md ("Legacy
    -- Talents"). C_ClassTalents.GetActiveConfigID turned out to return the class-talent config, not
    -- the Legacy one; the Legacy config is now resolved by its DB2 trait system/tree ids
    -- (GetConfigIDBySystemID, else GetConfigIDByTreeID), which this check exists to confirm.
    { area = "Legacy Talents", label = "ToggleLegacySystemUI", candidates = { "ToggleLegacySystemUI" } },
    { area = "Legacy Talents", label = "C_ClassTalents.GetActiveConfigID",
      candidates = { "C_ClassTalents.GetActiveConfigID" } },
    { area = "Legacy Talents", label = "C_Traits.GetConfigIDBySystemID",
      candidates = { "C_Traits.GetConfigIDBySystemID" } },
    { area = "Legacy Talents", label = "C_Traits.GetConfigIDByTreeID",
      candidates = { "C_Traits.GetConfigIDByTreeID" } },
    { area = "Legacy Talents", label = "C_Traits.GetConfigInfo", candidates = { "C_Traits.GetConfigInfo" } },
    { area = "Legacy Talents", label = "C_Traits.GetTreeNodes", candidates = { "C_Traits.GetTreeNodes" } },
    { area = "Legacy Talents", label = "C_Traits.GetNodeInfo", candidates = { "C_Traits.GetNodeInfo" } },
    { area = "Legacy Talents", label = "C_Traits.GetEntryInfo", candidates = { "C_Traits.GetEntryInfo" } },
    { area = "Legacy Talents", label = "C_Traits.GetDefinitionInfo",
      candidates = { "C_Traits.GetDefinitionInfo" } },

    -- Lockouts/Raids
    { area = "Lockouts", label = "RequestRaidInfo", candidates = { "RequestRaidInfo" } },
    { area = "Lockouts", label = "GetNumSavedInstances", candidates = { "GetNumSavedInstances" } },
    { area = "Lockouts", label = "GetSavedInstanceInfo", candidates = { "GetSavedInstanceInfo" } },

    -- Guild
    { area = "Guild", label = "GetGuildInfo", candidates = { "GetGuildInfo" } },
    { area = "Guild", label = "IsInGuild", candidates = { "IsInGuild" } },
    { area = "Guild", label = "GetNumGuildMembers", candidates = { "GetNumGuildMembers" } },
    { area = "Guild", label = "GetGuildRosterInfo", candidates = { "GetGuildRosterInfo" } },
    { area = "Guild", label = "GuildRoster", candidates = { "C_GuildInfo.GuildRoster", "GuildRoster" } },
    { area = "Guild", label = "GetGuildTabardInfo", candidates = { "C_GuildInfo.GetGuildTabardInfo" } },
    -- Reading guildmates' recipes by profession link (Guild/GuildLinkRead.lua) needs the roster's GUIDs
    -- (GetGuildRosterInfo's 17th return). Retail's guild profession roster, if Forever has it, would list
    -- every member's professions without a link: not used yet, checked so we learn whether it exists.
    { area = "Guild", label = "GetNumGuildTradeSkill", candidates = { "GetNumGuildTradeSkill" } },
    { area = "Guild", label = "GetGuildTradeSkillInfo", candidates = { "GetGuildTradeSkillInfo" } },
    { area = "Guild", label = "QueryGuildRecipes", candidates = { "QueryGuildRecipes" } },

    -- Addon/Timer/Chat infra
    { area = "Addon Infra", label = "IsAddOnLoaded",
      candidates = { "C_AddOns.IsAddOnLoaded", "IsAddOnLoaded" } },
    { area = "Addon Infra", label = "GetAddOnMetadata",
      candidates = { "C_AddOns.GetAddOnMetadata", "GetAddOnMetadata" } },
    { area = "Addon Infra", label = "C_Timer.After", candidates = { "C_Timer.After" } },
    { area = "Addon Infra", label = "RegisterAddonMessagePrefix",
      candidates = { "C_ChatInfo.RegisterAddonMessagePrefix" } },
    { area = "Addon Infra", label = "SendAddonMessage",
      candidates = { "C_ChatInfo.SendAddonMessage", "SendAddonMessage" } },
    { area = "Addon Infra", label = "SendChatMessage", candidates = { "SendChatMessage" } },
    { area = "Addon Infra", label = "hooksecurefunc", candidates = { "hooksecurefunc" } },
    { area = "Addon Infra", label = "GetBuildInfo", candidates = { "GetBuildInfo" } },

    -- Battle.net: linked accounts send each other their characters as game data between your own
    -- WoW accounts (Data/Link/LinkDiscovery.lua, /altarmy debug bnprobe).
    { area = "Battle.net", label = "BNGetInfo", candidates = { "BNGetInfo" } },
    { area = "Battle.net", label = "GetGameAccountInfoByID",
      candidates = { "C_BattleNet.GetGameAccountInfoByID" } },
    { area = "Battle.net", label = "GetAccountInfoByGUID", candidates = { "C_BattleNet.GetAccountInfoByGUID" } },
    { area = "Battle.net", label = "BNGetGameAccountInfo", candidates = { "BNGetGameAccountInfo" } },
    { area = "Battle.net", label = "SendGameData", candidates = { "C_BattleNet.SendGameData", "BNSendGameData" } },
    { area = "Battle.net", label = "InChatMessagingLockdown",
      candidates = { "C_ChatInfo.InChatMessagingLockdown" } },
    { area = "Battle.net", label = "issecretvalue", candidates = { "issecretvalue" } },
    { area = "Battle.net", label = "IsGUIDRelatedToLocalAccount",
      candidates = { "C_AccountInfo.IsGUIDRelatedToLocalAccount" } },

    -- Unit/Player Info
    { area = "Unit Info", label = "UnitName", candidates = { "UnitName" } },
    { area = "Unit Info", label = "UnitLevel", candidates = { "UnitLevel" } },
    { area = "Unit Info", label = "UnitClass", candidates = { "UnitClass" } },
    { area = "Unit Info", label = "UnitRace", candidates = { "UnitRace" } },
    { area = "Unit Info", label = "UnitFactionGroup", candidates = { "UnitFactionGroup" } },
    { area = "Unit Info", label = "UnitGUID", candidates = { "UnitGUID" } },
    { area = "Unit Info", label = "UnitXPMax", candidates = { "UnitXPMax" } },
    { area = "Unit Info", label = "GetMaxPlayerLevel", candidates = { "GetMaxPlayerLevel" } },
    { area = "Unit Info", label = "GetRealmName", candidates = { "GetRealmName" } },
    { area = "Unit Info", label = "GetMoney", candidates = { "GetMoney" } },
    { area = "Unit Info", label = "GetXPExhaustion", candidates = { "GetXPExhaustion" } },
    { area = "Unit Info", label = "GetRealZoneText", candidates = { "GetRealZoneText" } },
    { area = "Unit Info", label = "RequestTimePlayed", candidates = { "RequestTimePlayed" } },
    { area = "Unit Info", label = "ChatFrame_DisplayTimePlayed", candidates = { "ChatFrame_DisplayTimePlayed" } },
    { area = "Unit Info", label = "CombatLogGetCurrentEventInfo", candidates = { "CombatLogGetCurrentEventInfo" } },

    -- Quests
    { area = "Quests", label = "GetNumQuestChoices", candidates = { "GetNumQuestChoices" } },
    { area = "Quests", label = "GetNumQuestRewards", candidates = { "GetNumQuestRewards" } },
    { area = "Quests", label = "SelectQuestLogEntry", candidates = { "SelectQuestLogEntry" } },
    -- The quest log, read for Craftsman's Writ orders (Data/Economy/WritOrders.lua).
    { area = "Quests", label = "GetNumQuestLogEntries",
      candidates = { "C_QuestLog.GetNumQuestLogEntries", "GetNumQuestLogEntries" } },
    { area = "Quests", label = "GetQuestLogInfo", candidates = { "C_QuestLog.GetInfo", "GetQuestLogTitle" } },
    { area = "Quests", label = "GetQuestObjectives",
      candidates = { "C_QuestLog.GetQuestObjectives", "GetQuestLogLeaderBoard" } },
    { area = "Quests", label = "GetNumQuestLeaderBoards", candidates = { "GetNumQuestLeaderBoards" } },

    -- Misc UI
    { area = "Misc UI", label = "CreateFrame", candidates = { "CreateFrame" } },
    { area = "Misc UI", label = "GetCursorPosition", candidates = { "GetCursorPosition" } },
    { area = "Misc UI", label = "GetCursorInfo", candidates = { "GetCursorInfo" } },
    { area = "Misc UI", label = "ChatFrame_AddMessageEventFilter", candidates = { "ChatFrame_AddMessageEventFilter" } },
    { area = "Misc UI", label = "ChatFrame_OnHyperlinkClick", candidates = { "ChatFrame_OnHyperlinkClick" } },
    { area = "Misc UI", label = "SetItemRef", candidates = { "SetItemRef" } },
    { area = "Misc UI", label = "DEFAULT_CHAT_FRAME", candidates = { "DEFAULT_CHAT_FRAME" } },
    { area = "Misc UI", label = "GameTooltip.SetOwner", candidates = { "GameTooltip.SetOwner" } },
}

--- Walks `root` (defaults to _G) along a dotted path (e.g. "C_Container.GetContainerItemInfo").
--- Returns (value, true) if found, or (nil, false) if any segment is missing/not a table.
--- Side-effect-free — never calls the resolved function.
function AC.Resolve(path, root)
    root = root or _G
    local node = root
    for part in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then
            return nil, false
        end
        node = node[part]
    end
    if node == nil then
        return nil, false
    end
    return node, true
end

--- Checks one manifest entry against `root`. Returns "ok" (first/preferred
--- candidate resolved), "fallback" (a later candidate resolved), or
--- "missing" (none resolved), plus the matched candidate path (or nil).
function AC.CheckEntry(entry, root)
    for i, candidate in ipairs(entry.candidates) do
        local _, found = AC.Resolve(candidate, root)
        if found then
            return (i == 1) and "ok" or "fallback", candidate
        end
    end
    return "missing", nil
end

--- Runs `manifest` (defaults to AC.MANIFEST) against `root` (defaults to _G).
--- Returns (results, counts). results[i] = { area, label, status, matched, candidates }.
function AC.Run(manifest, root)
    manifest = manifest or AC.MANIFEST
    local results, counts = {}, { total = 0, ok = 0, fallback = 0, missing = 0 }
    for _, entry in ipairs(manifest) do
        local status, matched = AC.CheckEntry(entry, root)
        counts.total = counts.total + 1
        counts[status] = counts[status] + 1
        results[#results + 1] = {
            area = entry.area,
            label = entry.label,
            status = status,
            matched = matched,
            candidates = entry.candidates,
        }
    end
    return results, counts
end

function AC.BuildSnapshot(root)
    local results, counts = AC.Run(AC.MANIFEST, root)
    return {
        version = 1,
        timestamp = time and time() or 0,
        interface = GetBuildInfo and select(4, GetBuildInfo()) or nil,
        results = results,
        counts = counts,
    }
end

--- Prints a single terse status line — no per-entry/per-area detail. The
--- snapshot itself (saved separately) carries the detail for offline review.
function AC.ReportToChat(snapshot)
    local D = AltArmy.Debug
    if not D or not D.NotifyChat then
        return
    end
    local c = snapshot.counts
    if c.missing == 0 then
        D.NotifyChat(string.format(
            "|cff00ccff[Alt Army:ApiCheck]|r Checked %d API(s). No issues detected.", c.total))
    else
        D.NotifyChat(string.format(
            "|cff00ccff[Alt Army:ApiCheck]|r Checked %d API(s). %d issue(s) found — see the dump. "
                .. "/reload, then open WTF/.../SavedVariables/AltArmy_TBC.lua and look for debug.apiCheckSnapshot.",
            c.total, c.missing))
    end
end

--- Entry point for the /altarmy debug apicheck slash command. Never called
--- automatically — no login hook, no event registration anywhere in this file.
function AC.RunAndReport()
    local snapshot = AC.BuildSnapshot(_G)
    local D = AltArmy.Debug
    if D and D.SaveApiCheckSnapshot then
        D.SaveApiCheckSnapshot(snapshot)
    end
    AC.ReportToChat(snapshot)
    return snapshot
end
