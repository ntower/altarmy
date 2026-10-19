-- AltArmy TBC — DataStore module: professions (skills + recipes).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local function scheduleGuildShareBroadcast()
    local Comm = AltArmy and AltArmy.GuildShareComm
    if Comm and Comm.ScheduleBroadcast then
        -- Longer quiet period than Options edits: craft casts often exceed 5s, so a 5s
        -- trailing debounce would still fire once per skill-up during a crafting session.
        Comm.ScheduleBroadcast(Comm.PROFESSION_BROADCAST_DEBOUNCE_SEC)
    end
end

local function notifyRecipesChanged()
    local SD = AltArmy and AltArmy.SearchData
    if SD and SD.NotifyRecipesChanged then
        SD.NotifyRecipesChanged()
    end
    -- Presence includes profession ranks + recipe count/hash; coalesce with settings edits.
    scheduleGuildShareBroadcast()
    -- linked accounts: this character's partial manifest (debounced) carries the new recipes
    local T = AltArmy and AltArmy.LinkTransport
    if T and T.NoteLocalChange then
        T.NoteLocalChange()
    end
end

--- Chat debug for cooldown persistence. Enable: /altarmy debug on, then AltArmy > Debug > cooldown scans.
local function CooldownsDebugEnabled()
    local Dbg = AltArmy and AltArmy.Debug
    return Dbg and Dbg.IsCooldownsEnabled and Dbg.IsCooldownsEnabled()
end

local function LogCooldownScanDebug(msg)
    if not CooldownsDebugEnabled() then
        return
    end
    local text = "|cff00ccff[Alt Army:CD]|r " .. tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

--- WoW 2^32 ms clock offset (seconds) for reboot-corrupted GetSpellCooldown start times.
local UINT32_OFFSET_SEC = 4294967296 / 1000

--- Seconds left from GetSpellCooldown / GetActionCooldown (start, duration).
local function CooldownRemainingSecondsFromSpellApi(a, b, gt, wall)
    gt = gt or 0
    wall = wall or 0
    if type(a) ~= "number" or a < 0 then
        return 0
    end
    if type(b) ~= "number" or b <= 0 then
        return 0
    end

    local remaining
    if a <= gt then
        remaining = a + b - gt
    elseif a <= UINT32_OFFSET_SEC then
        -- Post-reboot corruption: start appears ahead of GetTime() in the 2^32 wrap range.
        local startupTime = wall - gt
        local cdTime = UINT32_OFFSET_SEC - a
        local cdStartTime = startupTime - cdTime
        local cdEndTime = cdStartTime + b
        remaining = cdEndTime - wall
    else
        -- start >> GetTime() (e.g. long-uptime multi-day CD): duration is the reliable signal.
        remaining = b
    end

    return math.max(0, remaining)
end

--- Seconds left from GetTradeSkillCooldown / GetCraftCooldown (remaining, isDayCooldown).
local function CooldownRemainingSecondsFromTradeSkillApi(a, _b)
    if type(a) ~= "number" or a < 0 then
        return 0
    end
    return a
end

local function CooldownRemainingSeconds(a, b, gt, wall, apiKind)
    if apiKind == "tradeskill" then
        return CooldownRemainingSecondsFromTradeSkillApi(a, b)
    end
    return CooldownRemainingSecondsFromSpellApi(a, b, gt, wall)
end

--- (start, duration) from the global GetSpellCooldown, or C_Spell.GetSpellCooldown's table where
--- the global is gone (WoW Forever). nil when neither API exists.
local function GetSpellCooldownCompat(spellId)
    local legacy = _G.GetSpellCooldown
    if legacy then
        return legacy(spellId)
    end
    local cSpell = _G.C_Spell
    if not cSpell or not cSpell.GetSpellCooldown then return nil end
    local ok, info = pcall(cSpell.GetSpellCooldown, spellId)
    if not ok or type(info) ~= "table" then return 0, 0 end
    return info.startTime, info.duration
end

local function HasSpellCooldownApi()
    return _G.GetSpellCooldown ~= nil or (_G.C_Spell ~= nil and _G.C_Spell.GetSpellCooldown ~= nil)
end

local function PrevExpiryUnix(char, spellId)
    if not char or not spellId then return nil end
    local t = char.ProfCooldownExpiry and char.ProfCooldownExpiry[spellId]
    if type(t) == "table" then
        return t.expiresAtUnix
    end
    if type(t) == "number" then
        return t
    end
    return nil
end

--- Persist a scanned cooldown safely.
--- Guard: zoning/loading can transiently return (0,0) for cooldown APIs even when not actually ready.
--- If we already have a future expiry and the scan returns exactly (0,0), keep the existing expiry.
--- @param apiKind string|nil "spell" (GetSpellCooldown) or "tradeskill" (GetTradeSkillCooldown / GetCraftCooldown)
local function PersistCooldownExpiry(char, spellId, a, b, gt, wall, logPrefix, apiKind)
    if not char or not spellId then return false end
    gt = gt or (GetTime and GetTime() or 0)
    wall = wall or (time and time() or 0)
    apiKind = apiKind or "spell"

    local remaining = CooldownRemainingSeconds(a, b, gt, wall, apiKind)
    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    if remaining <= 0 then
        local prev = PrevExpiryUnix(char, spellId)
        local a0 = type(a) == "number" and a == 0
        local b0 = (b == nil) or (type(b) == "number" and b == 0)
        if a0 and b0 and type(prev) == "number" and prev > (wall + 30) then
            LogCooldownScanDebug(string.format(
                "%s spell=%d suppress overwrite from (0,0); prevExpUnix=%s wall=%s",
                tostring(logPrefix or "Persist"),
                spellId,
                tostring(prev),
                tostring(wall)
            ))
            return false
        end
        char.ProfCooldownExpiry[spellId] = { expiresAtUnix = wall }
        return true
    end

    char.ProfCooldownExpiry[spellId] = { expiresAtUnix = wall + math.ceil(remaining) }
    return true
end

-- Exposed for unit tests (see spec/Data/DataStoreProfessions_spec.lua)
DS._PersistCooldownExpiryForTest = PersistCooldownExpiry
DS._CooldownRemainingSecondsFromSpellApiForTest = CooldownRemainingSecondsFromSpellApi
DS._CooldownRemainingSecondsFromTradeSkillApiForTest = CooldownRemainingSecondsFromTradeSkillApi

local SkillTypeToColor = { header = 0, optimal = 1, medium = 2, easy = 3, trivial = 4 }
local SPELL_ID_FIRSTAID = 3273
local SPELL_ID_COOKING = 2550
local SPELL_ID_FISHING = 7732

-- Legacy GetSpellInfo is absent on some clients (e.g. WoW Forever beta — see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md); DS.CompatGetSpellInfo (from
-- DataStoreItemSpellCompat.lua) falls back to C_Spell.GetSpellInfo. Checked
-- dynamically, not captured as a load-time upvalue (see that doc's Reputations
-- lesson on why).
local function HasSpellInfoApi()
    return GetSpellInfo ~= nil or (C_Spell ~= nil and C_Spell.GetSpellInfo ~= nil)
end

local function NormalizeProfessionName(name)
    if not name or name == "" or not HasSpellInfoApi() then
        return name
    end
    if name == "Secourisme" then
        return DS.CompatGetSpellInfo(SPELL_ID_FIRSTAID) or name
    end
    return name
end
DS.NormalizeProfessionName = NormalizeProfessionName

local function ApplyProfessionRank(prof, rank, maxRank)
    if not prof then
        return
    end
    if rank then
        prof.rank = rank
    end
    if maxRank then
        prof.maxRank = maxRank
    end
end

--- Expand all category headers (used by delayed reagent retry; full scan uses snapshot/restore).
local function ExpandAllTradeSkillHeaders()
    if not GetNumTradeSkills or not ExpandTradeSkillSubClass then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" and not isExpanded then
            ExpandTradeSkillSubClass(i)
        end
    end
end

-- Tradeskill UI snapshot (see DataStore_Crafts): force "All" filters + expand headers for scan, then restore.
local tsFilterSnapshot = {
    selectedIndex = nil,
    subClasses = nil,
    invSlots = nil,
    subClassID = nil,
    invSlotID = nil,
}

local tsHeaderCollapsed = {}

local function TradeSkillSubClassDropdownId()
    if not GetTradeSkillSubClassFilter then return 1 end
    if GetTradeSkillSubClassFilter(0) then
        return 1
    end
    local subs = tsFilterSnapshot.subClasses
    if not subs then return 1 end
    for i = 1, #subs do
        if GetTradeSkillSubClassFilter(i) then
            return i + 1
        end
    end
    return 1
end

local function TradeSkillInvSlotDropdownId()
    if not GetTradeSkillInvSlotFilter then return 1 end
    if GetTradeSkillInvSlotFilter(0) then
        return 1
    end
    local slots = tsFilterSnapshot.invSlots
    if not slots then return 1 end
    for i = 1, #slots do
        if GetTradeSkillInvSlotFilter(i) then
            return i + 1
        end
    end
    return 1
end

--- Returns true if subclass/slot filters were saved and switched to "All" (caller must restore).
local function SaveTradeSkillFiltersForScan()
    if not GetTradeSkillSelectionIndex or not SelectTradeSkill then return false end
    if not SetTradeSkillSubClassFilter or not SetTradeSkillInvSlotFilter then return false end
    if not GetTradeSkillSubClassFilter or not GetTradeSkillInvSlotFilter then return false end
    if not GetTradeSkillSubClasses or not GetTradeSkillInvSlots then return false end

    tsFilterSnapshot.selectedIndex = GetTradeSkillSelectionIndex()
    tsFilterSnapshot.subClasses = { GetTradeSkillSubClasses() }
    tsFilterSnapshot.invSlots = { GetTradeSkillInvSlots() }
    tsFilterSnapshot.subClassID = TradeSkillSubClassDropdownId()
    tsFilterSnapshot.invSlotID = TradeSkillInvSlotDropdownId()

    SetTradeSkillSubClassFilter(0, 1, 1)
    SetTradeSkillInvSlotFilter(0, 1, 1)
    if TradeSkillSubClassDropDown and UIDropDownMenu_SetSelectedID then
        UIDropDownMenu_SetSelectedID(TradeSkillSubClassDropDown, 1)
    end
    if TradeSkillInvSlotDropDown and UIDropDownMenu_SetSelectedID then
        UIDropDownMenu_SetSelectedID(TradeSkillInvSlotDropDown, 1)
    end
    return true
end

local function RestoreTradeSkillFiltersAfterScan()
    if tsFilterSnapshot.selectedIndex == nil then return end
    local subId = tsFilterSnapshot.subClassID
    local invId = tsFilterSnapshot.invSlotID
    local subs = tsFilterSnapshot.subClasses
    local slots = tsFilterSnapshot.invSlots

    if SetTradeSkillSubClassFilter and subId then
        SetTradeSkillSubClassFilter(subId - 1, 1, 1)
    end
    local frame = TradeSkillSubClassDropDown
    if frame and UIDropDownMenu_SetSelectedID and UIDropDownMenu_SetText and subs then
        local text = (subId == 1) and ALL_SUBCLASSES or subs[subId - 1]
        if text then
            UIDropDownMenu_SetSelectedID(frame, subId)
            UIDropDownMenu_SetText(frame, text)
        end
    end

    invId = invId or 1
    if SetTradeSkillInvSlotFilter then
        SetTradeSkillInvSlotFilter(invId - 1, 1, 1)
    end
    frame = TradeSkillInvSlotDropDown
    if frame and UIDropDownMenu_SetSelectedID and UIDropDownMenu_SetText and slots then
        local text = (invId == 1) and ALL_INVENTORY_SLOTS or slots[invId - 1]
        if text then
            UIDropDownMenu_SetSelectedID(frame, invId)
            UIDropDownMenu_SetText(frame, text)
        end
    end

    SelectTradeSkill(tsFilterSnapshot.selectedIndex)

    tsFilterSnapshot.selectedIndex = nil
    tsFilterSnapshot.subClasses = nil
    tsFilterSnapshot.invSlots = nil
    tsFilterSnapshot.subClassID = nil
    tsFilterSnapshot.invSlotID = nil
end

local function SaveTradeSkillHeadersForScan()
    wipe(tsHeaderCollapsed)
    if not GetNumTradeSkills or not GetTradeSkillInfo or not ExpandTradeSkillSubClass then return end
    local headerCount = 0
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if not isExpanded then
                ExpandTradeSkillSubClass(i)
                tsHeaderCollapsed[headerCount] = true
            end
        end
    end
end

local function RestoreTradeSkillHeadersAfterScan()
    if not GetNumTradeSkills or not GetTradeSkillInfo then
        wipe(tsHeaderCollapsed)
        return
    end
    local headerCount = 0
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if tsHeaderCollapsed[headerCount] and CollapseTradeSkillSubClass then
                CollapseTradeSkillSubClass(i)
            end
        end
    end
    wipe(tsHeaderCollapsed)
end

--- Spell ID from an item (pattern or crafted result), when the client exposes one (Cooldowns spell ids).
local function SpellIdFromItem(itemRef)
    if not itemRef or not GetItemSpell then return nil end
    local _, spellID = GetItemSpell(itemRef)
    if type(spellID) == "number" and spellID > 0 then
        return spellID
    end
    return nil
end

--- Match row title to Cooldown single-mode spells (hyperlink ids are often enchant/recipe, not cast spell).
local function AddCooldownSpellIdsMatchingRowName(index, add)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.CATEGORIES or not CD.CATEGORY_ORDER then return end
    if not GetTradeSkillInfo or not HasSpellInfoApi() then return end
    local rowName = select(1, GetTradeSkillInfo(index))
    if not rowName or rowName == "" then return end
    for _, catKey in ipairs(CD.CATEGORY_ORDER) do
        local cat = CD.CATEGORIES[catKey]
        if cat and cat.mode == "single" and cat.spellId then
            local sid = cat.spellId
            local spellTitle = DS.CompatGetSpellInfo(sid)
            if spellTitle and spellTitle == rowName then
                add(sid)
            end
        end
    end
end

--- All numeric ids for one tradeskill row: link ids + GetItemSpell for pattern/result (match CooldownData spell ids).
local function CollectRecipeIdsFromTradeSkillIndex(index)
    local ids = {}
    local seen = {}
    local function add(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if GetTradeSkillRecipeLink then
        local link = GetTradeSkillRecipeLink(index)
        if link then
            add(tonumber(link:match("enchant:(%d+)")))
            add(tonumber(link:match("spell:(%d+)")))
            local itemFromLink = tonumber(link:match("item:(%d+)"))
            add(itemFromLink)
            if itemFromLink then
                add(SpellIdFromItem(itemFromLink))
            end
        end
    end
    if GetTradeSkillItemLink then
        local itemLink = GetTradeSkillItemLink(index)
        local resultItemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
        if resultItemId then
            add(SpellIdFromItem(resultItemId))
        end
    end
    AddCooldownSpellIdsMatchingRowName(index, add)
    return ids
end

--- Pick the craft recipe id among alias keys sharing one prof.Recipes row (login migration).
local function InferPrimaryRecipeId(row, ids)
    if not row or not ids or #ids == 0 then
        return nil
    end
    if row.primaryRecipeID then
        return row.primaryRecipeID
    end
    if #ids == 1 then
        return ids[1]
    end

    local exclude = {}
    if row.resultItemID then
        local effectSpell = SpellIdFromItem(row.resultItemID)
        if effectSpell then
            exclude[effectSpell] = true
        end
    end

    local candidates = {}
    for _, id in ipairs(ids) do
        if not exclude[id] then
            candidates[#candidates + 1] = id
        end
    end

    if #candidates == 1 then
        return candidates[1]
    end

    local pool = #candidates > 0 and candidates or ids
    if HasSpellInfoApi() then
        table.sort(pool, function(a, b)
            local na = DS.CompatGetSpellInfo(a) or ""
            local nb = DS.CompatGetSpellInfo(b) or ""
            if #na ~= #nb then
                return #na > #nb
            end
            return a < b
        end)
        return pool[1]
    end

    table.sort(pool)
    return pool[1]
end
DS._InferPrimaryRecipeIdForTest = InferPrimaryRecipeId

local function MigrateOneProfessionRecipes(prof)
    if not prof or not prof.Recipes then
        return 0
    end
    local updated = 0

    for recipeID, data in pairs(prof.Recipes) do
        if type(data) == "number" then
            prof.Recipes[recipeID] = { color = data, primaryRecipeID = recipeID }
            updated = updated + 1
        end
    end

    local rowToIds = {}
    for recipeID, data in pairs(prof.Recipes) do
        if type(data) == "table" and not data.primaryRecipeID then
            local bucket = rowToIds[data]
            if not bucket then
                bucket = {}
                rowToIds[data] = bucket
            end
            bucket[#bucket + 1] = recipeID
        end
    end
    for row, ids in pairs(rowToIds) do
        local primary = InferPrimaryRecipeId(row, ids)
        if primary then
            row.primaryRecipeID = primary
            updated = updated + 1
        end
    end

    local byResultItem = {}
    for recipeID, data in pairs(prof.Recipes) do
        if type(data) == "table" and data.resultItemID then
            local bucket = byResultItem[data.resultItemID]
            if not bucket then
                bucket = {}
                byResultItem[data.resultItemID] = bucket
            end
            bucket[#bucket + 1] = recipeID
        end
    end
    for resultItemID, ids in pairs(byResultItem) do
        if #ids > 1 then
            local primary = InferPrimaryRecipeId({ resultItemID = resultItemID }, ids)
            if primary then
                local changed = false
                for _, id in ipairs(ids) do
                    local data = prof.Recipes[id]
                    if data and data.primaryRecipeID ~= primary then
                        data.primaryRecipeID = primary
                        changed = true
                    end
                end
                if changed then
                    updated = updated + 1
                end
            end
        end
    end

    for recipeID, data in pairs(prof.Recipes) do
        if type(data) == "table" and not data.primaryRecipeID then
            data.primaryRecipeID = recipeID
            updated = updated + 1
        end
    end

    return updated
end
DS._MigrateOneProfessionRecipesForTest = MigrateOneProfessionRecipes

function DS:ResetRecipePrimaryIdsMigration()
    local account = self.accountData or AltArmyTBC_Data
    if not account then
        return false
    end
    account.recipePrimaryIdsMigrated = nil
    account.recipePrimaryIdsMigrationVersion = nil
    return true
end

--- One-time account migration: backfill primaryRecipeID on stored recipe rows (search uses this only).
function DS:MigrateRecipePrimaryIds()
    local account = self.accountData or AltArmyTBC_Data
    if not account then
        return 0
    end
    if account.recipePrimaryIdsMigrated then
        return 0
    end

    local updated = 0
    self:ForEachCharacter(function(_, _, charData)
        if not charData or not charData.Professions then
            return
        end
        for _, prof in pairs(charData.Professions) do
            updated = updated + MigrateOneProfessionRecipes(prof)
        end
    end)

    account.recipePrimaryIdsMigrated = true
    account.recipePrimaryIdsMigrationVersion = nil
    if updated > 0 then
        notifyRecipesChanged()
    end
    return updated
end

function DS:RemigrateRecipePrimaryIdsDebug()
    self:ResetRecipePrimaryIdsMigration()
    return self:MigrateRecipePrimaryIds()
end

-- TBC crafting-profession specializations: profession key -> ordered { spellId, label }.
-- Order matters: the FIRST known spell wins, so list more specific specializations before
-- the general ones (e.g. Master Swordsmith before Weaponsmith). Labels are English; profession
-- names shown alongside them stay locale-safe (resolved via SearchSettings profession keys).
DS.PROFESSION_SPECIALIZATIONS = {
    alchemy = {
        { spellId = 28672, label = "Transmute" },
        { spellId = 28677, label = "Elixir" },
        { spellId = 28675, label = "Potion" },
    },
    blacksmithing = {
        { spellId = 17041, label = "Swordsmith" },
        { spellId = 17040, label = "Hammersmith" },
        { spellId = 17039, label = "Axesmith" },
        { spellId = 9788, label = "Armorsmith" },
        { spellId = 9787, label = "Weaponsmith" },
    },
    leatherworking = {
        { spellId = 10657, label = "Dragonscale" },
        { spellId = 10659, label = "Elemental" },
        { spellId = 10661, label = "Tribal" },
    },
    engineering = {
        { spellId = 20219, label = "Gnomish" },
        { spellId = 20222, label = "Goblin" },
    },
    tailoring = {
        { spellId = 26797, label = "Spellfire" },
        { spellId = 26801, label = "Shadoweave" },
        { spellId = 26798, label = "Mooncloth" },
    },
}

--- Specialization label for a profession key, using `knowsFn(spellId) -> bool`; nil when none.
--- Pure (no globals) so it is unit-testable; the live scan passes an IsSpellKnown wrapper.
function DS.ResolveSpecializationLabel(professionKey, knowsFn)
    local specs = professionKey and DS.PROFESSION_SPECIALIZATIONS[professionKey]
    if not specs or type(knowsFn) ~= "function" then return nil end
    for _, spec in ipairs(specs) do
        if knowsFn(spec.spellId) then return spec.label end
    end
    return nil
end

--- Persist each crafting profession's learned specialization label (current character only).
function DS:ScanProfessionSpecializations(char)
    if not char or not char.Professions then return end
    local SS = AltArmy and AltArmy.SearchSettings
    local resolveKey = SS and SS.ResolveProfessionKey
    local function knows(spellId)
        if not spellId or not _G.IsSpellKnown then return false end
        local ok, known = pcall(_G.IsSpellKnown, spellId)
        return ok and known and true or false
    end
    for profName, prof in pairs(char.Professions) do
        local key = resolveKey and resolveKey(profName) or nil
        prof.specialization = DS.ResolveSpecializationLabel(key, knows)
    end
end

--- Persist tailoring/alchemy specialization passives for cooldown option filters (current character).
function DS:ScanCooldownSpecializations(char)
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    local ids = CD and CD.COOLDOWN_SPEC_SPELL_IDS
    if not ids then return end
    char.cooldownSpecs = char.cooldownSpecs or {}
    local cs = char.cooldownSpecs
    local function knows(spellId)
        if not spellId then return false end
        if _G.IsSpellKnown then
            local ok, k = pcall(_G.IsSpellKnown, spellId)
            if ok and k then return true end
        end
        return false
    end
    cs.masterTransmutation = knows(ids.masterTransmutation)
    cs.spellfireTailor = knows(ids.spellfireTailor)
    cs.shadoweaveTailor = knows(ids.shadoweaveTailor)
    cs.moonclothTailor = knows(ids.moonclothTailor)
end

--- Lowercase names of professions the login scan can't see: WoW Forever's GetProfessions() only
--- reports fixed slots (two primaries, fishing, cooking, first aid), and Comprehension (mage-only)
--- isn't one. Only the recipe scan adds these, so pruning must leave them alone or their recipes
--- (and the Research cooldown row) vanish at every login until the window is reopened.
DS.PROFESSIONS_OUTSIDE_SKILL_SCAN = {
    comprehension = true,
}

--- Remove stored professions absent from the live skill-line scan.
--- Skips pruning until profession categories are present (skill data can load late at login).
local function PruneDroppedProfessions(char, currentNames, skillLinesReady)
    if not char or not char.Professions or not skillLinesReady or not currentNames then
        return false
    end
    local removed = false
    for profName in pairs(char.Professions) do
        if not currentNames[profName]
            and not (type(profName) == "string" and DS.PROFESSIONS_OUTSIDE_SKILL_SCAN[profName:lower()])
        then
            char.Professions[profName] = nil
            removed = true
        end
    end
    return removed
end
DS._PruneDroppedProfessionsForTest = PruneDroppedProfessions

--- True when either profession-presence API is available: the legacy skill-line-list pair
--- (GetNumSkillLines/GetSkillLineInfo) or the GetProfessions/GetProfessionInfo pair it falls back
--- to (stable since Patch 4.0.1; confirmed present on BC Anniversary/MoP Classic/mainline — see
--- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md). Clients missing both (unconfirmed whether WoW
--- Forever is one) can never populate char.Professions at all, so callers use this to avoid
--- telling the player to open a window that cannot possibly gather the data.
function DS.HasProfessionsListApi()
    return (GetNumSkillLines ~= nil and GetSkillLineInfo ~= nil)
        or (GetProfessions ~= nil and GetProfessionInfo ~= nil)
end

--- Applies one scanned skill-line row (name/rank/maxRank + primary/secondary) to char.Professions.
--- Shared by both the legacy (GetSkillLineInfo) and fallback (GetProfessionInfo) scan loops so the
--- presence/rank-change bookkeeping (currentNames, "did anything change") only exists once.
--- Returns the (possibly normalized) name and whether presence/rank changed.
local function CollectProfessionEntry(char, currentNames, skillName, rank, maxRank, isPrimary, isSecondary)
    if skillName == "Secourisme" and HasSpellInfoApi() then
        skillName = DS.CompatGetSpellInfo(SPELL_ID_FIRSTAID) or skillName
    end
    skillName = NormalizeProfessionName(skillName)
    currentNames[skillName] = true
    local prof = char.Professions[skillName]
    local newRank = rank or 0
    local newMaxRank = maxRank or 0
    local changed = false
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[skillName] = prof
        changed = true
    elseif (prof.rank or 0) ~= newRank or (prof.maxRank or 0) ~= newMaxRank then
        changed = true
    end
    prof.rank = newRank
    prof.maxRank = newMaxRank
    if isPrimary then prof.isPrimary = true end
    if isSecondary then prof.isSecondary = true end
    return skillName, changed
end

--- Legacy scan: enumerate every skill line via GetNumSkillLines/GetSkillLineInfo.
local function ScanProfessionLinksLegacy(char, currentNames)
    local presenceChanged = false
    local skillLinesReady = false
    for i = GetNumSkillLines(), 1, -1 do
        local _, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then
            ExpandSkillHeader(i)
        end
    end
    local category
    for i = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not skillName then break end
        if isHeader then
            category = skillName
            if category == "Professions" or category == "Secondary Skills" then
                skillLinesReady = true
            end
        else
            if category and skillName then
                local isPrimary = (category == "Professions")
                local isSecondary = (category == "Secondary Skills")
                if isPrimary or isSecondary then
                    local name, changed = CollectProfessionEntry(
                        char, currentNames, skillName, rank, maxRank, isPrimary, isSecondary)
                    if changed then presenceChanged = true end
                    if isPrimary then
                        if not char.Prof1 then char.Prof1 = name
                        else char.Prof2 = name end
                    end
                end
            end
        end
    end
    return presenceChanged, skillLinesReady
end

--- Applies one GetProfessions() slot index (nil = not learned) via GetProfessionInfo.
--- Returns (name, changed) — same order as CollectProfessionEntry — or (nil, false) when the
--- slot is empty/unresolvable.
local function ApplyProfessionSlot(char, currentNames, index, isPrimary, isSecondary)
    if not index then return nil, false end
    local name, _, rank, maxRank = GetProfessionInfo(index)
    if not name or name == "" then return nil, false end
    return CollectProfessionEntry(char, currentNames, name, rank, maxRank, isPrimary, isSecondary)
end

local SPELL_ID_ARCHAEOLOGY = 78670

--- Whether a GetProfessions() slot's name is Archaeology, the one profession with nothing to store here
--- (not in TBC or Forever content).
local function IsArchaeology(name)
    if type(name) ~= "string" or name == "" then return false end
    if HasSpellInfoApi() and DS.CompatGetSpellInfo(SPELL_ID_ARCHAEOLOGY) == name then return true end
    local label = _G.PROFESSIONS_ARCHAEOLOGY
    return name == "Archaeology" or (type(label) == "string" and name == label)
end

--- Fallback scan for clients missing GetNumSkillLines/GetSkillLineInfo (e.g. WoW Forever — see
--- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Seventh"). GetProfessions() returns spell-tab
--- indices (nil when not learned) for the primary/secondary profession slots; GetProfessionInfo
--- resolves each to name/rank/maxRank. Unlike the legacy loop this needs no window open first —
--- it's a direct query, not a UI-panel snapshot. The first two slots are the primaries; every other
--- slot is a secondary skill, told apart by name rather than position: WoW Forever reports First Aid
--- in the third slot, where clients with Archaeology have that (seen in game 2026-10-18: a character
--- with two primaries, First Aid and Cooking got slots 1, 2, 3 and 5), and the sixth stays empty.
--- Archaeology alone is skipped.
local function ScanProfessionLinksViaGetProfessions(char, currentNames)
    local slots = { GetProfessions() }
    local presenceChanged = false
    for slot = 1, 6 do
        local index = slots[slot]
        if type(index) == "number" and not IsArchaeology((GetProfessionInfo(index))) then
            local isPrimary = slot <= 2
            local name, changed = ApplyProfessionSlot(char, currentNames, index, isPrimary, not isPrimary)
            if changed then presenceChanged = true end
            if name and slot == 1 then char.Prof1 = name end
            if name and slot == 2 then char.Prof2 = name end
        end
    end
    return presenceChanged, true
end

function DS:ScanProfessionLinks()
    local char = GetCurrentCharTable()
    if not char then return end
    local hasLegacyApi = GetNumSkillLines ~= nil and GetSkillLineInfo ~= nil
    local hasFallbackApi = GetProfessions ~= nil and GetProfessionInfo ~= nil
    if not hasLegacyApi and not hasFallbackApi then return end

    char.Professions = char.Professions or {}
    char.Prof1 = nil
    char.Prof2 = nil
    local currentNames = {}
    local presenceChanged, skillLinesReady
    if hasLegacyApi then
        presenceChanged, skillLinesReady = ScanProfessionLinksLegacy(char, currentNames)
    else
        presenceChanged, skillLinesReady = ScanProfessionLinksViaGetProfessions(char, currentNames)
    end

    self:MarkForeignRecipeListsStale(char)
    if PruneDroppedProfessions(char, currentNames, skillLinesReady) then
        notifyRecipesChanged()
    elseif presenceChanged then
        -- Learn/rank changes affect presence even when the recipe cache is unchanged.
        scheduleGuildShareBroadcast()
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    self:ScanCooldownSpecializations(char)
    self:ScanProfessionSpecializations(char)
end

--- True when either recipe-scan API is available: the legacy trade-skill-window pair
--- (GetNumTradeSkills/GetTradeSkillLine) or the C_TradeSkillUI fallback it falls back to (see
--- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth"). Either way only an open profession window can
--- be scanned. C_TradeSkillUI.OpenTradeSkill needs a click, but on WoW Forever OwnRecipeRead.lua opens
--- the player's own professions in the background through a profession link; elsewhere the player has to.
function DS.HasTradeSkillRecipesApi()
    return (GetNumTradeSkills ~= nil and GetTradeSkillLine ~= nil)
        or (C_TradeSkillUI ~= nil and C_TradeSkillUI.GetAllRecipeIDs ~= nil
            and C_TradeSkillUI.GetBaseProfessionInfo ~= nil and C_TradeSkillUI.GetRecipeInfo ~= nil)
end

--- True when recipe scanning is happening via the C_TradeSkillUI fallback rather than the legacy
--- GetNumTradeSkills/GetTradeSkillLine pair. Some profession *content* differs by client family,
--- not just API shape — e.g. WoW Forever gave Skinning an actual recipe window that TBC's never
--- had (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Ninth") — so callers use this to adjust
--- profession-specific assumptions like "does this gathering skill have recipes at all", not just
--- which functions to call.
function DS.IsUsingTradeSkillUiFallback()
    return (GetNumTradeSkills == nil or GetTradeSkillLine == nil)
        and (C_TradeSkillUI ~= nil and C_TradeSkillUI.GetAllRecipeIDs ~= nil)
end

-- Canonical lowercase profession keys with no recipe list at all on the legacy TBC API (pure
-- gathering/secondary skills). WoW Forever gave Skinning, Mining, Herbalism, and Fishing real
-- recipes (Camp Chair, Smelt Copper, Incense Candle, Fish Bowl — see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Ninth"), so only Riding stays in the equivalent set
-- for the C_TradeSkillUI fallback. Single source of truth for "does this profession have a recipe
-- window" — SummaryData.lua's missing-data nag, GuildTabData.lua's crafting/gathering split, and
-- this file's recipe-stale / learned-recipe-share guards all read this (via
-- DS.ProfessionHasNoRecipeWindow), so a future correction only has to happen here.
DS.NO_RECIPE_PROFESSION_KEYS_LEGACY = {
    fishing = true,
    riding = true,
    herbalism = true,
    mining = true,
    skinning = true,
}
DS.NO_RECIPE_PROFESSION_KEYS_TRADESKILLUI_FALLBACK = {
    riding = true,
}

--- True when profNameOrKey (matched case-insensitively) has no recipe window to open on whichever
--- recipe-scan API is currently active.
function DS.ProfessionHasNoRecipeWindow(profNameOrKey)
    if type(profNameOrKey) ~= "string" or profNameOrKey == "" then return false end
    local key = profNameOrKey:lower()
    local set = (DS.IsUsingTradeSkillUiFallback and DS.IsUsingTradeSkillUiFallback())
        and DS.NO_RECIPE_PROFESSION_KEYS_TRADESKILLUI_FALLBACK
        or DS.NO_RECIPE_PROFESSION_KEYS_LEGACY
    return set[key] == true
end

--- Legacy scan: enumerate the open trade skill window via GetNumTradeSkills/GetTradeSkillInfo.
--- Returns the (possibly normalized) profession name, or nil to abort without marking anything
--- scanned (matches the original behavior when the window hasn't finished populating yet).
local function ScanRecipesLegacy(char)
    local tradeskillName, currentLevel, maxLevel = GetTradeSkillLine()
    if not tradeskillName or tradeskillName == "" or tradeskillName == "UNKNOWN" then return nil end
    tradeskillName = NormalizeProfessionName(tradeskillName)
    local prof = char.Professions[tradeskillName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[tradeskillName] = prof
    end
    ApplyProfessionRank(prof, currentLevel, maxLevel)
    local numTradeSkills = GetNumTradeSkills and GetNumTradeSkills()
    if not numTradeSkills or numTradeSkills == 0 then return nil end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    for i = 1, numTradeSkills do
        local skillName, recipeSkillType = GetTradeSkillInfo(i)
        -- Include rows whose difficulty string is unknown to our map (otherwise Spellcloth/etc. can be skipped).
        if recipeSkillType ~= "header" and recipeSkillType ~= "subheader" then
            local color = SkillTypeToColor[recipeSkillType] or 0
            -- recipeID must come from the recipe link (spell/enchant/recipe item), not the crafted result
            local recipeID
            if GetTradeSkillRecipeLink then
                local link = GetTradeSkillRecipeLink(i)
                if link then
                    recipeID = tonumber(link:match("enchant:(%d+)"))
                        or tonumber(link:match("spell:(%d+)"))
                        or tonumber(link:match("item:(%d+)"))
                end
            end
            local resultItemID
            if GetTradeSkillItemLink then
                local itemLink = GetTradeSkillItemLink(i)
                if itemLink then
                    resultItemID = tonumber(itemLink:match("item:(%d+)"))
                end
            end
            if recipeID then
                -- name comes straight from the open tradeskill window: recipeID isn't reliably a
                -- spell ID (it can be an item ID for non-enchant recipes), so search's later
                -- GetSpellInfo/GetItemInfo(recipeID) guess can miss or misresolve it.
                local row = {
                    color = color, resultItemID = resultItemID, primaryRecipeID = recipeID, name = skillName,
                }
                prof.Recipes[recipeID] = row
                for _, rid in ipairs(CollectRecipeIdsFromTradeSkillIndex(i)) do
                    if rid and rid ~= recipeID then
                        prof.Recipes[rid] = row
                    end
                end
            end
            -- Capture reagents even when recipe link parse fails (ids may come from item links/GetItemSpell).
            DS:CaptureTradeSkillReagentsForIndex(i)
        end
    end
    return tradeskillName
end

-- Enum.TradeskillRelativeDifficulty -> our SkillTypeToColor scale (optimal/medium/easy/trivial).
-- Confirmed against Warcraft Wiki's C_TradeSkillUI.GetRecipeInfo docs; not yet verified against a
-- live Forever snapshot (same epistemic caveat as the rest of docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md).
local RelativeDifficultyToColor = { [0] = 1, [1] = 2, [2] = 3, [3] = 4 }

--- Fallback scan for clients missing GetNumTradeSkills/GetTradeSkillLine (e.g. WoW Forever — see
--- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth"). Only learned recipes are stored, matching
--- the legacy scan's semantics (the trade skill window only ever lists known recipes) even though
--- C_TradeSkillUI.GetAllRecipeIDs() itself returns the whole class-wide recipe catalog including
--- ones this character hasn't learned. resultItemID is filled best-effort via
--- C_TradeSkillUI.GetRecipeOutputItemData when available; reagents are not scanned at all here —
--- that needs the separate, more involved GetRecipeSchematic API and remains deferred.
local function tradeSkillFlag(fnName)
    local fn = C_TradeSkillUI[fnName]
    if not fn then return false end
    local ok, a, b = pcall(fn)
    if not ok then return false end
    return a == true, b
end

--- Whether a profession window's learned recipe ids belong to the profession it names (by the bundled recipe
--- data, RecipeInfo.RecipesFitProfession); true when nothing can tell.
function DS.RecipesFitProfessionWindow(recipeIDs, professionName)
    local RI = AltArmy and AltArmy.RecipeInfo
    local SS = AltArmy and AltArmy.SearchSettings
    if not (RI and RI.RecipesFitProfession and SS and SS.ResolveProfessionKey) then return true end
    local ok, key = pcall(SS.ResolveProfessionKey, professionName)
    if not ok or not key then return true end
    return RI.RecipesFitProfession(recipeIDs, key) == true
end

--- True when the open window is not this character's own profession: a guild or NPC crafting window,
--- or another player's linked profession (a chat link the player clicked, OwnRecipeRead reading a
--- guildmate, or another addon reading players in the background). The player's own link, which
--- OwnRecipeRead opens, still passes: it comes back unlinked, or linked under the player's own name. A
--- linked window naming nobody is trusted only while OwnRecipeRead is waiting for the player's own; while
--- it waits for a guildmate's, no window is trusted, whatever the client says about it.
local function IsSomeoneElsesTradeSkill()
    if tradeSkillFlag("IsTradeSkillGuild") or tradeSkillFlag("IsNPCCrafting") then
        return true
    end
    local R = AltArmy.OwnRecipeRead
    if R and R.IsReadingGuild and R.IsReadingGuild() then
        return true
    end
    local linked, linkedName = tradeSkillFlag("IsTradeSkillLinked")
    if not linked then
        return false
    end
    if type(linkedName) ~= "string" or linkedName == "" then
        return not (R and R.IsReading and R.IsReading())
    end
    -- The link names the player in full ("First Surname" on WoW Forever, whose UnitName gives the two
    -- apart); older clients' links carry UnitName's one name.
    local short = (linkedName:match("^([^%-]+)") or linkedName):lower()
    local full = DS.GetCurrentPlayerName and DS:GetCurrentPlayerName()
    if type(full) == "string" and full ~= "" and short == full:lower() then
        return false
    end
    local me = UnitName and UnitName("player")
    return type(me) ~= "string" or short ~= me:lower()
end

local function ScanRecipesViaTradeSkillUI(char)
    if IsSomeoneElsesTradeSkill() then return nil end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if not info or not info.professionName or info.professionName == "" then return nil end
    local tradeskillName = NormalizeProfessionName(info.professionName)
    local prof = char.Professions[tradeskillName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[tradeskillName] = prof
    end
    ApplyProfessionRank(prof, info.skillLevel, info.maxSkillLevel)

    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then return nil end
    local learned, learnedIDs = {}, {}
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            learned[#learned + 1] = { recipeID, recipeInfo }
            learnedIDs[#learnedIDs + 1] = recipeID
        end
    end
    -- The window may describe this profession while still listing the one open before (another profession's
    -- recipes, as OwnRecipeRead's reads open windows back to back); its own list comes with a later event.
    if not DS.RecipesFitProfessionWindow(learnedIDs, tradeskillName) then return nil end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end

    local hasOutputApi = C_TradeSkillUI.GetRecipeOutputItemData ~= nil
    -- Cooldowns: the legacy ScanTradeSkillCooldownExpiry can't run on this API, so read tracked
    -- recipes' cooldowns here (remaining seconds; nil when ready — same shape as GetTradeSkillCooldown).
    local getRecipeCooldown = C_TradeSkillUI.GetRecipeCooldown
    local CD = AltArmy and AltArmy.CooldownData
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    for _, pair in ipairs(learned) do
        local recipeID, recipeInfo = pair[1], pair[2]
        local color = RelativeDifficultyToColor[recipeInfo.relativeDifficulty] or 1
        local resultItemID
        if hasOutputApi then
            local ok, outputInfo = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
            if ok and outputInfo then
                resultItemID = outputInfo.itemID
            end
        end
        -- name comes straight from GetRecipeInfo: recipeID here isn't reliably a spell ID,
        -- so search's later GetSpellInfo/GetItemInfo(recipeID) guess can miss or misresolve it.
        prof.Recipes[recipeID] = {
            color = color, resultItemID = resultItemID, primaryRecipeID = recipeID, name = recipeInfo.name,
        }
        if getRecipeCooldown and CD and CD.IsTrackedSpellId and CD.IsTrackedSpellId(recipeID) then
            local ok, remaining, isDay = pcall(getRecipeCooldown, recipeID)
            if ok then
                PersistCooldownExpiry(char, recipeID, remaining, isDay, gt, wall, "TradeSkillUI", "tradeskill")
                LogCooldownScanDebug(string.format(
                    "TradeSkillUI recipe=%d cd=%s -> expUnix=%s",
                    recipeID,
                    tostring(remaining),
                    tostring(char.ProfCooldownExpiry[recipeID] and char.ProfCooldownExpiry[recipeID].expiresAtUnix)
                ))
            end
        end
    end
    return tradeskillName
end

function DS:ScanRecipes()
    local char = GetCurrentCharTable()
    if not char then return end
    char.Professions = char.Professions or {}

    local tradeskillName
    if GetNumTradeSkills and GetTradeSkillLine then
        tradeskillName = ScanRecipesLegacy(char)
    elseif C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetBaseProfessionInfo
        and C_TradeSkillUI.GetRecipeInfo then
        tradeskillName = ScanRecipesViaTradeSkillUI(char)
    end
    if not tradeskillName then return end

    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    self:ScanCooldownSpecializations(char)
    self:ScanProfessionSpecializations(char)
    self:ClearProfessionRecipesStale(tradeskillName, char)
    notifyRecipesChanged()
    local R = AltArmy.OwnRecipeRead
    if R and R.OnRecipesScanned then
        R.OnRecipesScanned(tradeskillName)
    end
end

--- Scan recipes from the Craft window (Enchanting in TBC Classic uses Craft API, not Trade Skill).
--- Only runs when GetCraftSkillLine etc. exist (TBC Classic); no-op on clients that use Trade Skill only.
function DS:ScanCraftRecipes()
    if not GetCraftSkillLine or not GetNumCrafts or not GetCraftInfo or not GetCraftRecipeLink then
        return
    end
    local char = GetCurrentCharTable()
    if not char then return end
    -- Classic client requires a positive index; omitting it errors: Usage: GetCraftSkillLine(index)
    local craftName = GetCraftSkillLine(1)
    if not craftName or craftName == "" then return end
    craftName = NormalizeProfessionName(craftName)
    local numCrafts = GetNumCrafts()
    if not numCrafts or numCrafts == 0 then return end
    char.Professions = char.Professions or {}
    local prof = char.Professions[craftName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[craftName] = prof
    end
    if GetCraftDisplaySkillLine then
        local _, rank, maxRank = GetCraftDisplaySkillLine()
        ApplyProfessionRank(prof, rank, maxRank)
    end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    local craftTypeToColor = { optimal = 1, medium = 2, easy = 3, trivial = 4 }
    for i = 1, numCrafts do
        local _, _, craftType = GetCraftInfo(i)
        if craftType and craftType ~= "header" then
            local color = craftTypeToColor[craftType] or 1
            local link = GetCraftRecipeLink(i)
            if link then
                local recipeID = tonumber(link:match("enchant:(%d+)"))
                if recipeID then
                    prof.Recipes[recipeID] = { color = color, resultItemID = nil }
                    self:CaptureCraftReagentsForIndex(i, recipeID)
                end
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    if self.ScanCraftCooldownExpiry then
        self:ScanCraftCooldownExpiry()
    end
    self:ClearProfessionRecipesStale(craftName, char)
    notifyRecipesChanged()
end

local isRecipeScanInProgress = false

function DS:RunDeferredRecipeScan()
    if isRecipeScanInProgress then
        return
    end
    isRecipeScanInProgress = true
    local filtersSnapshotted = false
    local ok, err = pcall(function()
        filtersSnapshotted = SaveTradeSkillFiltersForScan()
        SaveTradeSkillHeadersForScan()
        self:ScanRecipes()
        if self.ScanTradeSkillCooldownExpiry then
            self:ScanTradeSkillCooldownExpiry()
        end
    end)
    pcall(RestoreTradeSkillHeadersAfterScan)
    if filtersSnapshotted then
        pcall(RestoreTradeSkillFiltersAfterScan)
    end
    isRecipeScanInProgress = false
    -- ScanRecipes notifies when it stored something; a window it passed over (another player's, read by
    -- OwnRecipeRead or opened from a chat link) changes nothing and must not clear the search caches or
    -- schedule a guild broadcast.
    if not ok and err then
        error(err)
    end
end

--- Second pass: refresh RecipeReagents only (no recipe wipe). Helps when reagent APIs lag right after open.
function DS:CaptureAllTradeSkillReagentsOnly()
    if not GetNumTradeSkills or not GetTradeSkillLine then return end
    local name = GetTradeSkillLine()
    if not name or name == "" or name == "UNKNOWN" then
        return
    end
    local n = GetNumTradeSkills()
    if not n or n == 0 then return end
    local prevSel = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
    pcall(function()
        ExpandAllTradeSkillHeaders()
        for i = 1, n do
            local _, skillType = GetTradeSkillInfo(i)
            if skillType ~= "header" and skillType ~= "subheader" then
                pcall(function()
                    self:CaptureTradeSkillReagentsForIndex(i)
                end)
            end
        end
    end)
    if prevSel and SelectTradeSkill then
        pcall(function()
            SelectTradeSkill(prevSel)
        end)
    end
end

--- Enchanting craft UI: capture reagents for every row only (RecipeReagents cache).
function DS:CaptureAllCraftReagentsOnly()
    if not GetNumCrafts or not GetCraftRecipeLink then return end
    local num = GetNumCrafts()
    if not num or num == 0 then return end
    for i = 1, num do
        local _, _, craftType = GetCraftInfo(i)
        if craftType and craftType ~= "header" then
            local link = GetCraftRecipeLink(i)
            local recipeID = link and tonumber(link:match("enchant:(%d+)"))
            if recipeID then
                pcall(function()
                    self:CaptureCraftReagentsForIndex(i, recipeID)
                end)
            end
        end
    end
end

function DS:GetProfessions(char)
    return (char and char.Professions) or {}
end

function DS:GetProfession(char, name)
    if not char or not char.Professions or not name then return nil end
    return char.Professions[name]
end

function DS:GetProfession1(char)
    if not char then return 0, 0, nil end
    local name = char.Prof1
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetProfession2(char)
    if not char then return 0, 0, nil end
    local name = char.Prof2
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetCookingRank(char)
    if not char or not HasSpellInfoApi() then return 0, 0 end
    local name = DS.CompatGetSpellInfo(SPELL_ID_COOKING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFishingRank(char)
    if not char or not HasSpellInfoApi() then return 0, 0 end
    local name = DS.CompatGetSpellInfo(SPELL_ID_FISHING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFirstAidRank(char)
    if not char or not HasSpellInfoApi() then return 0, 0 end
    local name = DS.CompatGetSpellInfo(SPELL_ID_FIRSTAID)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetNumRecipes(char, profName)
    if not char or not char.Professions or not profName then return 0 end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return 0 end
    local n = 0
    for _ in pairs(prof.Recipes) do n = n + 1 end
    return n
end

function DS:IsRecipeKnown(char, profName, spellID)
    if not char or not char.Professions or not profName or not spellID then return false end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return false end
    return prof.Recipes[spellID] ~= nil
end

--- Whether any profession on the character knows this recipe spell id.
function DS:IsRecipeKnownAnyProfession(char, spellID)
    if not char or not char.Professions or not spellID then return false end
    for _, prof in pairs(char.Professions) do
        if prof and prof.Recipes and prof.Recipes[spellID] ~= nil then
            return true
        end
    end
    return false
end

local function isTradeSkillUiOpen()
    if not GetTradeSkillLine then
        return false
    end
    local name = GetTradeSkillLine()
    return name ~= nil and name ~= "" and name ~= "UNKNOWN"
end

local function isCraftUiOpen()
    if not GetCraftSkillLine then
        return false
    end
    local name = GetCraftSkillLine(1)
    return name ~= nil and name ~= ""
end

--- Capture %s from a WoW global format string (e.g. ERR_LEARN_SPELL_S).
local function captureGlobalFormat(fmt, msg)
    if type(fmt) ~= "string" or type(msg) ~= "string" then
        return nil
    end
    local prefix, suffix = fmt:match("^(.*)%%s(.*)$")
    if not prefix then
        return nil
    end
    local function esc(s)
        return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
    end
    return msg:match("^" .. esc(prefix) .. "(.+)" .. esc(suffix) .. "$")
end

local function stripWowFormatting(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h%[(.-)%]|h", "%1")
    text = text:gsub("|T.-|t", "")
    return text
end

--- Enchant formulas use ERR_LEARN_SPELL_S ("You have learned a new spell: …"), not the recipe string.
local function isEnchantFormulaLearnName(name)
    name = stripWowFormatting(name)
    if name == "" then
        return false
    end
    -- "Enchant Cloak - Greater Shadow Resistance", "Enchant Weapon - Mongoose", etc.
    if name:find("^Enchant ") then
        return true
    end
    return false
end

--- Extract the learned recipe/formula name from a profession learn system chat line.
--- TBC Classic often does not fire NEW_RECIPE_LEARNED; chat is the reliable signal.
--- Patch 12.0+ clients (Forever included) can hand chat handlers a Secret Value
--- string whose *content* can't be inspected at all — even `== ""` throws
--- ("attempt to compare ... a secret string value"), not just pattern matching.
--- `canaccessvalue()` (existence-checked, safe to call on tainted execution paths
--- per Blizzard's own API, and the convention Thaoky's DataStore addons use for
--- this exact case) short-circuits the common case; `pcall` around the rest is the
--- fallback safety net for anything `canaccessvalue` doesn't catch, e.g. an older
--- client without it.
local function parseProfessionRecipeLearnName(msg)
    if type(msg) ~= "string" or msg == "" then
        return nil
    end
    local recipeName = captureGlobalFormat(_G.ERR_LEARN_RECIPE_S, msg)
    if recipeName then
        return stripWowFormatting(recipeName)
    end
    local spellName = captureGlobalFormat(_G.ERR_LEARN_SPELL_S, msg)
    if spellName and isEnchantFormulaLearnName(spellName) then
        return stripWowFormatting(spellName)
    end
    -- English fallbacks for unit tests / missing globals
    recipeName = msg:match("^You have learned how to create a new item: (.+)%.$")
    if recipeName then
        return stripWowFormatting(recipeName)
    end
    spellName = msg:match("^You have learned a new spell: (.+)%.$")
    if spellName and isEnchantFormulaLearnName(spellName) then
        return stripWowFormatting(spellName)
    end
    return nil
end

function DS:GetProfessionRecipeLearnName(msg)
    if _G.canaccessvalue and not _G.canaccessvalue(msg) then
        return nil
    end
    local ok, result = pcall(parseProfessionRecipeLearnName, msg)
    if not ok then
        return nil
    end
    return result
end

--- True when a system chat line indicates a profession recipe/formula was learned.
function DS:IsProfessionRecipeLearnSystemMessage(msg)
    return self:GetProfessionRecipeLearnName(msg) ~= nil
end

local function markOneProfessionRecipesStale(needing, char, professionName)
    if type(professionName) ~= "string" or professionName == "" then
        return false
    end
    if DS.ProfessionHasNoRecipeWindow(professionName) then
        return false
    end
    local prof = char.Professions[professionName]
    local rank = (prof and prof.rank) or 0
    if rank <= 0 then
        return false
    end
    needing[professionName] = true
    return true
end

local function markAllCraftableProfessionRecipesStale(needing, char)
    for profName, prof in pairs(char.Professions) do
        if type(profName) == "string" and not DS.ProfessionHasNoRecipeWindow(profName) then
            local rank = (prof and prof.rank) or 0
            if rank > 0 then
                needing[profName] = true
            end
        end
    end
end

--- Mark craftable professions as needing a recipe-window rescan (Summary ! warning).
--- When professionName is known (bundled recipe data), only that profession is marked.
--- Otherwise all craftable professions with rank > 0 are marked.
function DS:MarkProfessionRecipesStale(char, professionName)
    char = char or GetCurrentCharTable()
    if not char or type(char.Professions) ~= "table" then
        return
    end
    local needing = char.professionsNeedingRecipeScan
    if type(needing) ~= "table" then
        needing = {}
        char.professionsNeedingRecipeScan = needing
    end
    if professionName and markOneProfessionRecipesStale(needing, char, professionName) then
        return
    end
    markAllCraftableProfessionRecipesStale(needing, char)
end

--- Forget recipe lists stored for the wrong profession (a window scanned before the client refreshed its list
--- from the one open before: another profession's recipes under this one's name) and mark those professions
--- stale, so the window is read again. Returns how many were cleared.
function DS:MarkForeignRecipeListsStale(char)
    char = char or GetCurrentCharTable()
    if not char or type(char.Professions) ~= "table" then return 0 end
    local cleared = 0
    for profName, prof in pairs(char.Professions) do
        if type(prof) == "table" and type(prof.Recipes) == "table" and next(prof.Recipes) ~= nil then
            local ids = {}
            for id in pairs(prof.Recipes) do ids[#ids + 1] = id end
            if not DS.RecipesFitProfessionWindow(ids, profName) then
                prof.Recipes = {}
                self:MarkProfessionRecipesStale(char, profName)
                cleared = cleared + 1
            end
        end
    end
    if cleared > 0 then notifyRecipesChanged() end
    return cleared
end

--- Clear the Summary rescan warning for one profession after a successful recipe scan.
function DS:ClearProfessionRecipesStale(profName, char)
    if not profName then
        return
    end
    char = char or GetCurrentCharTable()
    if not char or type(char.professionsNeedingRecipeScan) ~= "table" then
        return
    end
    char.professionsNeedingRecipeScan[profName] = nil
    if not next(char.professionsNeedingRecipeScan) then
        char.professionsNeedingRecipeScan = nil
    end
end

--- Insert a newly learned recipe id so guild share can advertise it without a profession UI scan.
--- color: the scan's difficulty code (1 orange .. 4 gray), 0 when unknown.
--- Returns true when a new primary recipe entry was stored (and a share broadcast was scheduled).
function DS:AddLearnedRecipeForShare(professionName, recipeID, resultItemID, char, color)
    recipeID = tonumber(recipeID)
    if type(professionName) ~= "string" or professionName == "" or not recipeID then
        return false
    end
    char = char or GetCurrentCharTable()
    if not char or type(char.Professions) ~= "table" then
        return false
    end
    local prof = char.Professions[professionName]
    if type(prof) ~= "table" or (prof.rank or 0) <= 0 then
        return false
    end
    if DS.ProfessionHasNoRecipeWindow(professionName) then
        return false
    end
    prof.Recipes = prof.Recipes or {}
    if prof.Recipes[recipeID] ~= nil then
        return false
    end
    prof.Recipes[recipeID] = {
        color = tonumber(color) or 0,
        resultItemID = tonumber(resultItemID),
        primaryRecipeID = recipeID,
    }
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
    notifyRecipesChanged()
    return true
end

-- RecipeInfo difficulty -> the color code a recipe-window scan stores (SkillTypeToColor).
local DifficultyToColor = { orange = 1, yellow = 2, green = 3, gray = 4 }

--- Have OwnRecipeRead (WoW Forever) read a profession just marked stale, which stores its real recipe list
--- and clears the mark; every stale profession when the name is unknown.
local function readOwnRecipesSoon(professionName)
    local R = AltArmy.OwnRecipeRead
    if R and R.OnRecipeLearned then
        R.OnRecipeLearned(professionName)
    end
end

--- Recipe learned (event or system chat): scan if UI open; otherwise store the recipe from the bundled
--- recipe data (Data/Recipes) so Search and guild share have it without reopening the window. Only when
--- the recipe can't be identified or stored is a profession marked stale (Summary ! warning). On WoW
--- Forever a stale profession is then read in the background (OwnRecipeRead).
function DS:OnRecipeLearnDetected(recipeID, learnedName)
    local char = GetCurrentCharTable()
    if not char then
        return
    end

    if isTradeSkillUiOpen() then
        if self.RunDeferredRecipeScan then
            self:RunDeferredRecipeScan()
        end
        return
    end
    if isCraftUiOpen() then
        if self.ScanCraftRecipes then
            self:ScanCraftRecipes()
        end
        return
    end

    local RI = AltArmy and AltArmy.RecipeInfo
    local info = RI and RI.FindRecipeLearnInfo and RI.FindRecipeLearnInfo(recipeID, learnedName, char.Professions)
    if not info then
        self:MarkProfessionRecipesStale(char, nil)
        readOwnRecipesSoon(nil)
        return
    end
    local prof = type(char.Professions) == "table" and char.Professions[info.professionName]
    if type(prof) == "table" and type(prof.Recipes) == "table" and prof.Recipes[info.recipeID] ~= nil then
        return
    end
    local difficulty = prof and RI.GetDifficulty(RI.GetRecipe(info.recipeID), prof.rank)
    if self:AddLearnedRecipeForShare(info.professionName, info.recipeID, info.resultItemID, char,
            DifficultyToColor[difficulty]) then
        return
    end
    self:MarkProfessionRecipesStale(char, info.professionName)
    readOwnRecipesSoon(info.professionName)
end

--- Handle NEW_RECIPE_LEARNED when the client fires it (optional recipeID).
function DS:OnNewRecipeLearned(recipeID)
    self:OnRecipeLearnDetected(recipeID, nil)
end

--- Handle CHAT_MSG_SYSTEM learn lines (primary signal on TBC Classic).
function DS:OnProfessionLearnSystemMessage(msg)
    local learnedName = self:GetProfessionRecipeLearnName(msg)
    if not learnedName then
        return false
    end
    self:OnRecipeLearnDetected(nil, learnedName)
    return true
end

local function RecipeIdFromTradeLink(link)
    if not link then return nil end
    return tonumber(link:match("enchant:(%d+)"))
        or tonumber(link:match("spell:(%d+)"))
        or tonumber(link:match("item:(%d+)"))
end

local function RecipeIdFromEnchantLink(link)
    if not link then return nil end
    return tonumber(link:match("enchant:(%d+)"))
end

local function ItemIdFromItemLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- Account-wide recipe reagent lists { { itemID, qty }, ... } keyed by spell/enchant/item id (Cooldowns tab mats).
function DS:SaveRecipeReagentsMulti(spellIds, reagentList)
    if not spellIds or #spellIds == 0 or not reagentList or #reagentList == 0 then return end
    local db = self.accountData
    if not db then return end
    db.RecipeReagents = db.RecipeReagents or {}
    local copy = {}
    for i, pair in ipairs(reagentList) do
        copy[i] = { pair[1], pair[2] or 1 }
    end
    for _, spellId in ipairs(spellIds) do
        if spellId and spellId > 0 then
            db.RecipeReagents[spellId] = copy
        end
    end
end

function DS:SaveRecipeReagents(spellId, reagentList)
    if not spellId then return end
    self:SaveRecipeReagentsMulti({ spellId }, reagentList)
end

function DS:CaptureTradeSkillReagentsForIndex(tradeSkillIndex)
    if not GetTradeSkillNumReagents or not GetTradeSkillReagentItemLink then return end
    -- Classic clients often require the row to be selected before reagent APIs return data.
    if SelectTradeSkill then
        SelectTradeSkill(tradeSkillIndex)
    end
    local declared = GetTradeSkillNumReagents(tradeSkillIndex) or 0
    local list = {}
    local function pushReagent(r)
        local link = GetTradeSkillReagentItemLink(tradeSkillIndex, r)
        if not link or link == "" then return false end
        local itemId = ItemIdFromItemLink(link)
        local need = 1
        if GetTradeSkillReagentInfo then
            local _, _, cnt = GetTradeSkillReagentInfo(tradeSkillIndex, r)
            if type(cnt) == "number" and cnt > 0 then
                need = cnt
            end
        end
        if itemId then
            list[#list + 1] = { itemId, need }
        end
        return true
    end
    if declared > 0 then
        for r = 1, declared do
            pushReagent(r)
        end
    else
        for r = 1, 16 do
            local link = GetTradeSkillReagentItemLink(tradeSkillIndex, r)
            if not link or link == "" then break end
            pushReagent(r)
        end
    end
    if #list == 0 then
        return
    end
    local ids = CollectRecipeIdsFromTradeSkillIndex(tradeSkillIndex)
    if #ids == 0 and GetTradeSkillRecipeLink then
        local link = GetTradeSkillRecipeLink(tradeSkillIndex)
        local fallback = link and RecipeIdFromTradeLink(link)
        if fallback then
            ids = { fallback }
        end
    end
    if #ids > 0 then
        self:SaveRecipeReagentsMulti(ids, list)
    end
end

function DS:CaptureCraftReagentsForIndex(craftIndex, recipeSpellId)
    if not recipeSpellId or not GetCraftNumReagents then return end
    local n = GetCraftNumReagents(craftIndex)
    if not n or n < 1 then return end
    local list = {}
    for r = 1, n do
        local link = GetCraftReagentItemLink and GetCraftReagentItemLink(craftIndex, r)
        local itemId = ItemIdFromItemLink(link)
        local need = 1
        if GetCraftReagentInfo then
            local _, _, cnt = GetCraftReagentInfo(craftIndex, r)
            if type(cnt) == "number" and cnt > 0 then
                need = cnt
            end
        end
        if itemId then
            list[#list + 1] = { itemId, need }
        end
    end
    if #list > 0 then
        self:SaveRecipeReagents(recipeSpellId, list)
    end
end

--- Alchemy transmutes share one cooldown; the client may only expose it on one spell id.
--- Scan all transmute spells and persist the longest remaining cooldown.
function DS:TryScanTransmuteCooldownsFromSpellApi(preferredSpellId)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.GetTransmuteSpellIds or not CD.IsTrackedSpellId then return end
    if not HasSpellCooldownApi() then return end
    local transmuteIds = CD.GetTransmuteSpellIds()

    local char = GetCurrentCharTable()
    if not char then return end

    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    local bestRemaining = 0
    local bestSpellId = preferredSpellId

    local function consider(spellId)
        if not spellId or not CD.IsTrackedSpellId(spellId) then return end
        local a, b = GetSpellCooldownCompat(spellId)
        local rem = CooldownRemainingSecondsFromSpellApi(a, b, gt, wall)
        if rem > bestRemaining then
            bestRemaining = rem
            bestSpellId = spellId
        end
    end

    consider(preferredSpellId)
    for _, sid in ipairs(transmuteIds) do
        consider(sid)
    end

    if bestSpellId then
        local a, b = GetSpellCooldownCompat(bestSpellId)
        PersistCooldownExpiry(char, bestSpellId, a, b, gt, wall, "TransmuteSpellApi", "spell")
        local bestExp = char.ProfCooldownExpiry[bestSpellId]
            and char.ProfCooldownExpiry[bestSpellId].expiresAtUnix
        if bestExp and bestExp > wall then
            char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}
            for _, sid in ipairs(transmuteIds) do
                if CD.IsTrackedSpellId(sid) and select(1, CD.FindRecipeProfession(char, sid)) then
                    char.ProfCooldownExpiry[sid] = { expiresAtUnix = bestExp }
                end
            end
        end
        LogCooldownScanDebug(string.format(
            "TransmuteSpellApi preferred=%s best=%s rem=%.1fs expUnix=%s",
            tostring(preferredSpellId),
            tostring(bestSpellId),
            bestRemaining,
            tostring(bestExp)
        ))
    end
end

--- Void / Prismatic spheres share one cooldown; scan all sphere spells and mirror expiry.
function DS:TryScanSphereCooldownsFromSpellApi(preferredSpellId)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.SPHERE_SPELL_IDS or not CD.IsTrackedSpellId then return end
    if not HasSpellCooldownApi() then return end

    local char = GetCurrentCharTable()
    if not char then return end

    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    local bestRemaining = 0
    local bestSpellId = preferredSpellId

    local function consider(spellId)
        if not spellId or not CD.IsTrackedSpellId(spellId) then return end
        local a, b = GetSpellCooldownCompat(spellId)
        local rem = CooldownRemainingSecondsFromSpellApi(a, b, gt, wall)
        if rem > bestRemaining then
            bestRemaining = rem
            bestSpellId = spellId
        end
    end

    consider(preferredSpellId)
    for _, sid in ipairs(CD.SPHERE_SPELL_IDS) do
        consider(sid)
    end

    if bestSpellId then
        local a, b = GetSpellCooldownCompat(bestSpellId)
        PersistCooldownExpiry(char, bestSpellId, a, b, gt, wall, "SphereSpellApi", "spell")
        local bestExp = char.ProfCooldownExpiry[bestSpellId]
            and char.ProfCooldownExpiry[bestSpellId].expiresAtUnix
        if bestExp and bestExp > wall then
            char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}
            for _, sid in ipairs(CD.SPHERE_SPELL_IDS) do
                if CD.IsTrackedSpellId(sid) and select(1, CD.FindRecipeProfession(char, sid)) then
                    char.ProfCooldownExpiry[sid] = { expiresAtUnix = bestExp }
                end
            end
        end
        LogCooldownScanDebug(string.format(
            "SphereSpellApi preferred=%s best=%s rem=%.1fs expUnix=%s",
            tostring(preferredSpellId),
            tostring(bestSpellId),
            bestRemaining,
            tostring(bestExp)
        ))
    end
end

--- Persist expiry for one tracked spell by reading GetSpellCooldown(spellId).
--- Intended to be called right after a successful cast / use.
function DS:TryScanTrackedCooldownFromSpellApi(spellId)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    if not spellId or not CD.IsTrackedSpellId(spellId) then return end
    if not HasSpellCooldownApi() then return end

    local char = GetCurrentCharTable()
    if not char then return end

    local a, b = GetSpellCooldownCompat(spellId)
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    PersistCooldownExpiry(char, spellId, a, b, gt, wall, "SpellApi", "spell")
    LogCooldownScanDebug(string.format(
        "SpellApi spell=%d a=%s b=%s rem=%.1fs -> expUnix=%s",
        spellId,
        tostring(a),
        tostring(b),
        CooldownRemainingSecondsFromSpellApi(a, b, gt, wall),
        tostring(char.ProfCooldownExpiry[spellId] and char.ProfCooldownExpiry[spellId].expiresAtUnix)
    ))
end

--- An item's use cooldown: C_Container.GetItemCooldown, else the global GetItemCooldown; both give
--- (start, duration, enable) like GetSpellCooldown.
local function GetItemCooldownCompat(itemId)
    local cc = rawget(_G, "C_Container")
    if type(cc) == "table" and type(cc.GetItemCooldown) == "function" then
        return cc.GetItemCooldown(itemId)
    end
    local fn = rawget(_G, "GetItemCooldown")
    if type(fn) == "function" then
        return fn(itemId)
    end
    return nil, nil
end

--- Persist a tracked item's use cooldown (Salt Shaker), saved under its use spell's id like a recipe's.
--- Only while the current character holds the item (its last bags or bank scan).
function DS:TryScanTrackedItemCooldown(itemId, spellId)
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId or not CD.CharacterHoldsItem then return end
    if not itemId or not spellId or not CD.IsTrackedSpellId(spellId) then return end

    local char = GetCurrentCharTable()
    if not char or not CD.CharacterHoldsItem(char, itemId) then return end

    local a, b = GetItemCooldownCompat(itemId)
    if a == nil then return end
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    PersistCooldownExpiry(char, spellId, a, b, gt, wall, "ItemApi", "spell")
    LogCooldownScanDebug(string.format(
        "ItemApi item=%d spell=%d a=%s b=%s expUnix=%s",
        itemId,
        spellId,
        tostring(a),
        tostring(b),
        tostring(char.ProfCooldownExpiry and char.ProfCooldownExpiry[spellId]
            and char.ProfCooldownExpiry[spellId].expiresAtUnix)
    ))
end

--- Every tracked item cooldown this client has (login, so it shows without using the item first).
function DS:TryScanTrackedItemCooldowns()
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.TrackedItemCooldowns then return end
    for _, entry in ipairs(CD.TrackedItemCooldowns()) do
        self:TryScanTrackedItemCooldown(entry.itemId, entry.spellId)
    end
end

--- Scan action bars for tracked spell/item cooldowns (current character only).
--- Useful when the user never opens the profession window, but keeps the cooldown on a bar.
function DS:TryScanTrackedCooldownsFromActionBars()
    local GetActionInfo = _G.GetActionInfo
    local GetActionCooldown = _G.GetActionCooldown
    if not GetActionInfo or not GetActionCooldown then return end
    local GetMacroInfo = _G.GetMacroInfo
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    local trackedIds = {}
    if CD.CATEGORIES then
        for _, cat in pairs(CD.CATEGORIES) do
            local list = cat and cat.spellIds
            if type(list) == "table" then
                for _, sid in ipairs(list) do
                    -- Keep all category spell ids; we'll filter for persistence via IsTrackedSpellId.
                    trackedIds[#trackedIds + 1] = sid
                end
            end
        end
    end

    local maxSlots = 180 -- fallback: scan more for modern/extra bars (e.g. TBC Anniversary)
    if type(_G.NUM_ACTIONBAR_BUTTONS) == "number"
        and type(_G.NUM_ACTIONBAR_PAGES) == "number"
        and _G.NUM_ACTIONBAR_BUTTONS > 0
        and _G.NUM_ACTIONBAR_PAGES > 0
    then
        maxSlots = math.max(maxSlots, _G.NUM_ACTIONBAR_BUTTONS * _G.NUM_ACTIONBAR_PAGES)
    end
    local gt = GetTime and GetTime() or 0
    local wall = time and time() or 0
    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    local scanned = 0
    local macroHits = 0
    local nonEmpty = 0
    local debugPrinted = 0
    local function persistFromActionCooldown(spellId, slot)
        local a, b = GetActionCooldown(slot)
        PersistCooldownExpiry(char, spellId, a, b, gt, wall, "ActionBar", "spell")
        scanned = scanned + 1
        LogCooldownScanDebug(string.format(
            "ActionBar slot=%d type=%s spell=%d a=%s b=%s rem=%.1fs expUnix=%s",
            slot,
            tostring(select(1, GetActionInfo(slot))),
            spellId,
            tostring(a),
            tostring(b),
            CooldownRemainingSecondsFromSpellApi(a, b, gt, wall),
            tostring(char.ProfCooldownExpiry[spellId] and char.ProfCooldownExpiry[spellId].expiresAtUnix)
        ))
    end
    for slot = 1, maxSlots do
        local actionType, actionId = GetActionInfo(slot)
        if actionType ~= nil then
            nonEmpty = nonEmpty + 1
            if CooldownsDebugEnabled() and debugPrinted < 12 then
                debugPrinted = debugPrinted + 1
                LogCooldownScanDebug(string.format(
                    "ActionBar peek slot=%d type=%s id=%s",
                    slot,
                    tostring(actionType),
                    tostring(actionId)
                ))
            end
        end
        if actionType == "spell" and type(actionId) == "number" then
            local spellId = actionId
            if CD.IsTrackedSpellId(spellId) then
                persistFromActionCooldown(spellId, slot)
            end
        elseif actionType == "macro" and type(actionId) == "number" and GetMacroInfo and HasSpellInfoApi() then
            -- Some profession casts appear on action bars as macros; match tracked spell names in macro body.
            local _, _, body = GetMacroInfo(actionId)
            if type(body) == "string" and body ~= "" then
                local bodyLower = body:lower()
                for _, spellId in ipairs(trackedIds) do
                    local sid = spellId
                    if CD.IsTrackedSpellId(sid) then
                        local sname = DS.CompatGetSpellInfo(sid)
                        if type(sname) == "string" and sname ~= "" then
                            if bodyLower:find(sname:lower(), 1, true) then
                                persistFromActionCooldown(sid, slot)
                                macroHits = macroHits + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    LogCooldownScanDebug(string.format(
        "TryScanTrackedCooldownsFromActionBars maxSlots=%d nonEmpty=%d scanned=%d macroHits=%d trackedIds=%d",
        maxSlots,
        nonEmpty,
        scanned,
        macroHits,
        #trackedIds
    ))
end

--- Persist tracked profession cooldown expiry (unix) for spells used by Cooldowns tab.
function DS:ScanTradeSkillCooldownExpiry()
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end

    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}

    local prevSel = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
    local tradeLine = (GetTradeSkillLine and GetTradeSkillLine()) or "?"
    LogCooldownScanDebug(string.format(
        "ScanTradeSkillCooldownExpiry start trade=%s prevSel=%s",
        tradeLine,
        tostring(prevSel)
    ))

    pcall(function()
        ExpandAllTradeSkillHeaders()
    end)

    if not GetNumTradeSkills or not GetTradeSkillRecipeLink then
        LogCooldownScanDebug("abort: missing GetNumTradeSkills or GetTradeSkillRecipeLink")
    elseif GetNumTradeSkills then
        local numTradeSkills = GetNumTradeSkills()
        LogCooldownScanDebug("numTradeSkills=" .. tostring(numTradeSkills))
        if numTradeSkills and numTradeSkills > 0 then
            local trackedRows = 0
            for i = 1, numTradeSkills do
                local skillName, skillType = GetTradeSkillInfo(i)
                if skillType and skillType ~= "header" and skillType ~= "subheader" then
                    local link = GetTradeSkillRecipeLink(i)
                    local rowIds = CollectRecipeIdsFromTradeSkillIndex(i)
                    if #rowIds == 0 then
                        local fallback = RecipeIdFromTradeLink(link)
                        if fallback then
                            rowIds = { fallback }
                        end
                    end
                    local trackedIds = {}
                    for _, recipeID in ipairs(rowIds) do
                        if recipeID and CD.IsTrackedSpellId(recipeID) then
                            trackedIds[#trackedIds + 1] = recipeID
                        end
                    end
                    if #trackedIds > 0 then
                        trackedRows = trackedRows + 1
                        -- Cooldown APIs match the tradeskill UI: row must be selected (same as reagent capture).
                        if SelectTradeSkill then
                            pcall(SelectTradeSkill, i)
                        end
                        local gt = GetTime and GetTime() or 0
                        local wall = time and time() or 0
                        local a, b
                        if GetTradeSkillCooldown then
                            a, b = GetTradeSkillCooldown(i)
                        end
                        local remaining = CooldownRemainingSecondsFromTradeSkillApi(a, b)
                        local expiresUnix = wall
                        if remaining > 0 then
                            expiresUnix = wall + math.ceil(remaining)
                        end
                        for _, recipeID in ipairs(trackedIds) do
                            PersistCooldownExpiry(
                                char,
                                recipeID,
                                a,
                                b,
                                gt,
                                wall,
                                "TradeSkill",
                                "tradeskill"
                            )
                        end
                        local linkShort = link and link:sub(1, math.min(48, #link)) or "(nil)"
                        LogCooldownScanDebug(string.format(
                            " row=%d ids=%s name=%q a=%s b=%s gt=%.3f rem=%.1fs -> expUnix=%s (%s)",
                            i,
                            table.concat(trackedIds, ","),
                            skillName or "?",
                            tostring(a),
                            tostring(b),
                            gt,
                            remaining,
                            tostring(expiresUnix),
                            remaining <= 0 and "READY" or "CD"
                        ))
                        LogCooldownScanDebug("  link=" .. linkShort)
                    end
                end
            end
            LogCooldownScanDebug("tracked recipe rows scanned=" .. tostring(trackedRows))
        end
    end

    if prevSel and SelectTradeSkill then
        pcall(function()
            SelectTradeSkill(prevSel)
        end)
    end
    LogCooldownScanDebug("restored selection to " .. tostring(prevSel))
end

function DS:ScanCraftCooldownExpiry()
    local char = GetCurrentCharTable()
    if not char then return end
    local CD = AltArmy and AltArmy.CooldownData
    if not CD or not CD.IsTrackedSpellId then return end
    if not GetNumCrafts or not GetCraftRecipeLink then return end
    if not GetCraftCooldown then return end

    char.ProfCooldownExpiry = char.ProfCooldownExpiry or {}
    local wall = time and time() or 0
    local gt = GetTime and GetTime() or 0
    local numCrafts = GetNumCrafts()
    LogCooldownScanDebug("ScanCraftCooldownExpiry numCrafts=" .. tostring(numCrafts))
    if not numCrafts or numCrafts == 0 then return end

    for i = 1, numCrafts do
        local link = GetCraftRecipeLink(i)
        local recipeID = RecipeIdFromEnchantLink(link)
        if recipeID and CD.IsTrackedSpellId(recipeID) then
            local a, b = GetCraftCooldown(i)
            local remaining = CooldownRemainingSecondsFromTradeSkillApi(a, b)
            PersistCooldownExpiry(char, recipeID, a, b, gt, wall, "Craft", "tradeskill")
            local expiresUnix = char.ProfCooldownExpiry[recipeID]
                and char.ProfCooldownExpiry[recipeID].expiresAtUnix
            LogCooldownScanDebug(string.format(
                " craft row=%d enchantId=%d a=%s b=%s gt=%.3f rem=%.1fs expUnix=%s",
                i,
                recipeID,
                tostring(a),
                tostring(b),
                gt,
                remaining,
                tostring(expiresUnix)
            ))
        end
    end
end
