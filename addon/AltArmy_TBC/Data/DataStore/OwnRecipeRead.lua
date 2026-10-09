-- AltArmy TBC — read recipes through profession links without anyone opening a window (WoW Forever).
-- luacheck: globals ProfessionsFrame ProfessionsFrame_LoadUI GetUIPanel C_SpellBook
-- luacheck: globals ChatEdit_GetActiveWindow ChatFrameUtil GetFramesRegisteredForEvent
-- luacheck: globals GetMouseFoci WorldFrame SetItemRef
--
-- C_TradeSkillUI.OpenTradeSkill needs a click, but a hidden tooltip's SetHyperlink on a profession link,
-- "trade:<player GUID>:<profession spell>:<skill line>", does not: the client asks the server for that
-- profession and opens it as if the player had. Learned from the Linked Inn addon (Reader.ReadOwn); see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth".
--
-- Two kinds of read share one queue and one hidden window:
--   own   — the player's own stale professions (marked by the Summary warning, or with no recipes stored).
--           The DataStore's TRADE_SKILL_SHOW / TRADE_SKILL_DATA_SOURCE_CHANGED handlers scan the window
--           (ScanRecipesViaTradeSkillUI), which calls R.OnRecipesScanned. Queued after login and after a
--           recipe is learned that the bundled recipe data couldn't store.
--   guild — an online guildmate's profession, asked for by Guild/GuildLinkRead.lua with the profession's
--           Apprentice spell (R.Enqueue). The server answers only for players online on this server. This
--           file scans the linked window itself (R._ScanLinkedWindow) and hands the recipe ids and skill to
--           the job's callback; the DataStore never stores another player's window.
-- Own reads go first; guild reads follow in the order they were queued. Reads run one at a time, never in
-- combat, while typing, or while any panel (the player's own profession window included) is open, and a
-- click on the interface mid-read puts the read back in line. While a read waits, TRADE_SKILL_SHOW is
-- silenced (see "Keeping the window shut"), so Blizzard's window never opens and never plays its sound;
-- should it open all the same (silencing given up, or unavailable), it is concealed (alpha 0, tiny, no
-- mouse) and closed when the read ends. Only on clients with C_TradeSkillUI and no legacy trade skill API
-- (Forever); TBC's Enchanting has no trade skill window at all.
--
-- Nothing here ever shows Blizzard's window itself. Lua run from an addon is tainted, and the window's
-- OnShow (or the ShowUIPanel that triggers it) would write tainted state into ProfessionsFrame; its
-- crafting page later hands that taint to PlayerCastingBarFrame (SetOverrideCastBarActive, which writes
-- showCastbar), and every player cast then fails with ADDON_ACTION_BLOCKED on PlayerCastingBarFrame:Show().
-- The window is only ever opened by Blizzard's own TRADE_SKILL_SHOW handling. SetAlpha, SetScale,
-- EnableMouse and C_TradeSkillUI.CloseTradeSkill touch no Lua state and are safe.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore

AltArmy.OwnRecipeRead = AltArmy.OwnRecipeRead or {}
local R = AltArmy.OwnRecipeRead

R.LOGIN_DELAY = 10 -- seconds after login or a reload before the first read
R.LEARN_DELAY = 3  -- seconds after a recipe is learned before its profession is read again
R.GAP = 1          -- seconds between own reads
R.GUILD_GAP = 2    -- seconds after a guild read (Linked Inn paces its reads 1-2 s apart)
R.RETRY = 5        -- seconds before trying again while something is in the way
R.TIMEOUT = 3      -- seconds a read may take before its link counts as unanswered
R.SHOW_SCAN_DELAY = 0.5 -- seconds after TRADE_SKILL_SHOW before a linked window is scanned (the DataStore's delay)
-- Whether a guild read trusts only a window the client says is linked under the asked-for player's name.
-- Off, a window that comes back unlinked or unnamed counts too, as long as it is the asked-for profession
-- (to flip once the linked window's shape on Forever is known: docs/GUILD_PROFESSION_LINKS_IDEA.md).
R.REQUIRE_LINKED_NAME = true
-- Silenced reads that never once got an answer before silencing is given up for the session (the window is
-- then only concealed): keeps a client where the silenced window holds the data back from never reading.
R.QUIET_GIVE_UP = 8
R.LATE = 15        -- seconds after a read went unanswered during which a linked window opening is its late reply
R.LATE_CLOSE = 1   -- seconds a late reply's window stays (concealed) before it is closed
R.USER_LINK = 5    -- seconds after the player clicks a profession link during which a linked window is theirs
-- Whether reads silence TRADE_SKILL_SHOW at all (off: the window is only concealed). For comparing the two in
-- game: /run AltArmy.OwnRecipeRead.SILENCE = false
R.SILENCE = true

local PANELS = { "left", "center", "right", "doublewide", "fullscreen" }

-- The server answers a profession link only for skill lines the game lets players link (DB2 SkillLine.CanLink;
-- Forever 1.60.1). Fishing and Comprehension were tried in game and never opened; Mining, Herbalism and
-- Skinning carry the same flag. Those are left to the player to open.
R.LINKABLE_SKILL_LINES = {
    [129] = true, -- First Aid
    [164] = true, -- Blacksmithing
    [165] = true, -- Leatherworking
    [171] = true, -- Alchemy
    [185] = true, -- Cooking
    [197] = true, -- Tailoring
    [202] = true, -- Engineering
    [333] = true, -- Enchanting
}
-- The same by name (lowercase English, as DS.NO_RECIPE_PROFESSION_KEYS_*), for alts, whose skill lines aren't
-- stored; names the client gives another way are learned from this character's professions below.
R.UNREADABLE_PROFESSION_KEYS = {
    fishing = true,
    mining = true,
    herbalism = true,
    skinning = true,
    comprehension = true,
}
-- Each linkable skill line's Apprentice spell (the same spells Recipes/RecipeInfo.lua names its professions
-- by): a link built with it is answered for players of every rank (Linked Inn). Unverified on Forever.
R.APPRENTICE_SPELLS = {
    [129] = 3273, -- First Aid
    [164] = 2018, -- Blacksmithing
    [165] = 2108, -- Leatherworking
    [171] = 2259, -- Alchemy
    [185] = 2550, -- Cooking
    [197] = 3908, -- Tailoring
    [202] = 4036, -- Engineering
    [333] = 7411, -- Enchanting
}
-- SearchSettings' locale-safe profession keys per linkable skill line, and back.
R.KEY_BY_SKILL_LINE = {
    [129] = "firstAid",
    [164] = "blacksmithing",
    [165] = "leatherworking",
    [171] = "alchemy",
    [185] = "cooking",
    [197] = "tailoring",
    [202] = "engineering",
    [333] = "enchanting",
}
R.SKILL_LINE_BY_KEY = {}
for skillLine, key in pairs(R.KEY_BY_SKILL_LINE) do R.SKILL_LINE_BY_KEY[key] = skillLine end

local CONCEALED_SCALE = 0.01

local queue = {}
local pending
local pumpScheduled = false
local workedSpell = {} -- skill line -> the spell whose link was answered (this session)
local frameHooked = false
local concealed = false
local savedLook
local tooltip
local readLog = {}
local unreadableNames = {} -- lowercase names of this character's professions on unlinkable skill lines
local attempts = 0 -- each start's own number, so an old start's timeout can't end a newer one
local seq = 0 -- each job's place in line within its priority
local eventFrame -- this file's event frame (made at the bottom), which keeps TRADE_SKILL_SHOW while silenced
local silenced -- the frames TRADE_SKILL_SHOW was taken from for the read being waited for
local quietOff, quietTries, quietWorks = false, 0, 0
local unansweredAt = -math.huge -- when a read last ended (or stepped aside) without its answer
local userLinkAt = -math.huge -- when the player last clicked a profession link
local lateCatch = false -- a late reply's window is to be concealed when it shows

local function now()
    return GetTime and GetTime() or 0
end

--- Debug only: the last reads, written as a dev dump when /altarmy debug is on (docs/DEV_DUMPS.md).
local function note(entry)
    local D = AltArmy.Debug
    if not (D and D.Dump) then return end
    table.insert(readLog, 1, entry)
    if #readLog > 20 then table.remove(readLog) end
    D.Dump("ownRecipeRead", { reads = readLog })
end

function R.HasApi()
    local api = C_TradeSkillUI
    return DS.IsUsingTradeSkillUiFallback ~= nil and DS.IsUsingTradeSkillUiFallback()
        and api ~= nil and api.CloseTradeSkill ~= nil
        and GetProfessions ~= nil and GetProfessionInfo ~= nil
        and C_SpellBook ~= nil and C_SpellBook.GetSpellBookItemInfo ~= nil
        and UnitGUID ~= nil
end

--- Whether recipes are read in the background (on until turned off in Options > General > Advanced). The
--- one switch for own and guild reads alike.
function R.IsEnabled()
    return not (type(AltArmyTBC_Options) == "table" and AltArmyTBC_Options.autoReadRecipes == false)
end

function R.SetEnabled(on)
    if type(AltArmyTBC_Options) ~= "table" then
        AltArmyTBC_Options = {}
    end
    AltArmyTBC_Options.autoReadRecipes = on == true
end

local function active()
    return R.HasApi() and R.IsEnabled()
end

--- Whether a profession's recipes can be read in the background (its skill line can be linked).
function R.CanRead(profName)
    if type(profName) ~= "string" then return false end
    local key = profName:lower()
    return not R.UNREADABLE_PROFESSION_KEYS[key] and not unreadableNames[key]
end

--- True while an own read is waiting for its window (ScanRecipesViaTradeSkillUI trusts an unnamed link then).
function R.IsReading()
    return pending ~= nil and pending.kind == "own"
end

--- True while a guild read is waiting for its window (the DataStore then trusts no window as the player's).
function R.IsReadingGuild()
    return pending ~= nil and pending.kind == "guild"
end

--- Whether guild reads can run at all on this client (the same switch as own reads).
function R.CanRunGuildReads()
    return active()
end

-- Finding the professions --------------------------------------------------------------------------------

local function spellAt(slot)
    local enum = _G.Enum
    local bank = enum and enum.SpellBookSpellBank and enum.SpellBookSpellBank.Player or 0
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
    return ok and type(info) == "table" and tonumber(info.spellID) or nil
end

--- A profession's link candidates: its spellbook spells (a gathering profession's first may be a Find
--- spell that opens nothing), the one answered before first.
local function candidateSpells(numSpells, offset, skillLine)
    local spells = {}
    local known = workedSpell[skillLine]
    if known then spells[1] = known end
    for i = 1, math.max(tonumber(numSpells) or 1, 1) do
        local spellID = spellAt(offset + i)
        if spellID and spellID ~= known then
            spells[#spells + 1] = spellID
        end
    end
    return spells
end

--- One job per profession with recipes: { kind = "own", name, skillLine, spells }.
local function professionJobs()
    local jobs = {}
    local slots = { GetProfessions() }
    for i = 1, 6 do
        local index = slots[i]
        if i ~= 3 and type(index) == "number" then -- 3 is Archaeology
            local name, _, rank, _, numSpells, offset, skillLine = GetProfessionInfo(index)
            name = DS.NormalizeProfessionName and DS.NormalizeProfessionName(name) or name
            if type(name) == "string" and type(skillLine) == "number" and not R.LINKABLE_SKILL_LINES[skillLine] then
                unreadableNames[name:lower()] = true
            elseif type(name) == "string" and name ~= "" and (tonumber(rank) or 0) > 0
                and type(offset) == "number" and type(skillLine) == "number"
                and not DS.ProfessionHasNoRecipeWindow(name) then
                local spells = candidateSpells(numSpells, offset, skillLine)
                if #spells > 0 then
                    jobs[#jobs + 1] = {
                        kind = "own", priority = 1, name = name, skillLine = skillLine, spells = spells,
                    }
                end
            end
        end
    end
    return jobs
end

--- Whether a profession's stored recipes need reading: marked stale (Summary warning) or none stored. Only
--- those are read, since each read opens the profession window.
local function isStale(name)
    local char = DS._GetCurrentCharTable and DS._GetCurrentCharTable()
    if not char then return true end
    local needing = char.professionsNeedingRecipeScan
    if type(needing) == "table" and needing[name] then return true end
    return DS:GetNumRecipes(char, name) == 0
end

local function isOwnQueued(name)
    if pending and pending.kind == "own" and pending.name == name then return true end
    for _, job in ipairs(queue) do
        if job.kind == "own" and job.name == name then return true end
    end
    return false
end

-- Keeping the window out of sight ------------------------------------------------------------------------

local function conceal(frame)
    if not concealed then
        savedLook = {
            alpha = frame.GetAlpha and frame:GetAlpha() or 1,
            scale = frame.GetScale and frame:GetScale() or 1,
            mouse = frame.IsMouseEnabled and frame:IsMouseEnabled(),
        }
    end
    concealed = true
    pcall(frame.SetAlpha, frame, 0)
    pcall(frame.SetScale, frame, CONCEALED_SCALE)
    pcall(frame.EnableMouse, frame, false)
end

local function reveal()
    local frame = ProfessionsFrame
    if concealed and frame and savedLook then
        pcall(frame.SetAlpha, frame, savedLook.alpha)
        pcall(frame.SetScale, frame, savedLook.scale)
        if savedLook.mouse ~= nil then
            pcall(frame.EnableMouse, frame, savedLook.mouse)
        end
    end
    concealed = false
    savedLook = nil
end

local function hookFrame()
    local frame = ProfessionsFrame
    if frameHooked or not frame or not frame.HookScript then return end
    frameHooked = true
    frame:HookScript("OnShow", function(self)
        if pending or lateCatch then conceal(self) end
    end)
    frame:HookScript("OnHide", reveal)
end

local function ensureFrame()
    if not ProfessionsFrame then
        if ProfessionsFrame_LoadUI then
            pcall(ProfessionsFrame_LoadUI)
        elseif C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
        end
    end
    hookFrame()
end

local function closeWindow()
    pcall(C_TradeSkillUI.CloseTradeSkill)
    reveal()
end

-- Keeping the window shut --------------------------------------------------------------------------------
-- Whatever opens Blizzard's profession window on TRADE_SKILL_SHOW is taken off that event while a read waits
-- for its answer, so the window never shows and never plays its open (or close) sound; the answer is read
-- from C_TradeSkillUI all the same (TRADE_SKILL_DATA_SOURCE_CHANGED / TRADE_SKILL_LIST_UPDATE). On Forever
-- the opener is an unnamed, parentless frame in Blizzard_Game's event routing, so a filter on
-- ProfessionsFrame's tree misses it: every frame is taken off but this file's and the DataStore's.
-- Protected frames (action buttons, which only refresh their state on it) are left alone. Learned from the
-- Linked Inn addon (1.1.1, Reader.lua's Silence). Every frame taken off is put back when the read ends or
-- steps aside, and on combat and logout.

local function keepsListening(frame)
    if frame == eventFrame or frame == DS.eventFrame then return true end
    if frame.IsProtected then
        local ok, protected = pcall(frame.IsProtected, frame)
        if ok and protected then return true end
    end
    return false
end

--- Take TRADE_SKILL_SHOW off the window's openers. Returns whether the read runs silenced.
local function silence()
    if silenced then return true end
    if quietOff or not R.SILENCE or not GetFramesRegisteredForEvent then return false end
    local found = { pcall(GetFramesRegisteredForEvent, "TRADE_SKILL_SHOW") }
    if not found[1] then return false end
    silenced = {}
    for i = 2, #found do
        local frame = found[i]
        if type(frame) == "table" and frame.UnregisterEvent and not keepsListening(frame) then
            if pcall(frame.UnregisterEvent, frame, "TRADE_SKILL_SHOW") then
                silenced[#silenced + 1] = frame
            end
        end
    end
    return true
end

local function unsilence()
    if not silenced then return end
    for _, frame in ipairs(silenced) do
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
    end
    silenced = nil
end

--- Count a silenced read's ending; silencing is given up once R.QUIET_GIVE_UP of them got no answer at all.
local function countQuiet(answered)
    quietTries = quietTries + 1
    if answered then quietWorks = quietWorks + 1 end
    if not quietOff and quietWorks == 0 and quietTries >= R.QUIET_GIVE_UP then
        quietOff = true
        note({ quiet = "given up", tries = quietTries })
    end
end

--- Debug and tests: { off, tries, works, silenced (frames taken off now) }.
function R.QuietState()
    return { off = quietOff, tries = quietTries, works = quietWorks, silenced = silenced and #silenced or 0 }
end

local function linkState()
    local api = C_TradeSkillUI
    if not api or not api.IsTradeSkillLinked then return nil, nil end
    local ok, linked, name = pcall(api.IsTradeSkillLinked)
    if not ok then return nil, nil end
    return linked, name
end

local function isPlayerName(name)
    return UnitName ~= nil and R._NamesMatch(name, UnitName("player"))
end

local function shownProfession()
    local api = C_TradeSkillUI
    if not api or not api.GetBaseProfessionInfo then return nil end
    local ok, info = pcall(api.GetBaseProfessionInfo)
    local name = ok and type(info) == "table" and info.professionName or nil
    if type(name) ~= "string" or name == "" then return nil end
    return DS.NormalizeProfessionName and DS.NormalizeProfessionName(name) or name
end

--- Whether the window TRADE_SKILL_SHOW announced while a read waits is one the player opened, not its answer:
--- for a guild read, one that isn't linked (when a linked name is required) or is linked under the
--- player's own name; for an own read, someone else's or another profession.
local function playerOpened(job)
    local linked, name = linkState()
    if job.kind == "guild" then
        if linked == true then return isPlayerName(name) end
        return linked == false and R.REQUIRE_LINKED_NAME
    end
    if linked == true and type(name) == "string" and name ~= "" and not isPlayerName(name) then
        return true
    end
    local shown = shownProfession()
    return shown ~= nil and shown ~= job.name
end

--- Whether a linked window opening now is the late answer to a read that ended unanswered (never a link the
--- player clicked, nor the player's own).
local function lateReply()
    if pending then return false end
    local t = now()
    if t - unansweredAt > R.LATE or t - userLinkAt <= R.USER_LINK then return false end
    local linked, name = linkState()
    return linked == true and not isPlayerName(name)
end

--- Whether a mouse click landed on the interface (not the 3D world); true when the client can't say.
local function clickOnInterface()
    local focus
    if GetMouseFoci then
        local ok, foci = pcall(GetMouseFoci)
        if not ok then return true end
        focus = type(foci) == "table" and foci[1] or nil
    elseif GetMouseFocus then
        local ok, found = pcall(GetMouseFocus)
        if not ok then return true end
        focus = found
    else
        return true
    end
    return focus ~= nil and focus ~= WorldFrame
end

-- Waiting for a quiet moment -----------------------------------------------------------------------------

local function chatActive()
    local fn = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
    if not fn then return false end
    local ok, box = pcall(fn)
    return ok and box ~= nil
end

local function panelOpen()
    local frame = ProfessionsFrame
    if frame and frame.IsShown and frame:IsShown() and not concealed then
        return true
    end
    if not GetUIPanel then return false end
    for _, key in ipairs(PANELS) do
        local ok, open = pcall(GetUIPanel, key)
        if ok and open then return true end
    end
    return false
end

local function blocked()
    return (InCombatLockdown and InCombatLockdown()) or chatActive() or panelOpen()
end

-- Reading a guildmate's window ---------------------------------------------------------------------------

local function firstWord(name)
    name = tostring(name):lower()
    name = name:match("^([^%-]+)") or name
    return name:match("^(%S+)") or name
end

--- Whether a linked window's name is the player asked for: the first name, whatever the realm suffix or
--- surname either side carries (Forever names are "First Surname").
function R._NamesMatch(linkedName, targetName)
    if type(linkedName) ~= "string" or type(targetName) ~= "string" then return false end
    if linkedName == "" or targetName == "" then return false end
    return firstWord(linkedName) == firstWord(targetName)
end

local function professionKey(professionName)
    local SS = AltArmy.SearchSettings
    if SS and SS.ResolveProfessionKey then
        local ok, key = pcall(SS.ResolveProfessionKey, professionName)
        if ok then return key end
    end
    return nil
end

--- Read the open window for a guild job. Returns "wait" (nothing to read yet), "unnamed" (linked, but the
--- client says not under whose name), "wrong name" with the name it carries, "wrong profession", "absent"
--- (the server answers a link for a profession the player hasn't got too: an empty window at skill 0 of
--- max 0, nothing learned; the result carries { guid, name, skillLine, key }), or "ok"
--- with { guid, name, linkedName, skillLine, key, professionName, rank, maxRank, ids }: the learned
--- recipe ids sorted, nothing else (colours are relative to the linked player; cooldowns and reagents
--- aren't theirs to read).
function R._ScanLinkedWindow(api, job)
    if type(api) ~= "table" or not api.GetBaseProfessionInfo or not api.GetAllRecipeIDs
        or not api.GetRecipeInfo then
        return "wait"
    end
    local okInfo, info = pcall(api.GetBaseProfessionInfo)
    if not okInfo or type(info) ~= "table" or type(info.professionName) ~= "string"
        or info.professionName == "" then
        return "wait"
    end
    local linked, linkedName = false, nil
    if api.IsTradeSkillLinked then
        local ok, a, b = pcall(api.IsTradeSkillLinked)
        if ok then linked, linkedName = a == true, b end
    end
    if type(linkedName) ~= "string" or linkedName == "" then linkedName = nil end
    if R.REQUIRE_LINKED_NAME then
        if not linked then return "wait" end
        if not linkedName then return "unnamed" end
    end
    if linkedName and not R._NamesMatch(linkedName, job.name) then
        return "wrong name", { linkedName = linkedName }
    end
    local professionName = DS.NormalizeProfessionName and DS.NormalizeProfessionName(info.professionName)
        or info.professionName
    local expectedKey = R.KEY_BY_SKILL_LINE[job.skillLine]
    local key = professionKey(professionName)
    if key and expectedKey and key ~= expectedKey then
        return "wrong profession", { professionName = professionName }
    end
    local okIds, recipeIDs = pcall(api.GetAllRecipeIDs)
    if not okIds or type(recipeIDs) ~= "table" or #recipeIDs == 0 then return "wait" end
    local ids = {}
    for _, recipeID in ipairs(recipeIDs) do
        local okRecipe, recipeInfo = pcall(api.GetRecipeInfo, recipeID)
        if okRecipe and type(recipeInfo) == "table" and recipeInfo.learned and type(recipeID) == "number" then
            ids[#ids + 1] = recipeID
        end
    end
    table.sort(ids)
    if #ids == 0 and (tonumber(info.maxSkillLevel) or 0) == 0 and (tonumber(info.skillLevel) or 0) == 0 then
        return "absent", { guid = job.guid, name = job.name, skillLine = job.skillLine, key = key or expectedKey }
    end
    return "ok", {
        guid = job.guid,
        name = job.name,
        linkedName = linkedName,
        skillLine = job.skillLine,
        key = key or expectedKey,
        professionName = professionName,
        rank = tonumber(info.skillLevel) or 0,
        maxRank = tonumber(info.maxSkillLevel) or 0,
        ids = ids,
    }
end

-- The queue ----------------------------------------------------------------------------------------------

local pump
local finish

local function schedulePump(delay)
    if pumpScheduled then return end
    pumpScheduled = true
    C_Timer.After(delay, function()
        pumpScheduled = false
        pump()
    end)
end

local function enqueue(job)
    seq = seq + 1
    job.seq = seq
    queue[#queue + 1] = job
end

--- The queued job that goes next: the lowest priority number, then the first queued.
local function takeNext()
    local best
    for i, job in ipairs(queue) do
        if not best or job.priority < queue[best].priority
            or (job.priority == queue[best].priority and job.seq < queue[best].seq) then
            best = i
        end
    end
    return best and table.remove(queue, best) or nil
end

local function tryScanLinked()
    local job = pending
    if not job or job.kind ~= "guild" then return end
    local outcome, result = R._ScanLinkedWindow(C_TradeSkillUI, job)
    if outcome == "wait" then return end
    if outcome == "unnamed" then
        job.sawUnnamed = true
        return
    end
    finish(job, outcome, result)
end

finish = function(job, outcome, result)
    if pending ~= job then return end
    pending = nil
    job.attempt = nil
    closeWindow()
    unsilence()
    local answered = outcome ~= "timeout" and outcome ~= "error"
    if not answered then unansweredAt = now() end
    if job.quiet then countQuiet(answered) end
    local spell = job.spells[job.try]
    if job.kind == "guild" then
        if outcome == "timeout" and job.sawUnnamed then outcome = "unnamed" end
        local elapsed = job.startedAt and GetTime and (GetTime() - job.startedAt) or nil
        note({
            guild = job.name, guid = job.guid, skillLine = job.skillLine, spell = spell, outcome = outcome,
            quiet = job.quiet,
        })
        if job.onResult then pcall(job.onResult, outcome, result, elapsed) end
        schedulePump(R.GUILD_GAP)
        return
    end
    note({ profession = job.name, spell = spell, outcome = outcome, try = job.try, quiet = job.quiet })
    if outcome == "ok" then
        workedSpell[job.skillLine] = spell
    elseif job.try < #job.spells then
        queue[#queue + 1] = job -- its next spell; keeps its place in line
    end
    schedulePump(R.GAP)
end

local function start(job)
    local guid = job.guid
    if not guid then
        guid = UnitGUID("player")
        if type(guid) ~= "string" or guid == "" then
            queue[#queue + 1] = job
            schedulePump(R.RETRY)
            return
        end
    end
    job.try = (job.try or 0) + 1
    local spell = job.spells[job.try]
    ensureFrame()
    pending = job
    job.sawUnnamed = nil
    job.startedAt = GetTime and GetTime() or nil
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "AltArmyTBC_OwnRecipeReadTooltip", UIParent, "GameTooltipTemplate")
    end
    pcall(tooltip.SetOwner, tooltip, UIParent, "ANCHOR_NONE")
    job.quiet = silence()
    local link = string.format("trade:%s:%d:%d", guid, spell, job.skillLine)
    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    pcall(tooltip.Hide, tooltip)
    if not ok then
        finish(job, "error")
        return
    end
    if job.onStart then pcall(job.onStart, spell) end
    attempts = attempts + 1
    local mine = attempts
    job.attempt = mine
    C_Timer.After(R.TIMEOUT, function()
        if job.attempt == mine then
            finish(job, "timeout")
        end
    end)
end

pump = function()
    if pending or #queue == 0 or not active() then return end
    if blocked() then
        schedulePump(R.RETRY)
        return
    end
    start(takeNext())
end

--- Queue every stale profession, in the game's order. Returns how many were queued.
function R.QueueAll()
    if not active() then return 0 end
    local added = 0
    for _, job in ipairs(professionJobs()) do
        if isStale(job.name) and not isOwnQueued(job.name) then
            enqueue(job)
            added = added + 1
        end
    end
    if added > 0 then pump() end
    return added
end

--- Queue one profession by name if it is stale; every stale one when it is not among the character's.
function R.Queue(name)
    if not active() then return 0 end
    for _, job in ipairs(professionJobs()) do
        if job.name == name then
            if not isStale(name) or isOwnQueued(name) then return 0 end
            enqueue(job)
            pump()
            return 1
        end
    end
    return R.QueueAll()
end

--- Whether a guild job with this tag is queued or being read.
function R.IsQueued(tag)
    if pending and pending.tag == tag then return true end
    for _, job in ipairs(queue) do
        if job.tag == tag then return true end
    end
    return false
end

--- The tag of a guild job for a player's skill line (what R.Enqueue gives one without a tag).
function R.JobTag(guid, skillLine)
    return tostring(guid) .. "|" .. tostring(skillLine)
end

--- Move a queued guild job up (or down) the line. Returns true when one with that tag was queued.
function R.Promote(tag, priority)
    for _, job in ipairs(queue) do
        if job.tag == tag then
            job.priority = tonumber(priority) or job.priority
            return true
        end
    end
    return false
end

--- Queue a guildmate's profession: { guid, name, skillLine, priority (default 3), tag (default
--- R.JobTag(guid, skillLine)), onStart(spell), onResult(outcome, result, elapsed) }. The link is built
--- with the skill line's Apprentice spell. Returns false when reads are off, the job is malformed, or one
--- with the same tag is already queued or being read.
function R.Enqueue(job)
    if not active() or type(job) ~= "table" then return false end
    if type(job.guid) ~= "string" or job.guid == "" or type(job.name) ~= "string" or job.name == "" then
        return false
    end
    local spell = R.APPRENTICE_SPELLS[job.skillLine]
    if not spell then return false end
    job.kind = "guild"
    job.priority = tonumber(job.priority) or 3
    job.spells = { spell }
    job.tag = job.tag or R.JobTag(job.guid, job.skillLine)
    if R.IsQueued(job.tag) then return false end
    enqueue(job)
    pump()
    return true
end

--- Drop the queued guild jobs `pred(job)` is true for (never the one being read). Returns how many.
function R.CancelWhere(pred)
    local kept, dropped = {}, 0
    for _, job in ipairs(queue) do
        if job.kind == "guild" and pred(job) then
            dropped = dropped + 1
        else
            kept[#kept + 1] = job
        end
    end
    queue = kept
    return dropped
end

--- The DataStore stored the open window's recipes (DS:ScanRecipes): ends the own read waiting for it.
function R.OnRecipesScanned(professionName)
    if pending and pending.kind == "own" then
        local job = pending
        if professionName ~= job.name then
            note({ profession = job.name, scanned = professionName, outcome = "scanned another name" })
        end
        finish(job, "ok")
    end
end

--- A recipe was learned (DS:OnRecipeLearnDetected): read its profession, or every one when unknown.
function R.OnRecipeLearned(professionName)
    if not active() then return end
    C_Timer.After(R.LEARN_DELAY, function()
        if professionName then
            R.Queue(professionName)
        else
            R.QueueAll()
        end
    end)
end

--- Put the read being waited for back in line, the window left as it is (and the openers given back
--- TRADE_SKILL_SHOW). Its answer may still come: a late reply.
local function stepAside(why)
    unsilence()
    local job = pending
    if not job then return nil end
    pending = nil
    job.attempt = nil
    job.try = job.try - 1
    unansweredAt = now()
    if why then note({ profession = job.name, guild = job.kind == "guild" or nil, outcome = why }) end
    queue[#queue + 1] = job -- keeps its seq, so its place in line
    schedulePump(R.RETRY)
    return job
end

local function abort(why)
    if stepAside(why) then closeWindow() end
end

--- The player opened a profession window while a read waited: the read steps aside. When the read was
--- silenced, Blizzard's openers never heard of the window, and the addon must not show it in their place
--- (see the top of this file: that taints the cast bar), so the trade skill is closed and the player's
--- next click opens it as usual, the openers listening again.
local function playerTookWindow()
    local wasSilenced = silenced ~= nil
    stepAside("stepped aside for the player's window")
    reveal()
    if wasSilenced then closeWindow() end
end

--- A read's answer came after it ended: keep its window out of sight and close it.
local function catchLateReply()
    lateCatch = true
    note({ outcome = "late reply closed" })
    local frame = ProfessionsFrame
    if frame and frame.IsShown and frame:IsShown() then conceal(frame) end
    C_Timer.After(R.LATE_CLOSE, function()
        lateCatch = false
        if not pending then closeWindow() end
    end)
end

--- SetItemRef's hook: the player clicked a link; a profession link's window is theirs, never a late reply.
function R.OnLinkClicked(link)
    if type(link) == "string" and link:sub(1, 6) == "trade:" then
        userLinkAt = now()
    end
end

function R.OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if (isInitialLogin or isReloadingUi) and active() then
            C_Timer.After(R.LOGIN_DELAY, R.QueueAll)
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LOGOUT" then
        abort()
    elseif event == "GLOBAL_MOUSE_DOWN" then
        if pending and clickOnInterface() then abort("stepped aside for a click") end
    elseif event == "ADDON_LOADED" then
        if ... == "Blizzard_Professions" then hookFrame() end
    elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "TRADE_SKILL_LIST_UPDATE" then
        tryScanLinked()
    elseif event == "TRADE_SKILL_SHOW" then
        if pending and playerOpened(pending) then
            playerTookWindow()
        elseif pending then
            if pending.kind == "guild" then C_Timer.After(R.SHOW_SCAN_DELAY, tryScanLinked) end
        elseif lateReply() then
            catchLateReply()
        end
    end
end

function R._ResetForTests()
    unsilence()
    queue, pending, pumpScheduled, workedSpell = {}, nil, false, {}
    frameHooked, concealed, savedLook = false, false, nil
    tooltip, readLog, attempts, unreadableNames, seq = nil, {}, 0, {}, 0
    quietOff, quietTries, quietWorks, lateCatch = false, 0, 0, false
    unansweredAt, userLinkAt = -math.huge, -math.huge
end

--- Tests: this file's event frame (the one that keeps TRADE_SKILL_SHOW while silenced).
function R._EventFrame()
    return eventFrame
end

eventFrame = CreateFrame and CreateFrame("Frame")
if eventFrame then
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT", "ADDON_LOADED",
        "GLOBAL_MOUSE_DOWN", "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", function(_, event, ...) R.OnEvent(event, ...) end)
end
if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link) R.OnLinkClicked(link) end)
end
