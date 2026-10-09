-- AltArmy TBC — Debug options (master switch + per-feature flags).
-- Saved under AltArmyTBC_Options.debug. Enable UI: /altarmy debug on

if not AltArmy then return end

AltArmy.Debug = AltArmy.Debug or {}
local D = AltArmy.Debug

local function debugTable()
    D.Ensure()
    return AltArmyTBC_Options.debug
end

function D.Ensure()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local d = AltArmyTBC_Options.debug
    if type(d) ~= "table" then
        d = {}
        AltArmyTBC_Options.debug = d
    end
    if d.enabled == nil then
        d.enabled = false
    end
    if d.search == nil then
        d.search = false
    end
    if d.cooldowns == nil then
        d.cooldowns = false
    end
    if d.levelHistory == nil then
        d.levelHistory = false
    end
    if d.itemComparison == nil then
        d.itemComparison = false
    end
    if d.itemStats == nil then
        d.itemStats = false
    end
    if d.guildShareVerbose == nil then
        d.guildShareVerbose = false
    end
    -- Legacy SavedVariables key from when guild share was a debug toggle; no longer read.
    d.guildShare = nil
    -- Legacy SavedVariables key from the CraftLib dependency (recipe data is bundled now); no longer read.
    d.pretendCraftLibNotInstalled = nil
    if d.showZygorMissingGuides == nil then
        d.showZygorMissingGuides = false
    end
    if d.windowResize == nil then
        d.windowResize = false
    end
    -- Legacy SavedVariables key from the dual-engine experiment; no longer read.
    d.searchEngineV2 = nil
end

function D.IsEnabled()
    D.Ensure()
    return AltArmyTBC_Options.debug.enabled == true
end

function D.SetEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.enabled = on == true
end

function D.IsSearchEnabled()
    local d = debugTable()
    return d.enabled == true and d.search == true
end

function D.SetSearchEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.search = on == true
end

function D.LogSearch(msg)
    if not D.IsSearchEnabled() then
        return
    end
    D.NotifyChat("|cff00ccff[Alt Army:Search]|r " .. tostring(msg))
end

function D.IsCooldownsEnabled()
    local d = debugTable()
    return d.enabled == true and d.cooldowns == true
end

function D.SetCooldownsEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.cooldowns = on == true
end

function D.IsLevelHistoryEnabled()
    local d = debugTable()
    return d.enabled == true and d.levelHistory == true
end

function D.SetLevelHistoryEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.levelHistory = on == true
end

function D.IsItemComparisonEnabled()
    local d = debugTable()
    return d.enabled == true and d.itemComparison == true
end

function D.SetItemComparisonEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.itemComparison = on == true
end

function D.LogItemComparison(msgs)
    if not D.IsItemComparisonEnabled() then
        return
    end
    if type(msgs) == "string" then
        msgs = { msgs }
    end
    if type(msgs) ~= "table" then
        return
    end
    for i = 1, #msgs do
        D.NotifyChat("|cff00ccff[Alt Army:Compare]|r " .. tostring(msgs[i]))
    end
end

function D.IsItemStatsEnabled()
    local d = debugTable()
    return d.enabled == true and d.itemStats == true
end

function D.SetItemStatsEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.itemStats = on == true
end

function D.LogItemStats(msgs)
    if not D.IsItemStatsEnabled() then
        return
    end
    if type(msgs) == "string" then
        msgs = { msgs }
    end
    if type(msgs) ~= "table" then
        return
    end
    for i = 1, #msgs do
        D.NotifyChat("|cff00ccff[Alt Army:ItemStats]|r " .. tostring(msgs[i]))
    end
end

--- Guild data sharing is shipped on. Call sites and tests may still stub this for flag-off paths.
--- Gates RECEIVE + UI, and selects the opt-in SEND set (see GuildShareComm).
function D.IsGuildShareEnabled()
    return true
end

--- Verbose guild-share traffic logging. Standalone (does NOT require master enabled).
function D.IsGuildShareVerbose()
    D.Ensure()
    return AltArmyTBC_Options.debug.guildShareVerbose == true
end

function D.SetGuildShareVerbose(on)
    D.Ensure()
    AltArmyTBC_Options.debug.guildShareVerbose = on == true
end

function D.LogGuildShare(msg)
    if not D.IsGuildShareVerbose() then
        return
    end
    D.NotifyChat("|cff00ccff[Alt Army:GuildShare]|r " .. tostring(msg))
end

--- When true, Reputation-tab Zygor icons also appear for trial placeholder guides
--- (guide.missing). Standalone flag (does not require master debug on).
function D.IsShowZygorMissingGuides()
    D.Ensure()
    return AltArmyTBC_Options.debug.showZygorMissingGuides == true
end

function D.SetShowZygorMissingGuides(on)
    D.Ensure()
    AltArmyTBC_Options.debug.showZygorMissingGuides = on == true
end

--- When true, the main window shows its bottom-right resize grip and opens at its saved size. Off by
--- default until every tab reflows (only Inventory does). Standalone flag (does not require master
--- debug on).
function D.IsWindowResizeEnabled()
    D.Ensure()
    return AltArmyTBC_Options.debug.windowResize == true
end

function D.SetWindowResizeEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.windowResize = on == true
    if AltArmy.ApplyWindowResize then
        AltArmy.ApplyWindowResize()
    end
end

function D.RefreshZygorDependentUi()
    local repFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Reputation
    if repFrame and repFrame.RefreshGrid then
        pcall(function()
            repFrame:RefreshGrid()
        end)
    end
end

function D.NotifyChat(msg)
    local text = tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

--- Center-screen alert so a dump firing during play is impossible to miss.
function D.ShowCenterAlert(text)
    if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
        _G.UIErrorsFrame:AddMessage(tostring(text), 1, 0.3, 0.3, 1)
    end
end

--- Standing dev-dump tool — see docs/DEV_DUMPS.md. `AltArmy.Debug.Dump(label, payload)` is
--- meant to be called from wherever a debugging task needs to capture live-client data into
--- SavedVariables; it's a no-op unless master debug is on (/altarmy debug on), so leaving
--- calls in committed code between tasks is cheap. Writes to
--- AltArmyTBC_Options.debug.devDumps[label] (overwriting any previous payload under the same
--- label) and shows a center-screen alert. Read back with: /reload, then `npm run dump:sync`,
--- then read devDumps.<label> from the synced file (see docs/DEV_DUMPS.md).
function D.Dump(label, payload)
    if not D.IsEnabled() then
        return
    end
    if type(label) ~= "string" or label == "" then
        return
    end
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if type(d.devDumps) ~= "table" then
        d.devDumps = {}
    end
    d.devDumps[label] = payload
    D.ShowCenterAlert("Alt Army dev dump: " .. label)
end

local SAVED_VARIABLES = {
    "AltArmyTBC_Options", "AltArmyTBC_Data", "AltArmyTBC_GearSettings", "AltArmyTBC_ReputationSettings",
    "AltArmyTBC_SummarySettings", "AltArmyTBC_SearchSettings", "AltArmyTBC_GraphSettings", "AltArmyTBC_GuildData",
    "AltArmyTBC_SharingSettings", "AltArmyTBC_AuctionScans", "AltArmyTBC_AuctionBook",
}
local SERIALIZABLE = { string = true, number = true, boolean = true, table = true }
local MAX_LISTED = 60

--- Walk one SavedVariables table; append "path=type" for every key or value the client cannot write.
local function unserializableIn(root, name, hits, seen)
    local issecret = _G.issecretvalue
    local stack = { { t = root, path = name } }
    while #stack > 0 and #hits < MAX_LISTED do
        local cur = table.remove(stack)
        local t = cur.t
        if not seen[t] then
            seen[t] = true
            for k, v in pairs(t) do
                local kt, vt = type(k), type(v)
                local path = cur.path .. "." .. tostring(k)
                if kt ~= "string" and kt ~= "number" then
                    hits[#hits + 1] = path .. "=key:" .. kt
                elseif not SERIALIZABLE[vt] then
                    hits[#hits + 1] = path .. "=" .. vt
                elseif issecret and vt ~= "table" and issecret(v) then
                    hits[#hits + 1] = path .. "=secret:" .. vt
                elseif vt == "table" then
                    stack[#stack + 1] = { t = v, path = path }
                end
                if #hits >= MAX_LISTED then
                    break
                end
            end
        end
    end
end

--- Debug: report what is tainted on the player cast bar's code path and by whom, for ADDON_ACTION_BLOCKED on
--- PlayerCastingBarFrame:Show(): every field of the tables that path reads whose value is insecure, with the
--- addon the client blames; every global this addon tainted that is not its own, and every field it tainted in a
--- table it does not own (a Blizzard frame or mixin it wrote into); and anything in the addon's
--- SavedVariables the client cannot serialize (a function, userdata or secret value stops the whole file from
--- being written). Returns the report as one line of text (also written as dev dump "taint"); nil when the
--- client has no issecurevariable. Runs whether or not debug is on (/altarmy taint), since it only reads.
function D.DumpTaint()
    local issecure = _G.issecurevariable
    if type(issecure) ~= "function" then
        return nil
    end
    local out = { when = _G.date and _G.date() or nil, fields = {}, globals = {}, taintedGlobalsByAddon = {} }
    local lines = {}
    local function fieldsOf(t, name)
        if type(t) ~= "table" then
            return
        end
        local found, n = {}, 0
        for k in pairs(t) do
            local ok, src = true, nil
            if type(k) == "string" then
                ok, src = issecure(t, k)
            end
            if not ok then
                found[tostring(k)] = tostring(src or "?")
                n = n + 1
                lines[#lines + 1] = name .. "." .. tostring(k) .. "<" .. tostring(src or "?")
            end
        end
        if n > 0 then
            out.fields[name] = found
        end
    end
    local names = {
        "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarMixin", "PlayerCastingBarMixin",
        "PlayerCastingBarFrameMixin", "EditModeSystemMixin", "EditModeManagerFrame", "GameRulesUtil", "InputUtil",
        "C_GameRules", "Enum", "PlayerFrame", "UIParent", "ProfessionsFrame", "PlayerSpellsFrame", "SOUNDKIT",
        "ManagedFrameMixin",
    }
    for _, name in ipairs(names) do
        local ok, src = issecure(name)
        out.globals[name] = ok and "secure" or ("tainted by " .. tostring(src))
        if not ok then
            lines[#lines + 1] = "global " .. name .. "<" .. tostring(src)
        end
        fieldsOf(_G[name], name)
    end
    if type(_G.Enum) == "table" then
        fieldsOf(_G.Enum.GameRule, "Enum.GameRule")
    end
    local mine, counts, mineList = {}, {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            local ok, src = issecure(k)
            if not ok then
                src = tostring(src)
                counts[src] = (counts[src] or 0) + 1
                if src == "AltArmy_TBC" and not k:match("^AltArmy") and not k:match("^SLASH_ALTARMY") then
                    mine[k] = type(v)
                    if #mineList < MAX_LISTED then
                        mineList[#mineList + 1] = k .. ":" .. type(v)
                    end
                end
            end
        end
    end
    out.taintedGlobalsByAddon = counts
    out.globalsTaintedByAltArmy = mine
    -- Fields this addon tainted inside tables it does not own (a Blizzard frame or mixin it wrote into).
    local foreign = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and k ~= "_G" and not k:match("^AltArmy") and issecure(k) then
            for fk in pairs(v) do
                local ok, src = true, nil
                if type(fk) == "string" then
                    ok, src = issecure(v, fk)
                end
                if not ok and tostring(src) == "AltArmy_TBC" and #foreign < MAX_LISTED then
                    foreign[#foreign + 1] = k .. "." .. tostring(fk)
                end
            end
        end
    end
    table.sort(foreign)
    out.fieldsTaintedByAltArmy = foreign
    local countList = {}
    for src, n in pairs(counts) do
        countList[#countList + 1] = src .. "=" .. n
    end
    table.sort(countList)
    table.sort(mineList)
    local bad, seen = {}, {}
    for _, name in ipairs(SAVED_VARIABLES) do
        if type(_G[name]) == "table" then
            unserializableIn(_G[name], name, bad, seen)
        end
    end
    out.unserializable = bad
    local report = "TAINT " .. tostring(out.when) .. " | path: " .. (#lines > 0 and table.concat(lines, ", ") or "none")
        .. " | tainted globals per addon: " .. (#countList > 0 and table.concat(countList, ", ") or "none")
        .. " | globals tainted by AltArmy_TBC: " .. (#mineList > 0 and table.concat(mineList, ", ") or "none")
        .. " | fields tainted by AltArmy_TBC in other tables: "
        .. (#foreign > 0 and table.concat(foreign, ", ") or "none")
        .. " | unserializable in SavedVariables: " .. (#bad > 0 and table.concat(bad, ", ") or "none")
    out.report = report
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if type(d.devDumps) ~= "table" then
        d.devDumps = {}
    end
    d.devDumps.taint = out
    D.ShowCenterAlert("Alt Army dev dump: taint")
    return report
end

D.MAX_COMPARE_PANEL_DUMPS = 1
D.MAX_GUILD_SHARE_UNDECODABLE_DUMPS = 1

local function ensureComparePanelDumps()
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if type(d.comparePanelDumps) ~= "table" then
        d.comparePanelDumps = {}
    end
    return d.comparePanelDumps
end

local function ensureGuildShareUndecodableDumps()
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if type(d.guildShareUndecodableDumps) ~= "table" then
        d.guildShareUndecodableDumps = {}
    end
    return d.guildShareUndecodableDumps
end

function D.AppendComparePanelDump(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local dumps = ensureComparePanelDumps()
    dumps[#dumps + 1] = payload
    while #dumps > D.MAX_COMPARE_PANEL_DUMPS do
        table.remove(dumps, 1)
    end
    return #dumps
end

function D.AppendGuildShareUndecodableDump(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local dumps = ensureGuildShareUndecodableDumps()
    dumps[#dumps + 1] = payload
    while #dumps > D.MAX_GUILD_SHARE_UNDECODABLE_DUMPS do
        table.remove(dumps, 1)
    end
    return #dumps
end

function D.NotifyCompareDumpSaved(index, total)
    D.NotifyChat(string.format(
        "|cff00ccff[Alt Army:Debug]|r Compare dump #%d saved (%d in buffer). "
            .. "/reload, then open WTF/.../SavedVariables/AltArmy_TBC.lua",
        tonumber(index) or 0,
        tonumber(total) or 0))
end

function D.NotifyGuildShareUndecodableDumpSaved(index, total)
    D.NotifyChat(string.format(
        "|cff00ccff[Alt Army:GuildShare]|r Undecodable dump #%d saved (%d in buffer). "
            .. "/reload, then npm run dump:sync (guildShareUndecodableDumps).",
        tonumber(index) or 0,
        tonumber(total) or 0))
end

--- Overwrites (not appends — only the latest client's results matter) the
--- Blizzard-API existence check snapshot from ApiCheck.lua's /altarmy debug apicheck.
function D.SaveApiCheckSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return
    end
    D.Ensure()
    AltArmyTBC_Options.debug.apiCheckSnapshot = snapshot
end

--- Overwrites the auction house listings probe's result from AuctionProbe.lua's
--- /altarmy debug ahprobe.
function D.SaveAuctionProbe(result)
    if type(result) ~= "table" then
        return
    end
    D.Ensure()
    AltArmyTBC_Options.debug.auctionProbe = result
end

D.Ensure()
