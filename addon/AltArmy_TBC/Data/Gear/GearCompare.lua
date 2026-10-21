-- AltArmy TBC — Item comparison for Gear tab character selection.
-- luacheck: globals GetItemInfo GetItemStats

AltArmy = AltArmy or {}
AltArmy.GearCompare = AltArmy.GearCompare or {}

local GC = AltArmy.GearCompare
local GU = AltArmy.GearUpgrade
local ItemStats = AltArmy.ItemStats
local DS = AltArmy.DataStore

-- Whether two realms are one (Forever's coalesced realms are: RealmFilter.sameRealm).
local function sameRealm(a, b)
    local RF = AltArmy.RealmFilter
    if RF and RF.sameRealm then return RF.sameRealm(a, b) end
    return (a or "") == (b or "")
end

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

local function getStatLabel(key)
    if ItemStats and ItemStats.GetDisplayLabel then
        return ItemStats.GetDisplayLabel(key)
    end
    return key
end

local function IU()
    return AltArmy.ItemUsability
end

local function getItemName(link)
    if not link or not hasItemInfoApi() then return "?" end
    local name = compatGetItemInfo(link)
    return name or "?"
end

local function getRawStats(link)
    if ItemStats and ItemStats.GetNormalized then
        return ItemStats.GetNormalized(link)
    end
    if GU.GetNormalizedItemStats then
        return GU.GetNormalizedItemStats(link)
    end
    return {}
end

local OFFHAND_SCALED_STAT = "melee_dps"

local function offhandDpsFactor()
    local factor = GU and tonumber(GU.OFFHAND_DPS_FACTOR)
    return factor or 0.5
end

--- Tooltip text for the compare-panel hint shown when off-hand DPS scaling applies.
function GC.GetOffhandDpsHintText()
    return string.format(
        "When dual wielding, the offhand weapon's damage is scaled to %d%% of its listed amount",
        offhandDpsFactor() * 100)
end

--- Sum raw stats for one loadout side; off-hand weapon DPS is counted at
--- GU.OFFHAND_DPS_FACTOR so displayed rows match the weighted score.
--- Second return is true when scaling changed a value.
local function sumLoadoutSideStats(mhLink, ohLink)
    local totals = {}
    local scaled = false
    local function addStats(link, isOffhand)
        if not link then return end
        local stats = getRawStats(link)
        for key, value in pairs(stats) do
            if key == "conditional" then
                -- Situational stat groups (condition -> { short key -> number }); merge per
                -- condition rather than coercing the table to a number.
                if type(value) == "table" then
                    totals.conditional = totals.conditional or {}
                    for condition, sub in pairs(value) do
                        local merged = totals.conditional[condition] or {}
                        totals.conditional[condition] = merged
                        for subKey, subValue in pairs(sub) do
                            merged[subKey] = (merged[subKey] or 0) + (tonumber(subValue) or 0)
                        end
                    end
                end
            else
                local v = tonumber(value) or 0
                if isOffhand and key == OFFHAND_SCALED_STAT and v ~= 0 then
                    v = v * offhandDpsFactor()
                    scaled = true
                end
                totals[key] = (totals[key] or 0) + v
            end
        end
    end
    addStats(mhLink, false)
    addStats(ohLink, true)
    return totals, scaled
end

local function resolveLoadoutStatSides(newLink, oldLink, charData, entry, opts)
    if not charData or not newLink
        or not GU.IsWeaponPairItem or not GU.IsWeaponPairItem(newLink)
        or not GU.GetWeaponLoadoutCompareLinks then
        return getRawStats(newLink), oldLink and getRawStats(oldLink) or {}, false
    end
    local compareOpts = {}
    if opts then
        for k, v in pairs(opts) do
            compareOpts[k] = v
        end
    end
    local loadout = GU.GetWeaponLoadoutCompareLinks(charData, newLink, compareOpts, entry)
    local selection = loadout and loadout.selection
    if not selection then
        return getRawStats(newLink), oldLink and getRawStats(oldLink) or {}, false
    end
    local newStats, newScaled = sumLoadoutSideStats(
        selection.candidateMH, selection.candidateOH)
    local oldStats, oldScaled = sumLoadoutSideStats(
        selection.equippedMH, selection.equippedOH)
    return newStats, oldStats, newScaled or oldScaled
end

local function buildSummary(newLink, oldLink, technique, classFile, specKey, charData, entry, opts, level)
    opts = opts or {}
    if GU.IsWeaponPairItem and GU.IsWeaponPairItem(newLink) and charData then
        local compareOpts = {}
        for k, v in pairs(opts) do
            compareOpts[k] = v
        end
        if compareOpts.technique == nil then
            compareOpts.technique = technique
        end
        local delta, info = GU.GetWeaponConfigDelta(charData, newLink, compareOpts, entry)
        if info then
            return {
                newTotal = info.candidateValue or 0,
                oldTotal = info.currentValue or 0,
                delta = delta or 0,
                weaponLoadout = info,
            }
        end
    end
    local newTotal = GU.ScoreItem(newLink, technique, classFile, specKey, level) or 0
    local oldTotal = oldLink and (GU.ScoreItem(oldLink, technique, classFile, specKey, level) or 0) or 0
    return {
        newTotal = newTotal,
        oldTotal = oldTotal,
        delta = newTotal - oldTotal,
    }
end

local WEAPON_LOADOUT_CAVEAT = "Compares your full main-hand + off-hand setup. "
    .. "Off-hand weapon DPS counts at 50%; stat weights ignore weapon speed."

local function getItemNameFromLink(link)
    if not link then return nil end
    return getItemName(link)
end

local function weightedPercentValue(summary, _upgradeMaxDelta)
    if GU and GU.GetWeightedChangePercent then
        return GU.GetWeightedChangePercent(summary.delta, summary.oldTotal)
    end
    local delta = summary.delta or 0
    local oldTotal = summary.oldTotal or 0
    if oldTotal > 0 then
        return delta / oldTotal * 100
    end
    if delta > 0 then return 100 end
    return 0
end

local function buildWeaponLoadoutNote(info)
    if not info then return WEAPON_LOADOUT_CAVEAT end
    local note = WEAPON_LOADOUT_CAVEAT
    if info.offHandLink then
        local fillName = getItemNameFromLink(info.offHandLink)
        if fillName and fillName ~= "?" then
            note = note .. " Includes " .. fillName .. " from bags."
        end
    end
    return note
end

local function buildWeaponLoadoutRow(charData, entry, focusedLink, opts, upgradeMaxDelta)
    if not GU.IsWeaponPairItem or not GU.IsWeaponPairItem(focusedLink) or not charData then
        return nil
    end
    local delta, info = GU.GetWeaponConfigDelta(charData, focusedLink, opts, entry)
    if not info then return nil end
    local summary = {
        delta = delta or 0,
        oldTotal = info.currentValue or 0,
    }
    return {
        label = "Weapon loadout",
        delta = summary.delta,
        percent = info.currentValue and info.currentValue > 0
            and weightedPercentValue(summary, upgradeMaxDelta) or nil,
        hideWeight = true,
        formatAsWeightedChange = true,
        weaponLoadout = info,
    }
end

local function statWeightForKey(weights, key)
    if not weights then return 0 end
    local w = weights[key]
    if not w or w <= 0 then return 0 end
    return w
end

local function compareStatComparisonRows(a, b)
    local wa = a.weight or 0
    local wb = b.weight or 0
    local aImportant = wa > 0
    local bImportant = wb > 0
    if aImportant and bImportant then
        if wa ~= wb then return wa > wb end
        return (a.label or "") < (b.label or "")
    end
    if aImportant then return true end
    if bImportant then return false end
    return (a.label or "") < (b.label or "")
end

local function offhandHintForKey(key, offhandScaled)
    if offhandScaled and key == OFFHAND_SCALED_STAT then
        return GC.GetOffhandDpsHintText()
    end
    return nil
end

-- Conditional/situational stats (e.g. "...in Forest and Grassland areas") live under a
-- reserved `conditional` key on a normalized stats table (see ItemStats.lua) instead of the
-- normal flat short-key -> number shape. Pull that key out before any arithmetic over the rest.
local function splitScalarAndConditionalStats(stats)
    stats = stats or {}
    local scalar = {}
    for key, value in pairs(stats) do
        if key ~= "conditional" then scalar[key] = value end
    end
    return scalar, stats.conditional or {}
end

-- Resistance short keys fanned out by "all Resistances"-style equip lines. When a row set has a
-- changed row for every one of these keys and the rows are otherwise identical (same new/old/
-- weight), they're collapsed into one "All Resistances" row instead of six separate ones.
local ALL_RESISTANCE_SHORT_KEYS = {
    "holy_res", "fire_res", "nature_res", "frost_res", "shadow_res", "arcane_res",
}

local function collapseAllResistanceRows(rows)
    local byKey = {}
    local matchCount = 0
    for i = 1, #rows do
        local row = rows[i]
        if row.statKey then
            for j = 1, #ALL_RESISTANCE_SHORT_KEYS do
                if row.statKey == ALL_RESISTANCE_SHORT_KEYS[j] then
                    byKey[row.statKey] = row
                    matchCount = matchCount + 1
                    break
                end
            end
        end
    end
    if matchCount ~= #ALL_RESISTANCE_SHORT_KEYS then return rows end

    -- "Identical value" means the same new/old amount (what's actually displayed); per-school
    -- Pawn weights can differ slightly even when the amounts match, so weight isn't part of the
    -- equality check. The merged row shows the highest of the six weights so sort position/
    -- importance stays sensible even when they're not perfectly uniform.
    local first = byKey[ALL_RESISTANCE_SHORT_KEYS[1]]
    local maxWeight = first.weight or 0
    for j = 2, #ALL_RESISTANCE_SHORT_KEYS do
        local row = byKey[ALL_RESISTANCE_SHORT_KEYS[j]]
        if row.newValue ~= first.newValue or row.oldValue ~= first.oldValue then
            return rows
        end
        if (row.weight or 0) > maxWeight then
            maxWeight = row.weight or 0
        end
    end

    local isResistanceKey = {}
    for j = 1, #ALL_RESISTANCE_SHORT_KEYS do
        isResistanceKey[ALL_RESISTANCE_SHORT_KEYS[j]] = true
    end
    local collapsed = {}
    local inserted = false
    for i = 1, #rows do
        local row = rows[i]
        if not (row.statKey and isResistanceKey[row.statKey]) then
            collapsed[#collapsed + 1] = row
        elseif not inserted then
            local merged = {}
            for k, v in pairs(first) do merged[k] = v end
            merged.label = "All Resistances"
            merged.statKey = nil
            merged.weight = maxWeight
            merged.unimportant = maxWeight <= 0
            merged.weightedDelta = merged.delta and merged.delta * maxWeight or nil
            collapsed[#collapsed + 1] = merged
            inserted = true
        end
    end
    return collapsed
end

local function buildConditionalRows(newConditional, oldConditional)
    local labels = {}
    local seenLabel = {}
    for label in pairs(newConditional) do
        if not seenLabel[label] then
            seenLabel[label] = true
            labels[#labels + 1] = label
        end
    end
    for label in pairs(oldConditional) do
        if not seenLabel[label] then
            seenLabel[label] = true
            labels[#labels + 1] = label
        end
    end
    table.sort(labels)

    local rows = {}
    for i = 1, #labels do
        local label = labels[i]
        local newSub = newConditional[label] or {}
        local oldSub = oldConditional[label] or {}
        local seenKey = {}
        local keys = {}
        for k in pairs(newSub) do
            if not seenKey[k] then seenKey[k] = true; keys[#keys + 1] = k end
        end
        for k in pairs(oldSub) do
            if not seenKey[k] then seenKey[k] = true; keys[#keys + 1] = k end
        end
        table.sort(keys)

        local statRows = {}
        for j = 1, #keys do
            local key = keys[j]
            local newVal = newSub[key] or 0
            local oldVal = oldSub[key] or 0
            if newVal ~= oldVal then
                statRows[#statRows + 1] = {
                    label = getStatLabel(key),
                    statKey = key,
                    newValue = newVal,
                    oldValue = oldVal,
                    delta = newVal - oldVal,
                    weight = 0,
                    unimportant = true,
                    hideWeight = true,
                    conditional = true,
                }
            end
        end
        statRows = collapseAllResistanceRows(statRows)

        if #statRows > 0 then
            rows[#rows + 1] = {
                label = string.format("... %s:", label),
                isHeader = true,
                conditional = true,
            }
            for j = 1, #statRows do
                rows[#rows + 1] = statRows[j]
            end
        end
    end
    return rows
end

local function buildStatComparisonRows(newLink, oldLink, classFile, specKey, charData, entry, opts, level)
    local weights = GU.GetWeights and GU.GetWeights(classFile, specKey, level) or {}
    local newStatsRaw, oldStatsRaw, offhandScaled = resolveLoadoutStatSides(
        newLink, oldLink, charData, entry, opts)
    local newStats, newConditional = splitScalarAndConditionalStats(newStatsRaw)
    local oldStats, oldConditional = splitScalarAndConditionalStats(oldStatsRaw)
    local seen = {}
    for k in pairs(newStats) do seen[k] = true end
    for k in pairs(oldStats) do seen[k] = true end

    local rows = {}
    for key in pairs(seen) do
        local newVal = newStats[key] or 0
        local oldVal = oldStats[key] or 0
        if newVal ~= oldVal then
            local w = statWeightForKey(weights, key)
            rows[#rows + 1] = {
                label = getStatLabel(key),
                statKey = key,
                newValue = newVal,
                oldValue = oldVal,
                delta = newVal - oldVal,
                weight = w,
                unimportant = w <= 0,
                weightedDelta = (newVal - oldVal) * w,
                offhandHint = offhandHintForKey(key, offhandScaled),
            }
        end
    end
    rows = collapseAllResistanceRows(rows)
    table.sort(rows, compareStatComparisonRows)
    local conditionalRows = buildConditionalRows(newConditional, oldConditional)
    for i = 1, #conditionalRows do
        rows[#rows + 1] = conditionalRows[i]
    end
    return rows
end

local function buildRawStatRows(newLink, oldLink, charData, entry, opts)
    local newStatsRaw, oldStatsRaw, offhandScaled = resolveLoadoutStatSides(
        newLink, oldLink, charData, entry, opts)
    local newStats, newConditional = splitScalarAndConditionalStats(newStatsRaw)
    local oldStats, oldConditional = splitScalarAndConditionalStats(oldStatsRaw)
    local seen = {}
    local keys = {}
    for k in pairs(newStats) do
        seen[k] = true
        keys[#keys + 1] = k
    end
    for k in pairs(oldStats) do
        if not seen[k] then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local rows = {}
    for i = 1, #keys do
        local key = keys[i]
        local newVal = newStats[key] or 0
        local oldVal = oldStats[key] or 0
        rows[#rows + 1] = {
            label = getStatLabel(key),
            statKey = key,
            newValue = newVal,
            oldValue = oldVal,
            delta = newVal - oldVal,
            offhandHint = offhandHintForKey(key, offhandScaled),
        }
    end
    rows = collapseAllResistanceRows(rows)
    local conditionalRows = buildConditionalRows(newConditional, oldConditional)
    for i = 1, #conditionalRows do
        rows[#rows + 1] = conditionalRows[i]
    end
    return rows
end

local function buildCustomComparison(newLink, oldLink, classFile, specKey, opts, charData, entry, level)
    opts = opts or {}
    local rows = buildStatComparisonRows(
        newLink, oldLink, classFile, specKey, charData, entry, opts, level)
    local summary = buildSummary(
        newLink, oldLink, "custom", classFile, specKey, charData, entry, opts, level)
    local loadoutRow = buildWeaponLoadoutRow(charData, entry, newLink, opts, opts.upgradeMaxDelta)
    if loadoutRow then
        rows[#rows + 1] = loadoutRow
    else
        rows[#rows + 1] = {
            label = "Weighted",
            delta = summary.delta,
            percent = oldLink and weightedPercentValue(summary, opts.upgradeMaxDelta) or nil,
            hideWeight = true,
            formatAsWeightedChange = true,
        }
    end
    local sections = {
        {
            title = "Stat comparison",
            rows = rows,
        },
    }
    local result = {
        sections = sections,
        summary = summary,
    }
    if summary.weaponLoadout then
        result.weaponLoadoutNote = buildWeaponLoadoutNote(summary.weaponLoadout)
    end
    return result
end

local function buildScoreOnlyComparison(
    newLink, oldLink, classFile, specKey, technique, charData, entry, opts, level)
    local sections = {}
    local rawRows = buildRawStatRows(newLink, oldLink, charData, entry, opts)
    if #rawRows > 0 then
        sections[#sections + 1] = {
            title = "Raw stats",
            rows = rawRows,
        }
    end
    local summary = buildSummary(
        newLink, oldLink, technique, classFile, specKey, charData, entry, opts, level)
    if technique == "ilvl" then
        sections[#sections + 1] = {
            title = "Item level",
            rows = {
                {
                    label = "Item Level",
                    newValue = summary.newTotal,
                    oldValue = summary.oldTotal,
                    delta = summary.delta,
                },
            },
        }
    end
    local result = {
        sections = sections,
        summary = summary,
    }
    if summary.weaponLoadout then
        result.weaponLoadoutNote = buildWeaponLoadoutNote(summary.weaponLoadout)
    end
    return result
end

function GC.GetEquippedCompareItem(char, focusedLink, opts)
    opts = opts or {}
    if not char or not focusedLink then return nil, nil end
    local slots = IU() and IU().GetInventorySlotsForItem(focusedLink) or {}
    if #slots == 0 then return nil, nil end

    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile, specKey, level = GU.ResolveCompareContext(char, opts.entry)
    if not DS or not DS.GetInventoryItem then return nil, slots[1] end

    if opts.slot then
        local equipped = DS:GetInventoryItem(char, opts.slot)
        local eqLink = GU.ResolveItemLink(equipped)
        return eqLink, opts.slot
    end

    if GU.IsWeaponPairItem and GU.IsWeaponPairItem(focusedLink) then
        local _, configInfo = GU.GetWeaponConfigDelta(char, focusedLink, opts, opts.entry)
        local targetSlot = configInfo and configInfo.targetSlot or slots[1]
        local equipped = DS:GetInventoryItem(char, targetSlot)
        local eqLink = GU.ResolveItemLink(equipped)
        return eqLink, targetSlot
    end

    local newScore = GU.ScoreItem(focusedLink, technique, classFile, specKey, level)
    local bestSlot = slots[1]
    local bestLink = nil
    local bestDelta = -math.huge
    local hasEquipped = false

    for i = 1, #slots do
        local slot = slots[i]
        local equipped = DS:GetInventoryItem(char, slot)
        local eqLink = GU.ResolveItemLink(equipped)
        if eqLink then
            hasEquipped = true
            local oldScore = GU.ScoreItem(eqLink, technique, classFile, specKey, level)
            local delta = newScore - oldScore
            if delta > bestDelta then
                bestDelta = delta
                bestLink = eqLink
                bestSlot = slot
            end
        end
    end

    if not hasEquipped then
        return nil, bestSlot
    end
    return bestLink, bestSlot
end

function GC.BuildComparison(focusedLink, equippedLink, technique, charData, entry, opts)
    if not focusedLink then return nil end
    opts = opts or {}
    technique = GU.GetEffectiveTechnique(technique or "custom")
    local classFile, specKey, level = GU.ResolveCompareContext(charData, entry)
    local provider = GU.GetProvider(technique)
    local built

    if technique == "custom" then
        built = buildCustomComparison(
            focusedLink, equippedLink, classFile, specKey, opts, charData, entry, level)
    elseif technique == "ilvl" or technique == "gearscore" then
        built = buildScoreOnlyComparison(
            focusedLink, equippedLink, classFile, specKey, technique, charData, entry, opts, level)
    else
        built = buildCustomComparison(
            focusedLink, equippedLink, classFile, specKey, opts, charData, entry, level)
    end

    local sections = built.sections or built
    local summary = built.summary
    if not summary then
        summary = buildSummary(
            focusedLink, equippedLink, technique, classFile, specKey, charData, entry, opts, level)
    end

    return {
        focusedName = getItemName(focusedLink),
        equippedName = equippedLink and getItemName(equippedLink) or "(empty)",
        techniqueId = technique,
        techniqueLabel = provider and GU.GetProviderDisplayLabel(provider) or technique,
        summary = summary,
        sections = sections,
        weaponLoadoutNote = built.weaponLoadoutNote,
    }
end

local function formatDebugNumber(value)
    local n = tonumber(value) or 0
    if math.floor(n) == n then
        return tostring(n)
    end
    return string.format("%.1f", n)
end

local function charMatchesRealmFilter(realm, realmFilter, currentRealm)
    if realmFilter == "currentRealm" and currentRealm and not sameRealm(realm, currentRealm) then
        return false
    end
    return true
end

local function collectEquippableCharacters(itemLink, levelsAhead)
    if not DS or not DS.ForEachCharacter or not itemLink then return {} end
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return {} end

    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then realmFilter = GRF.Get() end
    local currentRealm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""

    local out = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        if not charMatchesRealmFilter(realm, realmFilter, currentRealm) then
            return
        end
        if DS.IsSameFactionAsCurrent and not DS:IsSameFactionAsCurrent(charData) then
            return
        end
        local BA = AltArmy.BankAlt
        if BA and BA.Is and BA.Is(charData.name or charName, realm) then
            return
        end
        local classFile = charData.classFile or ""
        local level = (DS.GetCharacterLevel and DS:GetCharacterLevel(charData))
            or tonumber(charData.level) or 0
        local equippable = IU() and IU().IsEquippableWithin(classFile, level, itemLink, levelsAhead)
        if not equippable then return end
        out[#out + 1] = {
            name = charData.name or charName,
            realm = realm,
            charData = charData,
        }
    end)
    table.sort(out, function(a, b)
        if a.realm ~= b.realm then return (a.realm or "") < (b.realm or "") end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

local function formatComparisonRow(row)
    if row.weightedDelta ~= nil then
        return string.format(
            "      %s: %s → %s (Δ%s, weighted Δ%s)",
            row.label or "?",
            formatDebugNumber(row.oldValue),
            formatDebugNumber(row.newValue),
            formatDebugNumber(row.delta),
            formatDebugNumber(row.weightedDelta))
    end
    return string.format(
        "      %s: %s → %s (Δ%s)",
        row.label or "?",
        formatDebugNumber(row.oldValue),
        formatDebugNumber(row.newValue),
        formatDebugNumber(row.delta))
end

--- Chat lines comparing one item across every gear technique (for debug logging).
function GC.BuildItemComparisonDebugReport(itemLink)
    local lines = {}
    if not itemLink or not GU then return lines end

    local opts = GU.GetOptions and GU.GetOptions() or {}
    local levelsAhead = tonumber(opts.levelsAhead)
    if levelsAhead == nil then levelsAhead = 5 end
    levelsAhead = math.max(0, math.floor(levelsAhead))

    lines[#lines + 1] = string.format("Item: %s", getItemName(itemLink))

    local itemStats = AltArmy.ItemStats
    if itemStats and itemStats.BuildStatParseDebugLines then
        local statLines = itemStats.BuildStatParseDebugLines(itemLink)
        for i = 1, #statLines do
            lines[#lines + 1] = statLines[i]
        end
    end

    local characters = collectEquippableCharacters(itemLink, levelsAhead)
    if #characters == 0 then
        lines[#lines + 1] = "No equippable alts for this item."
    end

    local providers = GU.GetProviders and GU.GetProviders() or {}
    for i = 1, #providers do
        local provider = providers[i]
        lines[#lines + 1] = string.format("[%s]", provider.label or provider.id or "?")
        if provider.IsAvailable and not provider.IsAvailable() then
            lines[#lines + 1] = "  (not installed — skipped)"
        elseif #characters == 0 then
            lines[#lines + 1] = "  (no equippable alts)"
        else
            local technique = provider.id or "custom"
            for c = 1, #characters do
                local entry = characters[c]
                local charData = entry.charData
                local equippedLink = GC.GetEquippedCompareItem(charData, itemLink, {
                    technique = technique,
                    entry = entry,
                })
                local comparison = GC.BuildComparison(itemLink, equippedLink, technique, charData, entry)
                if comparison then
                    local summary = comparison.summary or {}
                    local isUpgrade = GU.EvaluateForCharacter(charData, itemLink, {
                        technique = technique,
                        levelsAhead = levelsAhead,
                    })
                    local tag = isUpgrade and "upgrade" or "not upgrade"
                    lines[#lines + 1] = string.format(
                        "  %s-%s: %s → %s | total %s → %s (Δ%s) [%s]",
                        entry.name or "?",
                        entry.realm or "?",
                        comparison.equippedName or "(empty)",
                        comparison.focusedName or "?",
                        formatDebugNumber(summary.oldTotal),
                        formatDebugNumber(summary.newTotal),
                        formatDebugNumber(summary.delta),
                        tag)
                    local sections = comparison.sections or {}
                    for s = 1, #sections do
                        local section = sections[s]
                        if section.title and section.title ~= "" then
                            lines[#lines + 1] = "    " .. section.title .. ":"
                        end
                        local rows = section.rows or {}
                        for r = 1, #rows do
                            lines[#lines + 1] = formatComparisonRow(rows[r])
                        end
                    end
                end
            end
        end
    end
    return lines
end

function GC.LogItemComparisonDebug(itemLink)
    local D = AltArmy.Debug
    if not D or not D.IsItemComparisonEnabled or not D.IsItemComparisonEnabled() then
        return
    end
    local lines = GC.BuildItemComparisonDebugReport(itemLink)
    if #lines == 0 then return end
    if D.LogItemComparison then
        D.LogItemComparison(lines)
    end
    local itemStats = AltArmy.ItemStats
    if itemStats and itemStats.LogStatParseDebug then
        itemStats.LogStatParseDebug(itemLink)
    end
end

local COMPARE_DUMP_VERSION = 1

local function copyShallowTable(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

local function buildItemDump(link, classFile, specKey, technique, forceRefresh, level)
    if not link then return nil end
    local snapshot = ItemStats and ItemStats.CollectParseSnapshot
        and ItemStats.CollectParseSnapshot(link, { forceRefresh = forceRefresh })
    return {
        link = link,
        name = getItemName(link),
        cacheSource = ItemStats and ItemStats.GetSource and ItemStats.GetSource(link) or nil,
        parseSnapshot = snapshot,
        scoreBreakdown = GU and GU.BuildScoreBreakdown
            and GU.BuildScoreBreakdown(link, technique, classFile, specKey, level) or nil,
    }
end

--- Structured compare-panel payload for SavedVariables debug dumps.
function GC.BuildComparePanelDump(focusedLink, equippedLink, technique, charData, entry, opts)
    if not focusedLink then return nil end
    opts = opts or {}
    technique = GU.GetEffectiveTechnique(technique or "custom")
    local classFile, specKey, level = GU.ResolveCompareContext(charData, entry)
    -- Mirror the panel: it builds with compareSlot = selected slot, not auto best-hand.
    local compareOpts = copyShallowTable(opts)
    if compareOpts.compareSlot == nil then
        compareOpts.compareSlot = opts.invSlot
    end
    local comparison = GC.BuildComparison(
        focusedLink, equippedLink, technique, charData, entry, compareOpts)
    if not comparison then return nil end

    local summary = comparison.summary or {}
    local forceRefresh = opts.forceRefresh ~= false
    local weights = GU.GetWeights and GU.GetWeights(classFile, specKey, level) or {}

    return {
        version = COMPARE_DUMP_VERSION,
        timestamp = opts.timestamp or (time and time() or 0),
        character = {
            name = entry and entry.name or (charData and charData.name),
            realm = entry and entry.realm or (charData and charData.realm),
            classFile = classFile,
            specKey = specKey,
            level = level or (charData and tonumber(charData.level)) or nil,
        },
        context = {
            invSlot = opts.invSlot,
            techniqueId = technique,
            techniqueLabel = comparison.techniqueLabel,
            upgradeMaxDelta = opts.upgradeMaxDelta,
            upgradeThresholdPercent = opts.focusOpts
                and tonumber(opts.focusOpts.upgradeThresholdPercent) or nil,
            weightedChangePercent = weightedPercentValue(summary, opts.upgradeMaxDelta),
        },
        items = {
            focused = buildItemDump(focusedLink, classFile, specKey, technique, forceRefresh, level),
            equipped = equippedLink
                and buildItemDump(equippedLink, classFile, specKey, technique, forceRefresh, level)
                or nil,
        },
        comparison = comparison,
        weights = copyShallowTable(weights),
    }
end

function GC.SaveComparePanelDump(focusedLink, equippedLink, technique, charData, entry, opts)
    local D = AltArmy.Debug
    if not D or not D.IsEnabled or not D.IsEnabled() then
        return nil
    end
    local payload = GC.BuildComparePanelDump(
        focusedLink, equippedLink, technique, charData, entry, opts)
    if not payload then return nil end
    if not D.AppendComparePanelDump then return nil end
    return D.AppendComparePanelDump(payload)
end
